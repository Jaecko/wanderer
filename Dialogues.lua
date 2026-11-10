local _, ns = ...

-- Conversations with NPCs:
-- * quests accepted and handed in by themselves (never when a reward must be
--   chosen, nor when the quest asks for gold);
-- * the reward that sells for the most is marked with a coin when you choose;
-- * a dialogue with a single plain choice is passed (flight master, banker...).
-- Holding Shift while talking keeps everything manual.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local Gossip = C_GossipInfo or {}
local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"

-- Pages answered by themselves: the scene does not show them. Only the
-- latest page of each kind counts (a page shown again starts unanswered).
local answered = {} -- event -> true when its latest page was answered
local trivialSeen = {} -- questID -> true: offered grey in a gossip or greeting window

function ns.WasAnswered(event)
	return answered[event] == true
end

local function Settings()
	local db = ns.db
	if not (db and db.enabled) or U.IsSkipping() then return end
	-- (another addon accepting quests or passing dialogues: left to it, whatever was set here)
	local auto = ns.Yields and ns.Yields("questAuto")
	local skip = ns.Yields and ns.Yields("skipGossip")
	if not (auto or skip) then return db.quest end
	return setmetatable({ autoAccept = not auto and db.quest.autoAccept, autoTurnIn = not auto and db.quest.autoTurnIn,
		skipGossip = not skip and db.quest.skipGossip }, { __index = db.quest })
end

-- Gossip window: finished quests first, then new ones, then a single choice.
local function OnGossip(db)
	if db.autoTurnIn then
		for _, quest in ipairs(Safe(Gossip.GetActiveQuests) or {}) do
			-- (repeatable turn-ins, cloth donations and the like, stay for the player: no loop through a stack)
			if quest.isComplete and not quest.repeatable then Safe(Gossip.SelectActiveQuest, quest.questID) return true end
		end
	end
	local available = Safe(Gossip.GetAvailableQuests) or {}
	for _, quest in ipairs(available) do
		if quest.isTrivial and quest.questID then trivialSeen[quest.questID] = true end
	end
	if db.autoAccept then
		for _, quest in ipairs(available) do
			-- Grey (trivial) and repeatable quests stay for the player to decide.
			if not quest.isTrivial and not quest.repeatable then Safe(Gossip.SelectAvailableQuest, quest.questID) return true end
		end
	end
	-- (never in an instance: a single "I am ready" there starts an escort or an encounter)
	if db.skipGossip and not available[1] and not (Safe(Gossip.GetActiveQuests) or {})[1]
		and not Clean(Safe(IsInInstance)) then
		local options = Safe(Gossip.GetOptions) or {}
		local option = options[1]
		-- Only a plain choice: no spell, no cost, nothing to confirm.
		if #options == 1 and option.gossipOptionID and not option.spellID
			and not (option.rewards and option.rewards[1]) and (option.flags or 0) == 0 then
			Safe(Gossip.SelectOption, option.gossipOptionID)
			return true
		end
	end
end

-- Old-style greeting window (several quests without gossip).
local function OnGreeting(db)
	if db.autoTurnIn then
		for index = 1, (Clean(Safe(GetNumActiveQuests)) or 0) do
			local _, complete = Safe(GetActiveTitle, index)
			-- (repeatable turn-ins stay for the player, as in the gossip window)
			local id = GetActiveQuestID and Clean(Safe(GetActiveQuestID, index))
			local repeatable = id and C_QuestLog and C_QuestLog.IsRepeatableQuest and Clean(Safe(C_QuestLog.IsRepeatableQuest, id))
			if Clean(complete) and not repeatable then Safe(SelectActiveQuest, index) return true end
		end
	end
	for index = 1, (Clean(Safe(GetNumAvailableQuests)) or 0) do
		local isTrivial, _, isRepeatable, _, questID = Safe(GetAvailableQuestInfo, index)
		questID = Clean(questID)
		if isTrivial and questID then trivialSeen[questID] = true end
		if db.autoAccept and not isTrivial and not Clean(isRepeatable) then Safe(SelectAvailableQuest, index) return true end
	end
end

-- The quest shown is a grey one: the game says it when it can, else the
-- gossip or greeting window offered it grey (a quest opened by clicking it there).
local function IsTrivialDetail()
	local questID = Clean(Safe(GetQuestID))
	if not questID or questID == 0 then return false end
	if C_QuestLog and C_QuestLog.IsQuestTrivial and Clean(Safe(C_QuestLog.IsQuestTrivial, questID)) then return true end
	return trivialSeen[questID] == true
end

local function IsRepeatableDetail()
	local questID = Clean(Safe(GetQuestID))
	local isRepeatable = C_QuestLog and C_QuestLog.IsRepeatableQuest
	if not (questID and questID ~= 0 and isRepeatable) then return false end
	return Clean(Safe(isRepeatable, questID)) == true
end

-- Coin on the reward that sells for the most.
local marked = {}
local function ClearMarks()
	for _, coin in pairs(marked) do coin:Hide() end
end

local function MarkBestReward()
	ClearMarks()
	local count = Clean(Safe(GetNumQuestChoices)) or 0
	local rewards = QuestInfoFrame and rawget(QuestInfoFrame, "rewardsFrame")
	if count < 2 or type(rewards) ~= "table" then return end
	local best, bestPrice = nil, 0
	for index = 1, count do
		-- (the whole reward: its price times how many it gives)
		local _, _, many = Safe(GetQuestItemInfo, "choice", index)
		local price = (U.SellPrice(Safe(GetQuestItemLink, "choice", index)) or 0) * (Clean(many) or 1)
		if price > bestPrice then best, bestPrice = index, price end
	end
	-- (the game's own button, read where the game keeps it: never made by Wanderer, which would leave its mark on
	-- it and on the tooltips it opens, the money in them refused)
	local buttons = rawget(rewards, "RewardButtons")
	local rewardButton = best and type(buttons) == "table" and buttons[best]
	if type(rewardButton) ~= "table" or not rewardButton.CreateTexture or not rewardButton:IsShown() then return end
	local coin = marked[rewardButton]
	if not coin then
		coin = rewardButton:CreateTexture(nil, "OVERLAY", nil, 7)
		coin:SetSize(16, 16)
		coin:SetPoint("TOPLEFT", rewardButton, "TOPLEFT", -2, 2)
		coin:SetTexture(COIN_TEXTURE)
		marked[rewardButton] = coin
	end
	coin:Show()
end

local function OnEvent(_, event)
	answered[event] = nil
	if event == "QUEST_FINISHED" then return ClearMarks() end
	if event == "QUEST_COMPLETE" and ns.db and ns.db.enabled and ns.db.quest.bestReward then
		-- The reward buttons are laid out by the game first.
		C_Timer.After(0, MarkBestReward)
	end
	local db = Settings()
	if not db then return end
	local acted = false
	if event == "GOSSIP_SHOW" then
		acted = OnGossip(db)
	elseif event == "QUEST_GREETING" then
		acted = OnGreeting(db)
	elseif event == "QUEST_DETAIL" and db.autoAccept then
		if Clean(Safe(QuestGetAutoAccept)) then
			Safe(AcknowledgeAutoAcceptQuest)
			acted = true
		elseif not IsTrivialDetail() and not IsRepeatableDetail() then
			-- Grey (trivial) and repeatable quests stay for the player to decide, as in the gossip window.
			Safe(AcceptQuest)
			acted = true
		end
	elseif event == "QUEST_PROGRESS" and db.autoTurnIn then
		-- A quest asking for gold, or a repeatable one (it would spend a whole stack), stays for the player.
		if Clean(Safe(IsQuestCompletable)) and (Clean(Safe(GetQuestMoneyToGet)) or 0) == 0 and not IsRepeatableDetail() then
			Safe(CompleteQuest)
			acted = true
		end
	elseif event == "QUEST_COMPLETE" and db.autoTurnIn then
		local choices = Clean(Safe(GetNumQuestChoices)) or 0
		if choices <= 1 then
			Safe(GetQuestReward, choices)
			acted = true
		end
	end
	if acted then answered[event] = true end
end

function ns.InitDialogues()
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
		"QUEST_FINISHED" }) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", OnEvent)
end
