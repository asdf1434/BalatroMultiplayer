-- Small panel under the consumable slots that lists the "next blind" attacks
-- waiting to hit this player (see objects/consumables/_next_blind_attacks.lua).
-- Shown only while the list is not empty. Rebuilt only when the list changes.

local function text_row(text, scale, colour)
	return {
		n = G.UIT.R,
		config = { align = "cm" },
		nodes = {
			{ n = G.UIT.T, config = { text = text, scale = scale, colour = colour, shadow = true, maxw = 3.2 } },
		},
	}
end

function MP.UI.incoming_attacks_definition(lines)
	local rows = { text_row(localize("k_mp_nba_incoming"), 0.32, G.C.RED) }
	for _, line in ipairs(lines) do
		rows[#rows + 1] = text_row(line, 0.3, G.C.UI.TEXT_LIGHT)
	end
	return {
		n = G.UIT.ROOT,
		config = { align = "cm", colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cm", padding = 0.05, minw = 2.6, r = 0.1, colour = G.C.DYN_UI.BOSS_DARK, emboss = 0.05 },
				nodes = rows,
			},
		},
	}
end

local shown_key, shown_area = nil, nil

local function remove_panel()
	if G.HUD_mp_incoming_attacks then G.HUD_mp_incoming_attacks:remove() end
	G.HUD_mp_incoming_attacks = nil
	shown_key, shown_area = nil, nil
end

local incoming_hud_update_ref = Game.update
function Game:update(dt)
	local NBA = MP.NEXT_BLIND_ATTACKS
	local pending = NBA and G.STAGE == G.STAGES.RUN and G.consumeables and G.GAME and G.GAME.mp_next_blind
		and G.GAME.mp_next_blind.pending
	if pending and #pending > 0 then
		local lines = {}
		for i, entry in ipairs(pending) do
			lines[i] = NBA.describe(entry)
		end
		local key = table.concat(lines, "\n")
		-- G.consumeables is a new object each run, so a panel from the last run is replaced
		if
			key ~= shown_key
			or G.consumeables ~= shown_area
			or not G.HUD_mp_incoming_attacks
			or G.HUD_mp_incoming_attacks.REMOVED
		then
			remove_panel()
			G.HUD_mp_incoming_attacks = UIBox({
				definition = MP.UI.incoming_attacks_definition(lines),
				config = { major = G.consumeables, align = "bm", offset = { x = 0, y = 0.15 } },
			})
			shown_key, shown_area = key, G.consumeables
		end
	elseif G.HUD_mp_incoming_attacks then
		remove_panel()
	end
	return incoming_hud_update_ref(self, dt)
end
