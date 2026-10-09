-- Fog: the first hand drawn in the Nemesis' next blind is face down, like The
-- House. Each copy that lands covers one more draw: two Fogs make the first
-- draw and the draw after the first play or discard face down.

local KEY = "c_mp_fog"
local NBA = MP.NEXT_BLIND_ATTACKS

NBA.register(KEY, {
	apply = function(entries)
		return { hands = #entries }
	end,
	undo = function(state, leaving) end,
})

-- Same check as The House in Blind:stay_flipped, counted per Fog copy.
local stay_flipped_ref = Blind.stay_flipped
function Blind:stay_flipped(area, card, from_area)
	local ret = stay_flipped_ref(self, area, card, from_area)
	if ret then return ret end
	local active = NBA.active(KEY)
	if active and area == G.hand then
		local round = G.GAME.current_round
		if round.hands_played + round.discards_used < active.hands then return true end
	end
	return ret
end

SMODS.Consumable({
	key = "fog",
	set = "Attack",
	-- Placeholder art: The High Priestess' sprite from the default (vanilla Tarot) atlas
	pos = { x = 2, y = 0 },
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
