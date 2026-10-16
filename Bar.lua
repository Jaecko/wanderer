local _, ns = ...
local L = ns.L
local U = ns.Util

-- Wanderer's bar (option): a quiet line against the top left of the screen, in Wanderer's own hand: words
-- in small capitals on a dark band fading out to the right, a thin golden rule under it. A word turns gold
-- with a fine line under it when the mouse is on it; a count in gold beside it (reminders left). The menu,
-- the reminders, the extensions' windows, and the other addons' icons (those around the minimap, gathered)
-- in a list under "Other addons", only when there are some. Faint until the mouse comes near.

local HEIGHT = 34
local PAD = 12 -- the band's ends
local SPACE = 9 -- around each dot between the words
local REST, NEAR = 0.6, 1

local bar
local items, dots = {}, {}
local pulsing = {} -- words whose extension says something waits there
local C -- Wanderer's colors (Kit.lua, loaded after)

-- What the bar offers, as things stand: { key, label, hint, run, right }.
local function Entries()
	local list = {
		{ key = "menu", label = "Wanderer", hint = L.BAR_MENU_HINT, gold = true,
			run = function(self) ns.ShowMenu(self) end, right = function() ns.OpenOptions() end },
		{ key = "todo", label = L.TODO_TITLE, run = function() ns.ToggleTodo() end },
	}
	-- The extensions' windows (not the shopping list: it stays in the menu).
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		local launcher = extension.launcher
		if type(launcher) == "table" and launcher.label and launcher.open and extension.key ~= "auction" then
			-- (launcher.attention(): true when something waits there, the word then pulses)
			list[#list + 1] = { key = "ext:" .. extension.key, label = launcher.label, run = function() launcher.open() end,
				attention = type(launcher.attention) == "function" and launcher.attention or nil }
		end
	end
	-- The other addons' icons, in their drawer under the word; none: no word.
	if ns.CountIcons and ns.CountIcons() > 0 then
		list[#list + 1] = { key = "others", label = L.BAR_OTHERS, arrow = true,
			run = function(self) ns.ToggleIconDrawer(self, true) end }
	end
	return list
end

-- Faint at rest, clear while the mouse is on it.
local function Near(on) bar:SetAlpha(on and NEAR or REST) end

local function Color(item, hovered)
	local c = (hovered or item.entry.gold) and C.gold or C.label
	item.text:SetTextColor(c[1], c[2], c[3])
	item.line:SetShown(hovered and true or false)
end

local function Enter(self)
	Near(true)
	Color(self, true)
	if not self.entry.hint then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, -4)
	GameTooltip:AddLine(self.entry.hint, 1, 0.82, 0)
	GameTooltip:Show()
end

local function Leave(self)
	GameTooltip:Hide()
	Color(self, false)
	if not next(pulsing) then Near(false) end
end

-- A word of the bar: its text, its count in gold, the fine line under it on hover.
local function Item(index)
	local item = items[index]
	if item then return item end
	item = CreateFrame("Button", nil, bar)
	item:SetHeight(HEIGHT)
	item:RegisterForClicks("AnyUp")
	item.text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	item.text:SetPoint("LEFT", item, "LEFT", 0, 0)
	item.count = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	item.count:SetPoint("LEFT", item.text, "RIGHT", 4, 0)
	item.count:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
	item.line = item:CreateTexture(nil, "OVERLAY")
	item.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.8)
	item.line:SetHeight(1)
	item.line:SetPoint("TOPLEFT", item.text, "BOTTOMLEFT", 0, -3)
	item.line:SetPoint("TOPRIGHT", item.text, "BOTTOMRIGHT", 0, -3)
	-- (a list: a small arrow after its word)
	item.arrow = item:CreateTexture(nil, "OVERLAY")
	item.arrow:SetSize(12, 12)
	item.arrow:SetPoint("LEFT", item.text, "RIGHT", 3, -1)
	item.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	item.arrow:Hide()
	item.line:Hide()
	item:SetScript("OnClick", function(self, mouse)
		GameTooltip:Hide()
		PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 857)
		if mouse == "RightButton" and self.entry.right then return self.entry.right(self) end
		self.entry.run(self)
	end)
	item:SetScript("OnEnter", Enter)
	item:SetScript("OnLeave", Leave)
	items[index] = item
	return item
end

local function Dot(index)
	local dot = dots[index]
	if dot then return dot end
	dot = bar:CreateTexture(nil, "OVERLAY")
	dot:SetSize(3, 3)
	dot:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.45)
	dots[index] = dot
	return dot
end

-- Each word as wide as its text and its count; the band as long as them all.
local function Layout()
	local x = PAD
	local shown = 0
	for index, item in ipairs(items) do
		if item:IsShown() then
			shown = shown + 1
			if shown > 1 then
				local dot = Dot(shown - 1)
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", bar, "LEFT", x + SPACE, 0)
				dot:Show()
				x = x + SPACE * 2
			end
			local width = U.Measure(item.text, "GetStringWidth", 40)
			local count = item.count:GetText()
			if count and count ~= "" then width = width + 4 + U.Measure(item.count, "GetStringWidth", 8) end
			if item.entry.arrow then width = width + 15 end
			item:SetWidth(width)
			item:ClearAllPoints()
			item:SetPoint("LEFT", bar, "LEFT", x, 0)
			x = x + width
		end
		item.index = index
	end
	for index = math.max(shown, 1), #dots do dots[index]:Hide() end
	bar:SetWidth(x + PAD * 3)
end

-- Something waits behind a word (an extension says so): it pulses, gold, the bar in full while it does.
local pulse = 0
local step = 0
local function Pulse(_, elapsed)
	pulse, step = pulse + elapsed, step + elapsed
	if step < 0.05 then return end
	step = 0
	local glow = 0.55 + 0.45 * math.sin(pulse * 4)
	for item in pairs(pulsing) do
		item.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
		item.text:SetAlpha(glow)
		item.line:Show()
		item.line:SetAlpha(glow)
	end
end

local function Attention()
	local any = false
	for _, item in ipairs(items) do
		local wants = item:IsShown() and item.entry and item.entry.attention and select(2, pcall(item.entry.attention)) == true
		if wants then
			pulsing[item], any = true, true
		elseif pulsing[item] then
			pulsing[item] = nil
			item.text:SetAlpha(1)
			item.line:SetAlpha(0.8)
			Color(item, false)
		end
	end
	bar:SetScript("OnUpdate", any and Pulse or nil)
	if any then bar:SetAlpha(NEAR) elseif not (bar.IsMouseOver and bar:IsMouseOver()) then Near(false) end
end

-- The counts beside the words, and what waits behind them.
local function Marks()
	Attention()
	local changed = false
	for _, item in ipairs(items) do
		if item:IsShown() then
			local key = item.entry.key
			local count = key == "todo" and ns.TodoPending and ns.TodoPending() or 0
			local text = count > 0 and tostring(count) or ""
			if item.count:GetText() ~= text then
				item.count:SetText(text)
				changed = true
			end
		end
	end
	if changed then Layout() end
end

function ns.RefreshBar()
	if not bar then return end
	local shown = ns.BarActive()
	bar:SetShown(shown)
	if not shown then return end
	local list = Entries()
	for index, entry in ipairs(list) do
		local item = Item(index)
		item.entry = entry
		item.text:SetText(U.Upper(entry.label))
		item.arrow:SetShown(entry.arrow and true or false)
		Color(item, false)
		item:Show()
	end
	for index = #list + 1, #items do items[index]:Hide() end
	Layout()
	Marks()
end

function ns.SetBarShown(shown)
	ns.db.world.bar = shown and true or false
	ns.RefreshMinimapButton()
	if ns.RefreshIcons then ns.RefreshIcons() end
end

-- The bar is on the screen (then it takes the minimap button's place).
function ns.BarActive() return ns.db.enabled and ns.db.world.bar and true or false end

function ns.IsBarShown() return ns.db.world.bar and true or false end

function ns.InitBar()
	C = ns.Skin.COLORS
	bar = CreateFrame("Frame", "WandererBar", UIParent)
	bar:SetHeight(HEIGHT)
	bar:SetFrameStrata("MEDIUM")
	-- (against the top of the screen, from its left edge)
	bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	-- The band: dark, fading out to the right; a thin golden rule under it, fading the same way.
	local ground = bar:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(1, 1, 1, 1)
	local rule = bar:CreateTexture(nil, "BORDER")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(1, 1, 1, 1)
	if CreateColor and ground.SetGradient then
		ground:SetGradient("HORIZONTAL", CreateColor(0.03, 0.03, 0.04, 0.78), CreateColor(0.03, 0.03, 0.04, 0))
		rule:SetGradient("HORIZONTAL", CreateColor(C.gold[1], C.gold[2], C.gold[3], 0.5), CreateColor(C.gold[1], C.gold[2], C.gold[3], 0))
	else
		ground:SetColorTexture(0.03, 0.03, 0.04, 0.6)
		rule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.25)
	end
	Near(false)
	-- (the extensions register as they load: the bar made once they are all there, its counts kept fresh)
	C_Timer.After(1, ns.RefreshBar)
	if C_Timer.NewTicker then C_Timer.NewTicker(2, function() if bar:IsShown() then Marks() end end) end
end
