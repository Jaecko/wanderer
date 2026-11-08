local _, ns = ...
local L = ns.L

-- The unit frames in Wanderer's look: the game's own frames (you, your target, your focus, their targets, your
-- pet, your party, the bosses, the group frames and the cast bars) keep their code, their values and their
-- options; Wanderer only changes how their bars, grounds, texts and art look, through the regions the game
-- already has and a few pieces of its own laid on them (a dark ground behind the missing health, a fine ink
-- line). Nothing is written on the game's frames, no size, no place, no value: the game feeds every bar and
-- writes every text (what they show follows its own Interface options; sizes stay Edit Mode's). The look the
-- game had is kept and given back exactly when this is turned off.
--
-- One engine draws every bar of this look: the game's, the previews' and Wanderer's own (the label, its cast
-- line, the tooltip's power), so a preview cannot lie. Three looks are offered at once (presets): Fine (the
-- game's frames, Wanderer's bars), Ink lines (no metal: flat bars on a dark ground with a fine ink line) and
-- Classic (the bars of 2004). Portraits.lua draws the portraits' part of the same looks.

local U = ns.Util
local Safe, Clean, IsSecret = U.Safe, U.Clean, U.IsSecret

local MEDIA = "Interface\\AddOns\\Wanderer\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEXTURES = { smooth = MEDIA .. "Bar", clean = MEDIA .. "BarClean", flat = WHITE, classic = "Interface\\TargetingFrame\\UI-StatusBar" }
local NARROW = "Fonts\\ARIALN.TTF"
local FALLBACK_LEVEL = 10

-- Colours ----------------------------------------------------------------------------------------------------

local function Hex(hex)
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

-- A colour's hue (degrees) and saturation; the distance between two hues.
local function HueOf(r, g, b)
	local most, least = math.max(r, g, b), math.min(r, g, b)
	local span = most - least
	if most <= 0 then return 0, 0 end
	local hue = 0
	if span > 0 then
		if most == r then hue = ((g - b) / span) % 6 elseif most == g then hue = (b - r) / span + 2 else hue = (r - g) / span + 4 end
		hue = hue * 60
	end
	return hue, span / most
end

local function Gap(a, b)
	local gap = math.abs(a - b) % 360
	return gap > 180 and 360 - gap or gap
end

-- Creatures by their attitude towards you; tapped by others; offline (players); the colour-blind safe set.
local REACTION = { hostile = Hex("C2453A"), unfriendly = Hex("D2763A"), neutral = Hex("D9B54A"), friendly = Hex("4CA35A") }
local REACTION_SAFE = { hostile = Hex("D96A1F"), unfriendly = Hex("D9813F"), neutral = Hex("D9B54A"), friendly = Hex("3F8FD9") }
local REACTION_CLASSIC = { hostile = Hex("CC2A1F"), unfriendly = Hex("CC2A1F"), neutral = Hex("D9C21F"), friendly = Hex("00CC00") }
local TAPPED, OFFLINE = Hex("8C8C8C"), Hex("5C5C61")
-- Low health (yours, your party's): from its own colour at 35 % to a deep warning red at 20 %, no flash, no glow.
local LOW_RED = Hex("B8342C")
local LOW_FROM, LOW_FULL = 0.35, 0.2
-- Power in the game's hues, without the neon, readable on ink; "game": its own, the pure blue mana softened.
local POWER = { MANA = Hex("3B7DD8"), RAGE = Hex("C8443A"), ENERGY = Hex("E3C34A"), FOCUS = Hex("D9813F"), RUNIC_POWER = Hex("2FB5D9") }
local GAME_MANA = Hex("2E5CE6")
local POWER_FALLBACK = { 0, 0.55, 1 }
-- Cast bars: by what is cast; classic: the game's 2004 colours.
local CAST = { cast = Hex("E3B34A"), channel = Hex("6BBF7A"), locked = Hex("8F8775"), failed = Hex("C2453A"), done = Hex("8FE0A3") }
local CAST_CLASSIC = { cast = { 1, 0.7, 0 }, channel = { 0, 1, 0 }, locked = { 0.7, 0.7, 0.7 }, failed = { 1, 0, 0 }, done = { 0, 1, 0 } }
local GROUND = { dark = { 0.055, 0.059, 0.071, 0.85 }, classic = { 0, 0, 0, 0.6 } }
local INK = { 0, 0, 0, 0.9 }
local VALUE_COLOR = { 0.95, 0.93, 0.9 }
local NAME_COLOR = ns.Skin.COLORS.text
-- (the ink line's quiet tints: a fight, resting)
local COMBAT_EDGE, REST_EDGE = { 0.32, 0.18, 0.05, 1 }, { 0.2, 0.17, 0.1, 1 }

-- The looks -----------------------------------------------------------------------------------------------------

-- Each preset sets the bars and the portraits together (Portraits.lua reads ring, badge and iconStyle).
ns.UF_FIELDS = { "health", "texture", "ground", "power", "art", "texts", "ring", "badge", "iconStyle" }
ns.UF_PRESETS = {
	{ key = "fine", health = "class", texture = "smooth", ground = "dark", power = "wanderer", art = "game", texts = "wanderer",
		ring = "class", badge = "others", iconStyle = "game" },
	{ key = "lines", health = "class", texture = "flat", ground = "dark", power = "wanderer", art = "lines", texts = "wanderer",
		ring = "gold", badge = "others", iconStyle = "ink" },
	{ key = "classic", health = "classic", texture = "classic", ground = "classic", power = "game", art = "game", texts = "game",
		ring = "class", badge = "others", iconStyle = "classic" },
}
ns.UF_CHOICES = {
	health = { "class", "gradient", "one", "classic" }, texture = { "smooth", "clean", "flat", "classic" }, ground = { "dark", "faded", "classic" },
	power = { "wanderer", "game" }, art = { "game", "lines" }, texts = { "wanderer", "game" }, ring = { "off", "class", "gold" },
	badge = { "off", "others", "all" }, iconStyle = { "game", "classic", "ink" }, show = { "game", "face", "icon" },
	thickness = { "fine", "medium", "thick" },
}
-- The frames it dresses, each its own switch; the portraits' rows of "what each shows".
ns.UF_FRAMES = { "player", "target", "focus", "tot", "pet", "party", "group", "boss", "castBars" }
ns.UF_SHOWS = { "player", "target", "party", "tot" }

local function UF() return ns.db and ns.db.unitFrames end

-- The preset these settings match, or nil (customised).
function ns.UnitFramesPreset(look)
	look = look or UF()
	if not look then return nil end
	for _, preset in ipairs(ns.UF_PRESETS) do
		local same = true
		for _, field in ipairs(ns.UF_FIELDS) do
			if look[field] ~= preset[field] then same = false break end
		end
		if same then return preset.key end
	end
	return nil
end

local function PresetOf(key)
	for _, preset in ipairs(ns.UF_PRESETS) do
		if preset.key == key then return preset end
	end
end
ns.UnitFramesPresetOf = PresetOf

-- The engine-side gradient (the game colours a hidden health itself): offered only when the game has it.
local curve
local function Curve()
	if curve ~= nil then return curve or nil end
	curve = false
	local api = _G.C_CurveUtil
	if not (api and api.CreateColorCurve and _G.UnitHealthPercent and CreateColor) then return nil end
	local ok, made = pcall(api.CreateColorCurve)
	if not (ok and type(made) == "table" and made.AddPoint) then return nil end
	local points = { { 0, REACTION.hostile }, { 0.5, REACTION.neutral }, { 1, REACTION.friendly } }
	for _, point in ipairs(points) do
		if not pcall(made.AddPoint, made, point[1], CreateColor(point[2][1], point[2][2], point[2][3], 1)) then return nil end
	end
	curve = made
	return curve
end
function ns.UnitFramesGradient() return Curve() ~= nil end

-- A colour from green to red as health goes down (share: 0 to 1).
local function Blend(share, safe)
	local top = safe and REACTION_SAFE.friendly or REACTION.friendly
	local low, mid = safe and REACTION_SAFE.hostile or REACTION.hostile, REACTION.neutral
	local from, to, t
	if share >= 0.5 then from, to, t = mid, top, (share - 0.5) * 2 else from, to, t = low, mid, share * 2 end
	return from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t
end

local function Reaction(unit, look)
	local reaction = Clean(Safe(UnitReaction, unit, "player"))
	local set = look.health == "classic" and REACTION_CLASSIC or (look.colourBlind and REACTION_SAFE or REACTION)
	if type(reaction) ~= "number" then return set.friendly end
	if reaction <= 2 then return set.hostile elseif reaction == 3 then return set.unfriendly elseif reaction == 4 then return set.neutral end
	return set.friendly
end

-- A unit's health colour in a look: r, g, b (maybe the game's hidden colour, for the gradient), and whether it
-- is a plain colour (the faded ground can follow it).
function ns.UnitFramesHealthColor(unit, look)
	look = look or UF() or ns.UF_PRESETS[2]
	local isPlayer = Clean(Safe(UnitIsPlayer, unit))
	if isPlayer and Safe(UnitIsConnected, unit) == false then return OFFLINE[1], OFFLINE[2], OFFLINE[3], true end
	if Clean(Safe(UnitIsTapDenied, unit)) then return TAPPED[1], TAPPED[2], TAPPED[3], true end
	local mode = look.health
	if mode == "one" then
		local c = look.colourBlind and REACTION_SAFE.friendly or REACTION.friendly
		return c[1], c[2], c[3], true
	end
	if mode == "gradient" then
		local health, most = Clean(Safe(UnitHealth, unit)), Clean(Safe(UnitHealthMax, unit))
		if type(health) == "number" and type(most) == "number" and most > 0 then
			local r, g, b = Blend(math.max(0, math.min(1, health / most)), look.colourBlind)
			return r, g, b, true
		end
		local made = Curve()
		local ok, color = false, nil
		if made then ok, color = pcall(_G.UnitHealthPercent, unit, true, made) end
		if ok and type(color) == "table" and color.GetRGB then
			local r, g, b = color:GetRGB()
			return r, g, b, false
		end
		mode = "class"
	end
	if isPlayer and mode == "classic" then return REACTION_CLASSIC.friendly[1], REACTION_CLASSIC.friendly[2], REACTION_CLASSIC.friendly[3], true end
	if isPlayer then
		local _, class = Safe(UnitClass, unit)
		local r, g, b = U.ClassColor(Clean(class))
		-- (a very light class colour, the priest's white: a touch softer and warmer on the dark ink, its hue kept)
		if r and 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.9 then r, g, b = r * 0.92, g * 0.9, b * 0.86 end
		-- (a hidden class: the quiet green, never a guess)
		if r then return r, g, b, true end
		return REACTION.friendly[1], REACTION.friendly[2], REACTION.friendly[3], true
	end
	local c = Reaction(unit, look)
	return c[1], c[2], c[3], true
end

-- A power's colour in a look ("MANA", "RAGE"...): r, g, b.
function ns.UnitFramesPowerColor(token, look)
	look = look or UF() or ns.UF_PRESETS[2]
	token = type(token) == "string" and token or ""
	if look.power ~= "game" and POWER[token] then return unpack(POWER[token]) end
	if token == "MANA" then return unpack(GAME_MANA) end
	local color = (PowerBarColor or {})[token]
	if type(color) == "table" and color.r then return color.r, color.g, color.b end
	return unpack(POWER_FALLBACK)
end

-- A cast's colour in a look ("cast", "channel", "locked", "failed", "done").
function ns.UnitFramesCastColor(kind, look)
	look = look or UF() or ns.UF_PRESETS[2]
	local set = look.texture == "classic" and CAST_CLASSIC or CAST
	return unpack(set[kind] or set.cast)
end

local function TexturePath(look) return TEXTURES[look.texture] or TEXTURES.smooth end

-- The missing part's ground: r, g, b, a (faded: the bar's colour, dimmed).
local function GroundColor(look, r, g, b, plain)
	if look.ground == "faded" and plain and r then return r * 0.22, g * 0.22, b * 0.22, 0.9 end
	if look.ground == "classic" then return unpack(GROUND.classic) end
	-- (the deep ink, with a hint of the bar's own hue: the lost part still reads as this bar's)
	local ink = GROUND.dark
	if plain and type(r) == "number" then
		return ink[1] * 0.93 + r * 0.07, ink[2] * 0.93 + g * 0.07, ink[3] * 0.93 + b * 0.07, 0.88
	end
	return unpack(ink)
end

-- Pieces shared by every bar of the look -------------------------------------------------------------------

local function Level(frame)
	local level = Clean(Safe(frame.GetFrameLevel, frame))
	return type(level) == "number" and level or FALLBACK_LEVEL
end

-- The part of a bar the eye sees (DotBars.lua knows the game's masked bars).
local function Visible(bar)
	local parts = ns.HealthBands
	return parts and parts.GameVisible and parts.GameVisible(bar) or bar
end

-- One physical pixel at this frame's scale.
local function Pixel(frame)
	local pixel = _G.PixelUtil
	local scale = Clean(Safe(frame.GetEffectiveScale, frame))
	if pixel and pixel.GetNearestPixelSize and type(scale) == "number" and scale > 0 then
		local size = Clean(Safe(pixel.GetNearestPixelSize, 1, scale, 1))
		if type(size) == "number" and size > 0 then return size end
	end
	return 1
end

-- A thin ink line around a block (its own frame, under DotBars' and HotBars' bands and marks): around the part
-- the eye sees of bar and, given, of lower right under it, with a 1 px ink rule between them. The quarter marks
-- along bar (made hidden: shown only when asked). Corners only: every piece anchored by its corners, so nothing
-- is pulled to a centre. line.Color(r, g, b, a).
local function InkLine(bar, parent, lower)
	local line = CreateFrame("Frame", nil, parent or bar)
	line:SetFrameLevel(Level(bar) + 1)
	line.edges = {}
	for index = 1, 5 do
		local edge = line:CreateTexture(nil, "OVERLAY")
		edge:Hide()
		line.edges[index] = edge
	end
	line.marks = {}
	for index = 1, 3 do
		local mark = line:CreateTexture(nil, "OVERLAY", nil, 1)
		mark:SetColorTexture(0, 0, 0, 0.5)
		mark:Hide()
		line.marks[index] = mark
	end
	line.lower = lower
	function line.Color(r, g, b, a)
		for _, edge in ipairs(line.edges) do edge:SetColorTexture(r, g, b, a or 1) end
	end
	function line.Place(edged)
		local upper, px = line.upper or Visible(bar), Pixel(bar)
		local low = line.lower or upper
		-- (the box: from the top left of the upper part to the bottom right of the lower one, one pixel out)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", upper, "TOPLEFT", -px, px)
		line:SetPoint("BOTTOMRIGHT", low, "BOTTOMRIGHT", px, -px)
		local top, bottom, left, right, rule = unpack(line.edges)
		top:ClearAllPoints()
		top:SetPoint("TOPLEFT", line, "TOPLEFT")
		top:SetPoint("TOPRIGHT", line, "TOPRIGHT")
		top:SetHeight(px)
		bottom:ClearAllPoints()
		bottom:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT")
		bottom:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT")
		bottom:SetHeight(px)
		left:ClearAllPoints()
		left:SetPoint("TOPLEFT", line, "TOPLEFT")
		left:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT")
		left:SetWidth(px)
		right:ClearAllPoints()
		right:SetPoint("TOPRIGHT", line, "TOPRIGHT")
		right:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT")
		right:SetWidth(px)
		rule:ClearAllPoints()
		rule:SetPoint("TOPLEFT", upper, "BOTTOMLEFT")
		rule:SetPoint("TOPRIGHT", upper, "BOTTOMRIGHT")
		rule:SetHeight(px)
		for index, edge in ipairs(line.edges) do edge:SetShown(edged and (index < 5 or line.lower ~= nil)) end
	end
	function line.Marks(shown)
		local upper = line.upper or Visible(bar)
		local width = Clean(Safe(upper.GetWidth, upper))
		for index, mark in ipairs(line.marks) do
			local on = shown and type(width) == "number" and width > 0
			if on then
				mark:ClearAllPoints()
				mark:SetPoint("TOPLEFT", upper, "TOPLEFT", width * index / 4, 0)
				mark:SetPoint("BOTTOMLEFT", upper, "BOTTOMLEFT", width * index / 4, 0)
				mark:SetWidth(Pixel(bar))
			end
			mark:SetShown(on and true or false)
		end
	end
	line.Color(unpack(INK))
	return line
end

-- The ground behind the missing part: a texture of the bar's, under its fill (whatever layer the game gave the
-- fill: the lowest one, else just under it), over the bar's visible part (by its corners).
local function Ground(bar)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	local sublevel = -8
	if type(fill) == "table" and fill.GetDrawLayer then
		local fillLayer, fillSub = Safe(fill.GetDrawLayer, fill)
		fillLayer, fillSub = Clean(fillLayer), Clean(fillSub)
		if fillLayer == "BACKGROUND" and type(fillSub) == "number" then sublevel = math.max(-8, fillSub - 1) end
	end
	local ground = bar:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	local seen = Visible(bar)
	ground:SetPoint("TOPLEFT", seen, "TOPLEFT")
	ground:SetPoint("BOTTOMRIGHT", seen, "BOTTOMRIGHT")
	ground:SetTexture(WHITE)
	return ground
end

-- Skin.UnitBar: one of Wanderer's own bars (the previews', the label's) in a look, its colour (r, g, b) given;
-- plain: a colour the faded ground may follow. lower: the bar under it in one block (Ink lines: one line around
-- both, a 1 px rule between); false: a bar inside another's block (no line of its own).
function ns.Skin.UnitBar(bar, look, r, g, b, plain, lower)
	look = look or UF() or ns.UF_PRESETS[2]
	bar:SetStatusBarTexture(TexturePath(look))
	if r then bar:SetStatusBarColor(r, g, b) end
	bar.wandererGround = bar.wandererGround or Ground(bar)
	bar.wandererGround:SetVertexColor(GroundColor(look, r, g, b, plain ~= false))
	local edged = look.art == "lines" and lower ~= false
	if edged and not bar.wandererLine then bar.wandererLine = InkLine(bar, nil, lower or nil) end
	if bar.wandererLine then
		bar.wandererLine.lower = lower or nil
		bar.wandererLine.Place(edged)
		bar.wandererLine.Marks(edged and look.quarterMarks and true or false)
	end
end

-- The settings ----------------------------------------------------------------------------------------------

local yielded = {} -- job -> another addon does it (read once per drawing)
local function ReadYields()
	for _, job in ipairs({ "unitFrames", "unitFramesGroup", "unitFramesCasts" }) do yielded[job] = ns.Yields and ns.Yields(job) ~= nil end
end

local function On()
	local db, uf = ns.db, UF()
	return db and db.enabled and uf and uf.enabled and not yielded.unitFrames and true or false
end
ns.UnitFramesOn = On

local function FrameOn(key)
	if not On() then return false end
	local frames = UF().frames
	if type(frames) == "table" and frames[key] == false then return false end
	if key == "group" and yielded.unitFramesGroup then return false end
	if key == "castBars" and yielded.unitFramesCasts then return false end
	return true
end
ns.UnitFramesFrameOn = FrameOn

-- The art hidden now: Ink lines, out of Edit Mode (its selection boxes read on the game's art).
local function EditMode()
	local manager = _G.EditModeManagerFrame
	return type(manager) == "table" and Clean(Safe(manager.IsShown, manager)) and true or false
end
local function Lines() return On() and UF().art == "lines" and not EditMode() end
ns.UnitFramesLines = Lines

-- The game's frames ----------------------------------------------------------------------------------------

local function Walk(node, ...)
	for index = 1, select("#", ...) do
		if type(node) ~= "table" or IsSecret(node) then return nil end
		local key = select(index, ...)
		local value = rawget(node, key)
		if value == nil then value = Safe(function() return node[key] end) end
		node = value
	end
	return node
end
ns.UnitFramesWalk = Walk

local function IsBar(bar)
	return type(bar) == "table" and not IsSecret(bar) and type(bar.GetStatusBarTexture) == "function" and bar or nil
end

local function IsText(text)
	return type(text) == "table" and not IsSecret(text) and type(text.GetFont) == "function" and text or nil
end

local function Region(region)
	return type(region) == "table" and not IsSecret(region) and type(region.SetAlpha) == "function" and region or nil
end

-- A unit frame's parts, found the robust way (the fields the game sets on every unit frame), else by its paths.
local function Parts(entry)
	local frame = entry.frame
	local parts = {}
	parts.health = IsBar(Walk(frame, "healthbar")) or IsBar(Walk(frame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar"))
		or IsBar(Walk(frame, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar"))
		or IsBar(Walk(frame, "HealthBarContainer", "HealthBar")) or IsBar(Walk(frame, "HealthBar"))
	parts.power = IsBar(Walk(frame, "manabar")) or IsBar(Walk(frame, "TargetFrameContent", "TargetFrameContentMain", "ManaBar"))
		or IsBar(Walk(frame, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")) or IsBar(Walk(frame, "ManaBar"))
	parts.name = IsText(Walk(frame, "name"))
	if entry.key == "player" then
		parts.cast = IsBar(_G.PlayerCastingBarFrame) or IsBar(_G.CastingBarFrame)
		parts.trail = IsBar(Walk(frame, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "PlayerFrameHealthBarAnimatedLoss"))
			or IsBar(_G.PlayerFrameHealthBarAnimatedLoss)
		parts.art = { Walk(frame, "PlayerFrameContainer", "FrameTexture"), Walk(frame, "PlayerFrameContainer", "AlternatePowerFrameTexture"),
			Walk(frame, "PlayerFrameContainer", "VehicleFrameTexture"), Walk(frame, "PlayerFrameContainer", "FrameFlash"),
			Walk(frame, "PlayerFrameContent", "PlayerFrameContentMain", "StatusTexture") }
	elseif entry.kind == "target" or entry.kind == "boss" then
		parts.cast = IsBar(Walk(frame, "spellbar"))
		parts.art = { Walk(frame, "TargetFrameContainer", "FrameTexture"), Walk(frame, "TargetFrameContainer", "Flash"),
			Walk(frame, "TargetFrameContent", "TargetFrameContentMain", "ReputationColor") }
	else
		parts.art = { Walk(frame, "FrameTexture"), Walk(frame, "Texture"), Walk(frame, "PetFrameTexture"), Walk(frame, "Flash") }
	end
	return parts
end

-- Every unit frame of the game there is: { key (its switch), kind, frame, unit }.
local function Entries()
	local list = {}
	local function Add(key, kind, frame, unit)
		if type(frame) == "table" and not IsSecret(frame) and type(frame.GetObjectType) == "function" then
			list[#list + 1] = { key = key, kind = kind, frame = frame, unit = unit }
		end
	end
	Add("player", "player", _G.PlayerFrame, "player")
	Add("target", "target", _G.TargetFrame, "target")
	Add("focus", "target", _G.FocusFrame, "focus")
	Add("tot", "small", Walk(_G, "TargetFrameToT") or Walk(_G, "TargetFrame", "totFrame"), "targettarget")
	Add("tot", "small", Walk(_G, "FocusFrameToT") or Walk(_G, "FocusFrame", "totFrame"), "focustarget")
	Add("pet", "small", _G.PetFrame, "pet")
	for index = 1, 4 do Add("party", "party", Walk(_G, "PartyFrame", "MemberFrame" .. index) or _G["PartyMemberFrame" .. index], "party" .. index) end
	for index = 1, 5 do Add("boss", "boss", _G["Boss" .. index .. "TargetFrame"], "boss" .. index) end
	return list
end
ns.UnitFrameEntries = Entries

-- The units those frames show (a vehicle for you): a unit's event for any other (a raid member, a nameplate)
-- leaves them alone. Portraits.lua reads the same set.
ns.UF_UNITS = { player = true, target = true, focus = true, targettarget = true, focustarget = true, pet = true, vehicle = true,
	party1 = true, party2 = true, party3 = true, party4 = true, boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true }

-- The unit a frame shows now (a vehicle for you, a party member...).
local function UnitOf(entry)
	local unit = Clean(rawget(entry.frame, "unit"))
	return type(unit) == "string" and unit or entry.unit
end
ns.UnitFrameUnit = UnitOf

-- Restyling: each region's look saved first, given back exactly -------------------------------------------------

local dressed = setmetatable({}, { __mode = "k" }) -- a game bar -> its state
local hiddenArt = setmetatable({}, { __mode = "k" }) -- a game region -> its alpha before
local texts = setmetatable({}, { __mode = "k" }) -- a game text -> its look before
local hooked = setmetatable({}, { __mode = "k" }) -- what is hooked already (bars, texts, frames)
local deferred = false -- pieces to make once out of a fight
local coloring = false -- a health's colour being laid by Wanderer (its own hooks wait)

-- Our pieces on a game frame are made out of a fight when it is protected.
local function CanMake(frame)
	if not Clean(Safe(InCombatLockdown)) then return true end
	if Clean(Safe(frame.IsProtected, frame)) then
		deferred = true
		return false
	end
	return true
end

-- The fill's texture as the game set it last (an atlas or a file), kept to be given back.
local function KeepFill(state, texture)
	local atlas = Clean(Safe(texture.GetAtlas, texture))
	if atlas then
		state.atlas, state.file = atlas, nil
		return
	end
	local file = Clean(Safe(texture.GetTexture, texture))
	if file ~= nil and file ~= state.ours then state.atlas, state.file = nil, file end
end

local function Fill(bar, state, path)
	local texture = Safe(bar.GetStatusBarTexture, bar)
	if type(texture) ~= "table" then return end
	KeepFill(state, texture)
	-- (the same texture object: DotBars' and HotBars' bands stay anchored to it)
	texture:SetTexture(path)
	if texture.SetHorizTile then texture:SetHorizTile(false) end
	state.ours = Clean(Safe(texture.GetTexture, texture))
end

local function State(bar)
	local state = dressed[bar]
	if not state then
		local r, g, b = Safe(bar.GetStatusBarColor, bar)
		local fill = Safe(bar.GetStatusBarTexture, bar)
		local vr, vg, vb = 1, 1, 1
		if type(fill) == "table" and fill.GetVertexColor then vr, vg, vb = Safe(fill.GetVertexColor, fill) end
		state = { color = { Clean(r) or 1, Clean(g) or 1, Clean(b) or 1 }, vertex = { Clean(vr) or 1, Clean(vg) or 1, Clean(vb) or 1 } }
		dressed[bar] = state
	end
	return state
end

-- A game text in a font, colour and shadow (its own look kept first).
local function Dress(text, path, size, r, g, b, shadow)
	if not IsText(text) then return end
	if not texts[text] then
		local file, height, flags = Safe(text.GetFont, text)
		local tr, tg, tb, ta = Safe(text.GetTextColor, text)
		local sx, sy = Safe(text.GetShadowOffset, text)
		local sr, sg, sb, sa = Safe(text.GetShadowColor, text)
		texts[text] = { object = Safe(text.GetFontObject, text), file = file, size = height, flags = flags, color = { tr or 1, tg or 1, tb or 1, ta or 1 },
			shadow = { sx or 0, sy or 0, sr or 0, sg or 0, sb or 0, sa or 0 }, alpha = Clean(Safe(text.GetAlpha, text)) or 1 }
	end
	local saved = texts[text]
	if path then pcall(text.SetFont, text, path, size or saved.size or 11, saved.flags or "") end
	if r then text:SetTextColor(r, g, b) end
	if shadow then
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
	end
end

local function Undress(text)
	local saved = texts[text]
	if not saved then return end
	texts[text] = nil
	if saved.object and text.SetFontObject then
		pcall(text.SetFontObject, text, saved.object)
	elseif saved.file then
		pcall(text.SetFont, text, saved.file, saved.size or 11, saved.flags or "")
	end
	text:SetTextColor(unpack(saved.color))
	text:SetShadowOffset(saved.shadow[1], saved.shadow[2])
	text:SetShadowColor(saved.shadow[3], saved.shadow[4], saved.shadow[5], saved.shadow[6])
	text:SetAlpha(saved.alpha)
end

-- (the game shows some again by itself, the target's level circle when the target changes: kept unseen)
local artHooked = setmetatable({}, { __mode = "k" })
local function KeepHidden(region)
	if hiddenArt[region] ~= nil and (Clean(Safe(region.GetAlpha, region)) or 0) > 0 then region:SetAlpha(0) end
end

local function HideArt(region)
	region = Region(region)
	if not region then return end
	if hiddenArt[region] == nil then hiddenArt[region] = Clean(Safe(region.GetAlpha, region)) or 1 end
	region:SetAlpha(0)
	if not artHooked[region] and hooksecurefunc then
		artHooked[region] = true
		for _, method in ipairs({ "SetAlpha", "Show", "SetShown" }) do
			if region[method] then hooksecurefunc(region, method, KeepHidden) end
		end
	end
end

local function ShowArt(region)
	region = Region(region)
	if not region or hiddenArt[region] == nil then return end
	local alpha = hiddenArt[region]
	hiddenArt[region] = nil
	region:SetAlpha(alpha)
end
ns.UnitFramesHideArt, ns.UnitFramesShowArt = HideArt, ShowArt

-- The values' size by the height the eye sees of their bar.
local function ValueSize(bar)
	local height = Clean(Safe(Visible(bar).GetHeight, Visible(bar)))
	if type(height) ~= "number" then return 10 end
	if height >= 13 then return 11 elseif height >= 9 then return 10 end
	return 9
end

local function BarTexts(bar)
	return { Walk(bar, "TextString"), Walk(bar, "LeftText"), Walk(bar, "RightText") }
end

-- Texts of Wanderer's own: short numbers (More settings), or the power's values on the block's own power bar
-- (Ink lines). The game's string hidden, ours written from the same values, shown exactly when the game's would
-- be; never a reading of a hidden number (the game's widgets do it).
local function Percent(bar, value, most)
	local v, m = Clean(value), Clean(most)
	if type(v) == "number" and type(m) == "number" and m > 0 then return math.ceil(v / m * 100) end
	-- (hidden: only a health has its percent from the game)
	local state, curves = dressed[bar], _G.CurveConstants
	local unit = state and state.health
	if not (unit and _G.UnitHealthPercent and curves and curves.ScaleTo100) then return nil end
	return Safe(_G.UnitHealthPercent, unit, true, curves.ScaleTo100)
end

-- A value as the look writes it: short (12.3k) when asked, else grouped as the game does (12,345).
local function Number(value)
	local short = UF().shortNumbers and _G.AbbreviateNumbers
	local write = short or _G.BreakUpLargeNumbers
	if not write then return value end
	local ok, words = pcall(write, value)
	return ok and words or value
end

local function OwnSync(game)
	local mine = hooked[game]
	if type(mine) ~= "table" or not mine.text then return end
	local on = mine.active and Clean(Safe(game.IsShown, game))
	mine.text:SetShown(on and true or false)
end

local function OwnText(bar, game, value, _, most)
	local state = dressed[bar]
	if not IsText(game) then return end
	local mine = hooked[game]
	local host = state and state.mirrored and state.mirror or nil
	local wanted = state and state.on and (host or (UF().shortNumbers and _G.AbbreviateNumbers)) and true or false
	if type(mine) ~= "table" then
		if not wanted then return end
		mine = {}
		hooked[game] = mine
		hooksecurefunc(game, "Show", function() OwnSync(game) end)
		hooksecurefunc(game, "Hide", function() OwnSync(game) end)
	end
	local parent = host or bar
	if mine.parent ~= parent then
		if mine.text then mine.text:Hide() end
		mine.text, mine.parent = parent:CreateFontString(nil, "OVERLAY"), parent
	end
	local text = mine.text
	mine.active = false
	if wanted and not (not IsSecret(value) and (type(value) ~= "number" or value <= 0)) then
		local file, size, flags = Safe(game.GetFont, game)
		local ours = host and UF().texts ~= "game"
		if ours then file, size, flags = NARROW, ValueSize(host) + 1, "" end
		pcall(text.SetFont, text, file or NARROW, size or 11, flags or "")
		if ours then text:SetTextColor(VALUE_COLOR[1], VALUE_COLOR[2], VALUE_COLOR[3]) else text:SetTextColor(Safe(game.GetTextColor, game)) end
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
		text:ClearAllPoints()
		local left, right = game == rawget(bar, "LeftText"), game == rawget(bar, "RightText")
		local point = left and "LEFT" or right and "RIGHT" or "CENTER"
		if host then
			-- (on the block: a single value at its right end, the percent at its left)
			if point == "CENTER" then point = "RIGHT" end
			text:SetJustifyH(point)
			text:SetPoint(point, host, point, point == "LEFT" and 4 or -4, 0)
		else
			text:SetPoint(point, game, point)
		end
		local mode = Clean(Safe(GetCVar, "statusTextDisplay"))
		local ok
		if left or (not right and mode == "PERCENT") then
			local percent = Percent(bar, value, most)
			ok = percent ~= nil and pcall(text.SetFormattedText, text, "%d%%", percent)
		elseif right then
			ok = pcall(function() text:SetFormattedText("%s", Number(value)) end)
		else
			ok = pcall(function() text:SetFormattedText("%s / %s", Number(value), Number(most)) end)
		end
		mine.active = ok and true or false
	end
	if not texts[game] then Dress(game) end
	game:SetAlpha(mine.active and 0 or (texts[game] and texts[game].alpha or 1))
	OwnSync(game)
end

local function WatchTexts(bar)
	if hooked[bar] == "texts" or type(bar.UpdateTextStringWithValues) ~= "function" then return end
	hooked[bar] = "texts"
	hooksecurefunc(bar, "UpdateTextStringWithValues", OwnText)
end

-- The power's own bar of the block taken away: the game's power bar shown again where it is.
-- The game's bar under Wanderer's block takes no mouse (its hover would answer at its old place, beside ours);
-- given back as it was. (never in a fight on a protected frame: then left as it is)
function ns.UnitFramesMouse(bar, state, back)
	if not (bar.EnableMouse and bar.IsMouseEnabled) then return end
	if back then
		if state.mouse == nil then return end
		pcall(bar.EnableMouse, bar, state.mouse)
		state.mouse = nil
		return
	end
	if state.mouse == nil then state.mouse = Clean(Safe(bar.IsMouseEnabled, bar)) and true or false end
	if state.mouse then pcall(bar.EnableMouse, bar, false) end
end

local function Unmirror(bar, state)
	-- (a power bar kept unseen for a character without power: given back)
	if state and state.powerHidden and not state.mirrored then
		bar:SetAlpha(state.alpha or 1)
		state.powerHidden = nil
		ns.UnitFramesMouse(bar, state, true)
	end
	if not (state and state.mirrored) then return end
	ns.UnitFramesMouse(bar, state, true)
	state.mirrored = false
	state.mirror:Hide()
	if state.fillAlpha ~= nil or state.blanked then
		local fill = Safe(bar.GetStatusBarTexture, bar)
		if type(fill) == "table" then
			if state.blanked then
				if state.atlas then pcall(fill.SetAtlas, fill, state.atlas)
				elseif state.file then pcall(fill.SetTexture, fill, state.file) end
			end
			pcall(fill.SetAlpha, fill, state.fillAlpha or 1)
		end
		state.fillAlpha, state.blanked = nil, nil
	end
	if state.powerHidden then
		bar:SetAlpha(state.alpha or 1)
		state.powerHidden = nil
	end
	for _, text in ipairs(BarTexts(bar)) do
		local mine = IsText(text) and hooked[text]
		if type(mine) == "table" and mine.parent == state.mirror then
			mine.active = false
			mine.text:Hide()
			text:SetAlpha(texts[text] and texts[text].alpha or 1)
		end
	end
end

-- A game bar given back as the game had it.
local function RestoreBar(bar)
	local state = dressed[bar]
	-- (a power bar kept unseen for a character without power is given back even when never dressed)
	if state and not state.on then Unmirror(bar, state) end
	if not (state and state.on) then return end
	Unmirror(bar, state)
	state.on = false
	local texture = Safe(bar.GetStatusBarTexture, bar)
	if type(texture) == "table" then
		if state.atlas then pcall(texture.SetAtlas, texture, state.atlas)
		elseif state.file then pcall(texture.SetTexture, texture, state.file) end
	end
	coloring = true
	bar:SetStatusBarColor(unpack(state.color))
	if type(texture) == "table" and texture.SetVertexColor and state.health ~= nil then pcall(texture.SetVertexColor, texture, unpack(state.vertex or { 1, 1, 1 })) end
	coloring = false
	if state.ground then state.ground:Hide() end
	if state.line then state.line:Hide() end
	if state.block then state.block:Hide() end
	if state.icon then
		state.icon:Hide()
		local icon = Walk(bar, "Icon")
		if state.iconCropped and type(icon) == "table" and icon.SetTexCoord then pcall(icon.SetTexCoord, icon, 0, 1, 0, 1) end
		state.iconCropped = nil
	end
	for _, text in ipairs(BarTexts(bar)) do
		if IsText(text) then
			local mine = hooked[text]
			if type(mine) == "table" then
				mine.active = false
				mine.text:Hide()
			end
			Undress(text)
		end
	end
	for _, region in ipairs(state.art or {}) do ShowArt(region) end
end

-- A bar's ground (made once) and, while asked, its quarter marks (A and C: no ink line of its own).
local function Pieces(bar, state, look, r, g, b, plain)
	if not state.ground and CanMake(bar) then state.ground = Ground(bar) end
	if state.ground then
		state.ground:SetVertexColor(GroundColor(look, r, g, b, plain))
		state.ground:Show()
	end
	local marks = state.health ~= nil and look.quarterMarks and not (state.block and state.block:IsShown())
	if marks and not state.line and CanMake(bar) then state.line = InkLine(bar) end
	if state.line then
		state.line:SetShown(marks and true or false)
		state.line.Place(false)
		state.line.Marks(marks)
	end
end

-- The values and the name in the look's fonts (the game's choice of what they say).
local function DressTexts(bar, look)
	for _, text in ipairs(BarTexts(bar)) do
		if IsText(text) then
			if look.texts == "game" then Undress(text) else Dress(text, NARROW, ValueSize(bar), VALUE_COLOR[1], VALUE_COLOR[2], VALUE_COLOR[3], true) end
		end
	end
	WatchTexts(bar)
end

-- The ink line's colour: the game's states on its frames, as a quiet tint of the line while the metal is gone
-- (threat in the game's colour, a fight warm, resting faintly gold).
local THREAT_EDGE, WARY_EDGE = { 0.45, 0.12, 0.1, 1 }, { 0.4, 0.28, 0.08, 1 }
local function Threat(status)
	if type(status) ~= "number" or status < 1 then return nil end
	-- (holding or about to: a dark red; above the others' threat: a dark amber)
	return unpack(status >= 2 and THREAT_EDGE or WARY_EDGE)
end

local function EdgeColor(entry, unit)
	return ns.UnitFramesEdgeColor(entry, unit)
end
-- (Portraits.lua tints the medallion's border the same way)
function ns.UnitFramesEdgeColor(entry, unit)
	if entry.key == "player" then
		local r, g, b, a = Threat(Clean(Safe(UnitThreatSituation, "player")))
		if r then return r, g, b, a end
		if Clean(Safe(UnitAffectingCombat, "player")) then return unpack(COMBAT_EDGE) end
		if Clean(Safe(IsResting)) then return unpack(REST_EDGE) end
	elseif entry.kind == "target" or entry.kind == "boss" then
		local r, g, b, a = Threat(Clean(Safe(UnitThreatSituation, "player", unit)))
		if r then return r, g, b, a end
	end
	return unpack(INK)
end

-- A colour curve per own colour (the hidden percent coloured by the game itself, never read).
local lowCurves = {}
-- What the low-health colour found and did last (the diagnostic dump tells it).
local lowStatus = {}
ns.UnitFramesLowStatus = lowStatus

local function LowCurve(r, g, b)
	local key = ("%.2f %.2f %.2f"):format(r, g, b)
	if lowCurves[key] ~= nil then return lowCurves[key] or nil end
	lowCurves[key] = false
	local api = _G.C_CurveUtil
	if not (api and api.CreateColorCurve and _G.UnitHealthPercent and CreateColor) then
		lowStatus.curve = "absent"
		return nil
	end
	local ok, made = pcall(api.CreateColorCurve)
	if not (ok and type(made) == "table" and made.AddPoint) then
		lowStatus.curve = "refused: " .. tostring(made)
		return nil
	end
	-- (a straight blend between the points, where the game offers to say so)
	local kinds = Enum and Enum.LuaCurveType
	if made.SetType and kinds and kinds.Linear then pcall(made.SetType, made, kinds.Linear) end
	local red, own = CreateColor(LOW_RED[1], LOW_RED[2], LOW_RED[3], 1), CreateColor(r, g, b, 1)
	for _, point in ipairs({ { 0, red }, { LOW_FULL, red }, { LOW_FROM, own }, { 1, own } }) do
		local added, problem = pcall(made.AddPoint, made, point[1], point[2])
		if not added then
			lowStatus.curve = "points refused: " .. tostring(problem)
			return nil
		end
	end
	lowStatus.curve = "made"
	lowCurves[key] = made
	return made
end

-- The colour the game gives back through a curve, in r, g, b (hidden or not), else nil and why.
local function CurveColor(unit, made)
	for _, predicted in ipairs({ true, false }) do
		local ok, color = pcall(_G.UnitHealthPercent, unit, predicted, made)
		if not ok then
			lowStatus.error = "UnitHealthPercent: " .. tostring(color)
		elseif color ~= nil then
			local read, r, g, b = pcall(function() return color:GetRGB() end)
			if read then
				lowStatus.error = nil
				return r, g, b
			end
			lowStatus.error = "GetRGB: " .. tostring(r)
		end
	end
	return nil
end

-- The health's colour at this value: its own above 35 %, blending to the warning red at 20 %. Readable values:
-- worked out here; hidden: the game's curve gives it (nil without it: the own colour stays).
local function LowColor(unit, r, g, b, value, most)
	local v, m = Clean(value), Clean(most)
	-- (the game's own figures first: readable even where the bar's are not)
	if not (type(v) == "number" and type(m) == "number" and m > 0) and unit then
		v, m = Clean(Safe(UnitHealth, unit)), Clean(Safe(UnitHealthMax, unit))
	end
	if type(v) == "number" and type(m) == "number" and m > 0 then
		lowStatus.path, lowStatus.share = "readable", v / m
		local share = v / m
		if share >= LOW_FROM then return r, g, b end
		local t = share <= LOW_FULL and 1 or (LOW_FROM - share) / (LOW_FROM - LOW_FULL)
		return r + (LOW_RED[1] - r) * t, g + (LOW_RED[2] - g) * t, b + (LOW_RED[3] - b) * t
	end
	local made = LowCurve(r, g, b)
	if not made then
		lowStatus.path = "hidden, no curve"
		return nil
	end
	lowStatus.path = "curve"
	return CurveColor(unit, made)
end
ns.UnitFramesLowColor = LowColor

-- Low health in red: yours and your party's (an enemy's health keeps its attitude, as in most games).
local function LowWanted(entry)
	return UF().lowHealth ~= false and (entry.key == "player" or entry.key == "party")
end

-- A health's colour laid twice: on the bar and on its fill itself (some frames tint the fill, not the bar). False
-- when the game kept its own (a bar holding hidden values refuses an addon's colour: your own health on WoW Forever).
local function Paint(bar, r, g, b)
	coloring = true
	pcall(bar.SetStatusBarColor, bar, r, g, b)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if type(fill) == "table" and fill.SetVertexColor then pcall(fill.SetVertexColor, fill, r, g, b) end
	coloring = false
	-- (read back: a colour hidden or not the one given is a colour refused, never assumed taken)
	local nr, ng, nb = Safe(bar.GetStatusBarColor, bar)
	nr, ng, nb = Clean(nr), Clean(ng), Clean(nb)
	if type(nr) ~= "number" or type(ng) ~= "number" or type(nb) ~= "number" then return false end
	return math.abs(nr - r) < 0.02 and math.abs(ng - g) < 0.02 and math.abs(nb - b) < 0.02
end

local function Recolor(bar)
	local state = dressed[bar]
	if coloring or not (state and state.on and state.health) or state.mirrored then return end
	local look = UF()
	local r, g, b, plain = ns.UnitFramesHealthColor(state.health, look)
	if state.ground then state.ground:SetVertexColor(GroundColor(look, r, g, b, plain)) end
	if state.lowBase then
		local _, high = Safe(bar.GetMinMaxValues, bar)
		local lr, lg, lb = LowColor(state.health, r, g, b, Safe(bar.GetValue, bar), high)
		if lr ~= nil then r, g, b = lr, lg, lb end
	end
	Paint(bar, r, g, b)
end

-- The health: its colour again after anything the game did to it (a value, a colour set on the bar or its fill).
local function WatchHealth(bar)
	local state = State(bar)
	if state.watched then return end
	state.watched = true
	bar:HookScript("OnValueChanged", Recolor)
	hooksecurefunc(bar, "SetStatusBarColor", Recolor)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if type(fill) == "table" and type(fill.SetVertexColor) == "function" then
		hooksecurefunc(fill, "SetVertexColor", function() Recolor(bar) end)
	end
end

-- Fine and Classic: the game's health bar itself, in the look's texture and colour. A bar refusing the colour
-- keeps the game's own art (never a white bar).
local function StyleHealth(entry, bar, unit, look)
	local state = State(bar)
	state.health = unit
	Fill(bar, state, TexturePath(look))
	local r, g, b, plain = ns.UnitFramesHealthColor(unit, look)
	state.lowBase = LowWanted(entry) and plain and { r, g, b } or nil
	state.on = true
	if not Paint(bar, r, g, b) then
		local texture = Safe(bar.GetStatusBarTexture, bar)
		if type(texture) == "table" then
			if state.atlas then pcall(texture.SetAtlas, texture, state.atlas)
			elseif state.file then pcall(texture.SetTexture, texture, state.file) end
		end
		if state.ground then state.ground:Hide() end
		state.refused = true
		DressTexts(bar, look)
		WatchHealth(bar)
		return
	end
	state.refused = nil
	Pieces(bar, state, look, r, g, b, plain)
	DressTexts(bar, look)
	WatchHealth(bar)
	if state.lowBase then Recolor(bar) end
end

-- Ink lines: health and power as one block of Wanderer's own bars, laid where the game's health is seen: its
-- width, its top; the health as tall as the game's (16 at most), the power right under it (8 under the large
-- frames, 5 under the small ones). The game's bars stay where they are: the health's fill unseen (its bands and
-- marks still follow it), the power bar unseen; each of ours takes its values as the game gives them (never
-- read, passed on). Every colour is then Wanderer's to give, hidden values or not.
-- The block's sizes by thickness (large frames: you, your target and focus, the bosses; small: the others).
local SIZES = {
	fine = { health = 16, small = 10, power = 8, smallPower = 5 },
	medium = { health = 22, small = 14, power = 8, smallPower = 5 },
	thick = { health = 30, small = 18, power = 10, smallPower = 6 },
}
local LARGE = { player = true, target = true, boss = true }
local function Sizes() return SIZES[UF().thickness] or SIZES.medium end
local function HealthHeight(entry) local size = Sizes() return LARGE[entry.kind] and size.health or size.small end
local function PowerHeight(entry) local size = Sizes() return LARGE[entry.kind] and size.power or size.smallPower end

-- A heal absorb on our health (the part of it the next heals will fill first): from the health's end back,
-- dark red at 0.55 with a fine dark edge, fed by the game's figure as it comes; nothing without one.
local ABSORB = { 0.55, 0.1, 0.08, 0.55 }
local absorbs = setmetatable({}, { __mode = "k" }) -- our health bar -> its absorb
-- A heal coming (a heal being cast on the unit, yours or another's): from the health's end on, a soft green as the
-- game's own prediction, fed by the game's figure (hidden or not), cut at the bar's end. The game draws its own on
-- its bar, unseen under Wanderer's block: this one takes its place. (kept on the bar itself: no new name here)
function ns.UnitFramesIncoming(mirror, unit, width)
	local band = rawget(mirror, "incoming")
	if not band then
		local INCOMING = { 0.35, 0.85, 0.45, 0.45 }
		band = { clip = CreateFrame("Frame", nil, mirror) }
		band.clip:SetAllPoints(mirror)
		band.clip:SetClipsChildren(true)
		band.clip:SetFrameLevel(mirror:GetFrameLevel() + 1)
		band.fill = CreateFrame("StatusBar", nil, band.clip)
		band.fill:SetPoint("TOPLEFT", mirror:GetStatusBarTexture(), "TOPRIGHT")
		band.fill:SetPoint("BOTTOMLEFT", mirror:GetStatusBarTexture(), "BOTTOMRIGHT")
		band.fill:SetStatusBarTexture(WHITE)
		band.fill:SetStatusBarColor(INCOMING[1], INCOMING[2], INCOMING[3], INCOMING[4])
		mirror.incoming = band
	end
	if type(width) == "number" and width > 0 then band.fill:SetWidth(width) end
	local api = _G.UnitGetIncomingHeals
	local most, amount = Safe(UnitHealthMax, unit), api and Safe(api, unit)
	local shown = (IsSecret(amount) or (type(amount) == "number" and amount > 0))
		and pcall(band.fill.SetMinMaxValues, band.fill, 0, most) and pcall(band.fill.SetValue, band.fill, amount)
	band.clip:SetShown(shown and true or false)
end

local function Absorb(mirror, unit)
	-- (its width as Wanderer set it: the game hides a bar's measures once it carries hidden values)
	local width = rawget(mirror, "wandererWidth") or Clean(Safe(mirror.GetWidth, mirror))
	ns.UnitFramesIncoming(mirror, unit, width)
	local api = _G.UnitGetTotalHealAbsorbs
	if not api then return end
	local band = absorbs[mirror]
	if not band then
		local clip = CreateFrame("Frame", nil, mirror)
		clip:SetAllPoints(mirror)
		clip:SetClipsChildren(true)
		clip:SetFrameLevel(mirror:GetFrameLevel() + 1)
		local fill = CreateFrame("StatusBar", nil, clip)
		fill:SetPoint("TOPRIGHT", mirror:GetStatusBarTexture(), "TOPRIGHT")
		fill:SetPoint("BOTTOMRIGHT", mirror:GetStatusBarTexture(), "BOTTOMRIGHT")
		fill:SetReverseFill(true)
		fill:SetStatusBarTexture(WHITE)
		fill:SetStatusBarColor(ABSORB[1], ABSORB[2], ABSORB[3], ABSORB[4])
		local edge = fill:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(0, 0, 0, 0.8)
		edge:SetWidth(1)
		edge:SetPoint("TOPLEFT", fill:GetStatusBarTexture(), "TOPLEFT")
		edge:SetPoint("BOTTOMLEFT", fill:GetStatusBarTexture(), "BOTTOMLEFT")
		band = { clip = clip, fill = fill, unit = unit }
		absorbs[mirror] = band
	end
	band.unit = unit
	if type(width) == "number" and width > 0 then band.fill:SetWidth(width) end
	local most, amount = Safe(UnitHealthMax, unit), Safe(api, unit)
	local shown = (IsSecret(amount) or (type(amount) == "number" and amount > 0))
		and pcall(band.fill.SetMinMaxValues, band.fill, 0, most) and pcall(band.fill.SetValue, band.fill, amount)
	band.clip:SetShown(shown and true or false)
end

local function Mirror(entry, game, look, r, g, b, plain)
	local state = State(game)
	if not state.mirror then
		if not CanMake(entry.frame) then return nil end
		local mirror = CreateFrame("StatusBar", nil, entry.frame)
		mirror.ground = mirror:CreateTexture(nil, "BACKGROUND", nil, -8)
		mirror.ground:SetAllPoints()
		mirror.ground:SetTexture(WHITE)
		mirror:Hide()
		local function Copy()
			if not state.mirrored then return end
			local low, high = Safe(game.GetMinMaxValues, game)
			if low ~= nil and high ~= nil then pcall(mirror.SetMinMaxValues, mirror, low, high) end
			local value = Safe(game.GetValue, game)
			pcall(mirror.SetValue, mirror, value)
			if state.health then Absorb(mirror, state.health) end
			-- (a low health: its colour at this value)
			local base = state.lowBase
			if base and state.health then
				local lr, lg, lb = LowColor(state.health, base[1], base[2], base[3], value, high)
				if lr ~= nil then pcall(mirror.SetStatusBarColor, mirror, lr, lg, lb) end
			end
		end
		mirror.Copy = Copy
		game:HookScript("OnValueChanged", Copy)
		game:HookScript("OnMinMaxChanged", Copy)
		game:HookScript("OnShow", function() if state.mirrored then mirror:Show() end end)
		game:HookScript("OnHide", function() mirror:Hide() end)
		state.mirror = mirror
	end
	local mirror = state.mirror
	state.mirrored = true
	mirror:SetStatusBarTexture(TexturePath(look))
	mirror:SetStatusBarColor(r, g, b)
	mirror.ground:SetVertexColor(GroundColor(look, r, g, b, plain))
	mirror.Copy()
	mirror:SetShown(Clean(Safe(game.IsShown, game)) and true or false)
	return mirror
end

-- The health of the block: ours over the game's place, the game's fill unseen.
local function HealthBlock(entry, bar, unit, look)
	local state = State(bar)
	state.health, state.on = unit, true
	local r, g, b, plain = ns.UnitFramesHealthColor(unit, look)
	state.lowBase = LowWanted(entry) and plain and { r, g, b } or nil
	local mirror = Mirror(entry, bar, look, r, g, b, plain)
	if not mirror then return nil end
	local seen = Visible(bar)
	local height = HealthHeight(entry)
	-- (Fine: as tall as the game's, its size at most; Medium and Thick: theirs, growing downward from its top)
	if UF().thickness == "fine" then
		local game = Clean(Safe(seen.GetHeight, seen))
		if type(game) == "number" and game > 0 then height = math.min(game, height) end
	end
	mirror:SetFrameLevel(math.max(0, Level(bar) - 1))
	ns.UnitFramesMouse(bar, state, false)
	mirror:ClearAllPoints()
	mirror:SetPoint("TOPLEFT", seen, "TOPLEFT", 0, 0)
	mirror:SetPoint("TOPRIGHT", seen, "TOPRIGHT", 0, 0)
	-- (its width kept while it can be read: the game may hide it later)
	local across = Clean(Safe(seen.GetWidth, seen))
	if type(across) == "number" and across > 0 then mirror.wandererWidth = across end
	mirror:SetHeight(height)
	mirror.wandererHeight = height
	mirror.Copy()
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if type(fill) == "table" then
		-- (the game's own texture kept to be given back; the fill keeps its place: the bands follow it)
		KeepFill(state, fill)
		if state.fillAlpha == nil then state.fillAlpha = Clean(Safe(fill.GetAlpha, fill)) or 1 end
		pcall(fill.SetTexture, fill, nil)
		pcall(fill.SetAlpha, fill, 0)
		state.blanked = true
	end
	if state.ground then state.ground:Hide() end
	if state.line then state.line:Hide() end
	DressTexts(bar, look)
	WatchHealth(bar)
	Absorb(mirror, unit)
	return mirror
end

-- A character without any power (most beasts): no power part in the block, never an empty box under the health.
-- (the game hides the figure in a fight now and then: the last clear answer for that character is kept)
local POWER_KEPT = 300 -- characters remembered at most (then forgotten all at once)
local powerCount = 0
local powerKnown = {} -- a character's guid -> it has no power (true) or has one (false), as last told clearly
local function NoPower(unit)
	local most = Safe(UnitPowerMax, unit)
	local guid = Clean(Safe(UnitGUID, unit))
	if IsSecret(most) then
		if guid and powerKnown[guid] ~= nil then return powerKnown[guid] end
		return false
	end
	most = Clean(most)
	local none = type(most) == "number" and most <= 0
	if guid then
		if powerKnown[guid] == nil then
			powerCount = powerCount + 1
			if powerCount > POWER_KEPT then wipe(powerKnown) powerCount = 1 end
		end
		powerKnown[guid] = none
	end
	return none
end

local function StylePower(entry, bar, unit, look, above)
	local state = State(bar)
	state.health = nil
	if above and NoPower(unit) then
		Unmirror(bar, state)
		-- (the game's empty bar stays unseen too)
		state.alpha, state.powerHidden = Clean(Safe(bar.GetAlpha, bar)) or 1, true
		bar:SetAlpha(0)
		ns.UnitFramesMouse(bar, state, false)
		return nil
	end
	local _, token = Safe(UnitPowerType, unit)
	local r, g, b = ns.UnitFramesPowerColor(Clean(token), look)
	state.on = true
	-- (the resource in its own full colour, always: the ink rule between the two bars tells them apart)
	local mirror = above and Mirror(entry, bar, look, r, g, b, true)
	if mirror then
		if not state.powerHidden then
			state.alpha, state.powerHidden = Clean(Safe(bar.GetAlpha, bar)) or 1, true
		end
		bar:SetAlpha(0)
		ns.UnitFramesMouse(bar, state, false)
		mirror:SetFrameLevel(above:GetFrameLevel())
		mirror:ClearAllPoints()
		mirror:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -Pixel(above))
		mirror:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -Pixel(above))
		mirror:SetHeight(PowerHeight(entry))
		mirror.wandererHeight = PowerHeight(entry)
		if state.ground then state.ground:Hide() end
		if state.line then state.line:Hide() end
		WatchTexts(bar)
		-- (its texts on the block now, from the values the game gave its bar)
		local value = Safe(bar.GetValue, bar)
		local low, high = Safe(bar.GetMinMaxValues, bar)
		for _, text in ipairs(BarTexts(bar)) do
			if IsText(text) then OwnText(bar, text, value, low, high) end
		end
		return mirror
	end
	Unmirror(bar, state)
	Fill(bar, state, TexturePath(look))
	bar:SetStatusBarColor(r, g, b)
	Pieces(bar, state, look, r, g, b, true)
	DressTexts(bar, look)
	return nil
end

-- The fine ink link between the portrait's ring and the block: across the gap at the block's health middle, only
-- for a real gap (2 to 24 px), never luminous.
local function Link(entry, block, upper)
	local portrait = ns.UnitFramePortrait and ns.UnitFramePortrait(entry.frame)
	block.link = block.link or block:CreateTexture(nil, "OVERLAY")
	local link = block.link
	link:Hide()
	if not (portrait and upper) then return end
	local pl, pr = Clean(Safe(portrait.GetLeft, portrait)), Clean(Safe(portrait.GetRight, portrait))
	local ul, ur = Clean(Safe(upper.GetLeft, upper)), Clean(Safe(upper.GetRight, upper))
	local height = Clean(Safe(upper.GetHeight, upper))
	if not (pl and pr and ul and ur and height) then return end
	local px = Pixel(upper)
	local gap
	link:ClearAllPoints()
	if pr <= ul then
		gap = ul - pr
		link:SetPoint("TOPRIGHT", upper, "TOPLEFT", -px, -math.floor(height / 2))
	elseif pl >= ur then
		gap = pl - ur
		link:SetPoint("TOPLEFT", upper, "TOPRIGHT", px, -math.floor(height / 2))
	end
	if not gap or gap < 2 or gap > 24 then return end
	link:SetSize(gap - px, px)
	link:SetColorTexture(0, 0, 0, 0.6)
	link:Show()
end

-- The block's ink line: around our health and its power, a 1 px rule between them, the quarter marks if asked.
local function Block(entry, health, upper, lower, look)
	local state = State(health)
	if not state.block then
		if not CanMake(entry.frame) then return end
		state.block = InkLine(health, entry.frame, lower)
	end
	local block = state.block
	block.upper, block.lower = upper, lower
	block:Show()
	block.Place(true)
	block.Marks(look.quarterMarks and true or false)
	block.Color(EdgeColor(entry, UnitOf(entry)))
	if state.line then state.line:Hide() end
	Link(entry, block, upper)
end

local function Unblock(health)
	local state = health and dressed[health]
	if state and state.block then state.block:Hide() end
end

-- The health area and fill the eye sees on a game bar Wanderer's block covers (the bands follow them), or nil.
function ns.UnitFramesArea(bar)
	local state = type(bar) == "table" and dressed[bar]
	return state and state.mirrored and state.health and state.mirror or nil
end
function ns.UnitFramesFill(bar)
	local area = ns.UnitFramesArea(bar)
	return area and area:GetStatusBarTexture() or nil
end

-- Cast bars -----------------------------------------------------------------------------------------------

local CAST_KINDS = { standard = "cast", channel = "channel", uninterruptable = "locked", uninterruptible = "locked", interrupted = "failed",
	empowered = "channel" }

local function CastArt(bar)
	return { Walk(bar, "Border"), Walk(bar, "TextBorder") }
end

-- A cast bar's icon in Ink lines: cropped to its square, a 1 px ink frame around it; given back otherwise.
local function IconFrame(bar, state, edged)
	local icon = Walk(bar, "Icon")
	if type(icon) ~= "table" or IsSecret(icon) or not icon.SetTexCoord then return end
	if edged and not state.icon and CanMake(bar) then
		local frame = CreateFrame("Frame", nil, bar)
		frame:SetFrameLevel(Level(bar) + 1)
		frame.edges = {}
		for index = 1, 4 do frame.edges[index] = frame:CreateTexture(nil, "OVERLAY") end
		state.icon = frame
	end
	local frame = state.icon
	if not frame then return end
	if edged then
		local px = Pixel(bar)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", icon, "TOPLEFT", -px, px)
		frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", px, -px)
		local top, bottom, left, right = unpack(frame.edges)
		for _, edge in ipairs(frame.edges) do edge:ClearAllPoints() end
		top:SetPoint("TOPLEFT", frame, "TOPLEFT")
		top:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
		top:SetHeight(px)
		bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
		bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
		bottom:SetHeight(px)
		left:SetPoint("TOPLEFT", frame, "TOPLEFT")
		left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
		left:SetWidth(px)
		right:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
		right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
		right:SetWidth(px)
		for _, edge in ipairs(frame.edges) do edge:SetColorTexture(unpack(INK)) end
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		state.iconCropped = true
		frame:Show()
	else
		frame:Hide()
		if state.iconCropped then
			pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
			state.iconCropped = nil
		end
	end
end

local function StyleCast(bar)
	local state = dressed[bar]
	if not FrameOn("castBars") or not (state and state.cast) then return end
	local look = UF()
	local kind = rawget(bar, "barType")
	local edged = Lines()
	-- (a hidden kind of cast: the game's look for it, never a wrong colour)
	if IsSecret(kind) then
		bar:SetStatusBarColor(unpack(state.color))
		return
	end
	state.cast, state.on = true, true
	Fill(bar, state, TexturePath(look))
	bar:SetStatusBarColor(ns.UnitFramesCastColor(CAST_KINDS[kind] or "cast", look))
	Pieces(bar, state, look, nil, nil, nil, false)
	if edged and not state.block and CanMake(bar) then state.block = InkLine(bar) end
	if state.block then
		state.block:SetShown(edged)
		state.block.Place(edged)
	end
	local text = IsText(Walk(bar, "Text"))
	if text then
		if look.texts == "game" then Undress(text) else Dress(text, ns.Skin.FontPath(ns.db.label.font), 10, NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3], true) end
	end
	state.art = CastArt(bar)
	for _, region in ipairs(state.art) do
		if edged then HideArt(region) else ShowArt(region) end
	end
	IconFrame(bar, state, edged)
end

local function DressCast(bar)
	if not IsBar(bar) then return end
	local state = State(bar)
	state.cast = true
	if not hooked[bar] then
		hooked[bar] = "cast"
		if type(bar.UpdateBarFillTexture) == "function" then
			hooksecurefunc(bar, "UpdateBarFillTexture", StyleCast)
		else
			bar:HookScript("OnEvent", StyleCast)
		end
	end
	StyleCast(bar)
end

-- The block's extras (Ink lines) ---------------------------------------------------------------------------------
-- Under the power, while there are any: your class points (combo points: rogues, druids in cat form), a row of
-- pips as wide as the block; under them, while a spell is cast: the cast bar, its icon square at its left in a fine
-- ink frame, the spell's name at the left, its time at the right. Both are Wanderer's, fed by the game: the points
-- by its own count (each pip a bar from i - 1 to i given the count as it comes, hidden or not), the cast by the
-- game's cast bar (its values, its words and its icon passed on as they come, never read). The game's own cast bar
-- is kept unseen at its place meanwhile (Edit Mode open: shown again); its combo frame too.

local PIPS = 5
local PIP_GAP = 2
local POINT_COLOR = { 0.85, 0.33, 0.17 } -- combo points: the classic red-orange, apart from any health or power
local CAST_NEUTRAL = { 0.75, 0.72, 0.66 } -- a cast whose kind is hidden: no colour that could be wrong
local extras = setmetatable({}, { __mode = "k" }) -- a unit frame -> its points and cast

-- A thin ink frame (1 px) around a region of ours, its own frame one level up.
local function InkBox(parent, region)
	local box = CreateFrame("Frame", nil, parent)
	box:SetFrameLevel(Level(parent) + 1)
	box.edges = {}
	for index = 1, 4 do
		local edge = box:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(unpack(INK))
		box.edges[index] = edge
	end
	function box.Place()
		local px = Pixel(parent)
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", region, "TOPLEFT", -px, px)
		box:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", px, -px)
		local top, bottom, left, right = unpack(box.edges)
		for _, edge in ipairs(box.edges) do edge:ClearAllPoints() end
		top:SetPoint("TOPLEFT", box, "TOPLEFT")
		top:SetPoint("TOPRIGHT", box, "TOPRIGHT")
		top:SetHeight(px)
		bottom:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT")
		bottom:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
		bottom:SetHeight(px)
		left:SetPoint("TOPLEFT", box, "TOPLEFT")
		left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT")
		left:SetWidth(px)
		right:SetPoint("TOPRIGHT", box, "TOPRIGHT")
		right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
		right:SetWidth(px)
	end
	return box
end

-- Your class points now (the game's count, maybe hidden) and how many there can be; nil: none for you now.
local function Points()
	local _, class = Safe(UnitClass, "player")
	class = Clean(class)
	if class ~= "ROGUE" and class ~= "DRUID" then return nil end
	-- (a druid: in cat form only, the form whose power is energy)
	if class == "DRUID" then
		local _, token = Safe(UnitPowerType, "player")
		if Clean(token) ~= "ENERGY" then return nil end
	end
	local kinds = Enum and Enum.PowerType
	local kind = kinds and kinds.ComboPoints
	if kind and UnitPower then
		local count = Safe(UnitPower, "player", kind)
		local most = Clean(Safe(UnitPowerMax, "player", kind))
		if count ~= nil then return count, type(most) == "number" and most > 0 and most or PIPS end
	end
	if _G.GetComboPoints then
		local count = Safe(_G.GetComboPoints, "player", "target")
		if count ~= nil then return count, PIPS end
	end
	return nil
end

-- The points row is worth showing: points held (a hidden count: in a fight, so yes), or a fight with a target.
local function PointsWorth(count)
	if count == nil then return false end
	if IsSecret(count) then return true end
	if type(count) == "number" and count > 0 then return true end
	return Clean(Safe(UnitAffectingCombat, "player")) and Clean(Safe(UnitExists, "target")) and true or false
end

local function PointsRow(entry)
	local row = CreateFrame("Frame", nil, entry.frame)
	row.pips = {}
	for index = 1, PIPS do
		local pip = CreateFrame("StatusBar", nil, row)
		pip:SetMinMaxValues(index - 1, index)
		pip:SetValue(0)
		pip.ground = pip:CreateTexture(nil, "BACKGROUND", nil, -8)
		pip.ground:SetAllPoints()
		pip.ground:SetColorTexture(unpack(GROUND.dark))
		pip.box = InkBox(pip, pip)
		row.pips[index] = pip
	end
	return row
end

-- The pips laid across the block's width (count of them), filled from the game's count.
local function FillPoints(row, look, count, most)
	-- (a column beside the block: the points stacked from the bottom up; else a row under it)
	local vertical = row.vertical and true or false
	local length = vertical and (row.blockHeight or Clean(Safe(row.GetHeight, row))) or (row.blockWidth or Clean(Safe(row.GetWidth, row)))
	most = math.max(1, math.min(PIPS, most or PIPS))
	local each = type(length) == "number" and length > 0 and (length - (most - 1) * PIP_GAP) / most or 20
	for index, pip in ipairs(row.pips) do
		local shown = index <= most
		pip:SetShown(shown)
		if shown then
			pip:ClearAllPoints()
			local step = (index - 1) * (each + PIP_GAP)
			if vertical then
				pip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, step)
				pip:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, step)
				pip:SetHeight(each)
			else
				pip:SetPoint("TOPLEFT", row, "TOPLEFT", step, 0)
				pip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", step, 0)
				pip:SetWidth(each)
			end
			if pip.SetOrientation then pip:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL") end
			pip:SetStatusBarTexture(TexturePath(look))
			pip:SetStatusBarColor(unpack(POINT_COLOR))
			pcall(pip.SetValue, pip, count)
			pip.box.Place()
		end
	end
end

-- Our cast bar: icon square, bar, name, time, its ink frames; fed by the game's cast bar.
local function CastRow(entry, game)
	local row = CreateFrame("Frame", nil, entry.frame)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar.ground = row.bar:CreateTexture(nil, "BACKGROUND", nil, -8)
	row.bar.ground:SetAllPoints()
	row.bar.ground:SetColorTexture(unpack(GROUND.dark))
	row.name = row.bar:CreateFontString(nil, "OVERLAY")
	row.time = row.bar:CreateFontString(nil, "OVERLAY")
	for _, text in ipairs({ row.name, row.time }) do
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
		text:SetTextColor(VALUE_COLOR[1], VALUE_COLOR[2], VALUE_COLOR[3])
	end
	row.name:SetJustifyH("LEFT")
	row.time:SetJustifyH("RIGHT")
	row.iconBox = InkBox(row, row.icon)
	row.barBox = InkBox(row, row.bar)
	row:Hide()
	row.active = false
	local function Copy()
		if not row.active then return end
		local low, high = Safe(game.GetMinMaxValues, game)
		if low ~= nil and high ~= nil then pcall(row.bar.SetMinMaxValues, row.bar, low, high) end
		pcall(row.bar.SetValue, row.bar, (Safe(game.GetValue, game)))
	end
	-- (its words and its icon as the game writes them)
	local function Words()
		if not row.active then return end
		local name, timeText, icon = Walk(game, "Text"), Walk(game, "CastTimeText"), Walk(game, "Icon")
		if IsText(name) then pcall(row.name.SetText, row.name, (Safe(name.GetText, name))) end
		if IsText(timeText) and Clean(Safe(timeText.IsShown, timeText)) then
			pcall(row.time.SetText, row.time, (Safe(timeText.GetText, timeText)))
		else
			row.time:SetText("")
		end
		if type(icon) == "table" and icon.GetTexture then pcall(row.icon.SetTexture, row.icon, (Safe(icon.GetTexture, icon))) end
		local kind = rawget(game, "barType")
		local color = IsSecret(kind) and CAST_NEUTRAL or { ns.UnitFramesCastColor(CAST_KINDS[kind] or "cast", UF()) }
		row.bar:SetStatusBarColor(color[1], color[2], color[3])
	end
	row.Copy, row.Words = Copy, Words
	game:HookScript("OnValueChanged", Copy)
	game:HookScript("OnMinMaxChanged", Copy)
	-- (shown from a cast's start; at its end, held a moment, then gone: success 0.3 s, interrupted or failed in red
	-- 0.5 s)
	row.serial = 0
	function row.Begin()
		if not row.active then return end
		row.serial, row.holding = row.serial + 1, false
		Words()
		Copy()
		row:Show()
	end
	function row.Finish(failed)
		if not row:IsShown() then return end
		row.serial, row.holding = row.serial + 1, true
		local serial = row.serial
		if failed then
			local red = { ns.UnitFramesCastColor("failed", UF()) }
			row.bar:SetStatusBarColor(red[1], red[2], red[3])
		end
		C_Timer.After(failed and 0.5 or 0.3, function()
			if row.serial == serial then
				row.holding = false
				row:Hide()
			end
		end)
	end
	function row.Drop()
		row.serial, row.holding = row.serial + 1, false
		row:Hide()
	end
	if type(game.UpdateBarFillTexture) == "function" then hooksecurefunc(game, "UpdateBarFillTexture", Words) end
	local text = Walk(game, "Text")
	if IsText(text) then hooksecurefunc(text, "SetText", Words) end
	local timeText = Walk(game, "CastTimeText")
	if IsText(timeText) then hooksecurefunc(timeText, "SetText", Words) end
	return row
end

local castRows = {} -- unit -> its cast row
-- The unit casting or channelling now (a hidden name still says so).
local function Casting(unit)
	local name = Safe(UnitCastingInfo, unit)
	if name == nil and _G.UnitChannelInfo then name = Safe(_G.UnitChannelInfo, unit) end
	return name ~= nil
end

local castWatch = CreateFrame("Frame")
local START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true }
local DONE = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_SUCCEEDED = true,
	UNIT_SPELLCAST_EMPOWER_STOP = true }
local FAILED = { UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }
for _, list in ipairs({ START, DONE, FAILED }) do
	for event in pairs(list) do pcall(castWatch.RegisterEvent, castWatch, event) end
end
pcall(castWatch.RegisterEvent, castWatch, "PLAYER_TARGET_CHANGED")
castWatch:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then
		local row = castRows.target
		if row and row.active then
			if Casting("target") then row.Begin() else row.Drop() end
		end
		return
	end
	local row = castRows[Clean(unit) or ""]
	if not (row and row.active) then return end
	if START[event] then
		row.Begin()
	elseif FAILED[event] then
		row.Finish(true)
	elseif DONE[event] and not Casting(row.unit) then
		row.Finish(false)
	end
end)

local function CastHeight(entry) return LARGE[entry.kind] and 12 or 9 end

-- The extras of a frame laid under its block (anchor: the lowest bar of the block), or taken away.
local function Extras(entry, parts, anchor, look, edged)
	local mine = extras[entry.frame]
	if not edged or not anchor then
		if mine then
			if mine.points then mine.points:Hide() end
			if mine.cast then
				mine.cast.active = false
				mine.cast:Hide()
			end
			if mine.gameCast then ShowArt(mine.gameCast) end
			for _, region in ipairs(mine.comboArt or {}) do ShowArt(region) end
		end
		return
	end
	if not mine then
		if not CanMake(entry.frame) then return end
		mine = {}
		extras[entry.frame] = mine
	end
	local px = Pixel(anchor)
	local below = anchor
	-- Your points (the player's block only).
	if entry.key == "player" then
		local count, most = Points()
		mine.comboArt = { _G.ComboFrame, _G.ComboPointPlayerFrame, Walk(entry.frame, "classPowerBar") }
		for _, region in ipairs(mine.comboArt) do HideArt(region) end
		if PointsWorth(count) then
			mine.points = mine.points or PointsRow(entry)
			local row = mine.points
			row:SetFrameLevel(anchor:GetFrameLevel())
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(PIP_GAP + px))
			row:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -(PIP_GAP + px))
			row:SetHeight(UF().thickness == "thick" and 5 or 4)
			row.wandererHeight = UF().thickness == "thick" and 5 or 4
			-- (the block's exact width: the game's visible health, measured, never a guess before the row is laid)
			row.vertical = false -- (a row under the block; the large frames' composition stands it up beside it)
			row.blockWidth = Clean(Safe(anchor.GetWidth, anchor)) or Clean(Safe(Visible(parts.health).GetWidth, Visible(parts.health)))
			row:Show()
			FillPoints(row, look, count, most)
			below = row
		elseif mine.points then
			mine.points:Hide()
		end
	end
	-- The cast bar (the game's own kept unseen at its place).
	local game = parts.cast
	if game and UF().castInBlock ~= false and FrameOn("castBars") then
		-- (another cast bar of the game than the one followed: a row for it)
		if mine.cast and mine.gameCast ~= game then
			mine.cast.active = false
			mine.cast:Hide()
			mine.cast = nil
		end
		mine.cast = mine.cast or CastRow(entry, game)
		mine.gameCast = game
		local row = mine.cast
		local height = CastHeight(entry)
		row:SetFrameLevel(anchor:GetFrameLevel())
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -(PIP_GAP + 1 + px))
		row:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -(PIP_GAP + 1 + px))
		row:SetHeight(height)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		row.icon:SetSize(height, height)
		row.bar:ClearAllPoints()
		row.bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", PIP_GAP + px, 0)
		row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
		row.bar:SetStatusBarTexture(TexturePath(look))
		local size = math.max(9, height - 2)
		pcall(row.name.SetFont, row.name, ns.Skin.FontPath(ns.db.label.font), size, "")
		pcall(row.time.SetFont, row.time, NARROW, size, "")
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", row.bar, "LEFT", 4, 0)
		row.name:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
		if row.name.SetWordWrap then row.name:SetWordWrap(false) end
		row.time:ClearAllPoints()
		row.time:SetPoint("RIGHT", row.bar, "RIGHT", -4, 0)
		row.iconBox.Place()
		row.barBox.Place()
		row.active = true
		HideArt(game)
		row.unit = UnitOf(entry)
		castRows[row.unit] = row
		-- (a cast going on now: shown at once, else nothing until the next one starts)
		if Casting(row.unit) then row.Begin() elseif not row.holding then row.Drop() end
	else
		if mine.cast then
			mine.cast.active = false
			mine.cast:Hide()
		end
		if mine.gameCast then ShowArt(mine.gameCast) end
	end
end

-- (the points change: drawn again with the block)
local pointsWatch = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UPDATE_SHAPESHIFT_FORM", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED" }) do
	pcall(pointsWatch.RegisterEvent, pointsWatch, event)
end
pointsWatch:SetScript("OnEvent", function(_, event, unit)
	if (event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE") and Clean(unit) ~= "player" then return end
	if not Lines() then return end
	local frame = _G.PlayerFrame
	local mine = type(frame) == "table" and extras[frame]
	local row = mine and mine.points
	local count, most = Points()
	local shown = row and row:IsShown() or false
	local worth = PointsWorth(count)
	if row and shown and worth then return FillPoints(row, UF(), count, most) end
	if shown ~= worth and ns.UnitFramesSoon then ns.UnitFramesSoon() end
end)

-- The name a size up from the game's own (kept to come back), 12 at most.
local function NameSize(name)
	local saved = texts[name]
	local size = saved and saved.size
	if size == nil then size = select(2, Safe(name.GetFont, name)) end
	size = Clean(size)
	if type(size) ~= "number" then return nil end
	return math.min(12, size + 1)
end

-- The composition (Ink lines): the name and the block together, centred on the portrait's middle, whatever the
-- thickness. The block is ours: its health is set at that height (power, points and the cast follow it); the
-- game's name, which cannot move, stays unseen meanwhile and ours, the same words, sits just above the block,
-- left-aligned with it. The cast row comes and goes below: never counted, so nothing moves when it shows.
local NAME_GAP = 3
local Compose, HealthOverlays, Trail
local ourNames = setmetatable({}, { __mode = "k" }) -- a unit frame -> our name over its block

local function OurName(entry, game)
	local mine = ourNames[entry.frame]
	if mine then return mine end
	mine = { text = entry.frame:CreateFontString(nil, "OVERLAY") }
	mine.text:SetJustifyH("LEFT")
	if mine.text.SetWordWrap then mine.text:SetWordWrap(false) end
	mine.text:SetShadowOffset(1, -1)
	mine.text:SetShadowColor(0, 0, 0, 1)
	-- (the game's words copied each time it writes them, hidden or not)
	hooksecurefunc(game, "SetText", function(_, words) pcall(mine.text.SetText, mine.text, words) end)
	ourNames[entry.frame] = mine
	return mine
end

-- (the height Wanderer gave its own bars, kept: the game makes a bar's measures secret once it is fed hidden
-- values, and a secret reads as nothing; else the measure)
local function Height(frame)
	if not frame then return 0 end
	local known = rawget(frame, "wandererHeight")
	if type(known) == "number" then return known end
	local height = Clean(Safe(frame.GetHeight, frame))
	return type(height) == "number" and height or 0
end

-- The large frames (you, your target, the bosses), as one composition around the portrait: the name above the
-- portrait; the health and the power beside it, together exactly its height (the health takes what the power
-- leaves); the points in a column beside them; the cast under it all, from the portrait's outer edge to the
-- block's. The target and the bosses in mirror (the block on the portrait's left). Whatever a character does not
-- have (power, points, a cast) is not drawn at all, nor its frame.
local ARRANGE_GAP = 4
-- (the large frames' composition, Arrange below)
-- The target's auras above it (the game's own setting): they stand where the game's name was, just over the
-- portrait's top. The whole composition (name, portrait, block, cast) then comes down by the name's room, never
-- the game's auras moved (moving them from an addon would leave its mark on them).
local NAME_ROOM = 15
function ns.UnitFramesDrop(entry)
	if type(entry) ~= "table" or entry.kind ~= "target" or not Lines() then return 0 end
	return rawget(entry.frame, "buffsOnTop") and NAME_ROOM or 0
end

local arranged = setmetatable({}, { __mode = "k" }) -- a unit frame -> what it was last arranged with
local watchedPower = setmetatable({}, { __mode = "k" })
local Arrange
-- (the power coming or going later, a form changed, a power appearing: the health takes its height again at once)
local function Rearrange(frame)
	local last = arranged[frame]
	if last and Lines() then Arrange(last.entry, last.parts, last.upper, last.lower, last.portrait, last.size, "power shown/hidden") end
end

-- (a short log of your own frame's arrangements, kept through a /reload in WandererDB.framesLog: what a form
-- change did, read after it; the last LOG_KEPT only)
function ns.UnitFramesLog(entry, why, lower, health, withPower)
	local LOG_KEPT = 40
	if entry.key ~= "player" or not ns.root then return end
	local log = type(ns.root.framesLog) == "table" and ns.root.framesLog or {}
	ns.root.framesLog = log
	local _, token = Safe(UnitPowerType, "player")
	log[#log + 1] = ("%.2f %s | form=%s token=%s max=%s noPower=%s | lower=%s shown=%s height=%s | health=%s withPower=%s"):format(
		GetTime(), why, tostring(Clean(Safe(_G.GetShapeshiftForm))), tostring(Clean(token)), tostring(Clean(Safe(UnitPowerMax, "player"))),
		tostring(NoPower("player")), tostring(lower ~= nil), tostring(lower and lower:IsShown()), tostring(lower and Height(lower)),
		tostring(health), tostring(withPower))
	while #log > LOG_KEPT do table.remove(log, 1) end
end

function Arrange(entry, parts, upper, lower, portrait, size, why)
	local flip = entry.kind ~= "player"
	local drop = ns.UnitFramesDrop(entry)
	arranged[entry.frame] = { entry = entry, parts = parts, upper = upper, lower = lower, portrait = portrait, size = size }
	if lower and not watchedPower[lower] then
		watchedPower[lower] = true
		local frame = entry.frame
		lower:HookScript("OnShow", function() Rearrange(frame) end)
		lower:HookScript("OnHide", function() Rearrange(frame) end)
	end
	local px = Pixel(upper)
	local seen = Visible(parts.health)
	local width = Clean(Safe(seen.GetWidth, seen))
	if type(width) ~= "number" or width <= 0 then width = 124 end
	local withPower = lower and lower:IsShown() and true or false
	local health = size - 2 * px - (withPower and (Height(lower) + px) or 0)
	upper:ClearAllPoints()
	if flip then
		upper:SetPoint("TOPRIGHT", portrait, "TOPLEFT", -(ARRANGE_GAP + px), -px - drop)
	else
		upper:SetPoint("TOPLEFT", portrait, "TOPRIGHT", ARRANGE_GAP + px, -px - drop)
	end
	upper:SetWidth(width)
	upper.wandererWidth = width
	upper:SetHeight(math.max(4, math.floor(health + 0.5)))
	upper.wandererHeight = math.max(4, math.floor(health + 0.5))
	ns.UnitFramesLog(entry, why or "drawn", lower, math.floor(health + 0.5), withPower)
	local name = ourNames[entry.frame]
	if name and name.text:IsShown() then
		local text = name.text
		text:ClearAllPoints()
		text:SetJustifyH(flip and "RIGHT" or "LEFT")
		if flip then
			text:SetPoint("BOTTOMRIGHT", portrait, "TOPRIGHT", 0, NAME_GAP - drop)
			text:SetPoint("BOTTOMLEFT", upper, "TOPLEFT", -px, NAME_GAP + px)
		else
			text:SetPoint("BOTTOMLEFT", portrait, "TOPLEFT", 0, NAME_GAP - drop)
			text:SetPoint("BOTTOMRIGHT", upper, "TOPRIGHT", px, NAME_GAP + px)
		end
	end
	local extra = extras[entry.frame]
	-- The points: a column beside the block, its full height.
	local points = extra and extra.points
	if points and points:IsShown() then
		local bottom = withPower and lower or upper
		local side = ARRANGE_GAP + 2 * px
		points:ClearAllPoints()
		if flip then
			points:SetPoint("TOPRIGHT", upper, "TOPLEFT", -side, 0)
			points:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMLEFT", -side, 0)
		else
			points:SetPoint("TOPLEFT", upper, "TOPRIGHT", side, 0)
			points:SetPoint("BOTTOMLEFT", bottom, "BOTTOMRIGHT", side, 0)
		end
		points:SetWidth(UF().thickness == "thick" and 9 or 7)
		points.vertical = true
		points.blockHeight = size - 2 * px
		local count, most = Points()
		FillPoints(points, UF(), count, most)
	end
	-- The cast: under the portrait and the block, from one outer edge to the other.
	local cast = extra and extra.cast
	if cast and cast.active then
		local down = -(ARRANGE_GAP + px) - drop
		cast:ClearAllPoints()
		if flip then
			cast:SetPoint("TOPRIGHT", portrait, "BOTTOMRIGHT", -px, down)
			cast:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", -(ARRANGE_GAP + px + width), down)
		else
			cast:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", px, down)
			cast:SetPoint("TOPRIGHT", portrait, "BOTTOMRIGHT", ARRANGE_GAP + px + width, down)
		end
		if cast.iconBox then cast.iconBox.Place() end
		if cast.barBox then cast.barBox.Place() end
	end
	-- The ink box around what is shown now (the power come or gone since the block was boxed), no link drawn
	-- across the gap to the portrait: two clean shapes side by side.
	local state = dressed[parts.health]
	local block = state and state.block
	if block then
		block.lower = withPower and lower or nil
		block.Place(true)
		if block.link then block.link:Hide() end
	end
end

Compose = function(entry, parts, upper, lower, look)
	local mine = ourNames[entry.frame]
	local game = parts.name
	if not upper then
		arranged[entry.frame] = nil
		if mine then mine.text:Hide() end
		if game then ShowArt(game) end
		return
	end
	-- The name over the block: ours, in the look's font (the game's while the look's texts are the game's).
	local nameHeight = 0
	if game then
		mine = OurName(entry, game)
		local text = mine.text
		local file, size = Safe(game.GetFont, game)
		if look.texts ~= "game" then file, size = ns.Skin.FontPath(ns.db.label.font), NameSize(game) or size end
		pcall(text.SetFont, text, file or NARROW, Clean(size) or 11, "")
		if look.texts ~= "game" then text:SetTextColor(NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3]) else text:SetTextColor(Safe(game.GetTextColor, game)) end
		pcall(text.SetText, text, (Safe(game.GetText, game)))
		text:SetParent(upper)
		text:ClearAllPoints()
		text:SetPoint("BOTTOMLEFT", upper, "TOPLEFT", 1, NAME_GAP)
		text:SetPoint("BOTTOMRIGHT", upper, "TOPRIGHT", -1, NAME_GAP)
		text:Show()
		HideArt(game)
		nameHeight = (Clean(size) or 11) + NAME_GAP
	end
	-- The large frames: arranged around the portrait.
	local portrait = ns.UnitFramePortrait and ns.UnitFramePortrait(entry.frame)
	local size = portrait and Height(portrait)
	if LARGE[entry.kind] and size and size > 0 then return Arrange(entry, parts, upper, lower, portrait, size) end
	-- The block's height: health, power, points (when shown).
	local px = Pixel(upper)
	local block = Height(upper)
	if lower and lower:IsShown() then block = block + px + Height(lower) end
	local extra = extras[entry.frame]
	if extra and extra.points and extra.points:IsShown() then block = block + PIP_GAP + px + Height(extra.points) end
	-- Centred on the portrait's middle (no portrait, or no measure: the game's top kept).
	local seen = Visible(parts.health)
	local _, middle = Safe(portrait and portrait.GetCenter, portrait)
	middle = Clean(middle)
	local top = Clean(Safe(seen.GetTop, seen))
	local offset = 0
	if type(middle) == "number" and type(top) == "number" then
		local group = nameHeight + block
		offset = math.floor(middle + group / 2 - nameHeight - top + 0.5)
	end
	upper:ClearAllPoints()
	upper:SetPoint("TOPLEFT", seen, "TOPLEFT", 0, offset)
	upper:SetPoint("TOPRIGHT", seen, "TOPRIGHT", 0, offset)
end

-- The unit frames -------------------------------------------------------------------------------------------


-- The game's overlays on a health bar: heal predictions, absorbs and their glows, the lost maximum, the trail.
local OVERLAYS = { "myHealPredictionBar", "otherHealPredictionBar", "healAbsorbBar", "totalAbsorbBar", "overAbsorbGlow",
	"overHealAbsorbGlow", "tempMaxHealthLossBar", "myHealAbsorb", "myHealAbsorbLeftShadow", "myHealAbsorbRightShadow",
	"otherHealPrediction", "myHealPrediction", "totalAbsorb", "totalAbsorbOverlay", "overAbsorbGlow" }
function HealthOverlays(entry, parts)
	local list = {}
	for _, key in ipairs(OVERLAYS) do
		local region = Region(Walk(entry.frame, key))
		if region and region ~= parts.health then list[#list + 1] = region end
	end
	if parts.trail then list[#list + 1] = parts.trail end
	return list
end

-- The game's damage trail (its red chunk at each hit): its fill emptied under the block, given back after.
local trails = setmetatable({}, { __mode = "k" })
function Trail(bar, hidden)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if type(fill) ~= "table" then return end
	local kept = trails[bar]
	if hidden then
		if not kept then
			kept = { atlas = Clean(Safe(fill.GetAtlas, fill)), file = Clean(Safe(fill.GetTexture, fill)), alpha = Clean(Safe(fill.GetAlpha, fill)) or 1 }
			trails[bar] = kept
		end
		pcall(fill.SetTexture, fill, nil)
		pcall(fill.SetAlpha, fill, 0)
	elseif kept then
		trails[bar] = nil
		if kept.atlas then pcall(fill.SetAtlas, fill, kept.atlas) elseif kept.file then pcall(fill.SetTexture, fill, kept.file) end
		pcall(fill.SetAlpha, fill, kept.alpha)
	end
end

local function StyleEntry(entry)
	local parts = Parts(entry)
	local on = FrameOn(entry.key)
	local look = UF()
	local unit = UnitOf(entry)
	local edged = on and Lines()
	-- (the game's damage trail: left as the game draws it, unseen under Wanderer's block; given back if an older
	-- build dressed it)
	RestoreBar(parts.trail)
	-- (the game's health overlays keep the game's place and size, never our block's: unseen while it stands; the
	-- damage trail's own fill emptied too, since the game sets the trail's alpha itself at each hit)
	for _, region in ipairs(HealthOverlays(entry, parts)) do
		if edged then HideArt(region) else ShowArt(region) end
	end
	if parts.trail then Trail(parts.trail, edged) end
	if not on then
		Unblock(parts.health)
		RestoreBar(parts.health)
		RestoreBar(parts.power)
		Extras(entry, parts, nil, look, false)
		Compose(entry, parts, nil, nil, look)
		if parts.name then Undress(parts.name) end
	else
		local upper = parts.health and edged and HealthBlock(entry, parts.health, unit, look)
		if parts.health and not upper then
			Unmirror(parts.health, dressed[parts.health])
			StyleHealth(entry, parts.health, unit, look)
		end
		local lower = parts.power and StylePower(entry, parts.power, unit, look, upper or nil)
		-- (the box around the power only while it is shown: never an empty box under the health)
		local boxed = lower and lower:IsShown() and lower or nil
		if upper then Block(entry, parts.health, upper, boxed, look) else Unblock(parts.health) end
		Extras(entry, parts, lower or upper or nil, look, upper and edged)
		if parts.name then
			if look.texts == "game" then
				Undress(parts.name)
			else
				Dress(parts.name, ns.Skin.FontPath(ns.db.label.font), NameSize(parts.name), NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3], true)
			end
		end
		Compose(entry, parts, upper or nil, lower or nil, look)
	end
	for _, region in ipairs(parts.art or {}) do
		if edged then HideArt(region) else ShowArt(region) end
	end
	if parts.cast then
		if FrameOn("castBars") and FrameOn(entry.key) then DressCast(parts.cast) else RestoreBar(parts.cast) end
	end
end

local function StyleUnits()
	for _, entry in ipairs(Entries()) do StyleEntry(entry) end
	if ns.ApplyPortraits then ns.ApplyPortraits() end
end

-- The game's group and raid frames (raid style): only their texture, their ground and their names' font; their
-- colours and texts stay the game's options. Never the nameplates (the same frames).
local compact = setmetatable({}, { __mode = "k" })
local compactLook = setmetatable({}, { __mode = "k" }) -- a frame's ground -> its look before

local function CompactUnit(frame)
	local unit = Clean(rawget(frame, "displayedUnit")) or Clean(rawget(frame, "unit"))
	return type(unit) == "string" and unit or nil
end

local function StyleCompact(frame)
	if type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden()) then return end
	local unit = CompactUnit(frame)
	if unit and unit:find("^nameplate") then return end
	local health, power = IsBar(rawget(frame, "healthBar")), IsBar(rawget(frame, "powerBar"))
	local background, name = Region(rawget(frame, "background")), IsText(rawget(frame, "name"))
	if not FrameOn("group") then
		RestoreBar(health)
		RestoreBar(power)
		if name then Undress(name) end
		local saved = background and compactLook[background]
		if saved then
			compactLook[background] = nil
			if saved.file then pcall(background.SetTexture, background, saved.file) end
			background:SetVertexColor(unpack(saved.color))
		end
		return
	end
	local look = UF()
	for _, bar in ipairs({ health, power }) do
		if bar then
			local state = State(bar)
			Fill(bar, state, TexturePath(look))
			state.on = true
		end
	end
	if background then
		if not compactLook[background] then
			local r, g, b, a = Safe(background.GetVertexColor, background)
			compactLook[background] = { file = Clean(Safe(background.GetTexture, background)), color = { r or 1, g or 1, b or 1, a or 1 } }
		end
		background:SetTexture(WHITE)
		background:SetVertexColor(GroundColor(look))
	end
	if name then
		if look.texts == "game" then Undress(name) else Dress(name, ns.Skin.FontPath(ns.db.label.font)) end
	end
end

local COMPACT_NAMES = {}
for index = 1, 5 do COMPACT_NAMES[#COMPACT_NAMES + 1] = "CompactPartyFrameMember" .. index end
for index = 1, 40 do COMPACT_NAMES[#COMPACT_NAMES + 1] = "CompactRaidFrame" .. index end

local function StyleCompacts()
	for _, name in ipairs(COMPACT_NAMES) do
		local frame = _G[name]
		if type(frame) == "table" then compact[frame] = true end
	end
	for frame in pairs(compact) do StyleCompact(frame) end
end

-- Wanderer's own bars (the label's health and power, its cast lines, the tooltip's power) --------------------

local function FollowOwn() return On() and UF().wanderer ~= false end

local function DressOwn()
	local follow = FollowOwn()
	local look = UF()
	for bar, ground in pairs(U.ownBars or {}) do
		if follow then
			bar:SetStatusBarTexture(TexturePath(look))
			ground:SetColorTexture(GroundColor(look))
		else
			bar:SetStatusBarTexture(TEXTURES.classic)
			ground:SetColorTexture(0, 0, 0, 0.6)
		end
	end
end

-- (Util.FillPowerBar and Casts.lua ask: the look's colours while Wanderer's bars follow it, else nil)
U.OwnPowerColor = function(token)
	if not FollowOwn() then return nil end
	return ns.UnitFramesPowerColor(token)
end
function ns.UnitFramesOwnCastColor(kind)
	if not FollowOwn() then return nil end
	return { ns.UnitFramesCastColor(kind) }
end

-- Drawing and the game's moments ------------------------------------------------------------------------------

local function RestoreAll()
	for bar in pairs(dressed) do RestoreBar(bar) end
	for region in pairs(hiddenArt) do ShowArt(region) end
	for text in pairs(texts) do Undress(text) end
	for frame in pairs(compact) do StyleCompact(frame) end
end

local soon = false
local function Soon()
	if soon then return end
	soon = true
	C_Timer.After(0, function()
		soon = false
		if On() then StyleUnits() end
	end)
end
ns.UnitFramesSoon = Soon

local hookedGame = false
local function HookGame()
	if hookedGame then return end
	hookedGame = true
	local function After(name, fn)
		if type(_G[name]) == "function" then hooksecurefunc(name, fn) end
	end
	-- (each after the game's own work, never in its place)
	After("UnitFrameHealthBar_Update", function(bar) if On() then Recolor(bar) end end)
	After("UnitFrameManaBar_UpdateType", function() if On() then Soon() end end)
	for _, name in ipairs({ "PlayerFrame_UpdateHealthBarVisuals", "PlayerFrame_UpdateManaBarVisuals", "PlayerFrame_ToVehicleArt",
		"PlayerFrame_ToPlayerArt", "PlayerFrame_UpdateArt", "PlayerFrame_UpdateStatus" }) do
		After(name, function() if On() then Soon() end end)
	end
	for _, entry in ipairs(Entries()) do
		local frame = entry.frame
		if not hooked[frame] then
			hooked[frame] = "frame"
			for _, method in ipairs({ "UpdateHealthBarVisuals", "UpdateManaBarVisuals", "CheckClassification", "UpdateArt" }) do
				if type(frame[method]) == "function" then hooksecurefunc(frame, method, function() if On() then Soon() end end) end
			end
		end
	end
	After("DefaultCompactUnitFrameSetup", function(frame)
		if type(frame) == "table" then compact[frame] = true end
		if On() then StyleCompact(frame) end
	end)
	After("CompactUnitFrame_SetUnit", function(frame)
		if type(frame) ~= "table" then return end
		compact[frame] = true
		if On() then StyleCompact(frame) end
	end)
	-- (Edit Mode open: the game's art back for its selection boxes; closed: the look again)
	local manager = _G.EditModeManagerFrame
	if type(manager) == "table" and manager.HookScript then
		manager:HookScript("OnShow", function() if On() then StyleUnits() end end)
		manager:HookScript("OnHide", function() if On() then StyleUnits() end end)
	end
end

-- Everything drawn again in the look (a setting, a profile, Wanderer on or off).
function ns.ApplyUnitFrames()
	ReadYields()
	if On() then
		HookGame()
		StyleUnits()
		StyleCompacts()
	else
		RestoreAll()
		if ns.ApplyPortraits then ns.ApplyPortraits() end
	end
	DressOwn()
	if ns.RefreshUnitFramesCards then ns.RefreshUnitFramesCards() end
end

-- A preset chosen: its values written, the module on.
function ns.ApplyUnitFramesPreset(key)
	local preset, uf = PresetOf(key), UF()
	if not (preset and uf) then return false end
	for _, field in ipairs(ns.UF_FIELDS) do uf[field] = preset[field] end
	uf.enabled = true
	ns.ApplyUnitFrames()
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

local EVENTS = { "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_PREDICTION", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER", "UPDATE_SHAPESHIFT_FORM", "GROUP_ROSTER_UPDATE",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_PET", "UNIT_CONNECTION", "UNIT_FACTION",
	"UNIT_THREAT_SITUATION_UPDATE", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_LOADED" }
-- (those events, while the look is on, draw the portraits too: Portraits.lua leaves them to it)
ns.UF_EVENTS = {}
for _, event in ipairs(EVENTS) do ns.UF_EVENTS[event] = true end

function ns.InitUnitFrames()
	local frame = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
	frame:SetScript("OnEvent", function(_, event, unit)
		-- (a unit's event for a unit none of these frames shows: nothing to draw; raids fire them all the time)
		if event:sub(1, 5) == "UNIT_" and not ns.UF_UNITS[Clean(unit) or ""] then return end
		-- (another frame addon loaded late: the look steps aside for it)
		if event == "ADDON_LOADED" then
			local before = yielded.unitFrames
			ReadYields()
			if before ~= yielded.unitFrames then ns.ApplyUnitFrames() end
			return
		end
		if not On() then return end
		if event == "PLAYER_REGEN_ENABLED" and deferred then
			deferred = false
			return ns.ApplyUnitFrames()
		end
		if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then StyleCompacts() end
		Soon()
		-- (a form or a power changed: the game gives the new power's figures a moment later, so drawn once more
		-- then; the block never keeps the size of the power before)
		if event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_DISPLAYPOWER" then C_Timer.After(0.5, Soon) end
	end)
end

-- Preset cards ---------------------------------------------------------------------------------------------------
-- Big cards, one per look (and, at the welcome, the game's frames as they are): a small sample drawn by the
-- engine (a ring, a health bar, a power bar), the look's name, a sentence on hover. The chosen one in gold.

local CARD_GAP = 10
local cardGrids = {}

local function SampleRing(parent, size)
	local face = parent:CreateTexture(nil, "ARTWORK")
	face:SetSize(size, size)
	face:SetTexture("Interface\\Icons\\INV_Misc_Head_Human_01")
	face:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ns.Skin.RoundMask(parent, face)
	local ring = parent:CreateTexture(nil, "OVERLAY")
	ring:SetSize(size, size)
	ring:SetPoint("CENTER", face, "CENTER")
	ring:SetTexture(MEDIA .. "PortraitRing")
	face.ring = ring
	return face
end

-- A sample's metal (the game's frame art, drawn as a soft frame) or nothing (Ink lines).
local function Metal(parent)
	local metal = CreateFrame("Frame", nil, parent)
	metal.edges = ns.Skin.Edges(metal, 0.62, 0.56, 0.44, 0.75)
	return metal
end

-- A sample: portrait, health and power, in a look (also the settings' preview rows).
local function Sample(parent, height)
	local sample = CreateFrame("Frame", nil, parent)
	sample:SetHeight(height)
	sample.face = SampleRing(sample, height)
	sample.face:SetPoint("LEFT", sample, "LEFT", 0, 0)
	-- (Ink lines: the medallion, as Portraits.lua draws it: a rounded square, its ink border)
	sample.medal = CreateFrame("Frame", nil, sample)
	sample.medal:SetAllPoints(sample.face)
	sample.medal.border = sample.medal:CreateTexture(nil, "BACKGROUND")
	sample.medal.border:SetAllPoints()
	sample.medal.border:SetTexture(MEDIA .. "PortraitSquare")
	sample.medal.border:SetVertexColor(0, 0, 0, 0.9)
	sample.medal.face = sample.medal:CreateTexture(nil, "ARTWORK")
	sample.medal.face:SetPoint("TOPLEFT", sample.medal, "TOPLEFT", 2, -2)
	sample.medal.face:SetPoint("BOTTOMRIGHT", sample.medal, "BOTTOMRIGHT", -2, 2)
	if sample.medal.CreateMaskTexture and sample.medal.face.AddMaskTexture then
		local mask = sample.medal:CreateMaskTexture()
		mask:SetTexture(MEDIA .. "PortraitSquare", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(sample.medal.face)
		sample.medal.face:AddMaskTexture(mask)
	end
	sample.health = CreateFrame("StatusBar", nil, sample)
	sample.health:SetMinMaxValues(0, 100)
	sample.health:SetPoint("TOPLEFT", sample.face, "TOPRIGHT", 6, -math.floor(height * 0.2))
	sample.health:SetPoint("RIGHT", sample, "RIGHT", -2, 0)
	sample.healthHeight = math.max(6, math.floor(height * 0.34))
	sample.health:SetHeight(sample.healthHeight)
	sample.power = CreateFrame("StatusBar", nil, sample)
	sample.power:SetMinMaxValues(0, 100)
	sample.power:SetPoint("TOPLEFT", sample.health, "BOTTOMLEFT", 0, -1)
	sample.power:SetPoint("TOPRIGHT", sample.health, "BOTTOMRIGHT", 0, -1)
	sample.power:SetHeight(math.max(3, math.floor(height * 0.18)))
	sample.metal = Metal(sample)
	sample.metal:SetPoint("TOPLEFT", sample.health, "TOPLEFT", -3, 3)
	sample.metal:SetPoint("BOTTOMRIGHT", sample.power, "BOTTOMRIGHT", 3, -3)
	-- look: a preset's values or the settings; who: { class, power, health, reaction, ring }
	function sample:Draw(look, who)
		local r, g, b
		if who.class then
			r, g, b = U.ClassColor(who.class)
			if look.health == "classic" then r, g, b = unpack(REACTION_CLASSIC.friendly) end
			if look.health == "one" then r, g, b = unpack(look.colourBlind and REACTION_SAFE.friendly or REACTION.friendly) end
			if look.health == "gradient" then r, g, b = Blend(who.health / 100, look.colourBlind) end
		else
			local set = look.health == "classic" and REACTION_CLASSIC or (look.colourBlind and REACTION_SAFE or REACTION)
			local c = set[who.reaction or "hostile"]
			r, g, b = c[1], c[2], c[3]
			if look.health == "gradient" then r, g, b = Blend(who.health / 100, look.colourBlind) end
		end
		if who.offline then r, g, b = unpack(OFFLINE) end
		r, g, b = r or 0.5, g or 0.5, b or 0.5
		local grow = look.art == "lines" and ({ fine = 1, medium = 1.35, thick = 1.8 })[look.thickness or "medium"] or 1
		self.health:SetHeight(math.floor(self.healthHeight * (grow or 1)))
		ns.Skin.UnitBar(self.health, look, r, g, b, true, self.power)
		self.health:SetValue(who.health or 100)
		local pr, pg, pb = ns.UnitFramesPowerColor(who.power or "MANA", look)
		if look.art == "lines" then pr, pg, pb = pr * 0.88, pg * 0.88, pb * 0.88 end
		ns.Skin.UnitBar(self.power, look, pr, pg, pb, true, false)
		self.power:SetValue(who.powerShare or 80)
		self.metal:SetShown(look.art ~= "lines")
		-- The ring as Portraits.lua draws it.
		local ring = self.face.ring
		if look.ring == "off" then
			ring:Hide()
		else
			-- (as Portraits.lua: your quiet gold, the others' colour a little toward grey)
			local rr, rg, rb = r, g, b
			if look.ring == "gold" and who.you then
				rr, rg, rb = 0.78, 0.68, 0.42
			else
				if who.class then rr, rg, rb = U.ClassColor(who.class) end
				rr, rg, rb = (rr or 0.5) * 0.75 + 0.12, (rg or 0.5) * 0.75 + 0.12, (rb or 0.5) * 0.75 + 0.12
			end
			ring:SetVertexColor(rr, rg, rb, who.offline and 0.3 or 0.8)
			ring:Show()
		end
		self.face:SetDesaturated(who.offline and true or false)
		if who.icon then
			self.face:SetTexture(who.icon)
			self.face:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		-- Ink lines: the medallion instead of the round face and its ring.
		local medal = look.art == "lines"
		self.medal:SetShown(medal)
		self.face:SetShown(not medal)
		if medal then
			self.face.ring:Hide()
			local face = self.medal.face
			if who.icon then
				face:SetTexture(who.icon)
				face:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			elseif who.unit then
				face:SetTexCoord(0, 1, 0, 1)
				Safe(SetPortraitTexture, face, who.unit)
			else
				face:SetTexture(self.face:GetTexture())
			end
			face:SetDesaturated(who.offline and true or false)
		end
	end
	return sample
end
ns.UnitFramesSample = Sample

-- The cards: options.withGame (the game's frames as a fourth card), options.cardHeight, options.onPick(key).
function ns.UnitFramesCards(parent, options)
	options = options or {}
	local grid = { cards = {}, cardHeight = options.cardHeight or 92, parent = parent }
	local list = {}
	for _, preset in ipairs(ns.UF_PRESETS) do list[#list + 1] = preset.key end
	if options.withGame then list[#list + 1] = "game" end
	local you = select(2, Safe(UnitClass, "player"))
	local _, token = Safe(UnitPowerType, "player")
	for index, key in ipairs(list) do
		local card = CreateFrame("Button", nil, parent)
		card.key, card.index = key, index
		card:SetHeight(grid.cardHeight)
		card.background = card:CreateTexture(nil, "BACKGROUND")
		card.background:SetAllPoints()
		card.hover = card:CreateTexture(nil, "BACKGROUND", nil, 1)
		card.hover:SetAllPoints()
		card.hover:SetColorTexture(1, 1, 1, 0.06)
		card.hover:Hide()
		card.edges = ns.Skin.Edges(card, 1, 1, 1, 0.07)
		card.sample = Sample(card, math.max(20, grid.cardHeight - 50))
		card.sample:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
		card.sample:SetPoint("RIGHT", card, "RIGHT", -10, 0)
		card.check = card:CreateTexture(nil, "OVERLAY")
		card.check:SetSize(16, 16)
		card.check:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 8)
		ns.Skin.GlyphOn(card.check, "check")
		card.title = ns.Skin.Text(card, "GameTooltipText", "text")
		card.title:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 10)
		card.title:SetPoint("RIGHT", card.check, "LEFT", -4, 0)
		if card.title.SetWordWrap then card.title:SetWordWrap(false) end
		card.title:SetText(L["UF_PRESET_" .. key:upper()])
		local look = PresetOf(key) or { health = "class", texture = "classic", ground = "classic", power = "game", art = "game", ring = "off" }
		card.sample:Draw(look, { class = Clean(you) or "WARRIOR", you = true, power = Clean(token) or "MANA", health = 72 })
		card:SetScript("OnEnter", function(self)
			self.hover:Show()
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["UF_PRESET_" .. key:upper()], 1, 0.82, 0)
			GameTooltip:AddLine(L["UF_PRESET_" .. key:upper() .. "_DESC"], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		card:SetScript("OnLeave", function(self)
			self.hover:Hide()
			GameTooltip:Hide()
		end)
		card:SetScript("OnClick", function()
			ns.ChangeEverywhere(function()
				if key == "game" then
					UF().enabled = false
					ns.ApplyUnitFrames()
				else
					ns.ApplyUnitFramesPreset(key)
				end
			end)
			ns.Skin.Play("click")
			if options.onPick then options.onPick(key) end
			ns.RefreshUnitFramesCards()
			if ns.RefreshSettingsWindow then ns.RefreshSettingsWindow() end
		end)
		grid.cards[index] = card
	end
	function grid:Layout(anchor, width, offsetY)
		if not width or width <= 0 then return end
		local count = #self.cards
		local cardWidth = math.floor((width - (count - 1) * CARD_GAP) / count)
		for _, card in ipairs(self.cards) do
			card:SetWidth(cardWidth)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (card.index - 1) * (cardWidth + CARD_GAP), -(offsetY or 0))
		end
	end
	function grid:Height() return self.cardHeight end
	-- The chosen look in gold (the game's card: the module off).
	function grid:Refresh()
		local uf = UF()
		local current = uf and (uf.enabled and ns.UnitFramesPreset() or (options.withGame and "game")) or nil
		for _, card in ipairs(self.cards) do
			local chosen = card.key == current
			card.background:SetColorTexture(chosen and 1 or 1, chosen and 0.82 or 1, chosen and 0 or 1, chosen and 0.14 or 0.04)
			card.title:SetTextColor(unpack(chosen and ns.Skin.COLORS.gold or ns.Skin.COLORS.text))
			card.check:SetShown(chosen)
		end
		self.current = current
	end
	cardGrids[#cardGrids + 1] = grid
	grid:Refresh()
	return grid
end

function ns.RefreshUnitFramesCards()
	for _, grid in ipairs(cardGrids) do grid:Refresh() end
end

-- The settings page's pieces -----------------------------------------------------------------------------------

local function Colorize(words) return ns.Skin.Colorize(words, "label") end

local STATUS_TEXT = { NUMERIC = "UF_VALUES_NUMERIC", PERCENT = "UF_VALUES_PERCENT", BOTH = "UF_VALUES_BOTH", NONE = "UF_VALUES_NONE" }

local function OpenGameOptions()
	if ns.CloseSettings then ns.CloseSettings() end
	local settings = _G.Settings
	if settings and settings.OpenToCategory and settings.INTERFACE_CATEGORY_ID and pcall(settings.OpenToCategory, settings.INTERFACE_CATEGORY_ID) then return end
	local panel = _G.SettingsPanel
	if panel and panel.Open and pcall(panel.Open, panel) then return end
	if panel and ShowUIPanel then pcall(ShowUIPanel, panel) end
end

-- What the game decides (Wanderer follows it): what the values say and when, the class icons, the sizes.
function ns.UnitFramesGameWords()
	local mode = Clean(Safe(GetCVar, "statusTextDisplay"))
	local always = Clean(Safe(GetCVar, "statusText")) == "1"
	local values = L[STATUS_TEXT[mode or ""] or "UF_VALUES_NUMERIC"]
	if mode ~= "NONE" then values = values .. ", " .. (always and L.UF_VALUES_ALWAYS or L.UF_VALUES_HOVER) end
	local mine, others = Clean(Safe(GetCVar, "ReplaceMyPlayerPortrait")), Clean(Safe(GetCVar, "ReplaceOtherPlayerPortraits"))
	local icons
	if mine == nil and others == nil then
		icons = L.UF_ICONS_NONE
	else
		icons = L.UF_ICONS_STATE:format(others == "1" and L.CHANGES_ON or L.CHANGES_OFF, mine == "1" and L.CHANGES_ON or L.CHANGES_OFF)
	end
	return values, icons
end

-- The card "The game decides": a block of the settings page (frame:Layout(width) -> height, frame:Refresh()).
function ns.UnitFramesGameCard(canvas)
	local card = ns.Skin.Panel(canvas)
	card.kicker = ns.Skin.Caps(card, L.UF_GAME_DECIDES, "kicker")
	card.kicker:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
	card.lines = {}
	for index = 1, 3 do
		local line = ns.Skin.Text(card, "GameTooltipTextSmall", "soft")
		line:SetJustifyH("LEFT")
		if line.SetWordWrap then line:SetWordWrap(false) end
		card.lines[index] = line
	end
	card.button = ns.Skin.Button(card, L.UF_GAME_OPTIONS, function() OpenGameOptions() end, nil, 120)
	card.button:SetHeight(24)
	card.button:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	ns.Skin.Tooltip(card, L.UF_GAME_DECIDES_DESC)
	function card:Layout(width)
		local previous = self.kicker
		for _, line in ipairs(self.lines) do
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
			line:SetWidth(math.max(80, width - 180))
			previous = line
		end
		return 96
	end
	function card:Refresh()
		local values, icons = ns.UnitFramesGameWords()
		self.lines[1]:SetText(Colorize(L.UF_GAME_VALUES) .. "  " .. values)
		self.lines[2]:SetText(Colorize(L.UF_GAME_ICONS) .. "  " .. icons)
		self.lines[3]:SetText(Colorize(L.UF_GAME_SIZES) .. "  " .. L.UF_GAME_SIZES_EDIT)
	end
	return card
end

-- The presets block of the settings page: its caption ("Customised" when nothing matches) and the cards.
function ns.UnitFramesPresetBlock(canvas)
	local block = CreateFrame("Frame", nil, canvas)
	block.caption = ns.Skin.Caps(block, L.UF_LOOKS, "kicker")
	block.caption:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
	block.custom = ns.Skin.Chip(block)
	block.custom:SetPoint("LEFT", block.caption, "RIGHT", 10, 0)
	block.grid = ns.UnitFramesCards(block, { cardHeight = 96 })
	function block:Layout(width)
		self.grid:Layout(self.caption, width - 6, 10)
		return 18 + 10 + self.grid:Height() + 6
	end
	function block:Refresh()
		self.grid:Refresh()
		local uf = UF()
		self.custom:Set(uf and uf.enabled and not ns.UnitFramesPreset() and L.UF_CUSTOMISED or nil, "gold")
	end
	return block
end

-- The live preview beside the settings (Preview.lua): every sample drawn by the same engine, fake fixed values.
function ns.UnitFramesPreview(holder)
	local card, skin = ns.Skin.CreateWindow(nil, nil, holder)
	skin.minOpacity = nil
	card:EnableMouse(false)
	card:SetSize(250, 252)
	local you = Clean(select(2, Safe(UnitClass, "player"))) or "WARRIOR"
	local _, token = Safe(UnitPowerType, "player")
	local rows = {
		{ name = Clean(Safe(UnitName, "player")) or L.UF_SAMPLE_YOU, who = { class = you, you = true, power = Clean(token) or "MANA", health = 72 },
			height = 30, face = "player" },
		{ name = L.UF_SAMPLE_ENEMY, who = { reaction = "hostile", power = "RAGE", health = 64, icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf" }, height = 30 },
		{ name = L.UF_SAMPLE_OFFLINE, who = { class = "PALADIN", offline = true, health = 100, power = "MANA", icon = "Interface\\Icons\\INV_Misc_Head_Human_02" }, height = 22 },
		{ name = L.UF_SAMPLE_PARTY, who = { class = "ROGUE", power = "ENERGY", health = 45, icon = "Interface\\Icons\\INV_Misc_Head_Human_01" }, height = 22 },
	}
	card.rows = {}
	local previous
	for index, row in ipairs(rows) do
		local name = ns.Skin.Text(card, "GameTooltipTextSmall", "text")
		name:SetText(row.name)
		if previous then name:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10) else name:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12) end
		local sample = Sample(card, row.height)
		sample:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
		sample:SetPoint("RIGHT", card, "RIGHT", -14, 0)
		if row.face then
			Safe(SetPortraitTexture, sample.face, row.face)
			row.who.unit = row.face
		end
		card.rows[index] = { sample = sample, who = row.who, name = name }
		previous = sample
	end
	-- (the rogue's points, three of five, as the block draws them in Ink lines)
	local rogue = card.rows[4].sample
	card.points = CreateFrame("Frame", nil, card)
	card.points:SetPoint("TOPLEFT", rogue.power, "BOTTOMLEFT", 0, -3)
	card.points:SetPoint("TOPRIGHT", rogue.power, "BOTTOMRIGHT", 0, -3)
	card.points:SetHeight(4)
	card.pips = {}
	for index = 1, PIPS do
		local pip = card.points:CreateTexture(nil, "ARTWORK")
		pip:SetPoint("TOPLEFT", card.points, "TOPLEFT", (index - 1) * ((rogue:GetWidth() > 0 and rogue:GetWidth() or 180) / PIPS), 0)
		pip:SetSize(28, 4)
		card.pips[index] = pip
	end
	card.cast = CreateFrame("StatusBar", nil, card)
	card.cast:SetMinMaxValues(0, 100)
	card.cast:SetValue(62)
	card.cast:SetHeight(10)
	card.cast:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 20, -12)
	card.cast:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	card.castIcon = card:CreateTexture(nil, "ARTWORK")
	card.castIcon:SetSize(14, 14)
	card.castIcon:SetPoint("RIGHT", card.cast, "LEFT", -6, 0)
	card.castIcon:SetTexture("Interface\\Icons\\Spell_Frost_FrostBolt02")
	card.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	card.castText = ns.Skin.Text(card.cast, "GameTooltipTextSmall", "text")
	card.castText:SetPoint("LEFT", card.cast, "LEFT", 4, 0)
	card.castText:SetText(L.UF_SAMPLE_CAST)
	function card:Draw()
		local look = UF() or ns.UF_PRESETS[2]
		for _, row in ipairs(self.rows) do row.sample:Draw(look, row.who) end
		local lines = look.art == "lines"
		self.points:SetShown(lines)
		local width = Clean(Safe(self.points.GetWidth, self.points))
		local each = type(width) == "number" and width > 0 and (width - (PIPS - 1) * PIP_GAP) / PIPS or 28
		for index, pip in ipairs(self.pips) do
			pip:ClearAllPoints()
			pip:SetPoint("TOPLEFT", self.points, "TOPLEFT", (index - 1) * (each + PIP_GAP), 0)
			pip:SetSize(each, 4)
			if index <= 3 then pip:SetColorTexture(POINT_COLOR[1], POINT_COLOR[2], POINT_COLOR[3], 1) else pip:SetColorTexture(unpack(GROUND.dark)) end
		end
		ns.Skin.UnitBar(self.cast, look, ns.UnitFramesCastColor("cast", look))
		local path = look.texts ~= "game" and ns.Skin.FontPath(ns.db.label.font)
		for _, row in ipairs(self.rows) do
			if path then pcall(row.name.SetFont, row.name, path, 11, "") end
		end
		skin:SetFixedStyle("frame", 90)
		skin:Layout()
	end
	function card:Signature()
		local look = UF() or {}
		local words = {}
		for _, field in ipairs(ns.UF_FIELDS) do words[#words + 1] = tostring(look[field]) end
		words[#words + 1] = tostring(look.colourBlind)
		return table.concat(words, "|")
	end
	return card
end

-- Diagnostic (/wanderer frames dump) ---------------------------------------------------------------------------
-- The unit frames as the game built them, written into the account's saved data (WandererDB.framesDump, replaced
-- each time; read after a /reload): every region and child frame of your frame and your target's, with its
-- layer, texture or atlas, colours, alpha, size, anchors, level; the bars' values (a hidden one said so); the
-- pieces Wanderer made; the look's settings. Read only: nothing of the game is changed.

local DUMP_DEPTH, DUMP_CAP = 7, 2500

local function Word(value)
	if IsSecret(value) then return "<secret>" end
	if value == nil then return "nil" end
	if type(value) == "number" then return (("%.3f"):format(value):gsub("%.?0+$", "")) end
	return tostring(value)
end

function ns.DumpUnitFrames()
	if not ns.root then return false end
	local lines, names, seen = {}, {}, {}
	local ours = {}
	for _, state in pairs(dressed) do
		for _, key in ipairs({ "ground", "line", "block", "mirror" }) do
			if state[key] then ours[state[key]] = key end
		end
	end
	local function Name(object)
		if object == nil then return "nil" end
		if IsSecret(object) then return "<secret>" end
		if type(object) ~= "table" then return tostring(object) end
		local name = names[object] or Clean(Safe(object.GetName, object))
		return name or tostring(object):gsub("^table: ", "@")
	end
	local function Add(text)
		if #lines < DUMP_CAP then lines[#lines + 1] = text end
	end
	local Describe
	function Describe(object, path, depth)
		if type(object) ~= "table" or IsSecret(object) or seen[object] or #lines >= DUMP_CAP then return end
		seen[object] = true
		names[object] = names[object] or path
		local ok = pcall(function()
			local parts = { path, Word(Safe(object.GetObjectType, object)) }
			if ours[object] then parts[#parts + 1] = "WANDERER:" .. ours[object] end
			if object.GetDrawLayer then
				local layer, sublevel = Safe(object.GetDrawLayer, object)
				parts[#parts + 1] = "layer=" .. Word(layer) .. "/" .. Word(sublevel)
			end
			if object.GetAtlas then
				local atlas = Safe(object.GetAtlas, object)
				if atlas then parts[#parts + 1] = "atlas=" .. Word(atlas) end
			end
			if object.GetTexture and not object.GetStatusBarTexture then
				local file = Safe(object.GetTexture, object)
				if file then parts[#parts + 1] = "tex=" .. Word(file) end
			end
			if object.GetVertexColor then
				local r, g, b, a = Safe(object.GetVertexColor, object)
				parts[#parts + 1] = ("vertex=%s,%s,%s,%s"):format(Word(r), Word(g), Word(b), Word(a))
			end
			if object.IsDesaturated and Safe(object.IsDesaturated, object) then parts[#parts + 1] = "desaturated" end
			parts[#parts + 1] = "alpha=" .. Word(Safe(object.GetAlpha, object))
			parts[#parts + 1] = "shown=" .. Word(Safe(object.IsShown, object)) .. "/" .. Word(Safe(object.IsVisible, object))
			parts[#parts + 1] = "size=" .. Word(Safe(object.GetWidth, object)) .. "x" .. Word(Safe(object.GetHeight, object))
			if object.GetFrameLevel then
				parts[#parts + 1] = "level=" .. Word(Safe(object.GetFrameLevel, object)) .. " " .. Word(Safe(object.GetFrameStrata, object))
			end
			if object.GetStatusBarTexture then
				local fill = Safe(object.GetStatusBarTexture, object)
				local r, g, b = Safe(object.GetStatusBarColor, object)
				local low, high = Safe(object.GetMinMaxValues, object)
				parts[#parts + 1] = ("bar fill=%s color=%s,%s,%s min=%s max=%s value=%s"):format(Name(fill), Word(r), Word(g), Word(b), Word(low),
					Word(high), Word(Safe(object.GetValue, object)))
				if type(fill) == "table" then Describe(fill, path .. ">fill", depth + 1) end
			end
			if object.GetFont then
				local file, size = Safe(object.GetFont, object)
				parts[#parts + 1] = "font=" .. Word(file) .. " " .. Word(size) .. " text=" .. Word(Safe(object.GetText, object))
			end
			local points = {}
			for index = 1, Clean(Safe(object.GetNumPoints, object)) or 0 do
				local point, relative, relativePoint, x, y = Safe(object.GetPoint, object, index)
				points[#points + 1] = ("%s>%s.%s(%s,%s)"):format(Word(point), Name(relative), Word(relativePoint), Word(x), Word(y))
			end
			if points[1] then parts[#parts + 1] = "points=" .. table.concat(points, " ") end
			Add(table.concat(parts, " | "))
		end)
		if not ok then Add(path .. " | (unreadable)") end
		if depth >= DUMP_DEPTH then return end
		-- (its keys first: the game's names for its parts)
		pcall(function()
			for key, value in pairs(object) do
				if type(key) == "string" and type(value) == "table" and not IsSecret(value) and type(value.GetObjectType) == "function" and not names[value] then
					names[value] = path .. "." .. key
				end
			end
		end)
		local regions = { Safe(object.GetRegions, object) }
		for index, region in ipairs(regions) do Describe(region, names[region] or (path .. ">r" .. index), depth + 1) end
		local children = { Safe(object.GetChildren, object) }
		for index, child in ipairs(children) do Describe(child, names[child] or (path .. ">c" .. index), depth + 1) end
	end
	for _, root in ipairs({ "PlayerFrame", "TargetFrame", "PlayerCastingBarFrame" }) do
		if type(_G[root]) == "table" then Describe(_G[root], root, 0) end
	end
	for _, entry in ipairs(Entries()) do
		if entry.key == "player" or entry.key == "target" then
			local parts = Parts(entry)
			for _, key in ipairs({ "health", "power", "trail" }) do
				if parts[key] and not seen[parts[key]] then Describe(parts[key], entry.key .. ":" .. key, 1) end
			end
		end
	end
	for object, key in pairs(ours) do
		if not seen[object] then Describe(object, "WANDERER:" .. key, DUMP_DEPTH) end
	end
	-- Each health Wanderer dresses: the colour it gave, as read back on its own bar, its fill, and the game's fill.
	local function Color(object, method)
		if type(object) ~= "table" or not object[method] then return "-" end
		local r, g, b, a = Safe(object[method], object)
		return ("%s,%s,%s,%s"):format(Word(r), Word(g), Word(b), Word(a))
	end
	for _, entry in ipairs(Entries()) do
		if entry.key == "player" or entry.key == "target" then
			local parts = Parts(entry)
			for _, region in ipairs(HealthOverlays(entry, parts)) do
				local fill = region.GetStatusBarTexture and Safe(region.GetStatusBarTexture, region)
				local inner = type(fill) == "table" and fill or Walk(region, "Fill")
				Add(("OVERLAY %s %s | alpha=%s shown=%s | fill tex=%s atlas=%s vertex=%s alpha=%s"):format(entry.key, Name(region),
					Word(Safe(region.GetAlpha, region)), Word(Safe(region.IsVisible, region)),
					Word(type(inner) == "table" and Safe(inner.GetTexture, inner)), Word(type(inner) == "table" and Safe(inner.GetAtlas, inner)),
					Color(inner, "GetVertexColor"), Word(type(inner) == "table" and Safe(inner.GetAlpha, inner))))
			end
		end
	end
	for bar, state in pairs(dressed) do
		if state.health then
			local r, g, b = ns.UnitFramesHealthColor(state.health)
			local _, class = Safe(UnitClass, state.health)
			local mirror = state.mirror
			local ourFill = mirror and Safe(mirror.GetStatusBarTexture, mirror)
			local gameFill = Safe(bar.GetStatusBarTexture, bar)
			Add(("HEALTH %s | class=%s | computed=%s,%s,%s | mirrored=%s refused=%s blanked=%s | ours bar=%s fill=%s tex=%s alpha=%s shown=%s | game bar=%s fill=%s tex=%s atlas=%s alpha=%s"):format(
				Word(state.health), Word(class), Word(r), Word(g), Word(b), Word(state.mirrored), Word(state.refused), Word(state.blanked),
				Color(mirror, "GetStatusBarColor"), Color(ourFill, "GetVertexColor"), Word(ourFill and Safe(ourFill.GetTexture, ourFill)),
				Word(ourFill and Safe(ourFill.GetAlpha, ourFill)), Word(mirror and Safe(mirror.IsVisible, mirror)),
				Color(bar, "GetStatusBarColor"), Color(gameFill, "GetVertexColor"), Word(type(gameFill) == "table" and Safe(gameFill.GetTexture, gameFill)),
				Word(type(gameFill) == "table" and Safe(gameFill.GetAtlas, gameFill)), Word(type(gameFill) == "table" and Safe(gameFill.GetAlpha, gameFill))))
		end
	end
	-- The damage-over-time bands as drawn now (DotBars.lua).
	if ns.DotBandsDebug then
		for _, line in ipairs(ns.DotBandsDebug()) do Add(line) end
	end
	-- What the game says of each unit's power (an empty power box: why it is drawn).
	for _, unit in ipairs({ "player", "target", "focus" }) do
		if Clean(Safe(UnitExists, unit)) then
			local kind, token = Safe(UnitPowerType, unit)
			local most, now = Safe(UnitPowerMax, unit), Safe(UnitPower, unit)
			local arrangedWith = nil
			for frame, last in pairs(arranged) do
				if last.entry and UnitOf(last.entry) == unit then arrangedWith = frame end
			end
			local last = arrangedWith and arranged[arrangedWith]
			Add(("POWER %s | type=%s token=%s | max=%s secret=%s | now=%s | noPower=%s | dead=%s | lower shown=%s height=%s | upper height=%s"):format(
				unit, Word(kind), Word(token), Word(most), Word(IsSecret(most)), Word(now), Word(NoPower(unit)),
				Word(Safe(UnitIsDead, unit)), Word(last and last.lower and last.lower:IsShown()),
				Word(last and last.lower and Safe(last.lower.GetHeight, last.lower)), Word(last and Safe(last.upper.GetHeight, last.upper))))
		end
	end
	do
		local hr, hg, hb = ns.UnitFramesHealthColor("player")
		local tr, tg, tb = LowColor("player", hr, hg, hb)
		Add(("LOWHEALTH | C_CurveUtil=%s CreateColorCurve=%s UnitHealthPercent=%s CurveConstants=%s | health=%s/%s | test=%s,%s,%s | path=%s curve=%s error=%s"):format(
			Word(_G.C_CurveUtil ~= nil), Word(_G.C_CurveUtil ~= nil and _G.C_CurveUtil.CreateColorCurve ~= nil), Word(_G.UnitHealthPercent ~= nil),
			Word(_G.CurveConstants ~= nil), Word(Safe(UnitHealth, "player")), Word(Safe(UnitHealthMax, "player")), Word(tr), Word(tg), Word(tb),
			Word(lowStatus.path), Word(lowStatus.curve), Word(lowStatus.error)))
	end
	local settings = {}
	for key, value in pairs(UF() or {}) do
		if type(value) == "table" then
			local copy = {}
			for inner, word in pairs(value) do copy[inner] = word end
			settings[key] = copy
		else
			settings[key] = value
		end
	end
	ns.root.framesDump = {
		when = Clean(Safe(date, "%Y-%m-%d %H:%M:%S")), on = On(), lines = lines, settings = settings,
		cvars = { statusTextDisplay = Word(Safe(GetCVar, "statusTextDisplay")), statusText = Word(Safe(GetCVar, "statusText")) },
		editMode = EditMode(), cut = #lines >= DUMP_CAP or nil,
	}
	return true
end

-- The bands of DotBars.lua and HotBars.lua against the health shown ------------------------------------------
-- The damage over time band lies over the end of the health, the heals over time band starts where it ends: each
-- takes a colour that reads against the health's colour as it is drawn now (the game's, or this look's: class,
-- attitude, a creature tapped by others greyed). Close in hue to the band: the damage band turns to a light ink
-- with a dark edge, the heals band keeps its green and takes a light edge where it meets the health; a grey
-- health (tapped, offline): the damage band stronger.

local BANDS = {
	dot = { band = { 1, 0.42, 0.18, 0.55 }, edge = { 1, 0.78, 0.45, 0.9 } },
	hot = { band = { 0.2, 0.6, 0.35, 0.5 }, edge = { 0.56, 0.88, 0.64, 0.95 } },
}
local LIGHT_BAND, DARK_EDGE, LIGHT_EDGE = { 0.95, 0.93, 0.88, 0.42 }, { 0.04, 0.04, 0.05, 0.95 }, { 0.97, 0.96, 0.92, 0.95 }
local GREY_DOT = { 1, 0.42, 0.18, 0.75 }
local HUE_GAP = 45 -- degrees: closer than this, a band of that hue is lost on the health
local GREY = 0.25 -- saturation under which a health reads as grey

for _, set in pairs(BANDS) do set.hue = HueOf(set.band[1], set.band[2], set.band[3]) end

-- The colour a health bar shows now: as set on it (the game's or this look's), else this look's for the unit, else
-- the game's green; nil when hidden (the bands keep theirs).
local function Shown(unit, bar)
	-- (Ink lines: the health seen is ours, over the game's)
	local state = type(bar) == "table" and dressed[bar]
	if state and state.mirrored and state.mirror then bar = state.mirror end
	if type(bar) == "table" and bar.GetStatusBarColor then
		local r, g, b = Safe(bar.GetStatusBarColor, bar)
		r, g, b = Clean(r), Clean(g), Clean(b)
		-- (white: a bar coloured by its art, not by its colour)
		if type(r) == "number" and type(g) == "number" and type(b) == "number" and not (r > 0.9 and g > 0.9 and b > 0.9) then return r, g, b end
	end
	if unit and On() then
		local r, g, b, plain = ns.UnitFramesHealthColor(unit)
		if plain then return r, g, b end
		return nil
	end
	if unit and Clean(Safe(UnitIsTapDenied, unit)) then return 0.5, 0.5, 0.5 end
	return 0, 0.8, 0
end

-- kind "dot" or "hot": the band's colour and its edge's ({ r, g, b, a } each).
function ns.UnitFramesBandColors(kind, unit, bar, r, g, b)
	local set = BANDS[kind] or BANDS.dot
	if not r then r, g, b = Shown(unit, bar) end
	if not r then return set.band, set.edge end
	local hue, saturation = HueOf(r, g, b)
	if kind == "dot" then
		if saturation < GREY then return GREY_DOT, set.edge end
		if Gap(hue, set.hue) < HUE_GAP then return LIGHT_BAND, DARK_EDGE end
	elseif saturation >= GREY and Gap(hue, set.hue) < HUE_GAP then
		return set.band, LIGHT_EDGE
	end
	return set.band, set.edge
end
