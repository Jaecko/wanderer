local _, ns = ...
local L = ns.L

-- Your own list of sounds to silence: the game can only mute whole
-- categories (effects, music...), not one annoying sound. Each sound is
-- written with its number (the "file ID" shown by Wowhead), with a name if
-- you want: "Bells 567463, Fanfare 569584".

local U = ns.Util

local MAX_SOUNDS = 300 -- far more than a list needs
local MAX_ID = 99999999

local muted = {} -- file ID -> true, what Wanderer has muted

-- Numbers of the list, in order, without doubles. Anything else is ignored.
function ns.ParseSoundList(text)
	local ids, seen = {}, {}
	for number in tostring(text or ""):gmatch("%d+") do
		local id = tonumber(number)
		if id and id > 0 and id <= MAX_ID and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
			if #ids >= MAX_SOUNDS then break end
		end
	end
	return ids
end

function ns.RefreshSounds()
	if not (MuteSoundFile and UnmuteSoundFile) then return end
	local db = ns.db
	local wanted = {}
	if db.enabled and db.sounds.enabled then
		for _, id in ipairs(ns.ParseSoundList(db.sounds.list)) do wanted[id] = true end
	end
	for id in pairs(muted) do
		if not wanted[id] then
			U.Safe(UnmuteSoundFile, id)
			muted[id] = nil
		end
	end
	for id in pairs(wanted) do
		if not muted[id] then
			U.Safe(MuteSoundFile, id)
			muted[id] = true
		end
	end
end

function ns.EditSounds()
	ns.Skin.AskText(L.SOUNDS_PROMPT, ns.db.sounds.list, function(text)
		ns.ChangeEverywhere(function() ns.db.sounds.list = text end)
		ns.RefreshSounds()
		ns.Print(L.MSG_SOUNDS:format(#ns.ParseSoundList(ns.db.sounds.list)))
	end, 0, true)
end

function ns.InitSounds()
	ns.RefreshSounds()
end
