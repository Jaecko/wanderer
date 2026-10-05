local _, ns = ...
local L = ns.L

-- Conversations as quiet scenes. When you talk to a character, the
-- interface fades away and its words appear in a panel at the bottom of the
-- screen, drawn in your predefined style, page by page. Choices, quests and
-- their rewards stay in the same panel. (The camera: Camera.lua.)
--
-- Buttons at the bottom of the panel continue, accept or close; the same
-- with the keys during a scene: Space continues (and accepts), 1 to 9 choose,
-- Escape closes; a click on the text continues. They are borrowed only during the
-- scene and never in a fight. Holding Shift while talking, or a fight, opens
-- the game's own window instead.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local Gossip = C_GossipInfo or {}

-- Look and motion
local PANEL_WIDTH_SHARE, PANEL_MAX_WIDTH, PANEL_MIN_WIDTH = 0.5, 760, 460
local PANEL_BOTTOM = 110 -- above the bottom of the screen
local PANEL_MAX_HEIGHT_SHARE = 0.55
local RISE = 14 -- pixels the panel rises while it appears
local APPEAR, DISAPPEAR, PAGE_FADE = 0.7, 0.5, 0.4
local GAP, SMALL_GAP = 12, 6
local CHOICE_HEIGHT, REWARD_ICON = 24, 30
local BEST_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
local UP_TEXTURE, DOWN_TEXTURE = "Interface\\Buttons\\Arrow-Up-Up", "Interface\\Buttons\\Arrow-Down-Up"
-- Where an item goes: the equipment slots it would replace.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18, 16 }, INVTYPE_RANGEDRIGHT = { 18, 16 },
}
local UNUSABLE = { 1, 0.32, 0.32 }
local BUTTON_HEIGHT, BUTTON_PADDING = 26, 14
local PORTRAIT_SIZE = 52
local RING_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MAX_CHOICES = 9
local PAGE_CHARS = 260 -- about two or three sentences

-- Events the game's windows listen to, that Wanderer takes when scenes are on.
-- The game's dialogues are opened by a manager (CustomGossipFrameManager),
-- not by the gossip window itself; older games: the window.
local SHOW_EVENTS = {
	GOSSIP_SHOW = { "CustomGossipFrameManager", "GossipFrame" }, QUEST_GREETING = { "QuestFrame" },
	QUEST_DETAIL = { "QuestFrame" }, QUEST_PROGRESS = { "QuestFrame" }, QUEST_COMPLETE = { "QuestFrame" },
}

local QUEST_ICONS = {
	available = { atlas = "QuestNormal", texture = "Interface\\GossipFrame\\AvailableQuestIcon" },
	complete = { atlas = "QuestTurnin", texture = "Interface\\GossipFrame\\ActiveQuestIcon" },
	active = { atlas = "QuestActive", texture = "Interface\\GossipFrame\\IncompleteQuestIcon" },
}

local panel, skin, portrait, portraitRing, nameText, titleText, rule, bodyText, rewardsLabel, moneyText, keysText
local choiceRows, rewardItems, actionButtons = {}, {}, {}
local scene -- { kind, name, title, pages, page, choices, rewards, money, action, ... }
local taken = false
local takenFrames = {} -- event: the game's frames that stopped listening to it
local relaying = false
local appear, target = 0, 0 -- panel's appearance: current and wanted (0 to 1)
local pageAlpha = 1
local sceneToken = 0
local planned -- the event of the scene planned for the next frame

-- Game's windows ---------------------------------------------------------------------

local function Owner(event)
	for _, name in ipairs(SHOW_EVENTS[event]) do
		if _G[name] then return _G[name] end
	end
end

-- A frame of the game's conversation windows (the window or one of its parts).
local function IsGameWindow(frame)
	if frame.IsForbidden and frame:IsForbidden() then return false end
	local depth = 0
	while frame and depth < 8 do
		if frame == _G.GossipFrame or frame == _G.QuestFrame or frame == _G.CustomGossipFrameManager then return true end
		local ok, parent = pcall(frame.GetParent, frame)
		frame = ok and parent or nil
		depth = depth + 1
	end
	return false
end

-- Every frame of those windows that listens to the event: depending on the
-- version of the game, a part of the window may listen instead of the window.
local function Listeners(event)
	local list = {}
	if GetFramesRegisteredForEvent then
		for _, frame in ipairs({ GetFramesRegisteredForEvent(event) }) do
			if type(frame) == "table" and IsGameWindow(frame) then list[#list + 1] = frame end
		end
	end
	local owner = Owner(event)
	if owner and not list[1] and (not owner.IsEventRegistered or owner:IsEventRegistered(event)) then
		list[1] = owner
	end
	return list
end

-- Quests the game takes care of without any window (as its own quest window
-- does): offered by an item, accepted on entering a place, from the
-- adventure map. They go straight to the game.
local function GameHandlesAlone(event, startItem)
	if event ~= "QUEST_DETAIL" then return false end
	if QuestIsFromAdventureMap and Clean(Safe(QuestIsFromAdventureMap)) then return true end
	startItem = Clean(startItem)
	if startItem and startItem ~= 0 then return true end
	return Clean(Safe(QuestGetAutoAccept)) and QuestIsFromAreaTrigger and Clean(Safe(QuestIsFromAreaTrigger)) and true or false
end

-- Scenes on: Wanderer listens instead of the game's windows; off: given back.
local function SetTaken(take)
	if take == taken then return end
	for event in pairs(SHOW_EVENTS) do
		if take then
			takenFrames[event] = Listeners(event)
			for _, frame in ipairs(takenFrames[event]) do frame:UnregisterEvent(event) end
		else
			for _, frame in ipairs(takenFrames[event] or {}) do frame:RegisterEvent(event) end
			takenFrames[event] = nil
		end
	end
	taken = take
end

-- The game's own window shows the conversation (Shift, fight...).
local function Relay(event, ...)
	local frames = takenFrames[event]
	if not (frames and frames[1]) then frames = { Owner(event) } end
	relaying = true
	for _, frame in ipairs(frames) do
		local handler = frame.GetScript and frame:GetScript("OnEvent")
		if handler then pcall(handler, frame, event, ...) end
	end
	relaying = false
end

-- Text -------------------------------------------------------------------------------

-- Pages of whole sentences, about PAGE_CHARS long. A sentence is a run of
-- words with its ending marks; line breaks separate sentences too. Only
-- plain ASCII marks are used: accented letters are never cut.
local function Pages(text)
	if U.IsSecret(text) then return { text } end
	text = Clean(text)
	if not text then return { "" } end
	local pages, current = {}, ""
	for sentence in text:gmatch("[^%.!%?\n]+[%.!%?]*") do
		sentence = strtrim(sentence)
		if sentence ~= "" then
			if current ~= "" and #current + #sentence > PAGE_CHARS then
				pages[#pages + 1] = current
				current = sentence
			else
				current = current == "" and sentence or (current .. " " .. sentence)
			end
		end
	end
	if current ~= "" then pages[#pages + 1] = current end
	if not pages[1] then pages[1] = text end
	return pages
end

local function IsLastPage() return scene and scene.page >= #scene.pages end

-- Content ----------------------------------------------------------------------------

-- Choices of the conversation: { label, icon, atlas, action }.
local function GossipChoices()
	local choices = {}
	for _, quest in ipairs(Safe(Gossip.GetActiveQuests) or {}) do
		local icon = quest.isComplete and QUEST_ICONS.complete or QUEST_ICONS.active
		choices[#choices + 1] = { label = quest.title, atlas = icon.atlas, icon = icon.texture,
			action = function() Safe(Gossip.SelectActiveQuest, quest.questID) end }
	end
	for _, quest in ipairs(Safe(Gossip.GetAvailableQuests) or {}) do
		choices[#choices + 1] = { label = quest.title, atlas = QUEST_ICONS.available.atlas, icon = QUEST_ICONS.available.texture,
			action = function() Safe(Gossip.SelectAvailableQuest, quest.questID) end }
	end
	local options = Safe(Gossip.GetOptions) or {}
	table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
	for _, option in ipairs(options) do
		choices[#choices + 1] = { label = option.name, icon = option.icon,
			action = function() Safe(Gossip.SelectOption, option.gossipOptionID) end }
	end
	return choices
end

local function GreetingChoices()
	local choices = {}
	for index = 1, (Clean(Safe(GetNumActiveQuests)) or 0) do
		local title, complete = Safe(GetActiveTitle, index)
		local icon = complete and QUEST_ICONS.complete or QUEST_ICONS.active
		choices[#choices + 1] = { label = title, atlas = icon.atlas, icon = icon.texture,
			action = function() Safe(SelectActiveQuest, index) end }
	end
	for index = 1, (Clean(Safe(GetNumAvailableQuests)) or 0) do
		choices[#choices + 1] = { label = Safe(GetAvailableTitle, index), atlas = QUEST_ICONS.available.atlas,
			icon = QUEST_ICONS.available.texture, action = function() Safe(SelectAvailableQuest, index) end }
	end
	return choices
end

-- Items of the quest shown: { kind, index, name, texture, count, quality }.
local function Rewards(required)
	local rewards = {}
	local function add(kind, count)
		for index = 1, count do
			local name, texture, amount, quality, usable = Safe(GetQuestItemInfo, kind, index)
			if name then
				rewards[#rewards + 1] = { kind = kind, index = index, name = name, texture = texture,
					count = Clean(amount) or 1, quality = Clean(quality), unusable = Clean(usable) == false }
			end
		end
	end
	if required then
		add("required", Clean(Safe(GetNumQuestItems)) or 0)
	else
		add("choice", Clean(Safe(GetNumQuestChoices)) or 0)
		add("reward", Clean(Safe(GetNumQuestRewards)) or 0)
	end
	return rewards
end

local function ItemInfo(link)
	return Safe(C_Item and C_Item.GetItemInfo or GetItemInfo, link)
end

local function ItemLevel(link)
	local level = C_Item and C_Item.GetDetailedItemLevelInfo and Clean(Safe(C_Item.GetDetailedItemLevelInfo, link))
	return level or Clean(select(4, ItemInfo(link)))
end

-- Item level of the reward against what is worn in its place (the weakest of
-- two rings or trinkets): positive is better. Nil when it does not compare.
local function Compare(reward, link)
	if reward.unusable or not link then return end
	local slots = SLOTS[Clean(select(9, ItemInfo(link))) or ""]
	local level = slots and ItemLevel(link)
	if not level then return end
	local worn
	for _, slot in ipairs(slots) do
		local wornLink = Clean(Safe(GetInventoryItemLink, "player", slot))
		local wornLevel = wornLink and ItemLevel(wornLink) or 0
		worn = worn and math.min(worn, wornLevel) or wornLevel
	end
	return level - (worn or 0)
end

-- What each reward to choose sells for, and the one that sells for the most
-- (only worth telling between two choices or more); how each item compares
-- with what is worn. Items the game has not loaded yet come with
-- GET_ITEM_INFO_RECEIVED.
local function Prices(rewards)
	local choices, best, bestPrice, missing = 0, nil, 0, false
	for _, reward in ipairs(rewards) do
		reward.best = nil
		local itemLink = Clean(Safe(GetQuestItemLink, reward.kind, reward.index))
		reward.compare = Compare(reward, itemLink)
		if reward.kind == "choice" then
			choices = choices + 1
			local link = Safe(GetQuestItemLink, "choice", reward.index)
			local price = link and Clean(select(11, Safe(C_Item and C_Item.GetItemInfo or GetItemInfo, link)))
			if link and not price then
				missing = true
				if C_Item and C_Item.RequestLoadItemDataByID then Safe(C_Item.RequestLoadItemDataByID, link) end
			end
			reward.price = price
			if price and price > bestPrice then best, bestPrice = reward, price end
		end
	end
	if choices < 2 then
		for _, reward in ipairs(rewards) do reward.price = nil end
	elseif best then
		best.best = true
	end
	return missing
end

local function RewardMoney(required)
	local money = Clean(Safe(required and GetQuestMoneyToGet or GetRewardMoney)) or 0
	local xp = not required and Clean(Safe(GetRewardXP)) or 0
	local parts = {}
	if money > 0 then parts[#parts + 1] = (required and L.SCENE_COSTS or L.SCENE_MONEY):format(U.Coins(money)) end
	if xp and xp > 0 then parts[#parts + 1] = L.SCENE_XP:format(xp) end
	return table.concat(parts, "     ")
end

-- The quest's objectives and where they stand, for a quest brought back
-- unfinished (or to be sure before turning it in).
local function Objectives()
	local questID = Clean(Safe(GetQuestID))
	local list = questID and C_QuestLog and C_QuestLog.GetQuestObjectives and Safe(C_QuestLog.GetQuestObjectives, questID)
	if type(list) ~= "table" or not list[1] then return end
	local lines = { "|cffffd100" .. L.SCENE_OBJECTIVES .. "|r" }
	for _, objective in ipairs(list) do
		local text = Clean(objective.text)
		if text then
			lines[#lines + 1] = (Clean(objective.finished) and "|cff66dd66" or "|cffeeeeee") .. "-  " .. text .. "|r"
		end
	end
	return lines[2] and table.concat(lines, "\n") or nil
end

local function Build(event)
	local unit = Clean(Safe(UnitExists, "questnpc")) and "questnpc" or (Clean(Safe(UnitExists, "npc")) and "npc" or nil)
	local s = { kind = event, unit = unit, name = unit and Safe(UnitName, unit), page = 1, choices = {}, rewards = {} }
	if event == "GOSSIP_SHOW" then
		s.pages = Pages(Safe(Gossip.GetText))
		s.choices = GossipChoices()
	elseif event == "QUEST_GREETING" then
		s.pages = Pages(Safe(GetGreetingText))
		s.choices = GreetingChoices()
	elseif event == "QUEST_DETAIL" then
		s.title = Safe(GetTitleText)
		s.pages = Pages(Safe(GetQuestText))
		local objectives = Clean(Safe(GetObjectiveText))
		if objectives then s.pages[#s.pages + 1] = "|cffffd100" .. L.SCENE_OBJECTIVES .. "|r " .. objectives end
		s.rewards, s.money = Rewards(false), RewardMoney(false)
		s.waitingPrices = Prices(s.rewards)
		s.action = L.SCENE_ACCEPT
		s.declinable = true
	elseif event == "QUEST_PROGRESS" then
		s.title = Safe(GetTitleText)
		s.pages = Pages(Safe(GetProgressText))
		local objectives = Objectives()
		if objectives then s.pages[#s.pages + 1] = objectives end
		s.rewards, s.money = Rewards(true), RewardMoney(true)
		s.completable = Clean(Safe(IsQuestCompletable)) and true or false
		s.action = s.completable and L.SCENE_CONTINUE or nil
	elseif event == "QUEST_COMPLETE" then
		s.title = Safe(GetTitleText)
		s.pages = Pages(Safe(GetRewardText))
		s.rewards, s.money = Rewards(false), RewardMoney(false)
		s.waitingPrices = Prices(s.rewards)
		s.choiceCount = Clean(Safe(GetNumQuestChoices)) or 0
		s.action = s.choiceCount <= 1 and L.SCENE_COMPLETE or nil
	end
	return s
end

-- The game's own sounds, as its dialogue and quest windows play them (they
-- are kept closed while the scene shows): open, close, a choice, a refusal.
local function GameSound(key)
	local sound = SOUNDKIT and SOUNDKIT[key]
	if sound and PlaySound then pcall(PlaySound, sound) end
end

-- Actions ----------------------------------------------------------------------------

local function CloseConversation()
	if scene and scene.kind == "GOSSIP_SHOW" then
		Safe(Gossip.CloseGossip)
	else
		Safe(CloseQuest)
	end
end

local Render

-- Space or a click: next page, then the main action of the scene.
local function Continue()
	if not scene then return end
	if not IsLastPage() then
		scene.page = scene.page + 1
		pageAlpha = 0
		return Render()
	end
	local kind = scene.kind
	if kind == "QUEST_DETAIL" then
		if Clean(Safe(QuestGetAutoAccept)) then Safe(AcknowledgeAutoAcceptQuest) else Safe(AcceptQuest) end
	elseif kind == "QUEST_PROGRESS" then
		if scene.completable then Safe(CompleteQuest) else CloseConversation() end
	elseif kind == "QUEST_COMPLETE" then
		if scene.choiceCount <= 1 then Safe(GetQuestReward, scene.choiceCount) end
	elseif #scene.choices == 1 then
		GameSound("IG_QUEST_LIST_SELECT")
		scene.choices[1].action()
	elseif #scene.choices == 0 then
		CloseConversation()
	end
end

-- Escape or the second button: a quest offered is declined, the rest closed.
local function Leave()
	if not scene then return end
	GameSound("IG_QUEST_CANCEL")
	if scene.declinable then Safe(DeclineQuest) else CloseConversation() end
end

-- 1 to 9: a choice, or a reward to choose.
local function Choose(number)
	if not scene then return end
	if not IsLastPage() then
		-- The choices only show at the end: reach it first.
		scene.page = #scene.pages
		pageAlpha = 0
		return Render()
	end
	if scene.kind == "QUEST_COMPLETE" then
		if number <= (scene.choiceCount or 0) then Safe(GetQuestReward, number) end
		return
	end
	local choice = scene.choices[number]
	if choice then
		GameSound("IG_QUEST_LIST_SELECT")
		choice.action()
	end
end

-- Keys -------------------------------------------------------------------------------

local function BindKeys(bind)
	if InCombatLockdown() then return end
	Safe(ClearOverrideBindings, panel)
	if not bind then return end
	Safe(SetOverrideBindingClick, panel, true, "SPACE", "WandererSceneContinue")
	for number = 1, MAX_CHOICES do
		Safe(SetOverrideBindingClick, panel, true, tostring(number), "WandererSceneChoice" .. number)
	end
end

-- Pieces of the panel ----------------------------------------------------------------

local function StyleFont(object, size)
	local path = ns.Skin.FontPath(ns.db.label.font)
	if path then object:SetFont(path, size, "") end
end

local function SetIcon(texture, atlas, file)
	if atlas and U.HasAtlas(atlas) then
		texture:SetAtlas(atlas)
		texture:Show()
	elseif file then
		texture:SetTexture(file)
		texture:Show()
	else
		texture:Hide()
	end
end

-- A choice: a quiet row, a thin golden mark and light under the mouse.
local function ChoiceRow(index)
	local row = choiceRows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, panel)
	row:EnableMouse(true)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 0.82, 0, 0.07)
	row.hover:Hide()
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetColorTexture(1, 0.82, 0, 0.9)
	row.mark:SetWidth(2)
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.text = ns.Skin.CreateText(row, "GameTooltipText", 0.95, 0.92, 0.85)
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	if row.text.SetWordWrap then row.text:SetWordWrap(false) end
	row:SetScript("OnEnter", function(self) self.hover:Show() self.mark:Show() end)
	row:SetScript("OnLeave", function(self) self.hover:Hide() self.mark:Hide() end)
	row:SetScript("OnMouseUp", function(self, button) if button == "LeftButton" then Choose(self.number) end end)
	choiceRows[index] = row
	return row
end

-- An item: its icon with a thin border of its rarity, and its name.
local function RewardItem(index)
	local item = rewardItems[index]
	if item then return item end
	item = CreateFrame("Frame", nil, panel)
	item:EnableMouse(true)
	item.border = item:CreateTexture(nil, "BORDER")
	item.border:SetSize(REWARD_ICON + 2, REWARD_ICON + 2)
	item.border:SetPoint("LEFT")
	item.icon = item:CreateTexture(nil, "ARTWORK")
	item.icon:SetSize(REWARD_ICON, REWARD_ICON)
	item.icon:SetPoint("CENTER", item.border, "CENTER")
	item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	item.best = item:CreateTexture(nil, "OVERLAY")
	item.best:SetSize(14, 14)
	item.best:SetPoint("TOPRIGHT", item.border, "TOPRIGHT", 5, 5)
	item.best:SetTexture(BEST_TEXTURE)
	item.arrow = item:CreateTexture(nil, "OVERLAY")
	item.arrow:SetSize(14, 14)
	item.arrow:SetPoint("BOTTOMLEFT", item.border, "BOTTOMLEFT", -4, -4)
	item.price = ns.Skin.CreateText(item, "GameTooltipTextSmall", 0.7, 0.7, 0.7)
	item.price:SetJustifyH("RIGHT")
	item.price:SetPoint("RIGHT", item, "RIGHT", -4, 0)
	item.text = ns.Skin.CreateText(item, "GameTooltipTextSmall", 0.95, 0.92, 0.85)
	item.text:SetPoint("LEFT", item.border, "RIGHT", 8, 0)
	item.text:SetPoint("RIGHT", item.price, "LEFT", -6, 0)
	if item.text.SetWordWrap then item.text:SetWordWrap(false) end
	if item.price.SetWordWrap then item.price:SetWordWrap(false) end
	item:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		Safe(GameTooltip.SetQuestItem, GameTooltip, self.kind, self.index)
		if self.isBest then GameTooltip:AddLine(L.SCENE_BEST_VALUE, 1, 0.82, 0) end
		if self.compare and self.compare > 0 then
			GameTooltip:AddLine(L.SCENE_UPGRADE:format(self.compare), 0.4, 1, 0.4)
		elseif self.compare and self.compare < 0 then
			GameTooltip:AddLine(L.SCENE_DOWNGRADE:format(-self.compare), 1, 0.4, 0.4)
		end
		GameTooltip:Show()
	end)
	item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	item:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.number then Choose(self.number) end
	end)
	rewardItems[index] = item
	return item
end

-- A button drawn by the engine, like the panel: its text turns golden and its
-- border lights up under the mouse.
local function ActionButton(index)
	local button = actionButtons[index]
	if button then return button end
	local window, buttonSkin = ns.Skin.CreateWindow(nil, nil, panel)
	button = window
	button.skin = buttonSkin
	button:EnableMouse(true)
	button.text = ns.Skin.CreateText(button, "GameTooltipText", 0.95, 0.92, 0.85)
	button.text:SetPoint("CENTER")
	button.text:SetJustifyH("CENTER")
	button:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 0.82, 0)
		self.skin:SetHighlight("giver")
	end)
	button:SetScript("OnLeave", function(self)
		self.text:SetTextColor(0.95, 0.92, 0.85)
		self.skin:SetHighlight(nil)
	end)
	button:SetScript("OnMouseUp", function(self, mouse)
		if mouse == "LeftButton" and self.onClick then self.onClick() end
	end)
	actionButtons[index] = button
	return button
end

-- Layout -----------------------------------------------------------------------------

local function PanelWidth()
	local width = (UIParent:GetWidth() or 1280) * PANEL_WIDTH_SHARE
	return math.floor(math.max(PANEL_MIN_WIDTH, math.min(PANEL_MAX_WIDTH, width)))
end

local function Place(object, y, margin)
	object:ClearAllPoints()
	object:SetPoint("TOPLEFT", panel, "TOPLEFT", margin, -y)
end

Render = function()
	if not scene then return end
	local width = PanelWidth()
	local margin = ns.Skin.Margin() + 8
	local inner = width - margin * 2
	local y = margin
	local TEXT_SIZE = ns.db.scene.textSize or 15
	local NAME_SIZE, TITLE_SIZE = TEXT_SIZE + 3, TEXT_SIZE - 2
	StyleFont(nameText, NAME_SIZE)
	StyleFont(titleText, TITLE_SIZE)
	StyleFont(bodyText, TEXT_SIZE)

	-- Who speaks: its portrait in a round frame, its name, and the quest.
	local unit = scene.unit
	local top = y
	local textLeft, textWidth = margin, inner
	if unit then
		Safe(SetPortraitTexture, portrait, unit)
		portrait:ClearAllPoints()
		portrait:SetPoint("TOPLEFT", panel, "TOPLEFT", margin, -y)
		textLeft, textWidth = margin + PORTRAIT_SIZE + GAP, inner - PORTRAIT_SIZE - GAP
	end
	portrait:SetShown(unit ~= nil)
	-- The golden ring only when it can be cut round: never a square.
	portraitRing:SetShown(unit ~= nil and portraitRing.round or false)
	nameText:SetWidth(textWidth)
	if not pcall(nameText.SetText, nameText, scene.name or "") then nameText:SetText("") end
	local title = Clean(scene.title)
	titleText:SetWidth(textWidth)
	titleText:SetText(title or "")
	titleText:SetShown(title ~= nil)
	-- The name and the quest stand beside the portrait, centered on it.
	local textHeight = U.Measure(nameText, "GetStringHeight", NAME_SIZE)
		+ (title and (2 + U.Measure(titleText, "GetStringHeight", TITLE_SIZE)) or 0)
	local textTop = y + (unit and math.max(0, (PORTRAIT_SIZE - textHeight) / 2) or 0)
	Place(nameText, textTop, textLeft)
	if title then Place(titleText, textTop + U.Measure(nameText, "GetStringHeight", NAME_SIZE) + 2, textLeft) end
	y = math.max(textTop + textHeight, unit and (top + PORTRAIT_SIZE) or 0)
	y = y + SMALL_GAP
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", panel, "TOPLEFT", margin, -y)
	rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -margin, -y)
	y = y + 1 + GAP

	-- The words, page by page.
	bodyText:SetWidth(inner)
	if not pcall(bodyText.SetText, bodyText, scene.pages[scene.page] or "") then bodyText:SetText("") end
	bodyText:SetAlpha(pageAlpha)
	Place(bodyText, y, margin)
	y = y + U.Measure(bodyText, "GetStringHeight", TEXT_SIZE)

	local last = IsLastPage()

	-- Rewards, in two columns.
	for index, item in ipairs(rewardItems) do
		if not (last and scene.rewards[index]) then item:Hide() end
	end
	rewardsLabel:SetShown(last and scene.rewards[1] ~= nil)
	if last and scene.rewards[1] then
		y = y + GAP
		rewardsLabel:SetText(scene.kind == "QUEST_PROGRESS" and L.SCENE_REQUIRED or L.SCENE_REWARDS)
		Place(rewardsLabel, y, margin)
		y = y + U.Measure(rewardsLabel, "GetStringHeight", 12) + SMALL_GAP
		local column = math.floor((inner - GAP) / 2)
		local number = 0
		for index, reward in ipairs(scene.rewards) do
			local item = RewardItem(index)
			item.kind, item.index = reward.kind, reward.index
			item.number = nil
			if reward.kind == "choice" and scene.kind == "QUEST_COMPLETE" then
				number = number + 1
				item.number = number
			end
			item.icon:SetTexture(reward.texture)
			-- What this character cannot use: darkened, its name in red.
			if item.icon.SetDesaturated then item.icon:SetDesaturated(reward.unusable) end
			if reward.unusable then item.icon:SetVertexColor(1, 0.45, 0.45) else item.icon:SetVertexColor(1, 1, 1) end
			if reward.unusable then item.text:SetTextColor(unpack(UNUSABLE)) else item.text:SetTextColor(0.95, 0.92, 0.85) end
			item.isBest = reward.best
			item.compare = reward.compare
			if reward.compare and reward.compare ~= 0 then
				item.arrow:SetTexture(reward.compare > 0 and UP_TEXTURE or DOWN_TEXTURE)
				if reward.compare > 0 then item.arrow:SetVertexColor(0.3, 1, 0.3) else item.arrow:SetVertexColor(1, 0.3, 0.3) end
				item.arrow:Show()
			else
				item.arrow:Hide()
			end
			item.best:SetShown(reward.best and true or false)
			item.price:SetText(reward.price and reward.price > 0 and U.Coins(reward.price) or "")
			if reward.best then item.price:SetTextColor(1, 0.82, 0) else item.price:SetTextColor(0.7, 0.7, 0.7) end
			local r, g, b = 0.5, 0.5, 0.5
			if reward.quality and C_Item and C_Item.GetItemQualityColor then
				local qr, qg, qb = Safe(C_Item.GetItemQualityColor, reward.quality)
				if qr then r, g, b = qr, qg, qb end
			end
			item.border:SetColorTexture(r, g, b, 0.9)
			local label = reward.name .. (reward.count > 1 and (" x" .. reward.count) or "")
			if item.number then label = ("|cffffd100%d.|r %s"):format(item.number, label) end
			item.text:SetText(label)
			item:SetSize(column, REWARD_ICON + 4)
			item:ClearAllPoints()
			local col, line = (index - 1) % 2, math.floor((index - 1) / 2)
			item:SetPoint("TOPLEFT", panel, "TOPLEFT", margin + col * (column + GAP), -(y + line * (REWARD_ICON + 8)))
			item:Show()
		end
		y = y + math.ceil(#scene.rewards / 2) * (REWARD_ICON + 8)
	end
	local money = last and scene.money or ""
	moneyText:SetText(money)
	moneyText:SetShown(money ~= "")
	if money ~= "" then
		y = y + SMALL_GAP
		moneyText:SetWidth(inner)
		Place(moneyText, y, margin)
		y = y + U.Measure(moneyText, "GetStringHeight", 12)
	end

	-- Choices, one per line.
	for index, row in ipairs(choiceRows) do
		if not (last and scene.choices[index]) then row:Hide() end
	end
	if last and scene.choices[1] then
		y = y + GAP
		for index = 1, math.min(#scene.choices, MAX_CHOICES) do
			local choice = scene.choices[index]
			local row = ChoiceRow(index)
			row.number = index
			SetIcon(row.icon, choice.atlas, choice.icon)
			row.text:SetText(("|cffffd100%d.|r  %s"):format(index, Clean(choice.label) or "?"))
			row:SetSize(inner, CHOICE_HEIGHT)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", panel, "TOPLEFT", margin, -y)
			row:Show()
			y = y + CHOICE_HEIGHT + 2
		end
	end

	-- Buttons at the bottom right: the main action (Space), then leave (Escape).
	y = y + GAP
	local right = width - margin
	local function PlaceButton(button, label, key, onClick)
		button.text:SetText(label .. "   |cff808080" .. key .. "|r")
		local buttonWidth = U.Measure(button.text, "GetStringWidth", 80) + BUTTON_PADDING * 2
		button:SetSize(buttonWidth, BUTTON_HEIGHT)
		button:ClearAllPoints()
		button:SetPoint("TOPRIGHT", panel, "TOPLEFT", right, -y)
		button.onClick = onClick
		button.skin:Layout()
		button:Show()
		right = right - buttonWidth - SMALL_GAP
	end
	local main = not last and L.SCENE_NEXT or scene.action
	if main then PlaceButton(ActionButton(1), main, L.SCENE_KEY_SPACE, Continue) else ActionButton(1):Hide() end
	PlaceButton(ActionButton(2), scene.declinable and L.SCENE_DECLINE or L.SCENE_CLOSE, L.SCENE_KEY_ESCAPE, Leave)
	-- When something is to be chosen, the number keys are recalled on the left.
	local choosing = last and (scene.choices[1] ~= nil or (scene.choiceCount or 0) > 1)
	keysText:SetText(choosing and L.SCENE_KEYS_CHOOSE or "")
	keysText:SetWidth(math.max(right - margin - SMALL_GAP, 40))
	keysText:ClearAllPoints()
	keysText:SetPoint("LEFT", panel, "TOPLEFT", margin, -(y + BUTTON_HEIGHT / 2))
	y = y + BUTTON_HEIGHT + margin

	-- The panel grows with its content, within the screen.
	local maxHeight = (UIParent:GetHeight() or 720) * PANEL_MAX_HEIGHT_SHARE
	panel:SetScale(ns.Skin.Scale())
	panel:SetSize(width, math.min(y, maxHeight))
	skin:Layout()
end

-- Scene ------------------------------------------------------------------------------

local function Begin(event)
	sceneToken = sceneToken + 1
	local first = not scene
	scene = Build(event)
	pageAlpha = first and 1 or 0
	ns.sceneActive = true
	if ns.RefreshCinema then ns.RefreshCinema() end
	if first then
		appear, target = 0, 1
		panel:SetAlpha(0)
		panel:Show()
		BindKeys(true)
		GameSound("IG_QUEST_LIST_OPEN")
	end
	Render()
end

local function Finish(closeConversation)
	if not scene then return end
	if closeConversation then CloseConversation() end
	scene = nil
	ns.sceneActive = false
	GameSound("IG_QUEST_LIST_CLOSE")
	if ns.RefreshCinema then ns.RefreshCinema() end
	BindKeys(false)
	GameTooltip:Hide()
	-- The panel fades away (OnUpdate hides it).
	target = 0
end

-- The game closed the conversation: a new page of it may come right after
-- (a quest chosen in a dialogue, a choice that goes back), so the scene waits:
-- a moment, longer while you still face the character (the next page can
-- take a while to come), so the interface never comes back between two pages. A dialogue's
-- end never closes a quest shown after it, and the other way round.
local NEXT_PAGE_STEP = 0.15 -- seconds
local NEXT_PAGE_WAIT = 1.5 -- at most, while still facing the character

local function OnClosed(event)
	local gossip = event == "GOSSIP_CLOSED"
	if not scene then
		-- Answered at once (Comfort): the scene planned is not shown.
		sceneToken = sceneToken + 1
		planned = nil
		return
	end
	-- A page of the other kind closed before its scene appeared: dropped.
	if planned and (planned == "GOSSIP_SHOW") == gossip then
		sceneToken = sceneToken + 1
		planned = nil
	end
	if gossip ~= (scene.kind == "GOSSIP_SHOW") then return end
	sceneToken = sceneToken + 1
	local token = sceneToken
	local waited = 0
	local function Wait()
		if sceneToken ~= token then return end
		waited = waited + NEXT_PAGE_STEP
		local talking = Clean(Safe(UnitExists, "npc")) or Clean(Safe(UnitExists, "questnpc"))
		if talking and waited < NEXT_PAGE_WAIT then return C_Timer.After(NEXT_PAGE_STEP, Wait) end
		Finish(false)
	end
	C_Timer.After(NEXT_PAGE_STEP, Wait)
end

local function Wanted()
	local db = ns.db
	return db and db.enabled and db.scene.enabled and not InCombatLockdown() and not U.IsSkipping()
end

local function OnEvent(_, event, ...)
	if event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then return OnClosed(event) end
	-- The game took the quest (or its reward): its page is over.
	if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
		local kinds = event == "QUEST_ACCEPTED" and { QUEST_DETAIL = true } or { QUEST_PROGRESS = true, QUEST_COMPLETE = true }
		if planned and kinds[planned] then
			sceneToken = sceneToken + 1
			planned = nil
		end
		if scene and kinds[scene.kind] then Finish(false) end
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" then
		if scene and scene.waitingPrices then
			scene.waitingPrices = Prices(scene.rewards)
			Render()
		end
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		-- A fight: the keys and the camera are given back at once, and the
		-- game's windows hear their events themselves until it ends. Opened
		-- by Wanderer in a fight, they would be refused by the game and the
		-- conversation would stay stuck.
		if scene then Finish(true) end
		SetTaken(false)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then return ns.RefreshScene() end
	-- Scenes off: the game's windows hear their events themselves.
	if not taken then return end
	if GameHandlesAlone(event, ...) then
		if scene then Finish(false) end
		return Relay(event, ...)
	end
	if Wanted() then
		-- The game fills its data first; an automatic answer (Comfort) may
		-- also come before: the scene shows only if nothing moved on.
		local token = sceneToken + 1
		sceneToken = token
		planned = event
		C_Timer.After(0, function()
			if sceneToken == token then
				planned = nil
				sceneToken = token - 1
				-- Answered by itself (quests accepted and handed in by
				-- themselves): nothing to show.
				if ns.WasAnswered and ns.WasAnswered(event) then
					if scene then Finish(false) end
					return
				end
				Begin(event)
			end
		end)
	else
		if scene then Finish(false) end
		Relay(event, ...)
	end
end

-- A game window still open (from a fight, or Shift): Wanderer takes the
-- events back once it closes, never in the middle of its conversation.
local function GameWindowOpen()
	for _, name in ipairs({ "GossipFrame", "QuestFrame" }) do
		local window = _G[name]
		if window and window.IsShown and window:IsShown() then return true end
	end
	return false
end

local retryPending = false

function ns.RefreshScene()
	local db = ns.db
	local wanted = db.enabled and db.scene.enabled and not InCombatLockdown() and true or false
	if wanted and not taken and GameWindowOpen() then
		if not retryPending then
			retryPending = true
			C_Timer.After(0.5, function()
				retryPending = false
				ns.RefreshScene()
			end)
		end
		return
	end
	SetTaken(wanted)
	if not taken and scene then Finish(true) end
end

-- Motion: the panel rises softly as it appears, the page fades in.
local function Ease(t) return 1 - (1 - t) ^ 3 end

-- A scene with a character whose dialogue ended without a word from the game
-- (gone, out of reach): it fades away by itself.
local LOST_AFTER = 0.5
local lostFor = 0
local function StillTalking(elapsed)
	if not (scene and scene.unit) then lostFor = 0 return end
	if Clean(Safe(UnitExists, "npc")) or Clean(Safe(UnitExists, "questnpc")) then
		lostFor = 0
	else
		lostFor = lostFor + elapsed
		if lostFor > LOST_AFTER then
			lostFor = 0
			Finish(false)
		end
	end
end

local function OnUpdate(self, elapsed)
	StillTalking(elapsed)
	if appear ~= target then
		local step = elapsed / (target > appear and APPEAR or DISAPPEAR)
		appear = target > appear and math.min(target, appear + step) or math.max(target, appear - step)
		local eased = Ease(appear)
		self:SetAlpha(eased)
		self:ClearAllPoints()
		self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, PANEL_BOTTOM - RISE * (1 - eased))
	end
	-- Gone (even if it closed before it had begun to appear).
	if appear <= 0 and target == 0 then
		self:Hide()
		return
	end
	if pageAlpha < 1 then
		pageAlpha = math.min(1, pageAlpha + elapsed / PAGE_FADE)
		bodyText:SetAlpha(pageAlpha)
	end
end

-- Construction -----------------------------------------------------------------------

function ns.InitScene()
	panel, skin = ns.Skin.CreateWindow("WandererScene", "DIALOG")
	panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, PANEL_BOTTOM)
	panel:EnableMouse(true)
	panel:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then Continue() end end)
	-- Portrait: round, with a thin golden ring.
	portrait = panel:CreateTexture(nil, "ARTWORK")
	portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portraitRing = panel:CreateTexture(nil, "BORDER")
	portraitRing:SetSize(PORTRAIT_SIZE + 4, PORTRAIT_SIZE + 4)
	portraitRing:SetPoint("CENTER", portrait, "CENTER")
	-- A white file tinted gold, cut round by a mask texture (the game's
	-- current way: masks only cut texture files, never plain colors).
	portraitRing:SetTexture(RING_TEXTURE)
	portraitRing:SetVertexColor(1, 0.82, 0, 0.55)
	portraitRing.round = ns.Skin.RoundMask(panel, portraitRing)
	portrait.round = ns.Skin.RoundMask(panel, portrait)
	nameText = ns.Skin.CreateText(panel, "GameTooltipHeaderText", 1, 0.82, 0)
	titleText = ns.Skin.CreateText(panel, "GameTooltipText", 0.9, 0.8, 0.55)
	rule = panel:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.25)
	rule:SetHeight(1)
	bodyText = ns.Skin.CreateText(panel, "GameTooltipText", 0.95, 0.92, 0.85)
	rewardsLabel = ns.Skin.CreateText(panel, "GameTooltipTextSmall", 0.75, 0.68, 0.5)
	moneyText = ns.Skin.CreateText(panel, "GameTooltipTextSmall", 0.95, 0.92, 0.85)
	keysText = ns.Skin.CreateText(panel, "GameTooltipTextSmall", 0.55, 0.55, 0.55)
	if keysText.SetWordWrap then keysText:SetWordWrap(false) end
	-- Buttons the borrowed keys click.
	local continue = CreateFrame("Button", "WandererSceneContinue", panel)
	continue:SetScript("OnClick", Continue)
	for number = 1, MAX_CHOICES do
		local button = CreateFrame("Button", "WandererSceneChoice" .. number, panel)
		button:SetScript("OnClick", function() Choose(number) end)
	end
	-- Escape closes the scene and the conversation.
	if UISpecialFrames then table.insert(UISpecialFrames, "WandererScene") end
	panel:SetScript("OnHide", function() if scene then Finish(true) end end)
	panel:SetScript("OnUpdate", OnUpdate)
	panel:SetScript("OnEvent", OnEvent)
	for event in pairs(SHOW_EVENTS) do panel:RegisterEvent(event) end
	panel:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	-- Should a game window show anyway, the scene steps aside: never both.
	for _, name in ipairs({ "GossipFrame", "QuestFrame" }) do
		local window = _G[name]
		if window and window.HookScript then
			window:HookScript("OnShow", function()
				if scene and not relaying then
					if ns.debug then ns.Print("scene: " .. name .. " shown by the game") end
					Finish(false)
				end
			end)
		end
	end
	for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "QUEST_ACCEPTED", "QUEST_TURNED_IN" }) do
		panel:RegisterEvent(event)
	end
	ns.RefreshScene()
end
