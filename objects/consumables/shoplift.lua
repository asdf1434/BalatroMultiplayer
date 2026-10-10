-- Shoplift: the Nemesis' next shop has fewer card slots (never below 1), for
-- that shop visit only. Copies that land on the same shop add up.
--
-- The slots are removed from G.GAME.shop.joker_max when the shop is created,
-- before its card area is built and filled, and given back when the Nemesis
-- leaves the shop. Only the number actually removed is given back, so an
-- Overstock voucher bought during that visit keeps its extra slot.
--
-- Keeping the shop in sync: both games pick shop cards from the same random
-- sequence, so a shop with fewer slots would use fewer picks, and every later
-- card this ante (rerolls, the next shops) would differ from the attacker's
-- game. To avoid that, each time the shop is filled (on entry and on every
-- reroll), the cards for the removed slots are still picked and then thrown
-- away unseen. The cards the Nemesis sees are the same ones the attacker's
-- game shows in the same slots.

local KEY = "c_mp_shoplift"
local NBA = MP.NEXT_BLIND_ATTACKS

NBA.register(KEY, {
	target = "shop",
	detail = function(entry)
		return localize({ type = "variable", key = "k_mp_nba_shoplift_detail", vars = { NBA.config(KEY).slots } })
	end,
	effect = function(entry)
		return localize({ type = "variable", key = "k_mp_nba_effect_shoplift", vars = { NBA.config(KEY).slots } })
	end,
	apply = function(entries)
		local shop = G.GAME.shop
		local wanted = #entries * NBA.config(KEY).slots
		local removed = math.max(0, math.min(wanted, shop.joker_max - 1))
		shop.joker_max = shop.joker_max - removed
		return { removed = removed }
	end,
	-- The shop's card area is closed with the shop, so only the count is restored.
	undo = function(state, leaving)
		if state.removed > 0 and G.GAME.shop then G.GAME.shop.joker_max = G.GAME.shop.joker_max + state.removed end
	end,
})

-- change_shop_size (Overstock) adds one card for a new slot; that is not a
-- shop fill, so no hidden cards are picked for it.
local changing_size = false
local change_shop_size_ref = change_shop_size
function change_shop_size(mod)
	changing_size = true
	change_shop_size_ref(mod)
	changing_size = false
end

-- Tags must not act on a thrown-away card (an Edition Tag would be used up).
local tag_apply_ref = Tag.apply_to_run
function Tag:apply_to_run(context)
	if context and context.card and context.card.mp_shoplift_hidden then return nil end
	return tag_apply_ref(self, context)
end

-- A shop fill creates cards one at a time and places each before creating the
-- next, so the card for the last visible slot is the one created while the
-- area holds joker_max - 1 cards. Right after it, pick the hidden cards.
local create_card_for_shop_ref = create_card_for_shop
function create_card_for_shop(area)
	local card = create_card_for_shop_ref(area)
	local active = NBA.active(KEY)
	if
		active
		and active.removed > 0
		and not changing_size
		and area == G.shop_jokers
		and #area.cards == G.GAME.shop.joker_max - 1
	then
		-- Tags are kept out so a Rare or Uncommon Tag is not used up here.
		local tags = G.GAME.tags
		G.GAME.tags = {}
		for _ = 1, active.removed do
			local hidden = create_card_for_shop_ref(area)
			if hidden then
				hidden.mp_shoplift_hidden = true
				hidden.opening = true -- stops the price and Buy buttons from being built
				hidden:remove()
			end
		end
		G.GAME.tags = tags
	end
	return card
end

SMODS.Consumable({
	key = "shoplift",
	set = "Attack",
	-- Placeholder art: The Chariot's sprite from the default (vanilla Tarot) atlas
	pos = { x = 7, y = 0 },
	cost = 6,
	unlocked = true,
	discovered = true,
	config = { extra = { slots = 1, chance = 0.75 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return {
			vars = { math.floor(card.ability.extra.chance * 100 + 0.5), card.ability.extra.slots, NBA.max_pending },
		}
	end,
	can_use = function(self, card)
		return NBA.can_send()
	end,
	use = function(self, card, area, copier)
		NBA.send(KEY)
	end,
})
