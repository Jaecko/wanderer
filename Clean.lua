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
-- the profiles by place). Never during a fight.
--
-- Only opacities are changed, nothing is moved: switched off, everything is
-- back as the game draws it.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_EVERY = 0.1
local FADE_IN, FADE_OUT = 0.35, 0.8 -- seconds of a full fade
local TRACKER_REST = 0.7
local TRACKER_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "ScenarioObjectiveTracker",
	"AchievementObjectiveTracker", "BonusObjectiveTracker", "WorldQuestObjectiveTracker",
	"ProfessionsRecipeTracker", "MonthlyActivitiesObjectiveTracker", "AdventureObjectiveTracker" }

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

-- Motion -------------------------------------------------------------------------------

local function OnUpdate(_, elapsed)
	since = since + elapsed
	if since < CHECK_EVERY then return end
	elapsed, since = since, 0
	local world = ns.db and ns.db.enabled and ns.db.world
	if world and world.cleanMinimap and MinimapCluster then
		local over = ns.Util.IsMouseOver(MinimapCluster)
		hoverMinimap = minimapTween:Step(over and 1 or 0, elapsed, FADE_IN, FADE_OUT)
		sinceButtons = sinceButtons + elapsed
		if hoverMinimap ~= buttonsAlpha or sinceButtons >= BUTTONS_AGAIN then
			sinceButtons, buttonsAlpha = 0, hoverMinimap
			SetAlphas(MinimapButtons(), hoverMinimap)
		end
	end
	if world and world.cleanTracker and ObjectiveTrackerFrame then
		local over = ObjectiveTrackerFrame:IsShown() and ns.Util.IsMouseOver(ObjectiveTrackerFrame) or false
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
			if index ~= active then pcall(C_EditMode.SetActiveLayout, index) end
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

local function Place(entry, point, relativePoint, x, y)
	if not entry then return end
	entry.anchorInfo = { point = point, relativeTo = "UIParent", relativePoint = relativePoint, offsetX = x, offsetY = y }
	entry.isInDefaultPosition = false
end

-- A bar: where it sits and how it shows ("Always", "InCombat", "Hidden").
local function Bar(layout, name, y, visible)
	local system = Enum.EditModeSystem.ActionBar
	local entry = SystemEntry(layout, system, BarIndex(name))
	if not entry then return end
	local setting = Enum.EditModeActionBarSetting
	SetSetting(entry, setting.Orientation, Enum.ActionBarOrientation.Horizontal)
	SetSetting(entry, setting.NumRows, 1)
	SetSetting(entry, setting.NumIcons, 12)
	if visible and name ~= "MainBar" and Enum.ActionBarVisibleSetting then
		SetSetting(entry, setting.VisibleSetting, Enum.ActionBarVisibleSetting[visible])
	end
	if y then Place(entry, "BOTTOM", "BOTTOM", 0, y) end
	return entry
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
-- in the same place. The class colors of the game's option make each one
-- recognisable at a glance.
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
	local raid = index.Raid and SystemEntry(layout, system, index.Raid)
	if raid then Place(raid, "TOPLEFT", "TOPLEFT", GROUP_X, GROUP_Y) end
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

-- The game's menu and the bags at the bottom right, the bags over the menu;
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
	if bags and menu then
		bags.anchorInfo = { point = "BOTTOMRIGHT", relativeTo = "MicroMenuContainer", relativePoint = "TOPRIGHT", offsetX = 0, offsetY = 4 }
		bags.isInDefaultPosition = false
	end
	local index = Enum.EditModeStatusTrackingBarSystemIndices
	if not (system.StatusTrackingBar and index) then return end
	local first = SystemEntry(layout, system.StatusTrackingBar, index.StatusTrackingBar1)
	Place(first, "TOP", "TOP", 0, -2)
	local second = SystemEntry(layout, system.StatusTrackingBar, index.StatusTrackingBar2)
	if second and first then
		second.anchorInfo = { point = "TOP", relativeTo = "MainStatusTrackingBarContainer", relativePoint = "BOTTOM", offsetX = 0, offsetY = -2 }
		second.isInDefaultPosition = false
	end
end

-- What the game stacks over the bottom bars by itself (cast bar, swing timers,
-- extra button...): it measures the bars left in their default place, and
-- Wanderer's bars are all moved, so these would fall on them. Placed here over
-- the stack instead: the cast bar between the portraits, the swing timers
-- over it, the extra and encounter buttons higher, the vehicle exit beside
-- the main bar, the totems beside the stance bar.
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

local function OverTheBars(layout, top, mainY)
	local system = Enum.EditModeSystem
	local function At(entry, point, relativePoint, x, y) Place(entry, point, relativePoint, x, y) end
	if system.CastBar then At(SystemEntry(layout, system.CastBar, nil), "BOTTOM", "BOTTOM", 0, top + 50) end
	local swing = Enum.EditModeSwingTimerSystemIndices
	if system.SwingTimer and swing then
		-- Small, just over the cast bar.
		local y = top + 80
		for _, index in ipairs({ swing.MainHand, swing.OffHand, swing.Ranged }) do
			local entry = SystemEntry(layout, system.SwingTimer, index)
			At(entry, "BOTTOM", "BOTTOM", 0, y)
			if entry then SmallSwing(entry) end
			y = y + 16
		end
	end
	if system.ExtraAbilities then At(SystemEntry(layout, system.ExtraAbilities, nil), "BOTTOM", "BOTTOM", 0, top + 160) end
	if system.EncounterBar then At(SystemEntry(layout, system.EncounterBar, nil), "BOTTOM", "BOTTOM", 0, top + 300) end
	-- Over the block of bar 8, by the main bar.
	if system.VehicleLeaveButton then
		At(SystemEntry(layout, system.VehicleLeaveButton, nil), "BOTTOMLEFT", "BOTTOM", BLOCK_X, mainY + BLOCK_HEIGHT + 8)
	end
	-- Totems on the left of the cast bar, over the stance bar: clear of both.
	if system.TotemActionBar then At(SystemEntry(layout, system.TotemActionBar, nil), "BOTTOMRIGHT", "BOTTOM", -120, top + 44) end
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
		local system = Enum.EditModeSystem.ActionBar
		Place(SystemEntry(layout, system, BarIndex("StanceBar")), "BOTTOMRIGHT", "BOTTOM", -4, above)
		Place(SystemEntry(layout, system, BarIndex("PetActionBar")), "BOTTOMLEFT", "BOTTOM", 4, above)
		HideMainBarArt(layout)
		Corners(layout, 10)
		OverTheBars(layout, above - 4, 10)
		Portraits(layout, 180, above + 46)
		Group(layout)
	end,
	-- For immersion: the main bar alone at the bottom; every other bar shown
	-- only in fights, in its place (bars 2 and 3 over the main bar, the others
	-- around); nothing around them.
	clean = function(layout)
		Bar(layout, "MainBar", 40, "Always")
		Bar(layout, "Bar2", 40 + ACTION_BAR_STEP, "InCombat")
		Bar(layout, "Bar3", 40 + ACTION_BAR_STEP * 2, "InCombat")
		OtherBars(layout, "InCombat", 40, true)
		local system = Enum.EditModeSystem.ActionBar
		local above = math.max(40 + ACTION_BAR_STEP * 3, 40 + SIDE_HEIGHT) + 4
		Place(SystemEntry(layout, system, BarIndex("StanceBar")), "BOTTOMRIGHT", "BOTTOM", -4, above)
		Place(SystemEntry(layout, system, BarIndex("PetActionBar")), "BOTTOMLEFT", "BOTTOM", 4, above)
		HideMainBarArt(layout)
		Corners(layout, 40)
		OverTheBars(layout, above - 4, 40)
		Portraits(layout, 160, above + 46)
		Group(layout)
	end,
	-- The game's own default layout, as it is: to come back to it, or to start
	-- from it in Edit Mode.
	blizzard = function() end,
}

function ns.LayoutName(key)
	return L["LAYOUT_" .. key:upper()]
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
	ns.db.world.editLayout = name
	if edit.SetActiveLayout then pcall(edit.SetActiveLayout, index) end
	-- The group frames raid-style and in class colors: the game's options (older
	-- games keep the raid style there, not in Edit Mode), set once here; yours after.
	if key ~= "blizzard" and ns.WriteCVar then
		ns.WriteCVar("useCompactPartyFrames", "1")
		-- The swing timer, for the classes that strike (never a caster's bother).
		if STRIKERS[Clean(select(2, Safe(UnitClass, "player"))) or ""] then ns.WriteCVar("showSwingTimer", "1") end
		ns.WriteCVar("raidFramesDisplayClassColor", "1")
		if CompactPartyFrame_UpdateShown and CompactPartyFrame then Safe(CompactPartyFrame_UpdateShown, CompactPartyFrame) end
	end
	if ns.debug then
		local frames, setting = Enum.EditModeUnitFrameSystemIndices or {}, Enum.EditModeUnitFrameSetting or {}
		ns.Print(("Group: Edit Mode party %s, raid style setting %s, game option %s"):format(tostring(frames.Party),
			tostring(setting.UseRaidStylePartyFrames), tostring(Safe(GetCVar, "useCompactPartyFrames"))))
	end
	if ns.RefreshOptions then ns.RefreshOptions() end
	ns.Print(L.MSG_LAYOUT_READY:format(name))
	return true
end

-- Settings -----------------------------------------------------------------------------

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
		ObjectiveTrackerFrame:SetAlpha(1)
		hoverTracker = 1
		trackerTween:Set(1)
	end
	driver:SetShown((world.cleanMinimap or world.cleanTracker) and true or false)
	ns.ApplyEditLayout()
end

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
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if pendingLayout then ns.ApplyEditLayout() end
		else
			ns.RefreshClean()
		end
	end)
	ns.RefreshClean()
end
