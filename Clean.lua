local _, ns = ...
local L = ns.L

-- A clean interface, built on the game's own frames and settings:
--
-- Minimap: no border ring and no band behind the zone name; the buttons
-- around it (tracking, calendar, zoom, addons) appear when the mouse is
-- over the minimap. The mail and the zone name stay.
--
-- Quest tracker: no header backgrounds; it rests slightly faded and lights
-- up under the mouse.
--
-- Edit Mode: each profile can name one of the game's Edit Mode layouts;
-- Wanderer makes it the active layout (so each place can have its own, with
-- the profiles by place). Never during a fight. Layouts are only written on a
-- click (a layout made, a bar shown or hidden). Wanderer turned off: the layout
-- that was active before it chose one comes back, and the game's group frame
-- options it set with a layout too (unless you changed them since).
--
-- Only opacities are changed, nothing is moved: switched off, everything is
-- back as the game draws it.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_EVERY = 0.1
local FADE_IN, FADE_OUT = 0.35, 0.8 -- seconds of a full fade
local TRACKER_REST = 0.7
local TRACKER_MODULES = ns.TRACKER_MODULES -- (TrackerLook.lua, loaded before)

local driver
local since = 0
local sinceButtons = 0
local buttonsAlpha -- the opacity the minimap buttons were given last
local BUTTONS_AGAIN = 2 -- seconds: buttons added by other addons meanwhile take the opacity too
local hoverMinimap, hoverTracker = 0, 1 -- current opacities of the faded parts
local minimapTween, trackerTween = U.Tween(0), U.Tween(1)
local pendingLayout = false

-- Minimap ------------------------------------------------------------------------------

-- The ring and the band: hidden while the option is on.
local function MinimapBorders()
	local cluster = MinimapCluster or {}
	return { _G.MinimapCompassTexture, _G.MinimapBorder, _G.MinimapBorderTop, cluster.BorderTop }
end

-- The buttons around: shown under the mouse.
local function MinimapButtons()
	local cluster = MinimapCluster or {}
	local map = Minimap or {}
	return { cluster.Tracking, _G.MiniMapTracking, _G.GameTimeFrame, _G.AddonCompartmentFrame, map.ZoomIn, map.ZoomOut,
		_G.MinimapZoomIn, _G.MinimapZoomOut, _G.ExpansionLandingPageMinimapButton, _G.MiniMapWorldMapButton }
end

local function SetAlphas(list, alpha)
	for _, part in pairs(list) do
		if type(part) == "table" and part.SetAlpha then part:SetAlpha(alpha) end
	end
end

-- Quest tracker ------------------------------------------------------------------------

local function TrackerHeaders(alpha)
	local tracker = ObjectiveTrackerFrame
	if not tracker then return end
	if tracker.Header and tracker.Header.Background then tracker.Header.Background:SetAlpha(alpha) end
	for _, name in ipairs(TRACKER_MODULES) do
		local module = _G[name]
		local header = module and module.Header
		if header and header.Background then header.Background:SetAlpha(alpha) end
	end
end

-- The tracker's look taken by another (Wanderer Quests' own list, Kaliel's Tracker): the game's list's opacity is
-- theirs (Wanderer Quests holds it at 0 in a fight, out of sight).
local function TrackerTaken() return ns.Yields and ns.Yields("trackerLook") ~= nil end

-- Motion -------------------------------------------------------------------------------

local function OnUpdate(_, elapsed)
	since = since + elapsed
	if since < CHECK_EVERY then return end
	elapsed, since = since, 0
	local world = ns.db and ns.db.enabled and ns.db.world
	if world and world.cleanMinimap and MinimapCluster then
		-- (the names key held: shown too, as under the mouse)
		local over = ns.revealing or ns.Util.IsMouseOver(MinimapCluster)
		hoverMinimap = minimapTween:Step(over and 1 or 0, elapsed, FADE_IN, FADE_OUT)
		sinceButtons = sinceButtons + elapsed
		if hoverMinimap ~= buttonsAlpha or sinceButtons >= BUTTONS_AGAIN then
			sinceButtons, buttonsAlpha = 0, hoverMinimap
			SetAlphas(MinimapButtons(), hoverMinimap)
		end
	end
	if world and world.cleanTracker and ObjectiveTrackerFrame and not TrackerTaken() then
		local over = ns.revealing or (ObjectiveTrackerFrame:IsShown() and ns.Util.IsMouseOver(ObjectiveTrackerFrame)) or false
		hoverTracker = trackerTween:Step(over and 1 or TRACKER_REST, elapsed, FADE_IN, FADE_OUT)
		ObjectiveTrackerFrame:SetAlpha(hoverTracker)
	end
end

-- Edit Mode ----------------------------------------------------------------------------

-- The game's layouts in its own order (its presets first), and the active one.
local function Layouts()
	local names = {}
	local manager = EditModePresetLayoutManager
	local presets = manager and manager.GetCopyOfPresetLayouts and Safe(manager.GetCopyOfPresetLayouts, manager)
	for _, layout in ipairs(type(presets) == "table" and presets or {}) do names[#names + 1] = Clean(layout.layoutName) or "?" end
	local info = C_EditMode and C_EditMode.GetLayouts and Safe(C_EditMode.GetLayouts)
	if type(info) ~= "table" then return names, nil end
	for _, layout in ipairs(info.layouts or {}) do names[#names + 1] = Clean(layout.layoutName) or "?" end
	return names, Clean(info.activeLayout)
end

function ns.EditModeLayouts()
	return (Layouts())
end

-- What Wanderer changed for this character (Mine().layoutHeld): before, the layout active before it chose
-- one; set, the one it made active; cvars, the group frames' options written with a layout
-- (name -> { before, value }); off, given back while Wanderer is off.
local function LayoutHeld()
	local mine = ns.Mine()
	mine.layoutHeld = type(mine.layoutHeld) == "table" and mine.layoutHeld or {}
	return mine.layoutHeld
end

-- The active layout's name now.
local function ActiveName()
	local names, active = Layouts()
	return active and names[active] or nil
end

-- A layout made active by Wanderer (index in the game's list), the one before remembered (before: its name,
-- read before the list changed).
local function Activate(index, name, before)
	local held = LayoutHeld()
	if held.before == nil then held.before = before or ActiveName() end
	pcall(C_EditMode.SetActiveLayout, index)
	held.set = name
end

-- One of the game's options set with a layout, your value kept.
local function WriteHeld(cvar, value)
	local now = Clean(Safe(GetCVar, cvar))
	if now == nil then return end
	local held = LayoutHeld()
	held.cvars = type(held.cvars) == "table" and held.cvars or {}
	local entry = held.cvars[cvar]
	-- (changed by you since Wanderer wrote it: your value is the one to keep)
	if not entry or now ~= entry.value then
		entry = { before = now }
		held.cvars[cvar] = entry
	end
	entry.value = value
	ns.WriteCVar(cvar, value)
end

-- Wanderer turned off: your layout and your options back (those you did not change since).
local function GiveBackLayout()
	local mine = ns.Mine()
	local held = mine.layoutHeld
	if type(held) ~= "table" or held.off then return end
	if InCombatLockdown() then
		pendingLayout = true
		return
	end
	for cvar, entry in pairs(type(held.cvars) == "table" and held.cvars or {}) do
		if entry.before ~= nil and Clean(Safe(GetCVar, cvar)) == entry.value then ns.WriteCVar(cvar, entry.before) end
	end
	if held.before and held.set and C_EditMode and C_EditMode.SetActiveLayout then
		local names, active = Layouts()
		-- (the game's layouts not known yet, at loading: given back once they are)
		if not active then
			pendingLayout = true
			return
		end
		if names[active] == held.set then
			for index, name in ipairs(names) do
				if name == held.before then
					pcall(C_EditMode.SetActiveLayout, index)
					break
				end
			end
		end
	end
	held.before, held.set, held.off = nil, nil, true
end

-- Wanderer on again: the options set with a layout, written again (those still as given back).
local function TakeBackLayout()
	local held = ns.Mine().layoutHeld
	if type(held) ~= "table" or not held.off then return end
	if InCombatLockdown() then
		pendingLayout = true
		return
	end
	held.off = nil
	for cvar, entry in pairs(type(held.cvars) == "table" and held.cvars or {}) do
		if entry.value ~= nil and Clean(Safe(GetCVar, cvar)) == entry.before then ns.WriteCVar(cvar, entry.value) end
	end
end

-- The layout of the active profile becomes the game's active layout.
function ns.ApplyEditLayout()
	local wanted = ns.db and ns.db.enabled and ns.db.world.editLayout
	if not wanted or wanted == "" or not (C_EditMode and C_EditMode.SetActiveLayout) then return end
	if InCombatLockdown() then
		pendingLayout = true
		return
	end
	pendingLayout = false
	local names, active = Layouts()
	for index, name in ipairs(names) do
		if name == wanted then
			if index ~= active then Activate(index, wanted) end
			return
		end
	end
end

-- Wanderer's layouts ------------------------------------------------------------------
-- Real Edit Mode layouts, made the way the game makes one: a copy of its
-- "Modern" preset, a few systems moved or set, saved by the game. They then
-- belong to the player: Edit Mode adjusts, copies or shares them like any
-- other. Made again over themselves (same name), never over the player's.

local ACTION_BAR_STEP = 47 -- height of a bar of 12 icons, and a breath of space between two bars
local HALF_BAR = 281 -- half the width of a bar of 12 icons (45 each, 2 between)
local BLOCK_GAP = 10 -- between the bottom bars and the blocks beside them
local BLOCK_WIDTH, BLOCK_HEIGHT = 280, 92 -- a block of 6 icons by 2
local BLOCK_X = HALF_BAR + BLOCK_GAP
local SIDE_HEIGHT = BLOCK_HEIGHT * 2 + 4 -- two blocks on the left: bars 7 and 6
local BLOCK = { rows = 2 } -- 6 icons by 2
local COLUMN = { vertical = true } -- 12 icons one above the other

local function BarIndex(name)
	return Enum and Enum.EditModeActionBarSystemIndices and Enum.EditModeActionBarSystemIndices[name]
end

local function SystemEntry(layout, system, index)
	for _, entry in ipairs(layout.systems) do
		if entry.system == system and entry.systemIndex == index then return entry end
	end
end

local function SetSetting(entry, setting, value)
	if not (entry and setting ~= nil) then return end
	for _, item in ipairs(entry.settings) do
		if item.setting == setting then
			item.value = value
			return
		end
	end
	entry.settings[#entry.settings + 1] = { setting = setting, value = value }
end

local function Anchor(entry, point, relativeTo, relativePoint, x, y)
	if not entry then return end
	entry.anchorInfo = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, offsetX = x, offsetY = y }
	entry.isInDefaultPosition = false
end

local function Place(entry, point, relativePoint, x, y)
	Anchor(entry, point, "UIParent", relativePoint, x, y)
end

-- Your portrait and your target's over the bars. The target's cast bar sits
-- under its portrait (the game gives no other place): its auras go on top,
-- so only the cast bar is under it, and the portraits stand high enough for
-- it to stay clear of the bars.
local TARGET_CAST_ROOM = 34 -- the target's cast bar and its spell name
local function Portraits(layout, x, y)
	local system, index = Enum.EditModeSystem.UnitFrame, Enum.EditModeUnitFrameSystemIndices
	if not (system and index) then return end
	y = y + TARGET_CAST_ROOM
	Place(SystemEntry(layout, system, index.Player), "BOTTOMRIGHT", "BOTTOM", -x, y)
	local target = SystemEntry(layout, system, index.Target)
	Place(target, "BOTTOMLEFT", "BOTTOM", x, y)
	local setting = Enum.EditModeUnitFrameSetting
	if setting and setting.BuffsOnTop then SetSetting(target, setting.BuffsOnTop, 1) end
end

-- Your group, in the top left corner the portraits left free: the game's
-- raid-style frames (health, role, who is targeted, dispels), wide enough
-- for the names, sorted by role (tanks, healers, then the others); the raid
-- is placed with the look (Finish). The class colors of the game's option
-- make each one recognisable at a glance.
local GROUP_X, GROUP_Y = 24, -170
local GROUP_WIDTH, GROUP_HEIGHT = 96, 40 -- the game makes them 72 by 36 at least
local function Group(layout)
	local system, index = Enum.EditModeSystem.UnitFrame, Enum.EditModeUnitFrameSystemIndices
	local setting = Enum.EditModeUnitFrameSetting
	if not (system and index and setting) then return end
	local party = index.Party and SystemEntry(layout, system, index.Party)
	if party then
		Place(party, "TOPLEFT", "TOPLEFT", GROUP_X, GROUP_Y)
		if setting.UseRaidStylePartyFrames then SetSetting(party, setting.UseRaidStylePartyFrames, 1) end
		if setting.UseHorizontalGroups then SetSetting(party, setting.UseHorizontalGroups, 0) end
		if setting.FrameWidth then SetSetting(party, setting.FrameWidth, GROUP_WIDTH) end
		if setting.FrameHeight then SetSetting(party, setting.FrameHeight, GROUP_HEIGHT) end
		if setting.SortPlayersBy and Enum.SortPlayersBy and Enum.SortPlayersBy.Role then
			SetSetting(party, setting.SortPlayersBy, Enum.SortPlayersBy.Role)
		end
	end
end

-- No art around the main bar: its frame, its page arrows and the gryphons
-- (their own elements in WoW Forever).
local function HideMainBarArt(layout)
	local main = SystemEntry(layout, Enum.EditModeSystem.ActionBar, BarIndex("MainBar"))
	SetSetting(main, Enum.EditModeActionBarSetting.HideBarArt, 1)
	SetSetting(main, Enum.EditModeActionBarSetting.HideBarScrolling, 1)
	local system, index = Enum.EditModeSystem.MainActionBarEndCap, Enum.EditModeMainActionBarEndCapSystemIndices
	local setting = Enum.EditModeMainActionBarEndCapSetting
	if not (system and index and setting) then return end
	for _, cap in ipairs({ index.EndCapLeft, index.EndCapRight }) do
		SetSetting(SystemEntry(layout, system, cap), setting.Hidden, 1)
	end
end

-- The game's menu and the bags at the bottom right, the bags over the menu, the damage meter over them;
-- the experience and reputation bars at the top center.
local function Corners(layout, mainY)
	local system = Enum.EditModeSystem
	local menu = system.MicroMenu and SystemEntry(layout, system.MicroMenu, nil)
	-- Beside bar 8 when the screen is wide enough, over it otherwise.
	local half = (tonumber(UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920) / 2
	local menuWidth = tonumber(MicroMenuContainer and MicroMenuContainer.GetWidth and MicroMenuContainer:GetWidth()) or 0
	if menuWidth < 200 then menuWidth = 320 end -- not measured yet: the menu's usual width
	local room = half - 6 - menuWidth - (BLOCK_X + BLOCK_WIDTH)
	Place(menu, "BOTTOMRIGHT", "BOTTOMRIGHT", -6, room >= BLOCK_GAP and 4 or mainY + BLOCK_HEIGHT + 8)
	local bags = system.Bags and SystemEntry(layout, system.Bags, nil)
	if menu then Anchor(bags, "BOTTOMRIGHT", "MicroMenuContainer", "TOPRIGHT", 0, 4) end
	-- The game's damage meter on the right of the bars, over the bags (never in the top left corner, where the
	-- game puts it and the group frames are).
	-- (its first window: the others the game opens are placed by you)
	for _, entry in ipairs(system.DamageMeter and layout.systems or {}) do
		if entry.system == system.DamageMeter then
			if bags and menu then
				Anchor(entry, "BOTTOMRIGHT", "BagsBar", "TOPRIGHT", 0, 8)
			else
				Place(entry, "BOTTOMRIGHT", "BOTTOMRIGHT", -6, 110)
			end
			break
		end
	end
	local index = Enum.EditModeStatusTrackingBarSystemIndices
	if not (system.StatusTrackingBar and index) then return end
	local first = SystemEntry(layout, system.StatusTrackingBar, index.StatusTrackingBar1)
	Place(first, "TOP", "TOP", 0, -2)
	local second = SystemEntry(layout, system.StatusTrackingBar, index.StatusTrackingBar2)
	if first then Anchor(second, "TOP", "MainStatusTrackingBarContainer", "BOTTOM", 0, -2) end
end

-- A bar out of the bottom stack: its shape, how it shows ("Always",
-- "InCombat"), and where it sits (no point: the game's own place, where the
-- game also keeps the quest tracker clear of it).
local function BarAt(layout, name, visible, shape, point, relativePoint, x, y)
	local entry = SystemEntry(layout, Enum.EditModeSystem.ActionBar, BarIndex(name))
	if not entry then return end
	local setting = Enum.EditModeActionBarSetting
	SetSetting(entry, setting.Orientation, shape.vertical and Enum.ActionBarOrientation.Vertical or Enum.ActionBarOrientation.Horizontal)
	SetSetting(entry, setting.NumRows, shape.rows or 1)
	SetSetting(entry, setting.NumIcons, 12)
	if visible and Enum.ActionBarVisibleSetting then SetSetting(entry, setting.VisibleSetting, Enum.ActionBarVisibleSetting[visible]) end
	if point then Place(entry, point, relativePoint, x, y) end
end

-- A bar of the bottom stack: one row of 12, centered at its height, and how it shows (the main bar: always).
local ROW = {}
local function Bar(layout, name, y, visible)
	BarAt(layout, name, name ~= "MainBar" and visible or nil, ROW, "BOTTOM", "BOTTOM", 0, y)
end

-- Bars 5 to 8 (and 4 when it is not in the stack): bar 5 (and 4) upright on
-- the right edge where the game puts them; bars 6, 7 and 8 in blocks of 6 by 2
-- beside the bottom bars (7 and 6 over it on the left, 8 on the right), never
-- where the party frames or the chat are. Which ones show is still the game's
-- choice (Options > Action Bars).
local function OtherBars(layout, visible, mainY, fourth)
	if fourth then BarAt(layout, "RightBar1", visible, COLUMN) end
	BarAt(layout, "RightBar2", visible, COLUMN)
	BarAt(layout, "ExtraBar2", visible, BLOCK, "BOTTOMRIGHT", "BOTTOM", -BLOCK_X, mainY)
	BarAt(layout, "ExtraBar1", visible, BLOCK, "BOTTOMRIGHT", "BOTTOM", -BLOCK_X, mainY + BLOCK_HEIGHT + 4)
	BarAt(layout, "ExtraBar3", visible, BLOCK, "BOTTOMLEFT", "BOTTOM", BLOCK_X, mainY)
end

-- The swing timer, the game's own: small (70 %, no title, its time kept),
-- shown in fights only. The game keeps its scale as a step of its slider
-- (50 % to 200 %, by 10: step 2 is 70 %).
local SWING_SCALE_STEP = 2
local function SmallSwing(entry)
	local settings = Enum.EditModeSwingTimerSetting or {}
	if settings.Scale then SetSetting(entry, settings.Scale, SWING_SCALE_STEP) end
	if settings.ShowBarTitle then SetSetting(entry, settings.ShowBarTitle, 0) end
	local visibility = Enum.EditModeSwingTimerVisibility
	if settings.Visibility and visibility and visibility.InCombat then SetSetting(entry, settings.Visibility, visibility.InCombat) end
end

-- What the game stacks over the bottom bars by itself (extra button...): it
-- measures the bars left in their default place, and Wanderer's bars are all
-- moved, so these would fall on them. Placed here over the stack instead: the
-- extra and encounter buttons; the swing timers made small (the look places
-- them, with the cast bar, the vehicle exit and the totems: Finish).
local function OverTheBars(layout, top)
	local system = Enum.EditModeSystem
	local swing = Enum.EditModeSwingTimerSystemIndices
	if system.SwingTimer and swing then
		for _, index in ipairs({ swing.MainHand, swing.OffHand, swing.Ranged }) do
			local entry = SystemEntry(layout, system.SwingTimer, index)
			if entry then SmallSwing(entry) end
		end
	end
	if system.ExtraAbilities then Place(SystemEntry(layout, system.ExtraAbilities, nil), "BOTTOM", "BOTTOM", 0, top + 160) end
	if system.EncounterBar then Place(SystemEntry(layout, system.EncounterBar, nil), "BOTTOM", "BOTTOM", 0, top + 300) end
end

local function Settings(entry, list)
	if not entry then return end
	for _, pair in ipairs(list) do SetSetting(entry, pair[1], pair[2]) end
end
local SWING_LOOK = { { 0, 2 }, { 1, 50 }, { 2, 1 }, { 3, 60 }, { 5, 0 }, { 6, 1 } } -- (as the player set them)

-- The look of Wanderer's layouts, as the player shaped it in Edit Mode (2026-10, the stacked one), kept for
-- every one of them, each around its own stack (top: the frame of the stack's highest bar). Over that bar:
-- the stance bar on its left end, the vehicle's exit on its right, the swing timers above its right end; the
-- pet and totem bars against the main bar's right; the cast bar under your portrait, the durability beside
-- it; the tooltip left of the game's menu; the focus, the bosses and the raid where they read best.
local function Finish(layout, top)
	local system = Enum.EditModeSystem
	local bar = system.ActionBar
	Anchor(SystemEntry(layout, bar, BarIndex("StanceBar")), "BOTTOMLEFT", top, "TOPLEFT", 0, 4)
	Anchor(SystemEntry(layout, bar, BarIndex("PetActionBar")), "BOTTOMLEFT", "MainActionBar", "BOTTOMRIGHT", 4, 0)
	Anchor(SystemEntry(layout, bar, BarIndex("PossessActionBar")), "BOTTOM", "UIParent", "BOTTOM", -436.7, 2)
	if system.VehicleLeaveButton then Anchor(SystemEntry(layout, system.VehicleLeaveButton, nil), "TOPLEFT", top, "TOPRIGHT", 4, 0) end
	if system.TotemActionBar then Anchor(SystemEntry(layout, system.TotemActionBar, nil), "BOTTOMLEFT", "MainActionBar", "BOTTOMRIGHT", 4, 0) end
	if system.CastBar then Anchor(SystemEntry(layout, system.CastBar, nil), "TOP", "PlayerFrame", "BOTTOM", 8.8, 14) end
	if system.DurabilityFrame then
		local durability = SystemEntry(layout, system.DurabilityFrame, nil)
		Anchor(durability, "TOPLEFT", "PlayerFrame", "TOPRIGHT", -16, -16)
		Settings(durability, { { 0, 3 } })
	end
	if system.HudTooltip then Anchor(SystemEntry(layout, system.HudTooltip, nil), "BOTTOMRIGHT", "MicroMenuContainer", "BOTTOMLEFT", -8, -2) end
	if system.MicroMenu then Settings(SystemEntry(layout, system.MicroMenu, nil), { { 2, 4 } }) end
	if system.Bags then Settings(SystemEntry(layout, system.Bags, nil), { { 2, 1 } }) end
	local unit, index = system.UnitFrame, Enum.EditModeUnitFrameSystemIndices
	if unit and index then
		if index.Focus then Anchor(SystemEntry(layout, unit, index.Focus), "CENTER", "UIParent", "CENTER", -485.5, -260) end
		if index.Boss then Anchor(SystemEntry(layout, unit, index.Boss), "TOPRIGHT", "UIParent", "TOPRIGHT", -387.5, -293) end
		if index.Raid then Anchor(SystemEntry(layout, unit, index.Raid), "TOPLEFT", "UIParent", "TOPLEFT", 27.3, 0) end
	end
	local swing = Enum.EditModeSwingTimerSystemIndices
	if system.SwingTimer and swing then
		local main, off, ranged = SystemEntry(layout, system.SwingTimer, swing.MainHand), SystemEntry(layout, system.SwingTimer, swing.OffHand),
			SystemEntry(layout, system.SwingTimer, swing.Ranged)
		Anchor(main, "BOTTOMRIGHT", top, "TOPRIGHT", 0.6, 3.4)
		Anchor(off, "TOPRIGHT", "SwingTimerMainHandFrame", "TOPLEFT", -2.8, 0)
		Anchor(ranged, "BOTTOM", "SwingTimerOffHandFrame", "TOP", 92.8, 2.8)
		for _, entry in ipairs({ main, off, ranged }) do Settings(entry, SWING_LOOK) end
		Settings(main, { { 4, 4 } })
		Settings(off, { { 4, 2 } })
		Settings(ranged, { { 4, 2 } })
	end
end

local STRIKERS = { WARRIOR = true, ROGUE = true, PALADIN = true, HUNTER = true, SHAMAN = true, DRUID = true }

local LAYOUTS = {
	-- Bars 1 to 4 stacked at the bottom, portraits just over them; the others
	-- around (OtherBars).
	stacked = function(layout)
		local top = 10
		for _, name in ipairs({ "MainBar", "Bar2", "Bar3", "RightBar1" }) do
			Bar(layout, name, top, "Always")
			top = top + ACTION_BAR_STEP
		end
		OtherBars(layout, "Always", 10, false)
		local above = math.max(top, 10 + SIDE_HEIGHT) + 4
		HideMainBarArt(layout)
		Corners(layout, 10)
		OverTheBars(layout, above - 4)
		Portraits(layout, 180, above + 46)
		Group(layout)
		Finish(layout, "MultiBarRight") -- (bar 4, the highest of the stack)
	end,
	-- For immersion: the main bar alone at the bottom; every other bar shown
	-- only in fights, in its place (bars 2 and 3 over the main bar, the others
	-- around); nothing around them.
	clean = function(layout)
		Bar(layout, "MainBar", 40, "Always")
		Bar(layout, "Bar2", 40 + ACTION_BAR_STEP, "InCombat")
		Bar(layout, "Bar3", 40 + ACTION_BAR_STEP * 2, "InCombat")
		OtherBars(layout, "InCombat", 40, true)
		local above = math.max(40 + ACTION_BAR_STEP * 3, 40 + SIDE_HEIGHT) + 4
		HideMainBarArt(layout)
		Corners(layout, 40)
		OverTheBars(layout, above - 4)
		Portraits(layout, 160, above + 46)
		Group(layout)
		Finish(layout, "MultiBarBottomRight") -- (bar 3, the highest over the main bar)
	end,
	-- The game's own default layout, as it is: to come back to it, or to start
	-- from it in Edit Mode.
	blizzard = function() end,
}

function ns.LayoutName(key)
	return L["LAYOUT_" .. key:upper()]
end

-- The bars shown ---------------------------------------------------------------------
-- Which of bars 2 to 8 show is the game's own option, for each character (Options > Action Bars, kept by the
-- server; Edit Mode adds when each one shows). Wanderer never keeps a second switch for it: it opens the
-- game's page.
function ns.OpenGameActionBars()
	local GameSettings = _G.Settings -- (Settings in this file is a layout helper)
	local id = GameSettings and GameSettings.ACTION_BAR_CATEGORY_ID
	-- (Wanderer's own settings out of the way: the game's page in view)
	if ns.CloseSettingsWindow then ns.CloseSettingsWindow() end
	if id and GameSettings.OpenToCategory and pcall(GameSettings.OpenToCategory, id) then return true end
	local panel = _G.SettingsPanel
	if panel and panel.Open and pcall(panel.Open, panel) then return true end
	return false
end

-- The game said its layouts again: read from them.
function ns.LayoutsUpdated()
	ns.RefreshOptions()
	ns.RefreshWelcome()
end

-- How Wanderer's own fade (Cinema.lua) treats the bars now: "combat", faded out of combat even with a target;
-- "calm", faded when nothing happens; nil, never faded.
function ns.BarsFade()
	local cinema = ns.db and ns.db.enabled and ns.db.cinema
	if type(cinema) ~= "table" then return nil end
	if cinema.combatOnly then return "combat" end
	if cinema.enabled then return "calm" end
	return nil
end

-- Makes (or makes again) one of Wanderer's layouts and uses it with this
-- profile. Returns true when done.
function ns.MakeLayout(key)
	local build = LAYOUTS[key]
	local manager, edit = EditModePresetLayoutManager, C_EditMode
	if not (build and manager and edit and edit.GetLayouts and edit.SaveLayouts and Enum and Enum.EditModeSystem) then return false end
	if InCombatLockdown() then
		ns.Print(L.MSG_LAYOUT_COMBAT)
		return false
	end
	local before = ActiveName()
	local presets = Safe(manager.GetCopyOfPresetLayouts, manager)
	local info = Safe(edit.GetLayouts)
	if type(presets) ~= "table" or not presets[1] or type(info) ~= "table" then return false end
	local name = ns.LayoutName(key)
	local layout = presets[1] -- the game's "Modern" preset
	build(layout)
	layout.layoutName = name
	layout.layoutType = Enum.EditModeLayoutType.Account
	-- The full list, as the game keeps it: its presets first, then the saved ones.
	local all = Safe(manager.GetCopyOfPresetLayouts, manager)
	local count, highest, existing = 0, nil, nil
	for _, saved in ipairs(info.layouts or {}) do
		all[#all + 1] = saved
		if saved.layoutType == Enum.EditModeLayoutType.Account then
			count = count + 1
			highest = #all
		end
		if saved.layoutName == name then existing = #all end
	end
	local index = existing
	if existing then
		all[existing] = layout
	else
		local max = Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
		if count >= max then
			ns.Print(L.MSG_LAYOUT_FULL)
			return false
		end
		index = (highest or #presets) + 1
		table.insert(all, index, layout)
	end
	if not pcall(edit.SaveLayouts, { layouts = all, activeLayout = info.activeLayout }) then return false end
	if not existing and edit.OnLayoutAdded then pcall(edit.OnLayoutAdded, index, true, false) end
	-- (as any setting you change: in every profile of this character, else the next place put the old one back)
	ns.ChangeEverywhere(function() ns.db.world.editLayout = name end)
	if edit.SetActiveLayout then Activate(index, name, before) end
	-- The group frames raid-style and in class colors: the game's options (older
	-- games keep the raid style there, not in Edit Mode), set once here; yours after.
	if key ~= "blizzard" then
		WriteHeld("useCompactPartyFrames", "1")
		-- The swing timer, for the classes that strike (never a caster's bother).
		if STRIKERS[Clean(select(2, Safe(UnitClass, "player"))) or ""] then WriteHeld("showSwingTimer", "1") end
		WriteHeld("raidFramesDisplayClassColor", "1")
	end
	ns.RefreshOptions()
	ns.Print(L.MSG_LAYOUT_READY:format(name))
	return true, index, all
end

-- Settings -----------------------------------------------------------------------------

-- The layout and its options as Wanderer on or off calls for.
local function ApplyLayouts()
	if ns.db and ns.db.enabled then
		TakeBackLayout()
		ns.ApplyEditLayout()
	else
		pendingLayout = false
		GiveBackLayout()
	end
end

function ns.RefreshClean()
	if not driver then return end
	local world = ns.db.enabled and ns.db.world or {}
	SetAlphas(MinimapBorders(), world.cleanMinimap and 0 or 1)
	if not world.cleanMinimap then
		SetAlphas(MinimapButtons(), 1)
		hoverMinimap = 0
		minimapTween:Set(0)
	end
	TrackerHeaders(world.cleanTracker and 0 or 1)
	if not world.cleanTracker and ObjectiveTrackerFrame then
		if not TrackerTaken() then ObjectiveTrackerFrame:SetAlpha(1) end
		hoverTracker = 1
		trackerTween:Set(1)
	end
	driver:SetShown((world.cleanMinimap or world.cleanTracker) and true or false)
	ApplyLayouts()
end

-- The minimap's and the tracker's look, one choice each: the game's ("game"), discreet ("discreet"), or in
-- Wanderer's style ("wanderer", discreet as well). The settings and the welcome share them; profile: the one
-- written (the active one unless said).
local LOOK_KEYS = { minimap = { "cleanMinimap", "styledMinimap" }, tracker = { "cleanTracker", "styledTracker" } }
local function LookOf(which, profile)
	local world = (profile or ns.db).world or {}
	local keys = LOOK_KEYS[which]
	return world[keys[2]] and "wanderer" or world[keys[1]] and "discreet" or "game"
end
local function SetLookOf(which, value, profile)
	local world = (profile or ns.db).world
	local keys = LOOK_KEYS[which]
	world[keys[1]], world[keys[2]] = value ~= "game", value == "wanderer"
end
function ns.MinimapLook(profile) return LookOf("minimap", profile) end
function ns.TrackerLook(profile) return LookOf("tracker", profile) end
function ns.SetMinimapLook(value, profile)
	SetLookOf("minimap", value, profile)
	ns.RefreshClean()
	if ns.RefreshMinimapLook then ns.RefreshMinimapLook() end
end
function ns.SetTrackerLook(value, profile)
	SetLookOf("tracker", value, profile)
	ns.RefreshClean()
	if ns.RefreshTrackerLook then ns.RefreshTrackerLook() end
end
ns.LOOK_CHOICES = { "game", "discreet", "wanderer" }

function ns.InitClean()
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", OnUpdate)
	-- The tracker rebuilds its parts as quests come and go: headers again.
	if ObjectiveTrackerFrame and ObjectiveTrackerFrame.Update then
		hooksecurefunc(ObjectiveTrackerFrame, "Update", function()
			if ns.db and ns.db.enabled and ns.db.world.cleanTracker then TrackerHeaders(0) end
		end)
	end
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
	events:SetScript("OnEvent", function(_, event)
		if event == "EDIT_MODE_LAYOUTS_UPDATED" then
			-- (a layout to give back that waited for the game's list)
			if pendingLayout and not InCombatLockdown() then ApplyLayouts() end
			return ns.LayoutsUpdated()
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if pendingLayout then ApplyLayouts() end
		else
			ns.RefreshClean()
		end
	end)
	ns.RefreshClean()
end
