local _, ns = ...
local L = ns.L

-- Four comforts of the chat (options):
-- * Your sent messages with the arrow keys: Up and Down bring them back while
--   you type, the last one first (as in a terminal), Left and Right move in
--   the text instead of turning your character. Wanderer keeps them itself,
--   the last 32 of each character, from one session to the next, and puts them back in the box: it never
--   relies on the game's own memory of the box (Alt + arrows), which some
--   clients do not answer.
-- * Copy the chat: a discreet button in the corner of the chat, shown while
--   the mouse is over it, opens the chat of that tab as plain text.
-- * The conversations kept: each tab keeps its last lines (its channels, as
--   the game shows them) from one session to the next, for each character;
--   after a reload or a new session they are back in their tab, a little
--   dimmed, under a quiet line. Secret lines are never kept.
-- * Web addresses become links: a click opens the address, ready to copy
--   (the game lets nothing be copied from the chat), in the guild's windows too.

local U = ns.Util

local KEPT = 32 -- sent messages kept, as many as the game remembers
local BUTTON_SIZE = 18
local CHECK_EVERY = 0.1
local FADE_IN, FADE_OUT = 0.2, 0.5
local LOG_KEPT = 150 -- lines kept per tab
local LOG_DIM = 0.7 -- the lines of before, a little dimmed

local boxes = {} -- edit box -> true: watched
local browsing = {} -- edit box -> { index, draft } while you go through your messages
local buttons = {} -- chat frame -> its copy button

local function Settings()
	local db = ns.db
	return db and db.enabled and db.chat or nil
end

local function EditBoxes()
	local list = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local box = _G["ChatFrame" .. i .. "EditBox"]
		if box then list[#list + 1] = box end
	end
	return list
end

-- Each character has its own messages (a few only: KEPT), in the saved variables.
local function History()
	local root = ns.root
	if not (root and ns.CharacterKey) then return {} end
	local all = type(root.chatHistory) == "table" and root.chatHistory or {}
	if all[1] ~= nil then all = {} end -- an old shared list: started anew, per character
	root.chatHistory = all
	local key = ns.CharacterKey()
	if type(all[key]) ~= "table" then all[key] = {} end
	return all[key]
end

-- A message sent: remembered for the next session (never a secret one).
local function Remember(text)
	if type(text) ~= "string" or text == "" or U.IsSecret(text) then return end
	local history = History()
	if history[#history] == text then return end
	history[#history + 1] = text
	while #history > KEPT do table.remove(history, 1) end
end

-- The lines of each tab, per character: { [tab number] = { { text, r, g, b }, ... } }.
local function Log()
	local root = ns.root
	if not (root and ns.CharacterKey) then return {} end
	root.chatLog = type(root.chatLog) == "table" and root.chatLog or {}
	local key = ns.CharacterKey()
	if type(root.chatLog[key]) ~= "table" then root.chatLog[key] = {} end
	return root.chatLog[key]
end

local restoring = false -- Wanderer putting the lines of before back: not kept twice
local logged = {} -- chat frame -> true: watched

local function LogOn()
	local settings = Settings()
	return settings and settings.keepLog and true or false
end

-- The combat log (the game's second tab, loaded later) keeps its own lines: never touched.
local function IsCombatLogFrame(frame)
	return frame == _G.COMBATLOG or frame == _G.ChatFrame2
end

local function Keep(index, text, r, g, b)
	if restoring or not LogOn() or type(text) ~= "string" or U.IsSecret(text) or text == "" then return end
	if text:find("|K", 1, true) or text:find("|HBNplayer", 1, true) then return end
	-- The Wanderer tab (diagnostic mode) is never kept.
	if ns.IsDebugTab and ns.IsDebugTab(index) then return end
	local log = Log()
	log[index] = log[index] or {}
	local lines = log[index]
	lines[#lines + 1] = { text, r, g, b }
	while #lines > LOG_KEPT do table.remove(lines, 1) end
end

-- The lines of before, back in their tab, under a quiet line.
-- An addon that keeps the chat's history itself (ElvUI): the lines are not shown twice.
local function OtherHistory()
	local ok, on = pcall(function()
		local E = _G.ElvUI and _G.ElvUI[1]
		return E and E.private and E.private.chat and E.private.chat.enable and E.db and E.db.chat
			and E.db.chat.chatHistory and true or false
	end)
	return ok and on
end

local function Restore()
	if not LogOn() or OtherHistory() then return end
	local log = Log()
	restoring = true
	for index, lines in pairs(log) do
		local frame = type(index) == "number" and _G["ChatFrame" .. index]
		if frame and lines[1] and frame.AddMessage and not IsCombatLogFrame(frame) then
			U.Safe(frame.AddMessage, frame, "|cff808080" .. L.CHAT_LOG_BEFORE .. "|r")
			for _, line in ipairs(lines) do
				local r, g, b = line[2] or 1, line[3] or 1, line[4] or 1
				U.Safe(frame.AddMessage, frame, line[1], r * LOG_DIM, g * LOG_DIM, b * LOG_DIM)
			end
		end
	end
	restoring = false
end

ns.RestoreChatLog = Restore -- (tests)

-- /wanderer clear: the lines a tab kept go with its content.
function ns.ForgetChatLog(frame)
	local index = frame and frame.GetName and tonumber((frame:GetName() or ""):match("^ChatFrame(%d+)$"))
	if index then Log()[index] = nil end
end

local function WatchLog()
	for index = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. index]
		if frame and not logged[frame] and frame.AddMessage and not IsCombatLogFrame(frame) then
			logged[frame] = true
			hooksecurefunc(frame, "AddMessage", function(_, text, r, g, b)
				Keep(index, text, r, g, b)
			end)
		end
	end
end

-- Web addresses --------------------------------------------------------------------------

local LINK = "addon:Wanderer:url:"
local LINK_COLOR = "|cff9fd4ff"
local LINK_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }

local function LinksOn()
	local settings = Settings()
	return settings and settings.links and true or false
end

-- Each word that is an address becomes a link (its last mark of punctuation stays outside).
local function Linkify(text)
	if type(text) ~= "string" or U.IsSecret(text) or text:find("|H", 1, true) then return text end
	return (text:gsub("%S+", function(word)
		if not (word:match("^https?://%S") or word:match("^www%.[%w%-]+%.%a")) then return nil end
		local address, tail = word:match("^(.-)([%.,;:!%?%)]*)$")
		return LINK_COLOR .. "|H" .. LINK .. address .. "|h[" .. address .. "]|h|r" .. tail
	end))
end
ns.Linkify = Linkify -- (tests)

local function LinkFilter(_, _, message, ...)
	if U.IsSecret(message) or not LinksOn() then return false end
	local linked = Linkify(message)
	if linked ~= message then return false, linked, ... end
	return false
end

-- A click on an address: shown ready to copy.
local lastLink, lastLinkTime
local function OpenLink(link)
	if type(link) ~= "string" or link:sub(1, #LINK) ~= LINK then return end
	-- Heard twice (the registry and SetItemRef): opened once.
	if link == lastLink and GetTime() - lastLinkTime < 0.3 then return end
	lastLink, lastLinkTime = link, GetTime()
	if StaticPopup_Show then StaticPopup_Show("WANDERER_LINK", nil, nil, link:sub(#LINK + 1)) end
end

if StaticPopupDialogs then
	StaticPopupDialogs.WANDERER_LINK = {
		text = L.CHAT_LINK_COPY,
		button1 = CLOSE or OKAY,
		hasEditBox = true,
		editBoxWidth = 340,
		OnShow = function(self, address)
			local box = self.editBox or self.EditBox
			if box then
				box:SetText(address or "")
				box:HighlightText()
				box:SetFocus()
			end
		end,
		EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

local function WatchLinks()
	local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if addFilter then
		for _, event in ipairs(LINK_EVENTS) do pcall(addFilter, event, LinkFilter) end
	end
	-- The game hands the addons' links over through its registry; older games through SetItemRef.
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("SetItemRef", function(_, link) OpenLink(link) end, {})
	end
	if SetItemRef then hooksecurefunc("SetItemRef", OpenLink) end
end
ns.OpenChatLink = OpenLink -- (tests)

-- Web addresses in the guild's windows ------------------------------------------------------
-- The guild's information and its message of the day are shown by the game's
-- own windows, outside the chat: the addresses in what they show become links
-- too (only what is shown: the text kept by the guild never changes).

local GUILD_WINDOWS = { "CommunitiesFrame", "GuildFrame", "GuildInfoFrame" }
local GUILD_ADDONS = { Blizzard_Communities = true, Blizzard_GuildUI = true }
local GUILD_DEPTH = 10 -- frames looked into, at most, under a guild window
local GUILD_AGAIN = 0.5 -- seconds: the game fills its texts just after showing them
local listening = setmetatable({}, { __mode = "k" }) -- frame -> its links answer clicks

local function HearClicks(frame)
	if listening[frame] or not frame.HookScript then return end
	listening[frame] = true
	if frame.SetHyperlinksEnabled then pcall(frame.SetHyperlinksEnabled, frame, true) end
	pcall(frame.HookScript, frame, "OnHyperlinkClick", function(_, link) OpenLink(link) end)
end

-- Every text of a frame and of its children: its addresses made links. Returns how many texts.
local function LinkTexts(frame, depth)
	if depth > GUILD_DEPTH or not frame.GetRegions or (frame.IsForbidden and frame:IsForbidden()) then return 0 end
	local count = 0
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
			local text = U.Clean(region:GetText())
			if text and (text:find("https?://") or text:find("www%.")) then
				local linked = Linkify(text)
				if linked ~= text then
					region:SetText(linked)
					HearClicks(frame)
					count = count + 1
				end
			end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do count = count + LinkTexts(child, depth + 1) end
	return count
end

local function LinkGuildWindows()
	if not LinksOn() then return end
	for _, name in ipairs(GUILD_WINDOWS) do
		local window = _G[name]
		if window and window.IsShown and window:IsShown() then
			local count = LinkTexts(window, 1)
			if ns.debug and count > 0 then ns.Print(("guild links: %d text(s) in %s"):format(count, name)) end
		end
	end
end
ns.LinkGuildWindows = LinkGuildWindows -- (tests)

local function WatchGuildWindows()
	local hooked = {}
	local function Hook()
		for _, name in ipairs(GUILD_WINDOWS) do
			local window = _G[name]
			if window and not hooked[window] and window.HookScript then
				hooked[window] = true
				window:HookScript("OnShow", function()
					LinkGuildWindows()
					C_Timer.After(GUILD_AGAIN, LinkGuildWindows)
				end)
			end
		end
	end
	Hook()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("GUILD_MOTD")
	events:RegisterEvent("GUILD_ROSTER_UPDATE")
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if GUILD_ADDONS[name] then Hook() end
			return
		end
		-- The game filled the guild's texts again: their links again.
		C_Timer.After(GUILD_AGAIN, LinkGuildWindows)
	end)
end

-- The copy button of a chat frame.
local function Button(frame)
	if buttons[frame] then return buttons[frame] end
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
	button:SetFrameLevel(frame:GetFrameLevel() + 10)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetScript("OnClick", function() ns.CopyChat(frame) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L.COPY_TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L.CHAT_COPY_BUTTON_TIP, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetAlpha(0)
	button:Hide()
	button.tween = U.Tween(0)
	buttons[frame] = button
	return button
end

local function ArrowsOn()
	local settings = Settings()
	return settings and settings.arrowHistory and true or false
end

-- Up: one message further back; Down: one closer, then your text again.
local function Browse(box, key)
	if not ArrowsOn() or (key ~= "UP" and key ~= "DOWN") then return end
	local history = History()
	if not history[1] then return end
	local state = browsing[box]
	if key == "UP" then
		if not state then
			state = { index = #history + 1, draft = box:GetText() or "" }
			browsing[box] = state
		end
		state.index = math.max(1, state.index - 1)
	else
		if not state then return end
		state.index = state.index + 1
	end
	local text = history[state.index]
	if not text then
		text = state.draft
		browsing[box] = nil
	end
	box.wandererSetting = true
	box:SetText(text)
	box.wandererSetting = nil
	if box.SetCursorPosition then box:SetCursorPosition(#text) end
end

local function Watch()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then Button(frame) end
	end
	for _, box in ipairs(EditBoxes()) do
		if not boxes[box] and box.AddHistoryLine then
			boxes[box] = true
			hooksecurefunc(box, "AddHistoryLine", function(self, text)
				Remember(text)
				browsing[self] = nil
			end)
			box:HookScript("OnArrowPressed", Browse)
			box:HookScript("OnEditFocusGained", function(self)
				browsing[self] = nil
				-- The arrows to the box while you type (asked again each time: never lost).
				if ArrowsOn() and self.SetAltArrowKeyMode then U.Safe(self.SetAltArrowKeyMode, self, false) end
			end)
			box:HookScript("OnEditFocusLost", function(self) browsing[self] = nil end)
			box:HookScript("OnTextChanged", function(self, userInput)
				if userInput and not self.wandererSetting then browsing[self] = nil end
			end)
		end
	end
end

local arrowsApplied = false -- Wanderer set the arrows (else they are the game's or another addon's)

-- One size for the text of every chat window -----------------------------------------------
-- The game sets it window by window (right click on a tab): here once for all,
-- new windows included. Each window's size before is kept (per character) and
-- given back when Wanderer is turned off.

local function ChatWindows()
	local list = {}
	for index = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. index]
		if frame then list[#list + 1] = { index = index, frame = frame } end
	end
	-- Whisper windows the game opened apart.
	for _, name in ipairs(type(CHAT_FRAMES) == "table" and CHAT_FRAMES or {}) do
		local frame = _G[name]
		local index = frame and frame.GetID and frame:GetID()
		if index and index > (NUM_CHAT_WINDOWS or 10) then list[#list + 1] = { index = index, frame = frame } end
	end
	return list
end

local function SizeOf(window)
	local _, size = U.Safe(GetChatWindowInfo, window.index)
	size = U.Clean(size)
	if size then return size end
	if not window.frame.GetFont then return end
	local _, height = window.frame:GetFont()
	return height and math.floor(height + 0.5)
end

local function SetSize(window, size)
	if FCF_SetChatWindowFontSize then
		U.Safe(FCF_SetChatWindowFontSize, nil, window.frame, size)
	elseif window.frame.GetFont then
		local font, _, flags = window.frame:GetFont()
		if font then window.frame:SetFont(font, size, flags) end
		if SetChatWindowSize then U.Safe(SetChatWindowSize, window.index, size) end
	end
end

local function FontSizes()
	if not ns.root then return end
	ns.root.chatFontBefore = type(ns.root.chatFontBefore) == "table" and ns.root.chatFontBefore or {}
	local key = ns.CharacterKey()
	local before = ns.root.chatFontBefore[key] or {}
	local settings = Settings()
	local size = settings and settings.fontSize
	if size then
		for _, window in ipairs(ChatWindows()) do
			local current = SizeOf(window)
			if before[window.index] == nil and current then before[window.index] = current end
			if current ~= size then SetSize(window, size) end
		end
		ns.root.chatFontBefore[key] = before
	elseif next(before) then
		-- Wanderer turned off: each window as it was.
		for _, window in ipairs(ChatWindows()) do
			local old = before[window.index]
			if old and SizeOf(window) ~= old then SetSize(window, old) end
		end
		ns.root.chatFontBefore[key] = nil
	end
end
ns.ApplyChatFontSize = FontSizes

function ns.RefreshChatComfort()
	FontSizes()
	Watch()
	local settings = Settings()
	local arrows = settings and settings.arrowHistory and true or false
	if arrows or arrowsApplied then
		for _, box in ipairs(EditBoxes()) do
			if box.SetAltArrowKeyMode then U.Safe(box.SetAltArrowKeyMode, box, not arrows) end
		end
	end
	arrowsApplied = arrows
	local copy = settings and settings.copyButton and true or false
	for _, button in pairs(buttons) do
		if not copy then
			button.tween:Set(0)
			button:SetAlpha(0)
			button:Hide()
		end
		button.enabled = copy
	end
end

function ns.InitChatComfort()
	-- A window opened later (a whisper apart, a new tab): at the same size.
	if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() FontSizes() end) end
	if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", function() FontSizes() end) end
	-- The lines of before first, then every new one kept.
	Restore()
	WatchLog()
	WatchLinks()
	WatchGuildWindows()
	Watch()
	ns.RefreshChatComfort()
	local since = 0
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		local check = since >= CHECK_EVERY
		if check then since = 0 end
		for frame, button in pairs(buttons) do
			if check then
				button.wanted = button.enabled and frame:IsVisible() and (U.IsMouseOver(frame) or U.IsMouseOver(button)) and 1 or 0
			end
			local wanted = button.wanted or 0
			if wanted > 0 and not button:IsShown() then button:Show() end
			local alpha = button.tween:Step(wanted, elapsed, FADE_IN, FADE_OUT)
			button:SetAlpha(alpha)
			if alpha <= 0 and wanted == 0 and button:IsShown() then button:Hide() end
		end
	end)
end
