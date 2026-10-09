-- Blind Inflation: the Nemesis' next non-PvP blind needs a random -5% to +30%
-- chips. The percent is rolled when the attack arrives (on the Nemesis' game) so
-- the incoming list can show it. PvP blinds are skipped (their target is the
-- opponent's score), so the attack waits. Copies that land on the same blind add
-- up: +20% and -5% make +15%.

local KEY = "c_mp_blind_inflation"
local NBA = MP.NEXT_BLIND_ATTACKS

-- The percent can come from the network (attacker's messages), so keep it a
-- whole number inside the card's range.
local function entry_percent(entry)
	local extra = NBA.config(KEY)
	local percent = math.floor(tonumber(entry.percent) or 0)
	return math.max(extra.min_percent, math.min(extra.max_percent, percent))
end

NBA.register(KEY, {
	skips_pvp = true,
	on_receive = function(entry, pending)
		local extra = NBA.config(KEY)
		entry.percent = pseudorandom("mp_blind_inflation", extra.min_percent, extra.max_percent)
	end,
	detail = function(entry)
		return localize({
			type = "variable",
			key = "k_mp_nba_inflation_detail",
			vars = { string.format("%+d", entry_percent(entry)) },
		})
	end,
	apply = function(entries)
		local total = 0
		for _, entry in ipairs(entries) do
			total = total + entry_percent(entry)
		end
		local mult = 1 + total / 100
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
	cost = 6,
	unlocked = true,
	discovered = true,
	config = { extra = { min_percent = -5, max_percent = 30, chance = 0.75 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		local extra = card.ability.extra
		return {
			vars = { math.floor(extra.chance * 100 + 0.5), extra.min_percent, extra.max_percent, NBA.max_pending },
		}
	end,
	can_use = function(self, card)
		return NBA.can_send()
	end,
	use = function(self, card, area, copier)
		NBA.send(KEY)
	end,
})
