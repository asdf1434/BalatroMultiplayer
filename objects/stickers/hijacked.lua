-- Hijacked: marks the temporary Joker copy made by the Hijack Attack card (see
-- objects/consumables/hijack.lua). The copy itself is flagged with
-- ability.mp_hijack_copy; this sticker only shows the badge and the tooltip.
-- needs_enable_flag + default_compat = false: never rolls in shops or packs.
SMODS.Sticker({
	key = "sticker_hijacked",
	-- Placeholder art: the Unreliable sticker's icon from the alt_stickers atlas
	atlas = "alt_stickers",
	pos = { x = 1, y = 0 },
	badge_colour = HEX("8e44ad"),
	default_compat = false,
	needs_enable_flag = true,
})
