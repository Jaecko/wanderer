local _, ns = ...
local L = ns.L

-- Wanderer's loot rolls (option, on): what a group rolls for, in one window in place of the game's roll frames.
-- Each item on its card: its square, its name in its quality's color, how many, binds when picked up, better for
-- you, what it is worth; the time left as a line that runs out; Need, Greed, Disenchant (when offered) and Pass,
-- each dimmed with the game's own reason when you cannot choose it. A choice is a roll of the game's (it asks
-- first for what binds, as always). Every roll waiting is there at once. Closed by hand, the game's own frames
-- take the rolls left; its button brings them back for the next times too (a link above them comes back here).

local U = ns.Util
local Skin = ns.Skin
local Safe, Clean = U.Safe, U.Clean
local function G(name) return rawget(_G, name) end

local WIDTH = 440
local CARD = 74
local SHOWN = 6 -- cards at once; more said under them, and shown as the first ones end
local ROLL = { pass = 0, need = 1, greed = 2, disenchant = 3, transmog = 4 }

local window, swap
local rolls = {} -- { id, total (seconds), chosen }
local cards = {}
local switching = false

local function Find(id)
	for index, roll in ipairs(rolls) do if roll.id == id then return roll, index end end
	return nil
end

-- What is rolled for: { name, icon, count, quality, bop, need, greed, disenchant, transmog, reasons, link } or nil.
local function Read(id)
	local icon, name, count, quality, bop, need, greed, disenchant, reasonNeed, reasonGreed, reasonDisenchant, skill, transmog =
		Safe(G("GetLootRollItemInfo"), id)
	name = Clean(name)
	if not name then return nil end
	return { name = name, icon = Clean(icon), count = Clean(count) or 1, quality = Clean(quality), bop = Clean(bop) and true or false,
		need = Clean(need) and true or false, greed = Clean(greed) and true or false, disenchant = Clean(disenchant) and true or false,
		transmog = Clean(transmog) and true or false, link = Clean(Safe(G("GetLootRollItemLink"), id)),
		reasons = { need = Clean(reasonNeed), greed = Clean(reasonGreed), disenchant = Clean(reasonDisenchant) }, skill = Clean(skill) }
end
ns.LootRollRead = Read -- (tests)

-- Seconds left (nil: unknown).
local function Left(roll)
	local left = Clean(Safe(G("GetLootRollTimeLeft"), roll.id))
	return left and left / 1000 or nil
end

-- The game's own reason a choice is closed to you (its words, with the enchanting skill they may ask for), else ours.
local function Reason(code, skill)
	local words = code and G("LOOT_ROLL_INELIGIBLE_REASON" .. code)
	if type(words) ~= "string" then return L.ROLL_CLOSED end
	if words:find("%d", 1, true) then
		local ok, said = pcall(string.format, words, skill or 0)
		return ok and said or L.ROLL_CLOSED
	end
	return words
end

local function Choose(roll, kind)
	-- (one roll per item: a choice made, the others wait greyed until the roll ends, never a second roll sent)
	if not Find(roll.id) or roll.chosen then return end
	roll.chosen = kind
	Safe(G("RollOnLoot"), roll.id, ROLL[kind])
	ns.DrawLootRolls()
end
ns.LootRollChoose = Choose -- (tests)

local BUTTONS = {
	{ key = "need", words = function() return G("NEED") or L.ROLL_NEED end, tip = "ROLL_NEED_TIP" },
	{ key = "greed", words = function() return G("GREED") or L.ROLL_GREED end, tip = "ROLL_GREED_TIP" },
	{ key = "disenchant", words = function() return G("ROLL_DISENCHANT") or L.ROLL_DISENCHANT end, tip = "ROLL_DISENCHANT_TIP" },
	{ key = "pass", words = function() return G("PASS") or L.ROLL_PASS end, tip = "ROLL_PASS_TIP" },
}

local function Card(index)
	local card = Skin.Panel(window)
	card:SetHeight(CARD - 6)
	card.icon = Skin.Icon(card, 40)
	card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
	-- (hovered: the item's own tooltip)
	card.icon:EnableMouse(true)
	card.icon:SetScript("OnEnter", function(self)
		local roll = card.roll
		if not roll then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if GameTooltip.SetLootRollItem then Safe(GameTooltip.SetLootRollItem, GameTooltip, roll.id)
		elseif card.info and card.info.link then GameTooltip:SetHyperlink(card.info.link) end
		GameTooltip:Show()
	end)
	card.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	card.icon:SetScript("OnMouseUp", function()
		if card.info then U.ItemClick(card.info.link) end
	end)
	card.icon.padTip = true
	if Skin.GameWindows() then
		-- (the game look: the game's own count on an item square)
		card.count = Skin.CreateText(card.icon, "NumberFontNormal")
	else
		card.count = Skin.Text(card.icon, "GameTooltipTextSmall", "text")
	end
	card.count:SetPoint("BOTTOMRIGHT", card.icon, "BOTTOMRIGHT", -2, 2)
	card.name = Skin.CreateText(card, "GameTooltipText")
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 0)
	card.name:SetPoint("RIGHT", card, "RIGHT", -60, 0)
	card.name:SetJustifyH("LEFT")
	if card.name.SetWordWrap then card.name:SetWordWrap(false) end
	card.time = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.time:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
	card.detail = Skin.Text(card, "GameTooltipTextSmall", "muted")
	card.detail:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
	card.detail:SetPoint("RIGHT", card, "RIGHT", -10, 0)
	card.detail:SetJustifyH("LEFT")
	if card.detail.SetWordWrap then card.detail:SetWordWrap(false) end
	card.line = Skin.ProgressLine(card, 2)
	card.line:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
	card.line:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
	card.buttons = {}
	local previous
	for _, spec in ipairs(BUTTONS) do
		local button = Skin.SmallButton(card, spec.words(), function(self)
			if card.roll then Choose(card.roll, self.key) end
		end, function(self)
			if self.closed then return { spec.words(), self.closed } end
			return { spec.words(), L[spec.tip] }
		end, 22)
		button.key = spec.key
		button:SetWidth(78)
		if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0) else button:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, -14) end
		previous = button
		card.buttons[spec.key] = button
	end
	cards[index] = card
	return card
end

-- One card drawn (its roll), false when the game no longer has it.
local function Paint(card, roll)
	local info = Read(roll.id)
	card.roll, card.info = roll, info
	if not info then return false end
	card.icon:Set(info.icon, info.quality)
	ns.MarkUpgrade(card.icon, info.link)
	card.count:SetText(info.count > 1 and info.count or "")
	card.name:SetText(info.name)
	Skin.Quality(card.name, info.quality)
	local parts = {}
	if roll.chosen then
		local chosen
		for _, spec in ipairs(BUTTONS) do if spec.key == roll.chosen then chosen = spec.words() end end
		-- (the appearance roll is made on the Greed button, under its own word)
		if roll.chosen == "transmog" then chosen = G("TRANSMOGRIFY") or L.ROLL_GREED end
		parts[#parts + 1] = Skin.Colorize(L.ROLL_CHOSEN:format(chosen or "?"), "gold")
	end
	if info.bop then parts[#parts + 1] = Skin.Colorize(L.LOOT_BOP, "warn") end
	local gain = info.link and ns.UpgradeGain and ns.UpgradeGain(info.link)
	if gain then parts[#parts + 1] = Skin.Colorize(L.ITEM_BETTER:format(gain), "good") end
	local worth = ns.WorthText(info.link, info.count)
	if worth ~= "" then parts[#parts + 1] = worth end
	card.detail:SetText(table.concat(parts, U.SEPARATOR))
	-- (a choice the game closes to you: dimmed, its reason under the mouse; Greed becomes the appearance roll
	-- where the game offers that one instead)
	local greedKey = info.transmog and "transmog" or "greed"
	for key, button in pairs(card.buttons) do
		local open = key == "pass" or (key == "greed" and (info.greed or info.transmog)) or info[key]
		button.closed = not open and Reason(info.reasons[key], info.skill) or nil
		button.key = key == "greed" and greedKey or key
		local chosen = roll.chosen == button.key
		-- (a choice made: the others greyed until the roll ends, the one chosen stays lit; Choose sends no second)
		button:SetEnabled(open and (chosen or not roll.chosen) and true or false)
		button:SetShown(key ~= "disenchant" or info.disenchant or (info.reasons.disenchant or 0) > 0)
		if Skin.GameWindows() then
			-- (the game look: the game's button keeps its own words, greyed when closed; the choice made stays lit)
			if chosen and button.LockHighlight then button:LockHighlight() elseif button.UnlockHighlight then button:UnlockHighlight() end
		else
			button.caption:SetTextColor(Skin.RGB(chosen and "gold" or "kicker"))
		end
	end
	if info.transmog then card.buttons.greed:SetLabel(G("TRANSMOGRIFY") or L.ROLL_GREED) else card.buttons.greed:SetLabel(G("GREED") or L.ROLL_GREED) end
	card.buttons.greed:SetWidth(78)
	-- (Pass beside the last choice shown: no hole where Disenchant is not offered)
	local pass, disenchant = card.buttons.pass, card.buttons.disenchant
	pass:ClearAllPoints()
	pass:SetPoint("LEFT", disenchant:IsShown() and disenchant or card.buttons.greed, "RIGHT", 6, 0)
	return true
end

local function Tick()
	if not (window and window:IsShown()) then return end
	-- (said only while the controller is elsewhere)
	if window.padHint then window.padHint:SetShown(not (Skin.PadHolds and Skin.PadHolds(window))) end
	for _, card in ipairs(cards) do
		local roll = card:IsShown() and card.roll
		if roll then
			local left = Left(roll)
			if left and roll.total and roll.total > 0 then
				card.line:Set(left / roll.total)
				card.time:SetText(L.ROLL_SECONDS:format(math.max(0, math.ceil(left))))
				-- (the last seconds said in the warning colour)
				card.time:SetTextColor(Skin.RGB(left <= 10 and "warn" or "soft"))
			else
				card.time:SetText("")
			end
		end
	end
end

function ns.DrawLootRolls()
	if not (window and window:IsShown()) then return end
	local y = window.top
	local shown = 0
	for index, roll in ipairs(rolls) do
		if index > SHOWN then break end
		local card = cards[index] or Card(index)
		if Paint(card, roll) then
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", window, "TOPLEFT", window.margin, -y)
			card:SetPoint("RIGHT", window, "RIGHT", -window.margin, 0)
			card:Show()
			y = y + CARD
			shown = shown + 1
		else
			card:Hide()
		end
	end
	-- (cards go by roll: one the game cannot read yet is hidden above, those after it stay)
	for index = math.min(#rolls, SHOWN) + 1, #cards do cards[index]:Hide() end
	local waiting = #rolls - shown
	window.more:SetShown(waiting > 0)
	window.more:SetText(waiting > 0 and U.Plural(waiting, L.ROLLS_MORE_ONE, L.ROLLS_MORE_MANY) or "")
	window.title:SetText(U.Plural(#rolls, L.ROLLS_TITLE_ONE, L.ROLLS_TITLE_MANY))
	local pad = U.UsingPad and U.UsingPad()
	window.padHint:SetText(pad and (Skin.PadKeys({ { "PADSOCIAL", "CHOOSE" } }) or L.ROLLS_PAD_HINT) or "")
	window:SetHeight(y + ((waiting > 0 or pad) and 20 or 0) + window.bottom)
	Tick()
end

local function Create()
	window = Skin.CreateWindow("WandererLootRolls", "MEDIUM")
	Skin.Dress(window, { "BOTTOM", UIParent, "BOTTOM", 0, 220 }, "lootRollsPos")
	-- (a controller: the rolls come by themselves, in the middle of a fight's end, so they never take the cross away
	-- from your spells; the touchpad enters them, as a notice, and its right button leaves them, still waiting)
	Skin.PadWindow(window, { leaves = true })
	if Skin.PadNotice then Skin.PadNotice(window) end
	-- (Escape leaves it, as it leaves the game's roll frames: pressed in a fight to let go of a target, it must
	-- never push the rolls away; its cross does)
	local special = rawget(_G, "UISpecialFrames")
	if type(special) == "table" then
		for index = #special, 1, -1 do if special[index] == "WandererLootRolls" then table.remove(special, index) end end
	end
	-- (no sound of its own, as the game's roll frames)
	window.wandererSounds = true
	window:SetSize(WIDTH, 200)
	local _, title, margin = Skin.Header(window, L.ROLLS_KICKER, "", { margin = 6, settings = "practical" }, "GameFontNormalLarge")
	window.title, window.margin = title, margin
	-- (the game look: the heading in the game's bar, the button on one line level with the cog, the cards under it)
	local game = Skin.GameWindows()
	window.top = game and 32 or margin + 48
	window.game = ns.SwapButton(window, swap)
	if game then window.game:SetPoint("TOPRIGHT", window, "TOPRIGHT", -32, -3)
	else window.game:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(margin + 50), -margin + 2) end
	window.more = Skin.Text(window, "GameTooltipTextSmall", "muted")
	window.more:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin + 2)
	-- (with a controller, how to come to them)
	window.padHint = Skin.Text(window, "GameTooltipTextSmall", "muted")
	window.padHint:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin + 2)
	window.bottom = margin + 6
	window:HookScript("OnSizeChanged", function(self)
		local skin = Skin.Get(self)
		if skin then skin:Layout() end
	end)
	window:HookScript("OnShow", function() ns.DrawLootRolls() end)
	window:SetScript("OnUpdate", function(self, elapsed)
		self.since = (self.since or 0) + elapsed
		if self.since < 0.25 then return end
		self.since = 0
		Tick()
	end)
	-- Closed by hand (its cross, Escape): the game's own frames take the rolls left (never lost).
	window:HookScript("OnHide", function(self)
		if switching or self:IsShown() or not rolls[1] then return end
		swap:GameOnce()
	end)
	Skin.Get(window):Layout()
end

local function Show()
	if not rolls[1] then return end
	if not swap:Wanderer() then return end
	if not window then Create() end
	if window:IsShown() then
		ns.DrawLootRolls()
	else
		-- (come by itself: it waits for the controller)
		window.padWaits = true
		window:Show()
	end
end

local function HideWindow()
	if window and window:IsShown() then
		switching = true
		window:Hide()
		switching = false
	end
end

-- A roll begins (its id, its time in milliseconds).
local function Add(id, total)
	id = Clean(id)
	if not id or Find(id) then return end
	total = Clean(total) or Clean(Safe(G("C_Loot") and G("C_Loot").GetLootRollDuration, id))
	rolls[#rolls + 1] = { id = id, total = total and total / 1000 or nil }
	if not swap.visiting then swap:Start() end
	Show()
end

local function Remove(id)
	local _, index = Find(id)
	if index then table.remove(rolls, index) end
	if rolls[1] then
		ns.DrawLootRolls()
		return
	end
	HideWindow()
	swap:End()
end

local function RemoveAll()
	wipe(rolls)
	HideWindow()
	swap:End()
end
ns.LootRollAdd, ns.LootRollRemove = Add, Remove -- (tests)
function ns.LootRolls() return rolls end

function ns.RefreshLootRolls()
	if not (swap and rolls[1]) then return end
	swap.game = false
	swap:Place()
	if swap:Wanderer() then Show() else HideWindow() end
end

function ns.InitLootRolls()
	swap = ns.Swap({
		frame = function() return G("GroupLootContainer") end,
		wanted = function() return ns.db.loot.rolls and not ns.Yields("lootRolls") end,
		choose = function(on) ns.KeepChoice("loot", "rolls", on) end,
		link = L.ROLLS_WINDOW, linkTip = L.SWAP_BACK_DESC,
		point = { "BOTTOM", "TOP", 0, 6 },
		onGame = HideWindow,
		onWanderer = Show,
	})
	ns.rollsSwap = swap
	swap:Hook()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, id, total)
		if event == "START_LOOT_ROLL" then
			Add(id, total)
		elseif event == "CANCEL_LOOT_ROLL" then
			Remove(Clean(id))
		elseif event == "CANCEL_ALL_LOOT_ROLLS" then
			RemoveAll()
		elseif event == "PLAYER_ENTERING_WORLD" then
			-- (after a reload or a loading screen: the rolls still open; those ended meanwhile let go)
			local active = Safe(G("GetActiveLootRollIDs"))
			if type(active) == "table" then
				local still = {}
				for _, open in ipairs(active) do
					local rollID = Clean(open)
					if rollID then still[rollID] = true end
				end
				for index = #rolls, 1, -1 do
					if not still[rolls[index].id] then Remove(rolls[index].id) end
				end
				for _, open in ipairs(active) do Add(open) end
			end
		elseif rolls[1] then
			ns.DrawLootRolls()
		end
	end)
end
