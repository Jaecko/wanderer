local _, ns = ...
local L = ns.L

-- Is it better for you? Over an item you could wear, the game's tooltip says
-- how it compares with what you wear in that place, for the branch you play
-- (the one with the most talent points): "Frost: +1.8 %" in green, "-5 %" in red,
-- what it changes for everything you wear (under half a percent: "as good").
-- Each branch weighs the characteristics as players of the classic era do
-- (main stat 1); a percentage of critical strike or hit weighs much more than
-- a point of a stat, ratings brought back to it at your level. An estimate,
-- never a simulation. For those who strike with a weapon, the weights are calculated from your own figures
-- (StatModel.lua) unless you turn it off.
--
-- A feral druid sees two lines, the bear's (to tank) and the cat's (to strike).
-- Scales of Pawn (its "( Pawn: v1: ... )" strings, as Raidbots or the guides
-- give them) can be imported: for a class that has some, they replace
-- Wanderer's own, one line each.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

-- The game's names of the characteristics, gathered: several say the same.
local STATS = {
	str = { "ITEM_MOD_STRENGTH_SHORT" },
	agi = { "ITEM_MOD_AGILITY_SHORT" },
	sta = { "ITEM_MOD_STAMINA_SHORT" },
	int = { "ITEM_MOD_INTELLECT_SHORT" },
	spi = { "ITEM_MOD_SPIRIT_SHORT" },
	ap = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT" },
	rap = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
	crit = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT" },
	hit = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_RANGED_RATING_SHORT" },
	scrit = { "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
	shit = { "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
	sp = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
	heal = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
	mp5 = { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT" },
	def = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
	dodge = { "ITEM_MOD_DODGE_RATING_SHORT" },
	parry = { "ITEM_MOD_PARRY_RATING_SHORT" },
	block = { "ITEM_MOD_BLOCK_RATING_SHORT" },
	haste = { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_MELEE_RATING_SHORT", "ITEM_MOD_HASTE_RANGED_RATING_SHORT",
		"ITEM_MOD_HASTE_SPELL_RATING_SHORT" },
	expertise = { "ITEM_MOD_EXPERTISE_RATING_SHORT" },
	blockv = { "ITEM_MOD_BLOCK_VALUE_SHORT" },
	armor = { "RESISTANCE0_NAME" },
	dps = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" },
}
-- Percentages: a game counting them in rating points instead (values past
-- this) has them brought back to percentages.
local PERCENTS = { crit = true, hit = true, scrit = true, shit = true, dodge = true, parry = true, block = true,
	haste = true }
local RATING_LIKELY = 5
local MIN_GAIN = 0.5 -- percent of the whole character: less is "as good"

-- Rating points for 1 % (expertise: for 1 point, defense: for 1 point of skill) at level 60, and the game's
-- combat rating each one reads. Below 60 a point is worth more, as the game scales it. To verify in game on
-- Forever (an item's "1 %" line, the character sheet). Defense converts only when the game shows it counts
-- in ratings (classic items give defense points).
local RATINGS = {
	hit = { at60 = 10, rating = "CR_HIT_MELEE", id = 6 },
	crit = { at60 = 14, rating = "CR_CRIT_MELEE", id = 9 },
	shit = { at60 = 8, rating = "CR_HIT_SPELL", id = 8 },
	scrit = { at60 = 14, rating = "CR_CRIT_SPELL", id = 11 },
	dodge = { at60 = 12, rating = "CR_DODGE", id = 3 },
	parry = { at60 = 15, rating = "CR_PARRY", id = 4 },
	block = { at60 = 5, rating = "CR_BLOCK", id = 5 },
	haste = { at60 = 10, rating = "CR_HASTE_MELEE", id = 18 },
	expertise = { at60 = 2.5, rating = "CR_EXPERTISE", id = 24 },
	def = { rating = "CR_DEFENSE_SKILL", id = 2 },
}

local function YourLevel() return Clean(Safe(UnitLevel, "player")) or 60 end

-- How much a rating point grows with the level (1 at 60).
local function LevelScale(level)
	if level <= 10 then return 2 / 52 end
	if level <= 60 then return (level - 8) / 52 end
	return 82 / (262 - 3 * math.min(level, 70))
end

-- Rating points for one unit of a characteristic at your level; nil when it is not counted in ratings. The
-- game's own figure when you wear some of it (your rating over the bonus it gives), else the scaled table.
local measured = {} -- stat -> { level, value }
local function RatingPerUnit(stat)
	local entry = RATINGS[stat]
	if not entry then return nil end
	local level = YourLevel()
	local known = measured[stat]
	if known and known.level == level then return known.value or nil end
	local value
	local id = _G[entry.rating] or entry.id
	local rating = Clean(Safe(GetCombatRating, id))
	local bonus = Clean(Safe(GetCombatRatingBonus, id))
	if type(rating) == "number" and type(bonus) == "number" and rating > 0 and bonus > 0 then
		value = rating / bonus
		if stat == "def" and math.abs(value - 1) < 0.05 then value = nil end
	end
	-- (the game's figure hidden in a fight: the table's for now, the game's read again after it)
	if not value and InCombatLockdown() then return entry.at60 and entry.at60 * LevelScale(level) or nil end
	value = value or (entry.at60 and entry.at60 * LevelScale(level))
	measured[stat] = { level = level, value = value or false }
	return value
end
ns.RatingPerUnit = RatingPerUnit

-- A characteristic's value as weighed: a rating brought back to its percent (or its point).
local function Worth(stat, value)
	if PERCENTS[stat] and value <= RATING_LIKELY then return value end
	local per = RatingPerUnit(stat)
	return per and per > 0 and value / per or value
end

-- The weights, per class and branch (in the talent window's order).
local MELEE = { str = 1, agi = 0.75, ap = 0.5, crit = 14, hit = 16, haste = 10, expertise = 3.5, sta = 0.3, dps = 3,
	armor = 0.01 }
local TANK = { sta = 1, def = 1.2, dodge = 12, parry = 10, block = 6, blockv = 0.4, armor = 0.08, str = 0.5, agi = 0.6, hit = 6,
	expertise = 1.5 }
local HEALER = { heal = 1, sp = 0.9, int = 0.8, spi = 0.4, mp5 = 2, scrit = 8, haste = 5, sta = 0.2 }
local CASTER = { sp = 1, int = 0.4, shit = 13, scrit = 9, haste = 8, spi = 0.1, sta = 0.2, mp5 = 0.8 }
local WEIGHTS = {
	WARRIOR = { MELEE, MELEE, TANK },
	PALADIN = { HEALER, { sta = 1, def = 1, sp = 0.5, blockv = 0.5, block = 5, armor = 0.08, str = 0.4, int = 0.3 },
		{ str = 1, agi = 0.6, ap = 0.5, crit = 12, hit = 14, haste = 9, expertise = 3, int = 0.3, sta = 0.3, dps = 3 } },
	HUNTER = {}, -- (the same for the three, below)
	ROGUE = {},
	PRIEST = { HEALER, HEALER, { sp = 1, int = 0.4, spi = 0.3, shit = 12, scrit = 3, haste = 8, sta = 0.3 } },
	SHAMAN = { { sp = 1, int = 0.4, scrit = 10, shit = 12, haste = 8, mp5 = 1.2, sta = 0.2 },
		{ str = 1, agi = 0.7, ap = 0.5, crit = 13, hit = 15, haste = 10, expertise = 3.5, int = 0.2, sta = 0.3, dps = 3 },
		{ heal = 1, sp = 0.9, int = 0.8, mp5 = 2.5, scrit = 8, haste = 5, spi = 0.2, sta = 0.2 } },
	MAGE = { CASTER, CASTER, CASTER },
	WARLOCK = { CASTER, CASTER, CASTER },
	DRUID = { { sp = 1, int = 0.5, scrit = 9, shit = 12, haste = 8, spi = 0.2, mp5 = 1, sta = 0.2 },
		{ -- Feral: the bear and the cat, each its own line.
			{ key = "BEAR", weights = { sta = 1, armor = 0.1, agi = 0.6, def = 1, dodge = 12, str = 0.4, hit = 5, crit = 3,
				expertise = 1.5 } },
			{ key = "CAT", weights = { str = 1.2, agi = 1, ap = 0.5, crit = 14, hit = 14, haste = 10, expertise = 3.5,
				sta = 0.2 } },
		},
		{ heal = 1, sp = 0.9, int = 0.7, spi = 0.6, mp5 = 2, haste = 5, sta = 0.2 } },
}
local HUNTER = { agi = 1, rap = 0.5, ap = 0.2, crit = 18, hit = 18, haste = 12, int = 0.3, sta = 0.3, dps = 2 }
local ROGUE = { agi = 1, str = 0.5, ap = 0.5, crit = 14, hit = 16, haste = 10, expertise = 3.5, sta = 0.3, dps = 3 }
WEIGHTS.HUNTER = { HUNTER, HUNTER, HUNTER }
WEIGHTS.ROGUE = { ROGUE, ROGUE, ROGUE }
-- Before any talent: the branch most played at first.
local FIRST_BRANCH = { WARRIOR = 1, PALADIN = 3, HUNTER = 2, ROGUE = 2, PRIEST = 2, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2 }

local SLOTS = U.EQUIP_SLOTS -- the places an item goes, by its kind

-- What each class can wear: its heaviest armor (1 cloth ... 4 plate, from
-- level 40 for mail and plate), its weapons (the game's kinds), its shield.
local ARMOR = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local ARMOR_CLASS, WEAPON_CLASS, SHIELD_KIND = 4, 2, 6
for class, list in pairs(WEAPONS) do
	local set = {}
	for _, kind in ipairs(list) do set[kind] = true end
	WEAPONS[class] = set
end

local function ClassFile()
	local _, class = Safe(UnitClass, "player")
	return Clean(class)
end

-- The branch you play: the one with the most points (else the first one played). Read once, again
-- when your talents or level change (each item, each bag slot asks it).
local ownBranch
local function Branch(class)
	if ownBranch and ownBranch.class == class then return ownBranch.index end
	local trees = ns.Inspect.Own()
	local best, most = nil, 0
	for index, tree in ipairs(trees or {}) do
		if (tree.points or 0) > most then best, most = index, tree.points end
	end
	ownBranch = { class = class, index = best or FIRST_BRANCH[class] or 1 }
	return ownBranch.index
end
-- The calculated weights read again (StatModel.lua, loaded later) and their window drawn again.
local function ForgetModel()
	if ns.StatModel then ns.StatModel.Forget() end
	if ns.RefreshWeights then ns.RefreshWeights() end
end
function ns.ForgetBranch()
	ownBranch = nil
	ForgetModel()
	ns.ComparisonChanged()
end
do
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP",
		"PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", ns.ForgetBranch)
	-- Other gear worn: the whole character and the game's ratings are read again.
	local worn = CreateFrame("Frame")
	pcall(worn.RegisterEvent, worn, "PLAYER_EQUIPMENT_CHANGED")
	worn:SetScript("OnEvent", function()
		wipe(measured)
		ForgetModel()
		ns.ComparisonChanged()
	end)
end

-- A comparison changed (a weight, a scale, what you play, your talents): those who listen judge again.
local listeners = {}
function ns.OnComparisonChanged(fn) listeners[#listeners + 1] = fn end
local ForgetWorn
local function Changed()
	if ForgetWorn then ForgetWorn() end
	for _, fn in ipairs(listeners) do pcall(fn) end
end
ns.ComparisonChanged = U.Debounce(0.2, Changed)

-- Gear your class can wear. best: only its best kind of armor (what it is compared on: cloth is never "better"
-- for one who wears leather, whatever its stats); wornKind: the kind worn there (a hunter of level 40 still in
-- leather sees a better leather piece until the mail comes).
local function Wearable(class, itemClass, subclass, equip, best, wornKind)
	if itemClass == ARMOR_CLASS then
		if subclass == SHIELD_KIND then return SHIELD[class] or false end
		if subclass and subclass >= 1 and subclass <= 4 and equip ~= "INVTYPE_CLOAK" then
			local most = ARMOR[class] or 1
			local level = Clean(Safe(UnitLevel, "player")) or 60
			if level < 40 and most >= 3 then most = most - 1 end
			-- (from level 40, still in the kind below until the mail or plate comes: that kind too, only it)
			if best then return subclass == most or (level >= 40 and most >= 3 and wornKind == most - 1 and subclass == wornKind) end
			return subclass <= most
		end
		return true
	end
	if itemClass == WEAPON_CLASS then return WEAPONS[class] and WEAPONS[class][subclass] or false end
	return true
end

-- The kind of armor worn where an item goes (cloth 1 to plate 4), or nil.
local function WornKind(slots)
	local link = Clean(Safe(GetInventoryItemLink, "player", slots[1]))
	if not link then return nil end
	local _, _, _, _, _, itemClass, subclass = U.ItemInstant(link)
	subclass = Clean(subclass)
	if Clean(itemClass) == ARMOR_CLASS and subclass and subclass >= 1 and subclass <= 4 then return subclass end
	return nil
end

-- An item's worth for these weights.
local function Score(link, weights)
	local stats = U.ItemStats(link)
	local score = 0
	for stat, names in pairs(STATS) do
		local weight = weights[stat]
		if weight then
			for _, name in ipairs(names) do
				local value = Clean(stats[name])
				if value and value ~= 0 then
					score = score + Worth(stat, value) * weight
				end
			end
		end
	end
	return score
end

-- Your branch's name, in your language.
local BRANCH_KEYS = { WARRIOR = { "ARMS", "FURY", "PROTECTION" }, PALADIN = { "HOLY", "PROTECTION", "RETRIBUTION" },
	HUNTER = { "BEAST_MASTERY", "MARKSMANSHIP", "SURVIVAL" }, ROGUE = { "ASSASSINATION", "COMBAT", "SUBTLETY" },
	PRIEST = { "DISCIPLINE", "HOLY", "SHADOW" }, SHAMAN = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" },
	MAGE = { "ARCANE", "FIRE", "FROST" }, WARLOCK = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
	DRUID = { "BALANCE", "FERAL", "RESTORATION" } }

local function BranchName(branch)
	local list = BRANCH_KEYS[ClassFile() or ""]
	return list and L["BRANCH_" .. list[branch]] or "?"
end

-- What everything you wear is worth for these weights (shirt and tabard aside). Kept for the moment: a bag
-- refresh asks it for each item at once.
local WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
-- (until the gear, the level or a weight changes: forgotten with each comparison changed)
local wornWorth = setmetatable({}, { __mode = "k" }) -- weights -> { key, worth }
function ForgetWorn() wipe(wornWorth) end
local function WornWorth(weights)
	local links = { "", tostring(YourLevel()) }
	for _, slot in ipairs(WORN_SLOTS) do links[#links + 1] = Clean(Safe(GetInventoryItemLink, "player", slot)) or "" end
	local key = table.concat(links, "|")
	local known = wornWorth[weights]
	if known and known.key == key then return known.worth end
	local worth = 0
	for index = 3, #links do
		if links[index] ~= "" then worth = worth + Score(links[index], weights) end
	end
	wornWorth[weights] = { key = key, worth = worth }
	return worth
end

-- How the item compares for these weights: what it changes for the whole character, in percent of what you
-- wear now, "new" (a place you leave empty), "useful" (nothing you wear counts for them), or nil.
local function Compare(link, equip, slots, weights)
	local mine = Score(link, weights)
	if mine <= 0 then return end
	-- A two-hander worn: nothing goes in the other hand without leaving it. An off-hand item is never better
	-- then; a one-hander is weighed against the two-hander alone.
	local main = Clean(Safe(GetInventoryItemLink, "player", 16))
	if main and Clean(select(4, U.ItemInstant(main))) == "INVTYPE_2HWEAPON" and equip ~= "INVTYPE_2HWEAPON" then
		if equip == "INVTYPE_WEAPONOFFHAND" or equip == "INVTYPE_SHIELD" or equip == "INVTYPE_HOLDABLE" then return end
		if equip == "INVTYPE_WEAPON" then slots = { 16 } end
	end
	-- Against the worst of what you wear where it goes (two rings: the weaker).
	local worn
	for _, slot in ipairs(slots) do
		local wornLink = Clean(Safe(GetInventoryItemLink, "player", slot))
		if slot == 17 and equip == "INVTYPE_WEAPON" then
			local _, _, _, held = U.ItemInstant(wornLink or 0)
			held = Clean(held)
			-- (an empty other hand for one who can hold two: a new place; else only a weapon there counts)
			if wornLink and held ~= "INVTYPE_WEAPON" and held ~= "INVTYPE_WEAPONOFFHAND" then wornLink, slot = nil, nil end
			if not wornLink and not Clean(Safe(_G.CanDualWield)) then slot = nil end
		end
		if slot then
			if wornLink == link then return end
			local score = wornLink and Score(wornLink, weights) or 0
			if slot == 16 and equip == "INVTYPE_2HWEAPON" then
				local offhand = Clean(Safe(GetInventoryItemLink, "player", 17))
				score = score + (offhand and Score(offhand, weights) or 0)
			end
			if not wornLink then return "new" end
			if not worn or score < worn then worn = score end
		end
	end
	local whole = WornWorth(weights)
	if worn <= 0 and whole <= 0 then return "useful" end
	return math.floor((mine - worn) / math.max(whole, worn, 0.01) * 1000 + 0.5) / 10
end

-- A change as said: one decimal under 10, whole beyond, the game's decimal mark.
local function Percent(change)
	change = math.abs(change)
	local text = change >= 10 and ("%d"):format(math.floor(change + 0.5)) or ("%.1f"):format(change):gsub("%.0$", "")
	return (text:gsub("%.", _G.DECIMAL_SEPARATOR or "."))
end

-- Pawn's names of the characteristics, as Wanderer's.
local PAWN_STATS = {
	strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi", ap = "ap", rap = "rap",
	critrating = "crit", hitrating = "hit", spellcritrating = "scrit", spellhitrating = "shit", spellpower = "sp",
	spelldamage = "sp", healing = "heal", mp5 = "mp5", defenserating = "def", dodgerating = "dodge",
	parryrating = "parry", blockrating = "block", blockvalue = "blockv", armor = "armor", dps = "dps",
	meleedps = "dps", rangeddps = "dps", hasterating = "haste", spellhasterating = "haste",
	expertiserating = "expertise",
}
local PAWN_CLASSES = { warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
	shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID" }

-- "( Pawn: v1: "Bear": Class=Druid, Stamina=1, Agility=0.6, ... )" -> its name,
-- class and weights; nil and the reason when it cannot be read.
function ns.ParsePawnScale(text)
	if type(text) ~= "string" or not text:find("Pawn:", 1, true) then return nil, L.UPGRADE_IMPORT_BAD end
	local name = text:match('Pawn:%s*v%d+:%s*"([^"]+)"') or L.UPGRADE_IMPORTED_NAME
	local classText = text:match("Class=([%a ]+)")
	local class = classText and PAWN_CLASSES[classText:gsub("%s", ""):lower()] or ClassFile()
	local weights, count = {}, 0
	for key, value in text:gmatch("(%a+)=(%-?[%d%.]+)") do
		local stat = PAWN_STATS[key:lower()]
		value = tonumber(value)
		if stat and value then
			weights[stat] = (weights[stat] or 0) + value
			count = count + 1
		end
	end
	if count == 0 then return nil, L.UPGRADE_IMPORT_BAD end
	return { name = name, class = class, weights = weights }
end

-- Imported scales, this character's, by class.
local function Imported(class)
	local mine = ns.root and ns.Mine()
	local scales = mine and type(mine.scales) == "table" and mine.scales[class]
	return type(scales) == "table" and scales[1] and scales or nil
end

local choicesOf = {} -- class -> its choices, made once (again when a scale is imported or let go)

function ns.ImportPawnScale(text)
	local scale, problem = ns.ParsePawnScale(text)
	if not scale then return false, problem end
	local mine = ns.Mine()
	mine.scales = type(mine.scales) == "table" and mine.scales or {}
	local list = mine.scales[scale.class] or {}
	-- The same name again: replaced.
	for index = #list, 1, -1 do if list[index].name == scale.name then table.remove(list, index) end end
	list[#list + 1] = { name = scale.name, weights = scale.weights }
	mine.scales[scale.class] = list
	wipe(choicesOf)
	ns.ComparisonChanged()
	return true, scale
end

-- Wanderer's weights you changed, this character's: class -> scale id -> weights.
local function Overrides(class)
	local mine = ns.Mine()
	mine.weightOverrides = type(mine.weightOverrides) == "table" and mine.weightOverrides or {}
	local list = type(mine.weightOverrides[class]) == "table" and mine.weightOverrides[class] or {}
	mine.weightOverrides[class] = list
	return list
end

-- What you play: each way your class is played that has its own weights, { id, label }, in the talent
-- window's order (branches with the same weights together, the feral druid's bear and cat apart; an imported
-- Pawn scale each). Chosen by you, never guessed: the last choice kept for each character.
local function Choices(class)
	if choicesOf[class] then return choicesOf[class] end
	local list = {}
	choicesOf[class] = list
	local imported = Imported(class)
	if imported then
		for _, scale in ipairs(imported) do list[#list + 1] = { id = "pawn:" .. scale.name, label = scale.name } end
		return list
	end
	local together = {}
	for branch, entry in ipairs(WEIGHTS[class] or {}) do
		if entry[1] and entry[1].weights then
			for _, scale in ipairs(entry) do
				list[#list + 1] = { id = branch .. ":" .. scale.key,
					label = L.UPGRADE_SCALE_IN:format(BranchName(branch), L["UPGRADE_SCALE_" .. scale.key]) }
			end
		elseif together[entry] then
			together[entry].label = together[entry].label .. " / " .. BranchName(branch)
		else
			together[entry] = { id = tostring(branch), label = BranchName(branch) }
			list[#list + 1] = together[entry]
		end
	end
	return list
end
function ns.PlayChoices()
	local class = ClassFile()
	return class and Choices(class) or {}
end

-- The choice of this character (nil: not chosen yet, or no longer offered); id: chosen now.
function ns.PlayChoice(id)
	if not ns.root then return nil end
	ns.root.playChoice = type(ns.root.playChoice) == "table" and ns.root.playChoice or {}
	local key = ns.CharacterKey()
	if id then
		ns.root.playChoice[key] = id
		ns.ComparisonChanged()
		ns.RefreshWeights()
	end
	local chosen = ns.root.playChoice[key]
	for _, choice in ipairs(ns.PlayChoices()) do
		if choice.id == chosen then return chosen end
	end
	return nil
end

-- Wanderer's own scale: the weights calculated for you when they cover it (and you want them, StatModel.lua),
-- else the fixed ones; yours once you changed them. fixed: the class's own, calculated: what the model says.
local function OwnScale(class, id, label, fixed, overrides)
	local branch, key = id:match("^(%d+):?(%a*)$")
	branch, key = tonumber(branch), key ~= "" and key or nil
	local model = ns.StatModel
	local calculated = model and model.For(class, branch, key, id, fixed)
	local base = calculated and ns.UseCalculatedWeights() and calculated.weights or fixed
	return { id = id, label = label, weights = overrides[id] or base, defaults = base, fixed = fixed,
		calculated = calculated, covered = model and model.Covers(class, branch, key) or false }
end

-- The scales that speak for you: the imported ones, else your branch's (two for a feral druid).
-- Each scale: an id, its label, its weights (yours when changed), Wanderer's
-- own (nil for an imported one). What you play, once chosen: its scale alone.
local function Scales(class)
	local chosen = ns.root and ns.PlayChoice()
	if chosen then
		local overrides = Overrides(class)
		local label
		for _, choice in ipairs(Choices(class)) do if choice.id == chosen then label = choice.label end end
		local pawn = chosen:match("^pawn:(.+)$")
		if pawn then
			for _, scale in ipairs(Imported(class) or {}) do
				if scale.name == pawn then return { { id = chosen, label = label, weights = scale.weights, imported = scale } } end
			end
		end
		local branch, key = chosen:match("^(%d+):?(%a*)$")
		local entry = WEIGHTS[class] and WEIGHTS[class][tonumber(branch) or 0]
		if entry and key ~= "" then
			for _, scale in ipairs(entry) do
				if scale.key == key then
					return { OwnScale(class, chosen, label, scale.weights, overrides) }
				end
			end
		elseif entry then
			return { OwnScale(class, chosen, label, entry, overrides) }
		end
	end
	local imported = Imported(class)
	if imported then
		local list = {}
		for _, scale in ipairs(imported) do
			list[#list + 1] = { id = "pawn:" .. scale.name, label = scale.name, weights = scale.weights, imported = scale }
		end
		return list
	end
	local branch = Branch(class)
	local entry = WEIGHTS[class] and WEIGHTS[class][branch]
	if not entry then return {} end
	local name = BranchName(branch)
	local overrides = ns.root and Overrides(class) or {}
	local list = {}
	if entry[1] and entry[1].weights then
		for _, scale in ipairs(entry) do
			local id = branch .. ":" .. scale.key
			list[#list + 1] = OwnScale(class, id, L.UPGRADE_SCALE_IN:format(name, L["UPGRADE_SCALE_" .. scale.key]),
				scale.weights, overrides)
		end
	else
		local id = tostring(branch)
		list[1] = OwnScale(class, id, name, entry, overrides)
	end
	return list
end

-- For the weights window ---------------------------------------------------------------------

-- The characteristics, in the order shown, each with the game's own name.
ns.STAT_ORDER = { "str", "agi", "sta", "int", "spi", "ap", "rap", "crit", "hit", "sp", "heal", "scrit", "shit", "mp5",
	"haste", "expertise", "def", "dodge", "parry", "block", "blockv", "armor", "dps" }
ns.STAT_PERCENT = PERCENTS

function ns.StatLabel(stat)
	local names = STATS[stat]
	local label = names and Clean(_G[names[1]])
	-- (a client without rating names: its sheet's own word)
	if not label and stat == "haste" then label = Clean(_G.STAT_HASTE) end
	if not label and stat == "expertise" then label = Clean(_G.STAT_EXPERTISE) end
	if PERCENTS[stat] then label = (label or stat) .. " (%)" end
	return label or stat
end

function ns.UpgradeScales()
	local class = ClassFile()
	return class and ns.root and Scales(class) or {}, class
end

local function Find(id)
	for _, scale in ipairs((ns.UpgradeScales())) do
		if scale.id == id then return scale end
	end
end

-- A weight set by hand: on Wanderer's scale, it becomes yours (the others kept).
function ns.SetScaleWeight(id, stat, value)
	local scale = Find(id)
	if not scale then return end
	value = (value and value > 0) and math.floor(value * 100 + 0.5) / 100 or nil
	ns.ComparisonChanged()
	if scale.imported then
		scale.imported.weights[stat] = value
		return
	end
	local overrides = Overrides(ClassFile())
	local mine = overrides[id]
	if not mine then
		mine = {}
		for key, weight in pairs(scale.defaults) do mine[key] = weight end
		overrides[id] = mine
	end
	mine[stat] = value
end

-- Back to Wanderer's weights for this scale (an imported one is forgotten).
function ns.ResetScale(id)
	local scale = Find(id)
	if not scale then return end
	ns.ComparisonChanged()
	local class = ClassFile()
	if scale.imported then
		local mine = ns.Mine()
		local list = mine.scales[class]
		for index = #list, 1, -1 do if list[index] == scale.imported then table.remove(list, index) end end
		wipe(choicesOf)
		if not list[1] then mine.scales[class] = nil end
	else
		Overrides(class)[id] = nil
	end
end

function ns.IsScaleChanged(id)
	local scale = Find(id)
	return scale and not scale.imported and scale.weights ~= scale.defaults or false
end

-- A scale as Pawn writes it, to keep or to share.
local PAWN_NAMES = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", ap = "Ap",
	rap = "Rap", crit = "CritRating", hit = "HitRating", scrit = "SpellCritRating", shit = "SpellHitRating",
	sp = "SpellPower", heal = "Healing", mp5 = "Mp5", def = "DefenseRating", dodge = "DodgeRating",
	parry = "ParryRating", block = "BlockRating", blockv = "BlockValue", armor = "Armor", dps = "Dps",
	haste = "HasteRating", expertise = "ExpertiseRating" }
local PAWN_CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

function ns.ExportScale(id)
	local scale = Find(id)
	if not scale then return end
	local parts = {}
	for _, stat in ipairs(ns.STAT_ORDER) do
		local weight = scale.weights[stat]
		if weight and weight > 0 then parts[#parts + 1] = ("%s=%s"):format(PAWN_NAMES[stat], tostring(weight)) end
	end
	return ('( Pawn: v1: "%s": Class=%s, %s )'):format(scale.label, PAWN_CLASS_NAMES[ClassFile() or ""] or "",
		table.concat(parts, ", "))
end

-- The comparison asked for, and not Pawn's to make (Compat.lua "upgradeArrows"): with Pawn there, it alone
-- judges the items, no second opinion beside its own.
local function ComparisonOn()
	if not (ns.db and ns.db.enabled and ns.db.tooltips.upgrade) then return false end
	return not (ns.Yields and ns.Yields("upgradeArrows"))
end

-- The lines under an item, one per scale: { text, r, g, b }.
function ns.UpgradeLines(link)
	local lines = {}
	if not ComparisonOn() or not link then return lines end
	local class = ClassFile()
	if not class then return lines end
	local _, _, _, equip, _, itemClass, subclass = U.ItemInstant(link)
	equip, itemClass, subclass = Clean(equip), Clean(itemClass), Clean(subclass)
	local slots = equip and SLOTS[equip]
	if not slots or not Wearable(class, itemClass, subclass, equip, true, WornKind(slots)) then return lines end
	for _, scale in ipairs(Scales(class)) do
		local change = Compare(link, equip, slots, scale.weights)
		local name = scale.label
		if change == "new" then
			lines[#lines + 1] = { L.UPGRADE_NEW:format(name), 0.25, 1, 0.25 }
		elseif change == "useful" then
			lines[#lines + 1] = { L.UPGRADE_USEFUL:format(name), 0.25, 1, 0.25 }
		elseif change and math.abs(change) < MIN_GAIN then
			lines[#lines + 1] = { L.UPGRADE_SAME:format(name), 0.75, 0.75, 0.75 }
		elseif change and change > 0 then
			lines[#lines + 1] = { L.UPGRADE_BETTER:format(name, Percent(change)), 0.25, 1, 0.25 }
		elseif change then
			lines[#lines + 1] = { L.UPGRADE_WORSE:format(name, Percent(change)), 1, 0.35, 0.35 }
		end
	end
	return lines
end

-- How much better an item is for you, for the best of your branch's scales: a percentage of the whole
-- character (a place you leave empty counts 100, one where nothing you wear counts 50); nil when it is not
-- better, or by less than half a percent.
function ns.UpgradeGain(link)
	if not ComparisonOn() or not link then return nil end
	local class = ClassFile()
	if not class then return nil end
	local _, _, _, equip, _, itemClass, subclass = U.ItemInstant(link)
	equip, itemClass, subclass = Clean(equip), Clean(itemClass), Clean(subclass)
	local slots = equip and SLOTS[equip]
	if not slots or not Wearable(class, itemClass, subclass, equip, true, WornKind(slots)) then return nil end
	local best
	for _, scale in ipairs(Scales(class)) do
		local change = Compare(link, equip, slots, scale.weights)
		local gain = change == "new" and 100 or change == "useful" and 50 or type(change) == "number" and change or nil
		if gain and gain >= MIN_GAIN and (not best or gain > best) then best = gain end
	end
	-- (a whole number said without decimals)
	if best and best == math.floor(best) then best = math.floor(best) end
	return best
end

-- Better for one of your scales (or a place left empty): the bags' green arrow.
function ns.IsUpgrade(link) return ns.UpgradeGain(link) ~= nil end

-- Gear your class can wear (its armor, its weapons): true or false; nil when it is not gear.
function ns.CanWear(link)
	if not link then return nil end
	local class = ClassFile()
	local _, _, _, equip, _, itemClass, subclass = U.ItemInstant(link)
	equip, itemClass, subclass = Clean(equip), Clean(itemClass), Clean(subclass)
	if not (class and equip and SLOTS[equip]) then return nil end
	return Wearable(class, itemClass, subclass, equip) and true or false
end

-- (tests) The first line's text.
function ns.UpgradeLine(link)
	local line = ns.UpgradeLines(link)[1]
	return line and line[1]
end

-- /wanderer objet, an item hovered: what the game says of its characteristics.
function ns.DebugUpgrade()
	local _, link = Safe(GameTooltip.GetItem, GameTooltip)
	link = Clean(link)
	if not link then return ns.Print(L.DEBUG_HOVER_ITEM) end
	local class = ClassFile()
	local branch = Branch(class)
	ns.Print(L.DEBUG_ITEM_LINE:format(link, tostring(branch), tostring(ns.UpgradeLine(link))))
	for name, value in pairs(U.ItemStats(link)) do
		ns.Print(("  %s = %s"):format(tostring(name), tostring(Clean(value))))
	end
end

function ns.InitUpgrade()
	U.OnItemTooltip(function(tooltip)
		if not tooltip.GetItem then return false end
		local _, link = Safe(tooltip.GetItem, tooltip)
		local lines = ns.UpgradeLines(Clean(link))
		for _, line in ipairs(lines) do tooltip:AddLine(line[1], line[2], line[3], line[4]) end
		return lines[1] ~= nil
	end, true)
end
