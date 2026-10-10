-- Shared helper for "next blind" Attack cards (Suit Debuff, Blind Inflation,
-- Shrink, Fog, ...). An attack is sent to the Nemesis, waits in their "pending"
-- list, rolls its chance at the start of the next blind they play, and if it
-- lands it is undone when that blind ends.
--
-- Message exchange (mod actions):
--   1. user's game sends "next_blind_attack" with the effect key (the card key)
--   2. Nemesis' game picks any random data (for example the suit), adds the
--      attack to its pending list and replies with "next_blind_attack_reply"
--      carrying that data, so the user sees what is on its way
--   3. at the start of the Nemesis' next blind, each pending copy rolls its
--      chance separately. The Nemesis sees which landed and which fizzled, and
--      their game sends one "next_blind_attack_result" per copy back to the user
--
-- State lives on the Nemesis' game in G.GAME.mp_next_blind, so a new run starts
-- with an empty list:
--   pending        = { { key = "c_mp_suit_debuff", suit = "Spades" }, ... }
--   active         = { [key] = state returned by the effect's apply() }
--   active_entries = the entries that landed on the current blind (for the
--                    Attacks panel, ui/game/duel_attacks_panel.lua)
-- and on the user's game:
--   sent = entries the Nemesis accepted ("pending" reply) whose result has not
--          arrived yet (for the Attacks panel)
--
-- Timing rules:
--   - Effects land in Blind:set_blind for a real new blind. An attack that
--     arrives during a blind waits for the blind after. A skipped blind never
--     calls set_blind, so nothing lands on it.
--   - An effect with skips_pvp = true stays pending (and does not roll) through
--     PvP blinds.
--   - end_round undoes everything that landed (hand size, debuffs, ...).
--
-- "Next shop" attacks (Price Hike, Shoplift) use the same list, limit, chance
-- roll, messages and refunds, but target the Nemesis' next shop instead:
--   - Effects land when a new shop is created (Game:update_shop, before the
--     shop's card areas exist and before they are filled). An attack that
--     arrives during a shop waits for the next one. Returning to the shop
--     from a Booster Pack is the same shop visit, so nothing lands there.
--   - Leaving the shop (G.FUNCS.toggle_shop) undoes them.
--   - Blinds do not land them, and shops do not land "next blind" attacks.
--
-- Each card registers its effect with MP.NEXT_BLIND_ATTACKS.register(key, def):
--   target     "blind" | "shop"       optional, default "blind"; what the
--                                     attack lands on
--   skips_pvp  (bool)                 never land on a PvP blind
--   on_receive (entry, pending)       optional; add random data to the entry
--   detail     (entry) -> string|nil  optional; extra text for messages (for
--                                     example the suit)
--   short_name string                 optional; localization key of a short
--                                     name for the Attacks panel
--   short      (entry) -> string|nil  optional; short data for the Attacks
--                                     panel (for example "Spades" or "+20%")
--   effect     (entry) -> string      full effect text for the panel's tooltip
--   apply      (entries) -> state     the copies of this effect that landed, in
--                                     arrival order; returns what undo needs
--   undo       (state, leaving)       restore the game; leaving = true when the
--                                     run continues without the lobby
-- Tunable numbers live in the card's config.extra. Every effect has a chance
-- (config.extra.chance, 1 = always) rolled in roll_lands() below.
--
-- Limit: at most NBA.max_pending attacks (any mix of cards) can be waiting on
-- the Nemesis. The Nemesis' game is the authority: it refuses attacks over the
-- limit (and when it is not in a run), and the attacker gets the card back.
-- To grey out the cards before that happens, the attacker's game keeps
--   nemesis_pending  the Nemesis' pending count, sent with every reply and result
--   unacked          attacks sent that have no reply yet
-- and can_use() is false while nemesis_pending + unacked reaches the limit.
-- When the Nemesis drops out, messages can be lost, so both reset to 0 (and the
-- sent list is cleared); a later attack over the limit is refused and refunded,
-- so nothing gets stuck.

local NBA = {}
MP.NEXT_BLIND_ATTACKS = NBA

NBA.max_pending = 4

local defs = {}
local order = {}

function NBA.register(key, def)
	if not defs[key] then order[#order + 1] = key end
	defs[key] = def
end

function NBA.get_def(key)
	return defs[key]
end

function NBA.target(key)
	return defs[key] and defs[key].target or "blind"
end

-- Messages that name what the attack waits for.
local TARGET_TEXT = {
	blind = { incoming = "k_mp_nba_incoming_from_nemesis", sent = "k_mp_nba_sent_to_nemesis" },
	shop = { incoming = "k_mp_nba_incoming_shop_from_nemesis", sent = "k_mp_nba_sent_to_nemesis_shop" },
}

local function target_text(key, which)
	return TARGET_TEXT[NBA.target(key)][which]
end

-- Card config values (read from this game's own copy, never from the network).
function NBA.config(key)
	local center = G.P_CENTERS[key]
	return center and center.config and center.config.extra or {}
end

function NBA.state()
	if not G.GAME then return nil end
	G.GAME.mp_next_blind = G.GAME.mp_next_blind
		or { pending = {}, active = {}, active_entries = {}, sent = {}, nemesis_pending = 0, unacked = 0 }
	return G.GAME.mp_next_blind
end

function NBA.pending()
	local state = NBA.state()
	return state and state.pending or {}
end

-- The state an effect returned from apply() while its blind is running, else nil.
function NBA.active(key)
	local state = G.GAME and G.GAME.mp_next_blind
	return state and state.active[key]
end

function NBA.nemesis_present()
	if not (MP.LOBBY.code and MP.LOBBY.connected) then return false end
	if MP.enemy_disconnect_countdown then return false end
	local enemy = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host
	return enemy ~= nil and enemy.username ~= nil
end

local function in_run()
	return G.STAGE == G.STAGES.RUN and G.GAME and G.HUD and G.hand
end

-- can_use() for every next-blind Attack card.
function NBA.can_send()
	local state = NBA.state()
	return NBA.nemesis_present() and state ~= nil and state.nemesis_pending + state.unacked < NBA.max_pending
end

-- The Nemesis' count comes from the network, so keep it inside 0..max_pending.
local function set_nemesis_pending(p)
	local state = NBA.state()
	local count = math.floor(tonumber(p.pending_count) or 0)
	state.nemesis_pending = math.max(0, math.min(NBA.max_pending, count))
end

function NBA.name(key)
	if not defs[key] then return "?" end
	return localize({ type = "name_text", set = "Attack", key = key })
end

-- Short name and data for the Attacks panel: "Debuff", "Spades".
function NBA.short_name(key)
	local def = defs[key]
	if def and def.short_name then return localize({ type = "variable", key = def.short_name, vars = {} }) end
	return NBA.name(key)
end

function NBA.short(entry)
	local def = defs[entry.key]
	return def and def.short and def.short(entry) or nil
end

function NBA.effect(entry)
	local def = defs[entry.key]
	return def and def.effect and def.effect(entry) or NBA.name(entry.key)
end

-- Chance in whole percent, from this game's own card config.
function NBA.chance_percent(key)
	return math.floor((tonumber(NBA.config(key).chance) or 1) * 100 + 0.5)
end

-- "Shrink" or "Suit Debuff: Spades"
function NBA.describe(entry)
	local def = defs[entry.key]
	local detail = def and def.detail and def.detail(entry)
	if detail then return localize({ type = "variable", key = "k_mp_nba_entry_detail", vars = { NBA.name(entry.key), detail } }) end
	return NBA.name(entry.key)
end

-- The one place where an effect's chance is rolled. Runs on the Nemesis' game
-- at the start of the blind the attack targets, once per copy. Each effect has
-- its own seed key, different per player so the two games' rolls do not mirror.
-- Probability modifiers (Oops! All 6s) do not apply.
local function roll_lands(key)
	local chance = tonumber(NBA.config(key).chance) or 1
	if chance >= 1 then return true end
	return pseudorandom(MP.UTILS.player_seed_key("mp_nba_chance_" .. key)) < chance
end

-- Several messages can arrive at once (one result per copy), so each text
-- waits until the one before it has been shown for a while.
local TEXT_GAP = 1.5
local next_text_time = 0

local function show_text(text, colour)
	local now = G.TIMERS.REAL
	local wait = math.max(0, next_text_time - now)
	next_text_time = now + wait + TEXT_GAP
	G.E_MANAGER:add_event(Event({
		trigger = "after",
		delay = wait,
		timer = "REAL",
		blockable = false,
		blocking = false,
		func = function()
			G.FUNCS.attention_text_realtime({
				text = text,
				scale = 0.7,
				hold = 2,
				align = "cm",
				major = G.play,
				backdrop_colour = colour or G.C.RED,
			})
			play_sound("cancel")
			return true
		end,
	}))
end

NBA.show_text = show_text

-- Sender side: each card's use() is one call to this.
function NBA.send(key)
	local state = NBA.state()
	if state then state.unacked = state.unacked + 1 end
	MP.ACTIONS.modded(MP.id, "next_blind_attack", { effect = key })
end

local function entry_fields(entry)
	local fields = {}
	for k, v in pairs(entry) do
		if k ~= "key" then fields[k] = v end
	end
	fields.effect = entry.key
	return fields
end

-- Rebuild an entry from a message. Fields come from the network, so detail()
-- only uses them to look things up.
local function entry_from_message(p)
	local entry = { key = tostring(p.effect) }
	for k, v in pairs(p) do
		if k ~= "key" and k ~= "effect" and k ~= "result" and k ~= "pending_count" and type(v) ~= "table" then entry[k] = v end
	end
	return entry
end

-- Runs on the Nemesis' game.
MP.register_mod_action("next_blind_attack", function(p)
	local key = tostring(p.effect)
	local def = defs[key]
	if not def then return end
	if not in_run() then
		MP.ACTIONS.modded(MP.id, "next_blind_attack_reply", { effect = key, result = "not_in_run", pending_count = 0 })
		return
	end
	local pending = NBA.pending()
	if #pending >= NBA.max_pending then
		MP.ACTIONS.modded(MP.id, "next_blind_attack_reply", { effect = key, result = "full", pending_count = #pending })
		return
	end
	local entry = { key = key }
	if def.on_receive then def.on_receive(entry, pending) end
	pending[#pending + 1] = entry
	show_text(localize({ type = "variable", key = target_text(key, "incoming"), vars = { NBA.describe(entry) } }))
	local reply = entry_fields(entry)
	reply.result = "pending"
	reply.pending_count = #pending
	MP.ACTIONS.modded(MP.id, "next_blind_attack_reply", reply)
end, MP.id)

-- Runs on the user's game.
MP.register_mod_action("next_blind_attack_reply", function(p)
	if not in_run() then return end
	local entry = entry_from_message(p)
	if not defs[entry.key] then return end
	local state = NBA.state()
	state.unacked = math.max(0, state.unacked - 1)
	set_nemesis_pending(p)
	if p.result == "pending" then
		table.insert(state.sent, entry)
		show_text(localize({ type = "variable", key = target_text(entry.key, "sent"), vars = { NBA.describe(entry) } }))
		return
	end
	-- Refused: nothing was queued, so give the card back (like Joker Swap).
	if p.result == "full" then
		show_text(localize({ type = "variable", key = "k_mp_nba_full", vars = { NBA.max_pending } }))
	else
		show_text(localize({ type = "variable", key = "k_mp_nba_not_in_run", vars = {} }))
	end
	SMODS.add_card({ key = entry.key, area = G.consumeables })
end, MP.id)

-- Drop the sent entry a result is for: the first one with the same effect and
-- data, else the first one with the same effect.
local function forget_sent(entry)
	local sent = NBA.state().sent
	local same_key = nil
	for i, other in ipairs(sent) do
		if other.key == entry.key then
			local same = true
			for k, v in pairs(entry) do
				if other[k] ~= v then same = false end
			end
			for k in pairs(other) do
				if entry[k] == nil then same = false end
			end
			if same then
				table.remove(sent, i)
				return
			end
			same_key = same_key or i
		end
	end
	if same_key then table.remove(sent, same_key) end
end

-- Runs on the user's game, once per copy, when the Nemesis' blind starts.
MP.register_mod_action("next_blind_attack_result", function(p)
	if not in_run() then return end
	local entry = entry_from_message(p)
	if not defs[entry.key] then return end
	set_nemesis_pending(p)
	forget_sent(entry)
	if p.result == "landed" then
		show_text(localize({ type = "variable", key = "k_mp_nba_landed_on_nemesis", vars = { NBA.describe(entry) } }))
	else
		show_text(localize({ type = "variable", key = "k_mp_nba_fizzled_on_nemesis", vars = { NBA.describe(entry) } }), G.C.UI.TEXT_INACTIVE)
	end
end, MP.id)

-- Undo every effect that landed (only those for target, if given). leaving =
-- true when the lobby is gone and the run continues in singleplayer.
local function undo_active(leaving, target)
	local state = G.GAME and G.GAME.mp_next_blind
	if not state then return end
	local undone = {}
	for _, key in ipairs(order) do
		if state.active[key] ~= nil and (not target or NBA.target(key) == target) then
			undone[#undone + 1] = { key = key, state = state.active[key] }
			state.active[key] = nil
		end
	end
	local entries = {}
	for _, entry in ipairs(state.active_entries) do
		if target and NBA.target(entry.key) ~= target then entries[#entries + 1] = entry end
	end
	state.active_entries = entries
	for _, item in ipairs(undone) do
		defs[item.key].undo(item.state, leaving)
	end
end

-- Land every pending effect that targets this blind or shop: roll each copy's
-- chance, tell the attacker, apply what landed. pvp = true on a PvP blind.
local function land(target, pvp)
	local state = NBA.state()
	local landing, keep = {}, {}
	for _, entry in ipairs(state.pending) do
		local def = defs[entry.key]
		if def and (NBA.target(entry.key) ~= target or (def.skips_pvp and pvp)) then
			keep[#keep + 1] = entry
		elseif def then
			landing[entry.key] = landing[entry.key] or {}
			table.insert(landing[entry.key], entry)
		end
	end
	state.pending = keep
	local landed_names, fizzled_names = {}, {}
	for _, key in ipairs(order) do
		local landed = {}
		for _, entry in ipairs(landing[key] or {}) do
			local hit = roll_lands(key)
			local result = entry_fields(entry)
			result.result = hit and "landed" or "fizzled"
			result.pending_count = #keep
			MP.ACTIONS.modded(MP.id, "next_blind_attack_result", result)
			if hit then
				landed[#landed + 1] = entry
				table.insert(state.active_entries, entry)
				landed_names[#landed_names + 1] = NBA.describe(entry)
			else
				fizzled_names[#fizzled_names + 1] = NBA.describe(entry)
			end
		end
		if #landed > 0 then state.active[key] = defs[key].apply(landed) end
	end
	if #landed_names > 0 then
		show_text(localize({ type = "variable", key = "k_mp_nba_landed", vars = { table.concat(landed_names, ", ") } }))
	end
	if #fizzled_names > 0 then
		show_text(localize({ type = "variable", key = "k_mp_nba_fizzled", vars = { table.concat(fizzled_names, ", ") } }), G.C.GREEN)
	end
end

-- Start of a real new blind: land every pending effect that targets it.
-- Load order puts this after ui/game/game_state.lua, so G.GAME.blind.pvp is
-- already set when MP.is_pvp_boss() runs here.
local set_blind_ref = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
	set_blind_ref(self, blind, reset, silent)
	if not blind or reset or not G.hand then return end
	local state = NBA.state()
	if not state or #state.pending == 0 then return end
	-- Normally empty here; if a blind never reached end_round, undo it first.
	undo_active(false)
	land("blind", MP.is_pvp_boss())
end

-- A new shop: land every pending "next shop" effect before the shop's card
-- areas are built and filled. G.shop is nil only on the first frame of a new
-- shop visit (it still exists when coming back from a Booster Pack).
local update_shop_ref = Game.update_shop
function Game:update_shop(dt)
	if not G.STATE_COMPLETE and not G.shop and in_run() then
		local state = NBA.state()
		if state and #state.pending > 0 then
			undo_active(false, "shop")
			land("shop", false)
		end
	end
	return update_shop_ref(self, dt)
end

-- Leaving the shop ends its effects.
local toggle_shop_ref = G.FUNCS.toggle_shop
G.FUNCS.toggle_shop = function(e)
	undo_active(false, "shop")
	return toggle_shop_ref(e)
end

-- Messages to or from a Nemesis who dropped out may be lost, so forget the
-- counts kept for can_send(). The Nemesis' game still enforces the limit.
local nemesis_count_update_ref = Game.update
function Game:update(dt)
	local state = G.GAME and G.GAME.mp_next_blind
	if state and (state.unacked > 0 or state.nemesis_pending > 0 or #state.sent > 0) and not NBA.nemesis_present() then
		state.unacked = 0
		state.nemesis_pending = 0
		state.sent = {}
	end
	return nemesis_count_update_ref(self, dt)
end

-- End of the blind: undo whatever landed on it. Safe to run twice.
local end_round_ref = end_round
function end_round()
	undo_active(false)
	return end_round_ref()
end

-- Multiplayer runs are never saved; "Continue in Singleplayer" reloads the run
-- without the lobby. Undo anything still active and drop pending attacks there.
local start_run_ref = Game.start_run
function Game:start_run(args)
	start_run_ref(self, args)
	if MP.LOBBY.code or not G.GAME or not G.GAME.mp_next_blind then return end
	undo_active(true)
	G.GAME.mp_next_blind = nil
end
