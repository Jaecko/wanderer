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

-- An installed addon's version and release (its news show once per release).
local function VersionOf(addon)
	local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return get and U.Safe(get, addon, "Version") or "?"
end
local function ReleaseOf(addon) return VersionOf(addon):match("^(%d+%.%d+)") or VersionOf(addon) end

-- What to tell: Wanderer's news, then each installed extension's under its name (spec.addon, spec.news): the
-- ones not seen yet, or all of them (asked from the menu).
local function Sections(all)
	local sections = {}
	local function Add(title, text)
		local lines = {}
		for line in (text or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
		if lines[1] then sections[#sections + 1] = { title = title, lines = lines } end
	end
	if all or ns.root.seenVersion ~= Release() then Add(nil, L.NEWS_LINES) end
	local seen = ns.root.seenNews or {}
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		if extension.addon and extension.news and (all or seen[extension.addon] ~= ReleaseOf(extension.addon)) then
			local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
			local name = get and U.Safe(get, extension.addon, "Title") or extension.title
			Add(name .. " " .. VersionOf(extension.addon), extension.news)
		end
	end
	return sections
end

local showAll = false
local heads = {}

local function Layout()
	local margin = ns.Skin.Margin() + 8
	local inner = WIDTH - margin * 2
	window.title:SetText(L.NEWS_TITLE:format(Version()))
	local y = margin + 40 + 12
	local index = 0
	for _, head in ipairs(heads) do head:Hide() end
	for count, section in ipairs(Sections(showAll)) do
		-- (an extension's news: its name over them)
		if section.title then
			local head = heads[count]
			if not head then
				head = ns.Skin.CreateText(window, "GameTooltipText", 1, 0.82, 0)
				heads[count] = head
			end
			head:SetText(section.title)
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(y + 6))
			head:Show()
			y = y + 6 + U.Measure(head, "GetStringHeight", 14) + 8
		end
		for _, line in ipairs(section.lines) do
			index = index + 1
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
			row.text:Show()
			row.mark:Show()
			y = y + U.Measure(row.text, "GetStringHeight", 14) + 8
		end
	end
	for extra = index + 1, #rows do
		rows[extra].text:Hide()
		rows[extra].mark:Hide()
	end
	window:SetSize(WIDTH, y + 16 + 26 + margin)
	ns.Skin.Get(window):Layout()
end

-- Seen: Wanderer's release and every installed extension's.
local function Seen()
	ns.root.seenVersion = Release()
	ns.root.seenNews = ns.root.seenNews or {}
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		if extension.addon then ns.root.seenNews[extension.addon] = ReleaseOf(extension.addon) end
	end
end

local function Close()
	Seen()
	window:Hide()
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererNews", "DIALOG")
	ns.Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 60 }, nil, Close)
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
	local ok = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	ok:SetText(L.NEWS_OK)
	ok:SetSize(math.max(120, U.Measure(ok:GetFontString() or ok, "GetStringWidth", 90) + 30), 26)
	ok:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	ok:SetScript("OnClick", Close)
	window:SetScript("OnHide", Seen)
	window:SetScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		Layout()
	end)
end

-- all: every news (asked from the menu), else only what was not seen yet.
function ns.ShowNews(onlyNew)
	if not ns.root or InCombatLockdown() then return end
	showAll = not onlyNew
	if not window then CreateWindow() end
	if window:IsShown() then Layout() else window:Show() end
end

function ns.InitNews()
	-- First launch: the welcome screen tells everything, this version is seen.
	-- (the extensions are known once loaded: what is new is read a moment after entering the world)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		C_Timer.After(SHOW_DELAY, function()
			if not ns.root.welcomed then return Seen() end
			if not Sections(false)[1] then return end
			if InCombatLockdown() then
				self:RegisterEvent("PLAYER_REGEN_ENABLED")
			else
				ns.ShowNews(true)
			end
		end)
	end)
end
