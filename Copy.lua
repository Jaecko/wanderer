local _, ns = ...
local L = ns.L

-- Copy the chat: the game's chat can't be selected. This window shows the
-- last lines of the chat tab in view as plain text (no colors, icons or link
-- codes), already selected: Ctrl+C copies them. Opened from Wanderer's menu
-- or /wanderer copy; Escape closes it. Lines the game keeps secret are left
-- out.

local U = ns.Util

local WIDTH, HEIGHT = 620, 420
local MAX_LINES = 300

local window, box

-- Plain text: links keep their visible words, colors and icons go.
local function Plain(text)
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return text
end

local function ChatLines()
	local frame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1
	local lines = {}
	if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return lines end
	local count = frame:GetNumMessages() or 0
	for index = math.max(1, count - MAX_LINES + 1), count do
		local text = U.Safe(frame.GetMessageInfo, frame, index)
		if type(text) == "string" and not U.IsSecret(text) then lines[#lines + 1] = Plain(text) end
	end
	return lines
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererCopy", "DIALOG")
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER")
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	local margin = ns.Skin.Margin() + 6
	local title = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	title:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	title:SetPoint("RIGHT", window, "RIGHT", -36, 0)
	title:SetText(L.COPY_TITLE)
	local hint = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.65, 0.65, 0.65)
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	hint:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	hint:SetText(L.COPY_HINT)
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
	local scroll = CreateFrame("ScrollFrame", "WandererCopyScroll", window, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin - 22, margin)
	box = CreateFrame("EditBox", "WandererCopyBox", scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetWidth(WIDTH - 2 * margin - 30)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	scroll:SetScrollChild(box)
	if UISpecialFrames then table.insert(UISpecialFrames, "WandererCopy") end
end

function ns.CopyChat()
	if not window then CreateWindow() end
	box:SetText(table.concat(ChatLines(), "\n"))
	window:SetScale(ns.Skin.Scale())
	window:Show()
	ns.Skin.Get(window):Layout()
	box:SetFocus()
	box:HighlightText()
end
