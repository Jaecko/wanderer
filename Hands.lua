local _, ns = ...

-- Three things the game makes you do by hand, done for you when asked
-- (options, off until then):
-- * destroying an item no longer asks you to type the word: the confirmation
--   is enough (the word is written for you);
-- * your bags no longer open by themselves at a merchant, a mailbox, a bank
--   or the auction house (the game's own opening, closed again at once; they
--   still open when you ask);
-- * an action refused because you sit or ride: your character stands up, or
--   gets off its mount, so your next try goes through. Shift held skips it.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local DESTROY_DIALOGS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
-- The game's refusals (its own words, found by their names), and what answers them.
local STAND = { "SPELL_FAILED_NOT_STANDING", "ERR_CANTATTACK_NOTSTANDING", "ERR_LOOT_NOTSTANDING" }
local DISMOUNT = { "SPELL_FAILED_NOT_MOUNTED", "ERR_ATTACK_MOUNTED", "ERR_NOT_WHILE_MOUNTED", "ERR_TAXIPLAYERALREADYMOUNTED" }
local AGAIN = 1 -- seconds: one answer for a burst of refusals

local lastAnswer = 0

local function Wanted(key)
	local db = ns.db
	return db and db.enabled and db.hands and db.hands[key] and true or false
end

-- The dialog's "Yes" (its place changed across versions).
local function AcceptButton(dialog)
	local button = dialog.button1 or (type(dialog.ButtonContainer) == "table" and dialog.ButtonContainer.Button1) or nil
	if not button and dialog.GetButton1 then button = Safe(dialog.GetButton1, dialog) end
	return type(button) == "table" and button or nil
end

-- The word written in the dialog's box, once the game has set it up (left to another addon that writes it).
local function FillDestroyWord(which)
	if not (Wanted("easyDestroy") and DELETE_ITEM_CONFIRM_STRING and StaticPopup_FindVisible) or ns.Yields("easyDestroy") then return end
	local dialog = Safe(StaticPopup_FindVisible, which)
	local box = type(dialog) == "table" and U.EditBoxOf(dialog)
	if not (box and box.SetText) then return end
	Safe(box.SetText, box, DELETE_ITEM_CONFIRM_STRING)
	-- (the box's own change checks the word; should "Yes" stay greyed, it is lit once the word is there)
	local accept = AcceptButton(dialog)
	if accept and accept.IsEnabled and accept.Enable and not Safe(accept.IsEnabled, accept)
		and Clean(Safe(box.GetText, box)) == DELETE_ITEM_CONFIRM_STRING then
		Safe(accept.Enable, accept)
	end
end

local function Among(message, names)
	for _, name in ipairs(names) do
		local text = _G[name]
		if type(text) == "string" and text ~= "" and text == message then return true end
	end
	return false
end

local function Answer(message)
	if not Wanted("standUp") or U.IsSkipping() or InCombatLockdown() then return end
	if GetTime() - lastAnswer < AGAIN then return end
	if Among(message, STAND) then
		lastAnswer = GetTime()
		Safe(DoEmote, "STAND")
	elseif Among(message, DISMOUNT) and Clean(Safe(IsMounted)) and not Clean(Safe(IsFlying)) then
		lastAnswer = GetTime()
		Safe(Dismount)
	end
end

function ns.InitHands()
	if StaticPopup_Show then
		hooksecurefunc("StaticPopup_Show", function(which)
			if DESTROY_DIALOGS[which] then C_Timer.After(0, function() FillDestroyWord(which) end) end
		end)
	end
	-- The game opens the bags for its windows through one call, with the window asking (your key gives none):
	-- closed again right after, within the same frame. Nothing of the game's is replaced.
	local function CloseAgain(frame)
		if frame and Wanted("bagsClosed") and CloseAllBags then Safe(CloseAllBags, frame) end
	end
	for _, name in ipairs({ "OpenAllBagsMatchingContext", "OpenAllBags" }) do
		if type(_G[name]) == "function" then hooksecurefunc(name, CloseAgain) end
	end
	local events = CreateFrame("Frame")
	events:RegisterEvent("UI_ERROR_MESSAGE")
	events:SetScript("OnEvent", function(_, _, _, message) Answer(Clean(message)) end)
end
