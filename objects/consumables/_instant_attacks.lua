-- Shared helper for "instant" Attack cards (Level Drain, Level Steal, Level Swap,
-- Wallet Swap, Pollute, Curse). They all follow Tax Collector's shape:
--   1. user's game sends "<name>_request" (MP.INSTANT_ATTACKS.send)
--   2. Nemesis' game decides and applies the effect with its own state and card
--      config, then replies "<name>_reply" with what happened
--   3. user's game applies its side (if any) and shows what happened
-- Both players see a message.
--
-- Each card calls MP.INSTANT_ATTACKS.register(name, def):
--   answer (p) -> reply   Nemesis' game, only while in a run. Returns the reply
--                         fields; "result" says what happened.
--   finish (p)            user's game, only while in a run, for every reply
--                         except result = "not_in_run" (the helper shows a
--                         message for that one).
--   cancelled (p)         optional; user's game, for result = "not_in_run" and
--                         for a reply that arrives when the user left the run.
-- Both handlers run in a queued event, so an attack never lands in the middle
-- of a scoring animation (same as Joker Swap).
--
-- Values that arrive over the network are checked before use: hand names must
-- be a poker hand of this game, numbers go through tonumber.

local IA = {}
MP.INSTANT_ATTACKS = IA

function IA.nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

function IA.in_run()
	return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD and G.jokers and G.deck
end

-- Card config values (read from this game's own copy, never from the network).
function IA.config(key)
	local center = G.P_CENTERS[key]
	return center and center.config and center.config.extra or {}
end

-- key is a localization key in misc.v_dictionary (or misc.dictionary).
function IA.show_text(key, vars, sound)
	G.FUNCS.attention_text_realtime({
		text = localize({ type = "variable", key = key, vars = vars or {} }),
		scale = 0.8,
		hold = 2,
		align = "cm",
		major = G.play,
		backdrop_colour = G.C.SECONDARY_SET.Attack or G.C.RED,
	})
	play_sound(sound or "card1")
end

function IA.send(name, fields)
	MP.ACTIONS.modded(MP.id, name .. "_request", fields or {})
end

function IA.register(name, def)
	MP.register_mod_action(name .. "_request", function(p)
		G.E_MANAGER:add_event(Event({
			func = function()
				local reply
				if IA.in_run() then
					reply = def.answer(p) or {}
				else
					reply = { result = "not_in_run" }
				end
				MP.ACTIONS.modded(MP.id, name .. "_reply", reply)
				return true
			end,
		}))
	end, MP.id)

	MP.register_mod_action(name .. "_reply", function(p)
		G.E_MANAGER:add_event(Event({
			func = function()
				if not IA.in_run() then
					if def.cancelled then def.cancelled(p) end
				elseif p.result == "not_in_run" then
					IA.show_text("k_mp_attack_not_in_run", {}, "cancel")
					if def.cancelled then def.cancelled(p) end
				else
					def.finish(p)
				end
				return true
			end,
		}))
	end, MP.id)
end

----------------------------------------------------------------------------
-- Poker hands
----------------------------------------------------------------------------

local function plain_number(v)
	if to_number then v = to_number(v) end
	return tonumber(v) or 0
end

-- True if key names a poker hand of this game (keys arrive over the network).
function IA.is_hand(key)
	return type(key) == "string" and G.GAME.hands[key] ~= nil
end

function IA.hand_name(key)
	return localize(key, "poker_hands")
end

function IA.hand_level(key)
	return plain_number(G.GAME.hands[key].level)
end

-- The hand this game has played most often this run. G.handlist is ordered from
-- the highest-ranked hand down, and only a strictly higher count replaces the
-- current pick, so a tie goes to the higher-ranked hand. With no hand played yet
-- (only possible before the first hand of the run) it is High Card, the hand
-- every player has.
function IA.most_played_hand()
	local best, best_played = "High Card", 0
	for _, key in ipairs(G.handlist) do
		local hand = G.GAME.hands[key]
		local played = hand and plain_number(hand.played) or 0
		if played > best_played then
			best, best_played = key, played
		end
	end
	return best
end

-- Changes a hand's level with the vanilla level_up_hand (SMODS
-- upgrade_poker_hands), so chips, mult and the hand display update the same way
-- a Planet card does. Never goes below level 1. Returns the amount changed.
function IA.change_hand_level(key, amount)
	amount = math.max(amount, 1 - IA.hand_level(key))
	if amount ~= 0 then level_up_hand(nil, key, false, amount) end
	return amount
end

----------------------------------------------------------------------------
-- Money
----------------------------------------------------------------------------

function IA.dollars()
	return plain_number(G.GAME.dollars)
end

-- Adds (or removes) money right away. Money lost to an Attack is not spending:
-- the ease_dollars patch in lovely/game.toml counts every loss into spent_total
-- (which feeds spent_last_shop / Penny Pincher), so take it back out, as Tax
-- Collector does. Safe here because the ease is instant.
function IA.change_dollars(amount)
	if amount == 0 then return end
	ease_dollars(amount, true)
	if amount < 0 then MP.GAME.spent_total = to_big(MP.GAME.spent_total) - to_big(-amount) end
end
