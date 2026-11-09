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
-- The enemies' names: as the names settings say, always, never, or as you come near.
ns.ENEMY_NAMES = { "names", "always", "never", "near" }

-- What the label says, in three levels: the essential (who, what to do
-- with them), complete (the defaults) or all of it. Each line can still be
-- set alone below ("custom").
ns.LABEL_CONTENT_KEYS = { "showRace", "showClass", "showSpec", "shiftDetails", "showGuild", "showFaction", "showNPCFaction",
	"showStatus", "showCreatureType", "showClassification", "showNPCRole", "showReputation", "showTameable",
	"untagged", "showLevel", "showDifficulty", "showXP", "showPortrait", "showHealth", "showPower", "showTarget", "showCasts",
	"showProfessions", "showLoot", "showObjects", "showQuests" }
ns.LABEL_CONTENT_ORDER = { "essential", "complete", "all", "custom" }
local ESSENTIAL = { showClass = true, shiftDetails = true, showStatus = true, showClassification = true, showNPCRole = true,
	untagged = true, showLevel = true, showDifficulty = true, showPortrait = true, showHealth = true, showCasts = true,
	showProfessions = true, showLoot = true, showObjects = true, showQuests = true }

-- Settings stored in each profile.
local DEFAULTS = {
	styleVersion = 11,
	enabled = true,
	preset = "immersion",
	playstyle = "", -- the way to play chosen (Playstyles.lua), "" before any
	show = {},
	combatEnemies = false, -- enemy names in a fight: asked for (their health bars show anyway)
	groupMarks = true, -- in the world, the name of each member of your group, small, over their head
	guildMarks = true, -- and of each member of your guild, in the guild's color
	knownMarks = false, -- and of the players this character has met (Acquaintances.lua)
	enemyNames = "near", -- "names" (as the names settings say), "always", "never", "near" (as you come near)
	nearNames = {
		distance = 45, -- yards from the camera beyond which the enemies' names are gone
		show = "bar", -- what comes as you come near: "bar" (their health bar, as the game) or "name"
	},
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
		content = "complete", -- what the label says: "essential", "complete", "all" or "custom"
		style = "blizzard",
		anchor = "head",
		allHeads = true, -- nameplates turned on unseen, so the label finds every head
		worldOnly = true,
		showRace = true,
		showClass = true,
		showSpec = true,
		ownPortrait = true, -- over your portrait, the label shows you (the closer look included)
		stickyTarget = true, -- your target stays described while nothing else is hovered (off: as before)
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
		showPower = false, -- mana, rage, energy... under the health bar (label and game tooltip)
		showDifficulty = true,
		showReputation = true,
		showTameable = true,
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
		hideInCombat = false,
		combatLight = false, -- in a fight, only what matters for it (asked for: the label stays whole by default)
		scale = 1,
		textScale = 1,
		offset = 22,
		bgOpacity = 55,
		padding = 8,
		font = "default",
	},
	rp = {
		leaveCard = true, -- a player with a Total RP 3 profile: TRP3's own card, not the label
		useName = true,
		showTitle = true,
		showStatus = true,
	},
	tooltips = {
		upgrade = true, -- over an item: better or worse for the branch you play
		calculatedWeights = true, -- those weights calculated from your own figures (StatModel.lua), when they can be
		reagents = true, -- over a crafting reagent: the professions that use it
		sellPrice = true, -- over an item: what a merchant would give for it, wherever you are
		enabled = true,
		cursor = true,
		icon = true,
		quality = true,
	},
	cinema = {
		enabled = true,
		alpha = 20,
		delay = 4,
		-- faded out of a fight even with a target: asked for (on by default before the ways to play; a saved profile keeps its own)
		combatOnly = true,
	},
	merchant = {
		sellJunk = true,
		repair = true,
		guildRepair = false,
		repairReminder = true, -- back in town with worn equipment: a smith would be welcome
		provisions = true, -- what you buy again and again, offered at merchants when low (bought on a click only)
	},
	loot = {
		fast = true,
		feed = true, -- what you pick up, one line each at the side of the screen (LootFeed.lua)
		feedQuality = 1, -- the least quality shown (quest items always)
		feedMoney = true,
		feedReceived = true, -- quest rewards and purchases too
		feedTime = 4, -- seconds each line stays (an epic thing longer)
	},
	trainer = {
		learnAll = true,
	},
	sounds = {
		enabled = true,
		list = "",
	},
	fishing = {
		doubleClick = true,
		tell = true, -- the label tells the fishing over the bobber, a notice each catch
		splash = true, -- the music and the ambience lowered while the line is in the water
	},
	crafts = {
		skillUps = false, -- a short notice for the points gained in a profession (the game says it in the chat)
		gatherReach = true, -- a notice when a new gathering rank lets you gather something new
		ceiling = true, -- a profession at its ceiling: a trainer teaches the next rank (information)
	},
	gestures = {
		read = true, -- automations: off until the player asks
		levelUp = true,
		greet = true,
		sitAtFire = true, -- a click on a campfire seats you by it
	},
	hands = { -- what the game makes you do by hand, done for you: off until asked
		easyDestroy = false, -- destroying an item without typing the word
		bagsClosed = false, -- the bags no longer open by themselves for the game's windows
		standUp = true, -- stand up or dismount when an action is refused for it
	},
	travel = {
		enabled = true,
		camera = true,
	},
	away = {
		enabled = true, -- an ambiance while away: asked for
		style = "contemplation",
	},
	buffs = {
		remind = true, -- your long blessings that fade, to cast again (a notice, out of a fight)
	},
	meter = {
		show = "own", -- the game's damage meter: "own" (the game's own setting), "on" or "off" (the dungeons' profile: on)
		look = "game", -- "game" (as it is) or "text" (text only)
	},
	dots = {
		enabled = true, -- what your damage over time will still deal: asked for
		mark = true, -- and the skull on the portrait, whole when they will finish it
		target = true, -- on your target's frame
		focus = true, -- on your focus's frame
		tot = true, -- on your target's target
		plates = true, -- on the nameplates
	},
	hots = {
		enabled = true, -- what your heals over time will still heal: asked for
		mark = true, -- and the plus that fills up, whole when they will be topped
		player = true, -- on your own frame
		group = true, -- on the party frames and the game's group and raid frames
		target = true, -- on your target and focus, when friendly
		plates = true, -- on friendly nameplates
	},
	-- The unit frames in Wanderer's look (UnitFrames.lua, Portraits.lua): on, as the user's own main plays them
	-- (validated in game 2026-11-07; off in a click, offered again at the welcome); the values below are the look "Ink lines".
	unitFrames = {
		enabled = true,
		health = "class", -- "class" (players) and attitude (creatures), "gradient", "one", "classic"
		texture = "flat", -- "smooth", "clean" (flat, a hint of light on top), "flat", "classic"
		ground = "dark", -- behind the missing part: "dark", "faded" (the bar's colour, dimmed), "classic"
		power = "wanderer", -- "wanderer" (softer hues) or "game"
		art = "lines", -- the frames' metal: "game" or "lines" (gone, a fine ink line instead)
		texts = "wanderer", -- the values and names: "wanderer" (narrow numbers, Wanderer's font) or "game"
		ring = "gold", -- around the portraits: "off", "class" (and attitude), "gold" (yours gold, the others by class)
		badge = "others", -- a class badge on players' faces: "off", "others", "all"
		iconStyle = "ink", -- the class icons: "game", "classic", "ink"
		greyDead = true, -- dead, ghost or offline: the portrait greyed
		thickness = "medium", -- the Ink lines block: "fine" (the game's), "medium", "thick" (ElvUI-like)
		lowHealth = true, -- your health and your party's turn to a deep red below 35 % (full at 20 %)
		castInBlock = true, -- Ink lines: your cast bar (and your target's) under the block, the game's unseen meanwhile
		shortNumbers = false, -- large values as 12.3k (what is shown stays the game's choice)
		quarterMarks = false, -- fine marks at a quarter, half and three quarters of the health
		colourBlind = false, -- blue and orange instead of green and red
		wanderer = true, -- Wanderer's own bars and portraits (the label, its casts, the scenes) follow the look
		show = { player = "game", target = "game", party = "game", tot = "game" }, -- "game", "face" or "icon"
		frames = { player = true, target = true, focus = true, tot = true, pet = true, party = true, group = true, boss = true,
			castBars = true },
	},
	sparkles = {
		nodes = true, -- the game's gathering icon over the herb or vein you come near: asked for
		questObjects = true, -- and over quest objects: asked for
	},
	emotes = {
		enabled = true, -- the emote bar: asked for
	},
	threat = {
		show = true, -- in groups and dungeons only
		alert = true, -- in dungeons and raids, for the one holding the monsters
	},
	scene = {
		enabled = true,
		camera = true, -- closer to the character you talk to (conversations and quests)
		cameraShops = true, -- also at merchants, trainers, bankers, flight masters, auction houses: asked for
		cameraFrame = false, -- the character framed (a hidden setting of the game, which warns): asked for
		textSize = 16,
		hush = true, -- the music and the ambience lowered while a scene is shown
		parchment = false, -- the scene and the reading window on parchment
		reader = true, -- books, plaques and letters in Wanderer's reading window
		bgOpacity = 90, -- the panel's background, %
	},
	quest = {
		tags = true, -- elite and group quests said in their scene and in a character's list
		autoAccept = false,
		autoTurnIn = false,
		bestReward = true,
		skipGossip = true,
	},
	social = {
		declineDuels = false,
		acceptInvites = false,
		acceptResurrect = true,
		acceptSummon = true,
		inviteOnWord = false, -- a whisper made of one word brings its sender into your group
		inviteWord = "",
	},
	bars = {
		border = 15, -- the frame around each action button, % (100: as the game draws it, 0: gone)
		background = 45, -- the background of each slot, %
	},
	world = {
		threshold = true, -- at a dungeon's door: your quests there, your worn equipment
		townCard = true, -- arriving in a town or an inn: what waits there, in one notice (information)
		actionCam = true,
		calmMotion = true, -- no camera moved by Wanderer, its pieces fade without moving: asked for
		filterErrors = true, -- the red messages repeated in fights, filtered: asked for
		hideTalkingHead = false,
		cleanMinimap = true, -- the game's frames as they are, until asked
		-- Wanderer's looks: the quest tracker, the minimap, the bar (offered at the welcome; off until asked).
		styledTracker = true,
		styledMinimap = true,
		bar = true,
		cleanTracker = true,
		gatherIcons = true, -- other addons' buttons: left alone until asked
		layer = true, -- your layer: one line over the zone's name, never on the screen
		lootSparkle = true, -- the game's sparkle on quest items kept through the graphics presets: asked for
		editLayout = "", -- "": the game's Edit Mode layout is left alone
		moveFrames = true, -- the game's windows moved where you drop them (kept)
	},
}
ns.DEFAULTS = DEFAULTS

-- Extensions --------------------------------------------------------------------------------
-- Another addon of the family (Wanderer Bags...) joins Wanderer through the
-- global Wanderer: its settings live in Wanderer's profiles (spec.key), its
-- options page among Wanderer's, it is refreshed with the rest, and it draws
-- with the same engine (Skin) as every Wanderer window.
ns.EXTENSIONS = {}

-- An extension's launcher in the menu and the bar, while it is on: spec.launcher = { label (a text, or a
-- function giving it), open, shown() (false: not offered now), attention() (true: something waits there),
-- count() (a number shown beside it, 0: none), summary() (up to 3 lines { text, role } said on hover) }.
function ns.LauncherOf(extension)
	local launcher = extension.launcher
	if type(launcher) ~= "table" or not (launcher.label and launcher.open) then return nil end
	local settings = ns.db and ns.db[extension.key]
	if type(settings) == "table" and settings.enabled == false then return nil end
	if type(launcher.shown) == "function" and not launcher.shown() then return nil end
	local label = launcher.label
	if type(label) == "function" then label = label() end
	return { label = label, open = launcher.open, attention = type(launcher.attention) == "function" and launcher.attention or nil,
		count = type(launcher.count) == "function" and launcher.count or nil,
		summary = type(launcher.summary) == "function" and launcher.summary or nil, extension = extension }
end

-- What a launcher says on hover: up to 3 lines { text, role } (its summary failing or empty: none).
function ns.LauncherSummary(launcher)
	if not (launcher and launcher.summary) then return {} end
	local ok, lines = pcall(launcher.summary)
	local list = {}
	if not (ok and type(lines) == "table") then return list end
	for _, line in ipairs(lines) do
		if type(line) == "string" then line = { text = line } end
		if type(line) == "table" and type(line.text or line[1]) == "string" and #list < 3 then
			list[#list + 1] = { text = line.text or line[1], role = line.role or line[2] }
		end
	end
	return list
end

-- A launcher's count (0: none; failing: none).
function ns.LauncherCount(launcher)
	if not (launcher and launcher.count) then return 0 end
	local ok, count = pcall(launcher.count)
	return ok and tonumber(count) or 0
end

-- Something waits in an extension's window (the minimap button says it).
function ns.LaunchersWaiting()
	for _, extension in ipairs(ns.EXTENSIONS) do
		local launcher = ns.LauncherOf(extension)
		if launcher and launcher.attention and launcher.attention() then return true end
	end
	return false
end

-- A piece of Wanderer's saved data an extension keeps itself now, handed over once and gone from here
-- (byCharacter: this character's part of a table kept by character).
function ns.MoveOut(name, byCharacter)
	local root = ns.root
	if not root or root[name] == nil then return nil end
	if not byCharacter then
		local value = root[name]
		root[name] = nil
		return value
	end
	if type(root[name]) ~= "table" then return nil end
	local key = ns.CharacterKey()
	local value = root[name][key]
	root[name][key] = nil
	if next(root[name]) == nil then root[name] = nil end
	return value
end

-- spec: { key, addon, title, defaults, ranges, options, launcher, takes }. takes = { job = function() return on end }:
-- the jobs it does in Wanderer's place while on() says so (Compat.lua: Wanderer's option greyed, "Done by" it).
local function RegisterExtension(spec)
	if type(spec) ~= "table" or type(spec.key) ~= "string" or DEFAULTS[spec.key] then return false end
	ns.EXTENSIONS[#ns.EXTENSIONS + 1] = spec
	DEFAULTS[spec.key] = spec.defaults or {}
	for path, range in pairs(spec.ranges or {}) do ns.RANGES[path] = range end
	-- The active profile gets them now; the others when they are chosen.
	if ns.db then
		ns.db[spec.key] = type(ns.db[spec.key]) == "table" and ns.db[spec.key] or {}
		ns.Sanitize(DEFAULTS[spec.key], ns.db[spec.key], spec.key)
	end
	return true
end

_G.Wanderer = setmetatable({
	-- What the extensions may count on: 2 = the reagents, the junk rules and sales, the links, the bags' ids;
	-- 3 = the reminders (a line added, known); 4 = the shared pieces (Skin: Kit.lua;
	-- Util: items, the map, time) and the extensions' own setup (Locale, WhenLoaded); 5 = the reagents' table,
	-- an area's name, an item's levels and its count with the bank, the check box; 6 = what you play (chosen,
	-- kept per character), the dropdown, a comparison changed; 7 = the account's characters; 8 = the class color,
	-- money in letters, a signal, a tooltip of lines, a game window set aside, the comparison's switch; 9 = a button
	-- in the game's own look, your talent tree, the merchants' purchases (Util), the items an extension buys itself;
	-- 10 = the chat's moving out (saved data handed over, the copy window, the scenes, the launchers' counts);
	-- 11 = what the NPCs offered and asked for (QuestOffers); 12 = the creatures dropping quest items (QuestUnitDrops);
	-- 13 = the world's levels (ZoneLevels); the town card's lines (TownLine), notices taking a click (Toast);
	-- 14 = the jobs an extension does in Wanderer's place (spec.takes), the characters' window lines (CharacterLine),
	-- the options' Needs, the launchers' summary and count, the settings cog of a window's heading (Skin.Header);
	-- 15 = Util.AfterFight, Util.Try, Util.ShownPlates, Util.LearnServices, Util.HasFishingPole, Skin.FitScale,
	-- Skin.GlyphText, Skin.ProgressLine, Skin.UnitBar, OpenOptions, RemoveTodo, HasFishingPole, SetPortrait, the shared word PIN_FAILED,
	-- Skin.ShowTip, Skin.KeyListener, Skin.LineHeight, the dropdown's tip, Skin.Ask's strata, Skin.Tabs SetList, OnCharacterForgotten;
	-- 16 = Util.ChatInsert, the job "trackerLook" an extension may take (spec.takes); 17 = ChangeEverywhere.
	API = 18,
	-- A place's levels and fishing (ZoneData.lua): by its area id, or by its map (onMap); no id: the whole list.
	ZoneLevels = function(id, onMap) return ns.ZoneLevels and ns.ZoneLevels(id, onMap) end,
	RegisterExtension = RegisterExtension,
	-- What each NPC talked to offered or asked for, as Wanderer remembers it: npc id -> { offers = { quest id = true },
	-- receives = { ... } } (read only).
	QuestOffers = function() return ns.root and ns.root.questBook or {} end,
	-- fn(npc id) -> the items that creature drops ({ item id, ... }) or nil: one your quests still ask you to carry
	-- marks it as a quest objective, its line in the label.
	QuestUnitDrops = function(fn) ns.QuestUnitDrops(fn) end,
	Settings = function(key) return ns.db and ns.db.enabled and ns.db[key] or nil end,
	-- change() writes in W.Settings(key): the same then in every profile of this character (its own and its
	-- places'), as the options pages do. A window's own button or menu writing a setting goes through it. (API 17.)
	ChangeEverywhere = function(change) if ns.db then ns.ChangeEverywhere(change) else change() end end,
	-- The characters of this account Wanderer has met ({ key, name, realm, class, faction, level, money, seen, me },
	-- the last seen first; others: without this one), this one's key, one let go.
	Characters = function(others) return ns.Characters(others) or {} end,
	CharacterKey = function() return ns.CharacterKey() end,
	ForgetCharacter = function(key) ns.ForgetCharacter(key) end,
	-- fn() called when a line is cast (the double click) without a fishing pole in hand, everything else
	-- allowing it: an extension may put one in hand.
	OnFishingNoPole = function(fn) ns.fishingNoPole = fn end,
	-- A fishing pole in your main hand. (API 15, as Util.HasFishingPole,
	-- Util.IsFishingSpell, Util.AfterFight, Util.Go's info and RemoveTodo.)
	HasFishingPole = function() return ns.Util.HasFishingPole() end,
	-- Your talent tree, read from the game: { nodes = { { id, branch, tier, column, spell, ranks, most, opens } },
	-- names (the three branches) }, nil when the game says nothing.
	TalentTree = function() return ns.TalentTree() end,
	-- The characters' window.
	ToggleCharacters = function() ns.ToggleCharacters() end,
	-- Wanderer's settings window, at a page ("ext:chat"; nil: where it was). (API 15.)
	OpenOptions = function(page) ns.OpenOptions(page) end,
	-- Saved data Wanderer kept before an extension took it over: given once (see ns.MoveOut).
	MoveOut = function(name, byCharacter) return ns.MoveOut(name, byCharacter) end,
	-- A chat window's lines as plain text, ready to copy (nil: the tab shown).
	CopyChat = function(frame) ns.CopyChat(frame) end,
	-- The Wanderer tab of the chat (diagnostic mode): its window's number.
	IsDebugTab = function(index) return ns.IsDebugTab(index) end,
	-- A conversation scene shown (the words of a character, face to face).
	InScene = function() return ns.sceneActive and true or false end,
	-- Another addon doing one of Wanderer's jobs now ("sellJunk", "fastLoot"... see Compat.lua): its name, else
	-- nil; and the muted line for an option left to it.
	-- A portrait of Wanderer's look (texture, unit, where): a face, or the class icon in the unit frames' style when
	-- the game (or the player's exception) shows one there; true when an icon. W.Skin.UnitBar(bar, look, r, g, b): a bar
	-- in the unit frames' look. (API 15.)
	SetPortrait = function(texture, unit, where) return ns.SetPortrait(texture, unit, where) end,
	Yields = function(feature) return ns.Yields(feature) end,
	YieldText = function(feature) return ns.YieldText(feature) end,
	-- fn(info) -> a line under the reading window's title, or nil (info: title, item, creator, object, zone...).
	ReaderNote = function(fn) ns.ReaderNote(fn) end,
	-- A change that only takes effect after a reload (reason: a few words): the menu's Reload says it.
	NeedReload = function(reason) ns.NeedReload(reason) end,
	-- The extensions' launchers drawn again (a count changed: the menu, the bar, the minimap button).
	RefreshLaunchers = function() ns.RefreshMinimapButton() end,
	-- Whether gear is judged for your branch at all (the tooltips' setting).
	ComparisonOn = function()
		return ns.db and ns.db.enabled and ns.db.tooltips.upgrade and not (ns.Yields and ns.Yields("upgradeArrows")) and true or false
	end,
	Util = ns.Util,
	Print = function(text) ns.Print(text) end,
	-- What an item is worth to you: { text, r, g, b } lines, the first one the best.
	UpgradeLines = function(link) return ns.UpgradeLines(link) or {} end,
	IsUpgrade = function(link) return ns.IsUpgrade(link) or false end,
	-- How much better for your branch (a percentage), nil when it is not.
	UpgradeGain = function(link) return ns.UpgradeGain(link) end,
	-- What you play (chosen by you, kept for each character): the choices of your class { id, label }, the one
	-- chosen (nil: none yet), or a new one chosen (id).
	PlayChoices = function() return ns.PlayChoices() or {} end,
	PlayChoice = function(id) return ns.PlayChoice(id) end,
	-- A quest level's color, as the quest log colors it: r, g, b.
	QuestLevelColor = function(level) return ns.World.LevelColor(level, true) end,
	-- fn() called when a comparison changed (a weight, a scale, what you play, your talents).
	OnComparisonChanged = function(fn) ns.OnComparisonChanged(fn) end,
	-- Gear your class can wear: true or false (nil: not gear).
	CanWear = function(link) return ns.CanWear(link) end,
	-- Who uses a crafting reagent: { { name, mine, alt, count } }, see Reagents.lua.
	ReagentUses = function(item) return ns.ReagentUses(item) or {} end,
	-- Every crafting reagent known (item id -> the professions using it, as bits) and those bits by name.
	Reagents = function() return ns.REAGENT_PROFESSIONS, ns.REAGENT_BITS end,
	-- At a merchant: what is junk (rule(item id, quality) -> true, false, "ask" (sold on a click only) or nil),
	-- selling a list of { bag, slot, id }.
	AddJunkRule = function(rule) ns.AddJunkRule(rule) end,
	-- (this Wanderer understands "ask": an item then waits for a click, never sold by itself)
	JUNK_ASK = true,
	-- rule(item id) -> true: an extension buys that item itself at merchants (the provisions leave it to it).
	AddBuyRule = function(rule) ns.AddBuyRule(rule) end,
	SellItems = function(items) return ns.SellItems(items) or false end,
	-- The junk of your bags as the rules say ({ bag, slot, id }).
	FindJunk = function() return ns.FindJunk() or {} end,
	IsMerchantOpen = function() return ns.IsMerchantOpen() or false end,
	IsSellingJunk = function() return ns.IsSellingJunk() or false end,
	-- An item one of your quests asks you to carry: { quest, have, need }, else nil (Quests.lua).
	QuestNeed = function(item) return ns.QuestNeed(item) end,
	-- The reminders: a line added (see Todo.lua), one known by its key.
	AddTodo = function(text, opts) return ns.AddTodo(text, opts) end,
	HasTodo = function(key) return ns.HasTodo(key) or false end,
	RemoveTodo = function(key) return ns.RemoveTodo(key) or false end,
	-- A short notice at the top of the screen (Toast.lua): a title, a few words.
	Toast = function(title, text, options) ns.Toast(title, text, options) end,
	-- fn() -> { text, onClick, hint } or nil: a line of the card shown on arriving in a town or an inn (Town.lua);
	-- key ("trainer", "shopping", "mail"...): one line of that kind, a new provider taking its place.
	TownLine = function(fn, key) ns.TownLine(fn, key) end,
	-- fn(character key) -> { text, r, g, b, chip } or nil: a line of that character in the characters' window (its
	-- hover; chip: a few words on its row when it is urgent); key ("mail"...): one line of that kind.
	CharacterLine = function(fn, key) ns.CharacterLine(fn, key) end,
	-- fn(character key) called when a character is forgotten (its window's Forget): let go of what you keep for it.
	OnCharacterForgotten = function(fn) ns.OnCharacterForgotten(fn) end,
	-- An extension's words: its languages' tables ({ enUS = {...}, frFR = {...} }, the client's added by its own
	-- file, loaded after); a word it lacks in English, then Wanderer's words shared by every addon (OPEN, SELL...),
	-- else the key itself. esMX reads esES when it has none.
	Locale = function(tables)
		local client = GetLocale and GetLocale() or "enUS"
		return setmetatable({}, { __index = function(_, key)
			local here = tables[client] or (client == "esMX" and tables.esES) or nil
			return here and here[key] or (tables.enUS or {})[key] or ns.L[key] or key
		end })
	end,
	-- An addon's start, once its own files are loaded (its saved variables with them).
	WhenLoaded = function(addon, fn)
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("ADDON_LOADED")
		frame:SetScript("OnEvent", function(self, _, name)
			if name ~= addon then return end
			self:UnregisterEvent("ADDON_LOADED")
			fn()
		end)
	end,
}, {
	-- The engine is made after this file: given when asked.
	__index = function(_, key) if key == "Skin" then return ns.Skin end end,
})
for _, cat in ipairs(ns.CATEGORIES) do DEFAULTS.show[cat.key] = false end

-- Allowed values, shared by the options panel and the checks of saved and
-- imported settings: numbers { min, max, step }, texts: a list of choices
-- (a function, as some lists are defined by modules loaded later).
ns.RANGES = {
	["label.scale"] = { 0.6, 2, 0.1 },
	["nearNames.distance"] = { 20, 60, 5 },
	["label.offset"] = { 0, 80, 2 },
	["label.padding"] = { 0, 20, 1 },
	["label.bgOpacity"] = { 0, 100, 5 },
	["label.textScale"] = { 0.9, 1.3, 0.05 },
	["cinema.alpha"] = { 0, 80, 5 },
	["cinema.delay"] = { 1, 15, 1 },
	["bars.border"] = { 0, 100, 5 },
	["bars.background"] = { 0, 100, 5 },
	["scene.textSize"] = { 12, 22, 1 },
	["scene.bgOpacity"] = { 30, 100, 5 },
}
local function Keys(list, field)
	local keys = {}
	for i, item in ipairs(list or {}) do keys[i] = field and item[field] or item end
	return keys
end
local CHOICES = {
	["preset"] = function() return ns.PRESET_ORDER end,
	["playstyle"] = function()
		local list = { "" }
		for _, key in ipairs(ns.PLAYSTYLE_ORDER or {}) do list[#list + 1] = key end
		return list
	end,
	["revealMode"] = function() return { "hold", "toggle" } end,
	["nearNames.show"] = function() return { "bar", "name" } end,
	["enemyNames"] = function() return ns.ENEMY_NAMES end,
	["label.style"] = function() return ns.STYLES end,
	["label.font"] = function() return Keys(ns.FONTS, "key") end,
	["label.anchor"] = function() return { "head", "cursor" } end,
	["label.content"] = function() return ns.LABEL_CONTENT_ORDER end,
	["away.style"] = function() return ns.AWAY_STYLES end,
	["meter.show"] = function() return { "own", "on", "off" } end,
	["meter.look"] = function() return { "game", "text" } end,
}
-- (the unit frames' choices: UnitFrames.lua)
for _, field in ipairs({ "health", "texture", "ground", "power", "art", "texts", "ring", "badge", "iconStyle", "thickness" }) do
	CHOICES["unitFrames." .. field] = function() return ns.UF_CHOICES and ns.UF_CHOICES[field] or {} end
end
for _, row in ipairs({ "player", "target", "party", "tot" }) do
	CHOICES["unitFrames.show." .. row] = function() return { "game", "face", "icon" } end
end
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

local DeepCopy = ns.Util.Copy

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

-- The music and the ambience lowered for a while (a line in the water, a scene), given back after. One
-- snapshot of your values and a share for each reason: the smallest share held applies, the values come back
-- once no reason is left. Kept in the saved variables, so they come back at the next login after a crash.
-- What Wanderer wrote is kept too: a volume found at another value was moved meanwhile (by you, or by another
-- addon lowering it for its own reason), so it is yours again and never written over. Each change fades in
-- half a second.
local VOLUME_CVARS = { "Sound_MusicVolume", "Sound_AmbienceVolume" }
local VOLUME_FADE = 0.5 -- seconds
local VOLUME_STEPS = 10
local SAME_VOLUME = 0.005
local fades = {} -- cvar -> its fade under way
local fadeTargets = {} -- cvar -> where that fade goes
local fadeWriters = {} -- cvar -> how that fade writes (its last word kept with the snapshot)

local function VolumeText(value)
	return tostring(math.floor(value * 1000 + 0.5) / 1000)
end

local function SameVolume(a, b)
	a, b = tonumber(a), tonumber(b)
	return a ~= nil and b ~= nil and math.abs(a - b) < SAME_VOLUME
end

local function StopFade(cvar)
	if fades[cvar] then fades[cvar]:Cancel() end
	fades[cvar], fadeTargets[cvar], fadeWriters[cvar] = nil, nil, nil
end

-- Leaving the game (logout, reload) in the middle of a fade: each volume written where it was going at once.
function ns.FinishVolumeFades()
	for cvar in pairs(fades) do
		local target, write = fadeTargets[cvar], fadeWriters[cvar]
		StopFade(cvar)
		if target and write then write(target) end
	end
end

-- One volume brought to a value, step by step (written: Wanderer's last word for each, kept with the snapshot).
local function FadeVolume(cvar, target, written)
	StopFade(cvar)
	local from = tonumber(ns.Util.Safe(GetCVar, cvar)) or target
	local function Write(value)
		local text = VolumeText(value)
		WriteCVar(cvar, text)
		written[cvar] = text
	end
	if math.abs(from - target) < SAME_VOLUME or not (C_Timer and C_Timer.NewTicker) then return Write(target) end
	local step = 0
	fadeTargets[cvar] = target
	fadeWriters[cvar] = Write
	fades[cvar] = C_Timer.NewTicker(VOLUME_FADE / VOLUME_STEPS, function()
		-- Moved by someone else on its way: theirs.
		if written[cvar] and not SameVolume(ns.Util.Safe(GetCVar, cvar), written[cvar]) then return StopFade(cvar) end
		step = step + 1
		Write(from + (target - from) * step / VOLUME_STEPS)
		if step >= VOLUME_STEPS then StopFade(cvar) end
	end, VOLUME_STEPS)
end

local function ApplyVolumes(root)
	local share
	for _, held in pairs(root.volumeShares or {}) do share = math.min(share or 1, held) end
	root.volumesWritten = type(root.volumesWritten) == "table" and root.volumesWritten or {}
	local written = root.volumesWritten
	for cvar, value in pairs(root.volumes or {}) do
		local now = ns.Util.Safe(GetCVar, cvar)
		if written[cvar] and not fades[cvar] and not SameVolume(now, written[cvar]) then
			-- Changed since Wanderer wrote it: left as it is, and no longer Wanderer's to give back.
			root.volumes[cvar], written[cvar] = nil, nil
		elseif tonumber(value) then
			FadeVolume(cvar, share and tonumber(value) * share or tonumber(value), written)
		end
	end
	if not share then root.volumes, root.volumeShares, root.volumesWritten = nil, nil, nil end
end
function ns.LowerVolumes(key, share)
	local root = ns.root
	if not root then return end
	if not root.volumes then
		root.volumes = {}
		for _, cvar in ipairs(VOLUME_CVARS) do
			-- (a value still coming back: where it goes is yours)
			local value = fadeTargets[cvar] or tonumber(ns.Util.Safe(GetCVar, cvar))
			if value then root.volumes[cvar] = VolumeText(value) end
		end
	end
	root.volumeShares = root.volumeShares or {}
	root.volumeShares[key] = share
	ApplyVolumes(root)
end
function ns.RestoreVolumes(key)
	local root = ns.root
	if not root then return end
	-- (an older version kept the values under the reason's own key)
	if type(root[key]) == "table" then
		for cvar, value in pairs(root[key]) do WriteCVar(cvar, value) end
		root[key] = nil
	end
	if not (root.volumeShares and root.volumeShares[key]) then return end
	root.volumeShares[key] = nil
	ApplyVolumes(root)
end

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

-- Above every head: the nameplates the label needs, out of instances (the
-- game keeps the plates of allies to itself there). Plates.lua keeps the ones
-- Wanderer turned on invisible.
local function AllHeads(db)
	local zone = ns.zone or "world"
	return db.label.allHeads and db.label.anchor == "head" and zone ~= "dungeon" and zone ~= "raid" and zone ~= "pvp"
		and not (ns.Yields and ns.Yields("nameplates")) -- (another addon's plates: left to it)
end

-- In instances the health bars are the player's own choice (the game's
-- Nameplates options, V and Shift+V): Wanderer only turns on, out of them,
-- the plates the label needs.
local function FriendlyPlates(db)
	return AllHeads(db) and "1" or nil
end

-- Enemy names as you come near: out of a fight, the plates (and the names
-- Wanderer writes on them) fade with the distance, by the game's own settings.
-- Distances from the camera (the game measures from it), in yards: the names
-- are gone farther than the chosen distance and fully seen FADE yards closer.
local NEAR_FADE = 18

-- The plates' reach the player chose (before Wanderer touched it).
local function OwnReach()
	local original = ns.root.original and ns.root.original.nameplateMaxDistance
	return tonumber(original) or tonumber(ns.Util.Safe(GetCVar, "nameplateMaxDistance")) or 60
end
local function NearNames(db)
	return db.enemyNames == "near" and AllHeads(db) and not ns.inCombat
end

-- The game's loot sparkle on quest items: it only shows with the outline mode off, which the graphics presets
-- turn on again (the option keeps it so). Touched only while the option is on: your values kept when it is
-- switched on, given back when it is switched off; never otherwise.
local SPARKLE_CVARS = {
	outlineModeShowLootEffectWhenDisabled = "1", graphicsOutlineMode = "0", OutlineEngineMode = "0",
	raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0",
}

local function ActionCam(db)
	return db.world.actionCam and not (ns.Yields and ns.Yields("camera"))
end

-- Other variables Wanderer drives: name -> value wanted by the profile, or nil
-- to leave the player's own.
local MANAGED_CVARS = {
	-- The enemies' plates themselves (V in the game): their names need them.
	nameplateShowEnemies = function(db) return db.enemyNames == "near" and AllHeads(db) and "1" or nil end,
	nameplateMinAlpha = function(db) return NearNames(db) and "0" or nil end,
	nameplateMaxDistance = function(db)
		if not NearNames(db) then return nil end
		local own = OwnReach()
		return db.nearNames.distance > own and tostring(db.nearNames.distance) or nil
	end,
	nameplateMaxAlphaDistance = function(db)
		return NearNames(db) and tostring(math.max(5, db.nearNames.distance - NEAR_FADE)) or nil
	end,
	-- Counted by the game from the plates' farthest reach, not from you.
	nameplateMinAlphaDistance = function(db)
		if not NearNames(db) then return nil end
		local own = OwnReach()
		local reach = math.max(own, db.nearNames.distance)
		return tostring(math.max(0, reach - db.nearNames.distance))
	end,
	nameplateShowAll = function(db) return AllHeads(db) and "1" or nil end,
	nameplateShowFriendlyPlayers = FriendlyPlates,
	nameplateShowFriends = FriendlyPlates, -- its older name
	nameplateShowFriendlyNPCs = function(db) return AllHeads(db) and "1" or nil end,
	nameplateShowEnemyMinus = function(db) return AllHeads(db) and "1" or nil end,
	-- The game's damage meter, shown or not by the profile (the dungeons': shown).
	damageMeterEnabled = function(db)
		local show = type(db.meter) == "table" and db.meter.show
		if show == "on" then return "1" end
		if show == "off" then return "0" end
		return nil
	end,
	-- Action camera (hidden settings of the game): pitch following the ground,
	-- camera slightly over the shoulder. (another addon driving the camera: yours, left to it)
	test_cameraDynamicPitch = function(db) return ActionCam(db) and "1" or nil end,
	test_cameraOverShoulder = function(db) return ActionCam(db) and "0.5" or nil end,
}

local function ApplySparkle()
	local db, root = ns.db, ns.root
	if not (db and root) then return end
	-- (another addon keeping the sparkle: left to it)
	local other = ns.Yields("lootSparkle")
	local on = db.enabled and db.world.lootSparkle and not other
	if not (on or root.sparkleOriginal) then return end
	if InCombatLockdown() then
		pendingApply = true
		return
	end
	if on then
		root.sparkleOriginal = root.sparkleOriginal or {}
		for cvar, value in pairs(SPARKLE_CVARS) do
			if CVarExists(cvar) then
				if root.sparkleOriginal[cvar] == nil then root.sparkleOriginal[cvar] = GetCVar(cvar) end
				WriteCVar(cvar, value)
			end
		end
	else
		-- Your values back; the sparkle's own switch stays the other addon's.
		for cvar, value in pairs(root.sparkleOriginal) do
			if not (other and SPARKLE_CVARS[cvar] == "1") then WriteCVar(cvar, value) end
		end
		root.sparkleOriginal = nil
	end
end

-- A graphics preset chosen while the sparkle is kept: kept again a moment later (after the fight).
local sparkleWatch = CreateFrame("Frame")
pcall(sparkleWatch.RegisterEvent, sparkleWatch, "CVAR_UPDATE")
sparkleWatch:SetScript("OnEvent", function(_, _, name)
	local db = ns.db
	if not (db and db.enabled and db.world.lootSparkle and type(name) == "string") or ns.Yields("lootSparkle") then return end
	for cvar, value in pairs(SPARKLE_CVARS) do
		if cvar:lower() == name:lower() and ns.Util.Safe(GetCVar, cvar) ~= value then
			C_Timer.After(1, ApplySparkle)
			return
		end
	end
end)

-- The game's settings Wanderer drives (the names, the plates, the damage meter...), held like the volumes:
-- ns.root.original keeps your own value of each (the one before Wanderer wrote it, else the one seen now),
-- ns.root.cvarsWritten what Wanderer wrote (saved: after a crash, given back at the next load). A setting
-- found at another value than Wanderer wrote was changed meanwhile (V for the plates, the damage meter's
-- switch, the game's options, another addon): it is yours, never written over nor "given back". Wanderer
-- writes it again only once what it wants changes (cvarsLeft: what it wanted then, for each character).
local function SameValue(a, b)
	if a == b then return true end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and y ~= nil and math.abs(x - y) < 0.001
end

-- Saved before 0.46 (no record of what Wanderer wrote): every setting found away from the value kept as yours
-- counted as Wanderer's, so it comes back (as it did then).
local function AdoptOldSnapshot(root)
	local written = {}
	for cvar, value in pairs(type(root.original) == "table" and root.original or {}) do
		local now = CVarExists(cvar) and GetCVar(cvar)
		if now and not SameValue(now, value) then written[cvar] = now end
	end
	root.cvarsWritten = written
end

local function Held()
	local root = ns.root
	if root.cvarsWritten == nil then AdoptOldSnapshot(root) end
	root.original = type(root.original) == "table" and root.original or {}
	root.cvarsWritten = type(root.cvarsWritten) == "table" and root.cvarsWritten or {}
	root.cvarsLeft = type(root.cvarsLeft) == "table" and root.cvarsLeft or {}
	local key = ns.CharacterKey()
	root.cvarsLeft[key] = type(root.cvarsLeft[key]) == "table" and root.cvarsLeft[key] or {}
	return root.original, root.cvarsWritten, root.cvarsLeft[key]
end

-- Your value written back: false when the game refused it for now (in a fight).
local function GiveBack(cvar, original, written)
	local value = original[cvar]
	if value ~= nil then
		WriteCVar(cvar, value)
		if not SameValue(GetCVar(cvar), value) then return false end
	end
	written[cvar] = nil
	return true
end

local heldThisSession = {} -- cvar -> true once looked at since the game started (a /reload too)
local clampedWish = {} -- cvar -> the wish the game kept within its limits (written then holds what it took)

-- One setting as Wanderer wants it now (wish: a value, nil: yours). False when the game refused it.
local function Hold(cvar, wish)
	if not CVarExists(cvar) then return true end
	local original, written, left = Held()
	local now = GetCVar(cvar)
	if written[cvar] ~= nil and not SameValue(now, written[cvar]) then
		-- First look this session: the game did not keep Wanderer's value (a crash), nothing of yours there.
		if heldThisSession[cvar] then left[cvar] = written[cvar] end
		written[cvar] = nil
	end
	heldThisSession[cvar] = true
	if written[cvar] == nil then original[cvar] = now end
	if wish == nil then
		left[cvar] = nil
		if written[cvar] == nil then return true end
		return GiveBack(cvar, original, written)
	end
	-- (changed by you while Wanderer wanted this same value: yours)
	if left[cvar] ~= nil and SameValue(left[cvar], wish) then return true end
	left[cvar] = nil
	-- (this same wish already kept within the game's limits: nothing more to write)
	if written[cvar] ~= nil and clampedWish[cvar] ~= nil and SameValue(clampedWish[cvar], wish) then return true end
	WriteCVar(cvar, wish, true)
	local after = GetCVar(cvar)
	if not SameValue(after, wish) then
		-- (kept within the game's own limits: the value it took is still Wanderer's to give back)
		if after ~= nil and not SameValue(after, now) then
			written[cvar], clampedWish[cvar] = after, wish
			return true
		end
		return false
	end
	written[cvar], clampedWish[cvar] = wish, nil
	return true
end

-- Every setting Wanderer wrote given back, unless changed since (yours already). One the game refused (in a
-- fight) stays written down, given back at the next load.
function ns.RestoreOriginal()
	local original, written = Held()
	local names = {}
	for cvar in pairs(written) do names[#names + 1] = cvar end
	for _, cvar in ipairs(names) do
		if not CVarExists(cvar) or not SameValue(GetCVar(cvar), written[cvar]) then
			written[cvar] = nil
		else
			GiveBack(cvar, original, written)
		end
	end
	ns.root.dirty = next(written) ~= nil
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
	local zone = ns.zone or "world"
	local instance = zone == "dungeon" or zone == "raid" or zone == "pvp"
	if cat.enemy and db.enemyNames == "always" then show = true end
	-- Near: Wanderer writes them itself over the plates (Plates.lua); in instances the zone decides.
	if cat.enemy and (db.enemyNames == "never" or (db.enemyNames == "near" and not instance)) then show = false end
	if cat.enemy and db.combatEnemies and ns.inCombat then show = true end
	return show
end

function ns.Apply()
	local db = ns.db
	if not db then return end
	-- The game's damage meter dressed (or given back its own look when Wanderer is off).
	ns.ApplyMeter()
	-- The unit frames in Wanderer's look (or given back theirs).
	if ns.ApplyUnitFrames then ns.ApplyUnitFrames() end
	pendingApply = false
	ApplySparkle()
	if not db.enabled then
		ns.RestoreOriginal()
		return
	end
	local failed = false
	for _, cat in ipairs(ns.CATEGORIES) do
		local value = ShouldShowCategory(cat) and "1" or "0"
		for _, cvar in ipairs(cat.cvars) do
			if not Hold(cvar, value) then failed = true end
		end
	end
	-- (nil wanted: yours, given back if Wanderer wrote it and you did not change it since)
	for cvar, wanted in pairs(MANAGED_CVARS) do
		if not Hold(cvar, wanted(db)) then failed = true end
	end
	local _, written = Held()
	ns.root.dirty = next(written) ~= nil
	-- Some variables may be locked during combat: retry afterwards (the sparkle's own wait kept).
	pendingApply = pendingApply or (failed and InCombatLockdown())
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
	local own = ns.ChosenProfile()
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

-- One profile per kind of place, made from the character's own, ready to adjust.
-- What each place asks of the interface. The minimap, the quests and the
-- chat are never faded; the rest (portraits, action bars, menus, bags,
-- experience) fades out of the way when it is not needed, and comes back at
-- once in a fight, under the mouse or with a window open.
--   Dungeons (and raids, battlegrounds): everything in view, always.
--   Cities: nothing to fight, many characters to talk to: faded out of a
--   fight even with a target (talking to a merchant brings nothing back).
--   Open world: barely there while calm; a target brings everything back
--   (cooldowns and range before a pull), a fight too.
--   Flights (travel mode, every place): everything fades, the chat too (back under the mouse, or while typing).
local PLACE_SETTINGS = {
	dungeon = { enabled = false, combatOnly = false },
	city = { enabled = false, combatOnly = true, alpha = 0, delay = 2 },
	world = { enabled = true, combatOnly = false, alpha = 20, delay = 4 },
}
-- The game's damage meter: in dungeons (and raids, battlegrounds) only.
local PLACE_METER = { dungeon = "on", city = "off", world = "off" }
ns.PLACE_METER = PLACE_METER

-- What a place's profile is made with for a setting (MakePlaceProfiles below); nil: a profile that is no
-- place's of this character, or a setting the places leave alone.
function ns.PlaceValue(path, profile)
	if not (ns.root and type(ns.root.profiles) == "table") then return nil end
	local map = ns.PlaceProfiles()
	for zone, settings in pairs(PLACE_SETTINGS) do
		if map[zone] and ns.root.profiles[map[zone]] == profile then
			if path == "meter.show" then return PLACE_METER[zone] end
			if path == "travel.enabled" then return true end
			local key = path:match("^cinema%.(.+)$")
			if key then return settings[key] end
			return nil
		end
	end
	return nil
end

-- A place's profile, this character's: the place, then the name of the character's own profile (its name
-- while it has none).
local function PlaceProfileName(zone)
	local own = type(ns.root.ownProfile) == "table" and ns.root.ownProfile[ns.CharacterKey()]
	return L["PLACE_PROFILE_" .. zone:upper()] .. " (" .. (own or ns.CharacterName()) .. ")"
end

-- A setting you change: the same in every profile of this character (its own and its places'), but what the
-- places are for (the interface fading, travel, the damage meter), kept to the place where it was changed.
-- Before, a change made in town went back on the road and the setting seemed not to hold.
local PLACE_ONLY = { ["cinema.enabled"] = true, ["cinema.combatOnly"] = true, ["cinema.alpha"] = true,
	["cinema.delay"] = true, ["travel.enabled"] = true, ["meter.show"] = true }
function ns.ChangeEverywhere(change)
	local active, before = ns.db, DeepCopy(ns.db)
	change()
	-- (a profile chosen, or no profile: nothing to carry)
	if not (ns.root and ns.db == active and type(before) == "table") then return end
	local others, seen = {}, { [active] = true }
	local function Add(name)
		local profile = name and ns.root.profiles[name]
		if type(profile) == "table" and not seen[profile] then
			seen[profile] = true
			others[#others + 1] = profile
		end
	end
	Add(ns.ChosenProfile())
	for _, name in pairs(ns.PlaceProfiles()) do Add(name) end
	if not others[1] then return end
	local function Carry(now, was, keys)
		for key, value in pairs(now) do
			local path = {}
			for index, part in ipairs(keys) do path[index] = part end
			path[#path + 1] = key
			local old = type(was) == "table" and was[key] or nil
			if type(value) == "table" then
				Carry(value, old, path)
			elseif old ~= value and not PLACE_ONLY[table.concat(path, ".")] then
				for _, profile in ipairs(others) do
					local at = profile
					for index = 1, #path - 1 do
						if type(at[path[index]]) ~= "table" then at[path[index]] = {} end
						at = at[path[index]]
					end
					at[path[#path]] = DeepCopy(value)
				end
			end
		end
		-- (a key removed, a line taken out of a list: removed there too)
		if type(was) ~= "table" then return end
		for key in pairs(was) do
			if now[key] == nil then
				local path = {}
				for index, part in ipairs(keys) do path[index] = part end
				path[#path + 1] = key
				if not PLACE_ONLY[table.concat(path, ".")] then
					for _, profile in ipairs(others) do
						local at = profile
						for index = 1, #path - 1 do at = type(at) == "table" and at[path[index]] or nil end
						if type(at) == "table" then at[key] = nil end
					end
				end
			end
		end
	end
	Carry(active, before, {})
end

-- quiet: only made (or set again), nothing said or switched (the welcome's ways do it after).
function ns.MakePlaceProfiles(quiet)
	local map = ns.PlaceProfiles()
	local source = ns.ChosenProfile()
	for _, zone in ipairs({ "world", "city", "dungeon" }) do
		local name = PlaceProfileName(zone)
		if not ns.root.profiles[name] then ns.root.profiles[name] = DeepCopy(ns.root.profiles[source]) end
		-- Made ready for the place (asked again: set again; the rest is yours).
		local profile = ns.root.profiles[name]
		profile.cinema = profile.cinema or {}
		for key, value in pairs(PLACE_SETTINGS[zone]) do profile.cinema[key] = value end
		profile.travel = profile.travel or {}
		profile.travel.enabled = true
		profile.meter = profile.meter or {}
		profile.meter.show = PLACE_METER[zone]
		map[zone] = name
	end
	map.raid = map.raid or map.dungeon
	map.pvp = map.pvp or map.dungeon
	if quiet then return end
	ns.UpdatePlaceProfile()
	if ns.initialized then ns.RefreshAll() end
	ns.RefreshOptions()
	ns.Print(L.MSG_PLACE_PROFILES_MADE)
end

-- The profiles by place let go for this character (the profiles themselves stay): its own profile everywhere.
function ns.ClearPlaceProfiles()
	local map = ns.PlaceProfiles()
	for zone in pairs(map) do map[zone] = nil end
	ns.UpdatePlaceProfile()
	ns.RefreshOptions()
end

local function UpdateZone()
	local zone = DetectZone()
	if zone ~= ns.zone then
		ns.zone = zone
		ns.Apply()
		ns.UpdatePlaceProfile()
	end
end

-- Every module refreshed after a settings change, in this order (Wanderer's looks last: over what the
-- discreet minimap and tracker give back).
local REFRESH = { "RefreshOptions", "RefreshLabel", "RefreshMinimapButton", "RefreshCinema", "RefreshTooltips", "RefreshTrainer",
	"RefreshScreen", "RefreshSounds", "RefreshScene", "RefreshClean", "RefreshIcons", "RefreshBarSlots", "RefreshGameFrames",
	"RefreshTargetInfo", "RefreshPlates", "RefreshDots", "RefreshHots", "RefreshAway", "RefreshMinimapLook", "RefreshTrackerLook", "RefreshCrafts",
	"RefreshCurtain", "RefreshLootFeed" }

-- (one failing is reported, the others still refreshed)
function ns.RefreshAll()
	ns.Util.Try(ns.Apply)
	for _, extension in ipairs(ns.EXTENSIONS) do
		if extension.refresh then ns.Util.Try(extension.refresh) end
	end
	for _, name in ipairs(REFRESH) do
		if ns[name] then ns.Util.Try(ns[name]) end
	end
end

function ns.SetPreset(preset)
	local values = ns.PRESETS[preset]
	if not values then return end
	-- (as any setting you change: in every profile of this character, its places' too; /wanderer immersion too)
	ns.ChangeEverywhere(function()
		ns.db.preset = preset
		for _, cat in ipairs(ns.CATEGORIES) do
			ns.db.show[cat.key] = values[cat.key] and true or false
		end
		ns.db.label.enabled = preset ~= "all"
	end)
	ns.RefreshAll()
end

-- (the card's switch and /wanderer on, off, reset too: in every profile of this character, else Wanderer came
-- back on in the next place)
function ns.SetEnabled(enabled)
	ns.ChangeEverywhere(function() ns.db.enabled = enabled and true or false end)
	-- Every module, so nothing of Wanderer stays active (e.g. its interaction key).
	ns.RefreshAll()
end

-- Profiles --------------------------------------------------------------------
-- WandererDB = { profiles = { name = settings }, profileKeys = { character = name },
--             original, dirty, questBook, minimap }

-- This character, as Wanderer keeps its own data: its identity in the game (WoW Forever's names have several
-- words and its realm says nothing: two characters may share a first name). Before 0.45, its first name and
-- realm (OldCharacterKey), moved once to the new key.
local function OldCharacterKey()
	local name = UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return name .. " - " .. realm
end
function ns.CharacterKey()
	return ns.Util.Clean(ns.Util.Safe(UnitGUID, "player")) or OldCharacterKey()
end

-- The tables kept by character (Characters.lua lets a forgotten one go from all of them). The chat's four
-- stay until each character's part has gone to Wanderer Chat.
ns.BY_CHARACTER = { "profileKeys", "placeProfiles", "welcomedBy", "characters", "chatHistory", "chatLog", "chatFontBefore",
	"messages", "reagentsKnown", "todo", "playChoice", "provisions", "ownProfile", "mine", "cvarsLeft", "craftCeilings" }

-- This character's name, as its own profile is called.
function ns.CharacterName()
	return ns.Util.Clean(ns.Util.FullName("player")) or ns.Util.Clean(ns.Util.Safe(UnitName, "player")) or "?"
end

-- Each character its own profile, named after it (a name taken: a number after it), made the first time it
-- is needed: from the profile it shared until then (from), else Wanderer's defaults. Another profile, chosen
-- by you, is shared on purpose.
function ns.OwnProfile(from)
	local root, key = ns.root, ns.CharacterKey()
	root.ownProfile = type(root.ownProfile) == "table" and root.ownProfile or {}
	local name = root.ownProfile[key]
	if name and root.profiles[name] then return name end
	local base = ns.CharacterName()
	name = base
	local number = 2
	while root.profiles[name] do
		name = base .. " " .. number
		number = number + 1
	end
	root.profiles[name] = from and root.profiles[from] and DeepCopy(root.profiles[from]) or {}
	root.ownProfile[key] = name
	return name
end

-- The profile this character uses outside the places' own: the one chosen, else its own. Until 0.45, every
-- character shared "Default" unless another was chosen: each takes its copy of it, once.
function ns.ChosenProfile()
	local root, key = ns.root, ns.CharacterKey()
	local chosen = root.profileKeys[key]
	local hasOwn = type(root.ownProfile) == "table" and root.ownProfile[key]
	if chosen and root.profiles[chosen] and (chosen ~= DEFAULT_PROFILE or hasOwn) then return chosen end
	if chosen == DEFAULT_PROFILE and not hasOwn and root.profiles[DEFAULT_PROFILE] then
		ns.movedToOwn = true
		return ns.OwnProfile(DEFAULT_PROFILE)
	end
	return ns.OwnProfile()
end

-- Until 0.45, the places' profiles had one name for every character: each takes this character's name, a
-- copy when another character uses it too (a profile you chose for a place stays as chosen).
local function OwnPlaceProfiles(root)
	local key = ns.CharacterKey()
	local map = type(root.placeProfiles) == "table" and root.placeProfiles[key]
	if type(map) ~= "table" then return end
	local made = {}
	for zone, name in pairs(map) do
		local shared = false
		for _, place in ipairs({ "world", "city", "dungeon" }) do
			if name == L["PLACE_PROFILE_" .. place:upper()] then shared = place end
		end
		if shared and root.profiles[name] then
			made[name] = made[name] or PlaceProfileName(shared)
			root.profiles[made[name]] = root.profiles[made[name]] or DeepCopy(root.profiles[name])
			map[zone] = made[name]
		end
	end
	-- (the old name used by no one else now: gone)
	for name in pairs(made) do
		local used = false
		for _, places in pairs(root.placeProfiles) do
			if type(places) == "table" then
				for _, other in pairs(places) do used = used or other == name end
			end
		end
		for _, chosen in pairs(root.profileKeys or {}) do used = used or chosen == name end
		if not used then root.profiles[name] = nil end
	end
end

-- Settings once kept for the whole account, each character's own now (ns.Mine()): the account's value of
-- before, copied once to every character known then, and gone. A character made later starts with none.
local ACCOUNT_TO_CHARACTER = { "todoAtLogin", "todoSize", "minimap", "framePoints", "scales", "weightOverrides" }
-- The windows' spots (Skin.Dress: todoPos, questsPos...): this character's, in mine.spots.
local function IsSpot(name, value)
	return type(name) == "string" and name:match("Pos$") ~= nil and type(value) == "table" and type(value[1]) == "string"
end
local function SplitAccountSettings(root)
	local known = { [ns.CharacterKey()] = true }
	for _, name in ipairs({ "profileKeys", "characters", "todo", "welcomedBy" }) do
		if type(root[name]) == "table" then
			for key in pairs(root[name]) do known[key] = true end
		end
	end
	for _, name in ipairs(ACCOUNT_TO_CHARACTER) do
		if root[name] ~= nil then
			root.mine = type(root.mine) == "table" and root.mine or {}
			for key in pairs(known) do
				root.mine[key] = type(root.mine[key]) == "table" and root.mine[key] or {}
				if root.mine[key][name] == nil then root.mine[key][name] = DeepCopy(root[name]) end
			end
			root[name] = nil
		end
	end
	for name, value in pairs(root) do
		if IsSpot(name, value) then
			root.mine = type(root.mine) == "table" and root.mine or {}
			for key in pairs(known) do
				local mine = type(root.mine[key]) == "table" and root.mine[key] or {}
				root.mine[key] = mine
				mine.spots = type(mine.spots) == "table" and mine.spots or {}
				if mine.spots[name] == nil then mine.spots[name] = DeepCopy(value) end
			end
		end
	end
	local spots = {}
	for name, value in pairs(root) do
		if IsSpot(name, value) then spots[#spots + 1] = name end
	end
	for _, name in ipairs(spots) do root[name] = nil end
end

-- This character's own settings outside its profile (the todo list's size, the minimap button...).
function ns.Mine()
	local root = ns.root
	root.mine = type(root.mine) == "table" and root.mine or {}
	local key = ns.CharacterKey()
	root.mine[key] = type(root.mine[key]) == "table" and root.mine[key] or {}
	return root.mine[key]
end

-- What this character keeps through a /reload or a crash to put the game back as it was (the camera's distance,
-- the settings it borrowed): never another character's. One kept for the account before 0.45 is moved to it,
-- but for a camera distance (another character's: dropped; the settings borrowed are the account's: moved).
local ACCOUNT_KEPT = { travelZoom = "drop", sceneCamera = "cvars" }
function ns.Kept(key)
	local mine = ns.Mine()
	local old = ns.root[key]
	if old ~= nil then
		ns.root[key] = nil
		local rule = ACCOUNT_KEPT[key]
		if rule == "cvars" then
			mine[key] = type(old) == "table" and type(old.cvars) == "table" and { cvars = old.cvars } or nil
		elseif rule ~= "drop" then
			mine[key] = old
		end
	end
	return mine[key]
end
function ns.Keep(key, value)
	ns.Kept(key)
	ns.Mine()[key] = value
end

-- Where this character put Wanderer's windows: name -> { anchor, x, y, free }.
function ns.Spots()
	local mine = ns.Mine()
	mine.spots = type(mine.spots) == "table" and mine.spots or {}
	return mine.spots
end
-- (moved from the old key to the new one, once, at the first load after 0.45)
local function MoveCharacterKey(root)
	local old, new = OldCharacterKey(), ns.CharacterKey()
	if old == new then return end
	for _, name in ipairs(ns.BY_CHARACTER) do
		local list = root[name]
		if type(list) == "table" and list[old] ~= nil and list[new] == nil then
			list[new], list[old] = list[old], nil
		end
	end
end

-- Moves the settings of versions before profiles into the default profile.
local function Migrate(root)
	if root.profiles then return end
	local profile = {}
	for key in pairs(DEFAULTS) do
		if root[key] ~= nil then profile[key] = root[key] root[key] = nil end
	end
	-- (nothing of before: no profile yet, each character makes its own)
	if next(profile) == nil then
		root.profiles = {}
		return
	end
	root.profiles = { [DEFAULT_PROFILE] = profile }
	root.profileKeys = { [ns.CharacterKey()] = DEFAULT_PROFILE }
end

-- One of the three levels of the label's content, every line set at once.
function ns.SetLabelContent(level)
	local label = ns.db.label
	for _, key in ipairs(ns.LABEL_CONTENT_KEYS) do
		if level == "essential" then
			label[key] = ESSENTIAL[key] or false
		elseif level == "all" then
			label[key] = true
		else
			label[key] = DEFAULTS.label[key]
		end
	end
	label.content = level
	ns.RefreshLabel()
end

function ns.SetProfile(name, byPlace)
	local root = ns.root
	if not root.profiles[name] then root.profiles[name] = {} end
	local profile = root.profiles[name]
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
	if (profile.styleVersion or 0) < 9 then
		if type(profile.nearNames) == "table" and profile.nearNames.distance == 40 then profile.nearNames.distance = 45 end
		profile.styleVersion = 9
	end
	-- 0.40: the damage meter by place, once for the places' profiles already made (dungeons: shown, elsewhere: not).
	if (profile.styleVersion or 0) < 10 then
		for _, places in pairs(root.placeProfiles or {}) do
			for zone, placeName in pairs(places) do
				if placeName == name then
					profile.meter = type(profile.meter) == "table" and profile.meter or {}
					profile.meter.show = (zone == "dungeon" or zone == "raid" or zone == "pvp") and "on" or "off"
				end
			end
		end
		profile.styleVersion = 10
	end
	-- 0.43: Wanderer's bar, a setting of the profile (it was the account's while tried): kept as it was, in
	-- every profile at once (the place profiles are chosen later than the first).
	if (profile.styleVersion or 0) < 11 then
		if type(root.bar) == "table" and root.bar.hide == false then
			for _, other in pairs(root.profiles or {}) do
				if type(other) == "table" and type(other.world) == "table" and (other.styleVersion or 0) < 11 then other.world.bar = true end
			end
			if type(profile.world) == "table" then profile.world.bar = true end
		end
		root.bar = nil
		profile.styleVersion = 11
	end
	-- 0.45: the points gained in a profession, said by the game in the chat already: no notice any more, once
	-- for every profile (a new gathering reach is still told); free after.
	if (profile.styleVersion or 0) < 12 then
		if type(profile.crafts) == "table" then profile.crafts.skillUps = false end
		profile.styleVersion = 12
	end
	-- 0.46: the scene camera at the shops and its framing, asked for now; a profile that had the camera keeps
	-- them as it had them (a new profile starts without).
	if (profile.styleVersion or 0) < 13 then
		local scene = profile.scene
		if type(scene) == "table" and scene.camera ~= nil then
			if scene.cameraShops == nil then scene.cameraShops = scene.camera == true end
			if scene.cameraFrame == nil then scene.cameraFrame = scene.camera == true end
		end
		profile.styleVersion = 13
	end
	-- 1.4.6: the label stays whole in a fight, once for every profile (the option remains, to ask for less).
	if (profile.styleVersion or 0) < 14 then
		if type(profile.label) == "table" then profile.label.combatLight = false end
		profile.styleVersion = 14
	end
	Sanitize(DEFAULTS, profile)
	profile.cinema.combatBars = nil -- 0.18: replaced by combatOnly (every faded element)
	profile.scene.speak = nil -- 0.37: the voice, tried and dropped
	root.rareKills = nil
	-- 0.38: the travel journal, the session summary and the rares' victories are gone.
	if type(profile.journal) == "table" and profile.journal.threshold == false then profile.world.threshold = false end
	profile.journal, profile.session = nil, nil
	profile.label.showRareKills, profile.crafts.firstCrafts = nil, nil
	if profile.away.style == "journal" then profile.away.style = "contemplation" end
	-- 0.40: the damage meter's Wanderer look, heavier than the game's, dropped.
	if type(profile.meter) == "table" and profile.meter.look == "wanderer" then profile.meter.look = "game" end
	-- Settings of modules that are gone (the game does it itself).
	profile.interact, profile.questLog, profile.dev = nil, nil, nil
	if not byPlace then root.profileKeys[ns.CharacterKey()] = name end
	ns.profileName = name
	ns.db = root.profiles[name]
	if ns.initialized then ns.RefreshAll() end
end

ns.Sanitize = Sanitize

-- The active profile back to Wanderer's defaults. The journal, the other
-- profiles and the game's own settings are not part of it.
function ns.ResetProfile()
	local name = ns.profileName
	ns.root.profiles[name] = {}
	-- A place's profile stays the place's: the character keeps their own.
	ns.SetProfile(name, name ~= ns.root.profileKeys[ns.CharacterKey()])
	ns.RefreshOptions()
	ns.RefreshThemeGrids()
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

-- A character's own profile stays (reset it instead); those who used another one deleted go back to theirs.
function ns.DeleteProfile(name)
	for _, own in pairs(ns.root.ownProfile or {}) do
		if own == name then return false end
	end
	ns.root.profiles[name] = nil
	for character, profile in pairs(ns.root.profileKeys) do
		if profile == name then ns.root.profileKeys[character] = nil end
	end
	for _, places in pairs(ns.root.placeProfiles or {}) do
		for zone, profile in pairs(places) do
			if profile == name then places[zone] = nil end
		end
	end
	if ns.profileName == name then ns.SetProfile(WantedProfile(), true) end
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
BINDING_NAME_WANDERER_MARKERS = L.BINDING_MARKERS
BINDING_NAME_WANDERER_TODO = L.BINDING_TODO
_G["BINDING_NAME_CLICK WandererCampfire:LeftButton"] = L.BINDING_CAMPFIRE

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
		-- What removed features left behind (the journal, its sessions, the parchment): let go.
		for _, key in ipairs({ "journal", "questTitles", "sessions", "sessionPos", "paper" }) do WandererDB[key] = nil end
		-- The interaction prompt is gone: the game's own setting is the
		-- player's again, as it was before Wanderer.
		local original = WandererDB.original
		if original and original.SoftTargetInteract ~= nil then
			pcall(SetCVar, "SoftTargetInteract", original.SoftTargetInteract)
			original.SoftTargetInteract = nil
		end
		-- (0.44.33: the sparkle's settings were briefly kept with the others, to be put back at logout: never theirs)
		if original then
			for cvar in pairs(SPARKLE_CVARS) do original[cvar] = nil end
		end
		WandererDB.profileKeys = WandererDB.profileKeys or {}
		MoveCharacterKey(WandererDB)
		SplitAccountSettings(WandererDB)
		-- (the character's own profile first: the places' are named after it)
		local chosen = ns.ChosenProfile()
		OwnPlaceProfiles(WandererDB)
		ns.SetProfile(chosen)
		-- Modules are built once: frames, hooks and events must never be doubled.
		if not ns.initialized then
			for _, init in ipairs({ "InitCompat", "InitLabel","InitOptions", "InitMinimapButton", "InitBar", "InitCinema", "InitTooltips",
				"InitMerchant", "InitLoot", "InitTrainer", "InitDialogues", "InitSocial", "InitScreen",
				"InitTagging", "InitAcquaintances", "InitPlates", "InitMarkers", "InitToast", "InitSounds", "InitFishing", "InitCrafts", "InitTodo", "InitThreshold", "InitTown", "InitScene", "InitReader", "InitCamera", "InitGestures", "InitCurtain", "InitCampfire", "InitAway", "InitClean", "InitMinimapLook", "InitLayer", "InitProvisions", "InitDots", "InitDotBars", "InitHots", "InitHotBars", "InitTrackerLook", "InitIcons", "InitHands", "InitCharacters", "InitWorth", "InitThreat", "InitMeter", "InitBuffs", "InitUpgrade", "InitReagents", "InitWeights", "InitTargetInfo", "InitGameFrames", "InitBarSlots", "InitNews", "InitUnitFrames", "InitPortraits", "InitPreview", "InitSparkles", "InitLootFeed", "InitEmotes", "InitWelcome" }) do
				-- (one module failing at its start is reported, the others still start)
				if ns[init] then ns.Util.Try(ns[init]) end
			end
			ns.initialized = true
		end
	elseif event == "PLAYER_LOGIN" then
		-- (the character known by its name at loading, when the game had not given its identity yet)
		MoveCharacterKey(ns.root)
		ns.FinishOptions()
		ns.inCombat = InCombatLockdown()
		ns.zone = DetectZone()
		ns.Apply()
		ns.UpdatePlaceProfile()
		if ns.movedToOwn then
			ns.movedToOwn = nil
			C_Timer.After(6, function() ns.Print(L.MSG_OWN_PROFILE:format(ns.root.ownProfile[ns.CharacterKey()] or "?")) end)
		end
	elseif event == "PLAYER_LOGOUT" then
		-- Leave the game exactly as it was without Wanderer, in case it gets disabled.
		ns.FinishVolumeFades()
		ns.RestoreOriginal()
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.inCombat = true
		-- (enemy names as you come near: their fading with the distance ends with the fight, every enemy's bar
		-- seen; written now, before the fight locks the game's settings)
		if ns.db.enabled and (ns.db.combatEnemies or ns.db.enemyNames == "near") then ns.Apply() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.inCombat = false
		if pendingApply or (ns.db.enabled and (ns.db.combatEnemies or ns.db.enemyNames == "near")) then ns.Apply() end
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
				ns.ChangeEverywhere(function() ns.db.label.style = style end)
				ns.RefreshAll()
				ns.Print(L.MSG_STYLE:format(L["STYLE_" .. style:upper()]))
				return
			end
		end
		ns.Print(L.MSG_STYLE_HELP:format(table.concat(names, ", ")))
	elseif msg == "bienvenue" or msg == "welcome" then
		ns.ShowWelcome()
	elseif msg == "place" or msg == "placer" then
		ns.PlaceMode()
	elseif msg == "copy" or msg == "copier" then
		ns.CopyChat()
	elseif msg == "messages" then
		-- (the private messages' window is Wanderer Chat's now: opened there; without it, its page in the settings)
		if type(_G.WandererChat_ToggleMessages) == "function" then _G.WandererChat_ToggleMessages() else ns.OpenOptions("offer:WandererChat") end
	elseif msg == "away" or msg == "absent" then
		ns.GoAway()
	elseif msg == "photo" then
		ns.TogglePhotoMode()
	elseif msg == "nouveautes" or msg == "nouveautés" or msg == "news" then
		ns.OpenOptions("news")
	elseif msg == "todo" or msg == "afaire" or msg == "à faire" then
		ns.ToggleTodo()
	elseif msg:match("^ennemis") or msg:match("^enemies") then
		-- /wanderer ennemis proche | toujours | jamais | noms: the enemies' names, said back.
		local word = msg:match("^%S+%s+(%S+)")
		local choice = ({ proche = "near", near = "near", toujours = "always", always = "always", jamais = "never",
			never = "never", noms = "names", names = "names" })[word or ""]
		if choice then
			-- (as any setting you change: in every profile of this character, its places' too)
			ns.ChangeEverywhere(function() ns.db.enemyNames = choice end)
			ns.Apply()
			ns.RefreshPlates()
			ns.RefreshOptions()
		end
		ns.Print(L.ENEMY_NAMES_SAID:format(L.ENEMY_NAMES, L["ENEMY_NAMES_" .. ns.db.enemyNames:upper()], tostring(ns.profileName)))
	elseif msg == "poids" or msg == "weights" or msg == "pesos" or msg == "pesi" or msg == "gewichte" then
		ns.ToggleWeights()
	elseif msg == "objet" or msg == "item" then
		ns.DebugUpgrade()
	elseif msg == "clear" or msg == "effacer" then
		-- The tab shown (the Wanderer tab in diagnostic mode).
		local frame = ns.debug and ns.debugFrame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
		if frame and frame.Clear then frame:Clear() end
	elseif msg == "plates dump" or msg == "barres dump" then
		-- (diagnostic: the plates over the heads as Wanderer decides them, over 10 seconds)
		if ns.DumpPlates then ns.DumpPlates() end
	elseif msg == "frames dump" or msg == "cadres dump" then
		-- (diagnostic: the unit frames as the game built them, into the saved data, for a look outside the game)
		if ns.DumpUnitFrames and ns.DumpUnitFrames() then ns.Print(L.UF_DUMP_DONE) end
	elseif msg == "debug" then
		ns.debug = not ns.debug
		ns.debugFrame = ns.debug and ns.DebugFrame(true) or nil
		if ns.debugFrame and FCF_SelectDockFrame then pcall(FCF_SelectDockFrame, ns.debugFrame) end
		ns.Print(ns.debug and L.DEBUG_ON or L.DEBUG_OFF)
		if ns.debug then ns.DebugEnvironment() end
		if ns.debug then ns.Print(ns.Util.DebugNames()) end
	elseif PRESET_ALIASES[msg] then
		local preset = PRESET_ALIASES[msg]
		ns.ChangeEverywhere(function() ns.db.enabled = true end)
		ns.SetPreset(preset)
		ns.Print(L.MSG_PRESET:format(L["PRESET_" .. preset:upper()]))
	else
		ns.Print(L.SLASH_HELP)
		for _, extension in ipairs(ns.EXTENSIONS) do
			if extension.slash then ns.Print(extension.title .. ": " .. extension.slash) end
		end
	end
end

function Wanderer_OnAddonCompartmentClick(_, _, menuButton)
	ns.ShowMenu(menuButton)
end
