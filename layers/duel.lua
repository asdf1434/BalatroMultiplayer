-- Duel: cards that act on the opponent's run directly.
-- Attack cards (the "Attack" consumable type) only show up in the shop while this
-- layer is active. The type's shop_rate is 0 everywhere else, so the shop's type
-- roll is unchanged for every other ruleset.
MP.DUEL = MP.DUEL or {}
MP.DUEL.attack_shop_rate = 2

MP.Layer("duel", {
	reworked_consumables = {
		"c_mp_tax_collector",
		"c_mp_cripple",
		"c_mp_joker_swap",
	},
	on_apply_bans = function()
		G.GAME.attack_rate = MP.DUEL.attack_shop_rate
	end,
})
