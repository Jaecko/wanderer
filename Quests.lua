local _, ns = ...

-- Quest status of the hovered character.
-- * Objective: asked directly to the game.
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
	local entry = Book()[npc] or { offers = {}, receives = {} }
	Book()[npc] = entry
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
		for questID in pairs(entry.receives) do
			if IsOnQuest(questID) and IsComplete(questID) then return "turnin" end
		end
		for questID in pairs(entry.offers) do
			if not IsOnQuest(questID) and not IsDone(questID) then return "giver" end
		end
	end
	if hasObjectiveLines or Clean(Safe(QuestLog.UnitIsRelatedToActiveQuest, unit)) then return "objective" end
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
events:SetScript("OnEvent", function(_, event)
	if not ns.root or event == "QUEST_LOG_UPDATE" then return end
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

-- Once a session, a moment after login: the quests you have done leave the book (never offered nor taken back
-- again), and the characters with nothing left in it too. A repeatable one comes back the next time you talk.
local function Prune()
	if not (ns.root and ns.root.questBook) then return end
	for npc, entry in pairs(ns.root.questBook) do
		local left = false
		for _, kind in ipairs({ "offers", "receives" }) do
			for questID in pairs(type(entry[kind]) == "table" and entry[kind] or {}) do
				if IsDone(questID) then entry[kind][questID] = nil else left = true end
			end
		end
		if not left then ns.root.questBook[npc] = nil end
	end
end
do
	local login = CreateFrame("Frame")
	login:RegisterEvent("PLAYER_LOGIN")
	login:SetScript("OnEvent", function() C_Timer.After(15, Prune) end)
end

-- What your quests ask you to carry --------------------------------------------------------------------

-- Their item objectives, by the item's name (the game gives no item there): { quest, have, need }. Read when
-- first asked after the log changed; nothing runs otherwise.
local needs
local function ReadNeeds()
	needs = {}
	if not (QuestLog.GetNumQuestLogEntries and QuestLog.GetInfo and QuestLog.GetQuestObjectives) then return end
	for index = 1, Clean(Safe(QuestLog.GetNumQuestLogEntries)) or 0 do
		local info = Safe(QuestLog.GetInfo, index)
		local id = type(info) == "table" and not Clean(info.isHeader) and Clean(info.questID)
		local objectives = id and Safe(QuestLog.GetQuestObjectives, id)
		for _, objective in ipairs(type(objectives) == "table" and objectives or {}) do
			local text = Clean(objective.text)
			if Clean(objective.type) == "item" and type(text) == "string" then
				-- "Linen Cloth: 3/10", "3/10 Linen Cloth": the name alone
				local name = text:gsub("\194\160", " "):gsub("%d+%s*/%s*%d+", ""):gsub("^[%s:]+", ""):gsub("[%s:]+$", ""):lower()
				if name ~= "" then
					needs[name] = { quest = Clean(info.title) or "", have = Clean(objective.numFulfilled) or 0,
						need = Clean(objective.numRequired) or 0 }
				end
			end
		end
	end
end

function ns.QuestNeed(item)
	local name = item and ns.Util.ItemName(item)
	if not name then return nil end
	if not needs then ReadNeeds() end
	return needs[name:lower()]
end

pcall(events.RegisterEvent, events, "QUEST_LOG_UPDATE")
events:HookScript("OnEvent", function(_, event) if event == "QUEST_LOG_UPDATE" then needs = nil end end)
