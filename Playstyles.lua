local _, ns = ...
local L = ns.L

-- Ways to play: six ways of walking the world, each one click away (at the welcome and on the options' page
-- "Ways to play"). Each writes the same managed set of settings (BASE), so going from one to another never
-- leaves something of the first behind; keys outside the set are never touched. A way only changes how the
-- character plays, never its look (themes, unit frames, label's look, windows' spots), apart from the minimap in
-- Wanderer's style for every way and the quiet tracker of Immersion and Roleplay (presets approved 2026-11-06;
-- 2026-11-07: the choices of the user's own main character taken over where they fit each way).
-- Extension settings are written even before the extension is installed: it starts as the way wanted. The way chosen is kept in the
-- profile (playstyle); changed since, the character's way reads "custom".
-- Shared here: the data, applying, the undo of the options, and the grid of cards with its panel (the
-- welcome and the options draw the same one).

local U = ns.Util

ns.PLAYSTYLE_ORDER = { "newcomer", "immersion", "roleplay", "adventurer", "dungeons", "artisan" }

-- The managed set, in order, with its base values (a way changes some of them). Extension keys last.
local BASE_LIST = {
	{ "combatEnemies", false }, { "label.stickyTarget", true }, { "enemyNames", "names" }, { "nearNames.show", "bar" },
	{ "zones.dungeon", "group" }, { "zones.raid", "group" }, { "groupMarks", true }, { "guildMarks", true },
	{ "label.showPower", true }, { "scene.enabled", true }, { "scene.camera", true }, { "scene.cameraShops", false }, { "scene.hush", false },
	{ "cinema.enabled", false }, { "cinema.combatOnly", false }, { "cinema.alpha", 20 }, { "travel.enabled", true },
	{ "away.enabled", false }, { "away.style", "hearth" },
	{ "world.styledMinimap", true }, { "world.cleanMinimap", false }, { "world.cleanTracker", false },
	{ "world.styledTracker", false }, { "world.gatherIcons", true }, { "world.bar", true }, { "world.filterErrors", false },
	{ "world.lootSparkle", false }, { "sparkles.nodes", false }, { "sparkles.questObjects", false },
	{ "quest.autoAccept", false }, { "quest.autoTurnIn", false }, { "quest.skipGossip", false },
	{ "gestures.read", false }, { "gestures.levelUp", false }, { "gestures.greet", false }, { "emotes.enabled", false },
	{ "hands.standUp", false }, { "hands.bagsClosed", false }, { "fishing.splash", false }, { "crafts.skillUps", false },
	{ "loot.fast", true }, { "threat.show", true }, { "threat.alert", true }, { "meter.show", "own" },
	{ "dots.enabled", false }, { "hots.enabled", false }, { "social.acceptResurrect", false }, { "social.acceptSummon", false },
	-- (the extensions')
	{ "quests.mapGivers", true }, { "quests.remind", false }, { "quests.foldStory", false }, { "training.remind", false },
	{ "maps.services", false }, { "maps.flightNotice", false }, { "maps.arrowQuiet", false },
	{ "outfits.poleOnCast", false }, { "outfits.weaponsOnMount", false },
	{ "chat.messagesWindow", false }, { "chat.quietChannels", true }, { "chat.lookingFor", false },
	{ "chat.mentionChannels", false },
}
ns.PLAYSTYLE_KEYS, ns.PLAYSTYLE_BASE = {}, {}
for index, entry in ipairs(BASE_LIST) do
	ns.PLAYSTYLE_KEYS[index] = entry[1]
	ns.PLAYSTYLE_BASE[entry[1]] = entry[2]
end

-- The extensions' sections, their addon, and the defaults they register (known before they are installed).
local EXTENSION_ADDON = { quests = "WandererQuests", training = "WandererTraining", maps = "WandererMaps",
	outfits = "WandererOutfits", chat = "WandererChat", bags = "WandererBags", auction = "WandererAuction" }
ns.PLAYSTYLE_EXT_DEFAULTS = {}
for _, entry in ipairs(BASE_LIST) do
	local section = U.SplitPath(entry[1])
	if section and EXTENSION_ADDON[section] then ns.PLAYSTYLE_EXT_DEFAULTS[entry[1]] = entry[2] end
end

-- What a way does for you (the "Done for you" column; Shift skips each of them).
ns.PLAYSTYLE_AUTOMATIONS = { ["quest.autoAccept"] = true, ["quest.autoTurnIn"] = true, ["quest.skipGossip"] = true,
	["hands.standUp"] = true, ["gestures.read"] = true, ["gestures.levelUp"] = true, ["gestures.greet"] = true,
	["outfits.poleOnCast"] = true, ["outfits.weaponsOnMount"] = true,
	["social.acceptResurrect"] = true, ["social.acceptSummon"] = true }

local ICONS = "Interface\\Icons\\"
-- key, names (ns.PRESETS), places ("make", "clear", "keep"), icon, values (beside the base), told (defaults it tells).
local function Way(key, names, places, icon, values, told)
	local all = {}
	for path, value in pairs(ns.PLAYSTYLE_BASE) do all[path] = value end
	for path, value in pairs(values) do all[path] = value end
	return { key = key, names = names, places = places, icon = ICONS .. icon, values = all, own = values, told = told }
end

ns.PLAYSTYLES = {
	-- A first character: the world explained along the way, everything where the game puts it.
	newcomer = Way("newcomer", "balanced", "clear", "INV_Torch_Lit", {
		["world.lootSparkle"] = true, ["sparkles.nodes"] = true,
		["sparkles.questObjects"] = true, ["hands.standUp"] = true,
		["quests.remind"] = true, ["training.remind"] = true, ["maps.services"] = true, ["maps.flightNotice"] = true,
		["chat.quietChannels"] = true, ["chat.lookingFor"] = true,
	}, { "tooltips.sellPrice", "tooltips.reagents", "tooltips.upgrade", "merchant.sellJunk", "merchant.repair",
		"merchant.repairReminder", "loot.feed", "world.townCard", "world.threshold", "buffs.remind", "crafts.gatherReach",
		"crafts.ceiling", "fishing.doubleClick", "bags.upgrade", "bags.junk", "quests.mapGivers", "maps.arrow" }),
	-- No names, face to face, an interface that steps aside, a world to discover.
	immersion = Way("immersion", "immersion", "make", "INV_Misc_Map_01", {
		["enemyNames"] = "near", ["label.showPower"] = false, ["scene.cameraShops"] = true, ["scene.hush"] = true,
		["cinema.enabled"] = true, ["cinema.combatOnly"] = true, ["away.enabled"] = true, ["away.style"] = "contemplation",
		["world.cleanMinimap"] = true, ["world.cleanTracker"] = true, ["world.styledTracker"] = true,
		["world.filterErrors"] = true, ["world.lootSparkle"] = true, ["sparkles.nodes"] = true, ["sparkles.questObjects"] = true,
		["hands.standUp"] = true, ["fishing.splash"] = true, ["quest.skipGossip"] = true,
		["gestures.read"] = true, ["gestures.levelUp"] = true, ["gestures.greet"] = true, ["emotes.enabled"] = true,
		["dots.enabled"] = true, ["hots.enabled"] = true, ["social.acceptResurrect"] = true, ["social.acceptSummon"] = true,
		["outfits.poleOnCast"] = true, ["outfits.weaponsOnMount"] = true,
		["quests.mapGivers"] = false, ["quests.foldStory"] = true, ["maps.arrowQuiet"] = true,
		["chat.messagesWindow"] = true, ["chat.quietChannels"] = true,
	}, { "scene.reader", "travel.camera", "gestures.sitAtFire", "fishing.doubleClick", "world.layer" }),
	-- Quiet scenes, whispers as conversations, a character who greets, reads and expresses itself.
	roleplay = Way("roleplay", "immersion", "make", "INV_Misc_Book_09", {
		["enemyNames"] = "near", ["nearNames.show"] = "name", ["label.showPower"] = false, ["scene.cameraShops"] = true,
		["scene.hush"] = true, ["cinema.enabled"] = true, ["cinema.combatOnly"] = true, ["away.enabled"] = true,
		["world.cleanMinimap"] = true, ["world.cleanTracker"] = true, ["world.styledTracker"] = true,
		["world.filterErrors"] = true, ["sparkles.nodes"] = true,
		["gestures.read"] = true, ["gestures.levelUp"] = true, ["gestures.greet"] = true, ["emotes.enabled"] = true,
		["hands.bagsClosed"] = true, ["fishing.splash"] = true,
		["quests.mapGivers"] = false, ["quests.foldStory"] = true, ["maps.arrowQuiet"] = true,
		["chat.messagesWindow"] = true, ["chat.quietChannels"] = true,
	}, { "scene.reader", "gestures.sitAtFire", "chat.greetings", "chat.nameCard", "rp.useName" }),
	-- Quests without delay, the way shown, nothing in the way.
	adventurer = Way("adventurer", "balanced", "keep", "Ability_Rogue_Sprint", {
		["scene.enabled"] = false, ["scene.camera"] = false, ["world.filterErrors"] = true, ["world.lootSparkle"] = true,
		["sparkles.nodes"] = true, ["sparkles.questObjects"] = true, ["quest.autoAccept"] = true, ["quest.autoTurnIn"] = true, ["quest.skipGossip"] = true,
		["hands.standUp"] = true,
		["quests.remind"] = true, ["training.remind"] = true, ["maps.services"] = true, ["maps.flightNotice"] = true,
		["chat.quietChannels"] = true, ["chat.lookingFor"] = true,
	}, { "merchant.sellJunk", "merchant.repair", "merchant.provisions", "tooltips.upgrade", "loot.feed", "world.townCard",
		"training.trainer" }),
	-- Companions named, threat at a glance, the damage meter, your effects over time estimated.
	dungeons = Way("dungeons", "balanced", "keep", "INV_Shield_06", {
		["scene.camera"] = false, ["world.filterErrors"] = true, ["hands.standUp"] = true, ["meter.show"] = "on",
		["dots.enabled"] = true, ["hots.enabled"] = true, ["social.acceptResurrect"] = true, ["social.acceptSummon"] = true,
		["quests.remind"] = true, ["training.remind"] = true, ["chat.quietChannels"] = true, ["chat.lookingFor"] = true,
	}, { "world.threshold", "buffs.remind", "label.threatAlert" }),
	-- Herbs and veins spotted, reagents explained, the right price at a glance, fishing in one gesture.
	artisan = Way("artisan", "balanced", "keep", "Trade_BlackSmithing", {
		["world.filterErrors"] = true, ["sparkles.nodes"] = true, ["hands.standUp"] = true, ["fishing.splash"] = true,
		["crafts.skillUps"] = true,
		["maps.services"] = true, ["outfits.poleOnCast"] = true, ["outfits.weaponsOnMount"] = true,
		["chat.quietChannels"] = true, ["chat.mentionChannels"] = true,
	}, { "tooltips.reagents", "tooltips.sellPrice", "bags.byProfession", "bags.others", "bags.toBank", "auction.toMerchant",
		"maps.zoneFacts", "crafts.gatherReach", "crafts.ceiling", "fishing.doubleClick" }),
}

-- The panel's lines: a value of the set that is worth telling, in its column ("shows", "done", "left"). In
-- this order on the panel (a way's lines from installed extensions first). when(values): only then.
local LINES = {
	{ "places", "make", "PLAY_LINE_PLACES_MAKE", "shows" },
	{ "enemyNames", "near", "PLAY_LINE_ENEMIES_NEAR", "shows" },
	{ "quests.remind", true, "PLAY_LINE_QUESTS_REMIND", "shows" },
	{ "training.remind", true, "PLAY_LINE_TRAINING_REMIND", "shows" },
	{ "maps.services", true, "PLAY_LINE_MAPS_SERVICES", "shows" },
	{ "maps.flightNotice", true, "PLAY_LINE_MAPS_FLIGHTS", "shows" },
	{ "meter.show", "on", "PLAY_LINE_METER", "shows" },
	{ "dots.enabled", true, "DOTS_ENABLE", "shows" },
	{ "hots.enabled", true, "HOTS_ENABLE", "shows" },
	{ "emotes.enabled", true, "EMOTES_BAR", "shows" },
	{ "scene.cameraShops", true, "PLAY_LINE_CAMERA_SHOPS", "shows" },
	{ "scene.hush", true, "SCENE_HUSH", "shows" },
	{ "chat.messagesWindow", true, "PLAY_LINE_CHAT_WHISPERS", "shows" },
	{ "away.enabled", true, "AWAY_ENABLE", "shows" },
	{ "quests.foldStory", true, "PLAY_LINE_QUESTS_FOLD", "shows" },
	{ "maps.arrowQuiet", true, "PLAY_LINE_MAPS_ARROW_QUIET", "shows" },
	{ "sparkles.nodes", true, "SPARKLE_NODES", "shows" },
	{ "sparkles.questObjects", true, "PLAY_LINE_QUEST_OBJECTS", "shows" },
	{ "world.lootSparkle", true, "LOOT_SPARKLE", "shows" },
	{ "crafts.skillUps", true, "CRAFTS_SKILL_UPS", "shows" },
	{ "chat.mentionChannels", true, "PLAY_LINE_CHAT_MENTION", "shows" },
	{ "chat.lookingFor", true, "PLAY_LINE_CHAT_LFG", "shows" },
	{ "fishing.splash", true, "FISHING_SPLASH", "shows" },
	{ "world.filterErrors", true, "WORLD_ERRORS", "shows" },
	{ "world.bar", true, "BAR_SHOW", "shows" },
	{ "world.cleanMinimap", true, "CLEAN_MINIMAP", "shows" },
	{ "world.cleanTracker", true, "CLEAN_TRACKER", "shows" },
	{ "world.styledTracker", true, "STYLED_TRACKER", "shows" },
	{ "world.gatherIcons", true, "GATHER_ICONS", "shows" },
	{ "hands.bagsClosed", true, "HANDS_BAGS", "shows" },
	{ "chat.quietChannels", true, "PLAY_LINE_CHAT_QUIET", "shows" },
	{ "quest.autoAccept", true, "QUEST_AUTO_ACCEPT", "done" },
	{ "quest.autoTurnIn", true, "QUEST_AUTO_TURNIN", "done" },
	{ "quest.skipGossip", true, "QUEST_SKIP_GOSSIP", "done" },
	{ "gestures.greet", true, "GESTURES_GREET", "done" },
	{ "gestures.read", true, "GESTURES_READ", "done" },
	{ "gestures.levelUp", true, "GESTURES_LEVEL", "done" },
	{ "outfits.poleOnCast", true, "PLAY_LINE_OUTFITS_POLE", "done" },
	{ "hands.standUp", true, "HANDS_STAND", "done" },
	{ "social.acceptResurrect", true, "SOCIAL_RESURRECT", "done" },
	{ "social.acceptSummon", true, "SOCIAL_SUMMON", "done" },
	{ "names", "immersion", "PLAY_LINE_NAMES_QUIET", "left" },
	{ "quests.mapGivers", false, "PLAY_LINE_QUESTS_GIVERS_OFF", "left" },
	{ "scene.enabled", false, "PLAY_LINE_SCENES_OFF", "left" },
	{ "scene.camera", false, "PLAY_LINE_CAMERA_STILL", "left", function(values) return values["scene.enabled"] ~= false end },
}
ns.PLAYSTYLE_LINES = LINES

-- The defaults a card tells ("Already on"), by their words.
local TOLD_WORDS = {
	["tooltips.sellPrice"] = "TOOLTIPS_SELL_PRICE", ["tooltips.reagents"] = "TOOLTIPS_REAGENTS", ["tooltips.upgrade"] = "TOOLTIPS_UPGRADE",
	["merchant.sellJunk"] = "MERCHANT_SELL_JUNK", ["merchant.repair"] = "MERCHANT_REPAIR", ["merchant.repairReminder"] = "REPAIR_REMINDER",
	["merchant.provisions"] = "PROVISIONS_OPTION", ["loot.feed"] = "LOOT_FEED", ["world.townCard"] = "TOWN_CARD",
	["world.threshold"] = "THRESHOLD", ["buffs.remind"] = "BUFF_REMIND", ["crafts.gatherReach"] = "CRAFTS_GATHER_REACH",
	["crafts.ceiling"] = "CRAFTS_CEILING", ["fishing.doubleClick"] = "FISHING_DOUBLE_CLICK", ["scene.reader"] = "SCENE_READER",
	["travel.camera"] = "TRAVEL_CAMERA", ["gestures.sitAtFire"] = "GESTURES_SIT_FIRE", ["world.layer"] = "LAYER_OPTION",
	["label.threatAlert"] = "LABEL_THREAT", ["rp.useName"] = "RP_NAME",
	["bags.upgrade"] = "PLAY_TOLD_BAGS_UPGRADE", ["bags.junk"] = "PLAY_TOLD_BAGS_JUNK", ["bags.others"] = "PLAY_TOLD_BAGS_OTHERS",
	["bags.toBank"] = "PLAY_TOLD_BAGS_BANK", ["bags.byProfession"] = "PLAY_TOLD_BAGS_PROFESSION",
	["auction.toMerchant"] = "PLAY_TOLD_AUCTION_MERCHANT", ["maps.zoneFacts"] = "PLAY_TOLD_MAPS_ZONES",
	["maps.arrow"] = "PLAY_LINE_MAPS_ARROW", ["quests.mapGivers"] = "PLAY_LINE_QUESTS_GIVERS",
	["training.trainer"] = "PLAY_TOLD_TRAINING_TRAINER", ["chat.greetings"] = "PLAY_TOLD_CHAT_GREETINGS",
	["chat.nameCard"] = "PLAY_TOLD_CHAT_NAMECARD",
}
ns.PLAYSTYLE_TOLD_WORDS = TOLD_WORDS

-- Values ----------------------------------------------------------------------------------------------------

-- A value of a profile by its path; not there: the default it would take.
local function ValueOf(profile, path)
	local section, field = U.SplitPath(path)
	local value
	if section then
		if type(profile[section]) == "table" then value = profile[section][field] end
		if value == nil then
			local defaults = ns.DEFAULTS[section]
			if type(defaults) == "table" then value = defaults[field] end
			if value == nil then value = ns.PLAYSTYLE_EXT_DEFAULTS[path] end
		end
	else
		value = profile[path]
		if value == nil then value = ns.DEFAULTS[path] end
	end
	return value
end
ns.PlaystyleValueOf = ValueOf

local function Assign(profile, values)
	for path, value in pairs(values) do
		local section, field = U.SplitPath(path)
		if section then
			profile[section] = type(profile[section]) == "table" and profile[section] or {}
			profile[section][field] = value
		else
			profile[path] = value
		end
	end
end

-- A way written into a profile: its values, its names, Wanderer on, the way remembered.
local function ApplyTo(profile, way)
	Assign(profile, way.values)
	local names = ns.PRESETS[way.names] or {}
	profile.preset = way.names
	profile.show = type(profile.show) == "table" and profile.show or {}
	for _, category in ipairs(ns.CATEGORIES) do profile.show[category.key] = names[category.key] and true or false end
	profile.label = type(profile.label) == "table" and profile.label or {}
	profile.label.enabled = way.names ~= "all"
	profile.enabled = true
	profile.playstyle = way.key
end

-- A setting's value in the profile's way (the way kept even once customised), as ApplyPlaystyle writes it (a
-- place's profile: its damage meter, and its fade when the way makes the places); nil: no way chosen, or a
-- setting the ways leave alone ("What you changed" compares with it before Wanderer's defaults).
function ns.WayValue(path, profile)
	profile = profile or ns.db
	local way = type(profile) == "table" and ns.PLAYSTYLES[profile.playstyle or ""]
	if not way then return nil end
	local place = ns.PlaceValue and ns.PlaceValue(path, profile)
	if place ~= nil and (way.places == "make" or path == "meter.show") then return place end
	if path == "preset" then return way.names end
	if path == "label.enabled" then return way.names ~= "all" end
	if path == "enabled" then return true end
	return way.values[path]
end

-- This character's profile outside the places' (the one a way is judged by), else the active one.
local function ChosenTable()
	local root = ns.root
	local profile = root and type(root.profiles) == "table" and root.profiles[ns.ChosenProfile()]
	return type(profile) == "table" and profile or ns.db
end

-- The minimap's and the tracker's looks are each one choice written in two settings (Clean.lua): a profile holds
-- a way's look whatever pair shows it (Wanderer's style chosen again in the settings writes the pair otherwise
-- than the ways do, and changes nothing).
local LOOK_PAIRS = { ["world.cleanMinimap"] = "minimap", ["world.styledMinimap"] = "minimap",
	["world.cleanTracker"] = "tracker", ["world.styledTracker"] = "tracker" }
local function LookBy(which, get)
	local world = {}
	for path in pairs(LOOK_PAIRS) do world[path:match("%.(.+)$")] = get(path) end
	return which == "minimap" and ns.MinimapLook({ world = world }) or ns.TrackerLook({ world = world })
end

-- Whether a profile holds a way's value of a managed setting.
local function Holds(profile, values, path)
	local which = LOOK_PAIRS[path]
	if which then
		return LookBy(which, function(each) return ValueOf(profile, each) end) == LookBy(which, function(each) return values[each] end)
	end
	return ValueOf(profile, path) == values[path]
end

-- Whether a profile holds every value of a way.
local function Matches(profile, way)
	if profile.preset ~= way.names then return false end
	for path in pairs(way.values) do
		if not Holds(profile, way.values, path) then return false end
	end
	return true
end

-- The way of this character: its key while every managed setting still holds it, "custom" once one changed,
-- "" when none was chosen (an older profile matching one exactly reads as it, never written).
function ns.CurrentPlaystyle(profile)
	profile = profile or ChosenTable()
	if type(profile) ~= "table" then return "" end
	local way = ns.PLAYSTYLES[profile.playstyle or ""]
	if way then return Matches(profile, way) and way.key or "custom" end
	for _, key in ipairs(ns.PLAYSTYLE_ORDER) do
		if Matches(profile, ns.PLAYSTYLES[key]) then return key end
	end
	return ""
end

-- The way's words for the character's state: its name, "Customised" or "None yet".
function ns.PlaystyleWords(current)
	current = current or ns.CurrentPlaystyle()
	if current == "custom" then return L.PLAY_CUSTOMISED end
	if ns.PLAYSTYLES[current] then return L["PLAYSTYLE_" .. current:upper()] end
	return L.PLAY_NONE
end

-- The profile this character chose is not its own: other characters may use it.
function ns.PlaystyleShared()
	local root = ns.root
	if not root then return false end
	local own = type(root.ownProfile) == "table" and root.ownProfile[ns.CharacterKey()]
	return ns.ChosenProfile() ~= own
end

-- Whether this character's places would change (a way that makes them, or lets them go).
local function PlacesChange(way)
	local map = ns.PlaceProfiles()
	if way.places == "clear" then return next(map) ~= nil end
	if way.places == "make" then
		for _, zone in ipairs({ "world", "city", "dungeon" }) do
			if not (map[zone] and ns.root.profiles[map[zone]]) then return true end
		end
	end
	return false
end

-- A managed setting's words: its line for that value, its option's name, the words a card tells it by, any of its
-- lines; nil when none (never a setting's path shown to a player).
local function ChangeWords(path, value)
	local any
	for _, line in ipairs(LINES) do
		if line[1] == path then
			if line[2] == value then return L[line[3]] end
			any = any or L[line[3]]
		end
	end
	local option = ns.OPTION_WORDS and ns.OPTION_WORDS.paths[path]
	if option and option.label then return option.label end
	if TOLD_WORDS[path] then return L[TOLD_WORDS[path]] end
	return any
end

-- An extension's setting while it is not installed: written silently (it starts as the way wanted), never
-- counted nor named.
local function Silent(path)
	local addon = EXTENSION_ADDON[U.SplitPath(path) or ""]
	return addon ~= nil and ns.ExtensionInstalled ~= nil and not ns.ExtensionInstalled(addon)
end

-- What a way would change for this character: { { path, words } } (names and places included; words nil for a
-- setting without words: counted, never named), and how many of them are done for you.
function ns.PlaystyleChanges(key)
	local way = ns.PLAYSTYLES[key]
	if not (way and ns.root) then return {}, 0 end
	local profile = ChosenTable()
	local list, done = {}, 0
	if profile.preset ~= way.names then
		list[#list + 1] = { path = "names", words = L.MINIMAP_PRESET:format(L["PRESET_" .. way.names:upper()]) }
	end
	for _, path in ipairs(ns.PLAYSTYLE_KEYS) do
		local value = way.values[path]
		if not Holds(profile, way.values, path) and not Silent(path) then
			list[#list + 1] = { path = path, words = ChangeWords(path, value) }
			if ns.PLAYSTYLE_AUTOMATIONS[path] and value == true then done = done + 1 end
		end
	end
	if PlacesChange(way) then
		list[#list + 1] = { path = "places", words = way.places == "make" and L.PLAY_LINE_PLACES_MAKE or L.PLAY_LINE_PLACES_CLEAR }
	end
	return list, done
end

-- Applying -------------------------------------------------------------------------------------------------

local undo -- what this character had before the last way chosen in the options (for the session)

-- Every profile and this character's place map, kept to be put back (a way may write a shared profile, and
-- the places' own).
local function Snapshot()
	local root = ns.root
	return { profiles = U.Copy(root.profiles), places = U.Copy(ns.PlaceProfiles()), chosen = root.profileKeys[ns.CharacterKey()],
		active = ns.profileName }
end

-- A way chosen: written into this character's profiles (the active one, its own or chosen one, its places'),
-- names set, the places made, let go or kept as the way says. Never in a fight. remember: the options' Undo.
function ns.ApplyPlaystyle(key, remember)
	local way = ns.PLAYSTYLES[key]
	if not (way and ns.root and ns.db) or InCombatLockdown() then return false end
	if remember then undo = Snapshot() end
	if way.places == "make" then ns.MakePlaceProfiles(true) end
	local done = {}
	local function To(profile)
		if type(profile) ~= "table" or done[profile] then return end
		done[profile] = true
		ApplyTo(profile, way)
	end
	To(ns.db)
	To(ns.root.profiles[ns.ChosenProfile()])
	-- (the places' profiles too, also when let go: the same way if they are taken again)
	for _, name in pairs(ns.PlaceProfiles()) do To(ns.root.profiles[name]) end
	if way.places == "make" then
		ns.MakePlaceProfiles()
	elseif way.places == "clear" then
		ns.ClearPlaceProfiles()
	else
		-- (each place keeps its damage meter)
		for zone, name in pairs(ns.PlaceProfiles()) do
			local profile, meter = ns.root.profiles[name], ns.PLACE_METER[zone]
			if type(profile) == "table" and meter and type(profile.meter) == "table" then profile.meter.show = meter end
		end
	end
	ns.SetPreset(way.names) -- refreshes every module
	ns.RefreshOptions()
	ns.RefreshPlaystyleGrids()
	return true
end

function ns.CanUndoPlaystyle() return undo ~= nil end

-- The options' last way taken back: this character's profiles and places as they were before it.
function ns.UndoPlaystyle()
	if not undo or InCombatLockdown() then return false end
	local root = ns.root
	-- (the places' profiles the way made: gone again; every other one as it was)
	for _, name in pairs(ns.PlaceProfiles()) do
		if undo.profiles[name] == nil then root.profiles[name] = nil end
	end
	for name, profile in pairs(undo.profiles) do root.profiles[name] = profile end
	local map = ns.PlaceProfiles()
	for zone in pairs(map) do map[zone] = nil end
	for zone, name in pairs(undo.places) do map[zone] = name end
	local me = ns.CharacterKey()
	local active = root.profiles[undo.active] and undo.active or ns.ChosenProfile()
	root.profileKeys[me] = undo.chosen
	undo = nil
	ns.SetProfile(active, true)
	ns.UpdatePlaceProfile()
	ns.RefreshAll()
	ns.RefreshPlaystyleGrids()
	return true
end

-- The first character Wanderer meets on this account, still at the start of the road: the newcomer advised.
function ns.PlaystyleRecommended()
	if ns.Characters(true)[1] then return false end
	local level = U.Clean(U.Safe(UnitLevel, "player"))
	return type(level) == "number" and level <= 5
end

-- The panel's words -----------------------------------------------------------------------------------------

-- An extension's state for a section: "ok" (core, or installed and on), "off" (switched off), "missing".
local function ExtState(section)
	if not (section and EXTENSION_ADDON[section]) then return "ok" end
	for _, extension in ipairs(ns.EXTENSIONS) do
		if extension.key == section then
			local settings = ns.db and ns.db[section]
			return type(settings) == "table" and settings.enabled == false and "off" or "ok"
		end
	end
	for _, offer in ipairs(ns.MissingExtensions()) do
		if offer.addon == EXTENSION_ADDON[section] then return "missing" end
	end
	-- (there, but not loaded: switched off in the game's list)
	return "off"
end

local function ExtName(section)
	for _, offer in ipairs(ns.EXTENSION_OFFERS or {}) do
		if offer.addon == EXTENSION_ADDON[section] then return offer.name, offer end
	end
	return EXTENSION_ADDON[section] or section
end

-- A way's lines: { text, column, state, section }, the installed ones first in each column; and how many it
-- turns on (shows and done), apart those waiting for an extension.
function ns.PlaystyleLines(key)
	local way = ns.PLAYSTYLES[key]
	local lines, on, waiting = { shows = {}, done = {}, left = {} }, 0, 0
	if not way then return lines, 0, 0 end
	local later = { shows = {}, done = {}, left = {} }
	for _, line in ipairs(LINES) do
		local path, value = line[1], line[2]
		local wayValue = path == "places" and way.places or path == "names" and way.names or way.values[path]
		if wayValue == value and (not line[5] or line[5](way.values)) then
			local section = U.SplitPath(path)
			local state = ExtState(section)
			local entry = { text = L[line[3]], column = line[4], state = state, section = state ~= "ok" and section or nil }
			table.insert(state == "missing" and later[line[4]] or lines[line[4]], entry)
			if line[4] ~= "left" then
				if state == "missing" then waiting = waiting + 1 else on = on + 1 end
			end
		end
	end
	for column, list in pairs(later) do
		for _, entry in ipairs(list) do table.insert(lines[column], entry) end
	end
	return lines, on, waiting
end

-- The defaults a way tells that are really on now (an extension's only while it is there and on).
function ns.PlaystyleTold(key)
	local way = ns.PLAYSTYLES[key]
	local words = {}
	if not (way and ns.db) then return words end
	-- (the newcomer's one hint: the unit frames' look, when the module is on)
	if key == "newcomer" and type(ns.db.unitFrames) == "table" and ns.db.unitFrames.enabled and ns.UnitFramesPreset then
		local preset = ns.UnitFramesPreset()
		words[#words + 1] = L.PAGE_UNIT_FRAMES .. (preset and (" : " .. L["UF_PRESET_" .. preset:upper()]) or "")
	end
	for _, path in ipairs(way.told) do
		local section = U.SplitPath(path)
		if ExtState(section) == "ok" and (not EXTENSION_ADDON[section] or type(ns.db[section]) == "table") and ValueOf(ns.db, path) == true then
			words[#words + 1] = L[TOLD_WORDS[path]]
		end
	end
	return words
end

-- The extensions a way's lines wait for: the missing ones, the switched off ones (names).
local function Waiting(lines)
	local missing, off, seen = {}, {}, {}
	for _, column in ipairs({ "shows", "done", "left" }) do
		for _, entry in ipairs(lines[column]) do
			if entry.section and not seen[entry.section] then
				seen[entry.section] = true
				local name, offer = ExtName(entry.section)
				if entry.state == "missing" then missing[#missing + 1] = { name = name, offer = offer } else off[#off + 1] = name end
			end
		end
	end
	return missing, off
end

-- The grid of cards and its panel -------------------------------------------------------------------------
-- Six big cards (an icon, the way's name, its promise; the chosen one in gold), and under them a panel always
-- showing the card under the mouse, else the chosen one: what it shows, what it does for you (Shift skips),
-- what it leaves to you, the extensions it waits for, the defaults already on. A line under it says the way
-- belongs to this character (or that its profile is shared).

-- (the heights at the usual size of words; larger words for Wanderer's windows make them taller: Layout)
local CARD_MIN, CARD_GAP = 68, 8
local ICON_SIZE = 36
local PAD = 10
local LINE_MIN = 14
local ROWS = 6 -- lines under each caption
local COLUMN_GAP = 12
local TITLE_MIN, EXT_ROW = 16, 20
local BULLET = "·  "

local grids = {}
ns.PLAYSTYLE_GRIDS = grids -- (every grid made: the tests read them)
local GridMixin = {}

function ns.RefreshPlaystyleGrids()
	for _, grid in ipairs(grids) do
		if grid.parent:IsShown() then grid:Refresh() end
	end
end

local function NoWrap(text)
	if text.SetWordWrap then text:SetWordWrap(false) end
	text:SetJustifyH("LEFT")
	return text
end

local function CreateCard(grid, index, key)
	local way = ns.PLAYSTYLES[key]
	local Skin = ns.Skin
	local card = CreateFrame("Button", nil, grid.parent)
	card.key, card.index = key, index
	card.background = card:CreateTexture(nil, "BACKGROUND")
	card.background:SetAllPoints()
	card.hover = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, ns.Skin.HOVER)
	card.hover:Hide()
	card.edges = Skin.Edges(card, 1, 1, 1, 0.07)
	card.icon = Skin.Icon(card, ICON_SIZE)
	card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
	card.icon:Set(way.icon)
	card.check = card:CreateTexture(nil, "OVERLAY")
	card.check:SetSize(16, 16)
	card.check:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
	Skin.GlyphOn(card.check, "check")
	-- (its key, at the welcome: 1 to 6)
	card.keyHint = Skin.Text(card, "GameTooltipTextSmall", "muted")
	card.keyHint:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -10)
	card.keyHint:SetText(tostring(index))
	card.keyHint:SetShown(grid.options.keys and not (U.UsingPad and U.UsingPad()) and true or false)
	card.chip = Skin.Chip(card)
	card.chip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -30, -9)
	card.chip:EnableMouse(true)
	card.chip.padTip = true -- (a controller stops on it for its tooltip)
	Skin.Tooltip(card.chip, function(self) return self.tip end)
	card.title = NoWrap(Skin.CreateText(card, "GameTooltipText"))
	card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 1)
	card.title:SetText(L["PLAYSTYLE_" .. key:upper()])
	card.text = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.text:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 6)
	card.text:SetJustifyH("LEFT")
	card.text:SetJustifyV("TOP")
	if card.text.SetMaxLines then card.text:SetMaxLines(3) end
	card.text:SetText(L["PLAYSTYLE_" .. key:upper() .. "_DESC"])
	card:SetScript("OnEnter", function(self)
		self.hover:Show()
		grid.hovered = key
		grid:Tell()
	end)
	card:SetScript("OnLeave", function(self)
		self.hover:Hide()
		if grid.hovered == key then grid.hovered = nil end
		grid:Tell()
	end)
	card:SetScript("OnClick", function() grid:Pick(key) end)
	grid.cards[index] = card
	return card
end

local function CreatePanel(grid)
	local Skin = ns.Skin
	local panel = Skin.Panel(grid.parent)
	panel:EnableMouse(true)
	panel.title = NoWrap(Skin.Text(panel, "GameTooltipText", "gold"))
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
	panel.count = NoWrap(Skin.Text(panel, "GameTooltipTextSmall", "muted"))
	panel.count:SetPoint("BOTTOMLEFT", panel.title, "BOTTOMRIGHT", 10, 1)
	panel.count:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
	-- The slots: the left area (its caption, then two columns of lines), the right one (captions and lines).
	panel.left, panel.right = {}, {}
	for index = 1, 1 + 2 * ROWS do panel.left[index] = NoWrap(Skin.Text(panel, "GameTooltipTextSmall", "text")) end
	for index = 1, 1 + ROWS do panel.right[index] = NoWrap(Skin.Text(panel, "GameTooltipTextSmall", "text")) end
	panel.told = NoWrap(Skin.Text(panel, "GameTooltipTextSmall", "muted"))
	panel.ext = NoWrap(Skin.Text(panel, "GameTooltipTextSmall", "muted"))
	panel.get = Skin.SmallButton(panel, L.PLAY_GET, function()
		if grid.options.onGet then grid.options.onGet(grid.missing and grid.missing[1] and grid.missing[1].offer) end
	end, nil, EXT_ROW)
	panel.get:Fit()
	-- (everything, whole, under the mouse)
	Skin.Tooltip(panel, function() return grid.tooltip end)
	panel.padTip = true -- (a controller stops on it to read it whole)
	grid.panel = panel
	grid.footer = NoWrap(Skin.Text(grid.parent, "GameTooltipTextSmall", "muted"))
end

-- options: onPick(key), onGet(offer) (the extensions' place; none: no button), keys (1 to 6 shown),
-- recommend (the newcomer advised for a first character).
function ns.CreatePlaystyleGrid(parent, options)
	local grid = setmetatable({ parent = parent, cards = {}, options = options or {} }, { __index = GridMixin })
	for index, key in ipairs(ns.PLAYSTYLE_ORDER) do CreateCard(grid, index, key) end
	CreatePanel(grid)
	grids[#grids + 1] = grid
	return grid
end

function GridMixin:Pick(key)
	if self.options.onPick then self.options.onPick(key) end
end

-- The cards, then the panel and the footer under the anchor; the height they take.
function GridMixin:Layout(anchor, width, offsetY)
	if not width or width <= 0 then return 0 end
	self.width = width
	-- (the heights from the size of the words: a card holds its name and two lines, the panel its lines)
	local Skin = ns.Skin
	local LINE = math.max(LINE_MIN, Skin.LineHeight(self.panel.right[1]))
	local TITLE_ROW = math.max(TITLE_MIN, Skin.LineHeight(self.panel.title))
	local first = self.cards[1]
	local CARD_HEIGHT = math.max(CARD_MIN, 10 + Skin.LineHeight(first.title) + 3 + 2 * Skin.LineHeight(first.text) + 8)
	local PANEL_HEIGHT = PAD + TITLE_ROW + 8 + (ROWS + 1) * LINE + 6 + LINE + 4 + EXT_ROW + PAD
	self.panel:SetHeight(PANEL_HEIGHT)
	local cardWidth = math.floor((width - CARD_GAP) / 2)
	for _, card in ipairs(self.cards) do
		local column, row = (card.index - 1) % 2, math.floor((card.index - 1) / 2)
		card:SetSize(cardWidth, CARD_HEIGHT)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", column * (cardWidth + CARD_GAP), -offsetY - row * (CARD_HEIGHT + CARD_GAP))
	end
	local gridHeight = 3 * CARD_HEIGHT + 2 * CARD_GAP
	local panel = self.panel
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(offsetY + gridHeight + 10))
	panel:SetWidth(width)
	local inner = width - 2 * PAD
	local leftWidth = math.floor(inner * 2 / 3)
	local columnWidth = math.floor((leftWidth - COLUMN_GAP) / 2)
	local rightWidth = inner - leftWidth - COLUMN_GAP
	local top = PAD + TITLE_ROW + 8
	for index, slot in ipairs(panel.left) do
		slot:ClearAllPoints()
		if index == 1 then
			slot:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
			slot:SetWidth(leftWidth)
		else
			local column, row = math.floor((index - 2) / ROWS), (index - 2) % ROWS
			slot:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + column * (columnWidth + COLUMN_GAP), -(top + (row + 1) * LINE))
			slot:SetWidth(columnWidth)
		end
	end
	for index, slot in ipairs(panel.right) do
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + leftWidth + COLUMN_GAP, -(top + (index - 1) * LINE))
		slot:SetWidth(rightWidth)
	end
	panel.told:ClearAllPoints()
	panel.told:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(top + (ROWS + 1) * LINE + 6))
	panel.told:SetWidth(inner)
	panel.get:ClearAllPoints()
	panel.get:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)
	panel.ext:ClearAllPoints()
	panel.ext:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + EXT_ROW / 2)
	panel.ext:SetPoint("RIGHT", panel.get, "LEFT", -10, 0)
	self.footer:ClearAllPoints()
	self.footer:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 2, -8)
	self.footer:SetWidth(width - 4)
	self:Refresh()
	return gridHeight + 10 + PANEL_HEIGHT + 8 + LINE
end

-- The cards' state: the way chosen in gold, "Customised" on it once changed, the newcomer advised.
function GridMixin:Refresh()
	local current = ns.CurrentPlaystyle()
	local profile = ChosenTable()
	local base = type(profile) == "table" and profile.playstyle or ""
	self.current = ns.PLAYSTYLES[current] and current or (ns.PLAYSTYLES[base] and base) or nil
	local recommend = self.options.recommend and ns.PlaystyleRecommended()
	for _, card in ipairs(self.cards) do
		local chosen = card.key == current
		if chosen then
			card.background:SetColorTexture(ns.Skin.RGB("gold", ns.Skin.CHOSEN))
			card.title:SetTextColor(ns.Skin.COLORS.gold[1], ns.Skin.COLORS.gold[2], ns.Skin.COLORS.gold[3])
		else
			card.background:SetColorTexture(1, 1, 1, 0.04)
			card.title:SetTextColor(unpack(ns.Skin.COLORS.text))
		end
		card.check:SetShown(chosen)
		card.keyHint:SetShown(self.options.keys and not chosen and not (U.UsingPad and U.UsingPad()) and true or false)
		if current == "custom" and card.key == base then
			card.chip:Set(L.PLAY_CUSTOMISED, "grey")
			card.chip.tip = nil
		elseif recommend and card.key == "newcomer" then
			card.chip:Set(L.PLAY_RECOMMENDED, "gold")
			card.chip.tip = { L.PLAY_RECOMMENDED, L.PLAY_RECOMMENDED_DESC }
		else
			card.chip:Set(nil)
		end
		card.title:ClearAllPoints()
		card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 1)
		card.title:SetPoint("RIGHT", card.chip:IsShown() and card.chip or card.check, "LEFT", -6, 0)
	end
	self:Tell()
end

-- Lines in slots, the last one saying how many more when they do not fit.
local function Fill(slots, from, entries, room)
	local index = from
	for count, entry in ipairs(entries) do
		if index > #slots or count > room then break end
		local slot = slots[index]
		if count == room and #entries > room then
			slot:SetText(L.PLAY_MORE:format(#entries - room + 1))
			slot:SetTextColor(unpack(ns.Skin.COLORS.muted))
		else
			local words = BULLET .. entry.text
			slot:SetText(words)
			local role = entry.state == "missing" and "muted" or "text"
			slot:SetTextColor(unpack(ns.Skin.COLORS[role]))
		end
		index = index + 1
	end
	return index
end

local function Caption(slot, text)
	slot:SetText(U.Upper(text))
	slot:SetTextColor(unpack(ns.Skin.COLORS.kicker))
end

-- The defaults told on one line, as many as fit, "+N more" after (the whole list under the mouse).
local function TellDefaults(text, words, width)
	if not words[1] then
		text:SetText("")
		return
	end
	local shown = {}
	for index, word in ipairs(words) do
		local rest = #words - index
		local try = L.PLAY_ALREADY_ON:format(table.concat(shown, ", ") .. (shown[1] and ", " or "") .. word)
			.. (rest > 0 and ("  " .. L.PLAY_MORE:format(rest)) or "")
		text:SetText(try)
		if shown[1] and width and U.Measure(text, "GetStringWidth", 0) > width then break end
		shown[#shown + 1] = word
	end
	local rest = #words - #shown
	text:SetText(L.PLAY_ALREADY_ON:format(table.concat(shown, ", ")) .. (rest > 0 and ("  " .. L.PLAY_MORE:format(rest)) or ""))
end

-- The panel: the card under the mouse, else the chosen one (the newcomer while none is).
function GridMixin:Tell()
	local key = self.hovered or self.current or "newcomer"
	self.shown = key
	local panel = self.panel
	local lines, on, waiting = ns.PlaystyleLines(key)
	panel.title:SetText(L["PLAYSTYLE_" .. key:upper()])
	local count = L.PLAY_TURNS_ON:format(on) .. (waiting > 0 and (" " .. L.PLAY_WITH_EXT_COUNT:format(waiting)) or "")
	if ns.PLAYSTYLES[key].places == "clear" then count = count .. "  ·  " .. L.PLAY_LINE_PLACES_CLEAR end
	panel.count:SetText(count)
	for _, slot in ipairs(panel.left) do slot:SetText("") end
	for _, slot in ipairs(panel.right) do slot:SetText("") end
	Caption(panel.left[1], L.PLAY_SHOWS)
	Fill(panel.left, 2, lines.shows, 2 * ROWS)
	local index = 1
	if lines.done[1] then
		Caption(panel.right[index], L.PLAY_DONE_FOR_YOU)
		local room = #panel.right - index - (lines.left[1] and 2 or 0)
		index = Fill(panel.right, index + 1, lines.done, room)
	end
	if lines.left[1] then
		Caption(panel.right[index], L.PLAY_LEFT_TO_YOU)
		Fill(panel.right, index + 1, lines.left, #panel.right - index)
	end
	local told = ns.PlaystyleTold(key)
	TellDefaults(panel.told, told, self.width and (self.width - 2 * PAD) or nil)
	-- The extensions its lines wait for.
	local missing, off = Waiting(lines)
	self.missing = missing
	local parts = {}
	if missing[1] then
		local names = {}
		for _, entry in ipairs(missing) do names[#names + 1] = entry.name end
		parts[#parts + 1] = L.PLAY_EXT_MISSING:format(table.concat(names, ", "))
	end
	for _, name in ipairs(off) do parts[#parts + 1] = name .. " " .. L.PLAY_SWITCHED_OFF end
	panel.ext:SetText(table.concat(parts, "  ·  "))
	panel.get:SetShown(missing[1] ~= nil and self.options.onGet ~= nil)
	-- This character only, or a profile others share.
	local shared = ns.PlaystyleShared()
	self.footer:SetText(shared and L.PLAY_SHARED_WARN or L.PLAY_FOOTER)
	self.footer:SetTextColor(unpack(ns.Skin.COLORS[shared and "warn" or "muted"]))
	-- The whole of it, under the mouse.
	local C = ns.Skin.COLORS
	local tip = { L["PLAYSTYLE_" .. key:upper()], { L["PLAYSTYLE_" .. key:upper() .. "_DESC"], unpack(C.soft) } }
	for _, column in ipairs({ { "shows", "PLAY_SHOWS" }, { "done", "PLAY_DONE_FOR_YOU" }, { "left", "PLAY_LEFT_TO_YOU" } }) do
		if lines[column[1]][1] then
			tip[#tip + 1] = { " " }
			tip[#tip + 1] = { L[column[2]], unpack(C.kicker) }
			for _, entry in ipairs(lines[column[1]]) do
				local suffix = entry.section and (" (" .. ExtName(entry.section) .. ")") or ""
				local c = C[entry.state == "missing" and "muted" or "text"]
				tip[#tip + 1] = { BULLET .. entry.text .. suffix, c[1], c[2], c[3] }
			end
		end
	end
	if told[1] then
		tip[#tip + 1] = { " " }
		tip[#tip + 1] = { L.PLAY_ALREADY_ON:format(table.concat(told, ", ")), unpack(C.muted) }
	end
	self.tooltip = tip
end
