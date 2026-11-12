local _, ns = ...
local L = ns.L

-- What's new: after an update (a new release, not every build), once, a small card tells the few key points
-- of the new version (in the player's language), with a button to read everything (the News page of the
-- settings window). Never on the very first launch: the welcome screen comes then. Never in a fight, never
-- over the welcome or another addon's first window.

local U = ns.Util

local WIDTH = 440
local POINTS = 4 -- the key points told on the card
local SHOW_DELAY = 3
local ICON = "Interface\\Icons\\INV_Misc_Note_06"
local MIN_LEAD = 12 -- (a lead shorter than this says too little: the whole line instead)

local window
local points = {}

-- An installed addon's metadata (its version, its title), nil when the game says nothing.
local function Metadata(addon, field)
	local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return get and U.Safe(get, addon, field) or nil
end

-- An installed addon's version and release: 0.33.12 and 0.33.13 are both "0.33" (its news show once per
-- release, never at every build).
local function VersionOf(addon) return Metadata(addon, "Version") or "?" end
local function ReleaseOf(addon) return VersionOf(addon):match("^(%d+%.%d+)") or VersionOf(addon) end
local function Release() return ReleaseOf("Wanderer") end

local function Lines(text)
	local lines = {}
	for line in (text or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
	return lines
end

-- The news of Wanderer, then of each installed extension (spec.addon, spec.news): { addon, name, version,
-- lines, new } (new: not seen yet). onlyNew: those not seen yet only.
function ns.NewsSections(onlyNew)
	local sections = {}
	local function Add(addon, name, text, new)
		local lines = Lines(text)
		if lines[1] and (new or not onlyNew) then
			sections[#sections + 1] = { addon = addon, name = name, version = VersionOf(addon), lines = lines, new = new }
		end
	end
	Add("Wanderer", L.ADDON_TITLE, L.NEWS_LINES, ns.root ~= nil and ns.root.seenVersion ~= Release())
	local seen = ns.root and ns.root.seenNews or {}
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		if extension.addon and extension.news then
			local name = Metadata(extension.addon, "Title") or extension.title or extension.addon
			Add(extension.addon, name, extension.news, seen[extension.addon] ~= ReleaseOf(extension.addon))
		end
	end
	return sections
end

-- A line's key point: its words before the first colon (what it is about), else the whole line.
local COLONS = { ": ", " :", "\239\188\154" } -- (and the full width colon of Chinese)
function ns.NewsLead(line)
	local cut
	for _, colon in ipairs(COLONS) do
		local at = line:find(colon, 1, true)
		if at and (not cut or at < cut) then cut = at end
	end
	if not cut then return line end
	local lead = line:sub(1, cut - 1):gsub("[%s\194\160]+$", "")
	return #lead >= MIN_LEAD and lead or line
end

-- Seen: Wanderer's release and every installed extension's.
local function Seen()
	ns.root.seenVersion = Release()
	ns.root.seenNews = ns.root.seenNews or {}
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		if extension.addon then ns.root.seenNews[extension.addon] = ReleaseOf(extension.addon) end
	end
end

-- (seen once hidden: the OnHide hook below)
local function Close() window:Hide() end

local function Point(index)
	if points[index] then return points[index] end
	local point = {}
	point.mark = window:CreateTexture(nil, "ARTWORK")
	point.mark:SetSize(5, 5)
	point.mark:SetColorTexture(ns.Skin.RGB("gold", 0.8))
	point.text = ns.Skin.Text(window, "GameTooltipText", "text")
	if point.text.SetMaxLines then point.text:SetMaxLines(2) end
	points[index] = point
	return point
end

-- The card: the first section told (Wanderer's, else an extension's), its key points, the others named.
local function Layout(sections)
	local Skin = ns.Skin
	local margin = Skin.Margin() + 8
	local inner = WIDTH - margin * 2
	local first = sections[1]
	window.title:SetText(first.addon == "Wanderer" and L.NEWS_TITLE:format(first.version)
		or L.NEWS_TITLE_OF:format(first.name, first.version))
	local y = margin + 36 + 14
	for index = 1, POINTS do
		local line = first.lines[index]
		local point = line and Point(index) or points[index]
		if point then
			point.text:SetShown(line ~= nil)
			point.mark:SetShown(line ~= nil)
		end
		if line then
			point.text:SetWidth(inner - 14)
			point.text:SetText(ns.NewsLead(line))
			point.text:ClearAllPoints()
			point.text:SetPoint("TOPLEFT", window, "TOPLEFT", margin + 14, -y)
			point.mark:ClearAllPoints()
			point.mark:SetPoint("TOPLEFT", window, "TOPLEFT", margin + 2, -(y + 6))
			y = y + U.Measure(point.text, "GetStringHeight", 14) + 10
		end
	end
	-- (the other addons with news: named, read with the rest)
	local others = {}
	for index = 2, #sections do others[#others + 1] = sections[index].name end
	window.also:SetShown(others[1] ~= nil)
	if others[1] then
		window.also:SetWidth(inner)
		window.also:SetText(L.NEWS_ALSO:format(table.concat(others, ", ")))
		window.also:ClearAllPoints()
		window.also:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(y + 2))
		y = y + 2 + U.Measure(window.also, "GetStringHeight", 12) + 10
	end
	window:SetSize(WIDTH, y + 8 + 30 + margin)
	Skin.Get(window):Layout()
end

local function CreateWindow()
	local Skin = ns.Skin
	window = Skin.CreateWindow("WandererNews", "DIALOG")
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 60 }, nil, Close)
	local margin = Skin.Margin() + 8
	local icon = window:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	icon:SetTexture(ICON)
	Skin.RoundMask(window, icon)
	window.title = Skin.CreateText(window, "GameTooltipHeaderText", ns.Skin.RGB("gold"))
	window.title:SetPoint("LEFT", icon, "RIGHT", 12, 0)
	window.title:SetPoint("RIGHT", window, "RIGHT", -40, 0)
	if window.title.SetWordWrap then window.title:SetWordWrap(false) end
	window.also = Skin.Text(window, "GameTooltipTextSmall", "muted")
	if window.also.SetMaxLines then window.also:SetMaxLines(2) end
	local ok = Skin.Button(window, L.NEWS_OK, Close, "main", 110)
	ok:SetHeight(30)
	ok:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	-- Everything, every addon: the News page of the settings.
	local all = Skin.Button(window, L.NEWS_READ_ALL, function()
		Close()
		ns.OpenOptions("news")
	end, nil, 110)
	all:SetHeight(30)
	all:SetPoint("RIGHT", ok, "LEFT", -8, 0)
	window:HookScript("OnHide", Seen)
	window:HookScript("OnShow", function(self) self:SetScale(Skin.Scale()) end)
end

-- onlyNew: only what was not seen yet (after an update); else Wanderer's news of this version.
function ns.ShowNews(onlyNew)
	if not ns.root or InCombatLockdown() then return end
	local sections = ns.NewsSections(onlyNew)
	if not sections[1] then return end
	if not window then CreateWindow() end
	Layout(sections)
	-- (came by itself after an update: it never takes the controller away, it waits to be chosen)
	window.quiet = onlyNew and true or nil
	window:Show()
end

function ns.InitNews()
	-- First launch: the welcome screen tells everything, this version is seen.
	-- (the extensions are known once loaded: what is new is read a moment after entering the world)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		C_Timer.After(SHOW_DELAY, function()
			-- A character not welcomed yet: the welcome tells everything. The account's first one: this version
			-- seen; another one: the news wait for its next arrival.
			if not ns.Welcomed() then
				if not next(ns.root.welcomedBy or {}) then Seen() end
				return
			end
			-- (the chat Wanderer kept, waiting for Wanderer Chat: said once to this character)
			ns.TellChatWaiting()
			if not ns.NewsSections(true)[1] then return end
			if InCombatLockdown() then
				self:RegisterEvent("PLAYER_REGEN_ENABLED")
			else
				-- (never over another addon's first window: after it)
				ns.AfterOtherWelcome(function() ns.ShowNews(true) end)
			end
		end)
	end)
end
