local _, ns = ...
local L = ns.L

-- The weights window: what each characteristic is worth to you, scale by
-- scale (your branch, or the bear and the cat; the Pawn scales imported).
-- One line each, a quiet gauge for its weight next to the others; the wheel
-- or the - and + set it (Shift: finer). Wanderer's own weights become yours
-- as soon as one moves, and come back with Restore. Every change speaks at
-- once in the items' tooltips. Above the lines, for those who strike with a
-- weapon: the weights calculated for you (a check to turn them off), and what
-- changed lately (hit capped, critical strike worth more...).

local U = ns.Util

local WIDTH = 440
local ROW_HEIGHT = ns.Skin.ROW.compact
local STEP, FINE = 0.1, 0.01 -- a point of a characteristic
local STEP_PERCENT, FINE_PERCENT = 1, 0.1 -- a percent
local GOLD = ns.Skin.COLORS.gold
local QUIET = ns.Skin.COLORS.muted

local window, kicker, title, hint, rule, footer, roles, calcCheck, calcRule
local calcLines = {} -- the calculated weights said in a few lines
local tabs, tabsKeys -- the scales' tabs (the kit's), made again when the scales change
local rows, links = {}, {}
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

-- A weight brought to one point of the item (a rating point, at your level): the gauges compare those.
local function PerPoint(stat, weight)
	local per = ns.RatingPerUnit(stat)
	return per and per > 0 and weight / per or weight
end

local Refresh

local function Change(stat, direction)
	local scale = Selected()
	if not scale then return end
	local percent = ns.STAT_PERCENT[stat]
	local step = U.PadShiftDown() and (percent and FINE_PERCENT or FINE) or (percent and STEP_PERCENT or STEP)
	local value = math.max(0, (scale.weights[stat] or 0) + direction * step)
	ns.SetScaleWeight(scale.id, stat, value)
	Refresh()
end

local function Row(index)
	if rows[index] then return rows[index] end
	local row = CreateFrame("Frame", nil, window)
	row:SetHeight(ROW_HEIGHT)
	row:EnableMouse(true)
	row:EnableMouseWheel(true)
	row.name = ns.Skin.Text(row, "GameTooltipText", "text")
	row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.gauge = row:CreateTexture(nil, "ARTWORK")
	row.gauge:SetHeight(6)
	row.gauge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
	row.track = row:CreateTexture(nil, "BACKGROUND")
	row.track:SetHeight(6)
	row.track:SetColorTexture(1, 1, 1, 0.06)
	row.plus = ns.Skin.SmallButton(row, "+", function() Change(row.stat, 1) end)
	row.plus:SetSize(20, 18)
	row.plus:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.value = ns.Skin.CreateText(row, "GameTooltipText", ns.Skin.RGB("text"))
	row.value:SetWidth(44)
	row.value:SetJustifyH("CENTER")
	row.value:SetPoint("RIGHT", row.plus, "LEFT", 0, 0)
	row.minus = ns.Skin.SmallButton(row, "-", function() Change(row.stat, -1) end)
	row.minus:SetSize(20, 18)
	row.minus:SetPoint("RIGHT", row.value, "LEFT", 0, 0)
	row.track:SetPoint("LEFT", row, "LEFT", 150, 0)
	row.track:SetPoint("RIGHT", row.minus, "LEFT", -8, 0)
	row.gauge:SetPoint("LEFT", row.track, "LEFT", 0, 0)
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(ns.Skin.RGB("gold", ns.Skin.HOVER))
	row.highlight:Hide()
	row:SetScript("OnMouseWheel", function(self, delta) Change(self.stat, delta) end)
	row.padAdjust = function(self, delta) Change(self.stat, delta) end -- (a controller: left and right of the cross)
	row.padTip = true -- (a plain frame: reached all the same)
	row:SetScript("OnEnter", function(self) self.highlight:Show() end)
	row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
	rows[index] = row
	return row
end

-- The scales as the kit's tabs (one bar, its list given again when the scales changed: one imported or removed).
local function Tabs(scales)
	local list, keys = {}, {}
	for index, entry in ipairs(scales) do
		list[index] = { entry.id, entry.label }
		keys[index] = tostring(entry.id) .. "=" .. tostring(entry.label)
	end
	local signature = table.concat(keys, "|")
	if tabs and tabsKeys == signature then return tabs end
	if tabs then
		tabs:SetList(list)
	else
		tabs = ns.Skin.Tabs(window, list, function(id)
			selected = id
			Refresh()
		end)
	end
	tabsKeys = signature
	return tabs
end

-- Weights calculated for you (StatModel.lua) -------------------------------------------------------------

-- A characteristic's name, without its "(%)".
local function StatName(stat) return (ns.StatLabel(stat):gsub("%s*%(%%%)$", "")) end

local function Decimal(value, format)
	return ((format or "%.1f"):format(value):gsub("%.0$", ""):gsub("%.", _G.DECIMAL_SEPARATOR or "."))
end

-- The few lines under the check: { words, role }; nil for an imported scale (its own weights).
local function CalculatedLines(scale)
	if not scale or scale.imported then return nil end
	local calculated = scale.calculated
	if not scale.covered then return { { L.CALC_LATER, "muted" } } end
	if not ns.UseCalculatedWeights() then return { { L.CALC_OFF, "muted" } } end
	if not calculated then return { { L.CALC_UNREAD, "muted" } } end
	local lines = { { L.CALC_HEADER, "soft" }, { L.CALC_ESTIMATE, "muted" } }
	if calculated.hitCapped then
		lines[#lines + 1] = { calculated.whiteCapped and L.CALC_HIT_CAPPED or L.CALC_HIT_CAPPED_DUAL, "warn" }
	end
	for _, note in ipairs(calculated.notes or {}) do
		local more = note.change > 0
		local change = ("%d"):format(math.floor(math.abs(note.change) * 100 + 0.5))
		lines[#lines + 1] = { (more and L.CALC_NOTE_MORE or L.CALC_NOTE_LESS):format(StatName(note.stat), change),
			more and "good" or "bad" }
	end
	return lines
end

-- The check's tooltip: what it is, and the figures it was calculated from (to compare with the sheet).
local function CalculatedTip()
	local scale = Selected()
	local calculated = scale and scale.calculated
	local lines = { L.CALC_USE, L.CALC_USE_DESC }
	if calculated then
		local s = calculated.state
		local weapon = s.ranged and s.rangedWeapon or s.mh
		local soft = ns.Skin.COLORS.soft
		lines[#lines + 1] = { L.CALC_FIGURES:format(math.floor((s.ranged and s.rap or s.ap) + 0.5), Decimal(s.crit),
			Decimal(s.hit), Decimal(calculated.cap), Decimal(weapon and weapon.speed or 0, "%.2f")), soft[1], soft[2], soft[3] }
		local names = {}
		for _, talent in ipairs(s.counted or {}) do
			names[#names + 1] = ("%s %d/%d"):format(talent.name, talent.ranks, talent.most)
		end
		lines[#lines + 1] = { names[1] and L.CALC_TALENTS:format(table.concat(names, ", ")) or L.CALC_NO_TALENT,
			soft[1], soft[2], soft[3] }
	end
	local quiet = ns.Skin.COLORS.muted
	lines[#lines + 1] = { L.CALC_HOW, quiet[1], quiet[2], quiet[3] }
	return lines
end

-- Lays the check and its lines out from y; the next y.
local function LayoutCalculated(scale, margin, y)
	local lines = CalculatedLines(scale)
	calcCheck:SetShown(lines ~= nil and scale.covered or false)
	if calcCheck:IsShown() then
		calcCheck:Refresh()
		calcCheck:ClearAllPoints()
		calcCheck:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
		y = y + 22
	end
	for index, line in ipairs(lines or {}) do
		local text = calcLines[index]
		if not text then
			text = ns.Skin.Text(window, "GameTooltipTextSmall", "muted")
			text:SetJustifyH("LEFT")
			if text.SetWordWrap then text:SetWordWrap(true) end
			calcLines[index] = text
		end
		local color = ns.Skin.COLORS[line[2]] or ns.Skin.COLORS.muted
		text:SetText(line[1])
		text:SetTextColor(color[1], color[2], color[3])
		text:ClearAllPoints()
		-- (under the check, its lines aligned on its words)
		local indent = calcCheck:IsShown() and 21 or 0
		text:SetPoint("TOPLEFT", window, "TOPLEFT", margin + indent, -y)
		text:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
		text:Show()
		y = y + U.Measure(text, "GetStringHeight", 12) + 3
	end
	for index = #(lines or {}) + 1, #calcLines do calcLines[index]:Hide() end
	calcRule:SetShown(lines ~= nil)
	if lines then
		y = y + 6
		calcRule:ClearAllPoints()
		calcRule:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
		calcRule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -margin, -y)
		y = y + 10
	end
	return y
end

Refresh = function()
	if not (window and window:IsShown()) then return end
	local margin = ns.Skin.Margin() + 6
	local scales, class = ns.UpgradeScales()
	local scale = Selected()
	title:SetText(L.WEIGHTS_TITLE)
	local className = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or ""
	hint:SetText((ns.Pad and ns.Pad.On() and L.WEIGHTS_HINT_PAD or L.WEIGHTS_HINT):format(className))
	-- The scales, as tabs.
	local y = margin + U.Measure(kicker, "GetStringHeight", 10) + 3 + U.Measure(title, "GetStringHeight", 16) + 4
		+ U.Measure(hint, "GetStringHeight", 12) + 8
	local bar = Tabs(scales)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
	bar:Select(scale and scale.id)
	bar:Show()
	y = y + bar:GetHeight() + 6
	-- What you play (your choice): its weights are the ones shown.
	local several = #ns.PlayChoices() > 1
	roles:SetShown(several)
	roles.label:SetShown(several)
	if several then
		roles.label:ClearAllPoints()
		roles.label:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(y + 8))
		roles:ClearAllPoints()
		roles:SetPoint("LEFT", roles.label, "RIGHT", 10, 0)
		roles:Refresh()
		y = y + 34
	end
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
	rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -margin, -y)
	y = y + 10
	-- Calculated for you, or fixed: said first.
	y = LayoutCalculated(scale, margin, y)
	-- The characteristics: the ones weighed first, then the others, quiet.
	local weights = scale and scale.weights or {}
	local most = 0
	for _, stat in ipairs(ns.STAT_ORDER) do
		local weight = weights[stat] or 0
		local worth = PerPoint(stat, weight)
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
		local color = weight > 0 and ns.Skin.COLORS.text or QUIET
		row.name:SetTextColor(color[1], color[2], color[3])
		row.value:SetText(Format(weight, percent))
		row.value:SetTextColor(weight > 0 and 1 or QUIET[1], weight > 0 and 1 or QUIET[2], weight > 0 and 1 or QUIET[3])
		local share = most > 0 and math.min(1, PerPoint(stat, weight) / most) or 0
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
	-- What this scale is: calculated for you, Wanderer's, yours, or imported.
	local state = not scale and "" or (scale.imported and L.WEIGHTS_STATE_IMPORTED)
		or (ns.IsScaleChanged(scale.id) and L.WEIGHTS_STATE_YOURS)
		or (scale.calculated and ns.UseCalculatedWeights() and L.CALC_USE) or L.WEIGHTS_STATE_WANDERER
	footer:SetText(state)
	y = y + 12
	footer:ClearAllPoints()
	footer:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -y)
	local right = -margin
	-- (Restore only when the weights are yours)
	links[3]:SetEnabled(scale ~= nil and not scale.imported and ns.IsScaleChanged(scale.id) and true or false)
	for _, link in ipairs(links) do
		link:ClearAllPoints()
		link:SetPoint("TOPRIGHT", window, "TOPRIGHT", right, -(y - 4))
		right = right - link:GetWidth() - 6
	end
	window:SetHeight(y + 26 + margin)
	ns.Skin.Get(window):Layout()
end
ns.RefreshWeights = function() Refresh() end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererWeights", "MEDIUM")
	ns.Skin.Sounds(window, "IG_CHARACTER_INFO_OPEN", "IG_CHARACTER_INFO_CLOSE")
	window:SetWidth(WIDTH)
	ns.Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "weightsPos")
	local margin
	kicker, title, margin = ns.Skin.Header(window, L.WEIGHTS_KICKER, nil, { margin = 6, settings = "tooltips" })
	ns.Skin.Help(window, L.WEIGHTS_HELP, "HEADING")
	hint = ns.Skin.Text(window, "GameTooltipTextSmall", "muted")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	hint:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	hint:SetJustifyH("LEFT")
	if hint.SetWordWrap then hint:SetWordWrap(true) end
	rule = window:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(ns.Skin.RGB("gold", 0.2))
	rule:SetHeight(1)
	footer = ns.Skin.Text(window, "GameTooltipTextSmall", "muted")
	calcCheck = ns.Skin.Check(window, L.CALC_USE, ns.UseCalculatedWeights, ns.SetUseCalculatedWeights, CalculatedTip)
	calcRule = window:CreateTexture(nil, "ARTWORK")
	calcRule:SetColorTexture(1, 1, 1, 0.06)
	calcRule:SetHeight(1)
	roles = ns.Skin.Dropdown(window, ns.PlayChoices, function() return ns.PlayChoice() end, function(id) ns.PlayChoice(id) end,
		L.PLAY_CHOICE_PICK, nil, nil, L.PLAY_CHOICE_DESC)
	roles:SetHeight(24)
	roles.label = ns.Skin.Text(window, "GameTooltipTextSmall", "label")
	roles.label:SetText(L.PLAY_CHOICE)
	-- Right to left: export, import, restore.
	links[1] = ns.Skin.SmallButton(window, L.WEIGHTS_EXPORT, function()
		local scale = Selected()
		local text = scale and ns.ExportScale(scale.id)
		if text then ns.Skin.ShowCopy(L.WEIGHTS_EXPORT_PROMPT, text) end
	end)
	links[2] = ns.Skin.SmallButton(window, L.WEIGHTS_IMPORT, function()
		ns.Skin.AskText(L.UPGRADE_IMPORT_PROMPT, "", function(text)
			local ok, result = ns.ImportPawnScale(text)
			ns.Print(ok and L.UPGRADE_IMPORT_DONE:format(result.name) or result)
			Refresh()
		end, 0)
	end)
	links[3] = ns.Skin.SmallButton(window, L.WEIGHTS_RESET, function()
		local scale = Selected()
		if not (scale and ns.IsScaleChanged(scale.id)) then return end
		-- (your weights are lost: asked first)
		ns.Skin.Ask(L.WEIGHTS_RESET_ASK:format(scale.label or ""), function()
			ns.ResetScale(scale.id)
			Refresh()
		end)
	end)
	window:HookScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		Refresh()
	end)
end

-- A button of the game's own kind on the character sheet, inside it: at the
-- foot of the characteristics column (the equipment tab only), the weights a
-- click away from your equipment while the comparison is on. Made with the
-- sheet itself (it may come after us), never below it where it is not seen.
local function CharacterButton()
	local sheet = _G.CharacterFrame
	if not sheet or sheet.wandererWeights then return end
	local page = _G.PaperDollFrame or sheet
	local column = _G.CharacterFrameInsetRight
	local button = ns.Skin.GameButton(page, "WandererWeightsButton", L.WEIGHTS_BUTTON, function()
		-- A problem said in the chat, never a click that does nothing.
		local ok, problem = pcall(ns.ToggleWeights)
		if not ok then ns.Print(tostring(problem)) end
	end, { L.WEIGHTS_TITLE, L.WEIGHTS_OPEN_DESC })
	sheet.wandererWeights = button
	button:SetHeight(22)
	if column then
		button:SetPoint("BOTTOM", column, "BOTTOM", 0, 8)
	else
		button:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -10, 10)
	end
	button:SetFrameLevel(((column or sheet):GetFrameLevel() or 1) + 20)
	local function ShowIfOn()
		local db = ns.db
		button:SetShown(db and db.enabled and db.tooltips and db.tooltips.upgrade and not (ns.Yields and ns.Yields("upgradeArrows")) and true or false)
	end
	sheet:HookScript("OnShow", ShowIfOn)
	ShowIfOn()
end

function ns.InitWeights()
	CharacterButton()
	-- (the sheet made later: the button with its first opening)
	if not _G.CharacterFrame and _G.ToggleCharacter then hooksecurefunc("ToggleCharacter", CharacterButton) end
end

function ns.ToggleWeights()
	if not ns.root then return end
	if not window then CreateWindow() end
	window:SetShown(not window:IsShown())
end
