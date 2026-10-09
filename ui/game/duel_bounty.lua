-- Small panel above the deck that shows the current ante's Duel bounty and who
-- has it. Logic lives in overrides/duel_bounty.lua. The panel is rebuilt only
-- when the ante or the status changes.

local STATUS_COLOURS = {
	open = G.C.GREEN,
	pending = G.C.UI.TEXT_INACTIVE,
	mine = G.C.MONEY,
	nemesis = G.C.RED,
}

local function text_row(text, scale, colour)
	return {
		n = G.UIT.R,
		config = { align = "cm" },
		nodes = {
			{ n = G.UIT.T, config = { text = text, scale = scale, colour = colour, shadow = true, maxw = 2.4 } },
		},
	}
end

function MP.UI.duel_bounty_definition(ante, status)
	return {
		n = G.UIT.ROOT,
		config = { align = "cm", colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cm", padding = 0.05, minw = 2.6, r = 0.1, colour = G.C.DYN_UI.BOSS_DARK, emboss = 0.05 },
				nodes = {
					text_row(
						localize({ type = "variable", key = "k_mp_bounty_title", vars = { ante, MP.BOUNTY.reward } }),
						0.3,
						G.C.MONEY
					),
					text_row(MP.BOUNTY.goal_text(ante), 0.32, G.C.UI.TEXT_LIGHT),
					text_row(
						localize({ type = "variable", key = "k_mp_bounty_status_" .. status }),
						0.3,
						STATUS_COLOURS[status]
					),
				},
			},
		},
	}
end

local shown_key, shown_deck = nil, nil

local function remove_panel()
	if G.HUD_mp_bounty then G.HUD_mp_bounty:remove() end
	G.HUD_mp_bounty = nil
	shown_key, shown_deck = nil, nil
end

local bounty_hud_update_ref = Game.update
function Game:update(dt)
	local ante = MP.BOUNTY.is_active() and G.deck and MP.BOUNTY.current_ante()
	if ante then
		local status = MP.BOUNTY.status(ante)
		local key = ante .. ":" .. status
		-- G.deck is a new object each run, so a panel from the last run is replaced
		if key ~= shown_key or G.deck ~= shown_deck or not G.HUD_mp_bounty or G.HUD_mp_bounty.REMOVED then
			remove_panel()
			G.HUD_mp_bounty = UIBox({
				definition = MP.UI.duel_bounty_definition(ante, status),
				config = { major = G.deck, align = "tm", offset = { x = 0, y = -0.15 } },
			})
			shown_key, shown_deck = key, G.deck
		end
	elseif G.HUD_mp_bounty then
		remove_panel()
	end
	return bounty_hud_update_ref(self, dt)
end
