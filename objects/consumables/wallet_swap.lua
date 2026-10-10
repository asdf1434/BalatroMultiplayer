-- Wallet Swap: the two players trade money totals. Exchange (see
-- _instant_attacks.lua):
--   1. user's game sends "wallet_swap_request" with its money
--   2. Nemesis' game sets its money to that amount and replies with its old money
--   3. user's game changes its money by (Nemesis' old money - user's sent money)
-- Step 3 adds the difference instead of setting the total, so money the user
-- earned or spent between sending and the reply is kept, and no money is
-- created or lost overall. Money lost in a swap is not spending (Penny Pincher).
--
-- Both players using Wallet Swap at the same moment: each request reaches the
-- other game while that game still waits for its own reply. Doing both swaps
-- would trade the money twice (back to where it started, or worse with the
-- difference rule above), so only one happens: the host's game refuses the
-- guest's request ("busy") and the guest gets the card back, while the guest's
-- game answers the host's request normally. Messages from one player arrive in
-- order, so the host's game always sees the guest's request before the guest's
-- answer, while its own swap is still waiting.
local IA = MP.INSTANT_ATTACKS

-- The swap this game started and is still waiting on: { game = G.GAME } or nil.
-- One at a time: the card cannot be used while a swap is waiting.
local pending = nil

local function refund()
	SMODS.add_card({ key = "c_mp_wallet_swap", area = G.consumeables })
end

IA.register("wallet_swap", {
	-- Nemesis' game.
	answer = function(p)
		if pending and MP.LOBBY.is_host then return { result = "busy" } end
		local user_dollars = tonumber(p.dollars)
		if not user_dollars or user_dollars ~= user_dollars or math.abs(user_dollars) == math.huge then
			return { result = "failed" }
		end
		user_dollars = math.floor(user_dollars)
		local own_dollars = IA.dollars()
		IA.change_dollars(user_dollars - own_dollars)
		IA.show_text("k_mp_wallet_swapped_by_nemesis", { own_dollars, user_dollars }, "coin1")
		return { result = "swapped", nemesis_dollars = own_dollars, user_dollars = user_dollars }
	end,
	-- User's game.
	finish = function(p)
		pending = nil
		if p.result == "swapped" then
			local nemesis_dollars = math.floor(tonumber(p.nemesis_dollars) or 0)
			local user_dollars = math.floor(tonumber(p.user_dollars) or 0)
			IA.change_dollars(nemesis_dollars - user_dollars)
			IA.show_text("k_mp_wallet_swapped_nemesis", { user_dollars, nemesis_dollars }, "coin1")
		elseif p.result == "busy" then
			IA.show_text("k_mp_wallet_swap_busy", {}, "cancel")
			refund()
		else
			IA.show_text("k_mp_wallet_swap_failed", {}, "cancel")
		end
	end,
	cancelled = function(p)
		pending = nil
	end,
})

-- A reply can no longer arrive when the Nemesis dropped out or this run ended.
-- The card stays spent (as with Tax Collector, the Nemesis may already have
-- swapped before dropping out).
local wallet_swap_update_ref = Game.update
function Game:update(dt)
	if pending and (pending.game ~= G.GAME or not IA.nemesis_present()) then pending = nil end
	return wallet_swap_update_ref(self, dt)
end

SMODS.Consumable({
	key = "wallet_swap",
	set = "Attack",
	-- Placeholder art: The Wheel of Fortune's sprite from the default (vanilla Tarot) atlas
	pos = { x = 0, y = 1 },
	cost = 4,
	unlocked = true,
	discovered = true,
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = {} }
	end,
	can_use = function(self, card)
		return IA.nemesis_present() and not pending
	end,
	use = function(self, card, area, copier)
		pending = { game = G.GAME }
		IA.send("wallet_swap", { dollars = IA.dollars() })
	end,
})
