local _, ns = ...
local L = ns.L

-- What's new: after an update (a new release, not every build), once, a
-- short window lists what changed (in the player's language). Never on the
-- very first launch: the welcome screen comes then. Reopened with /wanderer news.

local U = ns.Util

local WIDTH = 520
local SHOW_DELAY = 3
local ICON = "Interface\\Icons\\INV_Misc_Note_06"

local window
local rows = {}

local function Version()
	local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return get and U.Safe(get, "Wanderer", "Version") or "?"
end

-- The release a build belongs to: 0.33.12 and 0.33.13 are both "0.33".
-- The news show once per release, never at every build.
local function Release()
	return Version():match("^(%d+%.%d+)") or Version()
end

local function Lines()
	local lines = {}
	for line in (L.NEWS_LINES or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
	return lines
end

local function Layout()
	local margin = ns.Skin.Margin() + 8
	local inner = WIDTH - margin * 2
	window.title:SetText(L.NEWS_TITLE:format(Version()))
	local y = margin + 40 + 12
	for index, line in ipairs(Lines()) do
		local row = rows[index]
		if not row then
			row = {}
			row.mark = window:CreateTexture(nil, "ARTWORK")
			row.mark:SetSize(5, 5)
			row.mark:SetColorTexture(1, 0.82, 0, 0.8)
			row.text = ns.Skin.CreateText(window, "GameTooltipText", 0.92, 0.9, 0.85)
			rows[index] = row
		end
		row.text:SetWidth(inner - 14)
		row.text:SetText(line)
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", window, "TOPLEFT", margin + 14, -y)
		row.mark:ClearAllPoints()
		row.mark:SetPoint("TOPLEFT", window, "TOPLEFT", margin + 2, -(y + 6))
		y = y + U.Measure(row.text, "GetStringHeight", 14) + 8
	end
	window:SetSize(WIDTH, y + 16 + 26 + margin)
	ns.Skin.Get(window):Layout()
end

local function Close()
	ns.root.seenVersion = Release()
	window:Hide()
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererNews", "DIALOG")
	window:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetClampedToScreen(true)
	local margin = ns.Skin.Margin() + 8
	local icon = window:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	icon:SetTexture(ICON)
	ns.Skin.RoundMask(window, icon)
	window.title = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	window.title:SetPoint("LEFT", icon, "RIGHT", 12, 0)
	window.title:SetPoint("RIGHT", window, "RIGHT", -40, 0)
	if window.title.SetWordWrap then window.title:SetWordWrap(false) end
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", Close)
	local ok = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	ok:SetText(L.NEWS_OK)
	ok:SetSize(math.max(120, U.Measure(ok:GetFontString() or ok, "GetStringWidth", 90) + 30), 26)
	ok:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	ok:SetScript("OnClick", Close)
	if UISpecialFrames then table.insert(UISpecialFrames, "WandererNews") end
	window:SetScript("OnHide", function() ns.root.seenVersion = Release() end)
	window:SetScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		Layout()
	end)
end

function ns.ShowNews()
	if not ns.root or InCombatLockdown() then return end
	if not window then CreateWindow() end
	window:Show()
end

function ns.InitNews()
	-- First launch: the welcome screen tells everything, this version is seen.
	if not ns.root.welcomed then
		ns.root.seenVersion = Release()
		return
	end
	if ns.root.seenVersion == Release() then return end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		C_Timer.After(SHOW_DELAY, function()
			if ns.root.seenVersion == Release() then return end
			if InCombatLockdown() then
				self:RegisterEvent("PLAYER_REGEN_ENABLED")
			else
				ns.ShowNews()
			end
		end)
	end)
end
