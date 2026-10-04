local _, ns = ...
local L = ns.L

-- Chat tabs: one click makes a tab for the group, one for the guild and one
-- for whispers, docked beside the game's own. A one-time setup, not a rule:
-- the tabs then belong to the player (rename, move, close as in the game).
-- A tab that already exists under the same name is never made twice, and
-- the General tab is left as it is.

local U = ns.Util
local Clean = U.Clean

ns.CHAT_TABS = {
	{ key = "group", groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
		"INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } },
	{ key = "guild", groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
	{ key = "whispers", groups = { "WHISPER", "BN_WHISPER" } },
}

local function TabName(tab)
	return L["CHAT_TAB_" .. tab.key:upper()]
end

-- Whether a chat window already carries this name.
local function Exists(name)
	if not GetChatWindowInfo then return false end
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local existing, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(index)
		if Clean(existing) == name and (shown or docked) then return true end
	end
	return false
end

-- The game's functions, wherever this version of the game keeps them.
local function AddGroup(frame, group)
	if frame.AddMessageGroup then return pcall(frame.AddMessageGroup, frame, group) end
	if ChatFrame_AddMessageGroup then return pcall(ChatFrame_AddMessageGroup, frame, group) end
end

local function Clear(frame)
	if frame.RemoveAllMessageGroups then pcall(frame.RemoveAllMessageGroups, frame)
	elseif ChatFrame_RemoveAllMessageGroups then pcall(ChatFrame_RemoveAllMessageGroups, frame) end
	if frame.RemoveAllChannels then pcall(frame.RemoveAllChannels, frame)
	elseif ChatFrame_RemoveAllChannels then pcall(ChatFrame_RemoveAllChannels, frame) end
end

-- Makes the chosen tabs; returns the names made and the names already there.
function ns.CreateChatTabs()
	local made, kept = {}, {}
	if InCombatLockdown() or not FCF_OpenNewWindow then return made, kept end
	for _, tab in ipairs(ns.CHAT_TABS) do
		if ns.db.chat[tab.key] then
			local name = TabName(tab)
			if Exists(name) then
				kept[#kept + 1] = name
			else
				-- true: without the default channels, only what the tab is for.
				local ok, frame = pcall(FCF_OpenNewWindow, name, true)
				if ok and frame then
					Clear(frame)
					for _, group in ipairs(tab.groups) do AddGroup(frame, group) end
					made[#made + 1] = name
				end
			end
		end
	end
	if made[1] then
		ns.Print(L.MSG_CHAT_TABS:format(table.concat(made, ", ")))
	elseif kept[1] then
		ns.Print(L.MSG_CHAT_TABS_EXIST)
	else
		ns.Print(L.MSG_CHAT_TABS_NONE)
	end
	return made, kept
end
