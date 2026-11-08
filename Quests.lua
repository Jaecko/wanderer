local _, ns = ...

-- Quest status of the hovered character.
-- * Objective: asked directly to the game; a creature dropping an item your
--   quests ask for is told by an extension's data (QuestUnitDrops).
-- * Quest giver / turn-in: the game does not expose the "!" and "?" markers to
--   addons, so Wanderer remembers what each NPC offered or expected whenever the
--   player talks to them, and re-evaluates it against the quest log.

local Safe, Clean = ns.Util.Safe, ns.Util.Clean

local QuestLog = C_QuestLog or {}
local Gossip = C_GossipInfo or {}

local NpcID = ns.Util.NpcID

local function Book()
	ns.root.questBook = ns.root.questBook or {}
	return ns.root.questBook
end

-- Records which quests an NPC offers (offers) or receives (receives).
local function Remember(kind, questID)
	questID = Clean(questID)
	if not questID or questID == 0 then return end
	local npc = NpcID(Safe(UnitGUID, "npc"))
	if not npc then return end
	local entry = Book()[npc] or {}
	Book()[npc] = entry
	entry.offers = type(entry.offers) == "table" and entry.offers or {}
	entry.receives = type(entry.receives) == "table" and entry.receives or {}
	entry[kind][questID] = true
end

local function IsOnQuest(questID)
	return Clean(Safe(QuestLog.IsOnQuest, questID)) and true or false
end

local function IsDone(questID)
	return Clean(Safe(QuestLog.IsQuestFlaggedCompleted, questID)) and true or false
end

local function IsComplete(questID)
	return Clean(Safe(QuestLog.IsComplete, questID)) and true or false
end

-- Returns "turnin", "giver", "objective" or nil.
function ns.GetQuestStatus(unit, guid, hasObjectiveLines)
	local entry = Book()[NpcID(guid) or 0]
	if entry then
		for questID in pairs(type(entry.receives) == "table" and entry.receives or {}) do
			if IsOnQuest(questID) and IsComplete(questID) then return "turnin" end
		end
		for questID in pairs(type(entry.offers) == "table" and entry.offers or {}) do
			if not IsOnQuest(questID) and not IsDone(questID) then return "giver" end
		end
	end
	if hasObjectiveLines or Clean(Safe(QuestLog.UnitIsRelatedToActiveQuest, unit)) or ns.QuestDrops(guid) then return "objective" end
end

-- Learning from conversations ----------------------------------------------------

local function ScanGossip()
	for _, quest in ipairs(Safe(Gossip.GetAvailableQuests) or {}) do Remember("offers", quest.questID) end
	for _, quest in ipairs(Safe(Gossip.GetActiveQuests) or {}) do Remember("receives", quest.questID) end
end

-- Old-style quest greeting windows (several quests without gossip).
local function ScanGreeting()
	for i = 1, (Clean(Safe(GetNumAvailableQuests)) or 0) do
		local _, _, _, _, questID = Safe(GetAvailableQuestInfo, i)
		Remember("offers", questID)
	end
	for i = 1, (Clean(Safe(GetNumActiveQuests)) or 0) do
		Remember("receives", Safe(GetActiveQuestID, i))
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("QUEST_GREETING")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
pcall(events.RegisterEvent, events, "QUEST_LOG_UPDATE")

-- Once a session, a moment after login: the characters with nothing left in the book leave it. The book
-- is the account's (your alts' givers stay): a quest this character has done is skipped when read, never erased.
local function Prune()
	if not (ns.root and ns.root.questBook) then return end
	for npc, entry in pairs(ns.root.questBook) do
		local offers, receives = type(entry.offers) == "table" and entry.offers, type(entry.receives) == "table" and entry.receives
		if not ((offers and next(offers)) or (receives and next(receives))) then ns.root.questBook[npc] = nil end
	end
end
do
	local login = CreateFrame("Frame")
	login:RegisterEvent("PLAYER_LOGIN")
	login:SetScript("OnEvent", function() C_Timer.After(15, Prune) end)
end

-- Your quests' objectives --------------------------------------------------------------------------------

-- An objective's name alone: "Linen Cloth: 3/10", "- 3/10 Linen Cloth" -> "linen cloth".
function ns.ObjectiveName(text)
	return (text:gsub("\194\160", " "):gsub("^%s*%-%s*", ""):gsub("%d+%s*/%s*%d+", ""):gsub("^[%s:]+", "")
		:gsub("[%s:]+$", ""):lower())
end

-- Every objective of your log, by its name: { text, kind, complete, have, need, quest }. Read when first asked
-- after the log changed; nothing runs otherwise. (The log is never protected, even in a fight.)
local objectives
function ns.QuestObjectives()
	if objectives then return objectives end
	objectives = {}
	if not (QuestLog.GetNumQuestLogEntries and QuestLog.GetInfo and QuestLog.GetQuestObjectives) then return objectives end
	for index = 1, Clean(Safe(QuestLog.GetNumQuestLogEntries)) or 0 do
		local info = Safe(QuestLog.GetInfo, index)
		local id = type(info) == "table" and not Clean(info.isHeader) and Clean(info.questID)
		local list = id and Safe(QuestLog.GetQuestObjectives, id)
		for _, objective in ipairs(type(list) == "table" and list or {}) do
			local text = Clean(objective.text)
			local name = type(text) == "string" and ns.ObjectiveName(text)
			-- (an item to carry kept first: another objective of the same name never hides it)
			if name and name ~= "" and not (objectives[name] and objectives[name].kind == "item") then
				objectives[name] = { text = text, kind = Clean(objective.type), complete = Clean(objective.finished) and true or false,
					have = Clean(objective.numFulfilled) or 0, need = Clean(objective.numRequired) or 0, quest = Clean(info.title) or "" }
			end
		end
	end
	return objectives
end

-- What your quests ask you to carry: an item objective, by the item's name (the game gives no item there).
function ns.QuestNeed(item)
	local name = item and ns.Util.ItemName(item)
	local objective = name and ns.QuestObjectives()[name:lower()]
	return objective and objective.kind == "item" and objective or nil
end

-- What a creature drops for your quests --------------------------------------------------------------------

-- The game marks the creatures a quest asks you to kill, not those that drop what it asks you to carry: an
-- extension that knows the drops tells it (fn(npc id) -> { item id, ... } or nil).
local dropsOf
local dropped = {} -- npc id -> its objectives still to gather, or false (until the log changes)
function ns.QuestUnitDrops(fn)
	dropsOf = type(fn) == "function" and fn or nil
	dropped = {}
end

-- The item objectives of your log a creature drops something for, still to gather: { objective, ... }, else nil.
function ns.QuestDrops(guid)
	if not dropsOf then return nil end
	local npc = NpcID(guid)
	if not npc then return nil end
	if dropped[npc] ~= nil then return dropped[npc] or nil end
	local items = Safe(dropsOf, npc)
	items = type(items) == "table" and items or {}
	local log = items[1] and ns.QuestObjectives() or {}
	local found, unnamed = nil, false
	for _, item in ipairs(items) do
		local name = ns.Util.ItemName(item)
		local objective = name and log[name:lower()]
		if not name then unnamed = true end -- (asked of the game: read again at the next hover)
		if objective and objective.kind == "item" and not objective.complete then
			found = found or {}
			found[#found + 1] = objective
		end
	end
	if not unnamed then dropped[npc] = found or false end
	return found
end

-- (set here, once the objectives' cache is known)
events:SetScript("OnEvent", function(_, event)
	if event == "QUEST_LOG_UPDATE" then
		objectives = nil
		dropped = {}
		return
	end
	if not ns.root then return end
	if event == "GOSSIP_SHOW" then
		ScanGossip()
	elseif event == "QUEST_GREETING" then
		ScanGreeting()
	elseif event == "QUEST_DETAIL" then
		Remember("offers", Safe(GetQuestID))
	else -- QUEST_PROGRESS, QUEST_COMPLETE: the NPC is where this quest is turned in
		Remember("receives", Safe(GetQuestID))
	end
end)
