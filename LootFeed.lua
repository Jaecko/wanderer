local _, ns = ...
local L = ns.L

-- The loot feed: what you just picked up, at the side of the screen, as in the old role playing games. Each
-- thing comes in turn (a breath apart), fading and rising a little, the newest at the bottom pushing the
-- others up; it stays a few seconds (an epic one longer) and fades away. The same thing again while it shows:
-- its count grows, with a soft pulse. The mouse over it holds every line and shows the item; Shift click
-- links it in the chat. Read from the game's own messages about you only (your loot, the items put in your
-- bags, your money and currencies); a secret line is left alone. Hidden while a conversation scene shows,
-- and caught up after. Another addon showing its own loot feed: left to it (Compat.lua).

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local WIDTH = 250
local ROW_HEIGHT = ns.Skin.ROW.normal
local ROW_GAP = 4
local ICON_SIZE = 26
local MAX_SHOWN = 6 -- lines at most (a newer one sends the oldest away early)
local STAGGER = 0.15 -- seconds between two lines coming
local FADE_IN = 0.25
local FADE_OUT = 0.6
local FADE_OUT_EARLY = 0.3 -- the oldest sent away by a newer one
local RISE = 8 -- pixels a line rises while it comes
local SLIDE_SPEED = 12 -- how fast the lines take their places
local LONGER = 3 -- seconds more for an epic thing or better
local EPIC = 4
local PULSE_TIME = 0.45
local PULSE_ALPHA = 0.22 -- the pulse at its brightest
local QUEUE_MAX = 30
local MONEY_GRACE = 1 -- seconds a money change and its loot message may lie apart
local QUEST_CLASS = 12 -- the game's class of quest items

ns.RANGES["loot.feedTime"] = { 3, 10, 1 }
ns.RANGES["loot.feedQuality"] = { 0, 4, 1 }

local holder
local rows, pool, queue = {}, {}, {}
local nextIn = 0
local lastMoney, pendingMoney, moneyHeard = nil, nil, -100
local lootOpen, lootUntil = false, -100

-- The game's messages about you, as patterns: the counted ones first (the plain one would take the count).
local LOOTED, RECEIVED, CURRENCY = {}, {}, {}
local function Patterns(list, ...)
	for index = 1, select("#", ...) do
		local format = _G[(select(index, ...))]
		local pattern = U.FormatPattern(format)
		if pattern then list[#list + 1] = { pattern = pattern, counted = format:find("%%d") ~= nil } end
	end
end
Patterns(LOOTED, "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF")
Patterns(RECEIVED, "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF")
Patterns(CURRENCY, "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED")

local function FeedSettings()
	return ns.db and ns.db.loot or nil
end

local function On()
	local settings = FeedSettings()
	return settings and ns.db.enabled and settings.feed and not ns.Yields("lootFeed") and true or false
end

-- What a message says: the link it carries and its count, or nil (not one of these messages).
local function Read(text, patterns)
	for _, known in ipairs(patterns) do
		local link, count = text:match(known.pattern)
		if link then return link, known.counted and tonumber(count) or 1 end
	end
end

-- An item's quality from its link's color, when the game does not know the item yet.
local function LinkQuality(link)
	local quality = tonumber(link:match("|cnIQ(%d+):"))
	if quality then return quality end
	local hex = link:match("|cff(%x%x%x%x%x%x)")
	if not hex then return nil end
	local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
	for index = 0, 7 do
		local qr, qg, qb = U.QualityColor(index)
		if math.abs(qr - r) + math.abs(qg - g) + math.abs(qb - b) < 0.05 then return index end
	end
end

-- The small line under an item: its worth for the grey ones, else its kind (and where it is worn).
local function ItemNote(link, quality, count, classID, kind, subKind, slot)
	if quality == 0 then
		local price = U.SellPrice(link)
		if price and price > 0 then return U.Coins(price * count, ns.Skin.COLORS.muted) end
	end
	if classID == QUEST_CLASS then return L.LOOT_FEED_QUEST_ITEM end
	local words = Clean(subKind) or Clean(kind)
	local slotName = Clean(slot) and Clean(_G[slot])
	if words and slotName and slotName ~= words then return words .. ", " .. slotName end
	return words or slotName
end

-- An item's line, or nil (not worth showing by the settings).
local function ItemEntry(text, count, received)
	local item = text:match("|H(item:[^|]+)|h")
	if not item then return nil end
	local id = U.ItemID(item)
	local _, kind, subKind, slot, icon, classID = U.ItemInstant(id or item)
	local quality = id and U.ItemQuality(id) or LinkQuality(text) or 1
	local settings = FeedSettings()
	if classID ~= QUEST_CLASS and quality < (settings.feedQuality or 1) then return nil end
	if received and not settings.feedReceived then return nil end
	return {
		key = "item:" .. (id or item), link = item, chatLink = text:match("|c.-|r") or text, kind = "item",
		name = U.LinkName(text) or "?", icon = Clean(icon) or (id and U.ItemIcon(id)), quality = quality, count = count,
		note = ItemNote(item, quality, count, classID, kind, subKind, slot),
	}
end

local function CurrencyEntry(text, count)
	local id = tonumber(text:match("|Hcurrency:(%d+)"))
	if not id then return nil end
	local info = C_CurrencyInfo and Safe(C_CurrencyInfo.GetCurrencyInfo, id)
	info = type(info) == "table" and info or {}
	return {
		key = "currency:" .. id, link = "currency:" .. id, kind = "currency", name = U.LinkName(text) or Clean(info.name) or "?",
		icon = Clean(info.iconFileID), quality = Clean(info.quality) or 1, count = count, note = L.LOOT_FEED_CURRENCY,
	}
end

local function CoinIcon(copper)
	if copper >= 10000 then return "Interface\\Icons\\INV_Misc_Coin_01" end
	if copper >= 100 then return "Interface\\Icons\\INV_Misc_Coin_03" end
	return "Interface\\Icons\\INV_Misc_Coin_05"
end

-- The lines ---------------------------------------------------------------------------------------------------

local function Fill(row)
	local entry = row.entry
	local gold = ns.Skin.COLORS.gold
	local r, g, b
	if entry.kind == "money" then
		r, g, b = gold[1], gold[2], gold[3]
		row.icon:Set(CoinIcon(entry.copper))
		row.icon.edges.Color(r, g, b, 0.6)
		row.name:SetText(U.Coins(entry.copper, ns.Skin.COLORS.text))
		row.name:SetTextColor(1, 1, 1)
		row.count:SetText("")
	else
		r, g, b = U.QualityColor(entry.quality)
		row.icon:Set(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark", entry.quality)
		row.name:SetText(entry.name)
		row.name:SetTextColor(r, g, b)
		row.count:SetText(entry.count > 1 and ("x" .. entry.count) or "")
	end
	row.tone:SetColorTexture(r, g, b, 0.75)
	row.note:SetText(entry.note or "")
	-- The name as wide as there is room beside its count; alone, in the middle of its line.
	local left = 8 + ICON_SIZE + 8
	local countWidth = row.count:GetText() ~= "" and (U.Measure(row.count, "GetStringWidth", 20) + 5) or 0
	row.name:SetWidth(math.max(40, math.min(U.Measure(row.name, "GetStringWidth", 120) + 2, WIDTH - left - 8 - countWidth)))
	row.name:ClearAllPoints()
	if entry.note and entry.note ~= "" then
		row.name:SetPoint("BOTTOMLEFT", row, "LEFT", left, 0)
		row.note:Show()
	else
		row.name:SetPoint("LEFT", row, "LEFT", left, 0)
		row.note:Hide()
	end
end

local function Leave(row)
	GameTooltip:Hide()
	if _G.ResetCursor then _G.ResetCursor() end
	row.hovered = nil
end

local function Enter(row)
	local entry = row.entry
	if not entry then return end
	row.hovered = true
	-- (an item: its own tooltip, by Skin.ItemTooltip on the row)
	if entry.link then return end
	ns.Skin.ShowTip(row, { L.LOOT_FEED_MONEY_LOOTED, U.Coins(entry.copper) }, "ANCHOR_LEFT")
end

local function Click(row)
	local entry = row.entry
	if entry and entry.chatLink and HandleModifiedItemClick then Safe(HandleModifiedItemClick, entry.chatLink) end
end

local function NewRow()
	local row = CreateFrame("Button", nil, holder)
	row:SetSize(WIDTH, ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	local band = row:CreateTexture(nil, "BACKGROUND")
	band:SetAllPoints()
	ns.Skin.FadingRule(band, 0.62, false, { 0.03, 0.03, 0.04 })
	row.tone = row:CreateTexture(nil, "BORDER")
	row.tone:SetWidth(2)
	row.tone:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.tone:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	-- (the pulse of a line that grows: a soft light on its own ground, never over the world)
	row.pulse = row:CreateTexture(nil, "BORDER")
	row.pulse:SetAllPoints()
	-- (its opacity written into the gradient's colours: this game draws a gradient whatever SetAlpha says)
	ns.Skin.FadingRule(row.pulse, 0, false)
	row.icon = ns.Skin.Icon(row, ICON_SIZE)
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.name = ns.Skin.Text(row, "GameTooltipText")
	if row.name.SetWordWrap then row.name:SetWordWrap(false) end
	row.count = ns.Skin.Text(row, "GameTooltipText", "soft")
	row.count:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
	row.note = ns.Skin.Text(row, "GameTooltipTextSmall", "muted")
	row.note:SetPoint("TOPLEFT", row, "LEFT", 8 + ICON_SIZE + 8, -1)
	row.note:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	if row.note.SetWordWrap then row.note:SetWordWrap(false) end
	row:SetScript("OnEnter", Enter)
	row:SetScript("OnLeave", Leave)
	row:SetScript("OnClick", Click)
	ns.Skin.ItemTooltip(row, function(self) return self.entry and self.entry.link end, "ANCHOR_LEFT")
	return row
end

local function Release(index)
	local row = table.remove(rows, index)
	if row.hovered then Leave(row) end
	row:Hide()
	row.entry = nil
	pool[#pool + 1] = row
end

local function Life(entry)
	local seconds = FeedSettings() and FeedSettings().feedTime or 4
	if (entry.quality or 0) >= EPIC then seconds = seconds + LONGER end
	return seconds
end

-- A line comes: at the bottom, the oldest sent away when there are too many.
local function Show(entry)
	local staying = 0
	for _, row in ipairs(rows) do
		if not row.leaving then staying = staying + 1 end
	end
	for index = #rows, 1, -1 do
		if staying < MAX_SHOWN then break end
		local row = rows[index]
		if not row.leaving then
			row.leaving, row.out, row.outTime = true, 0, FADE_OUT_EARLY
			staying = staying - 1
		end
	end
	local row = table.remove(pool) or NewRow()
	row.entry, row.age, row.life, row.leaving, row.pulsing = entry, 0, Life(entry), nil, nil
	-- (the calm movements: it fades in where it stays)
	row.y = ns.CalmMotion() and 0 or -RISE
	row:SetAlpha(0)
	ns.Skin.FadingRule(row.pulse, 0, false)
	Fill(row)
	row:ClearAllPoints()
	row:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, row.y)
	row:Show()
	table.insert(rows, 1, row)
end

-- Anything under the mouse holds every line (and the scenes hold them all, hidden).
local function Held()
	for _, row in ipairs(rows) do
		if row.hovered or U.IsMouseOver(row) then return true end
	end
	return false
end

local function OnUpdate(self, elapsed)
	local scene = ns.sceneActive and true or false
	ns.Skin.Fade(self, scene and 0 or 1, elapsed, 0.3, 0.3)
	local held = scene or Held()
	if not scene then
		nextIn = nextIn - elapsed
		if queue[1] and nextIn <= 0.001 then
			Show(table.remove(queue, 1))
			nextIn = STAGGER
		end
	end
	local step = ROW_HEIGHT + ROW_GAP
	local slide = ns.CalmMotion() and 1 or math.min(1, elapsed * SLIDE_SPEED)
	for index = #rows, 1, -1 do
		local row = rows[index]
		if row.leaving then
			row.out = row.out + elapsed
			row:SetAlpha(math.max(0, 1 - row.out / row.outTime))
			if row.out >= row.outTime then Release(index) end
		else
			if not held then row.age = row.age + elapsed end
			row:SetAlpha(math.min(1, row.age / FADE_IN))
			if row.age >= row.life then row.leaving, row.out, row.outTime = true, 0, FADE_OUT end
		end
		if row.pulsing then
			row.pulsing = row.pulsing + elapsed
			local share = math.min(1, row.pulsing / PULSE_TIME)
			ns.Skin.FadingRule(row.pulse, PULSE_ALPHA * math.sin(share * math.pi), false)
			if share >= 1 then row.pulsing = nil end
		end
	end
	for index, row in ipairs(rows) do
		local target = (index - 1) * step
		if row.y ~= target then
			if math.abs(target - row.y) < 0.5 then row.y = target else row.y = row.y + (target - row.y) * slide end
			row:ClearAllPoints()
			row:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, row.y)
		end
	end
	if not rows[1] and not queue[1] then self:Hide() end
end

-- Something picked up: added to its line if it still shows (or still waits), else queued.
local function Add(entry)
	if not entry then return end
	for _, row in ipairs(rows) do
		local known = row.entry
		if not row.leaving and known and known.key == entry.key then
			known.count = known.count + entry.count
			if entry.copper then known.copper = known.copper + entry.copper end
			if known.kind == "item" and known.quality == 0 then known.note = ItemNote(known.link, 0, known.count) end
			Fill(row)
			row.age = math.min(row.age, FADE_IN)
			row.pulsing = 0
			return
		end
	end
	for _, waiting in ipairs(queue) do
		if waiting.key == entry.key then
			waiting.count = waiting.count + entry.count
			if entry.copper then waiting.copper = waiting.copper + entry.copper end
			return
		end
	end
	queue[#queue + 1] = entry
	while #queue > QUEUE_MAX do table.remove(queue, 1) end
	if not holder:IsShown() then
		holder:SetScale(ns.Skin.Scale())
		ns.PlaceApply("lootFeed", holder)
		holder:SetAlpha(1)
		nextIn = 0
		holder:Show()
	end
end

local function AddMoney(copper)
	local settings = FeedSettings()
	if not (copper and copper > 0 and settings.feedMoney) then return end
	Add({ key = "money", kind = "money", copper = copper, count = 1, quality = 1 })
end

-- Events ------------------------------------------------------------------------------------------------------

local function OnLoot(text)
	text = Clean(text)
	if type(text) ~= "string" then return end
	local link, count = Read(text, LOOTED)
	if link then return Add(ItemEntry(link, count, false)) end
	link, count = Read(text, RECEIVED)
	if link then return Add(ItemEntry(link, count, true)) end
end

local function OnCurrency(text)
	text = Clean(text)
	if type(text) ~= "string" then return end
	local link, count = Read(text, CURRENCY)
	if link then Add(CurrencyEntry(link, count)) end
end

local function Looting(now)
	return lootOpen or now <= lootUntil or now - moneyHeard <= MONEY_GRACE
end

-- Your money grew: shown when it came from the loot (the loot window, or the loot's money message), else
-- kept a moment for that message (they may come in either order).
local function OnMoney()
	local money = Clean(Safe(GetMoney))
	if not money then return end
	local before = lastMoney
	lastMoney = money
	if not before or money <= before then return end
	local now = GetTime()
	if Looting(now) then
		AddMoney(money - before)
	else
		pendingMoney = { copper = money - before, at = now }
	end
end

local function OnEvent(_, event, text)
	if event == "PLAYER_MONEY" then
		if On() then return OnMoney() end
		lastMoney = Clean(Safe(GetMoney))
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastMoney = Clean(Safe(GetMoney))
		return
	elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
		lootOpen = true
		return
	elseif event == "LOOT_CLOSED" then
		lootOpen, lootUntil = false, GetTime() + MONEY_GRACE
		return
	end
	if not On() then return end
	if event == "CHAT_MSG_LOOT" then
		OnLoot(text)
	elseif event == "CHAT_MSG_CURRENCY" then
		OnCurrency(text)
	elseif event == "CHAT_MSG_MONEY" then
		local now = GetTime()
		moneyHeard = now
		if pendingMoney and now - pendingMoney.at <= MONEY_GRACE then AddMoney(pendingMoney.copper) end
		pendingMoney = nil
	end
end

-- Turned off (or left to another addon): every line goes at once.
function ns.RefreshLootFeed()
	if On() then
		if holder:IsShown() then holder:SetScale(ns.Skin.Scale()) end
		return
	end
	wipe(queue)
	for index = #rows, 1, -1 do Release(index) end
	holder:Hide()
end

-- (tests: the lines shown, newest first, and those waiting)
function ns.LootFeedRows() return rows, queue end

holder = CreateFrame("Frame", "WandererLootFeed", UIParent)
holder:SetSize(WIDTH, MAX_SHOWN * (ROW_HEIGHT + ROW_GAP))
holder:SetFrameStrata("MEDIUM")
holder:SetClampedToScreen(true)
-- (readable while the cinematic mode fades the interface, as Wanderer's windows)
if holder.SetIgnoreParentAlpha then holder:SetIgnoreParentAlpha(true) end
holder:Hide()
holder:SetScript("OnUpdate", OnUpdate)

ns.Placeable({
	key = "lootFeed", label = function() return L.PLACING_LOOT_FEED end, frame = holder, live = false,
	size = { WIDTH, MAX_SHOWN * (ROW_HEIGHT + ROW_GAP) },
	scale = function() return ns.db and ns.Skin.Scale() or 1 end,
	default = { "BOTTOMRIGHT", "BOTTOMRIGHT", -90, 230 },
	enabled = function() return On() end,
})

function ns.InitLootFeed()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "LOOT_READY",
		"LOOT_OPENED", "LOOT_CLOSED" }) do
		events:RegisterEvent(event)
	end
	-- (currencies: only where the game has them)
	pcall(events.RegisterEvent, events, "CHAT_MSG_CURRENCY")
	events:SetScript("OnEvent", OnEvent)
end
