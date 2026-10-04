local _, ns = ...
local L = ns.L

-- Two comforts of the chat (options):
-- * Your sent messages with the arrow keys: Up and Down bring them back while
--   you type, the last one first (as in a terminal), Left and Right move in
--   the text instead of turning your character. Wanderer keeps them itself,
--   the last 32 of each character, from one session to the next, and puts them back in the box: it never
--   relies on the game's own memory of the box (Alt + arrows), which some
--   clients do not answer.
-- * Copy the chat: a discreet button in the corner of the chat, shown while
--   the mouse is over it, opens the chat of that tab as plain text.

local U = ns.Util

local KEPT = 32 -- sent messages kept, as many as the game remembers
local BUTTON_SIZE = 18
local CHECK_EVERY = 0.1
local FADE_IN, FADE_OUT = 0.2, 0.5

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

function ns.RefreshChatComfort()
	Watch()
	local settings = Settings()
	local arrows = settings and settings.arrowHistory and true or false
	for _, box in ipairs(EditBoxes()) do
		if box.SetAltArrowKeyMode then U.Safe(box.SetAltArrowKeyMode, box, not arrows) end
	end
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
