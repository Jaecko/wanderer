local _, ns = ...
local L = ns.L

-- Travel journal: what this character has lived, kept by Wanderer as you play.
-- A chronicle day by day, the places discovered, the characters met, the rares
-- defeated, the quests turned in by region and the fish caught (where, how many);
-- the first time each recipe is crafted is written in the chronicle too. Shown in a window drawn by the
-- shared engine: the character's portrait and story at the top, a tile per
-- kind (each opens its page), and the pages themselves below.
--
-- Everything the game remembers is shown too, as part of the same story: the
-- places explored on the maps (read once per session, a little at each
-- frame), the quests completed with their titles, the professions, the gold,
-- the level. The game keeps no trace of the characters met or the rares
-- defeated: those are noted from the first day on.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local WIDTH, HEIGHT = 660, 580
local PORTRAIT_SIZE = 58
local TILE_HEIGHT = 58
local TILE_GAP = 8
local ROW_HEIGHT, HEADER_HEIGHT = 34, 26
local ICON_SIZE = 24
local DATE_FORMAT, TIME_FORMAT = "%d/%m/%Y", "%H:%M"
local KINDS = { "places", "npcs", "rares", "quests", "fish", "crafts" }
local PAGES = { "chronicle", "places", "npcs", "rares", "quests", "fish" }
local CHRONICLE_MAX = 400 -- oldest entries leave first
local TOOLTIP_PLACES = 20
local GRID = 24 -- points per side read on each map
local POINTS_PER_FRAME = 400
local SCAN_DELAY = 5 -- seconds after entering the world
local QUESTS_STATISTIC = 98 -- the game's "Quests completed"
local DAY = 86400
local SKILL_TIERS = { 75, 150, 225, 300 }
local GOLD_TIERS = { 10000, 100000, 1000000, 10000000 } -- 1, 10, 100, 1000 gold
local SESSION_MIN = 20 * 60 -- shorter sessions are not worth a line
local REST_GAP = 6 * 3600 -- one night at the inn a while
local MOUNT_LEVEL = 30 -- without the mount list, a character this high surely had one
local WRITE_SOUNDS = { 567445, 567503, 567396 } -- the game's own quill, as in the quest log
local NOTICE_TIME = 4
-- What deserves a notice when written (meeting characters is too frequent).
local NOTICE_KINDS = { zone = true, sub = true, level = true, rare = true, quest = true, mount = true,
	instance = true, skill = true, gold = true, death = true, craft = true }
local LOAD_BATCH, LOAD_EVERY = 25, 0.4 -- quest titles asked to the game

local ICONS = {
	chronicle = "Interface\\Icons\\INV_Misc_Book_09",
	places = "Interface\\Icons\\INV_Misc_Map_01",
	npcs = "Interface\\Icons\\INV_Misc_Head_Human_01",
	rares = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	quests = "Interface\\Icons\\INV_Scroll_03",
	zone = "Interface\\Icons\\INV_Misc_Map_01",
	sub = "Interface\\Icons\\INV_Misc_Spyglass_02",
	level = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
	rare = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	quest = "Interface\\Icons\\INV_Scroll_03",
	npc = "Interface\\Icons\\INV_Misc_Head_Human_01",
	mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
	instance = "Interface\\Icons\\INV_Misc_Key_03",
	skill = "Interface\\Icons\\INV_Misc_Note_02",
	gold = "Interface\\Icons\\INV_Misc_Coin_02",
	death = "Interface\\Icons\\Ability_Creature_Cursed_02",
	rest = "Interface\\Icons\\Spell_Nature_Sleep",
	session = "Interface\\Icons\\INV_Misc_PocketWatch_02",
	-- Characters by what they offered when you met them.
	merchant = "Interface\\Icons\\INV_Misc_Coin_01",
	trainer = "Interface\\Icons\\INV_Misc_Book_11",
	flight = "Interface\\Icons\\Ability_Mount_Gryphon_01",
	banker = "Interface\\Icons\\INV_Misc_Bag_10",
	questgiver = "Interface\\Icons\\INV_Misc_Note_01",
	todo = "Interface\\Icons\\INV_Misc_Note_05",
	fish = "Interface\\Icons\\Trade_Fishing",
	craft = "Interface\\Icons\\Trade_BlackSmithing",
	photo = "Interface\\Icons\\Spell_Holy_MindVision",
}

-- What a character is, from the window they opened.
local ROLES = {
	MERCHANT_SHOW = "merchant", TRAINER_SHOW = "trainer", TAXIMAP_OPENED = "flight",
	BANKFRAME_OPENED = "banker", QUEST_GREETING = "questgiver", QUEST_DETAIL = "questgiver",
}

-- Data ---------------------------------------------------------------------------------

-- The earliest dated entry of an older journal: the day it started.
local function EarliestStamp(journal)
	local earliest = time()
	for _, entry in pairs(journal.places) do
		if entry.first > 0 and entry.first < earliest then earliest = entry.first end
	end
	for _, entry in pairs(journal.npcs) do
		if entry.first and entry.first < earliest then earliest = entry.first end
	end
	return earliest
end

-- This character's journal: { places, npcs, rares, quests, chronicle, since }.
local function Journal()
	local root = ns.root
	root.journal = root.journal or {}
	local key = ns.CharacterKey()
	local journal = root.journal[key] or {}
	root.journal[key] = journal
	for _, kind in ipairs(KINDS) do journal[kind] = journal[kind] or {} end
	journal.chronicle = journal.chronicle or {}
	journal.questZones = journal.questZones or {}
	journal.since = journal.since or EarliestStamp(journal)
	return journal
end

local Notice -- defined with the texts of the chronicle

-- A line of the chronicle: kind, name, zone, value. Texts are written when
-- shown, so they follow the game's language. quiet: no notice for it.
local function Chronicle(kind, name, zone, value, quiet)
	local chronicle = Journal().chronicle
	local entry = { t = time(), k = kind, n = name, z = zone, v = value }
	chronicle[#chronicle + 1] = entry
	while #chronicle > CHRONICLE_MAX do table.remove(chronicle, 1) end
	if ns.RefreshJournalWindow then ns.RefreshJournalWindow() end
	if not quiet and Notice then Notice(entry) end
end

-- A line written by another part of the journal (the reminders): no notice.
function ns.JournalNote(kind, name)
	if not (ns.db and ns.db.enabled and ns.db.journal.enabled) then return end
	Chronicle(kind, name, nil, nil, true)
end

local function Zone()
	return Clean(Safe(GetRealZoneText)) or Clean(Safe(GetZoneText)) or "?"
end

local session = { places = 0, quests = 0 } -- this play session, for its line at the end

-- live: a place reached while playing. No notice before the places already
-- explored are known (they would all look new), nor on arriving in the world.
local function NotePlace(live)
	local zone, sub = Zone(), Clean(Safe(GetSubZoneText))
	local journal = Journal()
	local quiet = not (live and journal.scanned)
	local entry = journal.places[zone]
	if not entry then
		entry = { first = time(), subzones = {} }
		journal.places[zone] = entry
		Chronicle("zone", zone, nil, nil, quiet)
		session.places = session.places + 1
	end
	if sub and sub ~= zone and not entry.subzones[sub] then
		entry.subzones[sub] = time()
		Chronicle("sub", sub, zone, nil, quiet)
		session.places = session.places + 1
	end
end

-- The character you are talking to, and what they offer.
local function NoteCharacter(event)
	local npc = U.NpcID(Safe(UnitGUID, "npc"))
	local name = Clean(Safe(UnitName, "npc"))
	if not (npc and name) then return end
	local npcs = Journal().npcs
	local entry = npcs[npc]
	if not entry then
		entry = { name = name, zone = Zone(), first = time() }
		npcs[npc] = entry
		Chronicle("npc", name, entry.zone, nil, true)
	end
	entry.role = entry.role or ROLES[event]
end

-- Called by World when a rare is defeated.
function ns.JournalRare(npc, name)
	if not (ns.db and ns.db.enabled and ns.db.journal.enabled) then return end
	if not (npc and Clean(name)) then return end
	local rares = Journal().rares
	local entry = rares[npc] or { kills = 0 }
	entry.name, entry.zone, entry.last = name, Zone(), time()
	entry.kills = (entry.kills or 1) + 1
	rares[npc] = entry
	Chronicle("rare", name, entry.zone)
end

-- Quest titles, shared by every character (a title is the same for all).
local function TitleCache()
	ns.root.questTitles = ns.root.questTitles or {}
	return ns.root.questTitles
end

local function QuestTitle(questID)
	local cache = TitleCache()
	if cache[questID] then return cache[questID] end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Clean(Safe(C_QuestLog.GetTitleForQuestID, questID))
	if title then cache[questID] = title end
	return title
end

local function NoteQuest(questID)
	session.quests = session.quests + 1
	local journal = Journal()
	local zone = Zone()
	journal.quests[zone] = (journal.quests[zone] or 0) + 1
	if questID then journal.questZones[questID] = zone end
	Chronicle("quest", questID and QuestTitle(questID), zone)
end

local function NoteLevel(level)
	level = Clean(level)
	if level then Chronicle("level", nil, Zone(), level) end
end

-- Milestones -------------------------------------------------------------------------
-- Known on the first look without a line (a character may have lived long
-- before Wanderer); after that, each new step is a line of the chronicle.

local function Tier(value, tiers)
	local reached = 0
	for index, tier in ipairs(tiers) do if value >= tier then reached = index end end
	return reached
end

local function HasMount()
	local journal = C_MountJournal
	if journal and journal.GetMountIDs and journal.GetMountInfoByID then
		for _, id in ipairs(Safe(journal.GetMountIDs) or {}) do
			if select(11, Safe(journal.GetMountInfoByID, id)) then return true end
		end
		return false
	end
	return (Clean(Safe(UnitLevel, "player")) or 1) >= MOUNT_LEVEL
end

local function Skills()
	local list = {}
	if not GetProfessions then return list end
	-- Up to five professions, with gaps (no first profession, but fishing).
	local indices = { Safe(GetProfessions) }
	for slot = 1, 5 do
		local index = indices[slot]
		if index then
			local name, _, rank = Safe(GetProfessionInfo, index)
			name, rank = Clean(name), Clean(rank)
			if name and rank then list[name] = rank end
		end
	end
	return list
end

-- The level the character had when the journal began: the first level the
-- chronicle saw minus one, or the current level.
local function FirstLevel(journal)
	local first
	for _, entry in ipairs(journal.chronicle) do
		if entry.k == "level" and entry.v and (not first or entry.v < first) then first = entry.v end
	end
	return first and first - 1 or Clean(Safe(UnitLevel, "player"))
end

-- What the character had already reached when the journal began: shown in the
-- chronicle with the rest, only without a date.
local function Initial(milestones, journal)
	local skills = {}
	for name, tier in pairs(milestones.skills) do skills[name] = tier end
	return { level = FirstLevel(journal), mount = milestones.mount, gold = milestones.gold, skills = skills }
end

local function Milestones()
	local journal = Journal()
	local milestones = journal.milestones
	if not milestones then
		local skills = {}
		for name, rank in pairs(Skills()) do skills[name] = Tier(rank, SKILL_TIERS) end
		milestones = { mount = HasMount(), gold = Tier(Clean(Safe(GetMoney)) or 0, GOLD_TIERS),
			skills = skills, instances = {} }
		journal.milestones = milestones
	end
	milestones.initial = milestones.initial or Initial(milestones, journal)
	return milestones
end

local function NoteMount()
	if not Clean(Safe(IsMounted)) then return end
	local milestones = Milestones()
	if milestones.mount then return end
	milestones.mount = true
	Chronicle("mount", nil, Zone())
end

local function NoteInstance()
	local inside, kind = Safe(IsInInstance)
	kind = Clean(kind)
	if not (Clean(inside) and (kind == "party" or kind == "raid")) then return end
	local name = Clean(Safe(GetInstanceInfo))
	local milestones = Milestones()
	if not name or milestones.instances[name] then return end
	milestones.instances[name] = time()
	Chronicle("instance", name)
end

local function NoteSkills()
	local milestones = Milestones()
	for name, rank in pairs(Skills()) do
		local tier = Tier(rank, SKILL_TIERS)
		local known = milestones.skills[name]
		if known == nil then
			milestones.skills[name] = tier -- a profession just learnt: from here on
		elseif tier > known then
			milestones.skills[name] = tier
			Chronicle("skill", name, Zone(), SKILL_TIERS[tier])
		end
	end
end

-- A fish caught: its species kept (where first, how many); the first one of
-- each species written in the chronicle (the fishing notice tells it).
-- Returns true for a new species.
function ns.JournalCatch(name, icon)
	if not (ns.db and ns.db.enabled and ns.db.journal.enabled) then return end
	local fish = Journal().fish
	local entry = fish[name]
	local new = entry == nil
	if new then
		entry = { name = name, icon = icon, first = time(), zone = Zone(), count = 0 }
		fish[name] = entry
		Chronicle("fish", name, entry.zone, nil, true)
	end
	entry.count = entry.count + 1
	return new
end

-- Something crafted: the first time of each recipe is written, with its notice.
function ns.JournalCraft(name)
	local crafts = Journal().crafts
	if crafts[name] then
		crafts[name].count = crafts[name].count + 1
		return
	end
	crafts[name] = { first = time(), count = 1 }
	Chronicle("craft", name, Zone())
end

local function NoteMoney()
	local milestones = Milestones()
	local tier = Tier(Clean(Safe(GetMoney)) or 0, GOLD_TIERS)
	if tier > milestones.gold then
		milestones.gold = tier
		Chronicle("gold", nil, Zone(), GOLD_TIERS[tier])
	end
end

local function NoteDeath()
	if not ns.db.journal.deaths then return end
	Chronicle("death", nil, Zone(), Clean(Safe(UnitLevel, "player")))
end

-- At the end of the play: a night at the inn, and what the session brought.
local function NoteLogout()
	local journal = Journal()
	if Clean(Safe(IsResting)) and time() - (journal.lastRest or 0) > REST_GAP then
		journal.lastRest = time()
		Chronicle("rest", Clean(Safe(GetSubZoneText)) or Zone(), Zone())
	end
	local played = time() - (session.start or time())
	local level = Clean(Safe(UnitLevel, "player"))
	local written
	if played >= SESSION_MIN and (session.places > 0 or session.quests > 0 or (level and level ~= session.level)) then
		local chronicle = journal.chronicle
		written = { t = time(), k = "session", z = Zone(),
			d = { m = math.floor(played / 60), p = session.places, q = session.quests, a = session.level, b = level } }
		chronicle[#chronicle + 1] = written
		while #chronicle > CHRONICLE_MAX do table.remove(chronicle, 1) end
	end
	-- A /reload also ends here: kept, the session goes on after it.
	journal.lastSession = { t = time(), start = session.start, places = session.places, quests = session.quests,
		level = session.level, written = written and written.t or nil }
end

-- Back within a moment of the end: a /reload, the same play session.
local RELOAD_GAP = 120
local function ResumeSession()
	local journal = Journal()
	local last = journal.lastSession
	journal.lastSession = nil
	if not (last and last.start and time() - (last.t or 0) < RELOAD_GAP) then return end
	session.start, session.level = last.start, last.level or session.level
	session.places, session.quests = last.places or 0, last.quests or 0
	local chronicle = journal.chronicle
	local entry = chronicle[#chronicle]
	if last.written and entry and entry.k == "session" and entry.t == last.written then chronicle[#chronicle] = nil end
end

-- Date of an entry; 0: known from the game's memory, without a date.
local function Day(stamp)
	if stamp and stamp > 0 then return date(DATE_FORMAT, stamp) end
	return ""
end

-- Quests completed according to the game (all of this character's life).
local function QuestsCompleted()
	return tonumber(Clean(Safe(GetStatistic, QUESTS_STATISTIC)) or "")
end

-- Every quest completed, as the game remembers it; titles the game has not
-- loaded yet are asked for a few at a time while the journal shows them.
local loading = { tried = {} }

local function CompletedQuests()
	local ids = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and Safe(C_QuestLog.GetAllCompletedQuestIDs)
	return type(ids) == "table" and ids or {}
end

local function LoadNext()
	local queue = loading.queue
	for _ = 1, LOAD_BATCH do
		local id = queue and table.remove(queue)
		if not id then
			loading.queue = nil
			if ns.RefreshJournalWindow then ns.RefreshJournalWindow() end
			return
		end
		loading.tried[id] = true
		Safe(C_QuestLog.RequestLoadQuestByID, id)
	end
	C_Timer.After(LOAD_EVERY, LoadNext)
end

local function LoadTitles(ids)
	if loading.queue or not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
	local queue = {}
	for _, id in ipairs(ids) do
		if not QuestTitle(id) and not loading.tried[id] then queue[#queue + 1] = id end
	end
	if queue[1] then
		loading.queue = queue
		C_Timer.After(0, LoadNext)
	end
end

-- A title arrived: kept, and the open page follows (not at every one).
local refreshSoon = false
local function OnQuestLoaded(questID, success)
	if not (success and QuestTitle(questID)) or refreshSoon then return end
	refreshSoon = true
	C_Timer.After(0.5, function()
		refreshSoon = false
		if ns.RefreshJournalWindow then ns.RefreshJournalWindow() end
	end)
end

-- Places already explored ---------------------------------------------------------------

local scan -- { maps, map, point } while reading the maps

local function ZoneMaps()
	local maps = C_Map
	local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	if not (maps and maps.GetMapChildrenInfo) then return {} end
	local list = Safe(maps.GetMapChildrenInfo, 946, zone, true) -- the whole world
	if not (list and list[1]) then
		local world = Clean(Safe(maps.GetFallbackWorldMapID))
		list = world and Safe(maps.GetMapChildrenInfo, world, zone, true)
	end
	return list or {}
end

local function NoteExplored(zone, area)
	local places = Journal().places
	local entry = places[zone] or { first = 0, subzones = {} }
	places[zone] = entry
	if area and area ~= zone and not entry.subzones[area] then entry.subzones[area] = 0 end
end

-- Reads a part of the maps; returns true when every map is read.
local function ScanStep()
	local explore = C_MapExplorationInfo
	if not (explore and explore.GetExploredAreaIDsAtPosition and CreateVector2D) then return true end
	local budget = POINTS_PER_FRAME
	while budget > 0 do
		local map = scan.maps[scan.map]
		if not map then return true end
		local index = scan.point
		local x, y = index % GRID, math.floor(index / GRID)
		local areas = Safe(explore.GetExploredAreaIDsAtPosition, map.mapID, CreateVector2D((x + 0.5) / GRID, (y + 0.5) / GRID))
		for _, area in ipairs(type(areas) == "table" and areas or {}) do
			local name = Clean(Safe(C_Map.GetAreaInfo, area))
			if name and Clean(map.name) then NoteExplored(map.name, name) end
		end
		scan.point = index + 1
		if scan.point >= GRID * GRID then
			scan.map, scan.point = scan.map + 1, 0
			-- An open journal follows the reading, map by map.
			if ns.RefreshJournalWindow then ns.RefreshJournalWindow() end
		end
		budget = budget - 1
	end
	return false
end

local scanner = CreateFrame("Frame")
scanner:Hide()
scanner:SetScript("OnUpdate", function(self)
	-- Never during a fight: the reading waits.
	if InCombatLockdown() then return end
	if ScanStep() then
		scan = nil
		Journal().scanned = time()
		self:Hide()
		if ns.RefreshJournalWindow then ns.RefreshJournalWindow() end
	end
end)

-- Reads the maps for the places explored (once per session, or on demand).
function ns.ScanJournal()
	if scan or not (ns.db and ns.db.enabled and ns.db.journal.enabled) then return end
	scan = { maps = ZoneMaps(), map = 1, point = 0 }
	scanner:Show()
end

-- Pages --------------------------------------------------------------------------------
-- Each page is a list of rows: { icon, title, subtitle, right, sort, bar, tip }
-- or a day header: { header = text }.

local function CountSubzones(entry)
	local count, latest, latestName = 0, 0, nil
	for name, stamp in pairs(entry.subzones) do
		count = count + 1
		if stamp > latest then latest, latestName = stamp, name end
	end
	return count, latestName
end

local function PlacesTip(zone, entry)
	return function(tooltip)
		tooltip:AddLine(zone)
		local names = {}
		for name in pairs(entry.subzones) do names[#names + 1] = name end
		table.sort(names)
		for index = 1, math.min(#names, TOOLTIP_PLACES) do tooltip:AddLine(names[index], 0.85, 0.85, 0.85) end
		if #names > TOOLTIP_PLACES then
			tooltip:AddLine(L.JOURNAL_MORE:format(#names - TOOLTIP_PLACES), 0.6, 0.6, 0.6)
		end
	end
end

local EVENT_TEXT = {
	todo = function(entry) return L.JOURNAL_EVENT_TODO:format(entry.n or "?") end,
	fish = function(entry) return L.JOURNAL_EVENT_FISH:format(entry.n or "?") end,
	craft = function(entry) return L.JOURNAL_EVENT_CRAFT:format(entry.n or "?") end,
	photo = function(entry) return L.JOURNAL_EVENT_PHOTO:format(entry.n or "?") end,
	zone = function(entry) return L.JOURNAL_EVENT_ZONE:format(entry.n or "?") end,
	sub = function(entry) return L.JOURNAL_EVENT_SUB:format(entry.n or "?") end,
	level = function(entry) return L.JOURNAL_EVENT_LEVEL:format(entry.v or 0) end,
	rare = function(entry) return L.JOURNAL_EVENT_RARE:format(entry.n or "?") end,
	npc = function(entry) return L.JOURNAL_EVENT_NPC:format(entry.n or "?") end,
	quest = function(entry)
		return entry.n and L.JOURNAL_EVENT_QUEST:format(entry.n) or L.JOURNAL_EVENT_QUEST_UNKNOWN
	end,
	mount = function() return L.JOURNAL_EVENT_MOUNT end,
	instance = function(entry) return L.JOURNAL_EVENT_INSTANCE:format(entry.n or "?") end,
	skill = function(entry) return L.JOURNAL_EVENT_SKILL:format(entry.v or 0, entry.n or "?") end,
	gold = function(entry) return L.JOURNAL_EVENT_GOLD:format(U.Coins(entry.v or 0)) end,
	death = function(entry) return L.JOURNAL_EVENT_DEATH:format(entry.v or 0) end,
	rest = function(entry) return L.JOURNAL_EVENT_REST:format(entry.n or "?") end,
	session = function(entry)
		local d = entry.d or {}
		local text = L.JOURNAL_EVENT_SESSION:format(Safe(SecondsToTime, (d.m or 0) * 60, true) or "", d.p or 0, d.q or 0)
		if d.a and d.b and d.b > d.a then text = text .. L.JOURNAL_EVENT_SESSION_LEVEL:format(d.a, d.b) end
		return text
	end,
}

-- Something written in the journal: a short notice, and the quill on paper.
Notice = function(entry)
	local db = ns.db.journal
	if not NOTICE_KINDS[entry.k] then return end
	local function Quill()
		if db.sound and PlaySoundFile then pcall(PlaySoundFile, WRITE_SOUNDS[math.random(#WRITE_SOUNDS)], "SFX") end
	end
	if db.notices and ns.Toast then
		ns.Toast(EVENT_TEXT[entry.k](entry), L.JOURNAL_WRITTEN, { duration = NOTICE_TIME, onShow = Quill, corner = true })
	else
		Quill()
	end
end

-- Today's lines of the chronicle, newest first (the page shown while away).
function ns.JournalToday(max)
	local journal, today, lines = Journal(), date(DATE_FORMAT), {}
	for index = #journal.chronicle, 1, -1 do
		local entry = journal.chronicle[index]
		if date(DATE_FORMAT, entry.t) ~= today then break end
		local text = EVENT_TEXT[entry.k]
		if text then lines[#lines + 1] = { icon = ICONS[entry.k], text = text(entry), time = date(TIME_FORMAT, entry.t) } end
		if #lines >= (max or 8) then break end
	end
	return lines
end

-- What a day held: places, quests, catches, crafts ("Places 3 · Quests 12").
local DAY_COUNTS = { { "zone", "sub", key = "JOURNAL_DAY_PLACES" }, { "quest", key = "JOURNAL_DAY_QUESTS" },
	{ "fish", key = "JOURNAL_DAY_FISH" }, { "craft", key = "JOURNAL_DAY_CRAFTS" } }

local function DaySummaries(chronicle)
	local days = {}
	for _, entry in ipairs(chronicle) do
		local day = date(DATE_FORMAT, entry.t)
		days[day] = days[day] or {}
		days[day][entry.k] = (days[day][entry.k] or 0) + 1
	end
	local summaries = {}
	for day, kinds in pairs(days) do
		local parts = {}
		for _, count in ipairs(DAY_COUNTS) do
			local total = 0
			for _, kind in ipairs(count) do total = total + (kinds[kind] or 0) end
			if total > 0 then parts[#parts + 1] = L[count.key]:format(total) end
		end
		summaries[day] = parts[1] and table.concat(parts, "  ·  ") or nil
	end
	return summaries
end

local function ChronicleRows(journal)
	local rows, lastDay = {}, nil
	local chronicle = journal.chronicle
	local summaries = DaySummaries(chronicle)
	for index = #chronicle, 1, -1 do
		local entry = chronicle[index]
		local text = EVENT_TEXT[entry.k]
		if text then
			local day = date(DATE_FORMAT, entry.t)
			if day ~= lastDay then
				rows[#rows + 1] = { header = summaries[day] and (day .. "    |cffa8a8a8" .. summaries[day] .. "|r") or day }
				lastDay = day
			end
			rows[#rows + 1] = { ICONS[entry.k], text(entry), entry.z or "", date(TIME_FORMAT, entry.t),
				highlight = entry.k == "level" or entry.k == "rare" or entry.k == "instance" or entry.k == "mount" }
		end
	end
	-- Earlier in the journey: what the game remembers, without a date.
	local earlier = {}
	local initial = journal.milestones and journal.milestones.initial
	if initial then
		if initial.level and initial.level > 1 then
			earlier[#earlier + 1] = { ICONS.level, L.JOURNAL_EVENT_LEVEL:format(initial.level), "", "", highlight = true }
		end
		if initial.mount then earlier[#earlier + 1] = { ICONS.mount, L.JOURNAL_EVENT_MOUNT, "", "", highlight = true } end
		local skills = {}
		for name, tier in pairs(initial.skills or {}) do
			if tier > 0 then skills[#skills + 1] = { ICONS.skill, L.JOURNAL_EVENT_SKILL:format(SKILL_TIERS[tier], name), "", "" } end
		end
		table.sort(skills, function(a, b) return a[2] < b[2] end)
		for _, row in ipairs(skills) do earlier[#earlier + 1] = row end
		if (initial.gold or 0) > 0 then
			earlier[#earlier + 1] = { ICONS.gold, L.JOURNAL_EVENT_GOLD:format(U.Coins(GOLD_TIERS[initial.gold])), "", "" }
		end
	end
	local known = 0
	for _, count in pairs(journal.quests) do known = known + count end
	local quests = (QuestsCompleted() or 0) - known
	if quests > 0 then earlier[#earlier + 1] = { ICONS.quest, L.JOURNAL_EVENT_QUESTS_DONE:format(quests), "", "" } end
	local regions = {}
	for zone, entry in pairs(journal.places) do
		if entry.first == 0 then
			regions[#regions + 1] = { ICONS.zone, L.JOURNAL_EVENT_EXPLORED:format(zone),
				L.JOURNAL_PLACES_COUNT:format((CountSubzones(entry))), "", tip = PlacesTip(zone, entry) }
		end
	end
	table.sort(regions, function(a, b) return a[2] < b[2] end)
	for _, row in ipairs(regions) do earlier[#earlier + 1] = row end
	if earlier[1] then
		rows[#rows + 1] = { header = L.JOURNAL_EARLIER }
		for _, row in ipairs(earlier) do rows[#rows + 1] = row end
	end
	return rows
end

-- Newest first; what has no date last, by name.
local function SortRows(rows)
	table.sort(rows, function(a, b)
		if a.sort ~= b.sort then return a.sort > b.sort end
		return a[2] < b[2]
	end)
	return rows
end

local function Rows(page)
	local journal, rows = Journal(), {}
	if page == "chronicle" then return ChronicleRows(journal) end
	if page == "places" then
		for zone, entry in pairs(journal.places) do
			local count, latest = CountSubzones(entry)
			local subtitle = L.JOURNAL_PLACES_COUNT:format(count)
			if latest and entry.subzones[latest] > 0 then subtitle = subtitle .. "  ·  " .. L.JOURNAL_LATEST:format(latest) end
			rows[#rows + 1] = { ICONS.places, zone, subtitle, Day(entry.first), sort = entry.first, tip = PlacesTip(zone, entry) }
		end
	elseif page == "npcs" then
		for _, entry in pairs(journal.npcs) do
			local subtitle = entry.zone
			if entry.role then subtitle = L["JOURNAL_ROLE_" .. entry.role:upper()] .. "  ·  " .. subtitle end
			rows[#rows + 1] = { ICONS[entry.role] or ICONS.npcs, entry.name, subtitle, Day(entry.first), sort = entry.first }
		end
	elseif page == "fish" then
		for _, entry in pairs(journal.fish) do
			rows[#rows + 1] = { entry.icon or ICONS.fish, entry.name, (entry.zone or "") .. "  ·  " .. L.JOURNAL_FISH_COUNT:format(entry.count),
				Day(entry.first), sort = entry.first }
		end
	elseif page == "rares" then
		for _, entry in pairs(journal.rares) do
			local subtitle = entry.zone
			if (entry.kills or 1) > 1 then subtitle = subtitle .. "  ·  " .. L.JOURNAL_KILLS:format(entry.kills) end
			rows[#rows + 1] = { ICONS.rares, entry.name, subtitle, Day(entry.last), sort = entry.last, highlight = true }
		end
	else
		local known, most = 0, 1
		for _, count in pairs(journal.quests) do
			known = known + count
			most = math.max(most, count)
		end
		local total = math.max(known, QuestsCompleted() or 0, 1)
		for zone, count in pairs(journal.quests) do
			rows[#rows + 1] = { ICONS.quests, zone, L.JOURNAL_SHARE:format(math.floor(count / total * 100 + 0.5)),
				L.JOURNAL_QUEST_COUNT:format(count), sort = count, bar = count / most }
		end
		SortRows(rows)
		-- Then every quest completed, by title (with its region when known).
		local ids = CompletedQuests()
		LoadTitles(ids)
		local list = {}
		for _, id in ipairs(ids) do
			local title = QuestTitle(id)
			if title then list[#list + 1] = { ICONS.quest, title, journal.questZones[id] or "", "" } end
		end
		table.sort(list, function(a, b) return a[2] < b[2] end)
		if list[1] then
			rows[#rows + 1] = { header = L.JOURNAL_QUESTS_ALL:format(#list) }
			for _, row in ipairs(list) do rows[#rows + 1] = row end
		end
		return rows
	end
	return SortRows(rows)
end

local function Count(page)
	local journal = Journal()
	if page == "chronicle" then
		return math.floor((time() - journal.since) / DAY) + 1
	end
	local count = 0
	for _, value in pairs(journal[page]) do
		count = count + (page == "quests" and value or 1)
	end
	if page == "quests" then count = math.max(count, QuestsCompleted() or 0) end
	return count
end

-- Window -------------------------------------------------------------------------------

local window, scroll, content, footer
local tiles, rowPool = {}, {}
local layout = {} -- every row of the page: { data, y, height, odd }
local listWidth = WIDTH - 70
local currentPage = "chronicle"

local function Icon(parent, size)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetSize(size, size)
	if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	local border = parent:CreateTexture(nil, "BORDER")
	border:SetColorTexture(0, 0, 0, 0.8)
	border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	icon.border = border
	return icon
end

local function Row(index)
	local row = rowPool[index]
	if row then return row end
	row = CreateFrame("Frame", nil, content)
	row:EnableMouse(true)
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.bar = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetColorTexture(1, 0.82, 0, 0.1)
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.06)
	row.hover:Hide()
	row.icon = Icon(row, ICON_SIZE)
	row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.right = ns.Skin.CreateText(row, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	row.right:SetJustifyH("RIGHT")
	row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
	row.title = ns.Skin.CreateText(row, "GameTooltipText", 1, 1, 1)
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
	row.title:SetPoint("RIGHT", row.right, "LEFT", -10, 0)
	row.subtitle = ns.Skin.CreateText(row, "GameTooltipTextSmall", 0.68, 0.66, 0.6)
	row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.subtitle:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	-- Day headers: golden date with a thin rule.
	row.header = ns.Skin.CreateText(row, "GameTooltipText", 1, 0.82, 0)
	row.header:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 6)
	row.header:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetColorTexture(1, 0.82, 0, 0.22)
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 2)
	row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 2)
	-- Every text on one line, cut inside the row: nothing ever leaves the window.
	for _, text in ipairs({ row.title, row.subtitle, row.right, row.header }) do
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	row:SetScript("OnEnter", function(self)
		if self.isHeader then return end
		self.hover:Show()
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			self.tip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	rowPool[index] = row
	return row
end

local function ShowRow(row, data, odd, width)
	local isHeader = data.header ~= nil
	row.isHeader = isHeader
	row:SetHeight(isHeader and HEADER_HEIGHT or ROW_HEIGHT)
	row.header:SetShown(isHeader)
	row.rule:SetShown(isHeader)
	for _, part in ipairs({ row.icon, row.icon.border, row.title, row.subtitle, row.right }) do part:SetShown(not isHeader) end
	row.stripe:SetColorTexture(1, 1, 1, (odd and not isHeader) and 0.025 or 0)
	row.tip = data.tip
	if isHeader then
		row.header:SetText(data.header)
		row.bar:Hide()
		return
	end
	row.icon:SetTexture(data[1])
	row.title:SetText(data[2])
	row.title:SetTextColor(data.highlight and 1 or 0.95, data.highlight and 0.82 or 0.93, data.highlight and 0.4 or 0.88)
	row.subtitle:SetText(data[3])
	row.right:SetText(data[4])
	if data.bar then
		row.bar:SetWidth(math.max(1, (width - 2) * data.bar))
		row.bar:Show()
	else
		row.bar:Hide()
	end
end

local function FillTiles()
	for _, page in ipairs(PAGES) do
		local tile = tiles[page]
		local selected = page == currentPage
		tile.value:SetText(Count(page))
		tile.background:SetColorTexture(selected and 1 or 1, selected and 0.82 or 1, selected and 0 or 1, selected and 0.14 or 0.04)
		tile.line:SetShown(selected)
		tile.label:SetTextColor(selected and 1 or 0.75, selected and 0.82 or 0.75, selected and 0 or 0.75)
	end
end

-- Draws the rows in view (and a little around), reusing a few frames.
local function DrawVisible()
	local top = scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
	local height = scroll:GetHeight()
	if not height or height <= 0 then height = HEIGHT end
	local used = 0
	for _, item in ipairs(layout) do
		if item.y + item.height >= top - ROW_HEIGHT and item.y <= top + height + ROW_HEIGHT then
			used = used + 1
			local row = Row(used)
			ShowRow(row, item.data, item.odd, listWidth)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -item.y)
			row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -item.y)
			row:Show()
		end
	end
	for index = used + 1, #rowPool do rowPool[index]:Hide() end
end

local function Fill()
	local rows = Rows(currentPage)
	local width = scroll:GetWidth()
	listWidth = width and width > 0 and width or WIDTH - 70
	content:SetWidth(listWidth)
	wipe(layout)
	local y, odd = 0, false
	for _, data in ipairs(rows) do
		odd = data.header and false or not odd
		local height = data.header and HEADER_HEIGHT or ROW_HEIGHT
		layout[#layout + 1] = { data = data, y = y, height = height, odd = odd }
		y = y + height
	end
	content:SetHeight(math.max(y, 1))
	DrawVisible()
	window.empty:SetShown(not rows[1])
	window.pageTitle:SetText(L["JOURNAL_TAB_" .. currentPage:upper()])
	window.pageText:SetText(L["JOURNAL_PAGE_" .. currentPage:upper()])
	if scan then
		-- Reading the maps: how far it is.
		local total = math.max(#scan.maps, 1)
		footer:SetText(L.JOURNAL_SCANNING:format(math.floor((scan.map - 1) / total * 100)))
	elseif loading.queue and currentPage == "quests" then
		footer:SetText(L.JOURNAL_LOADING_QUESTS:format(#loading.queue))
	else
		footer:SetText(L.JOURNAL_FOOTER)
	end
	FillTiles()
end

-- The character: portrait, name in the class color, level, race and class.
local function FillHeader()
	SetPortraitTexture(window.portrait, "player")
	local _, classFile = Safe(UnitClass, "player")
	local color = Clean(classFile) and RAID_CLASS_COLORS[classFile]
	window.name:SetText(Clean(U.FullName("player")) or "")
	if color then window.name:SetTextColor(color.r, color.g, color.b) end
	local parts = { L.JOURNAL_LEVEL:format(Clean(Safe(UnitLevel, "player")) or 1) }
	parts[#parts + 1] = Clean(Safe(UnitRace, "player"))
	parts[#parts + 1] = Clean((Safe(UnitClass, "player")))
	window.identity:SetText(table.concat(parts, "  ·  "))
	window.since:SetText(L.JOURNAL_SINCE:format(date(DATE_FORMAT, Journal().since)) .. "  ·  " .. Zone())
end

local function CreateTile(page, index)
	local tile = CreateFrame("Button", nil, window)
	tile:SetHeight(TILE_HEIGHT)
	tile.index = index
	tile.background = tile:CreateTexture(nil, "BACKGROUND")
	tile.background:SetAllPoints()
	tile.hover = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
	tile.hover:SetAllPoints()
	tile.hover:SetColorTexture(1, 1, 1, 0.05)
	tile.hover:Hide()
	tile.line = tile:CreateTexture(nil, "OVERLAY")
	tile.line:SetColorTexture(1, 0.82, 0, 0.9)
	tile.line:SetHeight(2)
	tile.line:SetPoint("BOTTOMLEFT")
	tile.line:SetPoint("BOTTOMRIGHT")
	tile.icon = Icon(tile, 30)
	tile.icon:SetPoint("LEFT", tile, "LEFT", 10, 0)
	tile.icon:SetTexture(ICONS[page])
	tile.value = ns.Skin.CreateText(tile, "GameFontHighlightLarge", 1, 1, 1)
	tile.value:SetPoint("TOPLEFT", tile.icon, "TOPRIGHT", 9, 1)
	tile.value:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
	tile.label = ns.Skin.CreateText(tile, "GameTooltipTextSmall")
	tile.label:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -2)
	tile.label:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
	for _, text in ipairs({ tile.value, tile.label }) do
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	tile.label:SetText(L["JOURNAL_TILE_" .. page:upper()])
	tile:SetScript("OnClick", function()
		currentPage = page
		if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
		Fill()
	end)
	tile:SetScript("OnEnter", function(self)
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["JOURNAL_TAB_" .. page:upper()])
		GameTooltip:AddLine(L["JOURNAL_PAGE_" .. page:upper()], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	tile:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	tiles[page] = tile
end

local function LayoutTiles()
	local margin = ns.Skin.Margin() + 6
	local width = WIDTH - 2 * margin
	local tileWidth = math.floor((width - (#PAGES - 1) * TILE_GAP) / #PAGES)
	for _, page in ipairs(PAGES) do
		local tile = tiles[page]
		tile:SetWidth(tileWidth)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", window.headerRule, "BOTTOMLEFT", (tile.index - 1) * (tileWidth + TILE_GAP), -12)
	end
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererJournal", "DIALOG")
	ns.Skin.Sounds(window, "IG_SPELLBOOK_OPEN", "IG_SPELLBOOK_CLOSE") -- a book, as the game's
	window:SetSize(WIDTH, HEIGHT)
	local close = ns.Skin.Dress(window)
	local margin = ns.Skin.Margin() + 6

	-- Header: round portrait in a golden ring, the character's story.
	window.portrait = window:CreateTexture(nil, "ARTWORK")
	window.portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
	window.portrait:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	local ring = window:CreateTexture(nil, "BORDER")
	ring:SetSize(PORTRAIT_SIZE + 4, PORTRAIT_SIZE + 4)
	ring:SetPoint("CENTER", window.portrait, "CENTER")
	ring:SetTexture("Interface\\Buttons\\WHITE8X8")
	ring:SetVertexColor(1, 0.82, 0, 0.55)
	ns.Skin.RoundMask(window, window.portrait)
	ring:SetShown(ns.Skin.RoundMask(window, ring))
	window.kicker = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.85, 0.75, 0.5)
	window.kicker:SetPoint("TOPLEFT", window.portrait, "TOPRIGHT", 14, 0)
	window.kicker:SetText(L.JOURNAL_OPEN:upper())
	window.name = ns.Skin.CreateText(window, "GameFontNormalHuge", 1, 0.82, 0)
	window.name:SetPoint("TOPLEFT", window.kicker, "BOTTOMLEFT", 0, -3)
	window.identity = ns.Skin.CreateText(window, "GameTooltipText", 0.9, 0.88, 0.82)
	window.identity:SetPoint("TOPLEFT", window.name, "BOTTOMLEFT", 0, -3)
	window.since = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	window.since:SetPoint("TOPLEFT", window.identity, "BOTTOMLEFT", 0, -3)
	for _, text in ipairs({ window.kicker, window.name, window.identity, window.since }) do
		text:SetPoint("RIGHT", window, "RIGHT", -40, 0)
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	-- The reminders, a page of their own beside the journal.
	local reminders = CreateFrame("Button", nil, window)
	reminders:SetSize(26, 26)
	reminders:SetPoint("RIGHT", close, "LEFT", -4, 0)
	reminders:SetNormalTexture(ICONS.todo)
	reminders:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	reminders:SetScript("OnClick", function() if ns.ToggleTodo then ns.ToggleTodo() end end)
	reminders:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		local pending = ns.TodoPending and ns.TodoPending() or 0
		GameTooltip:AddLine(pending > 0 and L.TODO_TITLE_COUNT:format(pending) or L.TODO_TITLE, 1, 0.82, 0)
		GameTooltip:Show()
	end)
	reminders:SetScript("OnLeave", function() GameTooltip:Hide() end)
	window.headerRule = window:CreateTexture(nil, "ARTWORK")
	window.headerRule:SetColorTexture(1, 0.82, 0, 0.25)
	window.headerRule:SetHeight(1)
	window.headerRule:SetPoint("TOPLEFT", window.portrait, "BOTTOMLEFT", 0, -12)
	window.headerRule:SetPoint("RIGHT", window, "RIGHT", -margin, 0)

	-- Tiles: one per page, with its count.
	for index, page in ipairs(PAGES) do CreateTile(page, index) end
	LayoutTiles()

	-- The page: title, what it holds, and its rows on a darker inset.
	window.pageTitle = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	window.pageTitle:SetPoint("TOPLEFT", tiles.chronicle, "BOTTOMLEFT", 0, -14)
	window.pageText = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.68, 0.66, 0.6)
	window.pageText:SetPoint("TOPLEFT", window.pageTitle, "BOTTOMLEFT", 0, -3)
	for _, text in ipairs({ window.pageTitle, window.pageText }) do
		text:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	local inset = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	inset:SetColorTexture(0, 0, 0, 0.28)
	footer = ns.Skin.CreateText(window, "GameTooltipTextSmall", 0.55, 0.55, 0.55)
	footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	footer:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	if footer.SetWordWrap then footer:SetWordWrap(false) end
	inset:SetPoint("TOPLEFT", window.pageText, "BOTTOMLEFT", -4, -8)
	inset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin + 18)
	scroll = CreateFrame("ScrollFrame", "WandererJournalScroll", window, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 70, 1)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnVerticalScroll", DrawVisible)
	window.empty = ns.Skin.CreateText(window, "GameTooltipText", 0.5, 0.5, 0.5)
	window.empty:SetPoint("CENTER", inset, "CENTER")
	window.empty:SetText(L.JOURNAL_EMPTY)

	window:HookScript("OnShow", function(self)
		self:SetScale(ns.Skin.Scale())
		FillHeader()
		Fill()
	end)
	ns.Skin.Get(window):Layout()
end

function ns.RefreshJournalWindow()
	if window and window:IsShown() then Fill() end
end

-- Opens the journal, on a page if given ("places", "npcs"...).
function ns.ToggleJournal(page)
	if not ns.root then return end
	if not window then CreateWindow() end
	if page and tiles[page] then
		currentPage = page
		if window:IsShown() then Fill() return end
	end
	window:SetShown(not window:IsShown())
end

-- Key binding (Bindings.xml).
function Wanderer_ToggleJournal() ns.ToggleJournal() end
BINDING_NAME_WANDERER_JOURNAL = L.BINDING_JOURNAL

local scanStarted = false

-- A screenshot taken: a memory of the place, in the chronicle.
local function OnScreenshot()
	if not (ns.db and ns.db.enabled and ns.db.journal.enabled) then return end
	local place = Clean(Safe(GetSubZoneText)) or Zone()
	if place then Chronicle("photo", place, Zone(), nil, true) end
end
ns.JournalPhoto = OnScreenshot -- (tests)

function ns.InitJournal()
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
		frame:RegisterEvent(event)
	end
	for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "MERCHANT_SHOW", "TRAINER_SHOW",
		"TAXIMAP_OPENED", "BANKFRAME_OPENED" }) do
		frame:RegisterEvent(event)
	end
	for _, event in ipairs({ "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_MOUNT_DISPLAY_CHANGED", "SKILL_LINES_CHANGED",
		"PLAYER_MONEY", "PLAYER_DEAD", "PLAYER_LOGOUT", "QUEST_DATA_LOAD_RESULT", "SCREENSHOT_SUCCEEDED" }) do
		frame:RegisterEvent(event)
	end
	session.start, session.level = time(), Clean(Safe(UnitLevel, "player"))
	ResumeSession()
	frame:SetScript("OnEvent", function(_, event, arg1, arg2)
		if event == "QUEST_DATA_LOAD_RESULT" then return OnQuestLoaded(arg1, arg2) end
		if not (ns.db and ns.db.enabled and ns.db.journal.enabled) then return end
		if event == "SCREENSHOT_SUCCEEDED" then return OnScreenshot() end
		if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then return NoteMount() end
		if event == "SKILL_LINES_CHANGED" then return NoteSkills() end
		if event == "PLAYER_MONEY" then return NoteMoney() end
		if event == "PLAYER_DEAD" then return NoteDeath() end
		if event == "PLAYER_LOGOUT" then return NoteLogout() end
		if event:find("^ZONE_CHANGED") or event == "PLAYER_ENTERING_WORLD" then
			NotePlace(event ~= "PLAYER_ENTERING_WORLD")
			if event == "PLAYER_ENTERING_WORLD" then
				Milestones()
				NoteInstance()
			end
			-- Once per session, a moment after arriving: the places explored
			-- before (or while the journal was off).
			if event == "PLAYER_ENTERING_WORLD" and not scanStarted then
				scanStarted = true
				C_Timer.After(SCAN_DELAY, ns.ScanJournal)
			end
		elseif event == "QUEST_TURNED_IN" then
			NoteQuest(Clean(arg1))
		elseif event == "PLAYER_LEVEL_UP" then
			NoteLevel(arg1)
		else
			NoteCharacter(event)
		end
	end)
end
