-- Tax Collector: take up to $N from the Nemesis. Only the Nemesis' game knows
-- their money, so this is a two-step exchange:
--   1. user's game sends "tax_request" with the amount
--   2. Nemesis' game removes min(amount, max(0, dollars)) and replies with
--      "tax_reply" carrying what was actually taken
--   3. user's game adds that amount
-- There is no timeout: a reply is honoured whenever it arrives, so whatever the
-- Nemesis loses the user gains. If no reply ever comes (the Nemesis disconnected
-- before the request reached them), nothing was taken and the card is spent.

local function nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

local function in_run()
	return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD
end

local function show_tax_text(text)
	G.FUNCS.attention_text_realtime({
		text = text,
		scale = 0.8,
		hold = 2,
		align = "cm",
		major = G.play,
		backdrop_colour = G.C.MONEY,
	})
	play_sound("coin1")
end

-- Runs on the Nemesis' game.
MP.register_mod_action("tax_request", function(p)
	local taken = 0
	if in_run() then
		local dollars = G.GAME.dollars
		if to_number then dollars = to_number(dollars) end
		taken = math.min(tonumber(p.amount) or 0, math.max(0, math.floor(dollars)))
		-- instant so a second request in the same frame sees the updated total
		if taken > 0 then ease_dollars(-taken, true) end
		show_tax_text(localize({ type = "variable", key = "k_mp_taxed_by_nemesis", vars = { taken } }))
	end
	MP.ACTIONS.modded(MP.id, "tax_reply", { amount = taken })
end, MP.id)

-- Runs on the user's game.
MP.register_mod_action("tax_reply", function(p)
	if not in_run() then return end
	local amount = tonumber(p.amount) or 0
	if amount > 0 then ease_dollars(amount, true) end
	show_tax_text(localize({ type = "variable", key = "k_mp_taxed_nemesis", vars = { amount } }))
end, MP.id)

SMODS.Consumable({
	key = "tax_collector",
	set = "Attack",
	-- Placeholder art: The Hermit's sprite from the default (vanilla Tarot) atlas
	pos = { x = 9, y = 0 },
	cost = 4,
	unlocked = true,
	discovered = true,
	config = { extra = { dollars = 10 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = { card.ability.extra.dollars } }
	end,
	can_use = function(self, card)
		return nemesis_present()
	end,
	use = function(self, card, area, copier)
		MP.ACTIONS.modded(MP.id, "tax_request", { amount = card.ability.extra.dollars })
	end,
})
