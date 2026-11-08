local _, ns = ...

-- The chat itself is Wanderer Chat's (its tabs, its comforts, the private messages). Here only the
-- Wanderer tab: in diagnostic mode everything Wanderer writes goes there, and nothing of the game's chat,
-- ready to be copied as it is. Made once (out of a fight), then found again by its name; it is the
-- player's like any tab.

local Clean = ns.Util.Clean

-- The chat window of this name, shown or docked (its index).
local function WindowIndex(name)
	if not GetChatWindowInfo then return end
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local existing, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(index)
		if Clean(existing) == name and (shown or docked) then return index end
	end
end

local function Clear(frame)
	if frame.RemoveAllMessageGroups then pcall(frame.RemoveAllMessageGroups, frame)
	elseif ChatFrame_RemoveAllMessageGroups then pcall(ChatFrame_RemoveAllMessageGroups, frame) end
	if frame.RemoveAllChannels then pcall(frame.RemoveAllChannels, frame)
	elseif ChatFrame_RemoveAllChannels then pcall(ChatFrame_RemoveAllChannels, frame) end
end

local DEBUG_TAB = "Wanderer"

local function DebugIndex() return WindowIndex(DEBUG_TAB) end

function ns.IsDebugTab(index)
	return index ~= nil and index == DebugIndex()
end

function ns.DebugFrame(create)
	local index = DebugIndex()
	if index then return _G["ChatFrame" .. index] end
	if not create or InCombatLockdown() or not FCF_OpenNewWindow then return end
	local ok, frame = pcall(FCF_OpenNewWindow, DEBUG_TAB, true)
	if ok and frame then
		Clear(frame)
		return frame
	end
end
