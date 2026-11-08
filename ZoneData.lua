local _, ns = ...

-- The world's levels, shared world data (read through Wanderer.ZoneLevels): each outdoor zone's level range,
-- the dungeons' and the raids'. Forever's client gives none (no level range on its maps or areas), so they are
-- written here: the original world's ranges, Forever's own zones as played, its four new dungeons with their
-- highest level estimated (marked). Places by the game's own area ids (their names come from the game, in your
-- language); a zone also by its map (uiMapID), as the world map shows it.
--
-- Fishing: the skill a zone's waters ask, as the original world counts it (its base): from the base you catch
-- something, from the base and 95 nothing gets away. The cities fish as the second zones do.

-- { area, map, low, high, fish (the base; nil: no water worth a line), estimated (the high is a guess) }
local ZONES = {
	{ area = 12, map = 1429, low = 1, high = 10, fish = -70 }, -- Elwynn Forest
	{ area = 1, map = 1426, low = 1, high = 10, fish = -70 }, -- Dun Morogh
	{ area = 141, map = 1438, low = 1, high = 10, fish = -70 }, -- Teldrassil
	{ area = 14, map = 1411, low = 1, high = 10, fish = -70 }, -- Durotar
	{ area = 215, map = 1412, low = 1, high = 10, fish = -70 }, -- Mulgore
	{ area = 85, map = 1420, low = 1, high = 10, fish = -70 }, -- Tirisfal Glades
	{ area = 16593, map = 2521, low = 1, high = 12, fish = -70 }, -- Zephras Isle (Forever)
	{ area = 40, map = 1436, low = 10, high = 20, fish = -20 }, -- Westfall
	{ area = 38, map = 1432, low = 10, high = 20, fish = -20 }, -- Loch Modan
	{ area = 148, map = 1439, low = 10, high = 20, fish = -20 }, -- Darkshore
	{ area = 130, map = 1421, low = 10, high = 20, fish = -20 }, -- Silverpine Forest
	{ area = 17, map = 1413, low = 10, high = 25, fish = -20 }, -- The Barrens
	{ area = 44, map = 1433, low = 15, high = 25, fish = 55 }, -- Redridge Mountains
	{ area = 406, map = 1442, low = 15, high = 27, fish = 55 }, -- Stonetalon Mountains
	{ area = 10, map = 1431, low = 18, high = 30, fish = 55 }, -- Duskwood
	{ area = 331, map = 1440, low = 18, high = 30, fish = 55 }, -- Ashenvale
	{ area = 11, map = 1437, low = 20, high = 30, fish = 55 }, -- Wetlands
	{ area = 267, map = 1424, low = 20, high = 30, fish = 55 }, -- Hillsbrad Foothills
	{ area = 400, map = 1441, low = 25, high = 35, fish = 130 }, -- Thousand Needles
	{ area = 36, map = 1416, low = 30, high = 40, fish = 130 }, -- Alterac Mountains
	{ area = 45, map = 1417, low = 30, high = 40, fish = 130 }, -- Arathi Highlands
	{ area = 405, map = 1443, low = 30, high = 40, fish = 130 }, -- Desolace
	{ area = 33, map = 1434, low = 30, high = 45, fish = 130 }, -- Stranglethorn Vale
	{ area = 15, map = 1445, low = 35, high = 45, fish = 130 }, -- Dustwallow Marsh
	{ area = 16591, map = 2548, low = 35, high = 45, fish = 130 }, -- Riverglades (Forever)
	{ area = 3, map = 1418, low = 35, high = 45 }, -- Badlands
	{ area = 8, map = 1435, low = 35, high = 45, fish = 130 }, -- Swamp of Sorrows
	{ area = 16651, map = 2652, low = 40, high = 45, fish = 205 }, -- Shen'dralas (Forever)
	{ area = 357, map = 1444, low = 40, high = 50, fish = 205 }, -- Feralas
	{ area = 47, map = 1425, low = 40, high = 50, fish = 205 }, -- The Hinterlands
	{ area = 440, map = 1446, low = 40, high = 50, fish = 205 }, -- Tanaris
	{ area = 51, map = 1427, low = 43, high = 50 }, -- Searing Gorge
	{ area = 16, map = 1447, low = 45, high = 55, fish = 205 }, -- Azshara
	{ area = 4, map = 1419, low = 45, high = 55 }, -- Blasted Lands
	{ area = 490, map = 1449, low = 48, high = 55, fish = 205 }, -- Un'Goro Crater
	{ area = 361, map = 1448, low = 48, high = 55, fish = 205 }, -- Felwood
	{ area = 46, map = 1428, low = 50, high = 58 }, -- Burning Steppes
	{ area = 28, map = 1422, low = 51, high = 58, fish = 205 }, -- Western Plaguelands
	{ area = 139, map = 1423, low = 53, high = 60, fish = 330 }, -- Eastern Plaguelands
	{ area = 618, map = 1452, low = 55, high = 60, fish = 330 }, -- Winterspring
	{ area = 41, map = 1430, low = 55, high = 60, fish = 330 }, -- Deadwind Pass
	{ area = 493, map = 1450, low = 55, high = 60, fish = 205 }, -- Moonglade
	{ area = 1377, map = 1451, low = 55, high = 60, fish = 330 }, -- Silithus
	{ area = 616, map = 2482, low = 55, high = 60, fish = 330 }, -- Mount Hyjal (Forever)
	-- (the cities: no level range, waters to fish)
	{ area = 1519, map = 1453, fish = -20 }, -- Stormwind City
	{ area = 1537, map = 1455, fish = -20 }, -- Ironforge
	{ area = 1657, map = 1457, fish = -20 }, -- Darnassus
	{ area = 1637, map = 1454, fish = -20 }, -- Orgrimmar
	{ area = 1638, map = 1456, fish = -20 }, -- Thunder Bluff
	{ area = 1497, map = 1458, fish = -20 }, -- Undercity
}

local DUNGEONS = {
	{ area = 2437, low = 13, high = 18 }, -- Ragefire Chasm
	{ area = 16919, low = 13, high = 21, estimated = true }, -- The Hall of Thanes (Forever)
	{ area = 16611, low = 15, high = 27, estimated = true }, -- Ruins of Lordaeron (Forever)
	{ area = 718, low = 17, high = 24 }, -- Wailing Caverns
	{ area = 1581, low = 17, high = 26 }, -- The Deadmines
	{ area = 209, low = 22, high = 30 }, -- Shadowfang Keep
	{ area = 719, low = 24, high = 32 }, -- Blackfathom Deeps
	{ area = 717, low = 24, high = 32 }, -- The Stockade
	{ area = 16732, low = 26, high = 34, estimated = true }, -- Excavation Site: Wetlands (Forever)
	{ area = 16544, low = 28, high = 36, estimated = true }, -- City of Dalaran (Forever)
	{ area = 133, low = 29, high = 38 }, -- Gnomeregan
	{ area = 1717, low = 30, high = 40 }, -- Razorfen Kraul
	{ area = 796, low = 34, high = 45 }, -- Scarlet Monastery
	{ area = 722, low = 40, high = 50 }, -- Razorfen Downs
	{ area = 1517, low = 41, high = 51 }, -- Uldaman
	{ area = 978, low = 44, high = 54 }, -- Zul'Farrak
	{ area = 2100, low = 46, high = 55 }, -- Maraudon
	{ area = 1417, low = 50, high = 56 }, -- The Temple of Atal'Hakkar
	{ area = 1584, low = 52, high = 60 }, -- Blackrock Depths
	{ area = 1583, low = 55, high = 60 }, -- Blackrock Spire
	{ area = 2557, low = 56, high = 60 }, -- Dire Maul
	{ area = 2017, low = 58, high = 60 }, -- Stratholme
	{ area = 2057, low = 58, high = 60 }, -- Scholomance
}

local RAIDS = {
	{ area = 1977, low = 60, high = 62 }, -- Zul'Gurub
	{ area = 3429, low = 60, high = 62 }, -- Ruins of Ahn'Qiraj
	{ area = 2717, low = 60, high = 63 }, -- Molten Core
	{ area = 2159, low = 60, high = 63 }, -- Onyxia's Lair
	{ area = 2677, low = 60, high = 65 }, -- Blackwing Lair
	{ area = 3428, low = 60, high = 67 }, -- Temple of Ahn'Qiraj
	{ area = 3456, low = 60, high = 70 }, -- Naxxramas
}

-- (a zone with a second map of its own: Forever's Zephras Isle)
local MAP_ALIASES = { [2665] = 2521 }

-- How much skill past the base a zone asks before nothing gets away.
local FISH_SPAN = 95

local all, byArea, byMap = {}, {}, {}
local function Add(list, kind)
	for _, place in ipairs(list) do
		place.kind = kind
		if place.fish then place.fishLow, place.fishHigh = math.max(1, place.fish), place.fish + FISH_SPAN end
		all[#all + 1] = place
		byArea[place.area] = place
		if place.map then byMap[place.map] = place end
	end
end
Add(ZONES, "zone")
Add(DUNGEONS, "dungeon")
Add(RAIDS, "raid")

-- A place's levels: { area, map, kind ("zone", "dungeon", "raid"), low, high (nil for a city), estimated,
-- fishLow, fishHigh (nil: no water) }, by its area id, or by its map when onMap; nil when unknown. No id: the
-- whole list. Read only.
function ns.ZoneLevels(id, onMap)
	if id == nil then return all end
	id = tonumber(id)
	if not id then return nil end
	if onMap then return byMap[MAP_ALIASES[id] or id] end
	return byArea[id]
end
