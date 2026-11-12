local _, ns = ...
local L = ns.L
local U = ns.Util

-- Wanderer's bar (option): a quiet line against the top left of the screen, in Wanderer's own hand: words
-- in small capitals on a dark band fading out to the right, a thin golden rule under it. A word turns gold
-- with a fine line under it when the mouse is on it, a small card under it saying what waits there (the
-- launcher's summary); a count in gold beside it (reminders left, an extension's count). Wanderer's card,
-- the reminders, the extensions' windows, and the other addons' icons (those around the minimap, gathered)
-- in a list under "Other addons", only when there are some. Faint until the mouse comes near.

local HEIGHT = 34
local PAD = 12 -- the band's ends
local SPACE = 9 -- around each dot between the words
local REST, NEAR = 0.6, 1

local bar
local items, dots = {}, {}
local pulsing = {} -- words whose extension says something waits there
local C -- Wanderer's colors (Kit.lua's, read once the bar is made)

-- The extensions' words on the bar: a few by default (the ones used every day), the others in "More" (its card:
-- each window with its icon, its count, a star to pin it on the bar). Pinned or not: this profile's choice.
local DEFAULT_PINS = { quests = true, maps = true, chat = true }
local function Pinned(key)
	local pins = ns.db.world.barPins
	if type(pins) == "table" and pins[key] ~= nil then return pins[key] and true or false end
	return DEFAULT_PINS[key] or false
end
ns.BarPinned = Pinned

function ns.SetBarPin(key, on)
	if type(ns.db.world.barPins) ~= "table" then ns.db.world.barPins = {} end
	ns.db.world.barPins[key] = on and true or false
	ns.RefreshBar()
	if ns.RefreshBarMore then ns.RefreshBarMore() end
end

-- An extension's icon: its addon's own (its toc).
local function IconOf(extension)
	local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local icon = meta and extension.addon and U.Clean(U.Safe(meta, extension.addon, "IconTexture"))
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- The extensions' windows (not the shopping list: it stays in the menu): { key, label, icon, open, attention, count,
-- summary }, in their order.
local function Windows()
	local list = {}
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		local launcher = ns.LauncherOf(extension)
		if launcher and extension.key ~= "auction" then
			list[#list + 1] = { key = extension.key, label = launcher.label, icon = IconOf(extension), open = launcher.open,
				attention = launcher.attention, count = function() return ns.LauncherCount(launcher) end,
				summary = function() return ns.LauncherSummary(launcher) end }
		end
	end
	return list
end
ns.BarWindows = Windows

local function Safely(fn, fallback)
	if not fn then return fallback end
	local ok, value = pcall(fn)
	if ok and value ~= nil then return value end
	return fallback
end

-- What the bar offers, as things stand: { key, label, hint, hintPad (said under a controller), run, right,
-- rightWord (the controller's top button doing the right click) }.
local function Entries()
	local list = {
		{ key = "menu", label = "Wanderer", hint = L.BAR_MENU_HINT, hintPad = L.BAR_MENU_HINT_PAD, gold = true,
			run = function(self) ns.ShowMenu(self) end, right = function() ns.OpenOptions() end, rightWord = "OPTIONS" },
		{ key = "todo", label = L.TODO_TITLE, run = function() ns.ToggleTodo() end,
			summary = function() return ns.TodoLines() end },
	}
	-- The extensions' windows pinned (a right click takes one off), the others in "More".
	-- (attention(): true when something waits there, the word then pulses; count: a number beside the word;
	-- summary: what its hover card says)
	local more = {}
	for _, window in ipairs(Windows()) do
		if Pinned(window.key) then
			list[#list + 1] = { key = "ext:" .. window.key, label = window.label, run = function() window.open() end,
				attention = window.attention, count = window.count, summary = window.summary, hint = L.BAR_PINNED_HINT,
				hintPad = L.BAR_PINNED_HINT_PAD, right = function() ns.SetBarPin(window.key, false) end, rightWord = "UNPIN" }
		else
			more[#more + 1] = window
		end
	end
	if more[1] then
		list[#list + 1] = { key = "more", label = L.BAR_MORE, arrow = true, hint = L.BAR_MORE_HINT,
			run = function(self) ns.ToggleBarMore(self) end,
			-- (what waits behind it: the sum of their counts, a pulse when one of them asks)
			count = function()
				local sum = 0
				for _, window in ipairs(more) do sum = sum + (Safely(window.count, 0) or 0) end
				return sum
			end,
			attention = function()
				for _, window in ipairs(more) do if Safely(window.attention, false) == true then return true end end
				return false
			end,
			summary = function()
				local lines = {}
				for _, window in ipairs(more) do
					local count = Safely(window.count, 0) or 0
					if count > 0 and #lines < 3 then lines[#lines + 1] = { text = window.label .. "  " .. count, role = "text" } end
				end
				return lines
			end }
	end
	-- The other addons' icons, in their drawer under the word; none: no word.
	if ns.CountIcons() > 0 then
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

-- The small card under a word: its name in gold, what waits there (up to 3 lines), what a click does.
local hoverCard
local HOVER_WIDTH = 240
local function ShowHover(item)
	local entry = item.entry
	local lines = {}
	if entry.summary then
		local ok, made = pcall(entry.summary)
		for _, line in ipairs(ok and type(made) == "table" and made or {}) do
			if type(line) == "table" and type(line.text) == "string" and #lines < 3 then lines[#lines + 1] = line end
		end
	end
	local Skin = ns.Skin
	if not hoverCard then
		hoverCard = Skin.CreateWindow("WandererBarHover", "DIALOG")
		hoverCard:EnableMouse(false)
		hoverCard.title = Skin.CreateText(hoverCard, "GameTooltipHeaderText", C.gold[1], C.gold[2], C.gold[3])
		hoverCard.lines = {}
		hoverCard.hint = Skin.Text(hoverCard, "GameTooltipTextSmall", "muted")
	end
	local card, m = hoverCard, 10
	card:SetScale(Skin.Scale())
	card.title:SetText(entry.key == "menu" and L.ADDON_TITLE or entry.label)
	card.title:ClearAllPoints()
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", m, -m)
	local y = m + U.Measure(card.title, "GetStringHeight", 14) + 4
	for index, line in ipairs(lines) do
		local text = card.lines[index] or Skin.Text(card, "GameTooltipText", "text")
		card.lines[index] = text
		text:SetWidth(HOVER_WIDTH - m * 2)
		text:SetText(Skin.Colorize(line.text, line.role or "text"))
		text:ClearAllPoints()
		text:SetPoint("TOPLEFT", card, "TOPLEFT", m, -y)
		text:Show()
		y = y + U.Measure(text, "GetStringHeight", 14) + 3
	end
	for index = #lines + 1, #card.lines do card.lines[index]:Hide() end
	card.hint:SetWidth(HOVER_WIDTH - m * 2)
	local hint = entry.hintPad and U.UsingPad and U.UsingPad() and entry.hintPad or entry.hint
	card.hint:SetText(hint or L.BAR_CLICK_OPEN)
	card.hint:ClearAllPoints()
	card.hint:SetPoint("TOPLEFT", card, "TOPLEFT", m, -(y + 3))
	y = y + 3 + U.Measure(card.hint, "GetStringHeight", 12)
	card:SetSize(HOVER_WIDTH, y + m)
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", item, "BOTTOMLEFT", -4, -4)
	Skin.Get(card):Layout()
	card:Show()
end

local function HideHover()
	if hoverCard then hoverCard:Hide() end
end

local function Enter(self)
	Near(true)
	Color(self, true)
	ShowHover(self)
end

local function Leave(self)
	HideHover()
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
	item.text = ns.Skin.CreateText(item, "GameFontNormalSmall")
	item.text:SetPoint("LEFT", item, "LEFT", 0, 0)
	item.count = ns.Skin.CreateText(item, "GameFontNormalSmall")
	item.count:SetPoint("LEFT", item.text, "RIGHT", 4, 0)
	item.count:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
	item.line = item:CreateTexture(nil, "OVERLAY")
	item.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.8)
	item.line:SetHeight(1)
	item.line:SetPoint("TOPLEFT", item.text, "BOTTOMLEFT", 0, -3)
	item.line:SetPoint("TOPRIGHT", item.text, "BOTTOMRIGHT", 0, -3)
	-- (a list: a small arrow after its word)
	item.arrow = ns.Skin.Glyph(item, "down", 9, "OVERLAY")
	item.arrow:SetPoint("LEFT", item.text, "RIGHT", 4, 0)
	item.arrow:Hide()
	item.line:Hide()
	item:SetScript("OnClick", function(self, mouse)
		HideHover()
		ns.Skin.Play("confirm")
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
local CREST = 16
local function Layout()
	-- (the crest, once: Wanderer's sign at the head of the line, as on the minimap)
	if not bar.crest then
		bar.crest = bar:CreateTexture(nil, "ARTWORK")
		bar.crest:SetSize(CREST, CREST)
		bar.crest:SetPoint("LEFT", bar, "LEFT", PAD - 2, 0)
		bar.crest:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
		if not ns.Skin.RoundMask(bar, bar.crest) then bar.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		bar.crest:SetAlpha(0.9)
	end
	local x = PAD + CREST + 6
	local shown = 0
	for _, item in ipairs(items) do
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
	local glow = 0.65 + 0.3 * math.sin(pulse * 3)
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
	if any then bar:SetAlpha(NEAR) elseif not U.Hovered(bar) then Near(false) end
end

-- The counts beside the words, and what waits behind them.
local function Marks()
	Attention()
	local changed = false
	for _, item in ipairs(items) do
		if item:IsShown() then
			local key = item.entry.key
			local count = key == "todo" and ns.TodoPending() or (item.entry.count and item.entry.count()) or 0
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
		-- (its right click, the controller's top button)
		item.padRight, item.padRightWord = entry.right and true or nil, entry.rightWord
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
	ns.RefreshIcons()
end

-- The bar is on the screen (then it takes the minimap button's place).
function ns.BarActive() return ns.db.enabled and ns.db.world.bar and true or false end

function ns.InitBar()
	C = ns.Skin.COLORS
	bar = CreateFrame("Frame", "WandererBar", UIParent)
	bar:SetHeight(HEIGHT)
	bar:SetFrameStrata("MEDIUM")
	-- (against the top of the screen, from its left edge; or where you put it: Place.lua)
	ns.Placeable({ key = "bar", label = function() return L.BAR_SHOW end, frame = bar, size = { 420, HEIGHT },
		default = { "TOPLEFT", "TOPLEFT", 0, 0 }, enabled = function() return ns.BarActive() end })
	ns.PlaceApply("bar", bar)
	-- The band: dark, fading out to the right; a thin golden rule under it, fading the same way.
	local ground = bar:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ns.Skin.FadingRule(ground, 0.78, false, { 0.03, 0.03, 0.04 })
	local rule = bar:CreateTexture(nil, "BORDER")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)
	ns.Skin.FadingRule(rule, 0.5)
	Near(false)
	-- (the extensions register as they load: the bar made once they are all there, its counts kept fresh)
	C_Timer.After(1, ns.RefreshBar)
	-- (never in a fight: the counts wait for its end)
	C_Timer.NewTicker(2, function() if bar:IsShown() and not InCombatLockdown() then Marks() end end)
end
