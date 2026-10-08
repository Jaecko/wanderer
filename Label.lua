local _, ns = ...
local L = ns.L

-- Floating label shown while hovering a character (above its head when it has
-- a nameplate, otherwise next to the cursor) or a gatherable object.
-- Since Midnight, some unit information can be "secret" in combat or in
-- instances: those values may be displayed but never compared or combined,
-- so every read is guarded and simply skipped when it is protected.
--
-- Hovering runs a full analysis (tooltip lines, profession, quest, loot...),
-- repeated every SCAN_DELAY, and a light refresh of the changing parts
-- (health, target, status, threat) every REFRESH_DELAY.
--
-- Look: drawn by the shared engine (Skin.lua), like every Wanderer window.

-- The character described: the one hovered, or (option) your target when
-- nothing is hovered. TARGET: what that character looks at.
local UNIT = "mouseover"
local TARGET = "mouseovertarget"
local FADE_IN, FADE_OUT = 0.2, 0.45
local HEALTH_HEIGHT = 4
-- What the unit targets: a block under a thin line.
local TARGET_PORTRAIT = 30
local TARGET_GAP = 6
local TARGET_BAR_HEIGHT = 4
local TARGET_BAR_WIDTH = 90
local LINE_GAP = 2 -- as between the lines of the game's tooltips
local RANK_ICON_SIZE = 20
local PORTRAIT_SIZE = 40 -- the hovered character's portrait, left of the label
local PORTRAIT_GAP = 8
local FALLBACK_WIDTH, FALLBACK_HEIGHT = 160, 16
local FISH_ICON = "Interface\\Icons\\Trade_Fishing"
local REFRESH_DELAY = 0.2
local SCAN_DELAY = 1
local ALERT_SOUND_DELAY = 60 -- seconds before the same player can trigger the sound again
local HEAD_OFFSET = 4
local HOLD_GRACE = 0.4 -- seconds the label waits after a click before leaving
local MAX_QUEST_LINES = 3
local IsInnkeeper, HearthLine -- (below, with the tooltip reading)
local LOOT_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local INTERACT_ICON = "Interface\\Cursor\\Interact"
local TAME_ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local MAX_OBJECT_DETAILS = 2
-- Only characters present in the game fonts (Latin-1): no arrows or bullets.
local SEPARATOR = "  |cff808080·|r  "

local U = ns.Util
local Safe, Clean, IsSecret = U.Safe, U.Clean, U.IsSecret
local Measure, IsOverWorld, HasAtlas = U.Measure, U.IsOverWorld, U.HasAtlas

-- The game draws a text a little wider than it measures it (more so at some
-- interface scales): the label keeps a margin, so nothing ever overflows.
local TEXT_SLACK = 1.1 -- measured: up to 7 % in game
local function TextWidth(fontString, fallback)
	return math.ceil(Measure(fontString, "GetStringWidth", fallback) * TEXT_SLACK) + 6
end
local World = ns.World

local REACTION_COLORS = {
	hostile = { 1, 0.32, 0.28 },
	neutral = { 1, 0.85, 0.35 },
	friendly = { 0.45, 1, 0.5 },
	unknown = { 1, 1, 1 },
	tapped = { 0.6, 0.6, 0.6 },
}

-- Quest visuals, using the game's own markers (atlas when available).
local QUEST_STYLES = {
	turnin = { atlas = "QuestTurnin", texture = "Interface\\GossipFrame\\ActiveQuestIcon", text = "QUEST_TURNIN", color = "ffffd100" },
	giver = { atlas = "QuestNormal", texture = "Interface\\GossipFrame\\AvailableQuestIcon", text = "QUEST_GIVER", color = "ffffd100" },
	objective = { atlas = nil, texture = "Interface\\TargetingFrame\\PortraitQuestBadge", text = "QUEST_OBJECTIVE", color = "ffffee66" },
}

local FACTIONS = {
	Alliance = { icon = "Interface\\FriendsFrame\\PlusManz-Alliance", color = "ff4a8cff" },
	Horde = { icon = "Interface\\FriendsFrame\\PlusManz-Horde", color = "ffff4a4a" },
}

-- Rank: dragon icon before the name (as on the game's nameplates), a capital
-- tag and a colored border.
local CLASSIFICATIONS = {
	worldboss = { key = "CLASSIF_BOSS", highlight = "boss", color = "ffff4de6",
		atlas = nil, texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
	rareelite = { key = "CLASSIF_RAREELITE", highlight = "rare", color = "ffd9e6ff",
		atlas = "nameplates-icon-elite-silver", texture = "Interface\\Tooltips\\EliteNameplateIcon" },
	elite = { key = "CLASSIF_ELITE", highlight = "elite", color = "ffffb826",
		atlas = "nameplates-icon-elite-gold", texture = "Interface\\Tooltips\\EliteNameplateIcon" },
	rare = { key = "CLASSIF_RARE", highlight = "rare", color = "ffd9e6ff",
		atlas = "nameplates-icon-elite-silver", texture = "Interface\\Tooltips\\EliteNameplateIcon" },
}

local frame, skin, rankIcon
local nameText, alertText, titleText, questStatusText, identityText, actionText, questText, detailText, moreText, targetText, healthBar
local cast, targetCast -- what the character casts, and what its target casts
local shiftDown = false -- Shift held over a character: the closer look
local unitPortrait -- round, left of the name; .wanted while a character is hovered
local target = {} -- the target block: line, portrait, info, bar (targetText is its name)
local LINES -- display order under the name, set in InitLabel
local targetAlpha, sinceRefresh, sinceScan = 0, 0, 0
local objectMode = false -- hovering a gatherable object instead of a character
local fishLock = false -- the bobber was hovered: the label stays on it while the line is in the water
local current = nil -- result of the last full analysis
local lastAlert = {} -- player GUID -> time of the last alert sound

local function IconMarkup(atlas, texture, size)
	if HasAtlas(atlas) then return ("|A:%s:%d:%d|a"):format(atlas, size, size) end
	return ("|T%s:%d:%d:0:0|t"):format(texture, size, size)
end

-- Professions ----------------------------------------------------------------
-- Actions are detected from the tooltip lines the game writes for the hovered
-- creature or object ("Skinnable", "Requires Mining 150", "Herbalism"...).

local SKILL = { HERBALISM = 182, MINING = 186, SKINNING = 393, ENGINEERING = 202, FISHING = 356, ARCHAEOLOGY = 794 }
local ACTION_KEYS = {
	[SKILL.HERBALISM] = "ACTION_HERBALISM",
	[SKILL.MINING] = "ACTION_MINING",
	[SKILL.SKINNING] = "ACTION_SKINNING",
	[SKILL.ENGINEERING] = "ACTION_ENGINEERING",
	[SKILL.FISHING] = "ACTION_FISHING",
	[SKILL.ARCHAEOLOGY] = "ACTION_ARCHAEOLOGY",
}
-- Game strings shown on corpses that can be harvested.
local CORPSE_LINES = {
	UNIT_SKINNABLE_LEATHER = SKILL.SKINNING,
	UNIT_SKINNABLE_HERB = SKILL.HERBALISM,
	UNIT_SKINNABLE_ROCK = SKILL.MINING,
	UNIT_SKINNABLE_BOLTS = SKILL.ENGINEERING,
}

local professions = {} -- list of { name, icon, rank, skillLine }

local function RefreshProfessions()
	wipe(professions)
	-- Primary professions, archaeology, fishing and cooking (missing ones are nil).
	for _, index in pairs({ Safe(GetProfessions) }) do
		local name, icon, rank, _, _, _, skillLine = Safe(GetProfessionInfo, index)
		if Clean(name) then
			professions[#professions + 1] = { name = name, icon = icon, rank = Clean(rank) or 0, skillLine = Clean(skillLine) }
		end
	end
end

local function FindProfessionBySkill(skillLine)
	for _, prof in ipairs(professions) do
		if prof.skillLine == skillLine then return prof end
	end
end

-- Red tooltip lines mean the requirement is not met.
local function IsRed(r, g, b)
	return r and r > 0.9 and g < 0.3 and b < 0.3
end

-- lines: list of { text, r, g, b }. Returns the detected action or nil.
local function DetectProfessionAction(lines)
	for _, line in ipairs(lines) do
		local text = line.text
		for globalName, skillLine in pairs(CORPSE_LINES) do
			if text == _G[globalName] then
				local prof = FindProfessionBySkill(skillLine)
				return { prof = prof, skillLine = skillLine, possible = prof ~= nil and not IsRed(line.r, line.g, line.b),
					text = text, corpse = true }
			end
		end
		for _, prof in ipairs(professions) do
			if text:find(prof.name, 1, true) then
				local required = tonumber(text:match("%d+"))
				local possible = not IsRed(line.r, line.g, line.b) and (not required or prof.rank >= required)
				return { prof = prof, skillLine = prof.skillLine, possible = possible, required = required, text = text }
			end
		end
	end
end

local function FormatProfessionAction(action)
	if not action then return nil end
	local prof = action.prof
	if action.possible and prof then
		local verb = L[ACTION_KEYS[prof.skillLine] or ""] or prof.name
		local icon = prof.icon and ("|T%s:14:14:0:0|t "):format(prof.icon) or ""
		return ("%s|cffffd100%s|r  |cffaaaaaa(%s %d)|r"):format(icon, verb, prof.name, prof.rank)
	end
	-- Shown, but not highlighted: the player lacks the profession or the skill.
	if action.required and prof then
		return ("|cffff6060%s|r"):format(L.PROFESSION_TOO_LOW:format(prof.name, action.required, prof.rank))
	end
	return "|cffff6060" .. action.text .. "|r"
end

-- Tooltip reading ------------------------------------------------------------

local LineType = Enum and Enum.TooltipDataLineType

-- Tooltip lines of the hovered character (protected lines kept in place).
local function ReadUnitTooltipLines()
	local data = C_TooltipInfo and Safe(C_TooltipInfo.GetUnit, UNIT)
	return U.TooltipLines(data and data.lines, true)
end

local function ReadGameTooltipLines()
	local lines = {}
	for i = 1, GameTooltip:NumLines() do
		local fontString = _G["GameTooltipTextLeft" .. i]
		local text = fontString and Clean(fontString:GetText())
		if text then
			local r, g, b = fontString:GetTextColor()
			lines[#lines + 1] = { text = text, r = r, g = g, b = b }
		end
	end
	return lines
end

-- "Wolf slain: 3/8" style lines, identified by type when the game provides it.
local function DetectQuests(lines)
	local quests = {}
	for i, line in ipairs(lines) do
		if i > 1 and line.text then
			local isObjective = LineType and LineType.QuestObjective and line.type == LineType.QuestObjective
			local done, total = line.text:match("(%d+)%s*/%s*(%d+)")
			if isObjective or done then
				local complete = done and tonumber(done) >= tonumber(total)
				quests[#quests + 1] = { text = strtrim((line.text:gsub("^%s*%-%s*", ""))), complete = complete }
				if #quests >= MAX_QUEST_LINES then break end
			end
		end
	end
	return quests
end

-- NPC function such as "<Blacksmith>": the second line, when it is not the
-- level/type line or another known line.
local function DetectRole(lines)
	local line = lines[2]
	if not (line and line.text) then return end
	local text = line.text
	if text:find(LEVEL, 1, true) or text:match("%d+%s*/%s*%d+") then return end
	for globalName in pairs(CORPSE_LINES) do
		if text == _G[globalName] then return end
	end
	if World.IsFaction(text) then return end
	text = U.Grammar(text):gsub("^<", ""):gsub(">$", "")
	return "<" .. text .. ">"
end

-- The innkeeper: where your home is (here or elsewhere), and your hearthstone.
-- Known by the role the game gives them, in every language.
local HEARTHSTONE = 6948
local HEARTH_ICON = "Interface\\Icons\\INV_Misc_Rune_01"
local INNKEEPER_WORDS = { "innkeeper", "aubergiste", "gastwirt", "tabern", "posader", "locandier", "estalajadeir",
	"таверн", "여관", "旅店" }

IsInnkeeper = function(lines)
	local role = lines[2] and lines[2].text
	if not role then return false end
	role = role:lower()
	for _, word in ipairs(INNKEEPER_WORDS) do
		if role:find(word, 1, true) then return true end
	end
	return false
end

HearthLine = function()
	local home = Clean(Safe(GetBindLocation))
	local here = home and (home == Clean(Safe(GetSubZoneText)) or home == Clean(Safe(GetRealZoneText)))
	local text = here and L.HEARTH_HERE or (home and L.HEARTH_ELSEWHERE:format(home) or L.HEARTH_NONE)
	local cooldown = C_Container and C_Container.GetItemCooldown or GetItemCooldown
	local start, duration = Safe(cooldown, HEARTHSTONE)
	start, duration = Clean(start), Clean(duration)
	local left = start and duration and duration > 2 and (start + duration - GetTime()) or 0
	local stone = left > 0 and L.HEARTH_WAIT:format(Safe(SecondsToTime, left, true) or "") or L.HEARTH_READY
	return ("|T%s:14:14:0:0|t |cffffd100%s|r  |cffa8a8a8%s|r"):format(HEARTH_ICON, text, stone)
end

-- Total RP 3 ------------------------------------------------------------------

-- Returns the TRP3 profile of the hovered player, if they have one.
local function GetRPPlayer()
	local api = AddOn_TotalRP3 and AddOn_TotalRP3.Player
	if not (api and api.CreateFromUnit) then return end
	local player = Safe(api.CreateFromUnit, UNIT)
	if player and Clean(Safe(player.GetProfileID, player)) then return player end
end

-- The inspection of other players (talents, branches, item level): Inspect.lua.
local Inspect = ns.Inspect

-- Colors & text lines ----------------------------------------------------------

local function ClassColorCode(classFile)
	local color = classFile and RAID_CLASS_COLORS[classFile]
	return color and color.colorStr or "ffffffff"
end

local function GetUnitColor(unit, isPlayer)
	if isPlayer then
		local _, classFile = Safe(UnitClass, unit)
		local color = Clean(classFile) and RAID_CLASS_COLORS[classFile]
		if color then return color.r, color.g, color.b end
	end
	if Clean(Safe(UnitIsTapDenied, unit)) then return unpack(REACTION_COLORS.tapped) end
	local reaction = Clean(Safe(UnitReaction, unit, "player"))
	if not reaction then return unpack(REACTION_COLORS.unknown) end
	if reaction <= 3 then return unpack(REACTION_COLORS.hostile) end
	if reaction == 4 then return unpack(REACTION_COLORS.neutral) end
	return unpack(REACTION_COLORS.friendly)
end

ns.UnitColor = GetUnitColor
local ColorCode = U.ColorCode

-- Without real specializations (WoW Forever), the only "spec" is the class
-- name itself, often in the other gender: not worth repeating.
local function RepeatsClass(spec, className, classFile)
	if spec == className then return true end
	local male = classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
	local female = classFile and LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classFile]
	return spec == male or spec == female
end

-- Players: "Race Class (Spec)". Creatures: "Type · Elite/Rare/Boss".
local function BuildIdentityLine(a)
	local db = ns.db.label
	local isPlayer = a.isPlayer
	local parts = {}
	if isPlayer then
		if db.showRace then
			parts[#parts + 1] = Clean(Safe(UnitRace, UNIT))
		end
		local className, classFile = Safe(UnitClass, UNIT)
		className, classFile = Clean(className), Clean(classFile)
		if db.showClass then
			if className then
				parts[#parts + 1] = "|c" .. ClassColorCode(classFile) .. className .. "|r"
			end
		end
		local text = table.concat(parts, " ")
		if db.showSpec then
			local spec = Inspect.Spec(UNIT)
			if spec and not RepeatsClass(spec, className, classFile) then text = text ~= "" and (text .. " (" .. spec .. ")") or spec end
		end
		return text
	end
	if db.showCreatureType then
		parts[#parts + 1] = Clean(Safe(UnitCreatureType, UNIT))
	end
	if db.showClassification and a.rank then
		parts[#parts + 1] = ("|c%s%s|r"):format(a.rank.color, L[a.rank.key .. "_TAG"])
	end
	if a.tameable then
		parts[#parts + 1] = ("|T%s:14:14:0:0|t |cff9de04a%s|r"):format(TAME_ICON, L.TAMEABLE)
	end
	if a.rareKilled then
		local ago = Safe(SecondsToTime, a.rareKilled, true) or ""
		parts[#parts + 1] = "|cff999999" .. L.RARE_KILLED:format(ago) .. "|r"
	end
	return table.concat(parts, " · ")
end

-- Relation with the player: party/raid, guild, friend.
local function DetectRelation(isPlayer, guid)
	if not isPlayer or Clean(Safe(UnitIsUnit, UNIT, "player")) then return end
	if Clean(Safe(UnitInParty, UNIT)) or Clean(Safe(UnitInRaid, UNIT)) then return "party" end
	if Clean(Safe(UnitIsInMyGuild, UNIT)) then return "guild" end
	if guid and C_FriendList and Clean(Safe(C_FriendList.IsFriend, guid)) then return "friend" end
end

local function BuildStatus(isPlayer, rpPlayer, relation)
	local parts = {}
	if Clean(Safe(UnitIsGhost, UNIT)) then
		parts[#parts + 1] = "|cffaaaaaa" .. L.STATUS_GHOST .. "|r"
	elseif Clean(Safe(UnitIsDead, UNIT)) then
		parts[#parts + 1] = "|cffaaaaaa" .. L.STATUS_DEAD .. "|r"
	end
	if isPlayer then
		if relation then
			local color = ns.Skin.HIGHLIGHTS[relation].color
			parts[#parts + 1] = ColorCode(color[1], color[2], color[3]) .. L["RELATION_" .. relation:upper()] .. "|r"
		end
		if Clean(Safe(UnitIsAFK, UNIT)) then
			parts[#parts + 1] = "|cffffd100" .. L.STATUS_AFK .. "|r"
		elseif Clean(Safe(UnitIsDND, UNIT)) then
			parts[#parts + 1] = "|cffff8040" .. L.STATUS_DND .. "|r"
		end
		if Clean(Safe(UnitIsPVP, UNIT)) then
			parts[#parts + 1] = "|cffff4a4a" .. L.STATUS_PVP .. "|r"
		end
		if rpPlayer and ns.db.rp.showStatus then
			local inCharacter = Clean(Safe(rpPlayer.IsInCharacter, rpPlayer))
			parts[#parts + 1] = inCharacter and ("|cff66ff66" .. L.STATUS_IC .. "|r") or ("|cffff6666" .. L.STATUS_OOC .. "|r")
		end
	end
	return parts
end

-- "Level 60 · <Guild> · [icon] Alliance · Stormwind: Honored · Status"
local function BuildDetailLine(a)
	local db = ns.db.label
	local isPlayer = a.isPlayer
	local parts = {}
	if db.showLevel then
		local level = Clean(Safe(UnitLevel, UNIT))
		if level then
			local text = LEVEL .. " " .. (level > 0 and level or "??")
			-- Colored by difficulty, as in the original game.
			if db.showDifficulty then text = ColorCode(World.LevelColor(level, false, UNIT)) .. text .. "|r" end
			parts[#parts + 1] = text
			if not isPlayer then World.NoteLevel(a.name, level) end
		end
	end
	if not isPlayer and db.showXP and Clean(Safe(UnitCanAttack, "player", UNIT)) then
		local kills = World.KillsToLevel(a.name, Clean(Safe(UnitLevel, UNIT)))
		if kills then parts[#parts + 1] = "|cff9fb4ff" .. L.XP_KILLS:format(kills) .. "|r" end
	end
	if isPlayer and db.showGuild then
		local guild = Clean(Safe(GetGuildInfo, UNIT))
		if guild then parts[#parts + 1] = "<" .. guild .. ">" end
	end
	if db.showFaction then
		local faction, localized = Safe(UnitFactionGroup, UNIT)
		local style = Clean(faction) and FACTIONS[faction]
		if style and (isPlayer or db.showNPCFaction) then
			parts[#parts + 1] = ("|T%s:14:14:0:0|t|c%s%s|r"):format(style.icon, style.color, Clean(localized) or faction)
		end
	end
	if a.reputation then parts[#parts + 1] = a.reputation end
	if db.showStatus then
		for _, status in ipairs(BuildStatus(isPlayer, a.rpPlayer, a.relation)) do parts[#parts + 1] = status end
	end
	return table.concat(parts, SEPARATOR)
end

-- The mouse on a unit frame (the frame itself or its portrait, never its
-- auras: their tooltips stay the game's).
local function Over(unitFrame)
	local focus = unitFrame and U.MouseFocus()
	for _ = 1, 4 do
		if not focus then return false end
		if focus == unitFrame then return true end
		local ok, parent = pcall(focus.GetParent, focus)
		focus = ok and parent or nil
	end
	return false
end

-- Your own portrait: the label shows you there, the closer look included.
local ColorLevelLine -- (below)

local function OverOwnPortrait()
	local db = ns.db
	return db and db.label.ownPortrait and Over(PlayerFrame) and Clean(Safe(UnitIsUnit, UNIT, "player")) and true or false
end

-- The closer look, while Shift is held over a player: role, talents, item
-- level, rank in the guild. Waits for the inspection, says why when it cannot come.
local function BuildMoreLines(a)
	if not (a.isPlayer and ns.db.label.shiftDetails and (shiftDown or OverOwnPortrait())) then return "" end
	local talents, itemLevel, yours = Inspect.Known(UNIT, true)
	local lines = {}
	local talentLine = Inspect.TalentLine(talents, UNIT)
	if talentLine then lines[#lines + 1] = talentLine end
	local second = {}
	if itemLevel then second[#second + 1] = Inspect.ItemLevelText(itemLevel) end
	local guild, rank = Safe(GetGuildInfo, UNIT)
	if Clean(guild) and Clean(rank) then second[#second + 1] = "|cffd0c090" .. L.DETAILS_RANK .. "|r  " .. rank end
	if #second > 0 then lines[#lines + 1] = table.concat(second, SEPARATOR) end
	-- Nothing known yet: why.
	if not (talentLine or itemLevel or yours) then
		local why = InCombatLockdown() and L.DETAILS_COMBAT or (not Inspect.InReach(UNIT) and L.DETAILS_FAR) or L.DETAILS_WAIT
		lines[#lines + 1] = "|cff808080" .. why .. "|r"
	end
	return table.concat(lines, "\n")
end

-- What is known of a player shown in the game's own tooltip (your group's
-- frames): you always, the others once inspected. Lines for the tooltip.
local function KnownDetails(unit)
	if not Clean(Safe(UnitIsPlayer, unit)) and not Clean(Safe(UnitIsUnit, unit, "player")) then return end
	local talents, itemLevel = Inspect.Known(unit, false)
	local lines = {}
	local talentLine = Inspect.TalentLine(talents, unit)
	if talentLine then lines[#lines + 1] = talentLine end
	if itemLevel then lines[#lines + 1] = Inspect.ItemLevelText(itemLevel) end
	return lines
end

local function TargetPrefix()
	return "|cff808080" .. L.TARGET_PREFIX .. "|r "
end

-- What the unit targets (you, or someone else): portrait, "Target: Name",
-- level and kind (class, or creature type), health. Protected names and
-- health are shown as they are, never looked into.
local function UpdateTargetLine()
	targetText:SetText("")
	target.info:SetText("")
	if not ns.db.label.showTarget or not Clean(Safe(UnitExists, TARGET)) then return false end
	local isPlayer = Clean(Safe(UnitIsPlayer, TARGET)) and true or false
	local shown = false
	if Clean(Safe(UnitIsUnit, TARGET, "player")) then
		targetText:SetText(TargetPrefix() .. "|cffff8080" .. L.TARGET_YOU .. "|r")
		shown = true
	else
		local name = Safe(UnitName, TARGET)
		if Clean(name) then
			local r, g, b = GetUnitColor(TARGET, isPlayer)
			targetText:SetText(TargetPrefix() .. ColorCode(r, g, b) .. name .. "|r")
			shown = true
		elseif IsSecret(name) then
			shown = pcall(targetText.SetFormattedText, targetText, "%s%s", TargetPrefix(), name)
		end
	end
	if not shown then return false end
	local parts = {}
	local level = Clean(Safe(UnitLevel, TARGET))
	if level then
		local text = LEVEL .. " " .. (level > 0 and level or "??")
		-- An enemy: colored by difficulty, as in the label above.
		if ns.db.label.showDifficulty and Clean(Safe(UnitCanAttack, "player", TARGET)) then
			text = ColorCode(World.LevelColor(level, false, TARGET)) .. text .. "|r"
		end
		parts[#parts + 1] = text
	end
	local kind = isPlayer and Clean((Safe(UnitClass, TARGET))) or Clean(Safe(UnitCreatureType, TARGET))
	if kind then parts[#parts + 1] = kind end
	target.info:SetText(table.concat(parts, " "))
	-- The portrait is drawn again only when the target changes.
	local guid = Safe(UnitGUID, TARGET)
	if IsSecret(guid) or guid ~= target.guid then
		target.guid = not IsSecret(guid) and guid or nil
		Safe(SetPortraitTexture, target.portrait, TARGET)
	end
	-- Health: status bars accept protected values.
	local health, maximum = Safe(UnitHealth, TARGET), Safe(UnitHealthMax, TARGET)
	local bar = (IsSecret(maximum) or (maximum and maximum > 0))
		and pcall(target.bar.SetMinMaxValues, target.bar, 0, maximum) and pcall(target.bar.SetValue, target.bar, health)
	target.bar.wanted = bar and true or false
	if bar then target.bar:SetStatusBarColor(GetUnitColor(TARGET, isPlayer)) end
	return true
end

-- Every character and every ally; enemy players show theirs above them.
local function UpdateHealth(isPlayer)
	if not ns.db.label.showHealth then return false end
	if isPlayer then
		local hostile = Safe(UnitCanAttack, "player", UNIT)
		if IsSecret(hostile) or hostile then return false end
	end
	local health, maximum = Safe(UnitHealth, UNIT), Safe(UnitHealthMax, UNIT)
	if not IsSecret(health) and health == nil then return false end
	if not IsSecret(maximum) and (maximum == nil or maximum <= 0) then return false end
	-- Status bars accept secret values, so health still shows in combat.
	if not (pcall(healthBar.SetMinMaxValues, healthBar, 0, maximum) and pcall(healthBar.SetValue, healthBar, health)) then
		return false
	end
	healthBar:SetStatusBarColor(GetUnitColor(UNIT, isPlayer))
	return true
end

-- A player who can attack you right now (both flagged for PvP, War Mode, duel...).
local function IsThreat(isPlayer)
	if not (isPlayer and ns.db.label.threatAlert) then return false end
	if Clean(Safe(UnitIsDeadOrGhost, UNIT)) or Clean(Safe(UnitIsUnit, UNIT, "player")) then return false end
	return Clean(Safe(UnitCanAttack, UNIT, "player")) and true or false
end

local function PlayAlertSound(guid)
	if not ns.db.label.threatSound or not guid then return end
	if lastAlert[guid] and GetTime() - lastAlert[guid] < ALERT_SOUND_DELAY then return end
	lastAlert[guid] = GetTime()
	if SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
end

-- Layout & look ----------------------------------------------------------------

-- Laid out like the game's tooltips: left aligned, same margins and room
-- for the badge (ns.Skin metrics), so every window looks the same.
local function Layout()
	local margin = ns.Skin.Margin()
	-- Measured at their own width; bounded again once the label is sized.
	nameText:SetWidth(0)
	for _, line in ipairs(LINES) do
		line:SetWidth(0)
		line:SetShown(line.forceShow or Clean(line:GetText()) ~= nil)
	end
	local nameWidth = TextWidth(nameText, FALLBACK_WIDTH)
	local iconSpace = rankIcon:IsShown() and (RANK_ICON_SIZE + 4) or 0
	local width = nameWidth + iconSpace
	local height = math.max(Measure(nameText, "GetStringHeight", FALLBACK_HEIGHT), iconSpace > 0 and RANK_ICON_SIZE or 0)
	for _, line in ipairs(LINES) do
		if line:IsShown() then
			width = math.max(width, TextWidth(line, FALLBACK_WIDTH))
			height = height + LINE_GAP + Measure(line, "GetStringHeight", 10)
		end
	end
	-- The target block, under a thin line.
	local block = targetText.forceShow and true or false
	local info = block and Clean(target.info:GetText()) ~= nil
	local bar = block and target.bar.wanted or false
	for _, part in ipairs({ target.line, target.portrait, targetText }) do part:SetShown(block) end
	target.portrait.ring:SetShown(block and target.portrait.ringShown or false)
	target.info:SetShown(info)
	target.bar:SetShown(bar)
	if block then
		local castWidth, castHeight = targetCast:Size(TextWidth)
		local textWidth = math.max(TextWidth(targetText, FALLBACK_WIDTH),
			info and TextWidth(target.info, FALLBACK_WIDTH) or 0, bar and TARGET_BAR_WIDTH or 0, castWidth)
		width = math.max(width, TARGET_PORTRAIT + TARGET_GAP + textWidth)
		local textHeight = Measure(targetText, "GetStringHeight", 10)
			+ (info and LINE_GAP + Measure(target.info, "GetStringHeight", 10) or 0)
			+ (bar and TARGET_GAP + TARGET_BAR_HEIGHT or 0)
			+ (castHeight > 0 and TARGET_GAP + castHeight or 0)
		height = height + TARGET_GAP * 2 + 1 + math.max(TARGET_PORTRAIT, textHeight)
	end
	-- Same margins as the tooltips, on every side; room at the top only for a badge.
	if healthBar:IsShown() then
		height = height + LINE_GAP * 2 + HEALTH_HEIGHT
	end
	local castWidth, castHeight = cast:Size(TextWidth)
	if castHeight > 0 then
		width = math.max(width, castWidth)
		height = height + LINE_GAP * 2 + castHeight
	end
	-- The portrait on the left; everything else in a column beside it.
	local portrait = unitPortrait.wanted and true or false
	unitPortrait:SetShown(portrait)
	unitPortrait.ring:SetShown(portrait and unitPortrait.ringShown or false)
	local portraitSpace = portrait and (PORTRAIT_SIZE + PORTRAIT_GAP) or 0
	width = width + portraitSpace
	height = math.max(height, portrait and PORTRAIT_SIZE or 0)
	local insetTop, insetBottom = skin:Insets()
	local top, bottom = margin + insetTop, margin + insetBottom
	width = math.max(width, skin:MinWidth())
	-- Never past the frame: a text drawn wider than measured is cut, not spilled.
	local column = width - portraitSpace
	nameText:SetWidth(math.max(1, column - iconSpace))
	for _, line in ipairs(LINES) do
		if line:IsShown() then line:SetWidth(math.max(1, column)) end
	end
	unitPortrait:ClearAllPoints()
	unitPortrait:SetPoint("TOPLEFT", frame, "TOPLEFT", margin, -top)
	nameText:ClearAllPoints()
	nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", margin + portraitSpace + iconSpace, -top)
	-- Lines stacked under the name, aligned on the left margin.
	local previous, offset = nameText, -iconSpace
	for _, line in ipairs(LINES) do
		if line:IsShown() then
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", offset, -LINE_GAP)
			previous, offset = line, 0
		end
	end
	-- The unit's own health, right under its lines; its target comes after.
	if healthBar:IsShown() then
		healthBar:ClearAllPoints()
		healthBar:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", offset, -LINE_GAP * 2)
		healthBar:SetPoint("RIGHT", frame, "RIGHT", -margin, 0)
		previous, offset = healthBar, 0
	end
	if castHeight > 0 then
		previous, offset = cast:Place(previous, offset, LINE_GAP * 2), 0
	end
	if block then
		target.line:ClearAllPoints()
		target.line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", offset, -TARGET_GAP)
		target.line:SetPoint("RIGHT", frame, "RIGHT", -margin, 0)
		target.portrait:ClearAllPoints()
		target.portrait:SetPoint("TOPLEFT", target.line, "BOTTOMLEFT", 0, -TARGET_GAP)
		targetText:ClearAllPoints()
		targetText:SetPoint("TOPLEFT", target.portrait, "TOPRIGHT", TARGET_GAP, 0)
		target.info:ClearAllPoints()
		target.info:SetPoint("TOPLEFT", targetText, "BOTTOMLEFT", 0, -LINE_GAP)
		target.bar:ClearAllPoints()
		target.bar:SetPoint("TOPLEFT", info and target.info or targetText, "BOTTOMLEFT", 0, -TARGET_GAP)
		target.bar:SetPoint("RIGHT", frame, "RIGHT", -margin, 0)
		if targetCast.active then
			targetCast:Place(bar and target.bar or (info and target.info or targetText), 0, TARGET_GAP)
		end
	end
	if not block then
		targetCast.active = false
		targetCast:Size(TextWidth)
	end
	frame:SetSize(width + margin * 2, height + top + bottom)
	skin:Layout()
end

local function PickHighlight(a)
	if a.threat then return "threat" end
	if a.questStatus == "turnin" or a.questStatus == "giver" then return a.questStatus end
	if a.action and a.action.possible or a.loot then return "action" end
	if a.questStatus == "objective" then return "objective" end
	if a.interactable then return "interact" end
	if a.relation then return a.relation end
	return a.rank and a.rank.highlight or nil
end

local function ClearLines()
	for _, line in ipairs(LINES) do
		line:SetText("")
		line.forceShow = nil
	end
	targetText:SetText("")
	targetText.forceShow = nil
	target.guid = nil
	cast.active, targetCast.active = false, false
	healthBar:Hide()
	unitPortrait.wanted = false
	rankIcon:Hide()
	skin:ClearTopBadge()
end

-- Analysis ---------------------------------------------------------------------

local function AnalyzeUnit()
	local db = ns.db.label
	local isPlayer = Clean(Safe(UnitIsPlayer, UNIT)) and true or false
	local guid = Clean(Safe(UnitGUID, UNIT))
	local a = { kind = "unit", isPlayer = isPlayer, guid = guid, lines = {} }
	a.rpPlayer = isPlayer and GetRPPlayer()
	if not isPlayer then
		a.lines = ReadUnitTooltipLines()
		local clean = {}
		for _, line in ipairs(a.lines) do if line.text then clean[#clean + 1] = line end end
		a.action = db.showProfessions and DetectProfessionAction(clean) or nil
		a.quests = db.showQuests and DetectQuests(clean) or nil
		a.role = db.showNPCRole and DetectRole(clean) or nil
		a.innkeeper = IsInnkeeper(clean)
		local classification = Clean(Safe(UnitClassification, UNIT))
		a.rank = classification and CLASSIFICATIONS[classification] or nil
		a.reputation = db.showReputation and World.Reputation(clean) or nil
		a.tameable = db.showTameable and World.IsTameable(clean) or nil
		World.NoteRare(UNIT)
		if db.showRareKills and a.rank and a.rank.highlight == "rare" then a.rareKilled = World.RareKilledAgo(guid) end
		if db.showLoot and guid and Clean(Safe(UnitIsDead, UNIT)) and CanLootUnit then
			a.loot = Clean(Safe(CanLootUnit, guid)) and true or nil
		end
		-- Only what can be done right now: a body is skinned (or gathered) once
		-- its loot is taken.
		if a.loot and a.action and a.action.corpse then a.action = nil end
		if db.showQuests and ns.GetQuestStatus then
			local pending = false
			for _, quest in ipairs(a.quests or {}) do if not quest.complete then pending = true end end
			a.questStatus = ns.GetQuestStatus(UNIT, guid, pending)
		end
	else
		a.relation = DetectRelation(isPlayer, guid)
	end
	return a
end

local function RenderActions(a)
	local parts = {}
	if a.innkeeper then parts[#parts + 1] = HearthLine() end
	local profession = FormatProfessionAction(a.action)
	if profession then parts[#parts + 1] = profession end
	if a.loot then parts[#parts + 1] = ("|T%s:14:14:0:0|t |cffffd100%s|r"):format(LOOT_ICON, L.ACTION_LOOT) end
	if a.interactable and not profession then
		parts[#parts + 1] = ("|T%s:16:16:0:0|t |cff8cd1ff%s|r"):format(INTERACT_ICON, L.ACTION_INTERACT)
	end
	actionText:SetText(table.concat(parts, "\n"))

	-- Quest status: badge on the top edge and a line in the quest color.
	local style = a.questStatus and QUEST_STYLES[a.questStatus]
	if style then
		skin:SetTopBadge(style.texture, style.atlas, false)
		questStatusText:SetText(("|c%s%s|r"):format(style.color, L[style.text]))
	end
	local quests = {}
	for _, quest in ipairs(a.quests or {}) do
		local color = quest.complete and "|cff808080" or "|cffffee66"
		quests[#quests + 1] = ("%s %s%s|r"):format(IconMarkup(nil, QUEST_STYLES.objective.texture, 12), color, quest.text)
	end
	questText:SetText(table.concat(quests, "\n"))
end

-- Light refresh: everything that changes while hovering.
local function RefreshDynamic()
	local a = current
	a.threat = IsThreat(a.isPlayer)
	-- At the top: a player who can attack you, or a monster not yours yet.
	local untagged = not a.isPlayer and ns.IsUntaggedOnYou and ns.IsUntaggedOnYou(UNIT)
	alertText:SetText(a.threat and ("|cffff3030" .. L.THREAT_LINE .. "|r")
		or untagged and ("|cffff9933" .. L.UNTAGGED_STATUS .. "|r") or "")
	detailText:SetText(BuildDetailLine(a))
	moreText:SetText(BuildMoreLines(a))
	targetText.forceShow = UpdateTargetLine()
	cast:Read(UNIT, ns.db.label.showCasts)
	if targetText.forceShow then targetCast:Read(TARGET, ns.db.label.showCasts) else targetCast.active = false end
	healthBar:SetShown(UpdateHealth(a.isPlayer))
	a.highlight = PickHighlight(a)
	if skin:GetHighlight() ~= a.highlight then skin:SetHighlight(a.highlight) end
	if a.threat then PlayAlertSound(a.guid) end
	Layout()
end

local function UpdateContent(full)
	local name = U.FullName(UNIT)
	if not IsSecret(name) and name == nil then return false end
	if full or not current or current.kind ~= "unit" then
		current = AnalyzeUnit()
		current.name = name
		ClearLines()
		-- Name: roleplay name from Total RP 3 when available, game name otherwise.
		local rp = current.rpPlayer
		local rpName = rp and ns.db.rp.useName and Clean(Safe(rp.GetCustomColoredRoleplayingNamePrefixedWithIcon, rp, 16))
		if rpName then
			nameText:SetText(rpName)
			nameText:SetTextColor(1, 1, 1)
		else
			-- SetText accepts secret values, so the name shows even when it is protected.
			if not pcall(nameText.SetText, nameText, name) then return false end
			nameText:SetTextColor(GetUnitColor(UNIT, current.isPlayer))
		end
		local title = rp and ns.db.rp.showTitle and Clean(Safe(rp.GetFullTitle, rp))
		if title then
			titleText:SetText("|cffffd100« " .. title .. " »|r")
		elseif current.role then
			titleText:SetText("|cffd0c090" .. current.role .. "|r")
		end
		identityText:SetText(BuildIdentityLine(current))
		if ns.db.label.showPortrait then
			Safe(SetPortraitTexture, unitPortrait, UNIT)
			unitPortrait.wanted = true
		end
		local rank = ns.db.label.showClassification and current.rank
		if rank then
			if HasAtlas(rank.atlas) then rankIcon:SetAtlas(rank.atlas) else rankIcon:SetTexture(rank.texture) end
			rankIcon:Show()
		end
		RenderActions(current)
	end
	RefreshDynamic()
	return true
end

-- Whether the game itself offers this object to the interact key right now:
-- it is its soft interact target (in reach, usable). A tooltip alone proves
-- nothing: signs, statues and other decorations have one too.
local function IsInteractTarget(name, guid)
	if not Clean(Safe(UnitExists, "softinteract")) then return false end
	local softGuid = Clean(Safe(UnitGUID, "softinteract"))
	if guid and softGuid then return guid == softGuid end
	local softName = Clean(Safe(UnitName, "softinteract"))
	return softName ~= nil and softName == name
end

-- World objects: doors, chests, quest objects, herbs, but also decorations.
-- "Interact" is said only when the game offers the object to the interact
-- key; the other lines become the details.
-- The bobber, while the line is in the water: what happens, the time left,
-- the catches of the session. Returns false when there is nothing to tell.
local function RenderFishing()
	local words = ns.FishingWords and ns.FishingWords()
	if not words then return false end
	local status = ns.FishingStatus()
	cast.text:SetText("|cffffd100" .. words .. "|r")
	cast.icon:SetTexture(FISH_ICON)
	cast.icon.wanted = true
	cast.bar:SetStatusBarColor(0.35, 0.7, 1)
	cast.bar:SetMinMaxValues(0, 1)
	cast.start, cast.finish, cast.channel, cast.timed = status.start, status.finish, true, true
	cast.active = true
	cast:Tick()
	local details = {}
	if status.catches > 0 then details[#details + 1] = L.FISH_COUNT:format(status.catches) end
	if status.noLure then details[#details + 1] = "|cff999999" .. L.FISH_NO_LURE .. "|r" end
	detailText:SetText(table.concat(details, SEPARATOR))
	return true
end

-- The line still in the water after the bobber was hovered.
local function FishingLocked()
	if not (fishLock and objectMode and ns.FishingWords) then return false end
	local _, active = ns.FishingWords()
	return active and true or false
end

local function UpdateObjectContent(data)
	local db = ns.db.label
	local lines = U.TooltipLines(data and data.lines)
	if not lines[1] then lines = ReadGameTooltipLines() end
	if not lines[1] then current = nil return false end
	local action = db.showProfessions and DetectProfessionAction(lines) or nil
	local quests = db.showQuests and DetectQuests(lines) or nil
	local guid = data and Clean(data.guid)
	current = { kind = "object", name = lines[1].text, lines = lines, action = action, quests = quests,
		interactable = db.showObjects and IsInteractTarget(Clean(lines[1].text), guid) or nil }
	if not action and not db.showObjects then return false end
	for _, quest in ipairs(quests or {}) do
		if not quest.complete then current.questStatus = "objective" end
	end
	ClearLines()
	nameText:SetText(lines[1].text)
	nameText:SetTextColor(1, 1, 1)
	RenderActions(current)
	local details = {}
	for i = 2, #lines do
		local text = lines[i].text
		local used = (action and text == action.text) or text:match("%d+%s*/%s*%d+")
		if not used and #details < MAX_OBJECT_DETAILS then details[#details + 1] = text end
	end
	detailText:SetText(table.concat(details, SEPARATOR))
	current.highlight = PickHighlight(current)
	if RenderFishing() then
		fishLock = true
		current.highlight = "action"
	end
	skin:SetHighlight(current.highlight)
	Layout()
	return true
end

-- The game tooltip's level line of an enemy, in the color of its difficulty.
ColorLevelLine = function(tooltip, unit)
	if not Clean(Safe(UnitCanAttack, "player", unit)) then return end
	local level = Clean(Safe(UnitLevel, unit))
	if not level then return end
	local name = tooltip.GetName and tooltip:GetName()
	for index = 2, math.min(tooltip:NumLines(), 5) do
		local line = name and _G[name .. "TextLeft" .. index]
		local text = line and Clean(line:GetText())
		if text and text:find(LEVEL, 1, true) then
			line:SetTextColor(World.LevelColor(level, false, unit))
			return
		end
	end
end

function ns.GetHighlightMode() return skin and skin:GetHighlight() end -- (tests)

-- Debug --------------------------------------------------------------------------

local function DebugText(value)
	if value == nil then return "-" end
	if IsSecret(value) then return L.DEBUG_SECRET end
	return tostring(value)
end

local function DebugReport(anchor)
	if not ns.debug or not current then return end
	local a = current
	-- Where the label is, where it is asked to be, and what the game says of the nameplate.
	local _, plate = U.NameplateFor(UNIT)
	local plates = C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}
	ns.Print(("|cffffd100%s|r %s  (%s: %s [%s, nameplate %s, %d], %s: %s)"):format(
		a.kind == "object" and L.DEBUG_OBJECT or L.DEBUG_UNIT, DebugText(a.name),
		L.DEBUG_ANCHOR, anchor or "-", ns.db.label.anchor, plate, type(plates) == "table" and #plates or 0,
		L.DEBUG_ZONE, DebugText(ns.zone)))
	local texts = {}
	for i, line in ipairs(a.lines or {}) do texts[#texts + 1] = i .. ") " .. (line.text or L.DEBUG_SECRET) end
	if #texts > 0 then ns.Print("  " .. L.DEBUG_LINES .. " " .. table.concat(texts, "  |  ")) end
	local action = a.action and ((a.action.prof and a.action.prof.name or a.action.text) .. (a.action.possible and " (ok)" or " (x)"))
	local quests = {}
	for _, q in ipairs(a.quests or {}) do quests[#quests + 1] = q.text end
	ns.Print(("  %s %s | %s %s (%s) | %s %s | %s %s | %s %s"):format(
		L.DEBUG_PROFESSION, DebugText(action), L.DEBUG_QUESTS, DebugText(a.questStatus),
		#quests > 0 and table.concat(quests, ", ") or "-", L.DEBUG_LOOT, a.loot and L.DEBUG_YES or "-",
		L.DEBUG_ROLE, DebugText(a.role), L.DEBUG_RELATION, DebugText(a.relation)))
	if a.isPlayer then
		local entry = Inspect.cache[a.guid or ""]
		local trees = {}
		for _, tree in ipairs(entry and entry.talents or {}) do trees[#trees + 1] = tree.name .. " " .. tree.points end
		ns.Print(("  %s %s (%s) | %s %s"):format(L.DETAILS_TALENTS, #trees > 0 and table.concat(trees, ", ") or "-",
			DebugText(Safe(GetNumTalentTabs, true)), L.DETAILS_ITEM_LEVEL, DebugText(entry and entry.itemLevel)))
	end
	ns.Print(("  %s %s | %s %s"):format(L.DEBUG_THREAT, a.threat and "!!" or "-",
		L.DEBUG_HIGHLIGHT, DebugText(a.highlight)))
	-- Other tooltip windows on screen (e.g. a bubble that should not be there).
	local others = {}
	for _, other in ipairs(ns.VisibleTooltips and ns.VisibleTooltips() or {}) do
		others[#others + 1] = (Clean(Safe(other.GetName, other)) or "?") .. (ns.IsTooltipHidden(other) and (" (" .. L.DEBUG_HIDDEN .. ")") or "")
	end
	ns.Print("  " .. L.DEBUG_OTHER_TOOLTIPS .. " " .. (#others > 0 and table.concat(others, ", ") or "-"))
end

function ns.DebugEnvironment()
	local function has(v) return v and "|cff66ff66ok|r" or ("|cffff6060" .. L.DEBUG_MISSING .. "|r") end
	ns.Print(("%s %s | %s %s | %s %s"):format(L.DEBUG_ZONE, DebugText(ns.zone), L.DEBUG_COMBAT, ns.inCombat and L.DEBUG_YES or L.DEBUG_NO,
		L.DEBUG_PROFILE, DebugText(ns.profileName)))
	local names = {}
	for _, prof in ipairs(professions) do names[#names + 1] = ("%s %d (%s)"):format(prof.name, prof.rank, DebugText(prof.skillLine)) end
	ns.Print(L.DEBUG_PROFESSIONS .. " " .. (#names > 0 and table.concat(names, ", ") or "-"))
	ns.Print(("API : C_TooltipInfo %s, C_NamePlate %s, NotifyInspect %s, CanLootUnit %s, issecretvalue %s, Total RP 3 %s"):format(
		has(C_TooltipInfo and C_TooltipInfo.GetUnit), has(C_NamePlate and C_NamePlate.GetNamePlateForUnit), has(NotifyInspect),
		has(CanLootUnit), has(issecretvalue),
		has(AddOn_TotalRP3 and AddOn_TotalRP3.Player)))
	-- Style asked versus what each window really draws.
	local function drawn(owner)
		local report = owner and ns.Skin.Get(owner) and ns.Skin.Get(owner):Report()
		if not report then return "-" end
		if not report.active then return L.DEBUG_DRAWN_OFF end
		if report.wanderer and report.game then return "|cffff6060" .. L.DEBUG_DRAWN_BOTH .. "|r" end
		return report.game and L.DEBUG_DRAWN_GAME or (report.wanderer and L.DEBUG_DRAWN_WANDERER or "?")
	end
	ns.Print(("%s %s | %s %s | %s %s"):format(L.DEBUG_STYLE, ns.db.label.style,
		L.DEBUG_LABEL, drawn(frame), L.DEBUG_TOOLTIP, drawn(GameTooltip)))
end

-- Display ------------------------------------------------------------------

-- Clicking or turning the camera makes the game forget what is hovered.
local function IsClicking()
	if IsMouselooking and IsMouselooking() then return true end
	return IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) or false
end

local lastClick -- time of the last click or camera turn

-- Name of the object under the world cursor. Returns nil when there is none,
-- true when the name is protected, and supported = false when the game does
-- not provide this information (then the game tooltip is used instead).
local function WorldCursorObject()
	if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) then return nil, false end
	local data = Safe(C_TooltipInfo.GetWorldCursor)
	local first = data and data.lines and data.lines[1]
	if not first then return nil, true end
	return Clean(first.leftText) or true, true
end

local function IsObjectStillHovered()
	if Clean(Safe(UnitExists, UNIT)) or not IsOverWorld() then return false end
	local name, supported = WorldCursorObject()
	if not supported then return GameTooltip:IsShown() end
	return name ~= nil
end

-- Returns show, held: held means the hovered thing is momentarily missing
-- (click, camera) and the label keeps its content and place.
-- The settings allow the label right now (enabled, not hidden in combat).
local function LabelAllowed()
	local db = ns.db
	if not (db and db.enabled and db.label.enabled) or ns.sceneActive then return false end
	return not (db.label.hideInCombat and ns.inCombat)
end

-- Your target stays described while nothing else is hovered (option).
-- In a fight the game loses and finds the hovered character again several
-- times a second (it moves under the mouse): such a blink is not leaving it.
local HOVER_GRACE = 0.25 -- seconds
local lastHover = 0 -- when something was hovered last

local function Hovering()
	if Clean(Safe(UnitExists, "mouseover")) then lastHover = GetTime() return true end
	return GetTime() - lastHover < HOVER_GRACE
end

local function StickyTarget()
	local db = ns.db
	return db and db.label.stickyTarget and not objectMode and not Hovering()
		and Clean(Safe(UnitExists, "target")) and true or false
end

local function SetUnit(unit)
	if unit == UNIT then return false end
	UNIT, TARGET = unit, unit .. "target"
	return true
end

function ns.LabelUnit() return UNIT end

local function ShouldShow()
	local db = ns.db
	if not LabelAllowed() then return false end
	local clicking = IsClicking()
	if clicking then lastClick = GetTime() end
	local present
	if objectMode then
		present = IsObjectStillHovered() or FishingLocked()
	else
		-- Your target: only while it is on screen (its nameplate shown).
		local onScreen = UNIT ~= "target" or (U.NameplateFor(UNIT)) ~= nil
		present = Clean(Safe(UnitExists, UNIT)) and onScreen
			and (UNIT == "target" or not db.label.worldOnly or IsOverWorld() or clicking or OverOwnPortrait())
	end
	if present then
		if UNIT == "mouseover" and not objectMode then lastHover = GetTime() end
		return true, false
	end
	-- Missing only because of a click: keep it during the click and just after.
	-- (Never for your target: it is either on screen or gone.)
	if current and UNIT ~= "target" and (clicking or (lastClick and GetTime() - lastClick < HOLD_GRACE)) then return true, true end
	-- The hovered character blinked out a moment (a fight): it stays.
	if current and current.kind == "unit" and UNIT == "mouseover" and GetTime() - lastHover < HOVER_GRACE then return true, true end
	return false
end

local function GetNameplate()
	if objectMode then return end
	return (U.NameplateFor(UNIT))
end

local anchoredPlate, anchoredLow -- nameplate the label is attached to, if any; low: on the head
local anchoredGUID -- the character that plate carried then
local plateSeen = 0 -- when the plate of the one described was there last
local PLATE_GRACE = 0.3 -- seconds a missing plate is waited for

-- Returns "head" or "cursor", the place actually used. An anchor to a
-- nameplate follows it by itself: it is only set again when the plate changes.
-- The game hands its nameplates over to other characters (the camera turns,
-- someone leaves the screen): a plate still carrying the one described?
local function StillTheirs(plate)
	local token = plate and plate:IsShown() and U.PlateUnit(plate)
	local guid = token and Clean(Safe(UnitGUID, token))
	return guid ~= nil and guid == anchoredGUID
end

-- Gone at once: never above someone else.
local function Vanish()
	targetAlpha = 0
	frame:SetAlpha(0)
	anchoredPlate, anchoredGUID = nil, nil
end

local function Position()
	if FishingLocked() and not IsObjectStillHovered() then
		-- The bobber's own plate when the game gives one (soft interact), else where it was.
		local plate = U.NameplateFor("softinteract")
		if plate and plate ~= anchoredPlate then
			frame:ClearAllPoints()
			frame:SetPoint("BOTTOM", plate, "TOP", 0, HEAD_OFFSET)
			anchoredPlate = plate
		end
		return "head"
	end
	local plate = ns.db.label.anchor == "head" and not OverOwnPortrait() and GetNameplate()
	if plate then plateSeen = GetTime() end
	if not plate and anchoredPlate then
		-- The game lost the plate an instant (a fight): the label stays where it is,
		-- never a jump to the cursor and back.
		if targetAlpha > 0 and anchoredPlate:IsShown() and GetTime() - plateSeen < PLATE_GRACE then return "head" end
		-- Fading away (the mouse left): above the head it came from, while it is theirs.
		if targetAlpha == 0 and StillTheirs(anchoredPlate) then return "head" end
		-- Your target gone from the screen, or the plate given to another: gone.
		if targetAlpha == 0 or UNIT == "target" then
			Vanish()
			return "head"
		end
	end
	-- Your target off the screen: never at the cursor.
	if not plate and UNIT == "target" then return "head" end
	if plate then
		-- An invisible plate takes no room: the label stands right on the head,
		-- unless the game writes the name there itself (then just over it).
		local low = ns.IsPlateQuiet and ns.IsPlateQuiet(plate) and not (ns.GameShowsName and ns.GameShowsName(UNIT)) or false
		if plate ~= anchoredPlate or low ~= anchoredLow then
			frame:ClearAllPoints()
			frame:SetPoint("BOTTOM", plate, low and "BOTTOM" or "TOP", 0, HEAD_OFFSET)
			anchoredPlate, anchoredLow = plate, low
			anchoredGUID = Clean(Safe(UnitGUID, UNIT))
		end
		return "head"
	end
	anchoredPlate = nil
	frame:ClearAllPoints()
	local x, y = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	frame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / scale, y / scale + ns.db.label.offset)
	return "cursor"
end

-- Tooltips the label replaces in the world are made transparent (the game
-- keeps managing them). Those opened by a click (chat links) or comparing
-- equipment are never touched.
local KEPT_TOOLTIPS = {
	ItemRefTooltip = true, ItemRefShoppingTooltip1 = true, ItemRefShoppingTooltip2 = true,
	ShoppingTooltip1 = true, ShoppingTooltip2 = true,
}
local hiddenTooltips = {}

-- Parts the game draws apart from its tooltip (its health bar may not follow
-- the tooltip's opacity): hidden and given back with it.
local TOOLTIP_PARTS = { GameTooltip = { "GameTooltipStatusBar" } }

local function SetTooltipHidden(tooltip, hide)
	local name = tooltip.GetName and Clean(Safe(tooltip.GetName, tooltip))
	local parts = name and TOOLTIP_PARTS[name] or {}
	if hide then
		if tooltip:GetAlpha() > 0 then tooltip:SetAlpha(0) end
		for _, part in ipairs(parts) do
			local piece = _G[part]
			if piece and piece:GetAlpha() > 0 then piece:SetAlpha(0) end
		end
		hiddenTooltips[tooltip] = true
	elseif hiddenTooltips[tooltip] then
		tooltip:SetAlpha(1)
		for _, part in ipairs(parts) do
			if _G[part] then _G[part]:SetAlpha(1) end
		end
		hiddenTooltips[tooltip] = nil
	end
end

function ns.IsTooltipHidden(tooltip)
	return hiddenTooltips[tooltip] == true
end

-- In the world, Wanderer's label takes the place of the game tooltip.
local function ReplacesGameTooltip()
	local db = ns.db
	return db and db.enabled and db.hideUnitTooltip and db.label.enabled and IsOverWorld()
end

-- Whether the label describes what is hovered in the world, decided from the
-- settings only (never from timing): characters always, objects when enabled.
local function LabelHandlesWorld()
	if not LabelAllowed() then return false end
	if Clean(Safe(UnitExists, UNIT)) then return true end
	return ns.db.label.showObjects and true or false
end

-- Either the label or the game's tooltips, never one then the other.
-- Over a unit frame, the game's tooltip of the character (never of an aura).
local function UnitFrameTooltip(tooltip)
	local db = ns.db
	if not (db and db.enabled and tooltip == GameTooltip) then return false end
	local _, unit = Safe(tooltip.GetUnit, tooltip)
	if not Clean(unit) then return false end
	if OverOwnPortrait() and db.label.enabled then return true end
	return db.hideTargetTooltip and Over(TargetFrame) or false
end

local function UpdateTooltipVisibility(tooltip)
	local name = tooltip.GetName and Clean(Safe(tooltip.GetName, tooltip))
	-- A fight with the label hidden (option): no tooltip over characters either.
	local db = ns.db
	-- (Whatever the game says is hovered at that instant: it loses it now and then in a fight.)
	local quietFight = db and db.label.hideInCombat and ns.inCombat
	local hide = not KEPT_TOOLTIPS[name or ""]
		and (ReplacesGameTooltip() and (LabelHandlesWorld() or quietFight) or UnitFrameTooltip(tooltip))
	SetTooltipHidden(tooltip, hide or false)
end

-- Any game tooltip (watched by Tooltips.lua): checked when it shows and on
-- every frame before drawing, so the game cannot bring it back.
function ns.WatchTooltip(tooltip)
	tooltip:HookScript("OnShow", UpdateTooltipVisibility)
	tooltip:HookScript("OnUpdate", UpdateTooltipVisibility)
	tooltip:HookScript("OnHide", function(self) SetTooltipHidden(self, false) end)
end

local function Show()
	targetAlpha = 1
	sinceRefresh, sinceScan = 0, 0
	frame:Show()
	local anchor = Position()
	-- The small name of a group member steps aside at once.
	if ns.RefreshPlates then ns.RefreshPlates() end
	DebugReport(anchor)
end

local ShowSticky

local function OnUpdate(self, elapsed)
	-- Nothing hovered any more: your target (option); hovered again: the mouse.
	if not objectMode then
		local wanted = StickyTarget() and "target" or "mouseover"
		if SetUnit(wanted) and Clean(Safe(UnitExists, UNIT)) then
			-- The same character under another name (hovered, then your target): nothing to redo.
			local same = current and current.guid and current.guid == Clean(Safe(UnitGUID, UNIT))
			if not same then UpdateContent(true) end
			targetAlpha = 1
		end
	end
	local show, held = ShouldShow()
	if targetAlpha > 0 and not show then targetAlpha = 0 end
	local alpha = ns.Skin.Fade(self, targetAlpha, elapsed, FADE_IN, FADE_OUT)
	if alpha == 0 and targetAlpha == 0 then
		if objectMode then SetTooltipHidden(GameTooltip, false) end
		objectMode, fishLock = false, false
		current = nil
		skin:SetHighlight(nil)
		self:Hide()
		-- Gone from an object or a character: back on your target if it stays.
		if ns.db.label.stickyTarget then C_Timer.After(0.1, ShowSticky) end
		return
	end
	skin:Animate(alpha)
	sinceRefresh = sinceRefresh + elapsed
	sinceScan = sinceScan + elapsed
	if held then
		-- Keep content and place while the click lasts; your target is followed
		-- still: the game hands its nameplates over to others as the camera turns.
		if UNIT == "target" then Position() end
		return
	end
	-- Shift pressed or released over a character: the closer look at once.
	local shift = not objectMode and ns.db.label.shiftDetails and IsShiftKeyDown() and true or false
	if shift ~= shiftDown then
		shiftDown = shift
		sinceRefresh = REFRESH_DELAY
	end
	cast:Tick()
	targetCast:Tick()
	if targetAlpha > 0 and sinceRefresh >= REFRESH_DELAY then
		sinceRefresh = 0
		if objectMode and not IsObjectStillHovered() and FishingLocked() then
			-- Away from the bobber: only the words change, the label stays where it is.
			RenderFishing()
			Layout()
		elseif objectMode then
			UpdateObjectContent()
		else
			local full = sinceScan >= SCAN_DELAY
			if full then sinceScan = 0 end
			UpdateContent(full)
		end
	end
	Position()
end

-- Called whenever the game tooltip shows something that is not a character.
-- data: the tooltip data when called while the game fills the tooltip.
local function OnWorldTooltip(data)
	if not LabelAllowed() or not (ns.db.label.showProfessions or ns.db.label.showObjects) then return end
	if Clean(Safe(UnitExists, UNIT)) or not IsOverWorld() then return end
	if not data and not GameTooltip:IsShown() then return end
	objectMode = true
	if UpdateObjectContent(data) then
		Show()
		return true
	end
	objectMode = false
	if ns.debug and current and current.name then DebugReport(nil) end
	return false
end

local function IsLabelActive()
	return frame:IsShown() and targetAlpha > 0
end
ns.IsLabelActive = IsLabelActive

-- The nameplate the label stands on right now, if any.
function ns.LabelPlate()
	return IsLabelActive() and anchoredPlate or nil
end

local function OnEvent(_, event, guid)
	if event == "INSPECT_READY" then
		if not Inspect.OnReady(guid, UNIT) then return end
		if targetAlpha > 0 and not objectMode then UpdateContent(true) end
		return
	end
	if event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" then
		RefreshProfessions()
		return
	end
	if event == "NAME_PLATE_UNIT_ADDED" then
		-- Your target back on screen: the label comes back on it.
		if StickyTarget() and Clean(Safe(UnitIsUnit, guid, "target")) and not IsLabelActive() then ShowSticky() end
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		if StickyTarget() then
			-- Another target: described at once (and the label moves to it).
			SetUnit("mouseover")
			ShowSticky()
		end
		return
	end
	-- UPDATE_MOUSEOVER_UNIT. Without a unit (for example during a click), the
	-- update loop decides whether the label stays.
	if not Clean(Safe(UnitExists, "mouseover")) then return end
	SetUnit("mouseover")
	objectMode = false
	if ShouldShow() and UpdateContent(true) then
		Show()
	else
		targetAlpha = 0
	end
end

-- Your target, described while nothing is hovered (option).
ShowSticky = function()
	if not (frame and StickyTarget()) then return end
	SetUnit("target")
	if ShouldShow() and UpdateContent(true) then Show() end
end

function ns.RefreshLabel()
	if not frame then return end
	frame:SetScale(ns.Skin.Scale())
	ns.Skin.ApplyFont()
	skin:SetHighlight(nil)
	if not ns.db.label.enabled then
		targetAlpha = 0
	elseif targetAlpha > 0 then
		if objectMode then UpdateObjectContent() else UpdateContent(true) end
	end
end

local function CreateLine(template, r, g, b)
	return ns.Skin.CreateText(frame, template, r, g, b)
end

function ns.InitLabel()
	-- Background, border, badges and highlights: the shared engine.
	frame, skin = ns.Skin.CreateWindow("WandererLabel", "TOOLTIP")
	frame:SetAlpha(0)
	frame:EnableMouse(false)

	-- Rank icon, left of the name.
	rankIcon = frame:CreateTexture(nil, "OVERLAY")
	rankIcon:SetSize(RANK_ICON_SIZE, RANK_ICON_SIZE)
	rankIcon:Hide()

	nameText = CreateLine("GameTooltipHeaderText", 1, 0.82, 0)
	rankIcon:SetPoint("RIGHT", nameText, "LEFT", -4, 0)
	alertText = CreateLine("GameTooltipText")
	titleText = CreateLine("GameTooltipText")
	questStatusText = CreateLine("GameTooltipText")
	identityText = CreateLine("GameTooltipText", 1, 1, 1)
	actionText = CreateLine("GameTooltipText", 1, 1, 1)
	questText = CreateLine("GameTooltipText", 1, 1, 1)
	detailText = CreateLine("GameTooltipTextSmall", 0.8, 0.8, 0.8)
	moreText = CreateLine("GameTooltipTextSmall", 0.8, 0.8, 0.8)
	-- The quest objectives come right after the level and the status; the
	-- closer look (Shift) right under the level.
	LINES = { alertText, titleText, questStatusText, identityText, actionText, detailText, moreText, questText }
	-- One line each: cut at the frame's edge rather than folded under it.
	for _, line in ipairs({ nameText, alertText, titleText, questStatusText, identityText, detailText }) do
		if line.SetWordWrap then line:SetWordWrap(false) end
	end

	unitPortrait = ns.Skin.RoundPortrait(frame, PORTRAIT_SIZE)
	unitPortrait:Hide()
	unitPortrait.ring:Hide()

	-- The target block (laid out on its own, after the lines).
	target.line = frame:CreateTexture(nil, "ARTWORK")
	target.line:SetHeight(1)
	target.line:SetColorTexture(1, 0.82, 0, 0.25)
	target.portrait = ns.Skin.RoundPortrait(frame, TARGET_PORTRAIT)
	targetText = CreateLine("GameTooltipTextSmall", 0.8, 0.8, 0.8)
	target.info = CreateLine("GameTooltipTextSmall", 0.65, 0.65, 0.65)
	target.bar = CreateFrame("StatusBar", nil, frame)
	target.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	target.bar:SetHeight(TARGET_BAR_HEIGHT)
	local targetBackground = target.bar:CreateTexture(nil, "BACKGROUND")
	targetBackground:SetAllPoints()
	targetBackground:SetColorTexture(0, 0, 0, 0.6)
	for _, part in ipairs({ target.line, target.portrait, target.portrait.ring, targetText, target.info, target.bar }) do part:Hide() end

	cast, targetCast = ns.Casts.New(frame), ns.Casts.New(frame)

	healthBar = CreateFrame("StatusBar", nil, frame)
	healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	healthBar:SetHeight(HEALTH_HEIGHT)
	local healthBackground = healthBar:CreateTexture(nil, "BACKGROUND")
	healthBackground:SetAllPoints()
	healthBackground:SetColorTexture(0, 0, 0, 0.6)
	healthBar:Hide()

	frame:SetScript("OnUpdate", OnUpdate)
	frame:SetScript("OnEvent", OnEvent)
	frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	frame:RegisterEvent("INSPECT_READY")
	frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("SKILL_LINES_CHANGED")
	ns.RefreshLabel()

	-- Gatherable objects (herbs, ore...) only exist as game tooltips: read the
	-- ones shown without data on the next frame. Visibility: ns.WatchTooltip.
	GameTooltip:HookScript("OnShow", function()
		C_Timer.After(0, function() if not IsLabelActive() then OnWorldTooltip() end end)
	end)
	if TooltipDataProcessor then
		TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
			if tooltip ~= GameTooltip then return end
			-- Characters: the label follows the mouseover itself. Objects: read now.
			if not (data and Enum.TooltipDataType and data.type == Enum.TooltipDataType.Unit) then
				OnWorldTooltip(data)
			elseif ns.db and ns.db.enabled and not IsOverWorld() then
				local _, unit = Safe(tooltip.GetUnit, tooltip)
				unit = Clean(unit)
				-- Over a frame: an enemy's level in its difficulty color.
				if unit and ns.db.label.showDifficulty then ColorLevelLine(tooltip, unit) end
				-- Over a portrait or a group frame: what Wanderer knows of the player.
				local lines = unit and ns.db.label.shiftDetails and KnownDetails(unit)
				for _, line in ipairs(lines or {}) do tooltip:AddLine(line, 1, 1, 1) end
			end
			-- Decided before the tooltip is drawn: no flash of the game tooltip.
			UpdateTooltipVisibility(GameTooltip)
		end)
	end
end
