local _, ns = ...
local L = ns.L

-- Wanderer's loot window (option, on): when the game opens its loot window (its auto loot off, or the key that
-- reverses it held; what the bags could not hold), one window in its place. Each thing on its row: its square, its
-- name in its quality's color, how many, the coins written plainly, what it is worth (at the auction house when
-- Wanderer Auction knows it, else at a merchant), and a mark: a quest item, better for you, binds when picked
-- up, being rolled for. A click takes it (the game asks first for what binds); Take all takes the rest at once,
-- except what binds (a click on it, and the game asks). Master loot keeps the game's window (its menus need it),
-- as the button that brings the game's window back (a link above it comes back here). The window stands under
-- the mouse when the game's option asks for it.

local U = ns.Util
local Skin = ns.Skin
local Safe, Clean = U.Safe, U.Clean
local function G(name) return rawget(_G, name) end

local WIDTH = 340
local ROW = 40
local MADE_ROWS = 10 -- shown at once; more scroll
local AUTO_WAIT = 0.6 -- seconds: what the auto loot left behind (full bags) is shown after this
local BIND_ON_PICKUP = 1

local window, swap, list
local looting = false -- the loot open
local entries = {}
local switching = false

local function SlotKind(slot)
	local kind = Clean(Safe(G("GetLootSlotType"), slot))
	local kinds = Enum and Enum.LootSlotType
	if kinds and kind == kinds.Money then return "money" end
	if kinds and kind == kinds.Currency then return "currency" end
	if kinds and kind == kinds.None then return "none" end
	return "item"
end

-- A thing of the loot: { slot, kind, name, icon, count, quality, locked, quest, starts, link, bop }.
local function Slot(slot)
	local icon, name, count, currency, quality, locked, quest, questID, active, coin = Safe(GetLootSlotInfo, slot)
	name = Clean(name)
	if not name or name == "" then return nil end
	local entry = { slot = slot, kind = SlotKind(slot), name = name, icon = Clean(icon), count = Clean(count) or 0,
		quality = Clean(quality), locked = Clean(locked) and true or false, link = Clean(Safe(GetLootSlotLink, slot)) }
	if Clean(coin) then entry.kind = "money" end
	if Clean(currency) then entry.kind = "currency" end
	questID = Clean(questID)
	entry.quest = (Clean(quest) or questID) and true or false
	entry.starts = questID ~= nil and not Clean(active)
	if entry.link and entry.kind == "item" then
		local bind = select(14, Safe(C_Item and C_Item.GetItemInfo or G("GetItemInfo"), entry.link))
		entry.bop = Clean(bind) == BIND_ON_PICKUP
	end
	if entry.kind == "money" then entry.name = name:gsub("\n", " ") end
	return entry
end
ns.LootSlotEntry = Slot -- (tests)

local function Gather()
	wipe(entries)
	for slot = 1, Clean(Safe(GetNumLootItems)) or 0 do
		local entry = Slot(slot)
		if entry then entries[#entries + 1] = entry end
	end
	return entries
end

-- Its mark (one): words and a tone.
local function Mark(entry)
	if entry.locked then return L.LOOT_LOCKED, "red" end
	if entry.starts then return L.MERCHANT_QUEST, "gold" end
	if entry.quest then return L.LOOT_FEED_QUEST_ITEM, "gold" end
	local gain = entry.link and entry.kind == "item" and ns.UpgradeGain and ns.UpgradeGain(entry.link)
	if gain then return L.ITEM_BETTER:format(gain), "green" end
	if entry.bop then return L.LOOT_BOP, "grey" end
	return nil
end
ns.LootMark = Mark -- (tests)

-- One thing taken, the game's way (a question first for what binds: the game's own).
local function Take(entry)
	if not (looting and entry) then return end
	Safe(G("StaticPopup_Hide"), "CONFIRM_LOOT_DISTRIBUTION")
	Safe(LootSlot, entry.slot)
end

-- Everything taken but what binds when picked up (the game asks for each of those: a click on it) and what is
-- being rolled for.
local function TakeAll()
	if not looting then return end
	local found = Gather()
	for index = #found, 1, -1 do
		local entry = found[index]
		if not (entry.locked or entry.bop) then Safe(LootSlot, entry.slot) end
	end
end
ns.LootTakeAll = TakeAll -- (tests)

local function Draw()
	if not (window and window:IsShown() and list) then return end
	Gather()
	-- (as tall as what there is, up to its rows; more scroll)
	local shown = math.max(1, math.min(#entries, MADE_ROWS))
	if shown ~= window.shownRows then
		window.shownRows = shown
		window:SetHeight(window.top + shown * ROW + window.bottom)
		list:Fit(shown * ROW)
	end
	local offset = list:Clamp(#entries)
	local any, taking = false, false
	for index, row in ipairs(list.rows) do
		local entry = entries[offset + index]
		if not entry then
			row:Fill(nil)
		else
			local name = entry.count > 1 and entry.kind ~= "money" and (entry.name .. Skin.Colorize("  x" .. entry.count, "soft")) or entry.name
			local chip, tone = Mark(entry)
			local worth = entry.kind == "item" and ns.WorthText(entry.link, entry.count) or ""
			row:Fill({ name = name, icon = entry.icon, quality = entry.kind ~= "money" and entry.quality or nil, link = entry.link,
				color = entry.kind == "money" and Skin.COLORS.gold or nil, loot = entry }, false, { worth = worth }, chip, tone)
			if row.icon then
				if entry.locked then row.icon.texture:SetVertexColor(0.9, 0.2, 0.2) else row.icon.texture:SetVertexColor(1, 1, 1) end
			end
			ns.MarkUpgrade(row.icon, entry.kind == "item" and entry.link or nil)
		end
	end
	for _, entry in ipairs(entries) do
		any = true
		if not (entry.locked or entry.bop) then taking = true end
	end
	window.takeAll:SetEnabled(taking)
	list.empty:SetShown(not any)
	list.empty:SetText(L.LOOT_EMPTY)
	window.count:SetText(any and U.Plural(#entries, L.LOOT_COUNT_ONE, L.LOOT_COUNT_MANY) or "")
end
local drawSoon

-- Where the loot came from: a creature's name, else plain words.
local function Source()
	if Clean(Safe(G("IsFishingLoot"))) then return L.LOOT_FISHING end
	if Clean(Safe(UnitExists, "target")) and Clean(Safe(UnitIsDead, "target")) then
		local name = Clean(Safe(UnitName, "target"))
		if name then return name end
	end
	return L.LOOT_TITLE
end

local function Clicked(entry)
	if entry.loot then Take(entry.loot) end
end

local function Create()
	window = Skin.CreateWindow("WandererLootWindow", "MEDIUM")
	Skin.Dress(window, { "TOPLEFT", UIParent, "TOPLEFT", 40, -260 }, "lootPos")
	-- (no sound of its own: the game's loot window, kept open aside, plays the game's loot sounds)
	window.wandererSounds = true
	window:SetSize(WIDTH, 200)
	local _, title, margin = Skin.Header(window, L.LOOT_KICKER, "", { margin = 6, settings = "practical" }, "GameFontNormalLarge")
	window.title, window.margin = title, margin
	title:SetPoint("RIGHT", window, "RIGHT", -(margin + 40), 0)
	title:SetJustifyH("LEFT")
	if title.SetWordWrap then title:SetWordWrap(false) end
	window.count = Skin.Text(window, "GameTooltipTextSmall", "muted")
	-- (the game look: the title is in the game's bar, so the count takes its place, the list right under it)
	if Skin.GameWindows() then
		window.count:SetPoint("BOTTOMLEFT", title, "BOTTOMLEFT", 0, 1)
		window.top = margin + 10
	else
		window.count:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
		window.top = margin + 58
	end
	list = Skin.Table(window, {
		width = WIDTH - margin * 2, rows = MADE_ROWS, rowHeight = ROW, titles = false,
		columns = { { key = "worth", title = "", width = 92 } },
		onDraw = Draw, onClick = Clicked,
	})
	list:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -window.top)
	-- (the controller starts on the first thing to take)
	if list.rows[1] then list.rows[1].padFirst = true end
	for _, row in ipairs(list.rows) do
		-- Hovered: the game's own tooltip of the loot (its quest line, its comparison).
		row:HookScript("OnEnter", function(self)
			local entry = self.entry and self.entry.loot
			if not entry or entry.kind == "money" then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if entry.kind == "currency" and GameTooltip.SetLootCurrency then
				Safe(GameTooltip.SetLootCurrency, GameTooltip, entry.slot)
			elseif GameTooltip.SetLootItem then
				Safe(GameTooltip.SetLootItem, GameTooltip, entry.slot)
			elseif entry.link then
				GameTooltip:SetHyperlink(entry.link)
			end
			GameTooltip:Show()
		end)
	end
	window.list = list
	-- The foot: the game's window, Take all.
	window.takeAll = Skin.Button(window, L.LOOT_TAKE_ALL, TakeAll, "main", 120)
	window.takeAll:SetHeight(30)
	window.takeAll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin + 16)
	Skin.Tooltip(window.takeAll, L.LOOT_TAKE_ALL_TIP)
	window.game = ns.SwapButton(window, swap)
	window.game:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin + 20)
	window.hint = Skin.Text(window, "GameTooltipTextSmall", "muted")
	window.hint:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin - 2)
	window.hint:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	window.hint:SetJustifyH("LEFT")
	window.bottom = margin + 16 + 30 + 12
	window:HookScript("OnSizeChanged", function(self)
		local skin = Skin.Get(self)
		if skin then skin:Layout() end
	end)
	window:HookScript("OnShow", function(self)
		self.shownRows = nil
		self.title:SetText(Source())
		self.hint:SetText(U.UsingPad and U.UsingPad() and L.LOOT_HINT_PAD or L.LOOT_HINT)
		Draw()
	end)
	-- Closed by hand (its cross, Escape): the loot closes, as the game's window does.
	window:HookScript("OnHide", function(self)
		if switching or self:IsShown() or not looting then return end
		Safe(G("CloseLoot"))
	end)
	Skin.Get(window):Layout()
end

-- Under the mouse, when the game's own option asks for its loot window there (else where you left it).
local function PlaceUnderMouse()
	if not Clean(Safe(GetCVarBool, "lootUnderMouse")) then return end
	local x, y = Skin.CursorPoint()
	local scale = window:GetEffectiveScale()
	if not (x and y and scale and scale > 0) then return end
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 30, y / scale + 30)
end

local function Open()
	if not looting then return end
	if not window then Create() end
	if window:IsShown() then return Draw() end
	window:Show()
	PlaceUnderMouse()
end

-- Master loot in a group: the game's window, whose menus give the loot away.
local function MasterLoot()
	if not Clean(Safe(G("IsInGroup"))) then return false end
	if Clean(Safe(G("GetLootMethod"))) == "master" then return true end
	local method = C_PartyInfo and C_PartyInfo.GetLootMethod and Clean(Safe(C_PartyInfo.GetLootMethod))
	local kinds = Enum and Enum.LootMethod
	local master = kinds and (kinds.Masterlooter or kinds.MasterLooter or kinds.Master)
	return master ~= nil and method == master
end
ns.LootMasterLoot = MasterLoot -- (tests)

local function Opened(auto)
	looting = true
	if MasterLoot() then swap.game = true end
	swap:Start()
	if not swap:Wanderer() then return end
	-- (the auto loot takes everything by itself: shown only for what it left, full bags)
	if auto then
		C_Timer.After(AUTO_WAIT, function()
			if looting and swap:Wanderer() and Gather()[1] then Open() end
		end)
		return
	end
	Open()
end

local function Closed()
	looting = false
	swap:End()
	if window and window:IsShown() then
		switching = true
		window:Hide()
		switching = false
	end
end
ns.LootOpened, ns.LootClosed = Opened, Closed -- (tests)

function ns.RefreshLootWindow()
	if ns.RefreshLootRolls then ns.RefreshLootRolls() end
	if not (looting and swap) then return end
	swap.game = MasterLoot()
	swap:Place()
	if swap:Wanderer() then
		Open()
	elseif window and window:IsShown() then
		switching = true
		window:Hide()
		switching = false
	end
end

function ns.InitLootWindow()
	swap = ns.Swap({
		frame = function() return G("LootFrame") end,
		wanted = function() return ns.db.loot.window and not ns.Yields("lootWindow") end,
		choose = function(on) ns.KeepChoice("loot", "window", on) end,
		link = L.LOOT_WINDOW, linkTip = L.SWAP_BACK_DESC,
		onGame = function()
			if window and window:IsShown() then
				switching = true
				window:Hide()
				switching = false
			end
		end,
		onWanderer = Open,
	})
	ns.lootSwap = swap
	drawSoon = U.Debounce(0.05, Draw)
	swap:Hook()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "OPEN_MASTER_LOOT_LIST",
		"GET_ITEM_INFO_RECEIVED", "UI_ERROR_MESSAGE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, first, second)
		if event == "LOOT_OPENED" then
			Opened(Clean(first) and true or false)
		elseif event == "LOOT_CLOSED" then
			if looting then Closed() end
		elseif not looting then
			return
		elseif event == "OPEN_MASTER_LOOT_LIST" then
			-- (the game gives the loot away from its own window: it comes back for this time)
			if swap:Wanderer() then swap:GameOnce() end
		elseif event == "UI_ERROR_MESSAGE" then
			-- (bags full under the auto loot: what is left, shown now)
			if second == G("ERR_INV_FULL") and swap:Wanderer() then Open() end
		elseif window and window:IsShown() then
			drawSoon()
		end
	end)
end
