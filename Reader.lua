local _, ns = ...
local L = ns.L

-- Books, plaques and letters in a reading window of Wanderer's, in place of
-- the game's page by page one: the whole text in one scroll, its pages marked
-- by a thin line, the page you stopped at kept for each book and character,
-- the place where a plaque or a grave is read, who wrote a letter. On the
-- dark look of every window, or on parchment with the scenes (an option).
-- The game turns the pages itself, one after the other, while the first one
-- is already shown. Holding Shift opens the game's own window; another addon
-- showing books (DialogueUI) keeps them, and this window never opens.
--
-- Another part of the family may add a line under the title (a library book
-- to hand in): ns.ReaderNote(fn), Wanderer.ReaderNote(fn) for an extension,
-- fn(info) returning words or nil; info = { title, item, creator, material,
-- object, zone, subzone }.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local EVENTS = { "ITEM_TEXT_BEGIN", "ITEM_TEXT_READY", "ITEM_TEXT_CLOSED", "ITEM_TEXT_TRANSLATION" }
local WIDTH = 500
local MAX_VIEW, MIN_VIEW = 440, 60 -- height of the text shown at once
local SEPARATOR = 30 -- room between two pages
local MAX_PAGES = 60 -- a book never read further (a page that never ends)
local WHEEL_STEP = 48 -- pixels a turn of the wheel scrolls
local USED_WITHIN = 3 -- seconds: an item used this long before the text opened is the one read

local window, kicker, title, noteText, rule, scroll, content, bar
local pageTexts, separators = {}, {}
local reading -- { title, raw = { page texts }, last, item, creator, material, object, zone, subzone, note, relay }
local taker -- the game's reading window kept from its events while the reader is on (Util.EventTaker)
local closingByGame = false
local offset = 0
local lastUsed -- { id, at }: the last item used from the bags
local notes = {} -- fn(info) -> words: lines under the title

-- Another part of the family adds a line under the title (Wanderer.ReaderNote for an extension).
function ns.ReaderNote(fn)
	if type(fn) == "function" then notes[#notes + 1] = fn end
end

-- A letter (it has a writer), or anything read with the mailbox open.
function ns.ReadingMail()
	if Clean(Safe(ItemTextGetCreator)) then return true end
	for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
		local frame = _G[name]
		if frame and frame.IsShown and frame:IsShown() then return true end
	end
	return false
end

-- Which item was used to open the text (the game does not say): the one used from the bags just before.
if hooksecurefunc and C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
		local id = Clean(Safe(C_Container.GetContainerItemID, bag, slot))
		lastUsed = id and { id = id, at = GetTime() } or nil
	end)
end

local function Paper() return ns.ScenePaper() end

local function On()
	local db = ns.db
	-- (asked for with the scenes: nil is on, until said otherwise)
	return db and db.enabled and db.scene and db.scene.reader ~= false and not ns.StepsAside("books") and true or false
end

-- The game's window --------------------------------------------------------------------------------------------

local function IsGameWindow(frame)
	if frame.IsForbidden and frame:IsForbidden() then return false end
	local depth = 0
	while frame and depth < 6 do
		if frame == _G.ItemTextFrame then return true end
		local ok, parent = pcall(frame.GetParent, frame)
		frame = ok and parent or nil
		depth = depth + 1
	end
	return false
end

taker = U.EventTaker(EVENTS, function() return _G.ItemTextFrame end, IsGameWindow)

local function SetTaken(take) taker:Take(take) end

-- Shift held: the game's own window reads it, as without Wanderer.
local function Relay(event, ...) taker:Relay(event, ...) end

-- Text ---------------------------------------------------------------------------------------------------------

local ENTITIES = { lt = "<", gt = ">", amp = "&", quot = "\"", nbsp = " " }

-- A page as words: a book written in the game's HTML keeps its paragraphs and its headings (in the title's color).
local function Plain(text, paper)
	if type(text) ~= "string" or U.IsSecret(text) then return text or "" end
	if not text:find("^%s*<[Hh][Tt][Mm][Ll]") then return text end
	local r, g, b = ns.Skin.InkColor("gold", paper)
	local heading = U.ColorCode(r, g, b)
	text = text:gsub("\r", "")
	text = text:gsub("<[Bb][Rr]%s*/?>", "\n")
	text = text:gsub("<[Hh]%d[^>]*>(.-)</[Hh]%d>", function(inner) return "\n" .. heading .. inner .. "|r\n" end)
	text = text:gsub("</?[Pp][^>]*>", "\n")
	text = text:gsub("<[^>]+>", "")
	text = text:gsub("&(%a+);", function(name) return ENTITIES[name:lower()] end)
	text = text:gsub("\n[ \t]+", "\n"):gsub("\n\n\n+", "\n\n")
	return strtrim(text)
end

-- Where it is read: "Goldshire, Elwynn Forest".
local function PlaceName()
	local zone, subzone = reading.zone, reading.subzone
	if subzone and zone and subzone ~= zone then return subzone .. ", " .. zone end
	return zone or subzone
end

local function KickerText()
	if reading.creator then return L.READER_FROM:format(reading.creator) end
	if reading.object then return PlaceName() or L.READER_KICKER end
	return L.READER_KICKER
end

-- The lines the rest of the family adds under the title.
local function Notes()
	local info = { title = reading.title, item = reading.item, creator = reading.creator, material = reading.material,
		object = reading.object, zone = reading.zone, subzone = reading.subzone }
	local lines = {}
	for _, fn in ipairs(notes) do
		local ok, words = pcall(fn, info)
		if ok and type(words) == "string" and words ~= "" then lines[#lines + 1] = words end
	end
	return table.concat(lines, "\n")
end

-- The page you stopped at -------------------------------------------------------------------------------------

local function Key()
	if not reading then return end
	if reading.item then return "item:" .. reading.item end
	return reading.title and ("text:" .. reading.title) or nil
end

local function Kept()
	if not ns.root then return {} end
	local mine = ns.Mine()
	mine.readerPages = type(mine.readerPages) == "table" and mine.readerPages or {}
	return mine.readerPages
end

-- The page at the top of what is shown.
local function PageShown()
	local page = 1
	for index, top in ipairs(reading and reading.tops or {}) do
		if top <= offset + 8 then page = index end
	end
	return page
end

local function Remember()
	local key = Key()
	if not key then return end
	local page = PageShown()
	Kept()[key] = page > 1 and page or nil
end

-- Layout ------------------------------------------------------------------------------------------------------

local function ViewHeight()
	return math.max(MIN_VIEW, math.min(MAX_VIEW, reading and reading.height or MIN_VIEW))
end

local function SetOffset(value)
	if not reading then return end
	local most = math.max(0, (reading.height or 0) - ViewHeight())
	offset = math.max(0, math.min(most, math.floor((value or 0) + 0.5)))
	scroll:SetVerticalScroll(offset)
	bar:Set(reading.height or 0, ViewHeight(), offset)
end

local function Separator(index)
	local separator = separators[index]
	if separator then return separator end
	separator = CreateFrame("Frame", nil, content)
	separator:SetHeight(SEPARATOR)
	separator.number = ns.Skin.CreateText(separator, "GameTooltipTextSmall")
	separator.number:SetPoint("CENTER")
	separator.left = separator:CreateTexture(nil, "ARTWORK")
	separator.left:SetHeight(1)
	separator.left:SetWidth(70)
	separator.left:SetPoint("RIGHT", separator.number, "LEFT", -8, 0)
	separator.right = separator:CreateTexture(nil, "ARTWORK")
	separator.right:SetHeight(1)
	separator.right:SetWidth(70)
	separator.right:SetPoint("LEFT", separator.number, "RIGHT", 8, 0)
	separators[index] = separator
	return separator
end

local function PageText(index)
	local text = pageTexts[index]
	if text then return text end
	text = ns.Skin.CreateText(content, "GameTooltipText")
	text:SetJustifyH("LEFT")
	if text.SetSpacing then text:SetSpacing(3) end
	if text.SetWordWrap then text:SetWordWrap(true) end
	pageTexts[index] = text
	return text
end

local function Layout()
	if not (window and reading) then return end
	local Skin = ns.Skin
	local paper = Paper()
	Skin.Parchment(window, paper)
	window:SetScale(Skin.Scale())
	local margin = Skin.Margin() + 8
	local inner = WIDTH - margin * 2 - Skin.SCROLL_WIDTH
	local size = (ns.db.scene.textSize or 15)
	local path = Skin.FontPath(ns.db.label.font)

	-- The heading: where, or who wrote it; the title; the lines of the family.
	Skin.Ink(kicker, "kicker", paper)
	kicker:SetText(U.Upper(KickerText() or ""))
	Skin.Ink(title, "gold", paper)
	title:SetWidth(WIDTH - margin * 2 - 24)
	title:SetText(reading.title or "")
	Skin.Ink(noteText, "good", paper)
	noteText:SetWidth(WIDTH - margin * 2)
	noteText:SetText(reading.note or "")
	noteText:SetShown((reading.note or "") ~= "")
	local r, g, b = Skin.InkColor("gold", paper)
	rule:SetColorTexture(r, g, b, paper and 0.35 or 0.16)
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", noteText:IsShown() and noteText or title, "BOTTOMLEFT", 0, -8)
	rule:SetPoint("RIGHT", window, "RIGHT", -margin, 0)

	-- The pages, one under the other, a thin line and their number between them.
	local y = 0
	reading.tops = {}
	local muted = { Skin.InkColor("muted", paper) }
	for index = 1, reading.last or 0 do
		if index > 1 then
			local separator = Separator(index)
			separator:ClearAllPoints()
			separator:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			separator:SetWidth(inner)
			Skin.Ink(separator.number, "muted", paper)
			separator.number:SetText(tostring(index))
			Skin.FadingRule(separator.left, 0.5, true, muted)
			Skin.FadingRule(separator.right, 0.5, false, muted)
			separator:Show()
			reading.tops[index] = y
			y = y + SEPARATOR
		else
			reading.tops[index] = 0
		end
		local text = PageText(index)
		if path then text:SetFont(path, size, "") end
		Skin.Ink(text, "text", paper)
		text:SetWidth(inner)
		if not pcall(text.SetText, text, Plain(reading.raw[index], paper)) then text:SetText("") end
		text:ClearAllPoints()
		text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		text:Show()
		y = y + U.Measure(text, "GetStringHeight", size)
	end
	for index, text in ipairs(pageTexts) do
		if index > (reading.last or 0) then text:Hide() end
	end
	for index, separator in pairs(separators) do
		if index > (reading.last or 0) then separator:Hide() end
	end
	reading.height = math.max(1, math.floor(y + 0.5))
	content:SetSize(inner, reading.height)
	local view = ViewHeight()
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -10)
	scroll:SetSize(inner, view)

	local header = U.Measure(kicker, "GetStringHeight", 10) + 3 + U.Measure(title, "GetStringHeight", 14)
		+ (noteText:IsShown() and (4 + U.Measure(noteText, "GetStringHeight", 12)) or 0) + 8 + 1 + 10
	window:SetSize(WIDTH, margin * 2 + header + view)
	Skin.Get(window):Layout()

	-- Back at the page you stopped at, once it has come.
	local kept = not reading.placed and Key() and Kept()[Key()]
	if kept and reading.tops[kept] then
		SetOffset(reading.tops[kept])
		-- (placed once that page can be reached: the pages after it may still be coming)
		if offset >= reading.tops[kept] or reading.done then reading.placed = true end
	else
		SetOffset(offset)
	end
end

-- Reading -----------------------------------------------------------------------------------------------------

local function Open()
	reading.note = Notes()
	offset = 0
	scroll:SetVerticalScroll(0)
	Layout()
	window:Show()
end

local function Close()
	if not reading then return end
	Remember()
	reading = nil
	if window:IsShown() then
		closingByGame = true
		window:Hide()
		closingByGame = false
	end
end

local function OnEvent(_, event, ...)
	if event == "ADDON_LOADED" then return ns.RefreshReader() end
	if not taker.taken then return end
	if event == "ITEM_TEXT_BEGIN" then
		if window:IsShown() then Close() end
		-- Shift held: the game's own window, for this one (never in a fight: the game refuses to open it for
		-- an addon then, so Wanderer's window reads it; never with a controller: opened from here, it blocks the game).
		if U.IsSkipping() and not InCombatLockdown() and not U.UsingPad() then
			reading = { relay = true }
			return Relay(event, ...)
		end
		local used = lastUsed and GetTime() - lastUsed.at <= USED_WITHIN and lastUsed.id or nil
		lastUsed = nil
		reading = { raw = {}, last = 0, title = Clean(Safe(ItemTextGetItem)), item = used, object = used == nil,
			zone = Clean(Safe(GetRealZoneText)), subzone = Clean(Safe(GetSubZoneText)) }
		return
	end
	if reading and reading.relay then
		Relay(event, ...)
		if event == "ITEM_TEXT_CLOSED" then reading = nil end
		return
	end
	if event == "ITEM_TEXT_CLOSED" then return Close() end
	if event ~= "ITEM_TEXT_READY" or not reading then return end
	local page = Clean(Safe(ItemTextGetPage)) or (reading.last + 1)
	-- (a page already read: the end of the book reached, nothing to turn)
	if page <= reading.last then return end
	reading.raw[page] = Safe(ItemTextGetText) or ""
	reading.last = page
	reading.title = reading.title or Clean(Safe(ItemTextGetItem))
	reading.creator = reading.creator or Clean(Safe(ItemTextGetCreator))
	reading.material = reading.material or Clean(Safe(ItemTextGetMaterial))
	local more = page < MAX_PAGES and Clean(Safe(ItemTextHasNextPage)) and true or false
	reading.done = not more
	local ok, problem = pcall(function() if window:IsShown() then Layout() else Open() end end)
	if not ok then
		-- A page Wanderer could not lay out: the game's own window reads the book (out of a fight).
		Close()
		if ns.debug then ns.Print(tostring(problem)) end
		-- (in a fight, or with a controller, the game's window cannot open from here: the book closed, never left open with nothing shown)
		if InCombatLockdown() or U.UsingPad() then return Safe(CloseItemText) end
		reading = { relay = true }
		Relay("ITEM_TEXT_BEGIN")
		return Relay(event, ...)
	end
	-- The next page asked at once: the whole book in one scroll.
	if more then Safe(ItemTextNextPage) end
end

function ns.RefreshReader()
	if not window then return end
	-- (the game's window loaded after it was taken: taken again, with it)
	if taker.taken and _G.ItemTextFrame and not (taker.frames.ITEM_TEXT_BEGIN or {})[1] then SetTaken(false) end
	SetTaken(On())
	if not taker.taken and reading and not reading.relay then
		Safe(CloseItemText)
		Close()
	end
	if reading and window:IsShown() then Layout() end
end

-- Construction ------------------------------------------------------------------------------------------------

function ns.InitReader()
	if window then return end
	local Skin = ns.Skin
	window = Skin.CreateWindow("WandererReader", "MEDIUM")
	Skin.Sounds(window, Skin.SOUNDS.open, Skin.SOUNDS.close)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "readerPos")
	kicker, title = Skin.Header(window, L.READER_KICKER)
	if title.SetWordWrap then title:SetWordWrap(true) end
	noteText = Skin.Text(window, "GameTooltipTextSmall", "good")
	noteText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	noteText:Hide()
	rule = window:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	scroll = CreateFrame("ScrollFrame", nil, window)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	bar = Skin.ScrollBar(window, SetOffset)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta)
		SetOffset(offset - delta * WHEEL_STEP)
		Remember()
	end)
	-- (a controller's right stick: nothing to choose in here, the window's own wheel)
	Skin.PadWindow(window, { wheel = function(delta)
		SetOffset(offset - delta * WHEEL_STEP)
		Remember()
		return true
	end })
	-- A right click closes it, as the cross and Escape do.
	window:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then self:Hide() end end)
	-- Closed here: the game's reading ends too (walking away closes it from the game's side). Hidden only
	-- with the whole interface (Alt+Z): still read, shown again with it.
	window:HookScript("OnHide", function(self)
		if closingByGame or not reading or self:IsShown() then return end
		Remember()
		reading = nil
		Safe(CloseItemText)
	end)
	local events = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
	-- (the game's reading window may be loaded on demand)
	events:RegisterEvent("ADDON_LOADED")
	events:SetScript("OnEvent", OnEvent)
	ns.RefreshReader()
end

-- (tests)
ns.ReaderState = function() return reading, offset, taker.relaying end
