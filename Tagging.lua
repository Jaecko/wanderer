local _, ns = ...
local L = ns.L

-- Monsters attacking you that are not yours yet: nobody has hit them, so
-- another player could take them (and their loot and experience). A small
-- mark over their head tells which ones to hit first when several come.
--
-- The game marks a monster hit by someone else as taken ("tap denied"). So a
-- monster on you that is not taken and has not taken a blow has not been hit
-- by anyone. The blows are told by the game (UNIT_COMBAT) even where it keeps
-- the health secret (WoW Forever); elsewhere a full health says the same.
-- Damage that answers a blow on you (thorns, retribution aura) does not make
-- a monster yours: it lands at the very moment the monster strikes you, and
-- is not counted (a blow of yours landing at that same moment waits for the
-- next one: Wanderer never says a monster is yours when it is not). When
-- the game still says it directly (UnitIsTappedByPlayer), its answer is used.
--
-- The mark stands over the monster's nameplate when the game shows it; for
-- the monster you target, it is said on the line over the target frame
-- (TargetInfo.lua). The game may
-- keep some fight details from addons (health, threat): /wanderer debug then
-- tells which ones, on the target.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_DELAY = 0.2
local MARK_OFFSET = 26 -- above the place of the names
local ICON = "Interface\\Icons\\Ability_SteelMelee"

local marks = {} -- nameplate -> mark window
local sinceCheck = 0
local touched = {} -- monster (its GUID, or its nameplate) -> time of the blow that touched it
local struck -- time a monster last struck you
local BLOWS = { WOUND = true, BLOCK = true, ABSORB = true, RESIST = true }

-- How a monster is known: its GUID, or (when the game keeps it) its nameplate.
local function Key(unit)
	local guid = Safe(UnitGUID, unit)
	if guid and not U.IsSecret(guid) then return guid end
	return C_NamePlate and Safe(C_NamePlate.GetNamePlateForUnit, unit) or nil
end

local function OnBlow(unit, action)
	if not (unit and BLOWS[Clean(action) or ""]) then return end
	local now = GetTime()
	if unit == "player" then
		-- Struck: blows landing at this same moment answer it (thorns...).
		struck = now
		for key, at in pairs(touched) do
			if at == now then touched[key] = nil end
		end
		return
	end
	if now == struck then return end
	local key = Key(unit)
	if key and not touched[key] then touched[key] = now end
end

-- The monster is after you: you are on its threat list, or it targets you.
local function IsOnYou(unit)
	if Clean(Safe(UnitThreatSituation, "player", unit)) then return true end
	return Clean(Safe(UnitIsUnit, unit .. "target", "player")) and true or false
end

local function IsUntouched(unit)
	if UnitIsTappedByPlayer then
		local mine = Safe(UnitIsTappedByPlayer, unit)
		if not U.IsSecret(mine) then return not mine end
	end
	local key = Key(unit)
	if key and touched[key] then return false end -- took a blow of its own
	local health, maximum = Clean(Safe(UnitHealth, unit)), Clean(Safe(UnitHealthMax, unit))
	if health and maximum and maximum > 0 then return health >= maximum end
	-- Health kept secret: no blow seen on it means untouched.
	return key ~= nil
end

-- A monster attacking you that nobody has hit yet.
function ns.IsUntaggedOnYou(unit)
	local db = ns.db
	if not (db and db.enabled and db.label.untagged) then return false end
	if not Clean(Safe(UnitExists, unit)) or Clean(Safe(UnitIsPlayer, unit)) then return false end
	if not Clean(Safe(UnitCanAttack, "player", unit)) or Clean(Safe(UnitIsDead, unit)) then return false end
	-- Already someone else's, or the game keeps it secret: never claim it is free.
	local taken = Safe(UnitIsTapDenied, unit)
	if U.IsSecret(taken) or taken then return false end
	if not Clean(Safe(UnitAffectingCombat, unit)) then return false end
	return IsOnYou(unit) and IsUntouched(unit)
end

local function CreateMark()
	local mark, skin = ns.Skin.CreateWindow(nil, "LOW")
	mark:EnableMouse(false)
	mark.text = ns.Skin.CreateText(mark, "GameTooltipTextSmall", 1, 0.6, 0.2)
	mark.text:SetPoint("CENTER")
	mark.text:SetText(("|T%s:12:12:0:0|t %s"):format(ICON, L.UNTAGGED_MARK))
	local margin = ns.Skin.Padding() + 4
	mark:SetSize(U.Measure(mark.text, "GetStringWidth", 90) + margin * 2,
		U.Measure(mark.text, "GetStringHeight", 12) + margin * 2)
	skin:Layout()
	return mark
end

-- What the game tells (or keeps) about a monster, for /wanderer debug.
local function Shown(value)
	if U.IsSecret(value) then return "secret" end
	return tostring(value)
end

function ns.DebugTagging(unit)
	if not Clean(Safe(UnitExists, unit)) then return end
	local mine = UnitIsTappedByPlayer and Shown(Safe(UnitIsTappedByPlayer, unit)) or "-"
	local key = Key(unit)
	ns.Print(("untagged %s: attack=%s taken=%s combat=%s threat=%s targetsYou=%s mine=%s hit=%s health=%s/%s -> %s"):format(
		unit, Shown(Safe(UnitCanAttack, "player", unit)), Shown(Safe(UnitIsTapDenied, unit)),
		Shown(Safe(UnitAffectingCombat, unit)), Shown(Safe(UnitThreatSituation, "player", unit)),
		Shown(Safe(UnitIsUnit, unit .. "target", "player")), mine, tostring(key and touched[key] ~= nil or false), Shown(Safe(UnitHealth, unit)),
		Shown(Safe(UnitHealthMax, unit)), tostring(ns.IsUntaggedOnYou(unit))))
end

local function Update()
	local shown = {}
	local plates = C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}
	for _, plate in ipairs(plates) do
		local unit = U.PlateUnit(plate)
		-- The label says it already for the one it describes.
		local described = unit and ns.IsLabelActive and ns.IsLabelActive() and ns.LabelUnit
			and Clean(Safe(UnitIsUnit, unit, ns.LabelUnit()))
		if unit and not described and not (plate.IsForbidden and plate:IsForbidden()) and ns.IsUntaggedOnYou(unit) then
			local mark = marks[plate] or CreateMark()
			marks[plate] = mark
			mark:ClearAllPoints()
			mark:SetPoint("BOTTOM", plate, "TOP", 0, MARK_OFFSET)
			mark:SetScale(ns.Skin.Scale())
			mark:Show()
			shown[plate] = true
		end
	end
	for plate, mark in pairs(marks) do
		if not shown[plate] then mark:Hide() end
	end
end

function ns.InitTagging()
	-- A monster on you means a fight: the check runs only during one.
	local driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed
		if sinceCheck < CHECK_DELAY then return end
		sinceCheck = 0
		Update()
	end)
	driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	driver:RegisterEvent("PLAYER_REGEN_DISABLED")
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:RegisterEvent("PLAYER_TARGET_CHANGED")
	driver:RegisterEvent("UNIT_COMBAT")
	driver:SetScript("OnEvent", function(_, event, unit, action)
		if event == "UNIT_COMBAT" then return OnBlow(unit, action) end
		if ns.debug and (event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_DISABLED") then
			ns.DebugTagging("target")
		end
		if event == "PLAYER_REGEN_DISABLED" then
			driver:SetShown(ns.db and ns.db.enabled and ns.db.label.untagged and true or false)
		elseif event == "PLAYER_REGEN_ENABLED" then
			wipe(touched) -- fights over: monsters come back fresh
			Update()
			driver:Hide()
		else
			-- A plate handed to another monster: the blows it knew were not on this one.
			if event == "NAME_PLATE_UNIT_REMOVED" and unit and C_NamePlate then
				local plate = Safe(C_NamePlate.GetNamePlateForUnit, unit)
				if plate then touched[plate] = nil end
			end
			Update()
		end
	end)
end
