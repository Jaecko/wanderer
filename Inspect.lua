local _, ns = ...
local L = ns.L

-- What can be known of a player beyond the label's first look: the branch
-- they play and its role, their talents, their item level. WoW Forever keeps
-- the three branches of old in one tree of today's talent system: read by
-- their columns, named from Wanderer's knowledge of every class. Other
-- players need an inspection: asked out of combat, within reach, throttled,
-- kept a few minutes per character. Used by the label (Label.lua).

local U = ns.Util
local Safe, Clean, IsSecret = U.Safe, U.Clean, U.IsSecret
local HasAtlas = U.HasAtlas
local SEPARATOR = "  |cff808080·|r  "

local INSPECT_DELAY = 1.5
local INSPECT_KEEP = 300 -- seconds an inspection is trusted before asking again
-- Equipment counted in the average item level (no shirt, no tabard).
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- Inspection of other players ------------------------------------------------
-- Specialization, talents and equipment are only known after an inspection:
-- requested out of combat, within reach, throttled, and kept per character
-- for a few minutes.

local inspected = {} -- GUID -> { time, spec, talents, itemLevel }
local pendingGUID, lastInspect = nil, 0

local function SpecName(specID)
	specID = Clean(specID)
	if not specID or specID <= 0 then return end
	local _, name = Safe(GetSpecializationInfoByID, specID)
	return Clean(name)
end

-- WoW Forever keeps the three branches of old in one tree of today's talent
-- system, side by side: each node belongs to the branch of its column. The
-- columns are found from where the nodes stand (the two widest gaps between
-- them), the names from the class's specializations (or the branches' own).
local BRANCHES = 3

-- What Wanderer knows of the classes: their three branches in the game's
-- order (left to right in the talent window) and the role each one plays.
-- The names: Wanderer's (L.BRANCH_*), the game's only for a class it does not know.
local CLASS_BRANCHES = {
	WARRIOR = { { "ARMS", "DAMAGER" }, { "FURY", "DAMAGER" }, { "PROTECTION", "TANK" } },
	PALADIN = { { "HOLY", "HEALER" }, { "PROTECTION", "TANK" }, { "RETRIBUTION", "DAMAGER" } },
	HUNTER = { { "BEAST_MASTERY", "DAMAGER" }, { "MARKSMANSHIP", "DAMAGER" }, { "SURVIVAL", "DAMAGER" } },
	ROGUE = { { "ASSASSINATION", "DAMAGER" }, { "COMBAT", "DAMAGER" }, { "SUBTLETY", "DAMAGER" } },
	PRIEST = { { "DISCIPLINE", "HEALER" }, { "HOLY", "HEALER" }, { "SHADOW", "DAMAGER" } },
	SHAMAN = { { "ELEMENTAL", "DAMAGER" }, { "ENHANCEMENT", "DAMAGER" }, { "RESTORATION", "HEALER" } },
	MAGE = { { "ARCANE", "DAMAGER" }, { "FIRE", "DAMAGER" }, { "FROST", "DAMAGER" } },
	WARLOCK = { { "AFFLICTION", "DAMAGER" }, { "DEMONOLOGY", "DAMAGER" }, { "DESTRUCTION", "DAMAGER" } },
	-- Feral: a bear tanks, a cat strikes; the points alone cannot tell.
	DRUID = { { "BALANCE", "DAMAGER" }, { "FERAL", "FERAL" }, { "RESTORATION", "HEALER" } },
	DEATHKNIGHT = { { "BLOOD", "TANK" }, { "FROST", "DAMAGER" }, { "UNHOLY", "DAMAGER" } },
}

local function ClassBranches(unit)
	local _, classFile = Safe(UnitClass, unit)
	return Clean(classFile) and CLASS_BRANCHES[classFile]
end

local function BranchNames(unit)
	local known = ClassBranches(unit) or {}
	local names = {}
	for index, branch in ipairs(known) do names[index] = L["BRANCH_" .. branch[1]] end
	local _, _, classID = Safe(UnitClass, unit)
	classID = Clean(classID)
	-- A class Wanderer knows: its own names (the game's may come out garbled).
	if not classID or known[1] then return names end
	local count = Clean(Safe(GetNumSpecializationsForClassID, classID)) or 0
	if count == BRANCHES then
		for index = 1, BRANCHES do
			local _, name = Safe(GetSpecializationInfoForClassID, classID, index)
			names[index] = names[index] or Clean(name)
		end
	end
	return names
end

local function ReadTraits(inspect, unit)
	if not (C_Traits and C_Traits.GetConfigInfo) then return end
	local configID
	if inspect then
		configID = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
	else
		configID = C_ClassTalents and Clean(Safe(C_ClassTalents.GetActiveConfigID))
	end
	local config = configID and Safe(C_Traits.GetConfigInfo, configID)
	local treeID = type(config) == "table" and config.treeIDs and config.treeIDs[1]
	if not treeID then return end
	local nodes, xs = {}, {}
	for _, nodeID in ipairs(Safe(C_Traits.GetTreeNodes, treeID) or {}) do
		local node = Safe(C_Traits.GetNodeInfo, configID, nodeID)
		local x = type(node) == "table" and Clean(node.posX)
		if x and node.isVisible ~= false then
			nodes[#nodes + 1] = { x = x, ranks = Clean(node.ranksPurchased) or Clean(node.currentRank) or 0 }
			xs[#xs + 1] = x
		end
	end
	if #nodes < BRANCHES then return end
	-- The two widest gaps between the columns split the three branches.
	table.sort(xs)
	local gaps = {}
	for index = 2, #xs do gaps[#gaps + 1] = { size = xs[index] - xs[index - 1], at = (xs[index] + xs[index - 1]) / 2 } end
	table.sort(gaps, function(a, b) return a.size > b.size end)
	if not (gaps[2] and gaps[2].size > 0) then return end
	local first, second = math.min(gaps[1].at, gaps[2].at), math.max(gaps[1].at, gaps[2].at)
	local points, total = { 0, 0, 0 }, 0
	for _, node in ipairs(nodes) do
		local branch = node.x < first and 1 or (node.x < second and 2 or 3)
		points[branch] = points[branch] + node.ranks
		total = total + node.ranks
	end
	if total == 0 then return end
	local names = BranchNames(unit)
	local trees = {}
	for index = 1, BRANCHES do trees[index] = { name = names[index] or tostring(index), points = points[index] } end
	return trees
end


local function ItemLevelOf(link)
	local level = C_Item and Clean(Safe(C_Item.GetDetailedItemLevelInfo, link))
	if level then return level end
	local _, _, _, base = Safe(GetItemInfo, link)
	return Clean(base)
end

-- Average item level of what the unit wears (a two-handed weapon counts
-- twice). Returns nil, true while some items are still unknown to the client.
local function ReadItemLevel(unit)
	local api = C_PaperDollInfo and Clean(Safe(C_PaperDollInfo.GetInspectItemLevel, unit))
	if type(api) == "number" and api > 0 then return math.floor(api + 0.5) end
	local sum, worn = 0, 0
	for _, slot in ipairs(GEAR_SLOTS) do
		local link = Clean(Safe(GetInventoryItemLink, unit, slot))
		if link then
			local level = ItemLevelOf(link)
			if not level then return nil, true end
			sum, worn = sum + level, worn + 1
			local equip = select(9, Safe(GetItemInfo, link))
			if slot == 16 and equip == "INVTYPE_2HWEAPON" and not Clean(Safe(GetInventoryItemLink, unit, 17)) then sum = sum + level end
		end
	end
	if worn > 0 then return math.floor(sum / 16 + 0.5) end
end

-- Whether a fresh inspection can be asked now (nothing is asked in a fight).
local function CanAsk(unit)
	if not NotifyInspect or InCombatLockdown() then return false end
	if InspectFrame and InspectFrame:IsShown() then return false end
	return Clean(Safe(CanInspect, unit)) and true or false
end

-- Close enough to be inspected (unknown counts as close).
local function InReach(unit)
	if not CheckInteractDistance then return true end
	local close = Safe(CheckInteractDistance, unit, 1)
	return IsSecret(close) or close ~= false
end

-- The inspection of the hovered player, asked for when missing or old.
local function Inspection(unit)
	local guid = Clean(Safe(UnitGUID, unit))
	if not guid then return end
	local entry = inspected[guid]
	if entry and GetTime() - entry.time < INSPECT_KEEP then return entry end
	if not CanAsk(unit) or GetTime() - lastInspect < INSPECT_DELAY then return entry end
	lastInspect = GetTime()
	pendingGUID = guid
	NotifyInspect(unit)
	return entry
end

-- Reads the inspection just received; items unknown yet are read again a
-- moment later, while the same player is hovered.
local function ReadInspection(guid, unit, tries)
	if Clean(Safe(UnitGUID, unit)) ~= guid then return end
	local entry = inspected[guid] or {}
	inspected[guid] = entry
	entry.time = GetTime()
	entry.spec = SpecName(Safe(GetInspectSpecialization, unit))
	entry.talents = ReadTraits(true, unit)
	local level, missing = ReadItemLevel(unit)
	entry.itemLevel = level or entry.itemLevel
	if missing and tries < 3 then
		C_Timer.After(0.5, function() ReadInspection(guid, unit, tries + 1) end)
	end
end

local function GetSpec(unit)
	if Clean(Safe(UnitIsUnit, unit, "player")) then
		local index = Clean(Safe(GetSpecialization))
		if index then
			local _, name = Safe(GetSpecializationInfo, index)
			return Clean(name)
		end
		return
	end
	local entry = Inspection(unit)
	return entry and entry.spec
end

-- The role a talent tree gives, by class and tree order (the game's trees):
-- the tree holding the most points decides. Feral druids may tank or strike.
local ROLE_ICONS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

-- The role as the game's small icons (both for a feral druid), its name
-- when the game has no icon.
local function RoleIcons(role)
	if role == "FERAL" then return RoleIcons("TANK") .. RoleIcons("DAMAGER") end
	local atlas = ROLE_ICONS[role]
	if atlas and HasAtlas(atlas) then return ("|A:%s:14:14|a"):format(atlas) end
	return "|cffc8c8c8" .. (_G[role] or role) .. "|r "
end

-- The role of the main talent tree (your group's roles show on its frames).
local function Role(talents, unit)
	if not talents then return end
	local best, most, tie = nil, -1, false
	for index, tree in ipairs(talents) do
		if tree.points > most then best, most, tie = index, tree.points, false
		elseif tree.points == most then tie = true end
	end
	if tie or not best then return end
	local branches = ClassBranches(unit)
	return branches and branches[best] and branches[best][2]
end

-- "[role] Fire 31 · Frost 5": the main branch first, the others with points
-- after it, a little greyed; none without points. Nothing without talents.
local function TalentLine(talents, unit)
	if not talents then return end
	local spent = {}
	for _, tree in ipairs(talents) do
		if tree.points > 0 then spent[#spent + 1] = tree end
	end
	if not spent[1] then return end
	table.sort(spent, function(a, b) return a.points > b.points end)
	local role = Role(talents, unit)
	local parts = {}
	for index, tree in ipairs(spent) do
		parts[#parts + 1] = (index == 1 and "|cffffffff%s %d|r" or "|cffa8a8a8%s %d|r"):format(tree.name, tree.points)
	end
	return "|cffd0c090" .. L.DETAILS_TALENTS .. "|r  " .. (role and (RoleIcons(role) .. " ") or "") .. table.concat(parts, SEPARATOR)
end

-- Talents and item level of a player: you, read live; the others from their
-- inspection (asked for when ask is true, else only what is already known).
local function Known(unit, ask)
	if Clean(Safe(UnitIsUnit, unit, "player")) then
		local _, equipped = Safe(GetAverageItemLevel)
		return ReadTraits(false, "player"), Clean(equipped) and math.floor(equipped + 0.5) or nil, true
	end
	local entry
	if ask then
		entry = Inspection(unit)
	else
		local guid = Clean(Safe(UnitGUID, unit))
		entry = guid and inspected[guid]
	end
	if entry then return entry.talents, entry.itemLevel end
end

local function ItemLevelText(itemLevel)
	return "|cffd0c090" .. L.DETAILS_ITEM_LEVEL .. "|r  |cffffffff" .. itemLevel .. "|r"
end

-- INSPECT_READY: the answer for this unit, if it was the one asked.
local function OnReady(guid, unit)
	if not pendingGUID or not Clean(guid) or guid ~= pendingGUID then return false end
	pendingGUID = nil
	if Clean(Safe(UnitGUID, unit)) ~= guid then return false end
	ReadInspection(guid, unit, 0)
	return true
end

ns.Inspect = {
	Spec = GetSpec, Known = Known, InReach = InReach,
	TalentLine = TalentLine, ItemLevelText = ItemLevelText, OnReady = OnReady, cache = inspected,
}

-- What the game answers about talents and what Wanderer reads from it, for
-- you and for the last player inspected (/wanderer talents).
function ns.DebugTalents()
	local function show(value)
		if IsSecret(value) then return "<secret>" end
		return value == nil and "-" or tostring(value)
	end
	-- The points bought in each configuration of today's talent system.
	local function traits(configID)
		if not (C_Traits and configID) then return "-" end
		local info = Safe(C_Traits.GetConfigInfo, configID)
		if type(info) ~= "table" then return "no config" end
		local trees, nodes, ranks = 0, 0, 0
		for _, treeID in ipairs(info.treeIDs or {}) do
			trees = trees + 1
			for _, nodeID in ipairs(Safe(C_Traits.GetTreeNodes, treeID) or {}) do
				local node = Safe(C_Traits.GetNodeInfo, configID, nodeID)
				local bought = type(node) == "table" and Clean(node.ranksPurchased)
				if bought and bought > 0 then nodes, ranks = nodes + 1, ranks + bought end
			end
		end
		return ("%d trees, %d nodes, %d ranks"):format(trees, nodes, ranks)
	end
	local function branches(list)
		local out = {}
		for _, tree in ipairs(list or {}) do out[#out + 1] = tree.name .. " " .. tree.points end
		return #out > 0 and table.concat(out, ", ") or "-"
	end
	local inspectID = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
	local ownID = C_ClassTalents and Safe(C_ClassTalents.GetActiveConfigID)
	ns.Print("Traits: inspect (" .. show(inspectID) .. ") " .. traits(inspectID) .. " | own (" .. show(ownID) .. ") " .. traits(ownID))
	ns.Print("Branches: inspect " .. branches(ReadTraits(true, "target")) .. " | own " .. branches(ReadTraits(false, "player")))
end

