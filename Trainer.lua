local _, ns = ...
local L = ns.L

-- "Learn all" button on the trainers' window: buys every skill that can be
-- learned now and that you can afford, cheapest first.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local button

-- Skills that can be learned now: { index, cost }, cheapest first.
local function Learnable()
	local list = {}
	for index = 1, (Clean(Safe(GetNumTrainerServices)) or 0) do
		local _, _, category = Safe(GetTrainerServiceInfo, index)
		if category == "available" then
			list[#list + 1] = { index = index, cost = Clean(Safe(GetTrainerServiceCost, index)) or 0 }
		end
	end
	table.sort(list, function(a, b) return a.cost < b.cost end)
	return list
end

local function Update()
	if not button then return end
	local shown = ns.db and ns.db.enabled and ns.db.trainer.learnAll
	button:SetShown(shown and true or false)
	if not shown then return end
	local count = #Learnable()
	button:SetText(L.TRAINER_LEARN_ALL:format(count))
	button:SetEnabled(count > 0)
end

-- Bought from the highest index down: the indices of the others stay right.
local function LearnAll()
	local money = Clean(Safe(GetMoney)) or 0
	local chosen, total = {}, 0
	for _, skill in ipairs(Learnable()) do
		if total + skill.cost <= money then
			chosen[#chosen + 1] = skill.index
			total = total + skill.cost
		end
	end
	table.sort(chosen, function(a, b) return a > b end)
	for _, index in ipairs(chosen) do Safe(BuyTrainerService, index) end
	if #chosen > 0 then ns.Print(L.MSG_TRAINER_LEARNED:format(#chosen)) end
	C_Timer.After(0.5, Update)
end

-- The trainers' window is loaded by the game on the first visit.
local function CreateButton()
	local window = _G.ClassTrainerFrame
	if button or not window then return end
	button = CreateFrame("Button", "WandererLearnAllButton", window, "UIPanelButtonTemplate")
	button:SetSize(140, 22)
	local train = _G.ClassTrainerTrainButton
	if train then
		button:SetPoint("RIGHT", train, "LEFT", -4, 0)
	else
		button:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -100, 4)
	end
	button:SetScript("OnClick", LearnAll)
	Update()
end

function ns.InitTrainer()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("TRAINER_SHOW")
	frame:RegisterEvent("TRAINER_UPDATE")
	frame:SetScript("OnEvent", function()
		CreateButton()
		Update()
	end)
end

function ns.RefreshTrainer() Update() end
