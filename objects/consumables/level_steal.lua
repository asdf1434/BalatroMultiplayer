-- Level Steal: like Level Drain, and the user's game gains the levels the
-- Nemesis lost, on the same poker hand. If the Nemesis' hand is already level 1,
-- nothing is taken and nothing is gained (see _instant_attacks.lua).
local IA = MP.INSTANT_ATTACKS

IA.register("level_steal", {
	-- Nemesis' game. The amount comes from this game's own card config.
	answer = function(p)
		local hand = IA.most_played_hand()
		local stolen = -IA.change_hand_level(hand, -IA.config("c_mp_level_steal").levels)
		if stolen == 0 then
			IA.show_text("k_mp_level_steal_min_by_nemesis", { IA.hand_name(hand) }, "cancel")
			return { result = "min_level", hand = hand }
		end
		IA.show_text("k_mp_level_stolen_by_nemesis", { stolen, IA.hand_name(hand) }, "cancel")
		return { result = "stolen", hand = hand, levels = stolen }
	end,
	-- User's game. Gains what was taken, but never more than this game's own
	-- card config allows.
	finish = function(p)
		if not IA.is_hand(p.hand) then return end
		if p.result ~= "stolen" then
			IA.show_text("k_mp_level_min_nemesis", { IA.hand_name(p.hand) }, "cancel")
			return
		end
		local levels = math.floor(tonumber(p.levels) or 0)
		levels = math.max(0, math.min(levels, IA.config("c_mp_level_steal").levels))
		IA.change_hand_level(p.hand, levels)
		IA.show_text("k_mp_level_stolen_nemesis", { levels, IA.hand_name(p.hand) })
	end,
})

SMODS.Consumable({
	key = "level_steal",
	set = "Attack",
	-- Placeholder art: The Sun's sprite from the default (vanilla Tarot) atlas
	pos = { x = 9, y = 1 },
	cost = 4,
	unlocked = true,
	discovered = true,
	config = { extra = { levels = 1 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = { card.ability.extra.levels } }
	end,
	can_use = function(self, card)
		return IA.nemesis_present()
	end,
	use = function(self, card, area, copier)
		IA.send("level_steal")
	end,
})
