local _, ns = ...
local L = ns.L

-- The name of your target stays above its head while it is selected, small
-- and discreet, and "Not yours yet" under it when it is. In a fight the name
-- goes (its health bar over its head shows it): only "Not yours yet" stays,
-- alone in the bubble, while it is true. Never when the game writes the name
-- itself, nor at the same time as the mouseover label on the same character.
-- Drawn by the shared engine, like every Wanderer window.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local UNIT = "target"
local HEAD_OFFSET = 4
local FADE = 0.4
local CHECK_DELAY = 0.1

local frame, skin, nameText, markText
local driver -- asleep without a target
local targetAlpha, sinceCheck = 0, 0
local anchoredPlate, anchoredLow -- low: on the head (the plate is invisible)

local function Plate()
	return (ns.Util.NameplateFor(UNIT))
end

-- The hover label already describes this character.
local function LabelOnTarget()
	return ns.IsLabelActive and ns.IsLabelActive() and Clean(Safe(UnitIsUnit, "mouseover", UNIT)) and true or false
end

local function Wanted()
	local db = ns.db
	if not (db and db.enabled and db.label.targetName) or ns.sceneActive then return end
	if not Clean(Safe(UnitExists, UNIT)) or LabelOnTarget() then return end
	return Plate()
end

local function InFight()
	return ns.inCombat or InCombatLockdown()
end

-- Whether the target is a monster not yours yet (said in its bubble).
function ns.TargetBubbleSaysUntagged()
	local db = ns.db
	return db and db.enabled and db.label.targetName and ns.IsUntaggedOnYou and ns.IsUntaggedOnYou(UNIT) or false
end

local function Layout(showName, showMark)
	local margin = ns.Skin.Margin()
	nameText:SetShown(showName)
	markText:SetShown(showMark)
	local width, height = 0, 0
	if showName then
		width = U.Measure(nameText, "GetStringWidth", 80)
		height = U.Measure(nameText, "GetStringHeight", 14)
	end
	if showMark then
		width = math.max(width, U.Measure(markText, "GetStringWidth", 80))
		height = height + (showName and 2 or 0) + U.Measure(markText, "GetStringHeight", 14)
	end
	frame:SetSize(width + margin * 2, height + margin * 2)
	nameText:ClearAllPoints()
	markText:ClearAllPoints()
	if showName then
		nameText:SetPoint("TOP", frame, "TOP", 0, -margin)
		markText:SetPoint("TOP", nameText, "BOTTOM", 0, -2)
	else
		markText:SetPoint("CENTER")
	end
	skin:Layout()
end

local function Update()
	local plate = Wanted()
	if not plate then
		targetAlpha = 0
		return
	end
	-- In a fight the name is on the health bar over the head: only the warning.
	local showMark = ns.IsUntaggedOnYou and ns.IsUntaggedOnYou(UNIT) and true or false
	local showName = not InFight() and not ns.GameShowsName(UNIT)
	if showName then
		-- A protected name is shown as is, never compared.
		if not pcall(nameText.SetText, nameText, U.FullName(UNIT)) then showName = false end
		local isPlayer = Clean(Safe(UnitIsPlayer, UNIT)) and true or false
		nameText:SetTextColor(ns.UnitColor(UNIT, isPlayer))
	end
	if not (showName or showMark) then
		targetAlpha = 0
		return
	end
	Layout(showName, showMark)
	-- An invisible plate takes no room: the name stands right on the head.
	local low = ns.IsPlateQuiet and ns.IsPlateQuiet(plate) or false
	if plate ~= anchoredPlate or low ~= anchoredLow then
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOM", plate, low and "BOTTOM" or "TOP", 0, HEAD_OFFSET)
		anchoredPlate, anchoredLow = plate, low
	end
	targetAlpha = 1
	if not frame:IsShown() then
		frame:SetAlpha(0)
		frame:Show()
	end
end

local function OnUpdate(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= CHECK_DELAY then
		sinceCheck = 0
		Update()
	end
	if ns.Skin.Fade(frame, targetAlpha, elapsed, FADE, FADE) <= 0 and frame:IsShown() then
		frame:Hide()
		anchoredPlate = nil
	end
	if not frame:IsShown() and not Clean(Safe(UnitExists, UNIT)) then driver:Hide() end
end

function ns.RefreshTargetLabel()
	if not frame then return end
	frame:SetScale(ns.Skin.Scale())
	Update()
end

function ns.InitTargetLabel()
	frame, skin = ns.Skin.CreateWindow("WandererTargetLabel", "LOW")
	frame:EnableMouse(false)
	nameText = ns.Skin.CreateText(frame, "GameTooltipTextSmall")
	nameText:SetJustifyH("CENTER")
	markText = ns.Skin.CreateText(frame, "GameTooltipTextSmall", 1, 0.6, 0.2)
	markText:SetJustifyH("CENTER")
	markText:SetText(L.UNTAGGED_MARK)
	driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", OnUpdate)
	driver:RegisterEvent("PLAYER_TARGET_CHANGED")
	driver:RegisterEvent("PLAYER_REGEN_DISABLED")
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:SetScript("OnEvent", function()
		Update()
		driver:Show()
	end)
	ns.RefreshTargetLabel()
end
