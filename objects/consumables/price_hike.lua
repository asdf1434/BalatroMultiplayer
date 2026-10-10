-- Price Hike: everything in the Nemesis' next shop costs more (Jokers and other
-- cards, Booster Packs, Vouchers), including cards that appear after a reroll
-- in that same visit. Copies that land on the same shop add up. Leaving the
-- shop ends it.
--
-- Only prices change: the shop is built and filled exactly as without the
-- attack. The extra cost is added in Card:set_cost while the card sits in one
-- of the shop's card areas, so:
--   - a card's sell value is still worked out from its normal price
--   - a card that leaves the shop (bought) gets its normal price back the
--     next time its cost is recalculated
--   - free items (Coupon Tag, Astronomer) stay free
-- The attacker's game never has this effect active, so their shop is unchanged.

local KEY = "c_mp_price_hike"
local NBA = MP.NEXT_BLIND_ATTACKS

local function shop_area(area)
	return area ~= nil and (area == G.shop_jokers or area == G.shop_vouchers or area == G.shop_booster)
end

NBA.register(KEY, {
	target = "shop",
	detail = function(entry)
		return localize({ type = "variable", key = "k_mp_nba_price_hike_detail", vars = { NBA.config(KEY).dollars } })
	end,
	effect = function(entry)
		return localize({ type = "variable", key = "k_mp_nba_effect_price_hike", vars = { NBA.config(KEY).dollars } })
	end,
	apply = function(entries)
		return { dollars = #entries * NBA.config(KEY).dollars }
	end,
	-- The shop is being closed; its cards are removed with it.
	undo = function(state, leaving) end,
})

-- Load order puts this wrapper outside the other set_cost wrappers (decks,
-- stickers), so it sees the final price.
local set_cost_ref = Card.set_cost
function Card:set_cost()
	set_cost_ref(self)
	local active = NBA.active(KEY)
	if active and self.cost > 0 and shop_area(self.area) then self.cost = self.cost + active.dollars end
end

-- A shop card's price is set when it is created, before it is placed in the
-- shop, so work it out again once it is in a shop area.
local emplace_ref = CardArea.emplace
function CardArea:emplace(card, ...)
	emplace_ref(self, card, ...)
	if NBA.active(KEY) and shop_area(self) and card and card.set_cost then card:set_cost() end
end

SMODS.Consumable({
	key = "price_hike",
	set = "Attack",
	-- Placeholder art: Temperance's sprite from the default (vanilla Tarot) atlas
	pos = { x = 4, y = 1 },
	cost = 6,
	unlocked = true,
	discovered = true,
	config = { extra = { dollars = 2, chance = 0.75 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return {
			vars = { math.floor(card.ability.extra.chance * 100 + 0.5), card.ability.extra.dollars, NBA.max_pending },
		}
	end,
	can_use = function(self, card)
		return NBA.can_send()
	end,
	use = function(self, card, area, copier)
		NBA.send(KEY)
	end,
})
