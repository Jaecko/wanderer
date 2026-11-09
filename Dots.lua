local _, ns = ...

-- What your damage over time will still deal (option, off): this file follows your spells on every enemy
-- you put them on; DotBars.lua shows it on the health bars (target, focus, target of target, nameplates).
--
-- WoW Forever hides an enemy's health from addons in a fight: the comparison is the game's own (a bar's
-- size from a hidden number), never Wanderer's. What Wanderer knows is yours:
-- - the spells you cast, their damage from the game's tables (DotData.lua), with your spell power, attack
--   power and combo points;
-- - your own auras on the enemy when the game lets them be read: when the spell really started, how long
--   it really lasts (talents), whether it is still there (dispelled, pushed off);
-- - the ticks seen landing (the blows an enemy takes): their real size takes the estimate's place, and
--   how far off the tables were is kept for the next cast (talents, the enemy's resistances);
-- - a tick a shield ate: the skull waits, the shield may eat more.
-- Every remaining tick is counted one by one, at its own time: a tick already landed is never counted
-- again, a tick still to come always is.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local FLIGHT = 1.75 -- seconds a missile may fly before its damage over time starts (40 yards, slowest)
local SHIELD_FOR = 6 -- seconds a shield seen eating a tick keeps the skull away
local GROWTH = { 0.5, 1, 1.5 } -- Agony: its thirds
local SCHOOL_INDEX = { [1] = 1, [2] = 2, [4] = 3, [8] = 4, [16] = 5, [32] = 6, [64] = 7 } -- mask -> spell school
local AIMS = { "target", "softenemy", "focus", "mouseover" } -- where a cast may have gone, by its target's name
local LOOKED_AT = { "target", "focus" } -- units whose blows the game tells, besides the nameplates
local REFUSED = { RESIST = true, MISS = true, DODGE = true, PARRY = true, DEFLECT = true, IMMUNE = true } -- what the game says of a spell that did not land
local REFUSED_BEFORE = 0.4 -- seconds the game may tell it before the cast is seen
local REFUSED_AFTER = 0.7 -- seconds after a cast (and the flight of a missile) it still speaks of that cast

local tracker -- TickTracker.lua's following of your spells
local shields = {} -- enemy's key -> when a shield ate a tick
local refused = {} -- enemy's key -> { at, school } the last spell it shrugged off
local points -- your combo points when the last spell was sent
local power = {} -- spell school -> your spell power, last read out of a fight

-- (another addon marking them: left to it)
function ns.DotsOn()
	return ns.db and ns.db.enabled and ns.db.dots and ns.db.dots.enabled and not (ns.Yields and ns.Yields("dots")) and true or false
end

-- Your stats ---------------------------------------------------------------------------------------------

local function SpellPower(school)
	local index = SCHOOL_INDEX[school]
	if not index then
		-- (several schools: the strongest of them)
		local best = 0
		for mask, i in pairs(SCHOOL_INDEX) do
			if school % (2 * mask) >= mask then best = math.max(best, power[i] or 0) end
		end
		return best
	end
	local now = Clean(Safe(GetSpellBonusDamage, index))
	if now then power[index] = now end
	return power[index] or 0
end

local function AttackPower()
	local base, plus, minus = Safe(UnitAttackPower, "player")
	base, plus, minus = Clean(base), Clean(plus), Clean(minus)
	return base and (base + (plus or 0) + (minus or 0)) or 0
end

local function Middle(list)
	local sorted = {}
	for i, value in ipairs(list) do sorted[i] = value end
	table.sort(sorted)
	local n = #sorted
	if n == 0 then return nil end
	if n % 2 == 1 then return sorted[(n + 1) / 2] end
	return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

-- Enemies ------------------------------------------------------------------------------------------------

-- The nameplate token of a unit's plate, or nil.
local function PlateToken(unit)
	if type(unit) == "string" and unit:match("^nameplate%d+$") then return unit end
	local plate = U.NameplateFor(unit)
	local token = plate and Clean(U.PlateUnit(plate))
	return type(token) == "string" and token:match("^nameplate%d+$") and token or nil
end

-- Who an enemy is, to follow it: its GUID; where the game hides it (dungeons), its nameplate while shown;
-- else, for your target only, "target" (forgotten when you change target).
local function KeyOf(unit)
	if not unit or not Clean(Safe(UnitExists, unit)) then return nil end
	local guid = Clean(Safe(UnitGUID, unit))
	if guid then return guid end
	local token = PlateToken(unit)
	if token then return "plate:" .. token end
	if unit == "target" then return "target" end
	return nil
end

-- One damage over time ------------------------------------------------------------------------------------

-- One tick of a spell's damage over time, as you would deal it now (before the target's own defences).
local function TickOf(data, combo)
	return data[1] + data[7] * combo + data[5] * SpellPower(data[4]) + data[6] * AttackPower()
end

local function New(data, spell, at, combo)
	combo = combo or 0
	local duration = data[3] + data[8] * combo
	return { spell = spell, family = data[9], combo = combo, school = data[4], grows = data[10] or nil,
		flies = data[11] or nil, estimate = TickOf(data, combo), basePeriod = data[2], baseDuration = duration,
		period = data[2], count = math.max(1, math.floor(duration / data[2] + 0.5)), start = at, cast = at,
		drift = 0, heard = {}, something = {}, samples = {}, missed = 0, checked = 0 }
end

-- (its missile may still be flying: its start is not known yet)
local function Flying(dot) return dot.flies and not dot.anchored and not dot.fromAura end

-- Agony grows by thirds; every other spell ticks evenly.
local function Growth(dot, n)
	if not dot.grows then return 1 end
	return GROWTH[math.min(3, math.floor((n - 1) * 3 / dot.count) + 1)]
end

-- The size of tick n: what was seen of this one, else the estimate as corrected by the ticks seen before.
local function Size(dot, n)
	local ratios = tracker.ratios[dot.family]
	local ratio = ratios and Middle(ratios) or 1
	return (dot.real or dot.estimate * ratio) * Growth(dot, n)
end

-- What your damage over time will still deal to a unit (0: nothing of yours on it), and whether the skull
-- may say so (no shield seen eating your ticks lately). on: the option already known to be on (a drawing).
function ns.DotsLeft(unit, on)
	if not (on or ns.DotsOn()) or not tracker then return 0, false end
	local key = KeyOf(unit)
	if not key or not Clean(Safe(UnitCanAttack, "player", unit)) then return 0, false end
	if Clean(Safe(UnitIsDead, unit)) then
		tracker.active[key] = nil
		return 0, false
	end
	local total, now = tracker.Remaining(key, unit)
	if total <= 0 then return 0, false end
	local shield = shields[key]
	return total, not (shield and now - shield < SHIELD_FOR)
end

-- Whether anything of yours is still ticking somewhere (else nothing needs drawing).
function ns.DotsBusy()
	return tracker ~= nil and tracker.Busy()
end

-- Your spells --------------------------------------------------------------------------------------------

-- Where a spell sent at this name went (a macro's focus, your soft target), else your target. A name hidden
-- in a fight: your target when no other enemy could have been aimed at, else false (not known).
local function Aimed(name)
	if U.IsSecret(name) then
		for _, unit in ipairs(AIMS) do
			if unit ~= "target" and Clean(Safe(UnitExists, unit)) and not Clean(Safe(UnitIsUnit, unit, "target")) then return false end
		end
		name = nil
	end
	name = Clean(name)
	for _, unit in ipairs(AIMS) do
		if (unit == "target" and not name) or (name and Clean(Safe(UnitName, unit)) == name) then
			if Clean(Safe(UnitCanAttack, "player", unit)) then return unit end
		end
	end
	return nil
end

-- A finisher (its size from combo points): data, its numbers.
local function Finisher(data)
	return data ~= nil and (data[7] ~= 0 or data[8] ~= 0)
end

local function Sent(name, cast, spell)
	local combo = Clean(Safe(GetComboPoints, "player", "target"))
	points = combo and combo > 0 and combo or nil
	-- (a finisher spends the points on your target: it went there, whatever else is hovered)
	if points and Finisher(ns.DOTS[spell]) then
		tracker.Sent(Clean(Safe(UnitCanAttack, "player", "target")) and "target" or false, cast)
	else
		tracker.Sent(Aimed(name), cast)
	end
end

local function Cast(cast, spell)
	local combo = points or 0
	points = nil
	tracker.Cast(cast, spell, combo)
end

-- About its size (a sword's blow or another player's spell landing then is not it): a crit up to two and a
-- half times. Wider while nothing is known of its real size.
local function Fits(dot, n, amount, critical)
	local expected = Size(dot, n)
	if expected <= 0 then return false end
	local low, high = 0.5, 1.6
	if dot.real then low, high = 0.7, 1.35 end
	if critical then low, high = 1.25, 2.6 end
	return amount >= expected * low - 1 and amount <= expected * high + 1
end

-- The spell the game has just said did not land on this enemy (resisted, missed, dodged, immune): not followed.
-- Only one that has shown nothing yet: a tick resisted later does not end a spell that took.
local function DropRefused(key)
	local seen, list = refused[key], tracker.active[key]
	if not (seen and list) then return end
	for family, dot in pairs(list) do
		local after = seen.at - dot.cast
		local limit = REFUSED_AFTER + (Flying(dot) and FLIGHT or 0)
		if (not seen.school or seen.school == dot.school) and not dot.something[1] and not dot.fromAura
			and after >= -REFUSED_BEFORE and after <= limit then
			list[family] = nil
			refused[key] = nil
			break
		end
	end
	if not next(list) then tracker.active[key] = nil end
end

-- A blow an enemy took (UNIT_COMBAT), told once per unit showing it.
local function Landed(unit, action, flag, amount, school)
	action, flag, amount, school = Clean(action), Clean(flag), Clean(amount), Clean(school)
	if not action then return end
	local key = KeyOf(unit)
	local active = tracker.active
	if key and REFUSED[action] then
		refused[key] = { at = GetTime(), school = school }
		DropRefused(key)
		if action ~= "IMMUNE" then return end
	end
	local list = key and active[key]
	if not list then return end
	if action == "EVADE" then
		-- (it ran home: its health comes back, your spells are gone)
		active[key] = nil
		return
	end
	if action ~= "WOUND" and action ~= "ABSORB" and action ~= "IMMUNE" then return end
	local now = GetTime()
	-- (two of your spells of one school ticking for the same amount are told twice for one unit: both count)
	local first = tracker.Told(key, action .. ":" .. tostring(amount) .. ":" .. tostring(school), unit, now)
	if not first then return end
	local best, bestN, bestOff
	for family, dot in pairs(list) do
		if not first.fed[family] and (not school or school == dot.school) then
			local n, off = tracker.Due(dot, now)
			if n and not dot.heard[n] then
				-- (something of its school at its time: the spell is there, whatever its size)
				dot.something[n] = true
				local fits = action ~= "WOUND" or (amount and amount > 0 and Fits(dot, n, amount, flag == "CRITICAL"))
				if fits and (not bestOff or math.abs(off) < math.abs(bestOff)) then best, bestN, bestOff = dot, n, off end
			end
		end
	end
	if not best then return end
	first.fed[best.family] = true
	if action == "IMMUNE" then
		-- (immune to it: none of its ticks will hurt)
		list[best.family] = nil
		return
	end
	tracker.Heard(best, bestN, bestOff)
	if action == "ABSORB" then
		shields[key] = now
		return
	end
	if flag == "CRITICAL" then return end -- (one lucky tick: the next ones are not)
	local sample = amount / Growth(best, bestN)
	tracker.Keep(best.samples, sample)
	best.real = Middle(best.samples)
	if best.estimate > 0 then tracker.Ratio(best.family, sample / best.estimate) end
end

-- An option changed (the bars are DotBars.lua's, loaded later).
function ns.RefreshDots()
	if tracker then tracker.Sync() end
	if ns.DotBarsRefresh then ns.DotBarsRefresh() end
end

-- (for the tests)
function ns.DotsState() return tracker.active, tracker.ratios end

function ns.InitDots()
	tracker = ns.NewTickTracker({
		data = ns.DOTS, family = 9, filter = "HARMFUL|PLAYER", keyOf = KeyOf, looked = LOOKED_AT, size = Size, new = New,
		on = ns.DotsOn, flight = FLIGHT, flying = Flying, confirmAura = true, settle = DropRefused,
		late = function(dot, n) return (n == 1 and Flying(dot)) and FLIGHT or 0 end,
		-- (a finisher's combo points are not known afterwards: never started from an aura)
		fromAura = function(data) return not Finisher(data) end,
		fallback = function() return Clean(Safe(UnitCanAttack, "player", "target")) and KeyOf("target") or nil end,
		wake = function() if ns.DotBarsWake then ns.DotBarsWake() end end,
	})
	tracker.Listen({
		combat = Landed, sent = Sent, cast = Cast,
		PLAYER_TARGET_CHANGED = function() tracker.Forget("target") end,
		-- (a token goes to the next enemy shown: what was followed under it belonged to the one before)
		plate = function(unit) tracker.Forget("plate:" .. unit) end,
		rest = function()
			-- (out of a fight: your spell power, read again for the next one; the shields forgotten)
			for _, index in pairs(SCHOOL_INDEX) do power[index] = Clean(Safe(GetSpellBonusDamage, index)) or power[index] end
			local now = GetTime()
			for key, at in pairs(shields) do
				if now - at > SHIELD_FOR then shields[key] = nil end
			end
		end,
		aura = function(unit)
			-- (an enemy shown whose auras changed: read again now, and drawn if asleep)
			if not (unit == "target" or unit == "focus" or U.ShownPlates[unit]) then return end
			local key = KeyOf(unit)
			if key then tracker.Changed(key) end
			if ns.DotBarsWake then ns.DotBarsWake(true) end
		end,
	})
end
