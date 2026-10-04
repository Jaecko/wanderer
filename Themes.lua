local _, ns = ...
local L = ns.L

-- Predefined styles: one click sets the whole look of the label and the
-- tooltips (frame, font, opacity, spacing). The first page of the options
-- shows them as cards, each with a real preview drawn by the shared engine.

ns.THEMES = {
	{ key = "blizzard", style = "blizzard", font = "default", bgOpacity = 55, padding = 8 },
	{ key = "classic", style = "classic", font = "friz", bgOpacity = 90, padding = 8 },
	{ key = "royal", style = "royal", font = "morpheus", bgOpacity = 90, padding = 10 },
	{ key = "parchment", style = "parchment", font = "morpheus", bgOpacity = 85, padding = 10 },
	{ key = "frame", style = "frame", font = "default", bgOpacity = 75, padding = 8 },
	{ key = "minimal", style = "minimal", font = "arialn", bgOpacity = 55, padding = 4 },
}
local FIELDS = { "style", "font", "bgOpacity", "padding" }

function ns.ApplyTheme(key)
	for _, theme in ipairs(ns.THEMES) do
		if theme.key == key then
			for _, field in ipairs(FIELDS) do ns.db.label[field] = theme[field] end
			ns.RefreshAll()
			return true
		end
	end
	return false
end

-- The predefined style the current settings match, or nil (customized).
function ns.CurrentTheme()
	for _, theme in ipairs(ns.THEMES) do
		local same = true
		for _, field in ipairs(FIELDS) do
			if ns.db.label[field] ~= theme[field] then same = false break end
		end
		if same then return theme.key end
	end
end

-- Grid of cards ----------------------------------------------------------------------
-- Shared by the options page and the welcome screen: every grid stays in sync.

local GAP = 12
local PREVIEW_INSET = 8
local MIN_FONT_SIZE = 7
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"

local grids = {}
local GridMixin = {}

function GridMixin:Refresh()
	local currentKey = ns.CurrentTheme()
	for _, card in ipairs(self.cards) do
		local selected = card.theme.key == currentKey
		-- The chosen style: golden card and title, with a check mark.
		if selected then
			card.background:SetColorTexture(1, 0.82, 0, 0.16)
			card.title:SetTextColor(1, 0.82, 0)
		else
			card.background:SetColorTexture(1, 1, 1, 0.04)
			card.title:SetTextColor(0.9, 0.9, 0.9)
		end
		card.check:SetShown(selected)
	end
	if self.onRefresh then self.onRefresh(currentKey) end
end

local function RefreshGrids()
	for _, grid in ipairs(grids) do grid:Refresh() end
end
ns.RefreshThemeGrids = RefreshGrids

-- Each text of a preview at its size, made smaller until it fits the width.
local function FitTexts(card, width)
	local available = width - 2 * PREVIEW_INSET - 2 * card.margin
	for _, text in ipairs(card.texts) do
		local size = text.size
		repeat
			if card.font then text:SetFont(card.font, size, "") end
			size = size - 1
		until size < MIN_FONT_SIZE or ns.Util.Measure(text, "GetStringWidth", 0) <= available
		text:SetWidth(available) -- never beyond the frame, even in the smallest size
	end
end

-- Cards below the anchor, in a grid as wide as the given width.
function GridMixin:Layout(anchor, width, offsetY)
	if not width or width <= 0 then return end
	local columns = self.columns
	local cardWidth = math.floor((width - (columns - 1) * GAP) / columns)
	for _, card in ipairs(self.cards) do
		local column, row = (card.index - 1) % columns, math.floor((card.index - 1) / columns)
		card:SetWidth(cardWidth)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", column * (cardWidth + GAP), -offsetY - row * (self.cardHeight + GAP))
		FitTexts(card, cardWidth)
		ns.Skin.Get(card.preview):Layout()
	end
end

function GridMixin:Height()
	local rows = math.ceil(#self.cards / self.columns)
	return rows * self.cardHeight + (rows - 1) * GAP
end

-- A small label as it would appear in the world, in the theme's look.
local function CreatePreview(card, theme, height)
	local preview, skin = ns.Skin.CreateWindow(nil, nil, card)
	preview:SetPoint("TOPLEFT", card, "TOPLEFT", PREVIEW_INSET, -PREVIEW_INSET)
	preview:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PREVIEW_INSET, -PREVIEW_INSET)
	preview:SetHeight(height)
	preview:EnableMouse(false)
	local font = ns.Skin.FontPath(theme.font)
	local margin = 6 + math.floor(theme.padding / 2)
	card.preview, card.font, card.margin, card.texts = preview, font, margin, {}
	local lines = {
		{ L.THEME_SAMPLE_NAME, 13, 1, 0.82, 0 },
		{ L.THEME_SAMPLE_ROLE, 11, 0.82, 0.75, 0.56 },
		{ L.THEME_SAMPLE_DETAIL, 10, 0.8, 0.8, 0.8 },
	}
	local previous
	for _, line in ipairs(lines) do
		local text = ns.Skin.CreateText(preview, "GameTooltipText", line[3], line[4], line[5])
		if text.SetWordWrap then text:SetWordWrap(false) end
		text.size = line[2]
		text:SetText(line[1])
		card.texts[#card.texts + 1] = text
		if previous then
			text:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
		else
			text:SetPoint("TOPLEFT", preview, "TOPLEFT", margin, -margin)
		end
		previous = text
	end
	skin:SetFixedStyle(theme.style, theme.bgOpacity)
	skin:Layout()
	preview:Show()
end

local function CreateCard(grid, index, theme)
	local card = CreateFrame("Button", nil, grid.parent)
	card:SetHeight(grid.cardHeight)
	card.index, card.theme = index, theme
	card.background = card:CreateTexture(nil, "BACKGROUND")
	card.background:SetAllPoints()
	card.hover = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, 0.06)
	card.hover:Hide()
	CreatePreview(card, theme, grid.cardHeight - 50)
	card.check = card:CreateTexture(nil, "OVERLAY")
	card.check:SetSize(20, 20)
	card.check:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 6)
	card.check:SetTexture(CHECK_TEXTURE)
	-- The name stays between the left edge and the check mark.
	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.title:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 10)
	card.title:SetPoint("RIGHT", card.check, "LEFT", -4, 0)
	card.title:SetJustifyH("LEFT")
	if card.title.SetWordWrap then card.title:SetWordWrap(false) end
	card.title:SetText(L["STYLE_" .. theme.key:upper()])
	card:SetScript("OnClick", function()
		ns.ApplyTheme(theme.key)
		if not grid.quiet then ns.Print(L.MSG_THEME:format(L["STYLE_" .. theme.key:upper()])) end
		RefreshGrids()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
			pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
	end)
	card:SetScript("OnEnter", function(self)
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["STYLE_" .. theme.key:upper()])
		GameTooltip:AddLine(L["THEME_DESC_" .. theme.key:upper()], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	grid.cards[#grid.cards + 1] = card
end

-- options: columns, cardHeight, quiet (no chat message), onRefresh(currentKey).
function ns.CreateThemeGrid(parent, options)
	local grid = setmetatable({
		parent = parent, cards = {},
		columns = options.columns or 3, cardHeight = options.cardHeight or 124,
		quiet = options.quiet, onRefresh = options.onRefresh,
	}, { __index = GridMixin })
	for index, theme in ipairs(ns.THEMES) do CreateCard(grid, index, theme) end
	grids[#grids + 1] = grid
	return grid
end

-- Options page -----------------------------------------------------------------------

local PAGE_MARGIN = 16

-- Registers the page under the options' home page (first of the folded pages).
function ns.RegisterThemesPage(parentCategory)
	if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return end
	local page = CreateFrame("Frame")
	page.title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	page.title:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_MARGIN, -PAGE_MARGIN)
	page.title:SetText(L.PAGE_THEMES)
	page.description = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	page.description:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -8)
	page.description:SetPoint("RIGHT", page, "RIGHT", -PAGE_MARGIN, 0)
	page.description:SetJustifyH("LEFT")
	page.description:SetText(L.THEMES_DESC)
	page.custom = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	page.custom:SetJustifyH("LEFT")
	page.custom:SetText(L.THEMES_CUSTOM)
	local grid = ns.CreateThemeGrid(page, {
		onRefresh = function(currentKey) page.custom:SetShown(currentKey == nil) end,
	})
	page.custom:SetPoint("TOPLEFT", page.description, "BOTTOMLEFT", 0, -16 - grid:Height() - 12)
	page.custom:SetPoint("RIGHT", page, "RIGHT", -PAGE_MARGIN, 0)
	local function Layout()
		local width = page:GetWidth()
		if width and width > 0 then grid:Layout(page.description, width - 2 * PAGE_MARGIN, 16) end
	end
	page:SetScript("OnSizeChanged", Layout)
	page:SetScript("OnShow", function()
		Layout()
		grid:Refresh()
	end)
	Settings.RegisterCanvasLayoutSubcategory(parentCategory, page, L.PAGE_THEMES)
	grid:Refresh()
end
