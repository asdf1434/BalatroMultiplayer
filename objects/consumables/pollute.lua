-- Pollute: Stone cards are added to the Nemesis' deck permanently. Only the
-- Nemesis' game can add cards to their deck, so it adds them and replies with
-- how many (see _instant_attacks.lua).
--
-- Cards are created the way vanilla Marble Joker creates its Stone card
-- (create_playing_card, then playing_card_joker_effects, so Jokers such as
-- Hologram react as they would to any added card). They go to the bottom of the
-- draw pile, where vanilla puts added cards (CardArea:emplace for a deck).
-- During a blind, when the hand is waiting for input, the cards first appear in
-- the play area so the Nemesis sees them, then move to the deck. Anywhere else
-- (shop, packs, scoring) they go straight into the deck.
local IA = MP.INSTANT_ATTACKS

local function add_stone_cards(count)
	local show = G.STATE == G.STATES.SELECTING_HAND and #G.play.cards == 0
	local cards = {}
	for i = 1, count do
		local front = pseudorandom_element(G.P_CARDS, pseudoseed(MP.UTILS.player_seed_key("mp_pollute")))
		cards[i] = create_playing_card(
			{ front = front, center = G.P_CENTERS.m_stone },
			show and G.play or G.deck,
			not show,
			nil,
			{ G.C.SECONDARY_SET.Enhanced }
		)
	end
	if show then
		delay(0.8)
		for _ = 1, count do
			draw_card(G.play, G.deck, 90, "up", nil)
		end
	end
	playing_card_joker_effects(cards)
end

IA.register("pollute", {
	-- Nemesis' game. The count comes from this game's own card config.
	answer = function(p)
		local count = IA.config("c_mp_pollute").cards
		add_stone_cards(count)
		IA.show_text("k_mp_polluted_by_nemesis", { count }, "cancel")
		return { result = "polluted", count = count }
	end,
	-- User's game.
	finish = function(p)
		local count = math.floor(tonumber(p.count) or 0)
		IA.show_text("k_mp_polluted_nemesis", { count })
	end,
})

SMODS.Consumable({
	key = "pollute",
	set = "Attack",
	-- Placeholder art: The Empress' sprite from the default (vanilla Tarot) atlas
	pos = { x = 3, y = 0 },
	cost = 4,
	unlocked = true,
	discovered = true,
	config = { extra = { cards = 2 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		info_queue[#info_queue + 1] = G.P_CENTERS.m_stone
		return { vars = { card.ability.extra.cards } }
	end,
	can_use = function(self, card)
		return IA.nemesis_present()
	end,
	use = function(self, card, area, copier)
		IA.send("pollute")
	end,
})
