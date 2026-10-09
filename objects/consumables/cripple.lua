-- Cripple: one random Joker of the Nemesis is debuffed during their next PvP blind.
-- Only the Nemesis' game knows their Jokers, so this is a two-step exchange:
--   1. user's game sends "cripple_request"
--   2. Nemesis' game picks a Joker, puts the Crippled sticker on it, and replies
--      with "cripple_reply" carrying the result and the Joker's key
--   3. user's game shows which Joker was crippled
-- The sticker stays on the Joker until the Nemesis' next PvP blind starts; then the
-- Joker is debuffed (SMODS debuff source "mp_cripple") until that blind ends.
-- Selling or destroying the Joker removes the sticker with it.
--
-- For the Attacks panel (ui/game/duel_attacks_panel.lua) the user's game keeps
-- G.GAME.mp_cripple_sent, the keys of the Jokers it crippled that have not been
-- debuffed yet. When the Nemesis' next PvP blind starts, their game sends
-- "cripple_landed" and the user's game clears the list. A Cripple that arrives
-- during that blind is answered after "cripple_landed", so it stays listed.

local STICKER = "mp_sticker_crippled"
local DEBUFF_SOURCE = "mp_cripple"

local function nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

local function in_run()
	return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD and G.jokers
end

local function show_cripple_text(text)
	G.FUNCS.attention_text_realtime({
		text = text,
		scale = 0.8,
		hold = 2,
		align = "cm",
		major = G.play,
		backdrop_colour = G.C.RED,
	})
	play_sound("cancel")
end

-- The key arrives over the network, so only use it to look up a Joker name.
local function joker_name(key)
	local center = G.P_CENTERS[key]
	if not (center and center.set == "Joker") then return localize("k_joker") end
	return localize({ type = "name_text", set = "Joker", key = key })
end

MP.CRIPPLE = { sticker = STICKER, joker_name = joker_name }

function MP.CRIPPLE.sent()
	if not G.GAME then return {} end
	G.GAME.mp_cripple_sent = G.GAME.mp_cripple_sent or {}
	return G.GAME.mp_cripple_sent
end

local function uncripple(card)
	SMODS.Stickers[STICKER]:apply(card, nil)
	card.ability.mp_cripple_active = nil
	if card.ability.debuff_sources and card.ability.debuff_sources[DEBUFF_SOURCE] ~= nil then
		SMODS.debuff_card(card, nil, DEBUFF_SOURCE)
	end
end

-- Runs on the Nemesis' game.
-- A second Cripple picks a Joker that is not crippled yet. If every Joker is
-- already crippled, nothing more happens.
MP.register_mod_action("cripple_request", function(p)
	if not in_run() or #G.jokers.cards == 0 then
		MP.ACTIONS.modded(MP.id, "cripple_reply", { result = "none" })
		return
	end
	local candidates = {}
	for _, joker in ipairs(G.jokers.cards) do
		if not joker.ability[STICKER] then candidates[#candidates + 1] = joker end
	end
	if #candidates == 0 then
		MP.ACTIONS.modded(MP.id, "cripple_reply", { result = "all_crippled" })
		return
	end
	local joker = pseudorandom_element(candidates, pseudoseed("mp_cripple"))
	SMODS.Stickers[STICKER]:apply(joker, true)
	joker:juice_up(0.5, 0.5)
	local key = joker.config.center.key
	show_cripple_text(localize({ type = "variable", key = "k_mp_crippled_by_nemesis", vars = { joker_name(key) } }))
	G.GAME.mp_cripple_received = true
	MP.ACTIONS.modded(MP.id, "cripple_reply", { result = "crippled", joker = key })
end, MP.id)

-- Runs on the user's game.
MP.register_mod_action("cripple_reply", function(p)
	if not in_run() then return end
	if p.result == "crippled" then
		table.insert(MP.CRIPPLE.sent(), tostring(p.joker))
		show_cripple_text(
			localize({ type = "variable", key = "k_mp_crippled_nemesis", vars = { joker_name(tostring(p.joker)) } })
		)
	elseif p.result == "all_crippled" then
		show_cripple_text(localize({ type = "variable", key = "k_mp_cripple_all_crippled", vars = {} }))
	else
		show_cripple_text(localize({ type = "variable", key = "k_mp_cripple_no_jokers", vars = {} }))
	end
end, MP.id)

-- Runs on the user's game when the Nemesis' PvP blind starts.
MP.register_mod_action("cripple_landed", function(p)
	if not in_run() then return end
	G.GAME.mp_cripple_sent = {}
end, MP.id)

-- Messages to or from a Nemesis who dropped out may be lost, so forget the
-- sent list (same rule as the next-blind attacks).
local cripple_sent_update_ref = Game.update
function Game:update(dt)
	if G.GAME and G.GAME.mp_cripple_sent and #G.GAME.mp_cripple_sent > 0 and not nemesis_present() then
		G.GAME.mp_cripple_sent = {}
	end
	return cripple_sent_update_ref(self, dt)
end

-- Start of a PvP blind: debuff every Joker that was crippled before it started.
-- A Joker crippled during this blind keeps only the sticker (no mp_cripple_active),
-- so it waits for the next PvP blind.
local set_blind_ref = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
	set_blind_ref(self, blind, reset, silent)
	if not blind or reset or not G.jokers or not MP.is_pvp_boss() then return end
	for _, joker in ipairs(G.jokers.cards) do
		if joker.ability[STICKER] then
			joker.ability.mp_cripple_active = true
			SMODS.debuff_card(joker, true, DEBUFF_SOURCE)
		end
	end
	-- Also sent when the crippled Joker was sold, so the sender stops listing it.
	if G.GAME.mp_cripple_received then
		G.GAME.mp_cripple_received = nil
		if nemesis_present() then MP.ACTIONS.modded(MP.id, "cripple_landed", {}) end
	end
end

-- End of a PvP blind: remove the debuff and the sticker from Jokers it applied to.
local end_round_ref = end_round
function end_round()
	if G.jokers and MP.is_pvp_boss() then
		for _, joker in ipairs(G.jokers.cards) do
			if joker.ability.mp_cripple_active then uncripple(joker) end
		end
	end
	return end_round_ref()
end

-- Copies of a crippled Joker (Invisible Joker, Ankh, ...) are not crippled.
local copy_card_ref = copy_card
function copy_card(other, new_card, card_scale, playing_card, strip_edition)
	local card = copy_card_ref(other, new_card, card_scale, playing_card, strip_edition)
	if card and card.ability and card.ability[STICKER] then uncripple(card) end
	return card
end

-- Multiplayer runs are never saved (G.F_NO_SAVING is set in lobbies). The one way
-- a run is reloaded is "Continue in Singleplayer", which has no PvP blinds, so
-- drop any cripple there instead of leaving a Joker marked (or debuffed) forever.
local start_run_ref = Game.start_run
function Game:start_run(args)
	start_run_ref(self, args)
	if MP.LOBBY.code or not G.jokers then return end
	for _, joker in ipairs(G.jokers.cards) do
		if joker.ability[STICKER] or joker.ability.mp_cripple_active then uncripple(joker) end
	end
end

SMODS.Consumable({
	key = "cripple",
	set = "Attack",
	-- Placeholder art: The Hanged Man's sprite from the default (vanilla Tarot) atlas
	pos = { x = 2, y = 1 },
	cost = 4,
	unlocked = true,
	discovered = true,
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		info_queue[#info_queue + 1] = { key = STICKER, set = "Other" }
		return { vars = {} }
	end,
	can_use = function(self, card)
		return nemesis_present()
	end,
	use = function(self, card, area, copier)
		MP.ACTIONS.modded(MP.id, "cripple_request", {})
	end,
})
