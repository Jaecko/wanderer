local _, ns = ...

-- Helpers shared by every module. Since Midnight, some game values can be
-- "secret": they may be displayed but never compared or combined, so every
-- read goes through Clean before being used.

local Util = {}
ns.Util = Util

local issecretvalue = issecretvalue

function Util.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- The value when it is usable (present and not secret), nil otherwise.
function Util.Clean(value)
	if Util.IsSecret(value) or value == nil or value == "" then return nil end
	return value
end

local function Results(ok, ...)
	if ok then return ... end
end

-- Calls fn without letting an error escape; returns all its results.
function Util.Safe(fn, ...)
	if not fn then return end
	return Results(pcall(fn, ...))
end

-- Width or height of a font string, with a fallback when it is unknown or
-- protected (the size of a secret text can itself be secret).
function Util.Measure(fontString, method, fallback)
	local value = Util.Clean(Util.Safe(fontString[method], fontString))
	if not value or value <= 0 then return fallback end
	return value
end

-- The nameplate standing over a unit, or nil; the second value says why
-- ("ok", "none", "forbidden", "hidden", "no-api") for /wanderer debug. Some
-- games give the plate only through its own unit name: then every plate is
-- looked at.
function Util.NameplateFor(unit)
	local plates = C_NamePlate
	if not plates then return nil, "no-api" end
	local plate = plates.GetNamePlateForUnit and Util.Safe(plates.GetNamePlateForUnit, unit)
	if type(plate) ~= "table" then
		plate = nil
		for _, candidate in ipairs(Util.Safe(plates.GetNamePlates) or {}) do
			if not (candidate.IsForbidden and candidate:IsForbidden()) then
				local token = candidate.namePlateUnitToken or (candidate.UnitFrame and candidate.UnitFrame.unit)
				if token and Util.Clean(Util.Safe(UnitIsUnit, token, unit)) then
					plate = candidate
					break
				end
			end
		end
	end
	if not plate then return nil, "none" end
	if plate.IsForbidden and plate:IsForbidden() then return nil, "forbidden" end
	if not plate:IsShown() then return nil, "hidden" end
	return plate, "ok"
end

function Util.HasAtlas(atlas)
	return atlas and C_Texture and C_Texture.GetAtlasInfo and Util.Safe(C_Texture.GetAtlasInfo, atlas) ~= nil
end

-- Frame under the mouse. Several modules ask on every frame: it is looked up
-- once per frame (GetTime does not change within a frame).
local focusTime, focus
function Util.MouseFocus()
	local now = GetTime()
	if now ~= focusTime then
		focusTime = now
		local foci = GetMouseFoci and Util.Safe(GetMouseFoci)
		focus = foci and foci[1] or nil
	end
	return focus
end

-- True when the mouse is over the 3D world rather than the interface.
function Util.IsOverWorld()
	if not GetMouseFoci then return true end
	local current = Util.MouseFocus()
	return current == nil or current == WorldFrame
end

-- NPC id from a GUID: Creature-0-1234-0-12-NPCID-0000ABCDEF.
function Util.NpcID(guid)
	guid = Util.Clean(guid)
	return guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

-- Color escape code for text: |cffRRGGBB.
function Util.ColorCode(r, g, b)
	local function byte(v) return math.floor(v * 255 + 0.5) end
	return ("|cff%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

-- Tooltip data lines as { text, r, g, b, type }. With keepSecret, protected
-- lines are kept as { secret = true } so the line numbers stay right.
function Util.TooltipLines(dataLines, keepSecret)
	local lines = {}
	for _, line in ipairs(dataLines or {}) do
		local text = Util.Clean(line.leftText)
		if text then
			local color = line.leftColor
			local r, g, b
			if color and color.GetRGB then r, g, b = color:GetRGB() end
			lines[#lines + 1] = { text = text, r = r, g = g, b = b, type = line.type }
		elseif keepSecret then
			lines[#lines + 1] = { secret = true }
		end
	end
	return lines
end

-- Holding Shift keeps the hand: no automatic action this time (merchants,
-- quests, dialogues...).
function Util.IsSkipping()
	return IsShiftKeyDown ~= nil and IsShiftKeyDown() and true or false
end

-- Soft transitions: a value goes from where it is to where it is asked,
-- slowly at the start and at the end (smoothstep), so the eye catches the
-- change without being pulled by it. upTime and downTime are the seconds of a
-- full change (0 to 1); shorter changes take a share of it.
local TweenMixin = {}

function Util.Tween(value)
	return setmetatable({ value = value or 0 }, { __index = TweenMixin })
end

-- Moves toward target; returns the value now.
function TweenMixin:Step(target, elapsed, upTime, downTime)
	if self.to ~= target then
		self.from, self.to, self.t = self.value, target, 0
		local full = target > self.value and upTime or downTime
		self.duration = math.max(full * math.abs(target - self.value), 0.001)
	end
	if self.value == target then return target end
	self.t = math.min(self.duration, self.t + elapsed)
	local k = self.t / self.duration
	k = k * k * (3 - 2 * k)
	self.value = self.t >= self.duration and target or (self.from + (target - self.from) * k)
	return self.value
end

-- Jumps there at once (a value set from outside).
function TweenMixin:Set(value)
	self.value, self.to = value, nil
end

-- A character's whole name. WoW Forever lets a character have several names
-- ("Jæcko Druidæ"): UnitName then gives the first name, and the family name
-- where the realm usually is. The game is in that mode when this character's
-- own name has a second value (elsewhere, a player of your own realm has
-- none); then every player's second value is part of the name. The longest
-- form the game gives is kept (its record of the player included). A
-- protected name is returned as it is, never looked into.
local function IsOwnRealm(text)
	local realm = Util.Clean(Util.Safe(GetRealmName))
	local normalized = GetNormalizedRealmName and Util.Clean(Util.Safe(GetNormalizedRealmName))
	return text == realm or text == normalized
end

local multiNames -- nil: not known yet

local function MultiNames()
	if multiNames == nil then
		local _, second = Util.Safe(UnitName, "player")
		second = Util.Clean(second)
		if second ~= nil then multiNames = second ~= "" and not IsOwnRealm(second) end
	end
	return multiNames
end

function Util.FullName(unit)
	local first, second = Util.Safe(UnitName, unit)
	if Util.IsSecret(first) then return first end
	if not first then return nil end
	local best = first
	if Util.Clean(Util.Safe(UnitIsPlayer, unit)) and GetPlayerInfoByGUID then
		local guid = Util.Clean(Util.Safe(UnitGUID, unit))
		local recorded = guid and Util.Clean(select(6, Util.Safe(GetPlayerInfoByGUID, guid)))
		if recorded and #recorded > #best then best = recorded end
	end
	second = Util.Clean(second)
	local isPlayer = unit == "player" or Util.Clean(Util.Safe(UnitIsPlayer, unit))
	if isPlayer and MultiNames() and second and second ~= "" and not IsOwnRealm(second) then
		local joined = first .. " " .. second
		if #joined > #best then best = joined end
	end
	return best
end

-- Every name the game gives for this character, for /wanderer debug.
function Util.DebugNames()
	local values = { Util.Safe(UnitName, "player") }
	local guid = Util.Clean(Util.Safe(UnitGUID, "player"))
	local recorded = guid and GetPlayerInfoByGUID and select(6, Util.Safe(GetPlayerInfoByGUID, guid))
	local full = UnitFullName and { Util.Safe(UnitFullName, "player") } or {}
	local function list(t)
		local out = {}
		for i = 1, 4 do out[i] = tostring(t[i]) end
		return table.concat(out, " | ")
	end
	return ("UnitName: %s  ·  record: %s  ·  UnitFullName: %s  ·  kept: %s"):format(
		list(values), tostring(recorded), list(full), tostring(Util.FullName("player")))
end

-- Money as the game writes it, with coin icons ("-" for a loss).
function Util.Coins(copper)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	return sign .. (Util.Safe(C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString, copper)
		or Util.Safe(GetCoinTextureString, copper) or tostring(copper))
end

-- The text box of one of the game's dialogs (its name changed across versions).
function Util.EditBoxOf(dialog)
	return dialog.EditBox or dialog.editBox
end
