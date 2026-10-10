-- Curse: a random Joker of the Nemesis becomes Perishable (vanilla Perishable
-- sticker: debuffed after a number of rounds). Eternal Jokers, Jokers that are
-- already Perishable and Phantom copies of the user's own Jokers are skipped. If
-- none qualify, nothing happens and both players are told
-- (see _instant_attacks.lua).
--
-- The Joker's perishable_compat flag is ignored on purpose: it only keeps the
-- shop from rolling Perishable on Jokers that scale over time, and those are the
-- Jokers this attack is meant to threaten.
local IA = MP.INSTANT_ATTACKS

local function is_eternal(card)
	if SMODS.is_eternal then return SMODS.is_eternal(card, {}) end
	return card.ability.eternal
end

local function can_be_cursed(card)
	return card.ability
		and card.ability.set == "Joker"
		and not card.removed
		and not card.ability.perishable
		and not (card.edition and card.edition.type == "mp_phantom")
		-- Hijack's temporary copies vanish when the Blind ends
		and not card.ability.mp_hijack_copy
		and not is_eternal(card)
end

-- The key arrives over the network, so only use it to look up a Joker name.
local function joker_name(key)
	local center = G.P_CENTERS[key]
	if not (center and center.set == "Joker") then return localize("k_joker") end
	return localize({ type = "name_text", set = "Joker", key = key })
end

IA.register("curse", {
	-- Nemesis' game. The round count comes from this game's own card config.
	answer = function(p)
		local candidates = {}
		for _, joker in ipairs(G.jokers.cards) do
			if can_be_cursed(joker) then candidates[#candidates + 1] = joker end
		end
		if #candidates == 0 then
			IA.show_text("k_mp_curse_none_by_nemesis", {}, "cancel")
			return { result = "none" }
		end
		local joker = pseudorandom_element(candidates, pseudoseed(MP.UTILS.player_seed_key("mp_curse")))
		local rounds = IA.config("c_mp_curse").rounds
		SMODS.Stickers.perishable:apply(joker, true)
		joker.ability.perish_tally = rounds
		joker:juice_up(0.5, 0.5)
		local key = joker.config.center.key
		IA.show_text("k_mp_cursed_by_nemesis", { joker_name(key) }, "cancel")
		return { result = "cursed", joker = key }
	end,
	-- User's game.
	finish = function(p)
		if p.result == "cursed" then
			IA.show_text("k_mp_cursed_nemesis", { joker_name(tostring(p.joker)) })
		else
			IA.show_text("k_mp_curse_none_nemesis", {}, "cancel")
		end
	end,
})

SMODS.Consumable({
	key = "curse",
	set = "Attack",
	-- Placeholder art: The Devil's sprite from the default (vanilla Tarot) atlas
	pos = { x = 5, y = 1 },
	cost = 4,
	unlocked = true,
	discovered = true,
	config = { extra = { rounds = 5 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		info_queue[#info_queue + 1] = { key = "perishable", set = "Other", vars = { card.ability.extra.rounds, card.ability.extra.rounds } }
		return { vars = { card.ability.extra.rounds } }
	end,
	can_use = function(self, card)
		return IA.nemesis_present()
	end,
	use = function(self, card, area, copier)
		IA.send("curse")
	end,
})
