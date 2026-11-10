local _, ns = ...
local L = ns.L
local U = ns.Util

-- Wanderer's card, opened from the minimap crest or the bar's first word (in the place of a plain menu): who
-- you are in Wanderer (the profile, the names, what you changed) and its switch; a tile for each window
-- (reminders, weights, characters, each extension's), with what waits there and one sentence about it under
-- the mouse; then the quiet tools (placing, photos, other addons, recent notices, settings, welcome, news,
-- reload). Keys 1 to 9 open the tiles, Escape closes it, as does a click elsewhere or a second click on the crest.
-- Plain frames only: nothing protected, any time (the reload's secure button belongs to the screen).

local WIDTH = 316
local MARGIN = 12
local TILE_W, TILE_H, TILE_GAP, PER_ROW = 68, 60, 6, 4
local CREST = 36
local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local MAX_TILES = 12
local HOVER_LINES = 2

local card
local tiles, rows, recentRows = {}, {}, {}
local recentOpen = false
local Fill -- (the card drawn again)

-- Its colors, read once it is made (Kit.lua's).
local C

-- The extensions' icons: their own (the TOC's), else their offer's.
local function ExtensionIcon(extension)
	local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local icon = metadata and extension.addon and U.Clean(U.Safe(metadata, extension.addon, "IconTexture"))
	if icon then return icon end
	for _, offer in ipairs(ns.EXTENSION_OFFERS or {}) do
		if offer.addon == extension.addon then return offer.icon end
	end
	return ICON
end

-- The reminders' first lines left to do (their hover).
local function TodoLines()
	local lines = ns.TodoLines()
	if not lines[1] then lines[1] = { text = L.TODO_EMPTY_SHORT, role = "muted" } end
	return lines
end

-- The tiles, as things stand: { label, icon, count, summary() (lines), open, isOpen() }.
function ns.CardTiles()
	local list = {}
	local pending = ns.TodoPending()
	list[#list + 1] = { key = "todo", label = L.TODO_TITLE, icon = "Interface\\Icons\\INV_Misc_Note_01", count = pending,
		summary = TodoLines, open = function() ns.ToggleTodo() end,
		isOpen = function() return _G.WandererTodo and _G.WandererTodo:IsShown() end }
	if ns.db.tooltips.upgrade then
		list[#list + 1] = { key = "weights", label = L.WEIGHTS_TITLE, icon = "Interface\\Icons\\INV_Sword_04",
			summary = function() return { { text = L.WEIGHTS_OPEN_DESC } } end, open = function() ns.ToggleWeights() end,
			isOpen = function() return _G.WandererWeights and _G.WandererWeights:IsShown() end }
	end
	if #ns.Characters() > 1 then
		list[#list + 1] = { key = "characters", label = L.CHARACTERS_TITLE, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
			summary = function() return { { text = L.CHARACTERS_DESC } } end, open = function() ns.ToggleCharacters() end,
			isOpen = function() return _G.WandererCharacters and _G.WandererCharacters:IsShown() end }
	end
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		local launcher = ns.LauncherOf(extension)
		if launcher and #list < MAX_TILES then
			local waits = launcher.attention and select(2, pcall(launcher.attention)) == true
			list[#list + 1] = { key = "ext:" .. tostring(extension.key), label = launcher.label, icon = ExtensionIcon(extension),
				count = ns.LauncherCount(launcher), waits = waits, open = function() launcher.open() end,
				summary = function() return ns.LauncherSummary(launcher) end }
		end
	end
	return list
end

-- A tile chosen (a click, its key): the card closes, its window opens.
function ns.OpenCardTile(tile)
	if not (tile and tile.entry) then return end
	ns.Skin.Play("confirm")
	card:Hide()
	tile.entry.open()
end

-- A tile: its icon, its word under it, a gold count at its corner, a gold edge while its window is open.
local function Tile(index)
	local tile = tiles[index]
	if tile then return tile end
	tile = CreateFrame("Button", nil, card)
	tile:SetSize(TILE_W, TILE_H)
	tile.ground = tile:CreateTexture(nil, "BACKGROUND")
	tile.ground:SetAllPoints()
	tile.ground:SetColorTexture(1, 1, 1, 0.04)
	tile.edges = ns.Skin.Edges(tile, 1, 1, 1, 0.08)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetSize(28, 28)
	tile.icon:SetPoint("TOP", tile, "TOP", 0, -9)
	tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tile.word = ns.Skin.Text(tile, "GameFontNormalSmall", "soft")
	tile.word:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 3, 6)
	tile.word:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -3, 6)
	tile.word:SetJustifyH("CENTER")
	if tile.word.SetWordWrap then tile.word:SetWordWrap(false) end
	tile.count = ns.Skin.Chip(tile)
	tile.count:SetHeight(15)
	tile.count:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -2, -2)
	tile.dot = tile:CreateTexture(nil, "OVERLAY")
	tile.dot:SetSize(6, 6)
	tile.dot:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
	tile.dot:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -5, -5)
	tile.key = ns.Skin.Text(tile, "GameTooltipTextSmall", "muted")
	tile.key:SetPoint("TOPLEFT", tile, "TOPLEFT", 4, -3)
	local function Paint(self, hovered)
		local open = self.entry and self.entry.isOpen and self.entry.isOpen()
		-- (gold under the mouse or while open, else a quiet white)
		local tint = (hovered or open) and C.gold or { 1, 1, 1 }
		self.ground:SetColorTexture(tint[1], tint[2], tint[3], hovered and 0.1 or (open and 0.06 or 0.04))
		self.edges.Color(tint[1], tint[2], tint[3], open and 0.9 or (hovered and 0.5 or 0.08))
		local c = hovered and C.gold or C.soft
		self.word:SetTextColor(c[1], c[2], c[3])
	end
	tile.Paint = Paint
	tile:SetScript("OnEnter", function(self)
		Paint(self, true)
		card.ShowSummary(self.entry)
	end)
	tile:SetScript("OnLeave", function(self)
		Paint(self, false)
		card.ShowSummary(nil)
	end)
	tile:SetScript("OnClick", function(self) ns.OpenCardTile(self) end)
	tiles[index] = tile
	return tile
end

-- Reload ------------------------------------------------------------------------------------------------------
-- A change that only takes effect after a reload marks the card's Reload, with what it is for.

local reloadReasons = {} -- what waits for a reload, in order

function ns.NeedReload(reason)
	if type(reason) ~= "string" or reason == "" then return end
	for _, known in ipairs(reloadReasons) do
		if known == reason then return end
	end
	reloadReasons[#reloadReasons + 1] = reason
end

function ns.ReloadReasons() return reloadReasons end

-- The game's reload, at once (the slash command).
function ns.Reload()
	ReloadUI()
end

-- The game lets only its own secure buttons reload from a window of an addon. A secure button running the game's
-- /reload lies over the Reload line, out of a fight only. It belongs to the screen, never to the card (a card
-- holding a secure button could not close in a fight): placed where the line is once the card is shown, put away
-- as a fight begins and when the card closes. In a fight the line is greyed, "after the fight".
-- (the game locks only after PLAYER_REGEN_DISABLED: inside it, and for the rest of that frame, InCombatLockdown()
-- still says no, so the card keeps its own word for "a fight has begun" until the lock takes over)
local reloadCover
local fightingAt -- GetTime() of the frame a fight began in
local function Locked() return InCombatLockdown() or (fightingAt ~= nil and fightingAt == GetTime()) end

local function UncoverReloadRow()
	if reloadCover and not InCombatLockdown() then reloadCover:Hide() end
end

-- (a fight begins: the cover away, while it still may be; the card drawn again, its line greyed; after it, back)
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
	local fighting = event == "PLAYER_REGEN_DISABLED"
	fightingAt = fighting and GetTime() or nil
	if fighting then UncoverReloadRow() end
	if card and card:IsShown() then
		if ns.RefreshCard then ns.RefreshCard() end
	else
		UncoverReloadRow()
	end
end)

local function CoverReloadRow(row)
	if Locked() then return end
	if not reloadCover then
		local ok, made = pcall(CreateFrame, "Button", "WandererCardReload", UIParent, "SecureActionButtonTemplate")
		if not ok or not made then return end
		reloadCover = made
		reloadCover:SetFrameStrata("DIALOG")
		reloadCover:RegisterForClicks("AnyUp", "AnyDown")
		reloadCover:SetAttribute("type", "macro")
		reloadCover:SetAttribute("macrotext", "/reload")
		reloadCover:SetScript("OnEnter", function(self)
			local enter = self.row and self.row:GetScript("OnEnter")
			if enter then enter(self.row) end
		end)
		reloadCover:SetScript("OnLeave", function(self)
			local leave = self.row and self.row:GetScript("OnLeave")
			if leave then leave(self.row) end
		end)
	end
	reloadCover.row = row
	-- (where the line is on the screen, in the screen's own units)
	local left, top = row:GetLeft(), row:GetTop()
	local ratio = (row:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	if type(left) ~= "number" or type(top) ~= "number" then return reloadCover:Hide() end
	reloadCover:ClearAllPoints()
	reloadCover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * ratio, top * ratio)
	reloadCover:SetSize((row:GetWidth() or 0) * ratio, (row:GetHeight() or 0) * ratio)
	reloadCover:SetFrameLevel(card:GetFrameLevel() + 20)
	reloadCover:Show()
end

-- The tools under the tiles: { text, glyph, right, role, hint, onClick } (onClick: the card closes first, unless
-- keep).
local function Tools()
	local list = {}
	local function Close(fn) return function() card:Hide() fn() end end
	list[#list + 1] = { text = L.MENU_PLACE, glyph = "move", onClick = Close(function() ns.PlaceMode() end) }
	list[#list + 1] = { text = L.MENU_PHOTO, glyph = "camera", onClick = Close(function() ns.TogglePhotoMode() end) }
	if ns.IconsGathered() then
		ns.GatherIcons()
		local owner = card.owner
		local fromBar = owner and owner ~= _G.WandererMinimapButton and owner ~= UIParent
		list[#list + 1] = { text = L.MENU_ICONS:format(ns.CountIcons()), glyph = "grid", right = ">",
			onClick = Close(function() ns.ToggleIconDrawer(fromBar and owner or _G.WandererMinimapButton, fromBar) end) }
	end
	local recent = ns.RecentNotices()
	if recent[1] then
		list[#list + 1] = { text = L.TOAST_RECENT_COUNT:format(#recent), glyph = "bell", right = recentOpen and "^" or "v", keep = true,
			onClick = function()
				recentOpen = not recentOpen
				Fill()
			end }
	end
	list[#list + 1] = { text = L.MENU_OPTIONS, glyph = "cog", onClick = Close(function() ns.OpenOptions() end) }
	-- (the extensions not installed: their pages in the settings, the first one shown)
	local missing, new = ns.OfferInMenu()
	if missing then
		list[#list + 1] = { text = L.MENU_MORE:format(#missing), glyph = "plus", right = new and L.MENU_MORE_NEW or nil,
			role = new and "gold" or nil, onClick = Close(function() ns.OpenOptions("offer:" .. missing[1].addon) end) }
	end
	list[#list + 1] = { text = L.WELCOME_SHOW, glyph = "home", onClick = Close(function() ns.ShowWelcome() end) }
	local unread = ns.NewsSections(true)[1] ~= nil
	list[#list + 1] = { text = L.NEWS_SHOW, glyph = "star", right = unread and L.MENU_MORE_NEW or nil, role = unread and "gold" or nil,
		onClick = Close(function() ns.OpenOptions("news") end) }
	-- (a change waiting for it: in the warning color, and said what for; in a fight: greyed, after it)
	local reasons = ns.ReloadReasons()
	local waiting = reasons[1] ~= nil
	if Locked() then
		list[#list + 1] = { key = "reload", text = L.MENU_RELOAD, glyph = "reload", role = "muted", hint = L.RELOAD_AFTER_FIGHT,
			onClick = function() ns.Skin.Play("refuse") end }
	else
		list[#list + 1] = { key = "reload", text = waiting and (L.MENU_RELOAD .. " *") or L.MENU_RELOAD, glyph = "reload",
			role = waiting and "warn" or nil, hint = waiting and L.RELOAD_NEEDED_FOR:format(table.concat(reasons, ", ")) or nil,
			onClick = Close(function() ns.Reload() end) }
	end
	return list
end

-- The last notices, under their line while it is unfolded: a click repeats their action.
local function RecentEntries()
	local list = {}
	for _, notice in ipairs(ns.RecentNotices()) do
		local action
		for _, line in ipairs(notice.lines or {}) do
			if line.onClick and not action then action = line.onClick end
		end
		list[#list + 1] = { text = date("%H:%M", notice.at or time()) .. "  " .. tostring(notice.title or ""), glyph = false,
			hint = type(notice.text) == "string" and notice.text ~= "" and notice.text or nil,
			onClick = function()
				card:Hide()
				if action and not notice.onClick then action() else ns.ReplayNotice(notice) end
			end }
	end
	return list
end

-- Beside what opened it: under it near the top of the screen (over it near the bottom), toward the middle.
local function Anchor(owner)
	card:ClearAllPoints()
	if not owner or owner == UIParent then
		card:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
		return
	end
	local x, y = owner:GetCenter()
	local width, height = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	local ratio = (owner:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	local right = type(x) == "number" and width > 0 and x * ratio > width / 2
	local low = type(y) == "number" and height > 0 and y * ratio < height / 2
	local vertical = low and "BOTTOM" or "TOP"
	local side = right and "RIGHT" or "LEFT"
	card:SetPoint(vertical .. side, owner, (low and "TOP" or "BOTTOM") .. side, 0, low and 8 or -8)
end

-- The card drawn as things stand.
Fill = function()
	if not card then return end
	local Skin = ns.Skin
	card.state:SetText(L.CARD_STATE:format(ns.profileName or "", L["PRESET_" .. tostring(ns.db.preset):upper()] or ns.db.preset))
	local changed = #ns.ChangedSettings()
	card.changed:SetText(changed > 0 and U.Plural(changed, L.CARD_CHANGED_ONE, L.CARD_CHANGED) or L.CARD_CHANGED_NONE)
	card.switch:Set(ns.db.enabled)
	-- The tiles, four by row.
	local list = ns.CardTiles()
	card.entries = list
	local top = MARGIN + CREST + 14
	for index, entry in ipairs(list) do
		local tile = Tile(index)
		tile.entry = entry
		tile.icon:SetTexture(entry.icon)
		tile.word:SetText(entry.label or "")
		tile.count:Set((entry.count or 0) > 0 and tostring(entry.count) or nil, "gold")
		tile.dot:SetShown(entry.waits and (entry.count or 0) <= 0 or false)
		tile.key:SetText(index <= 9 and tostring(index) or "")
		local column, line = (index - 1) % PER_ROW, math.floor((index - 1) / PER_ROW)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", card, "TOPLEFT", MARGIN + column * (TILE_W + TILE_GAP), -(top + line * (TILE_H + TILE_GAP)))
		tile:Paint(false)
		tile:Show()
	end
	for index = #list + 1, #tiles do tiles[index]:Hide() end
	local y = top + math.ceil(#list / PER_ROW) * (TILE_H + TILE_GAP)
	card.hover:ClearAllPoints()
	card.hover:SetPoint("TOPLEFT", card, "TOPLEFT", MARGIN, -(y + 2))
	card.hover:SetWidth(WIDTH - MARGIN * 2)
	card.ShowSummary(nil)
	-- (its room follows the size of the words: Wanderer's windows' text size)
	local _, size = card.hover:GetFont()
	local room = HOVER_LINES * math.ceil((tonumber(size) or 11) + 3)
	card.hover:SetHeight(room)
	y = y + 2 + room + 8
	card.rule:ClearAllPoints()
	card.rule:SetPoint("TOPLEFT", card, "TOPLEFT", MARGIN, -y)
	card.rule:SetPoint("RIGHT", card, "RIGHT", -MARGIN, 0)
	y = y + 6
	-- The tools, the recent notices unfolded under their line.
	local used, usedRecent = 0, 0
	card.reloadRow = nil
	for _, entry in ipairs(Tools()) do
		used = used + 1
		local row = rows[used] or Skin.CardRow(card)
		rows[used] = row
		row:Set(entry)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", card, "TOPLEFT", MARGIN - 6, -y)
		row:SetPoint("RIGHT", card, "RIGHT", -(MARGIN - 6), 0)
		y = y + Skin.CARD_ROW
		if entry.key == "reload" then card.reloadRow = row end
		if entry.keep and recentOpen then
			for _, notice in ipairs(RecentEntries()) do
				usedRecent = usedRecent + 1
				local sub = recentRows[usedRecent] or Skin.CardRow(card)
				recentRows[usedRecent] = sub
				sub:Set(notice)
				sub:ClearAllPoints()
				sub:SetPoint("TOPLEFT", card, "TOPLEFT", MARGIN + 16, -y)
				sub:SetPoint("RIGHT", card, "RIGHT", -(MARGIN - 6), 0)
				y = y + Skin.CARD_ROW
			end
		end
	end
	for index = used + 1, #rows do rows[index]:Set(nil) end
	for index = usedRecent + 1, #recentRows do recentRows[index]:Set(nil) end
	card.foot:SetText(L.CARD_FOOT:format(math.min(9, #list)))
	card.foot:ClearAllPoints()
	card.foot:SetPoint("TOPLEFT", card, "TOPLEFT", MARGIN, -(y + 6))
	card.foot:SetWidth(WIDTH - MARGIN * 2)
	y = y + 6 + U.Measure(card.foot, "GetStringHeight", 12)
	card:SetSize(WIDTH, y + MARGIN)
	Skin.Get(card):Layout()
	-- (the reload's secure button over its line, once the card stands where it is shown)
	if card:IsShown() and card.reloadRow then CoverReloadRow(card.reloadRow) else UncoverReloadRow() end
end

-- Keys while it is open, out of a fight: 1 to 9 open the tiles, Escape closes it; every other key goes on to
-- the game.
local function Keys(on) ns.Skin.CardKeys(card, on) end

local function OnKey(self, key)
	if InCombatLockdown() then return end
	local index = tonumber(type(key) == "string" and (key:match("^NUMPAD(%d)$") or key:match("^(%d)$")) or "")
	local tile = index and index > 0 and tiles[index]
	local take = key == "ESCAPE" or (tile and tile:IsShown() and tile.entry ~= nil)
	if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, not take) end
	if key == "ESCAPE" then
		ns.Skin.Play("close")
		self:Hide()
	elseif take then
		ns.OpenCardTile(tile)
	end
end

local function Create()
	local Skin = ns.Skin
	C = Skin.COLORS
	card = Skin.CreateWindow("WandererCard", "DIALOG")
	Skin.PadWindow(card)
	Skin.Closable(card, "WandererCard")
	local look = Skin.Get(card)
	if look then look.minOpacity = 0.97 end
	card:SetWidth(WIDTH)
	-- The heading: the crest, Wanderer, who you are in it; its switch; the cross.
	card.crest = card:CreateTexture(nil, "ARTWORK")
	card.crest:SetSize(CREST, CREST)
	card.crest:SetPoint("TOPLEFT", card, "TOPLEFT", MARGIN, -MARGIN)
	card.crest:SetTexture(ICON)
	if not Skin.RoundMask(card, card.crest) then card.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	card.kicker = Skin.Caps(card, L.ADDON_TITLE, "kicker")
	card.kicker:SetPoint("TOPLEFT", card.crest, "TOPRIGHT", 10, 0)
	card.state = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.state:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -3)
	card.state:SetPoint("RIGHT", card, "RIGHT", -MARGIN, 0)
	if card.state.SetWordWrap then card.state:SetWordWrap(false) end
	card.changed = Skin.Text(card, "GameTooltipTextSmall", "muted")
	card.changed:SetPoint("TOPLEFT", card.state, "BOTTOMLEFT", 0, -2)
	Skin.CloseButton(card)
	-- (turning Wanderer off is rare: a small switch at the heading, never among the daily actions)
	-- (the kit's switch, small, its word left of it)
	card.switch = Skin.Switch(card, function()
		Skin.Play("mark")
		ns.SetEnabled(not ns.db.enabled)
		Fill()
	end, "small")
	card.switch:SetPoint("TOPRIGHT", card, "TOPRIGHT", -30, -10)
	card.switch.word = Skin.Text(card, "GameTooltipTextSmall", "muted")
	card.switch.word:SetPoint("RIGHT", card.switch, "LEFT", -6, 0)
	local paint = card.switch.Set
	function card.switch:Set(on)
		paint(self, on)
		self.word:SetText(on and L.CARD_ON or L.CARD_OFF)
	end
	Skin.Tooltip(card.switch, L.MENU_ENABLED, "ANCHOR_BOTTOM")
	-- One sentence about the tile under the mouse, in a room of two lines.
	card.hover = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.hover:SetJustifyH("LEFT")
	card.hover:SetJustifyV("TOP")
	function card.ShowSummary(entry)
		if not entry then
			card.hover:SetText(Skin.Colorize(L.CARD_HOVER_HINT, "muted"))
			return
		end
		local words = {}
		local ok, lines = pcall(entry.summary or function() return {} end)
		for _, line in ipairs(ok and type(lines) == "table" and lines or {}) do
			if #words < HOVER_LINES and type(line.text) == "string" then words[#words + 1] = Skin.Colorize(line.text, line.role or "text") end
		end
		card.hover:SetText(words[1] and table.concat(words, "\n") or Skin.Colorize(L.BAR_CLICK_OPEN, "muted"))
	end
	card.rule = Skin.Rule(card, false, 0.14)
	card.foot = Skin.Text(card, "GameTooltipTextSmall", "muted")
	card:SetScript("OnKeyDown", OnKey)
	card:HookScript("OnShow", function() Keys(true) end)
	card:HookScript("OnHide", function()
		Keys(false)
		UncoverReloadRow()
		recentOpen = false
		if ns.OffersSeen and ns.root then ns.OffersSeen() end
	end)
end

-- Opens the card beside its owner (a second click on it: closed).
function ns.ShowMenu(owner)
	if not ns.db then return end
	GameTooltip:Hide()
	if not card then Create() end
	if card:IsShown() and card.owner == owner then return card:Hide() end
	card.owner = owner
	card:SetScale(ns.Skin.Scale())
	Fill()
	Anchor(owner)
	card:Show()
	if card.reloadRow then CoverReloadRow(card.reloadRow) end
	return card
end

-- The card drawn again while it is open (a count changed).
function ns.RefreshCard()
	if card and card:IsShown() then Fill() end
end

function ns.HideCard()
	if card then card:Hide() end
end
