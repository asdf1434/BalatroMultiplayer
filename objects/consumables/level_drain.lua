-- Level Drain: the Nemesis' most-played poker hand loses levels (never below
-- level 1). Only the Nemesis' game knows their hands, so it picks the hand,
-- lowers it and replies with the result (see _instant_attacks.lua).
local IA = MP.INSTANT_ATTACKS

IA.register("level_drain", {
	-- Nemesis' game. The amount comes from this game's own card config.
	answer = function(p)
		local hand = IA.most_played_hand()
		local drained = -IA.change_hand_level(hand, -IA.config("c_mp_level_drain").levels)
		if drained == 0 then
			IA.show_text("k_mp_level_drain_min_by_nemesis", { IA.hand_name(hand) }, "cancel")
			return { result = "min_level", hand = hand }
		end
		IA.show_text("k_mp_level_drained_by_nemesis", { IA.hand_name(hand), IA.hand_level(hand) }, "cancel")
		return { result = "drained", hand = hand, level = IA.hand_level(hand) }
	end,
	-- User's game.
	finish = function(p)
		if not IA.is_hand(p.hand) then return end
		if p.result == "drained" then
			local level = math.floor(tonumber(p.level) or 1)
			IA.show_text("k_mp_level_drained_nemesis", { IA.hand_name(p.hand), level })
		else
			IA.show_text("k_mp_level_min_nemesis", { IA.hand_name(p.hand) }, "cancel")
		end
	end,
})

SMODS.Consumable({
	key = "level_drain",
	set = "Attack",
	-- Placeholder art: The Star's sprite from the default (vanilla Tarot) atlas
	pos = { x = 7, y = 1 },
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
		IA.send("level_drain")
	end,
})
