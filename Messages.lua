local _, ns = ...
local L = ns.L

-- Private messages in their own window, in Wanderer's look: the people you
-- whisper with on the left, the conversation on the right, a line to answer
-- at the bottom. Whispers (and Battle.net whispers) leave the chat for it.
--
-- A new message opens the window without taking the keyboard, never during a
-- fight or a conversation scene: then the minimap menu counts the unread
-- ones. History is kept per character (Battle.net ones for the session only:
-- the game renews their ids). Only events, nothing runs between messages.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local WIDTH, HEIGHT = 560, 340
local LIST_WIDTH = 150
local ROW_HEIGHT = 30
local MAX_LINES = 200 -- kept per person
local MAX_PEOPLE = 40
local TIME_FORMAT = "%H:%M"
local EVENTS = { -- event -> who wrote it
	CHAT_MSG_WHISPER = "them", CHAT_MSG_WHISPER_INFORM = "me",
	CHAT_MSG_BN_WHISPER = "them", CHAT_MSG_BN_WHISPER_INFORM = "me",
}

local window, list, history, input, header, portrait
local PORTRAIT, ROW_PORTRAIT = 40, 22
local CLASSES_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
-- The game's race names that its icons spell differently.
local RACE_ICONS = { Scourge = "undead", NightElf = "nightelf", BloodElf = "bloodelf", HighmountainTauren = "highmountain",
	LightforgedDraenei = "lightforged", VoidElf = "voidelf", ZandalariTroll = "zandalari", KulTiran = "kultiran",
	DarkIronDwarf = "darkirondwarf", MagharOrc = "magharorc", Nightborne = "nightborne" }
local rows = {}
local current -- key of the conversation shown
local session = {} -- Battle.net conversations (not saved)

-- Data -----------------------------------------------------------------------------------

local function Store()
	ns.root.messages = ns.root.messages or {}
	local key = ns.CharacterKey()
	ns.root.messages[key] = ns.root.messages[key] or {}
	return ns.root.messages[key]
end

local function Conversation(key)
	if key:sub(1, 3) == "BN:" then
		session[key] = session[key] or { lines = {}, unread = 0, last = 0 }
		return session[key]
	end
	local store = Store()
	store[key] = store[key] or { lines = {}, unread = 0, last = 0 }
	return store[key]
end

local function AllConversations()
	local all = {}
	for key, talk in pairs(Store()) do all[#all + 1] = { key = key, talk = talk } end
	for key, talk in pairs(session) do all[#all + 1] = { key = key, talk = talk } end
	table.sort(all, function(a, b) return (a.talk.last or 0) > (b.talk.last or 0) end)
	return all
end

-- The oldest people go when there are too many.
local function Trim()
	local all = AllConversations()
	for index = MAX_PEOPLE + 1, #all do
		local key = all[index].key
		if key:sub(1, 3) == "BN:" then session[key] = nil else Store()[key] = nil end
	end
end

function ns.UnreadMessages()
	local count = 0
	for _, entry in ipairs(AllConversations()) do count = count + (entry.talk.unread or 0) end
	return count
end

-- Portraits ---------------------------------------------------------------------------------
-- The real one when the person is around (target, group, nearby with a
-- nameplate); else the portrait of their race and gender as the game knows
-- them; else their class.

local UNITS = { "target", "focus", "mouseover" }
for index = 1, 4 do UNITS[#UNITS + 1] = "party" .. index end
for index = 1, 40 do UNITS[#UNITS + 1] = "raid" .. index end

local function UnitFor(guid)
	if not guid then return end
	for _, unit in ipairs(UNITS) do
		if Clean(Safe(UnitGUID, unit)) == guid then return unit end
	end
	for _, plate in ipairs(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}) do
		local unit = plate.namePlateUnitToken
		if unit and Clean(Safe(UnitGUID, unit)) == guid then return unit end
	end
end

local function SetPortrait(texture, talk)
	texture:SetTexCoord(0, 1, 0, 1)
	local unit = UnitFor(talk.guid)
	if unit and SetPortraitTexture then
		Safe(SetPortraitTexture, texture, unit)
		return true
	end
	if talk.race then
		local race = RACE_ICONS[talk.race] or talk.race:lower()
		local gender = talk.sex == 3 and "female" or "male"
		for _, atlas in ipairs({ "raceicon128-" .. race .. "-" .. gender, "raceicon-" .. race .. "-" .. gender }) do
			if U.HasAtlas(atlas) then
				texture:SetAtlas(atlas)
				return true
			end
		end
	end
	local coords = talk.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[talk.class]
	if coords then
		texture:SetTexture(CLASSES_TEXTURE)
		texture:SetTexCoord(unpack(coords))
		return true
	end
	return false
end

local function ShowPortrait(texture, talk)
	local shown = talk and SetPortrait(texture, talk) or false
	texture:SetShown(shown)
	texture.ring:SetShown(shown and texture.ringShown or false)
end

-- Window -----------------------------------------------------------------------------------

local function Hex(color) return color and color.colorStr and ("|c" .. color.colorStr) or "|cffffffff" end

local function NameOf(talk, key)
	local color = talk.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[talk.class]
	return Hex(color) .. (talk.name or key) .. "|r"
end

local function Line(entry)
	local stamp = "|cff808080" .. date(TIME_FORMAT, entry.t) .. "|r  "
	local who = entry.me and ("|cffbfbfbf" .. L.MESSAGES_ME .. "|r") or ("|cffffd100" .. (entry.from or "?") .. "|r")
	return stamp .. who .. "  " .. (entry.text or "")
end

local function ShowConversation(key)
	current = key
	local talk = Conversation(key)
	talk.unread = 0
	history:Clear()
	for _, entry in ipairs(talk.lines) do pcall(history.AddMessage, history, Line(entry)) end
	header:SetText(NameOf(talk, key))
	ShowPortrait(portrait, talk)
	input:Show()
	ns.RefreshMessages()
end

local function RowFor(index)
	local row = rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, list)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints()
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(6, 6)
	row.dot:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.dot:SetColorTexture(1, 0.82, 0, 1)
	row.portrait = ns.Skin.RoundPortrait(row, ROW_PORTRAIT)
	row.portrait:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.name = ns.Skin.CreateText(row, "GameTooltipText")
	row.name:SetPoint("LEFT", row.portrait, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.dot, "LEFT", -4, 0)
	if row.name.SetWordWrap then row.name:SetWordWrap(false) end
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			-- Forget this conversation.
			if self.key:sub(1, 3) == "BN:" then session[self.key] = nil else Store()[self.key] = nil end
			if current == self.key then current = nil end
		else
			ShowConversation(self.key)
		end
		ns.RefreshMessages()
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.MESSAGES_ROW_HINT, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[index] = row
	return row
end

function ns.RefreshMessages()
	if not (window and window:IsShown()) then return end
	local all = AllConversations()
	for index, entry in ipairs(all) do
		local row = RowFor(index)
		row.key = entry.key
		row.name:SetText(NameOf(entry.talk, entry.key))
		ShowPortrait(row.portrait, entry.talk)
		row.dot:SetShown((entry.talk.unread or 0) > 0)
		local selected = entry.key == current
		row.background:SetColorTexture(1, selected and 0.82 or 1, selected and 0 or 1, selected and 0.14 or 0)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		row:Show()
	end
	for index = #all + 1, #rows do rows[index]:Hide() end
	if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
	window.empty:SetShown(not all[1])
	if not current then
		header:SetText(L.MESSAGES_TITLE)
		ShowPortrait(portrait, nil)
		history:Clear()
		input:Hide()
	end
end

local function Send()
	local text = strtrim(input:GetText() or "")
	if text == "" or not current then return end
	input:SetText("")
	if current:sub(1, 3) == "BN:" then
		if BNSendWhisper then pcall(BNSendWhisper, tonumber(current:sub(4)), text) end
	else
		local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
		if send then pcall(send, text, "WHISPER", nil, current) end
	end
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererMessages", "MEDIUM")
	window:SetSize(WIDTH, HEIGHT)
	local pos = ns.root.messagesPos
	if pos then window:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else window:SetPoint("LEFT", UIParent, "LEFT", 40, 60) end
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint(1)
		ns.root.messagesPos = { point, x, y }
	end)
	local margin = ns.Skin.Margin() + 6
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)

	-- The people, on the left.
	list = CreateFrame("Frame", nil, window)
	list:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	list:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	list:SetWidth(LIST_WIDTH)
	local line = window:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.2)
	line:SetWidth(1)
	line:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	line:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 0)
	window.empty = ns.Skin.CreateText(list, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	window.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4)
	window.empty:SetPoint("RIGHT", list, "RIGHT", -4, 0)
	window.empty:SetText(L.MESSAGES_EMPTY)

	-- The conversation, on the right.
	portrait = ns.Skin.RoundPortrait(window, PORTRAIT)
	portrait:SetPoint("TOPLEFT", list, "TOPRIGHT", 16, 0)
	header = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	header:SetPoint("LEFT", portrait, "RIGHT", 12, 0)
	header:SetPoint("RIGHT", window, "RIGHT", -36, 0)
	if header.SetWordWrap then header:SetWordWrap(false) end
	input = CreateFrame("EditBox", "WandererMessagesInput", window)
	input:SetHeight(24)
	input:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 16, 0)
	input:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	input:SetFontObject("ChatFontNormal")
	input:SetAutoFocus(false)
	input:SetMaxLetters(255)
	input:SetTextInsets(8, 8, 0, 0)
	input.background = input:CreateTexture(nil, "BACKGROUND")
	input.background:SetAllPoints()
	input.background:SetColorTexture(0, 0, 0, 0.35)
	input:SetScript("OnEnterPressed", Send)
	input:SetScript("OnEscapePressed", input.ClearFocus)
	history = CreateFrame("ScrollingMessageFrame", "WandererMessagesHistory", window)
	history:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -10)
	history:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 8)
	history:SetFontObject("ChatFontNormal")
	history:SetJustifyH("LEFT")
	history:SetFading(false)
	history:SetMaxLines(MAX_LINES)
	history:SetHyperlinksEnabled(true)
	history:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
	history:EnableMouseWheel(true)
	history:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then self:ScrollUp() else self:ScrollDown() end
	end)

	if UISpecialFrames then table.insert(UISpecialFrames, "WandererMessages") end
	window:SetScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		if current then ShowConversation(current) else ns.RefreshMessages() end
	end)
	ns.Skin.Get(window):Layout()
end

function ns.ToggleMessages(key)
	if not ns.root then return end
	if not window then CreateWindow() end
	if key then
		window:Show()
		ShowConversation(key)
	else
		window:SetShown(not window:IsShown())
	end
end

-- For tests: a whisper to this very character. Its name exactly as the game
-- gives it (WoW Forever names may have two words: never cut, never suffixed).
function ns.WhisperMyself()
	local name = Clean(U.FullName("player"))
	if not name then return end
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	if send then pcall(send, L.TEST_WHISPER_TEXT:format(date("%H:%M:%S")), "WHISPER", nil, name) end
end

-- Messages --------------------------------------------------------------------------------

local function Enabled()
	return ns.db and ns.db.enabled and ns.db.messages.enabled
end

-- A message, written or received: kept, shown, and the window opened when quiet.
local function OnMessage(event, text, name, guid, bnID)
	local key
	if event:find("BN_") then
		bnID = Clean(bnID)
		if not bnID then return end
		key = "BN:" .. bnID
	else
		key = Clean(name)
		if not key then return end
	end
	local talk = Conversation(key)
	local me = EVENTS[event] == "me"
	if key:sub(1, 3) == "BN:" then
		-- The game gives a protected name: shown as is, never kept.
		talk.name = name
	else
		talk.name = Ambiguate and Clean(Safe(Ambiguate, key, "short")) or key
		guid = Clean(guid)
		if guid then
			local _, class, _, race, sex = Safe(GetPlayerInfoByGUID, guid)
			talk.guid = guid
			talk.class = Clean(class) or talk.class
			talk.race = Clean(race) or talk.race
			talk.sex = Clean(sex) or talk.sex
		end
	end
	talk.last = time()
	local entry = { t = time(), me = me or nil, from = talk.name }
	-- A text the game keeps secret is shown but not kept.
	if U.IsSecret(text) then
		entry.text = nil
	else
		entry.text = text
		talk.lines[#talk.lines + 1] = entry
		while #talk.lines > MAX_LINES do table.remove(talk.lines, 1) end
	end
	Trim()
	if current == key and window and window:IsShown() then
		if entry.text then pcall(history.AddMessage, history, Line(entry)) else pcall(history.AddMessage, history, text) end
	elseif not me then
		talk.unread = (talk.unread or 0) + 1
	end
	-- Opened by a message from someone, never over a fight or a scene, never taking the keyboard.
	if not me and not InCombatLockdown() and not ns.sceneActive and ns.db.messages.popup then
		if not (window and window:IsShown()) then ns.ToggleMessages(key) end
	end
	ns.RefreshMessages()
	if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
end

-- The chat no longer shows them (they are in the window); only those the
-- window can show: a message is never lost between the two.
local function Filter(_, event, _, name, ...)
	if not (Enabled() and ns.db.messages.hideInChat) then return false end
	if event:find("BN_") then return Clean(select(11, ...)) ~= nil end -- the 13th value: the Battle.net id
	return Clean(name) ~= nil
end

function ns.InitMessages()
	local frame = CreateFrame("Frame")
	for event in pairs(EVENTS) do frame:RegisterEvent(event) end
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_TARGET_CHANGED" then
			if current and window and window:IsShown() then ShowPortrait(portrait, Conversation(current)) end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			-- Messages came during the fight: the window opens now, on the newest.
			if Enabled() and ns.db.messages.popup and ns.UnreadMessages() > 0 and not (window and window:IsShown()) then
				ns.ToggleMessages(AllConversations()[1].key)
			end
			return
		end
		if not Enabled() then return end
		local text, name = ...
		local guid, bnID = select(12, ...), select(13, ...)
		OnMessage(event, text, name, guid, bnID)
	end)
	local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if addFilter then
		for event in pairs(EVENTS) do pcall(addFilter, event, Filter) end
	end
end
