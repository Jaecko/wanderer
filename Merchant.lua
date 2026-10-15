local _, ns = ...
local L = ns.L

-- At merchants:
-- * repair: everything is repaired (with the guild bank first if chosen) and
--   the cost is written in the chat;
-- * quick sale of junk: at a merchant who buys items (the game shows its
--   "Sell all junk" button), the poor quality items (grey) are sold by
--   themselves, one by one, and the gain is written in the chat.
-- Holding Shift while opening the merchant does nothing automatically.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local SELL_DELAY = 0.15 -- seconds between two items, as the server expects
local MAX_ITEMS = 120 -- safety: never more than the bags can hold
local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

local frame
local queue, sinceSell, startMoney = {}, 0, nil
local open = false -- the merchant window is there

-- The merchant buys items: the game shows its junk button only then. Clients
-- without this button rely on the server's answer (ERR_VENDOR_DOESNT_BUY).
local function MerchantBuys()
	local button = _G.MerchantSellAllJunkButton
	if button then return button:IsShown() end
	return true
end

local Container = C_Container or {}

-- What is junk: grey, unless an extension says otherwise (an item kept, or
-- marked as junk by the player): rule(item id, quality) -> true, false or nil.
local junkRules = {}
function ns.AddJunkRule(rule)
	if type(rule) == "function" then junkRules[#junkRules + 1] = rule end
end

local function IsJunk(info)
	for _, rule in ipairs(junkRules) do
		local ok, verdict = pcall(rule, Clean(info.itemID), Clean(info.quality))
		if ok and verdict ~= nil then return verdict end
	end
	return info.quality == POOR
end

-- Junk with a value, in bag order.
local function FindJunk()
	local found = {}
	U.EachBagItem(function(bag, slot, info)
		if #found < MAX_ITEMS and IsJunk(info) and not info.hasNoValue and not info.isLocked then
			found[#found + 1] = { bag = bag, slot = slot, id = info.itemID }
		end
	end)
	return found
end

local Coins = U.Coins

local function Stop()
	wipe(queue)
	frame:SetScript("OnUpdate", nil)
	if startMoney then
		local gain = (Clean(Safe(GetMoney)) or startMoney) - startMoney
		if gain > 0 then ns.Print(L.MSG_JUNK_SOLD:format(Coins(gain))) end
	end
	startMoney = nil
end

local function OnUpdate(_, elapsed)
	if not open then return Stop() end
	sinceSell = sinceSell + elapsed
	if sinceSell < SELL_DELAY then return end
	sinceSell = 0
	local item = table.remove(queue, 1)
	if not item then return Stop() end
	-- The slot is checked again: the bags may have changed in between.
	local info = Safe(Container.GetContainerItemInfo, item.bag, item.slot)
	if type(info) == "table" and info.itemID == item.id and not info.isLocked then
		if open then Safe(Container.UseContainerItem, item.bag, item.slot) end
	end
	if not queue[1] then
		-- The last sale needs a moment before the money is counted.
		C_Timer.After(0.5, function() if not queue[1] then Stop() end end)
		frame:SetScript("OnUpdate", nil)
	end
end

-- Repairs with the guild bank when allowed and chosen, else with your gold.
local function Repair()
	local db = ns.db.merchant
	if not (db.repair and Clean(Safe(CanMerchantRepair))) then return end
	local cost, canRepair = Safe(GetRepairAllCost)
	cost = Clean(cost)
	if not (cost and cost > 0 and canRepair) then return end
	if db.guildRepair and Clean(Safe(CanGuildBankRepair)) then
		local allowance = Clean(Safe(GetGuildBankWithdrawMoney)) or 0
		-- -1: no limit (guild master).
		if allowance == -1 or allowance >= cost then
			Safe(RepairAllItems, true)
			ns.Print(L.MSG_REPAIRED_GUILD:format(Coins(cost)))
			return
		end
	end
	if (Clean(Safe(GetMoney)) or 0) < cost then
		ns.Print(L.MSG_REPAIR_NO_MONEY:format(Coins(cost)))
		return
	end
	Safe(RepairAllItems, false)
	ns.Print(L.MSG_REPAIRED:format(Coins(cost)))
end

ns.FindJunk = FindJunk

-- Items to sell, chosen elsewhere ({ bag, slot, id }): sold one by one, the gain said. False when no merchant buys.
function ns.SellItems(items)
	if not (open and frame and MerchantBuys()) or type(items) ~= "table" or not items[1] then return false end
	for _, item in ipairs(items) do
		if #queue >= MAX_ITEMS then break end
		queue[#queue + 1] = { bag = item.bag, slot = item.slot, id = item.id }
	end
	startMoney = startMoney or Clean(Safe(GetMoney))
	sinceSell = SELL_DELAY
	frame:SetScript("OnUpdate", OnUpdate)
	return true
end

function ns.IsMerchantOpen() return open end

-- The junk being sold (its gain counted from your money): others wait before spending.
function ns.IsSellingJunk() return queue[1] ~= nil or startMoney ~= nil end

local function Start()
	if not (open and ns.db and ns.db.enabled and ns.db.merchant.sellJunk) then return end
	if not MerchantBuys() then return end
	local junk = FindJunk()
	if not junk[1] then return end
	queue, sinceSell, startMoney = junk, SELL_DELAY, Clean(Safe(GetMoney))
	frame:SetScript("OnUpdate", OnUpdate)
end

function ns.InitMerchant()
	frame = CreateFrame("Frame")
	frame:RegisterEvent("MERCHANT_SHOW")
	frame:RegisterEvent("MERCHANT_CLOSED")
	frame:RegisterEvent("UI_ERROR_MESSAGE")
	frame:SetScript("OnEvent", function(_, event, _, message)
		if event == "MERCHANT_SHOW" then
			open = true
			if not (ns.db and ns.db.enabled) or U.IsSkipping() then return end
			-- The merchant window sets up its buttons first; the junk is sold once
			-- the repair is paid, so the gain counted is the sale's alone.
			C_Timer.After(0, function()
				if not open then return end
				Repair()
				C_Timer.After(0.3, Start)
			end)
		elseif event == "MERCHANT_CLOSED" then
			open = false
			if queue[1] or startMoney then Stop() end
		elseif queue[1] and (message == ERR_VENDOR_DOESNT_BUY or message == ERR_TOO_MUCH_GOLD) then
			Stop()
		end
	end)
end
