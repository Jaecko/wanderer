local _, ns = ...

-- What your heals over time will still heal (option, off): the mirror of Dots.lua for your friends. This file
-- follows your Renew, Rejuvenation, Regrowth and the like on every friend you put them on; HotBars.lua shows it
-- on their health bars (yours, your group's, your target and focus when friendly, friendly nameplates).
--
-- A friend's health may be hidden from addons in a fight: the comparison is the game's own (a bar's size
-- from a hidden number), never Wanderer's. What Wanderer knows is yours:
-- - the spells you cast, their healing from the game's tables (HotData.lua), with your healing power;
-- - your own auras on the friend when the game lets them be read: when the spell really started, how long it
--   really lasts (talents), whether it is still there (dispelled, cancelled, put on again);
-- - the ticks seen landing (the heals a friend takes): their real size takes the estimate's place. A tick
--   that lands on a friend almost whole is told smaller (the part beyond the health is lost): the biggest of
--   the recent ones is the spell's size, never their middle.
-- Every remaining tick is counted one by one, at its own time; a lucky (critical) tick changes nothing.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local AIMS = { "target", "softfriend", "focus", "mouseover", "player" } -- where a cast may have gone, by name
local GROUP = {} -- the group's tokens, in the order a name is looked for
for i = 1, 4 do GROUP[#GROUP + 1] = "party" .. i end
for i = 1, 40 do GROUP[#GROUP + 1] = "raid" .. i end
-- Units whose heals the game tells, besides the plates: you, your target and focus, your group.
local LOOKED_AT = { "player", "target", "focus" }
for _, token in ipairs(GROUP) do LOOKED_AT[#LOOKED_AT + 1] = token end

local tracker -- TickTracker.lua's following of your spells
local power -- your healing power, last read

-- (off unless asked for: nil, before the setting exists, is off)
function ns.HotsOn()
	local hots = ns.db and ns.db.hots
	return ns.db and ns.db.enabled and type(hots) == "table" and hots.enabled == true or false
end

-- Your healing power: read when the game tells it, else the last one read.
local function HealingPower()
	local now = Clean(Safe(GetSpellBonusHealing))
	if type(now) == "number" then power = now end
	return power or 0
end

local function Biggest(list)
	local best
	for _, value in ipairs(list) do
		if not best or value > best then best = value end
	end
	return best
end

-- Friends ------------------------------------------------------------------------------------------------

local function Friendly(unit)
	return Clean(Safe(UnitCanAssist, "player", unit)) and true or false
end

-- Who a friend is, to follow it: its GUID; where the game hides it, its token when that token stays (you,
-- your group: forgotten when the group changes); else nothing.
local STABLE = { player = true }
for _, token in ipairs(GROUP) do STABLE[token] = true end
local function KeyOf(unit)
	if not unit or not Clean(Safe(UnitExists, unit)) then return nil end
	local guid = Clean(Safe(UnitGUID, unit))
	if guid then return guid end
	if STABLE[unit] then return "unit:" .. unit end
	return nil
end

-- One heal over time -------------------------------------------------------------------------------------

local function New(data, spell, at)
	return { spell = spell, family = data[5], estimate = data[1] + data[4] * HealingPower(), basePeriod = data[2],
		baseDuration = data[3], period = data[2], count = math.max(1, math.floor(data[3] / data[2] + 0.5)), start = at,
		cast = at, drift = 0, heard = {}, something = {}, samples = {}, missed = 0, checked = 0 }
end

-- The size of one tick: what was seen of this one, else the estimate as corrected by the ticks seen before.
local function Size(hot)
	local ratios = tracker.ratios[hot.family]
	local ratio = ratios and Biggest(ratios) or 1
	return hot.real or hot.estimate * ratio
end

-- What your heals over time will still heal on a unit (0: nothing of yours on it). on: the option already
-- known to be on (a drawing).
function ns.HotsLeft(unit, on)
	if not (on or ns.HotsOn()) or not tracker then return 0 end
	local key = KeyOf(unit)
	if not key or not Friendly(unit) then return 0 end
	if Clean(Safe(UnitIsDeadOrGhost, unit)) then
		tracker.active[key] = nil
		return 0
	end
	return (tracker.Remaining(key, unit))
end

-- Whether anything of yours is still ticking somewhere (else nothing needs drawing).
function ns.HotsBusy()
	return tracker ~= nil and tracker.Busy()
end

-- Your spells --------------------------------------------------------------------------------------------

local function Named(unit, name)
	local short = Clean(Safe(UnitName, unit))
	if short == nil then return false end
	if short == name then return true end
	local full = GetUnitName and Clean(Safe(GetUnitName, unit, true))
	return full == name
end

-- Where a heal sent at this name went (your target, your soft target, a mouseover on a group frame, someone
-- of your group by name), else your target when friendly, else you (the game casts it on you then). A name
-- hidden in a fight: the same when no other friend could have been aimed at, else false (not known).
local function Aimed(name)
	if U.IsSecret(name) then
		for _, unit in ipairs(AIMS) do
			if unit ~= "target" and unit ~= "player" and Clean(Safe(UnitExists, unit)) and not Clean(Safe(UnitIsUnit, unit, "target")) then
				return false
			end
		end
		name = nil
	end
	name = Clean(name)
	if name then
		for _, unit in ipairs(AIMS) do
			if Named(unit, name) and Friendly(unit) then return unit end
		end
		for _, unit in ipairs(GROUP) do
			if Named(unit, name) and Friendly(unit) then return unit end
		end
		return nil
	end
	if Friendly("target") then return "target" end
	return "player"
end

local function Sent(name, cast)
	tracker.Sent(Aimed(name), cast)
end

-- About its size (another healer's spell landing then is not it). Smaller is allowed: the part beyond the
-- friend's health is lost (an overheal). A lucky tick up to twice and a half.
local function Fits(hot, amount, critical)
	local expected = Size(hot)
	if expected <= 0 then return false end
	local high = hot.real and 1.35 or 1.6
	if critical then high = 2.6 end
	return amount > 0 and amount <= expected * high + 1
end

-- A heal a friend took (UNIT_COMBAT), told once per unit showing it.
local function Landed(unit, action, flag, amount, school)
	action, flag, amount, school = Clean(action), Clean(flag), Clean(amount), Clean(school)
	if action ~= "HEAL" or type(amount) ~= "number" then return end
	local key = KeyOf(unit)
	local list = key and tracker.active[key]
	if not list then return end
	local now = GetTime()
	local first = tracker.Told(key, tostring(amount) .. ":" .. tostring(school), unit, now)
	if not first then return end
	local best, bestN, bestOff
	for family, hot in pairs(list) do
		if not first.fed[family] then
			local n, off = tracker.Due(hot, now)
			if n and not hot.heard[n] and Fits(hot, amount, flag == "CRITICAL") and (not bestOff or math.abs(off) < math.abs(bestOff)) then
				best, bestN, bestOff = hot, n, off
			end
		end
	end
	if not best then return end
	first.fed[best.family] = true
	tracker.Heard(best, bestN, bestOff)
	if flag == "CRITICAL" then return end -- (one lucky tick: the next ones are not)
	tracker.Keep(best.samples, amount)
	-- (the biggest seen: a smaller one lost its end to an overheal)
	best.real = math.max(Biggest(best.samples), best.real or 0)
	if best.estimate > 0 then tracker.Ratio(best.family, amount / best.estimate) end
end

-- Whether an aura change may hold one of your heals over time: one added of yours (when the game tells it), or
-- everything read again.
local function Mine(info)
	if type(info) ~= "table" or U.IsSecret(info) then return false end
	if Clean(info.isFullUpdate) then return true end
	local added = Clean(info.addedAuras)
	if type(added) ~= "table" then return false end
	for _, aura in ipairs(added) do
		local spell = type(aura) == "table" and not U.IsSecret(aura) and Clean(aura.spellId)
		if spell and ns.HOTS[spell] then
			local source = Clean(aura.sourceUnit)
			if source == nil or source == "player" then return true end
		end
	end
	return false
end

-- An option changed (the bars are HotBars.lua's).
function ns.RefreshHots()
	if tracker then tracker.Sync() end
	if ns.HotBarsRefresh then ns.HotBarsRefresh() end
end

-- (for the tests)
function ns.HotsState() return tracker.active, tracker.ratios end

-- The group changed (in a raid also for someone offline, a role, a subgroup): only the tokens now held by
-- someone else (or by no one, or by a name the game hides) forget what was followed under them; never you.
local holders = {} -- token -> the name holding it at the last change
local function ForgetMoved()
	for _, token in ipairs(GROUP) do
		local name = Clean(Safe(UnitName, token))
		if name == nil or holders[token] ~= name then tracker.Forget("unit:" .. token) end
		holders[token] = name
	end
end

function ns.InitHots()
	tracker = ns.NewTickTracker({
		data = ns.HOTS, family = 5, filter = "HELPFUL|PLAYER", keyOf = KeyOf, looked = LOOKED_AT, size = Size, new = New,
		on = ns.HotsOn, trustAura = true, events = { "GROUP_ROSTER_UPDATE" },
		fallback = function() return KeyOf(Friendly("target") and "target" or "player") end,
		wake = function() if ns.HotBarsWake then ns.HotBarsWake() end end,
	})
	tracker.Listen({
		combat = Landed, sent = Sent, cast = function(cast, spell) tracker.Cast(cast, spell) end,
		-- (a token goes to someone else: what was followed under it belonged to the one before)
		GROUP_ROSTER_UPDATE = ForgetMoved,
		-- (out of a fight: your healing power, read again for the next one)
		rest = HealingPower,
		aura = function(unit, info)
			-- (a friend carrying your spells, or one you just gave one to without a cast seen: read again now,
			-- and drawn if asleep; a raid's other auras ask for nothing)
			local key = unit and KeyOf(unit)
			if not key then return end
			if tracker.active[key] or Mine(info) then
				tracker.Changed(key)
				if ns.HotBarsWake then ns.HotBarsWake(true) end
			end
		end,
	})
end
