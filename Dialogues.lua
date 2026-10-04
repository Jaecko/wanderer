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

function ns.WasAnswered(event)
	return answered[event] == true
end

local function Settings()
	local db = ns.db
	if not (db and db.enabled) or U.IsSkipping() then return end
	return db.quest
end

-- Gossip window: finished quests first, then new ones, then a single choice.
local function OnGossip(db)
	if db.autoTurnIn then
		for _, quest in ipairs(Safe(Gossip.GetActiveQuests) or {}) do
			if quest.isComplete then Safe(Gossip.SelectActiveQuest, quest.questID) return true end
		end
	end
	local available = Safe(Gossip.GetAvailableQuests) or {}
	if db.autoAccept then
		for _, quest in ipairs(available) do
			-- Grey (trivial) quests stay for the player to decide.
			if not quest.isTrivial then Safe(Gossip.SelectAvailableQuest, quest.questID) return true end
		end
	end
	if db.skipGossip and not available[1] and not (Safe(Gossip.GetActiveQuests) or {})[1] then
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
			if complete then Safe(SelectActiveQuest, index) return true end
		end
	end
	if db.autoAccept then
		for index = 1, (Clean(Safe(GetNumAvailableQuests)) or 0) do
			local isTrivial = Safe(GetAvailableQuestInfo, index)
			if not isTrivial then Safe(SelectAvailableQuest, index) return true end
		end
	end
end

-- Coin on the reward that sells for the most.
local marked = {}
local function ClearMarks()
	for _, coin in pairs(marked) do coin:Hide() end
end

local function MarkBestReward()
	ClearMarks()
	local count = Clean(Safe(GetNumQuestChoices)) or 0
	if count < 2 or not QuestInfo_GetRewardButton or not QuestInfoFrame then return end
	local best, bestPrice = nil, 0
	for index = 1, count do
		local link = Safe(GetQuestItemLink, "choice", index)
		local price = link and select(11, Safe(C_Item and C_Item.GetItemInfo or GetItemInfo, link))
		price = Clean(price) or 0
		if price > bestPrice then best, bestPrice = index, price end
	end
	local rewardButton = best and Safe(QuestInfo_GetRewardButton, QuestInfoFrame.rewardsFrame, best)
	if not rewardButton then return end
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
		else
			Safe(AcceptQuest)
		end
		acted = true
	elseif event == "QUEST_PROGRESS" and db.autoTurnIn then
		-- A quest asking for gold stays for the player to decide.
		if Clean(Safe(IsQuestCompletable)) and (Clean(Safe(GetQuestMoneyToGet)) or 0) == 0 then
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
