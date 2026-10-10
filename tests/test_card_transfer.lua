--[[
  Card transfer test (lib/card_transfer.lua).

  Joker Swap, Pickpocket and Hijack send a card's Card:save() table as JSON.
  serialize must drop this game's local fields, and decode must only accept a
  card of the expected kind ("joker" or "consumable") with a known edition.
  Card building needs the game, so it is not covered here.

  Needs the JSON library on LUA_PATH. Run from the repo root:
    LUA_PATH="$HOME/Library/Application Support/Balatro/Mods/smods/libs/json/?.lua;;" lua tests/test_card_transfer.lua
]]

local has_json = pcall(require, "json")
if not has_json then
	print("skip card transfer test (json module not on LUA_PATH)")
	return
end

MP = { UTILS = {} }
G = {
	P_CENTERS = {
		j_hologram = { set = "Joker" },
		c_fool = { set = "Tarot" },
		c_mp_pickpocket = { set = "Attack" },
		e_negative = {},
		e_mp_phantom = {},
	},
}
SMODS = { ConsumableTypes = { Tarot = {}, Attack = {} } }
dofile("lib/plain_data.lua")
dofile("lib/card_transfer.lua")
local CT = MP.CARD_TRANSFER

local failures = 0
local function check(cond, name)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local function fake_card(center, edition)
	return {
		save = function()
			return {
				save_fields = { center = center, card = "S_A" },
				ability = { set = G.P_CENTERS[center].set, card_limit = edition and 1 or 0, debuff_sources = { x = true } },
				edition = edition and { type = edition, negative = true } or nil,
				sort_id = 12,
				highlighted = true,
				added_to_deck = true,
				cost = 3,
			}
		end,
	}
end

local tarot = CT.serialize(fake_card("c_fool", "negative"))
check(type(tarot) == "string", "serialize returns text")
local data = CT.decode(tarot, "consumable")
check(data ~= nil, "a Tarot decodes as a consumable")
check(data and data.edition.type == "negative" and data.ability.card_limit == 1, "edition and its slot travel")
check(data and data.sort_id == nil and data.highlighted == nil and data.added_to_deck == nil, "local fields dropped")
check(data and data.save_fields.card == nil, "playing card field dropped")
check(data and next(data.ability.debuff_sources) == nil, "debuffs reset")
check(CT.decode(tarot, "joker") == nil, "a Tarot is not accepted as a Joker")

local attack = CT.serialize(fake_card("c_mp_pickpocket"))
check(CT.decode(attack, "consumable") ~= nil, "a modded consumable type decodes")

local joker = CT.serialize(fake_card("j_hologram"))
check(CT.decode(joker, "joker") ~= nil, "a Joker decodes as a Joker")
check(CT.decode(joker, "consumable") == nil, "a Joker is not accepted as a consumable")

check(CT.decode(CT.serialize(fake_card("j_hologram", "mp_phantom")), "joker") == nil, "phantom edition rejected")
G.P_CENTERS.j_gone = { set = "Joker" }
local unknown = CT.serialize(fake_card("j_gone"))
G.P_CENTERS.j_gone = nil
check(CT.decode(unknown, "joker") == nil, "unknown card rejected")
check(CT.decode("not json", "joker") == nil, "bad text rejected")
check(CT.decode(nil, "joker") == nil, "missing text rejected")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
