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
	warn = { 0.88, 0.63, 0.25 },
}
local COLORS = Skin.COLORS

-- A chip's tones: its ground (r, g, b, a), its words (r, g, b).
local TONES = {
	gold = { 1, 0.82, 0, 0.12, 0.95, 0.81, 0.42 }, red = { 0.94, 0.54, 0.49, 0.15, 0.95, 0.63, 0.58 },
	green = { 0.31, 0.78, 0.43, 0.15, 0.56, 0.88, 0.64 }, blue = { 0.31, 0.59, 0.9, 0.16, 0.61, 0.78, 0.96 },
	grey = { 1, 1, 1, 0.07, 0.69, 0.66, 0.6 },
}

local function Sound() if U.PlaySound then U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON") end end

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

-- A few words under the mouse (text, or a function giving them; nil: nothing).
function Skin.Tooltip(frame, text, anchor)
	frame:HookScript("OnEnter", function(self)
		local words = type(text) == "function" and text(self) or text
		if not words then return end
		GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
		GameTooltip:AddLine(words, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
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
	button:SetScript("OnClick", function(self, ...)
		Sound()
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
	check.mark = check.box:CreateTexture(nil, "ARTWORK")
	check.mark:SetPoint("TOPLEFT", -4, 4)
	check.mark:SetPoint("BOTTOMRIGHT", 4, -4)
	check.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	check.text = Skin.Text(check, "GameTooltipText", "soft")
	check.text:SetPoint("LEFT", check.box, "RIGHT", 7, 0)
	function check:Refresh() self.mark:SetShown(get() and true or false) end
	function check:SetLabel(text)
		self.text:SetText(text)
		self:SetWidth(21 + U.Measure(self.text, "GetStringWidth", 160))
	end
	check:SetScript("OnClick", function(self)
		set(not get())
		Sound()
		self:Refresh()
	end)
	if tip then Skin.Tooltip(check, tip) end
	check:SetLabel(label)
	check:Refresh()
	return check
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

-- A list to choose from: a button showing the choice (placeholder before one), a menu of all of them.
-- choices() gives { { id, label } }, get() the id chosen, set(id) chooses. box:Refresh() after a change.
function Skin.Dropdown(parent, choices, get, set, placeholder, minimum)
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
	box.arrow = box:CreateTexture(nil, "OVERLAY")
	box.arrow:SetSize(14, 14)
	box.arrow:SetPoint("RIGHT", box, "RIGHT", -6, 0)
	box.arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	function box:Refresh()
		local label = placeholder or ""
		for _, choice in ipairs(choices()) do
			if choice.id == get() then label = choice.label end
		end
		self:SetText(label .. "      ")
		self:Fit()
	end
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
		button:SetScript("OnClick", function()
			Sound()
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

-- An amount of money: gold, silver, copper (money:ShowCopper(false) where copper is not taken).
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
-- window's margin (the skin's, plus extra).
function Skin.Header(window, kickerText, titleText, extra, titleTemplate)
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
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", onClose or function() window:Hide() end)
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

-- A question before acting: yes does it, no lets it go. Each question goes with its own popup (another
-- one asked in its place does not answer it).
function Skin.Ask(text, accept, refuse)
	if StaticPopup_Show then StaticPopup_Show("WANDERER_ASK", text, nil, { accept = accept, refuse = refuse }) end
end

-- A question still open put away (its window closing): as if refused.
function Skin.CancelAsk()
	if StaticPopup_Hide then StaticPopup_Hide("WANDERER_ASK") end
end

if StaticPopupDialogs then
	StaticPopupDialogs.WANDERER_ASK = {
		text = "%s",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function(_, question)
			if question and question.accept then question.accept() end
		end,
		OnCancel = function(_, question, reason)
			if reason == "override" then return end
			if question and question.refuse then question.refuse() end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

-- A name to give, or a text to paste: onAccept(text) with the words written (trimmed; nothing when empty).
-- default: the words it opens with; maxLetters: how many (0: no limit).
function Skin.AskText(prompt, default, onAccept, maxLetters)
	if StaticPopup_Show then
		StaticPopup_Show("WANDERER_ASK_TEXT", prompt or "", nil, { default = default, accept = onAccept, maxLetters = maxLetters })
	end
end

if StaticPopupDialogs then
	local function Accept(box, data)
		local text = strtrim(box and box:GetText() or "")
		if text ~= "" and data and data.accept then data.accept(text) end
	end
	StaticPopupDialogs.WANDERER_ASK_TEXT = {
		text = "%s",
		button1 = OKAY or "OK",
		button2 = CANCEL or "Cancel",
		hasEditBox = true,
		editBoxWidth = 350,
		OnShow = function(self, data)
			local box = U.EditBoxOf(self)
			if not box then return end
			box:SetMaxLetters(data and data.maxLetters or 40)
			box:SetText(data and data.default or "")
			box:HighlightText()
			box:SetFocus()
		end,
		OnAccept = function(self, data) Accept(U.EditBoxOf(self), data) end,
		EditBoxOnEnterPressed = function(box, data)
			Accept(box, data)
			box:GetParent():Hide()
		end,
		EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

-- A text to copy (an address, a scale, a profile): shown selected under a few words, for Ctrl+C.
function Skin.ShowCopy(prompt, text)
	if StaticPopup_Show then StaticPopup_Show("WANDERER_COPY", prompt or "", nil, text or "") end
end

if StaticPopupDialogs then
	StaticPopupDialogs.WANDERER_COPY = {
		text = "%s",
		button1 = CLOSE or OKAY,
		hasEditBox = true,
		editBoxWidth = 350,
		OnShow = function(self, text)
			local box = U.EditBoxOf(self)
			if not box then return end
			box:SetText(text or "")
			box:HighlightText()
			box:SetFocus()
		end,
		EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
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
	local rowHeight = spec.rowHeight or 34
	local top = spec.titles == false and 0 or 18
	local iconSize = spec.icon ~= false and rowHeight - 8 or 0
	list:SetSize(spec.width, top + spec.rows * rowHeight)
	list:EnableMouseWheel(true)
	list.offset, list.rows, list.count, list.total = 0, {}, spec.rows, 0
	list:SetScript("OnMouseWheel", function(self, delta)
		self.offset = math.max(0, self.offset - delta * 3)
		spec.onDraw()
	end)
	-- The scroll bar: a thin rail, a thumb as long as the part shown (dragged; the rail clicked: a page).
	local bar = CreateFrame("Button", nil, list)
	bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -top)
	bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
	bar:SetWidth(BAR - 2)
	local rail = bar:CreateTexture(nil, "BACKGROUND")
	rail:SetColorTexture(1, 0.82, 0, 0.2)
	rail:SetWidth(2)
	rail:SetPoint("TOP")
	rail:SetPoint("BOTTOM")
	local thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(BAR - 4)
	thumb.fill = thumb:CreateTexture(nil, "ARTWORK")
	thumb.fill:SetAllPoints()
	thumb.fill:SetColorTexture(1, 0.82, 0, 0.4)
	bar:Hide()
	local function OffsetAt(position)
		local free = bar:GetHeight() - thumb:GetHeight()
		local total = list.total - list.count
		if free <= 0 or total <= 0 then return 0 end
		return math.floor(math.max(0, math.min(1, position / free)) * total + 0.5)
	end
	local function CursorTop()
		local _, y = GetCursorPosition()
		return (bar:GetTop() or 0) - y / bar:GetEffectiveScale()
	end
	thumb:SetScript("OnMouseDown", function(self)
		self.grab = CursorTop() - ((self:GetTop() and bar:GetTop()) and (bar:GetTop() - self:GetTop()) or 0)
		self:SetScript("OnUpdate", function(own)
			-- Let go anywhere: the drag ends.
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return own:SetScript("OnUpdate", nil) end
			local offset = OffsetAt(CursorTop() - own.grab)
			if offset ~= list.offset then
				list.offset = offset
				spec.onDraw()
			end
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnEnter", function(self) self.fill:SetColorTexture(1, 0.82, 0, 0.75) end)
	thumb:SetScript("OnLeave", function(self) self.fill:SetColorTexture(1, 0.82, 0, 0.4) end)
	bar:SetScript("OnClick", function()
		local below = CursorTop() > (bar:GetTop() or 0) - (thumb:GetTop() or 0) + thumb:GetHeight()
		list.offset = list.offset + (below and list.count or -list.count)
		spec.onDraw()
	end)
	local function DrawBar()
		local more = list.total > list.count
		bar:SetShown(more)
		if not more then return end
		local height = list.count * rowHeight
		local size = math.max(THUMB_MIN, math.floor(height * list.count / list.total))
		local position = math.floor((height - size) * list.offset / (list.total - list.count) + 0.5)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", bar, "TOP", 0, -position)
	end
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
				Sound()
				spec.onSort(sort)
			end)
			sorters[sort] = title
		end
		Sorter(nameTitle, spec.nameSort)
		for index, column in ipairs(spec.columns) do Sorter(titles[index], column.sort) end
	end
	list.titles = titles
	function list:SetSort(sort)
		for key, title in pairs(sorters) do
			local c = key == sort and COLORS.gold or COLORS.muted
			title:SetTextColor(c[1], c[2], c[3])
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
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			if self.entry and not self.entry.header then
				Sound()
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
			self.name:SetPoint("RIGHT", self, "RIGHT", leftmost + BAR - 10, lift)
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
