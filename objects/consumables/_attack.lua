-- Attack cards act on the opponent's run. shop_rate stays 0 so they never roll
-- in the shop unless a layer raises G.GAME.attack_rate (see layers/duel.lua).
SMODS.ConsumableType({
	key = "Attack",
	primary_colour = HEX("c0392b"),
	secondary_colour = HEX("e74c3c"),
	collection_rows = { 4, 4 },
	shop_rate = 0,
})
