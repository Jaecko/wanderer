local _, ns = ...
local L = ns.L

-- Raid markers under the mouse, for whoever may place them (in a group;
-- the leader or an assistant in a raid). Hold the key (Key Bindings >
-- Wanderer) over an enemy: the game's eight symbols open in a wheel around
-- the cursor. Let go over one and it is set on that enemy, without
-- targeting it; over the cross, its symbol is taken off.
--
-- Around them, the ground markers: a click on a color, then on the ground,
-- as the game asks. The game keeps those buttons to itself in a fight: the
-- outer ring only shows out of one (the symbols work in a fight).

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local INNER_RADIUS, INNER_ICON = 50, 26
local OUTER_RADIUS, OUTER_ICON = 92, 22
local PICK = 18 -- pixels from the center before a symbol is chosen
local REACH = INNER_RADIUS + INNER_ICON -- further out: the outer ring, no symbol
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
-- The ground markers in the game's order, drawn with the symbol of their color.
local GROUND_SYMBOLS = { 6, 4, 3, 7, 1, 2, 5, 8 }
local FADE = 0.12
local atan2 = math.atan2 or math.atan

local wheel, ground -- the symbols (never protected), the ground markers (the game's buttons)
local icons = {} -- slot -> texture; slots 1 to 8 the symbols, 9 the cross
local unit, unitGUID -- who the symbol goes to
local chosen
local pendingBuild = false

-- Allowed to mark: in a group, and leading or assisting in a raid.
local function CanMark()
	if not (IsInGroup and Safe(IsInGroup)) then return false end
	if IsInRaid and Safe(IsInRaid) then
		return (Safe(UnitIsGroupLeader, "player") or Safe(UnitIsGroupAssistant, "player")) and true or false
	end
	return true
end

-- The hovered enemy as a unit that stays valid while the mouse leaves it:
-- your target, or its nameplate; else the hovered unit itself.
local function MarkedUnit()
	local guid = Clean(Safe(UnitGUID, "mouseover"))
	if not guid then
		if Clean(Safe(UnitExists, "target")) then return "target", Clean(Safe(UnitGUID, "target")) end
		return
	end
	if guid == Clean(Safe(UnitGUID, "target")) then return "target", guid end
	for _, plate in ipairs(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}) do
		local token = U.PlateUnit(plate)
		if token and Clean(Safe(UnitGUID, token)) == guid then return token, guid end
	end
	return "mouseover", guid
end

-- Slot under the cursor: 1 to 8 around the circle, 9 the cross at the top.
local function Slot()
	local x, y = GetCursorPosition()
	local scale = wheel:GetEffectiveScale()
	local cx, cy = wheel:GetCenter()
	if not (cx and cy) then return end
	local dx, dy = x / scale - cx, y / scale - cy
	local distance = math.sqrt(dx * dx + dy * dy)
	if distance < PICK or distance > REACH then return end
	-- Clockwise from the top, the cross first, as they are drawn.
	local angle = (math.deg(atan2(dx, dy)) + 360 + 20) % 360
	local slot = math.floor(angle / 40) -- nine slots of 40 degrees
	return slot == 0 and 9 or slot
end

local function Highlight()
	for slot, icon in pairs(icons) do
		local on = slot == chosen
		icon:SetSize(on and INNER_ICON * 1.25 or INNER_ICON, on and INNER_ICON * 1.25 or INNER_ICON)
		icon:SetAlpha(unit and (on and 1 or 0.75) or 0.3)
	end
end

local function Place(frame)
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

local function Open()
	if not CanMark() then
		if UIErrorsFrame then UIErrorsFrame:AddMessage(L.MARKERS_NOT_ALLOWED, 1, 0.1, 0.1) end
		return
	end
	unit, unitGUID = MarkedUnit()
	chosen = nil
	wheel:SetScale(ns.Skin.Scale())
	Place(wheel)
	wheel:SetAlpha(0)
	wheel:Show()
	Highlight()
	-- The ground markers: the game's own buttons, never touched in a fight.
	if ground and not InCombatLockdown() then
		Place(ground)
		ground:Show()
	end
end

local function Close(apply)
	if not wheel:IsShown() then return end
	if apply and chosen and unit then
		-- The same character still (a unit can change hands): its symbol, or none.
		local guid = Clean(Safe(UnitGUID, unit))
		if not unitGUID or guid == unitGUID then
			Safe(SetRaidTarget, unit, chosen == 9 and 0 or chosen)
		end
	end
	wheel:Hide()
	if ground and ground:IsShown() and not InCombatLockdown() then ground:Hide() end
	unit, unitGUID, chosen = nil, nil, nil
end

function Wanderer_Markers(keystate)
	if not wheel then return end
	if keystate == "down" then Open() else Close(true) end
end

local function OnUpdate(self, elapsed)
	local alpha = self:GetAlpha()
	if alpha < 1 then self:SetAlpha(math.min(1, alpha + elapsed / FADE)) end
	local slot = Slot()
	if slot ~= chosen then
		chosen = slot
		Highlight()
	end
end

-- A disc of shade behind a ring, so the symbols read over any ground.
local function Disc(parent, size, alpha)
	local disc = parent:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(DISC)
	disc:SetVertexColor(0, 0, 0, alpha)
	disc:SetSize(size, size)
	disc:SetPoint("CENTER")
	return disc
end

local function Around(index, count, radius)
	local angle = math.rad((index - 1) * 360 / count)
	return math.sin(angle) * radius, math.cos(angle) * radius
end

-- The ground markers: the game's secure buttons (set on a click, then the
-- ground), one to clear them all. Made out of a fight only.
local function BuildGround()
	if ground then return end
	if InCombatLockdown() then
		pendingBuild = true
		return
	end
	pendingBuild = false
	ground = CreateFrame("Frame", "WandererGroundMarkers", UIParent)
	ground:SetSize(OUTER_RADIUS * 2 + OUTER_ICON, OUTER_RADIUS * 2 + OUTER_ICON)
	ground:SetFrameStrata("DIALOG")
	ground:Hide()
	for index = 1, 9 do
		local button = CreateFrame("Button", "WandererGroundMarker" .. index, ground, "SecureActionButtonTemplate")
		button:SetSize(OUTER_ICON, OUTER_ICON)
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetAttribute("type", "worldmarker")
		local texture = button:CreateTexture(nil, "ARTWORK")
		texture:SetAllPoints()
		if index <= 8 then
			button:SetAttribute("marker", index)
			button:SetAttribute("action", "set")
			texture:SetTexture(RAID_ICON:format(GROUND_SYMBOLS[index]))
			texture:SetVertexColor(1, 1, 1, 0.9)
		else
			button:SetAttribute("action", "clear")
			texture:SetTexture(CLEAR_ICON)
		end
		-- The ground ones stand on a small dark plate, apart from the symbols.
		local plate = button:CreateTexture(nil, "BACKGROUND")
		plate:SetTexture(DISC)
		plate:SetVertexColor(0, 0, 0, 0.6)
		plate:SetPoint("CENTER")
		plate:SetSize(OUTER_ICON + 8, OUTER_ICON + 8)
		local x, y = Around(index, 9, OUTER_RADIUS)
		button:SetPoint("CENTER", ground, "CENTER", x, y)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(index <= 8 and L.MARKERS_GROUND or L.MARKERS_GROUND_CLEAR, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
end

function ns.InitMarkers()
	wheel = CreateFrame("Frame", "WandererMarkers", UIParent)
	wheel:SetSize(REACH * 2, REACH * 2)
	wheel:SetFrameStrata("TOOLTIP")
	wheel:EnableMouse(false)
	wheel:Hide()
	Disc(wheel, INNER_RADIUS * 2 + INNER_ICON + 12, 0.55)
	for slot = 1, 9 do
		local icon = wheel:CreateTexture(nil, "ARTWORK")
		icon:SetSize(INNER_ICON, INNER_ICON)
		icon:SetTexture(slot == 9 and CLEAR_ICON or RAID_ICON:format(slot))
		-- The cross on top, the symbols clockwise after it.
		local x, y = Around(slot == 9 and 1 or slot + 1, 9, INNER_RADIUS)
		icon:SetPoint("CENTER", wheel, "CENTER", x, y)
		icons[slot] = icon
	end
	wheel:SetScript("OnUpdate", OnUpdate)
	BuildGround()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			-- Still allowed at this very moment: the ground ring goes before the fight locks it.
			if ground and ground:IsShown() then ground:Hide() end
		elseif pendingBuild then
			BuildGround()
		end
	end)
end
