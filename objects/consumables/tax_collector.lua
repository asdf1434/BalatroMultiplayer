-- Tax Collector: take a random 10-40% of the Nemesis' money (rounded down, no
-- minimum, no cap). Only the Nemesis' game knows their money, so this is a
-- two-step exchange:
--   1. user's game sends "tax_request" (no fields)
--   2. Nemesis' game rolls the percentage from its own copy of the card config,
--      removes floor(dollars * percent / 100) (0 if dollars <= 0) and replies
--      with "tax_reply" carrying the percentage and what was actually taken
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

-- Runs on the Nemesis' game. The range comes from this game's own card config,
-- not from the message, so a request can never ask for more than the card allows.
MP.register_mod_action("tax_request", function(p)
	local taken = 0
	local percent = 0
	if in_run() then
		local extra = G.P_CENTERS.c_mp_tax_collector.config.extra
		percent = pseudorandom("mp_tax_collector", extra.min_percent, extra.max_percent)
		local dollars = G.GAME.dollars
		if to_number then dollars = to_number(dollars) end
		taken = math.max(0, math.floor(dollars * percent / 100))
		-- instant so a second request in the same frame sees the updated total
		if taken > 0 then
			ease_dollars(-taken, true)
			-- A tax is not spending. The ease_dollars patch in lovely/game.toml counts
			-- every loss into spent_total (which feeds spent_last_shop / Penny Pincher),
			-- so take it back out. Safe right here because the ease above is instant.
			MP.GAME.spent_total = to_big(MP.GAME.spent_total) - to_big(taken)
		end
		show_tax_text(localize({ type = "variable", key = "k_mp_taxed_by_nemesis", vars = { percent, taken } }))
	end
	MP.ACTIONS.modded(MP.id, "tax_reply", { percent = percent, amount = taken })
end, MP.id)

-- Runs on the user's game.
MP.register_mod_action("tax_reply", function(p)
	if not in_run() then return end
	local percent = tonumber(p.percent) or 0
	local amount = tonumber(p.amount) or 0
	if amount > 0 then ease_dollars(amount, true) end
	show_tax_text(localize({ type = "variable", key = "k_mp_taxed_nemesis", vars = { percent, amount } }))
end, MP.id)

SMODS.Consumable({
	key = "tax_collector",
	set = "Attack",
	-- Placeholder art: The Hermit's sprite from the default (vanilla Tarot) atlas
	pos = { x = 9, y = 0 },
	cost = 4,
	unlocked = true,
	discovered = true,
	config = { extra = { min_percent = 10, max_percent = 40 } },
	loc_vars = function(self, info_queue, card)
		MP.UTILS.add_nemesis_info(info_queue)
		return { vars = { card.ability.extra.min_percent, card.ability.extra.max_percent } }
	end,
	can_use = function(self, card)
		return nemesis_present()
	end,
	use = function(self, card, area, copier)
		MP.ACTIONS.modded(MP.id, "tax_request", {})
	end,
})
