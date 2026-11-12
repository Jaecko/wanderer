local _, ns = ...
local L = ns.L

-- Other addons that already do one of Wanderer's jobs: that job is left to them. Each is known by its name
-- (loaded or not) and, when its own switches can be read from its saved data, by whether it does that job now;
-- they are read only, never written. A job left to another addon does nothing here, and its option says who
-- does it (greyed). Wanderer also offers its launchers to the addons that show launchers (LibDataBroker),
-- only when one of them brought that library: nothing is shipped for it.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local function Loaded(addon)
	local check = C_AddOns and C_AddOns.IsAddOnLoaded
	return check and Clean(Safe(check, addon)) and true or false
end
ns.IsAddOnLoaded = Loaded

-- Naowh Forever: its switches as it saved them for this character's profile, else its defaults (as it ships
-- them). Its profiles are chosen by first name and realm.
local NAOWH = "Naowh Forever"
local NAOWH_QOL = "NaowhForever_QoL"
local NAOWH_DEFAULTS = {
	qol = { enabled = true, questAccept = true, questTurnIn = true, questGossip = true, gossipAuto = false, autoRepair = true,
		sellJunk = true, restock = true, restockBuy = false, fastLoot = true, damageMeterSkin = false, deleteConfirm = false,
		altCounts = false, lootFeed = true },
	glimmer = { enabled = false, questSparkle = false },
}

local function NaowhProfile()
	local saved = _G.NaowhForeverDB
	if type(saved) ~= "table" or type(saved.profiles) ~= "table" then return nil end
	local me = (Clean(Safe(UnitName, "player")) or "") .. "-" .. (Clean(Safe(GetRealmName)) or "")
	local chosen = type(saved.charActive) == "table" and saved.charActive[me]
	local profile = type(chosen) == "string" and saved.profiles[chosen]
	if type(profile) ~= "table" then profile = saved.profiles[type(saved.defaultProfile) == "string" and saved.defaultProfile or "Default"] end
	return type(profile) == "table" and profile or nil
end

local function Naowh(module, key)
	local profile = NaowhProfile()
	local section = profile and profile[module]
	local value
	if type(section) == "table" then value = section[key] end
	if value == nil then value = (NAOWH_DEFAULTS[module] or {})[key] end
	return value == true
end

-- The module on, and one of these switches on.
local function NaowhAny(module, ...)
	if not Naowh(module, "enabled") then return false end
	for index = 1, select("#", ...) do
		if Naowh(module, (select(index, ...))) then return true end
	end
	return false
end

-- Wowdee: its switches (for the whole account), under one master switch.
local WOWDEE = "Wowdee"
local WOWDEE_DEFAULTS = { autoOn = true, autoAccept = true, autoTurnIn = true, autoGossip = true, autoSellJunk = true,
	autoRepair = true, autoFastLoot = true, autoRestock = false, autoBuy = false }

local function Wowdee(key)
	local saved = _G.WowdeeDB
	local settings = type(saved) == "table" and saved.settings
	local value
	if type(settings) == "table" then value = settings[key] end
	if value == nil then value = WOWDEE_DEFAULTS[key] end
	return value
end

local function WowdeeAny(...)
	if Wowdee("autoOn") == false then return false end
	for index = 1, select("#", ...) do
		if Wowdee((select(index, ...))) == true then return true end
	end
	return false
end

-- Leatrix Plus: its switches (for the whole account), "On" or "Off"; each of them off until chosen.
local LEATRIX = "Leatrix Plus"
local LEATRIX_ADDON = "Leatrix_Plus"

local function Leatrix(key)
	local saved = _G.LeaPlusDB
	return type(saved) == "table" and saved[key] == "On"
end

local function LeatrixOn(key) return function() return Leatrix(key) end end

-- The profile this character uses in another addon's saved data, as the common profile library keeps them
-- ("Name - Realm" -> profile name), or nil.
local function AceProfile(saved)
	if type(saved) ~= "table" or type(saved.profiles) ~= "table" then return nil end
	local me = (Clean(Safe(UnitName, "player")) or "") .. " - " .. (Clean(Safe(GetRealmName)) or "")
	local key = type(saved.profileKeys) == "table" and saved.profileKeys[me]
	local profile = saved.profiles[type(key) == "string" and key or me] or saved.profiles.Default
	return type(profile) == "table" and profile or nil
end

-- ElvUI: a module of its own (nameplates, bags, chat, tooltip) as this character uses it: read from ElvUI
-- itself once it runs, else from its saved data; on when it cannot be read (its default).
local ELVUI = "ElvUI"

-- (private: the module switches; profile: the settings inside a module)
local function ElvTable(kind)
	local engine = _G.ElvUI
	local E = type(engine) == "table" and engine[1]
	local live = type(E) == "table" and E[kind == "private" and "private" or "db"]
	if type(live) == "table" then return live end
	return AceProfile(kind == "private" and _G.ElvPrivateDB or _G.ElvDB)
end

local function ElvModule(module)
	local private = ElvTable("private")
	local section = type(private) == "table" and private[module]
	return not (type(section) == "table" and section.enable == false)
end

local function ElvOn(module) return function() return ElvModule(module) end end

-- A switch inside one of its modules (on unless saved off).
local function ElvSetting(module, key)
	local profile = ElvTable("profile")
	local section = type(profile) == "table" and profile[module]
	return not (type(section) == "table" and section[key] == false)
end

-- A setting inside one of its modules as saved (nil: never changed, its default).
local function ElvValue(module, ...)
	local node = ElvTable("profile")
	node = type(node) == "table" and node[module]
	for i = 1, select("#", ...) do
		if type(node) ~= "table" then return nil end
		node = node[select(i, ...)]
	end
	return node
end

-- ElvUI's own minimap (a switch of its private settings: on unless saved off).
local function ElvMinimap()
	local private = ElvTable("private")
	local general = type(private) == "table" and private.general
	local minimap = type(general) == "table" and general.minimap
	return not (type(minimap) == "table" and minimap.enable == false)
end

-- Auctionator's vendor price line in the tooltips (on unless saved off; its old and new names).
local function AuctionatorVendorLine()
	local config = _G.AUCTIONATOR_CONFIG
	if type(config) ~= "table" then return true end
	if config.vendor_tooltips == false or config.VENDOR_TOOLTIPS == false then return false end
	return true
end

-- Prat: a switch of one of its modules for this character's profile (off unless saved on).
local function Prat(module, key)
	local saved = _G.Prat3DB
	local spaces = type(saved) == "table" and saved.namespaces
	local profile = type(spaces) == "table" and AceProfile(spaces[module])
	return type(profile) == "table" and profile[key] == true
end

-- Questie: its quest tracker (its saved profile, else its default: shown).
local function QuestieTracker()
	local profile = AceProfile(_G.QuestieConfig)
	return not (type(profile) == "table" and profile.trackerEnabled == false)
end

-- BetterBlizzFrames (its switches, for the whole account): its dark mode on the unit frames, its class colours, its
-- textures (off unless saved on).
local function BetterBlizzLook()
	local saved = _G.BetterBlizzFramesDB
	if type(saved) ~= "table" then return false end
	if saved.darkModeUi == true and saved.darkModeUnitFrames ~= false then return true end
	return saved.classColorFrames == true or saved.changeUnitFrameHealthbarTexture == true or saved.retailTextures == true
end

-- Wanderer's jobs, and who may do them instead: { addon (its folder), name (as shown), on() (does it now;
-- none: always while loaded) }. text: the option's line when only part of the job is left (the others say
-- "Done by"). of: the extension whose job it is (told only while it is there).
local OTHERS = {
	-- The conversations shown in their own windows.
	scenes = { { addon = "DialogueUI", name = "Dialogue UI" }, { addon = "Immersion", name = "Immersion" } },
	-- Books and letters in their own window.
	reader = {
		{ addon = "DialogueUI", name = "Dialogue UI", on = function()
			local saved = _G.DialogueUI_DB
			return not (type(saved) == "table" and saved.BookUIEnabled == false)
		end },
	},
	questAuto = {
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "questAccept", "questTurnIn", "questGossip") end },
		{ addon = "Wowdee", name = WOWDEE, on = function() return WowdeeAny("autoAccept", "autoTurnIn") end },
		{ addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("AutomateQuests") },
	},
	skipGossip = {
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "gossipAuto") end },
		{ addon = "Wowdee", name = WOWDEE, on = function() return WowdeeAny("autoGossip") end },
		{ addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("AutomateGossip") },
	},
	repair = {
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "autoRepair") end },
		{ addon = "Wowdee", name = WOWDEE, on = function() return WowdeeAny("autoRepair") end },
		{ addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("AutoRepairGear") },
		-- (ElvUI repairs by itself unless told "none", its default)
		{ addon = ELVUI, name = "ElvUI", on = function()
			local repair = ElvValue("general", "autoRepair")
			return repair ~= nil and repair ~= "NONE"
		end },
	},
	sellJunk = {
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "sellJunk") end },
		{ addon = "Wowdee", name = WOWDEE, on = function() return WowdeeAny("autoSellJunk") end },
		{ addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("AutoSellJunk") },
		{ addon = ELVUI, name = "ElvUI", on = function() return ElvValue("bags", "vendorGrays", "enable") == true end },
		{ addon = "Scrap", name = "Scrap" },
		{ addon = "Peddler", name = "Peddler" },
		{ addon = "Vendor", name = "Vendor" },
		{ addon = "Dejunk", name = "Dejunk" },
	},
	-- An item's sell price in its tooltip.
	sellPrice = { { addon = "Auctionator", name = "Auctionator", on = AuctionatorVendorLine } },
	-- The away ambiance: ElvUI's AFK screen turns the camera and hides the interface itself (on unless saved off).
	away = { { addon = ELVUI, name = "ElvUI", on = function() return ElvSetting("general", "afk") end } },
	-- The minimap's look and its place.
	minimapLook = {
		{ addon = ELVUI, name = "ElvUI", on = ElvMinimap },
		{ addon = "SexyMap", name = "SexyMap" },
		{ addon = "BasicMinimap", name = "BasicMinimap" },
		{ addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("SquareMinimap") },
	},
	-- The minimap's buttons gathered in a drawer.
	minimapButtons = {
		{ addon = "MinimapButtonButton", name = "MinimapButtonButton" },
		{ addon = "MBB", name = "MBB" },
		{ addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("CombineAddonButtons") },
	},
	fastLoot = {
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "fastLoot") end },
		{ addon = "Wowdee", name = WOWDEE, on = function() return WowdeeAny("autoFastLoot") end },
		{ addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("FasterLooting") },
	},
	-- The game's red messages kept quiet.
	errors = { { addon = LEATRIX_ADDON, name = LEATRIX, on = LeatrixOn("HideErrorMessages") } },
	-- The nameplates drawn by another addon: Wanderer neither turns them on nor touches them.
	nameplates = {
		{ addon = ELVUI, name = "ElvUI", on = ElvOn("nameplates") },
		{ addon = "Plater", name = "Plater" },
		{ addon = "TidyPlates_ThreatPlates", name = "Threat Plates" },
		{ addon = "Kui_Nameplates", name = "KuiNameplates" },
	},
	-- The camera's settings (the action camera).
	camera = { { addon = "DynamicCam", name = "DynamicCam" } },
	-- Better or worse for you, on the items and in the bags.
	upgradeArrows = { { addon = "Pawn", name = "Pawn" } },
	-- The game's tooltips drawn by another addon: their opacity is left alone while they show.
	tooltip = {
		{ addon = ELVUI, name = "ElvUI", on = ElvOn("tooltip") },
		{ addon = "TipTac", name = "TipTac" },
	},
	-- The bags (Wanderer Bags).
	bags = {
		{ addon = "Baganator", name = "Baganator" },
		{ addon = "Bagnon", name = "Bagnon" },
		{ addon = "AdiBags", name = "AdiBags" },
		{ addon = "ArkInventory", name = "ArkInventory" },
		{ addon = ELVUI, name = "ElvUI", on = ElvOn("bags") },
		of = "WandererBags",
	},
	-- The auction house's window (Wanderer Auction).
	auctionWindow = {
		{ addon = "Auctionator", name = "Auctionator" },
		{ addon = "TradeSkillMaster", name = "TradeSkillMaster" },
		of = "WandererAuction",
	},
	-- The quests followed on the screen (Wanderer Quests).
	questTracker = { { addon = "Questie", name = "Questie", on = QuestieTracker }, { addon = "!KalielsTracker", name = "Kaliel's Tracker" },
		of = "WandererQuests" },
	-- The quest givers shown on the map.
	questGivers = { { addon = "Questie", name = "Questie" }, of = "WandererQuests" },
	-- The arrow to a place.
	arrow = { { addon = "TomTom", name = "TomTom" }, of = "WandererMaps" },
	-- The messages you sent, brought back with the arrows (Wanderer Chat).
	chatHistory = {
		{ addon = ELVUI, name = "ElvUI", on = ElvOn("chat") },
		{ addon = "Prat-3.0", name = "Prat", on = function() return Prat("Prat_History", "savehistory") end },
		of = "WandererChat",
	},
	-- The lines of each chat tab kept from one session to the next (Wanderer Chat).
	chatLog = {
		{ addon = ELVUI, name = "ElvUI", on = function() return ElvModule("chat") and ElvSetting("chat", "chatHistory") end },
		{ addon = "Chattynator", name = "Chattynator" },
		{ addon = "Prat-3.0", name = "Prat", on = function() return Prat("Prat_History", "scrollback") end },
		of = "WandererChat",
	},
	-- The private messages in their own window (Wanderer Chat).
	whispers = { { addon = "WIM", name = "WIM" }, of = "WandererChat" },
	-- The chat's look: its panel and its shorter channel names (Wanderer Chat).
	chatLook = {
		{ addon = ELVUI, name = "ElvUI", on = ElvOn("chat") },
		{ addon = "Prat-3.0", name = "Prat" },
		{ addon = "Chattynator", name = "Chattynator" },
		{ addon = "Glass", name = "Glass" },
		of = "WandererChat",
	},
	-- The mailbox's buttons (Wanderer Mail).
	mailButtons = {
		{ addon = "Postal", name = "Postal" },
		{ addon = "TradeSkillMaster", name = "TradeSkillMaster" },
		{ addon = "TradeSkillMaster_Mailing", name = "TradeSkillMaster" },
		of = "WandererMail",
	},
	-- Sets of gear put on in one click (Wanderer Outfits).
	gearSwap = { { addon = "ItemRack", name = "ItemRack" }, of = "WandererOutfits" },
	-- Buying what runs low (the provisions' "Fill up").
	restock = {
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "restock") and Naowh("qol", "restockBuy") end },
		{ addon = "Wowdee", name = WOWDEE, on = function() return WowdeeAny("autoRestock", "autoBuy") end },
	},
	-- The world map's place and size (its Map Window, unless EllesmereUI's own took it).
	mapSize = {
		{ addon = NAOWH_QOL, name = NAOWH, on = function()
			local ellesmere = _G.EllesmereUIDB
			return Naowh("qol", "enabled") and not (type(ellesmere) == "table" and ellesmere.shifterEnabled)
		end },
		text = "COMPAT_MAP_LEFT",
	},
	lootSparkle = {
		{ addon = "ForeverLootSparkles", name = "Forever Loot Sparkles", on = function()
			local saved = _G.ForeverLootSparklesDB
			return not (type(saved) == "table" and saved.enabled == false)
		end },
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("glimmer", "questSparkle") and Naowh("glimmer", "enabled") end },
	},
	-- The icons over herbs, veins and quest objects as you come near (the game's interact icons, Sparkles.lua).
	nodeSparkle = {
		{ addon = "ForeverLootSparkles", name = "Forever Loot Sparkles", on = function()
			local saved = _G.ForeverLootSparklesDB
			if type(saved) ~= "table" then return true end
			if saved.enabled == false then return false end
			return not (saved.sparkleOre == false and saved.sparkleHerbs == false and not saved.sparkleQuest)
		end },
		{ addon = "Lueur", name = "Lueur" },
		{ addon = NAOWH_QOL, name = NAOWH, on = function() return Naowh("glimmer", "enabled") end },
	},
	-- What you pick up, shown one line each at the side of the screen (LootFeed.lua).
	lootFeed = { { addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "lootFeed") end } },
	meterLook = { { addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "damageMeterSkin") end } },
	easyDestroy = { { addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "deleteConfirm") end } },
	-- The unit frames' look (UnitFrames.lua): left whole to the addons drawing their own frames, and to the ones
	-- restyling the game's while their look is on (BetterBlizzFrames: its dark mode, class colours or textures).
	unitFrames = {
		{ addon = ELVUI, name = "ElvUI", on = ElvOn("unitframe") },
		{ addon = "ShadowedUnitFrames", name = "Shadowed Unit Frames" },
		{ addon = "PitBull4", name = "PitBull 4" },
		{ addon = "UnhaltedUF", name = "Unhalted Unit Frames" },
		{ addon = "UnhaltedUnitFrames", name = "Unhalted Unit Frames" },
		{ addon = "MidnightSimpleUnitFrames", name = "Midnight Simple Unit Frames" },
		{ addon = "ZPerl", name = "Z-Perl" },
		{ addon = "XPerl", name = "X-Perl" },
		{ addon = "DragonflightUI", name = "Dragonflight UI" },
		{ addon = "BetterBlizzFrames", name = "BetterBlizzFrames", on = BetterBlizzLook },
		{ addon = "EasyFrames", name = "Easy Frames" },
		{ addon = "HealthBarColor", name = "HealthBarColor" },
	},
	-- The game's group frames, hidden by the addons drawing their own.
	unitFramesGroup = {
		{ addon = "Cell", name = "Cell" },
		{ addon = "Grid2", name = "Grid2" },
		{ addon = "VuhDo", name = "VuhDo" },
	},
	-- The cast bars, drawn by another addon.
	unitFramesCasts = { { addon = "Quartz", name = "Quartz" } },
	-- The damage left by your damage over time, on the target's health.
	dots = { { addon = "DoesItDie", name = "DoesItDie" } },
	-- What your other characters carry, on the items' tooltips (Wanderer Bags).
	altCounts = { { addon = NAOWH_QOL, name = NAOWH, on = function() return NaowhAny("qol", "altCounts") end }, of = "WandererBags" },
}
-- The game's quest tracker dressed (TrackerLook.lua, Clean.lua): put away and drawn anew by Kaliel's Tracker.
OTHERS.trackerLook = { { addon = "!KalielsTracker", name = "Kaliel's Tracker" } }
-- (the scene asks for the books by that name)
OTHERS.books = OTHERS.reader
ns.COMPAT = OTHERS

-- Wanderer's jobs an extension of the family may do in its place (its spec.takes, see RegisterExtension):
-- text, the option's line when only part of the job goes to it.
local FAMILY = { trainerWindow = {}, flightCard = { text = "COMPAT_FLIGHT_CARD_LEFT" }, trackerLook = {} }
for job, entry in pairs(FAMILY) do OTHERS[job] = OTHERS[job] or { text = entry.text } end

-- The extension of the family doing a job now (its spec), or nil. Its callback is a settings read, pcalled.
function ns.FamilyTaker(feature)
	for _, extension in ipairs(ns.EXTENSIONS or {}) do
		local takes = type(extension.takes) == "table" and extension.takes[feature]
		if type(takes) == "function" then
			local ok, on = pcall(takes)
			if ok and on then return extension end
		end
	end
	return nil
end

-- The order the jobs are told in (of: told only while that extension, whose job it is, is there).
local ORDER = { "scenes", "reader", "questAuto", "skipGossip", "repair", "sellJunk", "sellPrice", "fastLoot", "restock", "mapSize",
	"away", "minimapLook", "minimapButtons",
	"lootFeed", "lootSparkle", "nodeSparkle", "meterLook", "unitFrames", "unitFramesGroup", "unitFramesCasts", "easyDestroy", "dots", "errors", "nameplates", "camera", "upgradeArrows", "tooltip",
	"altCounts", "bags", "auctionWindow", "questTracker", "questGivers", "arrow", "chatHistory", "chatLog", "chatLook", "whispers", "mailButtons", "gearSwap",
	"trainerWindow", "flightCard", "trackerLook" }

-- The other addon doing this job now (its name as shown), or nil: Wanderer's to do. An extension of the
-- family taking it is asked first.
function ns.Yields(feature)
	local taker = ns.FamilyTaker(feature)
	if taker then return taker.title or taker.addon end
	for _, other in ipairs(OTHERS[feature] or {}) do
		if Loaded(other.addon) then
			local ok, on = true, true
			if other.on then ok, on = pcall(other.on) end
			if ok and on then return other.name end
		end
	end
	return nil
end

-- The muted line of an option whose job is left to another addon, or nil.
function ns.YieldText(feature)
	local name = ns.Yields(feature)
	if not name then return nil end
	return L[(OTHERS[feature] and OTHERS[feature].text) or "COMPAT_DONE_BY"]:format(name)
end

-- The settings page of the extension of the family doing a job now ("ext:training"), or nil.
function ns.YieldPage(feature)
	local taker = ns.FamilyTaker(feature)
	return taker and type(taker.key) == "string" and ("ext:" .. taker.key) or nil
end

-- Told once to each character (and again when it changes): what is left to whom, and that Wanderer Bags' "keep"
-- marks cannot hold back an item another addon sells.
local function Tell()
	if not (ns.db and ns.db.enabled and ns.root) then return end
	local byAddon, names = {}, {}
	for _, feature in ipairs(ORDER) do
		-- (a job an extension of the family does: its own page says so, nothing printed)
		local name = not FAMILY[feature] and ns.Yields(feature)
		local of = OTHERS[feature].of
		if name and (not of or Loaded(of)) then
			if not byAddon[name] then
				byAddon[name] = {}
				names[#names + 1] = name
			end
			table.insert(byAddon[name], L["COMPAT_JOB_" .. feature:upper()])
		end
	end
	local lines = {}
	for _, name in ipairs(names) do lines[#lines + 1] = L.MSG_COMPAT_LEFT:format(name, table.concat(byAddon[name], L.COMPAT_SEPARATOR)) end
	local sellJunk = ns.Yields("sellJunk")
	if sellJunk and Loaded("WandererBags") then lines[#lines + 1] = L.MSG_COMPAT_KEEP_MARKS:format(sellJunk) end
	local said = table.concat(lines, "\n")
	local mine = ns.Mine()
	if said == (mine.compatTold or "") then return end
	mine.compatTold = said ~= "" and said or nil
	for _, line in ipairs(lines) do ns.Print(line) end
end

-- Launchers for the bars of other addons ----------------------------------------------------------------------

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local published = false

local function Broker()
	local stub = _G.LibStub
	if not stub then return nil end
	local ok, broker = pcall(stub, "LibDataBroker-1.1", true)
	return ok and type(broker) == "table" and broker.NewDataObject and broker or nil
end

local function Publish(broker, name, object)
	pcall(broker.NewDataObject, broker, name, object)
end

-- Wanderer's menu, and each extension's window, as launchers (only once LibDataBroker is there).
function ns.PublishLaunchers()
	local broker = not published and Broker()
	if not broker then return false end
	published = true
	Publish(broker, "Wanderer", {
		type = "launcher", label = L.ADDON_TITLE, icon = ICON,
		OnClick = function(frame, button)
			if button == "RightButton" then ns.OpenOptions() else ns.ShowMenu(frame) end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(L.ADDON_TITLE)
			local r, g, b = ns.Skin.RGB("muted")
			tooltip:AddLine(L.MINIMAP_HINT, r, g, b, true)
		end,
	})
	local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	for _, extension in ipairs(ns.EXTENSIONS) do
		if type(extension.launcher) == "table" and type(extension.addon) == "string" then
			local icon = metadata and Clean(Safe(metadata, extension.addon, "IconTexture")) or ICON
			Publish(broker, extension.addon, {
				type = "launcher", label = extension.title or extension.addon, icon = icon,
				OnClick = function()
					local launcher = ns.LauncherOf(extension)
					if launcher then launcher.open() else ns.OpenOptions() end
				end,
				OnTooltipShow = function(tooltip)
					local launcher = ns.LauncherOf(extension)
					tooltip:AddLine(extension.title or extension.addon)
					if not launcher then
						local r, g, b = ns.Skin.RGB("muted")
						tooltip:AddLine(L.COMPAT_LAUNCHER_OFF, r, g, b, true)
					elseif launcher.label ~= extension.title then tooltip:AddLine(launcher.label, 1, 1, 1) end
				end,
			})
		end
	end
	return true
end

-- What another addon sells or buys itself is left to it: the provisions offer nothing while one restocks.
function ns.InitCompat()
	if ns.AddBuyRule then ns.AddBuyRule(function() return ns.Yields("restock") ~= nil end) end
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("ADDON_LOADED")
	local loggedIn = false
	events:SetScript("OnEvent", function(self, event)
		-- (an addon loaded later may bring the launchers' library: offered then, every extension known by now)
		if event == "ADDON_LOADED" then
			if loggedIn and ns.PublishLaunchers() then self:UnregisterEvent("ADDON_LOADED") end
			return
		end
		loggedIn = true
		if ns.PublishLaunchers() then self:UnregisterEvent("ADDON_LOADED") end
		C_Timer.After(8, Tell)
	end)
end
