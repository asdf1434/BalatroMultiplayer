-- Suit Debuff: every card of a random suit is debuffed during the Nemesis' next
-- blind, like The Goad. The suit is picked when the attack arrives (on the
-- Nemesis' game) so the incoming list can name it. Copies waiting for the same
-- blind pick different suits while any are left.
-- Uses its own SMODS debuff source, so it never touches other debuffs.

local KEY = "c_mp_suit_debuff"
local DEBUFF_SOURCE = "mp_suit_debuff"
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
local NBA = MP.NEXT_BLIND_ATTACKS

NBA.register(KEY, {
	on_receive = function(entry, pending)
		local taken = {}
		for _, other in ipairs(pending) do
			if other.key == KEY then taken[other.suit] = true end
		end
		local choices = {}
		for _, suit in ipairs(SUITS) do
			if not taken[suit] then choices[#choices + 1] = suit end
		end
		if #choices == 0 then choices = SUITS end
		entry.suit = pseudorandom_element(choices, pseudoseed("mp_suit_debuff"))
	end,
	detail = function(entry)
		if not SMODS.Suits[entry.suit] then return nil end
		return localize(entry.suit, "suits_plural")
	end,
	short_name = "k_mp_nba_short_suit_debuff",
	short = function(entry)
		if not SMODS.Suits[entry.suit] then return nil end
		return localize(entry.suit, "suits_plural")
	end,
	effect = function(entry)
		local suit = SMODS.Suits[entry.suit] and localize(entry.suit, "suits_plural") or "?"
		return localize({ type = "variable", key = "k_mp_nba_effect_suit_debuff", vars = { suit } })
	end,
	apply = function(entries)
		local suits = {}
		for _, entry in ipairs(entries) do
			if SMODS.Suits[entry.suit] then suits[#suits + 1] = entry.suit end
		end
		return { suits = suits }
	end,
	-- The state is cleared before this runs, so recalculating drops the source.
	undo = function(state, leaving)
		for _, card in ipairs(G.playing_cards or {}) do
			if card.ability.debuff_sources and card.ability.debuff_sources[DEBUFF_SOURCE] ~= nil then
				SMODS.debuff_card(card, nil, DEBUFF_SOURCE)
			end
		end
	end,
})

-- Every debuff check (blind start, card drawn, suit changed, card created) goes
-- through here, so a card that changes suit mid-blind is updated too.
local debuff_card_ref = Blind.debuff_card
function Blind:debuff_card(card, from_blind)
	if card and card.playing_card and card.ability then
		local active = NBA.active(KEY)
		local hit = nil
		if active then
			for _, suit in ipairs(active.suits) do
				if card:is_suit(suit, true) then hit = true end
			end
		end
		card.ability.debuff_sources = card.ability.debuff_sources or {}
		card.ability.debuff_sources[DEBUFF_SOURCE] = hit
	end
	return debuff_card_ref(self, card, from_blind)
end

-- Apply runs after the blind's own debuff pass, so recheck the deck here.
local set_blind_ref = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
	set_blind_ref(self, blind, reset, silent)
	if NBA.active(KEY) and blind and not reset then
		for _, card in ipairs(G.playing_cards or {}) do
			SMODS.recalc_debuff(card)
		end
	end
end

SMODS.Consumable({
	key = "suit_debuff",
	set = "Attack",
	-- Placeholder art: The Moon's sprite from the default (vanilla Tarot) atlas
	pos = { x = 8, y = 1 },
	cost = 6,
	unlocked = true,
	discovered = true,
	config = { extra = { chance = 0.75 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = { math.floor(card.ability.extra.chance * 100 + 0.5), NBA.max_pending } }
	end,
	can_use = function(self, card)
		return NBA.can_send()
	end,
	use = function(self, card, area, copier)
		NBA.send(KEY)
	end,
})
