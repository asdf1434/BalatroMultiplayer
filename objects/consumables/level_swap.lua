-- Level Swap: the two players trade their levels of the Nemesis' most-played
-- poker hand (for example the user's level 2 Flush for the Nemesis' level 8
-- Flush). Exchange (see _instant_attacks.lua):
--   1. user's game sends "level_swap_request" with its level of every poker hand
--      (it does not know which hand the Nemesis will pick), as a JSON string
--   2. Nemesis' game picks its most-played hand, sets it to the user's level and
--      replies with its own old level of that hand
--   3. user's game changes the hand by (Nemesis' old level - user's sent level)
-- Step 3 adds the difference instead of setting a level, so a level the user
-- gained between sending and the reply (a Planet used meanwhile) is kept.
-- Received text is only ever JSON-decoded, never run.
local IA = MP.INSTANT_ATTACKS
local json = require("json")

local function encode_levels()
	local levels = {}
	for key, _ in pairs(G.GAME.hands) do
		levels[key] = IA.hand_level(key)
	end
	local ok, text = pcall(json.encode, levels)
	return ok and text or nil
end

-- The user's level of one hand from the request, or nil.
local function decode_level(text, hand)
	if type(text) ~= "string" then return nil end
	local ok, levels = pcall(json.decode, text)
	if not ok or type(levels) ~= "table" then return nil end
	local level = tonumber(levels[hand])
	if not level or level ~= level or level == math.huge then return nil end
	return math.max(1, math.floor(level))
end

IA.register("level_swap", {
	-- Nemesis' game.
	answer = function(p)
		local hand = IA.most_played_hand()
		local user_level = decode_level(p.levels, hand)
		if not user_level then return { result = "failed" } end
		local own_level = IA.hand_level(hand)
		IA.change_hand_level(hand, user_level - own_level)
		IA.show_text("k_mp_level_swapped_by_nemesis", { IA.hand_name(hand), own_level, user_level })
		return { result = "swapped", hand = hand, nemesis_level = own_level, user_level = user_level }
	end,
	-- User's game.
	finish = function(p)
		if p.result ~= "swapped" or not IA.is_hand(p.hand) then
			IA.show_text("k_mp_level_swap_failed", {}, "cancel")
			return
		end
		local nemesis_level = math.max(1, math.floor(tonumber(p.nemesis_level) or 1))
		local user_level = math.max(1, math.floor(tonumber(p.user_level) or 1))
		IA.change_hand_level(p.hand, nemesis_level - user_level)
		IA.show_text("k_mp_level_swapped_nemesis", { IA.hand_name(p.hand), user_level, nemesis_level })
	end,
})

SMODS.Consumable({
	key = "level_swap",
	set = "Attack",
	-- Placeholder art: Justice's sprite from the default (vanilla Tarot) atlas
	pos = { x = 8, y = 0 },
	cost = 4,
	unlocked = true,
	discovered = true,
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = {} }
	end,
	can_use = function(self, card)
		return IA.nemesis_present()
	end,
	use = function(self, card, area, copier)
		local levels = encode_levels()
		if levels then IA.send("level_swap", { levels = levels }) end
	end,
})
