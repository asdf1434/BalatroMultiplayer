-- Duel bounty race: each ante has one goal that both players can see. The first
-- player to complete it earns money. Only runs in lobbies whose ruleset has the
-- `duel` layer.
--
-- Same goal on both games: the goal for ante N is picked from the run seed and N
-- with pseudorandom (see goal_for_ante). No message is needed to agree on it.
--
-- Open / expired: the bounty for ante N is open on a player's game while that
-- player is in ante N. It expires on their game when they leave ante N (after
-- that ante's boss / PvP blind). A game only sends or makes a claim while its
-- bounty is open.
--
-- One winner: the host's game decides.
--   host completes it  -> host records "host" if nobody has it yet, pays itself,
--                         sends "bounty_result" to the guest
--   guest completes it -> guest sends "bounty_claim"; host records "guest" if
--                         nobody has it yet, replies "bounty_result" with the
--                         recorded winner; guest pays itself if it won
-- The host answers every claim with whoever it has recorded, so a repeated claim
-- is harmless. The guest resends an unanswered claim every few seconds (covers a
-- lost message or a Nemesis that disconnected and came back). A claim the host
-- receives after it has left that ante is still honoured: the guest completed
-- the goal while the bounty was open on its game, and message delay should not
-- cost it the race.

MP.BOUNTY = MP.BOUNTY or {}
MP.BOUNTY.reward = 8 -- dollars for the winner
MP.BOUNTY.first_ante = 1 -- first ante that has a bounty
MP.BOUNTY.face_cards = 3 -- "play N or more face cards in one hand"
MP.BOUNTY.discard_cards = 5 -- "discard N cards at once"
MP.BOUNTY.score_mult = 1 -- "score X chips in one hand", X = ante's base blind amount * this
MP.BOUNTY.claim_retry_seconds = 5

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

function MP.BOUNTY.score_target(ante)
	return get_blind_amount(ante) * MP.BOUNTY.score_mult
end

-- Order matters: both games index this list with the same seeded number.
-- Append new goals at the end.
MP.BOUNTY.GOALS = {
	{
		key = "flush",
		check = function(ctx)
			return ctx.after and ctx.poker_hands and next(ctx.poker_hands["Flush"] or {})
		end,
	},
	{
		key = "straight",
		check = function(ctx)
			return ctx.after and ctx.poker_hands and next(ctx.poker_hands["Straight"] or {})
		end,
	},
	{
		key = "faces",
		vars = function() return { MP.BOUNTY.face_cards } end,
		check = function(ctx) return ctx.after and face_count(ctx.full_hand) >= MP.BOUNTY.face_cards end,
	},
	{
		key = "big_hand",
		vars = function(ante) return { number_format(MP.BOUNTY.score_target(ante)) } end,
		check = function(ctx, ante)
			return ctx.after and to_big(hand_score()) >= to_big(MP.BOUNTY.score_target(ante))
		end,
	},
	{
		key = "discard",
		vars = function() return { MP.BOUNTY.discard_cards } end,
		check = function(ctx)
			return ctx.pre_discard and #(ctx.full_hand or {}) >= MP.BOUNTY.discard_cards
		end,
	},
	{
		key = "tarot",
		check = function(ctx)
			return ctx.using_consumeable and ctx.consumeable and ctx.consumeable.ability.set == "Tarot"
		end,
	},
	{
		key = "buy_joker",
		check = function(ctx) return ctx.buying_card and ctx.card and ctx.card.ability.set == "Joker" end,
	},
}

-- Stateless: hashing a new key with the ante and seed, then seeding pseudorandom
-- with that number, gives the same result every call and never advances any of
-- the game's own RNG queues. With "different seeds" the two runs have different
-- seeds, so the lobby code (same on both games) is used instead.
function MP.BOUNTY.goal_for_ante(ante)
	local base = MP.LOBBY.config.different_seeds and MP.LOBBY.code or G.GAME.pseudorandom.seed
	local seed = pseudohash("mp_duel_bounty_ante_" .. ante .. tostring(base))
	return MP.BOUNTY.GOALS[pseudorandom(seed, 1, #MP.BOUNTY.GOALS)]
end

function MP.BOUNTY.goal_text(ante)
	local goal = MP.BOUNTY.goal_for_ante(ante)
	return localize({
		type = "variable",
		key = "k_mp_bounty_goal_" .. goal.key,
		vars = goal.vars and goal.vars(ante) or {},
	})
end

local function state()
	MP.GAME.duel_bounty = MP.GAME.duel_bounty or { winners = {}, paid = {}, pending = {} }
	return MP.GAME.duel_bounty
end

local function my_role() return MP.LOBBY.is_host and "host" or "guest" end

local function in_run() return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD end

function MP.BOUNTY.is_active()
	return MP.LOBBY.code and in_run() and MP.is_layer_active("duel") and true or false
end

function MP.BOUNTY.current_ante()
	local ante = G.GAME.round_resets.ante
	if ante < MP.BOUNTY.first_ante then return nil end
	return ante
end

-- "open", "pending" (guest is waiting for the host's answer), "mine" or "nemesis"
function MP.BOUNTY.status(ante)
	local s = state()
	local winner = s.winners[ante]
	if winner then return winner == my_role() and "mine" or "nemesis" end
	if s.pending[ante] then return "pending" end
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

-- Records the winner once and pays / notifies locally. Later calls for the same
-- ante do nothing, so a result or claim that arrives twice cannot pay twice.
local function record_winner(ante, winner)
	local s = state()
	s.pending[ante] = nil
	if s.winners[ante] then return end
	s.winners[ante] = winner
	if not in_run() then return end
	if winner == my_role() then
		if not s.paid[ante] then
			s.paid[ante] = true
			ease_dollars(MP.BOUNTY.reward)
			show_text(localize({ type = "variable", key = "k_mp_bounty_won", vars = { MP.BOUNTY.reward } }), G.C.MONEY)
			play_sound("coin1")
		end
	else
		show_text(localize({ type = "variable", key = "k_mp_bounty_lost", vars = {} }), G.C.RED)
	end
end

local function send_claim(ante)
	state().pending[ante] = love.timer.getTime()
	MP.ACTIONS.modded(MP.id, "bounty_claim", { ante = ante })
end

-- Called when this player completes the current ante's goal.
local function on_goal_completed(ante)
	if MP.BOUNTY.status(ante) ~= "open" then return end
	if MP.LOBBY.is_host then
		record_winner(ante, "host")
		MP.ACTIONS.modded(MP.id, "bounty_result", { ante = ante, winner = "host" })
	else
		send_claim(ante)
	end
end

local function valid_ante(a)
	a = tonumber(a)
	if not a or a ~= math.floor(a) or a < 1 or a > 1000 then return nil end
	return a
end

-- Runs on the host's game.
MP.register_mod_action("bounty_claim", function(p)
	if not MP.LOBBY.is_host or not MP.BOUNTY.is_active() then return end
	local ante = valid_ante(p.ante)
	if not ante then return end
	record_winner(ante, "guest") -- no-op if someone already has it
	MP.ACTIONS.modded(MP.id, "bounty_result", { ante = ante, winner = state().winners[ante] })
end, MP.id)

-- Runs on the guest's game.
MP.register_mod_action("bounty_result", function(p)
	if MP.LOBBY.is_host or not MP.BOUNTY.is_active() then return end
	local ante = valid_ante(p.ante)
	if not ante or (p.winner ~= "host" and p.winner ~= "guest") then return end
	record_winner(ante, p.winner)
end, MP.id)

local calculate_context_ref = SMODS.calculate_context
function SMODS.calculate_context(context, return_table, no_resolve)
	if
		type(context) == "table"
		and (context.after or context.pre_discard or context.using_consumeable or context.buying_card)
		and MP.BOUNTY.is_active()
	then
		local ante = MP.BOUNTY.current_ante()
		if ante and MP.BOUNTY.status(ante) == "open" and MP.BOUNTY.goal_for_ante(ante).check(context, ante) then
			on_goal_completed(ante)
		end
	end
	return calculate_context_ref(context, return_table, no_resolve)
end

-- Guest: resend unanswered claims. The host answers repeats with the same winner.
local bounty_update_ref = Game.update
function Game:update(dt)
	if MP.LOBBY.code and not MP.LOBBY.is_host and MP.GAME.duel_bounty and nemesis_present() then
		local now = love.timer.getTime()
		for ante, sent_at in pairs(MP.GAME.duel_bounty.pending) do
			if now - sent_at >= MP.BOUNTY.claim_retry_seconds then send_claim(ante) end
		end
	end
	return bounty_update_ref(self, dt)
end
