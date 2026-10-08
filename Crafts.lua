local _, ns = ...
local L = ns.L

-- Professions, quietly followed:
-- * each point gained is said by a short notice (several in a row: one notice,
--   "Mining rises to 75", "+3");
-- * the first time each recipe is crafted is written in the travel journal;
-- * what is gathered (herbs, ore, leather) is counted for the session summary,
--   with the fish caught.
-- Read from the game's own messages ("You create:", "You receive loot:"),
-- whatever its language. Only events: nothing runs between them.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local SKILL_WAIT = 3 -- seconds: points gained in a row make one notice
-- Trade goods (class 7) gathered, by subclass.
local TRADE_GOODS = 7
local GATHERED = { [9] = "herbs", [7] = "ore", [6] = "leather" }
local GATHER_ORDER = { "herbs", "ore", "leather" }

local ranks = {} -- profession name -> its rank
local rising = {} -- profession name -> rank before the points gained in a row
local risingToken = 0
local gathered = { herbs = 0, ore = 0, leather = 0 }

local function Settings()
	local db = ns.db
	return db and db.enabled and db.crafts or nil
end

-- A message of the game ("You create: %s.") as a pattern that reads it back.
local function Pattern(text)
	if type(text) ~= "string" then return end
	-- Its placeholders (%s, %d, also numbered: %1$s) set aside, the rest taken literally.
	text = text:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
	text = text:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
	text = text:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
	return "^" .. text .. "$"
end

local function Patterns(...)
	local list = {}
	for index = 1, select("#", ...) do
		local pattern = Pattern((select(index, ...)))
		if pattern then list[#list + 1] = pattern end
	end
	return list
end

local CREATED = Patterns(LOOT_ITEM_CREATED_SELF_MULTIPLE, LOOT_ITEM_CREATED_SELF)
local RECEIVED = Patterns(LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF)

local function Match(patterns, message)
	for _, pattern in ipairs(patterns) do
		local link, count = message:match(pattern)
		if link then return link, tonumber(count) or 1 end
	end
end

local function NameOf(link)
	return link:match("%[(.-)%]") or link
end

-- Points gained: one notice for the points of a row.
local function SayRise()
	for name, from in pairs(rising) do
		local to = ranks[name]
		if to and to > from and ns.Toast then
			ns.Toast(L.CRAFT_SKILL_UP:format(name, to), to - from > 1 and L.CRAFT_SKILL_GAIN:format(to - from) or nil,
				{ duration = 2.5, corner = true })
		end
	end
	wipe(rising)
end

local function ReadRanks(first)
	for _, index in pairs({ Safe(GetProfessions) }) do
		local name, _, rank = Safe(GetProfessionInfo, index)
		name, rank = Clean(name), Clean(rank)
		if name and rank then
			local before = ranks[name]
			if not first and before and rank > before then
				local settings = Settings()
				if settings and settings.skillUps then
					rising[name] = rising[name] or before
					risingToken = risingToken + 1
					local token = risingToken
					C_Timer.After(SKILL_WAIT, function() if token == risingToken then SayRise() end end)
				end
			end
			ranks[name] = rank
		end
	end
end

local function OnLoot(message)
	message = Clean(message)
	if not message then return end
	local made = Match(CREATED, message)
	if made then
		local settings = Settings()
		if settings and settings.firstCrafts and ns.db.journal.enabled and ns.JournalCraft then ns.JournalCraft(NameOf(made)) end
		return
	end
	local link, count = Match(RECEIVED, message)
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id then return end
	local _, _, _, _, _, class, subclass = Safe(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, id)
	local kind = Clean(class) == TRADE_GOODS and GATHERED[Clean(subclass) or -1]
	if kind then gathered[kind] = gathered[kind] + count end
end

-- What was gathered this session, with the fish caught: "Herbs 23 · Ore 12".
function ns.GatheredLine()
	local parts = {}
	for _, kind in ipairs(GATHER_ORDER) do
		if gathered[kind] > 0 then parts[#parts + 1] = L["GATHER_" .. kind:upper()]:format(gathered[kind]) end
	end
	local fish = ns.FishingStatus and ns.FishingStatus().catches or 0
	if fish > 0 then parts[#parts + 1] = L.GATHER_FISH:format(fish) end
	if parts[1] then return L.SESSION_GATHERED:format(table.concat(parts, "  ·  ")) end
end

function ns.InitCrafts()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("SKILL_LINES_CHANGED")
	frame:RegisterEvent("CHAT_MSG_LOOT")
	frame:SetScript("OnEvent", function(_, event, message)
		if event == "CHAT_MSG_LOOT" then return OnLoot(message) end
		ReadRanks(event == "PLAYER_LOGIN")
	end)
	ReadRanks(true)
end
