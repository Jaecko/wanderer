local _, ns = ...
local L = ns.L

-- The weights window: what each characteristic is worth to you, scale by
-- scale (your branch, or the bear and the cat; the Pawn scales imported).
-- One line each, a quiet gauge for its weight next to the others; the wheel
-- or the - and + set it (Shift: finer). Wanderer's own weights become yours
-- as soon as one moves, and come back with Restore. Every change speaks at
-- once in the items' tooltips.

local U = ns.Util

local WIDTH = 440
local ROW_HEIGHT = 20
local TAB_HEIGHT = 22
local STEP, FINE = 0.1, 0.01 -- a point of a characteristic
local STEP_PERCENT, FINE_PERCENT = 1, 0.1 -- a percent
local GOLD = { 1, 0.82, 0 }
local QUIET = { 0.55, 0.55, 0.55 }

local window, kicker, title, hint, rule, footer
local tabs, rows, links = {}, {}, {}
local selected -- id of the scale shown

local function Scales() return (ns.UpgradeScales()) end

local function Selected()
	local scales = Scales()
	for _, scale in ipairs(scales) do
		if scale.id == selected then return scale end
	end
	selected = scales[1] and scales[1].id
	return scales[1]
end

local function Format(value, percent)
	if not value or value == 0 then return "-" end
	if percent then return ("%g"):format(math.floor(value * 10 + 0.5) / 10) end
	return ("%.2f"):format(value)
end

local Refresh

local function Change(stat, direction)
	local scale = Selected()
	if not scale then return end
	local percent = ns.STAT_PERCENT[stat]
	local step = IsShiftKeyDown() and (percent and FINE_PERCENT or FINE) or (percent and STEP_PERCENT or STEP)
	local value = math.max(0, (scale.weights[stat] or 0) + direction * step)
	ns.SetScaleWeight(scale.id, stat, value)
	Refresh()
end

-- A small text button, gold when hovered, as the journal's.
local function TextButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent)
	button.text = ns.Skin.CreateText(button, "GameTooltipTextSmall", 0.75, 0.68, 0.5)
	button.text:SetPoint("CENTER")
	button.text:SetText(text)
	button:SetSize(U.Measure(button.text, "GetStringWidth", 60) + 10, 18)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self) self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
	button:SetScript("OnLeave", function(self) self.text:SetTextColor(0.75, 0.68, 0.5) end)
	return button
end

local function Row(index)
	if rows[index] then return rows[index] end
	local row = CreateFrame("Frame", nil, window)
	row:SetHeight(ROW_HEIGHT)
	row:EnableMouse(true)
	row:EnableMouseWheel(true)
	row.name = ns.Skin.CreateText(row, "GameTooltipText", 0.9, 0.9, 0.9)
	row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.gauge = row:CreateTexture(nil, "ARTWORK")
	row.gauge:SetHeight(4)
	row.gauge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	row.track = row:CreateTexture(nil, "BACKGROUND")
	row.track:SetHeight(4)
	row.track:SetColorTexture(1, 1, 1, 0.06)
	row.plus = TextButton(row, "+", function() Change(row.stat, 1) end)
	row.plus:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.value = ns.Skin.CreateText(row, "GameTooltipText", 1, 1, 1)
	row.value:SetWidth(44)
	row.value:SetJustifyH("CENTER")
	row.value:SetPoint("RIGHT", row.plus, "LEFT", 0, 0)
	row.minus = TextButton(row, "-", function() Change(row.stat, -1) end)
	row.minus:SetPoint("RIGHT", row.value, "LEFT", 0, 0)
	row.track:SetPoint("LEFT", row, "LEFT", 150, 0)
	row.track:SetPoint("RIGHT", row.minus, "LEFT", -8, 0)
	row.gauge:SetPoint("LEFT", row.track, "LEFT", 0, 0)
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 0.82, 0, 0.06)
	row.highlight:Hide()
	row:SetScript("OnMouseWheel", function(self, delta) Change(self.stat, delta) end)
	row:SetScript("OnEnter", function(self) self.highlight:Show() end)
	row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
	rows[index] = row
	return row
end

local function Tab(index)
	if tabs[index] then return tabs[index] end
	local tab = CreateFrame("Button", nil, window)
	tab:SetHeight(TAB_HEIGHT)
	tab.text = ns.Skin.CreateText(tab, "GameTooltipText", 0.75, 0.75, 0.75)
	tab.text:SetPoint("CENTER")
	tab.line = tab:CreateTexture(nil, "ARTWORK")
	tab.line:SetHeight(2)
	tab.line:SetPoint("BOTTOMLEFT", 4, 0)
	tab.line:SetPoint("BOTTOMRIGHT", -4, 0)
	tab.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	tab:SetScript("OnClick", function(self)
		selected = self.id
		U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		Refresh()
	end)
	tabs[index] = tab
	return tab
end

Refresh = function()
	if not (window and window:IsShown()) then return end
	local margin = ns.Skin.Margin() + 6
	local scales, class = ns.UpgradeScales()
	local scale = Selected()
	title:SetText(L.WEIGHTS_TITLE)
	local className = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or ""
	hint:SetText(L.WEIGHTS_HINT:format(className))
	-- The scales, as tabs.
	local x = margin
	local y = margin + U.Measure(kicker, "GetStringHeight", 10) + 3 + U.Measure(title, "GetStringHeight", 16) + 4
		+ U.Measure(hint, "GetStringHeight", 12) + 12
	for index, entry in ipairs(scales) do
		local tab = Tab(index)
		tab.id = entry.id
		tab.text:SetText(entry.label)
		tab:SetWidth(U.Measure(tab.text, "GetStringWidth", 80) + 20)
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", window, "TOPLEFT", x, -y)
		local on = scale and entry.id == scale.id
		tab.text:SetTextColor(on and GOLD[1] or 0.75, on and GOLD[2] or 0.75, on and GOLD[3] or 0.75)
		tab.line:SetShown(on)
		tab:Show()
		x = x + tab:GetWidth() + 4
	end
	for index = #scales + 1, #tabs do tabs[index]:Hide() end
	y = y + TAB_HEIGHT + 4
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
	rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -margin, -y)
	y = y + 10
	-- The characteristics: the ones weighed first, then the others, quiet.
	local weights = scale and scale.weights or {}
	local most = 0
	for _, stat in ipairs(ns.STAT_ORDER) do
		local weight = weights[stat] or 0
		local worth = ns.STAT_PERCENT[stat] and weight / 14 or weight
		if worth > most then most = worth end
	end
	local order = {}
	for _, stat in ipairs(ns.STAT_ORDER) do if (weights[stat] or 0) > 0 then order[#order + 1] = stat end end
	for _, stat in ipairs(ns.STAT_ORDER) do if (weights[stat] or 0) <= 0 then order[#order + 1] = stat end end
	for index, stat in ipairs(order) do
		local row = Row(index)
		row.stat = stat
		local weight = weights[stat] or 0
		local percent = ns.STAT_PERCENT[stat]
		row.name:SetText(ns.StatLabel(stat))
		local color = weight > 0 and { 0.92, 0.9, 0.85 } or QUIET
		row.name:SetTextColor(color[1], color[2], color[3])
		row.value:SetText(Format(weight, percent))
		row.value:SetTextColor(weight > 0 and 1 or QUIET[1], weight > 0 and 1 or QUIET[2], weight > 0 and 1 or QUIET[3])
		local share = most > 0 and math.min(1, (percent and weight / 14 or weight) / most) or 0
		local trackWidth = math.max(1, row.track:GetWidth() > 0 and row.track:GetWidth() or (WIDTH - margin * 2 - 150 - 90))
		row.gauge:SetWidth(math.max(0.01, trackWidth * share))
		row.gauge:SetShown(share > 0)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
		row:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
		row:Show()
		y = y + ROW_HEIGHT
	end
	for index = #order + 1, #rows do rows[index]:Hide() end
	-- What this scale is: Wanderer's, yours, or imported.
	local state = not scale and "" or (scale.imported and L.WEIGHTS_STATE_IMPORTED)
		or (ns.IsScaleChanged(scale.id) and L.WEIGHTS_STATE_YOURS) or L.WEIGHTS_STATE_WANDERER
	footer:SetText(state)
	y = y + 12
	footer:ClearAllPoints()
	footer:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
	local right = -margin
	for _, link in ipairs(links) do
		link:ClearAllPoints()
		link:SetPoint("TOPRIGHT", window, "TOPRIGHT", right, -(y - 2))
		right = right - link:GetWidth() - 6
	end
	window:SetHeight(y + 18 + margin)
	ns.Skin.Get(window):Layout()
end
ns.RefreshWeights = function() Refresh() end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererWeights", "DIALOG")
	ns.Skin.Sounds(window, "IG_CHARACTER_INFO_OPEN", "IG_CHARACTER_INFO_CLOSE")
	window:SetWidth(WIDTH)
	ns.Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "weightsPos")
	local margin = ns.Skin.Margin() + 6
	kicker = ns.Skin.CreateKicker(window, L.WEIGHTS_KICKER)
	kicker:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	title = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -3)
	hint = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.65, 0.65, 0.65)
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	hint:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	hint:SetJustifyH("LEFT")
	if hint.SetWordWrap then hint:SetWordWrap(true) end
	rule = window:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.2)
	rule:SetHeight(1)
	footer = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	-- Right to left: export, import, restore.
	links[1] = TextButton(window, L.WEIGHTS_EXPORT, function()
		local scale = Selected()
		local text = scale and ns.ExportScale(scale.id)
		if text and StaticPopup_Show then StaticPopup_Show("WANDERER_EXPORT_SCALE", nil, nil, text) end
	end)
	links[2] = TextButton(window, L.WEIGHTS_IMPORT, function()
		if StaticPopup_Show then StaticPopup_Show("WANDERER_IMPORT_SCALE") end
	end)
	links[3] = TextButton(window, L.WEIGHTS_RESET, function()
		local scale = Selected()
		if scale then ns.ResetScale(scale.id) end
		Refresh()
	end)
	window:HookScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		Refresh()
	end)
	if StaticPopupDialogs then
		StaticPopupDialogs.WANDERER_EXPORT_SCALE = {
			text = L.WEIGHTS_EXPORT_PROMPT, button1 = CLOSE or OKAY, hasEditBox = true, editBoxWidth = 350,
			OnShow = function(self, text)
				local box = U.EditBoxOf(self)
				if box then
					box:SetText(text or "")
					box:HighlightText()
					box:SetFocus()
				end
			end,
			EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
			timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end
end

-- A button of the game's own kind on the character sheet, just outside its
-- top right corner (never over its title bar, which takes the clicks): the
-- weights a click away from your equipment, while the comparison is on.
local function CharacterButton()
	local sheet = _G.CharacterFrame
	if not sheet or sheet.wandererWeights then return end
	local button = CreateFrame("Button", "WandererWeightsButton", sheet, "UIPanelButtonTemplate")
	sheet.wandererWeights = button
	button:SetText(L.WEIGHTS_BUTTON)
	button:SetSize(U.Measure(button:GetFontString() or button, "GetStringWidth", 60) + 24, 22)
	button:SetPoint("TOPLEFT", sheet, "TOPRIGHT", 4, -28)
	button:SetScript("OnClick", function()
		-- A problem said in the chat, never a click that does nothing.
		local ok, problem = pcall(ns.ToggleWeights)
		if not ok then ns.Print(tostring(problem)) end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.WEIGHTS_TITLE)
		GameTooltip:AddLine(L.WEIGHTS_OPEN_DESC, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local function ShowIfOn() button:SetShown(ns.db and ns.db.enabled and ns.db.tooltips.upgrade and true or false) end
	sheet:HookScript("OnShow", ShowIfOn)
	ShowIfOn()
end

function ns.InitWeights()
	CharacterButton()
end

function ns.ToggleWeights()
	if not ns.root then return end
	if not window then CreateWindow() end
	window:SetShown(not window:IsShown())
end
