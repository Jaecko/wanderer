local _, ns = ...
local L = ns.L

-- Private messages in their own window, in Wanderer's look: the people you
-- whisper with on the left, the conversation on the right, a line to answer
-- at the bottom. Whispers (and Battle.net whispers) leave the chat for it.
-- The conversation reads as a thread of bubbles drawn with the game's own
-- tooltip frame: theirs on the left, yours on the right in gold, the hour
-- between moments apart.
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
local ECHO_WAIT = 60 -- seconds: the game's confirmation of a message, recognised within this time
local EVENTS = { -- event -> who wrote it
	CHAT_MSG_WHISPER = "them", CHAT_MSG_WHISPER_INFORM = "me",
	CHAT_MSG_BN_WHISPER = "them", CHAT_MSG_BN_WHISPER_INFORM = "me",
}

local window, list, thread, input, header, info, portrait, person
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
	-- Pinned people first, then the most recent.
	table.sort(all, function(a, b)
		if (a.talk.pinned and true or false) ~= (b.talk.pinned and true or false) then return a.talk.pinned and true or false end
		return (a.talk.last or 0) > (b.talk.last or 0)
	end)
	return all
end

-- The oldest people go when there are too many.
local function Trim()
	local all = AllConversations()
	for index = MAX_PEOPLE + 1, #all do
		local key = all[index].key
		if not all[index].talk.pinned then -- a pinned conversation is never forgotten
			if key:sub(1, 3) == "BN:" then session[key] = nil else Store()[key] = nil end
		end
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

local function Hex(color) return color and color.colorStr and ("|c" .. color.colorStr) or "|cffffffff" end

-- Who they are ------------------------------------------------------------------------------
-- What the game can tell, best source first: the person near you, your
-- friends list, your guild's roster, a /who you asked for; else race and
-- class from the message itself. Kept with the conversation, with the time
-- it was true.

local SEEN_FRESH = 600 -- seconds: older information says when it was seen
local WHO_WAIT = 6 -- seconds before a /who without answer counts as "not found"
local WHO_MISS_SHOWN = 30 -- seconds the "not found" stays

local function IsBattleNet(key) return key:sub(1, 3) == "BN:" end

local function Short(talk, key)
	return talk.name or (Ambiguate and Clean(Safe(Ambiguate, key, "short"))) or key
end

-- The friends list functions, current or older names.
local function Friends(name)
	return C_FriendList and C_FriendList[name] or _G[name]
end

local function SameName(name, key, short)
	return name == key or (Ambiguate and Safe(Ambiguate, name, "short")) == short
end

local function Learn(talk, key)
	if IsBattleNet(key) then return end
	local short = Short(talk, key)
	local unit = UnitFor(talk.guid)
	if unit then
		talk.level = Clean(Safe(UnitLevel, unit)) or talk.level
		talk.guild = Clean(Safe(GetGuildInfo, unit))
		talk.zone = Clean(Safe(GetRealZoneText)) or talk.zone
		talk.online, talk.seen = true, time()
	end
	local friend = Safe(Friends("GetFriendInfo"), short)
	talk.friend = type(friend) == "table" or nil
	if talk.friend then
		talk.online = friend.connected and true or false
		if friend.connected then
			talk.level = Clean(friend.level) or talk.level
			talk.zone = Clean(friend.area) or talk.zone
			talk.seen = time()
		end
	end
	if not unit and IsInGuild and Safe(IsInGuild) then
		for index = 1, Clean(Safe(GetNumGuildMembers)) or 0 do
			local name, rank, _, level, _, zone, _, _, online = Safe(GetGuildRosterInfo, index)
			name = Clean(name)
			if name and SameName(name, key, short) then
				talk.guild = Clean(Safe(GetGuildInfo, "player")) or talk.guild
				talk.rank, talk.level = Clean(rank), Clean(level) or talk.level
				talk.online = online and true or false
				if online then talk.zone, talk.seen = Clean(zone) or talk.zone, time() end
				break
			end
		end
	end
end

-- "Level 60 Human Warrior · <Guild> Officer · Ironforge · Online"
local function InfoLine(talk, key)
	if IsBattleNet(key) then return "" end
	local parts = {}
	local color = talk.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[talk.class]
	local who = {}
	if talk.level then who[#who + 1] = LEVEL .. " " .. talk.level end
	if talk.raceName then who[#who + 1] = talk.raceName end
	if talk.className then who[#who + 1] = Hex(color) .. talk.className .. "|r" end
	if who[1] then parts[#parts + 1] = table.concat(who, " ") end
	if talk.guild then parts[#parts + 1] = "<" .. talk.guild .. ">" .. (talk.rank and (" " .. talk.rank) or "") end
	if talk.zone then parts[#parts + 1] = talk.zone end
	if talk.looking then
		parts[#parts + 1] = "|cff808080" .. L.MESSAGES_WHO_WAIT .. "|r"
	elseif talk.whoMiss and time() - talk.whoMiss < WHO_MISS_SHOWN then
		parts[#parts + 1] = "|cff808080" .. L.MESSAGES_WHO_NONE .. "|r"
	elseif talk.online == true then
		parts[#parts + 1] = "|cff66ff66" .. L.MESSAGES_ONLINE .. "|r"
	elseif talk.online == false then
		parts[#parts + 1] = "|cff808080" .. L.MESSAGES_OFFLINE .. "|r"
	end
	if talk.friend then parts[#parts + 1] = "|cff82c5ff" .. L.MESSAGES_FRIEND .. "|r" end
	if talk.seen and time() - talk.seen > SEEN_FRESH and talk.online ~= true then
		parts[#parts + 1] = "|cff808080" .. L.MESSAGES_SEEN:format(Safe(SecondsToTime, time() - talk.seen, true) or "?") .. "|r"
	end
	return table.concat(parts, "  |cff808080·|r  ")
end

local function RefreshHeader()
	if not (current and info) then return end
	info:SetText(InfoLine(Conversation(current), current))
end

-- /who on someone, asked from the menu: the answer fills their information.
local whoFor, friendsOpen

local function AskWho(key)
	local send = Friends("SendWho")
	if not send then return end
	local talk = Conversation(key)
	whoFor = key
	friendsOpen = FriendsFrame and FriendsFrame:IsShown()
	Safe(Friends("SetWhoToUi"), true)
	talk.looking, talk.whoMiss = true, nil
	Safe(send, ('n-"%s"'):format(Short(talk, key)))
	RefreshHeader()
	C_Timer.After(WHO_WAIT, function()
		if whoFor ~= key then return end
		whoFor = nil
		talk.looking, talk.whoMiss = nil, time()
		RefreshHeader()
	end)
end

local function OnWho()
	if not whoFor then return end
	local key, talk = whoFor, Conversation(whoFor)
	local short = Short(talk, key)
	local found = false
	for index = 1, Clean(Safe(Friends("GetNumWhoResults"))) or 0 do
		local entry = Safe(Friends("GetWhoInfo"), index)
		local name = type(entry) == "table" and Clean(entry.fullName)
		if name and SameName(name, key, short) then
			talk.level = Clean(entry.level) or talk.level
			talk.raceName = Clean(entry.raceStr) or talk.raceName
			talk.className = Clean(entry.classStr) or talk.className
			talk.class = Clean(entry.filename) or talk.class
			talk.guild = Clean(entry.fullGuildName)
			talk.zone = Clean(entry.area) or talk.zone
			talk.online, talk.seen = true, time()
			found = true
			break
		end
	end
	whoFor = nil
	talk.looking = nil
	if not found then talk.whoMiss = time() end
	-- The game's list may open for the answer: closed again if it was closed.
	if FriendsFrame and FriendsFrame:IsShown() and not friendsOpen and not InCombatLockdown() then FriendsFrame:Hide() end
	RefreshHeader()
end

-- What can be done with someone: the game's own actions, in every menu of a person.
local function PersonActions(root, key, talk)
	if IsBattleNet(key) then return end
	local short = Short(talk, key)
	root:CreateButton(L.MESSAGES_WHO, function() AskWho(key) end)
	root:CreateButton(L.MESSAGES_INVITE, function()
		Safe(C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit, key)
	end)
	if Safe(Friends("GetFriendInfo"), short) then
		root:CreateButton(L.MESSAGES_REMOVE_FRIEND, function() Safe(Friends("RemoveFriend"), short) end)
	else
		root:CreateButton(L.MESSAGES_ADD_FRIEND, function() Safe(Friends("AddFriend"), key) end)
	end
	if Clean(Safe(Friends("IsIgnored"), key)) then
		root:CreateButton(L.MESSAGES_UNIGNORE, function() Safe(Friends("DelIgnore"), key) end)
	else
		root:CreateButton(L.MESSAGES_IGNORE, function() Safe(Friends("AddIgnore"), key) end)
	end
end

-- Window -----------------------------------------------------------------------------------

local function NameOf(talk, key)
	local color = talk.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[talk.class]
	return Hex(color) .. (talk.name or key) .. "|r"
end

-- The thread of bubbles -----------------------------------------------------------------------

local BUBBLE_SHARE = 0.72 -- of the thread's width, at most
local BUBBLE_PAD_X, BUBBLE_PAD_Y = 10, 7
local SAME_GAP, OTHER_GAP = 3, 10 -- between bubbles of the same person, between two people
local TOGETHER = 180 -- seconds: closer messages of one person stay together
local APART = 900 -- seconds: the hour is written between moments further apart
local SCROLL_STEP = 40
local SENDING_ALPHA = 0.65 -- your message until the game confirms it
local BUBBLE_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BUBBLE_LOOK = {
	them = { bg = { 0.05, 0.05, 0.07, 0.88 }, edge = { 0.55, 0.55, 0.6, 0.9 }, text = { 0.95, 0.93, 0.88 } },
	me = { bg = { 0.2, 0.14, 0.04, 0.88 }, edge = { 1, 0.82, 0, 0.75 }, text = { 1, 0.95, 0.8 } },
}

local bubbles, stamps = {}, {} -- pools
local used = { bubbles = 0, stamps = 0, height = 0 }
local lastShown -- the entry shown last (its time and its author)
local bubbleOf = setmetatable({}, { __mode = "k" }) -- entry -> its bubble

local function ThreadWidth()
	return math.max(120, (thread.width or 300))
end

local function Bubble()
	used.bubbles = used.bubbles + 1
	local bubble = bubbles[used.bubbles]
	if bubble then return bubble end
	bubble = CreateFrame("Frame", nil, thread.content, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if bubble.SetBackdrop then bubble:SetBackdrop(BUBBLE_BACKDROP) end
	bubble.text = bubble:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	bubble.text:SetJustifyH("LEFT")
	if bubble.text.SetWordWrap then bubble.text:SetWordWrap(true) end
	bubble.text:SetPoint("TOPLEFT", bubble, "TOPLEFT", BUBBLE_PAD_X, -BUBBLE_PAD_Y)
	-- Item and quest links stay clickable; the hour shows under the mouse.
	if bubble.SetHyperlinksEnabled then pcall(bubble.SetHyperlinksEnabled, bubble, true) end
	bubble:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
	bubble:EnableMouse(true)
	bubble:SetScript("OnEnter", function(self)
		if not self.entry then return end
		GameTooltip:SetOwner(self, self.entry.me and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
		GameTooltip:AddLine(date("%d/%m %H:%M", self.entry.t or time()), 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	bubble:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bubbles[used.bubbles] = bubble
	return bubble
end

local function Stamp()
	used.stamps = used.stamps + 1
	local stamp = stamps[used.stamps]
	if not stamp then
		stamp = ns.Skin.CreateText(thread.content, "GameTooltipTextSmall", 0.55, 0.55, 0.55)
		stamp:SetJustifyH("CENTER")
		stamps[used.stamps] = stamp
	end
	return stamp
end

local function ClearThread()
	for index = 1, used.bubbles do bubbles[index]:Hide() bubbles[index].entry = nil end
	for index = 1, used.stamps do stamps[index]:Hide() end
	used.bubbles, used.stamps, used.height = 0, 0, 0
	lastShown = nil
	thread.content:SetHeight(1)
	thread:SetVerticalScroll(0)
end

local function ScrollToEnd()
	local range = math.max(0, used.height - (thread:GetHeight() or 0))
	thread:SetVerticalScroll(range)
end

-- One message as a bubble, under the others.
local function AddBubble(entry, secretText)
	local width = ThreadWidth()
	local t = entry.t or time()
	-- The hour, between moments apart (and before the first one).
	if not lastShown or t - (lastShown.t or 0) > APART then
		local stamp = Stamp()
		local today = date("%d/%m") == date("%d/%m", t)
		stamp:SetText(today and date(TIME_FORMAT, t) or date("%d/%m " .. TIME_FORMAT, t))
		stamp:ClearAllPoints()
		used.height = used.height + (lastShown and OTHER_GAP or 2)
		stamp:SetPoint("TOP", thread.content, "TOP", 0, -used.height)
		stamp:SetWidth(width)
		stamp:Show()
		used.height = used.height + 12
		lastShown = nil
	end
	local together = lastShown and (lastShown.me and true or false) == (entry.me and true or false)
		and t - (lastShown.t or 0) <= TOGETHER
	used.height = used.height + (lastShown and (together and SAME_GAP or OTHER_GAP) or 4)
	local bubble = Bubble()
	local look = entry.me and BUBBLE_LOOK.me or BUBBLE_LOOK.them
	if bubble.SetBackdropColor then
		bubble:SetBackdropColor(look.bg[1], look.bg[2], look.bg[3], look.bg[4])
		bubble:SetBackdropBorderColor(look.edge[1], look.edge[2], look.edge[3], look.edge[4])
	end
	local text = bubble.text
	text:SetTextColor(look.text[1], look.text[2], look.text[3])
	local most = math.floor(width * BUBBLE_SHARE) - BUBBLE_PAD_X * 2
	text:SetWidth(most)
	if not pcall(text.SetText, text, secretText or entry.text or "") then text:SetText("") end
	local natural = U.Measure(text, "GetStringWidth", most)
	local textWidth = math.min(most, math.ceil(natural) + 1)
	text:SetWidth(textWidth)
	local textHeight = U.Measure(text, "GetStringHeight", 14)
	bubble:SetSize(textWidth + BUBBLE_PAD_X * 2, textHeight + BUBBLE_PAD_Y * 2)
	bubble:ClearAllPoints()
	if entry.me then
		bubble:SetPoint("TOPRIGHT", thread.content, "TOPRIGHT", -2, -used.height)
	else
		bubble:SetPoint("TOPLEFT", thread.content, "TOPLEFT", 2, -used.height)
	end
	-- Yours waits, a little faded, for the game to confirm it.
	local waiting = entry.echo and GetTime() - entry.echo >= 0 and GetTime() - entry.echo <= ECHO_WAIT
	bubble:SetAlpha(waiting and SENDING_ALPHA or 1)
	bubble.entry = entry
	bubbleOf[entry] = bubble
	bubble:Show()
	used.height = used.height + textHeight + BUBBLE_PAD_Y * 2
	thread.content:SetHeight(math.max(1, used.height + 4))
	lastShown = entry
	ScrollToEnd()
end

local function ShowConversation(key)
	current = key
	local talk = Conversation(key)
	talk.unread = 0
	ClearThread()
	for _, entry in ipairs(talk.lines) do AddBubble(entry) end
	header:SetText(NameOf(talk, key))
	Learn(talk, key)
	info:SetText(InfoLine(talk, key))
	person:SetShown(not IsBattleNet(key))
	ShowPortrait(portrait, talk)
	input:Show()
	ns.RefreshMessages()
end

local function Forget(key)
	if key:sub(1, 3) == "BN:" then session[key] = nil else Store()[key] = nil end
	if current == key then current = nil end
	ns.RefreshMessages()
end

-- The menu of someone in the list (right click), the game's own menus.
local function OpenMenu(row)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local key = row.key
	local talk = Conversation(key)
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(NameOf(talk, key))
		root:CreateButton(talk.pinned and L.MESSAGES_UNPIN or L.MESSAGES_PIN, function()
			talk.pinned = not talk.pinned or nil
			ns.RefreshMessages()
		end)
		if (talk.unread or 0) > 0 then
			root:CreateButton(L.MESSAGES_MARK_READ, function()
				talk.unread = 0
				ns.RefreshMessages()
			end)
		end
		if not IsBattleNet(key) then
			root:CreateDivider()
			PersonActions(root, key, talk)
		end
		root:CreateDivider()
		root:CreateButton("|cffff6060" .. L.MESSAGES_DELETE .. "|r", function() Forget(key) end)
	end)
end

-- The menu of the person shown (a click on their name or portrait).
local function OpenPersonMenu(owner)
	if not (current and MenuUtil and MenuUtil.CreateContextMenu) or IsBattleNet(current) then return end
	local key = current
	local talk = Conversation(key)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(NameOf(talk, key))
		PersonActions(root, key, talk)
	end)
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
	row.pin = row:CreateTexture(nil, "ARTWORK")
	row.pin:SetSize(12, 12)
	row.pin:SetPoint("RIGHT", row.dot, "LEFT", -4, 0)
	local atlasOk, applied = false, false
	if row.pin.SetAtlas then atlasOk, applied = pcall(row.pin.SetAtlas, row.pin, "PetJournal-FavoritesIcon") end
	if not atlasOk or applied == false then
		row.pin:SetTexture("Interface\\Common\\FavoritesIcon")
	end
	row.portrait = ns.Skin.RoundPortrait(row, ROW_PORTRAIT)
	row.portrait:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.name = ns.Skin.CreateText(row, "GameTooltipText")
	row.name:SetPoint("LEFT", row.portrait, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.pin, "LEFT", -4, 0)
	if row.name.SetWordWrap then row.name:SetWordWrap(false) end
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			OpenMenu(self)
		else
			ShowConversation(self.key)
			ns.RefreshMessages()
		end
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
		row.pin:SetShown(entry.talk.pinned and true or false)
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
		info:SetText("")
		person:Hide()
		ShowPortrait(portrait, nil)
		ClearThread()
		input:Hide()
	end
end

-- Your message in the window at once, as you send it: never waiting for the
-- game's confirmation (it may come late, or not reach Wanderer at all).
local function Echo(key, text)
	local talk = Conversation(key)
	local entry = { t = time(), me = true, from = talk.name, text = text, echo = GetTime() }
	talk.lines[#talk.lines + 1] = entry
	while #talk.lines > MAX_LINES do table.remove(talk.lines, 1) end
	talk.last = time()
	if current == key and window and window:IsShown() then AddBubble(entry) end
	ns.RefreshMessages()
end

local function Send()
	local text = strtrim(input:GetText() or "")
	if text == "" or not current then return end
	input:SetText("")
	Echo(current, text)
	local ok, problem
	if current:sub(1, 3) == "BN:" then
		if BNSendWhisper then ok, problem = pcall(BNSendWhisper, tonumber(current:sub(4)), text) end
	else
		local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
		if send then ok, problem = pcall(send, text, "WHISPER", nil, current) end
	end
	-- /wanderer debug: why the game refused it.
	if ns.debug and ok == false then ns.Print(L.MESSAGES_DEBUG_FAILED:format(tostring(problem))) end
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererMessages", "MEDIUM")
	ns.Skin.Sounds(window, "IG_CHARACTER_INFO_OPEN", "IG_CHARACTER_INFO_CLOSE")
	window:SetSize(WIDTH, HEIGHT)
	ns.Skin.Dress(window, { "LEFT", UIParent, "LEFT", 40, 60 }, "messagesPos")
	local margin = ns.Skin.Margin() + 6

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
	header:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 12, -3)
	header:SetPoint("RIGHT", window, "RIGHT", -36, 0)
	if header.SetWordWrap then header:SetWordWrap(false) end
	-- Who they are, under the name.
	info = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.8, 0.8, 0.8)
	info:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	info:SetPoint("RIGHT", window, "RIGHT", -36, 0)
	if info.SetWordWrap then info:SetWordWrap(false) end
	-- A click on the person (portrait or name): what can be done with them.
	person = CreateFrame("Button", nil, window)
	person:SetPoint("TOPLEFT", portrait, "TOPLEFT")
	person:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT")
	person:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	person:SetScript("OnClick", function(self) OpenPersonMenu(self) end)
	person:SetScript("OnEnter", function(self)
		header:SetAlpha(0.8)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L.MESSAGES_PERSON_HINT, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	person:SetScript("OnLeave", function()
		header:SetAlpha(1)
		GameTooltip:Hide()
	end)
	person:Hide()
	input = ns.Skin.CreateInput(window, "WandererMessagesInput", 255)
	input:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 16, 0)
	input:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	input:SetScript("OnEnterPressed", Send)
	input:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		window:Hide()
	end)
	thread = CreateFrame("ScrollFrame", "WandererMessagesHistory", window)
	thread:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -10)
	thread:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 8)
	-- Its width is known from the window's (the frame may not be laid out yet).
	thread.width = WIDTH - margin * 2 - LIST_WIDTH - 16
	thread.content = CreateFrame("Frame", nil, thread)
	thread.content:SetSize(thread.width, 1)
	thread:SetScrollChild(thread.content)
	thread:EnableMouseWheel(true)
	thread:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, used.height - (self:GetHeight() or 0))
		local value = (self:GetVerticalScroll() or 0) - delta * SCROLL_STEP
		self:SetVerticalScroll(math.min(range, math.max(0, value)))
	end)

	window:HookScript("OnShow", function(self)
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

local SOUND_COOLDOWN = 3 -- seconds: a quick exchange rings once, as in the game
local lastSound = 0

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
			local className, class, raceName, race, sex = Safe(GetPlayerInfoByGUID, guid)
			talk.guid = guid
			talk.className = Clean(className) or talk.className
			talk.raceName = Clean(raceName) or talk.raceName
			talk.class = Clean(class) or talk.class
			talk.race = Clean(race) or talk.race
			talk.sex = Clean(sex) or talk.sex
		end
	end
	talk.last = time()
	-- The confirmation of a message already shown when you sent it: nothing more.
	if me then
		for index = #talk.lines, math.max(1, #talk.lines - 10), -1 do
			local line = talk.lines[index]
			if line.echo and GetTime() - line.echo <= ECHO_WAIT and (U.IsSecret(text) or line.text == text) then
				line.echo = nil
				if bubbleOf[line] and bubbleOf[line].entry == line then bubbleOf[line]:SetAlpha(1) end
				return
			end
		end
	end
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
	-- The chat no longer shows it, so the game no longer rings: Wanderer rings
	-- with the game's own whisper sound instead (never both).
	if not me and ns.db.messages.sound and ns.db.messages.hideInChat and GetTime() - lastSound >= SOUND_COOLDOWN then
		lastSound = GetTime()
		local sound = SOUNDKIT and SOUNDKIT.TELL_MESSAGE
		if sound and PlaySound then pcall(PlaySound, sound) end
	end
	if current == key and window and window:IsShown() then
		AddBubble(entry, not entry.text and text or nil)
	elseif not me then
		talk.unread = (talk.unread or 0) + 1
	end
	-- Opened by a message from someone, never over a fight or a scene, never taking the keyboard.
	if not me and not InCombatLockdown() and not ns.sceneActive and ns.db.messages.popup then
		if not (window and window:IsShown()) then
			-- Opened by the message itself: its own sound rings, not the window's.
			if not window then CreateWindow() end
			window.quiet = true
			ns.ToggleMessages(key)
			window.quiet = nil
		end
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
	frame:RegisterEvent("WHO_LIST_UPDATE")
	frame:RegisterEvent("FRIENDLIST_UPDATE")
	frame:RegisterEvent("GUILD_ROSTER_UPDATE")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "WHO_LIST_UPDATE" then return OnWho() end
		if event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
			if current and window and window:IsShown() then
				Learn(Conversation(current), current)
				RefreshHeader()
			end
			return
		end
		if event == "PLAYER_TARGET_CHANGED" then
			if current and window and window:IsShown() then ShowPortrait(portrait, Conversation(current)) end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			-- Messages came during the fight: the window opens now, on the newest.
			if Enabled() and ns.db.messages.popup and ns.UnreadMessages() > 0 and not (window and window:IsShown()) then
				if not window then CreateWindow() end
				window.quiet = true
				ns.ToggleMessages(AllConversations()[1].key)
				window.quiet = nil
			end
			return
		end
		local text, name = ...
		if not Enabled() then return end
		local guid, bnID = select(12, ...), select(13, ...)
		OnMessage(event, text, name, guid, bnID)
	end)
	local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if addFilter then
		for event in pairs(EVENTS) do pcall(addFilter, event, Filter) end
	end
end
