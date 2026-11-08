local _, ns = ...

-- Weights calculated for you: what each characteristic is worth to this
-- character, from its own figures (strength, agility, attack power, critical
-- strike and hit as the game shows them, the weapon worn, the talents that
-- change the sums). Never a simulation in time: an average damage per second
-- from the classic formulas (14 attack power for 1 damage per second, the hit
-- table with its misses, dodges and glancing blows, critical strikes twice the
-- damage), then for each characteristic a little more of it, the damage again,
-- the difference: its weight, the main characteristic at 1. Hit loses its worth
-- past the cap, critical strike gains with the talents that feed on it.
--
-- Phase 1: those who strike with a weapon (warrior, rogue, hunter, enhancement
-- shaman, the druid's cat, retribution paladin). Phase 2 (later): casters,
-- healers and tanks, who keep the fixed weights per class meanwhile.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local Model = {}
ns.StatModel = Model

-- The characteristics the model weighs; the others keep the fixed weights.
local MODELLED = { "str", "agi", "ap", "rap", "crit", "hit", "haste", "dps" }
local IS_MODELLED = {}
for _, stat in ipairs(MODELLED) do IS_MODELLED[stat] = true end
-- How much is added to measure each one (points, or a percent).
local STEPS = { str = 10, agi = 10, ap = 20, rap = 20, crit = 1, hit = 1, haste = 1, dps = 1 }
local CHANGE_SHOWN = 0.15 -- a weight that moved by this much (relative) is told
local CR_HIT_MELEE, CR_HIT_RANGED, CR_HASTE_MELEE, CR_HASTE_RANGED = 6, 7, 18, 19
local CAT_FORM = 1

-- Per class, at level 60 (classic): attack power for a point of strength or agility, agility for 1 %
-- of critical strike, the main characteristic.
local CLASSES = {
	WARRIOR = { strAp = 2, agiAp = 0, agiCrit = 20, main = "str" },
	PALADIN = { strAp = 2, agiAp = 0, agiCrit = 20, main = "str" },
	SHAMAN = { strAp = 2, agiAp = 0, agiCrit = 20, main = "str" },
	ROGUE = { strAp = 1, agiAp = 1, agiCrit = 29, main = "agi" },
	HUNTER = { strAp = 1, agiAp = 1, agiRap = 2, agiCrit = 53, main = "agi", ranged = true },
	DRUID = { strAp = 2, agiAp = 1, agiCrit = 20, main = "agi", cat = true },
}

-- The ways of playing covered: class -> branch -> true (or the feral druid's scale key).
local COVERED = {
	WARRIOR = { true, true }, PALADIN = { [3] = true }, HUNTER = { true, true, true }, ROGUE = { true, true, true },
	SHAMAN = { [2] = true }, DRUID = { [2] = "CAT" },
}

function Model.Covers(class, branch, key)
	local entry = COVERED[class or ""] and COVERED[class][branch or 0]
	if entry == true then return key == nil end
	return entry ~= nil and entry == key
end

-- Talents that change the sums (the ones adding critical strike or hit are already in the game's
-- figures): the spell of their first rank, else their name (English, French).
local TALENTS = {
	[16493] = "impale", [14128] = "lethality", [19485] = "mortalShots", [12319] = "flurry", [16256] = "flurry",
	[12834] = "deepWounds", [20049] = "vengeance", [19168] = "reflexes", [20262] = "divineStrength",
	[23584] = "dualWield", [13715] = "dualWield", [16942] = "claws", [16972] = "predatory",
}
local TALENT_NAMES = {
	["Impale"] = "impale", ["Empaler"] = "impale", ["Lethality"] = "lethality", ["Létalité"] = "lethality",
	["Mortal Shots"] = "mortalShots", ["Tirs mortels"] = "mortalShots", ["Flurry"] = "flurry", ["Rafale"] = "flurry",
	["Deep Wounds"] = "deepWounds", ["Blessures profondes"] = "deepWounds", ["Vengeance"] = "vengeance",
	["Lightning Reflexes"] = "reflexes", ["Réflexes éclair"] = "reflexes", ["Divine Strength"] = "divineStrength",
	["Force divine"] = "divineStrength", ["Dual Wield Specialization"] = "dualWield",
	["Spécialisation Ambidextrie"] = "dualWield", ["Sharpened Claws"] = "claws", ["Griffes aiguisées"] = "claws",
	["Predatory Strikes"] = "predatory", ["Frappes prédatrices"] = "predatory",
}

local function SpellName(spell)
	if not spell then return nil end
	if C_Spell and C_Spell.GetSpellName then
		local name = Clean(Safe(C_Spell.GetSpellName, spell))
		if name then return name end
	end
	return Clean((Safe(_G.GetSpellInfo, spell)))
end

-- Your talents as the model reads them: key -> ranks, the names counted ({ name, ranks, most }), the
-- points in each branch.
local function ReadTalents()
	local ranks, counted, points = {}, {}, { 0, 0, 0 }
	local tree = ns.TalentTree and ns.TalentTree()
	for _, node in ipairs(tree and tree.nodes or {}) do
		local bought = tonumber(node.ranks) or 0
		if node.branch and points[node.branch] then points[node.branch] = points[node.branch] + bought end
		if bought > 0 and node.spell then
			local name = SpellName(node.spell)
			local key = TALENTS[node.spell] or (name and TALENT_NAMES[name])
			if key then
				ranks[key] = (ranks[key] or 0) + bought
				counted[#counted + 1] = { name = name or key, ranks = bought, most = node.most or bought }
			end
		end
	end
	return ranks, counted, points
end

-- The enemy: a boss three levels above at 60 (hit cap 9 %), else one of your level.
local function Target(level)
	if level >= 60 then
		return { miss = 0.09, dualMiss = 0.28, dodge = 0.065, glance = 0.4, glanceDamage = 0.7 }
	end
	return { miss = 0.05, dualMiss = 0.24, dodge = 0.05, glance = 0.1, glanceDamage = 0.95 }
end

-- What each way of playing does besides its white hits, at level 60 (flat damage brought down below):
-- every (seconds) or ppm (procs a minute), weapon (times a weapon hit), flat, ap (times the attack power),
-- special (the talents raising critical damage of abilities count), windfury.
local ABILITIES = {
	arms = { { every = 6, weapon = 1, flat = 160, special = true }, { every = 10, weapon = 1, special = true } },
	fury = { { every = 6, ap = 0.45, special = true }, { every = 10, weapon = 1, special = true } },
	sinister = { { every = 4, weapon = 1, flat = 68, special = true }, { every = 10, flat = 900 } },
	backstab = { { every = 5, weapon = 1.5, flat = 225, special = true }, { every = 10, flat = 900 } },
	hunter = { { every = 10, weapon = 1, flat = 150, special = true }, { every = 6, flat = 183, special = true } },
	enhancement = { { every = 20, weapon = 1 }, { windfury = true } },
	cat = { { every = 4, weapon = 2.25, flat = 180 } },
	retribution = { { ppm = 7, weapon = 0.7 } },
	melee = { { every = 6, weapon = 1 } },
}

-- The average damage per second of this state.
local function Dps(s)
	local target, talents = s.target, s.talents
	local crit = math.min(1, math.max(0, s.crit / 100))
	local hit = math.max(0, s.hit / 100)
	local miss = math.max(0, target.miss - hit)
	local abilities = ABILITIES[s.spec] or ABILITIES.melee
	local scale = s.flatScale
	if s.ranged then
		local w = s.rangedWeapon
		local shot = (w.base + s.rap / 14 * w.speed) * s.pct
		local landed = 1 - miss
		local total = shot / (w.speed / s.rate) * landed * (1 + crit)
		local bonus = 0.06 * (talents.mortalShots or 0)
		for _, a in ipairs(abilities) do
			local damage = (a.weapon or 0) * shot + (a.flat or 0) * scale * s.pct
			total = total + damage / a.every * landed * (1 + crit * (1 + (a.special and bonus or 0)))
		end
		return total
	end
	local dual = s.oh ~= nil
	local whiteMiss = dual and math.max(0, target.dualMiss - hit) or miss
	local glance = target.glance
	local landedWhite = math.max(0, 1 - whiteMiss - target.dodge - glance)
	local whiteCrit = math.min(crit, landedWhite)
	-- (a critical strike counts twice, a glancing blow less)
	local whiteMult = landedWhite + whiteCrit + glance * target.glanceDamage
	local landed = math.max(0, 1 - miss - target.dodge)
	local flurry = (talents.flurry or 0) > 0 and (0.05 + 0.05 * math.min(5, talents.flurry)) * (1 - (1 - crit) ^ 3) or 0
	local rate = s.rate * (1 + flurry)
	local function Swing(w, extraAp) return (w.base + (s.ap + (extraAp or 0)) / 14 * w.speed) * s.pct end
	local mhSwing = Swing(s.mh)
	local swings = rate / s.mh.speed
	local total = mhSwing * swings * whiteMult
	local crits = swings * whiteCrit
	if dual then
		local ohSwings = rate / s.oh.speed
		total = total + Swing(s.oh) * s.ohFactor * ohSwings * whiteMult
		crits = crits + ohSwings * whiteCrit
	end
	local bonus = 0.1 * (talents.impale or 0) + 0.06 * (talents.lethality or 0)
	for _, a in ipairs(abilities) do
		local per, damage
		if a.windfury then
			per = swings * (1 - whiteMiss - target.dodge) * 0.2
			damage = Swing(s.mh, 315 * scale)
		else
			per = a.ppm and a.ppm / 60 or 1 / a.every
			damage = (a.weapon or 0) * mhSwing + (a.flat or 0) * scale * s.pct + (a.ap or 0) * s.ap * s.pct
		end
		total = total + damage * per * landed * (1 + crit * (1 + (a.special and bonus or 0)))
		crits = crits + per * landed * crit
	end
	-- Deep wounds: each critical strike bleeds a part of a weapon hit.
	if (talents.deepWounds or 0) > 0 then total = total + crits * 0.2 * math.min(3, talents.deepWounds) * mhSwing end
	-- Vengeance: more damage for a while after a critical strike.
	if (talents.vengeance or 0) > 0 then
		local uptime = 1 - (1 - crit) ^ math.max(1, 8 * swings)
		total = total * (1 + 0.03 * math.min(5, talents.vengeance) * uptime)
	end
	return total
end
Model.Dps = Dps

local function Copy(s)
	local copy = {}
	for key, value in pairs(s) do copy[key] = value end
	for _, key in ipairs({ "mh", "oh", "rangedWeapon" }) do
		if s[key] then copy[key] = { base = s[key].base, speed = s[key].speed } end
	end
	return copy
end

-- The same state with a little more of a characteristic.
local function With(s, stat, amount)
	local t = Copy(s)
	local class = CLASSES[s.class]
	if stat == "str" then
		t.ap = t.ap + amount * s.strMult * class.strAp
	elseif stat == "agi" then
		local agi = amount * s.agiMult
		t.ap = t.ap + agi * class.agiAp
		t.rap = t.rap + agi * (class.agiRap or 0)
		t.crit = t.crit + agi / s.agiCrit
	elseif stat == "ap" then
		t.ap, t.rap = t.ap + amount, t.rap + amount
	elseif stat == "rap" then
		t.rap = t.rap + amount
	elseif stat == "crit" then
		t.crit = t.crit + amount
	elseif stat == "hit" then
		t.hit = t.hit + amount
	elseif stat == "haste" then
		t.rate = t.rate * (100 + s.haste + amount) / (100 + s.haste)
	elseif stat == "dps" and not s.cat then
		-- (a weapon's damage per second: on the weapon that counts)
		local weapon = s.ranged and t.rangedWeapon or t.mh
		if weapon then weapon.base = weapon.base + amount * weapon.speed end
	end
	return t
end

local function Round(value) return math.floor(value * 100 + 0.5) / 100 end

-- The weights of a state: stat -> weight (the main one at 1; nothing for a characteristic worth
-- nothing), and the raw gains per point; nil when the damage cannot be measured.
function Model.Weights(s)
	local base = Dps(s)
	if not (base and base > 0) then return nil end
	local gains = {}
	for _, stat in ipairs(MODELLED) do gains[stat] = (Dps(With(s, stat, STEPS[stat])) - base) / STEPS[stat] end
	local main = gains[s.main]
	if not (main and main > 0) then return nil end
	local weights = {}
	for stat, gain in pairs(gains) do
		local weight = Round(gain / main)
		if weight > 0 then weights[stat] = weight end
	end
	weights[s.main] = 1
	return weights, gains
end

-- Has the hit cap been reached (for abilities, and for every hit)?
function Model.HitCapped(s)
	local cap = s.target.miss * 100
	local capped = s.hit >= cap - 0.05
	local whiteToo = capped and (s.ranged or not s.oh or s.hit >= s.target.dualMiss * 100 - 0.05)
	return capped, whiteToo, cap
end

local function Number(value) return tonumber(Clean(value)) end

local function Sum(...)
	local total = 0
	for index = 1, select("#", ...) do total = total + (Number(select(index, ...)) or 0) end
	return total
end

local function RatingBonus(id) return Number(Safe(_G.GetCombatRatingBonus, id)) or 0 end

-- A weapon read from the game's figures: its own average hit (the attack power taken out), its speed.
local function Weapon(low, high, percent, speed, ap)
	low, high, speed = Number(low), Number(high), Number(speed)
	if not (low and high and speed and speed > 0) then return nil end
	return { base = math.max(1, (low + high) / 2 / percent - ap / 14 * speed), speed = speed }
end

-- Your state, from the game; nil when it does not say enough.
function Model.Read(class, branch)
	local info = CLASSES[class or ""]
	if not info then return nil end
	local level = Number(Safe(UnitLevel, "player")) or 60
	local talents, counted, points = ReadTalents()
	local _, str = Safe(_G.UnitStat, "player", 1)
	local _, agi = Safe(_G.UnitStat, "player", 2)
	local apBase, apPlus, apMinus = Safe(_G.UnitAttackPower, "player")
	str, agi = Number(str), Number(agi)
	if not (str and agi and Number(apBase)) then return nil end
	local s = {
		class = class, level = level, main = info.main, talents = talents, counted = counted,
		target = Target(level), rate = 1, pct = 1, flatScale = math.max(0.2, math.min(1, level / 60)),
		strMult = 1 + 0.02 * (talents.divineStrength or 0), agiMult = 1 + 0.03 * (talents.reflexes or 0),
		agiCrit = info.agiCrit * math.max(10, math.min(60, level)) / 60,
		str = str, agi = agi, ap = Sum(apBase, apPlus, apMinus), rap = 0,
	}
	if info.ranged then
		s.ranged, s.spec = true, "hunter"
		local rapBase, rapPlus, rapMinus = Safe(_G.UnitRangedAttackPower, "player")
		if not Number(rapBase) then return nil end
		s.rap = Sum(rapBase, rapPlus, rapMinus)
		s.crit = Number(Safe(_G.GetRangedCritChance)) or Number(Safe(_G.GetCritChance)) or 0
		s.hit = (Number(Safe(_G.GetHitModifier)) or 0) + RatingBonus(_G.CR_HIT_RANGED or CR_HIT_RANGED)
		s.haste = RatingBonus(_G.CR_HASTE_RANGED or CR_HASTE_RANGED)
		local speed, low, high, _, _, percent = Safe(_G.UnitRangedDamage, "player")
		percent = Number(percent) or 1
		s.pct = percent > 0 and percent or 1
		s.rangedWeapon = Weapon(low, high, s.pct, speed, s.rap)
		if not s.rangedWeapon then return nil end
		return s
	end
	s.crit = Number(Safe(_G.GetCritChance)) or 0
	s.hit = (Number(Safe(_G.GetHitModifier)) or 0) + RatingBonus(_G.CR_HIT_MELEE or CR_HIT_MELEE)
	s.haste = RatingBonus(_G.CR_HASTE_MELEE or CR_HASTE_MELEE)
	local low, high, offLow, offHigh, _, _, percent = Safe(_G.UnitDamage, "player")
	local speed, offSpeed = Safe(_G.UnitAttackSpeed, "player")
	percent = Number(percent) or 1
	s.pct = percent > 0 and percent or 1
	if info.cat then
		-- The cat: its claws, never the weapon; out of the form, its power and critical strikes as in it.
		s.cat, s.spec = true, "cat"
		if Number(Safe(_G.GetShapeshiftFormID)) == CAT_FORM then
			s.mh = Weapon(low, high, s.pct, speed, s.ap)
		else
			s.ap = s.ap + agi + 0.5 * level * (talents.predatory or 0)
			s.crit = s.crit + 2 * (talents.claws or 0)
		end
		s.mh = s.mh or { base = math.max(1, 0.9 * level), speed = 1 }
		return s
	end
	s.mh = Weapon(low, high, s.pct, speed, s.ap)
	if not s.mh then return nil end
	s.oh = Weapon(offLow, offHigh, s.pct, offSpeed, s.ap)
	if s.oh then
		-- (the game halves the off hand already; the talent raises it)
		s.ohFactor = 1 + (class == "ROGUE" and 0.1 or 0.05) * (talents.dualWield or 0)
	end
	if class == "WARRIOR" then
		s.spec = (points[2] or 0) > (points[1] or 0) and "fury" or "arms"
	elseif class == "ROGUE" then
		local link = Clean(Safe(GetInventoryItemLink, "player", 16))
		local _, _, _, _, _, _, subclass = U.ItemInstant(link or 0)
		s.spec = Clean(subclass) == 15 and "backstab" or "sinister"
	elseif class == "SHAMAN" then
		s.spec = "enhancement"
	elseif class == "PALADIN" then
		s.spec = "retribution"
	else
		s.spec = "melee"
	end
	s.branch = branch
	return s
end

-- Calculated, kept until your gear, talents or level change -------------------------------------------

local known = {} -- scale id -> its result (false: not calculable)

local function Stored(id)
	local mine = ns.root and ns.Mine()
	if not mine then return nil end
	mine.calculated = type(mine.calculated) == "table" and mine.calculated or {}
	local entry = mine.calculated[id]
	if type(entry) ~= "table" then
		entry = {}
		mine.calculated[id] = entry
	end
	return entry
end

-- What moved since the last weights kept: { stat, change } (a fraction), the largest first, two at most.
local function Changes(before, after)
	local list = {}
	for _, stat in ipairs(MODELLED) do
		local old, new = before[stat] or 0, after[stat] or 0
		if old > 0 and math.abs(new - old) / old >= CHANGE_SHOWN then
			list[#list + 1] = { stat = stat, change = (new - old) / old }
		end
	end
	table.sort(list, function(a, b) return math.abs(a.change) > math.abs(b.change) end)
	while #list > 2 do table.remove(list) end
	return list
end

-- The calculated weights of a scale (class, branch, key: the feral druid's "CAT"), merged into its fixed
-- ones (stamina and the others the model does not weigh): { weights, notes, hitCapped, whiteCapped, cap,
-- state }; nil when the model does not cover it or the game says too little.
function Model.For(class, branch, key, id, fixed)
	if not Model.Covers(class, branch, key) then return nil end
	id = id or tostring(branch)
	local result = known[id]
	if result ~= nil then return result or nil end
	-- (in a fight the game hides your numbers: nothing read nor kept then, the fixed weights speak meanwhile)
	if InCombatLockdown() then return nil end
	local s = Model.Read(class, branch)
	local weights = s and Model.Weights(s)
	if not weights then
		known[id] = false
		return nil
	end
	local merged = {}
	for stat, weight in pairs(fixed or {}) do
		if not IS_MODELLED[stat] then merged[stat] = weight end
	end
	for stat, weight in pairs(weights) do merged[stat] = weight end
	local capped, whiteCapped, cap = Model.HitCapped(s)
	result = { weights = merged, state = s, hitCapped = capped, whiteCapped = whiteCapped, cap = cap, notes = {} }
	-- What changed since the last weights kept for this character (kept from one session to the next).
	local stored = Stored(id)
	if stored then
		local before = type(stored.weights) == "table" and stored.weights
		local notes = before and Changes(before, weights) or {}
		if notes[1] then
			stored.notes = notes
		end
		stored.weights = {}
		for stat, weight in pairs(weights) do stored.weights[stat] = weight end
		result.notes = type(stored.notes) == "table" and stored.notes or {}
	end
	known[id] = result
	return result
end

-- Calculated again (soon): gear, talents or level changed.
function Model.Forget()
	wipe(known)
end

-- (gear, talents or level changed: Upgrade.lua, which listens to those, calls Forget)

-- On, for this character (its profile): the calculated weights speak in place of the fixed ones.
function ns.UseCalculatedWeights()
	return ns.db and ns.db.tooltips and ns.db.tooltips.calculatedWeights ~= false or false
end

-- Set from the weights window (Options.lua sets it as every option): in every profile of this character.
function ns.SetUseCalculatedWeights(value)
	local function Set() ns.db.tooltips.calculatedWeights = value and true or false end
	if ns.ChangeEverywhere then ns.ChangeEverywhere(Set) else Set() end
	ns.ComparisonChanged()
	if ns.RefreshWeights then ns.RefreshWeights() end
	if ns.RefreshOptions then ns.RefreshOptions() end
end
