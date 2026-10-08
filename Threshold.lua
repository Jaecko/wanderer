local _, ns = ...
local L = ns.L

-- Things not to forget, said at the right moment:
-- * the threshold of a dungeon or a raid: on entering, a short notice tells
--   the quests of your log that are done there and, when it is worn, the
--   state of your equipment (said only when there is something to say: the
--   game writes the place's name itself);
-- * back in a city or an inn with worn equipment: a smith would be welcome.
-- Only events: nothing runs between them.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local WORN = 50 -- percent: equipment worth a word at a dungeon's door
local VERY_WORN = 35 -- percent: worth a word back in town
local REPAIR_AGAIN = 1800 -- seconds before the town reminder comes again
local MAX_QUESTS = 4

local seen = {} -- instances already announced this session
local lastRepair = -REPAIR_AGAIN

-- The most worn piece of equipment, in percent (nil: nothing to wear out).
local function Wear()
	local lowest
	for slot = 1, 18 do
		local current, maximum = Safe(GetInventoryItemDurability, slot)
		current, maximum = Clean(current), Clean(maximum)
		if current and maximum and maximum > 0 then
			local share = math.floor(current / maximum * 100)
			if not lowest or share < lowest then lowest = share end
		end
	end
	return lowest
end

-- The quests of your log done in this place (the log groups them under its name).
local function QuestsHere(place)
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return {} end
	local found, under = {}, false
	for index = 1, Clean(Safe(log.GetNumQuestLogEntries)) or 0 do
		local info = Safe(log.GetInfo, index)
		if type(info) == "table" then
			if info.isHeader then
				under = Clean(info.title) == place
			elseif under and Clean(info.title) and #found < MAX_QUESTS then
				found[#found + 1] = info.title
			end
		end
	end
	return found
end

local function Settings()
	local db = ns.db
	return db and db.enabled and db.journal or nil
end

local function OnEnter()
	local settings = Settings()
	if not (settings and settings.threshold and ns.Toast) then return end
	local inInstance, kind = Safe(IsInInstance)
	if not (Clean(inInstance) and (kind == "party" or kind == "raid")) then return end
	local name, _, _, _, _, _, _, instanceID = Safe(GetInstanceInfo)
	name = Clean(name)
	local key = Clean(instanceID) or name
	if not name or seen[key] then return end
	seen[key] = true
	local lines = {}
	local quests = QuestsHere(name)
	if quests[1] then lines[#lines + 1] = L.THRESHOLD_QUESTS:format(table.concat(quests, ", ")) end
	local wear = Wear()
	if wear and wear < WORN then lines[#lines + 1] = L.THRESHOLD_WORN:format(wear) end
	if lines[1] then ns.Toast(name, table.concat(lines, "\n"), { duration = 8 }) end
end

-- Back in a city or an inn with worn equipment.
local function OnRest()
	local db = ns.db
	if not (db and db.enabled and db.merchant.repairReminder and ns.Toast) or not Clean(Safe(IsResting)) then return end
	local wear = Wear()
	if not wear or wear >= VERY_WORN or GetTime() - lastRepair < REPAIR_AGAIN then return end
	lastRepair = GetTime()
	ns.Toast(L.REPAIR_TITLE, L.REPAIR_TEXT:format(wear), { duration = 5, corner = true })
end

function ns.InitThreshold()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("PLAYER_UPDATE_RESTING")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_UPDATE_RESTING" then return OnRest() end
		-- The game sets the instance a moment after the loading screen.
		C_Timer.After(2, OnEnter)
		C_Timer.After(2, OnRest)
	end)
end
