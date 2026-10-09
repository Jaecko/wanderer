local _, ns = ...
local L = ns.L

-- Your long blessings to cast again: an Arcane Intellect, a Mark of the Wild,
-- a Fortitude given (to yourself or your group) that fades, out of a fight,
-- comes back as a short notice with who lost it. Only what you cast and meant
-- to last (a few minutes or more); never during a fight (said after it); not
-- for someone dead or gone.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_EVERY = 3 -- seconds between two looks
local MIN_DURATION = 300 -- seconds: shorter ones are not blessings to keep up
local MAX_AURAS = 40

local watched = {} -- "guid:name" -> { name, icon, who, guid, self }
local since = 0

local function On()
	return ns.db and ns.db.enabled and ns.db.buffs.remind
end

-- You, and your group or raid.
local function Units()
	local list = { "player" }
	local raid = Clean(Safe(IsInRaid))
	local count = raid and 40 or 4
	for index = 1, count do
		local unit = (raid and "raid" or "party") .. index
		if Clean(Safe(UnitExists, unit)) and not Clean(Safe(UnitIsUnit, unit, "player")) then list[#list + 1] = unit end
	end
	return list
end

-- One of your auras on a unit: name, icon, duration (nil past the last).
local function Aura(unit, index)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local aura = Safe(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL|PLAYER")
		if type(aura) ~= "table" then return end
		return Clean(aura.name), Clean(aura.icon), Clean(aura.duration)
	end
	if UnitBuff then
		local name, icon, _, _, duration = Safe(UnitBuff, unit, index, "PLAYER")
		if not name then return end
		return Clean(name), Clean(icon), Clean(duration)
	end
end

local function Scan()
	if not On() then return wipe(watched) end
	if ns.inCombat or InCombatLockdown() then return end
	local seen, present = {}, {}
	for _, unit in ipairs(Units()) do
		local guid = Clean(Safe(UnitGUID, unit))
		local alive = guid and Clean(Safe(UnitIsConnected, unit)) ~= false and not Clean(Safe(UnitIsDeadOrGhost, unit))
		if alive then
			present[guid] = true
			for index = 1, MAX_AURAS do
				local name, icon, duration = Aura(unit, index)
				if not name then break end
				if duration and duration >= MIN_DURATION then
					local key = guid .. ":" .. name -- (its ranks share its name)
					seen[key] = true
					watched[key] = { name = name, icon = icon, guid = guid,
						who = Clean(Safe(UnitName, unit)) or "?", self = unit == "player" }
				end
			end
		end
	end
	-- Gone from someone still here and alive: to cast again.
	local faded, order = {}, {}
	for key, entry in pairs(watched) do
		if not seen[key] then
			watched[key] = nil
			if present[entry.guid] then
				if not faded[entry.name] then
					faded[entry.name] = { icon = entry.icon, who = {} }
					order[#order + 1] = entry.name
				end
				local list = faded[entry.name].who
				list[#list + 1] = entry.self and L.BUFF_YOU or entry.who
			end
		end
	end
	for _, name in ipairs(order) do
		local spell = faded[name]
		local icon = spell.icon and ("|T%s:16:16:0:0|t "):format(spell.icon) or ""
		if ns.Toast then ns.Toast(L.BUFF_FADED, icon .. L.BUFF_FADED_TEXT:format(name, table.concat(spell.who, ", "))) end
	end
end
ns.ScanBuffs = Scan -- (tests)

function ns.InitBuffs()
	local frame = CreateFrame("Frame")
	frame:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < CHECK_EVERY then return end
		since = 0
		Scan()
	end)
end
