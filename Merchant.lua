local _, ns = ...
local saidWaiting = 0 -- the junk waiting for a click, as last said
local L = ns.L

-- At merchants:
-- * repair: everything is repaired (with the guild bank first if chosen) and
--   the cost is written in the chat;
-- * quick sale of junk: at a merchant who buys items (the game shows its
--   "Sell all junk" button), the poor quality items (grey) are sold by
--   themselves, one by one, and the gain is written in the chat. Better items
--   go by themselves only when you marked them junk yourself (Wanderer Bags);
--   one an addon made junk (Wanderer Auction) waits for your click.
-- Holding Shift while opening the merchant does nothing automatically. Another
-- addon repairing or selling the junk itself does it alone (Compat.lua).

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local SELL_DELAY = 0.15 -- seconds between two items, as the server expects
local MAX_ITEMS = 120 -- safety: never more than the bags can hold
local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

local frame
local queue, sinceSell, startMoney = {}, 0, nil
local earned = 0 -- what the items sold are worth (the money itself may come later than the last sale)
local repairAfterSale = false -- the repair waits for the junk's gold
local open = false -- the merchant window is there

-- The merchant buys items: the game shows its junk button only then. Clients
-- without this button rely on the server's answer (ERR_VENDOR_DOESNT_BUY).
local function MerchantBuys()
	local button = _G.MerchantSellAllJunkButton
	if button then return button:IsShown() end
	return true
end

local Container = C_Container or {}

-- What is junk: grey, unless an extension says otherwise: rule(item id, quality) -> true (junk: marked so by
-- the player), false (never: kept), "ask" (junk, but sold only by a click: made junk by an addon, not by
-- you) or nil (no say). Whatever their order: false wins, then "ask", then true.
local junkRules = {}
function ns.AddJunkRule(rule)
	if type(rule) == "function" then junkRules[#junkRules + 1] = rule end
end

-- True, "ask" or false.
local function IsJunk(info)
	local quality = Clean(info.quality)
	local verdict
	for _, rule in ipairs(junkRules) do
		local ok, said = pcall(rule, Clean(info.itemID), quality)
		if ok and said == false then return false end
		if ok and (said == "ask" or (said == true and verdict == nil)) then verdict = said end
	end
	if verdict ~= nil then return verdict end
	return quality == POOR
end
ns.IsJunk = IsJunk -- (tests)

-- Junk with a value, in bag order. automatic: only what may go by itself (no "ask"); then how many of the
-- "ask" ones were left for your click.
local function FindJunk(automatic)
	local found, asked = {}, 0
	U.EachBagItem(function(bag, slot, info)
		local junk = IsJunk(info)
		if not junk or Clean(info.hasNoValue) or Clean(info.isLocked) then return end
		if automatic and junk == "ask" then
			asked = asked + 1
		elseif #found < MAX_ITEMS then
			found[#found + 1] = { bag = bag, slot = slot, id = Clean(info.itemID) }
		end
	end)
	return found, asked
end

local Coins = U.Coins

local Repair

local function Stop()
	wipe(queue)
	frame:SetScript("OnUpdate", nil)
	if startMoney then
		local gain = math.max((Clean(Safe(GetMoney)) or startMoney) - startMoney, earned)
		if gain > 0 then ns.Print(L.MSG_JUNK_SOLD:format(Coins(gain))) end
	end
	startMoney, earned = nil, 0
	-- (Fill up waited for the sale to be counted)
	ns.RefreshProvisions()
	if repairAfterSale then
		repairAfterSale = false
		if open then Repair() end
	end
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
	if type(info) == "table" and Clean(info.itemID) == item.id and not Clean(info.isLocked) then
		Safe(Container.UseContainerItem, item.bag, item.slot)
		earned = earned + (U.SellPrice(Clean(info.hyperlink)) or 0) * (Clean(info.stackCount) or 1)
	end
	if not queue[1] then
		-- The last sale needs a moment before the money is counted.
		C_Timer.After(0.5, function() if not queue[1] then Stop() end end)
		frame:SetScript("OnUpdate", nil)
	end
end

local function RepairCost()
	local cost, canRepair = Safe(GetRepairAllCost)
	cost = Clean(cost)
	return cost and cost > 0 and Clean(canRepair) and cost or nil
end

local function RepairWithGold(cost)
	if (Clean(Safe(GetMoney)) or 0) < cost then
		ns.Print(L.MSG_REPAIR_NO_MONEY:format(Coins(cost)))
		return
	end
	Safe(RepairAllItems, false)
	ns.Print(L.MSG_REPAIRED:format(Coins(cost)))
end

-- The guild's repair asked for (cost): judged once, when the server answers (your durability told
-- again) or after 1.5 s at the latest (a slow server: never your gold paying what the guild was about to).
local guildAsked
local function JudgeGuildRepair()
	local cost = guildAsked
	guildAsked = nil
	if not (cost and open) then return end
	local left = RepairCost()
	if not left then return ns.Print(L.MSG_REPAIRED_GUILD:format(Coins(cost))) end
	RepairWithGold(left)
end

-- Repairs with the guild bank when allowed and chosen, else with your gold. The guild bank may hold less
-- than your allowance (its balance is not known before it is opened): still to repair a moment later, your gold.
function Repair()
	local db = ns.db.merchant
	if not (db.repair and Clean(Safe(CanMerchantRepair))) or ns.Yields("repair") then return end
	local cost = RepairCost()
	if not cost then return end
	if db.guildRepair and Clean(Safe(CanGuildBankRepair)) then
		local allowance = Clean(Safe(GetGuildBankWithdrawMoney)) or 0
		-- -1: no limit (guild master).
		if allowance == -1 or allowance >= cost then
			guildAsked = cost
			Safe(RepairAllItems, true)
			C_Timer.After(1.5, JudgeGuildRepair)
			return
		end
	end
	RepairWithGold(cost)
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
	if not (open and ns.db and ns.db.enabled and ns.db.merchant.sellJunk) or ns.Yields("sellJunk") then return end
	if not MerchantBuys() then return end
	local junk, waiting = FindJunk(true)
	-- What waits for your click (made junk by an addon, uncommon or better): never sold here, and said only
	-- when it changed since the last time (not at every merchant).
	if waiting > 0 and waiting ~= saidWaiting then ns.Print(L.MSG_JUNK_WAITING:format(waiting)) end
	saidWaiting = waiting
	if not junk[1] then return end
	-- (added to what an extension may have just queued, never in its place)
	for _, item in ipairs(junk) do
		if #queue >= MAX_ITEMS then break end
		queue[#queue + 1] = item
	end
	sinceSell, startMoney = SELL_DELAY, startMoney or Clean(Safe(GetMoney))
	frame:SetScript("OnUpdate", OnUpdate)
	return true
end

function ns.InitMerchant()
	frame = CreateFrame("Frame")
	frame:RegisterEvent("MERCHANT_SHOW")
	frame:RegisterEvent("MERCHANT_CLOSED")
	frame:RegisterEvent("UI_ERROR_MESSAGE")
	pcall(frame.RegisterEvent, frame, "UPDATE_INVENTORY_DURABILITY")
	frame:SetScript("OnEvent", function(_, event, _, message)
		if event == "UPDATE_INVENTORY_DURABILITY" then
			-- (the server's answer to the guild's repair, if one is asked: a moment for the cost to follow)
			if guildAsked then C_Timer.After(0, JudgeGuildRepair) end
		elseif event == "MERCHANT_SHOW" then
			open = true
			if not (ns.db and ns.db.enabled) or U.IsSkipping() then return end
			-- The merchant window sets up its buttons first; the junk is sold first, then
			-- the repair is paid (with the junk's gold too).
			C_Timer.After(0, function()
				if not open then return end
				if Start() then repairAfterSale = true else Repair() end
			end)
		elseif event == "MERCHANT_CLOSED" then
			open, repairAfterSale, guildAsked = false, false, nil
			if queue[1] or startMoney then Stop() end
		elseif queue[1] and (message == ERR_VENDOR_DOESNT_BUY or message == ERR_TOO_MUCH_GOLD) then
			Stop()
		end
	end)
end
