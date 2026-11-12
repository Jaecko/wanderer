local _, ns = ...
local SOLID = 0.97 -- the window's least opacity
local L = ns.L
local U = ns.Util

-- Wanderer's settings window. On the left, a search over every word of the settings and the pages: Wanderer's,
-- each installed extension's, then Profiles, Keys, What you changed, Pieces on the screen and News. On the
-- right, the page, its rows drawn from the declarations of Options.lua: a switch, a slider with its value, a
-- list, a button, each with its description under its name. An option under another one is stepped in and
-- greyed while that one is off; one left to another addon is greyed and says who does it. The less used rows
-- (an advanced section) wait at the bottom, folded under "More settings". Values apply at once, through the
-- same setters. Its place is kept for each character, Escape closes it, the size of its
-- words follows Wanderer's.

local WIDTH, HEIGHT = 880, 600
local SIDEBAR = 210
local NAV_ROW = 24
local INDENT = 22
local CONTROL = 190 -- the room of a row's control, at its right
local WHEEL = 54 -- scrolled by a notch of the wheel
local FLASH_TIME = 1.6
local MAX_RESULTS = 60
local HEADING_GAP = 18

local Skin
local window, navBox, navCanvas, contentBox, search
local views = {}
local navButtons, navCaptions = {}, {}
local current -- the view shown ("results" while searching)
local lastPage = "home" -- the last page shown
local pageByKey = {}

-- Pieces ------------------------------------------------------------------------------------------------------

-- An area that scrolls: the frame it holds (box:Hold(canvas)) moves under it, the kit's scroll bar beside it,
-- the wheel scrolls it. In pixels.
local function Scroller(parent)
	local box = CreateFrame("Frame", nil, parent)
	if box.SetClipsChildren then box:SetClipsChildren(true) end
	box:EnableMouseWheel(true)
	box.offset, box.total = 0, 0
	box.bar = Skin.ScrollBar(parent, function(offset) box:ScrollTo(offset) end)
	box.bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
	box.bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
	function box:Hold(canvas)
		if self.canvas and self.canvas ~= canvas then self.canvas:Hide() end
		self.canvas = canvas
		self.offset = 0
		canvas:Show()
	end
	function box:SetTotal(total)
		self.total = total or 0
		if self.canvas then self.canvas:SetHeight(math.max(1, self.total)) end
		self:ScrollTo(self.offset)
	end
	function box:ScrollTo(offset)
		local room = math.max(0, self.total - self:GetHeight())
		self.offset = math.floor(math.max(0, math.min(room, offset or 0)) + 0.5)
		if self.canvas then
			self.canvas:ClearAllPoints()
			self.canvas:SetPoint("TOPLEFT", self, "TOPLEFT", 0, self.offset)
			self.canvas:SetWidth(self:GetWidth())
		end
		self.bar:Set(self.total, self:GetHeight(), self.offset)
	end
	box:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.offset - delta * WHEEL) end)
	return box
end

local function Height(text, fallback)
	if not text:IsShown() or (text:GetText() or "") == "" then return 0 end
	return U.Measure(text, "GetStringHeight", fallback or 14)
end

-- A value on the slider's steps (and no 1.2999999).
local function Snap(row, value)
	local step = row.step or 1
	value = row.min + math.floor((value - row.min) / step + 0.5) * step
	return tonumber(("%.4f"):format(math.max(row.min, math.min(row.max, value))))
end

-- A slider: its value written beside it, in gold; onValue(value) when moved by the player.
local function Slider(parent, row, onValue)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(CONTROL, 20)
	local slider = CreateFrame("Slider", nil, holder)
	slider:SetSize(126, 16)
	slider:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(row.min, row.max)
	slider:SetValueStep(row.step or 1)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetHeight(4)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetColorTexture(1, 1, 1, 0.12)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(8, 16)
	thumb:SetColorTexture(ns.Skin.RGB("gold", 1))
	slider:SetThumbTexture(thumb)
	local fill = slider:CreateTexture(nil, "ARTWORK")
	fill:SetHeight(4)
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetPoint("RIGHT", thumb, "CENTER")
	fill:SetColorTexture(ns.Skin.RGB("gold", 0.9))
	holder.value = Skin.Text(holder, "GameTooltipText", "gold")
	holder.value:SetJustifyH("RIGHT")
	holder.value:SetWidth(54)
	holder.value:SetPoint("RIGHT", slider, "LEFT", -10, 0)
	slider:SetScript("OnValueChanged", function(_, value)
		value = Snap(row, value)
		holder.value:SetText(row.text(value))
		if holder.filling then return end
		if math.abs(value - (tonumber(row.get()) or value)) > 0.0001 then onValue(value) end
	end)
	function holder:Set(value)
		self.filling = true
		slider:SetValue(value)
		self.value:SetText(row.text(value))
		self.filling = false
	end
	function holder:SetUsable(on)
		if on then slider:Enable() else slider:Disable() end
		slider:EnableMouse(on)
	end
	holder.slider = slider
	return holder
end

-- An option's job left to another addon: the first one done by another, or the only one.
local function Job(job)
	if type(job) ~= "table" then return job end
	for _, one in ipairs(job) do
		if ns.Yields(one) then return one end
	end
	return job[1]
end

-- Who does a row's job now (its muted words), nil when nobody.
function ns.SettingsRowNote(row)
	if not (row and row.yield) then return nil end
	return ns.YieldText(Job(row.yield))
end

-- What a row needs and lacks now ("Needs: words"), nil when it has it (or needs nothing).
function ns.SettingsRowNeeds(row)
	local needs = row and row.needs
	if not needs then return nil end
	local ok, on = pcall(needs.isOn)
	if ok and on then return nil end
	return L.NEEDS_PREFIX:format(tostring(needs.words or ""))
end

-- A row can be used: its job not left to another addon, what it needs there, the options it sits under on.
function ns.SettingsRowUsable(row)
	if row.yield and not row.partial and ns.Yields(Job(row.yield)) then return false end
	if ns.SettingsRowNeeds(row) then return false end
	if type(row.usable) == "function" then
		local ok, usable = pcall(row.usable)
		if ok and not usable then return false end
	end
	if not row.parent then return true end
	if row.isOn and not row.isOn() then return false end
	return ns.SettingsRowUsable(row.parent)
end

-- How far a row steps in: the options it sits under, among those drawn with it (a folded row under a row
-- shown above the fold starts at the edge).
local function Depth(row)
	local depth, at = 0, row.parent
	while at and depth < 4 do
		if (at.advanced and true or false) == (row.advanced and true or false) then depth = depth + 1 end
		at = at.parent
	end
	return depth
end

-- More settings: a page's rows under an advanced section, folded at its bottom under one quiet row. Unfolded
-- by a click (remembered for this character), or for a while by a search leading there.
local unfoldedNow = {}

function ns.SettingsPageUnfolded(page)
	if not page then return false end
	if unfoldedNow[page.key] then return true end
	local mine = ns.root and ns.Mine()
	return type(mine and mine.settingsMore) == "table" and mine.settingsMore[page.key] == true or false
end

function ns.SetSettingsPageUnfolded(page, on)
	unfoldedNow[page.key] = nil
	local mine = ns.Mine()
	mine.settingsMore = type(mine.settingsMore) == "table" and mine.settingsMore or {}
	mine.settingsMore[page.key] = on and true or nil
end

-- A row found by the search, lit a moment.
local flashing, flashDriver = {}, nil
local function Flash(frame)
	if not frame.flash then return end
	frame.flashLeft = FLASH_TIME
	frame.flash:SetAlpha(1)
	frame.flash:Show()
	flashing[frame] = true
	if not flashDriver then flashDriver = CreateFrame("Frame") end
	flashDriver:SetScript("OnUpdate", function(self, elapsed)
		for each in pairs(flashing) do
			each.flashLeft = each.flashLeft - elapsed
			each.flash:SetAlpha(math.max(0, each.flashLeft / FLASH_TIME))
			if each.flashLeft <= 0 then
				each.flash:Hide()
				flashing[each] = nil
			end
		end
		if not next(flashing) then self:SetScript("OnUpdate", nil) end
	end)
end

-- Views ----------------------------------------------------------------------------------------------------------
-- Each page is a view: a canvas in the scrolled area, built the first time it shows. view:Layout(width) places
-- its pieces and says how tall it is; view:Refresh() reads the values again.

local ShowView, Relayout, BuildNav

-- A page's title over its content, a few words under it (intro), a chip beside the title (a version).
local function Heading(view, title, intro)
	local canvas = view.canvas
	view.title = Skin.CreateText(canvas, "GameFontNormalLarge", ns.Skin.RGB("gold"))
	view.title:SetText(title or "")
	-- (one line from the start: measured as one line at the first layout)
	if view.title.SetWordWrap then view.title:SetWordWrap(false) end
	view.chip = Skin.Chip(canvas)
	view.intro = Skin.Text(canvas, "GameTooltipText", "soft")
	view.intro:SetText(intro or "")
	view.intro:SetShown(intro ~= nil)
end

local function LayoutHeading(view, width)
	view.title:ClearAllPoints()
	view.title:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", 0, -2)
	view.chip:ClearAllPoints()
	view.chip:SetPoint("LEFT", view.title, "LEFT", U.Measure(view.title, "GetStringWidth", 120) + 10, 0)
	local y = 2 + Height(view.title, 18)
	if view.intro:IsShown() then
		view.intro:SetWidth(width - 10)
		view.intro:ClearAllPoints()
		view.intro:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", 0, -(y + 8))
		y = y + 8 + Height(view.intro)
	end
	return y + HEADING_GAP
end

-- A section's title: in capitals, a thin rule after it.
local function SectionFrame(canvas, text)
	local frame = CreateFrame("Frame", nil, canvas)
	frame.caps = Skin.Caps(frame, text, "kicker")
	frame.caps:SetPoint("LEFT", frame, "LEFT", 0, 0)
	frame.rule = Skin.Rule(frame, false, 0.14)
	frame.rule:SetPoint("LEFT", frame.caps, "RIGHT", 10, 0)
	frame.rule:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
	return frame
end

local function PlaceSection(frame, canvas, y, width, first)
	y = y + (first and 0 or 16)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
	frame:SetSize(width, 20)
	frame.top = y
	return y + 26
end

-- A row's frame: its name, its description, who does its job, a hover, a light when found; control: its own.
local function RowFrame(canvas, label, desc)
	local frame = CreateFrame("Button", nil, canvas)
	frame.hover = frame:CreateTexture(nil, "BACKGROUND")
	frame.hover:SetAllPoints()
	frame.hover:SetColorTexture(1, 1, 1, ns.Skin.HOVER)
	frame.hover:Hide()
	frame.flash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	frame.flash:SetAllPoints()
	frame.flash:SetColorTexture(ns.Skin.RGB("gold", 0.14))
	frame.flash:Hide()
	frame.guide = frame:CreateTexture(nil, "ARTWORK")
	frame.guide:SetColorTexture(ns.Skin.RGB("gold", 0.16))
	frame.guide:SetWidth(1)
	frame.guide:Hide()
	frame.label = Skin.Text(frame, "GameTooltipText", "text")
	frame.label:SetText(label or "")
	frame.desc = Skin.Text(frame, "GameTooltipTextSmall", "muted")
	frame.desc:SetText(desc or "")
	frame.desc:SetShown(desc ~= nil and desc ~= "")
	frame.note = Skin.Chip(frame)
	-- (what it needs and lacks: one muted line under its description)
	frame.needs = Skin.Text(frame, "GameTooltipTextSmall", "warn")
	frame.needs:Hide()
	-- (a job an extension of the family does: its words open its page)
	frame.note:SetScript("OnMouseUp", function(self)
		if not self.page then return end
		Skin.Play("click")
		ShowView(self.page)
	end)
	Skin.Tooltip(frame.note, function(self) return self.page and L.SETTINGS_OPEN_PAGE or nil end)
	frame:SetScript("OnEnter", function(self) self.hover:Show() end)
	frame:SetScript("OnLeave", function(self) self.hover:Hide() end)
	return frame
end

-- A setting changed from its default: a small gold dot before its name, and under the mouse an undo glyph left
-- of its control (back to the default, one click; "What you changed" keeps the undo of it).
local function ChangeMarks(frame)
	frame.changedDot = frame:CreateTexture(nil, "OVERLAY")
	frame.changedDot:SetSize(5, 5)
	frame.changedDot:SetColorTexture(ns.Skin.RGB("gold", 0.9))
	frame.changedDot:SetPoint("TOPRIGHT", frame.label, "TOPLEFT", -4, -5)
	frame.changedDot:Hide()
	frame.reset = Skin.GlyphButton(frame, "undo", 14, function(self)
		local changes = self.changes or {}
		local first = changes[1]
		if not first then return nil end
		return { L.SETTINGS_ROW_RESET, L.SETTINGS_ROW_DEFAULT:format(ns.SettingText(first.words, first.default)) }
	end, function(self)
		local paths = {}
		for _, changed in ipairs(self.changes or {}) do
			for _, path in ipairs(changed.paths) do paths[#paths + 1] = path end
		end
		if paths[1] and ns.ResetSettings(paths) then Skin.Play("confirm") end
		if ns.RefreshSettingsWindow then ns.RefreshSettingsWindow() end
	end)
	frame.reset:SetPoint("RIGHT", frame, "RIGHT", -(10 + CONTROL + 2), 0)
	frame.reset:SetFrameLevel(frame:GetFrameLevel() + 3)
	frame.reset:Hide()
	local function Hover()
		frame.reset:SetShown(frame.changes ~= nil and (U.Hovered(frame) or U.Hovered(frame.reset)))
	end
	frame:HookScript("OnEnter", Hover)
	frame:HookScript("OnLeave", Hover)
	frame.reset:HookScript("OnLeave", Hover)
end

local function PlaceRow(frame, canvas, y, width, depth)
	local indent = depth * INDENT
	-- (room left for the undo glyph, left of the control)
	local textWidth = width - indent - CONTROL - 44
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
	frame:SetWidth(width)
	frame.label:SetWidth(textWidth)
	frame.label:ClearAllPoints()
	frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", indent + 10, -9)
	frame.desc:SetWidth(textWidth)
	frame.desc:ClearAllPoints()
	frame.desc:SetPoint("TOPLEFT", frame.label, "BOTTOMLEFT", 0, -3)
	frame.note:ClearAllPoints()
	frame.note:SetPoint("LEFT", frame.label, "LEFT", math.min(textWidth, U.Measure(frame.label, "GetStringWidth", 100)) + 8, 0)
	local height = 9 + Height(frame.label) + (frame.desc:IsShown() and 3 + Height(frame.desc, 12) or 0) + 9
	if frame.needs and frame.needs:IsShown() then
		frame.needs:SetWidth(textWidth)
		frame.needs:ClearAllPoints()
		frame.needs:SetPoint("TOPLEFT", frame.desc:IsShown() and frame.desc or frame.label, "BOTTOMLEFT", 0, -3)
		height = height + 3 + Height(frame.needs, 12)
	end
	-- (a row of choices: every choice in view, under its words)
	local segmented = frame.control and frame.control.segmented
	if segmented then
		frame.control:ClearAllPoints()
		frame.control:SetPoint("TOPLEFT", frame, "TOPLEFT", indent + 10, -height)
		height = height + frame.control:GetHeight() + 10
	end
	height = math.max(height, 38)
	frame:SetHeight(height)
	-- (under another option: a thin line where it steps in)
	frame.guide:SetShown(depth > 0)
	if depth > 0 then
		frame.guide:ClearAllPoints()
		frame.guide:SetPoint("TOPLEFT", frame, "TOPLEFT", indent - 6, -4)
		frame.guide:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", indent - 6, 4)
	end
	if frame.control and not segmented then
		frame.control:ClearAllPoints()
		frame.control:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
	end
	frame.top = y
	return y + height + 2
end

-- The rows of a page of Options.lua ------------------------------------------------------------------------------

local function Choices(row)
	local list = {}
	local made = type(row.choices) == "function" and row.choices() or row.choices
	for _, choice in ipairs(made or {}) do list[#list + 1] = { id = choice[1], label = choice[2] } end
	return list
end

-- A value changed: the page drawn again (the options under it, their state).
local function Changed()
	if ns.RefreshSettingsWindow then ns.RefreshSettingsWindow() end
end

local function Control(frame, row)
	if row.kind == "check" then
		local function Toggle()
			if not frame.usable then return Skin.Play("refuse") end
			row.set(not row.get())
			Skin.Play("mark")
			Changed()
		end
		frame.control = Skin.Switch(frame, Toggle)
		-- (the row's words switch it too)
		frame:SetScript("OnClick", Toggle)
	elseif row.kind == "slider" then
		frame.control = Slider(frame, row, function(value)
			row.set(value)
			Changed()
		end)
	elseif row.kind == "dropdown" and row.segmented then
		local list = {}
		for _, choice in ipairs(Choices(row)) do list[#list + 1] = { choice.id, choice.label } end
		frame.control = Skin.Choices(frame, list, function(value)
			if not frame.usable then
				frame.control:Select(row.get())
				return Skin.Play("refuse")
			end
			row.set(value)
			Changed()
		end, 26)
		frame.control.segmented = true
	elseif row.kind == "dropdown" then
		frame.control = Skin.Dropdown(frame, function() return Choices(row) end, row.get, function(value)
			row.set(value)
			Changed()
		end, nil, 120, CONTROL)
		frame.control:SetHeight(26)
	elseif row.kind == "button" then
		frame.control = Skin.Button(frame, type(row.text) == "string" and row.text or "", function(self)
			row.onClick(self)
			Changed()
		end, nil, 100)
		frame.control:SetHeight(26)
	end
end

-- The settings changed from their defaults, by the words of their option: words -> { { path, value, default,
-- words } } (made again at each refresh: one walk of the profile).
local changedIndex = {}
local function IndexChanges()
	changedIndex = {}
	for _, changed in ipairs(ns.ChangedSettings and ns.ChangedSettings() or {}) do
		local list = changedIndex[changed.words] or {}
		list[#list + 1] = changed
		changedIndex[changed.words] = list
	end
end

-- A row's settings changed from their defaults (nil: none, or a row that is no setting of the profile).
local function RowChanges(row)
	if row.shortcut or not row.variable then return nil end
	local words = ns.OPTION_WORDS.variables[row.variable]
	return words and changedIndex[words] or nil
end

-- A page's changed settings: how many rows, and all their paths.
function ns.SettingsPageChanges(page)
	local count, paths = 0, {}
	for _, row in ipairs(page and page.rows or {}) do
		local changes = RowChanges(row)
		if changes then
			count = count + 1
			for _, changed in ipairs(changes) do
				for _, path in ipairs(changed.paths) do paths[#paths + 1] = path end
			end
		end
	end
	return count, paths
end

-- The family's page doing a row's job (its blue words open it).
local function NotePage(row)
	return row.yield and ns.YieldPage and ns.YieldPage(Job(row.yield)) or nil
end

local function RefreshRow(frame)
	local row = frame.row
	if row.kind == "header" then return end
	if row.kind == "block" then return frame:Refresh() end
	local usable = ns.SettingsRowUsable(row)
	frame.usable = usable
	frame:SetAlpha(usable and 1 or 0.45)
	local note = ns.SettingsRowNote(row)
	frame.note:Set(note, "blue")
	frame.note.page = note and NotePage(row) or nil
	frame.note:EnableMouse(frame.note.page ~= nil)
	local needs = ns.SettingsRowNeeds(row)
	frame.needs:SetText(needs or "")
	frame.needs:SetShown(needs ~= nil)
	local changes = RowChanges(row)
	frame.changes, frame.reset.changes = changes, changes
	frame.changedDot:SetShown(changes ~= nil)
	if not changes then frame.reset:Hide() end
	if row.kind == "button" and type(row.text) == "function" and frame.control then
		local ok, words = pcall(row.text)
		frame.control:SetText(ok and tostring(words or "") or "")
		if frame.control.Fit then frame.control:Fit() end
	end
	local control = frame.control
	if not control then return end
	if row.kind == "check" then
		control:Set(row.get())
	elseif row.kind == "slider" then
		control:Set(tonumber(row.get()) or row.min)
		control:SetUsable(usable)
	elseif control.segmented then
		control:Select(row.get())
	elseif row.kind == "dropdown" then
		control:Refresh()
	end
	if control.SetEnabled and row.kind ~= "slider" then
		control:SetEnabled(usable)
		-- (the row is dimmed already)
		control:SetAlpha(1)
	end
end

-- A page's title (the home page: its general settings; the sidebar names Wanderer over it).
function ns.SettingsPageTitle(page)
	return page.key == "home" and L.SECTION_GENERAL or page.name
end

-- The quiet row folding a page's less used rows: its words, how many, a sign up or down.
local function FoldFrame(canvas, count, onClick)
	local frame = CreateFrame("Button", nil, canvas)
	frame.rule = Skin.Rule(frame, false, 0.1)
	frame.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	frame.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, 0)
	frame.hover = frame:CreateTexture(nil, "BACKGROUND")
	frame.hover:SetAllPoints()
	frame.hover:SetColorTexture(1, 1, 1, ns.Skin.HOVER)
	frame.hover:Hide()
	frame.label = Skin.Text(frame, "GameTooltipText", "soft")
	frame.label:SetText(L.SETTINGS_MORE)
	frame.label:SetPoint("LEFT", frame, "LEFT", 10, 0)
	frame.count = Skin.Chip(frame)
	frame.count:Set(tostring(count), "grey")
	frame.count:SetPoint("LEFT", frame.label, "LEFT", U.Measure(frame.label, "GetStringWidth", 100) + 8, 0)
	frame.sign = Skin.Glyph(frame, "down", 10)
	frame.sign:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
	frame:SetScript("OnEnter", function(self) self.hover:Show() end)
	frame:SetScript("OnLeave", function(self) self.hover:Hide() end)
	frame:SetScript("OnClick", onClick)
	return frame
end

local function PageView(page)
	local view = { page = page, frames = {}, folded = 0 }
	function view:Build()
		Heading(self, ns.SettingsPageTitle(page))
		if page.addon then
			local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
			local version = get and U.Safe(get, page.addon, "Version")
			self.chip:Set(version, "grey")
			self.version = version
		end
		-- At the title's right: the page back to its defaults (asked first), then its undo for a while.
		self.resetLink = Skin.CreateLink(self.canvas, "", function()
			if self.undoUntil and GetTime() < self.undoUntil and ns.CanUndoReset() then
				self.undoUntil = nil
				ns.UndoReset()
				Skin.Play("confirm")
				return Changed()
			end
			local count, paths = ns.SettingsPageChanges(page)
			if count == 0 then return end
			Skin.Ask(U.Plural(count, L.SETTINGS_PAGE_RESET_ASK_ONE, L.SETTINGS_PAGE_RESET_ASK), function()
				if not ns.ResetSettings(paths) then return end
				self.undoUntil = GetTime() + 10
				Changed()
				C_Timer.After(10.1, Changed)
			end)
		end)
		self.resetLink:Hide()
		for index, row in ipairs(page.rows) do
			local frame
			if row.kind == "header" then
				-- (a first section named as the page: its title says it already)
				if not (index == 1 and row.label == ns.SettingsPageTitle(page)) then frame = SectionFrame(self.canvas, row.label) end
			elseif row.kind == "block" then
				-- (a piece the page draws itself: cards, a card of the game's settings)
				frame = row.build(self.canvas)
			else
				-- (with a controller, its own words when it has them)
				frame = RowFrame(self.canvas, row.label, U.UsingPad() and row.descPad or row.desc)
				ChangeMarks(frame)
				Control(frame, row)
				if row.advanced then self.advanced = true end
			end
			if frame then
				frame.row = row
				self.frames[#self.frames + 1] = frame
			end
		end
		-- (the fold exists whenever the page has less used rows; Layout counts the ones offered now)
		if self.advanced then
			self.fold = FoldFrame(self.canvas, 0, function()
				Skin.Play("click")
				ns.SetSettingsPageUnfolded(page, not ns.SettingsPageUnfolded(page))
				Relayout()
			end)
		end
	end
	-- The rows shown first, then the fold, then (unfolded) the rows under it.
	function view:Layout(width)
		local y = LayoutHeading(self, width)
		self.resetLink:ClearAllPoints()
		self.resetLink:SetPoint("TOPRIGHT", self.canvas, "TOPRIGHT", -6, -2)
		-- (a long title stops short of the reset link, on one line)
		self.title:SetPoint("RIGHT", self.resetLink, "LEFT", -12, 0)
		-- (a title cut there: no version chip after it, over the link)
		if self.version then
			local room = width - 6 - (self.resetLink:GetWidth() or 0) - 12
			self.chip:SetShown(U.Measure(self.title, "GetStringWidth", 120) + 10 + (self.chip:GetWidth() or 0) <= room)
		end
		-- (the pad can come or go while the window lives: each row's words, and the fold's count, follow it)
		local pad = U.UsingPad()
		self.folded = 0
		for _, frame in ipairs(self.frames) do
			local row = frame.row
			if row.kind ~= "header" and row.kind ~= "block" and frame.desc then
				local desc = pad and row.descPad or row.desc
				frame.desc:SetText(desc or "")
				frame.desc:SetShown(desc ~= nil and desc ~= "")
				if row.advanced and not (row.hidden and row.hidden()) then self.folded = self.folded + 1 end
			end
		end
		local placed = 0
		local function Place(frame)
			if frame.row.kind == "header" then
				y = PlaceSection(frame, self.canvas, y, width, placed == 0)
			elseif frame.row.kind == "block" then
				y = y + (placed > 0 and 8 or 0)
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
				local height = frame:Layout(width - 6)
				frame:SetSize(width - 6, height)
				frame.top = y
				y = y + height + 8
			else
				y = PlaceRow(frame, self.canvas, y, width, Depth(frame.row))
			end
			placed = placed + 1
		end
		for _, frame in ipairs(self.frames) do
			-- (row.hidden(): a row not offered now, the placing under the controller)
			local hidden = frame.row.hidden and frame.row.hidden()
			if not frame.row.advanced then
				frame:SetShown(not hidden)
				if not hidden then Place(frame) end
			end
		end
		if self.fold then self.fold:SetShown(self.folded > 0) end
		if self.fold and self.folded == 0 then
			for _, frame in ipairs(self.frames) do
				if frame.row.advanced then frame:Hide() end
			end
		elseif self.fold then
			local open = ns.SettingsPageUnfolded(page)
			self.fold.count:Set(tostring(self.folded), "grey")
			y = y + (placed > 0 and 14 or 0)
			self.fold:ClearAllPoints()
			self.fold:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
			self.fold:SetSize(width, 34)
			Skin.SetGlyph(self.fold.sign, open and "up" or "down")
			self.fold.top = y
			y = y + 36
			placed = open and 0 or placed
			for _, frame in ipairs(self.frames) do
				if frame.row.advanced then
					local shown = open and not (frame.row.hidden and frame.row.hidden())
					frame:SetShown(shown)
					if shown then Place(frame) end
				end
			end
		end
		return y + 20
	end
	function view:Refresh()
		IndexChanges()
		for _, frame in ipairs(self.frames) do RefreshRow(frame) end
		local count = ns.SettingsPageChanges(page)
		if self.undoUntil and GetTime() < self.undoUntil and ns.CanUndoReset() then
			self.resetLink:SetLabel(L.CHANGES_UNDO)
			self.resetLink:Show()
		else
			self.undoUntil = nil
			self.resetLink:SetLabel(L.SETTINGS_PAGE_RESET:format(count))
			self.resetLink:SetShown(count > 0)
		end
	end
	function view:FrameOf(row)
		for _, frame in ipairs(self.frames) do
			if frame.row == row then return frame end
		end
	end
	return view
end

-- Predefined styles: the cards of Themes.lua -----------------------------------------------------------------------

local function ThemesView()
	local view = {}
	function view:Build()
		Heading(self, L.PAGE_THEMES, L.THEMES_DESC)
		self.custom = Skin.Text(self.canvas, "GameTooltipTextSmall", "muted")
		self.custom:SetText(L.THEMES_CUSTOM)
		self.grid = ns.CreateThemeGrid(self.canvas, {
			onRefresh = function(key) self.custom:SetShown(key == nil) end,
		})
	end
	function view:Layout(width)
		local y = LayoutHeading(self, width)
		self.grid:Layout(self.intro, width - 6, HEADING_GAP)
		y = y + self.grid:Height() + 12
		self.custom:ClearAllPoints()
		self.custom:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
		self.custom:SetWidth(width - 10)
		return y + 30
	end
	function view:Refresh() self.grid:Refresh() end
	return view
end

-- Ways to play: the cards of Playstyles.lua ---------------------------------------------------------------------
-- The same grid and panel as the welcome. Here a way is asked first (how many settings change, which ones),
-- and the one taken can be undone for the session.

local ASK_LISTED = 8 -- the settings named in the question, the rest counted

local function PlaystylesView()
	local view = {}
	local function Ask(key)
		if InCombatLockdown() then return Skin.Play("refuse") end
		local changes, done = ns.PlaystyleChanges(key)
		local function Apply()
			if ns.ApplyPlaystyle(key, true) then Skin.Play("confirm") else Skin.Play("refuse") end
			Relayout()
		end
		if not changes[1] then return Apply() end
		-- (the settings named, the first ones; those without words only counted)
		local names = {}
		for _, change in ipairs(changes) do
			if change.words and #names < ASK_LISTED then names[#names + 1] = change.words end
		end
		local named = #names
		local list = table.concat(names, ", ")
		if #changes > named then list = list .. "  " .. L.PLAY_MORE:format(#changes - named) end
		local ask = done > 0 and L.PLAY_APPLY_ASK_DONE:format(#changes, done) or L.PLAY_APPLY_ASK:format(#changes)
		local text = ask .. "\n\n" .. Skin.Colorize(list, "muted")
		if ns.PlaystyleShared() then text = text .. "\n\n" .. Skin.Colorize(L.PLAY_SHARED_WARN, "warn") end
		Skin.Ask(text, Apply)
	end
	function view:Build()
		Heading(self, L.PAGE_PLAYSTYLES, L.PLAYSTYLES_DESC)
		self.grid = ns.CreatePlaystyleGrid(self.canvas, {
			onPick = Ask,
			onGet = function(offer) if offer then ShowView("offer:" .. offer.addon) end end,
		})
		self.undo = Skin.Button(self.canvas, L.PLAY_UNDO, function()
			if ns.UndoPlaystyle() then Skin.Play("confirm") else Skin.Play("refuse") end
			Relayout()
		end, nil, 120)
		self.undo:SetHeight(26)
		Skin.Tooltip(self.undo, { L.PLAY_UNDO, L.PLAY_UNDO_DESC })
	end
	function view:Layout(width)
		-- (said otherwise under a controller: no hovering there)
		self.intro:SetText(U.UsingPad() and L.PLAYSTYLES_DESC_PAD or L.PLAYSTYLES_DESC)
		local y = LayoutHeading(self, width)
		y = y + self.grid:Layout(self.intro, width - 6, HEADING_GAP)
		self.undo:ClearAllPoints()
		self.undo:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -(y + 12))
		self.undo:SetShown(ns.CanUndoPlaystyle())
		return y + 12 + (self.undo:IsShown() and self.undo:GetHeight() + 20 or 0)
	end
	function view:Refresh()
		local way = ns.CurrentPlaystyle()
		self.chip:Set(ns.PlaystyleWords(way), ns.PLAYSTYLES[way] and "gold" or "grey")
		self.undo:SetShown(ns.CanUndoPlaystyle())
		self.grid:Refresh()
	end
	return view
end

-- Keys ------------------------------------------------------------------------------------------------------------
-- Every key of Wanderer and of its extensions, set right here: a click, then the key (with Shift, Ctrl or Alt);
-- Escape keeps the one there was. A key another action uses is asked first. Never in a fight.

local KEYS = { "WANDERER_REVEAL", "WANDERER_MARKERS", "WANDERER_TODO", "WANDERER_PHOTO", "CLICK WandererCampfire:LeftButton" }

-- The game's keys of an action: the first, the second.
local function KeysOf(command)
	if not GetBindingKey then return nil end
	local first, second = GetBindingKey(command)
	return type(first) == "string" and first ~= "" and first or nil, type(second) == "string" and second ~= "" and second or nil
end


local function SaveKeys()
	if SaveBindings then pcall(SaveBindings, GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
end

-- The action on this key, in place of its first key (its second stays); true when set.
function ns.SetKey(command, key)
	if InCombatLockdown() or not SetBinding then return false end
	local first = KeysOf(command)
	if first and first ~= key then pcall(SetBinding, first) end
	local ok, set = pcall(SetBinding, key, command)
	if not ok or set == false then
		if first and first ~= key then pcall(SetBinding, first, command) end
		return false
	end
	SaveKeys()
	return true
end

-- Its keys let go.
function ns.ClearKeys(command)
	if InCombatLockdown() or not SetBinding then return false end
	local first, second = KeysOf(command)
	if first then pcall(SetBinding, first) end
	if second then pcall(SetBinding, second) end
	SaveKeys()
	return true
end

-- The commands of the game's list, in its order.
local function Commands()
	local list = {}
	if not (GetNumBindings and GetBinding) then return list end
	for index = 1, GetNumBindings() do
		local command = GetBinding(index)
		if type(command) == "string" then list[#list + 1] = command end
	end
	return list
end

-- Wanderer's keys, then each extension's (its commands are named after its folder: WANDERERCHAT_REPLY...).
local function KeyGroups()
	local groups = { { title = L.ADDON_TITLE, commands = KEYS } }
	local all = Commands()
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		if type(extension.addon) == "string" then
			local prefix, list = extension.addon:upper() .. "_", {}
			for _, command in ipairs(all) do
				if command:sub(1, #prefix) == prefix then list[#list + 1] = command end
			end
			if list[1] then groups[#groups + 1] = { title = extension.title or extension.addon, commands = list } end
		end
	end
	return groups
end

local function KeysView()
	local view = { frames = {} }
	local function Said(text)
		view.status:SetText(text or "")
	end
	local function Take(frame, key)
		local command = frame.command
		local action = GetBindingAction and GetBindingAction(key)
		if type(action) == "string" and action ~= "" and action ~= command then
			-- (another action's key: asked first)
			Skin.Ask(L.SETTINGS_KEY_TAKEN:format(ns.Skin.KeyText(key), ns.Skin.BindingName(action), ns.Skin.BindingName(command)), function()
				if not ns.SetKey(command, key) then return Said(L.SETTINGS_KEY_COMBAT) end
				Skin.Play("confirm")
				view:Refresh()
			end)
			return
		end
		if ns.SetKey(command, key) then Skin.Play("confirm") else Said(L.SETTINGS_KEY_COMBAT) end
	end
	local function KeyRow(command)
		local frame = RowFrame(view.canvas, ns.Skin.BindingName(command))
		frame.command = command
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetSize(CONTROL, 26)
		holder.key = Skin.Button(holder, "", function()
			Said(nil)
			local listening = frame.listener:Listening()
			-- (keys are never set in a fight)
			if not listening and InCombatLockdown() then
				Skin.Play("refuse")
				return Said(L.SETTINGS_KEY_COMBAT)
			end
			frame.listener:Set(not listening)
		end, nil, 130)
		holder.key:SetHeight(26)
		holder.key:SetPoint("RIGHT", holder, "RIGHT", -26, 0)
		-- (the kit's listening: Escape, the modifiers, a fight, one row at a time)
		frame.listener = Skin.KeyListener(holder.key, {
			onChange = function() frame:Refresh() end,
			onKey = function(full)
				Take(frame, full)
				view:Refresh()
			end,
		})
		holder.clear = CreateFrame("Button", nil, holder)
		holder.clear:SetSize(20, 20)
		holder.clear:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
		holder.clear.glyph = Skin.Glyph(holder.clear, "close", 9)
		holder.clear.glyph:SetPoint("CENTER")
		holder.clear:SetScript("OnClick", function()
			if not ns.ClearKeys(command) then
				Skin.Play("refuse")
				return Said(L.SETTINGS_KEY_COMBAT)
			end
			Skin.Play("click")
			view:Refresh()
		end)
		Skin.Tooltip(holder.clear, L.SETTINGS_KEY_CLEAR)
		frame.control = holder
		function frame:Refresh()
			local first, second = KeysOf(command)
			local words = first and ns.Skin.KeyText(first) or L.SETTINGS_KEY_NONE
			if second then words = words .. ", " .. ns.Skin.KeyText(second) end
			local listening = self.listener and self.listener:Listening()
			holder.key:SetText(listening and L.WELCOME_REVEAL_PRESS or words)
			holder.key:Fit()
			holder.key.caption:SetTextColor(unpack(listening and Skin.COLORS.gold or (first and Skin.COLORS.text or Skin.COLORS.muted)))
			holder.clear:SetShown(first ~= nil and not listening)
		end
		return frame
	end
	function view:Build()
		Heading(self, L.KEYBINDS, L.SETTINGS_KEYS_DESC)
		self.status = Skin.Text(self.canvas, "GameTooltipTextSmall", "warn")
		for _, group in ipairs(KeyGroups()) do
			local section = SectionFrame(self.canvas, group.title)
			self.frames[#self.frames + 1] = section
			for _, command in ipairs(group.commands) do self.frames[#self.frames + 1] = KeyRow(command) end
		end
		-- (the page left: what was said goes; the listening stops with its button, or as a fight begins)
		self.canvas:HookScript("OnHide", function() Said(nil) end)
	end
	function view:Layout(width)
		-- (said otherwise under a controller: these keys are a keyboard's)
		self.intro:SetText(U.UsingPad() and L.SETTINGS_KEYS_DESC_PAD or L.SETTINGS_KEYS_DESC)
		local y = LayoutHeading(self, width)
		self.status:ClearAllPoints()
		self.status:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -(y - HEADING_GAP + 6))
		self.status:SetWidth(width)
		for index, frame in ipairs(self.frames) do
			if frame.command then y = PlaceRow(frame, self.canvas, y, width, 0) else y = PlaceSection(frame, self.canvas, y, width, index == 1) end
		end
		return y + 20
	end
	function view:Refresh()
		for _, frame in ipairs(self.frames) do
			if frame.Refresh then frame:Refresh() end
		end
	end
	return view
end

-- What you changed (Changes.lua): a line per setting, its value beside the default, a reset each ---------------------

local function ChangesView()
	local view = { fixed = true }
	local ROWS = 14
	function view:Build()
		Heading(self, L.CHANGES_TITLE, L.CHANGES_DESC)
		self.undo = Skin.Button(self.canvas, L.CHANGES_UNDO, function()
			ns.UndoReset()
			self:Refresh()
		end, nil, 80)
		self.undo:SetHeight(24)
		Skin.Tooltip(self.undo, L.CHANGES_UNDO_DESC)
		self.count = Skin.Text(self.canvas, "GameTooltipTextSmall", "muted")
	end
	function view:Draw()
		local list = self.list
		if not list then return end
		local all = ns.ChangedSettings()
		local offset = list:Clamp(#all)
		for index, row in ipairs(list.rows) do
			local changed = all[offset + index]
			if changed then
				local words = changed.words
				row:Fill({ name = words.label or changed.path, icon = false, tip = { words.label or changed.path, words.page or "", changed.path } },
					false, { value = ns.SettingText(words, changed.value), default = ns.SettingText(words, changed.default) },
					words.page, "grey", L.CHANGES_RESET, function()
						ns.ResetSettings(changed.paths)
						self:Refresh()
					end)
			else
				row:Fill(nil)
			end
		end
		list.empty:SetShown(#all == 0)
		self.count:SetText(#all > 0 and U.Plural(#all, L.CHANGES_COUNT_ONE, L.CHANGES_COUNT) or "")
		self.undo:SetShown(ns.CanUndoReset())
	end
	function view:Layout(width)
		local y = LayoutHeading(self, width)
		if not self.list then
			self.list = Skin.Table(self.canvas, {
				width = width, rows = ROWS, icon = false, action = 70, nameTitle = L.CHANGES_COL_OPTION,
				columns = {
					{ key = "value", title = L.CHANGES_COL_YOURS, width = 120 },
					{ key = "default", title = L.CHANGES_COL_DEFAULT, width = 120 },
				},
				onClick = function() end,
				onDraw = function() self:Draw() end,
			})
			self.list.empty:SetText(L.CHANGES_NONE)
		end
		self.list:ClearAllPoints()
		self.list:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
		self.list:Fit(contentBox:GetHeight() - y - 30)
		self.undo:ClearAllPoints()
		self.undo:SetPoint("TOPRIGHT", self.canvas, "TOPRIGHT", -Skin.SCROLL_WIDTH, -2)
		self.count:ClearAllPoints()
		self.count:SetPoint("TOPLEFT", self.list, "BOTTOMLEFT", 6, -8)
		return contentBox:GetHeight()
	end
	function view:Refresh() self:Draw() end
	return view
end

-- Pieces on the screen (Place.lua) ------------------------------------------------------------------------------

local function PlaceView()
	local view = {}
	function view:Build()
		Heading(self, L.PLACING_TITLE, L.PLACING_DESC)
		self.button = Skin.Button(self.canvas, L.PLACING_BUTTON, function()
			ns.CloseSettings()
			ns.PlaceMode()
		end, "main", 160)
	end
	function view:Layout(width)
		-- (said otherwise under a controller: placing the pieces needs a mouse)
		self.intro:SetText(U.UsingPad() and L.PLACING_DESC_PAD or L.PLACING_DESC)
		local y = LayoutHeading(self, width)
		self.button:ClearAllPoints()
		self.button:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
		self.button:SetShown(not U.UsingPad())
		return y + self.button:GetHeight() + 20
	end
	function view:Refresh() end
	return view
end

-- An extension not installed (Extensions.lua): one card, its icon, what it does, where to get it ------------------

local function OfferView(offer)
	local view = {}
	function view:Build()
		Heading(self, (offer.name:gsub("^Wanderer%s+", "")))
		self.chip:Set(L.EXT_NOT_INSTALLED, "grey")
		self.card = Skin.Panel(self.canvas)
		self.icon = self.card:CreateTexture(nil, "ARTWORK")
		self.icon:SetSize(40, 40)
		self.icon:SetTexture(offer.icon)
		self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		self.name = Skin.CreateText(self.card, "GameTooltipHeaderText", ns.Skin.RGB("gold"))
		self.name:SetText(offer.name)
		self.text = Skin.Text(self.card, "GameTooltipText", "text")
		self.text:SetText(L[offer.text])
		self.how = Skin.Text(self.card, "GameTooltipTextSmall", "muted")
		self.how:SetText(L.EXT_OFFER_HOW)
		self.get = Skin.Button(self.card, L.EXT_GET_BUTTON, function() ns.OfferExtension(offer) end, "main", 160)
		-- (none of them wanted: no more pages, line in the card nor welcome step for them)
		self.stop = Skin.SmallButton(self.canvas, L.EXT_STOP_OFFERS, function()
			ns.StopOffers()
			BuildNav()
			ShowView("home")
		end, L.EXT_STOP_OFFERS_DESC, 24)
	end
	function view:Layout(width)
		local y = LayoutHeading(self, width)
		local inner = width - 16 - 40 - 14 - 16
		self.card:ClearAllPoints()
		self.card:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
		self.icon:ClearAllPoints()
		self.icon:SetPoint("TOPLEFT", self.card, "TOPLEFT", 16, -16)
		self.name:ClearAllPoints()
		self.name:SetPoint("TOPLEFT", self.icon, "TOPRIGHT", 14, 0)
		for _, text in ipairs({ self.text, self.how }) do text:SetWidth(inner) end
		self.text:ClearAllPoints()
		self.text:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -8)
		self.how:ClearAllPoints()
		self.how:SetPoint("TOPLEFT", self.text, "BOTTOMLEFT", 0, -8)
		self.get:ClearAllPoints()
		self.get:SetPoint("TOPLEFT", self.how, "BOTTOMLEFT", 0, -16)
		local height = 16 + Height(self.name, 16) + 8 + Height(self.text) + 8 + Height(self.how, 12) + 16
			+ self.get:GetHeight() + 16
		self.card:SetSize(width - 6, math.max(height, 72))
		self.stop:ClearAllPoints()
		self.stop:SetPoint("TOPLEFT", self.card, "BOTTOMLEFT", 0, -12)
		return y + math.max(height, 72) + 12 + self.stop:GetHeight() + 20
	end
	function view:Refresh()
		-- (seen here: no more "new" for it in Wanderer's card)
		if ns.root then
			ns.root.offersSeen = ns.root.offersSeen or {}
			ns.root.offersSeen[offer.addon] = true
		end
	end
	return view
end

-- News (News.lua): every addon's news of its version ------------------------------------------------------------

local function NewsView()
	local view = { blocks = {} }
	function view:Build()
		Heading(self, L.NEWS_SHOW)
		for _, section in ipairs(ns.NewsSections(false)) do
			local block = { lines = {} }
			block.name = Skin.CreateText(self.canvas, "GameTooltipHeaderText", ns.Skin.RGB("gold"))
			block.name:SetText(section.name)
			block.chip = Skin.Chip(self.canvas)
			block.chip:Set(L.NEWS_VERSION:format(section.version), section.new and "gold" or "grey")
			block.rule = Skin.Rule(self.canvas, false, 0.14)
			for _, line in ipairs(section.lines) do
				local mark = self.canvas:CreateTexture(nil, "ARTWORK")
				mark:SetSize(5, 5)
				mark:SetColorTexture(ns.Skin.RGB("gold", 0.8))
				local text = Skin.Text(self.canvas, "GameTooltipText", "text")
				text:SetText(line)
				block.lines[#block.lines + 1] = { mark = mark, text = text }
			end
			self.blocks[#self.blocks + 1] = block
		end
	end
	function view:Layout(width)
		local y = LayoutHeading(self, width)
		for index, block in ipairs(self.blocks) do
			if index > 1 then y = y + 18 end
			block.name:ClearAllPoints()
			block.name:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
			block.chip:ClearAllPoints()
			block.chip:SetPoint("LEFT", block.name, "LEFT", U.Measure(block.name, "GetStringWidth", 100) + 10, 0)
			y = y + Height(block.name, 16) + 6
			block.rule:ClearAllPoints()
			block.rule:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
			block.rule:SetPoint("RIGHT", self.canvas, "RIGHT", -6, 0)
			y = y + 10
			for _, line in ipairs(block.lines) do
				line.text:SetWidth(width - 30)
				line.text:ClearAllPoints()
				line.text:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 16, -y)
				line.mark:ClearAllPoints()
				line.mark:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 3, -(y + 6))
				y = y + Height(line.text) + 9
			end
		end
		return y + 20
	end
	function view:Refresh() end
	return view
end

-- Search ----------------------------------------------------------------------------------------------------------
-- Every row's name and description, its page and section, and who does its job; the pages by their names. Found
-- by their names first. A result opens its page there, the row lit a moment.

local SYSTEM = { { "keys", "KEYBINDS" }, { "changes", "CHANGES_TITLE" }, { "place", "PLACING_TITLE" }, { "news", "NEWS_SHOW" } }
-- (placing is the mouse's: its page not offered under the controller)
local function Offered(key) return key ~= "place" or not U.UsingPad() end

function ns.SearchSettings(query)
	local folded = U.Fold(query or "")
	local named, described = {}, {}
	local function Add(list, result)
		if #named + #described < MAX_RESULTS then list[#list + 1] = result end
	end
	for _, page in ipairs(ns.SETTINGS_PAGES) do
		-- (an extension not installed: no settings to find there)
		if not page.offer and U.Matches(page.name, folded, true) then Add(named, { key = page.key, label = page.name }) end
		for _, row in ipairs(page.rows) do
			-- (a shortcut of the home page: the setting is found on its own page)
			-- (nor a row not offered now)
			if row.kind ~= "header" and row.kind ~= "block" and not row.shortcut and not (row.hidden and row.hidden()) then
				local where = page.name
				if row.section and row.section ~= page.name then where = where .. " · " .. row.section end
				local result = { key = page.key, row = row, label = row.label, where = where }
				if U.Matches(row.label, folded, true) then
					Add(named, result)
				elseif U.Matches(table.concat({ (U.UsingPad() and row.descPad or row.desc) or "", row.section or "", page.name, ns.SettingsRowNote(row) or "" }, " "),
					folded, true) then
					Add(described, result)
				end
			end
		end
	end
	for _, system in ipairs(SYSTEM) do
		if Offered(system[1]) and U.Matches(L[system[2]], folded, true) then Add(named, { key = system[1], label = L[system[2]] }) end
	end
	-- (a key by its action's name: the Keys page)
	for _, group in ipairs(KeyGroups()) do
		for _, command in ipairs(group.commands) do
			if U.Matches(ns.Skin.BindingName(command), folded, true) then
				Add(named, { key = "keys", label = ns.Skin.BindingName(command), where = L.KEYBINDS })
			end
		end
	end
	for _, result in ipairs(described) do named[#named + 1] = result end
	return named
end

local function ResultsView()
	local view = { buttons = {}, results = {} }
	function view:Build()
		Heading(self, "")
	end
	local function Go(result)
		search:SetText("")
		search:ClearFocus()
		ShowView(result.key, result.row)
	end
	view.Go = Go
	local function Button(index)
		local button = view.buttons[index]
		if button then return button end
		button = CreateFrame("Button", nil, view.canvas)
		button:SetHeight(42)
		button.hover = button:CreateTexture(nil, "BACKGROUND")
		button.hover:SetAllPoints()
		button.hover:SetColorTexture(1, 1, 1, ns.Skin.HOVER)
		button.hover:Hide()
		button.label = Skin.Text(button, "GameTooltipText", "text")
		button.label:SetPoint("TOPLEFT", button, "TOPLEFT", 10, -6)
		button.label:SetPoint("RIGHT", button, "RIGHT", -24, 0)
		if button.label.SetWordWrap then button.label:SetWordWrap(false) end
		button.where = Skin.Text(button, "GameTooltipTextSmall", "muted")
		button.where:SetPoint("TOPLEFT", button.label, "BOTTOMLEFT", 0, -3)
		button.where:SetPoint("RIGHT", button, "RIGHT", -24, 0)
		if button.where.SetWordWrap then button.where:SetWordWrap(false) end
		button.more = Skin.Glyph(button, "chevron", 10)
		button.more:SetPoint("RIGHT", button, "RIGHT", -8, 0)
		button:SetScript("OnEnter", function(self) self.hover:Show() end)
		button:SetScript("OnLeave", function(self) self.hover:Hide() end)
		button:SetScript("OnClick", function(self)
			Skin.Play("click")
			Go(self.result)
		end)
		view.buttons[index] = button
		return button
	end
	function view:Fill(query)
		self.results = ns.SearchSettings(query)
		local count = #self.results
		self.title:SetText(count > 0 and U.Plural(count, L.SETTINGS_RESULT_ONE, L.SETTINGS_RESULTS)
			or L.SETTINGS_NO_RESULTS:format(query))
		for index, result in ipairs(self.results) do
			local button = Button(index)
			button.result = result
			button.label:SetText(result.label or "")
			button.where:SetText(result.where or L.SETTINGS_PAGE)
			button:Show()
		end
		for index = count + 1, #self.buttons do self.buttons[index]:Hide() end
	end
	function view:Layout(width)
		local y = LayoutHeading(self, width)
		for index = 1, #self.results do
			local button = self.buttons[index]
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -y)
			button:SetWidth(width)
			y = y + 44
		end
		return y + 20
	end
	function view:Refresh() end
	return view
end

-- The window -------------------------------------------------------------------------------------------------------

local function MakeView(key)
	local view
	if key == "themes" then view = ThemesView()
	elseif key == "playstyles" then view = PlaystylesView()
	elseif key == "keys" then view = KeysView()
	elseif key == "changes" then view = ChangesView()
	elseif key == "place" then view = PlaceView()
	elseif key == "news" then view = NewsView()
	elseif key == "results" then view = ResultsView()
	elseif pageByKey[key] and pageByKey[key].offer then view = OfferView(pageByKey[key].offer)
	elseif pageByKey[key] then view = PageView(pageByKey[key])
	end
	if not view then return nil end
	-- ("What you changed" keeps its old name: /fstack, the tests)
	view.canvas = CreateFrame("Frame", key == "changes" and "WandererChanges" or nil, contentBox)
	view.canvas:SetSize(1, 1)
	view.canvas:Hide()
	view:Build()
	views[key] = view
	return view
end

-- The pages of the sidebar, in order: { key, name } and the groups' captions ({ caption }).
-- The extensions in their fixed order (ns.EXTENSION_OFFERS), installed or offered; one unknown there after them.
local function FamilyRank(page)
	local addon = page.offer and page.offer.addon or page.addon
	for index, offer in ipairs(ns.EXTENSION_OFFERS or {}) do
		if offer.addon == addon then return index end
	end
	return 100
end

local function NavEntries()
	local list = {}
	local groups = { wanderer = {}, extensions = {}, more = {} }
	for index, page in ipairs(ns.SETTINGS_PAGES) do
		pageByKey[page.key] = page
		local group = groups[page.group] or groups.wanderer
		-- (the extensions not installed: not after "stop suggesting them")
		if not page.offer or ns.OffersWanted() then
			group[#group + 1] = { key = page.key, name = ns.SettingsPageTitle(page), page = page, muted = page.offer ~= nil,
				rank = page.group == "extensions" and FamilyRank(page) * 1000 + index or index }
		end
	end
	table.sort(groups.extensions, function(a, b) return a.rank < b.rank end)
	for _, system in ipairs(SYSTEM) do
		if Offered(system[1]) then groups.more[#groups.more + 1] = { key = system[1], name = L[system[2]] } end
	end
	for _, part in ipairs({ { "wanderer", L.ADDON_TITLE }, { "extensions", L.SECTION_EXTENSIONS }, { "more", L.SETTINGS_GROUP_MORE } }) do
		if groups[part[1]][1] then
			list[#list + 1] = { caption = part[2] }
			for _, entry in ipairs(groups[part[1]]) do list[#list + 1] = entry end
		end
	end
	return list
end

local function SelectNav(key)
	for _, button in ipairs(navButtons) do
		local on = button.key == key
		button.chosen:SetShown(on)
		button.bar:SetShown(on)
		-- (an extension not installed: muted)
		local c = on and Skin.COLORS.gold or (button.muted and Skin.COLORS.muted or Skin.COLORS.soft)
		button.text:SetTextColor(c[1], c[2], c[3])
	end
end

-- Each page's count of changed settings, quiet at the right of its name in the sidebar.
local function NavCounts()
	IndexChanges()
	for _, button in ipairs(navButtons) do
		local page = button:IsShown() and pageByKey[button.key]
		local count = page and ns.SettingsPageChanges(page) or 0
		button.count:SetText(count > 0 and tostring(count) or "")
	end
end

local function NavButton(index)
	local button = navButtons[index]
	if button then return button end
	button = CreateFrame("Button", nil, navCanvas)
	button:SetHeight(NAV_ROW)
	button.chosen = button:CreateTexture(nil, "BACKGROUND")
	button.chosen:SetAllPoints()
	button.chosen:SetColorTexture(ns.Skin.RGB("gold", ns.Skin.CHOSEN))
	button.bar = button:CreateTexture(nil, "ARTWORK")
	button.bar:SetColorTexture(ns.Skin.RGB("gold", 1))
	button.bar:SetWidth(2)
	button.bar:SetPoint("TOPLEFT")
	button.bar:SetPoint("BOTTOMLEFT")
	button.hover = button:CreateTexture(nil, "BACKGROUND", nil, 1)
	button.hover:SetAllPoints()
	button.hover:SetColorTexture(1, 1, 1, ns.Skin.HOVER)
	button.hover:Hide()
	button.text = Skin.Text(button, "GameTooltipText", "soft")
	button.text:SetPoint("LEFT", button, "LEFT", 12, 0)
	button.text:SetPoint("RIGHT", button, "RIGHT", -28, 0)
	button.count = Skin.Text(button, "GameTooltipTextSmall", "muted")
	button.count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
	button.count:SetJustifyH("RIGHT")
	if button.text.SetWordWrap then button.text:SetWordWrap(false) end
	button:SetScript("OnEnter", function(self) self.hover:Show() end)
	button:SetScript("OnLeave", function(self) self.hover:Hide() end)
	button:SetScript("OnClick", function(self)
		Skin.Play("click")
		if search:GetText() ~= "" then search:SetText("") end
		search:ClearFocus()
		ShowView(self.key)
	end)
	navButtons[index] = button
	return button
end

-- The sidebar, made again when the pages changed (an extension's page added).
local navCount
function BuildNav()
	local entries = NavEntries()
	if navCount == #entries then return end
	navCount = #entries
	local y, used = 0, 0
	for _, caption in ipairs(navCaptions) do caption:Hide() end
	local captions = 0
	for _, entry in ipairs(entries) do
		if entry.caption then
			captions = captions + 1
			local caption = navCaptions[captions]
			if not caption then
				caption = Skin.Caps(navCanvas, "", "muted")
				navCaptions[captions] = caption
			end
			caption:SetText(U.Upper(entry.caption))
			caption:ClearAllPoints()
			caption:SetPoint("TOPLEFT", navCanvas, "TOPLEFT", 12, -(y + (captions > 1 and 14 or 2)))
			caption:Show()
			y = y + (captions > 1 and 14 or 2) + 18
		else
			used = used + 1
			local button = NavButton(used)
			button.key, button.muted = entry.key, entry.muted
			button.text:SetText(entry.name)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", navCanvas, "TOPLEFT", 0, -y)
			button:SetPoint("RIGHT", navCanvas, "RIGHT", 0, 0)
			button:Show()
			y = y + NAV_ROW + 1
		end
	end
	for index = used + 1, #navButtons do navButtons[index]:Hide() end
	navBox:Hold(navCanvas)
	navBox:SetTotal(y + 8)
end

-- The view drawn again in place (its rows' heights may change: a value, the size of the words).
function Relayout()
	local view = views[current]
	if not view then return end
	local offset = contentBox.offset
	contentBox:SetTotal(view:Layout(contentBox:GetWidth()))
	contentBox:ScrollTo(view.fixed and 0 or offset)
end

-- A page shown (its key; row: one of its rows, scrolled to and lit).
function ShowView(key, row)
	local view = views[key] or MakeView(key)
	if not view then
		key = "home"
		view = views.home or MakeView("home")
	end
	if key ~= "results" then lastPage = key end
	current = key
	-- (a row under the fold, found by a search: the fold opened for it)
	if row and row.advanced and view.page and not ns.SettingsPageUnfolded(view.page) then unfoldedNow[view.page.key] = true end
	contentBox:Hold(view.canvas)
	contentBox:SetTotal(view:Layout(contentBox:GetWidth()))
	view:Refresh()
	if key ~= "results" then SelectNav(key) end
	NavCounts()
	if row and view.FrameOf then
		local frame = view:FrameOf(row)
		if frame and frame.top then
			contentBox:ScrollTo(frame.top - 30)
			Flash(frame)
		end
	end
end

local function OnSearch(input)
	local query = (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if query == "" then
		if current == "results" then ShowView(lastPage) end
		return
	end
	local view = views.results or MakeView("results")
	view:Fill(query)
	ShowView("results")
end

-- Its size: as set, smaller on a small screen (at the size of its words).
local function Arrange()
	local scale = Skin.Scale()
	local width, height = WIDTH, HEIGHT
	local screenWidth, screenHeight = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	if screenWidth > 0 then width = math.floor(math.min(WIDTH, screenWidth / scale - 40)) end
	if screenHeight > 0 then height = math.floor(math.min(HEIGHT, screenHeight / scale - 60)) end
	window:SetSize(width, height)
	local margin = Skin.Margin() + 8
	local top = margin + 46
	search:ClearAllPoints()
	search:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -top)
	search:SetWidth(SIDEBAR)
	navBox:ClearAllPoints()
	navBox:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(top + 26 + 12))
	navBox:SetSize(SIDEBAR - Skin.SCROLL_WIDTH - 4, height - top - 38 - margin)
	window.rule:ClearAllPoints()
	window.rule:SetPoint("TOPLEFT", window, "TOPLEFT", margin + SIDEBAR + 14, -top)
	window.rule:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin + SIDEBAR + 14, margin)
	local left = margin + SIDEBAR + 30
	contentBox:ClearAllPoints()
	contentBox:SetPoint("TOPLEFT", window, "TOPLEFT", left, -top)
	contentBox:SetSize(width - left - margin - Skin.SCROLL_WIDTH - 6, height - top - margin)
	Skin.Get(window):Layout()
end

local target -- the page asked for

local function Create()
	Skin = ns.Skin
	window = Skin.CreateWindow("WandererSettings", "MEDIUM")
	-- (a page of words read at length: nearly solid, whatever the opacity chosen for the label)
	local look = Skin.Get(window)
	if look then look.minOpacity = SOLID end
	Skin.Sounds(window, Skin.SOUNDS.open, Skin.SOUNDS.close)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 20 }, "settingsPos")
	local _, _, margin = Skin.Header(window, L.ADDON_TITLE, L.SETTINGS_TITLE)
	Skin.Help(window, L.SETTINGS_HELP, "HEADING")
	window.version = Skin.Text(window, "GameTooltipTextSmall", "muted")
	window.version:SetPoint("TOPRIGHT", window, "TOPRIGHT", -margin - 44, -margin) -- (left of the help's "?")
	local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	window.version:SetText(get and U.Safe(get, "Wanderer", "Version") or "")
	window.rule = Skin.Rule(window, true, 0.12)
	search = Skin.CreateInput(window, nil, 40, {
		hint = L.SETTINGS_SEARCH,
		onChange = function(input) OnSearch(input) end,
		onEnter = function(input)
			local results = views.results
			if current == "results" and results and results.results[1] then
				results.Go(results.results[1])
			else
				input:ClearFocus()
			end
		end,
		onEscape = function(input)
			if (input:GetText() or "") ~= "" then input:SetText("") else input:ClearFocus() end
		end,
	})
	search:SetHeight(26)
	navBox = Scroller(window)
	navCanvas = CreateFrame("Frame", nil, navBox)
	navCanvas:SetSize(1, 1)
	contentBox = Scroller(window)
	window:HookScript("OnShow", function(self)
		-- (never taller than the screen: a laptop, a large scale)
		self:SetScale(Skin.FitScale(self))
		Arrange()
		BuildNav()
		ShowView(target or lastPage)
		target = nil
		if ns.WatchPreview then ns.WatchPreview(true) end
	end)
	window:HookScript("OnHide", function()
		if ns.WatchPreview then ns.WatchPreview(false) end
		if (search:GetText() or "") ~= "" then search:SetText("") end
		search:ClearFocus()
	end)
end

-- Opens the settings (on a page: its key, else the last one shown).
function ns.OpenOptions(key)
	if not (ns.db and ns.SETTINGS_PAGES[1]) then return end
	if not window then Create() end
	if window:IsShown() then
		ShowView(key or lastPage)
		-- (asked from another window, a cog: in front of it)
		if Skin.Front then Skin.Front(window) end
	else
		target = key
		window:Show()
	end
end

function ns.CloseSettingsWindow()
	if window and window:IsShown() then window:Hide() end
end

function ns.ToggleChanges()
	if window and window:IsShown() and current == "changes" then return window:Hide() end
	ns.OpenOptions("changes")
end

-- The values read again (a profile chosen, a change made elsewhere), the page laid out again.
function ns.RefreshSettingsWindow()
	if not (window and window:IsShown() and views[current]) then return end
	views[current]:Refresh()
	Relayout()
	NavCounts()
end

-- The sidebar made again (the extensions not installed suggested again, or no more).
function ns.RefreshSettingsNav()
	if window then BuildNav() end
end

-- The window beside which the label's preview stands (Preview.lua): shown on the label's pages.
function ns.SettingsPreviewHost()
	local page = window and window:IsShown() and current and pageByKey[current]
	return page and page.preview and window or nil
end

-- Which preview stands beside it: "label" (the label's pages) or "unitframes".
function ns.SettingsPreviewKind()
	local page = window and window:IsShown() and current and pageByKey[current]
	return page and (page.preview == "unitframes" and "unitframes" or "label") or nil
end

-- (tests) the view shown and its frame of a row.
function ns.SettingsView() return current, views[current] end
