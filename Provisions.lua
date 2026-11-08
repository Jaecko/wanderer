local _, ns = ...
local L = ns.L

-- Provisions (option, on): what you buy again and again at merchants (arrows, water, reagents, thread...),
-- learned for each character: an item bought by the stack at a merchant, how many you carried when you left
-- him is how many you like to have. At a merchant who sells some of them, while you carry less than a third
-- of that: one line under his tabs says which, and "Fill up" buys what is missing, at his price, when you
-- click it (never by itself). An item not bought again for a month is let go; a right click on the line
-- forgets one sooner.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean
local Skin = ns.Skin

local LOW = 1 / 3 -- carried under this share of the usual: low
local FORGET_AFTER = 30 * 86400 -- seconds without buying it again

local line, button
local bought = {} -- item id -> how many bought during this visit
local open = false
local filling = false -- a fill under way (one at a time: a second click buys nothing more)
-- What Fill up asked and the bags do not show yet: item id -> { count, at }. Counted as carried until the
-- bags show it (or a moment passed), so the line never comes back between the purchase and the bags.
local pending = {}
local PENDING_FOR = 3

local function On() return ns.db and ns.db.enabled and ns.db.merchant.provisions and true or false end

-- This character's provisions: item id -> { usual, time }.
local function Store()
	local root = ns.root
	if not root then return nil end
	root.provisions = type(root.provisions) == "table" and root.provisions or {}
	local key = ns.CharacterKey()
	root.provisions[key] = type(root.provisions[key]) == "table" and root.provisions[key] or {}
	return root.provisions[key]
end

local function Stacks(id)
	return U.ItemMaxStack(id) > 1
end

-- What an extension buys itself at merchants (Wanderer Auction: your shopping list): rule(item id) -> true. Those
-- are left to it, never offered here too.
local buyRules = {}
function ns.AddBuyRule(rule)
	if type(rule) == "function" then buyRules[#buyRules + 1] = rule end
end
local function BoughtElsewhere(id)
	for _, rule in ipairs(buyRules) do
		local ok, mine = pcall(rule, id)
		if ok and mine then return true end
	end
	return false
end

-- What this merchant sells of your provisions running low: { index, id, name, have, usual, need, cost }.
local function Lacking()
	local list, store = {}, Store()
	if not (store and next(store)) then return list end
	local now = time()
	for id, entry in pairs(store) do
		if now - (entry.time or now) > FORGET_AFTER then store[id] = nil end
	end
	for id, asked in pairs(pending) do
		if U.ItemCount(id) >= asked.count or GetTime() - asked.at > PENDING_FOR then pending[id] = nil end
	end
	for index = 1, Clean(Safe(GetMerchantNumItems)) or 0 do
		local id = Clean(Safe(GetMerchantItemID, index))
		local entry = id and store[id]
		if entry and not BoughtElsewhere(id) then
			local have = pending[id] and pending[id].count or U.ItemCount(id)
			if have < entry.usual * LOW then
				local _, _, _, forGold = U.MerchantOffer(index)
				-- (sold for gold only, and as many as he has when he has few)
				if forGold then
					local need = math.min(entry.usual - have, U.MerchantMost(index))
					if need > 0 then
						list[#list + 1] = { index = index, id = id, name = U.ItemName(id) or "?", have = have,
							usual = entry.usual, need = need, cost = U.MerchantCost(index, need) }
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local function Refresh()
	if not line then return end
	local shown = On() and open and (not MerchantFrame.selectedTab or MerchantFrame.selectedTab == 1)
	local list = shown and Lacking() or {}
	if not list[1] then
		line:Hide()
		button:Hide()
		return
	end
	local parts, cost = {}, 0
	for _, item in ipairs(list) do
		parts[#parts + 1] = L.PROVISIONS_ITEM:format(item.name, item.have, item.usual)
		cost = cost + item.cost
	end
	line.text:SetText(L.PROVISIONS_LINE:format(table.concat(parts, U.SEPARATOR)))
	line:SetHeight(math.max(16, U.Measure(line.text, "GetStringHeight", 14)))
	line:Show()
	button:SetText(L.PROVISIONS_FILL:format(U.Coins(cost)))
	button:SetWidth(math.max(90, U.Measure(button:GetFontString() or button, "GetStringWidth", 80) + 28))
	button.cost = cost
	-- (not while the junk is sold: its gain is counted from your money)
	button:SetEnabled(not filling and not next(pending) and not ns.IsSellingJunk() and (Clean(Safe(GetMoney)) or 0) >= cost)
	button:Show()
end
ns.RefreshProvisions = Refresh

-- What is missing bought (Wanderer's purchases: whole lots, as the price shown), one item after the other.
-- Once at a time: a second click buys nothing more.
local function Fill()
	if filling or ns.IsSellingJunk() then return end
	local queue = {}
	for _, item in ipairs(Lacking()) do queue[#queue + 1] = { index = item.index, count = item.need, id = item.id } end
	if not queue[1] then return end
	filling = true
	button:Disable()
	local now = GetTime()
	for _, item in ipairs(queue) do pending[item.id] = { count = U.ItemCount(item.id) + item.count, at = now } end
	U.BuyQueue(queue, function()
		filling = false
		for _, asked in pairs(pending) do asked.at = GetTime() end
		Refresh()
		-- (the bags slower than that: the line comes back as it is)
		C_Timer.After(PENDING_FOR + 0.1, Refresh)
	end)
end

-- Leaving the merchant: what was bought here by the stack, how many you carry now is your usual.
local function Learn()
	local store = Store()
	if not store then return end
	for id, count in pairs(bought) do
		local have = U.ItemCount(id)
		local before = store[id] and store[id].usual or 0
		-- (a little bought on the way does not lower the usual: half of it at least; what an extension buys
		-- itself is its own: Wanderer Auction's shopping list; a new one only when bought by the stack, or
		-- 20 at least: a single potion bought once is no usual)
		local enough = store[id] or count >= math.min(U.ItemMaxStack(id), 20)
		if have > 0 and enough and Stacks(id) and not BoughtElsewhere(id) then
			store[id] = { usual = have >= before / 2 and have or before, time = time() }
		end
	end
	wipe(bought)
end

local function Forget(id)
	local store = Store()
	if store then store[id] = nil end
	Refresh()
end

local function Menu(owner)
	local store = Store()
	U.Menu(owner, function(_, root)
		root:CreateTitle(L.PROVISIONS_TITLE)
		local ids = {}
		for id in pairs(store or {}) do ids[#ids + 1] = id end
		table.sort(ids, function(a, b) return (U.ItemName(a) or "") < (U.ItemName(b) or "") end)
		for _, id in ipairs(ids) do
			root:CreateButton(L.PROVISIONS_FORGET:format(U.ItemName(id) or ("#" .. id), store[id].usual), function() Forget(id) end)
		end
	end)
end

local function Build()
	if line or not MerchantFrame then return end
	local tab1, tab2 = _G.MerchantFrameTab1, _G.MerchantFrameTab2
	line = CreateFrame("Button", "WandererProvisions", MerchantFrame)
	if tab1 then line:SetPoint("TOPLEFT", tab1, "BOTTOMLEFT", 6, -6) else line:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 12, -28) end
	line:SetWidth(math.max(MerchantFrame:GetWidth() or 0, 336) - 24)
	line.text = Skin.CreateText(line, "GameFontNormalSmall")
	line.text:SetPoint("TOPLEFT")
	line.text:SetPoint("RIGHT")
	line.text:SetJustifyH("LEFT")
	if line.text.SetWordWrap then line.text:SetWordWrap(true) end
	line:RegisterForClicks("RightButtonUp")
	line:SetScript("OnClick", function(self) Menu(self) end)
	Skin.Tooltip(line, L.PROVISIONS_TIP, "ANCHOR_BOTTOMLEFT")
	button = Skin.GameButton(MerchantFrame, "WandererProvisionsFill", L.PROVISIONS_FILL:format(""), Fill, L.PROVISIONS_FILL_DESC)
	if tab2 then button:SetPoint("LEFT", tab2, "RIGHT", 8, 0) else button:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -8, -2) end
	line:Hide()
	button:Hide()
	for _, tab in ipairs({ tab1, tab2 }) do
		if tab then tab:HookScript("OnClick", Refresh) end
	end
end

function ns.InitProvisions()
	if BuyMerchantItem then
		-- (any purchase: yours by hand, the game's, Fill up's)
		hooksecurefunc("BuyMerchantItem", function(index, quantity)
			local id = Clean(Safe(GetMerchantItemID, index))
			if not id then return end
			local _, lot = U.MerchantOffer(index)
			bought[id] = (bought[id] or 0) + (tonumber(Clean(quantity)) or lot or 1)
		end)
	end
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
		pcall(frame.RegisterEvent, frame, event)
	end
	frame:SetScript("OnEvent", function(_, event)
		if event == "MERCHANT_SHOW" then
			open = true
			Build()
		elseif event == "MERCHANT_CLOSED" then
			if open then Learn() end
			open, filling = false, false
			wipe(pending)
		end
		Refresh()
	end)
end
