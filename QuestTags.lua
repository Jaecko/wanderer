local _, ns = ...
local L = ns.L

-- Elite and group quests, said where the game says nothing: a line under the
-- quest's title in its scene ("Elite · group of 3"), before you say yes, and
-- a mark in the list of what a character offers. (The quest log and the
-- tracker already show it.)

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local COLOR = "ffff7a4a"

local function On()
	local db = ns.db
	return db and db.enabled and db.quest and db.quest.tags and true or false
end

-- What a quest asks: elite, its kind (dungeon, raid, pvp), the players advised.
-- inDialog: the quest offered by a character (not in the log yet).
function ns.QuestTag(questID, inDialog)
	questID = tonumber(questID)
	if not questID then return nil end
	local log = C_QuestLog or {}
	local info = Safe(log.GetQuestTagInfo, questID)
	local tagID = type(info) == "table" and Clean(info.tagID) or nil
	local consts = Constants and Constants.QuestConsts or {}
	local elite = Clean(Safe(log.IsEliteQuest, questID)) and true or false
	if type(info) == "table" and Clean(info.isElite) then elite = true end
	if tagID and tagID == consts.QUEST_INFO_ELITE_ID then elite = true end
	local kind
	if tagID and tagID == consts.QUEST_INFO_DUNGEON_ID then kind = "dungeon"
	elseif tagID and tagID == consts.QUEST_INFO_RAID_ID then kind = "raid"
	elseif tagID and tagID == consts.QUEST_INFO_PVP_ID then kind = "pvp" end
	local group = Clean(Safe(log.GetSuggestedGroupSize, questID))
	if inDialog and not (group and group > 1) then group = Clean(Safe(GetSuggestedGroupNum)) end
	group = group and group > 1 and group or nil
	if not (elite or kind or group) then return nil end
	return { elite = elite, kind = kind, group = group }
end

-- "Elite · group of 3" (short: "Elite · 3", for the tracker and the lists).
function ns.QuestTagText(questID, inDialog, short)
	local tag = ns.QuestTag(questID, inDialog)
	if not tag then return nil end
	local parts = {}
	if tag.elite then parts[#parts + 1] = L.QUEST_ELITE end
	if tag.kind then parts[#parts + 1] = L["QUEST_KIND_" .. tag.kind:upper()] end
	if tag.group then parts[#parts + 1] = short and tostring(tag.group) or L.QUEST_GROUP:format(tag.group) end
	return table.concat(parts, " · ")
end

-- The quest's scene: the line under its title, in capitals.
function ns.QuestSceneTag(questID)
	if not On() then return nil end
	local text = ns.QuestTagText(questID, true)
	return text and ("|c%s%s|r"):format(COLOR, U.Upper(text)) or nil
end

-- A quest in a character's list: its mark after its name.
function ns.QuestChoiceTag(questID)
	if not On() then return "" end
	local text = ns.QuestTagText(questID, false, true)
	return text and ("  |c%s(%s)|r"):format(COLOR, text) or ""
end
