local _, ns = ...

-- Knowledge about what is hovered in the world: difficulty colors of the
-- original game, reputation with an NPC's faction, beasts a hunter can tame,
-- and rares this character has already defeated.

local World = {}
ns.World = World

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

-- Difficulty ------------------------------------------------------------------------

-- A creature's level as the classic game colors it, when the game gives no
-- function for it: yellow from two levels under you to two over, orange and
-- red above, green under, grey once it gives nothing any more.
local function GreyLevel(player)
	if player <= 5 then return 0 end
	if player <= 39 then return player - math.floor(player / 10) - 5 end
	if player <= 59 then return player - math.floor(player / 5) - 1 end
	return player - 9
end

local function CreatureColor(level)
	local player = Clean(Safe(UnitLevel, "player")) or level
	local gap = level - player
	if gap >= 5 then return 1, 0.1, 0.1 end
	if gap >= 3 then return 1, 0.5, 0.25 end
	if gap >= -2 then return 1, 0.82, 0 end
	if level > GreyLevel(player) then return 0.25, 0.75, 0.25 end
	return 0.5, 0.5, 0.5
end

-- Color of a level compared to the player's: grey, green, yellow, orange, red.
-- forQuest: the quests' own scale (slightly different from creatures').
-- unit: the character itself, as the game's own frames color it (its
-- difficulty for you, not only its level); else the level alone.
function World.LevelColor(level, forQuest, unit)
	if unit and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer and GetDifficultyColor then
		local difficulty = Clean(Safe(C_PlayerInfo.GetContentDifficultyCreatureForPlayer, unit))
		local color = difficulty and Safe(GetDifficultyColor, difficulty)
		if type(color) == "table" and color.r then return color.r, color.g, color.b end
	end
	if not level or level <= 0 then return 1, 0.1, 0.1 end -- "??": far above you
	local color = Safe(forQuest and GetQuestDifficultyColor or GetCreatureDifficultyColor, level)
	if type(color) == "table" and color.r then return color.r, color.g, color.b end
	return CreatureColor(level)
end

-- Reputation --------------------------------------------------------------------------

local factions = {} -- faction name -> { reaction, value, min, max }

local function RefreshFactions()
	wipe(factions)
	local Reputation = C_Reputation
	if Reputation and Reputation.GetNumFactions and Reputation.GetFactionDataByIndex then
		for i = 1, (Clean(Safe(Reputation.GetNumFactions)) or 0) do
			local data = Safe(Reputation.GetFactionDataByIndex, i)
			if type(data) == "table" and Clean(data.name) and not data.isHeader then
				factions[data.name] = { reaction = data.reaction, value = data.currentStanding,
					min = data.currentReactionThreshold, max = data.nextReactionThreshold }
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, (Clean(Safe(GetNumFactions)) or 0) do
			local name, _, reaction, min, max, value, _, _, isHeader = Safe(GetFactionInfo, i)
			if Clean(name) and not isHeader then
				factions[name] = { reaction = reaction, value = value, min = min, max = max }
			end
		end
	end
end

function World.IsFaction(text)
	return factions[text] ~= nil
end

-- The game writes an NPC's faction in its tooltip: "Stormwind". Returns the
-- line of the reputation with it: "Stormwind: Honored (45 %)".
function World.Reputation(lines)
	for _, line in ipairs(lines) do
		local faction = line.text and factions[line.text]
		if faction then
			local standing = _G["FACTION_STANDING_LABEL" .. tostring(faction.reaction)] or "?"
			local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[faction.reaction]
			local code = color and U.ColorCode(color.r, color.g, color.b) or "|cffffffff"
			local text = ("%s : %s%s|r"):format(line.text, code, standing)
			if faction.max and faction.min and faction.value and faction.max > faction.min then
				text = text .. (" |cffaaaaaa(%d %%)|r"):format(math.floor((faction.value - faction.min) / (faction.max - faction.min) * 100))
			end
			return text
		end
	end
end

-- Tameable beasts (hunters) -------------------------------------------------------------

-- Lines the game uses for tameable beasts, when it provides them.
local TAMEABLE_GLOBALS = { "TAMEABLE", "TAMEABLE_EXOTIC", "UNIT_TAMEABLE" }

function World.IsTameable(lines)
	local _, class = Safe(UnitClass, "player")
	if class ~= "HUNTER" then return false end
	local texts = { ns.L.TAMEABLE_LINE }
	for _, name in ipairs(TAMEABLE_GLOBALS) do
		if type(_G[name]) == "string" then texts[#texts + 1] = _G[name] end
	end
	for _, line in ipairs(lines) do
		for _, text in ipairs(texts) do
			if line.text and line.text:find(text, 1, true) then return true end
		end
	end
	return false
end

-- Rares already defeated ----------------------------------------------------------------

local RARE = { rare = true, rareelite = true }

local function Kills()
	local key = ns.CharacterKey()
	ns.root.rareKills = ns.root.rareKills or {}
	ns.root.rareKills[key] = ns.root.rareKills[key] or {}
	return ns.root.rareKills[key]
end

-- A rare lying dead that this character (or its group) had engaged counts as
-- defeated. Checked on mouseover and on target; dated once per kill (looking
-- at the body again within RESPAWN_GUARD keeps the first date).
local RESPAWN_GUARD = 3600
function World.NoteRare(unit)
	if not RARE[Clean(Safe(UnitClassification, unit)) or ""] then return end
	if not Clean(Safe(UnitIsDead, unit)) or Clean(Safe(UnitIsTapDenied, unit)) then return end
	local npc = U.NpcID(Safe(UnitGUID, unit))
	if not npc then return end
	local kills = Kills()
	if kills[npc] and time() - kills[npc] < RESPAWN_GUARD then return end
	kills[npc] = time()
	if ns.JournalRare then ns.JournalRare(npc, Safe(UnitName, unit)) end
end

-- Seconds since this character defeated the rare, or nil.
function World.RareKilledAgo(guid)
	local npc = U.NpcID(guid)
	local when = npc and Kills()[npc]
	return when and (time() - when) or nil
end

-- Experience ---------------------------------------------------------------------------
-- Learned from the game's own messages ("Wolf dies, you gain 45 experience"),
-- for this session and this level: the real numbers, not a formula.

local xpByName, xpByLevel, levelByName = {}, {}, {}
local xpPatterns -- built from the game's messages, once
local SLOT = string.char(1) -- stands for a value while the pattern is built

-- Turns a message of the game ("%s dies, you gain %d experience.") into a
-- pattern that captures its values, in their order.
local function ToPattern(format)
	local kinds = {}
	local text = format:gsub("%%%d?%$?([sd])", function(kind)
		kinds[#kinds + 1] = kind
		return SLOT
	end)
	text = text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	local index = 0
	text = text:gsub(SLOT, function()
		index = index + 1
		return kinds[index] == "d" and "(%d+)" or "(.-)"
	end)
	return "^" .. text, kinds
end

local function XPPatterns()
	if not xpPatterns then
		xpPatterns = {}
		for _, name in ipairs({ "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_RESTED",
			"COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID" }) do
			local format = _G[name]
			if type(format) == "string" then
				local pattern, kinds = ToPattern(format)
				xpPatterns[#xpPatterns + 1] = { pattern = pattern, kinds = kinds }
			end
		end
	end
	return xpPatterns
end

-- Name of the monster and experience gained, from a message of the game.
function World.ParseKillXP(message)
	message = Clean(message)
	if type(message) ~= "string" then return end
	for _, entry in ipairs(XPPatterns()) do
		local captures = { message:match(entry.pattern) }
		if captures[1] then
			local name, xp
			for i, kind in ipairs(entry.kinds) do
				if kind == "s" and not name then name = captures[i] end
				if kind == "d" and not xp then xp = tonumber(captures[i]) end
			end
			if name and xp then return name, xp end
		end
	end
end

-- The label tells the level of what it describes (to estimate unknown kills
-- of the same level).
function World.NoteLevel(name, level)
	name, level = Clean(name), Clean(level)
	if name and level then levelByName[name] = level end
end

-- About how many kills like this one before the next level, or nil.
function World.KillsToLevel(name, level)
	name, level = Clean(name), Clean(level)
	local xp = (name and xpByName[name]) or (level and xpByLevel[level])
	local current, maximum = Clean(Safe(UnitXP, "player")), Clean(Safe(UnitXPMax, "player"))
	if not (xp and xp > 0 and current and maximum and maximum > 0) then return end
	if Clean(Safe(IsPlayerAtEffectiveMaxLevel)) then return end
	return math.ceil((maximum - current) / xp)
end

local killListeners = {}
-- fn(name, xp): called for every kill that gave experience.
function World.OnKill(fn) killListeners[#killListeners + 1] = fn end

local function OnXPMessage(message)
	local name, xp = World.ParseKillXP(message)
	if not name then return end
	xpByName[name] = xp
	local level = levelByName[name]
	if level then xpByLevel[level] = xp end
	for _, fn in ipairs(killListeners) do fn(name, xp) end
end

-- Events -------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_FACTION")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event, message)
	if event == "PLAYER_TARGET_CHANGED" then
		if ns.root then World.NoteRare("target") end
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		OnXPMessage(message)
	elseif event == "PLAYER_LEVEL_UP" then
		-- Each kill is worth differently at the new level.
		wipe(xpByName)
		wipe(xpByLevel)
	else
		RefreshFactions()
	end
end)
