local _, ns = ...
local L = ns.L

-- The reminders: what not to forget on the way. Write a line, Enter notes
-- it; a click ticks it (done ones go greyed to the bottom); the cross under
-- the mouse removes it, one button clears the done ones. Each character has
-- its own, kept between sessions. Opened by its key, /wanderer todo, the
-- options or the minimap menu, under Wanderer's own heading.
--
-- A right click on a line: important (a star, on top), up or down, tied to
-- the place where you stand (back there, a notice says what is left to do;
-- the game's own map pin shows the way), crossed out.
--
-- The other addons may add lines (Wanderer.AddTodo): an item to gather says
-- how many you carry; such a line can go to Wanderer Auction's shopping list.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local WIDTH = 300
local ROW_HEIGHT = 22
local VISIBLE = 12 -- rows shown at once (until the window is resized: as many as fit); the wheel scrolls the rest
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 240, 170, 700, 900
local MAX_ITEMS = 60

local window, title, input, clearButton, empty
local rows = {}
local offset = 0 -- first item shown (scrolling)
local scrollBar
local sizing = false -- its corner being dragged

-- The size you gave it (nil: as tall as its lines).
local function Size() return ns.root and ns.Mine().todoSize end

-- What is around the lines: heading, the line to write, the button over it.
local function Chrome(margin)
	return margin * 2 + 14 + 18 + 8 + 10 + 24 + (clearButton:IsShown() and 22 or 0)
end

-- The rows shown at once: those that fit in the height you gave, else the usual number.
local function Visible(margin)
	if not (Size() or sizing) then return VISIBLE end
	return math.max(1, math.floor((window:GetHeight() - Chrome(margin)) / ROW_HEIGHT))
end

-- The list of this character: { { text, done, t }, ... }.
local function Items()
	local root = ns.root
	root.todo = type(root.todo) == "table" and root.todo or {}
	local key = ns.CharacterKey()
	if type(root.todo[key]) ~= "table" then root.todo[key] = {} end
	return root.todo[key]
end

-- Important ones first, then the others to do, in their order; done ones after.
local function Sorted()
	local important, pending, done = {}, {}, {}
	for _, item in ipairs(Items()) do
		if item.done then done[#done + 1] = item
		elseif item.star then important[#important + 1] = item
		else pending[#pending + 1] = item end
	end
	for _, item in ipairs(pending) do important[#important + 1] = item end
	for _, item in ipairs(done) do important[#important + 1] = item end
	return important
end

-- One place up or down among its own kind (important, to do, done).
local function Move(target, step)
	local items = Items()
	local function Kind(item) return item.done and 3 or (item.star and 1 or 2) end
	local from
	for index, item in ipairs(items) do if item == target then from = index end end
	if not from then return end
	local to = from + step
	while items[to] and Kind(items[to]) ~= Kind(target) do to = to + step end
	if items[to] then items[from], items[to] = items[to], items[from] end
end

-- Where you stand: the map and the point, the place's name.
local function Here()
	local map, x, y = U.HereOnMap()
	return { map = map, x = x, y = y, zone = Clean(Safe(GetRealZoneText)), sub = Clean(Safe(GetSubZoneText)) }
end

local function PlaceName(place)
	return place.sub and place.sub ~= place.zone and (place.sub .. ", " .. (place.zone or "")) or place.zone or "?"
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

-- The menu of a line (right click), the game's own menus.
local OpenMenu = function(row)
	local item = row.item
	U.Menu(row, function(_, root)
		root:CreateButton(item.star and L.TODO_UNSTAR or L.TODO_STAR, function()
			item.star = not item.star or nil
			Refresh()
		end)
		root:CreateButton(L.MOVE_UP, function() Move(item, -1) Refresh() end)
		root:CreateButton(L.MOVE_DOWN, function() Move(item, 1) Refresh() end)
		root:CreateDivider()
		if item.place then
			-- (with Wanderer Maps: followed by its arrow; else the game's own pin)
			root:CreateButton(L.GO_THERE, function() U.Go(item.place.map, item.place.x, item.place.y, item.text) end)
			root:CreateButton(L.TODO_UNPLACE, function() item.place = nil Refresh() end)
		else
			root:CreateButton(L.TODO_PLACE, function() item.place = Here() Refresh() end)
		end
		local auction = _G.WandererAuction
		-- (once on the shopping list, Auction buys it: never offered twice)
		-- (Auction switched off: no list offered; an older Auction without IsOn taken as on)
		if item.item and type(auction) == "table" and auction.AddToShopping
			and (type(auction.IsOn) ~= "function" or auction.IsOn())
			and not (auction.InShopping and auction.InShopping(item.item)) then
			root:CreateDivider()
			root:CreateButton(L.TODO_SHOPPING, function()
				auction.AddToShopping(item.item, item.count or 1, item.text)
			end)
		end
		root:CreateDivider()
		root:CreateButton("|cffff6060" .. L.TODO_REMOVE .. "|r", function() Remove(item) Refresh() end)
	end)
end

local function Row(index)
	local row = rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, window)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- The kit's check box, ticked when done (the whole row answers the clicks).
	row.check = ns.Skin.Check(row, "", function() return row.item and row.item.done end, function() end)
	row.check:EnableMouse(false)
	row.check:SetWidth(row.check.box:GetWidth())
	row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
	-- (the kit's glyph button: its gold under the mouse, its press, its click)
	row.remove = ns.Skin.GlyphButton(row, "close", 10, L.TODO_REMOVE, function()
		Remove(row.item)
		Refresh()
	end)
	row.remove:SetSize(14, 14)
	row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.remove:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
	-- Important: a small star by the box.
	row.star = row:CreateTexture(nil, "OVERLAY")
	row.star:SetSize(12, 12)
	row.star:SetPoint("CENTER", row.check.box, "TOPRIGHT", -2, -2)
	local starred = row.star.SetAtlas and pcall(row.star.SetAtlas, row.star, "PetJournal-FavoritesIcon")
	if not starred then row.star:SetTexture("Interface\\Common\\FavoritesIcon") end
	row.star:Hide()
	row.text = ns.Skin.CreateText(row, "GameTooltipText", 0.95, 0.93, 0.88)
	row.text:SetPoint("LEFT", row.check.box, "RIGHT", 6, 0)
	-- (the "⋯" button's own column, left of the cross: never over the words)
	row.text:SetPoint("RIGHT", row.remove, "LEFT", -(ns.Skin.ROW_MORE + 6), 0)
	if row.text.SetWordWrap then row.text:SetWordWrap(false) end
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 0.82, 0, 0.08)
	row.highlight:Hide()
	-- A click ticks (or unticks); a right click opens its menu.
	row:SetScript("OnClick", function(self, button)
		if not self.item then return end
		if button == "RightButton" then
			return OpenMenu(self)
		else
			self.item.done = not self.item.done or nil
			U.PlaySound(self.item.done and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		end
		Refresh()
	end)
	row:SetScript("OnEnter", function(self)
		self.highlight:Show()
		self.remove:Show()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L.TODO_ROW_HINT, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		self.highlight:Hide()
		if not (U.IsMouseOver(self.remove)) then self.remove:Hide() end
	end)
	row.remove:Hide()
	-- (after the row's own hover: its hooks kept)
	row.more = ns.Skin.RowMore(row, function(self) if self.item then OpenMenu(self) end end, row.remove)
	rows[index] = row
	return row
end

Refresh = function()
	if not (window and window:IsShown()) then return end
	local list = Sorted()
	local pending = 0
	for _, item in ipairs(list) do if not item.done then pending = pending + 1 end end
	title:SetText(pending > 0 and L.TODO_TITLE_COUNT:format(pending) or L.TODO_TITLE)
	local margin = ns.Skin.Margin() + 6
	clearButton:SetShown(#list > pending)
	-- The size you gave it first (while you drag, the corner's): the lines that fit follow.
	local size = Size()
	if size and not sizing then window:SetSize(size[1], size[2]) end
	local visible = Visible(margin)
	offset = math.max(0, math.min(offset, #list - visible))
	local shown = math.min(visible, #list)
	if scrollBar then
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(margin - 8), -(margin + 30))
		scrollBar:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 10, 28)
		scrollBar:Set(#list, visible, offset)
	end
	for index = 1, shown do
		local item = list[index + offset]
		local row = Row(index)
		row.item = item
		local words = item.text
		-- An item to gather: how many you carry (green once enough).
		if item.item and item.count and not item.done then
			words = words .. "  " .. U.HaveNeed(U.ItemCount(item.item), item.count)
		end
		if item.place then words = words .. "  |cff808080· " .. PlaceName(item.place) .. "|r" end
		row.text:SetText(words)
		row.star:SetShown(item.star and not item.done or false)
		if item.done then row.text:SetTextColor(0.5, 0.5, 0.5) else row.text:SetTextColor(0.95, 0.93, 0.88) end
		row.check:Refresh()
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
	-- Never resized: as tall as its lines.
	if not (size or sizing) then
		local listHeight = math.max(1, shown) * ROW_HEIGHT
		if #list == 0 then listHeight = math.max(listHeight, U.Measure(empty, "GetStringHeight", ROW_HEIGHT) + 6) end
		window:SetHeight(Chrome(margin) + listHeight)
	end
	ns.Skin.Get(window):Layout()
end

local function Add()
	local text = strtrim(input:GetText() or "")
	if text == "" then return end
	local items = Items()
	-- (full: said, the line stays in the box)
	if #items >= MAX_ITEMS then return ns.Print(L.TODO_FULL:format(MAX_ITEMS)) end
	input:SetText("")
	items[#items + 1] = { text = text, t = time() }
	-- The new line in view.
	offset = math.max(0, #Sorted() - Visible(ns.Skin.Margin() + 6))
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
	window:SetWidth(Size() and Size()[1] or WIDTH)
	ns.Skin.Dress(window, { "RIGHT", UIParent, "RIGHT", -260, 80 }, "todoPos")
	local _, margin
	_, title, margin = ns.Skin.Header(window, L.ADDON_TITLE, nil, { margin = 6, settings = "practical" })
	empty = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	empty:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	-- Inside the window, over as many lines as it needs.
	empty:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	if empty.SetWordWrap then empty:SetWordWrap(true) end
	empty:SetJustifyH("LEFT")
	empty:SetText(L.TODO_EMPTY)
	-- The line to write a new one, at the bottom.
	input = ns.Skin.CreateInput(window, "WandererTodoInput", 120, {
		hint = L.TODO_ADD_HINT,
		onEnter = Add,
		onEscape = function(self)
			self:ClearFocus()
			window:Hide()
		end,
	})
	input:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	input:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin - 10, margin) -- (the corner's grip beside it)
	-- Clear the done ones, over the line.
	clearButton = CreateFrame("Button", nil, window)
	clearButton:SetHeight(18)
	clearButton:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 4)
	clearButton.text = ns.Skin.CreateText(clearButton, "GameTooltipTextSmall", 0.75, 0.68, 0.5)
	clearButton.text:SetPoint("RIGHT")
	clearButton.text:SetText(L.TODO_CLEAR_DONE)
	clearButton:SetWidth(U.Measure(clearButton.text, "GetStringWidth", 160) + 8)
	clearButton:SetScript("OnClick", function()
		ns.Skin.Play("click")
		ClearDone()
	end)
	clearButton:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0) end)
	clearButton:SetScript("OnLeave", function(self) self.text:SetTextColor(0.75, 0.68, 0.5) end)
	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		Refresh()
	end)
	scrollBar = ns.Skin.ScrollBar(window, function(at)
		offset = math.floor(at + 0.5)
		Refresh()
	end)
	window:HookScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		Refresh()
	end)
	-- The corner: dragged, the window grows or shrinks, as many lines as fit; its size and place kept.
	ns.Skin.Resizable(window, {
		minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, maxWidth = MAX_WIDTH, maxHeight = MAX_HEIGHT,
		onStart = function() sizing = true end,
		onSizing = function() Refresh() end,
		onResized = function(width, height)
			sizing = false
			ns.Mine().todoSize = { width, height }
			Refresh()
		end,
	})
end

-- Back where a line was tied: what is left to do there.
local function Arrived()
	local zone = Clean(Safe(GetRealZoneText))
	if not (zone and ns.root and ns.db and ns.db.enabled) then return end
	local here = {}
	for _, item in ipairs(Items()) do
		if item.place and not item.done and item.place.zone == zone then here[#here + 1] = item.text end
	end
	if here[1] then ns.Toast(L.TODO_HERE, table.concat(here, "\n"), { duration = 6 }) end
end

-- At login, something left to do: the reminders open by themselves (silently, once the interface is
-- there), unless you said not to (ns.Mine().todoAtLogin false).
local function LoggedIn()
	if not (ns.root and ns.Mine().todoAtLogin ~= false and ns.db and ns.db.enabled) then return end
	C_Timer.After(3, function()
		if ns.TodoPending() == 0 then return end
		if not window then CreateWindow() end
		if window:IsShown() then return end
		window.quiet = true
		window:Show()
	end)
end

function ns.InitTodo()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:SetScript("OnEvent", function(_, event, isLogin)
		if event == "BAG_UPDATE_DELAYED" then
			-- (what you carry changed: the counts of the lines shown)
			if window and window:IsShown() then Refresh() end
			return
		end
		if event == "PLAYER_ENTERING_WORLD" then
			if isLogin then LoggedIn() end
			return
		end
		Arrived()
	end)
end

-- A line from another addon: text; opts.key (never twice the same), opts.item and opts.count (an item to
-- gather), opts.place ({ map, x, y (0 to 1), zone }). True when added; false and why ("known", "full").
function ns.AddTodo(text, opts)
	if not ns.root or type(text) ~= "string" or strtrim(text) == "" then return false end
	opts = type(opts) == "table" and opts or {}
	local items = Items()
	if opts.key then
		for _, item in ipairs(items) do
			if item.key == opts.key and not item.done then return false, "known" end
		end
	end
	if #items >= MAX_ITEMS then return false, "full" end
	local place = type(opts.place) == "table" and opts.place.map and opts.place or nil
	items[#items + 1] = { text = strtrim(text), t = time(), key = opts.key, item = tonumber(opts.item),
		count = tonumber(opts.count), place = place }
	Refresh()
	return true
end

-- A line from another addon still to do (by its key).
function ns.HasTodo(key)
	if not (ns.root and key) then return false end
	for _, item in ipairs(Items()) do
		if item.key == key and not item.done then return true end
	end
	return false
end

-- A line an extension put here, taken away when its reason is gone (the letters sent): true when one was.
function ns.RemoveTodo(key)
	if not (ns.root and key) then return false end
	local items, removed = Items(), false
	for index = #items, 1, -1 do
		if items[index].key == key and not items[index].done then
			table.remove(items, index)
			removed = true
		end
	end
	if removed then Refresh() end
	return removed
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
