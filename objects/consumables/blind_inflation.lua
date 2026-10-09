-- Blind Inflation: the Nemesis' next non-PvP blind needs more chips. PvP blinds
-- are skipped (their target is the opponent's score), so the attack waits.
-- Copies that land on the same blind add up: two make +50%.

local KEY = "c_mp_blind_inflation"
local NBA = MP.NEXT_BLIND_ATTACKS

NBA.register(KEY, {
	skips_pvp = true,
	detail = function(entry)
		return localize({ type = "variable", key = "k_mp_nba_inflation_detail", vars = { NBA.config(KEY).percent } })
	end,
	apply = function(entries)
		local mult = 1 + #entries * NBA.config(KEY).percent / 100
		local blind = G.GAME.blind
		blind.chips = blind.chips * mult
		if type(blind.chips) == "number" then blind.chips = math.floor(blind.chips) end
		blind.chip_text = number_format(blind.chips)
		return { mult = mult }
	end,
	-- At the end of a blind the requirement is still needed to decide the round,
	-- so only put it back when the run continues in singleplayer mid-blind.
	undo = function(state, leaving)
		if not leaving or not G.GAME.blind then return end
		G.GAME.blind.chips = G.GAME.blind.chips / state.mult
		if type(G.GAME.blind.chips) == "number" then G.GAME.blind.chips = math.floor(G.GAME.blind.chips + 0.5) end
		G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
	end,
})

SMODS.Consumable({
	key = "blind_inflation",
	set = "Attack",
	-- Placeholder art: The Tower's sprite from the default (vanilla Tarot) atlas
	pos = { x = 6, y = 1 },
	cost = 4,
	unlocked = true,
	discovered = true,
	config = { extra = { percent = 25, chance = 0.75 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = { math.floor(card.ability.extra.chance * 100 + 0.5), card.ability.extra.percent } }
	end,
	can_use = function(self, card)
		return NBA.nemesis_present()
	end,
	use = function(self, card, area, copier)
		NBA.send(KEY)
	end,
})
