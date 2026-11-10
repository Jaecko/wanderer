local _, ns = ...
local L = ns.L

-- Conversations as quiet scenes. When you talk to a character, the
-- interface fades away and its words appear in a panel at the bottom of the
-- screen, drawn in your predefined style (or, if asked, on parchment), page
-- by page. Choices, quests and their rewards stay in the same panel. (The
-- camera: Camera.lua.)
--
-- Buttons at the bottom of the panel continue, accept or close; the same
-- with the keys during a scene: Space continues (and accepts), 1 to 9 choose,
-- Escape (or a right click) closes, the mouse wheel (or a click on its hint)
-- goes back to what was said before, never a movement key; a click on the
-- text continues. A reward is
-- chosen in two steps: picked (1 to 9, a click, Tab for the next), then taken
-- with Space. A turn-in that costs gold is never paid by a hurried Space: a
-- click, or Space after a short moment. The keys are borrowed only during the
-- scene and never in a fight. Holding Shift while talking, or a fight, opens
-- the game's own window instead. Another addon that shows conversations
-- (DialogueUI): the scenes step aside entirely.
--
-- The panel is placed with Wanderer's placing mode, its background's opacity
-- chosen; the choices already read show dimmed, never hidden.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local Gossip = C_GossipInfo or {}

-- Look and motion
local PANEL_WIDTH_SHARE, PANEL_MAX_WIDTH, PANEL_MIN_WIDTH = 0.5, 760, 460
local PANEL_BOTTOM = 110 -- above the bottom of the screen

local RISE = 14 -- pixels the panel rises while it appears
local APPEAR, DISAPPEAR, PAGE_FADE = 0.7, 0.5, 0.4
local GAP, SMALL_GAP = 12, 6
local CHOICE_HEIGHT, REWARD_ICON = 24, 30
local BEST_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
local UP_TEXTURE, DOWN_TEXTURE = "Interface\\Buttons\\Arrow-Up-Up", "Interface\\Buttons\\Arrow-Down-Up"
-- An object (a wanted poster, a board, a book) speaks: a written note in the round frame, never the game's
-- black disc. An item that begins a quest: its own icon.
local OBJECT_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local BUTTON_HEIGHT, BUTTON_PADDING = 26, 14
local PORTRAIT_SIZE = 52
local RING_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MAX_CHOICES = 9
local PAGE_CHARS = 260 -- about two or three sentences
local NAME_ON_BUTTON = 28 -- letters of a reward's name on the button that takes it
-- A turn-in that costs gold: Space works only after this many seconds (longer for a large share of your money).
local LOCK_SHORT, LOCK_LONG, LOCK_SHARE = 1, 3, 0.1

-- Events the game's windows listen to, that Wanderer takes when scenes are on.
-- The game's dialogues are opened by a manager (CustomGossipFrameManager),
-- not by the gossip window itself; older games: the window.
local SHOW_EVENTS = {
	GOSSIP_SHOW = { "CustomGossipFrameManager", "GossipFrame" }, QUEST_GREETING = { "QuestFrame" },
	QUEST_DETAIL = { "QuestFrame" }, QUEST_PROGRESS = { "QuestFrame" }, QUEST_COMPLETE = { "QuestFrame" },
}
-- Pages of a quest itself (Spoken can read them again from here).
local QUEST_PAGES = { QUEST_DETAIL = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true }

local QUEST_ICONS = {
	available = { atlas = "QuestNormal", texture = "Interface\\GossipFrame\\AvailableQuestIcon" },
	complete = { atlas = "QuestTurnin", texture = "Interface\\GossipFrame\\ActiveQuestIcon" },
	active = { atlas = "QuestActive", texture = "Interface\\GossipFrame\\IncompleteQuestIcon" },
}

-- Colors on the dark look and on parchment, by role.
local DARK = {
	text = { 0.95, 0.92, 0.85 }, name = { 1, 0.82, 0 }, title = { 0.9, 0.8, 0.55 }, label = { 0.75, 0.68, 0.5 },
	muted = { 0.62, 0.6, 0.54 }, keys = { 0.7, 0.7, 0.7 }, price = { 0.7, 0.7, 0.7 }, accent = { 1, 0.82, 0 },
	unusable = { 1, 0.32, 0.32 }, done = { 0.4, 0.87, 0.4 }, open = { 0.93, 0.93, 0.93 },
	rule = { 1, 0.82, 0, 0.25 }, hover = { 1, 0.82, 0, 0.07 }, picked = { 1, 0.82, 0, 0.14 }, mark = { 1, 0.82, 0, 0.9 },
	ring = { 1, 0.82, 0, 0.55 },
}
local PAPER = {
	text = { 0.2, 0.13, 0.07 }, name = { 0.42, 0.15, 0.05 }, title = { 0.34, 0.22, 0.1 }, label = { 0.38, 0.28, 0.15 },
	muted = { 0.45, 0.37, 0.27 }, keys = { 0.42, 0.35, 0.26 }, price = { 0.36, 0.28, 0.18 }, accent = { 0.5, 0.27, 0.03 },
	unusable = { 0.62, 0.12, 0.08 }, done = { 0.1, 0.4, 0.12 }, open = { 0.2, 0.13, 0.07 },
	rule = { 0.35, 0.22, 0.08, 0.35 }, hover = { 0.35, 0.2, 0.05, 0.08 }, picked = { 0.45, 0.26, 0.05, 0.16 },
	mark = { 0.45, 0.26, 0.05, 0.85 }, ring = { 0.3, 0.19, 0.07, 0.75 },
}

local panel, skin, portrait, portraitRing, nameText, titleText, rule, saidText, bodyText, rewardsLabel, moneyText, keysText
local replayLink, keysLink
local PlacePanel
local choiceRows, rewardItems, actionButtons = {}, {}, {}
local scene -- { kind, name, title, pages, page, choices, rewards, money, action, ... }
local said -- your words just chosen, shown over the character's answer
local taker -- the game's windows kept from the show events while scenes are on (Util.EventTaker)
local appear, target = 0, 0 -- panel's appearance: current and wanted (0 to 1)
local pageAlpha = 1
local sceneToken = 0
local planned -- the event of the scene planned for the next frame
local paper = false -- drawn on parchment

-- Another addon showing conversations or books ----------------------------------------

-- DialogueUI (or Immersion) shows the conversations: Wanderer's scenes, their keys, the music lowered and
-- the camera never start. what: "scenes" or "books". The compatibility rules decide when they exist.
local REPLACERS = { scenes = { "DialogueUI", "Immersion" }, books = { "DialogueUI" } }
function ns.StepsAside(what)
	if ns.Yields then return ns.Yields(what) and true or false end
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
	for _, name in ipairs(REPLACERS[what] or {}) do
		if loaded and Clean(Safe(loaded, name)) then return true end
	end
	return false
end
function ns.SceneYielded() return ns.StepsAside("scenes") end

-- Spoken voices the conversations: its voice plays as usual, its words read again from the scene's quest.
function ns.SpokenLoaded() return rawget(_G, "Spoken") ~= nil end
local function SpokenReread()
	local read = SlashCmdList and SlashCmdList.SPOKENQUESTSREAD
	return ns.SpokenLoaded() and type(read) == "function" and read or nil
end

-- Colors ------------------------------------------------------------------------------

-- The parchment look of the scenes, and of the reader with them.
local function Paper()
	local db = ns.db
	return db and db.scene and db.scene.parchment == true or false
end
ns.ScenePaper = Paper
local function C(role) return (paper and PAPER or DARK)[role] end
local function Hex(role)
	local c = C(role)
	return U.ColorCode(c[1], c[2], c[3])
end
local function Paint(text, role)
	local c = C(role)
	text:SetTextColor(c[1], c[2], c[3])
	text:SetShadowColor(0, 0, 0, paper and 0 or 0.9)
end
-- A color of the game (a quest's level) as ink on parchment: darker.
local function Tone(r, g, b)
	if paper then return r * 0.55, g * 0.55, b * 0.55 end
	return r, g, b
end

-- Game's windows ---------------------------------------------------------------------

local function Owner(event)
	for _, name in ipairs(SHOW_EVENTS[event]) do
		if _G[name] then return _G[name] end
	end
end

-- A frame of the game's conversation windows (the window or one of its parts).
local function IsGameWindow(frame)
	if frame.IsForbidden and frame:IsForbidden() then return false end
	local name = frame.GetName and frame:GetName()
	if name and issecurevariable and not issecurevariable(name) then return false end
	local depth = 0
	while frame and depth < 8 do
		if frame == _G.GossipFrame or frame == _G.QuestFrame or frame == _G.CustomGossipFrameManager then return true end
		local ok, parent = pcall(frame.GetParent, frame)
		frame = ok and parent or nil
		depth = depth + 1
	end
	return false
end

do
	local events = {}
	for event in pairs(SHOW_EVENTS) do events[#events + 1] = event end
	taker = U.EventTaker(events, Owner, IsGameWindow)
end
-- Quests the game takes care of without any window (as its own quest window
-- does): accepted on entering a place, from the adventure map. They go
-- straight to the game. (A quest begun by an item has its scene, the item's
-- picture in the round frame.)
local function GameHandlesAlone(event)
	if event ~= "QUEST_DETAIL" then return false end
	if QuestIsFromAdventureMap and Clean(Safe(QuestIsFromAdventureMap)) then return true end
	return Clean(Safe(QuestGetAutoAccept)) and QuestIsFromAreaTrigger and Clean(Safe(QuestIsFromAreaTrigger)) and true or false
end

-- Scenes on: Wanderer listens instead of the game's windows; off: given back.
local function SetTaken(take) taker:Take(take) end

-- A game window still open (from a fight, or Shift): Wanderer takes the
-- events back once it closes, never in the middle of its conversation.
local function GameWindowOpen()
	for _, name in ipairs({ "GossipFrame", "QuestFrame" }) do
		local window = _G[name]
		if window and window.IsShown and window:IsShown() then return true end
	end
	return false
end

-- The game's own window shows the conversation (Shift, fight...). With a controller, that window opened from
-- here would leave the game's actions blocked for the session: the conversation is closed instead.
local function Relay(event, ...)
	if U.UsingPad() and not GameHandlesAlone(event) and not GameWindowOpen() then
		if event == "GOSSIP_SHOW" then Safe(Gossip.CloseGossip) else Safe(CloseQuest) end
		return
	end
	taker:Relay(event, ...)
end

-- Text -------------------------------------------------------------------------------

-- Pages of whole sentences, about PAGE_CHARS long. A sentence is a run of
-- words with its ending marks; line breaks separate sentences too. Only
-- plain ASCII marks are used: accented letters are never cut.
local function Sentences(text)
	local list = {}
	for sentence in text:gmatch("[^%.!%?\n]+[%.!%?]*") do
		sentence = strtrim(sentence)
		if sentence ~= "" then list[#list + 1] = sentence end
	end
	return list
end

local function Pages(text)
	if U.IsSecret(text) then return { text } end
	text = Clean(text)
	if not text then return { "" } end
	local pages, current = {}, ""
	for _, sentence in ipairs(Sentences(text)) do
		if current ~= "" and #current + #sentence > PAGE_CHARS then
			pages[#pages + 1] = current
			current = sentence
		else
			current = current == "" and sentence or (current .. " " .. sentence)
		end
	end
	if current ~= "" then pages[#pages + 1] = current end
	if not pages[1] then pages[1] = text end
	return pages
end

-- A page Spoken reads aloud: the sentence being read in the text's color, the others quieter.
-- A page that is not plain sentences (a link, a color, one cut otherwise) stays as it is.
local function Voiced(text, current)
	if type(text) ~= "string" or U.IsSecret(text) or text:find("|", 1, true) then return text end
	local sentences = Sentences(text)
	if not sentences[current] or table.concat(sentences, " ") ~= text then return text end
	local quiet = Hex("muted")
	for index, sentence in ipairs(sentences) do
		if index ~= current then sentences[index] = quiet .. sentence .. "|r" end
	end
	return table.concat(sentences, " ")
end

-- At most a number of letters (never a letter cut in two), "..." after.
local function Short(text, most)
	if type(text) ~= "string" or U.IsSecret(text) then return "" end
	local count, cut = 0, nil
	for position in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
		count = count + 1
		if count > most then cut = position break end
	end
	return cut and (text:sub(1, cut - 1) .. "...") or text
end

local function IsLastPage() return scene and scene.page >= #scene.pages end

-- Choices already read -----------------------------------------------------------------

-- The dialogue options chosen and the quests offered that this character already opened: shown dimmed the
-- next time, never hidden, at their place. Forgotten after a few months, a few thousand at most.
local SEEN_DAYS, SEEN_MOST = 120, 4000
local SEEN_ALPHA = 0.55

local function SeenList()
	local root = ns.root
	if not root then return {} end
	local mine = ns.Mine()
	mine.seenChoices = type(mine.seenChoices) == "table" and mine.seenChoices or {}
	-- (until 1.3, one list for the whole account: given once to the character playing then, and gone)
	if type(root.seenChoices) == "table" then
		for key, day in pairs(root.seenChoices) do
			if mine.seenChoices[key] == nil then mine.seenChoices[key] = day end
		end
	end
	root.seenChoices = nil
	return mine.seenChoices
end

local function Today() return math.floor((time and time() or 0) / 86400) end

function ns.ChoiceSeen(key) return key ~= nil and SeenList()[key] ~= nil end
local function MarkSeen(key)
	if key then SeenList()[key] = Today() end
end

-- The old ones forgotten (at each login): too old, or the oldest beyond the most kept.
local function ForgetOldSeen()
	local list, today, count = SeenList(), Today(), 0
	for key, day in pairs(list) do
		if type(day) ~= "number" or today - day > SEEN_DAYS then list[key] = nil else count = count + 1 end
	end
	if count <= SEEN_MOST then return end
	local keys = {}
	for key in pairs(list) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return list[a] < list[b] end)
	for index = 1, count - SEEN_MOST do list[keys[index]] = nil end
end

-- The character's number in its GUID (a dialogue option is known with the one who offers it).
local function NpcID(guid)
	return type(guid) == "string" and guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)") or nil
end

-- Content ----------------------------------------------------------------------------

-- A quest in the choices, its title colored by its level as the quest log does.
local function QuestChoice(title, questID, level, trivial, icon, action)
	return { label = title and (title .. (ns.QuestChoiceTag(questID) or "")), level = Clean(level),
		trivial = trivial and true or false, atlas = icon.atlas, icon = icon.texture, action = action }
end

-- Choices of the conversation: { label, icon, atlas, action, level, trivial, said, seen }. The quests your
-- level makes grey come last. seen: its key in the choices already read (offered quests and options).
local function GossipChoices(guid)
	local choices, grey = {}, {}
	local npc = NpcID(guid)
	for _, quest in ipairs(Safe(Gossip.GetActiveQuests) or {}) do
		choices[#choices + 1] = QuestChoice(quest.title, quest.questID, quest.questLevel, false,
			quest.isComplete and QUEST_ICONS.complete or QUEST_ICONS.active,
			function() Safe(Gossip.SelectActiveQuest, quest.questID) end)
	end
	for _, quest in ipairs(Safe(Gossip.GetAvailableQuests) or {}) do
		local trivial = Clean(quest.isTrivial) and true or false
		local list = trivial and grey or choices
		local choice = QuestChoice(quest.title, quest.questID, quest.questLevel, trivial, QUEST_ICONS.available,
			function() Safe(Gossip.SelectAvailableQuest, quest.questID) end)
		local id = Clean(quest.questID)
		choice.seen = type(id) == "number" and ("q" .. id) or nil
		list[#list + 1] = choice
	end
	local options = Safe(Gossip.GetOptions) or {}
	table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
	for _, option in ipairs(options) do
		local id = Clean(option.gossipOptionID)
		choices[#choices + 1] = { label = option.name, icon = option.icon, said = true,
			seen = npc and type(id) == "number" and ("o" .. npc .. ":" .. id) or nil,
			action = function() Safe(Gossip.SelectOption, option.gossipOptionID) end }
	end
	for _, choice in ipairs(grey) do choices[#choices + 1] = choice end
	return choices
end

local function GreetingChoices()
	local choices, grey = {}, {}
	for index = 1, (Clean(Safe(GetNumActiveQuests)) or 0) do
		local title, complete = Safe(GetActiveTitle, index)
		choices[#choices + 1] = QuestChoice(title, nil, Safe(GetActiveLevel, index), false,
			complete and QUEST_ICONS.complete or QUEST_ICONS.active, function() Safe(SelectActiveQuest, index) end)
	end
	for index = 1, (Clean(Safe(GetNumAvailableQuests)) or 0) do
		local trivial = Clean((Safe(GetAvailableQuestInfo, index))) and true or false
		local list = trivial and grey or choices
		list[#list + 1] = QuestChoice(Safe(GetAvailableTitle, index), nil, Safe(GetAvailableLevel, index), trivial,
			QUEST_ICONS.available, function() Safe(SelectAvailableQuest, index) end)
	end
	for _, choice in ipairs(grey) do choices[#choices + 1] = choice end
	return choices
end

-- Items of the quest shown: { kind, index, name, texture, count, quality }.
-- A reward's name: the game's, else the one in its link; nil while the game is still fetching it
-- (it comes a moment later: GET_ITEM_INFO_RECEIVED, the scene drawn again then).
local function RewardName(kind, index)
	local name = Clean((Safe(GetQuestItemInfo, kind, index)))
	if name then return name end
	local link = Clean(Safe(GetQuestItemLink, kind, index))
	return U.LinkName(link)
end

local function Rewards(required)
	local rewards = {}
	local function add(kind, count)
		for index = 1, count do
			local name, texture, amount, quality, usable = Safe(GetQuestItemInfo, kind, index)
			if name ~= nil or texture ~= nil then
				local known = RewardName(kind, index)
				rewards[#rewards + 1] = { kind = kind, index = index, name = known or "", waiting = known == nil,
					texture = Clean(texture), count = Clean(amount) or 1, quality = Clean(quality),
					unusable = Clean(usable) == false }
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

-- Item level of the reward against what is worn in its place (the weakest of
-- two rings or trinkets; a weapon: what it would replace in the main hand): positive is better. Nil when it
-- does not compare.
local PAIRS = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }
local function Compare(reward, link)
	if reward.unusable or not link then return end
	local kind = U.ItemEquipKind(link)
	local slots = kind and U.EQUIP_SLOTS[kind]
	local level = slots and U.ItemLevel(link)
	if not level then return end
	local worn
	for index = 1, PAIRS[kind] and #slots or 1 do
		local wornLink = Clean(Safe(GetInventoryItemLink, "player", slots[index]))
		local wornLevel = wornLink and U.ItemLevel(wornLink) or 0
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
			local price = U.SellPrice(itemLink)
			if itemLink and not price then
				missing = true
				U.LoadItem(itemLink)
			end
			reward.price = price
			-- (the most gold for the whole reward: five potions against one sword)
			local worth = price and price * (reward.count or 1)
			if worth and worth > bestPrice then best, bestPrice = reward, worth end
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
	local lines = { Hex("accent") .. L.SCENE_OBJECTIVES .. "|r" }
	for _, objective in ipairs(list) do
		local text = Clean(objective.text)
		if text then
			lines[#lines + 1] = Hex(Clean(objective.finished) and "done" or "open") .. "-  " .. text .. "|r"
		end
	end
	return lines[2] and table.concat(lines, "\n") or nil
end

-- What speaks is an object (a poster, a board) or an item, not a character.
local function IsThing(guid)
	return type(guid) == "string" and (guid:find("^GameObject") ~= nil or guid:find("^Item") ~= nil)
end

local function Build(event, startItem)
	paper = Paper()
	local unit = Clean(Safe(UnitExists, "questnpc")) and "questnpc" or (Clean(Safe(UnitExists, "npc")) and "npc" or nil)
	local s = { kind = event, unit = unit, name = unit and Safe(UnitName, unit), page = 1, choices = {}, rewards = {} }
	s.guid = unit and Clean(Safe(UnitGUID, unit)) or nil
	if type(s.guid) ~= "string" then s.guid = nil end
	if IsThing(s.guid) then s.icon = OBJECT_ICON end
	if event == "GOSSIP_SHOW" then
		s.pages = Pages(Safe(Gossip.GetText))
		s.choices = GossipChoices(s.guid)
	elseif event == "QUEST_GREETING" then
		s.pages = Pages(Safe(GetGreetingText))
		s.choices = GreetingChoices()
	elseif event == "QUEST_DETAIL" then
		-- A quest begun by an item: the item in the round frame, its name above the words.
		startItem = Clean(startItem)
		if type(startItem) == "number" and startItem > 0 then
			s.item = startItem
			s.icon = U.ItemIcon(startItem) or OBJECT_ICON
			s.itemKnown = U.ItemName(startItem) ~= nil
			s.name = U.ItemName(startItem) or s.name
			if not s.itemKnown then U.LoadItem(startItem) end
		end
		s.title = Safe(GetTitleText)
		-- Elite, a group advised: said under the title, before you say yes.
		s.tag = ns.QuestSceneTag(Clean(Safe(GetQuestID)))
		s.pages = Pages(Safe(GetQuestText))
		local objectives = Clean(Safe(GetObjectiveText))
		if objectives then s.pages[#s.pages + 1] = Hex("accent") .. L.SCENE_OBJECTIVES .. "|r " .. objectives end
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
		s.cost = Clean(Safe(GetQuestMoneyToGet)) or 0
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

-- Actions ----------------------------------------------------------------------------

-- The game's own sounds play as its dialogue and quest windows play them
-- (they are kept closed while the scene shows): open, close, a choice, a
-- refusal.

local function CloseConversation()
	if scene and scene.kind == "GOSSIP_SHOW" then
		Safe(Gossip.CloseGossip)
	else
		Safe(CloseQuest)
	end
end

local Render

-- A choice made: your words (a plain choice, not a quest) are kept for the answer's page.
local function Pick(choice)
	U.PlaySound("IG_QUEST_LIST_SELECT")
	local label = choice.said and Clean(choice.label)
	said = type(label) == "string" and U.PlainText(label) or nil
	MarkSeen(choice.seen)
	choice.action()
end

-- A turn-in that costs gold, still too fresh for Space.
local function Locked()
	return scene ~= nil and scene.lockUntil ~= nil and GetTime() < scene.lockUntil
end
local function LockTime(cost)
	local money = Clean(Safe(GetMoney)) or 0
	return (money <= 0 or cost > money * LOCK_SHARE) and LOCK_LONG or LOCK_SHORT
end

-- A reward picked (not taken yet): its line lit, the others dimmed, its tooltip shown.
local ShowRewardTip
local function Select(number)
	if not (scene and number and number >= 1 and number <= (scene.choiceCount or 0)) then return end
	scene.selected = number
	U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	Render()
	for _, item in ipairs(rewardItems) do
		if item:IsShown() and item.number == number then ShowRewardTip(item) end
	end
end

-- Tab: the next reward picked.
local function Cycle()
	if not (scene and scene.kind == "QUEST_COMPLETE" and (scene.choiceCount or 0) > 1 and IsLastPage()) then return end
	Select((scene.selected or 0) % scene.choiceCount + 1)
end

-- Space or a click: next page, then the main action of the scene. deliberate:
-- the button itself was clicked (a turn-in that costs gold is paid at once).
local function Continue(deliberate)
	if not scene then return end
	-- Looking back: to what is said now.
	if scene.back then
		scene.back = false
		pageAlpha = 0
		return Render()
	end
	if not IsLastPage() then
		scene.page = scene.page + 1
		pageAlpha = 0
		return Render()
	end
	local kind = scene.kind
	if kind == "QUEST_DETAIL" then
		if Clean(Safe(QuestGetAutoAccept)) then Safe(AcknowledgeAutoAcceptQuest) else Safe(AcceptQuest) end
	elseif kind == "QUEST_PROGRESS" then
		if not scene.completable then return CloseConversation() end
		-- Gold asked: never paid by a Space pressed in a hurry.
		if (scene.cost or 0) > 0 and deliberate ~= true and Locked() then
			scene.warned = true
			return Render()
		end
		Safe(CompleteQuest)
	elseif kind == "QUEST_COMPLETE" then
		if scene.choiceCount <= 1 then
			Safe(GetQuestReward, scene.choiceCount)
		elseif scene.selected then
			Safe(GetQuestReward, scene.selected)
		end
	elseif #scene.choices == 1 then
		Pick(scene.choices[1])
	elseif #scene.choices == 0 then
		CloseConversation()
	end
end

-- Up arrow or the wheel: the page before, then what the character said before your words.
local function Back()
	if not scene or scene.back then return end
	if scene.page > 1 then
		scene.page = scene.page - 1
	elseif scene.previous then
		scene.back = true
	else
		return
	end
	pageAlpha = 0
	Render()
end

-- Escape, a right click or the second button: a quest offered is declined, the rest closed.
local function Leave()
	if not scene then return end
	U.PlaySound("IG_QUEST_CANCEL")
	if scene.declinable then Safe(DeclineQuest) else CloseConversation() end
end

-- 1 to 9: a choice, or a reward to pick.
local function Choose(number)
	if not scene then return end
	if scene.back or not IsLastPage() then
		-- The choices only show at the end: reach it first.
		scene.back = false
		scene.page = #scene.pages
		pageAlpha = 0
		return Render()
	end
	if scene.kind == "QUEST_COMPLETE" then return Select(number) end
	local choice = scene.choices[number]
	if choice then Pick(choice) end
end

-- Keys -------------------------------------------------------------------------------

local function CanCycle()
	return scene ~= nil and not scene.back and scene.kind == "QUEST_COMPLETE" and (scene.choiceCount or 0) > 1
		and IsLastPage() and true or false
end
local function CanGoBack()
	return scene ~= nil and not scene.back and (scene.page > 1 or scene.previous ~= nil)
end

local unbindPending = false
local boundKeys -- the keys borrowed now, in one word (borrowed again only when it changes)
local function BindKeys(bind)
	if InCombatLockdown() then
		unbindPending = not bind
		return
	end
	unbindPending = false
	local wanted = bind and scene and ("keys" .. (CanCycle() and " tab" or "")) or nil
	if bind and wanted == boundKeys then return end
	boundKeys = wanted
	Safe(ClearOverrideBindings, panel)
	if not wanted then return end
	Safe(SetOverrideBindingClick, panel, true, "SPACE", "WandererSceneContinue")
	for number = 1, MAX_CHOICES do
		Safe(SetOverrideBindingClick, panel, true, tostring(number), "WandererSceneChoice" .. number)
	end
	if wanted:find("tab", 1, true) then Safe(SetOverrideBindingClick, panel, true, "TAB", "WandererSceneCycle") end
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
	-- (a Button: picked only when pressed and released on it, never by a camera drag ending over it)
	row = CreateFrame("Button", nil, panel)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp") row.padRight = true
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:Hide()
	row.mark = row:CreateTexture(nil, "ARTWORK")
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
	row.text:SetJustifyH("LEFT")
	-- (two lines at most: a long answer in German or Russian is read whole)
	if row.text.SetWordWrap then row.text:SetWordWrap(true) end
	if row.text.SetMaxLines then row.text:SetMaxLines(2) end
	row:SetScript("OnEnter", function(self) self.hover:Show() self.mark:Show() end)
	row:SetScript("OnLeave", function(self) self.hover:Hide() self.mark:Hide() end)
	row:SetScript("OnClick", function(self, button)
		if button == "LeftButton" then Choose(self.number) elseif button == "RightButton" then Leave() end
	end)
	choiceRows[index] = row
	return row
end

ShowRewardTip = function(item)
	GameTooltip:SetOwner(item, "ANCHOR_RIGHT")
	Safe(GameTooltip.SetQuestItem, GameTooltip, item.kind, item.index)
	if item.isBest then GameTooltip:AddLine(L.SCENE_BEST_VALUE, 1, 0.82, 0) end
	if item.compare and item.compare > 0 then
		GameTooltip:AddLine(L.SCENE_UPGRADE:format(item.compare), 0.4, 1, 0.4)
	elseif item.compare and item.compare < 0 then
		GameTooltip:AddLine(L.SCENE_DOWNGRADE:format(-item.compare), 1, 0.4, 0.4)
	end
	GameTooltip:Show()
end

-- An item: its icon with a thin border of its rarity, and its name. A click
-- picks a reward to choose; Shift links it, Ctrl tries it on (the game's own
-- modified clicks).
local function RewardItem(index)
	local item = rewardItems[index]
	if item then return item end
	item = CreateFrame("Button", nil, panel)
	item:RegisterForClicks("LeftButtonUp", "RightButtonUp") item.padRight = true
	item.picked = item:CreateTexture(nil, "BACKGROUND")
	item.picked:SetAllPoints()
	item.picked:Hide()
	item.pickMark = item:CreateTexture(nil, "ARTWORK")
	item.pickMark:SetWidth(2)
	item.pickMark:SetPoint("TOPRIGHT")
	item.pickMark:SetPoint("BOTTOMRIGHT")
	item.pickMark:Hide()
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
	item.price:SetPoint("RIGHT", item, "RIGHT", -6, 0)
	item.text = ns.Skin.CreateText(item, "GameTooltipTextSmall", 0.95, 0.92, 0.85)
	item.text:SetPoint("LEFT", item.border, "RIGHT", 8, 0)
	item.text:SetPoint("RIGHT", item.price, "LEFT", -6, 0)
	if item.text.SetWordWrap then item.text:SetWordWrap(false) end
	if item.price.SetWordWrap then item.price:SetWordWrap(false) end
	item:SetScript("OnEnter", ShowRewardTip)
	item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	item:SetScript("OnClick", function(self, button)
		if button == "RightButton" then return Leave() end
		if button ~= "LeftButton" then return end
		local link = Clean(Safe(GetQuestItemLink, self.kind, self.index))
		if link and HandleModifiedItemClick and (U.IsSkipping() or (IsControlKeyDown and IsControlKeyDown())) then
			Safe(HandleModifiedItemClick, link)
			return
		end
		if self.number then
			if scene and (scene.back or not IsLastPage()) then return Choose(self.number) end
			Select(self.number)
		end
	end)
	rewardItems[index] = item
	return item
end

-- A button drawn by the engine, like the panel: its text turns golden and its
-- border lights up under the mouse. onClick(true): clicked (a deliberate act).
local function ButtonLook(button, hovered)
	if hovered then
		Paint(button.text, "accent")
	else
		Paint(button.text, button.locked and "keys" or "text")
	end
	if paper then
		local layers = button.wandererParchment
		local c = C(hovered and "accent" or "label")
		if layers then layers.edges.Color(c[1], c[2], c[3], hovered and 0.85 or 0.45) end
	else
		button.skin:SetHighlight(hovered and "giver" or nil)
	end
end

local function ActionButton(index)
	local button = actionButtons[index]
	if button then return button end
	local window, buttonSkin = ns.Skin.CreateWindow(nil, nil, panel, nil, "Button")
	button = window
	button.skin = buttonSkin
	button.text = ns.Skin.CreateText(button, "GameTooltipText", 0.95, 0.92, 0.85)
	button.text:SetPoint("CENTER")
	button.text:SetJustifyH("CENTER")
	button:SetScript("OnEnter", function(self) ButtonLook(self, true) end)
	button:SetScript("OnLeave", function(self) ButtonLook(self, false) end)
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function(self)
		if self.onClick then self.onClick(true) end
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

-- The dark look or the parchment, as chosen (the panel and its buttons together).
local function ApplyLook()
	paper = Paper()
	if panel.paper ~= paper then
		ns.Skin.Parchment(panel, paper)
		panel.paper = paper
	end
	for _, button in ipairs(actionButtons) do
		if button.paper ~= paper then
			ns.Skin.Parchment(button, paper, true)
			button.paper = paper
		end
	end
	local ring = C("ring")
	portraitRing:SetVertexColor(ring[1], ring[2], ring[3], ring[4])
	local line = C("rule")
	rule:SetColorTexture(line[1], line[2], line[3], line[4])
	Paint(nameText, "name")
	Paint(titleText, "title")
	Paint(rewardsLabel, "label")
	Paint(moneyText, "text")
	Paint(keysText, "keys")
	Paint(replayLink.text, "label")
	-- The background's opacity, the scene's own (the label's never lowers it).
	local opacity = ns.db.scene.bgOpacity or 90
	if skin.fixedOpacity ~= opacity then
		skin.fixedOpacity, skin.minOpacity = opacity, opacity / 100
		skin:ApplyStyle()
	end
end

-- The drawing's measures, shared by its parts (one table, set again at each drawing): width, margin, inner,
-- textSize, nameSize, titleSize, smallSize, choiceHeight, last (the last page, not looking back), picking (a
-- reward to choose).
local layout = {}

-- The sizes chosen for the words (the smaller ones follow too: rewards, gold, keys).
local function StyleWords()
	local textSize = ns.db.scene.textSize or 15
	layout.textSize, layout.nameSize, layout.titleSize = textSize, textSize + 3, textSize - 2
	layout.smallSize = math.max(10, textSize - 3)
	layout.choiceHeight = math.max(CHOICE_HEIGHT, textSize + 10)
	StyleFont(nameText, layout.nameSize)
	StyleFont(titleText, layout.titleSize)
	StyleFont(saidText, layout.titleSize)
	StyleFont(bodyText, textSize)
	StyleFont(rewardsLabel, layout.smallSize)
	StyleFont(moneyText, layout.smallSize)
	StyleFont(keysText, layout.smallSize)
end

-- Who speaks: its portrait in a round frame (an object's or an item's picture, never a black disc), its name,
-- and the quest; Spoken's control to read it again at the top right; a rule under them.
local function RenderHeader(y)
	local margin, inner = layout.margin, layout.inner
	local nameSize, titleSize = layout.nameSize, layout.titleSize
	-- Spoken can read the quest again: its control, at the top right.
	local reread = QUEST_PAGES[scene.kind] and SpokenReread() ~= nil
	replayLink:SetShown(reread)
	local replayWidth = 0
	if reread then
		replayLink:SetWidth(U.Measure(replayLink.text, "GetStringWidth", 80) + 10)
		replayLink:ClearAllPoints()
		replayLink:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -margin, -margin + 4)
		replayWidth = replayLink:GetWidth() + SMALL_GAP
	end
	local unit, face = scene.unit, scene.icon
	local top = y
	local textLeft, textWidth = margin, inner - replayWidth
	local pictured = face ~= nil or unit ~= nil
	if face then
		portrait:SetTexture(face)
		portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	elseif unit then
		portrait:SetTexCoord(0, 1, 0, 1)
		ns.SetPortrait(portrait, unit, "scene")
	end
	if pictured then
		portrait:ClearAllPoints()
		portrait:SetPoint("TOPLEFT", panel, "TOPLEFT", margin, -y)
		textLeft, textWidth = margin + PORTRAIT_SIZE + GAP, inner - PORTRAIT_SIZE - GAP - replayWidth
	end
	portrait:SetShown(pictured)
	-- The ring only when it can be cut round: never a square.
	portraitRing:SetShown(pictured and portraitRing.round or false)
	nameText:SetWidth(textWidth)
	local speaker = scene.name
	if not U.IsSecret(speaker) and not speaker then speaker = "" end
	if not pcall(nameText.SetText, nameText, speaker) then nameText:SetText("") end
	local title = Clean(scene.title)
	titleText:SetWidth(textWidth)
	titleText:SetText(title and (scene.tag and (title .. "\n" .. scene.tag) or title) or "")
	titleText:SetShown(title ~= nil)
	-- The name and the quest stand beside the portrait, centered on it.
	local textHeight = U.Measure(nameText, "GetStringHeight", nameSize)
		+ (title and (2 + U.Measure(titleText, "GetStringHeight", titleSize)) or 0)
	local textTop = y + (pictured and math.max(0, (PORTRAIT_SIZE - textHeight) / 2) or 0)
	Place(nameText, textTop, textLeft)
	if title then Place(titleText, textTop + U.Measure(nameText, "GetStringHeight", nameSize) + 2, textLeft) end
	y = math.max(textTop + textHeight, pictured and (top + PORTRAIT_SIZE) or 0)
	y = y + SMALL_GAP
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", panel, "TOPLEFT", margin, -y)
	rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -margin, -y)
	return y + 1 + GAP
end

-- Your words, quiet, over the character's answer; looking back, what it said before.
local function RenderSaid(y)
	local saidLine
	if scene.back then
		saidLine = L.SCENE_EARLIER
	elseif scene.said and scene.page == 1 then
		saidLine = L.SCENE_SAID:format(scene.said)
	end
	saidText:SetShown(saidLine ~= nil)
	if not saidLine then return y end
	Paint(saidText, "muted")
	saidText:SetWidth(layout.inner)
	if not pcall(saidText.SetText, saidText, saidLine) then saidText:SetText("") end
	Place(saidText, y, layout.margin)
	return y + U.Measure(saidText, "GetStringHeight", layout.titleSize) + SMALL_GAP
end

-- The words, page by page.
local function RenderBody(y)
	bodyText:SetWidth(layout.inner)
	local words
	if scene.back then words = scene.previous.text else words = scene.pages[scene.page] end
	if not U.IsSecret(words) and not words then words = "" end
	-- (Spoken reading this page: the sentence it says stands out)
	if not scene.back and scene.voice and scene.voice.page == scene.page then words = Voiced(words, scene.voice.sentence) end
	if not pcall(bodyText.SetText, bodyText, words) then bodyText:SetText("") end
	Paint(bodyText, scene.back and "muted" or "text")
	bodyText:SetAlpha(pageAlpha)
	Place(bodyText, y, layout.margin)
	return y + U.Measure(bodyText, "GetStringHeight", layout.textSize)
end

-- One reward drawn on its item (number: its place among the rewards to choose, else nil).
local function PaintReward(item, reward, number)
	local picking = layout.picking
	StyleFont(item.text, math.max(10, layout.textSize - 2))
	StyleFont(item.price, layout.smallSize)
	item.kind, item.index = reward.kind, reward.index
	item.number = number
	item.icon:SetTexture(reward.texture)
	-- What this character cannot use: darkened, its name in red.
	if item.icon.SetDesaturated then item.icon:SetDesaturated(reward.unusable) end
	if reward.unusable then item.icon:SetVertexColor(1, 0.45, 0.45) else item.icon:SetVertexColor(1, 1, 1) end
	Paint(item.text, reward.unusable and "unusable" or "text")
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
	Paint(item.price, reward.best and "accent" or "price")
	-- Picked: lit, the other choices dimmed.
	local isPicked = picking and item.number ~= nil and item.number == scene.selected
	local pickedColor, mark = C("picked"), C("mark")
	item.picked:SetColorTexture(pickedColor[1], pickedColor[2], pickedColor[3], pickedColor[4])
	item.pickMark:SetColorTexture(mark[1], mark[2], mark[3], mark[4])
	item.picked:SetShown(isPicked)
	item.pickMark:SetShown(isPicked)
	item:SetAlpha((picking and scene.selected and item.number and not isPicked) and 0.45 or 1)
	local r, g, b = 0.5, 0.5, 0.5
	if reward.quality then r, g, b = U.QualityColor(reward.quality) end
	item.border:SetColorTexture(r, g, b, 0.9)
	local label = (reward.waiting and (Hex("muted") .. (RETRIEVING_ITEM_INFO or "...") .. "|r") or reward.name)
		.. (reward.count > 1 and (" x" .. reward.count) or "")
	if item.number then label = ("%s%d.|r %s"):format(Hex("accent"), item.number, label) end
	item.text:SetText(label)
end

-- Rewards, in two columns (on the last page).
local function RenderRewards(y)
	local last, margin = layout.last, layout.margin
	for index, item in ipairs(rewardItems) do
		if not (last and scene.rewards[index]) then item:Hide() end
	end
	rewardsLabel:SetShown(last and scene.rewards[1] ~= nil)
	if not (last and scene.rewards[1]) then return y end
	y = y + GAP
	rewardsLabel:SetText(scene.kind == "QUEST_PROGRESS" and L.SCENE_REQUIRED or L.REWARDS)
	Place(rewardsLabel, y, margin)
	y = y + U.Measure(rewardsLabel, "GetStringHeight", 12) + SMALL_GAP
	local column = math.floor((layout.inner - GAP) / 2)
	for index, reward in ipairs(scene.rewards) do
		local item = RewardItem(index)
		local chosen
		if reward.kind == "choice" and scene.kind == "QUEST_COMPLETE" then
			-- (the game's own number for it: a choice not given yet must never shift the others)
			chosen = reward.index
		end
		PaintReward(item, reward, chosen)
		item:SetSize(column, REWARD_ICON + 4)
		item:ClearAllPoints()
		local col, line = (index - 1) % 2, math.floor((index - 1) / 2)
		item:SetPoint("TOPLEFT", panel, "TOPLEFT", margin + col * (column + GAP), -(y + line * (REWARD_ICON + 8)))
		item:Show()
	end
	return y + math.ceil(#scene.rewards / 2) * (REWARD_ICON + 8)
end

-- The gold of the reward (on the last page).
local function RenderMoney(y)
	local money = layout.last and scene.money or ""
	moneyText:SetText(money)
	moneyText:SetShown(money ~= "")
	if money == "" then return y end
	y = y + SMALL_GAP
	moneyText:SetWidth(layout.inner)
	Place(moneyText, y, layout.margin)
	return y + U.Measure(moneyText, "GetStringHeight", 12)
end

-- Choices, one per line; a quest's title in its level's color.
local function RenderChoices(y)
	local last = layout.last
	for index, row in ipairs(choiceRows) do
		if not (last and scene.choices[index]) then row:Hide() end
	end
	if not (last and scene.choices[1]) then return y end
	y = y + GAP
	local hover, mark = C("hover"), C("mark")
	for index = 1, math.min(#scene.choices, MAX_CHOICES) do
		local choice = scene.choices[index]
		local row = ChoiceRow(index)
		row.number = index
		row.hover:SetColorTexture(hover[1], hover[2], hover[3], hover[4])
		row.mark:SetColorTexture(mark[1], mark[2], mark[3], mark[4])
		Paint(row.text, "text")
		StyleFont(row.text, layout.textSize - 1)
		SetIcon(row.icon, choice.atlas, choice.icon)
		local label = Clean(choice.label) or "?"
		if choice.level and choice.level > 0 and type(label) == "string" then
			label = U.Colorize(label, Tone(ns.World.LevelColor(choice.level, true)))
		end
		if not pcall(row.text.SetText, row.text, ("%s%d.|r  %s"):format(Hex("accent"), index, label)) then
			row.text:SetText(("%s%d.|r"):format(Hex("accent"), index))
		end
		-- (already read: dimmed, at its place)
		row:SetAlpha(ns.ChoiceSeen(choice.seen) and SEEN_ALPHA or 1)
		row:SetSize(layout.inner, layout.choiceHeight)
		local height = math.max(layout.choiceHeight, U.Measure(row.text, "GetStringHeight", 0) + 8)
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", layout.margin, -y)
		row:Show()
		y = y + height + 2
	end
	return y
end

-- One action button, its right edge at right, at the height y: its words and its key, its click. Returns where
-- the next one ends (to its left).
local function PlaceButton(button, label, key, onClick, dim, right, y)
	if button.paper ~= paper then
		ns.Skin.Parchment(button, paper, true)
		button.paper = paper
	end
	-- (with a controller, no key of a keyboard said: the pad's buttons are the game's)
	local keyText = ns.Pad.On() and "" or ("   " .. Hex("keys") .. key .. "|r")
	button.text:SetText(label .. keyText)
	local buttonWidth = U.Measure(button.text, "GetStringWidth", 80) + BUTTON_PADDING * 2
	button:SetSize(buttonWidth, BUTTON_HEIGHT)
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", panel, "TOPLEFT", right, -y)
	button.onClick = onClick
	button.locked = dim and true or false
	button.skin:Layout()
	ButtonLook(button, false)
	button:Show()
	return right - buttonWidth - SMALL_GAP
end

-- The buttons at the bottom right: the main action (Space), then leave (Escape); what the keys do now, on the
-- left. cost: the gold a turn-in costs; locked: Space still waiting for it.
local function RenderActions(y, cost, locked)
	local last, picking, margin = layout.last, layout.picking, layout.margin
	y = y + GAP
	local right = layout.width - margin
	local main
	if scene.back then
		main = L.SCENE_RESUME
	elseif not last then
		main = L.SCENE_NEXT
	elseif cost > 0 then
		main = L.SCENE_PAY:format(U.Coins(cost))
	elseif picking and scene.selected then
		local reward
		for _, candidate in ipairs(scene.rewards) do
			if candidate.kind == "choice" and candidate.index == scene.selected then reward = candidate end
		end
		main = L.SCENE_TAKE:format(Short(reward and reward.name or "", NAME_ON_BUTTON))
	else
		main = scene.action
	end
	if main then
		right = PlaceButton(ActionButton(1), main, L.SCENE_KEY_SPACE, Continue, locked, right, y)
	else
		ActionButton(1):Hide()
	end
	right = PlaceButton(ActionButton(2), scene.declinable and L.SCENE_DECLINE or L.SCENE_CLOSE, L.SCENE_KEY_ESCAPE, Leave,
		nil, right, y)
	local hint = ""
	if locked then
		hint = L.SCENE_KEYS_GOLD
	elseif picking then
		hint = scene.selected and L.SCENE_KEYS_TAKE or L.SCENE_KEYS_REWARD
	elseif last and scene.choices[1] ~= nil then
		hint = L.SCENE_KEYS_CHOOSE
	elseif CanGoBack() then
		hint = L.SCENE_KEYS_BACK
	end
	if ns.Pad.On() and not locked and hint ~= L.SCENE_KEYS_BACK then
		hint = ns.Skin.PadKeys({ { "PAD1", "CHOOSE" }, { "PAD2", "LEAVE" } }) or L.SCENE_PAD_KEYS
	end
	keysText:SetText(hint)
	if locked and scene.warned then Paint(keysText, "accent") end
	keysText:SetWidth(math.max(right - margin - SMALL_GAP, 40))
	keysText:ClearAllPoints()
	keysText:SetPoint("LEFT", panel, "TOPLEFT", margin, -(y + BUTTON_HEIGHT / 2))
	-- (saying what was said before: a click on it goes back too)
	local backHint = hint == L.SCENE_KEYS_BACK
	keysLink:SetShown(backHint)
	if backHint then
		keysLink:ClearAllPoints()
		keysLink:SetPoint("LEFT", keysText, "LEFT", 0, 0)
		keysLink:SetSize(math.min(U.Measure(keysText, "GetStringWidth", 120), keysText:GetWidth() or 120), BUTTON_HEIGHT)
	end
	-- A controller: the page read again by the game's navigation, the first answer (else the main button) chosen.
	if ns.Pad.On() then
		local first = last and choiceRows[1]
		if not (first and first:IsShown()) then first = actionButtons[1] and actionButtons[1]:IsShown() and actionButtons[1] or actionButtons[2] end
		ns.Pad.Refresh(panel, first)
	end
	return y + BUTTON_HEIGHT + margin
end

Render = function()
	if not scene then return end
	ApplyLook()
	layout.width = PanelWidth()
	layout.margin = ns.Skin.Margin() + 8
	layout.inner = layout.width - layout.margin * 2
	StyleWords()
	local y = RenderHeader(layout.margin)
	y = RenderSaid(y)
	y = RenderBody(y)
	layout.last = IsLastPage() and not scene.back
	layout.picking = layout.last and scene.kind == "QUEST_COMPLETE" and (scene.choiceCount or 0) > 1
	y = RenderRewards(y)
	y = RenderMoney(y)
	y = RenderChoices(y)
	-- A turn-in that costs gold: the button says the price, Space waits a moment.
	local cost = layout.last and scene.kind == "QUEST_PROGRESS" and scene.completable and (scene.cost or 0) or 0
	if cost > 0 and not scene.lockUntil then scene.lockUntil = GetTime() + LockTime(cost) end
	y = RenderActions(y, cost, cost > 0 and Locked())
	-- The panel grows with its content (nothing drawn out of it), kept on the screen.
	panel:SetScale(ns.Skin.Scale())
	panel:SetSize(layout.width, y)
	panel:SetClampedToScreen(true)
	skin:Layout()
	if panel.wandererParchment and panel.wandererParchment.Tile then panel.wandererParchment.Tile() end
	BindKeys(true)
end

-- Spoken's voice ---------------------------------------------------------------------

-- While Spoken reads the scene's own words, the scene follows its voice: the page turns as the
-- voice reaches it (unless you turned pages yourself) and the sentence being read stands out.
-- Only Spoken's public calls are read: GetCaption (the word being said, timed as its subtitles
-- time it), else, with an older Spoken, the line playing and its length. Its subtitles would show
-- the same words under the panel: Spoken has no public switch for them, so they are hidden while
-- the scene shows that line and shown again once it ends; Spoken's settings are never written.

local FOLLOW_STEP = 0.1 -- seconds between two looks at the voice
local SAME_SHARE = 0.8 -- two copies of a line: the share of the shorter alike from the start

local heardLines = setmetatable({}, { __mode = "k" }) -- Spoken's line: its letters, where each word ends
local lineStarts = setmetatable({}, { __mode = "k" }) -- Spoken's line: when it began (an older Spoken)
local listening = false
local followFor = 0

local function SpokenAPI()
	local spoken = rawget(_G, "Spoken")
	return type(spoken) == "table" and spoken or nil
end

-- Letters only, lower case: what two copies of the same words share (no escapes, spaces or marks).
local function Letters(text)
	if type(text) ~= "string" or U.IsSecret(text) then return "" end
	return (U.PlainText(text):lower():gsub("[%s%p]", ""))
end

-- A line's letters and where each of its words ends in them, kept while the line lives.
local function Heard(line, words)
	local known = heardLines[line]
	if known then return known end
	local all, ends, length = {}, {}, 0
	for index, word in ipairs(words) do
		all[index] = Letters(word)
		length = length + #all[index]
		ends[index] = length
	end
	known = { text = table.concat(all), ends = ends }
	heardLines[line] = known
	return known
end

-- An older Spoken without captions: when each line begins, from its callback.
local function Listen(spoken)
	if listening or type(spoken.GetCaption) == "function" or type(spoken.RegisterCallback) ~= "function" then return end
	listening = true
	pcall(spoken.RegisterCallback, spoken, "CLIP_STARTED", function(line)
		if type(line) == "table" then lineStarts[line] = GetTime() end
	end)
end

-- What Spoken reads now: the line, its letters, and how many of them are said (nil: not speaking).
local function Voice(spoken)
	if type(spoken.GetCaption) == "function" then
		local ok, caption = pcall(spoken.GetCaption, spoken)
		if not ok or type(caption) ~= "table" or type(caption.clip) ~= "table" or type(caption.words) ~= "table" then
			return nil
		end
		local line = caption.clip
		local heard = heardLines[line]
		if not heard then
			local words = {}
			for index, word in ipairs(caption.words) do words[index] = type(word) == "table" and word.text or "" end
			heard = Heard(line, words)
		end
		local active = caption.speaking and tonumber(caption.activeWord)
		return line, heard, active and heard.ends[active] or nil
	end
	if type(spoken.GetNowPlaying) ~= "function" then return nil end
	local ok, line = pcall(spoken.GetNowPlaying, spoken)
	if not ok or type(line) ~= "table" then return nil end
	local present = type(line.present) == "table" and line.present or {}
	local text = present.transcript or line.text
	if type(text) ~= "string" then return nil end
	local heard = heardLines[line]
	if not heard then
		local words = {}
		for word in text:gmatch("%S+") do words[#words + 1] = word end
		heard = Heard(line, words)
	end
	-- Timed by its length: the letters said in proportion to the time gone.
	local length, began = tonumber(line.length), lineStarts[line]
	local paused = type(spoken.IsPaused) == "function" and select(2, pcall(spoken.IsPaused, spoken)) == true
	if not (length and length > 0 and began) or paused then return line, heard, nil end
	local share = (GetTime() - began) / length
	if share >= 1 then return line, heard, nil end
	return line, heard, math.max(1, math.floor(#heard.text * share))
end

-- The scene's letters, sentence by sentence, with the page and sentence each ends in.
local function SceneLetters()
	if scene.letters then return scene.letters end
	local all, marks, length = {}, {}, 0
	for page, text in ipairs(scene.pages) do
		if type(text) == "string" and not U.IsSecret(text) then
			for index, sentence in ipairs(Sentences(text)) do
				local letters = Letters(sentence)
				all[#all + 1] = letters
				length = length + #letters
				marks[#marks + 1] = { page = page, sentence = index, last = length }
			end
		end
	end
	scene.letters = { text = table.concat(all), marks = marks }
	return scene.letters
end

-- Where Spoken's line starts in the scene's letters, or nil when it reads something else.
local function Offset(heard, letters)
	local voiced, shown = heard.text, letters.text
	if voiced == "" or shown == "" then return nil end
	local at = shown:find(voiced, 1, true)
	if at then return at - 1 end
	-- The same words, one copy a little different (a name, a last line): alike from the start.
	local shorter, same = math.min(#voiced, #shown), 0
	while same < shorter and voiced:byte(same + 1) == shown:byte(same + 1) do same = same + 1 end
	return same >= shorter * SAME_SHARE and 0 or nil
end

-- Spoken's line: the scene's own words? Its place in them then.
local function Ours(line, heard)
	if scene.heardLine ~= line then
		scene.heardLine, scene.heardAt = line, Offset(heard, SceneLetters()) or false
	end
	return scene.heardAt or nil
end

-- Spoken's windows: its subtitles and its players (the one in use). While a scene shows, the scene alone is
-- seen: Spoken's voice plays, its words go by in the scene, its own windows wait hidden and come back as
-- they were once the scene ends. Only shown and hidden: Spoken's settings are never written.
local SPOKEN_WINDOWS = { "SpokenSubtitleFrame", "SpokenPlayerFrame", "SpokenMinimalPlayerFrame", "SpokenDialogueUIPlayerFrame" }
local spokenHidden, spokenWatched = {}, {}

local function HideSubtitles(frame)
	spokenHidden[frame] = true
	pcall(frame.Hide, frame)
end

-- Spoken's windows back as they were: shown again, and Spoken goes on with them (or hides them itself,
-- its voice over).
local function GiveSubtitlesBack()
	for frame in pairs(spokenHidden) do
		if type(frame.Show) == "function" then pcall(frame.Show, frame) end
	end
	wipe(spokenHidden)
end

-- Each of Spoken's windows: hidden now while a scene shows, and kept hidden should Spoken show it again,
-- before a single frame is drawn.
local function HideSpoken()
	if not scene then return end
	for _, name in ipairs(SPOKEN_WINDOWS) do
		local frame = rawget(_G, name)
		if type(frame) == "table" and type(frame.Hide) == "function" and type(frame.HookScript) == "function" then
			if not spokenWatched[frame] then
				spokenWatched[frame] = true
				pcall(frame.HookScript, frame, "OnShow", function(self)
					if scene then HideSubtitles(self) end
				end)
			end
			if Clean(Safe(frame.IsShown, frame)) then HideSubtitles(frame) end
		end
	end
end

local Follow

-- One look at the voice; true when Spoken reads the scene's words.
Follow = function()
	if not scene then return false end
	local spoken = SpokenAPI()
	if not spoken then return false end
	Listen(spoken)
	local line, heard, reached = Voice(spoken)
	local at = line and Ours(line, heard)
	HideSpoken()
	-- The sentence the voice is in (none looking back, or the voice silent).
	local mark
	if at and reached and not scene.back then
		local position = at + reached
		for _, each in ipairs(SceneLetters().marks) do
			mark = each
			if each.last >= position then break end
		end
	end
	local shown = scene.voice
	if not mark then
		if shown then
			scene.voice = nil
			Render()
		end
		return at ~= nil
	end
	if shown and shown.page == mark.page and shown.sentence == mark.sentence then return true end
	-- The page turns with the voice while you follow it: never away from a page you went to yourself.
	local followed = scene.voicePage
	local following = followed == scene.page or (followed == nil and mark.page >= scene.page)
	if following and mark.page ~= scene.page then
		scene.page = mark.page
		pageAlpha = 0
	end
	scene.voicePage = mark.page
	scene.voice = { page = mark.page, sentence = mark.sentence }
	Render()
	return true
end

-- Scene ------------------------------------------------------------------------------

local HUSH_SHARE = 0.4 -- the music and the ambience while a scene is shown

local function Begin(event, startItem, args)
	sceneToken = sceneToken + 1
	local before = scene
	scene = Build(event, startItem)
	scene.args = args
	-- The same character goes on talking: the page it said before, and your words, kept.
	if before and before.guid and before.guid == scene.guid and not before.back then
		local text = before.pages and before.pages[before.page]
		if type(text) == "string" and not U.IsSecret(text) and text ~= "" then scene.previous = { text = text } end
		scene.said = said
	end
	said = nil
	local first = not before
	pageAlpha = first and 1 or 0
	ns.sceneActive = true
	ns.RefreshCinema()
	if first then
		appear, target = 0, 1
		panel:SetAlpha(0)
		panel:Show()
		U.PlaySound("IG_QUEST_LIST_OPEN")
		-- (written once, before the camera moves: a setting written stops it on its way)
		-- Spoken lowers the music itself while it speaks: never both at once.
		if ns.db.scene.hush and not ns.SpokenLoaded() then ns.LowerVolumes("sceneVolumes", HUSH_SHARE) end
	end
	Render()
	-- (Spoken may already be reading it)
	followFor = 0
	Follow()
end

-- The conversation left: Spoken's voice stops with it, and what it would queue as the quest is taken or
-- handed in (its accept and turn-in lines come a moment after) is dropped too. To hear a quest again,
-- Spoken's own buttons. Its public StopAll only; nothing of Spoken is changed.
-- Only once the conversation is really over: going from a dialogue to its quest closes one page before the
-- next opens, and the new page's voice must play. Any page shown after the end keeps Spoken speaking.
local QUIET_AGAIN = { 0.4, 1.2 } -- seconds after the end: the lines Spoken queues late
local lastPage = 0 -- when a conversation page was last shown
local pages = CreateFrame("Frame")
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
	pages:RegisterEvent(event)
end
pages:SetScript("OnEvent", function() lastPage = GetTime() end)

local function QuietSpoken()
	local spoken = SpokenAPI()
	local stop = spoken and spoken.StopAll
	if type(stop) ~= "function" then return end
	local ended = GetTime()
	local function Stop()
		-- (a page shown since, or a scene open again: its voice is the one wanted)
		if scene or lastPage > ended then return end
		pcall(stop, spoken)
	end
	for _, delay in ipairs(QUIET_AGAIN) do C_Timer.After(delay, Stop) end
end

local function Finish(closeConversation)
	if not scene then return end
	if closeConversation then CloseConversation() end
	scene = nil
	said = nil
	ns.sceneActive = false
	ns.RestoreVolumes("sceneVolumes")
	GiveSubtitlesBack()
	QuietSpoken()
	U.PlaySound("IG_QUEST_LIST_CLOSE")
	ns.RefreshCinema()
	BindKeys(false)
	GameTooltip:Hide()
	-- The panel fades away (OnUpdate hides it).
	target = 0
end

-- A scene that could not be drawn (a page the game says in a way Wanderer does not expect): let go, and the
-- game's own window shows the conversation instead. Said once a session, quietly; the fault itself in the
-- diagnostic mode.
local faultSaid = false
local function Fallback(event, args, problem)
	if scene then Finish(false) end
	if panel then
		appear, target = 0, 0
		panel:Hide()
	end
	if not faultSaid then
		faultSaid = true
		ns.Print(L.SCENE_FALLBACK)
	end
	if ns.debug then ns.Print(tostring(problem)) end
	if event and not InCombatLockdown() then Relay(event, unpack(args or {}, 1, args and args.n or 0)) end
end

-- Every drawing of the scene guarded: a fault never leaves you stuck before a character.
local Draw = Render
Render = function()
	if not scene then return end
	local ok, problem = pcall(Draw)
	if ok then return end
	-- (the conversation already closed, or the character gone: nothing to hand to the game's window)
	local talking = Clean(Safe(UnitExists, "npc")) or Clean(Safe(UnitExists, "questnpc"))
	local event = scene and not scene.closed and talking and scene.kind or nil
	Fallback(event, scene and scene.args, problem)
end

-- A show event taken, then nothing on the screen half a second later (no scene, no game window) while you
-- still face the character: the game's window gets it.
local WATCH_AFTER = 0.5
local watched -- { event, args } of the last show event taken
local function Watch(event, args)
	local this = { event = event, args = args }
	watched = this
	C_Timer.After(WATCH_AFTER, function()
		if watched ~= this then return end
		watched = nil
		if scene or planned or InCombatLockdown() or GameWindowOpen() or ns.WasAnswered(event) then return end
		if not (Clean(Safe(UnitExists, "npc")) or Clean(Safe(UnitExists, "questnpc"))) then return end
		if ns.debug then ns.Print("scene watchdog: " .. tostring(event)) end
		Relay(event, unpack(args, 1, args.n))
	end)
end

-- The game closed the conversation: a new page of it may come right after
-- (a quest chosen in a dialogue, a choice that goes back), so the scene waits:
-- a moment, longer while you still face the character (the next page can
-- take a while to come), so the interface never comes back between two
-- pages. A dialogue's end never closes a quest shown after it, and the other
-- way round.
local NEXT_PAGE_STEP = 0.15 -- seconds
local NEXT_PAGE_WAIT = 1.5 -- at most, while still facing the character

local function OnClosed(event)
	local gossip = event == "GOSSIP_CLOSED"
	watched = nil
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
	scene.closed = true
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
	-- (Shift never asks for the game's window with a controller: see Relay)
	return db and db.enabled and db.scene.enabled and not InCombatLockdown() and (U.UsingPad() or not U.IsSkipping())
		and not ns.SceneYielded()
end

local function OnEvent(_, event, ...)
	if event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then return OnClosed(event) end
	-- The game took the quest (or its reward): its page is over.
	if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
		watched = nil
		local kinds = event == "QUEST_ACCEPTED" and { QUEST_DETAIL = true } or { QUEST_PROGRESS = true, QUEST_COMPLETE = true }
		if planned and kinds[planned] then
			sceneToken = sceneToken + 1
			planned = nil
		end
		if scene and kinds[scene.kind] then Finish(false) end
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" or event == "QUEST_ITEM_UPDATE" then
		if not scene then return end
		local changed = false
		for _, reward in ipairs(scene.rewards or {}) do
			if reward.waiting then
				local name = RewardName(reward.kind, reward.index)
				if name then
					local _, texture, _, quality = Safe(GetQuestItemInfo, reward.kind, reward.index)
					reward.name, reward.waiting = name, false
					reward.texture = Clean(texture) or reward.texture
					reward.quality = Clean(quality) or reward.quality
					changed = true
				end
			end
		end
		if scene.waitingPrices then
			scene.waitingPrices = Prices(scene.rewards)
			changed = true
		end
		-- (the item that began the quest: its name and picture once the game knows them)
		if scene.item and not scene.itemKnown and U.ItemName(scene.item) then
			scene.name, scene.icon, scene.itemKnown = U.ItemName(scene.item), U.ItemIcon(scene.item) or scene.icon, true
			changed = true
		end
		if changed then Render() end
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		-- A fight: the keys and the camera are given back at once, and the
		-- game's windows hear their events themselves until it ends. Opened
		-- by Wanderer in a fight, they would be refused by the game and the
		-- conversation would stay stuck.
		sceneToken = sceneToken + 1
		planned = nil
		watched = nil
		if scene then Finish(true) end
		SetTaken(false)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if unbindPending and not scene then BindKeys(false) end
		return ns.RefreshScene()
	end
	-- Scenes off (or shown by another addon): the game's windows hear their events themselves.
	if not taker.taken then return end
	-- (the game's own window shows this conversation already: its next page stays there, never a scene over it)
	if GameHandlesAlone(event) or GameWindowOpen() then
		if scene then Finish(false) end
		return Relay(event, ...)
	end
	if Wanted() then
		-- The game fills its data first; an automatic answer (Comfort) may
		-- also come before: the scene shows only if nothing moved on.
		local token = sceneToken + 1
		sceneToken = token
		planned = event
		local startItem = event == "QUEST_DETAIL" and ... or nil
		local args = { n = select("#", ...), ... }
		C_Timer.After(0, function()
			if sceneToken == token then
				planned = nil
				sceneToken = token - 1
				-- Answered by itself (quests accepted and handed in by
				-- themselves): nothing to show.
				if ns.WasAnswered(event) then
					if scene then Finish(false) end
					return
				end
				local ok, problem = pcall(Begin, event, startItem, args)
				if not ok then Fallback(event, args, problem) end
			end
		end)
		Watch(event, args)
	else
		if scene then Finish(false) end
		Relay(event, ...)
	end
end

local retryPending = false

function ns.RefreshScene()
	local db = ns.db
	local wanted = db.enabled and db.scene.enabled and not InCombatLockdown() and not ns.SceneYielded() and true or false
	if wanted and not taker.taken and GameWindowOpen() then
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
	if not taker.taken and scene then Finish(true) end
	if scene then Render() end
	-- (the reading window follows the scenes' settings: its own, the parchment)
	if ns.RefreshReader then ns.RefreshReader() end
end

-- Motion: the panel rises softly as it appears (only fades with the calm movements), the page fades in.
local function Ease(t) return 1 - (1 - t) ^ 3 end

-- The panel where this character put it (the placing mode), risen as far as it appeared (0 to 1).
PlacePanel = function(eased)
	local point, relPoint, x, y = ns.PlaceSpot("scene")
	if not point then point, relPoint, x, y = "BOTTOM", "BOTTOM", 0, PANEL_BOTTOM end
	local rise = ns.CalmMotion() and 0 or RISE * (1 - (eased or 1))
	panel:ClearAllPoints()
	panel:SetPoint(point, UIParent, relPoint, x, y - rise)
end

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
	-- Spoken's voice, followed.
	if scene then
		followFor = followFor + elapsed
		if followFor >= FOLLOW_STEP then
			followFor = 0
			Follow()
		end
	end
	-- A turn-in's short wait over: Space pays now.
	if scene and scene.lockUntil and not scene.unlocked and not Locked() then
		scene.unlocked = true
		Render()
	end
	if appear ~= target then
		local step = elapsed / (target > appear and APPEAR or DISAPPEAR)
		appear = target > appear and math.min(target, appear + step) or math.max(target, appear - step)
		local eased = Ease(appear)
		self:SetAlpha(eased)
		PlacePanel(eased)
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
	ns.RestoreVolumes("sceneVolumes") -- a session ended within a scene: the sounds back
	panel, skin = ns.Skin.CreateWindow("WandererScene", "DIALOG")
	-- Its place: where this character put it in the placing mode, else at the bottom of the screen.
	ns.Placeable({ key = "scene", label = function() return L.PLACING_SCENE end, frame = panel,
		size = function() return { PanelWidth(), 200 } end, scale = function() return ns.Skin.Scale() end,
		default = { "BOTTOM", "BOTTOM", 0, PANEL_BOTTOM },
		enabled = function() return ns.db and ns.db.enabled and ns.db.scene.enabled and not ns.SceneYielded() or false end,
		onMoved = function() PlacePanel(1) end })
	-- (this character's list: once the game knows who it is, at login; loaded after it, a /reload: now)
	if IsLoggedIn and IsLoggedIn() then
		ForgetOldSeen()
	else
		local login = CreateFrame("Frame")
		login:RegisterEvent("PLAYER_LOGIN")
		login:SetScript("OnEvent", function(self)
			self:UnregisterAllEvents()
			ForgetOldSeen()
		end)
	end
	PlacePanel(1)
	panel:EnableMouse(true)
	-- A controller: the game's navigation moves among the answers and buttons; its back button leaves.
	ns.Skin.PadWindow(panel, { close = function() Leave() end })
	-- (only a click begun on the panel: a camera drag ending over it neither turns the page nor accepts)
	panel:SetScript("OnMouseDown", function(self, button) self.pressed = button end)
	panel:SetScript("OnMouseUp", function(self, button)
		local pressed = self.pressed
		self.pressed = nil
		if pressed ~= button then return end
		if button == "LeftButton" then Continue(false) elseif button == "RightButton" then Leave() end
	end)
	-- The wheel: up, what was said before; down, the next page (never an answer).
	if panel.EnableMouseWheel then panel:EnableMouseWheel(true) end
	panel:SetScript("OnMouseWheel", function(_, delta)
		if delta > 0 then return Back() end
		if scene and (scene.back or not IsLastPage()) then Continue(false) end
	end)
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
	saidText = ns.Skin.CreateText(panel, "GameTooltipText", 0.62, 0.6, 0.54)
	saidText:Hide()
	bodyText = ns.Skin.CreateText(panel, "GameTooltipText", 0.95, 0.92, 0.85)
	rewardsLabel = ns.Skin.CreateText(panel, "GameTooltipTextSmall", 0.75, 0.68, 0.5)
	moneyText = ns.Skin.CreateText(panel, "GameTooltipTextSmall", 0.95, 0.92, 0.85)
	keysText = ns.Skin.CreateText(panel, "GameTooltipTextSmall", 0.55, 0.55, 0.55)
	if keysText.SetWordWrap then keysText:SetWordWrap(false) end
	-- Spoken's own reading of the quest, again (its slash command, as its key binding does).
	replayLink = CreateFrame("Button", nil, panel)
	replayLink:SetHeight(18)
	replayLink.text = ns.Skin.CreateText(replayLink, "GameTooltipTextSmall", 0.75, 0.68, 0.5)
	replayLink.text:SetPoint("RIGHT")
	replayLink.text:SetText(L.SCENE_SPOKEN_REPLAY)
	replayLink:SetScript("OnEnter", function(self)
		Paint(self.text, "accent")
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.SCENE_SPOKEN_REPLAY_DESC, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	replayLink:SetScript("OnLeave", function(self)
		Paint(self.text, "label")
		GameTooltip:Hide()
	end)
	replayLink:SetScript("OnClick", function()
		local reread = SpokenReread()
		if reread then pcall(reread, "") end
	end)
	replayLink:Hide()
	-- Buttons the borrowed keys click.
	local continue = CreateFrame("Button", "WandererSceneContinue", panel)
	continue:SetScript("OnClick", function() Continue(false) end)
	for number = 1, MAX_CHOICES do
		local button = CreateFrame("Button", "WandererSceneChoice" .. number, panel)
		button:SetScript("OnClick", function() Choose(number) end)
	end
	CreateFrame("Button", "WandererSceneCycle", panel):SetScript("OnClick", Cycle)
	CreateFrame("Button", "WandererSceneBack", panel):SetScript("OnClick", Back)
	-- The hint "what was said before", clickable (no key is borrowed for it: the arrows move you).
	keysLink = CreateFrame("Button", nil, panel)
	keysLink:SetScript("OnClick", Back)
	keysLink:SetScript("OnEnter", function() Paint(keysText, "accent") end)
	keysLink:SetScript("OnLeave", function() Paint(keysText, "keys") end)
	keysLink:Hide()
	-- Escape closes the scene and the conversation.
	if UISpecialFrames then table.insert(UISpecialFrames, "WandererScene") end
	-- Closed (Escape), not merely hidden with the whole interface (Alt+Z).
	panel:SetScript("OnHide", function()
		if scene and UIParent:IsShown() then Finish(true) end
	end)
	panel:SetScript("OnUpdate", OnUpdate)
	panel:SetScript("OnEvent", OnEvent)
	for event in pairs(SHOW_EVENTS) do panel:RegisterEvent(event) end
	panel:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	pcall(panel.RegisterEvent, panel, "QUEST_ITEM_UPDATE")
	-- Should a game window show anyway, the scene steps aside: never both.
	for _, name in ipairs({ "GossipFrame", "QuestFrame" }) do
		local window = _G[name]
		if window and window.HookScript then
			window:HookScript("OnShow", function()
				if scene and not taker.relaying then
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
