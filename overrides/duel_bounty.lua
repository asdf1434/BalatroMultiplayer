-- Duel bounty race: there is always one live bounty, a goal both players can
-- see. The first player to complete it earns money. Only runs in lobbies whose
-- ruleset has the `duel` layer and whose "Bounties" lobby option is on.
--
-- Reveal (same moment on both games, no messages needed):
--   bounty 1 appears at game start
--   bounty k+1 appears when a boss PvP blind ends (the server's endPvP reaches
--   both games together); the previous bounty expires at that moment
--
-- Same goal on both games: tier, goal and goal option for bounty k are picked
-- with pseudorandom, seeded from the run seed, k and the ante (see pick()). No
-- message is needed to agree on them, and no game RNG queue is advanced.
--
-- Tiers: easy / medium / hard, chosen from the bounty's ante (TIERS_BY_ANTE).
-- Jackpot: an expired, unclaimed bounty's reward is added to the next one.
--
-- One winner: the host's game decides.
--   host completes it  -> host records "host" if nobody has it yet, pays itself,
--                         sends "bounty_result" to the guest
--   guest completes it -> guest sends "bounty_claim"; host records "guest" if
--                         nobody has it yet and it has not expired, then replies
--                         "bounty_result" with the recorded winner and amount
-- The host answers every claim with whoever it has recorded ("none" = expired
-- unclaimed), so a repeated claim is harmless. The guest resends an unanswered
-- claim every few seconds (lost message, or a Nemesis who reconnected). The
-- amount in the host's reply is what the guest is paid, so a jackpot the guest
-- computed differently (after a lost message) cannot pay the wrong amount.

MP.BOUNTY = MP.BOUNTY or {}
MP.BOUNTY.rewards = { easy = 4, medium = 8, hard = 12 }
MP.BOUNTY.jackpot = true
-- First row whose max_ante is >= the bounty's ante wins; one tier is picked from it.
MP.BOUNTY.TIERS_BY_ANTE = {
	{ max_ante = 3, tiers = { "easy" } },
	{ max_ante = 5, tiers = { "easy", "medium" } },
	{ max_ante = math.huge, tiers = { "medium", "hard" } },
}
MP.BOUNTY.claim_retry_seconds = 5

-- Goal numbers
MP.BOUNTY.hand_types = { "High Card", "Pair", "Three of a Kind" }
MP.BOUNTY.discard_counts = { 1, 2 }
MP.BOUNTY.low_shop_money = 3 -- "have less than $3 in the shop"
MP.BOUNTY.face_counts = { 3, 4, 5 }
MP.BOUNTY.quick_blind_hands = 2
MP.BOUNTY.reroll_streak = 5
MP.BOUNTY.exact_money = { 49, 64, 81, 100 }
MP.BOUNTY.low_score = 100
MP.BOUNTY.sell_jokers = 2

local function num(x)
	if to_number then return to_number(x) end
	return x
end

local function face_count(cards)
	local n = 0
	for _, c in ipairs(cards or {}) do
		if c:is_face() then n = n + 1 end
	end
	return n
end

local function hand_score()
	if SMODS.calculate_round_score then return SMODS.calculate_round_score() end
	return (hand_chips or 0) * (mult or 0)
end

local function dollars() return num(G.GAME.dollars) end

-- Each goal reacts to one kind of event. Every handler is called as
-- handler(ctx, opt, b); ctx is only set for `context`.
--   context: a top-level SMODS.calculate_context call
--   poll:    every frame (for money checks)
--   lucky:   a Lucky card triggered
--   reroll:  the shop was rerolled (b.shop_rerolls already counted)
-- `opt` is the option picked for this bounty from `options` (or nil); `b` is the
-- bounty record, which also holds per-bounty counters.
-- Order matters inside each tier: both games index these lists with the same
-- seeded number. Append new goals at the end of a tier.
MP.BOUNTY.GOALS = {
	easy = {
		{
			key = "reroll",
			reroll = function() return true end,
		},
		{
			key = "hand_type",
			options = MP.BOUNTY.hand_types,
			vars = function(opt) return { localize(opt, "poker_hands") } end,
			context = function(ctx, opt) return ctx.after and ctx.scoring_name == opt end,
		},
		{
			key = "discard",
			options = MP.BOUNTY.discard_counts,
			loc_key = function(opt) return opt == 1 and "discard_one" or "discard" end,
			vars = function(opt) return { opt } end,
			context = function(ctx, opt) return ctx.pre_discard and #(ctx.full_hand or {}) == opt end,
		},
		{
			key = "low_money",
			vars = function() return { MP.BOUNTY.low_shop_money } end,
			poll = function()
				return G.STATE == G.STATES.SHOP and dollars() < MP.BOUNTY.low_shop_money
			end,
		},
		{
			key = "tarot",
			context = function(ctx)
				return ctx.using_consumeable and ctx.consumeable and ctx.consumeable.ability.set == "Tarot"
			end,
		},
	},
	medium = {
		{
			key = "faces",
			options = MP.BOUNTY.face_counts,
			vars = function(opt) return { opt } end,
			context = function(ctx, opt) return ctx.after and face_count(ctx.full_hand) >= opt end,
		},
		{
			-- PvP blinds are left out: they have no fixed target to beat.
			key = "quick_blind",
			vars = function() return { MP.BOUNTY.quick_blind_hands } end,
			context = function(ctx)
				return ctx.end_of_round
					and not ctx.game_over
					and not MP.is_pvp_boss()
					and G.GAME.current_round.hands_played <= MP.BOUNTY.quick_blind_hands
			end,
		},
		{
			key = "lucky",
			lucky = function() return true end,
		},
		{
			key = "reroll_streak",
			vars = function() return { MP.BOUNTY.reroll_streak } end,
			reroll = function(_, _, b) return b.shop_rerolls >= MP.BOUNTY.reroll_streak end,
		},
		{
			key = "spectral",
			context = function(ctx)
				return ctx.using_consumeable and ctx.consumeable and ctx.consumeable.ability.set == "Spectral"
			end,
		},
	},
	hard = {
		{
			key = "exact_money",
			options = MP.BOUNTY.exact_money,
			vars = function(opt) return { opt } end,
			poll = function(_, opt) return dollars() == opt end,
		},
		{
			key = "straight_flush",
			context = function(ctx)
				return ctx.after and ctx.poker_hands and next(ctx.poker_hands["Straight Flush"] or {})
			end,
		},
		{
			key = "low_score",
			vars = function() return { MP.BOUNTY.low_score } end,
			context = function(ctx) return ctx.after and to_big(hand_score()) < to_big(MP.BOUNTY.low_score) end,
		},
		{
			-- Counts only Jokers sold after this bounty appeared.
			key = "sell_jokers",
			vars = function(_, b) return { MP.BOUNTY.sell_jokers, math.min(b.sold, MP.BOUNTY.sell_jokers) } end,
			context = function(ctx, _, b)
				if ctx.selling_card and ctx.card and ctx.card.ability.set == "Joker" then b.sold = b.sold + 1 end
				return b.sold >= MP.BOUNTY.sell_jokers
			end,
		},
	},
}

-- Stateless seeded pick in 1..n: hash a new key, seed pseudorandom with the
-- number. Same answer every call, on both games, and no RNG queue moves. With
-- "different seeds" the runs have different seeds, so the lobby code is used.
local function pick(key, n)
	local base = MP.LOBBY.config.different_seeds and MP.LOBBY.code or G.GAME.pseudorandom.seed
	return pseudorandom(pseudohash("mp_duel_bounty_" .. key .. "_" .. tostring(base)), 1, n)
end

local function tiers_for_ante(ante)
	for _, row in ipairs(MP.BOUNTY.TIERS_BY_ANTE) do
		if ante <= row.max_ante then return row.tiers end
	end
end

local function new_bounty(index, ante)
	local tiers = tiers_for_ante(ante)
	local tier = tiers[pick(index .. "_tier", #tiers)]
	local goals = MP.BOUNTY.GOALS[tier]
	local goal = goals[pick(index .. "_goal", #goals)]
	local opt = goal.options and goal.options[pick(index .. "_opt", #goal.options)]
	return { index = index, ante = ante, tier = tier, goal = goal, opt = opt, sold = 0, shop_rerolls = 0 }
end

local function state() return MP.GAME.duel_bounty end

local function my_role() return MP.LOBBY.is_host and "host" or "guest" end

local function in_run() return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD and G.GAME.round_resets end

function MP.BOUNTY.is_active()
	return MP.LOBBY.code
			and MP.LOBBY.config.duel_bounties ~= false
			and in_run()
			and MP.is_layer_active("duel")
			and true
		or false
end

-- Reward for bounty `index`, including the jackpot from earlier unclaimed ones.
-- A past bounty with no known winner counts as unclaimed.
function MP.BOUNTY.reward(index)
	local s = state()
	local b = s.history[index]
	if not b then return 0 end
	local amount = MP.BOUNTY.rewards[b.tier]
	local prev = s.winners[index - 1]
	if MP.BOUNTY.jackpot and index > 1 and (prev == nil or prev == "none") then
		amount = amount + MP.BOUNTY.reward(index - 1)
	end
	return amount
end

function MP.BOUNTY.current()
	local s = state()
	return s and s.history[s.index]
end

function MP.BOUNTY.goal_text(b)
	local goal = b.goal
	local loc_key = goal.loc_key and goal.loc_key(b.opt) or goal.key
	return localize({
		type = "variable",
		key = "k_mp_bounty_goal_" .. loc_key,
		vars = goal.vars and goal.vars(b.opt, b) or {},
	})
end

-- "open", "pending" (guest is waiting for the host's answer), "mine" or "nemesis"
function MP.BOUNTY.status(index)
	local s = state()
	local winner = s.winners[index]
	if winner == "host" or winner == "guest" then return winner == my_role() and "mine" or "nemesis" end
	if s.pending[index] then return "pending" end
	return "open"
end

local function nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

local function show_text(text, colour)
	G.FUNCS.attention_text_realtime({
		text = text,
		scale = 0.7,
		hold = 2.5,
		align = "cm",
		major = G.play,
		backdrop_colour = colour,
	})
end

local function reveal(index, ante)
	local s = state()
	-- The previous bounty expires now. The host's "none" is final; the guest
	-- keeps a pending claim open until the host answers it.
	local prev = index - 1
	if prev >= 1 and s.winners[prev] == nil and (MP.LOBBY.is_host or not s.pending[prev]) then
		s.winners[prev] = "none"
	end
	s.index = index
	s.history[index] = new_bounty(index, ante)
	if index > 1 then
		show_text(localize({ type = "variable", key = "k_mp_bounty_new", vars = {} }), G.C.GOLD)
	end
end

-- Records the winner once and pays / notifies locally. Later calls for the same
-- bounty do nothing, so a result or claim that arrives twice cannot pay twice.
-- `amount` is what the winner is paid (the host's figure).
local function record_winner(index, winner, amount)
	local s = state()
	local was_pending = s.pending[index]
	s.pending[index] = nil
	if s.winners[index] and s.winners[index] ~= "none" then return end
	if s.winners[index] == "none" and MP.LOBBY.is_host then return end
	s.winners[index] = winner
	if winner == "none" then
		if was_pending then
			show_text(localize({ type = "variable", key = "k_mp_bounty_too_late", vars = {} }), G.C.RED)
		end
		return
	end
	if winner == my_role() then
		if not s.paid[index] then
			s.paid[index] = true
			ease_dollars(amount)
			show_text(localize({ type = "variable", key = "k_mp_bounty_won", vars = { amount } }), G.C.MONEY)
			play_sound("coin1")
		end
	else
		show_text(localize({ type = "variable", key = "k_mp_bounty_lost", vars = {} }), G.C.RED)
	end
end

local function send_claim(index)
	state().pending[index] = love.timer.getTime()
	MP.ACTIONS.modded(MP.id, "bounty_claim", { index = index })
end

local function on_goal_completed(b)
	if MP.BOUNTY.status(b.index) ~= "open" then return end
	if MP.LOBBY.is_host then
		local amount = MP.BOUNTY.reward(b.index)
		record_winner(b.index, "host", amount)
		MP.ACTIONS.modded(MP.id, "bounty_result", { index = b.index, winner = "host", amount = amount })
	else
		send_claim(b.index)
	end
end

-- Runs the current goal's handler for one event and claims if it is met.
local function check(event, ctx)
	if not MP.BOUNTY.is_active() then return end
	local b = MP.BOUNTY.current()
	if not b or MP.BOUNTY.status(b.index) ~= "open" then return end
	local handler = b.goal[event]
	if handler and handler(ctx, b.opt, b) then on_goal_completed(b) end
end

local function valid_index(i)
	i = tonumber(i)
	if not i or i ~= math.floor(i) or i < 1 then return nil end
	return i
end

-- Runs on the host's game.
MP.register_mod_action("bounty_claim", function(p)
	if not MP.LOBBY.is_host or not MP.BOUNTY.is_active() or not state() then return end
	local index = valid_index(p.index)
	-- A claim one ahead is allowed: the guest may see endPvP a moment earlier.
	if not index or index > state().index + 1 then return end
	if index > state().index then
		-- Not revealed here yet; reveal it now so the reward can be computed.
		reveal(index, G.GAME.round_resets.ante + 1)
	end
	record_winner(index, "guest", nil) -- no-op if someone has it or it expired
	local winner = state().winners[index]
	MP.ACTIONS.modded(MP.id, "bounty_result", {
		index = index,
		winner = winner,
		amount = winner == "guest" and MP.BOUNTY.reward(index) or 0,
	})
end, MP.id)

-- Runs on the guest's game.
MP.register_mod_action("bounty_result", function(p)
	if MP.LOBBY.is_host or not MP.BOUNTY.is_active() or not state() then return end
	local index = valid_index(p.index)
	if not index or (p.winner ~= "host" and p.winner ~= "guest" and p.winner ~= "none") then return end
	local amount = math.max(0, math.min(tonumber(p.amount) or 0, 10000))
	record_winner(index, p.winner, amount)
end, MP.id)

local calculate_context_ref = SMODS.calculate_context
function SMODS.calculate_context(context, return_table, no_resolve)
	if type(context) == "table" and state() then
		if context.starting_shop and MP.BOUNTY.current() then MP.BOUNTY.current().shop_rerolls = 0 end
		if
			context.after
			or context.pre_discard
			or context.using_consumeable
			or context.end_of_round
			or context.selling_card
		then
			check("context", context)
		end
	end
	return calculate_context_ref(context, return_table, no_resolve)
end

local reroll_shop_ref = G.FUNCS.reroll_shop
function G.FUNCS.reroll_shop(e)
	local ret = reroll_shop_ref(e)
	local b = state() and MP.BOUNTY.current()
	if b then
		b.shop_rerolls = b.shop_rerolls + 1
		check("reroll")
	end
	return ret
end

-- Lucky cards set lucky_trigger when their mult or money roll succeeds.
local get_chip_mult_ref = Card.get_chip_mult
function Card:get_chip_mult()
	local ret = get_chip_mult_ref(self)
	if self.lucky_trigger and state() then check("lucky") end
	return ret
end

local get_p_dollars_ref = Card.get_p_dollars
function Card:get_p_dollars()
	local ret = get_p_dollars_ref(self)
	if self.lucky_trigger and state() then check("lucky") end
	return ret
end

local was_end_pvp = false
local bounty_update_ref = Game.update
function Game:update(dt)
	if MP.BOUNTY.is_active() then
		-- First bounty at game start. MP.GAME is reset for every new game.
		if not MP.GAME.duel_bounty then
			MP.GAME.duel_bounty =
				{ index = 0, pvp_ends = 0, history = {}, winners = {}, paid = {}, pending = {} }
			reveal(1, G.GAME.round_resets.ante)
			was_end_pvp = MP.GAME.end_pvp
		end
		-- Next bounty when a boss PvP blind ends. The ante has not gone up yet.
		-- The host may already have revealed it early because of a guest claim.
		if MP.GAME.end_pvp and not was_end_pvp and G.GAME.blind_on_deck == "Boss" then
			local s = state()
			s.pvp_ends = s.pvp_ends + 1
			if s.index < s.pvp_ends + 1 then reveal(s.pvp_ends + 1, G.GAME.round_resets.ante + 1) end
		end
		was_end_pvp = MP.GAME.end_pvp
		check("poll")

		-- Guest: resend unanswered claims. The host answers repeats the same way.
		if not MP.LOBBY.is_host and nemesis_present() then
			local now = love.timer.getTime()
			for index, sent_at in pairs(state().pending) do
				if now - sent_at >= MP.BOUNTY.claim_retry_seconds then send_claim(index) end
			end
		end
	end
	return bounty_update_ref(self, dt)
end
