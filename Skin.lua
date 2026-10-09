local _, ns = ...

-- The one rendering engine of every Wanderer window: the mouseover label and the
-- game tooltips. It draws the background and border of the chosen style, puts
-- a badge on the top edge (icon or marker), colors and animates the highlights, and shows the red screen
-- edges of the threat alert. Windows only say what to show.
--
-- A style is drawn in one of three ways ("kind"):
--   game     the game's own tooltip frame (its NineSlice)
--   texture  a frame made of the game's classic textures (backdrop)
--   lines    Wanderer's thin lines, cut around the badges

local Skin = {}
ns.Skin = Skin

local BORDER, HIGHLIGHT_BORDER, ALERT_BORDER = 1, 2, 3
local BADGE_SIZE = 26
local BADGE_GAP = 6 -- transparent space between a badge and the cut border
local VIGNETTE_TEXTURE = "Interface\\FullScreenTextures\\LowHealth"
Skin.BADGE_SIZE = BADGE_SIZE

local U = ns.Util

-- Styles ------------------------------------------------------------------------

ns.STYLES = { "blizzard", "classic", "royal", "minimal", "frame", "parchment" }
local STYLES = {
	-- The game's own tooltip frame (silver border, night-blue background).
	blizzard = { kind = "game" },
	-- The tooltip of the original game (vanilla).
	classic = {
		kind = "texture", bg = { 0.06, 0.06, 0.14 }, border = { 1, 1, 1, 1 },
		backdrop = {
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
	},
	-- The golden border of the game's dialog windows, on a dark background.
	royal = {
		kind = "texture", bg = { 1, 1, 1 }, border = { 1, 1, 1, 1 },
		backdrop = {
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = true, tileSize = 32, edgeSize = 20,
			insets = { left = 5, right = 5, top = 5, bottom = 5 },
		},
	},
	minimal = { kind = "lines", bg = { 0, 0, 0 }, border = { 1, 1, 1, 0.85 } },
	frame = { kind = "lines", bg = { 0.05, 0.05, 0.07 }, border = { 0.45, 0.45, 0.5, 1 } },
	parchment = { kind = "lines", bg = { 0.2, 0.14, 0.07 }, border = { 0.7, 0.55, 0.28, 1 } },
}

-- Highlights, each enabled by a setting { section, key }. "quality" takes the
-- color given by the caller (item rarity).
local HIGHLIGHTS = {
	threat = { color = { 1, 0.12, 0.12 }, pulse = 12, option = { "label", "threatAlert" }, border = ALERT_BORDER, alert = true },
	turnin = { color = { 1, 0.82, 0.1 }, pulse = 3, option = { "label", "highlightQuest" }, border = HIGHLIGHT_BORDER },
	giver = { color = { 1, 0.82, 0.1 }, option = { "label", "highlightQuest" }, border = HIGHLIGHT_BORDER },
	action = { color = { 1, 0.78, 0.2 }, pulse = 4, option = { "label", "highlight" }, border = HIGHLIGHT_BORDER },
	objective = { color = { 1, 0.95, 0.35 }, option = { "label", "highlightQuest" }, border = HIGHLIGHT_BORDER },
	interact = { color = { 0.55, 0.82, 1 }, pulse = 3, option = { "label", "highlight" }, border = HIGHLIGHT_BORDER },
	party = { color = { 0.3, 1, 0.4 }, option = { "label", "highlightRelations" }, border = HIGHLIGHT_BORDER },
	guild = { color = { 0.25, 0.65, 1 }, option = { "label", "highlightRelations" }, border = HIGHLIGHT_BORDER },
	friend = { color = { 0.8, 0.5, 1 }, option = { "label", "highlightRelations" }, border = HIGHLIGHT_BORDER },
	boss = { color = { 1, 0.3, 0.9 }, pulse = 2, option = { "label", "highlightRank" }, border = ALERT_BORDER },
	rare = { color = { 0.85, 0.9, 1 }, option = { "label", "highlightRank" }, border = HIGHLIGHT_BORDER },
	elite = { color = { 1, 0.72, 0.15 }, option = { "label", "highlightRank" }, border = HIGHLIGHT_BORDER },
	quality = { option = { "tooltips", "quality" }, border = HIGHLIGHT_BORDER },
}
Skin.HIGHLIGHTS = HIGHLIGHTS

local function CurrentStyle()
	return STYLES[ns.db.label.style] or STYLES.blizzard
end

-- Default colors of the game's tooltips.
local function GameColors()
	local bg, border = TOOLTIP_DEFAULT_BACKGROUND_COLOR, TOOLTIP_DEFAULT_COLOR
	local br, bgc, bb = 0.03, 0.03, 0.08
	if bg and bg.GetRGB then br, bgc, bb = bg:GetRGB() end
	local r, g, b = 1, 1, 1
	if border and border.GetRGB then r, g, b = border:GetRGB() end
	return { br, bgc, bb }, { r, g, b, 1 }
end

-- Background color, opacity and resting border of a style (the chosen one by
-- default). opacity: 0-100, the chosen one by default.
function Skin.GetColors(style, opacity)
	style = style or CurrentStyle()
	opacity = (opacity or ns.db.label.bgOpacity) / 100
	if style.kind == "game" then
		local bg, border = GameColors()
		return bg, opacity, border
	end
	return style.bg, opacity, style.border
end

-- Shared metrics: every window uses the same margins, scale and fonts.
local GAME_MARGIN = 10 -- inner margin of the game's tooltips

-- Extra inner spacing added by Wanderer to the game's own margin.
function Skin.Padding()
	return math.floor((ns.db.label.padding or 8) / 2)
end

-- Total inner margin of a Wanderer window (the game's margin + Wanderer's spacing),
-- and the room always kept at the top for the badge.
function Skin.Margin()
	return GAME_MARGIN + Skin.Padding()
end
Skin.TOP_ROOM = BADGE_SIZE / 2

function Skin.Scale()
	return ns.db.label.scale or 1
end

-- Fonts of the game's tooltips, also used by the label: changing them changes
-- every window at once.
Skin.FONT_OBJECTS = { "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }
ns.FONTS = {
	{ key = "default" },
	{ key = "friz", path = "Fonts\\FRIZQT__.TTF" },
	{ key = "morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ key = "skurri", path = "Fonts\\SKURRI.TTF" },
	{ key = "arialn", path = "Fonts\\ARIALN.TTF" },
}
local originalFonts = {}

local function Original(name)
	local object = _G[name]
	if not (object and object.GetFont) then return end
	originalFonts[name] = originalFonts[name] or { object:GetFont() }
	return object, originalFonts[name]
end

-- File of a font of ns.FONTS, nil for "default" (each object keeps its own).
local function ChosenPath(key)
	for _, font in ipairs(ns.FONTS) do
		if font.key == key then return font.path end
	end
end

-- File of a font of ns.FONTS ("default": the game's own tooltip font).
function Skin.FontPath(key)
	local path = ChosenPath(key)
	if path then return path end
	local _, original = Original("GameTooltipText")
	return original and original[1]
end

function Skin.ApplyFont()
	local path = ChosenPath(ns.db.label.font)
	for _, name in ipairs(Skin.FONT_OBJECTS) do
		local object, original = Original(name)
		if original and original[1] then object:SetFont(path or original[1], original[2], original[3]) end
	end
end

-- Red screen edges, shared by every window --------------------------------------

local vignette
local alertingSkins = {}

local function UpdateVignette(skin, on)
	alertingSkins[skin] = on or nil
	if not vignette then
		vignette = CreateFrame("Frame", "WandererVignette", UIParent)
		vignette:SetAllPoints(UIParent)
		vignette:SetFrameStrata("BACKGROUND")
		vignette:EnableMouse(false)
		if vignette.SetIgnoreParentAlpha then vignette:SetIgnoreParentAlpha(true) end
		local edges = vignette:CreateTexture(nil, "BACKGROUND")
		edges:SetAllPoints()
		edges:SetTexture(VIGNETTE_TEXTURE)
		edges:SetBlendMode("ADD")
		edges:SetVertexColor(1, 0.1, 0.1)
	end
	vignette:SetShown(next(alertingSkins) ~= nil)
end

-- Skin of one window ----------------------------------------------------------------

local SkinMixin = {}
SkinMixin.__index = SkinMixin
local byOwner = setmetatable({}, { __mode = "k" })

-- The skin drawing a given window.
function Skin.Get(owner)
	return byOwner[owner]
end

function Skin.Attach(owner)
	-- A window never gets two skins drawing over each other.
	if byOwner[owner] then return byOwner[owner] end
	-- nineSlice: the game's own frame of the window (tooltips, label template).
	local s = setmetatable({ owner = owner, nineSlice = owner.NineSlice, active = true }, SkinMixin)
	s.background = owner:CreateTexture(nil, "BACKGROUND", nil, -7)
	s.background:SetAllPoints()
	s.lines = {}
	for _, key in ipairs({ "topLeft", "topRight", "left", "right", "bottomLeft", "bottomRight" }) do
		s.lines[key] = owner:CreateTexture(nil, "BORDER")
	end
	s.lines.left:SetPoint("TOPLEFT")
	s.lines.left:SetPoint("BOTTOMLEFT")
	s.lines.right:SetPoint("TOPRIGHT")
	s.lines.right:SetPoint("BOTTOMRIGHT")
	-- Frame of game textures, drawn under the window's content.
	local ok, art = pcall(CreateFrame, "Frame", nil, owner, "BackdropTemplate")
	if ok and art and art.SetBackdrop then
		s.art = art
		art:SetAllPoints()
		art:SetFrameLevel(math.max((owner:GetFrameLevel() or 1) - 1, 0))
		art:Hide()
	end
	-- Top badge: an icon (framed, cropped like the game's buttons) or a marker.
	s.badgeFrame = owner:CreateTexture(nil, "OVERLAY", nil, 6)
	s.badgeFrame:SetSize(BADGE_SIZE + 2, BADGE_SIZE + 2)
	s.badgeFrame:SetPoint("CENTER", owner, "TOP", 0, 0)
	s.badgeFrame:Hide()
	s.badge = owner:CreateTexture(nil, "OVERLAY", nil, 7)
	s.badge:SetSize(BADGE_SIZE, BADGE_SIZE)
	s.badge:SetPoint("CENTER", owner, "TOP", 0, 0)
	s.badge:Hide()
	s:SetBorderSize(BORDER)
	s:Layout()
	-- Every time the window shows, the style is applied again.
	owner:HookScript("OnShow", function() s:ApplyStyle() end)
	byOwner[owner] = s
	return s
end

-- A Wanderer window: the game's tooltip frame (for the "Game interface" style)
-- dressed by the engine. Returns the frame and its skin.
-- A window that opens and closes with the game's own sounds (SOUNDKIT names),
-- like the game's windows. window.quiet: this time, silently (it opened by
-- itself: a message, a notice).
function Skin.Sounds(window, open, close)
	local function Play(key)
		U.PlaySound(key)
	end
	window:HookScript("OnShow", function(self) if not self.quiet then Play(open) end end)
	window:HookScript("OnHide", function(self)
		if not self.quiet then Play(close) end
		self.quiet = nil
	end)
end

-- What every Wanderer window does: moved by dragging it (its place kept in
-- ns.root[save] when given, else at point), closed by its cross and by
-- Escape. The cross closes directly (or calls onClose), never through the
-- game's panel manager, locked during a fight. Returns the cross.
-- The lines of a sample label (the live preview and the style cards):
-- locale key, size, color.
Skin.SAMPLE_LINES = {
	{ "THEME_SAMPLE_NAME", 14, 1, 0.82, 0 },
	{ "THEME_SAMPLE_ROLE", 12, 0.82, 0.75, 0.56 },
	{ "THEME_SAMPLE_DETAIL", 11, 0.8, 0.8, 0.8 },
}

-- The game's color picker: onPick(r, g, b) while choosing, the color before on Cancel.
function Skin.PickColor(r, g, b, onPick)
	local picker = rawget(_G, "ColorPickerFrame") -- (the game's, filled in below for older games)
	if not picker then return end
	local function Current() return picker:GetColorRGB() end
	if picker.SetupColorPickerAndShow then
		picker:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = function() onPick(Current()) end,
			cancelFunc = function() onPick(r, g, b) end })
		return
	end
	picker.func = function() onPick(Current()) end
	picker.cancelFunc = function() onPick(r, g, b) end
	picker.hasOpacity, picker.previousValues = false, { r, g, b }
	picker:SetColorRGB(r, g, b)
	picker:Hide()
	picker:Show()
end

-- The small golden heading over a window ("TRAVEL JOURNAL"), placed by its owner.
function Skin.CreateKicker(parent, text)
	local kicker = Skin.CreateText(parent, "GameTooltipTextSmall", 0.85, 0.75, 0.5)
	if text then kicker:SetText(text:upper()) end
	return kicker
end

function Skin.Dress(window, point, save, onClose)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if save and ns.root then
			local anchor, _, _, x, y = self:GetPoint(1)
			ns.root[save] = { anchor, x, y }
		end
	end)
	local saved = save and ns.root and ns.root[save]
	window:ClearAllPoints()
	if saved then
		window:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
	else
		window:SetPoint(unpack(point or { "CENTER" }))
	end
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", onClose or function() window:Hide() end)
	local name = window:GetName()
	if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
	return close
end

-- A line to write in, on a dark band, as in the chat.
function Skin.CreateInput(parent, name, maxLetters)
	local input = CreateFrame("EditBox", name, parent)
	input:SetHeight(24)
	input:SetFontObject("ChatFontNormal")
	input:SetAutoFocus(false)
	input:SetMaxLetters(maxLetters or 255)
	input:SetTextInsets(8, 8, 0, 0)
	input.background = input:CreateTexture(nil, "BACKGROUND")
	input.background:SetAllPoints()
	input.background:SetColorTexture(0, 0, 0, 0.35)
	return input
end

function Skin.CreateWindow(name, strata, parent)
	parent = parent or UIParent
	local ok, created = pcall(CreateFrame, "Frame", name, parent, "TooltipBackdropTemplate")
	local window = ok and created or CreateFrame("Frame", name, parent)
	if strata then window:SetFrameStrata(strata) end
	window:SetSize(1, 1)
	window:Hide()
	-- Stays readable when the cinematic mode fades the interface.
	if window.SetIgnoreParentAlpha then window:SetIgnoreParentAlpha(true) end
	return window, Skin.Attach(window)
end

-- Cuts a texture round; returns false when the game cannot (then a ring
-- drawn around it should not be shown at all, rather than as a square).
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
function Skin.RoundMask(owner, texture)
	if not (owner.CreateMaskTexture and texture.AddMaskTexture) then return false end
	local mask = owner:CreateMaskTexture()
	if not mask then return false end
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return true
end

-- A round portrait in a thin golden ring (texture.ring; texture.ringShown:
-- false when the game cannot cut it round, then the ring stays hidden).
function Skin.RoundPortrait(owner, size)
	local texture = owner:CreateTexture(nil, "ARTWORK")
	texture:SetSize(size, size)
	local ring = owner:CreateTexture(nil, "BORDER")
	ring:SetSize(size + 3, size + 3)
	ring:SetPoint("CENTER", texture, "CENTER")
	ring:SetTexture("Interface\\Buttons\\WHITE8X8")
	ring:SetVertexColor(1, 0.82, 0, 0.5)
	Skin.RoundMask(owner, texture)
	texture.ring = ring
	texture.ringShown = Skin.RoundMask(owner, ring)
	return texture
end

-- A line of text in the tooltips' fonts, left aligned, with their shadow.
function Skin.CreateText(owner, template, r, g, b)
	local text = owner:CreateFontString(nil, "OVERLAY", template)
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.9)
	if r then text:SetTextColor(r, g, b) end
	text:SetJustifyH("LEFT")
	return text
end

-- Moves a window's opacity toward target: fadeIn and fadeOut are the seconds
-- of a full fade. Returns the new opacity.
local fades = setmetatable({}, { __mode = "k" }) -- window -> its tween

function Skin.Fade(window, target, elapsed, fadeIn, fadeOut)
	local alpha = window:GetAlpha()
	local tween = fades[window]
	if not tween then
		tween = ns.Util.Tween(alpha)
		fades[window] = tween
	elseif math.abs(tween.value - alpha) > 0.01 then
		tween:Set(alpha) -- set from outside (shown at 0, for instance): from there
	end
	if alpha == target and tween.value == target then return alpha end
	alpha = tween:Step(target, elapsed, fadeIn, fadeOut)
	window:SetAlpha(alpha)
	return alpha
end

-- The style this window draws: the chosen one, or a fixed one (previews).
function SkinMixin:Style()
	return STYLES[self.fixedStyle] or CurrentStyle()
end

-- Draws this window in a given style and opacity whatever the settings
-- (previews of the predefined styles).
function SkinMixin:SetFixedStyle(style, opacity)
	self.fixedStyle, self.fixedOpacity = style, opacity
	self:ApplyStyle()
end

-- How this window draws the current style. A window without the game frame
-- or the backdrop support falls back to Wanderer's lines.
function SkinMixin:Kind()
	if not self.active then return "off" end
	local kind = self:Style().kind
	if kind == "game" and not self.nineSlice then return "lines" end
	if kind == "texture" and not self.art then return "lines" end
	return kind
end

-- inactive: the window keeps the game's look (tooltips with Wanderer style off).
function SkinMixin:SetActive(active)
	self.active = active and true or false
	self:ApplyStyle()
end

function SkinMixin:SetBackground(r, g, b, a)
	local kind = self:Kind()
	if kind == "game" then
		pcall(self.nineSlice.SetCenterColor, self.nineSlice, r, g, b, a)
	elseif kind == "texture" then
		self.art:SetBackdropColor(r, g, b, a)
	elseif kind == "lines" then
		self.background:SetColorTexture(r, g, b, a)
	end
end

function SkinMixin:SetBorderColor(r, g, b, a)
	local kind = self:Kind()
	if kind == "off" then return end
	if kind == "game" then
		pcall(self.nineSlice.SetBorderColor, self.nineSlice, r, g, b, a)
	elseif kind == "texture" then
		self.art:SetBackdropBorderColor(r, g, b, a)
	else
		for _, line in pairs(self.lines) do line:SetColorTexture(r, g, b, a) end
	end
	self.badgeFrame:SetColorTexture(r, g, b, 1)
end

function SkinMixin:SetBorderSize(size)
	for key, line in pairs(self.lines) do
		if key == "left" or key == "right" then line:SetWidth(size) else line:SetHeight(size) end
	end
end

-- Exactly one drawing at a time: Wanderer's lines, the game textures or the game
-- frame. The game may give its frame back its opacity: it is hidden, not
-- only faded.
function SkinMixin:ShowDecoration()
	local kind = self:Kind()
	local lines = kind == "lines"
	self.background:SetShown(lines)
	self.lines.topLeft:SetShown(lines)
	self.lines.left:SetShown(lines)
	self.lines.right:SetShown(lines)
	self.lines.bottomLeft:SetShown(lines)
	self.lines.topRight:SetShown(lines and self.badge:IsShown())
	self.lines.bottomRight:Hide()
	if self.art then
		local style = self:Style()
		if kind == "texture" and self.artStyle ~= style then
			self.art:SetBackdrop(style.backdrop)
			self.artStyle = style
		end
		self.art:SetShown(kind == "texture")
	end
	if self.nineSlice then
		local game = kind == "game" or kind == "off"
		self.nineSlice:SetAlpha(game and 1 or 0)
		self.nineSlice:SetShown(game)
	end
end

-- What is really drawn, for /wanderer debug.
function SkinMixin:Report()
	local nineSlice = self.nineSlice
	return {
		kind = self:Kind(),
		wanderer = self.background:IsShown() or (self.art ~= nil and self.art:IsShown()),
		game = nineSlice ~= nil and nineSlice:IsShown() and nineSlice:GetAlpha() > 0,
		active = self.active,
	}
end

-- Border lines anchored on the center of the edges: no width to measure (it
-- can be secret in combat), and they leave a gap around the badges.
function SkinMixin:Layout()
	local owner = self.owner
	local function edge(first, second, point, gap)
		first:ClearAllPoints()
		second:ClearAllPoints()
		first:SetPoint(point .. "LEFT")
		if gap then
			first:SetPoint(point .. "RIGHT", owner, point, -gap, 0)
			second:SetPoint(point .. "LEFT", owner, point, gap, 0)
			second:SetPoint(point .. "RIGHT")
		else
			first:SetPoint(point .. "RIGHT")
		end
	end
	local topGap = self.badge:IsShown() and (BADGE_SIZE / 2 + BADGE_GAP) or nil
	edge(self.lines.topLeft, self.lines.topRight, "TOP", topGap)
	edge(self.lines.bottomLeft, self.lines.bottomRight, "BOTTOM", nil)
	self:ShowDecoration()
end

-- Room taken inside the window by the badge (top, bottom).
function SkinMixin:Insets()
	return self.badge:IsShown() and BADGE_SIZE / 2 or 0, 0
end

-- Smallest inner width that keeps the badge and its gaps.
function SkinMixin:MinWidth()
	return self.badge:IsShown() and (BADGE_SIZE + BADGE_GAP * 2) or 0
end

-- icon: texture; atlas: game marker used when available; framed: icon frame.
function SkinMixin:SetTopBadge(icon, atlas, framed)
	if self.badge:IsShown() and self.badgeKey == (atlas or icon) and self.badgeFramed == framed then return end
	self.badgeKey, self.badgeFramed = atlas or icon, framed
	if atlas and U.HasAtlas(atlas) then
		self.badge:SetAtlas(atlas)
		self.badge:SetTexCoord(0, 1, 0, 1)
	elseif icon then
		self.badge:SetTexture(icon)
		if framed then self.badge:SetTexCoord(0.08, 0.92, 0.08, 0.92) else self.badge:SetTexCoord(0, 1, 0, 1) end
	else
		return self:ClearTopBadge()
	end
	self.badge:Show()
	self.badgeFrame:SetShown(framed and true or false)
	self:Layout()
end

function SkinMixin:ClearTopBadge()
	if not self.badge:IsShown() then return end
	self.badgeKey = nil
	self.badge:Hide()
	self.badgeFrame:Hide()
	self:Layout()
end

-- Resting look of the style, with the current highlight on top.
function SkinMixin:ApplyStyle()
	local bg, opacity, border = Skin.GetColors(self:Style(), self.fixedOpacity)
	self:ShowDecoration()
	self:SetBackground(bg[1], bg[2], bg[3], opacity)
	local c = self.color or border
	self:SetBorderColor(c[1], c[2], c[3], self.color and 0.95 or c[4])
end

-- mode: key of HIGHLIGHTS, or nil for the resting border. r, g, b: color of
-- the "quality" highlight.
function SkinMixin:SetHighlight(mode, r, g, b)
	local def = mode and HIGHLIGHTS[mode]
	if def then
		local section = ns.db[def.option[1]]
		if not (section and section[def.option[2]]) then mode, def = nil, nil end
	end
	self.mode, self.def = mode, def
	self.color = def and (r and { r, g, b } or def.color) or nil
	self:SetBorderSize(def and def.border or BORDER)
	self:ApplyStyle()
	UpdateVignette(self, def and def.alert and ns.db.label.threatVignette)
end

function SkinMixin:GetHighlight()
	return self.mode
end

-- Called on every frame by the window: pulsing highlights and the alert.
function SkinMixin:Animate(alpha)
	local def = self.def
	if not (def and def.pulse and self.color) then return end
	local pulse = 0.5 + 0.5 * math.sin(GetTime() * def.pulse)
	local c = self.color
	if def.alert then
		-- Fast red flashing border, background and screen edges.
		self:SetBorderColor(c[1], c[2], c[3], 0.4 + 0.6 * pulse)
		self:SetBackground(0.45 * pulse, 0, 0, math.max(ns.db.label.bgOpacity / 100, 0.6))
		if vignette then vignette:SetAlpha((0.25 + 0.5 * pulse) * (alpha or 1)) end
	else
		self:SetBorderColor(c[1], c[2], c[3], 0.6 + 0.4 * pulse)
	end
end
