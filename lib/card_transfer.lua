-- Send a card's full state from one game to the other: Joker Swap, Pickpocket
-- and Hijack use this.
--
-- The state is Balatro's own save data (Card:save / Card:load, as used when a
-- run is saved). It travels as a JSON string built by MP.UTILS.to_plain_data
-- (lib/plain_data.lua). Received text is only ever JSON-decoded, never run, and
-- is checked before a card is built from it.
--
--   MP.CARD_TRANSFER.serialize(card)        -> JSON text, or nil
--   MP.CARD_TRANSFER.decode(text, kind)     -> save data, or nil
--       kind = "joker" or "consumable": what the card must be
--   MP.CARD_TRANSFER.build(data, area)      -> Card (not added to any area), or nil
--   MP.CARD_TRANSFER.discard(card)          throw away a built card that was never added

local json = require("json")

MP.CARD_TRANSFER = MP.CARD_TRANSFER or {}
local CT = MP.CARD_TRANSFER

-- Fields of Card:save() that describe this game's copy of the card (position,
-- selection, hooks already run, IDs) rather than the card itself.
local LOCAL_ONLY_FIELDS = {
	"sort_id",
	"highlighted",
	"added_to_deck",
	"joker_added_to_deck_but_debuffed",
	"debuff",
	"rank",
	"pinned",
	"unique_val",
	"unique_val__saved_ID",
	"playing_card",
	"shop_voucher",
}

-- Returns a JSON string with the card's full save data, or nil.
function CT.serialize(card)
	local saved = {}
	for k, v in pairs(card:save()) do
		saved[k] = v
	end
	for _, k in ipairs(LOCAL_ONLY_FIELDS) do
		saved[k] = nil
	end
	local plain = MP.UTILS.to_plain_data(saved)
	if not plain then return nil end
	local ok, text = pcall(json.encode, plain)
	if ok then return text end
	return nil
end

local function optional_table(v)
	return v == nil or type(v) == "table"
end

local function is_kind(center, kind)
	if kind == "joker" then return center.set == "Joker" end
	if kind == "consumable" then return SMODS.ConsumableTypes[center.set] ~= nil end
	return false
end

-- Decodes and checks received card data. Returns the save table or nil.
-- Rejects anything this game cannot build: unknown card key, a card of the
-- wrong kind, unknown edition, wrong field types.
function CT.decode(text, kind)
	if type(text) ~= "string" then return nil end
	local ok, plain = pcall(json.decode, text)
	if not ok then return nil end
	local data = MP.UTILS.from_plain_data(plain)
	if type(data) ~= "table" or type(data.save_fields) ~= "table" then return nil end

	local center = G.P_CENTERS[data.save_fields.center]
	if type(data.save_fields.center) ~= "string" or not center or not is_kind(center, kind) then return nil end
	if type(data.ability) ~= "table" then return nil end
	if data.edition ~= nil then
		if type(data.edition) ~= "table" or type(data.edition.type) ~= "string" then return nil end
		if not G.P_CENTERS["e_" .. data.edition.type] or data.edition.type == "mp_phantom" then return nil end
	end
	if not (optional_table(data.params) and optional_table(data.base)) then return nil end
	if not (optional_table(data.ignore_base_shader) and optional_table(data.ignore_shadow)) then return nil end

	for _, k in ipairs(LOCAL_ONLY_FIELDS) do
		data[k] = nil
	end
	data.save_fields.card = nil
	data.params = data.params or {}
	data.facing = "front"
	data.sprite_facing = "front"
	-- Debuffs belong to the game the card left; this game recomputes its own.
	data.ability.debuff_sources = {}
	return data
end

-- Runs fn with a fake menu open. Card() and Card:remove skip their used_jokers
-- bookkeeping while a menu is open (same trick as the phantom code), so cards
-- that are only built to be loaded or thrown away do not change the shop pool.
local function without_pool_bookkeeping(fn, ...)
	local menu = G.OVERLAY_MENU
	G.OVERLAY_MENU = G.OVERLAY_MENU or true
	local ok, result = pcall(fn, ...)
	G.OVERLAY_MENU = menu
	return ok, result
end

function CT.discard(card)
	card.added_to_deck = nil
	card.states.visible = false
	without_pool_bookkeeping(card.remove, card)
end

-- Creates a Card from decoded save data, placed next to `area` but not added to
-- it. Returns the card or nil.
function CT.build(data, area)
	-- The temporary center is replaced by Card:load; without the fake menu,
	-- creating it would mark plain Joker as owned and hide it from the shop.
	local ok, card = without_pool_bookkeeping(function()
		return Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, G.P_CENTERS.j_joker, G.P_CENTERS.c_base)
	end)
	if not ok or not card then return nil end
	local sort_id = card.sort_id
	if not pcall(card.load, card, data) then
		CT.discard(card)
		return nil
	end
	-- Card:load copies sort_id from the save data; keep this game's fresh one.
	card.sort_id = sort_id
	card:set_cost()
	return card
end
