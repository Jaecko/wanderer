local _, ns = ...
local L = ns.L

-- The emote bar (option, off until asked): a slim row of the game's friendly emotes, out of sight until
-- the mouse comes near, then it comes in a breath. A click is the emote as if typed (toward your target
-- when you have one): players nearby see it. Moved by dragging it, its place kept for this character.
-- Out of the way in a fight.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local SIZE = 26 -- a button
local GAP = 4
local PAD = 6
local NEAR = 48 -- pixels around the bar where the mouse brings it in
local SHOW_FIRST = 6 -- seconds it shows when it first comes, so it can be found
local shownOnce = false
local FADE_IN, FADE_OUT = 0.2, 0.8
local USABLE_ALPHA = 0.5 -- seen enough to be clicked
local SPOT = "emotes"
local POINT = { "TOP", UIParent, "TOP", 0, -6 }
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The game's emote tokens, with their icons.
ns.EMOTES = {
	{ token = "WAVE", icon = "INV_Gauntlets_04" },
	{ token = "BOW", icon = "Spell_Holy_DivineSpirit" },
	{ token = "SALUTE", icon = "INV_Banner_02" },
	{ token = "CHEER", icon = "Ability_Warrior_BattleShout" },
	{ token = "APPLAUD", icon = "Spell_Holy_ChampionsBond" },
	{ token = "LAUGH", icon = "Spell_Holy_MindSooth" },
	{ token = "DANCE", icon = "Spell_Nature_Cyclone" },
	{ token = "SIT", icon = "Spell_Nature_Tranquility" },
	{ token = "KNEEL", icon = "Spell_Holy_PrayerOfHealing" },
	{ token = "SLEEP", icon = "Spell_Nature_Sleep" },
	{ token = "EAT", icon = "INV_Misc_Food_15" },
	{ token = "STAND", icon = "Ability_Rogue_Sprint" },
}

local bar
local commands -- token -> the game's own command in your language ("/danse"), read once

local function On()
	local db = ns.db
	local own = db and db.emotes
	return db and db.enabled and type(own) == "table" and own.enabled == true or false
end

-- The icon's file, or the question mark when the game does not know it.
local function IconPath(name)
	local path = "Interface\\Icons\\" .. name
	if GetFileIDFromPath and Clean(Safe(GetFileIDFromPath, path)) == nil then return FALLBACK_ICON end
	return path
end

-- The game's own command for an emote, as typed in your language.
local function Command(token)
	if not commands then
		commands = {}
		for index = 1, tonumber(_G.MAXEMOTEINDEX) or 800 do
			local known = _G["EMOTE" .. index .. "_TOKEN"]
			local typed = _G["EMOTE" .. index .. "_CMD1"]
			if type(known) == "string" and type(typed) == "string" and not commands[known] then commands[known] = typed end
		end
	end
	return commands[token]
end

-- The emote, toward your target when you have one (the game's own rule). Never in a fight.
function ns.PlayEmote(token)
	if InCombatLockdown() or not DoEmote then return false end
	Safe(DoEmote, token)
	return true
end

local function Tip(button)
	local entry = button.entry
	local lines = { L["EMOTE_" .. entry.token] or entry.token }
	local target = Clean(Safe(UnitName, "target"))
	if target then lines[#lines + 1] = { L.EMOTES_TOWARD:format(target), ns.Skin.RGB("soft") } end
	local typed = Command(entry.token)
	if typed then lines[#lines + 1] = { typed, 0.56, 0.53, 0.46 } end
	return lines
end

-- The bar comes in while the mouse is near, out of a fight; goes out slowly otherwise.
local function Watch(self, elapsed)
	-- (shown a moment when it comes, so you know where it waits; with a controller it is not kept and cannot be reached)
	local near = not InCombatLockdown() and (self:IsMouseOver(NEAR, -NEAR, -NEAR, NEAR) or GetTime() < (self.showUntil or 0))
	local alpha = ns.Skin.Fade(self, near and 1 or 0, elapsed, FADE_IN, FADE_OUT)
	-- (clicks taken only once it is seen: an emote never goes from a bar still out of sight)
	local usable = (alpha or 0) > USABLE_ALPHA
	if usable ~= self.usable then
		self.usable = usable
		self:EnableMouse(usable)
		for _, button in ipairs(self.buttons or {}) do button:EnableMouse(usable) end
	end
end

local function Save()
	local anchor, _, _, x, y = bar:GetPoint(1)
	if anchor and ns.root then ns.Spots()[SPOT] = { anchor, x, y } end
end

-- Where this character put it (dragged, or in the placing mode: Place.lua), or the top of the screen.
local function Place() ns.PlaceApply(SPOT, bar) end

local function Button(index, entry)
	local button = CreateFrame("Button", nil, bar)
	button:SetSize(SIZE, SIZE)
	button:SetPoint("LEFT", bar, "LEFT", PAD + (index - 1) * (SIZE + GAP), 0)
	button.entry = entry
	button.square = ns.Skin.Icon(button, SIZE)
	button.square:SetPoint("CENTER")
	button.square:Set(IconPath(entry.icon))
	button:RegisterForClicks("LeftButtonUp")
	-- (dragged from a button: the bar moves, no emote)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		self.dragged = true
		bar:StartMoving()
	end)
	button:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		Save()
	end)
	button:SetScript("OnClick", function(self)
		if self.dragged then
			self.dragged = nil
			return
		end
		GameTooltip:Hide()
		if ns.PlayEmote(entry.token) then ns.Skin.Play("click") end
	end)
	button:SetScript("OnMouseDown", function(self)
		self.dragged = nil
		self.square:SetPoint("CENTER", 1, -1)
	end)
	button:SetScript("OnMouseUp", function(self) self.square:SetPoint("CENTER", 0, 0) end)
	button:SetScript("OnEnter", function(self)
		local gold = ns.Skin.COLORS.gold
		self.square.edges.Color(gold[1], gold[2], gold[3], 0.9)
	end)
	button:SetScript("OnLeave", function(self) self.square.edges.Color(1, 1, 1, 0.2) end)
	ns.Skin.Tooltip(button, Tip, "ANCHOR_TOP")
	return button
end

local function Build()
	bar = ns.Skin.CreateWindow(nil, "MEDIUM", nil, true)
	bar:SetSize(PAD * 2 + #ns.EMOTES * SIZE + (#ns.EMOTES - 1) * GAP, SIZE + PAD * 2)
	-- Moved like every window, without its cross: nothing to close, the option says if it is there.
	local cross = ns.Skin.Dress(bar, POINT)
	if cross then cross:Hide() end
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Save()
	end)
	bar.buttons = {}
	for index, entry in ipairs(ns.EMOTES) do bar.buttons[index] = Button(index, entry) end
	bar:SetAlpha(0)
	bar:SetScript("OnUpdate", Watch)
end

-- The bar itself (tests).
function ns.EmoteBar() return bar end
-- Its first coming of the session, to come again (tests: a way to play may have shown it before).
function ns.ForgetEmoteBarShown() shownOnce = false end

function ns.RefreshEmotes()
	if not On() then
		if bar then bar:Hide() end
		return
	end
	if not bar then Build() end
	Place()
	-- (out of the way in a fight: back after it)
	if InCombatLockdown() then bar:Hide() return end
	if not bar:IsShown() then
		bar:SetAlpha(0)
		bar:Show()
		-- Where it waits, the first time it comes in a session: seen a few seconds, then said once.
		if not shownOnce then
			shownOnce = true
			bar.showUntil = GetTime() + SHOW_FIRST
			-- Under the pad the bar is out of reach: nothing to point at.
			if not U.UsingPad() and not (ns.Mine and ns.Mine().emotesTold) then
				if ns.Mine then ns.Mine().emotesTold = true end
				ns.Print(L.EMOTES_WHERE)
			end
		end
	end
end

local initialized = false
function ns.InitEmotes()
	if initialized then return end
	initialized = true
	ns.Placeable({ key = SPOT, spot = SPOT, label = function() return L.EMOTES_BAR end, frame = function() return bar end,
		default = { POINT[1], POINT[3], POINT[4], POINT[5] }, enabled = On,
		size = { PAD * 2 + #ns.EMOTES * SIZE + (#ns.EMOTES - 1) * GAP, SIZE + PAD * 2 } })
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			if bar then bar:Hide() end
		else
			ns.RefreshEmotes()
		end
	end)
	-- Settings changed, profile or character switched: brought in line.
	if ns.RefreshAll then hooksecurefunc(ns, "RefreshAll", ns.RefreshEmotes) end
	ns.RefreshEmotes()
end
