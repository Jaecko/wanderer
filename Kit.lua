local _, ns = ...

-- The pieces every Wanderer window is built of, Wanderer's and its
-- extensions' alike (Wanderer.Skin): texts in a role's color, captions,
-- thin rules and edges, panels, chips, buttons, rows of choices, an item's
-- square, a window's heading, its resize corner, a table (titles that sort,
-- rows with an item's square, a chip, a button, a scroll bar), an amount of
-- money, a question asked before acting, a tooltip on hover. One way to draw
-- each: the windows look alike and nothing is written twice.

local Skin, U = ns.Skin, ns.Util

-- Colors ------------------------------------------------------------------------------------------------

-- The colors, by role.
Skin.COLORS = {
	gold = { 1, 0.82, 0 }, kicker = { 0.85, 0.75, 0.5 }, label = { 0.75, 0.68, 0.5 }, text = { 0.9, 0.88, 0.82 },
	soft = { 0.81, 0.78, 0.72 }, muted = { 0.56, 0.53, 0.46 }, good = { 0.56, 0.88, 0.64 }, bad = { 0.95, 0.54, 0.49 },
	warn = { 0.88, 0.63, 0.25 }, blue = { 0.61, 0.78, 0.96 },
}
local COLORS = Skin.COLORS

-- Words in a role's color.
function Skin.Colorize(text, role)
	local c = COLORS[role] or COLORS.text
	return U.Colorize(text, c[1], c[2], c[3])
end

-- The heights of a row every window shares: a window drawn with them reads as one hand.
Skin.ROW = { compact = 24, normal = 34, rich = 54 }

-- The sounds, each for one kind of touch (a few of the game's, quiet): Skin.Play(kind).
Skin.SOUNDS = {
	click = "IG_MAINMENU_OPTION_CHECKBOX_ON", confirm = "IG_MAINMENU_OPTION", mark = "IG_CHARACTER_INFO_TAB",
	refuse = "IG_QUEST_LOG_ABORT", open = "IG_CHARACTER_INFO_OPEN", close = "IG_CHARACTER_INFO_CLOSE",
}
function Skin.Play(kind) U.PlaySound(Skin.SOUNDS[kind] or Skin.SOUNDS.click) end

-- A chip's tones: its ground (r, g, b, a), its words (r, g, b).
local TONES = {
	gold = { 1, 0.82, 0, 0.12, 0.95, 0.81, 0.42 }, red = { 0.94, 0.54, 0.49, 0.15, 0.95, 0.63, 0.58 },
	green = { 0.31, 0.78, 0.43, 0.15, 0.56, 0.88, 0.64 }, blue = { 0.31, 0.59, 0.9, 0.16, 0.61, 0.78, 0.96 },
	grey = { 1, 1, 1, 0.07, 0.69, 0.66, 0.6 },
}

-- Glyphs ----------------------------------------------------------------------------------------------------
-- Wanderer's own small signs, on two sheets (Media/Glyphs.tga, eight squares; Media/Glyphs2.tga, sixteen): a
-- texture of one of them, in the label's color unless colored after. Skin.SetGlyph(texture, name, flipped)
-- changes it. (the first sheet keeps its size: other addons read it by it)
local GLYPH_SHEET = "Interface\\AddOns\\Wanderer\\Media\\Glyphs"
local GLYPH_SHEET2 = "Interface\\AddOns\\Wanderer\\Media\\Glyphs2"
local GLYPHS = { close = 0, back = 1, chevron = 2, check = 3, up = 4, down = 5, dot = 6, plus = 7 }
local GLYPHS2 = { cog = 0, undo = 1, move = 2, camera = 3, grid = 4, bell = 5, star = 6, reload = 7, home = 8, eyeoff = 9 }
function Skin.SetGlyph(texture, name, flipped)
	local index, squares, sheet = GLYPHS[name], 8, GLYPH_SHEET
	if not index and GLYPHS2[name] then index, squares, sheet = GLYPHS2[name], 16, GLYPH_SHEET2 end
	index = index or 0
	texture:SetTexture(sheet)
	local left, right = index / squares, (index + 1) / squares
	if flipped then texture:SetTexCoord(left, right, 1, 0) else texture:SetTexCoord(left, right, 0, 1) end
end
function Skin.GlyphOn(texture, name)
	Skin.SetGlyph(texture, name)
	texture:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
	return texture
end
function Skin.Glyph(parent, name, size, layer)
	local texture = parent:CreateTexture(nil, layer or "ARTWORK")
	texture:SetSize(size or 12, size or 12)
	Skin.SetGlyph(texture, name)
	texture:SetVertexColor(COLORS.label[1], COLORS.label[2], COLORS.label[3])
	return texture
end

-- A glyph inside words ("|T...|t"): Skin.GlyphText(name, role, size). role: a color's role (label unless
-- said) or { r, g, b }; size: its height in the line (0: the line's own, the default).
function Skin.GlyphText(name, role, size)
	local index, squares, sheet = GLYPHS[name], 8, GLYPH_SHEET
	if not index and GLYPHS2[name] then index, squares, sheet = GLYPHS2[name], 16, GLYPH_SHEET2 end
	index = index or 0
	local c = type(role) == "table" and role or COLORS[role or "label"] or COLORS.label
	size = math.floor((tonumber(size) or 0) + 0.5)
	-- (the sheet's pixels: squares of 16 on a line)
	return ("|T%s:%d:%d:0:0:%d:16:%d:%d:0:16:%d:%d:%d|t"):format(sheet, size, size, squares * 16, index * 16,
		(index + 1) * 16, math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Texts -----------------------------------------------------------------------------------------------------

-- A text in a role's color.
function Skin.Text(parent, template, role)
	local c = COLORS[role or "text"] or COLORS.text
	return Skin.CreateText(parent, template or "GameTooltipText", c[1], c[2], c[3])
end

-- A small title in capitals (a section, a column): muted, or in a role's color.
function Skin.Caps(parent, text, role)
	local caps = Skin.Text(parent, "GameTooltipTextSmall", role or "muted")
	caps:SetText(U.Upper(text or ""))
	return caps
end

-- An item's name in its quality's color.
function Skin.Quality(text, quality)
	text:SetTextColor(U.QualityColor(quality or 1))
end

-- Lines and grounds ----------------------------------------------------------------------------------------

-- A thin frame around something: four lines, one color (edges.Color(r, g, b, a) changes it).
function Skin.Edges(frame, r, g, b, a)
	local edges = {}
	for index, points in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local edge = frame:CreateTexture(nil, "BORDER")
		edge:SetPoint(points[1])
		edge:SetPoint(points[2])
		if index <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
		edges[index] = edge
	end
	function edges.Color(red, green, blue, alpha)
		for _, edge in ipairs(edges) do edge:SetColorTexture(red, green, blue, alpha or 1) end
	end
	edges.Color(r or 1, g or 1, b or 1, a or 0.1)
	return edges
end

-- A thin golden rule, across or down (placed by its owner).
function Skin.Rule(parent, vertical, alpha)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, alpha or 0.16)
	if vertical then rule:SetWidth(1) else rule:SetHeight(1) end
	return rule
end

-- A texture fading out to its right (reversed: to its left), in gold or the color given: a golden rule
-- fading out, a dark band (made and placed by its owner).
function Skin.FadingRule(texture, alpha, reversed, color)
	local c = color or COLORS.gold
	local full, clear = CreateColor(c[1], c[2], c[3], alpha), CreateColor(c[1], c[2], c[3], 0)
	texture:SetColorTexture(1, 1, 1, 1)
	texture:SetGradient("HORIZONTAL", reversed and clear or full, reversed and full or clear)
	return texture
end

-- A soft panel (a card): a light ground, a thin edge.
function Skin.Panel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel.ground = panel:CreateTexture(nil, "BACKGROUND")
	panel.ground:SetAllPoints()
	panel.ground:SetColorTexture(1, 1, 1, 0.035)
	panel.edges = Skin.Edges(panel, 1, 1, 1, 0.07)
	return panel
end

-- A chip: a few words on a tinted ground (gold, red, green, blue, grey). chip:Set(nil) hides it.
function Skin.Chip(parent)
	local chip = CreateFrame("Frame", nil, parent)
	chip:SetHeight(17)
	chip.ground = chip:CreateTexture(nil, "BACKGROUND")
	chip.ground:SetAllPoints()
	chip.text = Skin.CreateText(chip, "GameTooltipTextSmall")
	chip.text:SetPoint("CENTER")
	function chip:Set(text, tone)
		self:SetShown(text ~= nil)
		if not text then return end
		local t = TONES[tone or "grey"] or TONES.grey
		self.ground:SetColorTexture(t[1], t[2], t[3], t[4])
		self.text:SetTextColor(t[5], t[6], t[7])
		self.text:SetText(text)
		self:SetWidth(U.Measure(self.text, "GetStringWidth", 40) + 14)
	end
	chip:Hide()
	return chip
end

-- Hover ------------------------------------------------------------------------------------------------------

-- The standard tooltip, shown now beside owner (anchor: "ANCHOR_RIGHT" unless said). lines: a line, or lines
-- ({ title, { words, r, g, b }, ... }: the first in gold, unless it is itself { words, r, g, b }), or a function
-- of the owner giving either (nil or "": nothing shown). True when shown.
function Skin.ShowTip(owner, lines, anchor)
	local words = lines
	if type(words) == "function" then
		local ok, made = pcall(words, owner)
		words = ok and made or nil
	end
	if words == nil or words == "" or (type(words) == "table" and words[1] == nil) then return false end
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	if type(words) == "table" then
		for index, line in ipairs(words) do
			if type(line) == "table" then GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
			elseif index == 1 then GameTooltip:AddLine(line, COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
			else GameTooltip:AddLine(line, 1, 1, 1, true) end
		end
	else
		GameTooltip:AddLine(tostring(words), 1, 1, 1, true)
	end
	GameTooltip:Show()
	return true
end

-- A few words under the mouse (Skin.ShowTip's lines), gone when it leaves.
function Skin.Tooltip(frame, text, anchor)
	frame:HookScript("OnEnter", function(self) Skin.ShowTip(self, text, anchor) end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The game's window out of sight while Wanderer's is used in its place (still open under it), back in its
-- place otherwise; the game places its windows again and again (another one opened, its tabs): out of sight
-- each time. away() says when. Gives Place(), to call when that changes.
function Skin.AsideGameWindow(frame, away)
	local function Place() U.HideOffScreen(frame, away() and true or false) end
	frame:HookScript("OnShow", Place)
	if UpdateUIPanelPositions then
		hooksecurefunc("UpdateUIPanelPositions", function() if away() then Place() end end)
	end
	return Place
end

-- A button in the game's own look, for a game window (the mailbox, a merchant): as wide as its words.
function Skin.GameButton(parent, name, text, onClick, tip)
	local made = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
	made:SetHeight(24)
	made:SetText(text)
	made:SetWidth(math.max(90, U.Measure(made:GetFontString() or made, "GetStringWidth", 80) + 28))
	made:SetScript("OnClick", onClick)
	if tip then Skin.Tooltip(made, tip, "ANCHOR_RIGHT") end
	return made
end

-- An item's tooltip under the mouse: item(frame) gives its link (a string) or its id (a number).
function Skin.ItemTooltip(frame, item, anchor)
	frame:HookScript("OnEnter", function(self)
		local what = item(self)
		if not what then return end
		GameTooltip:SetOwner(self, anchor or "ANCHOR_LEFT")
		if type(what) == "number" then GameTooltip:SetItemByID(what) else GameTooltip:SetHyperlink(what) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Keys ------------------------------------------------------------------------------------------------------------
-- A key pressed to be set (the settings' Keys page, the welcome's reveal key): Skin.MODIFIER_KEYS only change
-- another (never a key of their own); Skin.FullKey(key) names it with the modifiers held, as the game does
-- ("ALT-CTRL-SHIFT-F"); Skin.KeyText(key) in the game's words; Skin.BindingName(command) an action's name.
Skin.MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true,
	RMETA = true, UNKNOWN = true }
function Skin.FullKey(key)
	local prefix = ""
	if IsAltKeyDown and IsAltKeyDown() then prefix = prefix .. "ALT-" end
	if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
	if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
	return prefix .. key
end
function Skin.KeyText(key)
	local words = GetBindingText and GetBindingText(key, "KEY_")
	return type(words) == "string" and words ~= "" and words or key
end
-- A button waiting for a key once asked (listener:Set(true), out of a fight): the next key pressed is given to
-- opts.onKey(full key, with its modifiers); Escape lets it go, a modifier alone waits for the rest. The key pressed
-- does nothing else meanwhile. One listener at a time; a fight beginning, or the button hidden, stops it.
-- opts.onChange(listening): to draw it again. listener:Listening().
local keyListener, keyGuard
function Skin.KeyListener(button, opts)
	opts = opts or {}
	local listener = { on = false }
	function listener:Set(on)
		on = on and true or false
		if on and keyListener and keyListener ~= self then keyListener:Set(false) end
		if on then keyListener = self elseif keyListener == self then keyListener = nil end
		self.on = on
		if button.EnableKeyboard then button:EnableKeyboard(on) end
		if on and button.SetPropagateKeyboardInput then pcall(button.SetPropagateKeyboardInput, button, false) end
		if opts.onChange then opts.onChange(on) end
	end
	function listener:Listening() return self.on end
	button:SetScript("OnKeyDown", function(_, key)
		if not listener.on then return end
		if key == "ESCAPE" then
			Skin.Play("click")
			return listener:Set(false)
		end
		if Skin.MODIFIER_KEYS[key] then return end
		listener:Set(false)
		if opts.onKey then opts.onKey(Skin.FullKey(key)) end
	end)
	button:HookScript("OnHide", function() if listener.on then listener:Set(false) end end)
	-- (a fight begins: no more listening, before the game locks the keys)
	if not keyGuard then
		keyGuard = CreateFrame("Frame")
		keyGuard:RegisterEvent("PLAYER_REGEN_DISABLED")
		keyGuard:SetScript("OnEvent", function() if keyListener then keyListener:Set(false) end end)
	end
	return listener
end

function Skin.BindingName(command)
	return _G["BINDING_NAME_" .. command] or command
end

-- Buttons and choices --------------------------------------------------------------------------------------------

-- A button: "main" (gold, the one of its window), else quiet (an outline). Dimmed while it cannot be used.
-- button:Fit() makes it as wide as its words (at least minimum).
function Skin.Button(parent, text, onClick, kind, minimum)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(kind == "main" and 36 or 30)
	button.ground = button:CreateTexture(nil, "BACKGROUND")
	button.ground:SetAllPoints()
	button.caption = Skin.CreateText(button, kind == "main" and "GameFontNormal" or "GameFontHighlightSmall")
	button.caption:SetPoint("CENTER")
	button:SetFontString(button.caption)
	if kind == "main" then
		button.ground:SetColorTexture(0.54, 0.43, 0.07, 1)
		Skin.Edges(button, 0.79, 0.64, 0.15, 1)
		button.caption:SetTextColor(1, 0.96, 0.84)
	else
		button.ground:SetColorTexture(1, 1, 1, 0.04)
		Skin.Edges(button, 1, 0.82, 0, 0.3)
		button.caption:SetTextColor(0.85, 0.75, 0.5)
	end
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
	button:SetText(text)
	function button:Fit()
		self:SetWidth(math.max(minimum or 0, U.Measure(self.caption, "GetStringWidth", 60) + 28))
	end
	button:Fit()
	button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
	button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
	button:SetScript("OnMouseDown", function(self)
		if not self:IsEnabled() then return end
		self.caption:SetPoint("CENTER", 1, -1)
		self.ground:SetVertexColor(0.8, 0.8, 0.8)
	end)
	button:SetScript("OnMouseUp", function(self)
		self.caption:SetPoint("CENTER", 0, 0)
		self.ground:SetVertexColor(1, 1, 1)
	end)
	button:SetScript("OnClick", function(self, ...)
		Skin.Play(kind == "main" and "confirm" or "click")
		onClick(self, ...)
	end)
	return button
end

-- A choice on or off: a small box with its label beside it (a click on either). get() is read each time it is
-- drawn (check:Refresh()), set(value) called on a click; tip: its tooltip.
function Skin.Check(parent, label, get, set, tip)
	local check = CreateFrame("Button", nil, parent)
	check:SetHeight(18)
	check.box = CreateFrame("Frame", nil, check)
	check.box:SetSize(14, 14)
	check.box:SetPoint("LEFT")
	local ground = check.box:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.45)
	Skin.Edges(check.box, 0.79, 0.64, 0.15, 0.9)
	check.mark = Skin.Glyph(check.box, "check", 12)
	check.mark:SetPoint("CENTER")
	check.mark:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
	check.text = Skin.Text(check, "GameTooltipText", "soft")
	check.text:SetPoint("LEFT", check.box, "RIGHT", 7, 0)
	function check:Refresh() self.mark:SetShown(get() and true or false) end
	function check:SetLabel(text)
		self.text:SetText(text)
		self:SetWidth(21 + U.Measure(self.text, "GetStringWidth", 160))
	end
	check:SetScript("OnMouseDown", function(self) self.box:SetPoint("LEFT", 1, -1) end)
	check:SetScript("OnMouseUp", function(self) self.box:SetPoint("LEFT", 0, 0) end)
	check:SetScript("OnClick", function(self)
		set(not get())
		Skin.Play("mark")
		self:Refresh()
	end)
	if tip then Skin.Tooltip(check, tip) end
	check:SetLabel(label)
	check:Refresh()
	return check
end

-- A switch: on (gold, its knob to the right) or off. switch:Set(on) draws it; onClick(switch) on a click.
-- size: "small" (28 x 14, a card's heading) or the settings' (36 x 18).
function Skin.Switch(parent, onClick, size)
	local small = size == "small"
	local switch = CreateFrame("Button", nil, parent)
	switch:SetSize(small and 28 or 36, small and 14 or 18)
	switch.track = switch:CreateTexture(nil, "BACKGROUND")
	switch.track:SetAllPoints()
	switch.edges = Skin.Edges(switch, 1, 0.82, 0, 0.3)
	switch.knob = switch:CreateTexture(nil, "ARTWORK")
	switch.knob:SetSize(small and 10 or 12, small and 10 or 12)
	local inset = small and 2 or 3
	function switch:Set(on)
		self.on = on and true or false
		self.knob:ClearAllPoints()
		if self.on then
			self.track:SetColorTexture(0.54, 0.43, 0.07, 1)
			self.edges.Color(0.79, 0.64, 0.15, 1)
			self.knob:SetColorTexture(1, 0.96, 0.84, 1)
			self.knob:SetPoint("RIGHT", self, "RIGHT", -inset, 0)
		else
			self.track:SetColorTexture(0, 0, 0, 0.45)
			self.edges.Color(0.85, 0.75, 0.5, 0.35)
			self.knob:SetColorTexture(0.56, 0.53, 0.46, 1)
			self.knob:SetPoint("LEFT", self, "LEFT", inset, 0)
		end
	end
	switch:SetScript("OnClick", onClick)
	switch:Set(false)
	return switch
end

-- A small button, for a window's bar or a row: framed, its words saying what it does, its tooltip; a link's
-- methods (SetLabel), so it takes a link's place. Every action is one of these (or Skin.Button), never a bare
-- word to guess. height: 22 unless said.
function Skin.SmallButton(parent, text, onClick, tooltip, height)
	local button = Skin.Button(parent, text or "", function(self, ...) if onClick then onClick(self, ...) end end)
	button:SetHeight(height or 22)
	function button:SetLabel(label)
		self:SetText(label or "")
		self:Fit()
	end
	if tooltip then Skin.Tooltip(button, tooltip) end
	return button
end

-- A quiet button made of one glyph (a cog, an undo...): in the label's color, gold under the mouse, its
-- tooltip (a line, lines, or a function giving them). size: the glyph's (the button a little larger).
function Skin.GlyphButton(parent, name, size, tooltip, onClick)
	local button = CreateFrame("Button", nil, parent)
	size = size or 14
	button:SetSize(size + 6, size + 6)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.glyph = Skin.Glyph(button, name, size)
	button.glyph:SetPoint("CENTER")
	function button:Tint(role)
		local c = COLORS[role] or COLORS.label
		self.glyph:SetVertexColor(c[1], c[2], c[3])
	end
	button:SetScript("OnEnter", function(self) self:Tint("gold") end)
	button:SetScript("OnLeave", function(self) self:Tint(self.role or "label") end)
	button:SetScript("OnMouseDown", function(self) self.glyph:SetPoint("CENTER", 1, -1) end)
	button:SetScript("OnMouseUp", function(self) self.glyph:SetPoint("CENTER", 0, 0) end)
	button:SetScript("OnClick", function(self, mouse)
		Skin.Play("click")
		if onClick then onClick(self, mouse) end
	end)
	if tooltip then Skin.Tooltip(button, tooltip, "ANCHOR_BOTTOM") end
	return button
end

-- A list to choose from: a button showing the choice (placeholder before one), a menu of all of them.
-- choices() gives { { id, label } }, get() the id chosen, set(id) chooses. box:Refresh() after a change.
-- As wide as its words, between minimum and maximum (220 unless said): a longer choice is cut, whole under
-- the mouse. tip: its tooltip (Skin.ShowTip's lines), under the cut choice when there is one (one tooltip:
-- never Skin.Tooltip on top of it).
local DROPDOWN_MAX = 220
function Skin.Dropdown(parent, choices, get, set, placeholder, minimum, maximum, tip)
	local box
	box = Skin.Button(parent, "", function(self)
		U.Menu(self, function(_, root)
			for _, choice in ipairs(choices()) do
				root:CreateRadio(choice.label, function() return get() == choice.id end, function()
					set(choice.id)
					box:Refresh()
				end)
			end
		end)
	end, nil, minimum)
	box.arrow = Skin.Glyph(box, "down", 9, "OVERLAY")
	box.arrow:SetPoint("RIGHT", box, "RIGHT", -8, 0)
	-- (its words from its left edge to the arrow, on one line)
	local caption = box.caption
	local function Place(dx, dy)
		caption:ClearAllPoints()
		caption:SetPoint("LEFT", box, "LEFT", 10 + dx, dy)
		caption:SetPoint("RIGHT", box.arrow, "LEFT", -6 + dx, dy)
	end
	Place(0, 0)
	caption:SetJustifyH("LEFT")
	if caption.SetWordWrap then caption:SetWordWrap(false) end
	box:SetScript("OnMouseDown", function(self)
		if not self:IsEnabled() then return end
		Place(1, -1)
		self.ground:SetVertexColor(0.8, 0.8, 0.8)
	end)
	box:SetScript("OnMouseUp", function(self)
		Place(0, 0)
		self.ground:SetVertexColor(1, 1, 1)
	end)
	maximum = maximum or DROPDOWN_MAX
	function box:Fit()
		local wanted = U.Measure(caption, "GetStringWidth", 60) + 34
		self:SetWidth(math.min(maximum, math.max(minimum or 0, wanted)))
	end
	function box:Refresh()
		local label = placeholder or ""
		for _, choice in ipairs(choices()) do
			if choice.id == get() then label = choice.label end
		end
		self.chosenLabel = label
		self:SetText(label)
		self:Fit()
	end
	-- (a choice cut short: whole under the mouse, in gold, its tooltip under it)
	box:HookScript("OnEnter", function(self)
		local words = tip
		if type(words) == "function" then
			local ok, made = pcall(words, self)
			words = ok and made or nil
		end
		if not (caption.IsTruncated and caption:IsTruncated()) then return Skin.ShowTip(self, words) end
		local lines = { self.chosenLabel or "" }
		local gold = COLORS.gold
		if type(words) == "table" then
			for index, line in ipairs(words) do
				lines[#lines + 1] = (index == 1 and type(line) ~= "table") and { line, gold[1], gold[2], gold[3] } or line
			end
		elseif words ~= nil and words ~= "" then
			lines[2] = { tostring(words), 1, 1, 1 }
		end
		Skin.ShowTip(self, lines)
	end)
	box:HookScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
	box:Refresh()
	return box
end

-- A row of choices, one of them chosen (in gold): { { key, label }, ... }; onPick(key). bar:Select(key),
-- bar:SetLabels({ label, ... }).
function Skin.Choices(parent, list, onPick, height)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height or 32)
	bar.ground = bar:CreateTexture(nil, "BACKGROUND")
	bar.ground:SetAllPoints()
	bar.ground:SetColorTexture(1, 1, 1, 0.04)
	Skin.Edges(bar, 1, 1, 1, 0.08)
	bar.buttons = {}
	local previous
	for _, choice in ipairs(list) do
		local key = choice[1]
		local button = CreateFrame("Button", nil, bar)
		button:SetPoint("TOP", bar, "TOP", 0, -3)
		button:SetPoint("BOTTOM", bar, "BOTTOM", 0, 3)
		if previous then button:SetPoint("LEFT", previous, "RIGHT", 3, 0) else button:SetPoint("LEFT", bar, "LEFT", 3, 0) end
		button.ground = button:CreateTexture(nil, "BACKGROUND")
		button.ground:SetAllPoints()
		button.text = Skin.CreateText(button, "GameFontHighlightSmall")
		button.text:SetPoint("CENTER")
		button:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 1, -1) end)
		button:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
		button:SetScript("OnClick", function()
			Skin.Play("click")
			bar:Select(key)
			onPick(key)
		end)
		button.key = key
		bar.buttons[#bar.buttons + 1] = button
		previous = button
	end
	-- Each as wide as its words, the bar as wide as them all.
	function bar:SetLabels(labels)
		local width = 3
		for index, button in ipairs(self.buttons) do
			button.text:SetText(labels[index] or "")
			local w = math.max(56, U.Measure(button.text, "GetStringWidth", 50) + 24)
			button:SetWidth(w)
			width = width + w + 3
		end
		self:SetWidth(width)
	end
	function bar:Select(key)
		self.chosen = key
		for _, button in ipairs(self.buttons) do
			local on = button.key == key
			button.ground:SetColorTexture(on and 0.16 or 0, on and 0.14 or 0, on and 0.06 or 0, on and 1 or 0)
			button.text:SetTextColor(on and 1 or 0.72, on and 0.82 or 0.68, on and 0 or 0.61)
		end
	end
	local labels = {}
	for index, choice in ipairs(list) do labels[index] = choice[2] end
	bar:SetLabels(labels)
	return bar
end

-- An item ---------------------------------------------------------------------------------------------------------

-- An item's square: its icon, an edge in its quality's color. square:Set(icon, quality).
function Skin.Icon(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size, size)
	holder.ground = holder:CreateTexture(nil, "BACKGROUND")
	holder.ground:SetAllPoints()
	holder.ground:SetColorTexture(0.09, 0.11, 0.16, 1)
	holder.texture = holder:CreateTexture(nil, "ARTWORK")
	holder.texture:SetPoint("TOPLEFT", 1, -1)
	holder.texture:SetPoint("BOTTOMRIGHT", -1, 1)
	holder.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	holder.edges = Skin.Edges(holder, 1, 1, 1, 0.2)
	function holder:Set(icon, quality)
		self.texture:SetTexture(icon)
		if quality then
			local r, g, b = U.QualityColor(quality)
			self.edges.Color(r, g, b, 0.85)
		else
			self.edges.Color(1, 1, 1, 0.2)
		end
	end
	return holder
end

-- An amount of money: gold, silver, copper (money:ShowCopper(false) hides the copper box).
-- money:Set(copper), money:Get().
function Skin.Money(parent, onChange)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(190, 28)
	local function Box(width, icon, anchor)
		local input = Skin.CreateInput(box, nil, 7)
		input:SetSize(width, 28)
		input:SetNumeric(true)
		input:SetJustifyH("RIGHT")
		input.coin = box:CreateTexture(nil, "ARTWORK")
		input.coin:SetSize(13, 13)
		input.coin:SetTexture(icon)
		input.coin:SetPoint("LEFT", input, "RIGHT", 3, 0)
		if anchor then input:SetPoint("LEFT", anchor, "RIGHT", 8, 0) else input:SetPoint("LEFT") end
		input:SetScript("OnTextChanged", function() if onChange then onChange() end end)
		input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		return input
	end
	box.gold = Box(62, "Interface\\MoneyFrame\\UI-GoldIcon")
	box.silver = Box(38, "Interface\\MoneyFrame\\UI-SilverIcon", box.gold.coin)
	box.copper = Box(38, "Interface\\MoneyFrame\\UI-CopperIcon", box.silver.coin)
	function box:Set(copper)
		copper = math.max(0, math.floor(copper or 0))
		self.gold:SetText(tostring(math.floor(copper / 10000)))
		self.silver:SetText(tostring(math.floor(copper / 100) % 100))
		self.copper:SetText(tostring(copper % 100))
	end
	function box:Get()
		local copper = self.copper:IsShown() and (tonumber(self.copper:GetText()) or 0) or 0
		return (tonumber(self.gold:GetText()) or 0) * 10000 + (tonumber(self.silver:GetText()) or 0) * 100 + copper
	end
	function box:ShowCopper(shown)
		self.copper:SetShown(shown)
		self.copper.coin:SetShown(shown)
	end
	return box
end

-- A line of a summary: its words on the left, its value on the right (line.label, line.value).
function Skin.SummaryLine(parent, anchor, label, big)
	local line = CreateFrame("Frame", nil, parent)
	line:SetHeight(big and 22 or 16)
	if anchor then line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6) else line:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -12) end
	line:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
	line.label = Skin.Text(line, big and "GameTooltipText" or "GameTooltipTextSmall", big and "soft" or "muted")
	line.label:SetPoint("LEFT")
	line.label:SetText(label)
	line.value = Skin.Text(line, big and "GameTooltipHeaderText" or "GameTooltipTextSmall", big and "good" or "soft")
	line.value:SetPoint("RIGHT")
	return line
end

-- A window ------------------------------------------------------------------------------------------------------

-- A window's heading: the small kicker ("WANDERER"), its title under it in gold. Returns them and the
-- window's margin (the skin's, plus extra). extra: a number (that margin), or { margin, settings }: settings,
-- a page of Wanderer's settings ("tooltips", "ext:training") or a function, puts a cog left of the window's
-- cross, opening that page (the window stays open; window.settingsCog).
function Skin.Header(window, kickerText, titleText, extra, titleTemplate)
	local options = type(extra) == "table" and extra or {}
	if type(extra) == "table" then extra = extra.margin end
	if options.settings then
		local settings = options.settings
		local cog = Skin.GlyphButton(window, "cog", 14, ns.L.SETTINGS_COG, function()
			if type(settings) == "function" then settings() elseif ns.OpenOptions then ns.OpenOptions(settings) end
		end)
		cog:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, -6)
		cog:SetFrameLevel(window:GetFrameLevel() + 5)
		window.settingsCog, window.cog = cog, cog
	end
	local margin = Skin.Margin() + (extra or 8)
	local kicker = Skin.CreateKicker(window, kickerText or "Wanderer")
	kicker:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	local title = Skin.CreateText(window, titleTemplate or "GameTooltipHeaderText", 1, 0.82, 0)
	title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -3)
	if titleText then title:SetText(titleText) end
	return kicker, title, margin
end

-- The cross in a window's corner.
function Skin.CloseButton(window, onClose)
	local close = CreateFrame("Button", nil, window)
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
	close.wandererClose = true -- (the cross of a Wanderer window, for those who look for it)
	window.closeButton = close
	close.glyph = Skin.Glyph(close, "close", 11)
	close.glyph:SetPoint("CENTER")
	close:SetScript("OnEnter", function(self) self.glyph:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3]) end)
	close:SetScript("OnLeave", function(self) self.glyph:SetVertexColor(COLORS.label[1], COLORS.label[2], COLORS.label[3]) end)
	close:SetScript("OnMouseDown", function(self) self.glyph:SetPoint("CENTER", 1, -1) end)
	close:SetScript("OnMouseUp", function(self) self.glyph:SetPoint("CENTER", 0, 0) end)
	close:SetScript("OnClick", function()
		if not window.wandererSounds then Skin.Play("close") end
		if onClose then onClose() else window:Hide() end
	end)
	return close
end

-- A window resized by its corner, within bounds: opts { minWidth, minHeight, maxWidth, maxHeight,
-- onStart(), onResized(width, height) (its size, to keep), onSizing() (while dragged) }. Its place is
-- kept as when it is moved (and it holds to its neighbors).
function Skin.Resizable(window, opts)
	window:SetResizable(true)
	if window.SetResizeBounds then
		window:SetResizeBounds(opts.minWidth, opts.minHeight, opts.maxWidth, opts.maxHeight)
	elseif window.SetMinResize then
		window:SetMinResize(opts.minWidth, opts.minHeight)
		if window.SetMaxResize then window:SetMaxResize(opts.maxWidth, opts.maxHeight) end
	end
	local grip = CreateFrame("Button", nil, window)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(window:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	local sizing = false
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		sizing = true
		if opts.onStart then opts.onStart() end
		window:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		if not sizing then return end
		sizing = false
		window:StopMovingOrSizing()
		if opts.onResized then opts.onResized(math.floor(window:GetWidth() + 0.5), math.floor(window:GetHeight() + 0.5)) end
		-- Its place kept as when moved (sizing may anchor it again).
		local keep = window:GetScript("OnDragStop")
		if keep then keep(window) end
	end)
	if opts.onSizing then window:HookScript("OnSizeChanged", function() if sizing then opts.onSizing() end end) end
	function grip:IsSizing() return sizing end
	window.grip = grip
	return grip
end

-- A size kept, within bounds (a saved one may be from other bounds).
function Skin.Within(value, low, high) return math.max(low, math.min(high, value)) end

-- The scale a window is shown at: Wanderer's (Skin.Scale), made smaller when the window would not fit the
-- screen (a tall window on a laptop, a large scale chosen). window:SetScale(Skin.FitScale(window)) in its OnShow.
local SCREEN_ROOM = 48
function Skin.FitScale(window)
	local scale = Skin.Scale()
	local width, height = window:GetWidth(), window:GetHeight()
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
	if type(height) == "number" and height > 0 and type(screenHeight) == "number" and screenHeight > SCREEN_ROOM then
		scale = math.min(scale, (screenHeight - SCREEN_ROOM) / height)
	end
	if type(width) == "number" and width > 0 and type(screenWidth) == "number" and screenWidth > SCREEN_ROOM then
		scale = math.min(scale, (screenWidth - SCREEN_ROOM) / width)
	end
	return math.max(0.5, scale)
end

local ask -- the one window of questions
local question -- the one open: { accept, refuse, text }
local function AskWindow()
	if ask then return ask end
	ask = Skin.CreateWindow("WandererAsk", "DIALOG")
	ask:SetSize(380, 120)
	ask:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	ask:EnableMouse(true)
	ask.words = Skin.Text(ask, "GameTooltipText", "text")
	ask.words:SetJustifyH("CENTER")
	ask.words:SetWidth(340)
	ask.words:SetSpacing(2)
	ask.yes = Skin.Button(ask, YES or "Yes", function()
		local open = question
		if open and open.input then
			open.value = strtrim(ask.input:GetText() or "")
			if open.value == "" and not open.allowEmpty then return end
		end
		question = nil
		ask:Hide()
		if open and open.accept then open.accept(open.value) end
	end, "main", 110)
	ask.no = Skin.Button(ask, NO or "No", function()
		local open = question
		question = nil
		ask:Hide()
		if open and open.refuse then open.refuse() end
	end, nil, 110)
	ask.no:SetHeight(36)
	-- A line to write in, for the questions that ask for words.
	ask.input = Skin.CreateInput(ask, nil, 255, {
		onEnter = function() if ask.yes:IsEnabled() then ask.yes:Click() end end,
		onEscape = function() ask.no:Click() end,
	})
	ask.input:SetWidth(340)
	ask.input:Hide()
	-- Closed otherwise (Escape, the cross): as if refused, once. One asked in its place keeps the window
	-- shown, so the first is let go unanswered.
	if UISpecialFrames then table.insert(UISpecialFrames, "WandererAsk") end
	Skin.CloseButton(ask, function() ask.no:Click() end)
	ask:HookScript("OnHide", function()
		local open = question
		question = nil
		if open and open.refuse then open.refuse() end
	end)
	ask:HookScript("OnShow", function(self) self:SetScale(Skin.Scale()) end)
	return ask
end

local function Layout(window)
	local margin = Skin.Margin() + 10
	local input = window.input:IsShown() and 34 or 0
	local height = U.Measure(window.words, "GetStringHeight", 14)
	window:SetSize(340 + margin * 2, margin + height + 14 + input + 36 + margin)
	window.words:ClearAllPoints()
	window.words:SetPoint("TOP", window, "TOP", 0, -margin)
	window.input:ClearAllPoints()
	window.input:SetPoint("TOP", window.words, "BOTTOM", 0, -10)
	local anchor = window.input:IsShown() and window.input or window.words
	window.yes:ClearAllPoints()
	window.no:ClearAllPoints()
	if window.no:IsShown() then
		window.yes:SetPoint("TOPRIGHT", anchor, "BOTTOM", -6, -14)
		window.no:SetPoint("TOPLEFT", anchor, "BOTTOM", 6, -14)
	else
		window.yes:SetPoint("TOP", anchor, "BOTTOM", 0, -14)
	end
	Skin.Get(window):Layout()
end

local function Open(open)
	local window = AskWindow()
	question = open
	window.words:SetText(open.text or "")
	window.input:SetShown(open.input ~= nil)
	window.no:SetShown(not open.copy)
	window.yes:SetText(open.yesText or YES or "Yes")
	window.no:SetText(open.noText or NO or "No")
	window.yes:Fit()
	window.no:Fit()
	window.yes:SetWidth(math.max(110, window.yes:GetWidth()))
	window.no:SetWidth(math.max(110, window.no:GetWidth()))
	if open.input then
		window.input:SetMaxLetters(open.input.maxLetters or 0)
		window.input:SetText(open.input.default or "")
	end
	-- (over a window of a higher layer when asked: the placing mode's, for one; the dialogs' layer otherwise)
	window:SetFrameStrata(open.strata or "DIALOG")
	Layout(window)
	if window:IsShown() then if window.Raise then window:Raise() end else window:Show() end
	if open.input then
		window.input:SetFocus()
		window.input:HighlightText()
	end
end

-- A question before acting: yes does it, no lets it go. Another one asked in its place does not answer
-- the first. Returns the question (to put away later: Skin.CancelAsk). opts: { strata } (a layer over the
-- dialogs' one, for that question only).
function Skin.Ask(text, accept, refuse, opts)
	local open = { text = text, accept = accept, refuse = refuse, strata = type(opts) == "table" and opts.strata or nil }
	Open(open)
	return open
end

-- The question open answered (tests).
function Skin.AnswerAsk(yes)
	if not (ask and ask:IsShown()) then return false end
	local button = yes and ask.yes or ask.no
	local run = button:GetScript("OnClick")
	if run then run(button) end
	return true
end

-- A name to give, or a text to paste: onAccept(text) with the words written (trimmed; nothing when empty).
-- default: the words it opens with; maxLetters: how many (0 or nil: no limit).
function Skin.AskText(prompt, default, onAccept, maxLetters, allowEmpty)
	Open({
		text = prompt or "", input = { default = default, maxLetters = (maxLetters or 0) > 0 and maxLetters or 0 },
		accept = onAccept, yesText = OKAY or "OK", noText = CANCEL or "Cancel", allowEmpty = allowEmpty,
	})
end

-- A question open (a window waits before acting on its own).
function Skin.Asking() return ask ~= nil and ask:IsShown() end

-- This question (Skin.Ask's) still the one open: not answered, closed, nor replaced by another.
function Skin.IsAsking(handle) return handle ~= nil and question == handle and Skin.Asking() end

-- A question still open put away (its window closing): as if refused. Given one (Skin.Ask's), only that one,
-- if it is still the one open.
function Skin.CancelAsk(only)
	if ask and ask:IsShown() and (not only or question == only) then ask.no:Click() end
end

-- A text to copy (an address, a scale, a profile): shown selected under a few words, for Ctrl+C.
function Skin.ShowCopy(prompt, text)
	Open({ text = prompt or "", input = { default = text or "", maxLetters = 0 }, copy = true, allowEmpty = true, yesText = CLOSE or OKAY or "Close" })
end

-- A table ---------------------------------------------------------------------------------------------------------
-- Column titles (optional), then rows: an item's square (optional), a name (in its quality's color, or
-- entry.color), stepped right by entry.indent, a chip under it, values in columns, a button at the end;
-- or a section's title (entry.header). The wheel scrolls it, a thin bar beside shows where you are.
-- spec: { width, rows (the most shown), rowHeight, columns = { { key, title, width, justify, sort } },
--   titles (false: none), icon (false: none), nameTitle, nameSort, action (a button's width),
--   onClick(entry, mouse), onDraw(), onSort(sort) }.
-- table.offset, table.rows (those shown: table.count), table:Clamp(total), table:Fit(height),
-- table:SetSort(sort), table.empty (a text for an empty table);
-- row:Fill(entry, chosen, values, chip, tone, actionText, actionFn).
local BAR = 10
local THUMB_MIN = 18

function Skin.Table(parent, spec)
	local list = CreateFrame("Frame", nil, parent)
	local rowHeight = spec.rowHeight or Skin.ROW.normal
	local top = spec.titles == false and 0 or 18
	local iconSize = spec.icon ~= false and rowHeight - 8 or 0
	list:SetSize(spec.width, top + spec.rows * rowHeight)
	list:EnableMouseWheel(true)
	list.offset, list.rows, list.count, list.total = 0, {}, spec.rows, 0
	list:SetScript("OnMouseWheel", function(self, delta)
		self.offset = math.max(0, self.offset - delta * 3)
		spec.onDraw()
	end)
	-- The scroll bar (the one of every list), in rows.
	local bar = Skin.ScrollBar(list, function(offset)
		offset = math.floor(offset + 0.5)
		if offset ~= list.offset then
			list.offset = offset
			spec.onDraw()
		end
	end)
	bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -top)
	bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
	local function DrawBar() bar:Set(list.total, list.count, list.offset) end
	-- The column titles (left of the rows' buttons and the bar).
	local right = -(BAR + (spec.action and spec.action + 10 or 0))
	local titles = {}
	for index = #spec.columns, 1, -1 do
		local column = spec.columns[index]
		if top > 0 then
			local title = Skin.Caps(list, column.title)
			title:SetWidth(column.width)
			title:SetJustifyH(column.justify or "RIGHT")
			title:SetPoint("TOPRIGHT", list, "TOPRIGHT", right, 0)
			titles[index] = title
		end
		column.right = right
		right = right - column.width - 10
	end
	local sorters = {}
	if top > 0 then
		local nameTitle = Skin.Caps(list, spec.nameTitle or "")
		nameTitle:SetPoint("TOPLEFT", list, "TOPLEFT", iconSize > 0 and iconSize + 14 or 6, 0)
		-- The titles that sort: a click on them.
		local function Sorter(title, sort)
			if not (sort and spec.onSort) then return end
			local button = CreateFrame("Button", nil, list)
			button:SetAllPoints(title)
			button:SetScript("OnClick", function()
				Skin.Play("click")
				spec.onSort(sort)
			end)
			sorters[sort] = title
		end
		Sorter(nameTitle, spec.nameSort)
		for index, column in ipairs(spec.columns) do Sorter(titles[index], column.sort) end
	end
	list.titles = titles
	-- The column sorted by, in gold with an arrow (down unless descending is false: up).
	list.sortArrow = Skin.Glyph(list, "down", 9, "OVERLAY")
	list.sortArrow:SetVertexColor(1, 0.82, 0)
	list.sortArrow:Hide()
	function list:SetSort(sort, descending)
		self.sortArrow:Hide()
		for key, title in pairs(sorters) do
			local on = key == sort
			local c = on and COLORS.gold or COLORS.muted
			title:SetTextColor(c[1], c[2], c[3])
			if on then
				self.sortArrow:ClearAllPoints()
				if title:GetJustifyH() == "LEFT" then
					self.sortArrow:SetPoint("LEFT", title, "LEFT", U.Measure(title, "GetStringWidth", 30) + 4, 0)
				else
					self.sortArrow:SetPoint("RIGHT", title, "LEFT", -3, 0)
				end
				Skin.SetGlyph(self.sortArrow, descending == false and "up" or "down")
				self.sortArrow:Show()
			end
		end
	end
	local leftmost = right + 10
	for index = 1, spec.rows do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(rowHeight - 2)
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -top - (index - 1) * rowHeight)
		row:SetPoint("RIGHT", list, "RIGHT", -BAR, 0)
		row.chosen = row:CreateTexture(nil, "BACKGROUND")
		row.chosen:SetAllPoints()
		row.chosen:SetColorTexture(1, 0.82, 0, 0.08)
		row.chosenEdges = Skin.Edges(row, 1, 0.82, 0, 0)
		row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		row.hover:SetAllPoints()
		row.hover:SetColorTexture(1, 1, 1, 0.04)
		row.hover:Hide()
		if iconSize > 0 then
			row.icon = Skin.Icon(row, iconSize)
			row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
		end
		row.cells = {}
		for _, column in ipairs(spec.columns) do
			local cell = Skin.Text(row, "GameTooltipText", "soft")
			cell:SetWidth(column.width)
			cell:SetJustifyH(column.justify or "RIGHT")
			cell:SetPoint("RIGHT", row, "RIGHT", column.right + BAR, 0)
			if cell.SetWordWrap then cell:SetWordWrap(false) end
			row.cells[column.key] = cell
		end
		row.name = Skin.CreateText(row, "GameTooltipText")
		row.name:SetJustifyH("LEFT")
		if row.name.SetWordWrap then row.name:SetWordWrap(false) end
		row.chip = Skin.Chip(row)
		row.chip:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
		if spec.action then
			row.action = Skin.Button(row, "", function(self) if self.run then self.run() end end, nil, spec.action)
			row.action:SetWidth(spec.action)
			row.action:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		end
		row.header = Skin.Text(row, "GameTooltipTextSmall", "label")
		row.header:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 4)
		-- (a row that opens something says so, a chevron at its end: spec.chevron)
		if spec.chevron then
			row.more = Skin.Glyph(row, "chevron", 10)
			row.more:SetAlpha(0.8)
			row.more:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		end
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			if self.entry and not self.entry.header then
				Skin.Play("click")
				spec.onClick(self.entry, mouse)
			end
		end)
		-- Hovered: its item's tooltip, else its own words (entry.tip: a line, or { lines }; its whole name
		-- when it was cut).
		row:SetScript("OnEnter", function(self)
			local entry = self.entry
			if not entry or entry.header then return end
			self.hover:Show()
			if entry.link then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:SetHyperlink(entry.link)
				GameTooltip:Show()
				return
			end
			local tip = entry.tip
			if not tip and self.name:IsTruncated() then tip = self.name:GetText() end
			if not tip then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			for _, line in ipairs(type(tip) == "table" and tip or { tip }) do GameTooltip:AddLine(line, 1, 1, 1, true) end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(self)
			self.hover:Hide()
			GameTooltip:Hide()
		end)
		function row:Fill(entry, chosen, values, chip, tone, actionText, actionFn)
			self.entry = entry
			self:SetShown(entry ~= nil and index <= list.count)
			if self.action then
				self.action:SetShown(entry ~= nil and not entry.header and actionText ~= nil)
				self.action:SetText(actionText or "")
				self.action.run = actionFn
			end
			if not entry then return end
			local header = entry.header ~= nil
			self.header:SetShown(header)
			if self.icon then self.icon:SetShown(not header) end
			self.name:SetShown(not header)
			self.chosen:SetShown(chosen and not header or false)
			self.chosenEdges.Color(1, 0.82, 0, chosen and not header and 0.3 or 0)
			for key, cell in pairs(self.cells) do
				cell:SetShown(not header)
				cell:SetText(values and values[key] or "")
			end
			if self.more then self.more:SetShown(not header and not (self.action and self.action:IsShown())) end
			if header then
				self.header:SetText(U.Upper(entry.header))
				self.chip:Set(nil)
				return
			end
			if self.icon then self.icon:Set(entry.icon, entry.quality) end
			self.name:SetText(entry.name or "")
			if entry.color then
				self.name:SetTextColor(entry.color[1], entry.color[2], entry.color[3])
			else
				Skin.Quality(self.name, entry.quality)
			end
			self.chip:Set(chip, tone)
			-- (stepped right by its indent; with a chip, the name a little higher)
			local lift = chip and 7 or 0
			self.name:ClearAllPoints()
			if self.icon then
				self.name:SetPoint("LEFT", self.icon, "RIGHT", 8 + (entry.indent or 0), lift)
			else
				self.name:SetPoint("LEFT", self, "LEFT", 6 + (entry.indent or 0), lift)
			end
			self.name:SetPoint("RIGHT", self, "RIGHT", leftmost + BAR - 10 - (self.more and self.more:IsShown() and (self.more:GetWidth() + 6) or 0), lift)
		end
		list.rows[index] = row
	end
	-- The offset kept within what there is to show (and the bar drawn): call it before filling the rows.
	function list:Clamp(total)
		self.total = total
		self.offset = math.max(0, math.min(self.offset, total - self.count))
		DrawBar()
		return self.offset
	end
	-- As many rows as a height holds (up to those made).
	function list:Fit(height)
		local count = math.max(1, math.min(#self.rows, math.floor((height - top) / rowHeight)))
		if count == self.count then return end
		self.count = count
		self:SetHeight(top + count * rowHeight)
		for index, row in ipairs(self.rows) do
			if index > count then row:Hide() end
		end
		spec.onDraw()
	end
	list.empty = Skin.Text(list, "GameTooltipText", "muted")
	list.empty:SetPoint("TOP", list, "TOP", 0, -50)
	list.empty:SetWidth(spec.width - 40)
	list.empty:Hide()
	return list
end

-- A scroll bar ------------------------------------------------------------------------------------------------
-- The one of every list: a thin golden rail, a thumb as long as the part shown, dragged; the rail clicked, a
-- page. In whatever unit the list counts (rows, or pixels): bar:Set(total, shown, offset) draws it (hidden
-- when everything fits); onOffset(offset) is called while it is dragged or clicked. Placed by its owner
-- (TOPRIGHT and BOTTOMRIGHT); Skin.SCROLL_WIDTH is the room it takes.
Skin.SCROLL_WIDTH = BAR
function Skin.ScrollBar(parent, onOffset)
	local bar = CreateFrame("Button", nil, parent)
	bar:SetWidth(BAR - 2)
	local rail = bar:CreateTexture(nil, "BACKGROUND")
	rail:SetColorTexture(0.85, 0.75, 0.5, 0.22)
	rail:SetWidth(2)
	rail:SetPoint("TOP")
	rail:SetPoint("BOTTOM")
	local thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(BAR - 4)
	thumb.fill = thumb:CreateTexture(nil, "ARTWORK")
	thumb.fill:SetAllPoints()
	thumb.fill:SetColorTexture(0.85, 0.75, 0.5, 0.5)
	bar.thumb = thumb
	bar.total, bar.shown, bar.offset = 0, 0, 0
	bar:Hide()
	local function Range() return math.max(0, bar.total - bar.shown) end
	local function OffsetAt(position)
		local free = bar:GetHeight() - thumb:GetHeight()
		if free <= 0 or Range() <= 0 then return 0 end
		return math.max(0, math.min(1, position / free)) * Range()
	end
	local function CursorTop()
		local _, y = GetCursorPosition()
		return (bar:GetTop() or 0) - y / bar:GetEffectiveScale()
	end
	function bar:Set(total, shown, offset)
		self.total, self.shown, self.offset = total or 0, shown or 0, offset or 0
		local more = Range() > 0
		self:SetShown(more)
		if not more then return end
		local height = self:GetHeight() or 0
		if height <= 0 then return end
		local size = math.max(THUMB_MIN, math.floor(height * self.shown / self.total))
		local position = math.floor((height - size) * math.min(1, self.offset / Range()) + 0.5)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", self, "TOP", 0, -position)
	end
	thumb:SetScript("OnMouseDown", function(self)
		self.grab = CursorTop() - ((self:GetTop() and bar:GetTop()) and (bar:GetTop() - self:GetTop()) or 0)
		self:SetScript("OnUpdate", function(own)
			-- Let go anywhere: the drag ends.
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return own:SetScript("OnUpdate", nil) end
			onOffset(OffsetAt(CursorTop() - own.grab))
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnEnter", function(self) self.fill:SetColorTexture(1, 0.82, 0, 0.75) end)
	thumb:SetScript("OnLeave", function(self) self.fill:SetColorTexture(0.85, 0.75, 0.5, 0.5) end)
	bar:SetScript("OnClick", function(self)
		local below = CursorTop() > (self:GetTop() or 0) - (thumb:GetTop() or 0) + thumb:GetHeight()
		onOffset(math.max(0, math.min(Range(), self.offset + (below and self.shown or -self.shown))))
	end)
	return bar
end

-- Tabs ----------------------------------------------------------------------------------------------------------
-- A row of tabs (the pages of a window): words, the one shown underlined in gold, a count beside those where
-- something waits. list: { { key, label } }; onPick(key). tabs:Select(key), tabs:SetBadge(key, count, tone),
-- tabs:SetLabel(key, label); tabs.byKey[key] is each tab (its .text, .badge, .line). Placed by its owner
-- (its BOTTOMLEFT on a rule's TOPLEFT, as a rule).
function Skin.Tabs(parent, list, onPick)
	local tabs = CreateFrame("Frame", nil, parent)
	tabs:SetHeight(30)
	tabs.byKey, tabs.order, tabs.made = {}, {}, {}
	local function MakeTab()
		local tab = CreateFrame("Button", nil, tabs)
		tab:SetHeight(30)
		tab.text = Skin.CreateText(tab, "GameFontNormal")
		tab.text:SetPoint("LEFT")
		tab.badge = Skin.Chip(tab)
		tab.badge:SetPoint("LEFT", tab.text, "RIGHT", 7, 0)
		tab.line = tab:CreateTexture(nil, "ARTWORK")
		tab.line:SetColorTexture(1, 0.82, 0, 1)
		tab.line:SetHeight(2)
		tab.line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, -1)
		tab.line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, -1)
		tab.line:Hide()
		tab:SetScript("OnMouseDown", function(self) self.text:SetPoint("LEFT", 1, -1) end)
		tab:SetScript("OnMouseUp", function(self) self.text:SetPoint("LEFT", 0, 0) end)
		tab:SetScript("OnEnter", function(self) if self.key ~= tabs.chosen then self.text:SetTextColor(COLORS.kicker[1], COLORS.kicker[2], COLORS.kicker[3]) end end)
		tab:SetScript("OnLeave", function(self) if self.key ~= tabs.chosen then self.text:SetTextColor(COLORS.label[1], COLORS.label[2], COLORS.label[3]) end end)
		tab:SetScript("OnClick", function(self)
			Skin.Play("click")
			tabs:Select(self.key)
			onPick(self.key)
		end)
		return tab
	end
	-- (another list of tabs in the same bar: its buttons used again, those left over hidden)
	function tabs:SetList(choices)
		self.byKey, self.order = {}, {}
		for index, choice in ipairs(choices) do
			local tab = self.made[index] or MakeTab()
			self.made[index] = tab
			tab.key = choice[1]
			tab.text:SetText(choice[2] or "")
			tab.badge:Set(nil)
			tab:Show()
			self.byKey[tab.key] = tab
			self.order[index] = tab
		end
		for index = #choices + 1, #self.made do self.made[index]:Hide() end
		self:Layout()
		self:Select(self.chosen)
	end
	function tabs:Layout()
		local previous, width = nil, 0
		for _, tab in ipairs(self.order) do
			tab:SetWidth(U.Measure(tab.text, "GetStringWidth", 60) + (tab.badge:IsShown() and tab.badge:GetWidth() + 8 or 0))
			tab:ClearAllPoints()
			if previous then tab:SetPoint("LEFT", previous, "RIGHT", 26, 0) else tab:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0) end
			width = width + tab:GetWidth() + (previous and 26 or 0)
			previous = tab
		end
		self:SetWidth(math.max(1, width))
	end
	function tabs:Select(key)
		self.chosen = key
		for _, tab in ipairs(self.order) do
			local on = tab.key == key
			local c = on and COLORS.gold or COLORS.label
			tab.text:SetTextColor(c[1], c[2], c[3])
			tab.line:SetShown(on)
		end
	end
	function tabs:SetBadge(key, count, tone)
		local tab = self.byKey[key]
		if not tab then return end
		tab.badge:Set(count and count > 0 and tostring(count) or nil, tone or "red")
		self:Layout()
	end
	function tabs:SetLabel(key, label)
		local tab = self.byKey[key]
		if not tab then return end
		tab.text:SetText(label or "")
		self:Layout()
	end
	tabs:SetList(list)
	return tabs
end

-- A text that waits: dots come and go after its words (Skin.Waiting(text, words)); Skin.Waiting(text) stops
-- it and leaves the words. One driver for all of them.
local waiting, waitDriver, waitClock = {}, nil, 0
local DOTS = { "", ".", "..", "..." }
local function DriveWaiting(_, elapsed)
	waitClock = waitClock + elapsed
	if waitClock < 0.45 then return end
	waitClock = 0
	local any = false
	for text, state in pairs(waiting) do
		state.step = state.step % #DOTS + 1
		text:SetText(state.words .. DOTS[state.step])
		any = true
	end
	if not any then waitDriver:SetScript("OnUpdate", nil) end
end
function Skin.Waiting(text, words)
	if not words then
		local state = waiting[text]
		if state then text:SetText(state.words) end
		waiting[text] = nil
		return
	end
	if not waitDriver then waitDriver = CreateFrame("Frame") end
	waiting[text] = { words = words, step = 1 }
	text:SetText(words)
	waitDriver:SetScript("OnUpdate", DriveWaiting)
end

-- A thin line of progress (a queue, a wait): a faint rail, a gold fill. line:Set(share) fills it (0 to 1);
-- line:Wander(on) shows instead a short gold piece (40 px) going to and fro at 120 px a second (how long is
-- unknown). Placed and sized by its owner (the fill follows its width); height: 2 unless said. One driver for
-- every line wandering, asleep when none is (or none is seen).
local wandering, wanderDriver = {}, nil
local WANDER_PIECE, WANDER_SPEED = 40, 120
local function DriveWander(_, elapsed)
	local any = false
	for line, travelled in pairs(wandering) do
		local width = line:GetWidth() or 0
		local size = math.min(WANDER_PIECE, math.max(1, width))
		local room = math.max(1, width - size)
		travelled = (travelled + elapsed * WANDER_SPEED) % (room * 2)
		wandering[line] = travelled
		local x = travelled > room and room * 2 - travelled or travelled
		line.piece:SetWidth(size)
		line.piece:ClearAllPoints()
		line.piece:SetPoint("LEFT", line, "LEFT", x, 0)
		any = true
	end
	if not any then wanderDriver:SetScript("OnUpdate", nil) end
end
function Skin.ProgressLine(parent, height)
	local gold = COLORS.gold
	local line = CreateFrame("Frame", nil, parent)
	line:SetHeight(height or 2)
	line.rail = line:CreateTexture(nil, "BACKGROUND")
	line.rail:SetAllPoints()
	line.rail:SetColorTexture(1, 1, 1, 0.07)
	line.fill = line:CreateTexture(nil, "ARTWORK")
	line.fill:SetPoint("TOPLEFT")
	line.fill:SetPoint("BOTTOMLEFT")
	line.fill:SetColorTexture(gold[1], gold[2], gold[3], 0.9)
	line.piece = line:CreateTexture(nil, "ARTWORK")
	line.piece:SetHeight(height or 2)
	line.piece:SetColorTexture(gold[1], gold[2], gold[3], 0.9)
	line.piece:Hide()
	line.share, line.wanders = 0, false
	local function Draw(self)
		local width = self:GetWidth() or 0
		self.fill:SetWidth(math.max(0.001, width * self.share))
		self.fill:SetShown(self.share > 0 and not self.wanders)
	end
	local function Drive(self)
		if self.wanders and self:IsVisible() then
			wandering[self] = wandering[self] or 0
			if not wanderDriver then wanderDriver = CreateFrame("Frame") end
			wanderDriver:SetScript("OnUpdate", DriveWander)
		else
			wandering[self] = nil
		end
	end
	function line:Set(share)
		self.share = math.max(0, math.min(1, tonumber(share) or 0))
		Draw(self)
	end
	function line:Wander(on)
		self.wanders = on and true or false
		self.piece:SetShown(self.wanders)
		Drive(self)
		Draw(self)
	end
	line:SetScript("OnSizeChanged", Draw)
	line:SetScript("OnShow", Drive)
	line:SetScript("OnHide", Drive)
	return line
end

-- Cards ---------------------------------------------------------------------------------------------------------
-- A line of a card (Wanderer's card, a notice's choices): a glyph, its words, a key or a count at its right,
-- gold under the mouse. row:Set({ text, glyph, right, role, onClick, hint }) (nil: hidden).
Skin.CARD_ROW = 22
function Skin.CardRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(Skin.CARD_ROW)
	row:RegisterForClicks("LeftButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 0.82, 0, 0.08)
	row.hover:Hide()
	row.glyph = Skin.Glyph(row, "chevron", 14)
	row.glyph:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.right = Skin.Text(row, "GameTooltipTextSmall", "muted")
	row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.text = Skin.Text(row, "GameTooltipText", "soft")
	row.text:SetPoint("LEFT", row.glyph, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	if row.text.SetWordWrap then row.text:SetWordWrap(false) end
	local function Paint(self, on)
		local c = COLORS[on and "gold" or (self.role or "soft")] or COLORS.soft
		self.text:SetTextColor(c[1], c[2], c[3])
		local g = COLORS[on and "gold" or (self.role == "warn" and "warn" or "label")]
		self.glyph:SetVertexColor(g[1], g[2], g[3])
		self.hover:SetShown(on)
	end
	function row:Set(spec)
		self.spec = spec
		self:SetShown(spec ~= nil)
		if not spec then return end
		self.role = spec.role
		self.text:SetText(spec.text or "")
		self.right:SetText(spec.right or "")
		self.glyph:SetShown(spec.glyph ~= false)
		if spec.glyph then Skin.SetGlyph(self.glyph, spec.glyph) end
		Paint(self, false)
	end
	row:SetScript("OnEnter", function(self)
		Paint(self, true)
		local hint = self.spec and self.spec.hint
		if hint then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(type(hint) == "function" and hint() or hint, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		Paint(self, false)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if not (self.spec and self.spec.onClick) then return end
		Skin.Play("click")
		self.spec.onClick(self)
	end)
	return row
end

-- A card made to close: in front of everything, closed by Escape (its name in the game's list), a click
-- anywhere else (not on its owner) or its owner hidden. card.owner: what opened it.
function Skin.Closable(card, name)
	card:EnableMouse(true)
	card:SetClampedToScreen(true)
	card:SetScript("OnEvent", function(self)
		if self:IsMouseOver() or (self.owner and self.owner.IsMouseOver and self.owner:IsMouseOver()) then return end
		self:Hide()
	end)
	card:HookScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
	card:HookScript("OnHide", function(self)
		self:UnregisterAllEvents()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
	return card
end

-- A small card of choices beside what asked for it (owner; at the cursor when spec.atCursor): a title, its
-- rows ({ text, glyph, hint, onClick, role, right }: a click chooses and closes; run: onClick's other name, as
-- Skin.Card's rows had it), a muted line at its foot.
-- One at a time; Skin.ActionCard(nil) closes it.
local actionCard
function Skin.ActionCard(owner, spec)
	if not spec then
		if actionCard then actionCard:Hide() end
		return nil
	end
	if not actionCard then
		actionCard = Skin.CreateWindow("WandererActionCard", "DIALOG")
		Skin.Closable(actionCard, "WandererActionCard")
		actionCard.title = Skin.Caps(actionCard, "", "kicker")
		actionCard.foot = Skin.Text(actionCard, "GameTooltipTextSmall", "muted")
		actionCard.rows = {}
	end
	local card, m = actionCard, Skin.Margin() + 6
	local width = spec.width or 240
	card:SetSize(width, 10)
	card.owner = owner
	card.title:SetText(spec.title and U.Upper(spec.title) or "")
	card.title:ClearAllPoints()
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", m, -m)
	card.title:SetShown(spec.title ~= nil)
	local y = m + (spec.title and 18 or 0)
	for index, entry in ipairs(spec.rows or {}) do
		local row = card.rows[index] or Skin.CardRow(card)
		card.rows[index] = row
		local run = entry.onClick or entry.run
		row:Set({ text = entry.text, glyph = entry.glyph or entry.sign or false, hint = entry.hint, role = entry.role, right = entry.right,
			onClick = function(self)
				card:Hide()
				if run then run(self) end
			end })
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", card, "TOPLEFT", m - 6, -y)
		row:SetPoint("RIGHT", card, "RIGHT", -(m - 6), 0)
		y = y + Skin.CARD_ROW
	end
	for index = #(spec.rows or {}) + 1, #card.rows do card.rows[index]:Set(nil) end
	card.foot:SetShown(spec.foot ~= nil)
	if spec.foot then
		card.foot:SetText(spec.foot)
		card.foot:SetWidth(width - m * 2)
		card.foot:ClearAllPoints()
		card.foot:SetPoint("TOPLEFT", card, "TOPLEFT", m, -(y + 6))
		y = y + 6 + U.Measure(card.foot, "GetStringHeight", 12)
	end
	card:SetSize(width, y + m)
	card:SetScale(Skin.Scale())
	card:ClearAllPoints()
	local x, cy
	if GetCursorPosition then x, cy = GetCursorPosition() end
	local scale = card:GetEffectiveScale() or 1
	if (spec.atCursor or not owner) and x and cy and scale > 0 then
		card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 4, cy / scale - 4)
	elseif owner then
		card:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -8)
	end
	Skin.Get(card):Layout()
	card:Show()
	return card
end

-- A card of choices -------------------------------------------------------------------------------------------
-- A small window of choices beside what it is about (an item, a section, a set): its heading (a square when it
-- has one, a name, a line saying what it is now), big tiles (a sign, a word, a key 1 to 9; the one now in gold,
-- those that cannot be used dimmed), a quiet list (a gold button among them when there is a main thing to do), a
-- line of keys. Closed by a choice, Escape, a click elsewhere, or what it is about going away. Only words kept:
-- fine in a fight. (The Bags mark picker's card, made one piece of the kit.)
do
	local TILE_WIDTH, TILE_HEIGHT, TILE_GAP, TILE_ICON = 62, 60, 6, 28
	local ICON_SIZE, HEAD_HEIGHT, ROW_HEIGHT, MAIN_HEIGHT = 36, 32, 20, 26

	-- A tile's look: chosen (what is now) in gold, else quiet; under the mouse, its edge warms; dimmed when it
	-- cannot be used.
	local function PaintTile(tile)
		local on, over, off = tile.on, tile:IsMouseOver(), tile.disabled
		local gold, soft = Skin.COLORS.gold, Skin.COLORS.soft
		if on then
			tile.ground:SetColorTexture(gold[1], gold[2], gold[3], 0.13)
			tile.edges.Color(gold[1], gold[2], gold[3], 0.85)
			tile.word:SetTextColor(gold[1], gold[2], gold[3])
		else
			tile.ground:SetColorTexture(1, 1, 1, 0.035)
			tile.edges.Color(gold[1], gold[2], gold[3], over and not off and 0.45 or 0.12)
			tile.word:SetTextColor(soft[1], soft[2], soft[3])
		end
		tile:SetAlpha(off and 0.35 or 1)
		if tile.shownSign then tile.shownSign:SetAlpha((on or (over and not off)) and 1 or 0.8) end
	end

	-- A tile's sign: { file, atlas, coords, size (a smaller picture, sitting on the glyphs' line), glyph (Wanderer's), bar
	-- (a line above the glyph: "to the top"), text (a number, drawn large like a count) }.
	local function SetSign(tile, sign)
		tile.sign:Hide()
		tile.glyph:Hide()
		tile.bar:Hide()
		tile.number:Hide()
		sign = sign or {}
		if sign.text then
			-- (a number, drawn as a count)
			tile.number:SetText(tostring(sign.text))
			tile.shownSign, tile.signY = tile.number, -12
		elseif sign.glyph then
			Skin.SetGlyph(tile.glyph, sign.glyph)
			tile.shownSign, tile.signY = tile.glyph, sign.bar and -17 or -15
			tile.bar:SetShown(sign.bar and true or false)
		else
			local texture = tile.sign
			texture:SetSize(sign.size or TILE_ICON, sign.size or TILE_ICON)
			texture:SetTexCoord(0, 1, 0, 1)
			if not (sign.atlas and texture.SetAtlas and pcall(texture.SetAtlas, texture, sign.atlas)) then
				texture:SetTexture(sign.file)
				if sign.coords then texture:SetTexCoord(unpack(sign.coords)) end
			end
			tile.shownSign, tile.signY = texture, sign.size and sign.size - 31 or -9
		end
		tile.shownSign:ClearAllPoints()
		tile.shownSign:SetPoint("TOP", tile, "TOP", 0, tile.signY)
		tile.shownSign:Show()
	end

	local function MakeTile(card, index)
		local tile = CreateFrame("Button", nil, card)
		tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
		tile.ground = tile:CreateTexture(nil, "BACKGROUND")
		tile.ground:SetAllPoints()
		tile.edges = Skin.Edges(tile, 1, 1, 1, 0.1)
		tile.sign = tile:CreateTexture(nil, "ARTWORK")
		tile.sign:SetSize(TILE_ICON, TILE_ICON)
		tile.glyph = Skin.Glyph(tile, "close", 16)
		tile.bar = tile:CreateTexture(nil, "ARTWORK")
		tile.bar:SetSize(12, 2)
		tile.bar:SetPoint("BOTTOM", tile.glyph, "TOP", 0, 1)
		local label = Skin.COLORS.label
		tile.bar:SetColorTexture(label[1], label[2], label[3], 1)
		tile.number = Skin.Text(tile, "GameFontNormalLarge", "gold")
		tile.number:Hide()
		tile.word = Skin.CreateText(tile, "GameTooltipTextSmall")
		tile.word:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 2, 8)
		tile.word:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -2, 8)
		tile.word:SetJustifyH("CENTER")
		if tile.word.SetWordWrap then tile.word:SetWordWrap(false) end
		-- (its key, small in a corner)
		tile.key = Skin.Text(tile, "GameTooltipTextSmall", "muted")
		tile.key:SetPoint("TOPLEFT", tile, "TOPLEFT", 4, -3)
		-- (only 1 to 9 are keys)
		tile.key:SetText(index <= 9 and tostring(index) or "")
		tile:SetScript("OnEnter", PaintTile)
		tile:SetScript("OnLeave", PaintTile)
		tile:SetScript("OnMouseDown", function(self)
			if self.shownSign and not self.disabled then self.shownSign:SetPoint("TOP", self, "TOP", 1, self.signY - 1) end
		end)
		tile:SetScript("OnMouseUp", function(self)
			if self.shownSign then self.shownSign:SetPoint("TOP", self, "TOP", 0, self.signY) end
		end)
		tile:SetScript("OnClick", function() card.Choose(index) end)
		Skin.Tooltip(tile, function(self)
			local spec = self.spec
			if not spec then return nil end
			local lines = { spec.label }
			if spec.tip then lines[2] = { spec.tip, 0.9, 0.88, 0.82 } end
			return lines
		end, "ANCHOR_BOTTOM")
		return tile
	end

	-- A quiet line of the list: its words, a sign at its end (a chevron: more inside; a check: the one now), or a
	-- back arrow before them (the way out of a list inside the card); role: its words' color.
	local function MakeRow(card)
		local row = CreateFrame("Button", nil, card)
		row:SetHeight(ROW_HEIGHT)
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.05)
		row.text = Skin.Text(row, "GameTooltipTextSmall", "label")
		row.lead = Skin.Glyph(row, "back", 10)
		row.lead:SetPoint("LEFT", row, "LEFT", 6, 0)
		row.sign = Skin.Glyph(row, "chevron", 10)
		row.sign:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		local function Color(self, over)
			local c = Skin.COLORS[(over or self.checked) and "gold" or (self.role or "label")]
			self.text:SetTextColor(c[1], c[2], c[3])
		end
		row:SetScript("OnEnter", function(self)
			Color(self, true)
			if self.hint then Skin.ShowTip(self, self.hint) end
		end)
		row:SetScript("OnLeave", function(self)
			Color(self, false)
			if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
		end)
		row:SetScript("OnClick", function(self)
			Skin.Play("click")
			if self.run then self.run(self) end
		end)
		function row:Fill(entry)
			self.run, self.checked, self.role, self.hint = entry.onClick or entry.run, entry.checked, entry.role, entry.hint
			self.text:ClearAllPoints()
			self.text:SetPoint("LEFT", self, "LEFT", entry.back and 22 or 8, 0)
			self.text:SetPoint("RIGHT", self, "RIGHT", -22, 0)
			self.text:SetText(entry.text)
			self.lead:SetShown(entry.back and true or false)
			local sign = entry.checked and "check" or entry.sign
			self.sign:SetShown(sign ~= nil)
			if sign then
				Skin.SetGlyph(self.sign, sign)
				local c = Skin.COLORS[entry.checked and "gold" or "label"]
				self.sign:SetVertexColor(c[1], c[2], c[3])
			end
			Color(self, false)
			self:Show()
		end
		return row
	end

	-- Keys while it is open: 1 to 9 choose a tile, Escape closes, every other key goes on to the game. Never in a
	-- fight (the game keeps the keys then): the mouse, and Escape through the game's own list of windows.
	local function Keys(card, on)
		on = on and not InCombatLockdown()
		if card.EnableKeyboard then pcall(card.EnableKeyboard, card, on and true or false) end
		if on and card.SetPropagateKeyboardInput then pcall(card.SetPropagateKeyboardInput, card, true) end
	end

	local function OnKey(card, key)
		-- (a key that could not be kept from the game does nothing here: never a spell and a choice at once)
		if InCombatLockdown() then return end
		-- (the card's own keys first: spec.onKey(key) true when it took it)
		if card.onKey and key ~= "ESCAPE" then
			local ok, took = pcall(card.onKey, key, card)
			if ok and took then
				if card.SetPropagateKeyboardInput then pcall(card.SetPropagateKeyboardInput, card, false) end
				return
			end
		end
		local index = tonumber(type(key) == "string" and (key:match("^NUMPAD(%d)$") or key) or "")
		local spec = index and card.specs[index]
		local take = key == "ESCAPE" or (spec ~= nil and not spec.disabled)
		if card.SetPropagateKeyboardInput then pcall(card.SetPropagateKeyboardInput, card, not take) end
		if key == "ESCAPE" then
			Skin.Play("close")
			card:Hide()
		elseif take then
			card.Choose(index)
		end
	end

	-- Beside its owner: on its right, or its left when the owner is on the right of the screen.
	local function Anchor(card, owner)
		card:ClearAllPoints()
		local x = owner.GetCenter and owner:GetCenter()
		local width = UIParent:GetWidth()
		local onRight = type(x) == "number" and type(width) == "number" and width > 0
			and x * owner:GetEffectiveScale() > width * UIParent:GetEffectiveScale() / 2
		if onRight then
			card:SetPoint("TOPRIGHT", owner, "TOPLEFT", -6, 4)
		else
			card:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 4)
		end
	end

	-- Skin.Card(name, withIcon): a card (name: its frame's; withIcon: a square in its heading). Filled by card:Fill({ title, now, icon,
	-- quality, titleColor, body (a frame under the heading; under the tiles with bodyBelow) and bodyHeight, tiles = { { sign, label, tip, on,
	-- disabled, stay, run } }, perRow, minWidth, rows = { { text, onClick (run: its old name), hint, sign, checked, back,
	-- role, main } } (the names of Skin.ActionCard's rows), keys (a line, wrapped inside the card),
	-- onKey(key, card): its own keys (arrows, + and -...), true when taken, before 1 to 9 and Escape }),
	-- shown beside its owner (nil: at the mouse) by card:Present(owner). card.valid(): false when what it is about
	-- is gone (it closes); card.onHide(card) when it closes.
	function Skin.Card(name, withIcon)
		local card = Skin.CreateWindow(name, "DIALOG")
		card:EnableMouse(true)
		card:SetClampedToScreen(true)
		card.margin = Skin.Margin() + 8
		local m = card.margin
		card.withIcon = withIcon
		if withIcon then
			card.icon = Skin.Icon(card, ICON_SIZE)
			card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", m, -m)
		end
		card.name = Skin.CreateText(card, "GameFontNormal")
		if withIcon then
			card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
		else
			card.name:SetPoint("TOPLEFT", card, "TOPLEFT", m, -m)
		end
		card.name:SetPoint("RIGHT", card, "RIGHT", -(m + 18), 0)
		if card.name.SetWordWrap then card.name:SetWordWrap(false) end
		card.now = Skin.Text(card, "GameTooltipTextSmall", "muted")
		card.now:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
		card.now:SetPoint("RIGHT", card, "RIGHT", -m, 0)
		if card.now.SetWordWrap then card.now:SetWordWrap(false) end
		Skin.CloseButton(card)
		card.tiles, card.rows, card.specs = {}, {}, {}
		card.rule = Skin.Rule(card, false, 0.14)
		card.main = Skin.Button(card, "", function(self) if self.run then self.run() end end, "main")
		card.main:SetHeight(MAIN_HEIGHT)
		card.main:Hide()
		card.keys = Skin.Text(card, "GameTooltipTextSmall", "muted")
		card.keys:SetJustifyH("LEFT")
		if card.keys.SetWordWrap then card.keys:SetWordWrap(true) end
		function card.Choose(index)
			local spec = card.specs[index]
			if not spec or spec.disabled then return end
			Skin.Play("mark")
			if not spec.stay then card:Hide() end
			if spec.run then spec.run() end
		end
		card:SetScript("OnKeyDown", OnKey)
		-- Closed by a click anywhere else (its owner's own click opens or closes it), Escape, or its owner gone;
		-- a fight begins: its keys go back to the game.
		Skin.Closable(card, name)
		local elsewhere = card:GetScript("OnEvent")
		card:SetScript("OnEvent", function(self, event, ...)
			if event == "PLAYER_REGEN_DISABLED" then return Keys(self, false) end
			elsewhere(self, event, ...)
		end)
		card:SetScript("OnUpdate", function(self)
			if self.owner and (not self.owner:IsVisible() or (self.valid and not self.valid())) then self:Hide() end
		end)
		card:HookScript("OnShow", function(self)
			self:RegisterEvent("PLAYER_REGEN_DISABLED")
			Keys(self, true)
		end)
		card:HookScript("OnHide", function(self)
			Keys(self, false)
			self.owner, self.valid = nil, nil
			if self.onHide then self.onHide(self) end
		end)

		-- Its words, tiles and list drawn, and its size.
		function card:Fill(spec)
			local c = Skin.COLORS
			if self.icon then self.icon:Set(spec.icon, spec.quality) end
			self.name:SetText(spec.title or "")
			if spec.quality then
				Skin.Quality(self.name, spec.quality)
			else
				local color = c[spec.titleColor or "gold"] or c.gold
				self.name:SetTextColor(color[1], color[2], color[3])
			end
			self.now:SetText(spec.now or "")
			local y = m + (self.icon and ICON_SIZE or HEAD_HEIGHT) + 12
			-- (a block of its own under the heading, when it has one: placed by the card, drawn by its maker; under
			-- the tiles with spec.bodyBelow)
			if self.body and self.body ~= spec.body then self.body:Hide() end
			self.body = spec.body
			local function PlaceBody()
				spec.body:ClearAllPoints()
				spec.body:SetPoint("TOPLEFT", self, "TOPLEFT", m, -y)
				spec.body:Show()
				y = y + (spec.bodyHeight or spec.body:GetHeight() or 0) + 12
			end
			if spec.body and not spec.bodyBelow then PlaceBody() end
			-- The tiles, in rows of five.
			self.specs = spec.tiles or {}
			self.onKey = spec.onKey
			local perRow = spec.perRow or 5
			local count = #self.specs
			for index, tileSpec in ipairs(self.specs) do
				local tile = self.tiles[index] or MakeTile(self, index)
				self.tiles[index] = tile
				tile.spec, tile.on, tile.disabled = tileSpec, tileSpec.on and true or false, tileSpec.disabled and true or false
				SetSign(tile, tileSpec.sign)
				tile.word:SetText(tileSpec.label or "")
				tile:ClearAllPoints()
				local column, line = (index - 1) % perRow, math.floor((index - 1) / perRow)
				tile:SetPoint("TOPLEFT", self, "TOPLEFT", m + column * (TILE_WIDTH + TILE_GAP), -(y + line * (TILE_HEIGHT + TILE_GAP)))
				PaintTile(tile)
				tile:Show()
			end
			for index = count + 1, #self.tiles do self.tiles[index]:Hide() end
			local lines = math.ceil(count / perRow)
			y = y + lines * TILE_HEIGHT + math.max(0, lines - 1) * TILE_GAP
			if spec.body and spec.bodyBelow then
				y = y + (lines > 0 and 12 or 0)
				PlaceBody()
				y = y - 12
			end
			local columns = math.max(1, math.min(count, perRow))
			local width = math.max(columns * TILE_WIDTH + (columns - 1) * TILE_GAP, spec.minWidth or 0)
			-- The list, under a rule.
			local entries = spec.rows or {}
			self.rule:SetShown(entries[1] ~= nil)
			self.main:Hide()
			local used = 0
			if entries[1] then
				self.rule:ClearAllPoints()
				self.rule:SetPoint("TOPLEFT", self, "TOPLEFT", m, -(y + 10))
				self.rule:SetWidth(width)
				y = y + 10 + 1 + 6
				for _, entry in ipairs(entries) do
					if entry.main then
						self.main:SetText(entry.text)
						self.main:Fit()
						local run = entry.onClick or entry.run
						self.main.run = function() self:Hide() if run then run() end end
						self.main:ClearAllPoints()
						self.main:SetPoint("TOPLEFT", self, "TOPLEFT", m, -(y + 2))
						self.main:Show()
						y = y + MAIN_HEIGHT + 6
					else
						used = used + 1
						local row = self.rows[used] or MakeRow(self)
						self.rows[used] = row
						row:ClearAllPoints()
						row:SetPoint("TOPLEFT", self, "TOPLEFT", m, -y)
						row:SetWidth(width)
						row:Fill(entry)
						y = y + ROW_HEIGHT
					end
				end
			end
			for index = used + 1, #self.rows do self.rows[index]:Hide() end
			-- (the keys' line as wide as the card, as tall as its words: long in some languages, it wraps inside)
			self.keys:SetText(spec.keys or "")
			self.keys:SetWidth(width)
			self.keys:ClearAllPoints()
			self.keys:SetPoint("TOPLEFT", self, "TOPLEFT", m, -(y + 8))
			local keysHeight = (spec.keys or "") ~= "" and U.Measure(self.keys, "GetStringHeight", 12) or 12
			self:SetSize(width + m * 2, y + 8 + keysHeight + m)
			Skin.Get(self):Layout()
		end

		-- Shown beside its owner (none: at the mouse; already shown: its keys taken again, in front).
		function card:Present(owner)
			self.owner = owner
			self:SetScale(Skin.Scale())
			if owner then
				Anchor(self, owner)
			else
				local x, y = GetCursorPosition()
				local scale = self:GetEffectiveScale()
				scale = type(scale) == "number" and scale > 0 and scale or 1
				self:ClearAllPoints()
				self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / scale - 24, (y or 0) / scale + 24)
			end
			if self:IsShown() then
				Keys(self, true)
				if self.Raise then self:Raise() end
			else
				Skin.Play("click")
				self:Show()
			end
		end
		return card
	end
end

-- Help --------------------------------------------------------------------------------------------------------
-- A small "Help" word in a window's corner (bottom left unless said): what can be done there, under the mouse.
-- corner "HEADING": a "?" at the heading's right, left of the window's cog (else its cross), for a window whose
-- foot is full (window.help).
function Skin.Help(window, text, corner)
	if corner == "HEADING" then
		local help = Skin.CreateLink(window, "?", nil, text)
		help.text:SetFontObject(Skin.FontFor("GameTooltipText"))
		help:SetSize(18, 18)
		local beside = window.cog or window.closeButton
		if beside then
			help:SetPoint("RIGHT", beside, "LEFT", -2, 0)
		else
			help:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, -6)
		end
		help:SetFrameLevel(window:GetFrameLevel() + 5)
		window.help = help
		return help
	end
	local help = Skin.CreateLink(window, ns.L.HELP, nil, text)
	corner = corner or "BOTTOMLEFT"
	help:SetPoint(corner, window, corner, corner == "BOTTOMLEFT" and Skin.Margin() + 2 or -(Skin.Margin() + 2), Skin.Margin() - 2)
	return help
end
-- (the "HEADING" corner is there: extensions ask before using it)
Skin.HELP_HEADING = true

-- A row's quiet "⋯" button (three dots, gold under the mouse), seen while the mouse is on the row: what its
-- right click does, for those who do not know it. It stands in its own column at the row's right end, or left
-- of a piece there (before): Skin.ROW_MORE wide, which the row keeps free for it. paper: on parchment (ink colors).
-- opts: { manual (its owner shows and hides it: a row chosen keeps it), below (its tooltip under it), tip (other
-- words for its tooltip) }.
Skin.ROW_MORE = 26
local MORE_SIZE, MORE_DOTS = 20, { -6, 0, 6 }
function Skin.RowMore(row, onClick, before, paper, opts)
	opts = opts or {}
	local more = CreateFrame("Button", nil, row)
	more:SetSize(MORE_SIZE, MORE_SIZE)
	more:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	more.dots = {}
	for index, x in ipairs(MORE_DOTS) do
		local dot = Skin.Glyph(more, "dot", 10)
		dot:SetPoint("CENTER", more, "CENTER", x, 0)
		more.dots[index] = dot
	end
	local function Tint(role)
		local r, g, b = Skin.InkColor(role, paper)
		for _, dot in ipairs(more.dots) do dot:SetVertexColor(r, g, b) end
	end
	Tint("label")
	if before then more:SetPoint("RIGHT", before, "LEFT", -4, 0) else more:SetPoint("RIGHT", row, "RIGHT", -3, 0) end
	more:SetFrameLevel(row:GetFrameLevel() + 2)
	more:Hide()
	local function Hover()
		if not opts.manual then more:SetShown(row:IsMouseOver() or more:IsMouseOver()) end
	end
	more:SetScript("OnEnter", function(self)
		Tint("gold")
		GameTooltip:SetOwner(self, opts.below and "ANCHOR_BOTTOM" or "ANCHOR_RIGHT")
		GameTooltip:AddLine(opts.tip or ns.L.ROW_MORE, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	more:SetScript("OnLeave", function()
		Tint("label")
		GameTooltip:Hide()
		Hover()
	end)
	more:SetScript("OnClick", function()
		Skin.Play("click")
		onClick(row)
	end)
	row:HookScript("OnEnter", Hover)
	row:HookScript("OnLeave", Hover)
	return more
end

-- Parchment -----------------------------------------------------------------------------------------------------
-- An optional look for the conversation scene and the reading window only (every other window keeps the dark
-- look): Wanderer's own warm paper grain (Media/Parchment), softened so it is never a bright sheet, darker
-- toward its sides, a thin ink border. plain: a button on that paper (a light tint and an ink edge, no grain).
-- Skin.Parchment(window, on, plain) shows or hides it; Skin.INK are the ink colors to write on it, by the roles
-- of Skin.COLORS, and Skin.Ink(text, role, paper) colors a text for either ground.
local PARCHMENT_FILE = "Interface/AddOns/Wanderer/Media/Parchment"
local PARCHMENT_TILE = 384 -- pixels one copy of the grain covers
local PARCHMENT_TINT = { 0.92, 0.88, 0.82 }
local SHADE = { 0.24, 0.15, 0.06 } -- the darker sides
local INK_EDGE = { 0.28, 0.18, 0.08 }

Skin.INK = {
	gold = { 0.45, 0.22, 0.04 }, kicker = { 0.42, 0.3, 0.14 }, label = { 0.38, 0.28, 0.15 }, text = { 0.2, 0.13, 0.07 },
	soft = { 0.28, 0.2, 0.11 }, muted = { 0.44, 0.36, 0.26 }, good = { 0.1, 0.4, 0.12 }, bad = { 0.6, 0.13, 0.08 },
	warn = { 0.55, 0.3, 0.05 }, blue = { 0.12, 0.27, 0.5 },
}

-- A role's color on either ground: r, g, b.
function Skin.InkColor(role, paper)
	local c = (paper and Skin.INK or COLORS)[role] or (paper and Skin.INK.text or COLORS.text)
	return c[1], c[2], c[3]
end

-- A text in a role's color; on paper without the dark shadow (ink has none).
function Skin.Ink(text, role, paper)
	text:SetTextColor(Skin.InkColor(role, paper))
	if paper then text:SetShadowColor(0, 0, 0, 0) else text:SetShadowColor(0, 0, 0, 0.9) end
end

-- A band darkening one side, fading inward.
local function Shade(window, side, size, alpha)
	local band = window:CreateTexture(nil, "BACKGROUND", nil, -7)
	local across = side == "TOP" or side == "BOTTOM"
	if across then
		band:SetPoint(side .. "LEFT")
		band:SetPoint(side .. "RIGHT")
		band:SetHeight(size)
	else
		band:SetPoint("TOP" .. side)
		band:SetPoint("BOTTOM" .. side)
		band:SetWidth(size)
	end
	local dark, clear = CreateColor(SHADE[1], SHADE[2], SHADE[3], alpha), CreateColor(SHADE[1], SHADE[2], SHADE[3], 0)
	band:SetColorTexture(1, 1, 1, 1)
	-- (a gradient goes from its minimum, left or bottom, to its maximum)
	local darkFirst = side == "BOTTOM" or side == "LEFT"
	band:SetGradient(across and "VERTICAL" or "HORIZONTAL", darkFirst and dark or clear, darkFirst and clear or dark)
	return band
end

local function ParchmentLayers(window, plain)
	local layers = window.wandererParchment
	if layers then return layers end
	layers = { pieces = {} }
	local function Add(piece) layers.pieces[#layers.pieces + 1] = piece return piece end
	if plain then
		local fill = Add(window:CreateTexture(nil, "BACKGROUND", nil, -8))
		fill:SetAllPoints()
		fill:SetColorTexture(0.32, 0.2, 0.08, 0.1)
		layers.edges = Skin.Edges(window, INK_EDGE[1], INK_EDGE[2], INK_EDGE[3], 0.45)
	else
		local paper = Add(window:CreateTexture(nil, "BACKGROUND", nil, -8))
		paper:SetAllPoints()
		paper:SetTexture(PARCHMENT_FILE, "REPEAT", "REPEAT")
		paper:SetVertexColor(PARCHMENT_TINT[1], PARCHMENT_TINT[2], PARCHMENT_TINT[3])
		layers.paper = paper
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			-- (a wide faint band and a narrow one: a soft curve, never a bevel)
			Add(Shade(window, side, 44, 0.16))
			Add(Shade(window, side, 12, 0.2))
		end
		layers.edges = Skin.Edges(window, INK_EDGE[1], INK_EDGE[2], INK_EDGE[3], 0.7)
		-- The grain repeats at its own size, whatever the window's.
		local function Tile()
			local width, height = window:GetWidth() or 0, window:GetHeight() or 0
			if width > 0 and height > 0 then paper:SetTexCoord(0, width / PARCHMENT_TILE, 0, height / PARCHMENT_TILE) end
		end
		window:HookScript("OnSizeChanged", Tile)
		layers.Tile = Tile
	end
	for _, edge in ipairs(layers.edges) do layers.pieces[#layers.pieces + 1] = edge end
	window.wandererParchment = layers
	return layers
end

function Skin.Parchment(window, on, plain)
	local layers = on and ParchmentLayers(window, plain) or window.wandererParchment
	if layers then
		for _, piece in ipairs(layers.pieces) do piece:SetShown(on and true or false) end
		if on and layers.Tile then layers.Tile() end
	end
	local skin = Skin.Get(window)
	if skin then skin:SetParchment(on) end
	return layers
end
