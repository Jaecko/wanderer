local _, ns = ...
local L = ns.L

-- Mailbox: a "Take all" button opens every letter and takes its gold and its
-- items, one at a time (the game answers each before the next). Letters
-- asking for payment on delivery are left for the player. Only where the
-- game shows no such button of its own; it stops when the bags are full,
-- when the mailbox closes, or on a second click.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local STEP = 0.35 -- seconds between two takes
local MAX_ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16

local button
local running = false
local taken = { money = 0, items = 0 }

local function SetRunning(on)
	running = on
	if button then button:SetText(on and L.MAIL_STOP or L.MAIL_TAKE_ALL) end
end

local function Finish(reason)
	if not running then return end
	SetRunning(false)
	if taken.money > 0 or taken.items > 0 then
		ns.Print(L.MSG_MAIL_TAKEN:format(U.Coins(taken.money), taken.items))
	end
	if reason then ns.Print(reason) end
end

-- The next thing to take: the last letters first, so the indexes stay right.
local function NextTake()
	for index = (Clean(Safe(GetInboxNumItems)) or 0), 1, -1 do
		local _, _, _, _, money, cod = Safe(GetInboxHeaderInfo, index)
		money, cod = Clean(money) or 0, Clean(cod) or 0
		if cod == 0 then
			if money > 0 then return "money", index, money end
			for slot = 1, MAX_ATTACHMENTS do
				if Clean(Safe(GetInboxItem, index, slot)) then return "item", index, slot end
			end
		end
	end
end

local function Step()
	if not running then return end
	if InCombatLockdown() then return Finish() end
	local kind, index, value = NextTake()
	if not kind then return Finish() end
	if kind == "money" then
		Safe(TakeInboxMoney, index)
		taken.money = taken.money + value
	else
		Safe(TakeInboxItem, index, value)
		taken.items = taken.items + 1
	end
	C_Timer.After(STEP, Step)
end

local function Start()
	if running then return Finish() end
	if InCombatLockdown() then return end
	taken.money, taken.items = 0, 0
	SetRunning(true)
	Step()
end

-- The game's own button, when this version of the game has one.
local function GameHasButton()
	return _G.OpenAllMail ~= nil
end

function ns.RefreshMail()
	if button then button:SetShown(ns.db.enabled and not GameHasButton()) end
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
			button:SetScript("OnClick", Start)
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(L.MAIL_TAKE_ALL)
				GameTooltip:AddLine(L.MAIL_TAKE_ALL_DESC, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		ns.RefreshMail()
	end)
end
