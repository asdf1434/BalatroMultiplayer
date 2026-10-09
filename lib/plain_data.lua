-- Convert plain Lua data to and from a shape that the JSON library (rxi json.lua)
-- can always encode, so game state can be sent over the network as JSON instead
-- of through STR_PACK / STR_UNPACK (which run received text as code).
--
-- rxi json rejects tables with mixed or non-string keys, sparse arrays and
-- non-finite numbers. The "plain" shape avoids all of these:
--   * every table becomes an object whose keys carry their Lua type:
--     "s:name" for a string key, "n:3" for a number key, "b:true" for a boolean key
--   * a non-finite number becomes { ["$num"] = "inf" | "-inf" | "nan" }
--   * strings, booleans and finite numbers stay as they are
--   * functions, userdata and threads are dropped
-- Metatables are not kept. Cycles and nesting deeper than MAX_DEPTH are rejected.

MP.UTILS = MP.UTILS or {}

local MAX_DEPTH = 32
local NUMBER_TAG = "$num"

local function encode_number(n)
	if n ~= n then return { [NUMBER_TAG] = "nan" } end
	if n == math.huge then return { [NUMBER_TAG] = "inf" } end
	if n == -math.huge then return { [NUMBER_TAG] = "-inf" } end
	return n
end

local function encode_key(k)
	local t = type(k)
	if t == "string" then return "s:" .. k end
	if t == "number" and k == k and k ~= math.huge and k ~= -math.huge then
		return "n:" .. string.format("%.17g", k)
	end
	if t == "boolean" then return "b:" .. tostring(k) end
	return nil -- table / function / non-finite keys are dropped
end

local function to_plain(value, depth, seen)
	local t = type(value)
	if t == "string" or t == "boolean" then return value end
	if t == "number" then return encode_number(value) end
	if t ~= "table" then return nil end
	if depth > MAX_DEPTH then error("plain data: nesting too deep") end
	if seen[value] then error("plain data: table cycle") end
	seen[value] = true
	local out = {}
	for k, v in pairs(value) do
		local key = encode_key(k)
		local plain = key and to_plain(v, depth + 1, seen)
		if plain ~= nil then out[key] = plain end
	end
	seen[value] = nil
	return out
end

local function decode_key(k)
	if type(k) ~= "string" then return nil end
	local prefix, rest = k:sub(1, 2), k:sub(3)
	if prefix == "s:" then return rest end
	if prefix == "n:" then return tonumber(rest) end
	if prefix == "b:" then
		if rest == "true" then return true end
		if rest == "false" then return false end
	end
	return nil
end

local special_numbers = { nan = 0 / 0, inf = math.huge, ["-inf"] = -math.huge }

local function from_plain(value, depth)
	local t = type(value)
	if t == "string" or t == "boolean" or t == "number" then return value end
	if t ~= "table" then error("plain data: unexpected " .. t) end
	if depth > MAX_DEPTH then error("plain data: nesting too deep") end
	local tag = value[NUMBER_TAG]
	if tag ~= nil then
		local n = special_numbers[tag]
		if n == nil then error("plain data: bad number tag") end
		return n
	end
	local out = {}
	for k, v in pairs(value) do
		local key = decode_key(k)
		if key == nil then error("plain data: bad key " .. tostring(k)) end
		out[key] = from_plain(v, depth + 1)
	end
	return out
end

-- Returns the plain copy, or nil and an error message.
function MP.UTILS.to_plain_data(value)
	local ok, result = pcall(to_plain, value, 1, {})
	if not ok then return nil, result end
	return result
end

-- Returns the Lua value, or nil and an error message. Never runs received text.
function MP.UTILS.from_plain_data(value)
	local ok, result = pcall(from_plain, value, 1)
	if not ok then return nil, result end
	return result
end
