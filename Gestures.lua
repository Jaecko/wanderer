local _, ns = ...

-- Gestures: the character acts out what the player does. Opening the map,
-- the spellbook, a book or the mailbox, they take out something to read (the
-- game's /read emote); reaching a new level, they cheer; meeting a character
-- to talk to, they greet it (once in a while); clicking a campfire, they sit
-- by it. These are real emotes: players nearby see them, as if typed. Off by
-- default (the campfire's sit excepted, asked for); never in a fight, mounted,
-- moving, swimming or flying; Shift held skips them.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local READ_COOLDOWN = 20 -- seconds: toggling the map never repeats the gesture
local CHEER_DELAY = 1.5 -- after the level up's own light
local GREET_AGAIN = 30 * 60 -- the same character is greeted again after this
local GREET_EVENTS = { GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true, MERCHANT_SHOW = true,
	TRAINER_SHOW = true, TAXIMAP_OPENED = true, BANKFRAME_OPENED = true }

-- Windows that open a reading, with the addon that holds them (nil: always loaded).
local READING_FRAMES = {
	{ "WorldMapFrame", "Blizzard_WorldMap" },
	{ "PlayerSpellsFrame", "Blizzard_PlayerSpells" },
	{ "SpellBookFrame" },
}

local lastRead = 0
local SIT_AGAIN = 2 -- seconds: one click seats you once
local CLICK_SLACK = 6 -- pixels the mouse may move between press and release
-- A campfire's name as the game shows it over one (its spell's name holds it too).
local FIRE_NAMES = { "Campfire", "Feu de camp", "Lagerfeuer", "Fogata", "Hoguera", "Fuoco da campo", "Fogueira",
	"Костер", "Костёр", "모닥불", "营火", "營火" }
local FIRE_SPELL = 818

local function Free()
	if not (ns.db and ns.db.enabled) then return false end
	if InCombatLockdown() or U.IsSkipping() then return false end
	if Clean(Safe(IsMounted)) or Clean(Safe(IsFlying)) or Clean(Safe(IsSwimming)) then return false end
	if Clean(Safe(UnitInVehicle, "player")) or Clean(Safe(UnitIsDeadOrGhost, "player")) then return false end
	local speed = Clean(Safe(GetUnitSpeed, "player"))
	return not (speed and speed > 0)
end

local function Read()
	if not (ns.db.gestures.read and Free()) then return end
	if GetTime() - lastRead < READ_COOLDOWN then return end
	lastRead = GetTime()
	if DoEmote then Safe(DoEmote, "READ") end
end

-- A nod to the character you start talking to (once in a while, not at
-- every page of the same conversation).
local greeted = {} -- npc id -> time
local function Greet()
	if not (ns.db.gestures.greet and Free()) then return end
	local npc = U.NpcID(Safe(UnitGUID, "npc"))
	if not npc or GetTime() - (greeted[npc] or -GREET_AGAIN) < GREET_AGAIN then return end
	greeted[npc] = GetTime()
	-- The game wants the name of whom to greet (else it greets everyone).
	local name = Clean(Safe(UnitName, "npc"))
	-- A wave, without a word: the character you greet is the one speaking.
	if name and DoEmote then Safe(DoEmote, "WAVE", name) end
end

local hooked = {}

-- Each window there hooked; true while one may still come (its addon not loaded yet).
local function HookFrames()
	local waiting = false
	for _, entry in ipairs(READING_FRAMES) do
		local frame = _G[entry[1]]
		if frame and not hooked[frame] and frame.HookScript then
			hooked[frame] = true
			frame:HookScript("OnShow", Read)
		end
		if not hooked[frame or false] and entry[2] and not ns.IsAddOnLoaded(entry[2]) then waiting = true end
	end
	return waiting
end

-- A campfire under the mouse: the game's tooltip shows its name, no unit is there.
local function IsFire(text)
	if type(text) ~= "string" or text == "" then return false end
	for _, name in ipairs(FIRE_NAMES) do
		if text == name then return true end
	end
	local spell = C_Spell and C_Spell.GetSpellName and Clean(Safe(C_Spell.GetSpellName, FIRE_SPELL))
	return type(spell) == "string" and #text >= 4 and spell:find(text, 1, true) ~= nil
end

local function FireHovered()
	if not (GameTooltip:IsShown() and Safe(GameTooltip.GetOwner, GameTooltip) == UIParent) then return false end
	if Clean(Safe(UnitExists, "mouseover")) then return false end
	local line = _G.GameTooltipTextLeft1
	return line ~= nil and IsFire(Clean(Safe(line.GetText, line)))
end

local lastSit, press = 0, nil

local function WatchFire()
	WorldFrame:HookScript("OnMouseDown", function(_, button)
		press = nil
		if button ~= "LeftButton" or not (ns.db and ns.db.gestures.sitAtFire) or not FireHovered() then return end
		local x, y = GetCursorPosition()
		press = { x = x, y = y }
	end)
	WorldFrame:HookScript("OnMouseUp", function(_, button)
		local at = press
		press = nil
		if button ~= "LeftButton" or not at or not (ns.db.gestures.sitAtFire and Free()) then return end
		local x, y = GetCursorPosition()
		if math.abs(x - at.x) > CLICK_SLACK or math.abs(y - at.y) > CLICK_SLACK then return end
		if GetTime() - lastSit < SIT_AGAIN or not FireHovered() then return end
		lastSit = GetTime()
		Safe(DoEmote, "SIT")
	end)
end

function ns.InitGestures()
	local waiting = HookFrames()
	WatchFire()
	local frame = CreateFrame("Frame")
	if waiting then frame:RegisterEvent("ADDON_LOADED") end
	frame:RegisterEvent("ITEM_TEXT_BEGIN")
	frame:RegisterEvent("MAIL_SHOW")
	frame:RegisterEvent("PLAYER_LEVEL_UP")
	for event in pairs(GREET_EVENTS) do frame:RegisterEvent(event) end
	frame:SetScript("OnEvent", function(_, event)
		if GREET_EVENTS[event] then return Greet() end
		if event == "ADDON_LOADED" then
			-- Windows of the game loaded on demand (every one hooked: no more listening).
			if not HookFrames() then frame:UnregisterEvent("ADDON_LOADED") end
		elseif event == "PLAYER_LEVEL_UP" then
			if not ns.db.gestures.levelUp then return end
			C_Timer.After(CHEER_DELAY, function()
				if ns.db.gestures.levelUp and Free() and DoEmote then Safe(DoEmote, "CHEER") end
			end)
		elseif event == "ITEM_TEXT_BEGIN" then
			-- A letter opened at the mailbox: the mailbox itself was the gesture; a book, a plaque: one now.
			if ns.ReadingMail and ns.ReadingMail() then return end
			Read()
		else
			Read()
		end
	end)
end
