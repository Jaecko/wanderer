local _, ns = ...
local L = ns.L

-- "Learn all" button on the trainers' window: buys every skill listed that can
-- be learned now and that you can afford, cheapest first. Headers closed by the
-- player stay closed (their skills are not counted): opening them here would
-- send the game's TRAINER_UPDATE again at each change.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local button
local learning = false -- a Learn all buying now (its button kept off until it is done)

-- Skills that can be learned now: { index, cost, name, sub }.
local function Learnable()
	local list = {}
	for index = 1, (Clean(Safe(GetNumTrainerServices)) or 0) do
		local name, sub, state = U.TrainerService(index)
		if state == "available" then
			list[#list + 1] = { index = index, cost = Clean(Safe(GetTrainerServiceCost, index)) or 0, name = name, sub = sub }
		end
	end
	return list
end

-- (an extension showing the trainers in its own window, Wanderer Training: its buttons buy there)
local function Replaced() return ns.Yields("trainerWindow") ~= nil end

local function Update()
	if not button then return end
	local shown = ns.db and ns.db.enabled and ns.db.trainer.learnAll and not Replaced()
	button:SetShown(shown and true or false)
	if not shown then return end
	-- (what Learn all buys: as far as your gold goes)
	local count = #U.TrainerPlan(Learnable())
	button:SetText(L.TRAINER_LEARN_ALL:format(count))
	button:SetEnabled(count > 0 and not learning)
end

-- The cheapest first while your gold lasts (Wanderer's plan, as Wanderer Training's), one after the other while
-- the trainer is open; what was really bought said at the end.
local open = false
local function LearnAll()
	if learning then return end
	learning = true
	button:SetEnabled(false)
	U.LearnServices((U.TrainerPlan(Learnable())), function(bought)
		learning = false
		if bought > 0 then ns.Print(L.MSG_TRAINER_LEARNED:format(bought)) end
		C_Timer.After(0.5, Update)
	end, function() return open end)
end

-- What Learn all costs (as far as your gold goes).
local function Cost()
	local chosen, spent = U.TrainerPlan(Learnable())
	if not chosen[1] then return nil end
	return { L.TRAINER_LEARN_ALL:format(#chosen), ((_G.COSTS_LABEL and (_G.COSTS_LABEL .. " ")) or "") .. U.Coins(spent) }
end

-- The trainers' window is loaded by the game on the first visit.
local function CreateButton()
	local window = _G.ClassTrainerFrame
	if button or not window then return end
	button = ns.Skin.GameButton(window, "WandererLearnAllButton", L.TRAINER_LEARN_ALL:format(0), LearnAll)
	button:SetSize(140, 22)
	ns.Skin.Tooltip(button, Cost, "ANCHOR_TOP")
	local train = _G.ClassTrainerTrainButton
	if train then
		button:SetPoint("RIGHT", train, "LEFT", -4, 0)
	else
		button:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -100, 4)
	end
	Update()
end

function ns.InitTrainer()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("TRAINER_SHOW")
	frame:RegisterEvent("TRAINER_UPDATE")
	pcall(frame.RegisterEvent, frame, "TRAINER_CLOSED")
	frame:SetScript("OnEvent", function(_, event)
		open = event ~= "TRAINER_CLOSED"
		if not open then return end
		CreateButton()
		Update()
	end)
end

function ns.RefreshTrainer() Update() end
