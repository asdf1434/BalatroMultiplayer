-- Mirage: during the Nemesis' next blind (any kind, PvP included), when they
-- play their last hand (the hand played with 1 hand left), a random
-- non-Eternal Joker of theirs is destroyed before that hand scores. If the
-- blind ends before their last hand, Mirage does nothing and both players see
-- "Mirage faded". Each copy that lands on the same blind destroys one more
-- Joker on that same last hand.
--
-- The chance is rolled at the start of the blind, like the other next-blind
-- attacks. The Nemesis' game reports what happened with a "mirage_result"
-- message, so the attacker sees which Joker was destroyed or that it faded.

local KEY = "c_mp_mirage"
local NBA = MP.NEXT_BLIND_ATTACKS

local function joker_name(key)
	local center = G.P_CENTERS[key]
	if not (center and center.set == "Joker") then return localize("k_joker") end
	return localize({ type = "name_text", set = "Joker", key = key })
end

local function text(key, vars)
	return localize({ type = "variable", key = key, vars = vars or {} })
end

local function report(outcome, joker_key)
	MP.ACTIONS.modded(MP.id, "mirage_result", { outcome = outcome, joker = joker_key })
end

-- Mirage is used up: drop it from the Attacks panel's Active line.
local function clear_active_entries()
	local state = NBA.state()
	local entries = {}
	for _, entry in ipairs(state.active_entries) do
		if entry.key ~= KEY then entries[#entries + 1] = entry end
	end
	state.active_entries = entries
end

NBA.register(KEY, {
	effect = function(entry)
		return text("k_mp_nba_effect_mirage")
	end,
	apply = function(entries)
		return { copies = #entries, fired = false }
	end,
	undo = function(state, leaving)
		if state.fired or leaving then return end
		NBA.show_text(text("k_mp_mirage_faded"), G.C.GREEN)
		for _ = 1, state.copies do
			report("faded")
		end
	end,
})

-- Destroy up to state.copies Jokers. Uses this game's own seed key, so the
-- pick does not mirror the other player's rolls.
local function strike(state)
	state.fired = true
	clear_active_entries()
	for _ = 1, state.copies do
		local candidates = {}
		for _, joker in ipairs(G.jokers and G.jokers.cards or {}) do
			if not joker.getting_sliced and not SMODS.is_eternal(joker, { destroy_cards = true }) then
				candidates[#candidates + 1] = joker
			end
		end
		local joker = #candidates > 0
			and pseudorandom_element(candidates, pseudoseed(MP.UTILS.player_seed_key("mp_mirage")))
		if not joker then
			NBA.show_text(text("k_mp_mirage_nothing"), G.C.GREEN)
			report("nothing")
		else
			local key = joker.config.center.key
			-- getting_sliced is set right away, so the Joker no longer scores;
			-- it dissolves and leaves the Joker area right after.
			SMODS.destroy_cards(joker, nil, true)
			NBA.show_text(text("k_mp_mirage_destroyed", { joker_name(key) }))
			report("destroyed", key)
		end
	end
end

-- evaluate_play runs after the hand counter has gone down, so hands_left is 0
-- on the last hand, before any card or Joker scores.
local evaluate_play_ref = G.FUNCS.evaluate_play
G.FUNCS.evaluate_play = function(e)
	local active = NBA.active(KEY)
	if active and not active.fired and G.GAME.current_round.hands_left <= 0 then strike(active) end
	return evaluate_play_ref(e)
end

-- Runs on the attacker's game. The Joker key comes from the network, so it is
-- only used to look up a name.
MP.register_mod_action("mirage_result", function(p)
	if not (G.STAGE == G.STAGES.RUN and G.GAME) then return end
	if p.outcome == "destroyed" then
		NBA.show_text(text("k_mp_mirage_destroyed_on_nemesis", { joker_name(tostring(p.joker)) }))
	elseif p.outcome == "nothing" then
		NBA.show_text(text("k_mp_mirage_nothing_on_nemesis"), G.C.UI.TEXT_INACTIVE)
	else
		NBA.show_text(text("k_mp_mirage_faded"), G.C.UI.TEXT_INACTIVE)
	end
end, MP.id)

SMODS.Consumable({
	key = "mirage",
	set = "Attack",
	-- Placeholder art: The Star's sprite from the default (vanilla Tarot) atlas
	pos = { x = 7, y = 1 },
	cost = 10,
	unlocked = true,
	discovered = true,
	config = { extra = { chance = 0.25 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = { math.floor(card.ability.extra.chance * 100 + 0.5), NBA.max_pending } }
	end,
	can_use = function(self, card)
		return NBA.can_send()
	end,
	use = function(self, card, area, copier)
		NBA.send(KEY)
	end,
})
