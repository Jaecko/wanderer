local _, ns = ...

-- Gestures: the character acts out what the player does. Opening the map,
-- the spellbook, a book or the mailbox, they take out something to read (the
-- game's /read emote); reaching a new level, they cheer; meeting a character
-- to talk to, they greet it (once in a while). These are real
-- emotes: players nearby see them, as if typed. Off by default; never in a
-- fight, mounted, moving, swimming or flying; Shift held skips them.

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

local function Free()
	if not (ns.db and ns.db.enabled) then return false end
	if InCombatLockdown() or IsShiftKeyDown() then return false end
	if Clean(Safe(IsMounted)) or Clean(Safe(IsFlying)) or Clean(Safe(IsSwimming)) then return false end
	if Clean(Safe(UnitInVehicle, "player")) or Clean(Safe(UnitIsDeadOrGhost, "player")) then return false end
	local speed = Clean(Safe(GetUnitSpeed, "player"))
	return not (speed and speed > 0)
end

local function Read()
	if not (ns.db.gestures.read and Free()) then return end
	if GetTime() - lastRead < READ_COOLDOWN then return end
	lastRead = GetTime()
	if DoEmote then pcall(DoEmote, "READ") end
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
	if name and DoEmote then pcall(DoEmote, "WAVE", name) end
end

local hooked = {}

local function HookFrames()
	for _, entry in ipairs(READING_FRAMES) do
		local frame = _G[entry[1]]
		if frame and not hooked[frame] and frame.HookScript then
			hooked[frame] = true
			frame:HookScript("OnShow", Read)
		end
	end
end

function ns.InitGestures()
	HookFrames()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("ITEM_TEXT_BEGIN")
	frame:RegisterEvent("MAIL_SHOW")
	frame:RegisterEvent("PLAYER_LEVEL_UP")
	for event in pairs(GREET_EVENTS) do frame:RegisterEvent(event) end
	frame:SetScript("OnEvent", function(_, event)
		if GREET_EVENTS[event] then return Greet() end
		if event == "ADDON_LOADED" then
			-- Windows of the game loaded on demand.
			HookFrames()
		elseif event == "PLAYER_LEVEL_UP" then
			if not ns.db.gestures.levelUp then return end
			C_Timer.After(CHEER_DELAY, function()
				if ns.db.gestures.levelUp and Free() and DoEmote then pcall(DoEmote, "CHEER") end
			end)
		else
			Read()
		end
	end)
end
