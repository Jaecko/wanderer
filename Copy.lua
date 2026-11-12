local _, ns = ...
local L = ns.L

-- Copy the chat: the game's chat can't be selected. This window shows the
-- last lines of the chat tab in view (or of the tab whose copy button was
-- clicked) as plain text (no colors, icons or link codes), already selected:
-- Ctrl+C copies them. Opened from the chat's copy button, Wanderer's menu or
-- /wanderer copy; Escape closes it. Lines the game keeps secret are left
-- out.

local U = ns.Util

local WIDTH, HEIGHT = 620, 420
local MAX_LINES = 300
local WHEEL_STEP = 40 -- pixels a turn of the wheel scrolls

local window, box, scroll, bar, hint
local offset = 0

local function ChatLines(frame)
	frame = frame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1
	local lines = {}
	if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return lines end
	local count = frame:GetNumMessages() or 0
	for index = math.max(1, count - MAX_LINES + 1), count do
		local text = U.Safe(frame.GetMessageInfo, frame, index)
		if type(text) == "string" and not U.IsSecret(text) then lines[#lines + 1] = U.PlainText(text) end
	end
	return lines
end

-- The lines scrolled to a height (pixels), the kit's bar following.
local function SetOffset(value)
	local shown, total = scroll:GetHeight() or 0, box:GetHeight() or 0
	offset = math.max(0, math.min(math.max(0, total - shown), math.floor((value or 0) + 0.5)))
	scroll:SetVerticalScroll(offset)
	bar:Set(total, shown, offset)
end

local function CreateWindow()
	local Skin = ns.Skin
	window = Skin.CreateWindow("WandererCopy", "DIALOG")
	Skin.Sounds(window, "IG_CHARACTER_INFO_OPEN", "IG_CHARACTER_INFO_CLOSE")
	window:SetSize(WIDTH, HEIGHT)
	Skin.Dress(window)
	local _, title, margin = Skin.Header(window, L.ADDON_TITLE, L.COPY_TITLE)
	title:SetPoint("RIGHT", window, "RIGHT", -36, 0)
	hint = Skin.Text(window, "GameTooltipTextSmall", "muted")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	hint:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	hint:SetText(L.COPY_HINT)
	-- (the kit's scroll bar, as in every Wanderer list)
	scroll = CreateFrame("ScrollFrame", "WandererCopyScroll", window)
	scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin - Skin.SCROLL_WIDTH - 4, margin)
	bar = Skin.ScrollBar(window, SetOffset)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	box = CreateFrame("EditBox", "WandererCopyBox", scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(Skin.FontFor("ChatFontNormal"))
	box:SetWidth(WIDTH - 2 * margin - Skin.SCROLL_WIDTH - 4)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	-- (the text's height known once laid out: the bar drawn again)
	box:SetScript("OnSizeChanged", function() SetOffset(offset) end)
	scroll:SetScrollChild(box)
	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta) SetOffset(offset - delta * WHEEL_STEP) end)
	-- (a controller's right stick: nothing to choose in here, the window's own wheel)
	Skin.PadWindow(window, { wheel = function(delta)
		SetOffset(offset - delta * WHEEL_STEP)
		return true
	end })
end

function ns.CopyChat(frame)
	if not window then CreateWindow() end
	box:SetText(table.concat(ChatLines(type(frame) == "table" and frame or nil), "\n"))
	window:SetScale(ns.Skin.Scale())
	window:Show()
	ns.Skin.Get(window):Layout()
	SetOffset(0)
	-- (with a controller nothing is typed: no focus taken, the hint says copying needs a keyboard)
	hint:SetText(U.UsingPad() and L.COPY_HINT_PAD or L.COPY_HINT)
	if not U.UsingPad() then box:SetFocus() end
	box:HighlightText()
end
