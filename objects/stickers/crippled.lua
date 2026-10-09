-- Crippled: marks the Joker that the Nemesis' Cripple card picked. The Joker is
-- debuffed during the next PvP blind (see objects/consumables/cripple.lua).
-- needs_enable_flag + default_compat = false: never rolls in shops or packs.
SMODS.Sticker({
	key = "sticker_crippled",
	-- Placeholder art: the Draining sticker's red icon from the alt_stickers atlas
	atlas = "alt_stickers",
	pos = { x = 2, y = 0 },
	badge_colour = HEX("c0392b"),
	default_compat = false,
	needs_enable_flag = true,
})
