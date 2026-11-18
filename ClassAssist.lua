local _, ns = ...
local L = ns.L

-- The class assistant (approved 2026-11-18 on its mockup): under your portrait, a row of your class's own icons,
-- as action buttons are drawn: the spell's or the item's real icon, a sweep and its countdown when a time
-- applies, a count at the bottom right when one applies. A 2 px ink edge when all is well, orange when it ends
-- soon (under a minute for a buff, five for a weapon's enchant) or runs low, the icon greyed with that orange
-- edge when it is missing (out of a fight only). In a fight: what lasts; out of a fight: only what is missing,
-- ending or low (nothing when all is well). It never suggests a spell, never casts anything (no secure button),
-- no sound, no flash, nothing in the middle of the screen.
-- Beside it: a spark on your power bar (the next energy tick; the five seconds after a mana spell, then the next
-- tick), a druid's mana as a thin third bar in bear and cat form, a hunter's pet mood against the pet frame. The
-- combo points stay as UnitFrames.lua draws them. Nothing on your target: the game shows your debuffs there.
--
-- The game hides many values in a fight ("secret"): an aura's data, a duration, a power. Every one is passed
-- on to the widgets that take them (a cooldown from the game's own duration object, a bar's value, a text)
-- and read only when it is clear; what cannot be read is simply not shown, never guessed. /wanderer classe dump
-- writes what each reading answers, in and out of a fight, for the ones still to make reliable.

local U = ns.Util
local Safe, Clean, IsSecret = U.Safe, U.Clean, U.IsSecret

local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GAP = 4 -- (the composition's own gap, UnitFrames.lua's ARRANGE_GAP)
local ICON_SIZES = { fine = 20, medium = 22, thick = 26 }
local THIRD_SIZES = { fine = 4, medium = 5, thick = 6 }
local POOL = 6 -- icons at most (a shaman: four totems, the shield, the imbue)
local BUFF_SOON, ENCHANT_SOON = 60, 300 -- seconds: a buff, a weapon's enchant ending soon
local AMMO_LOW, WATER_LOW = 200, 4
local TICK, FIVE = 2, 5 -- seconds between two ticks (energy, mana); the mana's five-second rule
local INK = { 0, 0, 0, 0.9 }
local MANA = { 0.231, 0.490, 0.847 } -- #3B7DD8
local function Hex(hex) return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 } end
-- (the totems by the game's slots: fire, earth, water, air)
local ELEMENTS = { Hex("c0532a"), Hex("8a6a3a"), Hex("3a7ab0"), Hex("7aa0b0") }
local function Warn()
	local c = ns.Skin.SCREEN_COLORS.warn
	return c[1], c[2], c[3], 1
end

-- Spell families: every rank of a spell (the game's own tables, WoW Forever 1.60.1.70658: SpellName and
-- SkillLineAbility), and its larger form for a group where it has one. An aura of any of them is the family's.
local FAMILIES = {
	sliceDice = { 5171, 6774 },
	wild = { 1126, 5232, 5234, 6756, 8907, 9884, 9885, 21849, 21850 },
	aspect = { 13163, 5118, 13159, 20043, 20190, 13161, 1299445, 1299446, 1299447, 34074, 415423, 415424, 415718,
		13165, 14318, 14319, 14320, 14321, 14322, 25296 },
	battleShout = { 5242, 6192, 6673, 11549, 11550, 11551, 25289 },
	seal = { 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 21084, 20162, 20305, 20306, 20307, 20308, 21082,
		20375, 20915, 20918, 20919, 20920, 20166, 20356, 20357, 20165, 20347, 20348, 20349, 20164 },
	paladinAura = { 465, 643, 1032, 10290, 10291, 10292, 10293, 7294, 10298, 10299, 10300, 10301, 19746, 19876, 19895, 19896,
		19888, 19897, 19898, 19891, 19899, 19900, 20218 },
	blessing = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 19742, 19850, 19852, 19853, 19854, 25290, 20217, 19977, 19978,
		19979, 25782, 25916, 25894, 25918, 25898, 25890 },
	lightningShield = { 324, 325, 905, 945, 8134, 10431, 10432 },
	mageArmor = { 168, 7300, 7301, 7302, 7320, 10219, 10220, 6117, 22782, 22783, 428741, 428743, 429307, 456403 },
	intellect = { 1459, 1460, 1461, 10156, 10157, 23028 },
	demonArmor = { 687, 696, 706, 1086, 11733, 11734, 11735, 403619 },
	soulstone = { 20707, 20762, 20763, 20764, 20765 },
	innerFire = { 588, 602, 1006, 7128, 10951, 10952 },
	fortitude = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 },
}
-- Spells that make an item (the item missing tells only when you can make it).
local MAKERS = {
	manaGem = { 759, 3552, 10053, 10054 },
	water = { 5504, 5505, 5506, 6127, 10138, 10139, 10140, 468766 },
	healthstone = { 5699, 6201, 6202, 11729, 11730 },
	soulstone = { 693, 20752, 20755, 20756, 20757 },
}
-- Items counted in your bags.
local ITEMS = {
	manaGem = { 8008, 8007, 5513, 5514 },
	water = { 8079, 8078, 8077, 3772, 2136, 2288, 5350 },
	healthstone = { 9421, 19012, 19013, 5510, 19010, 19011, 5509, 19008, 19009, 5511, 19006, 19007, 5512, 19004, 19005 },
	shard = { 6265 },
}
local ARROW_ICON, BULLET_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02", "Interface\\Icons\\INV_Ammo_Bullet_02"

local BY_SPELL = {} -- spell id -> its family
for family, ids in pairs(FAMILIES) do
	for _, id in ipairs(ids) do BY_SPELL[id] = family end
end

local function DB() return ns.db and ns.db.classAssist end
local function On()
	local db = DB()
	return ns.db and ns.db.enabled and type(db) == "table" and db.enabled and true or false
end
local function SparksOn() return On() and DB().sparks ~= false end
local function ThirdWanted() return On() and DB().druidMana ~= false end
local function Fighting()
	if Clean(Safe(InCombatLockdown)) or ns.inCombat then return true end
	return Clean(Safe(UnitAffectingCombat, "player")) and true or false
end
local function Class()
	local _, class = Safe(UnitClass, "player")
	return Clean(class)
end
local function PowerToken()
	local _, token = Safe(UnitPowerType, "player")
	return Clean(token)
end
local function PowerIndex(name, fallback)
	local kinds = Enum and Enum.PowerType
	return kinds and kinds[name] or fallback
end

-- Spells ---------------------------------------------------------------------------------------------------

local function SpellName(id)
	if not id then return nil end
	local get = C_Spell and C_Spell.GetSpellName
	if get then return Clean(Safe(get, id)) end
	return Clean((Safe(_G.GetSpellInfo, id)))
end
local function SpellIcon(id)
	if not id then return nil end
	local get = (C_Spell and C_Spell.GetSpellTexture) or _G.GetSpellTexture
	return Clean(Safe(get, id))
end
local function KnownSpell(id)
	-- (the three checks named, no list made per call: read for every rank every second)
	local spellBook = C_SpellBook and C_SpellBook.IsSpellKnown
	if type(_G.IsPlayerSpell) == "function" and Clean(Safe(_G.IsPlayerSpell, id)) then return true end
	if type(_G.IsSpellKnown) == "function" and Clean(Safe(_G.IsSpellKnown, id)) then return true end
	return type(spellBook) == "function" and Clean(Safe(spellBook, id)) and true or false
end
-- The highest rank of a list you know, or nil.
local function Known(list)
	for index = #list, 1, -1 do
		if KnownSpell(list[index]) then return list[index] end
	end
	return nil
end

-- The families by their names in your client's language (an aura whose spell is hidden but whose name is not).
local byName
local function ByName()
	if byName then return byName end
	local made, any = {}, false
	for family, ids in pairs(FAMILIES) do
		for _, id in ipairs(ids) do
			local name = SpellName(id)
			if type(name) == "string" and made[name] == nil then
				made[name] = family
				any = true
			end
		end
	end
	-- (the names may not be loaded yet: asked again next time)
	if any then byName = made end
	return made
end

-- Your auras ------------------------------------------------------------------------------------------------

local instances = {} -- family -> its aura's instance id, kept through a fight
local icons = {} -- family -> its aura's icon, last seen
local pending = {} -- family -> when you cast it last (an unreadable aura added then is that one)
local lengths = {} -- family -> its full time when last read (0: lasts until removed), for its hidden times

-- Your helpful auras as read now: family -> { spell, instance, icon, expires, duration, count, name }, and whether
-- the reading was whole (false: the game hides them now).
local function ReadAuras()
	local found, readable = {}, true
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then return found, false end
	local names = ByName()
	local seen = 0
	local mine = {} -- instance -> family, as kept (an aura whose words are hidden, known by its instance)
	for family, id in pairs(instances) do mine[id] = family end
	for index = 1, 40 do
		local aura = Safe(get, "player", index, "HELPFUL")
		if not IsSecret(aura) and aura == nil then break end
		if IsSecret(aura) or type(aura) ~= "table" then
			readable = false
			break
		end
		seen = seen + 1
		local spell, name = Clean(aura.spellId), Clean(aura.name)
		if spell == nil and name == nil then readable = false end
		local instance = Clean(aura.auraInstanceID)
		local family = (spell and BY_SPELL[spell]) or (type(name) == "string" and names[name]) or (instance and mine[instance]) or nil
		if family and not found[family] then
			local icon = Clean(aura.icon)
			found[family] = { spell = spell, instance = instance, icon = icon, expires = Clean(aura.expirationTime),
				duration = Clean(aura.duration), count = Clean(aura.applications), name = name }
			if icon then icons[family] = icon end
		end
	end
	-- (nothing at all in a fight, while auras were known before it: the game keeps them from us, not gone)
	if seen == 0 and Fighting() and next(instances) then readable = false end
	return found, readable
end

-- Your auras by family: read whole when the game lets it; else what was there, still there by its instance.
local function Auras()
	local found, readable = ReadAuras()
	if readable then
		wipe(instances)
		for family, info in pairs(found) do
			if info.instance then instances[family] = info.instance end
		end
		return found, true
	end
	local byInstance = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
	for family, id in pairs(instances) do
		if not found[family] then
			local still = byInstance and Safe(byInstance, "player", id)
			if IsSecret(still) or type(still) == "table" then
				found[family] = { instance = id, icon = icons[family], hidden = true }
			else
				instances[family] = nil
			end
		end
	end
	return found, false
end

-- An aura added (the game's UNIT_AURA details): its instance kept for its family, its spell read or, hidden,
-- the family you just cast; one removed: forgotten.
local function AuraChanged(info)
	if type(info) ~= "table" or IsSecret(info) then return end
	local added = info.addedAuras
	if type(added) == "table" and not IsSecret(added) then
		for _, aura in ipairs(added) do
			if type(aura) == "table" and not IsSecret(aura) then
				local id, spell = Clean(aura.auraInstanceID), Clean(aura.spellId)
				local family = spell and BY_SPELL[spell]
				if not family and id and spell == nil then
					local now, at = GetTime(), nil
					for which, when in pairs(pending) do
						if now - when < 1 and (not at or when > at) then family, at = which, when end
					end
				end
				if family and id then
					instances[family], pending[family] = id, nil
				end
			end
		end
	end
	local removed = info.removedAuraInstanceIDs
	if type(removed) == "table" and not IsSecret(removed) then
		for _, id in ipairs(removed) do
			id = Clean(id)
			for family, known in pairs(instances) do
				if id and known == id then instances[family] = nil end
			end
		end
	end
end

-- A soulstone you placed (on you or someone of your group): { unit, instance, expires, duration } as last
-- read out of a fight; kept through it (its time from the game's own object).
local stone
local stoneReadAt -- (your group's auras read again every few seconds at most)
local function ReadSoulstone()
	if Fighting() then
		if stone and stone.instance then
			local byInstance = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
			local still = byInstance and Safe(byInstance, stone.unit, stone.instance)
			if not (IsSecret(still) or type(still) == "table") then stone = nil end
		end
		return stone
	end
	local now = GetTime()
	if stoneReadAt and now - stoneReadAt < 3 then return stone end
	stoneReadAt = now
	stone = nil
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then return nil end
	local units = { "player" }
	local raid = Clean(Safe(IsInRaid))
	for index = 1, raid and 40 or 4 do units[#units + 1] = (raid and "raid" or "party") .. index end
	local names = ByName()
	for _, unit in ipairs(units) do
		if Clean(Safe(UnitExists, unit)) then
			for index = 1, 40 do
				local aura = Safe(get, unit, index, "HELPFUL")
				if IsSecret(aura) or type(aura) ~= "table" then break end
				local spell, name = Clean(aura.spellId), Clean(aura.name)
				local family = (spell and BY_SPELL[spell]) or (type(name) == "string" and names[name]) or nil
				local source = aura.sourceUnit
				if family == "soulstone" and not IsSecret(source) and (source == nil or source == "player") then
					stone = { unit = unit, instance = Clean(aura.auraInstanceID), expires = Clean(aura.expirationTime),
						duration = Clean(aura.duration), icon = Clean(aura.icon), name = name, who = Clean(Safe(UnitName, unit)) }
					return stone
				end
			end
		end
	end
	return nil
end

-- Weapons, items, totems, stances, the pet ---------------------------------------------------------------------

-- The game's slot for a hand (1 main, 2 off) in C_Item.GetWeaponEnchantInfo, by its name.
local function WeaponSlot(which)
	local slots = Enum and Enum.WeaponSlot
	if type(slots) ~= "table" then return nil end
	for key, value in pairs(slots) do
		if type(key) == "string" and key:find(which == 1 and "Main" or "Off") then return value end
	end
	return nil
end

-- A hand's temporary enchant (poison, stone, oil, imbue): has (nil: not known), seconds left (nil: not readable),
-- charges, its icon if the game gives one.
local function Enchant(which)
	local api = C_Item and C_Item.GetWeaponEnchantInfo
	local slot = WeaponSlot(which)
	if api and slot ~= nil then
		local list = Safe(api, slot)
		if type(list) == "table" and not IsSecret(list) then
			-- (one entry hidden in a fight: not known, never "none")
			local unknown = false
			for _, each in pairs(list) do
				if IsSecret(each) or (type(each) == "table" and IsSecret(each.hasEnchant)) then
					unknown = true
				elseif type(each) == "table" and Clean(each.hasEnchant) then
					local left = Clean(each.timeLeft)
					return true, type(left) == "number" and left / 1000 or nil, Clean(each.charges), Clean(each.enchantIconID)
				end
			end
			if unknown then return nil end
			return false
		end
	end
	if _G.GetWeaponEnchantInfo then
		local values = { Safe(_G.GetWeaponEnchantInfo) }
		local base = which == 1 and 0 or 4
		local has = values[base + 1]
		if IsSecret(has) or has == nil then return nil end
		local left = Clean(values[base + 2])
		return has and true or false, type(left) == "number" and left / 1000 or nil, Clean(values[base + 3])
	end
	return nil
end

local function ItemCount(id) return U.ItemCount(id) end
-- The count of a list of items in your bags, the icon and name of the first you hold (else the first's).
local function Count(list)
	local total, icon, name = 0, nil, nil
	for _, id in ipairs(list) do
		local count = ItemCount(id)
		if type(count) == "number" and count > 0 then
			total = total + count
			if not icon then icon, name = U.ItemIcon(id), U.ItemName(id) end
		end
	end
	return total, icon or U.ItemIcon(list[1]), name or U.ItemName(list[1])
end

-- Your ammunition (hunters): count, icon, name; nil when your ranged weapon takes none (thrown, a wand) or none is
-- known. Bows and crossbows take arrows, guns bullets: the ammo slot first, else what your bags hold of that kind.
local function Ammo()
	local ranged = Clean(Safe(GetInventoryItemID, "player", 18))
	if not ranged then return nil end
	local info = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
	local _, _, _, _, _, class, sub = Safe(info, ranged)
	class, sub = Clean(class), Clean(sub)
	local kind = (sub == 2 or sub == 18) and 2 or (sub == 3 and 3) or nil
	if class ~= 2 or not kind then return nil end
	local fallback = kind == 2 and ARROW_ICON or BULLET_ICON
	local equipped = Clean(Safe(GetInventoryItemID, "player", 0))
	if equipped then
		local slotCount = Clean(Safe(_G.GetInventoryItemCount, "player", 0))
		local count = math.max(type(slotCount) == "number" and slotCount or 0, ItemCount(equipped) or 0)
		return count, U.ItemIcon(equipped) or fallback, U.ItemName(equipped)
	end
	local best, bestCount = nil, 0
	U.EachBagItem(function(_, _, item)
		local _, _, _, _, _, itemClass, itemSub = Safe(info, item.itemID)
		if Clean(itemClass) == 6 and Clean(itemSub) == kind then
			local count = ItemCount(item.itemID) or 0
			if count > bestCount then best, bestCount = item.itemID, count end
		end
	end)
	if best then return bestCount, U.ItemIcon(best) or fallback, U.ItemName(best) end
	return 0, fallback, nil
end

-- A totem slot (1 fire, 2 earth, 3 water, 4 air): present (nil: hidden and never seen), name, start, length,
-- icon (each maybe hidden: passed on as they come), and the game's own answer when it is hidden (the icon's
-- alpha takes it: a totem destroyed or replaced in a fight leaves, one put down in it comes).
local totemSeen = {}
local row, pool -- our frame under your portrait, its icons (made in Build below)
local function BoolAlpha() return pool and pool[1] and type(pool[1].SetAlphaFromBoolean) == "function" or false end
local function Totem(slot)
	if not _G.GetTotemInfo then return nil end
	local have, name, start, length, icon = Safe(_G.GetTotemInfo, slot)
	if IsSecret(have) then
		local present = totemSeen[slot]
		if BoolAlpha() then present = true end
		return present, name, start, length, icon, have
	end
	totemSeen[slot] = have and true or false
	return have and true or false, name, start, length, icon
end

-- Your stance or form now (warriors): icon, spell; nil without one.
local function Stance()
	local index = Clean(Safe(_G.GetShapeshiftForm))
	if type(index) ~= "number" or index <= 0 then return nil end
	local icon, _, _, spell = Safe(_G.GetShapeshiftFormInfo, index)
	return Clean(icon), Clean(spell)
end

-- Your hunter pet's mood: 1 unhappy, 2 content, 3 happy; nil without a hunter's pet or a clear answer.
local function Mood()
	local _, hunterPet = Safe(_G.HasPetUI)
	if not Clean(hunterPet) then return nil end
	local api = (_G.C_PetInfo and _G.C_PetInfo.GetPetHappiness) or _G.GetPetHappiness
	local level = Clean(Safe(api))
	-- (only the three moods drawn: any other answer, none)
	return (level == 1 or level == 2 or level == 3) and level or nil
end

-- What each class shows ------------------------------------------------------------------------------------------
-- An item: { key, icon, state ("ok", "ending", "missing"), title, words, count, instance (an aura's), unit,
-- expires and duration (readable), start and length (a cooldown as the game gives it), element (a totem's colour) }.

local function Add(list, item) list[#list + 1] = item end

local function Left(expires)
	if type(expires) ~= "number" or expires <= 0 then return nil end
	return expires - GetTime()
end

-- When a buff "ends soon": its last minute, or its last quarter for a short one (Slice and Dice).
local function SoonFor(duration)
	if type(duration) == "number" and duration > 0 then return math.min(BUFF_SOON, duration / 4) end
	return BUFF_SOON
end

-- An aura family: opts.fight (shown in a fight while active), opts.ending (out of one: when it ends soon),
-- opts.missing (out of one: when it is not there and you know it), opts.count (its stacks or charges shown).
local function AuraItem(list, fight, found, family, opts)
	local ids = FAMILIES[family]
	local info = found[family]
	local known = Known(ids)
	if info then
		-- (its threshold from its full time, as read now or last; hidden and never read, or lasting until removed
		-- like an aura or an aspect: none, its edge never guessed)
		if type(info.duration) == "number" then lengths[family] = info.duration end
		local length = lengths[family]
		local left, soon = Left(info.expires), type(length) == "number" and length > 0 and SoonFor(length) or nil
		local ending = left ~= nil and soon ~= nil and left < soon
		if fight and not opts.fight then return end
		if not fight and not (opts.ending and ending) then return end
		Add(list, { key = family, icon = info.icon or icons[family] or SpellIcon(info.spell or known or ids[1]),
			state = ending and "ending" or "ok", title = info.name or SpellName(info.spell or known or ids[1]),
			count = opts.count and info.count, charges = opts.count, instance = info.instance, unit = "player", expires = info.expires,
			duration = info.duration, soon = soon })
	elseif not fight and opts.missing and known then
		Add(list, { key = family, icon = SpellIcon(known), state = "missing", title = SpellName(known) })
	end
end

-- A hand's enchant: opts.fight (shown in a fight while there), opts.gone (out of one: missing once it wore off
-- on the same weapon). Its sweep from when Wanderer first saw it (its full length then).
local enchantSeen = {} -- hand -> { item, start, length, left }
local function EnchantItem(list, fight, which, opts)
	local slot = which == 1 and 16 or 17
	local held = Safe(GetInventoryItemID, "player", slot)
	local weapon = Clean(held)
	local seen = enchantSeen[which]
	-- (your weapon hidden in a fight: the one seen before it, it cannot be changed meanwhile)
	if weapon == nil and IsSecret(held) and seen then weapon = seen.item end
	if not weapon then
		enchantSeen[which] = nil
		return
	end
	if seen and seen.item ~= weapon then seen, enchantSeen[which] = nil, nil end
	local has, left, charges = Enchant(which)
	-- (whether one is there hidden in a fight: the last state known before it, never a guess of a new one)
	if has == nil and fight and seen then has = not seen.gone end
	if has == nil then return end
	local texture = Safe(GetInventoryItemTexture, "player", slot)
	local icon = IsSecret(texture) and texture or Clean(texture)
	local title = which == 1 and L.ASSIST_MAIN_HAND or L.ASSIST_OFF_HAND
	if has then
		local now = GetTime()
		if left then
			-- (put on again: a longer time than the last one read starts its sweep over)
			if not seen or not seen.left or left > seen.left + 2 then
				seen = { item = weapon, start = now, length = left }
				enchantSeen[which] = seen
			end
			seen.left, seen.gone = left, nil
		elseif not seen then
			seen = { item = weapon }
			enchantSeen[which] = seen
		end
		local ending = left ~= nil and left < ENCHANT_SOON
		if fight and not opts.fight then return end
		if not fight and not ending then return end
		-- (its time hidden: the icon alone, no sweep nor figure)
		Add(list, { key = "enchant" .. which, icon = icon, state = ending and "ending" or "ok", title = title,
			count = type(charges) == "number" and charges > 0 and charges or nil, start = left and seen.start or nil,
			length = left and seen.length or nil, soon = ENCHANT_SOON, expires = left and now + left or nil })
	elseif seen then
		seen.gone = true
		if not fight and opts.gone then Add(list, { key = "enchant" .. which, icon = icon, state = "missing", title = title, words = L.ASSIST_GONE }) end
	end
end

-- Items in your bags: opts.fight (shown in a fight, greyed when none), opts.low (out of one: under it, orange;
-- none: missing), opts.maker (the spell that makes it: none only tells when you know it).
local function CountItem(list, fight, key, opts)
	local count, icon, name = Count(ITEMS[key])
	local makes = not opts.maker or Known(MAKERS[opts.maker]) ~= nil
	if not makes then return end
	local state = count == 0 and "missing" or (opts.low and count < opts.low and "ending") or "ok"
	if fight then
		if not opts.fight then return end
		Add(list, { key = key, icon = icon, state = count == 0 and "missing" or "ok", title = name, count = count, items = true })
	elseif state ~= "ok" then
		Add(list, { key = key, icon = icon, state = state, title = name, count = count, items = true })
	end
end

local CLASSES = {}

CLASSES.ROGUE = function(list, fight, found)
	AuraItem(list, fight, found, "sliceDice", { fight = true })
	EnchantItem(list, fight, 1, { fight = true, gone = true })
	EnchantItem(list, fight, 2, { fight = true, gone = true })
end

CLASSES.DRUID = function(list, fight, found)
	AuraItem(list, fight, found, "wild", { ending = true })
end

CLASSES.HUNTER = function(list, fight, found)
	local count, icon, name = Ammo()
	if count then
		local state = count == 0 and "missing" or (count < AMMO_LOW and "ending") or "ok"
		if fight or state ~= "ok" then
			Add(list, { key = "ammo", icon = icon, state = state, title = name or L.ASSIST_AMMO, count = count, items = true })
		end
	end
	AuraItem(list, fight, found, "aspect", { fight = true, missing = true })
end

CLASSES.WARRIOR = function(list, fight, found)
	if fight then
		local icon, spell = Stance()
		if icon then Add(list, { key = "stance", icon = icon, state = "ok", title = SpellName(spell) }) end
	end
	AuraItem(list, fight, found, "battleShout", { fight = true })
	EnchantItem(list, fight, 1, {})
end

CLASSES.PALADIN = function(list, fight, found)
	AuraItem(list, fight, found, "seal", { fight = true })
	AuraItem(list, fight, found, "paladinAura", { fight = true })
	AuraItem(list, fight, found, "blessing", { ending = true })
end

CLASSES.SHAMAN = function(list, fight, found)
	if fight then
		for slot = 1, 4 do
			local have, name, start, length, icon, hidden = Totem(slot)
			if have then
				Add(list, { key = "totem" .. slot, icon = icon, state = "ok", title = name, totem = slot, element = ELEMENTS[slot],
					start = start, length = length, present = hidden })
			end
		end
	end
	AuraItem(list, fight, found, "lightningShield", { fight = true, count = true })
	EnchantItem(list, fight, 1, {})
end

CLASSES.MAGE = function(list, fight, found)
	CountItem(list, fight, "manaGem", { fight = true, maker = "manaGem" })
	AuraItem(list, fight, found, "mageArmor", { fight = true, missing = true })
	CountItem(list, fight, "water", { low = WATER_LOW, maker = "water" })
	AuraItem(list, fight, found, "intellect", { ending = true })
end

CLASSES.WARLOCK = function(list, fight, found)
	CountItem(list, fight, "shard", { fight = true, maker = "healthstone" })
	CountItem(list, fight, "healthstone", { fight = true, maker = "healthstone" })
	local placed = ReadSoulstone()
	if placed then
		local left = Left(placed.expires)
		local ending = left ~= nil and left < SoonFor(placed.duration)
		if fight or ending then
			Add(list, { key = "soulstone", icon = placed.icon or SpellIcon(FAMILIES.soulstone[1]), state = ending and "ending" or "ok",
				title = placed.name or SpellName(FAMILIES.soulstone[1]), words = placed.who, instance = placed.instance, unit = placed.unit,
				expires = placed.expires, duration = placed.duration, soon = BUFF_SOON })
		end
	end
	AuraItem(list, fight, found, "demonArmor", { missing = true })
end

CLASSES.PRIEST = function(list, fight, found)
	AuraItem(list, fight, found, "innerFire", { fight = true, missing = true, count = true })
	AuraItem(list, fight, found, "fortitude", { ending = true })
end

-- Your class's items now, in its order (nothing that is fine out of a fight).
local function Collect()
	local fill = CLASSES[Class() or ""]
	if not fill then return {} end
	local fight = Fighting()
	local found = Auras()
	local list = {}
	fill(list, fight, found)
	if not fight then
		local kept = {}
		for _, item in ipairs(list) do
			if item.state ~= "ok" then kept[#kept + 1] = item end
		end
		list = kept
	end
	while #list > POOL do table.remove(list) end
	return list
end
ns.ClassAssistItems = Collect -- (tests, the dump)

-- The row ---------------------------------------------------------------------------------------------------------

local third -- a druid's mana in forms
local sparkFrame -- the spark on your power bar
local petIcon -- a hunter's pet mood
local holder -- where your portrait's frame stands, the game's frame hidden by another addon (ElvUI...): the row held there

local function Pixel(frame)
	local pixel = _G.PixelUtil
	local scale = Clean(Safe(frame.GetEffectiveScale, frame))
	if pixel and pixel.GetNearestPixelSize and type(scale) == "number" and scale > 0 then
		local size = Clean(Safe(pixel.GetNearestPixelSize, 1, scale, 1))
		if type(size) == "number" and size > 0 then return size end
	end
	return 1
end

local function Thickness()
	local uf = ns.db and ns.db.unitFrames
	return uf and uf.thickness or "medium"
end

-- An edge of four ink strips inside a square (2 px), its colour changed at will.
local function Edges(frame)
	frame.edges = {}
	for index = 1, 4 do
		local edge = frame.top:CreateTexture(nil, "OVERLAY")
		edge:SetTexture(WHITE)
		frame.edges[index] = edge
	end
	function frame.PlaceEdges(width)
		local up, down, left, right = unpack(frame.edges)
		for _, edge in ipairs(frame.edges) do edge:ClearAllPoints() end
		up:SetPoint("TOPLEFT", frame, "TOPLEFT")
		up:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
		up:SetHeight(width)
		down:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
		down:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
		down:SetHeight(width)
		left:SetPoint("TOPLEFT", frame, "TOPLEFT")
		left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
		left:SetWidth(width)
		right:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
		right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
		right:SetWidth(width)
	end
	function frame.Tint(r, g, b, a)
		for _, edge in ipairs(frame.edges) do pcall(edge.SetVertexColor, edge, r, g, b, a or 1) end
		-- (kept in one table: drawn again every second)
		local tint = frame.tint or {}
		tint[1], tint[2], tint[3], tint[4] = r, g, b, a
		frame.tint = tint
	end
end

-- (the help card's words for an icon: its state, its count)
local function Words(self)
	local item = self.item
	if not item then return nil end
	local parts = {}
	if item.words then parts[#parts + 1] = item.words end
	if item.mood then
		parts[#parts + 1] = item.mood
	elseif item.state == "missing" then
		parts[#parts + 1] = item.items and L.ASSIST_NONE or (item.words and "" or L.ASSIST_MISSING)
	elseif item.state == "ending" then
		parts[#parts + 1] = item.items and L.ASSIST_LOW or L.ASSIST_ENDING
	else
		parts[#parts + 1] = L.ASSIST_ACTIVE
	end
	local count = Clean(item.count)
	if item.items and type(count) == "number" and count > 0 then parts[#parts + 1] = L.ASSIST_COUNT:format(count) end
	local words = {}
	for _, part in ipairs(parts) do
		if part ~= "" then words[#words + 1] = part end
	end
	return table.concat(words, " ")
end

local function MakeIcon(parent)
	local icon = CreateFrame("Frame", nil, parent)
	icon.padSkip = true
	icon.art = icon:CreateTexture(nil, "ARTWORK")
	icon.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	local cooldown = icon.cooldown
	cooldown:SetAllPoints(icon.art)
	for method, value in pairs({ SetDrawEdge = false, SetDrawBling = false, SetHideCountdownNumbers = false, SetReverse = true }) do
		if cooldown[method] then pcall(cooldown[method], cooldown, value) end
	end
	if cooldown.SetSwipeColor then pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, 0.65) end
	icon.top = CreateFrame("Frame", nil, icon)
	icon.top:SetAllPoints()
	icon.top:SetFrameLevel(icon:GetFrameLevel() + 3)
	icon.count = icon.top:CreateFontString(nil, "OVERLAY", _G.NumberFontNormal and "NumberFontNormal" or nil)
	icon.count:SetJustifyH("RIGHT")
	Edges(icon)
	-- (the mouse for the help card only: clicks go through to the world)
	if icon.EnableMouseMotion then
		icon:EnableMouseMotion(true)
	else
		icon:EnableMouse(true)
		if icon.SetMouseClickEnabled then pcall(icon.SetMouseClickEnabled, icon, false) end
	end
	icon:SetScript("OnEnter", function(self)
		if not self.item then return end
		self.wandererHelpTitle = Clean(self.item.title) or false
		ns.Skin.ShowTip(self, Words)
	end)
	icon:SetScript("OnLeave", function(self) ns.Skin.HideTip(self) end)
	return icon
end

-- The cooldown of an icon from its item: the game's own duration object for an aura (works hidden), else the
-- times read or given (passed on, hidden or not).
local function SetTime(icon, item)
	local cooldown = icon.cooldown
	icon.durationObject = nil
	if item.instance and item.unit and C_UnitAuras and C_UnitAuras.GetAuraDuration and cooldown.SetCooldownFromDurationObject then
		local object = Safe(C_UnitAuras.GetAuraDuration, item.unit, item.instance)
		if (IsSecret(object) or object ~= nil) and pcall(cooldown.SetCooldownFromDurationObject, cooldown, object, true) then
			icon.durationObject = object
			return true
		end
	end
	if item.totem and _G.GetTotemDuration and cooldown.SetCooldownFromDurationObject then
		local object = Safe(_G.GetTotemDuration, item.totem)
		if (IsSecret(object) or object ~= nil) and pcall(cooldown.SetCooldownFromDurationObject, cooldown, object, true) then
			icon.durationObject = object
			return true
		end
	end
	local expires, duration = Clean(item.expires), Clean(item.duration)
	if type(expires) == "number" and type(duration) == "number" and duration > 0 then
		return pcall(cooldown.SetCooldown, cooldown, expires - duration, duration)
	end
	-- (a totem's times as the game gives them, maybe hidden: the widget takes them)
	local start, length = item.start, item.length
	if IsSecret(start) or IsSecret(length) then return pcall(cooldown.SetCooldown, cooldown, start, length) end
	if type(start) == "number" and type(length) == "number" and length > 0 then return pcall(cooldown.SetCooldown, cooldown, start, length) end
	pcall(cooldown.Clear, cooldown)
	return false
end

-- An ending edge from a hidden time: the game's curve on its own duration object (orange under the threshold),
-- never a value read; nothing when the client cannot.
local endCurves = {}
local function EndCurve(threshold)
	if endCurves[threshold] ~= nil then return endCurves[threshold] or nil end
	endCurves[threshold] = false
	local api = _G.C_CurveUtil
	if not (api and api.CreateColorCurve and CreateColor) then return nil end
	local ok, curve = pcall(api.CreateColorCurve)
	-- (the game's objects may be tables or its own userdata: called through methods, never indexed bare)
	if not ok or IsSecret(curve) or (type(curve) ~= "table" and type(curve) ~= "userdata") then return nil end
	local kinds = Enum and Enum.LuaCurveType
	if kinds and kinds.Step then pcall(function() curve:SetType(kinds.Step) end) end
	local r, g, b = Warn()
	local orange, ink = CreateColor(r, g, b, 1), CreateColor(INK[1], INK[2], INK[3], INK[4])
	for _, point in ipairs({ { 0, orange }, { threshold - 0.01, orange }, { threshold, ink }, { 86400, ink } }) do
		if not pcall(function() curve:AddPoint(point[1], point[2]) end) then return nil end
	end
	endCurves[threshold] = curve
	return curve
end

local function CurveTint(icon, threshold)
	local object = icon.durationObject
	if IsSecret(object) or object == nil then return false end
	local curve = EndCurve(threshold)
	if not curve then return false end
	local ok, color = pcall(function() return object:EvaluateRemainingDuration(curve) end)
	if not ok or (not IsSecret(color) and color == nil) then return false end
	local read, r, g, b = pcall(function() return color:GetRGB() end)
	if not read then return false end
	icon.Tint(r, g, b, 1)
	return true
end

-- An icon drawn from its item.
local function Draw(icon, item, size, px)
	icon.item = item
	icon:SetSize(size, size)
	local inner = 2 * px
	icon.art:ClearAllPoints()
	icon.art:SetPoint("TOPLEFT", icon, "TOPLEFT", inner, -inner)
	icon.art:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inner, inner)
	local art = item.icon
	if not IsSecret(art) and art == nil then art = "Interface\\Icons\\INV_Misc_QuestionMark" end
	pcall(icon.art.SetTexture, icon.art, art)
	local missing = item.state == "missing"
	if icon.art.SetDesaturated then icon.art:SetDesaturated(missing) end
	icon.art:SetAlpha(missing and 0.55 or 1)
	icon.PlaceEdges(inner)
	if item.element then
		icon.Tint(unpack(item.element))
	elseif item.state == "ok" then
		icon.Tint(unpack(INK))
	else
		icon.Tint(Warn())
	end
	icon.count:ClearAllPoints()
	icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
	local count = item.count
	-- (charges hidden in a fight: the game's own words for them by the aura's instance, empty at none)
	local display = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
	if (count == nil or IsSecret(count)) and item.charges and item.instance and display then
		local words = Safe(display, item.unit or "player", item.instance, 1)
		if IsSecret(words) or type(words) == "string" then count = words end
	end
	if IsSecret(count) or (type(count) == "string" and count ~= "")
		or (type(count) == "number" and (count > 1 or item.items or (item.charges and count > 0))) then
		pcall(icon.count.SetText, icon.count, count)
		icon.count:Show()
	else
		icon.count:SetText("")
		icon.count:Hide()
	end
	if missing then
		pcall(icon.cooldown.Clear, icon.cooldown)
		icon.durationObject = nil
	else
		SetTime(icon, item)
	end
	-- (an aura's hidden time: its ending edge from the game's curve)
	if item.state == "ok" and not item.element and item.soon and Clean(item.expires) == nil then CurveTint(icon, item.soon) end
	-- (a totem's presence hidden: the game's answer as the icon's alpha, never read)
	if not (IsSecret(item.present) and icon.SetAlphaFromBoolean and pcall(icon.SetAlphaFromBoolean, icon, item.present, 1, 0)) then
		icon:SetAlpha(1)
	end
	icon:Show()
end

local function Build()
	if row then return true end
	local player = _G.PlayerFrame
	if type(player) ~= "table" then return false end
	-- (made out of a fight: the player's frame is the game's, protected)
	if Clean(Safe(InCombatLockdown)) then return false end
	row = CreateFrame("Frame", "WandererClassAssist", player)
	row.padSkip = true
	row:SetSize(1, 1)
	-- (its home when the game's frame is hidden by another addon: on the interface itself, faded with your portrait
	-- by Cinema.lua, gone with the interface in the curtain and the photo)
	holder = CreateFrame("Frame", "WandererClassAssistHolder", UIParent)
	holder.padSkip = true
	holder:SetSize(1, 1)
	pool = {}
	for index = 1, POOL do pool[index] = MakeIcon(row) end
	-- The druid's mana: one of Wanderer's bars, dressed in the look.
	third = CreateFrame("StatusBar", "WandererClassAssistMana", player)
	third:SetMinMaxValues(0, 1)
	third:SetValue(0)
	third:Hide()
	-- The spark: its own frame over the power bar.
	sparkFrame = CreateFrame("Frame", "WandererClassAssistSpark", player)
	sparkFrame:SetSize(1, 1)
	sparkFrame.spark = sparkFrame:CreateTexture(nil, "OVERLAY")
	sparkFrame.spark:SetTexture(SPARK)
	if sparkFrame.spark.SetBlendMode then sparkFrame.spark:SetBlendMode("ADD") end
	local soft = ns.Skin.SCREEN_COLORS.onGold
	sparkFrame.spark:SetVertexColor(soft[1], soft[2], soft[3], 1)
	sparkFrame:Hide()
	-- The pet's mood, beside its portrait.
	local pet = _G.PetFrame
	if type(pet) == "table" then
		petIcon = MakeIcon(pet)
		petIcon:Hide()
	end
	return true
end

-- Where the row goes: under your composition (Ink lines: below the cast's place, from the portrait's outer
-- edge), else under the game's frame.
local function Lowest(candidates, always)
	local lowest, bottom
	for _, frame in ipairs(candidates) do
		if type(frame) == "table" and not IsSecret(frame) and (frame == always or Clean(Safe(frame.IsShown, frame))) then
			local at = Clean(Safe(frame.GetBottom, frame))
			if type(at) == "number" and (not bottom or at < bottom) then lowest, bottom = frame, at end
		end
	end
	return lowest
end

-- The game's frame hidden by another addon (ElvUI, a unit frame addon): the row on the interface where that frame
-- stands (read even hidden), else where it was last read, else the game's own first place for it.
local DEFAULT_SPOT = { x = -19, y = -4, width = 232, height = 100 } -- (from the screen's top left)
local spot -- left, top, width, height in the frame's own measure; scale against the interface's
local function ReadSpot(player)
	local left, top = Clean(Safe(player.GetLeft, player)), Clean(Safe(player.GetTop, player))
	local width, height = Clean(Safe(player.GetWidth, player)), Clean(Safe(player.GetHeight, player))
	local scale, base = Clean(Safe(player.GetEffectiveScale, player)), Clean(Safe(UIParent.GetEffectiveScale, UIParent))
	for _, value in ipairs({ left, top, width, height, scale, base }) do
		if type(value) ~= "number" then return end
	end
	if scale <= 0 or base <= 0 or width <= 0 then return end
	spot = spot or {}
	spot.left, spot.top, spot.width, spot.height, spot.scale = left, top, width, height, scale / base
end

-- Nothing to hold the row: the game's frame not shown (your composition is drawn on it), the interface itself shown.
local function Stray(player)
	if Clean(Safe(player.IsVisible, player)) then return false end
	return Clean(Safe(UIParent.IsVisible, UIParent)) and true or false
end

local function Hold()
	holder:ClearAllPoints()
	if spot then
		-- (its measure the frame's own: the place read is used as it is)
		holder:SetScale(spot.scale)
		holder:SetSize(spot.width, spot.height)
		holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot.left, spot.top)
	else
		holder:SetScale(1)
		holder:SetSize(DEFAULT_SPOT.width, DEFAULT_SPOT.height)
		holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", DEFAULT_SPOT.x, DEFAULT_SPOT.y)
	end
end

-- The left of your portrait in the game's frame (read even hidden), else the game's own.
local function PortraitX(player)
	local portrait = ns.UnitFramePortrait and ns.UnitFramePortrait(player)
	if portrait then
		local left, frameLeft = Clean(Safe(portrait.GetLeft, portrait)), Clean(Safe(player.GetLeft, player))
		if type(left) == "number" and type(frameLeft) == "number" then return left - frameLeft end
	end
	return 24
end

local function Place()
	if not row then return end
	local block = ns.UnitFramesPlayerBlock
	local player = _G.PlayerFrame
	ReadSpot(player)
	-- (moved from one home to the other out of a fight only: the game's frame is protected)
	if not Clean(Safe(InCombatLockdown)) then
		local home = Stray(player) and holder or player
		if row:GetParent() ~= home then row:SetParent(home) end
	end
	row:ClearAllPoints()
	if row:GetParent() == holder then
		Hold()
		row:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", PortraitX(player), 0)
		return
	end
	if block and block.portrait and ns.UnitFramesLines and ns.UnitFramesLines() then
		local px = block.px or 1
		local down = GAP + px + ((block.cast or 0) > 0 and block.cast + GAP + px or 0)
		row:SetPoint("TOPLEFT", block.portrait, "BOTTOMLEFT", 0, -down)
		return
	end
	-- (the game's frame: below the lowest of its own pieces under it, at its portrait's left)
	local x = PortraitX(player)
	-- (the game's cast bar locked under its frame in Edit Mode: its place kept even between two casts, the row
	-- never jumping while you cast)
	local cast = _G.PlayerCastingBarFrame
	local attached = type(cast) == "table" and not IsSecret(cast) and (Clean(rawget(cast, "attachedToPlayerFrame"))
		or Clean(Safe(cast.IsAttachedToPlayerFrame, cast))) and cast or nil
	local candidates = { attached or false, _G.TotemFrame or false, _G.ComboPointPlayerFrame or false, rawget(player, "classPowerBar") or false }
	local under = Lowest(candidates, attached)
	if under then
		row:SetPoint("TOP", under, "BOTTOM", 0, -GAP)
		row:SetPoint("LEFT", player, "LEFT", x, 0)
	else
		row:SetPoint("TOPLEFT", player, "BOTTOMLEFT", x, 0)
	end
end

-- The game's Edit Mode open, a vehicle, you dead: nothing of ours shown.
local function Hidden()
	local edit = _G.EditModeManagerFrame
	if type(edit) == "table" and Clean(Safe(edit.IsShown, edit)) then return true end
	if Clean(Safe(_G.UnitHasVehicleUI, "player")) then return true end
	-- (dead or a ghost: every buff gone with you, nothing to tell until you are back)
	if Clean(Safe(_G.UnitIsDeadOrGhost, "player")) then return true end
	return false
end

-- The power bar the spark runs on, and its width (kept while it can be read).
local function PowerBar()
	local block = ns.UnitFramesPlayerBlock
	if block and block.lower and ns.UnitFramesLines and ns.UnitFramesLines() then return block.lower, block.width end
	local walk = ns.UnitFramesWalk
	local bar = walk and walk(_G.PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
	if type(bar) ~= "table" or IsSecret(bar) then return nil end
	local width = Clean(Safe(bar.GetWidth, bar))
	if type(width) == "number" and width > 0 then rawset(bar, "wandererWidth", width) end
	return bar, rawget(bar, "wandererWidth")
end

-- The druid's mana -----------------------------------------------------------------------------------------------

local function ThirdShown()
	if not ThirdWanted() or Class() ~= "DRUID" or Hidden() then return false end
	local token = PowerToken()
	return token == "RAGE" or token == "ENERGY"
end

-- Its height in your composition (UnitFrames.lua's Arrange makes room for it), 0 when none.
function ns.ClassAssistThird()
	if not ThirdShown() then return 0 end
	return THIRD_SIZES[Thickness()] or THIRD_SIZES.medium
end

local function FillThird()
	if not third then return end
	local kind = PowerIndex("Mana", 0)
	local most, value = Safe(UnitPowerMax, "player", kind), Safe(UnitPower, "player", kind)
	-- (passed on as they come, hidden or not; nothing read)
	pcall(third.SetMinMaxValues, third, 0, most)
	pcall(third.SetValue, third, value)
end

local function PlaceThird()
	if not third then return end
	if not ThirdShown() then
		third:Hide()
		return
	end
	local look = ns.db.unitFrames
	local r, g, b = MANA[1], MANA[2], MANA[3]
	if ns.UnitFramesPowerColor then
		local cr, cg, cb = ns.UnitFramesPowerColor("MANA", look)
		if type(cr) == "number" then r, g, b = cr, cg, cb end
	end
	local block = ns.UnitFramesPlayerBlock
	third:ClearAllPoints()
	local lines = block and ns.UnitFramesLines and ns.UnitFramesLines()
	-- (your composition without room for it: the power hidden for now)
	if lines and not (block.lower and (block.third or 0) > 0) then
		third:Hide()
		return
	end
	if lines then
		-- (right under the power, its top on the block's own bottom line)
		local px = block.px or 1
		third:SetFrameLevel(block.lower:GetFrameLevel())
		third:SetPoint("TOPLEFT", block.lower, "BOTTOMLEFT", 0, -px)
		third:SetPoint("TOPRIGHT", block.lower, "BOTTOMRIGHT", 0, -px)
		third:SetHeight(block.third)
		-- (dressed again only when the look changed)
		local dress = ("lines %s %s %s %.3f %.3f %.3f"):format(tostring(look.texture), tostring(look.ground), tostring(look.art), r, g, b)
		if third.dressed ~= dress then
			third.dressed = dress
			ns.Skin.UnitBar(third, look, r, g, b, true, nil)
		elseif third.wandererLine then
			third.wandererLine.Place(look.art == "lines")
		end
	else
		local bar = PowerBar()
		-- (the game's frame already showing your mana in this form: one bar, not two)
		local own = _G.AlternatePowerBar or _G.PlayerFrameAlternateManaBar
		local gameShows = type(own) == "table" and not IsSecret(own) and Clean(Safe(own.IsShown, own))
		if not bar or gameShows then
			third:Hide()
			return
		end
		third:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
		third:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
		third:SetHeight(THIRD_SIZES[Thickness()] or THIRD_SIZES.medium)
		local dress = ("game %s %s %.3f %.3f %.3f"):format(tostring(look.texture), tostring(look.ground), r, g, b)
		if third.dressed ~= dress then
			third.dressed = dress
			ns.Skin.UnitBar(third, look, r, g, b, true, false)
		end
	end
	FillThird()
	third:Show()
end

-- The sparks -------------------------------------------------------------------------------------------------------
-- Energy comes every 2 seconds on the server's own beat: a gain read clearly sets the beat, and the beat holds
-- when the figures are hidden. A gain off the beat (a talent, a potion) moves it only when a second one agrees.
-- Mana: a spell paid in mana starts five seconds without regeneration (the spark crosses the bar), then the
-- regeneration's own 2-second beat (set the same way) while the mana is not full.

local beats = { energy = {}, mana = {} } -- kind -> { at (the beat), off (a gain off it), last (the last clear figure) }
local spentAt -- a mana spell, last

local function Gain(kind, now)
	local beat = beats[kind]
	if not beat.at then
		beat.at = now
		return
	end
	local phase = (now - beat.at) % TICK
	if phase < 0.3 or phase > TICK - 0.3 then
		beat.at, beat.off = now, nil
		return
	end
	local off = beat.off
	if off then
		local agree = (now - off) % TICK
		if agree < 0.3 or agree > TICK - 0.3 then beat.at, beat.off = now, nil return end
	end
	beat.off = now
end
ns.ClassAssistBeats = beats -- (tests)

-- A power figure changed: a clear rise is a gain (on the beat or not), a clear fall of mana a spell paid.
local POWERS = { energy = "ENERGY", mana = "MANA" }
local function PowerChanged(token)
	local now = GetTime()
	for kind, name in pairs(POWERS) do
		if token == nil or token == name then
			local index = PowerIndex(kind == "energy" and "Energy" or "Mana", kind == "energy" and 3 or 0)
			local value = Clean(Safe(UnitPower, "player", index))
			local beat = beats[kind]
			if type(value) == "number" then
				if beat.last and value > beat.last and (kind ~= "mana" or not spentAt or now - spentAt >= FIVE) then Gain(kind, now) end
				if kind == "mana" and beat.last and value < beat.last then spentAt = now end
				beat.last = value
			end
		end
	end
end

-- A spell of yours: paid in mana, the five seconds start.
local function CostsMana(spell)
	local get = C_Spell and C_Spell.GetSpellPowerCost or _G.GetSpellPowerCost
	local costs = get and Safe(get, spell)
	if type(costs) ~= "table" or IsSecret(costs) then return false end
	for _, cost in ipairs(costs) do
		if type(cost) == "table" and not IsSecret(cost) and Clean(cost.type) == PowerIndex("Mana", 0) then
			local amount = Clean(cost.cost) or Clean(cost.minCost)
			if type(amount) == "number" and amount > 0 then return true end
		end
	end
	return false
end

-- Where the spark is now on its bar (0 to 1), or nil: not shown.
local function SparkAt(now)
	local token = PowerToken()
	local class = Class()
	if token == "ENERGY" and (class == "ROGUE" or class == "DRUID") then
		local beat = beats.energy
		if not beat.at then return nil end
		local value, most = Clean(Safe(UnitPower, "player", PowerIndex("Energy", 3))), Clean(Safe(UnitPowerMax, "player", PowerIndex("Energy", 3)))
		if type(value) == "number" and type(most) == "number" and value >= most then return nil end
		return ((now - beat.at) % TICK) / TICK
	end
	if token == "MANA" then
		if spentAt and now - spentAt < FIVE then return (now - spentAt) / FIVE end
		local beat = beats.mana
		if not beat.at then return nil end
		local value, most = Clean(Safe(UnitPower, "player", PowerIndex("Mana", 0))), Clean(Safe(UnitPowerMax, "player", PowerIndex("Mana", 0)))
		if type(value) == "number" and type(most) == "number" and value >= most then return nil end
		return ((now - beat.at) % TICK) / TICK
	end
	return nil
end
ns.ClassAssistSparkAt = SparkAt -- (tests)

local function MoveSpark()
	if not sparkFrame then return end
	local bar, width = PowerBar()
	local at = SparksOn() and not Hidden() and bar and type(width) == "number" and width > 0 and SparkAt(GetTime()) or nil
	if not at then
		sparkFrame.spark:Hide()
		return
	end
	local height = rawget(bar, "wandererHeight") or Clean(Safe(bar.GetHeight, bar)) or 8
	-- (our frame on its bar: a frame placed nowhere draws nothing; set again only when the bar changed)
	if sparkFrame.on ~= bar then
		sparkFrame.on = bar
		sparkFrame:ClearAllPoints()
		sparkFrame:SetAllPoints(bar)
	end
	sparkFrame:SetFrameLevel(Clean(Safe(bar.GetFrameLevel, bar)) and bar:GetFrameLevel() + 4 or 10)
	sparkFrame.spark:ClearAllPoints()
	sparkFrame.spark:SetPoint("CENTER", bar, "LEFT", math.floor(width * at + 0.5), 0)
	sparkFrame.spark:SetSize(8, height * 2.2)
	sparkFrame.spark:Show()
end

local function SyncSpark()
	if not sparkFrame then return end
	if SparksOn() and not Hidden() and Class() ~= "WARRIOR" then
		sparkFrame:Show()
		-- (one function, set once: SyncSpark runs every second)
		if not sparkFrame:GetScript("OnUpdate") then sparkFrame:SetScript("OnUpdate", MoveSpark) end
		MoveSpark()
	else
		sparkFrame:SetScript("OnUpdate", nil)
		sparkFrame:Hide()
	end
end

-- The pet's mood --------------------------------------------------------------------------------------------------

local MOOD_ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }
local MOOD_COORDS = { { 0.375, 0.5625, 0, 0.359375 }, { 0.1875, 0.375, 0, 0.359375 }, { 0, 0.1875, 0, 0.359375 } }

local function DrawMood()
	if not petIcon then return end
	local pet = _G.PetFrame
	local level = On() and Class() == "HUNTER" and not Hidden() and Mood() or nil
	local game = _G.PetFrameHappiness
	if not level or type(pet) ~= "table" or not Clean(Safe(pet.IsShown, pet)) then
		petIcon:Hide()
		petIcon.item = nil
		if type(game) == "table" and ns.UnitFramesShowArt then ns.UnitFramesShowArt(game) end
		return
	end
	local fight = Fighting()
	local item = { key = "mood", state = level < 3 and "ending" or "ok", title = L.ASSIST_PET_MOOD,
		mood = level == 3 and L.ASSIST_PET_HAPPY or level == 2 and L.ASSIST_PET_CONTENT or L.ASSIST_PET_UNHAPPY }
	-- (out of a fight, an unhappy pet's icon greyed: to feed)
	if not fight and level == 1 then item.state = "missing" end
	local size = math.max(16, (ICON_SIZES[Thickness()] or ICON_SIZES.medium) - 4)
	local px = Pixel(pet)
	Draw(petIcon, item, size, px)
	if U.HasAtlas and U.HasAtlas(MOOD_ATLAS[level]) then
		petIcon.art:SetAtlas(MOOD_ATLAS[level])
	else
		petIcon.art:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
		petIcon.art:SetTexCoord(unpack(MOOD_COORDS[level]))
	end
	petIcon:ClearAllPoints()
	local portrait = ns.UnitFramePortrait and ns.UnitFramePortrait(pet)
	if portrait then
		petIcon:SetPoint("RIGHT", portrait, "LEFT", -GAP, 0)
	else
		petIcon:SetPoint("RIGHT", pet, "LEFT", -GAP, 0)
	end
	-- (the game's own small mood icon unseen meanwhile: one, not two)
	if type(game) == "table" and ns.UnitFramesHideArt then ns.UnitFramesHideArt(game) end
end

-- Everything drawn again ----------------------------------------------------------------------------------------

-- The third bar wanted now and the room your composition made for it differ (out of a vehicle, Edit Mode or
-- death, which no restyle of the frames follows): your composition arranged again, once per change.
local asked
local function AskRoom()
	local block = ns.UnitFramesPlayerBlock
	if not (block and block.lower and ns.UnitFramesLines and ns.UnitFramesLines() and ns.UnitFramesSoon) then return end
	local wanted = ns.ClassAssistThird()
	if wanted == (block.third or 0) then
		asked = nil
	elseif asked ~= wanted then
		asked = wanted
		ns.UnitFramesSoon()
	end
end

local shown = {} -- the items drawn last (tests, the dump)
ns.ClassAssistShown = function() return shown end

local function Update()
	if not On() then
		if row then row:Hide() end
		if third then third:Hide() end
		if petIcon then
			petIcon:Hide()
			if type(_G.PetFrameHappiness) == "table" and ns.UnitFramesShowArt then ns.UnitFramesShowArt(_G.PetFrameHappiness) end
		end
		wipe(shown)
		SyncSpark()
		return
	end
	if not Build() then return end
	Place()
	PlaceThird()
	AskRoom()
	DrawMood()
	SyncSpark()
	wipe(shown)
	if Hidden() then
		row:Hide()
		return
	end
	local list = Collect()
	local size = ICON_SIZES[Thickness()] or ICON_SIZES.medium
	local px = Pixel(row)
	for index, icon in ipairs(pool) do
		local item = list[index]
		if item then
			Draw(icon, item, size, px)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", row, "TOPLEFT", (index - 1) * (size + GAP), 0)
			shown[index] = item
		else
			icon.item = nil
			icon:Hide()
		end
	end
	row:SetSize(math.max(1, #list * (size + GAP) - GAP), size)
	row:SetShown(#list > 0)
end
ns.ClassAssistUpdate = Update -- (tests)

local Soon = U.Debounce(0, function() Update() end)

-- Your composition arranged again (UnitFrames.lua): placed again at once.
function ns.ClassAssistArranged()
	if not row then return end
	Place()
	PlaceThird()
end

function ns.RefreshClassAssist()
	Update()
	-- (the third bar comes or goes: your composition arranged again)
	if ns.UnitFramesSoon and ns.UnitFramesOn and ns.UnitFramesOn() then ns.UnitFramesSoon() end
end

-- Diagnostic (/wanderer classe dump) --------------------------------------------------------------------------------
-- What every reading answers for your class, written into the account's saved data (WandererDB.classDump,
-- replaced each time; read after a /reload): now, then every 2 seconds for 40 seconds (a fight entered meanwhile
-- is caught). A hidden value is said "<secret>". Read only.

local DUMP_FOR, DUMP_EVERY = 40, 2

local function Word(value)
	if IsSecret(value) then return "<secret>" end
	if value == nil then return "nil" end
	if type(value) == "number" then return (("%.3f"):format(value):gsub("%.?0+$", "")) end
	if type(value) == "table" then return "<table>" end
	return tostring(value)
end

local function Joined(...)
	local out = {}
	for index = 1, select("#", ...) do out[#out + 1] = Word((select(index, ...))) end
	return table.concat(out, ", ")
end

local function Sample(lines, label)
	local function Line(text) lines[#lines + 1] = text end
	local now = GetTime()
	Line(("== %s t=%s combat=%s lockdown=%s class=%s"):format(label, Word(now), Word(Fighting()), Word(Safe(InCombatLockdown)), Word(Class())))
	local kind, token = Safe(UnitPowerType, "player")
	Line("power: type=" .. Joined(kind, token) .. " value/max=" .. Joined(Safe(UnitPower, "player"), Safe(UnitPowerMax, "player"))
		.. " mana=" .. Joined(Safe(UnitPower, "player", PowerIndex("Mana", 0)), Safe(UnitPowerMax, "player", PowerIndex("Mana", 0)))
		.. " energy=" .. Joined(Safe(UnitPower, "player", PowerIndex("Energy", 3))))
	Line("form: index=" .. Joined(Safe(_G.GetShapeshiftForm)) .. " id=" .. Joined(Safe(_G.GetShapeshiftFormID)))
	local index = Clean(Safe(_G.GetShapeshiftForm))
	if type(index) == "number" and index > 0 then Line("form info: " .. Joined(Safe(_G.GetShapeshiftFormInfo, index))) end
	Line("beats: energy=" .. Joined(beats.energy.at, beats.energy.last) .. " mana=" .. Joined(beats.mana.at, beats.mana.last) .. " spent=" .. Word(spentAt))
	-- Auras: the whole list as the game gives it.
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	for slot = 1, 40 do
		local aura = get and Safe(get, "player", slot, "HELPFUL")
		if not IsSecret(aura) and aura == nil then
			Line(("aura %d: nil (end)"):format(slot))
			break
		end
		if IsSecret(aura) or type(aura) ~= "table" then
			Line(("aura %d: %s"):format(slot, Word(aura)))
		else
			Line(("aura %d: spell=%s name=%s instance=%s icon=%s expires=%s duration=%s count=%s source=%s"):format(slot, Word(aura.spellId),
				Word(aura.name), Word(aura.auraInstanceID), Word(aura.icon), Word(aura.expirationTime), Word(aura.duration),
				Word(aura.applications), Word(aura.sourceUnit)))
		end
	end
	local found, readable = Auras()
	Line("auras readable=" .. Word(readable))
	for family, info in pairs(found) do
		local object = info.instance and C_UnitAuras and C_UnitAuras.GetAuraDuration and Safe(C_UnitAuras.GetAuraDuration, "player", info.instance)
		local remaining
		if not IsSecret(object) and object ~= nil then remaining = Safe(function() return object:GetRemainingDuration() end) end
		Line(("family %s: instance=%s expires=%s duration=%s hidden=%s durationObject=%s remaining=%s"):format(family, Word(info.instance),
			Word(info.expires), Word(info.duration), Word(info.hidden), type(object), Word(remaining)))
	end
	for family, ids in pairs(FAMILIES) do
		local known = Known(ids)
		if known then
			local byId = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and Safe(C_UnitAuras.GetPlayerAuraBySpellID, known)
			Line(("known %s: rank=%s name=%s byId=%s"):format(family, Word(known), Word(SpellName(known)), IsSecret(byId) and "<secret>" or type(byId)))
		end
	end
	-- Totems, weapons, items, ammo, the pet.
	for slot = 1, 4 do
		local object = _G.GetTotemDuration and Safe(_G.GetTotemDuration, slot)
		Line(("totem %d: %s left=%s durationObject=%s"):format(slot, Joined(Safe(_G.GetTotemInfo, slot)), Word(Safe(_G.GetTotemTimeLeft, slot)),
			type(object)))
	end
	Line("GetWeaponEnchantInfo: " .. Joined(Safe(_G.GetWeaponEnchantInfo)))
	for which = 1, 2 do
		local slot = WeaponSlot(which)
		local list = slot ~= nil and C_Item and C_Item.GetWeaponEnchantInfo and Safe(C_Item.GetWeaponEnchantInfo, slot)
		local text = "slot=" .. Word(slot)
		if type(list) == "table" and not IsSecret(list) then
			for _, each in pairs(list) do
				if type(each) == "table" and not IsSecret(each) then
					text = text .. (" | has=%s left=%s charges=%s type=%s icon=%s"):format(Word(each.hasEnchant), Word(each.timeLeft), Word(each.charges),
						Word(each.enchantType), Word(each.enchantIconID))
				end
			end
		else
			text = text .. " list=" .. Word(list)
		end
		Line(("C_Item.GetWeaponEnchantInfo hand %d: %s weapon=%s reading=%s"):format(which, text,
			Word(Safe(GetInventoryItemID, "player", which == 1 and 16 or 17)), Joined(Enchant(which))))
	end
	Line("ammo slot: id=" .. Word(Safe(GetInventoryItemID, "player", 0)) .. " count=" .. Word(Safe(_G.GetInventoryItemCount, "player", 0))
		.. " ranged=" .. Word(Safe(GetInventoryItemID, "player", 18)) .. " reading=" .. Joined(Ammo()))
	for key, list in pairs(ITEMS) do Line(("items %s: %s"):format(key, Joined(Count(list)))) end
	Line("pet: HasPetUI=" .. Joined(Safe(_G.HasPetUI)) .. " _G.C_PetInfo=" .. Joined(_G.C_PetInfo and _G.C_PetInfo.GetPetHappiness and Safe(_G.C_PetInfo.GetPetHappiness))
		.. " GetPetHappiness=" .. Joined(_G.GetPetHappiness and Safe(_G.GetPetHappiness)))
	local stoneNow = ReadSoulstone()
	if stoneNow then Line("soulstone: " .. Joined(stoneNow.unit, stoneNow.instance, stoneNow.expires, stoneNow.duration)) end
	local list = Collect()
	for position, item in ipairs(list) do
		Line(("shown %d: %s state=%s count=%s expires=%s"):format(position, item.key, item.state, Word(item.count), Word(item.expires)))
	end
	-- (the client's pieces the hidden readings lean on, and the game's own pieces under its frame)
	local cast, alt = _G.PlayerCastingBarFrame, _G.AlternatePowerBar or _G.PlayerFrameAlternateManaBar
	Line("apis: alphaFromBoolean=" .. tostring(BoolAlpha()) .. " displayCount=" .. type(C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount)
		.. " castAttached=" .. Word(type(cast) == "table" and (rawget(cast, "attachedToPlayerFrame") or Safe(cast.IsAttachedToPlayerFrame, cast)) or nil)
		.. " altManaShown=" .. Word(type(alt) == "table" and Safe(alt.IsShown, alt) or nil))
	local bar, width = PowerBar()
	Line("spark: bar=" .. tostring(bar ~= nil) .. " width=" .. Word(width) .. " at=" .. Word(SparkAt(now)) .. " third=" .. Word(ns.ClassAssistThird()))
end

function ns.DumpClassAssist()
	if not ns.root then return false end
	local lines = {}
	ns.root.classDump = lines
	Sample(lines, "start")
	local ticks = 0
	local ticker
	ticker = C_Timer.NewTicker(DUMP_EVERY, function()
		ticks = ticks + 1
		local ok, problem = pcall(Sample, lines, "sample " .. ticks)
		if not ok then lines[#lines + 1] = "error: " .. tostring(problem) end
		if ticks * DUMP_EVERY >= DUMP_FOR then
			if ticker and ticker.Cancel then ticker:Cancel() end
			ns.Print(L.ASSIST_DUMP_DONE)
		end
	end)
	ns.Print(L.ASSIST_DUMP_START:format(DUMP_FOR))
	return true
end

-- Events ---------------------------------------------------------------------------------------------------------

local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_AURA", "UNIT_INVENTORY_CHANGED",
	"BAG_UPDATE_DELAYED", "PLAYER_TOTEM_UPDATE", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "UNIT_PET", "UNIT_HAPPINESS",
	"PET_UI_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "WEAPON_ENCHANT_CHANGED",
	"PLAYER_EQUIPMENT_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED",
	"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "EDIT_MODE_LAYOUTS_UPDATED" }

function ns.InitClassAssist()
	local frame = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
	frame:SetScript("OnEvent", function(_, event, unit, ...)
		if not On() then
			if event == "PLAYER_ENTERING_WORLD" then Update() end
			return
		end
		if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
			if Clean(unit) ~= "player" then return end
			PowerChanged(Clean((...)))
			if third and third:IsShown() then FillThird() end
			return
		end
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if Clean(unit) ~= "player" then return end
			local _, spell = ...
			spell = Clean(spell)
			if spell then
				local family = BY_SPELL[spell]
				if family then
					pending[family] = GetTime()
					icons[family] = icons[family] or SpellIcon(spell)
				end
				if CostsMana(spell) then spentAt = GetTime() end
			end
			return Soon()
		end
		if event == "UNIT_AURA" then
			if Clean(unit) ~= "player" then
				-- (the one carrying your soulstone: its time drawn again; the others wait for the next look)
				if stone and Clean(unit) == stone.unit then Soon() end
				return
			end
			AuraChanged((...))
		end
		if event == "SPELLS_CHANGED" then byName = nil end
		Soon()
		-- (a form changed: the power's figures come a moment later)
		if event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_DISPLAYPOWER" then C_Timer.After(0.5, Soon) end
	end)
	-- (the times shown move on: ending states, a weapon's enchant read again, once a second)
	C_Timer.NewTicker(1, function() if On() then Update() end end)
	Update()
end
