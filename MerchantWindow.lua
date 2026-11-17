local _, ns = ...
local L = ns.L

-- Wanderer's merchant window (option, on): at a merchant, one window in place of the game's. His goods in one
-- list (no pages): each with its square, its name in its quality's color, its lot, what is left when he has
-- few, its price in gold or in the tokens and items he asks; marked when you cannot use it (red), when you know
-- it already, when it is better for you than what you wear, when your shopping list lacks it (Wanderer
-- Auction). A search, the class filter of the game. A click on a row: how many you want, each choice with its
-- price (no arithmetic); its right click or its Buy button: one lot, as the game's right click. Every purchase
-- goes through the game's own confirmations (tokens, items that cannot be returned, an expensive item). The
-- buy back page; repairs (yours, the guild's, one item) with their cost; the junk sold on a click; the
-- provisions running low with their Fill up. The game's window stays open out of sight: a right click on an
-- item of your bags still sells it, and its button brings it back (a link above it comes back here).

local U = ns.Util
local Skin = ns.Skin
local Safe, Clean = U.Safe, U.Clean
local function G(name) return rawget(_G, name) end

local WIDTH, HEIGHT = 640, 660
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 560, 500, 1000, 1100
local ROW = 40
local MADE_ROWS = 30 -- rows made; as many shown as the window holds
local HIGH_PRICE = 1500000 -- the game's own line for an expensive purchase (MERCHANT_HIGH_PRICE_COST)
local MAX_COSTS = 3 -- tokens and items a price may ask (MAX_ITEM_COST)
local RECIPE, MISC = 9, 15 -- item classes whose tooltip may say "Already known"

local window, swap, list, proxy
local open = false -- at a merchant
local switching = false -- Wanderer's window hidden to show the game's (the merchant stays open)
local page = "goods" -- "goods" or "buyback"
local query = ""
local entries = {}
local known = {} -- this visit: "index:id" -> known (read once from its tooltip)

-- Reading the merchant ------------------------------------------------------------------------------------------

-- An item he sells: { index, id, link, name, icon, quality, price, lot, available, maxStack, purchasable, usable,
-- extended, refundable, quest, costs = { { icon, value, link, currency } }, afford } or nil.
local function Offer(index)
	local api = C_MerchantFrame and C_MerchantFrame.GetItemInfo
	local info = api and Safe(api, index)
	local o
	if type(info) == "table" then
		o = { name = Clean(info.name), icon = Clean(info.texture), price = Clean(info.price) or 0,
			lot = math.max(1, Clean(info.stackCount) or 1), available = Clean(info.numAvailable),
			purchasable = Clean(info.isPurchasable) ~= false, usable = Clean(info.isUsable) ~= false,
			extended = Clean(info.hasExtendedCost) and true or false, quest = Clean(info.isQuestStartItem) and true or false }
	else
		local name, icon, price, lot, available, purchasable, usable, extended = Safe(G("GetMerchantItemInfo"), index)
		if not Clean(name) then return nil end
		o = { name = Clean(name), icon = Clean(icon), price = Clean(price) or 0, lot = math.max(1, Clean(lot) or 1),
			available = Clean(available), purchasable = Clean(purchasable) ~= false, usable = Clean(usable) ~= false,
			extended = Clean(extended) and true or false, quest = false }
	end
	if not o.name then return nil end
	o.index = index
	o.id = Clean(Safe(GetMerchantItemID, index))
	o.link = Clean(Safe(G("GetMerchantItemLink"), index))
	o.quality = o.id and U.ItemQuality(o.id) or nil
	o.maxStack = math.max(o.lot, Clean(Safe(GetMerchantItemMaxStack, index)) or o.lot)
	local refundable = C_MerchantFrame and C_MerchantFrame.IsMerchantItemRefundable
	o.refundable = not refundable or Clean(Safe(refundable, index)) ~= false
	o.costs = {}
	if o.extended and (Clean(Safe(GetMerchantItemCostInfo, index)) or 0) > 0 then
		for cost = 1, MAX_COSTS do
			local icon, value, link, currency = Safe(GetMerchantItemCostItem, index, cost)
			icon = Clean(icon)
			if icon then
				o.costs[#o.costs + 1] = { icon = icon, value = Clean(value) or 0, link = Clean(link), currency = Clean(currency) }
			end
		end
	end
	local afford = G("CanAffordMerchantItem")
	if afford then
		o.afford = Clean(Safe(afford, index)) ~= false
	else
		o.afford = (Clean(Safe(GetMoney)) or 0) >= o.price
	end
	return o
end
ns.MerchantOfferInfo = Offer -- (tests)

-- What one costs for count items (whole lots): its gold and what else he asks.
local function Lots(o, count) return math.max(1, math.ceil((count or o.lot) / o.lot)) end
local function PriceText(o, count, colored)
	local lots = Lots(o, count)
	local parts = {}
	if o.price > 0 then
		parts[#parts + 1] = U.Coins(o.price * lots, colored and not o.afford and Skin.COLORS.bad or nil)
	end
	for _, cost in ipairs(o.costs) do
		parts[#parts + 1] = ("%d|T%s:0:0:2:0|t"):format(cost.value * lots, tostring(cost.icon))
	end
	return table.concat(parts, "  ")
end

-- A recipe (or a pet, a mount) its tooltip says you know already (read once a visit).
local KNOWN_WORDS = G("ITEM_SPELL_KNOWN")
local function Known(o)
	if not (o.id and KNOWN_WORDS) then return false end
	local key = o.index .. ":" .. o.id
	if known[key] ~= nil then return known[key] end
	local class = select(6, U.ItemInstant(o.id))
	local found = false
	if (class == RECIPE or class == MISC) and C_TooltipInfo and C_TooltipInfo.GetMerchantItem then
		local data = Safe(C_TooltipInfo.GetMerchantItem, o.index)
		for _, line in ipairs(U.TooltipLines(type(data) == "table" and data.lines or nil)) do
			if line.text == KNOWN_WORDS then found = true end
		end
	end
	known[key] = found
	return found
end

-- How many your shopping list (Wanderer Auction) still lacks of it, or nil.
local function ShoppingLack(id)
	local auction = rawget(_G, "WandererAuction")
	if not (id and type(auction) == "table" and type(auction.InShopping) == "function") then return nil end
	local ok, listed = pcall(auction.InShopping, id)
	if not (ok and listed) then return nil end
	local want = type(auction.ShoppingCount) == "function" and select(2, pcall(auction.ShoppingCount, id))
	local lack = (tonumber(want) or 0) - U.ItemCount(id, true)
	return lack > 0 and lack or nil
end

-- The mark under its name (one, the most useful): words and a tone.
local function Mark(o)
	if not o.usable then return L.MERCHANT_CANNOT_USE, "red" end
	if not o.purchasable then return L.MERCHANT_NOT_YET, "red" end
	if Known(o) then return L.MERCHANT_KNOWN, "grey" end
	if o.available == 0 then return L.MERCHANT_SOLD_OUT, "grey" end
	local gain = o.link and ns.UpgradeGain and ns.UpgradeGain(o.link)
	if gain then return L.ITEM_BETTER:format(gain), "green" end
	local lack = ShoppingLack(o.id)
	if lack then return L.MERCHANT_SHOPPING:format(lack), "blue" end
	if o.quest then return L.MERCHANT_QUEST, "gold" end
	return nil
end
ns.MerchantMark = Mark -- (tests)

-- Buying --------------------------------------------------------------------------------------------------------

-- The merchant still there, still selling this item at this place.
local function Still(o)
	return open and Clean(Safe(GetMerchantItemID, o.index)) == o.id
end

-- The game's own item button, as its window would hand it to its confirmations (never one of its own: ours,
-- unseen). Its confirmations then ask exactly as they ask in the game's window.
local function Proxy(o)
	if not proxy then
		proxy = CreateFrame("Button")
		proxy:Hide()
	end
	proxy:SetID(o.index)
	proxy.price = o.price
	proxy.extendedCost = o.extended or nil
	proxy.showNonrefundablePrompt = not o.refundable or nil
	proxy.link, proxy.name, proxy.texture, proxy.count = o.link, o.name, o.icon, o.lot
	return proxy
end

-- count of it bought (whole lots), the game's way: what costs tokens or cannot be returned through its
-- confirmation, an expensive lot through its own; a larger amount above the expensive line asked here first.
-- Nothing bought when the merchant changed meanwhile.
local function Buy(o, count)
	if not (o and Still(o)) then return end
	local buy = G("BuyMerchantItem")
	local confirmExtended, confirmHigh = G("MerchantFrame_ConfirmExtendedItemCost"), G("MerchantFrame_ConfirmHighCostItem")
	local quantity = Lots(o, count) * o.lot
	local single = quantity == o.lot
	if o.extended or not o.refundable then
		if confirmExtended then return Safe(confirmExtended, Proxy(o), not single and quantity or nil) end
		return Skin.Ask(L.MERCHANT_ASK_BUY:format(quantity, o.name, PriceText(o, quantity)), function()
			if Still(o) then Safe(buy, o.index, quantity) end
		end)
	end
	if o.price * Lots(o, quantity) >= HIGH_PRICE then
		if single and confirmHigh then return Safe(confirmHigh, Proxy(o)) end
		return Skin.Ask(L.MERCHANT_ASK_BUY:format(quantity, o.name, PriceText(o, quantity)), function()
			if Still(o) then Safe(buy, o.index, quantity) end
		end)
	end
	if single then Safe(buy, o.index) else Safe(buy, o.index, quantity) end
end
ns.MerchantBuy = Buy -- (tests)

-- The most of it one purchase may take: a stack (as the game's split), what he has left, what you can pay.
local function Most(o)
	local most = o.maxStack
	if o.available and o.available >= 0 then most = math.min(most, o.available * o.lot) end
	if o.price > 0 then
		local money = Clean(Safe(GetMoney)) or 0
		most = math.min(most, math.floor(money / o.price) * o.lot)
	end
	for _, cost in ipairs(o.costs) do
		if cost.link and not cost.currency and cost.value > 0 then
			most = math.min(most, math.floor(U.ItemCount(U.ItemID(cost.link) or 0) / cost.value) * o.lot)
		end
	end
	return math.max(0, most)
end

-- How many: a card of choices beside the row, each with its price.
local function HowMany(owner, o)
	local most = Most(o)
	local rows = {}
	local function Add(count, words)
		count = Lots(o, count) * o.lot
		for _, row in ipairs(rows) do if row.count == count then return end end
		rows[#rows + 1] = { text = words:format(count), right = PriceText(o, count), count = count, glyph = "plus",
			onClick = function() Buy(o, count) end }
	end
	Add(o.lot, L.MERCHANT_BUY_COUNT)
	if o.maxStack > o.lot and most >= o.maxStack then Add(o.maxStack, L.MERCHANT_BUY_STACK) end
	if most > o.lot and most < o.maxStack then Add(most, L.MERCHANT_BUY_AFFORD) end
	if o.maxStack > o.lot and most > o.lot then
		rows[#rows + 1] = { text = L.MERCHANT_BUY_OTHER, glyph = "pencil", onClick = function()
			Skin.AskText(L.MERCHANT_ASK_COUNT:format(o.name, most), "", function(text)
				local count = tonumber(text)
				if count and count > 0 then Buy(o, math.min(count, most)) end
			end, 5)
		end }
	end
	Skin.ActionCard(owner, { title = o.name, rows = rows, foot = most < o.lot and L.MERCHANT_CANNOT_AFFORD or nil, width = 300,
		atCursor = true })
end

-- Drawing -------------------------------------------------------------------------------------------------------

local function Buyback()
	local found = {}
	for index = 1, Clean(Safe(G("GetNumBuybackItems"))) or 0 do
		local name, icon, price, count = Safe(G("GetBuybackItemInfo"), index)
		name = Clean(name)
		if name then
			local link = Clean(Safe(G("GetBuybackItemLink"), index))
			local id = U.ItemID(link)
			found[#found + 1] = { index = index, name = name, icon = Clean(icon), price = Clean(price) or 0, count = Clean(count) or 1,
				link = link, quality = id and U.ItemQuality(id) or nil, buyback = true }
		end
	end
	return found
end

local function Gather()
	wipe(entries)
	local folded = U.Fold(query or "")
	if page == "buyback" then
		for _, entry in ipairs(Buyback()) do
			if U.Matches(entry.name, folded, true) then entries[#entries + 1] = entry end
		end
		return
	end
	for index = 1, Clean(Safe(GetMerchantNumItems)) or 0 do
		local o = Offer(index)
		if o and U.Matches(o.name, folded, true) then entries[#entries + 1] = o end
	end
end

local function Draw()
	if not (window and window:IsShown() and list) then return end
	Gather()
	local offset = list:Clamp(#entries)
	for index, row in ipairs(list.rows) do
		local entry = entries[offset + index]
		if not entry then
			row:Fill(nil)
		elseif entry.buyback then
			local name = entry.count > 1 and (entry.name .. Skin.Colorize("  x" .. entry.count, "soft")) or entry.name
			row:Fill({ name = name, icon = entry.icon, quality = entry.quality, link = entry.link, offer = entry }, false,
				{ stock = "", price = U.Coins(entry.price) }, nil, nil, L.MERCHANT_BUYBACK_DO, function() Safe(G("BuybackItem"), entry.index) end)
			if row.icon then row.icon.texture:SetVertexColor(1, 1, 1) end
			ns.MarkUpgrade(row.icon, nil)
		else
			local o = entry
			local name = o.lot > 1 and (o.name .. Skin.Colorize("  x" .. o.lot, "soft")) or o.name
			local stock = o.available and o.available >= 0 and L.MERCHANT_LEFT:format(o.available) or ""
			local chip, tone = Mark(o)
			row:Fill({ name = name, icon = o.icon, quality = o.quality, link = o.link, offer = o }, false,
				{ stock = stock, price = PriceText(o, o.lot, true) }, chip, tone, L.BUY, function() Buy(o) end)
			-- (the game's tint: red what you cannot use, grey what is sold out)
			local red = not o.usable or not o.purchasable
			if row.icon then
				if red then row.icon.texture:SetVertexColor(0.9, 0.2, 0.2)
				elseif o.available == 0 then row.icon.texture:SetVertexColor(0.5, 0.5, 0.5)
				else row.icon.texture:SetVertexColor(1, 1, 1) end
			end
			ns.MarkUpgrade(row.icon, o.link)
		end
	end
	list.empty:SetShown(not entries[1])
	if query ~= "" then
		list.empty:SetText(L.SETTINGS_NO_RESULTS)
	else
		list.empty:SetText(page == "buyback" and L.MERCHANT_BUYBACK_EMPTY or L.MERCHANT_EMPTY)
	end
	ns.DrawMerchantFoot()
end

-- The heading, the tabs' counts, the provisions, the foot.
local function DrawAll()
	if not (window and window:IsShown()) then return end
	window.title:SetText(Clean(Safe(UnitName, "npc")) or L.MERCHANT_KICKER)
	window.money:SetText(U.Coins(Clean(Safe(GetMoney)) or 0))
	local buyback = Clean(Safe(G("GetNumBuybackItems"))) or 0
	window.tabs:SetBadge("buyback", buyback > 0 and buyback or nil, "grey")
	if window.filter then window.filter:Refresh() end
	ns.DrawMerchantProvisions()
	Draw()
end
ns.DrawMerchantWindow = DrawAll
local drawSoon
function ns.DrawMerchantSoon() if drawSoon and window and window:IsShown() then drawSoon() end end

-- The provisions running low (Provisions.lua): a band over the list, its Fill up.
function ns.DrawMerchantProvisions()
	if not window then return end
	local band = window.band
	local state = page == "goods" and ns.ProvisionsState and ns.ProvisionsState() or nil
	local shown = state and state.list[1] ~= nil
	band:SetShown(shown and true or false)
	if shown then
		local parts = {}
		for _, item in ipairs(state.list) do parts[#parts + 1] = L.PROVISIONS_ITEM:format(item.name, item.have, item.usual) end
		band.text:SetText(L.PROVISIONS_LINE:format(table.concat(parts, U.SEPARATOR)))
		band.fill:SetLabel(L.PROVISIONS_FILL:format(U.Coins(state.cost)))
		band.fill:SetEnabled(state.ready)
	end
	window:Layout()
end

-- The foot: the junk to sell, the repairs.
function ns.DrawMerchantFoot()
	if not window then return end
	local foot = window.foot
	local junk = ns.FindJunk and ns.FindJunk() or {}
	local worth, count = 0, 0
	for _, item in ipairs(junk) do
		local info = Safe(C_Container and C_Container.GetContainerItemInfo, item.bag, item.slot)
		local stack = type(info) == "table" and Clean(info.stackCount) or 1
		worth = worth + (U.SellPrice(type(info) == "table" and Clean(info.hyperlink) or nil) or 0) * stack
		count = count + stack
	end
	foot.junk:SetLabel(L.MERCHANT_SELL_JUNK:format(U.Coins(worth)))
	foot.junk.count, foot.junk.worth = count, worth
	foot.junk:SetShown(count > 0 and (not ns.MerchantBuys or ns.MerchantBuys()))
	foot.junk:SetEnabled(not (ns.IsSellingJunk and ns.IsSellingJunk()))
	local repairs = Clean(Safe(CanMerchantRepair)) and true or false
	local cost, canRepair = Safe(GetRepairAllCost)
	cost = Clean(cost) or 0
	local needed = repairs and Clean(canRepair) and cost > 0
	foot.repair:SetShown(repairs)
	foot.one:SetShown(repairs and G("ShowRepairCursor") ~= nil)
	foot.repair:SetLabel(needed and L.MERCHANT_REPAIR_ALL:format(U.Coins(cost)) or L.MERCHANT_REPAIR_NONE)
	foot.repair:SetEnabled(needed and (Clean(Safe(GetMoney)) or 0) >= cost)
	local guild = repairs and Clean(Safe(CanGuildBankRepair)) and true or false
	foot.guild:SetShown(guild)
	-- (-1: no limit; an allowance under the cost would repair nothing)
	local allowance = guild and Clean(Safe(GetGuildBankWithdrawMoney)) or 0
	foot.guild:SetEnabled(needed and (allowance == -1 or allowance >= cost) and true or false)
	foot.guild.cost = cost
	-- (side by side from the right, those shown)
	local previous
	for _, button in ipairs({ foot.repair, foot.guild, foot.one }) do
		button:ClearAllPoints()
		if button:IsShown() then
			if previous then button:SetPoint("RIGHT", previous, "LEFT", -8, 0) else button:SetPoint("RIGHT", foot, "RIGHT", 0, 0) end
			previous = button
		end
	end
end

-- A repair asked by its button (your gold, or the guild's).
local function Repair(guild)
	local cost = Clean(Safe(GetRepairAllCost)) or 0
	if cost <= 0 then return end
	Safe(G("RepairAllItems"), guild and true or false)
	ns.Print((guild and L.MSG_REPAIRED_GUILD or L.MSG_REPAIRED):format(U.Coins(cost)))
	C_Timer.After(0.5, ns.DrawMerchantSoon)
end

-- The window -----------------------------------------------------------------------------------------------------

function ns.ShowMerchantPage(name)
	page = name == "buyback" and "buyback" or "goods"
	if not window then return end
	window.tabs:Select(page)
	list.offset = 0
	Skin.ActionCard(nil)
	DrawAll()
end

local function Clicked(entry, mouse)
	local o = entry.offer
	if not o then return end
	if o.buyback then return Safe(G("BuybackItem"), o.index) end
	if mouse == "RightButton" then return Buy(o) end
	-- (a left click, or Shift as the game's split: how many)
	local owner = window
	for _, row in ipairs(list.rows) do if row.entry == entry then owner = row end end
	HowMany(owner, o)
end

-- Selling by dropping an item from the bags on the window (the game's window does it too).
local function DropSell()
	if not (open and Clean(Safe(G("CursorHasItem")))) then return end
	local sell = G("SellCursorItem")
	if sell then Safe(sell) else Safe(G("PickupMerchantItem"), 0) end
end

local function Create()
	window = Skin.CreateWindow("WandererMerchantWindow", "MEDIUM")
	Skin.Dress(window, { "TOPLEFT", UIParent, "TOPLEFT", 24, -110 }, "merchantPos")
	Skin.Sounds(window, "IG_CHARACTER_INFO_OPEN", "IG_CHARACTER_INFO_CLOSE")
	-- (opened silently at a merchant, yet by the player: the controller comes to it)
	window.padTakes = true
	local sizes = ns.root and ns.Mine().sizes
	local saved = type(sizes) == "table" and sizes.merchant
	window:SetSize(Skin.Within(type(saved) == "table" and saved[1] or WIDTH, MIN_WIDTH, MAX_WIDTH),
		Skin.Within(type(saved) == "table" and saved[2] or HEIGHT, MIN_HEIGHT, MAX_HEIGHT))
	local _, title, margin = Skin.Header(window, L.MERCHANT_KICKER, "", { margin = 10, settings = "practical" }, "GameFontNormalLarge")
	window.title, window.margin = title, margin
	-- (the game look: the heading in the game's bar, its actions on one line level with the cog, the tabs under it)
	local game = Skin.GameWindows()
	local ruleTop = game and margin + 44 or margin + 68
	window.game = ns.SwapButton(window, swap)
	if game then window.game:SetPoint("TOPRIGHT", window, "TOPRIGHT", -32, -3)
	else window.game:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(margin + 54), -margin + 2) end
	window.money = Skin.Text(window, "GameTooltipText", "soft")
	window.money:SetPoint("RIGHT", window.game, "LEFT", -18, 0)
	-- The tabs, over a thin rule.
	local rule = Skin.Rule(window)
	-- (the game look: the game's own divider, from its options' list)
	if game then Skin.GameAtlas(rule, "Options_HorizontalDivider") end
	rule:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -ruleTop)
	rule:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	window.tabs = Skin.Tabs(window, { { "goods", L.MERCHANT_TAB_GOODS }, { "buyback", L.MERCHANT_TAB_BUYBACK } },
		function(name) ns.ShowMerchantPage(name) end)
	window.tabs:SetPoint("BOTTOMLEFT", rule, "TOPLEFT", 0, 0)
	-- The search, and the game's filter on the right.
	local search = Skin.CreateInput(window, nil, 40, { hint = L.MERCHANT_SEARCH, onChange = function(self)
		query = self:GetText() or ""
		list.offset = 0
		Draw()
	end })
	search:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -10)
	search:SetWidth(220)
	window.search = search
	if G("GetMerchantFilter") and G("SetMerchantFilter") and G("LE_LOOT_FILTER_ALL") then
		window.filter = Skin.Dropdown(window, function()
			local choices = {}
			local class = Clean(Safe(UnitClass, "player"))
			if G("LE_LOOT_FILTER_CLASS") then choices[#choices + 1] = { id = G("LE_LOOT_FILTER_CLASS"), label = class or (G("ALL_SPECS") or "") } end
			if G("LE_LOOT_FILTER_SPEC1") and G("GetNumSpecializations") and G("GetSpecializationInfo") then
				for index = 1, Clean(Safe(G("GetNumSpecializations"))) or 0 do
					local _, name = Safe(G("GetSpecializationInfo"), index)
					if Clean(name) then choices[#choices + 1] = { id = G("LE_LOOT_FILTER_SPEC1") + index - 1, label = Clean(name) } end
				end
			end
			if G("LE_LOOT_FILTER_BOE") then choices[#choices + 1] = { id = G("LE_LOOT_FILTER_BOE"), label = G("ITEM_BIND_ON_EQUIP") or "" } end
			choices[#choices + 1] = { id = G("LE_LOOT_FILTER_ALL"), label = G("ALL") or "" }
			return choices
		end, function() return Clean(Safe(G("GetMerchantFilter"))) end, function(value)
			Safe(G("SetMerchantFilter"), value)
			list.offset = 0
			C_Timer.After(0.2, ns.DrawMerchantSoon)
		end, nil, 140, 200, L.MERCHANT_FILTER_TIP)
		window.filter:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", 0, -8)
	end
	-- The provisions running low: a band over the list.
	local band = Skin.Panel(window)
	band:SetHeight(44)
	band:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -10)
	band:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	band:EnableMouse(true)
	band.fill = Skin.SmallButton(band, "", function() if ns.ProvisionsFill then ns.ProvisionsFill() end end, L.PROVISIONS_FILL_DESC, 26)
	band.fill:SetPoint("RIGHT", band, "RIGHT", -10, 0)
	band.text = Skin.Text(band, "GameTooltipTextSmall", "text")
	band.text:SetPoint("LEFT", band, "LEFT", 12, 0)
	band.text:SetPoint("RIGHT", band.fill, "LEFT", -12, 0)
	band.text:SetJustifyH("LEFT")
	band:SetScript("OnMouseUp", function(self) if ns.ProvisionsMenu then ns.ProvisionsMenu(self) end end)
	band.padTip = true
	Skin.Tooltip(band, L.PROVISIONS_TIP, "ANCHOR_TOP")
	band:Hide()
	window.band = band
	-- The list.
	list = Skin.Table(window, {
		width = WIDTH - margin * 2, rows = MADE_ROWS, rowHeight = ROW, action = 76,
		columns = { { key = "stock", title = L.MERCHANT_COL_STOCK, width = 70 }, { key = "price", title = L.MERCHANT_COL_PRICE, width = 150 } },
		onDraw = Draw, onClick = Clicked, padRight = true, padRightWord = L.BUY,
	})
	-- (the controller starts on the first of his goods, not on the tabs above them)
	if list.rows[1] then list.rows[1].padFirst = true end
	for _, row in ipairs(list.rows) do
		-- Hovered: the game's own tooltip of the merchant's item (its price, what you wear beside it).
		row:HookScript("OnEnter", function(self)
			local o = self.entry and self.entry.offer
			if not o then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			if o.buyback and GameTooltip.SetBuybackItem then
				Safe(GameTooltip.SetBuybackItem, GameTooltip, o.index)
			elseif GameTooltip.SetMerchantItem then
				Safe(GameTooltip.SetMerchantItem, GameTooltip, o.index)
				Safe(G("GameTooltip_ShowCompareItem"), GameTooltip)
			elseif o.link then
				GameTooltip:SetHyperlink(o.link)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnReceiveDrag", DropSell)
		if row.action then
			row.action:RegisterForClicks("LeftButtonUp")
			Skin.Tooltip(row.action, function(self)
				local o = self:GetParent().entry and self:GetParent().entry.offer
				return o and (o.buyback and L.MERCHANT_BUYBACK_TIP or L.MERCHANT_BUY_TIP) or nil
			end)
		end
	end
	window.list = list
	-- The foot: the junk, the repairs; a line of what clicks do.
	local foot = CreateFrame("Frame", nil, window)
	foot:SetHeight(26)
	foot:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin + 16)
	foot:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	foot.junk = Skin.SmallButton(foot, "", function(self)
		if not ns.SellItems then return end
		Skin.Ask(L.MERCHANT_SELL_JUNK_ASK:format(self.count or 0, U.Coins(self.worth or 0)), function()
			ns.SellItems(ns.FindJunk())
			C_Timer.After(0.3, ns.DrawMerchantSoon)
		end)
	end, L.MERCHANT_SELL_JUNK_TIP, 26)
	foot.junk:SetPoint("LEFT", foot, "LEFT", 0, 0)
	foot.repair = Skin.SmallButton(foot, "", function() Repair(false) end, L.MERCHANT_REPAIR_ALL_TIP, 26)
	foot.guild = Skin.SmallButton(foot, L.MERCHANT_REPAIR_GUILD, function() Repair(true) end, function()
		local allowance = Clean(Safe(GetGuildBankWithdrawMoney)) or 0
		return L.MERCHANT_REPAIR_GUILD_TIP:format(allowance == -1 and L.MERCHANT_NO_LIMIT or U.Coins(allowance))
	end, 26)
	-- (a second click puts the hammer away, as the game's button does)
	foot.one = Skin.SmallButton(foot, L.MERCHANT_REPAIR_ONE, function()
		if G("InRepairMode") and Clean(Safe(G("InRepairMode"))) then Safe(G("HideRepairCursor")) else Safe(G("ShowRepairCursor")) end
	end, L.MERCHANT_REPAIR_ONE_TIP, 26)
	window.foot = foot
	window.hint = Skin.Text(window, "GameTooltipTextSmall", "muted")
	window.hint:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin - 2)
	window.hint:SetPoint("RIGHT", window, "RIGHT", -(margin + 16), 0)
	window.hint:SetJustifyH("LEFT")
	-- An item of the bags dropped on the window: sold.
	window:SetScript("OnReceiveDrag", DropSell)
	window:HookScript("OnMouseUp", DropSell)
	-- The places, after a change of size or of the provisions' band.
	function window:Layout()
		local width = self:GetWidth()
		list:ClearAllPoints()
		list:SetPoint("TOPLEFT", band:IsShown() and band or search, "BOTTOMLEFT", 0, -12)
		list:SetWidth(width - margin * 2)
		local top = ruleTop + 10 + 24 + 12 + (band:IsShown() and 56 or 0)
		list:Fit(self:GetHeight() - top - (margin + 16 + 26 + 10))
		self.hint:SetText(U.UsingPad and U.UsingPad() and L.MERCHANT_HINT_PAD or L.MERCHANT_HINT)
	end
	Skin.Resizable(window, {
		minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, maxWidth = MAX_WIDTH, maxHeight = MAX_HEIGHT,
		onResized = function(width, height)
			if not ns.root then return end
			local mine = ns.Mine()
			mine.sizes = type(mine.sizes) == "table" and mine.sizes or {}
			mine.sizes.merchant = { width, height }
		end,
	})
	window:HookScript("OnSizeChanged", function(self)
		local skin = Skin.Get(self)
		if skin then skin:Layout() end
		self:Layout()
		Draw()
	end)
	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.FitScale(self))
		self:Layout()
		self.tabs:Select(page)
		DrawAll()
	end)
	-- Closed by hand (its cross, Escape): the visit ends with it, as the game's window does.
	window:HookScript("OnHide", function(self)
		Skin.ActionCard(nil)
		if switching or self:IsShown() or not (open and swap:Wanderer()) then return end
		Skin.CancelAsk()
		Safe(G("CloseMerchant"))
	end)
	window:Layout()
	Skin.Get(window):Layout()
end

local function Open()
	if not window then Create() end
	if window:IsShown() then DrawAll() else window:Show() end
end

-- Init ----------------------------------------------------------------------------------------------------------

local function Visit(on)
	open = on
	if on then
		wipe(known)
		page, query = "goods", ""
		if window and window.search then window.search:SetText("") end
		-- (another merchant's goods: from the first one, not where the last visit was scrolled)
		if list then list.offset = 0 end
		swap:Start()
		if swap:Wanderer() then
			if not window then Create() end
			-- (the game's window plays its own sound as the visit begins and ends)
			window.quiet = not window:IsShown()
			Open()
			window.quiet = nil
		end
	else
		Skin.ActionCard(nil)
		swap:End()
		if window and window:IsShown() then
			window.quiet = true
			window:Hide()
		end
	end
end
ns.MerchantVisit = Visit -- (tests)

-- The settings' row changed (or Wanderer switched off) while at a merchant: the window chosen now is the one shown.
function ns.RefreshMerchantWindow()
	if not (open and swap) then return end
	swap.game = false
	swap:Place()
	if swap:Wanderer() then
		Open()
	elseif window and window:IsShown() then
		switching = true
		window:Hide()
		switching = false
	end
end

function ns.InitMerchantWindow()
	swap = ns.Swap({
		frame = function() return G("MerchantFrame") end,
		wanted = function() return ns.db.merchant.window end,
		choose = function(on) ns.KeepChoice("merchant", "window", on) end,
		link = L.MERCHANT_WINDOW, linkTip = L.SWAP_BACK_DESC,
		onGame = function()
			Skin.ActionCard(nil)
			if window and window:IsShown() then
				switching = true
				window:Hide()
				switching = false
			end
		end,
		onWanderer = Open,
	})
	ns.merchantSwap = swap
	drawSoon = U.Debounce(0.1, DrawAll)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE", "PLAYER_MONEY",
		"BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "GUILDBANK_UPDATE_MONEY", "GET_ITEM_INFO_RECEIVED", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, kind)
		if event == "MERCHANT_SHOW" then
			if not open then Visit(true) end
		elseif event == "MERCHANT_CLOSED" then
			if open then Visit(false) end
		elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
			local merchant = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Merchant
			if open and merchant and kind == merchant then Visit(false) end
		elseif open then
			ns.DrawMerchantSoon()
		end
	end)
	-- (the game's window put away by itself, the merchant out of reach: the visit ends with it)
	local frame = G("MerchantFrame")
	if frame then
		swap:Hook()
		frame:HookScript("OnHide", function()
			C_Timer.After(0, function() if open and not frame:IsShown() then Visit(false) end end)
		end)
	end
end
