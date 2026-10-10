local _, ns = ...
local L = ns.L

-- Is it better for you? Over an item you could wear, the game's tooltip says
-- how it compares with what you wear in that place, for the branch you play
-- (the one with the most talent points): "Frost: +12 %" in green, "-5 %" in red.
-- Each branch weighs the characteristics as players of the classic era do
-- (main stat 1); a percentage of critical strike or hit weighs much more than
-- a point of a stat. An estimate, never a simulation.
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
	blockv = { "ITEM_MOD_BLOCK_VALUE_SHORT" },
	armor = { "RESISTANCE0_NAME" },
	dps = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" },
}
-- Percentages: a game counting them in rating points instead (values past
-- this) has them brought back to percentages.
local PERCENTS = { crit = true, hit = true, scrit = true, shit = true, dodge = true, parry = true, block = true }
local RATING_PER_PERCENT = 14
local RATING_LIKELY = 5

-- The weights, per class and branch (in the talent window's order).
local MELEE = { str = 1, agi = 0.75, ap = 0.5, crit = 14, hit = 16, sta = 0.3, dps = 3, armor = 0.01 }
local TANK = { sta = 1, def = 1.2, dodge = 12, parry = 10, block = 6, blockv = 0.4, armor = 0.08, str = 0.5, agi = 0.6, hit = 6 }
local HEALER = { heal = 1, sp = 0.9, int = 0.8, spi = 0.4, mp5 = 2, scrit = 8, sta = 0.2 }
local CASTER = { sp = 1, int = 0.4, shit = 13, scrit = 9, spi = 0.1, sta = 0.2, mp5 = 0.8 }
local WEIGHTS = {
	WARRIOR = { MELEE, MELEE, TANK },
	PALADIN = { HEALER, { sta = 1, def = 1, sp = 0.5, blockv = 0.5, block = 5, armor = 0.08, str = 0.4, int = 0.3 },
		{ str = 1, agi = 0.6, ap = 0.5, crit = 12, hit = 14, int = 0.3, sta = 0.3, dps = 3 } },
	HUNTER = {}, -- (the same for the three, below)
	ROGUE = {},
	PRIEST = { HEALER, HEALER, { sp = 1, int = 0.4, spi = 0.3, shit = 12, scrit = 3, sta = 0.3 } },
	SHAMAN = { { sp = 1, int = 0.4, scrit = 10, shit = 12, mp5 = 1.2, sta = 0.2 },
		{ str = 1, agi = 0.7, ap = 0.5, crit = 13, hit = 15, int = 0.2, sta = 0.3, dps = 3 },
		{ heal = 1, sp = 0.9, int = 0.8, mp5 = 2.5, scrit = 8, spi = 0.2, sta = 0.2 } },
	MAGE = { CASTER, CASTER, CASTER },
	WARLOCK = { CASTER, CASTER, CASTER },
	DRUID = { { sp = 1, int = 0.5, scrit = 9, shit = 12, spi = 0.2, mp5 = 1, sta = 0.2 },
		{ -- Feral: the bear and the cat, each its own line.
			{ key = "BEAR", weights = { sta = 1, armor = 0.1, agi = 0.6, def = 1, dodge = 12, str = 0.4, hit = 5, crit = 3 } },
			{ key = "CAT", weights = { str = 1.2, agi = 1, ap = 0.5, crit = 14, hit = 14, sta = 0.2 } },
		},
		{ heal = 1, sp = 0.9, int = 0.7, spi = 0.6, mp5 = 2, sta = 0.2 } },
}
local HUNTER = { agi = 1, rap = 0.5, ap = 0.2, crit = 18, hit = 18, int = 0.3, sta = 0.3, dps = 2 }
local ROGUE = { agi = 1, str = 0.5, ap = 0.5, crit = 14, hit = 16, sta = 0.3, dps = 3 }
WEIGHTS.HUNTER = { HUNTER, HUNTER, HUNTER }
WEIGHTS.ROGUE = { ROGUE, ROGUE, ROGUE }
-- Before any talent: the branch most played at first.
local FIRST_BRANCH = { WARRIOR = 1, PALADIN = 3, HUNTER = 2, ROGUE = 2, PRIEST = 2, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2 }

-- The places an item goes, by its kind.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

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

-- The branch you play: the one with the most points (else the first one played).
local function Branch(class)
	local trees = ns.Inspect and ns.Inspect.Own and ns.Inspect.Own()
	local best, most = nil, 0
	for index, tree in ipairs(trees or {}) do
		if (tree.points or 0) > most then best, most = index, tree.points end
	end
	return best or FIRST_BRANCH[class] or 1
end

local function Wearable(class, itemClass, subclass, equip)
	if itemClass == ARMOR_CLASS then
		if subclass == SHIELD_KIND then return SHIELD[class] or false end
		if subclass and subclass >= 1 and subclass <= 4 and equip ~= "INVTYPE_CLOAK" then
			local most = ARMOR[class] or 1
			local level = Clean(Safe(UnitLevel, "player")) or 60
			if level < 40 and most >= 3 then most = most - 1 end
			return subclass <= most
		end
		return true
	end
	if itemClass == WEAPON_CLASS then return WEAPONS[class] and WEAPONS[class][subclass] or false end
	return true
end

-- An item's worth for these weights.
local function Score(link, weights)
	if not link then return 0 end
	local stats = Safe(C_Item and C_Item.GetItemStats or GetItemStats, link)
	if type(stats) ~= "table" then return 0 end
	local score = 0
	for stat, names in pairs(STATS) do
		local weight = weights[stat]
		if weight then
			for _, name in ipairs(names) do
				local value = Clean(stats[name])
				if value and value ~= 0 then
					if PERCENTS[stat] and value > RATING_LIKELY then value = value / RATING_PER_PERCENT end
					score = score + value * weight
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

-- How the item compares for these weights: a percentage, "new" (a place you
-- leave empty), "useful" (what you wear there brings nothing to them), or nil.
local function Compare(link, equip, slots, weights)
	local mine = Score(link, weights)
	if mine <= 0 then return end
	-- Against the worst of what you wear where it goes (two rings: the weaker).
	local worn
	for _, slot in ipairs(slots) do
		local wornLink = Clean(Safe(GetInventoryItemLink, "player", slot))
		if slot == 17 and equip == "INVTYPE_WEAPON" then
			local _, _, _, held = Safe(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, wornLink or 0)
			held = Clean(held)
			if held ~= "INVTYPE_WEAPON" and held ~= "INVTYPE_WEAPONOFFHAND" then wornLink, slot = nil, nil end
		end
		if slot then
			if wornLink == link then return end
			local score = wornLink and Score(wornLink, weights) or 0
			if slot == 16 and equip == "INVTYPE_2HWEAPON" then
				local offhand = Clean(Safe(GetInventoryItemLink, "player", 17))
				score = score + (offhand and Score(offhand, weights) or 0)
			end
			if not wornLink and not (slot == 17 and equip == "INVTYPE_WEAPON") then return "new" end
			if wornLink and (not worn or score < worn) then worn = score end
		end
	end
	if not worn then return "new" end
	if worn <= 0 then return "useful" end
	return math.floor((mine - worn) / worn * 100 + 0.5)
end

-- Pawn's names of the characteristics, as Wanderer's.
local PAWN_STATS = {
	strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi", ap = "ap", rap = "rap",
	critrating = "crit", hitrating = "hit", spellcritrating = "scrit", spellhitrating = "shit", spellpower = "sp",
	spelldamage = "sp", healing = "heal", mp5 = "mp5", defenserating = "def", dodgerating = "dodge",
	parryrating = "parry", blockrating = "block", blockvalue = "blockv", armor = "armor", dps = "dps",
	meleedps = "dps", rangeddps = "dps",
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

-- Imported scales, account wide, by class.
local function Imported(class)
	local scales = ns.root and type(ns.root.scales) == "table" and ns.root.scales[class]
	return type(scales) == "table" and scales[1] and scales or nil
end

function ns.ImportPawnScale(text)
	local scale, problem = ns.ParsePawnScale(text)
	if not scale then return false, problem end
	ns.root.scales = type(ns.root.scales) == "table" and ns.root.scales or {}
	local list = ns.root.scales[scale.class] or {}
	-- The same name again: replaced.
	for index = #list, 1, -1 do if list[index].name == scale.name then table.remove(list, index) end end
	list[#list + 1] = { name = scale.name, weights = scale.weights }
	ns.root.scales[scale.class] = list
	return true, scale
end


-- The scales that speak for you: the imported ones, else your branch's (two for a feral druid).
-- Wanderer's weights you changed, account wide: class -> scale id -> weights.
local function Overrides(class)
	ns.root.weightOverrides = type(ns.root.weightOverrides) == "table" and ns.root.weightOverrides or {}
	local list = type(ns.root.weightOverrides[class]) == "table" and ns.root.weightOverrides[class] or {}
	ns.root.weightOverrides[class] = list
	return list
end

-- Each scale: an id, its label, its weights (yours when changed), Wanderer's
-- own (nil for an imported one).
local function Scales(class)
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
			list[#list + 1] = { id = id, label = L.UPGRADE_SCALE_IN:format(name, L["UPGRADE_SCALE_" .. scale.key]),
				weights = overrides[id] or scale.weights, defaults = scale.weights }
		end
	else
		local id = tostring(branch)
		list[1] = { id = id, label = name, weights = overrides[id] or entry, defaults = entry }
	end
	return list
end

-- For the weights window ---------------------------------------------------------------------

-- The characteristics, in the order shown, each with the game's own name.
ns.STAT_ORDER = { "str", "agi", "sta", "int", "spi", "ap", "rap", "crit", "hit", "sp", "heal", "scrit", "shit", "mp5",
	"def", "dodge", "parry", "block", "blockv", "armor", "dps" }
ns.STAT_PERCENT = PERCENTS

function ns.StatLabel(stat)
	local names = STATS[stat]
	local label = names and Clean(_G[names[1]])
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
	local class = ClassFile()
	if scale.imported then
		local list = ns.root.scales[class]
		for index = #list, 1, -1 do if list[index] == scale.imported then table.remove(list, index) end end
		if not list[1] then ns.root.scales[class] = nil end
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
	parry = "ParryRating", block = "BlockRating", blockv = "BlockValue", armor = "Armor", dps = "Dps" }
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

-- The lines under an item, one per scale: { text, r, g, b }.
function ns.UpgradeLines(link)
	local lines = {}
	if not (ns.db and ns.db.enabled and ns.db.tooltips.upgrade) or not link then return lines end
	local class = ClassFile()
	if not class then return lines end
	local _, _, _, equip, _, itemClass, subclass = Safe(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, link)
	equip, itemClass, subclass = Clean(equip), Clean(itemClass), Clean(subclass)
	local slots = equip and SLOTS[equip]
	if not slots or not Wearable(class, itemClass, subclass, equip) then return lines end
	for _, scale in ipairs(Scales(class)) do
		local change = Compare(link, equip, slots, scale.weights)
		local name = scale.label
		if change == "new" then
			lines[#lines + 1] = { L.UPGRADE_NEW:format(name), 0.25, 1, 0.25 }
		elseif change == "useful" then
			lines[#lines + 1] = { L.UPGRADE_USEFUL:format(name), 0.25, 1, 0.25 }
		elseif change and math.abs(change) < 1 then
			lines[#lines + 1] = { L.UPGRADE_SAME:format(name), 0.75, 0.75, 0.75 }
		elseif change and change > 0 then
			lines[#lines + 1] = { L.UPGRADE_BETTER:format(name, change), 0.25, 1, 0.25 }
		elseif change then
			lines[#lines + 1] = { L.UPGRADE_WORSE:format(name, -change), 1, 0.35, 0.35 }
		end
	end
	return lines
end

-- Better for one of your scales (or a place left empty): the bags' green arrow.
function ns.IsUpgrade(link)
	if not (ns.db and ns.db.enabled and ns.db.tooltips.upgrade) or not link then return false end
	local class = ClassFile()
	if not class then return false end
	local _, _, _, equip, _, itemClass, subclass = Safe(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, link)
	equip, itemClass, subclass = Clean(equip), Clean(itemClass), Clean(subclass)
	local slots = equip and SLOTS[equip]
	if not slots or not Wearable(class, itemClass, subclass, equip) then return false end
	for _, scale in ipairs(Scales(class)) do
		local change = Compare(link, equip, slots, scale.weights)
		if change == "new" or change == "useful" or (type(change) == "number" and change >= 1) then return true end
	end
	return false
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
	if not link then return ns.Print("Item: hover an item first") end
	local class = ClassFile()
	local branch = Branch(class)
	ns.Print(("Item %s, branch %s, line: %s"):format(link, tostring(branch), tostring(ns.UpgradeLine(link))))
	for name, value in pairs(Safe(C_Item and C_Item.GetItemStats or GetItemStats, link) or {}) do
		ns.Print(("  %s = %s"):format(tostring(name), tostring(Clean(value))))
	end
end

function ns.InitUpgrade()
	if not (TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) then return end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
		-- The comparison tooltips beside show what you wear: nothing there.
		local name = tooltip.GetName and Clean(Safe(tooltip.GetName, tooltip)) or ""
		if name:find("^ShoppingTooltip") or name:find("^ItemRefShoppingTooltip") then return end
		if not tooltip.GetItem then return end
		local _, link = Safe(tooltip.GetItem, tooltip)
		local lines = ns.UpgradeLines(Clean(link))
		for _, line in ipairs(lines) do tooltip:AddLine(line[1], line[2], line[3], line[4]) end
		if lines[1] then tooltip:Show() end
	end)
end
