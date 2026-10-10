-- Joker Swap: give one of your Jokers to the Nemesis and take a random one of
-- theirs, permanently. Jokers keep their progress, edition and stickers.
--
-- Request / reply exchange (same shape as Tax Collector):
--   1. user's game sends "joker_swap_request" with the full state of the chosen
--      Joker. The Joker stays with the user and is locked (cannot be sold or used
--      in another swap) until the swap is resolved: the reply arrives, or the
--      Nemesis disconnects / the lobby or run ends (then no reply can come).
--   2. Nemesis' game picks a random non-Eternal Joker of its own, removes it,
--      adds the received Joker, and replies "joker_swap_reply" with the full state
--      of the Joker it gave up.
--   3. user's game removes the chosen Joker and adds the received one.
-- If the Nemesis cannot swap (no Jokers, only Eternal ones, not in a run), the
-- reply says why, nothing moves, and the user gets the Joker Swap card back.
--
-- Joker state travels as JSON text built by lib/card_transfer.lua (Balatro's
-- own save data). Received text is only ever JSON-decoded, never run.

-- Swaps this game started and is still waiting on, keyed by swap id.
local pending_swaps = {}
local next_swap_id = 1

local function nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

local function in_run()
	return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD and G.jokers
end

local function show_swap_text(key)
	G.FUNCS.attention_text_realtime({
		text = localize(key),
		scale = 0.8,
		hold = 2,
		align = "cm",
		major = G.play,
		backdrop_colour = G.C.SECONDARY_SET.Attack or G.C.RED,
	})
	play_sound("card1")
end

local function is_eternal(card)
	if SMODS.is_eternal then return SMODS.is_eternal(card, {}) end
	return card.ability.eternal
end

local function is_phantom(card)
	return card.edition and card.edition.type == "mp_phantom"
end

-- True while the Joker is promised to a swap that has not been answered yet.
-- There is deliberately no time limit: if the lock ended while a reply was still
-- on its way, the Joker could be sold or swapped again and then also be given away
-- by the late reply, so it would exist twice.
local function is_swap_locked(card)
	return card.mp_swap_locked == true
end

-- A Joker that may leave this game in a swap (chosen by the user, or picked at
-- random when the Nemesis swaps with us). Hijack's temporary copies stay.
local function can_be_swapped(card)
	return card.ability
		and card.ability.set == "Joker"
		and not card.removed
		and not is_phantom(card)
		and not card.ability.mp_hijack_copy
		and not is_eternal(card)
		and not is_swap_locked(card)
end

local sell_ref = Card.can_sell_card
function Card:can_sell_card(context)
	if is_swap_locked(self) then return false end
	return sell_ref(self, context)
end

----------------------------------------------------------------------------
-- Joker state <-> network text (lib/card_transfer.lua)
----------------------------------------------------------------------------

local CT = MP.CARD_TRANSFER

local function serialize_joker(card)
	return CT.serialize(card)
end

local function decode_joker_data(text)
	return CT.decode(text, "joker")
end

local function build_joker_from_data(data)
	return CT.build(data, G.jokers)
end

----------------------------------------------------------------------------
-- Moving Jokers in and out of this game
----------------------------------------------------------------------------

-- Removes a Joker that is leaving in a swap. remove_from_deck runs right away so
-- its effects (hand size, Joker slots, ...) end now; the dissolve is visual only.
-- This is not a sale and not a destruction, so no sell / destroy effects trigger.
local function remove_swapped_joker(card)
	card.mp_swap_locked = nil
	card:remove_from_deck()
	card:start_dissolve({ G.C.RED }, nil, 1.6)
	if card.area then card.area:remove_card(card) end
end

-- Adds a Joker that arrived in a swap and runs its add_to_deck effects.
-- Joker slots follow the cards: a Negative Joker carries its extra slot with it
-- (SMODS counts ability.card_limit of the cards in the area). If that leaves a
-- player above their slot limit, nothing is destroyed; they cannot add more
-- Jokers until they are back under the limit, as in vanilla.
local function add_swapped_joker(card)
	card:add_to_deck()
	G.jokers:emplace(card)
	card:start_materialize()
	G.GAME.used_jokers[card.config.center.key] = true
	if G.GAME.blind and SMODS.recalc_debuff then SMODS.recalc_debuff(card) end
end

-- Picks which of this game's Jokers to give when the Nemesis swaps with us.
-- Uses its own seed key (different per player) so no other random queue moves.
local function pick_joker_to_give()
	local eligible = {}
	for _, card in ipairs(G.jokers.cards) do
		if can_be_swapped(card) then eligible[#eligible + 1] = card end
	end
	if #eligible == 0 then return nil end
	return pseudorandom_element(eligible, pseudoseed(MP.UTILS.player_seed_key("mp_joker_swap")))
end

----------------------------------------------------------------------------
-- Exchange
----------------------------------------------------------------------------

-- Step 1, user's game.
local function start_joker_swap(card)
	local id = next_swap_id
	next_swap_id = next_swap_id + 1
	local text = serialize_joker(card)
	if not text then return false end
	card.mp_swap_locked = true
	pending_swaps[id] = { card = card, game = G.GAME }
	MP.ACTIONS.modded(MP.id, "joker_swap_request", { swap_id = id, card = text })
	return true
end

-- Step 2, Nemesis' game. Replies with result "ok" plus the given Joker, or a
-- failure reason: "not_in_run", "no_jokers", "bad_card".
local function answer_joker_swap(p)
	local function reply(result, card_text)
		MP.ACTIONS.modded(MP.id, "joker_swap_reply", { swap_id = p.swap_id, result = result, card = card_text })
	end
	if not in_run() then return reply("not_in_run") end

	local data = decode_joker_data(p.card)
	if not data then return reply("bad_card") end
	local given = pick_joker_to_give()
	if not given then return reply("no_jokers") end
	local given_text = serialize_joker(given)
	if not given_text then return reply("bad_card") end
	-- Built last: a card is only created once the swap is sure to happen.
	local received = build_joker_from_data(data)
	if not received then return reply("bad_card") end

	remove_swapped_joker(given)
	add_swapped_joker(received)
	show_swap_text("k_mp_joker_swapped_by_nemesis")
	reply("ok", given_text)
end

local FAILURE_TEXT = {
	not_in_run = "k_mp_joker_swap_not_in_run",
	no_jokers = "k_mp_joker_swap_no_jokers",
	bad_card = "k_mp_joker_swap_failed",
}

-- Step 3, user's game.
local function finish_joker_swap(p)
	local id = tonumber(p.swap_id)
	local swap = id and pending_swaps[id]
	if not swap then return end
	pending_swaps[id] = nil
	local mine = swap.card
	mine.mp_swap_locked = nil
	if swap.game ~= G.GAME or not in_run() then return end

	if p.result ~= "ok" then
		-- Nothing moved on either side: give the card back.
		show_swap_text(FAILURE_TEXT[p.result] or "k_mp_joker_swap_failed")
		SMODS.add_card({ key = "c_mp_joker_swap", area = G.consumeables })
		return
	end

	local data = decode_joker_data(p.card)
	local received = data and build_joker_from_data(data)
	if not received then
		-- The Nemesis already took our Joker's copy; keep ours rather than lose it
		-- for nothing. Only possible with mismatched mod versions.
		show_swap_text("k_mp_joker_swap_failed")
		return
	end
	-- The chosen Joker may already be gone (destroyed by another card, e.g.
	-- Madness); the received Joker is still added.
	if mine.area == G.jokers and not mine.removed then remove_swapped_joker(mine) end
	add_swapped_joker(received)
	show_swap_text("k_mp_joker_swapped")
end

-- Ends every pending swap when no reply can arrive anymore: the Nemesis
-- disconnected, the lobby closed, or this run ended. The Joker unlocks and stays
-- with the user; the entry is dropped, so a reply that still shows up is ignored.
local function cancel_unanswerable_swaps()
	if next(pending_swaps) == nil then return end
	local nemesis_gone = not nemesis_present()
	for id, swap in pairs(pending_swaps) do
		local run_over = swap.game ~= G.GAME or not in_run()
		if nemesis_gone or run_over then
			pending_swaps[id] = nil
			swap.card.mp_swap_locked = nil
			if not run_over then
				show_swap_text("k_mp_joker_swap_cancelled")
				SMODS.add_card({ key = "c_mp_joker_swap", area = G.consumeables })
			end
		end
	end
end

local game_update_ref = Game.update
function Game:update(dt)
	game_update_ref(self, dt)
	cancel_unanswerable_swaps()
end

-- Both handlers run in a queued event so a swap never lands in the middle of a
-- scoring animation.
MP.register_mod_action("joker_swap_request", function(p)
	G.E_MANAGER:add_event(Event({
		func = function()
			answer_joker_swap(p)
			return true
		end,
	}))
end, MP.id)

MP.register_mod_action("joker_swap_reply", function(p)
	G.E_MANAGER:add_event(Event({
		func = function()
			finish_joker_swap(p)
			return true
		end,
	}))
end, MP.id)

SMODS.Consumable({
	key = "joker_swap",
	set = "Attack",
	-- Placeholder art: The Lovers' sprite from the default (vanilla Tarot) atlas
	pos = { x = 6, y = 0 },
	-- Twice the other Attack cards: it can take the Nemesis' best Joker, so it is
	-- priced like a Rare Joker ($8, e.g. DNA or Baron).
	cost = 8,
	unlocked = true,
	discovered = true,
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = {} }
	end,
	can_use = function(self, card)
		if not (in_run() and nemesis_present()) then return false end
		local highlighted = G.jokers.highlighted
		return #highlighted == 1 and can_be_swapped(highlighted[1])
	end,
	use = function(self, card, area, copier)
		local joker = G.jokers.highlighted[1]
		if joker and start_joker_swap(joker) then
			G.jokers:remove_from_highlighted(joker)
			joker:juice_up(0.5, 0.5)
		else
			-- The Joker's state could not be packed; nothing was sent.
			show_swap_text("k_mp_joker_swap_failed")
			G.E_MANAGER:add_event(Event({
				func = function()
					SMODS.add_card({ key = "c_mp_joker_swap", area = G.consumeables })
					return true
				end,
			}))
		end
	end,
})
