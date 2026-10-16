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
-- The game's grammar codes, as its own frames render them: "|2 Name" is the
-- French "de Name" ("d'Name" before a vowel), as in "Familier |2 Vixi".
local function StartsWithVowel(word)
	if word:find("^[AEIOUYaeiouy]") then return true end
	-- An accented capital or small vowel (UTF-8 À to Ü, à to ü).
	local first, second = word:byte(1, 2)
	return first == 195 and second ~= nil and ((second >= 128 and second <= 156) or (second >= 160 and second <= 188))
		and second ~= 135 and second ~= 167 -- never Ç or ç
end

function Util.Grammar(text)
	if type(text) ~= "string" or Util.IsSecret(text) or not text:find("|2", 1, true) then return text end
	return (text:gsub("|2%s*(%S+)", function(word)
		return (StartsWithVowel(word) and "d'" or "de ") .. word
	end))
end

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
	-- The whole line, even when the game has already laid it out narrower.
	if method == "GetStringWidth" and fontString.GetUnboundedStringWidth then method = "GetUnboundedStringWidth" end
	local value = Util.Clean(Util.Safe(fontString[method], fontString))
	if not value or value <= 0 then return fallback end
	return value
end

-- The nameplate standing over a unit, or nil; the second value says why
-- ("ok", "none", "forbidden", "hidden", "no-api") for /wanderer debug. Some
-- games give the plate only through its own unit name: then every plate is
-- looked at.
-- The unit a nameplate shows: some games leave the plate's own token empty
-- and keep it only on the frame drawn inside.
function Util.PlateUnit(plate)
	return plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)) or nil
end

function Util.NameplateFor(unit)
	local plates = C_NamePlate
	if not plates then return nil, "no-api" end
	local plate = plates.GetNamePlateForUnit and Util.Safe(plates.GetNamePlateForUnit, unit)
	if type(plate) ~= "table" then
		plate = nil
		for _, candidate in ipairs(Util.Safe(plates.GetNamePlates) or {}) do
			if not (candidate.IsForbidden and candidate:IsForbidden()) then
				local token = Util.PlateUnit(candidate)
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
-- True when the mouse is over a frame (the game's own method; the old global
-- MouseIsOver is gone from some clients).
function Util.IsMouseOver(frame)
	if not frame then return false end
	if frame.IsMouseOver then
		local ok, over = pcall(frame.IsMouseOver, frame)
		return ok and over and true or false
	end
	return MouseIsOver ~= nil and MouseIsOver(frame) and true or false
end

function Util.MouseFocus()
	local now = GetTime()
	if now ~= focusTime then
		focusTime = now
		if GetMouseFoci then
			local foci = Util.Safe(GetMouseFoci)
			focus = foci and foci[1] or nil
		else
			focus = GetMouseFocus and Util.Safe(GetMouseFocus) or nil
		end
	end
	return focus
end

-- A thin status bar on a dark ground (health, power).
function Util.NewBar(parent, height, name)
	local bar = CreateFrame("StatusBar", name, parent)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetHeight(height)
	local ground = bar:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.6)
	bar:Hide()
	return bar
end

-- A unit's power (mana, rage, energy, focus) in a bar, in the game's colors.
-- Status bars take protected values; false when the unit has none.
local POWER_FALLBACK = { r = 0, g = 0.55, b = 1 }
function Util.FillPowerBar(bar, unit)
	local maximum = Util.Safe(UnitPowerMax, unit)
	if not Util.IsSecret(maximum) and (maximum == nil or maximum <= 0) then return false end
	local power = Util.Safe(UnitPower, unit)
	if not Util.IsSecret(power) and power == nil then return false end
	if not (pcall(bar.SetMinMaxValues, bar, 0, maximum) and pcall(bar.SetValue, bar, power)) then return false end
	local kind, token = Util.Safe(UnitPowerType, unit)
	local colors = PowerBarColor or {}
	local color = colors[Util.Clean(token) or ""] or colors[Util.Clean(kind) or -1] or POWER_FALLBACK
	bar:SetStatusBarColor(color.r or 0, color.g or 0.55, color.b or 1)
	return true
end

-- Between the parts of a line ("Mage  ·  Level 30").
Util.SEPARATOR = "  |cff808080·|r  "

-- What a merchant pays for an item (nil while the game has not loaded it).
function Util.SellPrice(link)
	if not link then return end
	return Util.Clean((select(11, Util.Safe(C_Item and C_Item.GetItemInfo or GetItemInfo, link))))
end

-- A sound of the game, by its SOUNDKIT name or number; silent when missing.
function Util.PlaySound(sound, channel)
	if type(sound) == "string" then sound = SOUNDKIT and SOUNDKIT[sound] end
	if sound and PlaySound then pcall(PlaySound, sound, channel) end
end

-- "label.scale" -> "label", "scale" (nil for a setting at the top).
function Util.SplitPath(path)
	return path:match("^(%w+)%.(%w+)$")
end

-- A message of the game ("%s dies, you gain %d experience.") as a pattern that
-- reads its values back, in their order (kinds: "s" or "d" for each). Open: it
-- may go on after (else the whole message).
local SLOT = string.char(1)
function Util.FormatPattern(format, open)
	if type(format) ~= "string" then return end
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
	return "^" .. text .. (open and "" or "$"), kinds
end

-- True when the mouse is over the 3D world rather than the interface.
function Util.IsOverWorld()
	if not (GetMouseFoci or GetMouseFocus) then return false end
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

-- Your bags' container ids: the backpack, the bags, the reagent bag where the game has one.
function Util.BagIDs()
	local list = {}
	local last = NUM_BAG_SLOTS or 4
	for bag = 0, last do list[#list + 1] = bag end
	local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
	local slots = reagent and C_Container and Util.Clean(Util.Safe(C_Container.GetContainerNumSlots, reagent)) or 0
	if reagent and reagent > last and slots > 0 then list[#list + 1] = reagent end
	return list
end

-- The text box of one of the game's dialogs (its name changed across versions).
function Util.EditBoxOf(dialog)
	return dialog.EditBox or dialog.editBox
end

-- Capitals in every language: the game's upper() changes only a to z, so the
-- accented letters (é, ê, ç...) and the Cyrillic ones stay small without this.
local UPPER = { ["\197\147"] = "\197\146", ["\209\145"] = "\208\129" } -- œ, ё
for byte = 0xA0, 0xBE do
	if byte ~= 0xB7 then UPPER["\195" .. string.char(byte)] = "\195" .. string.char(byte - 0x20) end -- à..þ (not ÷)
end
for byte = 0xB0, 0xBF do UPPER["\208" .. string.char(byte)] = "\208" .. string.char(byte - 0x20) end -- а..п
for byte = 0x80, 0x8F do UPPER["\209" .. string.char(byte)] = "\208" .. string.char(byte + 0x20) end -- р..я
function Util.Upper(text)
	return (tostring(text):upper():gsub("[\195\197\208\209][\128-\191]", UPPER))
end

-- Items ------------------------------------------------------------------------------------------------
-- What the game knows of an item (by its id): nil until it has it (Util.LoadItem asks for it; the game
-- then sends GET_ITEM_INFO_RECEIVED).

local function ItemAPI(name) return C_Item and C_Item[name] or _G[name] end

function Util.ItemName(id) return Util.Clean(Util.Safe(ItemAPI("GetItemNameByID") or ItemAPI("GetItemInfo"), id)) end
function Util.ItemIcon(id) return Util.Clean(Util.Safe(ItemAPI("GetItemIconByID"), id)) end
function Util.ItemQuality(id) return Util.Clean(Util.Safe(ItemAPI("GetItemQualityByID"), id)) end
-- How many you carry (bank: the bank's too).
function Util.ItemCount(id, bank) return Util.Clean(Util.Safe(ItemAPI("GetItemCount"), id, bank and true or nil)) or 0 end
-- Its item level and the level it asks (nil until the game has it).
function Util.ItemLevels(id)
	local _, _, _, level, minimum = Util.Safe(ItemAPI("GetItemInfo"), id)
	return Util.Clean(level), Util.Clean(minimum)
end
-- What the game knows at once of an item (id, link or name), without asking the server: the values of
-- GetItemInfoInstant (id, type, subtype, equip slot, icon, class id, subclass id).
function Util.ItemInstant(item)
	if item == nil then return nil end
	return Util.Safe(ItemAPI("GetItemInfoInstant"), item)
end

-- An item's stats (the game's names: ITEM_MOD_STRENGTH_SHORT...): a table, empty when the game has none yet.
function Util.ItemStats(link)
	local stats = link and Util.Safe(ItemAPI("GetItemStats"), link)
	return type(stats) == "table" and stats or {}
end

-- How many make a stack of it (1: it does not stack).
function Util.ItemMaxStack(id) return Util.Clean(Util.Safe(ItemAPI("GetItemMaxStackSizeByID"), id)) or 1 end

-- Its name, link and quality at once.
function Util.ItemInfo(id)
	local name, link, quality = Util.Safe(ItemAPI("GetItemInfo"), id)
	return Util.Clean(name), Util.Clean(link), Util.Clean(quality)
end

function Util.LoadItem(id)
	if C_Item and C_Item.RequestLoadItemDataByID then Util.Safe(C_Item.RequestLoadItemDataByID, id) end
end

-- An area's name in your language (a zone, a dungeon), without what the game adds in parentheses.
function Util.AreaName(area)
	local name = area and Util.Clean(Util.Safe(C_Map and C_Map.GetAreaInfo, area))
	return name and (name:gsub("%s*%b()", "")) or nil
end

-- A place's name made comparable: lower case, trimmed, without what the game adds in parentheses ("Les Paluns
-- (Wetlands)" is "les paluns").
function Util.PlainName(name)
	if type(name) ~= "string" then return nil end
	return (name:gsub("%s*%b()", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower())
end

-- From a link: the item's id, its name.
function Util.ItemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end
function Util.LinkName(link) return type(link) == "string" and link:match("%[(.-)%]") or nil end

-- A quality's color (r, g, b).
function Util.QualityColor(quality)
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b = Util.Safe(C_Item.GetItemQualityColor, quality)
		if r then return r, g, b end
	end
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
	if color then return color.r, color.g, color.b end
	return 1, 1, 1
end

-- Words in a color.
function Util.Colorize(text, r, g, b) return Util.ColorCode(r, g, b) .. tostring(text) .. "|r" end

-- How many you carry of how many are needed: "3/8", green once enough.
function Util.HaveNeed(have, need)
	local color = have >= need and "|cff66dd66" or "|cffb0a080"
	return color .. math.min(have, need) .. "/" .. need .. "|r"
end

-- Each item of your bags: fn(bag, slot, info) (info: the game's, its values cleaned when read).
function Util.EachBagItem(fn)
	local container = C_Container or {}
	for _, bag in ipairs(Util.BagIDs()) do
		for slot = 1, Util.Clean(Util.Safe(container.GetContainerNumSlots, bag)) or 0 do
			local info = Util.Safe(container.GetContainerItemInfo, bag, slot)
			if type(info) == "table" and Util.Clean(info.itemID) then fn(bag, slot, info) end
		end
	end
end

-- Time -------------------------------------------------------------------------------------------------

-- A function that runs fn once, a moment after the last time it was called (many calls at once: one run).
-- "3 hours": how long ago (seconds), in the game's words (a minute at least).
function Util.Ago(seconds)
	seconds = math.max(60, tonumber(seconds) or 0)
	if SecondsToTime then return SecondsToTime(seconds, true, true, 1) end
	return ("%d min"):format(math.floor(seconds / 60))
end

function Util.Debounce(delay, fn)
	local waiting = false
	return function()
		if waiting then return end
		waiting = true
		C_Timer.After(delay, function()
			waiting = false
			fn()
		end)
	end
end

-- The map ---------------------------------------------------------------------------------------------

-- The game's own pin on a map (x, y: 0 to 1), followed; false when it cannot.
function Util.Pin(map, x, y)
	if not (map and x and y and UiMapPoint and C_Map and C_Map.SetUserWaypoint) then return false end
	local point = Util.Safe(UiMapPoint.CreateFromCoordinates, map, x, y)
	if not point then return false end
	Util.Safe(C_Map.SetUserWaypoint, point)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then Util.Safe(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	return true
end

-- The game's windows -----------------------------------------------------------------------------------

-- One of the game's windows out of sight (still open: the game's own window under Wanderer's), then back
-- where the game had placed it (none of the game's placing called from here).
local OFF_SCREEN = -10000
local offPoints = setmetatable({}, { __mode = "k" })
function Util.HideOffScreen(frame, hidden)
	if not frame then return end
	if hidden then
		local _, _, _, x = frame:GetPoint(1)
		if x ~= OFF_SCREEN then
			local points = {}
			for index = 1, frame:GetNumPoints() do points[index] = { frame:GetPoint(index) } end
			offPoints[frame] = points
		end
		frame:SetAlpha(0)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", OFF_SCREEN, 0)
	elseif (frame:GetAlpha() or 1) < 1 then
		frame:SetAlpha(1)
		local points = offPoints[frame]
		if points and points[1] then
			frame:ClearAllPoints()
			for _, point in ipairs(points) do frame:SetPoint(point[1], point[2], point[3], point[4], point[5]) end
		end
		offPoints[frame] = nil
	end
end

-- A frame put out of sight by HideOffScreen (still shown for the game, not for you).
function Util.IsOffScreen(frame) return offPoints[frame] ~= nil end

-- A piece of a frame by its key (nil when it has none, or not a frame's table).
function Util.Part(frame, key)
	local part = type(frame) == "table" and frame[key]
	return type(part) == "table" and part or nil
end

-- A menu of the game's (MenuUtil) at a frame; false when the game has none.
function Util.Menu(owner, build)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
	MenuUtil.CreateContextMenu(owner, build)
	return true
end
