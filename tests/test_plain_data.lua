--[[
  Plain data converter test (lib/plain_data.lua).

  Joker Swap sends a Joker's Card:save() table as JSON. The converter must turn
  any such table into a shape rxi json.lua accepts (only string keys, finite
  numbers) and back without loss, and must reject malformed received data
  instead of erroring.

  Run from the repo root:
    lua tests/test_plain_data.lua
  To also round-trip through the real JSON library, point LUA_PATH at it, e.g.
    LUA_PATH="$HOME/Library/Application Support/Balatro/Mods/smods/libs/json/?.lua;;" lua tests/test_plain_data.lua
]]

MP = { UTILS = {} }
dofile("lib/plain_data.lua")

local failures = 0
local function check(cond, name)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local function deep_equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "number" and a ~= a then return b ~= b end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not deep_equal(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

-- Every table key is a string and every number is finite: what rxi json needs.
local function json_safe(v)
	if type(v) == "number" then return v == v and v ~= math.huge and v ~= -math.huge end
	if type(v) ~= "table" then return true end
	for k, x in pairs(v) do
		if type(k) ~= "string" or not json_safe(x) then return false end
	end
	return true
end

-- Shaped like Card:save() for a Negative, Eternal Hologram with progress.
local saved = {
	save_fields = { center = "j_hologram" },
	params = { bypass_discovery_center = true },
	base_cost = 7,
	extra_cost = 0,
	cost = 7,
	sell_cost = 3,
	facing = "front",
	ability = {
		name = "Hologram",
		set = "Joker",
		x_mult = 2.75,
		extra = 0.25,
		eternal = true,
		card_limit = 1,
		extra_slots_used = 0,
		debuff_sources = {},
		hands = { 1, 2, 3 },
		sparse = { [1] = "a", [3] = "c" },
		mixed = { "first", key = "value" },
		big = math.huge,
		small = -math.huge,
		[5] = "number key",
		[true] = "bool key",
	},
	edition = { negative = true, type = "negative", card_limit = 1 },
	ignore_base_shader = {},
	ignore_shadow = {},
}

local plain = MP.UTILS.to_plain_data(saved)
check(plain ~= nil, "encodes a Card:save()-shaped table")
check(json_safe(plain), "encoded data has only string keys and finite numbers")
check(deep_equal(MP.UTILS.from_plain_data(plain), saved), "decodes back to the same table")

local nan_back = MP.UTILS.from_plain_data(MP.UTILS.to_plain_data({ x = 0 / 0 }))
check(nan_back and nan_back.x ~= nan_back.x, "NaN survives the round trip")

local dropped = MP.UTILS.from_plain_data(MP.UTILS.to_plain_data({ f = print, keep = 1 }))
check(dropped and dropped.f == nil and dropped.keep == 1, "functions are dropped")

local cycle = {}
cycle.self = cycle
local c_plain, c_err = MP.UTILS.to_plain_data(cycle)
check(c_plain == nil and c_err ~= nil, "cycles are rejected")

local deep = {}
local cur = deep
for _ = 1, 40 do
	cur.next = {}
	cur = cur.next
end
check(MP.UTILS.to_plain_data(deep) == nil, "very deep nesting is rejected")

-- Malformed received data: must return nil, never error.
check(MP.UTILS.from_plain_data({ ["x:bad"] = 1 }) == nil, "unknown key prefix is rejected")
check(MP.UTILS.from_plain_data({ ["s:a"] = { ["$num"] = "big" } }) == nil, "unknown number tag is rejected")
check(MP.UTILS.from_plain_data({ ["n:abc"] = 1 }) == nil, "non-numeric number key is rejected")
check(MP.UTILS.from_plain_data(print) == nil, "non-data value is rejected")

local has_json, json = pcall(require, "json")
if has_json then
	local text = json.encode(plain)
	check(deep_equal(MP.UTILS.from_plain_data(json.decode(text)), saved), "round-trips through json.lua")
else
	print("skip json.lua round trip (json module not on LUA_PATH)")
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("all passed")
