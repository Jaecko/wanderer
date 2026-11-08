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

-- The value when it is usable (present, not empty and not secret), nil otherwise.
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

-- A value copied all the way down (a table's tables too, never shared with the original).
function Util.Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, inner in pairs(value) do copy[key] = Util.Copy(inner) end
	return copy
end

-- The game's own window kept from some events while Wanderer shows them its way (the scenes, the reader), and
-- given them back: events (a list), owner(event) (the window that listens when nothing else is found),
-- isPart(frame) (a frame of that window: depending on the version of the game, a part listens instead).
-- taker:Take(true/false); taker:Relay(event, ...) shows one in the game's window after all (taker.relaying
-- meanwhile); taker.taken; taker.frames[event] (the frames that stopped listening).
function Util.EventTaker(events, owner, isPart)
	local taker = { taken = false, relaying = false, frames = {} }
	local function Listeners(event)
		local list = {}
		if GetFramesRegisteredForEvent then
			for _, frame in ipairs({ GetFramesRegisteredForEvent(event) }) do
				if type(frame) == "table" and isPart(frame) then list[#list + 1] = frame end
			end
		end
		local window = owner(event)
		if window and not list[1] and (not window.IsEventRegistered or window:IsEventRegistered(event)) then list[1] = window end
		return list
	end
	function taker:Take(take)
		take = take and true or false
		if take == self.taken then return end
		for _, event in ipairs(events) do
			if take then
				self.frames[event] = Listeners(event)
				for _, frame in ipairs(self.frames[event]) do frame:UnregisterEvent(event) end
			else
				for _, frame in ipairs(self.frames[event] or {}) do frame:RegisterEvent(event) end
				self.frames[event] = nil
			end
		end
		self.taken = take
	end
	function taker:Relay(event, ...)
		local frames = self.frames[event]
		if not (frames and frames[1]) then frames = { owner(event) } end
		self.relaying = true
		for _, frame in ipairs(frames) do
			local handler = frame and frame.GetScript and frame:GetScript("OnEvent")
			if handler then pcall(handler, frame, event, ...) end
		end
		self.relaying = false
	end
	return taker
end

-- An error caught so the rest goes on, still shown as the game shows any
-- (outside the game, where no handler exists, raised again).
function Util.Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if handler then return handler(err) end
	error(err, 0)
end

-- fn(...) run so an error in it lets the rest go on: true and its results, or false. The game's handler is
-- called right at the error, so what BugSack or the error frame shows keeps where it came from (its stack);
-- outside the game, where no handler exists, the error goes on up.
function Util.Try(fn, ...)
	local handler = geterrorhandler and geterrorhandler()
	if not handler then return true, fn(...) end
	return xpcall(fn, handler, ...)
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

-- The unit a nameplate shows: some games leave the plate's own token empty
-- and keep it only on the frame drawn inside.
function Util.PlateUnit(plate)
	return plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)) or nil
end

-- The nameplate standing over a unit, or nil; the second value says why
-- ("ok", "none", "forbidden", "hidden", "no-api") for /wanderer debug. Some
-- games give the plate only through its own unit name: then every plate is
-- looked at. Several modules ask on every frame: each unit's answer is kept for
-- the frame (GetTime does not change within one), forgotten when a plate comes or goes, or a unit changes.
local plateTime, plateFound, plateWhy = nil, {}, {}
local LookForPlate
function Util.NameplateFor(unit)
	local now = GetTime()
	if now ~= plateTime then
		plateTime = now
		wipe(plateFound)
		wipe(plateWhy)
	end
	if type(unit) ~= "string" then return LookForPlate(unit) end
	if plateWhy[unit] == nil then plateFound[unit], plateWhy[unit] = LookForPlate(unit) end
	return plateFound[unit] or nil, plateWhy[unit]
end
local platesChanged = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED",
	"PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
	pcall(platesChanged.RegisterEvent, platesChanged, event)
end
-- The nameplates shown: token -> true (one list for the trackers and the bars that draw on them).
Util.ShownPlates = {}
platesChanged:SetScript("OnEvent", function(_, event, unit)
	plateTime = nil
	if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		unit = Util.Clean(unit)
		if unit then Util.ShownPlates[unit] = event == "NAME_PLATE_UNIT_ADDED" or nil end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- (after a reload or a loading screen: the plates already shown, announced again or not)
		wipe(Util.ShownPlates)
		for _, plate in ipairs(C_NamePlate and Util.Safe(C_NamePlate.GetNamePlates) or {}) do
			if not (plate.IsForbidden and plate:IsForbidden()) then
				local token = Util.Clean(Util.PlateUnit(plate))
				if token then Util.ShownPlates[token] = true end
			end
		end
	end
end)

function LookForPlate(unit)
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

-- Frame under the mouse. Several modules ask on every frame: it is looked up
-- once per frame (GetTime does not change within a frame).
local focusTime, focus
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

-- A thin status bar on a dark ground (health, power). Each one known (bar -> its ground): they take the unit
-- frames' look while Wanderer's own bars follow it (UnitFrames.lua).
Util.ownBars = setmetatable({}, { __mode = "k" })
function Util.NewBar(parent, height, name)
	local bar = CreateFrame("StatusBar", name, parent)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetHeight(height)
	local ground = bar:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.6)
	Util.ownBars[bar] = ground
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
	-- (the unit frames' colours while Wanderer's own bars follow their look)
	local r, g, b
	if Util.OwnPowerColor then r, g, b = Util.OwnPowerColor(Util.Clean(token)) end
	if r then
		bar:SetStatusBarColor(r, g, b)
		return true
	end
	local colors = PowerBarColor or {}
	local color = colors[Util.Clean(token) or ""] or colors[Util.Clean(kind) or -1] or POWER_FALLBACK
	bar:SetStatusBarColor(color.r or 0, color.g or 0.55, color.b or 1)
	return true
end

-- Between the parts of a line ("Mage  ·  Level 30").
Util.SEPARATOR = "  |cff808080·|r  "

-- A chat line as plain text: links keep their visible words, colors, icons and atlases go.
function Util.PlainText(text)
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return text
end

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
		if second ~= nil then multiNames = not IsOwnRealm(second) end
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
	if isPlayer and MultiNames() and second and not IsOwnRealm(second) then
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
-- (color: { r, g, b } for the figures, beside the coins' own icons: a page's ink)
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function Util.Coins(copper, color)
	copper = tonumber(copper) or 0
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	if color then
		copper = math.floor(copper)
		local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
		local parts = {}
		local function Part(value, coin) parts[#parts + 1] = Util.Colorize(value, color[1], color[2], color[3]) .. COIN:format(coin) end
		if gold > 0 then Part(gold, "Gold") end
		if silver > 0 then Part(silver, "Silver") end
		if rest > 0 or not parts[1] then Part(rest, "Copper") end
		return sign .. table.concat(parts, " ")
	end
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

-- Searches: a text folded to small letters without accents, so "foret" finds "Forêt" and "ETE" finds "été".
-- Latin letters lose their marks (œ: oe, ß: ss), Cyrillic is made small (ё: е); other scripts stay as they are.
-- (one base per letter, from U+00C0 and from U+0100; "=": kept)
local LATIN1 = "a a a a a a ae c e e e e i i i i d n o o o o o = o u u u u y th ss "
	.. "a a a a a a ae c e e e e i i i i d n o o o o o = o u u u u y th y"
local LATIN_A = "a a a a a a c c c c c c c c d d d d e e e e e e e e e e g g g g g g g g h h h h i i i i i i i i i i "
	.. "ij ij j j k k k l l l l l l l l l l n n n n n n n n n o o o o o o oe oe r r r r r r s s s s s s s s "
	.. "t t t t t t u u u u u u u u u u u u w w y y y z z z z z z s"
local FOLD = { ["\208\129"] = "\208\181", ["\209\145"] = "\208\181" } -- Ё, ё: е
do
	local index = 0
	for base in LATIN1:gmatch("%S+") do
		if base ~= "=" then FOLD["\195" .. string.char(0x80 + index)] = base end
		index = index + 1
	end
	index = 0
	for base in LATIN_A:gmatch("%S+") do
		FOLD[string.char(0xC4 + math.floor(index / 64), 0x80 + index % 64)] = base
		index = index + 1
	end
	for byte = 0x90, 0x9F do FOLD["\208" .. string.char(byte)] = "\208" .. string.char(byte + 0x20) end -- А..П
	for byte = 0xA0, 0xAF do FOLD["\208" .. string.char(byte)] = "\209" .. string.char(byte - 0x20) end -- Р..Я
end
function Util.Fold(text)
	if text == nil then return "" end
	return (tostring(text):lower():gsub("[\195\196\197\208\209][\128-\191]", FOLD))
end

-- A search's words found in a text (accents and capitals aside; an empty search finds everything). folded:
-- the query is folded already (a list searched with one query: fold it once).
function Util.Matches(text, query, folded)
	if query == nil or query == "" then return true end
	if text == nil then return false end
	return Util.Fold(text):find(folded and query or Util.Fold(query), 1, true) ~= nil
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
-- A trainer's service: name, rank (nil for none), state ("header", "available", "unavailable", "used") and
-- whether a header is open. Clients differ on the order of the rank and the state: the state is found by its
-- word, the rank is the other string.
local TRAINER_STATES = { header = true, available = true, unavailable = true, used = true }
function Util.TrainerService(index)
	local a, b, c, d = Util.Safe(GetTrainerServiceInfo, index)
	local name = Util.Clean(a)
	b, c = Util.Clean(b), Util.Clean(c)
	if type(b) == "string" and TRAINER_STATES[b] then
		local sub = type(c) == "string" and not TRAINER_STATES[c] and c ~= "" and c or nil
		return name, sub, b, type(c) == "boolean" and c or Util.Clean(d)
	end
	if type(c) == "string" and TRAINER_STATES[c] then
		return name, (type(b) == "string" and b ~= "") and b or nil, c, Util.Clean(d)
	end
	return name, nil, nil, nil
end

-- What to learn of services ({ { index, cost } }): the cheapest first while your gold lasts. The chosen ones,
-- what they cost, what all of them would cost.
function Util.TrainerPlan(services)
	local wanted = {}
	for _, service in ipairs(services) do wanted[#wanted + 1] = service end
	table.sort(wanted, function(a, b) return a.cost < b.cost end)
	local money, chosen, spent, total = Util.Clean(Util.Safe(GetMoney)) or 0, {}, 0, 0
	for _, service in ipairs(wanted) do
		total = total + service.cost
		if spent + service.cost <= money then
			chosen[#chosen + 1] = service
			spent = spent + service.cost
		end
	end
	return chosen, spent, total
end

-- Services learned, from the highest index down (the indices of the others stay right).
-- The trainer's services chosen ({ index, cost, name, sub }) bought one a moment after the other, from the highest
-- index down (the indices of the others stay right): each one first found again (still there and still to learn,
-- by its name and rank when it moved), while the gold lasts (counted here: the game takes it only with the
-- trainer's answer) and still() says go on (the trainer still open). done(bought) once the last one is asked:
-- how many were. Returns how many will be tried.
local LEARN_SPACING = 0.15 -- seconds between two purchases (the trainer answers each one)
Util.LEARN_SPACING = LEARN_SPACING
local function StillToLearn(service)
	local function Same(index)
		local name, sub, state = Util.TrainerService(index)
		return state == "available" and (service.name == nil or (name == service.name and sub == service.sub))
	end
	if Same(service.index) then return service.index end
	if service.name == nil then return nil end
	for index = 1, (Util.Clean(Util.Safe(GetNumTrainerServices)) or 0) do
		if Same(index) then return index end
	end
end
function Util.LearnServices(chosen, done, still)
	local order = {}
	for _, service in ipairs(chosen) do order[#order + 1] = service end
	table.sort(order, function(a, b) return a.index > b.index end)
	local left, bought = Util.Clean(Util.Safe(GetMoney)) or 0, 0
	local function Next(at)
		local service = order[at]
		if not service or (still and not still()) then
			if done then done(bought) end
			return
		end
		local index = StillToLearn(service)
		local cost = tonumber(service.cost) or 0
		if index and cost <= math.min(left, Util.Clean(Util.Safe(GetMoney)) or 0) then
			left = left - cost
			bought = bought + 1
			Util.Safe(BuyTrainerService, index)
		end
		if order[at + 1] then C_Timer.After(LEARN_SPACING, function() Next(at + 1) end) else Next(at + 1) end
	end
	Next(1)
	return #order
end

-- A merchant's item (by its place in his list): its price (of a lot, in copper), how many in a lot, how many he
-- has left (-1 or nil: no end), whether it is sold for gold alone. The game's table where it has one, its older
-- answers elsewhere.
function Util.MerchantOffer(index)
	local api = C_MerchantFrame and C_MerchantFrame.GetItemInfo
	local info = api and Util.Safe(api, index)
	local C = Util.Clean
	if type(info) == "table" then
		return C(info.price), math.max(1, C(info.stackCount) or 1), C(info.numAvailable),
			C(info.isPurchasable) ~= false and not C(info.hasExtendedCost) and not C(info.currencyID) and (C(info.price) or 0) > 0
	end
	local _, _, price, lot, available, purchasable, _, extended = Util.Safe(GetMerchantItemInfo, index)
	price = C(price)
	return price, math.max(1, C(lot) or 1), C(available), C(purchasable) ~= false and not C(extended) and (price or 0) > 0
end

-- How many of it the merchant can still sell (math.huge: no end).
function Util.MerchantMost(index)
	local _, lot, available = Util.MerchantOffer(index)
	if available and available >= 0 then return available * lot end
	return math.huge
end

-- What count of it costs, in whole lots (as the merchant's window buys them) and no more than he has; nil when
-- not for gold alone.
function Util.MerchantCost(index, count)
	local price, lot, _, forGold = Util.MerchantOffer(index)
	if not forGold then return nil end
	return price * math.ceil(math.min(count, Util.MerchantMost(index)) / lot)
end

-- count of the merchant's item index bought, in whole lots and stacks, a moment apart (as the server expects).
-- Each purchase first checks it is still item id at that place (another merchant meanwhile: nothing bought).
-- done() once the last one is asked (or nothing could be). How many purchases it makes.
local BUY_DELAY = 0.25
function Util.BuyFromMerchant(index, count, id, done)
	local function Still()
		return MerchantFrame and MerchantFrame:IsShown() and Util.Clean(Util.Safe(GetMerchantItemID, index)) == id
	end
	local _, lot, _, forGold = Util.MerchantOffer(index)
	if not (id and count and count > 0 and forGold and Still()) then
		if done then done() end
		return 0
	end
	local stack = Util.Clean(Util.Safe(GetMerchantItemMaxStack, index)) or lot
	local most = math.max(lot, math.floor(stack / lot) * lot)
	local steps, left = {}, math.ceil(math.min(count, Util.MerchantMost(index)) / lot) * lot
	while left > 0 do
		local take = math.min(left, most)
		steps[#steps + 1] = take
		left = left - take
	end
	for step, quantity in ipairs(steps) do
		C_Timer.After((step - 1) * BUY_DELAY, function()
			if Still() then Util.Safe(BuyMerchantItem, index, quantity) end
			if step == #steps and done then done() end
		end)
	end
	return #steps
end

-- Several of the merchant's items bought one after the other ({ { index, count, id } }), each once the last
-- one's purchases are asked, a moment apart; done() at the end.
function Util.BuyQueue(items, done)
	local step = 0
	local function Next()
		step = step + 1
		local item = items[step]
		if not item then
			if done then done() end
			return
		end
		Util.BuyFromMerchant(item.index, item.count, item.id, function() C_Timer.After(BUY_DELAY, Next) end)
	end
	Next()
end

-- Its item level and the level it asks (nil until the game has it).
function Util.ItemLevels(id)
	local _, _, _, level, minimum = Util.Safe(ItemAPI("GetItemInfo"), id)
	return Util.Clean(level), Util.Clean(minimum)
end
-- The item level of this very item (its upgrades counted when the game tells them), else its kind's.
function Util.ItemLevel(link)
	local level = C_Item and C_Item.GetDetailedItemLevelInfo and Util.Clean(Util.Safe(C_Item.GetDetailedItemLevelInfo, link))
	return level or (Util.ItemLevels(link))
end
-- Its kind of gear (INVTYPE_HEAD...; nil or "": not gear).
function Util.ItemEquipKind(item)
	local _, _, _, kind = Util.ItemInstant(item)
	kind = Util.Clean(kind)
	if kind and kind ~= "" then return kind end
	return Util.Clean((select(9, Util.Safe(ItemAPI("GetItemInfo"), item))))
end
-- The places an item goes, by its kind (rings and trinkets: either of two).
Util.EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
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

-- A class's color (r, g, b) from its file name ("WARRIOR"), nil when unknown.
function Util.ClassColor(class)
	if not class then return nil end
	local colors = (C_ClassColor and C_ClassColor.GetClassColor and Util.Safe(C_ClassColor.GetClassColor, class))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if type(colors) == "table" and colors.r then return colors.r, colors.g, colors.b end
	return nil
end

-- Money in letters, briefly: "1 g 20 s" (the game's own letters; nothing for a part at zero).
function Util.CoinsWords(copper)
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. " " .. (GOLD_AMOUNT_SYMBOL or "g") end
	if silver > 0 then parts[#parts + 1] = silver .. " " .. (SILVER_AMOUNT_SYMBOL or "s") end
	if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. " " .. (COPPER_AMOUNT_SYMBOL or "c") end
	return table.concat(parts, " ")
end

-- A signal: On(fn) listens, Fire(...) calls every listener (each kept from the others' errors).
function Util.Signal()
	local listeners = {}
	return {
		On = function(fn) listeners[#listeners + 1] = fn end,
		Fire = function(...) for _, fn in ipairs(listeners) do pcall(fn, ...) end end,
	}
end

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

-- "3 hours": how long ago (seconds), in the game's words (a minute at least).
function Util.Ago(seconds)
	seconds = math.max(60, tonumber(seconds) or 0)
	if SecondsToTime then return SecondsToTime(seconds, true, true, 1) end
	return ("%d min"):format(math.floor(seconds / 60))
end

-- "2 hours ago", in the game's words for the time and Wanderer's for "ago".
function Util.AgoWords(seconds)
	return ns.L.AGO:format(Util.Ago(seconds))
end

-- One of two forms by a count ("%d item" / "%d items"), the count put in.
function Util.Plural(count, one, many)
	count = tonumber(count) or 0
	return (count == 1 and one or many):format(count)
end

-- A function that runs fn once, a moment after the last time it was called (many calls at once: one run).
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

-- You and your world ------------------------------------------------------------------------------------

-- Your professions (the primary ones, fishing, cooking, first aid): { { name, icon, rank, line } }.
-- (the game's list has holes, a trade not learned: read by position; the first two are your two trades)
function Util.Professions()
	local list = {}
	local indexes = { Util.Safe(GetProfessions) }
	for position = 1, 6 do
		local index = indexes[position]
		local name, icon, rank, most, line
		if index then name, icon, rank, most, _, _, line = Util.Safe(GetProfessionInfo, index) end
		name = Util.Clean(name)
		if name then
			list[#list + 1] = { name = name, icon = Util.Clean(icon), rank = Util.Clean(rank) or 0, most = Util.Clean(most),
				line = Util.Clean(line), primary = position <= 2 }
		end
	end
	return list
end

-- A faction: its name and your standing with it (1 hated ... 4 neutral, 5 friendly, 6 honored, 7 revered, 8
-- exalted).
function Util.Faction(id)
	local api = C_Reputation and C_Reputation.GetFactionDataByID
	local data = api and Util.Safe(api, id)
	if type(data) == "table" then return Util.Clean(data.name), Util.Clean(data.reaction) end
	local name, _, standing = Util.Safe(GetFactionInfoByID, id)
	return Util.Clean(name), Util.Clean(standing)
end

-- Whether an item (its id) is a fishing pole.
local FISHING_POLE = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
local WEAPON = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
-- The spells of fishing of WoW Forever (its ranks: Apprentice to Artisan; checked against its own tables).
Util.FISHING_SPELLS = { 7620, 7731, 7732, 18248 }
local FISHING = {}
for _, id in ipairs(Util.FISHING_SPELLS) do FISHING[id] = true end
function Util.IsFishingSpell(spell) return FISHING[Util.Clean(spell)] == true end

-- A fishing pole in your main hand.
function Util.HasFishingPole()
	return Util.IsFishingPole(Util.Clean(Util.Safe(GetInventoryItemID, "player", INVSLOT_MAINHAND or 16)))
end

-- fn run once the fight is over, once for each key however often asked meanwhile: what the game keeps out of
-- reach in a fight (protected frames, the map's pins, the settings written back). Asked in a fight.
local afterFight, fightFrame = {}, nil
function Util.AfterFight(key, fn)
	afterFight[key] = fn
	if fightFrame then return end
	fightFrame = CreateFrame("Frame")
	fightFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	fightFrame:SetScript("OnEvent", function()
		local waiting = afterFight
		afterFight = {}
		for _, run in pairs(waiting) do Util.Try(run) end
	end)
end

function Util.IsFishingPole(id)
	if not id then return false end
	local _, _, _, _, _, class, subclass = Util.ItemInstant(id)
	return Util.Clean(class) == WEAPON and Util.Clean(subclass) == FISHING_POLE
end

-- The bank ----------------------------------------------------------------------------------------------

-- The tabs bought of a bank (kind: Enum.BankType.Character or .Account): { { id (its container), name } }.
function Util.BankTabs(kind)
	local tabs = kind and C_Bank and C_Bank.FetchPurchasedBankTabData and Util.Safe(C_Bank.FetchPurchasedBankTabData, kind)
	local list = {}
	for _, tab in ipairs(type(tabs) == "table" and tabs or {}) do
		local id = Util.Clean(tab.ID)
		if id then list[#list + 1] = { id = id, name = Util.Clean(tab.name) } end
	end
	return list
end

-- Every container of the bank: your character's tabs then the account's; a bank of the older kind: its main
-- container and its bags.
function Util.BankIDs()
	local list = {}
	local types = Enum and Enum.BankType or {}
	for _, kind in ipairs({ types.Character, types.Account }) do
		for _, tab in ipairs(Util.BankTabs(kind)) do list[#list + 1] = tab.id end
	end
	if not list[1] then
		list[1] = BANK_CONTAINER or -1
		local first = Enum and Enum.BagIndex and Enum.BagIndex.BankBag_1 or (NUM_BAG_SLOTS or 4) + 1
		for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = bag end
	end
	return list
end

-- Item tooltips ------------------------------------------------------------------------------------------

-- The comparison tooltips beside one (what you wear): nothing of Wanderer's added there.
function Util.IsComparisonTooltip(tooltip)
	local name = tooltip and tooltip.GetName and Util.Clean(Util.Safe(tooltip.GetName, tooltip)) or ""
	return name:find("^ShoppingTooltip") ~= nil or name:find("^ItemRefShoppingTooltip") ~= nil
end

-- A tooltip shown again so the lines added fit, unless it holds coins: the game's coins measure their words on
-- each showing, and a showing asked by an addon makes those widths hidden (an error in the game's money frame).
-- The game shows such a tooltip itself (a merchant's item, a sell price): the lines fit then.
function Util.ShowTooltipAgain(tooltip)
	if not (tooltip and tooltip.Show) then return end
	if (tonumber(Util.Clean(tooltip.shownMoneyFrames)) or 0) > 0 then return end
	tooltip:Show()
end

-- add(tooltip, item id, data) called for every item tooltip but the comparison ones (and, unless inFight, out of a
-- fight); it returns true when it added lines. Every one asked in one pass, in the order they came: the tooltip
-- is then shown again once, whoever added (never once for each).
local adders
function Util.OnItemTooltip(add, inFight)
	if not (TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) then return false end
	if not adders then
		adders = {}
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if Util.IsComparisonTooltip(tooltip) then return end
			local fight, id, added = InCombatLockdown(), type(data) == "table" and Util.Clean(data.id) or nil, false
			for _, entry in ipairs(adders) do
				if entry.inFight or not fight then
					local ok, did = Util.Try(entry.add, tooltip, id, data)
					if ok and did then added = true end
				end
			end
			if added then Util.ShowTooltipAgain(tooltip) end
		end)
	end
	adders[#adders + 1] = { add = add, inFight = inFight and true or false }
	return true
end

-- The world and its maps --------------------------------------------------------------------------------
-- World positions as the game counts them (UnitPosition's first two values, the servers' x and y) and its
-- continent; map positions from 0 to 1. The game converts between them, its redrawn maps (Forever's
-- Stormwind...) included.

-- A map point in the world: x, y, continent (nil: unknown).
function Util.MapToWorld(map, x, y)
	if not (map and x and y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local instance, point = Util.Safe(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if type(point) ~= "table" then return nil end
	local wx, wy = Util.Clean(point.x), Util.Clean(point.y)
	if not (wx and wy) then return nil end
	return wx, wy, Util.Clean(instance)
end

-- A world point on a map: map, x, y (0 to 1). On the map asked (nil when it lies outside it), else on the
-- closest map the game has for it (the zone under it).
function Util.WorldToMap(continent, wx, wy, map)
	if not (wx and wy and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
	local function At(target)
		local found, point = Util.Safe(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(wx, wy), target)
		if type(point) ~= "table" then return nil end
		local x, y = Util.Clean(point.x), Util.Clean(point.y)
		if not (x and y) then return nil end
		return Util.Clean(found) or target, x, y
	end
	if map then
		local _, x, y = At(map)
		if not (x and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
		return map, x, y
	end
	local found, x, y = At(nil)
	if not found then return nil end
	local info = C_Map.GetMapInfoAtPosition and Util.Safe(C_Map.GetMapInfoAtPosition, found, x, y)
	local zone = type(info) == "table" and Util.Clean(info.mapID)
	if zone and zone ~= found then
		local _, zx, zy = At(zone)
		if zx then return zone, zx, zy end
	end
	return found, x, y
end

-- Where you stand in the world: x, y, continent (nil inside an instance, where the game keeps it to itself).
function Util.Here()
	local a, b, _, instance = Util.Safe(UnitPosition, "player")
	a, b = Util.Clean(a), Util.Clean(b)
	if not (a and b) then return nil end
	return a, b, Util.Clean(instance)
end

-- Where you stand on the map you are on: map, x, y (0 to 1), or nil.
function Util.HereOnMap()
	local map = C_Map and Util.Clean(Util.Safe(C_Map.GetBestMapForUnit, "player"))
	local point = map and Util.Safe(C_Map.GetPlayerMapPosition, map, "player")
	if type(point) ~= "table" then return nil end
	local x, y = Util.Clean(point.x), Util.Clean(point.y)
	if not (x and y) or (x == 0 and y == 0) then return nil end
	return map, x, y
end

-- The name of a map, or of the zone under a point of it.
function Util.MapName(map, x, y)
	if not (map and C_Map) then return nil end
	if x and y and C_Map.GetMapInfoAtPosition then
		local info = Util.Safe(C_Map.GetMapInfoAtPosition, map, x, y)
		if type(info) == "table" and Util.Clean(info.name) then return Util.Clean(info.name) end
	end
	local info = C_Map.GetMapInfo and Util.Safe(C_Map.GetMapInfo, map)
	return type(info) == "table" and Util.Clean(info.name) or nil
end

-- The game's own pin on a map (x, y: 0 to 1), followed; false when it cannot.
function Util.Pin(map, x, y)
	if not (map and x and y and UiMapPoint and C_Map and C_Map.SetUserWaypoint) then return false end
	local point = Util.Safe(UiMapPoint.CreateFromCoordinates, map, x, y)
	if not point then return false end
	Util.Safe(C_Map.SetUserWaypoint, point)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then Util.Safe(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	return true
end

-- The way to a place (map, x, y from 0 to 1): followed by Wanderer Maps' arrow when it is there, else the
-- game's own pin. Whether it could.
function Util.Go(map, x, y, title, info)
	local maps = _G.WandererMaps
	if type(maps) == "table" and maps.Go then return maps.Go(map, x, y, title, info) and true or false end
	return Util.Pin(map, x, y)
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
			-- (a frame without a point yet: the former places kept, if any)
			if points[1] or not offPoints[frame] then offPoints[frame] = points end
		end
		frame:SetAlpha(0)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", OFF_SCREEN, 0)
	elseif offPoints[frame] or (frame:GetAlpha() or 1) < 1 then
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

-- A link in the chat's box (never sent: the player sends it or not); false when no box opens.
function Util.ChatInsert(link)
	if type(link) ~= "string" or link == "" then return false end
	local util = _G.ChatFrameUtil
	local insert = _G.ChatEdit_InsertLink or (util and util.InsertLink)
	if insert and insert(link) then return true end
	local open = _G.ChatFrame_OpenChat or (util and util.OpenChat)
	if not open then return false end
	open(link)
	return true
end

-- A menu of the game's (MenuUtil) at a frame; false when the game has none.
function Util.Menu(owner, build)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
	MenuUtil.CreateContextMenu(owner, build)
	return true
end
