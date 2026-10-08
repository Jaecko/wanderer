local _, ns = ...
local L = ns.L

-- Welcome screen: shown once, on the first arrival in the world with Wanderer,
-- a few steps to make it yours: the look, the way you play, a quieter
-- interface, the chat tabs, and what is worth knowing. One step at a time,
-- with Back, Next and Skip. Reopened with /wanderer welcome or from the options.

local U = ns.Util

local WIDTH, HEIGHT = 620, 510
local SCREEN_SHARE = 0.94 -- never taller than this share of the screen
local CREST_SIZE = 44
local CARD_HEIGHT, CARD_GAP = 64, 10
local ROW_HEIGHT = 46
local CHIP_HEIGHT, CHIP_GAP = 28, 8
local DOT_SIZE, DOT_GAP = 8, 8
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local SHOW_DELAY = 2 -- seconds after arriving, once the screen has settled
local STEPS = { "intro", "look", "play", "interface", "chat", "ready" }
local PLAYSTYLE_ORDER = { "immersion", "adventurer", "roleplay", "dungeons" }
local HIGHLIGHTS = {
	{ "Interface\\CURSOR\\Point", "WELCOME_HIGHLIGHT_NAMES" },
	{ "Interface\\Icons\\INV_Misc_Note_06", "WELCOME_HIGHLIGHT_SCENES" },
	{ "Interface\\Icons\\INV_Misc_Book_09", "WELCOME_HIGHLIGHT_JOURNAL" },
}
-- The quieter interface: options from several pages, gathered for the start.
local INTERFACE = {
	{ "world.cleanMinimap", "CLEAN_MINIMAP" },
	{ "world.cleanTracker", "CLEAN_TRACKER" },
	{ "world.gatherIcons", "GATHER_ICONS" },
	{ "cinema.enabled", "CINEMA_ENABLE" },
	{ "travel.enabled", "TRAVEL_ENABLE" },
	{ "scene.enabled", "SCENE_ENABLE" },
}
local TIPS = {
	{ "Interface\\CURSOR\\Point", "WELCOME_TIP_HOVER" },
	{ "Interface\\Icons\\INV_Misc_Spyglass_02", "WELCOME_TIP_REVEAL" },
	{ "Interface\\Icons\\INV_Misc_Book_09", "WELCOME_TIP_MINIMAP" },
	{ "Interface\\Icons\\INV_Misc_Note_01", "WELCOME_TIP_COMMAND" },
}

-- Ways to play: each one sets the same whole set of options (names, scenes,
-- the interface fading, the ambiance while away, quest automations, gestures),
-- so going from one to another never leaves something of the first behind.
-- Merchants, loot, the label's content and the journal are everyone's: left
-- as they are. Everything stays free to change afterwards.
local function Way(preset, values)
	local all = {
		["combatEnemies"] = false, ["label.stickyTarget"] = true, ["enemyNames"] = "names", ["nearNames.show"] = "bar", ["zones.dungeon"] = "group", ["zones.raid"] = "group",
		["scene.enabled"] = true, ["scene.camera"] = true,
		["cinema.enabled"] = false, ["cinema.combatOnly"] = true, ["cinema.alpha"] = 20,
		["travel.enabled"] = true, ["away.enabled"] = false,
		["world.cleanMinimap"] = false, ["world.cleanTracker"] = false, ["world.gatherIcons"] = false,
		["quest.autoAccept"] = false, ["quest.autoTurnIn"] = false, ["quest.skipGossip"] = false,
		["gestures.read"] = false, ["gestures.levelUp"] = false, ["gestures.greet"] = false,
	}
	for path, value in pairs(values) do all[path] = value end
	return { preset = preset, values = all }
end

ns.PLAYSTYLES = {
	-- No names, face to face, an interface that steps aside, an ambiance while away.
	immersion = Way("immersion", {
		["enemyNames"] = "near",
		["cinema.enabled"] = true, ["away.enabled"] = true, ["away.style"] = "contemplation",
		["world.cleanMinimap"] = true, ["world.cleanTracker"] = true, ["world.gatherIcons"] = true }),
	-- Enemies named, quests without delay, the whole interface at hand.
	adventurer = Way("balanced", {
		["scene.enabled"] = false, ["scene.camera"] = false, ["cinema.combatOnly"] = false,
		["quest.autoAccept"] = true, ["quest.autoTurnIn"] = true, ["quest.skipGossip"] = true,
		["merchant.sellJunk"] = true, ["merchant.repair"] = true, ["loot.fast"] = true }),
	-- No names, quiet scenes, a character who lives, resting by the fire while away.
	roleplay = Way("immersion", {
		["enemyNames"] = "near", ["nearNames.show"] = "name",
		["cinema.enabled"] = true, ["away.enabled"] = true, ["away.style"] = "hearth",
		["world.cleanMinimap"] = true, ["world.cleanTracker"] = true, ["world.gatherIcons"] = true,
		["gestures.read"] = true, ["gestures.levelUp"] = true, ["gestures.greet"] = true }),
	-- Companions named and their health bars in dungeons and raids, the whole
	-- interface, threat at a glance.
	dungeons = Way("balanced", {
		["cinema.combatOnly"] = false,
		["scene.camera"] = false, ["threat.show"] = true, ["threat.alert"] = true }),
}

local function Path(path)
	return path:match("^(%w+)%.(%w+)$")
end

function ns.ApplyPlaystyle(key)
	local style = ns.PLAYSTYLES[key]
	if not style then return end
	for path, value in pairs(style.values) do
		local section, field = Path(path)
		if section then ns.db[section][field] = value else ns.db[path] = value end
	end
	ns.db.enabled = true
	ns.SetPreset(style.preset) -- refreshes every module
	if ns.RefreshOptions then ns.RefreshOptions() end
end

local window
local pages, dots = {}, {}
local current = 1
local chosenStyle
local refreshers = {} -- one per page, run when it shows

local function Sound()
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
		pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

-- Pieces --------------------------------------------------------------------------------

-- A choice card: background, golden when chosen, title and up to two lines.
local function Card(parent, title, text, height)
	local card = CreateFrame("Button", nil, parent)
	card:SetHeight(height)
	card.background = card:CreateTexture(nil, "BACKGROUND")
	card.background:SetAllPoints()
	card.hover = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, 0.06)
	card.hover:Hide()
	card.check = card:CreateTexture(nil, "OVERLAY")
	card.check:SetSize(18, 18)
	card.check:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
	card.check:SetTexture(CHECK)
	card.title = ns.Skin.CreateText(card, "GameTooltipText")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
	card.title:SetPoint("RIGHT", card.check, "LEFT", -4, 0)
	if card.title.SetWordWrap then card.title:SetWordWrap(false) end
	card.title:SetText(title)
	card.text = ns.Skin.CreateText(card, "GameTooltipTextSmall", 0.78, 0.78, 0.78)
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.text:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 6)
	card.text:SetJustifyV("TOP")
	if card.text.SetMaxLines then card.text:SetMaxLines(2) end
	card.text:SetText(text)
	card:SetScript("OnEnter", function(self) self.hover:Show() end)
	card:SetScript("OnLeave", function(self) self.hover:Hide() end)
	function card:SetChosen(chosen)
		if chosen then
			self.background:SetColorTexture(1, 0.82, 0, 0.16)
			self.title:SetTextColor(1, 0.82, 0)
		else
			self.background:SetColorTexture(1, 1, 1, 0.04)
			self.title:SetTextColor(0.9, 0.9, 0.9)
		end
		self.check:SetShown(chosen)
	end
	return card
end

-- A line of icon and text.
local function IconLine(parent, icon, text, anchor, offset)
	local texture = parent:CreateTexture(nil, "ARTWORK")
	texture:SetSize(18, 18)
	texture:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -offset)
	texture:SetTexture(icon)
	if texture.SetTexCoord and icon:find("Icons") then texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	local line = ns.Skin.CreateText(parent, "GameTooltipText", 0.9, 0.88, 0.82)
	line:SetPoint("LEFT", texture, "RIGHT", 10, 0)
	line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	if line.SetWordWrap then line:SetWordWrap(false) end
	line:SetText(text)
	return texture
end

-- Each page: a title, a line saying what it is for, its content below.
local function Page(step, titleKey, textKey)
	local page = CreateFrame("Frame", nil, window)
	page:SetPoint("TOPLEFT", window.top, "TOPLEFT", 0, 0)
	page:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -(ns.Skin.Margin() + 8), 56)
	page:Hide()
	page.title = ns.Skin.CreateText(page, "GameTooltipHeaderText", 1, 0.82, 0)
	page.title:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	page.title:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	if page.title.SetWordWrap then page.title:SetWordWrap(false) end
	page.title:SetText(L[titleKey])
	page.text = ns.Skin.CreateText(page, "GameTooltipTextSmall", 0.7, 0.68, 0.62)
	page.text:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)
	page.text:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.text:SetText(textKey and L[textKey] or "")
	page.rule = page:CreateTexture(nil, "ARTWORK")
	page.rule:SetColorTexture(1, 0.82, 0, 0.2)
	page.rule:SetHeight(1)
	page.rule:SetPoint("TOPLEFT", page.text, "BOTTOMLEFT", 0, -8)
	page.rule:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	pages[step] = page
	return page
end

-- Steps ---------------------------------------------------------------------------------

local function IntroPage()
	local page = Page("intro", "WELCOME_TITLE")
	page.title:SetFontObject("GameFontNormalHuge")
	page.title:SetTextColor(1, 0.82, 0)
	page.text:SetFontObject("GameTooltipText")
	page.text:SetTextColor(0.9, 0.88, 0.8)
	page.text:SetText(L.WELCOME_INTRO)
	local previous = page.rule
	for index, line in ipairs(HIGHLIGHTS) do
		previous = IconLine(page, line[1], L[line[2]], previous, index == 1 and 18 or 12)
	end
end

local function LookPage()
	local page = Page("look", "WELCOME_STEP_LOOK", "WELCOME_LOOK_DESC")
	local grid = ns.CreateThemeGrid(page, { columns = 3, cardHeight = 96, quiet = true })
	refreshers.look = function()
		grid:Layout(page.rule, page:GetWidth() > 0 and page:GetWidth() or WIDTH - 2 * (ns.Skin.Margin() + 8), 12)
		grid:Refresh()
	end
end

local function PlayPage()
	local page = Page("play", "WELCOME_STEP_PLAY", "WELCOME_PLAY_DESC")
	local cards = {}
	for index, key in ipairs(PLAYSTYLE_ORDER) do
		local card = Card(page, L["PLAYSTYLE_" .. key:upper()], L["PLAYSTYLE_" .. key:upper() .. "_DESC"], CARD_HEIGHT)
		card.index = index
		card:SetScript("OnClick", function()
			chosenStyle = key
			ns.ApplyPlaystyle(key)
			if ns.RefreshThemeGrids then ns.RefreshThemeGrids() end
			for _, other in ipairs(cards) do other:SetChosen(other == card) end
			Sound()
		end)
		cards[index] = card
	end
	refreshers.play = function()
		local width = page:GetWidth() > 0 and page:GetWidth() or WIDTH - 2 * (ns.Skin.Margin() + 8)
		local cardWidth = math.floor((width - CARD_GAP) / 2)
		for index, card in ipairs(cards) do
			local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
			card:SetWidth(cardWidth)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", column * (cardWidth + CARD_GAP), -12 - row * (CARD_HEIGHT + CARD_GAP))
			card:SetChosen(chosenStyle == PLAYSTYLE_ORDER[index])
		end
	end
end

-- A switch: a quiet row, checked when on.
local function SwitchRow(page, path, key, previous)
	local section, field = Path(path)
	local row = CreateFrame("Button", nil, page)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == page.rule and -10 or -4)
	row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.hover:Hide()
	row.box = row:CreateTexture(nil, "ARTWORK")
	row.box:SetSize(16, 16)
	row.box:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -6)
	row.box:SetColorTexture(0, 0, 0, 0.5)
	row.check = row:CreateTexture(nil, "OVERLAY")
	row.check:SetSize(22, 22)
	row.check:SetPoint("CENTER", row.box, "CENTER", 1, 1)
	row.check:SetTexture(CHECK)
	row.title = ns.Skin.CreateText(row, "GameTooltipText")
	row.title:SetPoint("TOPLEFT", row.box, "TOPRIGHT", 10, 1)
	row.title:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.text = ns.Skin.CreateText(row, "GameTooltipTextSmall", 0.7, 0.68, 0.62)
	row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	for _, text in ipairs({ row.title, row.text }) do
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	row.title:SetText(L[key])
	row.text:SetText(L[key .. "_DESC"])
	function row:Refresh()
		local on = ns.db[section][field] and true or false
		self.check:SetShown(on)
		self.title:SetTextColor(on and 1 or 0.85, on and 0.92 or 0.85, on and 0.75 or 0.85)
	end
	row:SetScript("OnClick", function(self)
		ns.db[section][field] = not ns.db[section][field]
		ns.RefreshAll()
		self:Refresh()
		Sound()
	end)
	row:SetScript("OnEnter", function(self)
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L[key])
		GameTooltip:AddLine(L[key .. "_DESC"], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	return row
end

local function InterfacePage()
	local page = Page("interface", "WELCOME_STEP_INTERFACE", "WELCOME_INTERFACE_DESC")
	local rows, previous = {}, page.rule
	for _, entry in ipairs(INTERFACE) do
		previous = SwitchRow(page, entry[1], entry[2], previous)
		rows[#rows + 1] = previous
	end
	refreshers.interface = function()
		for _, row in ipairs(rows) do row:Refresh() end
	end
end

local function ChatPage()
	local page = Page("chat", "WELCOME_STEP_CHAT", "WELCOME_CHAT_DESC")
	local chips, previous = {}, nil
	for _, tab in ipairs(ns.CHAT_TABS) do
		local key = tab.key
		local chip = CreateFrame("Button", nil, page)
		chip:SetHeight(CHIP_HEIGHT)
		chip.background = chip:CreateTexture(nil, "BACKGROUND")
		chip.background:SetAllPoints()
		chip.box = chip:CreateTexture(nil, "ARTWORK")
		chip.box:SetSize(14, 14)
		chip.box:SetPoint("LEFT", chip, "LEFT", 8, 0)
		chip.box:SetColorTexture(0, 0, 0, 0.5)
		chip.check = chip:CreateTexture(nil, "OVERLAY")
		chip.check:SetSize(20, 20)
		chip.check:SetPoint("CENTER", chip.box, "CENTER", 1, 1)
		chip.check:SetTexture(CHECK)
		chip.label = ns.Skin.CreateText(chip, "GameTooltipText")
		chip.label:SetPoint("LEFT", chip.box, "RIGHT", 8, 0)
		if chip.label.SetWordWrap then chip.label:SetWordWrap(false) end
		chip.label:SetText(L["CHAT_TAB_" .. key:upper()])
		chip:SetWidth(U.Measure(chip.label, "GetStringWidth", 70) + 44)
		if previous then
			chip:SetPoint("LEFT", previous, "RIGHT", CHIP_GAP, 0)
		else
			chip:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", 0, -14)
		end
		function chip:Refresh()
			local on = ns.db.chat[key]
			self.check:SetShown(on and true or false)
			self.background:SetColorTexture(1, on and 0.82 or 1, on and 0 or 1, on and 0.12 or 0.04)
			self.label:SetTextColor(on and 1 or 0.7, on and 0.92 or 0.7, on and 0.75 or 0.7)
		end
		chip:SetScript("OnClick", function(self)
			ns.db.chat[key] = not ns.db.chat[key]
			self:Refresh()
			if ns.RefreshOptions then ns.RefreshOptions() end
		end)
		chip:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["CHAT_TAB_" .. key:upper()])
			GameTooltip:AddLine(L["CHAT_TAB_" .. key:upper() .. "_DESC"], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
		chips[#chips + 1] = chip
		previous = chip
	end
	local create = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	create:SetText(L.CHAT_TABS_BUTTON)
	create:SetSize(math.max(160, U.Measure(create:GetFontString() or create, "GetStringWidth", 120) + 30), 26)
	create:SetPoint("TOPLEFT", chips[1], "BOTTOMLEFT", 0, -16)
	create:SetScript("OnClick", function(self)
		local made = ns.CreateChatTabs()
		if made[1] then
			self:SetText(L.CHAT_TABS_DONE)
			self:Disable()
		end
	end)
	local messages = SwitchRow(page, "messages.enabled", "MESSAGES_ENABLE", create)
	messages:ClearAllPoints()
	messages:SetPoint("TOPLEFT", create, "BOTTOMLEFT", 0, -18)
	messages:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	refreshers.chat = function()
		for _, chip in ipairs(chips) do chip:Refresh() end
		messages:Refresh()
	end
end

local function ReadyPage()
	local page = Page("ready", "WELCOME_STEP_READY", "WELCOME_READY_DESC")
	local previous = page.rule
	for index, tip in ipairs(TIPS) do
		previous = IconLine(page, tip[1], L[tip[2]], previous, index == 1 and 16 or 12)
	end
	local options = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	options:SetText(L.WELCOME_OPTIONS)
	options:SetSize(math.max(140, U.Measure(options:GetFontString() or options, "GetStringWidth", 110) + 30), 24)
	options:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -22)
	options:SetScript("OnClick", function()
		window:Hide()
		if ns.OpenOptions then ns.OpenOptions() end
	end)
	local later = ns.Skin.CreateText(page, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	later:SetPoint("LEFT", options, "RIGHT", 12, 0)
	later:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	later:SetText(L.WELCOME_LATER)
end

-- Navigation ----------------------------------------------------------------------------

local function ShowStep(step)
	current = math.max(1, math.min(#STEPS, step))
	for index, key in ipairs(STEPS) do
		pages[key]:SetShown(index == current)
		local done = index <= current
		dots[index]:SetColorTexture(1, done and 0.82 or 1, done and 0 or 1, done and 0.9 or 0.25)
	end
	local refresh = refreshers[STEPS[current]]
	if refresh then refresh() end
	window.back:SetShown(current > 1)
	local last = current == #STEPS
	window.next:SetText(last and L.WELCOME_START or L.WELCOME_NEXT)
	window.skip:SetShown(not last)
	window.counter:SetText(L.WELCOME_STEP_COUNT:format(current, #STEPS))
end

local function Close()
	ns.root.welcomed = true
	window:Hide()
end

local function FooterButton(text, onClick)
	local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(math.max(110, U.Measure(button:GetFontString() or button, "GetStringWidth", 80) + 30), 26)
	button:SetScript("OnClick", onClick)
	return button
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererWelcome", "DIALOG")
	window:SetSize(WIDTH, HEIGHT)
	ns.Skin.Dress(window, nil, nil, Close)
	local margin = ns.Skin.Margin() + 8

	-- The crest and the name, on every step.
	local crest = window:CreateTexture(nil, "ARTWORK")
	crest:SetSize(CREST_SIZE, CREST_SIZE)
	crest:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	crest:SetTexture(ICON)
	local ring = window:CreateTexture(nil, "BORDER")
	ring:SetSize(CREST_SIZE + 4, CREST_SIZE + 4)
	ring:SetPoint("CENTER", crest, "CENTER")
	ring:SetTexture("Interface\\Buttons\\WHITE8X8")
	ring:SetVertexColor(1, 0.82, 0, 0.55)
	ns.Skin.RoundMask(window, crest)
	ring:SetShown(ns.Skin.RoundMask(window, ring))
	local name = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	name:SetPoint("LEFT", crest, "RIGHT", 12, 6)
	name:SetPoint("RIGHT", window, "RIGHT", -40, 0)
	if name.SetWordWrap then name:SetWordWrap(false) end
	name:SetText(L.ADDON_TITLE)
	window.counter = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	window.counter:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	window.counter:SetPoint("RIGHT", window, "RIGHT", -40, 0)
	window.top = CreateFrame("Frame", nil, window)
	window.top:SetSize(1, 1)
	window.top:SetPoint("TOPLEFT", crest, "BOTTOMLEFT", 0, -16)

	IntroPage()
	LookPage()
	PlayPage()
	InterfacePage()
	ChatPage()
	ReadyPage()

	-- Progress dots and the way forward.
	for index in ipairs(STEPS) do
		local dot = window:CreateTexture(nil, "ARTWORK")
		dot:SetSize(DOT_SIZE, DOT_SIZE)
		dot:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin + (index - 1) * (DOT_SIZE + DOT_GAP), margin + 9)
		dots[index] = dot
	end
	window.next = FooterButton(L.WELCOME_NEXT, function()
		if current == #STEPS then Close() else ShowStep(current + 1) end
	end)
	window.next:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	window.back = FooterButton(L.WELCOME_BACK, function() ShowStep(current - 1) end)
	window.back:SetPoint("RIGHT", window.next, "LEFT", -8, 0)
	window.skip = CreateFrame("Button", nil, window)
	window.skip.text = ns.Skin.CreateText(window.skip, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	window.skip.text:SetText(L.WELCOME_SKIP)
	window.skip:SetSize(U.Measure(window.skip.text, "GetStringWidth", 60) + 16, 20)
	window.skip.text:SetPoint("LEFT", window.skip, "LEFT", 0, 0)
	window.skip.text:SetPoint("RIGHT", window.skip, "RIGHT", 0, 0)
	window.skip.text:SetJustifyH("CENTER")
	window.skip:SetPoint("LEFT", dots[#STEPS], "RIGHT", 16, 0)
	window.skip:SetScript("OnClick", Close)
	window.skip:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0) end)
	window.skip:SetScript("OnLeave", function(self) self.text:SetTextColor(0.6, 0.6, 0.6) end)

	window:SetScript("OnHide", function() ns.root.welcomed = true end)
	window:SetScript("OnShow", function(self)
		-- On a small screen (or a large interface scale), the window shrinks to fit.
		local screen = (UIParent:GetHeight() or 768) * SCREEN_SHARE
		self:SetScale(math.min(ns.Skin.Scale(), screen / HEIGHT))
		ShowStep(1)
	end)
	ns.Skin.Get(window):Layout()
end

function ns.ShowWelcome()
	if not ns.root or InCombatLockdown() then return end
	if not window then CreateWindow() end
	if window:IsShown() then ShowStep(1) else window:Show() end
end

function ns.InitWelcome()
	if ns.root.welcomed then return end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- Never over a fight: it waits for the next quiet moment.
	frame:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		if ns.root.welcomed then return end
		C_Timer.After(SHOW_DELAY, function()
			if ns.root.welcomed or (window and window:IsShown()) then return end
			if InCombatLockdown() then
				self:RegisterEvent("PLAYER_REGEN_ENABLED")
			else
				ns.ShowWelcome()
			end
		end)
	end)
end
