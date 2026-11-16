local _, ns = ...

-- Threat: the health bar of a monster in a fight says who it is after, in three colors.
--   green: it is on you (you hold it),
--   yellow: you are losing it, or about to take it,
--   red: it is on someone else.
-- On the game's nameplates, on Wanderer's label over the head and on the target's (and focus', boss') frame in
-- Wanderer's look. Only a monster fighting with you on its list: any other keeps its own color. The game may keep
-- threat hidden from addons in a fight; then the bar keeps its color, nothing is guessed.
-- (Before 2026-11-16: a share in percent over the target frame and a line in the middle of the screen when a
-- monster left you. Replaced at the user's request by these colors, as threat plates do.)

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

-- By the game's threat status (UnitThreatSituation): 0 not on you, 1 about to take it, 2 losing it, 3 on you.
local COLORS = {
	[0] = { 0.86, 0.22, 0.2 },
	[1] = { 0.96, 0.78, 0.18 },
	[2] = { 0.96, 0.78, 0.18 },
	[3] = { 0.24, 0.78, 0.3 },
}
ns.THREAT_COLORS = COLORS

local function On()
	local db = ns.db
	return db and db.enabled and db.threat and db.threat.colors and true or false
end

-- The color of a monster's health for its threat now: r, g, b, or nil (not a monster in a fight with you on its
-- list, the setting off, or the game hiding it).
function ns.ThreatColor(unit)
	if not (On() and unit) then return nil end
	if Clean(Safe(UnitIsPlayer, unit)) or not Clean(Safe(UnitCanAttack, "player", unit)) then return nil end
	if not Clean(Safe(UnitAffectingCombat, unit)) then return nil end
	if not UnitThreatSituation then return nil end
	local status = Safe(UnitThreatSituation, "player", unit)
	if U.IsSecret(status) then return nil end
	local color = COLORS[status]
	if not color then return nil end
	return color[1], color[2], color[3]
end

-- The game's nameplates --------------------------------------------------------------------------------------

local painted = setmetatable({}, { __mode = "k" }) -- a plate's health bar we colored -> true

local function PlateBar(frame)
	if type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden()) then return nil end
	local unit = frame.unit or frame.displayedUnit
	if type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return nil end
	local bar = frame.healthBar or frame.HealthBar
	if type(bar) ~= "table" or not bar.SetStatusBarColor or (bar.IsForbidden and bar:IsForbidden()) then return nil end
	return bar, unit
end

-- A plate's health colored for its threat, or given back the game's own color (kept on the bar by the game).
local function PaintPlate(frame)
	local bar, unit = PlateBar(frame)
	if not bar then return end
	local r, g, b = ns.ThreatColor(unit)
	if r then
		pcall(bar.SetStatusBarColor, bar, r, g, b)
		painted[bar] = true
	elseif painted[bar] then
		painted[bar] = nil
		if type(bar.r) == "number" then pcall(bar.SetStatusBarColor, bar, bar.r, bar.g, bar.b) end
	end
end

local function PlateOf(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and Safe(C_NamePlate.GetNamePlateForUnit, unit)
	return type(plate) == "table" and plate.UnitFrame or nil
end

local function PaintAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(Safe(C_NamePlate.GetNamePlates) or {}) do
		if type(plate) == "table" and plate.UnitFrame then PaintPlate(plate.UnitFrame) end
	end
end
ns.RefreshThreatColors = PaintAll

function ns.InitThreat()
	-- (the game colors a plate again as it likes: ours laid again right after)
	if type(rawget(_G, "CompactUnitFrame_UpdateHealthColor")) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", PaintPlate)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "NAME_PLATE_UNIT_ADDED",
		"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, unit)
		unit = Clean(unit)
		if type(unit) == "string" and unit:match("^nameplate%d+$") then
			local frame = PlateOf(unit)
			if frame then PaintPlate(frame) end
			return
		end
		-- (a fight over, or begun: every plate as it is now; the target's frame follows its own health)
		if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" or not unit then PaintAll() end
		if ns.UnitFramesSoon then ns.UnitFramesSoon() end
	end)
end
