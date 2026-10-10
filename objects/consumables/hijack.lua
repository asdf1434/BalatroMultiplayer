-- Hijack: the user gets a temporary copy of a random Joker of the Nemesis for
-- the user's next Blind. The copy takes no Joker slot, sells for $0 and
-- disappears when that Blind ends. The Nemesis' Joker is not touched.
--
-- Request / reply exchange:
--   1. user's game sends "hijack_request"
--   2. Nemesis' game picks a random Joker and replies "hijack_reply" with its
--      full state (so the copy reflects the Joker as it is now)
--   3. user's game stores the copy in G.GAME.mp_hijack.pending (shown as
--      Incoming in the Attacks panel)
--   4. at the start of the user's next real Blind (Blind:set_blind, like the
--      next-blind attacks), each pending copy rolls its chance on the user's
--      game. A copy that lands joins the user's Jokers (shown as Active)
--   5. end_round removes every copy
-- If the Nemesis has no Jokers (or is not in a run), nothing is copied and the
-- user gets the Hijack back.
--
-- The copy must not change the user's shop: it is built without marking the
-- Joker as owned (lib/card_transfer.lua), and Card:remove's own bookkeeping
-- only forgets a Joker when no other copy of it is held.
-- Card state travels as JSON text built by lib/card_transfer.lua.

local KEY = "c_mp_hijack"
local STICKER = "mp_sticker_hijacked"
local CT = MP.CARD_TRANSFER

-- Requests this game sent and is still waiting on, keyed by id, so a reply
-- from an earlier run is ignored.
local pending_requests = {}
local next_request_id = 1

local function nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

local function in_run()
	return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD and G.jokers
end

local function text(key, vars)
	return localize({ type = "variable", key = key, vars = vars or {} })
end

local function show_hijack_text(str, colour)
	G.FUNCS.attention_text_realtime({
		text = str,
		scale = 0.8,
		hold = 2,
		align = "cm",
		major = G.play,
		backdrop_colour = colour or G.C.SECONDARY_SET.Attack or G.C.RED,
	})
	play_sound("card1")
end

-- The key may come from the network, so only use it to look up a name.
local function joker_name(key)
	local center = G.P_CENTERS[key]
	if not (center and center.set == "Joker") then return localize("k_joker") end
	return localize({ type = "name_text", set = "Joker", key = key })
end

local function is_copy(card)
	return card.ability and card.ability.mp_hijack_copy == true
end

local function is_phantom(card)
	return card.edition and card.edition.type == "mp_phantom"
end

local function config()
	return G.P_CENTERS[KEY].config.extra
end

MP.HIJACK = { key = KEY, joker_name = joker_name, is_copy = is_copy }

-- Copies waiting for the user's next Blind: { { key = joker key, card = JSON text }, ... }
function MP.HIJACK.pending()
	if not G.GAME then return {} end
	G.GAME.mp_hijack = G.GAME.mp_hijack or { pending = {} }
	return G.GAME.mp_hijack.pending
end

function MP.HIJACK.chance_percent()
	return math.floor(config().chance * 100 + 0.5)
end

-- Copies affecting the current Blind.
function MP.HIJACK.active_copies()
	local copies = {}
	for _, card in ipairs(G.jokers and G.jokers.cards or {}) do
		if is_copy(card) then copies[#copies + 1] = card end
	end
	return copies
end

-- Sells for $0 whatever changes its value later (for example Gift Card).
local set_cost_ref = Card.set_cost
function Card:set_cost()
	set_cost_ref(self)
	if is_copy(self) then self.sell_cost = 0 end
end

----------------------------------------------------------------------------
-- Exchange
----------------------------------------------------------------------------

-- Step 2, Nemesis' game. Replies with result "ok" plus the Joker, or a failure
-- reason: "not_in_run", "no_jokers", "bad_card". Uses its own seed key
-- (different per player) so no other random queue moves.
local function answer_hijack(p)
	local function reply(result, joker_key, card_text)
		MP.ACTIONS.modded(
			MP.id,
			"hijack_reply",
			{ request_id = p.request_id, result = result, joker = joker_key, card = card_text }
		)
	end
	if not in_run() then return reply("not_in_run") end
	local eligible = {}
	for _, card in ipairs(G.jokers.cards) do
		if not card.removed and not is_phantom(card) and not is_copy(card) then eligible[#eligible + 1] = card end
	end
	if #eligible == 0 then return reply("no_jokers") end
	local picked = pseudorandom_element(eligible, pseudoseed(MP.UTILS.player_seed_key("mp_hijack")))
	local card_text = CT.serialize(picked)
	if not card_text then return reply("bad_card") end
	local key = picked.config.center.key
	picked:juice_up(0.5, 0.5)
	show_hijack_text(text("k_mp_hijacked_by_nemesis", { joker_name(key) }))
	reply("ok", key, card_text)
end

local FAILURE_TEXT = {
	not_in_run = "k_mp_hijack_not_in_run",
	no_jokers = "k_mp_hijack_no_jokers",
	bad_card = "k_mp_hijack_failed",
}

-- Step 3, user's game.
local function finish_hijack(p)
	local id = tonumber(p.request_id)
	local game = id and pending_requests[id]
	if not game then return end
	pending_requests[id] = nil
	if game ~= G.GAME or not in_run() then return end

	-- Checked now so a copy that could never be built is refunded right away.
	local data = p.result == "ok" and CT.decode(p.card, "joker")
	if not data then
		show_hijack_text(text(FAILURE_TEXT[p.result] or "k_mp_hijack_failed"))
		SMODS.add_card({ key = KEY, area = G.consumeables })
		return
	end
	local key = data.save_fields.center
	table.insert(MP.HIJACK.pending(), { key = key, card = p.card })
	show_hijack_text(text("k_mp_hijack_incoming", { joker_name(key) }))
end

MP.register_mod_action("hijack_request", function(p)
	G.E_MANAGER:add_event(Event({
		func = function()
			answer_hijack(p)
			return true
		end,
	}))
end, MP.id)

MP.register_mod_action("hijack_reply", function(p)
	G.E_MANAGER:add_event(Event({
		func = function()
			finish_hijack(p)
			return true
		end,
	}))
end, MP.id)

----------------------------------------------------------------------------
-- The copy during the user's Blind
----------------------------------------------------------------------------

-- Turns a built card into a temporary copy and adds it to the user's Jokers.
local function add_copy(card)
	card.ability.mp_hijack_copy = true
	-- Counts as -1 used slots, so it fills none (SMODS CardArea:handle_card_limit).
	card.ability.extra_slots_used = -1
	-- A Negative copy gives no extra slot either.
	card.ability.card_limit = 0
	-- Stickers that belong to the Nemesis' Joker.
	if MP.CRIPPLE then card.ability[MP.CRIPPLE.sticker] = nil end
	card.ability.mp_cripple_active = nil
	SMODS.Stickers[STICKER]:apply(card, true)
	card:set_cost()
	card:add_to_deck()
	G.jokers:emplace(card)
	card:start_materialize()
	if SMODS.recalc_debuff then SMODS.recalc_debuff(card) end
end

-- Removes a copy. remove_from_deck runs right away so its effects (hand size,
-- discards, ...) end now; the dissolve is visual only. Not a sale and not a
-- destruction, so no sell / destroy effects trigger.
local function remove_copy(card)
	card:remove_from_deck()
	card:start_dissolve({ G.C.RED }, nil, 1.6)
	if card.area then card.area:remove_card(card) end
end

local function roll_lands()
	local chance = config().chance
	if chance >= 1 then return true end
	return pseudorandom(MP.UTILS.player_seed_key("mp_hijack_chance")) < chance
end

-- Start of a real new Blind: each pending copy rolls its chance. A skipped
-- Blind never calls set_blind, so copies wait through it.
local set_blind_ref = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
	set_blind_ref(self, blind, reset, silent)
	if not blind or reset or not G.hand or not G.jokers then return end
	local state = G.GAME.mp_hijack
	if not state or #state.pending == 0 then return end
	local pending = state.pending
	state.pending = {}
	local landed, fizzled = {}, {}
	for _, entry in ipairs(pending) do
		local name = joker_name(entry.key)
		local card = nil
		if roll_lands() then
			local data = CT.decode(entry.card, "joker")
			card = data and CT.build(data, G.jokers)
		end
		if card then
			add_copy(card)
			landed[#landed + 1] = name
		else
			fizzled[#fizzled + 1] = name
		end
	end
	if #landed > 0 then show_hijack_text(text("k_mp_hijack_landed", { table.concat(landed, ", ") })) end
	if #fizzled > 0 then
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = #landed > 0 and 1.5 or 0,
			timer = "REAL",
			blockable = false,
			blocking = false,
			func = function()
				show_hijack_text(text("k_mp_hijack_fizzled", { table.concat(fizzled, ", ") }), G.C.UI.TEXT_INACTIVE)
				return true
			end,
		}))
	end
end

-- End of the Blind: every copy disappears, before end-of-round effects run.
local end_round_ref = end_round
function end_round()
	for _, card in ipairs(MP.HIJACK.active_copies()) do
		remove_copy(card)
	end
	return end_round_ref()
end

-- Multiplayer runs are never saved; "Continue in Singleplayer" reloads the run
-- without the lobby. Drop copies still waiting there (same rule as the
-- next-blind attacks). A copy already in play still leaves at end_round.
local start_run_ref = Game.start_run
function Game:start_run(args)
	start_run_ref(self, args)
	if MP.LOBBY.code or not G.GAME or not G.GAME.mp_hijack then return end
	G.GAME.mp_hijack = nil
end

SMODS.Consumable({
	key = "hijack",
	set = "Attack",
	-- Placeholder art: The Devil's sprite from the default (vanilla Tarot) atlas
	pos = { x = 5, y = 1 },
	cost = 6,
	unlocked = true,
	discovered = true,
	config = { extra = { chance = 0.75 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		info_queue[#info_queue + 1] = { key = STICKER, set = "Other" }
		return { vars = { math.floor(card.ability.extra.chance * 100 + 0.5) } }
	end,
	can_use = function(self, card)
		return in_run() and nemesis_present()
	end,
	use = function(self, card, area, copier)
		local id = next_request_id
		next_request_id = next_request_id + 1
		pending_requests[id] = G.GAME
		MP.ACTIONS.modded(MP.id, "hijack_request", { request_id = id })
	end,
})
