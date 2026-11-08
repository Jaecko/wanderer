local _, ns = ...

-- Where your damage over time shows (Dots.lua follows it): on the health bars of your target, your focus,
-- your target's target and the enemies' nameplates, a soft band ending where the health ends, the part your
-- spells are about to take; covering the whole bar, they will finish it. On the target's and the focus's
-- portrait, and beside a nameplate, a small skull that fills up as that damage covers what is left: whole,
-- they will. Never on allies.
--
-- The game's hidden numbers (an enemy's health) go straight to the bars: the game compares, Wanderer never
-- reads them. Nameplates of another addon (Plater, ThreatPlates, KuiNameplates, ElvUI): their health bar
-- when it can be found as a plain bar, else nothing on them.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_EVERY = 0.1
local BAND_COLOR = { 1, 0.42, 0.18, 0.55 }
local EDGE_COLOR = { 1, 0.78, 0.45, 0.9 }
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FALLBACK_LEVEL = 10

-- The unit frames, by unit: the setting that shows them, and whether the portrait has a skull.
local FRAMES = {
	{ unit = "target", setting = "target", frame = "TargetFrame", skull = true },
	{ unit = "focus", setting = "focus", frame = "FocusFrame", skull = true },
	{ unit = "targettarget", setting = "tot" },
}

local overlays = {} -- unit -> its overlay on the unit frame (false: none to be had)
local plateOverlays = setmetatable({}, { __mode = "k" }) -- a plate's health bar -> its overlay
local plateUnits = U.ShownPlates -- nameplate token -> true while shown (Util.lua keeps it)
local drawn = {} -- this drawing's plate overlays
local driver

-- A part of the bands of an option (dots, hots), on unless turned off.
local function Option(table, key)
	local settings = ns.db and ns.db[table]
	local value = type(settings) == "table" and settings[key]
	if value == nil then return true end
	return value and true or false
end
local function Setting(key) return Option("dots", key) end

local function Level(frame)
	local level = Clean(Safe(frame.GetFrameLevel, frame))
	return type(level) == "number" and level or FALLBACK_LEVEL
end

-- A part down a path of fields, or nil (each step a table: the frames of other addons vary).
local function Walk(node, ...)
	for i = 1, select("#", ...) do
		if type(node) ~= "table" or U.IsSecret(node) then return nil end
		node = node[select(i, ...)]
	end
	return node
end

local function IsBar(bar)
	return type(bar) == "table" and not U.IsSecret(bar) and type(bar.GetStatusBarTexture) == "function" and bar or nil
end

-- Drawing ----------------------------------------------------------------------------------------------

-- The part of a bar the eye sees: the game's portrait frames draw a taller bar inside a shorter holder that
-- masks it (its top and bottom hidden); there, the holder's height. Else the bar itself.
local function GameVisible(bar)
	local holder = Clean(Safe(bar.GetParent, bar))
	if type(holder) ~= "table" or U.IsSecret(holder) or holder == UIParent then return bar end
	local high, outer = Clean(Safe(holder.GetHeight, holder)), Clean(Safe(bar.GetHeight, bar))
	if type(high) == "number" and type(outer) == "number" and high > 0 and high < outer - 0.5 then return holder end
	return bar
end

-- The part seen now: the health of Wanderer's block over the game's place when the unit frames' look draws one
-- (UnitFrames.lua), else the game's.
local function Visible(bar)
	local ours = ns.UnitFramesArea and ns.UnitFramesArea(bar)
	return ours or GameVisible(bar)
end

-- The fill the bands follow: the block's health when there is one (the same values, at its size), else the game's.
local function HealthFill(bar)
	local ours = ns.UnitFramesFill and ns.UnitFramesFill(bar)
	return ours or bar:GetStatusBarTexture()
end

-- A band frame over exactly the bar's visible part (its width, the height the eye sees), its children cut to it.
-- (all four sides on the part seen: Wanderer's block may stand elsewhere than the game's bar, beside the portrait)
local function Cover(band, bar)
	local seen = Visible(bar)
	band:ClearAllPoints()
	-- (sideways: on Wanderer's block when it stands elsewhere, else on the game's bar itself)
	local across = ns.UnitFramesArea and ns.UnitFramesArea(bar) or bar
	band:SetPoint("LEFT", across, "LEFT")
	band:SetPoint("RIGHT", across, "RIGHT")
	band:SetPoint("TOP", seen, "TOP")
	band:SetPoint("BOTTOM", seen, "BOTTOM")
	band:SetClipsChildren(true)
	-- (a child of the block when there is one: the game's bar holder cuts what leaves its own place, and the block
	-- stands beside the portrait now; back on the game's bar otherwise)
	local owner = ns.UnitFramesArea and ns.UnitFramesArea(bar) or bar
	if band:GetParent() ~= owner then
		band:SetParent(owner)
		band:SetFrameLevel(Level(owner) + 2)
	end
end

-- The band: from where the health ends, back over what your damage will take; cut at the bar's ends.
local function Band(bar)
	local band = CreateFrame("Frame", nil, bar)
	Cover(band, bar)
	band:SetFrameLevel(Level(bar) + 2)
	local fill = CreateFrame("StatusBar", nil, band)
	local health = HealthFill(bar)
	fill:SetPoint("TOPRIGHT", health, "TOPRIGHT")
	fill:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
	fill:SetWidth(Clean(Safe(bar.GetWidth, bar)) or 100)
	fill:SetReverseFill(true)
	fill:SetStatusBarTexture(WHITE)
	fill:SetStatusBarColor(unpack(BAND_COLOR))
	local edge = fill:CreateTexture(nil, "OVERLAY")
	edge:SetTexture(WHITE)
	edge:SetVertexColor(unpack(EDGE_COLOR))
	edge:SetWidth(1)
	edge:SetPoint("TOPLEFT", fill:GetStatusBarTexture(), "TOPLEFT")
	edge:SetPoint("BOTTOMLEFT", fill:GetStatusBarTexture(), "BOTTOMLEFT")
	band:Hide()
	return { bar = bar, band = band, fill = fill, edge = edge, health = health }
end

-- The band moved onto the fill seen now (the look turned on or off, the block made later).
local function Follow(overlay)
	local health = HealthFill(overlay.bar)
	if health == overlay.health then return end
	overlay.health = health
	overlay.fill:ClearAllPoints()
	overlay.fill:SetPoint("TOPRIGHT", health, "TOPRIGHT")
	overlay.fill:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
	Cover(overlay.band, overlay.bar)
end

-- The band's colours against the health shown under it (UnitFrames.lua's rule: a hue too close, a grey health),
-- set again only when they change. band, edge: the colours without that rule.
local function Tint(overlay, unit, kind, band, edge)
	local rule = ns.UnitFramesBandColors
	band, edge = band or BAND_COLOR, edge or EDGE_COLOR
	if rule then band, edge = rule(kind, unit, overlay.bar) end
	if overlay.tint == band and overlay.edgeTint == edge then return end
	overlay.tint, overlay.edgeTint = band, edge
	overlay.fill:SetStatusBarColor(band[1], band[2], band[3], band[4])
	overlay.edge:SetVertexColor(edge[1], edge[2], edge[3], edge[4])
end

-- The skull, filling up from below; a dim one behind it.
local function Skull(parent, size, level)
	local mark = CreateFrame("StatusBar", nil, parent)
	mark:SetSize(size, size)
	mark:SetFrameLevel(level)
	mark:SetOrientation("VERTICAL")
	mark:SetStatusBarTexture(SKULL)
	local empty = mark:CreateTexture(nil, "BACKGROUND")
	empty:SetAllPoints()
	empty:SetTexture(SKULL)
	empty:SetDesaturated(true)
	empty:SetAlpha(0.35)
	mark:Hide()
	return mark
end

local function Hide(overlay)
	if not overlay then return end
	overlay.band:Hide()
	if overlay.mark then overlay.mark:Hide() end
end

-- One overlay for one unit: shown while your spells on it still have damage to deal (left, lethal: already
-- asked, a nameplate's).
local function Paint(overlay, unit, left, lethal)
	if not left then left, lethal = ns.DotsLeft(unit, true) end
	if left <= 0 then return Hide(overlay) end
	Follow(overlay)
	local width = Clean(Safe(overlay.bar.GetWidth, overlay.bar))
	if width and width > 0 then overlay.fill:SetWidth(width) end
	-- (the hidden maximum straight to the bar)
	if not pcall(overlay.fill.SetMinMaxValues, overlay.fill, 0, UnitHealthMax(unit)) then return Hide(overlay) end
	overlay.fill:SetValue(left)
	Tint(overlay, unit, "dot")
	overlay.band:Show()
	local mark = overlay.mark
	if mark and lethal and Setting("mark") and pcall(mark.SetMinMaxValues, mark, 0, UnitHealth(unit)) then
		mark:SetValue(left)
		mark:Show()
	elseif mark then
		mark:Hide()
	end
	return true
end

-- Unit frames --------------------------------------------------------------------------------------------

local function FrameBar(entry)
	local frame = _G[entry.frame]
	if entry.unit == "targettarget" then
		local tot = Walk(_G, "TargetFrameToT") or Walk(_G, "TargetFrame", "totFrame")
		return IsBar(Walk(tot, "HealthBar")) or IsBar(Walk(tot, "healthbar")) or IsBar(_G.TargetFrameToTHealthBar)
	end
	return IsBar(Walk(frame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar"))
		or IsBar(_G[entry.frame .. "HealthBar"])
end

local function Portrait(entry)
	local frame = _G[entry.frame]
	local portrait = Walk(frame, "TargetFrameContainer", "Portrait") or _G[entry.frame .. "Portrait"]
	return type(portrait) == "table" and type(portrait.GetCenter) == "function" and portrait or nil
end

local function FrameOverlay(entry)
	local overlay = overlays[entry.unit]
	if overlay ~= nil then return overlay or nil end
	local bar = FrameBar(entry)
	if not bar then return nil end -- (looked for again later: some frames come late)
	overlay = Band(bar)
	bar:HookScript("OnSizeChanged", function(self)
		local width = Clean(Safe(self.GetWidth, self))
		if width and width > 0 then overlay.fill:SetWidth(width) end
	end)
	local portrait = entry.skull and Portrait(entry)
	if portrait then
		overlay.mark = Skull(_G[entry.frame], 20, Level(bar) + 4)
		overlay.portrait = portrait
	end
	overlays[entry.unit] = overlay
	return overlay
end

-- Nameplates ---------------------------------------------------------------------------------------------

-- The health bar of a plate: the game's own, or, when another addon draws the plates, theirs if found as a
-- plain shown bar (never a guess further down).
-- (Plater, ElvUI, ThreatPlates old and new, KuiNameplates; the game's own)
local OTHER_PLATE_BARS = { { "unitFrame", "healthBar" }, { "unitFrame", "Health" }, { "TPFrame", "visual", "Healthbar" },
	{ "TPFrame", "visual", "healthbar" }, { "kui", "HealthBar" } }
local GAME_PLATE_BARS = { { "UnitFrame", "healthBar" }, { "UnitFrame", "HealthBarsContainer", "healthBar" } }
local function PlateBar(unit, yielded)
	local plate = U.NameplateFor(unit)
	if type(plate) ~= "table" then return nil end
	for _, path in ipairs(yielded and OTHER_PLATE_BARS or GAME_PLATE_BARS) do
		local bar = IsBar(Walk(plate, unpack(path)))
		if bar and Clean(Safe(bar.IsVisible, bar)) then return bar end
	end
	return nil
end

local function PlateOverlay(unit, yielded)
	local bar = PlateBar(unit, yielded)
	if not bar then return nil end
	local overlay = plateOverlays[bar]
	if not overlay then
		overlay = Band(bar)
		overlay.mark = Skull(overlay.band:GetParent(), 12, Level(bar) + 4)
		overlay.mark:SetPoint("RIGHT", bar, "LEFT", -2, 0)
		plateOverlays[bar] = overlay
	end
	return overlay
end

-- The driver ---------------------------------------------------------------------------------------------

local function HideAll()
	for _, overlay in pairs(overlays) do
		if overlay then Hide(overlay) end
	end
	for _, overlay in pairs(plateOverlays) do Hide(overlay) end
	if driver then driver.Keep(false) end
end

local function Draw()
	if not ns.DotsOn() then return HideAll() end
	local shown = false
	for _, entry in ipairs(FRAMES) do
		local overlay = FrameOverlay(entry)
		if overlay and overlay.mark then
			-- (the skull by the portrait: in Ink lines the bottom corner away from the medallion's level, mirrored,
			-- down with the medallion when the auras stand above; else the game's bottom left)
			local lines = ns.UnitFramesLines and ns.UnitFramesLines()
			local drop = lines and ns.UnitFramesDrop and ns.UnitFramesDrop({ kind = "target", frame = _G[entry.frame] }) or 0
			local point, x, y = lines and "BOTTOMRIGHT" or "BOTTOMLEFT", lines and -8 or 8, 8 - drop
			local key = point .. x .. ":" .. y
			if overlay.markKey ~= key then
				overlay.markKey = key
				overlay.mark:ClearAllPoints()
				overlay.mark:SetPoint("CENTER", overlay.portrait, point, x, y)
			end
		end
		if overlay then
			if Setting(entry.setting) and Paint(overlay, entry.unit) then shown = true else Hide(overlay) end
		end
	end
	local plates = Setting("plates")
	-- (asked once a drawing, not for every plate)
	local yielded = plates and ns.Yields and ns.Yields("nameplates") ~= nil
	wipe(drawn)
	if plates then
		for unit in pairs(plateUnits) do
			-- (an overlay made only on an enemy carrying something of yours: never on allies)
			local left, lethal = ns.DotsLeft(unit, true)
			local overlay = left > 0 and PlateOverlay(unit, yielded)
			if overlay then
				drawn[overlay] = true
				if Paint(overlay, unit, left, lethal) then shown = true end
			end
		end
	end
	for _, overlay in pairs(plateOverlays) do
		if not drawn[overlay] then Hide(overlay) end
	end
	-- (asleep while nothing of yours ticks anywhere)
	if driver then driver.Keep(shown or ns.DotsBusy()) end
end

-- The bands' driver, the same for both kinds: draw() every moment while awake, asleep when nothing ticks;
-- told by the events (events: the bars' own besides the plates; asked(event, unit): false to skip one).
-- Wake(soon): drawn now (a cast); soon, only if asleep (an aura changed: awake, it draws within a moment).
-- Refresh(): an option changed. Keep(awake).
local function NewDriver(draw, on, hideAll, events, asked)
	local frame = CreateFrame("Frame")
	frame:Hide()
	local since = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < CHECK_EVERY then return end
		since = 0
		draw()
	end)
	local D = { frame = frame }
	function D.Keep(awake) if awake then frame:Show() else frame:Hide() end end
	function D.Wake(soon)
		if soon and frame:IsShown() then return end
		frame:Show()
		draw()
	end
	function D.Refresh() if on() then draw() else hideAll() end end
	local listener = CreateFrame("Frame")
	for _, event in ipairs(events) do pcall(listener.RegisterEvent, listener, event) end
	for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do pcall(listener.RegisterEvent, listener, event) end
	listener:SetScript("OnEvent", function(_, event, unit)
		-- (the plates shown are Util.lua's list; a plate gone hides its overlay at the next drawing)
		if event ~= "NAME_PLATE_UNIT_ADDED" and event ~= "NAME_PLATE_UNIT_REMOVED" and asked and asked(event, unit) == false then
			return
		end
		-- (drawn once on the next frame, however many events come in this one: a pull shows 30 plates at once)
		if on() then
			since = CHECK_EVERY
			frame:Show()
		end
	end)
	return D
end

function ns.DotBarsWake(soon) if driver then driver.Wake(soon) end end
function ns.DotBarsRefresh() if driver then driver.Refresh() end end

function ns.InitDotBars()
	driver = NewDriver(Draw, ns.DotsOn, HideAll, { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET" },
		function(event, unit) return not (event == "UNIT_TARGET" and Clean(unit) ~= "target") end)
end

-- (HotBars.lua finds the same bars the same way and draws its bands the same way; UnitFrames.lua dresses the
-- same visible part)
-- (/wanderer frames dump) each unit frame's band as drawn now.
function ns.DotBandsDebug()
	local out = {}
	local function Rect(region)
		if type(region) ~= "table" or not region.GetRect then return "-" end
		local ok, l, b, w, h = pcall(region.GetRect, region)
		if not ok then return "?" end
		return ("%s,%s %sx%s"):format(tostring(Clean(l)), tostring(Clean(b)), tostring(Clean(w)), tostring(Clean(h)))
	end
	for unit, overlay in pairs(overlays) do
		if overlay then
			out[#out + 1] = ("DOTBAND %s | shown=%s visible=%s | band=%s | fill=%s | health fill=%s | seen=%s | ours=%s"):format(tostring(unit),
				tostring(overlay.band:IsShown()), tostring(overlay.band:IsVisible()), Rect(overlay.band), Rect(overlay.fill:GetStatusBarTexture()),
				Rect(overlay.health), Rect(Visible(overlay.bar)), tostring(ns.UnitFramesArea and ns.UnitFramesArea(overlay.bar) ~= nil))
		end
	end
	return out
end

ns.HealthBands = { Walk = Walk, IsBar = IsBar, Level = Level, PlateBar = PlateBar, FrameBar = FrameBar, Portrait = Portrait,
	Cover = Cover, Visible = Visible, GameVisible = GameVisible, HealthFill = HealthFill, Tint = Tint, Hide = Hide,
	Option = Option, NewDriver = NewDriver, WHITE = WHITE }
