-- Duel Attacks panel: up to three short lines in the left HUD, under the
-- Hands/Discards, money and Ante boxes.
--   Incoming: attacks waiting for this player's next blind or next shop (and
--             Cripples waiting for their next PvP blind)
--   Active:   attacks affecting the current blind or shop
--   Sent:     this player's attacks still waiting on the Nemesis
-- Each line is shown only when it has something; with all three empty the
-- panel is hidden. Hovering the panel shows every attack's full effect.
-- Data comes from objects/consumables/_next_blind_attacks.lua (MP.NEXT_BLIND_ATTACKS)
-- and objects/consumables/cripple.lua (MP.CRIPPLE).
--
-- Placement: in a lobby the button column (Run Info, Options, Lobby Info) is
-- taller than the round column next to it, so the round column has spare room
-- under the Ante box. In Duel the HUD gets an empty slot there
-- ("mp_attacks_slot"), and the panel is drawn over that slot, so it covers
-- nothing and nothing moves when it appears.

local SLOT_W = 3.03 -- width of the round column: two 1.45 boxes and the 0.13 gap
local SLOT_H = 0.8
local SCALE = 0.26
local LABEL_W = 0.85

local SECTIONS = {
	{ id = "incoming", label = "k_mp_attacks_incoming", tip = "k_mp_attacks_tip_incoming", colour = G.C.RED, tip_colour = "red" },
	{ id = "active", label = "k_mp_attacks_active", tip = "k_mp_attacks_tip_active", colour = G.C.FILTER, tip_colour = "attention" },
	{ id = "sent", label = "k_mp_attacks_sent", tip = "k_mp_attacks_tip_sent", colour = G.C.GREEN, tip_colour = "green" },
}

local function text(key, vars)
	return localize({ type = "variable", key = key, vars = vars or {} })
end

local function panel_enabled()
	return MP.LOBBY.code and MP.is_layer_active("duel")
end

-- Reserve the slot in the round column of the left HUD (Duel only).
local function find_node(node, id)
	if type(node) ~= "table" then return nil end
	if node.config and node.config.id == id then return node end
	for _, child in ipairs(node.nodes or {}) do
		local found = find_node(child, id)
		if found then return found end
	end
end

local create_UIBox_HUD_ref = create_UIBox_HUD
function create_UIBox_HUD()
	local definition = create_UIBox_HUD_ref()
	if not panel_enabled() then return definition end
	local row_round = find_node(definition, "row_round")
	local round_column = row_round and row_round.nodes and row_round.nodes[2]
	if not (round_column and round_column.nodes) then return definition end
	table.insert(round_column.nodes, { n = G.UIT.R, config = { minh = 0.08 }, nodes = {} })
	table.insert(round_column.nodes, {
		n = G.UIT.R,
		config = { id = "mp_attacks_slot", align = "cm", minw = SLOT_W, minh = SLOT_H },
		nodes = {},
	})
	return definition
end

-- One item per attack copy:
--   group  what copies are grouped by
--   name   short name, short  short data or nil
--   tip    full line for the tooltip
local function nba_item(entry, with_chance)
	local NBA = MP.NEXT_BLIND_ATTACKS
	local tip
	if with_chance then
		tip = text("k_mp_attacks_tip_chance", { NBA.name(entry.key), NBA.effect(entry), NBA.chance_percent(entry.key) })
	else
		tip = text("k_mp_attacks_tip_line", { NBA.name(entry.key), NBA.effect(entry) })
	end
	return { group = entry.key, name = NBA.short_name(entry.key), short = NBA.short(entry), tip = tip }
end

local function cripple_item(joker_key, effect_key)
	local joker = MP.CRIPPLE.joker_name(joker_key)
	local name = localize({ type = "name_text", set = "Attack", key = "c_mp_cripple" })
	return {
		group = "c_mp_cripple",
		name = name,
		short = joker,
		tip = text("k_mp_attacks_tip_line", { name, text(effect_key, { joker }) }),
	}
end

local function collect()
	local items = { incoming = {}, active = {}, sent = {} }
	local NBA = MP.NEXT_BLIND_ATTACKS
	local state = NBA and G.GAME.mp_next_blind
	if state then
		for _, entry in ipairs(state.pending) do
			table.insert(items.incoming, nba_item(entry, true))
		end
		for _, entry in ipairs(state.active_entries or {}) do
			table.insert(items.active, nba_item(entry, false))
		end
		for _, entry in ipairs(state.sent or {}) do
			table.insert(items.sent, nba_item(entry, true))
		end
	end
	if MP.CRIPPLE then
		for _, joker in ipairs(G.jokers and G.jokers.cards or {}) do
			if joker.ability.mp_cripple_active then
				table.insert(items.active, cripple_item(joker.config.center.key, "k_mp_cripple_effect_active"))
			elseif joker.ability[MP.CRIPPLE.sticker] then
				table.insert(items.incoming, cripple_item(joker.config.center.key, "k_mp_cripple_effect_incoming"))
			end
		end
		for _, joker_key in ipairs(G.GAME.mp_cripple_sent or {}) do
			table.insert(items.sent, cripple_item(joker_key, "k_mp_cripple_effect_sent"))
		end
	end
	return items
end

-- "Shrink x2, Debuff Spades/Hearts, Inflation +20%"
local function compact_line(items)
	local groups, by_id = {}, {}
	for _, item in ipairs(items) do
		local group = by_id[item.group]
		if not group then
			group = { name = item.name, count = 0, shorts = {} }
			by_id[item.group] = group
			groups[#groups + 1] = group
		end
		group.count = group.count + 1
		if item.short then group.shorts[#group.shorts + 1] = item.short end
	end
	local parts = {}
	for i, group in ipairs(groups) do
		if #group.shorts > 0 then
			parts[i] = text("k_mp_attacks_group_detail", { group.name, table.concat(group.shorts, "/") })
		elseif group.count > 1 then
			parts[i] = text("k_mp_attacks_group_count", { group.name, group.count })
		else
			parts[i] = group.name
		end
	end
	return table.concat(parts, ", ")
end

function MP.UI.attacks_panel_definition(lines, tooltip_lines)
	local rows = {}
	for _, line in ipairs(lines) do
		rows[#rows + 1] = {
			n = G.UIT.R,
			config = { align = "cl", padding = 0.01 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cl", minw = LABEL_W },
					nodes = {
						{ n = G.UIT.T, config = { text = line.label, scale = SCALE, colour = line.colour, shadow = true } },
					},
				},
				{
					n = G.UIT.T,
					config = {
						text = line.body,
						scale = SCALE,
						colour = G.C.UI.TEXT_LIGHT,
						shadow = true,
						maxw = SLOT_W - LABEL_W - 0.15,
					},
				},
			},
		}
	end
	return {
		n = G.UIT.ROOT,
		config = { align = "cm", colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.C,
				config = {
					align = "cm",
					padding = 0.04,
					minw = SLOT_W,
					r = 0.1,
					colour = G.C.DYN_UI.BOSS_MAIN,
					emboss = 0.05,
					tooltip = { text = tooltip_lines },
				},
				nodes = rows,
			},
		},
	}
end

local shown_key, shown_slot = nil, nil
local slot_hud, slot = nil, nil

local function remove_panel()
	if G.HUD_mp_attacks then G.HUD_mp_attacks:remove() end
	G.HUD_mp_attacks = nil
	shown_key, shown_slot = nil, nil
end

-- The slot element, looked up again only when the HUD is rebuilt.
local function current_slot()
	if not G.HUD or G.HUD.REMOVED then return nil end
	if G.HUD ~= slot_hud then
		slot_hud = G.HUD
		slot = G.HUD:get_UIE_by_ID("mp_attacks_slot")
	end
	return slot
end

local attacks_hud_update_ref = Game.update
function Game:update(dt)
	local target = G.STAGE == G.STAGES.RUN and G.GAME and current_slot()
	local lines, tooltip_lines = {}, {}
	if target then
		local items = collect()
		for _, section in ipairs(SECTIONS) do
			local list = items[section.id]
			if #list > 0 then
				lines[#lines + 1] = { label = text(section.label), body = compact_line(list), colour = section.colour }
				tooltip_lines[#tooltip_lines + 1] = "{C:" .. section.tip_colour .. "}" .. text(section.tip) .. "{}"
				for _, item in ipairs(list) do
					tooltip_lines[#tooltip_lines + 1] = item.tip
				end
			end
		end
	end
	if #lines > 0 then
		local parts = {}
		for i, line in ipairs(lines) do
			parts[i] = line.label .. line.body
		end
		local key = table.concat(parts, "\n") .. "\n" .. table.concat(tooltip_lines, "\n")
		if key ~= shown_key or target ~= shown_slot or not G.HUD_mp_attacks or G.HUD_mp_attacks.REMOVED then
			remove_panel()
			G.HUD_mp_attacks = UIBox({
				definition = MP.UI.attacks_panel_definition(lines, tooltip_lines),
				config = { major = target, align = "cm", offset = { x = 0, y = 0 } },
			})
			shown_key, shown_slot = key, target
		end
	elseif G.HUD_mp_attacks then
		remove_panel()
	end
	return attacks_hud_update_ref(self, dt)
end
