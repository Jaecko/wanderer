local _, ns = ...
local L = ns.L

-- Mailbox: a "Take all" button opens every letter and takes its gold and its
-- items, one at a time (the game answers each before the next). Letters
-- asking for payment on delivery are left for the player. Only where the
-- game shows no such button of its own; it stops when the bags are full,
-- when the mailbox closes, or on a second click.
--
-- "Take the gold" takes only the gold of the letters, and leaves the rest
-- (items, letters without gold, payment on delivery): the game has no such
-- button, so it is always there.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local STEP = 0.35 -- seconds between two takes
local MAX_ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16

local button, goldButton
local running = false -- "all", "gold" or false
local taken = { money = 0, items = 0 }

local function SetRunning(mode)
	running = mode
	if button then button:SetText(mode == "all" and L.MAIL_STOP or L.MAIL_TAKE_ALL) end
	if goldButton then goldButton:SetText(mode == "gold" and L.MAIL_STOP or L.MAIL_TAKE_GOLD) end
end

local function Finish(reason)
	if not running then return end
	SetRunning(false)
	-- The gold really received, whatever the game refused.
	local now = Clean(Safe(GetMoney))
	taken.money = (now and taken.start) and math.max(0, now - taken.start) or 0
	if taken.money > 0 or taken.items > 0 then
		ns.Print(L.MSG_MAIL_TAKEN:format(U.Coins(taken.money), taken.items))
	end
	if reason then ns.Print(reason) end
end

-- The next thing to take: the last letters first, so the indexes stay right.
local tries = {} -- "kind:index:slot" -> times asked, during one run
local MAX_TRIES = 3

local function NextTake()
	local function Wanted(kind, index, value)
		return (tries[kind .. ":" .. index .. ":" .. value] or 0) < MAX_TRIES
	end
	for index = (Clean(Safe(GetInboxNumItems)) or 0), 1, -1 do
		local _, _, _, _, money, cod = Safe(GetInboxHeaderInfo, index)
		money, cod = Clean(money) or 0, Clean(cod) or 0
		if cod == 0 then
			if money > 0 and Wanted("money", index, 0) then return "money", index, money end
			-- The gold only: the items of the letter are left as they are.
			if running ~= "gold" then
				for slot = 1, MAX_ATTACHMENTS do
					if Clean(Safe(GetInboxItem, index, slot)) and Wanted("item", index, slot) then return "item", index, slot end
				end
			end
		end
	end
end

local function Step()
	if not running then return end
	if InCombatLockdown() then return Finish() end
	local kind, index, value = NextTake()
	if not kind then return Finish() end
	local key = kind .. ":" .. index .. ":" .. (kind == "money" and 0 or value)
	local first = tries[key] == nil
	tries[key] = (tries[key] or 0) + 1
	if kind == "money" then
		Safe(TakeInboxMoney, index)
	else
		Safe(TakeInboxItem, index, value)
		if first then taken.items = taken.items + 1 end
	end
	C_Timer.After(STEP, Step)
end

local function Start(mode)
	if running then return Finish() end
	if InCombatLockdown() then return end
	taken.money, taken.items = 0, 0
	taken.start = Clean(Safe(GetMoney))
	wipe(tries)
	SetRunning(mode)
	Step()
end

local function Hint(owner, title, text)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The game's own button, when this version of the game has one.
local function GameHasButton()
	return _G.OpenAllMail ~= nil
end

function ns.RefreshMail()
	if button then button:SetShown(ns.db.enabled and not GameHasButton()) end
	if goldButton then goldButton:SetShown(ns.db.enabled and true or false) end
end

function ns.InitMail()
	local events = CreateFrame("Frame")
	events:RegisterEvent("MAIL_SHOW")
	events:RegisterEvent("MAIL_CLOSED")
	events:RegisterEvent("UI_ERROR_MESSAGE")
	events:SetScript("OnEvent", function(_, event, _, message)
		if event == "MAIL_CLOSED" then return Finish() end
		if event == "UI_ERROR_MESSAGE" then
			-- Bags full: no use going on.
			if running and ERR_INV_FULL and message == ERR_INV_FULL then Finish(L.MSG_MAIL_FULL) end
			return
		end
		if not button and InboxFrame and not GameHasButton() then
			button = CreateFrame("Button", "WandererTakeAllMail", InboxFrame, "UIPanelButtonTemplate")
			button:SetSize(120, 24)
			button:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -10, 100)
			button:SetText(L.MAIL_TAKE_ALL)
			button:SetScript("OnClick", function() Start("all") end)
			Hint(button, L.MAIL_TAKE_ALL, L.MAIL_TAKE_ALL_DESC)
		end
		-- On the row of the tabs, at the right (the inbox's own buttons fill its bottom):
		-- shown with the inbox only.
		if not goldButton and InboxFrame then
			goldButton = CreateFrame("Button", "WandererTakeGoldMail", InboxFrame, "UIPanelButtonTemplate")
			goldButton:SetSize(120, 24)
			-- Right after the last tab ("Send mail"), never over it.
			local tab = _G.MailFrameTab2
			if tab then
				goldButton:SetPoint("LEFT", tab, "RIGHT", 8, 0)
			else
				goldButton:SetPoint("TOPRIGHT", _G.MailFrame or InboxFrame, "BOTTOMRIGHT", -8, -2)
			end
			goldButton:SetText(L.MAIL_TAKE_GOLD)
			goldButton:SetWidth(math.max(90, U.Measure(goldButton:GetFontString() or goldButton, "GetStringWidth", 80) + 28))
			goldButton:SetScript("OnClick", function() Start("gold") end)
			Hint(goldButton, L.MAIL_TAKE_GOLD, L.MAIL_TAKE_GOLD_DESC)
		end
		ns.RefreshMail()
	end)
end
