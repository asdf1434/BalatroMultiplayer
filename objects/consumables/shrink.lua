-- Shrink: hand size is smaller during the Nemesis' next blind. Copies that land
-- on the same blind add up. Hand size never goes below 1. The amount actually
-- removed is stored and given back when the blind ends, so other hand size
-- changes during the blind (Juggler, vouchers, ...) are kept.

local KEY = "c_mp_shrink"
local NBA = MP.NEXT_BLIND_ATTACKS

NBA.register(KEY, {
	detail = function(entry)
		return localize({ type = "variable", key = "k_mp_nba_shrink_detail", vars = { NBA.config(KEY).hand_size } })
	end,
	effect = function(entry)
		return localize({ type = "variable", key = "k_mp_nba_effect_shrink", vars = { NBA.config(KEY).hand_size } })
	end,
	apply = function(entries)
		local wanted = #entries * NBA.config(KEY).hand_size
		local removed = math.max(0, math.min(wanted, G.hand.config.card_limit - 1))
		if removed > 0 then G.hand:change_size(-removed) end
		return { removed = removed }
	end,
	undo = function(state, leaving)
		if state.removed > 0 and G.hand then G.hand:change_size(state.removed) end
	end,
})

SMODS.Consumable({
	key = "shrink",
	set = "Attack",
	-- Placeholder art: Death's sprite from the default (vanilla Tarot) atlas
	pos = { x = 3, y = 1 },
	cost = 6,
	unlocked = true,
	discovered = true,
	config = { extra = { hand_size = 1, chance = 0.75 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return {
			vars = { math.floor(card.ability.extra.chance * 100 + 0.5), card.ability.extra.hand_size, NBA.max_pending },
		}
	end,
	can_use = function(self, card)
		return NBA.can_send()
	end,
	use = function(self, card, area, copier)
		NBA.send(KEY)
	end,
})
