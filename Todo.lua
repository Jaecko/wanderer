local _, ns = ...
local L = ns.L

-- The reminders of the travel journal: what not to forget on the way. Write
-- a line, Enter notes it; a click ticks it (done ones go greyed to the
-- bottom) and the journal's chronicle keeps it ("Done as planned: ..."); the
-- cross under the mouse removes it, one button clears the done ones. Each
-- character has its own, kept between sessions. Opened by its key, /wanderer
-- todo, the minimap menu or the journal itself. Drawn by the shared engine,
-- under the journal's own heading.

local U = ns.Util

local WIDTH = 300
local ROW_HEIGHT = 22
local VISIBLE = 12 -- rows shown at once; the wheel scrolls the rest
local MAX_ITEMS = 60
local CHECK_SIZE = 18

local window, kicker, title, input, clearButton, empty
local rows = {}
local offset = 0 -- first item shown (scrolling)

-- The list of this character: { { text, done, t }, ... }.
local function Items()
	local root = ns.root
	root.todo = type(root.todo) == "table" and root.todo or {}
	local key = ns.CharacterKey()
	if type(root.todo[key]) ~= "table" then root.todo[key] = {} end
	return root.todo[key]
end

-- To do first, in the order written; done ones after.
local function Sorted()
	local pending, done = {}, {}
	for _, item in ipairs(Items()) do
		if item.done then done[#done + 1] = item else pending[#pending + 1] = item end
	end
	for _, item in ipairs(done) do pending[#pending + 1] = item end
	return pending
end

local function Remove(target)
	local items = Items()
	for index, item in ipairs(items) do
		if item == target then
			table.remove(items, index)
			return
		end
	end
end

local Refresh

local function Row(index)
	local row = rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, window)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.box = row:CreateTexture(nil, "ARTWORK")
	row.box:SetSize(CHECK_SIZE, CHECK_SIZE)
	row.box:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
	row.check = row:CreateTexture(nil, "OVERLAY")
	row.check:SetAllPoints(row.box)
	row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(14, 14)
	row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
	row.remove:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
	row.remove:SetScript("OnClick", function()
		Remove(row.item)
		Refresh()
	end)
	row.remove:SetScript("OnEnter", function(self)
		row.remove:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.TODO_REMOVE, 1, 1, 1)
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.text = ns.Skin.CreateText(row, "GameTooltipText", 0.95, 0.93, 0.88)
	row.text:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
	if row.text.SetWordWrap then row.text:SetWordWrap(false) end
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 0.82, 0, 0.08)
	row.highlight:Hide()
	-- A click ticks (or unticks); a right click removes, as the cross does.
	row:SetScript("OnClick", function(self, button)
		if not self.item then return end
		if button == "RightButton" then
			Remove(self.item)
		else
			self.item.done = not self.item.done or nil
			-- Done: written in the journal's chronicle, as the rest of the journey.
			if self.item.done and ns.JournalNote then ns.JournalNote("todo", self.item.text) end
			local sound = SOUNDKIT and SOUNDKIT[self.item.done and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF"]
			if sound then pcall(PlaySound, sound) end
		end
		Refresh()
	end)
	row:SetScript("OnEnter", function(self)
		self.highlight:Show()
		self.remove:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.highlight:Hide()
		if not (U.IsMouseOver(self.remove)) then self.remove:Hide() end
	end)
	row.remove:Hide()
	rows[index] = row
	return row
end

Refresh = function()
	if not (window and window:IsShown()) then return end
	local list = Sorted()
	local pending = 0
	for _, item in ipairs(list) do if not item.done then pending = pending + 1 end end
	offset = math.max(0, math.min(offset, #list - VISIBLE))
	title:SetText(pending > 0 and L.TODO_TITLE_COUNT:format(pending) or L.TODO_TITLE)
	local margin = ns.Skin.Margin() + 6
	local shown = math.min(VISIBLE, #list)
	for index = 1, shown do
		local item = list[index + offset]
		local row = Row(index)
		row.item = item
		row.text:SetText(item.text)
		if item.done then row.text:SetTextColor(0.5, 0.5, 0.5) else row.text:SetTextColor(0.95, 0.93, 0.88) end
		row.check:SetShown(item.done and true or false)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8 - (index - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
		row:Show()
	end
	for index = shown + 1, #rows do
		rows[index]:Hide()
		rows[index].item = nil
	end
	empty:SetShown(#list == 0)
	clearButton:SetShown(#list > pending)
	local listHeight = math.max(1, shown) * ROW_HEIGHT
	window:SetHeight(margin * 2 + 14 + 18 + 8 + listHeight + 10 + 24 + (clearButton:IsShown() and 22 or 0))
	ns.Skin.Get(window):Layout()
end

local function Add()
	local text = strtrim(input:GetText() or "")
	if text == "" then return end
	input:SetText("")
	local items = Items()
	if #items >= MAX_ITEMS then return end
	items[#items + 1] = { text = text, t = time() }
	-- The new line in view.
	offset = math.max(0, #Sorted() - VISIBLE)
	Refresh()
end

local function ClearDone()
	local items = Items()
	for index = #items, 1, -1 do
		if items[index].done then table.remove(items, index) end
	end
	Refresh()
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererTodo", "MEDIUM")
	ns.Skin.Sounds(window, "IG_QUEST_LOG_OPEN", "IG_QUEST_LOG_CLOSE")
	window:SetWidth(WIDTH)
	ns.Skin.Dress(window, { "RIGHT", UIParent, "RIGHT", -260, 80 }, "todoPos")
	local margin = ns.Skin.Margin() + 6
	-- Under the journal's heading, like its pages.
	kicker = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.85, 0.75, 0.5)
	kicker:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	kicker:SetText(L.JOURNAL_OPEN:upper())
	title = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -3)
	empty = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	empty:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	empty:SetText(L.TODO_EMPTY)
	-- The line to write a new one, at the bottom.
	input = ns.Skin.CreateInput(window, "WandererTodoInput", 120)
	input:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	input:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	input.hint = ns.Skin.CreateText(input, "GameTooltipTextSmall", 0.5, 0.5, 0.5)
	input.hint:SetPoint("LEFT", input, "LEFT", 8, 0)
	input.hint:SetText(L.TODO_ADD_HINT)
	input:SetScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end)
	input:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
	input:SetScript("OnEditFocusLost", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
	input:SetScript("OnEnterPressed", Add)
	input:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		window:Hide()
	end)
	-- Clear the done ones, over the line.
	clearButton = CreateFrame("Button", nil, window)
	clearButton:SetHeight(18)
	clearButton:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 4)
	clearButton.text = ns.Skin.CreateText(clearButton, "GameTooltipTextSmall", 0.75, 0.68, 0.5)
	clearButton.text:SetPoint("RIGHT")
	clearButton.text:SetText(L.TODO_CLEAR_DONE)
	clearButton:SetWidth(U.Measure(clearButton.text, "GetStringWidth", 160) + 8)
	clearButton:SetScript("OnClick", ClearDone)
	clearButton:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0) end)
	clearButton:SetScript("OnLeave", function(self) self.text:SetTextColor(0.75, 0.68, 0.5) end)
	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		Refresh()
	end)
	window:HookScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		Refresh()
	end)
end

function ns.ToggleTodo()
	if not ns.root then return end
	if not window then CreateWindow() end
	window:SetShown(not window:IsShown())
end

function Wanderer_ToggleTodo() ns.ToggleTodo() end

-- What is left to do (the minimap menu shows it).
function ns.TodoPending()
	if not ns.root then return 0 end
	local count = 0
	for _, item in ipairs(Items()) do if not item.done then count = count + 1 end end
	return count
end

-- (tests)
ns.TodoItems = Items
