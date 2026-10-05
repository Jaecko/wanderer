local ADDON, ns = ...
local L = ns.L

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

-- Each category drives one or more of the game's "UnitName*" console variables.
-- Variables that do not exist in the running client are ignored.
ns.CATEGORIES = {
	{ key = "own",             cvars = { "UnitNameOwn" } },
	{ key = "friendlyPlayers", cvars = { "UnitNameFriendlyPlayerName" } },
	{ key = "enemyPlayers",    cvars = { "UnitNameEnemyPlayerName" }, enemy = true },
	{ key = "friendlyNPCs",    cvars = { "UnitNameNPC", "UnitNameInteractiveNPC", "UnitNameFriendlySpecialNPCName" } },
	{ key = "hostileNPCs",     cvars = { "UnitNameHostleNPC" }, enemy = true },
	{ key = "critters",        cvars = { "UnitNameNonCombatCreatureName" } },
	{ key = "friendlyPets",    cvars = { "UnitNameFriendlyPetName", "UnitNameFriendlyGuardianName",
		"UnitNameFriendlyMinionName", "UnitNameFriendlyTotemName" } },
	{ key = "enemyPets",       cvars = { "UnitNameEnemyPetName", "UnitNameEnemyGuardianName",
		"UnitNameEnemyMinionName", "UnitNameEnemyTotemName" }, enemy = true },
	{ key = "guilds",          cvars = { "UnitNamePlayerGuild" } },
	{ key = "titles",          cvars = { "UnitNamePlayerPVPTitle" } },
}

ns.PRESETS = {
	immersion = {},
	balanced = { enemyPlayers = true, hostileNPCs = true },
	-- Dungeons and raids: your companions named, never yourself; enemies by
	-- their health bars (names on them).
	group = { friendlyPlayers = true, enemyPlayers = true, hostileNPCs = true, enemyPets = true },
	all = { own = true, friendlyPlayers = true, enemyPlayers = true, friendlyNPCs = true, hostileNPCs = true,
		critters = true, friendlyPets = true, enemyPets = true, guilds = true, titles = true },
}
ns.PRESET_ORDER = { "immersion", "balanced", "all", "custom" }

-- Places where a different preset can apply automatically.
ns.ZONES = { "world", "city", "dungeon", "raid", "pvp" }
ns.ZONE_CHOICES = { "default", "immersion", "balanced", "group", "all" }

-- Settings stored in each profile.
local DEFAULTS = {
	styleVersion = 5,
	enabled = true,
	preset = "immersion",
	show = {},
	combatEnemies = false, -- enemy names in a fight: asked for (their health bars show anyway)
	groupMarks = true, -- in the world, the name of each member of your group, small, over their head
	hideUnitTooltip = true,
	hideTargetTooltip = true, -- no game tooltip over your target's portrait (its auras keep theirs)
	revealMode = "hold",
	zones = {
		world = "default",
		city = "default",
		dungeon = "group",
		raid = "group",
		pvp = "all",
	},
	label = {
		enabled = true,
		style = "blizzard",
		anchor = "head",
		allHeads = true, -- nameplates turned on unseen, so the label finds every head
		worldOnly = true,
		showRace = true,
		showClass = true,
		showSpec = true,
		ownPortrait = true,
		stickyTarget = true, -- your target stays described while nothing else is hovered (off: as before) -- over your portrait, the label shows you (the closer look included)
		shiftDetails = true, -- Shift over a player: talents, item level, guild rank
		showCasts = true,
		showCreatureType = true,
		showClassification = true,
		showNPCRole = true,
		showLevel = true,
		showGuild = true,
		showFaction = true,
		showNPCFaction = false,
		showStatus = true,
		showTarget = true,
		showPortrait = true,
		showHealth = true, -- allies only
		showDifficulty = true,
		showReputation = true,
		showTameable = true,
		showRareKills = true,
		targetName = true,
		showXP = true,
		untagged = true,
		showProfessions = true,
		showQuests = true,
		showLoot = true,
		showObjects = true,
		highlight = true,
		highlightQuest = true,
		highlightRelations = true,
		highlightRank = true,
		threatAlert = true,
		threatSound = true,
		threatVignette = true,
		hideInCombat = false,
		scale = 1,
		offset = 22,
		bgOpacity = 55,
		padding = 8,
		font = "default",
	},
	rp = {
		useName = true,
		showTitle = true,
		showStatus = true,
	},
	tooltips = {
		enabled = true,
		cursor = true,
		icon = true,
		quality = true,
	},
	cinema = {
		enabled = false,
		alpha = 20,
		delay = 4,
		combatOnly = true,
	},
	merchant = {
		sellJunk = true,
		repair = true,
		guildRepair = false,
	},
	loot = {
		fast = true,
	},
	trainer = {
		learnAll = true,
	},
	session = {
		breakEvery = 0, -- minutes, 0: never
	},
	sounds = {
		enabled = true,
		list = "",
	},
	fishing = {
		doubleClick = true,
	},
	journal = {
		enabled = true,
		notices = true, -- a short notice when something is written
		sound = true, -- and the quill on paper
		deaths = false,
	},
	gestures = {
		read = false, -- automations: off until the player asks
		levelUp = false,
		greet = false,
	},
	travel = {
		enabled = true,
		camera = true,
	},
	away = {
		enabled = false, -- an ambiance while away: asked for
		style = "hearth",
	},
	threat = {
		show = true, -- in groups and dungeons only
		alert = true, -- in dungeons and raids, for the one holding the monsters
	},
	messages = {
		enabled = false, -- private messages in their own window: asked for
		popup = true, -- the window opens on a new message (never in a fight)
		hideInChat = true, -- and the chat no longer shows them
		sound = true, -- the game's own whisper sound, which the chat no longer plays for them
	},
	chat = {
		group = true, -- which tabs "Create the chat tabs" makes
		arrowHistory = true, -- Up and Down bring back your sent messages, kept between sessions
		copyButton = true, -- a discreet copy button in the corner of the chat
		keepLog = true, -- each tab keeps its last lines from one session to the next
		guild = true,
		whispers = true,
	},
	scene = {
		enabled = true,
		camera = true,
		textSize = 15,
	},
	quest = {
		autoAccept = false,
		autoTurnIn = false,
		bestReward = true,
		skipGossip = false,
	},
	social = {
		declineDuels = false,
		acceptInvites = false,
		acceptResurrect = false,
		acceptSummon = false,
	},
	bars = {
		border = 100, -- the frame around each action button, % (100: as the game draws it, 0: gone)
		background = 100, -- the background of each slot, %
	},
	world = {
		actionCam = false,
		filterErrors = true,
		hideTalkingHead = false,
		cleanMinimap = false, -- the game's frames as they are, until asked
		cleanTracker = false,
		gatherIcons = false, -- other addons' buttons: left alone until asked
		editLayout = "", -- "": the game's Edit Mode layout is left alone
		moveFrames = false, -- the game's windows where the game puts them, until asked
	},
}
ns.DEFAULTS = DEFAULTS
for _, cat in ipairs(ns.CATEGORIES) do DEFAULTS.show[cat.key] = false end

-- Allowed values, shared by the options panel and the checks of saved and
-- imported settings: numbers { min, max, step }, texts: a list of choices
-- (a function, as some lists are defined by modules loaded later).
ns.RANGES = {
	["label.scale"] = { 0.6, 2, 0.1 },
	["label.offset"] = { 0, 80, 2 },
	["label.padding"] = { 0, 20, 1 },
	["label.bgOpacity"] = { 0, 100, 5 },
	["cinema.alpha"] = { 0, 80, 5 },
	["cinema.delay"] = { 1, 15, 1 },
	["bars.border"] = { 0, 100, 5 },
	["bars.background"] = { 0, 100, 5 },
	["session.breakEvery"] = { 0, 240, 30 },
	["scene.textSize"] = { 12, 22, 1 },
}
local function Keys(list, field)
	local keys = {}
	for i, item in ipairs(list or {}) do keys[i] = field and item[field] or item end
	return keys
end
local CHOICES = {
	["preset"] = function() return ns.PRESET_ORDER end,
	["revealMode"] = function() return { "hold", "toggle" } end,
	["label.style"] = function() return ns.STYLES end,
	["label.font"] = function() return Keys(ns.FONTS, "key") end,
	["label.anchor"] = function() return { "head", "cursor" } end,
	["away.style"] = function() return ns.AWAY_STYLES end,
}
for _, zone in ipairs(ns.ZONES) do CHOICES["zones." .. zone] = function() return ns.ZONE_CHOICES end end

local function IsAllowed(path, value)
	local range = ns.RANGES[path]
	if range then
		-- value == value rejects NaN.
		return type(value) == "number" and value == value and value >= range[1] and value <= range[2]
	end
	local choices = CHOICES[path]
	if choices then
		for _, choice in ipairs(choices() or {}) do
			if choice == value then return true end
		end
		return false
	end
	return true
end

-- Puts back the default of every value of the wrong type or out of its
-- allowed values (old versions, edited saved variables, imports).
local function Sanitize(defaults, values, path)
	for key, default in pairs(defaults) do
		local full = path and (path .. "." .. key) or key
		local value = values[key]
		if type(default) == "table" then
			if type(value) ~= "table" then values[key] = {} end
			Sanitize(default, values[key], full)
		elseif type(value) ~= type(default) or not IsAllowed(full, value) then
			values[key] = default
		end
	end
end

local DEFAULT_PROFILE = "Default"

local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t) do copy[k] = DeepCopy(v) end
	return copy
end

-- In diagnostic mode, in the Wanderer chat tab (only Wanderer's lines there).
function ns.Print(msg)
	local line = "|cff9fb4ffWanderer|r " .. msg
	local frame = ns.debug and ns.debugFrame
	if frame and frame.AddMessage then
		frame:AddMessage(line)
	else
		print(line)
	end
end

-- Console variables ---------------------------------------------------------

local function CVarExists(name)
	return ns.Util.Safe(GetCVar, name) ~= nil
end

function ns.IsCategoryAvailable(cat)
	for _, cvar in ipairs(cat.cvars) do
		if CVarExists(cvar) then return true end
	end
	return false
end

local pendingApply = false

local borrowedTests = {} -- hidden ("test_") settings Wanderer turned on, with their value

-- borrowed: the value is Wanderer's own (not the player's being put back).
local function WriteCVar(name, value, borrowed)
	if not CVarExists(name) then return true end
	if name:find("^test_") then borrowedTests[name] = borrowed and value or nil end
	if GetCVar(name) == value then return true end
	return (pcall(SetCVar, name, value))
end

-- A setting changed for a moment (camera): never left as an unknown value.
ns.WriteCVar = WriteCVar

-- The game warns when one of its hidden ("test_") settings is changed, and
-- asks again after every reload. Once you have accepted it (the settings
-- Wanderer wrote stayed on), Wanderer closes it by itself from then on; refusing it
-- ("Disable" puts them back) keeps it coming.
local WARNING = "EXPERIMENTAL_CVAR_WARNING"
local WATCH_DELAY = 0.5

local function WarningShown()
	return StaticPopup_Visible and ns.Util.Safe(StaticPopup_Visible, WARNING) and true or false
end

local function WatchAnswer()
	if WarningShown() then return C_Timer.After(WATCH_DELAY, WatchAnswer) end
	for name, value in pairs(borrowedTests) do
		if GetCVar(name) == value then
			ns.root.experimentalAccepted = true
			return
		end
	end
end

local function HideWarning()
	if StaticPopup_Hide then ns.Util.Safe(StaticPopup_Hide, WARNING) end
end

if StaticPopup_Show then
	hooksecurefunc("StaticPopup_Show", function(which)
		if which ~= WARNING or not ns.root then return end
		if ns.root.experimentalAccepted then
			HideWarning()
			C_Timer.After(0, HideWarning) -- shown again once the frame is set up
		else
			C_Timer.After(WATCH_DELAY, WatchAnswer)
		end
	end)
end

-- Other variables Wanderer drives: name -> value wanted by the profile, or nil
-- to leave the player's own.
-- Above every head: the nameplates the label needs, out of instances (the
-- game keeps the plates of allies to itself there). Plates.lua keeps the ones
-- Wanderer turned on invisible.
local function AllHeads(db)
	local zone = ns.zone or "world"
	return db.label.allHeads and db.label.anchor == "head" and zone ~= "dungeon" and zone ~= "raid" and zone ~= "pvp"
end

-- In instances the health bars are the player's own choice (the game's
-- Nameplates options, V and Shift+V): Wanderer only turns on, out of them,
-- the plates the label needs.
local function FriendlyPlates(db)
	return AllHeads(db) and "1" or nil
end

local MANAGED_CVARS = {
	nameplateShowAll = function(db) return AllHeads(db) and "1" or nil end,
	nameplateShowFriendlyPlayers = FriendlyPlates,
	nameplateShowFriends = FriendlyPlates, -- its older name
	nameplateShowFriendlyNPCs = function(db) return AllHeads(db) and "1" or nil end,
	nameplateShowEnemyMinus = function(db) return AllHeads(db) and "1" or nil end,
	-- Action camera (hidden settings of the game): pitch following the ground,
	-- camera slightly over the shoulder.
	test_cameraDynamicPitch = function(db) return db.world.actionCam and "1" or nil end,
	test_cameraOverShoulder = function(db) return db.world.actionCam and "0.5" or nil end,
}

-- Remember the player's own values so they can always be restored.
local function Snapshot()
	local original = {}
	for _, cat in ipairs(ns.CATEGORIES) do
		for _, cvar in ipairs(cat.cvars) do
			if CVarExists(cvar) then original[cvar] = GetCVar(cvar) end
		end
	end
	for cvar in pairs(MANAGED_CVARS) do
		if CVarExists(cvar) then original[cvar] = GetCVar(cvar) end
	end
	ns.root.original = original
end

function ns.RestoreOriginal()
	if not ns.root.original then return end
	for cvar, value in pairs(ns.root.original) do
		WriteCVar(cvar, value)
	end
	ns.root.dirty = false
end

-- Whether the game itself writes the name above this unit right now.
function ns.GameShowsName(unit)
	local U = ns.Util
	local cvar
	if U.Clean(U.Safe(UnitIsPlayer, unit)) then
		cvar = U.Clean(U.Safe(UnitCanAttack, "player", unit)) and "UnitNameEnemyPlayerName" or "UnitNameFriendlyPlayerName"
	else
		cvar = U.Clean(U.Safe(UnitCanAttack, "player", unit)) and "UnitNameHostleNPC" or "UnitNameNPC"
	end
	return CVarExists(cvar) and GetCVar(cvar) == "1"
end

-- Zones ---------------------------------------------------------------------

local function DetectZone()
	local inInstance, instanceType = IsInInstance()
	if inInstance then
		if instanceType == "raid" then return "raid" end
		if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
		return "dungeon"
	end
	if IsResting() then return "city" end
	return "world"
end

-- Which names should show, in priority order: reveal key, place rule,
-- player's own choices, then enemies during combat.
local function ShouldShowCategory(cat)
	local db = ns.db
	if ns.revealing then return true end
	local rule = db.zones[ns.zone or "world"]
	local preset = rule and rule ~= "default" and ns.PRESETS[rule]
	local show
	if preset then
		show = preset[cat.key] and true or false
	else
		show = db.show[cat.key] and true or false
	end
	if cat.enemy and db.combatEnemies and ns.inCombat then show = true end
	return show
end

function ns.Apply()
	local db = ns.db
	if not db then return end
	if not db.enabled then
		ns.RestoreOriginal()
		return
	end
	-- Never write before the player's own values are remembered.
	if not ns.root.original then Snapshot() end
	local failed = false
	for _, cat in ipairs(ns.CATEGORIES) do
		local value = ShouldShowCategory(cat) and "1" or "0"
		for _, cvar in ipairs(cat.cvars) do
			if not WriteCVar(cvar, value) then failed = true end
		end
	end
	local original = ns.root.original
	for cvar, wanted in pairs(MANAGED_CVARS) do
		-- Added after the snapshot was taken (older version): the current value
		-- is still the player's own, Wanderer never wrote it.
		if original and original[cvar] == nil and CVarExists(cvar) then original[cvar] = GetCVar(cvar) end
		local own = wanted(db)
		local value = own or (original and original[cvar])
		if value and not WriteCVar(cvar, value, own ~= nil) then failed = true end
	end
	ns.root.dirty = true
	-- Some variables may be locked during combat: retry afterwards.
	pendingApply = failed and InCombatLockdown()
end

-- Profiles by place ------------------------------------------------------------
-- Each kind of place can have its own profile (open world, cities, dungeons,
-- raids, battlegrounds): Wanderer switches to it on arrival and back to the
-- character's own profile elsewhere. Changes made there are kept for that place.

function ns.PlaceProfiles()
	local root = ns.root
	root.placeProfiles = root.placeProfiles or {}
	local key = ns.CharacterKey()
	root.placeProfiles[key] = root.placeProfiles[key] or {}
	return root.placeProfiles[key]
end

-- The profile this place calls for.
local function WantedProfile()
	local root = ns.root
	local own = root.profileKeys[ns.CharacterKey()] or DEFAULT_PROFILE
	local byPlace = ns.PlaceProfiles()[ns.zone or "world"]
	if byPlace and root.profiles[byPlace] then return byPlace end
	return own
end

local pendingProfile = false
function ns.UpdatePlaceProfile()
	if not (ns.root and ns.zone) then return end
	local wanted = WantedProfile()
	if wanted == ns.profileName then return end
	-- Never in a fight: the switch waits for its end.
	if InCombatLockdown() then
		pendingProfile = true
		return
	end
	pendingProfile = false
	ns.SetProfile(wanted, true) -- quietly: the place speaks for itself
end

-- One profile per kind of place, made from the current one, ready to adjust.
-- What each place asks of the interface. The minimap, the quests and the
-- chat are never faded; the rest (portraits, action bars, menus, bags,
-- experience) fades out of the way when it is not needed, and comes back at
-- once in a fight, under the mouse or with a window open.
--   Dungeons (and raids, battlegrounds): everything in view, always.
--   Cities: nothing to fight, many characters to talk to: faded out of a
--   fight even with a target (talking to a merchant brings nothing back).
--   Open world: barely there while calm; a target brings everything back
--   (cooldowns and range before a pull), a fight too.
--   Flights (travel mode, every place): everything fades but the chat.
local PLACE_SETTINGS = {
	dungeon = { enabled = false, combatOnly = false },
	city = { enabled = false, combatOnly = true, alpha = 0, delay = 2 },
	world = { enabled = true, combatOnly = false, alpha = 20, delay = 4 },
}

function ns.MakePlaceProfiles()
	local map = ns.PlaceProfiles()
	local source = ns.root.profileKeys[ns.CharacterKey()] or DEFAULT_PROFILE
	for _, zone in ipairs({ "world", "city", "dungeon" }) do
		local name = L["PLACE_PROFILE_" .. zone:upper()]
		if not ns.root.profiles[name] then ns.root.profiles[name] = DeepCopy(ns.root.profiles[source]) end
		-- Made ready for the place (asked again: set again; the rest is yours).
		local profile = ns.root.profiles[name]
		profile.cinema = profile.cinema or {}
		for key, value in pairs(PLACE_SETTINGS[zone]) do profile.cinema[key] = value end
		profile.travel = profile.travel or {}
		profile.travel.enabled = true
		map[zone] = name
	end
	map.raid = map.raid or map.dungeon
	map.pvp = map.pvp or map.dungeon
	ns.UpdatePlaceProfile()
	if ns.RefreshOptions then ns.RefreshOptions() end
	ns.Print(L.MSG_PLACE_PROFILES_MADE)
end

local function UpdateZone()
	local zone = DetectZone()
	if zone ~= ns.zone then
		ns.zone = zone
		ns.Apply()
		ns.UpdatePlaceProfile()
	end
end

-- Refreshes every module after a settings change.
function ns.RefreshAll()
	ns.Apply()
	if ns.RefreshOptions then ns.RefreshOptions() end
	if ns.RefreshLabel then ns.RefreshLabel() end
	if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
	if ns.RefreshCinema then ns.RefreshCinema() end
	if ns.RefreshTooltips then ns.RefreshTooltips() end
	if ns.RefreshTrainer then ns.RefreshTrainer() end
	if ns.RefreshScreen then ns.RefreshScreen() end
	if ns.RefreshTargetLabel then ns.RefreshTargetLabel() end
	if ns.RefreshSession then ns.RefreshSession() end
	if ns.RefreshSounds then ns.RefreshSounds() end
	if ns.RefreshScene then ns.RefreshScene() end
	if ns.RefreshClean then ns.RefreshClean() end
	if ns.RefreshIcons then ns.RefreshIcons() end
	if ns.RefreshBarSlots then ns.RefreshBarSlots() end
	if ns.RefreshChatComfort then ns.RefreshChatComfort() end
	if ns.RefreshGameFrames then ns.RefreshGameFrames() end
	if ns.RefreshMail then ns.RefreshMail() end
	if ns.RefreshTargetInfo then ns.RefreshTargetInfo() end
	if ns.RefreshPlates then ns.RefreshPlates() end
	if ns.RefreshAway then ns.RefreshAway() end
end

function ns.SetPreset(preset)
	local values = ns.PRESETS[preset]
	if not values then return end
	ns.db.preset = preset
	for _, cat in ipairs(ns.CATEGORIES) do
		ns.db.show[cat.key] = values[cat.key] and true or false
	end
	ns.db.label.enabled = preset ~= "all"
	ns.RefreshAll()
end

function ns.SetEnabled(enabled)
	ns.db.enabled = enabled and true or false
	-- Every module, so nothing of Wanderer stays active (e.g. its interaction key).
	ns.RefreshAll()
end

-- Profiles --------------------------------------------------------------------
-- WandererDB = { profiles = { name = settings }, profileKeys = { character = name },
--             original, dirty, questBook, minimap }

function ns.CharacterKey()
	local name = UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return name .. " - " .. realm
end

-- Moves the settings of versions before profiles into the default profile.
local function Migrate(root)
	if root.profiles then return end
	local profile = {}
	for key in pairs(DEFAULTS) do
		if root[key] ~= nil then profile[key] = root[key] root[key] = nil end
	end
	root.profiles = { [DEFAULT_PROFILE] = profile }
end

function ns.SetProfile(name, byPlace)
	local root = ns.root
	if not root.profiles[name] then root.profiles[name] = {} end
	local profile = root.profiles[name]
	-- Profiles made before 0.11: the label replaces the game's tooltip for
	-- characters. Version 0.14 had removed the "Game interface" style and moved
	-- its users to Minimal: they get it back.
	if profile.label and (profile.styleVersion or 0) < 4 then
		if not profile.styleVersion then profile.hideUnitTooltip = true end
		if not profile.styleVersion or profile.styleVersion == 3 and profile.label.style == "minimal" then
			profile.label.style = "blizzard"
		end
		profile.styleVersion = 4
	end
	-- 0.21: the label replaces the game's tooltip in the world, once for every
	-- profile (the game's tooltip showed with it); the choice stays free after.
	if (profile.styleVersion or 0) < 5 then
		profile.hideUnitTooltip = true
		profile.styleVersion = 5
	end
	-- 0.34: enemy names no longer come back in a fight unless asked, once for
	-- every profile; the choice stays free after.
	if (profile.styleVersion or 0) < 6 then
		profile.combatEnemies = false
		profile.styleVersion = 6
	end
	-- 0.36: dungeons and raids name your companions but never you, once for
	-- every profile that had the earlier choices there; free after.
	if (profile.styleVersion or 0) < 7 then
		for _, zone in ipairs({ "dungeon", "raid" }) do
			local rule = type(profile.zones) == "table" and profile.zones[zone]
			if rule == "balanced" or rule == "all" then profile.zones[zone] = "group" end
		end
		profile.styleVersion = 7
	end
	-- 0.36: the label stays on your target, once for every profile; free after.
	if (profile.styleVersion or 0) < 8 then
		if type(profile.label) == "table" then profile.label.stickyTarget = true end
		profile.styleVersion = 8
	end
	Sanitize(DEFAULTS, profile)
	profile.cinema.combatBars = nil -- 0.18: replaced by combatOnly (every faded element)
	-- Not in DEFAULTS (nil means the game's own key): checked on its own.
	-- Settings of modules that are gone (the game does it itself).
	profile.interact, profile.questLog, profile.dev = nil, nil, nil
	if not byPlace then root.profileKeys[ns.CharacterKey()] = name end
	ns.profileName = name
	ns.db = root.profiles[name]
	if ns.initialized then ns.RefreshAll() end
end

-- The active profile back to Wanderer's defaults. The journal, the other
-- profiles and the game's own settings are not part of it.
function ns.ResetProfile()
	local name = ns.profileName
	ns.root.profiles[name] = {}
	ns.SetProfile(name)
	if ns.RefreshOptions then ns.RefreshOptions() end
	if ns.RefreshThemeGrids then ns.RefreshThemeGrids() end
	ns.Print(L.MSG_RESET_PROFILE:format(name))
end

function ns.ListProfiles()
	local names = {}
	for name in pairs(ns.root.profiles) do names[#names + 1] = name end
	table.sort(names)
	return names
end

function ns.CopyProfile(name, source)
	ns.root.profiles[name] = DeepCopy(ns.root.profiles[source or ns.profileName])
	ns.SetProfile(name)
end

function ns.DeleteProfile(name)
	if name == DEFAULT_PROFILE then return false end
	ns.root.profiles[name] = nil
	for character, profile in pairs(ns.root.profileKeys) do
		if profile == name then ns.root.profileKeys[character] = DEFAULT_PROFILE end
	end
	for _, places in pairs(ns.root.placeProfiles or {}) do
		for zone, profile in pairs(places) do
			if profile == name then places[zone] = nil end
		end
	end
	if ns.profileName == name then ns.SetProfile(DEFAULT_PROFILE) end
	return true
end

-- Export / import: "WANDERER1;label.scale=1.2;show.own=0;preset=immersion".
-- Only keys known in DEFAULTS, with the same type and an allowed value, are accepted.
local EXPORT_PREFIX = "WANDERER1"

local function Encode(value)
	return (tostring(value):gsub("[;=%%]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Decode(text)
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function ns.ExportProfile()
	local parts = { EXPORT_PREFIX }
	local function walk(defaults, values, path)
		local keys = {}
		for key in pairs(defaults) do keys[#keys + 1] = key end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local full = path and (path .. "." .. key) or key
			if type(defaults[key]) == "table" then
				walk(defaults[key], values[key] or {}, full)
			else
				local value = values[key]
				if type(value) == "boolean" then value = value and 1 or 0 end
				parts[#parts + 1] = full .. "=" .. Encode(value)
			end
		end
	end
	walk(DEFAULTS, ns.db)
	return table.concat(parts, ";")
end

-- Returns the imported settings table, or nil and an error message.
local function ParseExport(text)
	text = strtrim(text or "")
	local fields = {}
	for field in text:gmatch("[^;]+") do fields[#fields + 1] = field end
	if fields[1] ~= EXPORT_PREFIX then return nil, L.IMPORT_INVALID end
	local settings = DeepCopy(DEFAULTS)
	local count = 0
	for i = 2, #fields do
		local path, raw = fields[i]:match("^([%w%.]+)=(.*)$")
		if path then
			local parent, defaults, key = settings, DEFAULTS, nil
			for part in path:gmatch("[^%.]+") do
				if key then
					parent, defaults = parent[key], defaults[key]
					if type(defaults) ~= "table" then parent = nil break end
				end
				key = part
			end
			local expected = parent and defaults and defaults[key]
			local value = Decode(raw)
			if type(expected) == "boolean" then
				parent[key] = value == "1"
				count = count + 1
			elseif type(expected) == "number" and tonumber(value) then
				parent[key] = tonumber(value)
				count = count + 1
			elseif type(expected) == "string" then
				parent[key] = value
				count = count + 1
			end
		end
	end
	if count == 0 then return nil, L.IMPORT_INVALID end
	Sanitize(DEFAULTS, settings)
	return settings
end

function ns.ImportProfile(text, name)
	local settings, err = ParseExport(text)
	if not settings then return false, err end
	ns.root.profiles[name] = settings
	ns.SetProfile(name)
	return true
end

-- Reveal key ------------------------------------------------------------------

function ns.SetRevealing(revealing)
	revealing = revealing and true or false
	if ns.revealing == revealing then return end
	ns.revealing = revealing
	ns.Apply()
end

-- Called by the key binding (Bindings.xml): "down" when pressed, "up" when released.
function Wanderer_Reveal(keystate)
	if not (ns.db and ns.db.enabled) then return end
	if ns.db.revealMode == "toggle" then
		if keystate == "down" then ns.SetRevealing(not ns.revealing) end
	else
		ns.SetRevealing(keystate == "down")
	end
end

BINDING_HEADER_WANDERER = L.ADDON_TITLE
BINDING_NAME_WANDERER_REVEAL = L.BINDING_REVEAL
BINDING_NAME_WANDERER_PHOTO = L.BINDING_PHOTO
BINDING_NAME_WANDERER_MESSAGES = L.BINDING_MESSAGES
BINDING_NAME_WANDERER_MARKERS = L.BINDING_MARKERS
BINDING_NAME_WANDERER_TODO = L.BINDING_TODO
_G["BINDING_NAME_CLICK WandererCampfire:LeftButton"] = L.BINDING_CAMPFIRE
function Wanderer_ToggleMessages() ns.ToggleMessages() end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		WandererDB = WandererDB or {}
		ns.root = WandererDB
		Migrate(WandererDB)
		-- The interaction prompt is gone: the game's own setting is the
		-- player's again, as it was before Wanderer.
		local original = WandererDB.original
		if original and original.SoftTargetInteract ~= nil then
			pcall(SetCVar, "SoftTargetInteract", original.SoftTargetInteract)
			original.SoftTargetInteract = nil
		end
		WandererDB.profileKeys = WandererDB.profileKeys or {}
		ns.SetProfile(WandererDB.profileKeys[ns.CharacterKey()] or DEFAULT_PROFILE)
		-- Modules are built once: frames, hooks and events must never be doubled.
		if not ns.initialized then
			for _, init in ipairs({ "InitLabel", "InitOptions", "InitMinimapButton", "InitCinema", "InitTooltips",
				"InitMerchant", "InitLoot", "InitTrainer", "InitDialogues", "InitSocial", "InitScreen", "InitTargetLabel",
				"InitTagging", "InitPlates", "InitMarkers", "InitToast", "InitSession", "InitSounds", "InitFishing", "InitJournal", "InitScene", "InitCamera", "InitGestures", "InitCurtain", "InitAway", "InitClean", "InitIcons", "InitMail", "InitThreat", "InitTargetInfo", "InitMessages", "InitGameFrames", "InitBarSlots", "InitChatComfort", "InitNews", "InitPreview", "InitWelcome" }) do
				if ns[init] then ns[init]() end
			end
			ns.initialized = true
		end
	elseif event == "PLAYER_LOGIN" then
		-- Values are restored on every clean logout, so the current ones are the
		-- player's own. After a crash (dirty), keep the previous snapshot.
		if not ns.root.dirty or not ns.root.original then Snapshot() end
		ns.inCombat = InCombatLockdown()
		ns.zone = DetectZone()
		ns.Apply()
		ns.UpdatePlaceProfile()
	elseif event == "PLAYER_LOGOUT" then
		-- Leave the game exactly as it was without Wanderer, in case it gets disabled.
		ns.RestoreOriginal()
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.inCombat = true
		if ns.db.enabled and ns.db.combatEnemies then ns.Apply() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.inCombat = false
		if pendingApply or (ns.db.enabled and ns.db.combatEnemies) then ns.Apply() end
		if pendingProfile then ns.UpdatePlaceProfile() end
	else -- zone changes
		UpdateZone()
	end
end)

-- Slash command & addon compartment ----------------------------------------

local PRESET_ALIASES = {
	immersion = "immersion",
	balanced = "balanced", equilibre = "balanced", ["équilibré"] = "balanced",
	all = "all", tout = "all",
}

SLASH_WANDERER1 = "/wanderer"
SlashCmdList.WANDERER = function(msg)
	msg = strtrim((msg or ""):lower())
	if msg == "" or msg == "options" or msg == "config" then
		ns.OpenOptions()
	elseif msg == "on" then
		ns.SetEnabled(true)
		ns.Print(L.MSG_ENABLED)
	elseif msg == "off" then
		ns.SetEnabled(false)
		ns.Print(L.MSG_DISABLED)
	elseif msg == "reset" then
		ns.SetEnabled(false)
		ns.Print(L.MSG_RESTORED)
	elseif msg == "reveal" or msg == "reveler" or msg == "révéler" then
		ns.SetRevealing(not ns.revealing)
	elseif msg:match("^style") then
		local style = strtrim(msg:sub(6))
		local names = {}
		for _, name in ipairs(ns.STYLES) do
			names[#names + 1] = name
			if name == style then
				ns.db.label.style = style
				ns.RefreshAll()
				ns.Print(L.MSG_STYLE:format(L["STYLE_" .. style:upper()]))
				return
			end
		end
		ns.Print(L.MSG_STYLE_HELP:format(table.concat(names, ", ")))
	elseif msg == "bienvenue" or msg == "welcome" then
		ns.ShowWelcome()
	elseif msg == "copy" or msg == "copier" then
		ns.CopyChat()
	elseif msg == "messages" or msg == "msg" then
		ns.ToggleMessages()
	elseif msg == "away" or msg == "absent" then
		ns.GoAway()
	elseif msg == "photo" then
		ns.TogglePhotoMode()
	elseif msg == "nouveautes" or msg == "nouveautés" or msg == "news" then
		ns.ShowNews()
	elseif msg == "carnet" or msg == "journal" then
		ns.ToggleJournal()
	elseif msg == "bilan" or msg == "session" then
		ns.PrintSession()
	elseif msg == "talents" and ns.DebugTalents then
		ns.DebugTalents()
	elseif msg == "todo" or msg == "afaire" or msg == "à faire" then
		ns.ToggleTodo()
	elseif msg == "clear" or msg == "effacer" then
		-- The tab shown (the Wanderer tab in diagnostic mode), and what it kept.
		local frame = ns.debug and ns.debugFrame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
		if frame and frame.Clear then
			frame:Clear()
			if ns.ForgetChatLog then ns.ForgetChatLog(frame) end
		end
	elseif msg == "debug" then
		ns.debug = not ns.debug
		ns.debugFrame = ns.debug and ns.DebugFrame and ns.DebugFrame(true) or nil
		if ns.debugFrame and FCF_SelectDockFrame then pcall(FCF_SelectDockFrame, ns.debugFrame) end
		ns.Print(ns.debug and L.DEBUG_ON or L.DEBUG_OFF)
		if ns.debug and ns.DebugEnvironment then ns.DebugEnvironment() end
		if ns.debug then ns.Print(ns.Util.DebugNames()) end
	elseif PRESET_ALIASES[msg] then
		local preset = PRESET_ALIASES[msg]
		ns.db.enabled = true
		ns.SetPreset(preset)
		ns.Print(L.MSG_PRESET:format(L["PRESET_" .. preset:upper()]))
	else
		ns.Print(L.SLASH_HELP)
	end
end

function Wanderer_OnAddonCompartmentClick(_, _, menuButton)
	if ns.ShowMenu then ns.ShowMenu(menuButton) else ns.OpenOptions() end
end
