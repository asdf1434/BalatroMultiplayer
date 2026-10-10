-- Pickpocket: take a random consumable from the Nemesis. It keeps its edition
-- (a Negative card brings its extra slot with it).
--
-- Request / reply exchange (same shape as Joker Swap):
--   1. user's game sends "pickpocket_request"
--   2. Nemesis' game picks a random card from its consumable area, removes it
--      and replies "pickpocket_reply" with the card's full state
--   3. user's game adds the card to its consumable area
-- If the Nemesis has nothing to take (or is not in a run), the reply says why,
-- nothing moves, and the user gets the Pickpocket back.
--
-- Room: using Pickpocket frees its own slot. The stolen card is added even if
-- the user filled that slot again before the reply arrived; they are then over
-- the limit and cannot add more until they are back under it, as in vanilla.
--
-- A card that is being used has already left the consumable area (vanilla
-- G.FUNCS.use_card), so a Pickpocket that is being used can never be taken.
-- Card state travels as JSON text built by lib/card_transfer.lua.

local CT = MP.CARD_TRANSFER

-- Requests this game sent and is still waiting on, keyed by id, so a reply
-- from an earlier run is ignored.
local pending_requests = {}
local next_request_id = 1

local function nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

local function in_run()
	return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD and G.consumeables
end

local function text(key, vars)
	return localize({ type = "variable", key = key, vars = vars or {} })
end

local function show_pickpocket_text(str)
	G.FUNCS.attention_text_realtime({
		text = str,
		scale = 0.8,
		hold = 2,
		align = "cm",
		major = G.play,
		backdrop_colour = G.C.SECONDARY_SET.Attack or G.C.RED,
	})
	play_sound("card1")
end

local function card_name(card)
	return localize({ type = "name_text", set = card.ability.set, key = card.config.center.key })
end

local function refund()
	SMODS.add_card({ key = "c_mp_pickpocket", area = G.consumeables })
end

-- Picks the card to give away. Uses its own seed key (different per player) so
-- no other random queue moves.
local function pick_card_to_give()
	local eligible = {}
	for _, card in ipairs(G.consumeables.cards) do
		if not card.removed and not card.getting_sliced then eligible[#eligible + 1] = card end
	end
	if #eligible == 0 then return nil end
	return pseudorandom_element(eligible, pseudoseed(MP.UTILS.player_seed_key("mp_pickpocket")))
end

-- Step 2, Nemesis' game. Replies with result "ok" plus the card, or a failure
-- reason: "not_in_run", "empty", "bad_card".
local function answer_pickpocket(p)
	local function reply(result, card_text)
		MP.ACTIONS.modded(MP.id, "pickpocket_reply", { request_id = p.request_id, result = result, card = card_text })
	end
	if not in_run() then return reply("not_in_run") end
	local given = pick_card_to_give()
	if not given then return reply("empty") end
	local given_text = CT.serialize(given)
	if not given_text then return reply("bad_card") end

	local name = card_name(given)
	-- Not a sale and not a use: no sell or use effects trigger.
	G.consumeables:remove_from_highlighted(given)
	given:remove_from_deck()
	given:start_dissolve({ G.C.RED }, nil, 1.6)
	if given.area then given.area:remove_card(given) end
	show_pickpocket_text(text("k_mp_pickpocketed_by_nemesis", { name }))
	reply("ok", given_text)
end

local FAILURE_TEXT = {
	not_in_run = "k_mp_pickpocket_not_in_run",
	empty = "k_mp_pickpocket_empty",
	bad_card = "k_mp_pickpocket_failed",
}

-- Step 3, user's game.
local function finish_pickpocket(p)
	local id = tonumber(p.request_id)
	local game = id and pending_requests[id]
	if not game then return end
	pending_requests[id] = nil
	if game ~= G.GAME or not in_run() then return end

	if p.result ~= "ok" then
		show_pickpocket_text(text(FAILURE_TEXT[p.result] or "k_mp_pickpocket_failed"))
		refund()
		return
	end

	local data = CT.decode(p.card, "consumable")
	local received = data and CT.build(data, G.consumeables)
	if not received then
		-- The Nemesis already gave the card up. Only possible with mismatched
		-- mod versions.
		show_pickpocket_text(text("k_mp_pickpocket_failed"))
		return
	end
	received:add_to_deck()
	G.consumeables:emplace(received)
	received:start_materialize()
	-- Holding a card keeps its duplicates out of the shop, as in vanilla.
	G.GAME.used_jokers[received.config.center.key] = true
	show_pickpocket_text(text("k_mp_pickpocketed_nemesis", { card_name(received) }))
end

-- Both handlers run in a queued event so a card never moves in the middle of
-- another card's use.
MP.register_mod_action("pickpocket_request", function(p)
	G.E_MANAGER:add_event(Event({
		func = function()
			answer_pickpocket(p)
			return true
		end,
	}))
end, MP.id)

MP.register_mod_action("pickpocket_reply", function(p)
	G.E_MANAGER:add_event(Event({
		func = function()
			finish_pickpocket(p)
			return true
		end,
	}))
end, MP.id)

SMODS.Consumable({
	key = "pickpocket",
	set = "Attack",
	-- Placeholder art: The Magician's sprite from the default (vanilla Tarot) atlas
	pos = { x = 1, y = 0 },
	cost = 4,
	unlocked = true,
	discovered = true,
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = {} }
	end,
	can_use = function(self, card)
		return in_run() and nemesis_present()
	end,
	use = function(self, card, area, copier)
		local id = next_request_id
		next_request_id = next_request_id + 1
		pending_requests[id] = G.GAME
		MP.ACTIONS.modded(MP.id, "pickpocket_request", { request_id = id })
	end,
})
