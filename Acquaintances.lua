local _, ns = ...

-- The players you know (option, off by default): with every name hidden, those of the players this character
-- has met still come, small, over their head (Plates.lua writes them, as your group's). Met: grouped with
-- you, whispered by you (a whisper only received is not a meeting), on your friends list, or chosen from the
-- game's menu of a player ("Remember this name", "Forget this name"). Kept by character (ns.Mine()), the
-- oldest let go past KEPT. Nothing is learned while the option is off.

local L = ns.L
local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local KEPT = 500
local MENU_TAGS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET",
	"MENU_UNIT_FOCUS", "MENU_UNIT_RAID", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
	"MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_GUILD", "MENU_UNIT_CHAT_ROSTER" }

local function On()
	local db = ns.db
	return db and db.enabled and db.knownMarks and true or false
end

local function Known()
	local mine = ns.Mine()
	mine.acquaintances = type(mine.acquaintances) == "table" and mine.acquaintances or {}
	return mine.acquaintances
end

-- Those you chose to forget: never learned again by themselves (a group, a whisper), only chosen again by hand.
local function Forgotten()
	local mine = ns.Mine()
	mine.acquaintancesForgotten = type(mine.acquaintancesForgotten) == "table" and mine.acquaintancesForgotten or {}
	return mine.acquaintancesForgotten
end

-- One way to write a player, whatever gave it: "name-realm" in small letters, the realm without spaces.
local function OwnRealm()
	return Clean(Safe(GetNormalizedRealmName)) or Clean(Safe(GetRealmName)) or ""
end
local function Key(name, realm)
	if type(name) ~= "string" or name == "" then return nil end
	if not realm or realm == "" then
		local dash = name:find("-", 1, true)
		if dash then name, realm = name:sub(1, dash - 1), name:sub(dash + 1) end
	end
	if not realm or realm == "" then realm = OwnRealm() end
	-- (the realm as the game normalizes it: no spaces, apostrophes or dashes, whatever gave it)
	return (name .. "-" .. realm:gsub("[%s'%-]", "")):lower(), name
end

local function KeyOfUnit(unit)
	local name, realm = Safe(UnitName, unit)
	return Key(Clean(name), Clean(realm))
end

local function Changed()
	if ns.PlatesForget then ns.PlatesForget() end
end

local function Add(key, name, why)
	if not key then return end
	if why == "chosen" then Forgotten()[key] = nil elseif Forgotten()[key] then return end
	local known = Known()
	local entry = known[key]
	if entry then
		entry.at = time()
		if why == "chosen" then entry.why = "chosen" end
		return
	end
	known[key] = { name = name, at = time(), why = why }
	-- (past KEPT: the oldest met, never one chosen by hand while another can go; all chosen: the oldest of them)
	local count, oldest, oldestAt, oldestChosen, chosenAt = 0, nil, math.huge, nil, math.huge
	for other, data in pairs(known) do
		count = count + 1
		local at = data.at or 0
		if data.why ~= "chosen" then
			if at < oldestAt then oldest, oldestAt = other, at end
		elseif at < chosenAt then
			oldestChosen, chosenAt = other, at
		end
	end
	if count > KEPT then known[oldest or oldestChosen] = nil end
	Changed()
end

-- Whether this character knows the player on this unit (friends included).
function ns.IsAcquaintance(unit)
	if not On() or not Clean(Safe(UnitIsPlayer, unit)) or Clean(Safe(UnitIsUnit, unit, "player")) then return false end
	local guid = Clean(Safe(UnitGUID, unit))
	if guid and C_FriendList and C_FriendList.IsFriend and Clean(Safe(C_FriendList.IsFriend, guid)) then return true end
	local key = KeyOfUnit(unit)
	return key ~= nil and Known()[key] ~= nil
end

function ns.RememberPlayer(name, realm, why)
	local key, short = Key(name, realm)
	Add(key, short, why or "chosen")
end

function ns.ForgetPlayer(name, realm)
	local key = Key(name, realm)
	if not key then return end
	Forgotten()[key] = true
	if Known()[key] then
		Known()[key] = nil
		Changed()
	end
end

function ns.KnowsPlayer(name, realm)
	local key = Key(name, realm)
	return key ~= nil and Known()[key] ~= nil
end

function ns.AcquaintanceCount()
	local count = 0
	for _ in pairs(Known()) do count = count + 1 end
	return count
end

function ns.ForgetAllAcquaintances()
	ns.Mine().acquaintances = {}
	Changed()
end

-- Your group, met: every member (out of a fight, when the game hides names: read again at the next change).
local function LearnGroup()
	if not On() then return end
	local raid = Clean(Safe(IsInRaid))
	for index = 1, raid and 40 or 4 do
		local unit = (raid and "raid" or "party") .. index
		if Clean(Safe(UnitExists, unit)) and Clean(Safe(UnitIsPlayer, unit)) and not Clean(Safe(UnitIsUnit, unit, "player")) then
			local key, name = KeyOfUnit(unit)
			-- (met again: kept fresh, so those you play with often are the last ever let go)
			local entry = key and Known()[key]
			if entry then entry.at = time() elseif key then Add(key, name, "group") end
		end
	end
end
ns.LearnGroupAcquaintances = LearnGroup -- (tests)

-- The game's menu of a player: remember or forget their name.
local function MenuEntries(_, root, context)
	if not (On() and root and root.CreateButton and type(context) == "table") then return end
	local unit = Clean(context.unit)
	local name, realm = Clean(context.name), Clean(context.server)
	if unit then
		if not Clean(Safe(UnitIsPlayer, unit)) or Clean(Safe(UnitIsUnit, unit, "player")) then return end
		local unitName, unitRealm = Safe(UnitName, unit)
		name, realm = Clean(unitName) or name, Clean(unitRealm) or realm
	end
	if type(name) ~= "string" or name == "" then return end
	-- (yourself: nothing; a friend: known by your friends list already, nothing to remember or forget)
	if Key(name, realm) == Key(Clean(Safe(UnitName, "player")), OwnRealm()) then return end
	local guid = unit and Clean(Safe(UnitGUID, unit))
	if guid and C_FriendList and C_FriendList.IsFriend and Clean(Safe(C_FriendList.IsFriend, guid)) then return end
	if root.CreateDivider then root:CreateDivider() end
	if ns.KnowsPlayer(name, realm) then
		root:CreateButton(L.KNOWN_FORGET, function() ns.ForgetPlayer(name, realm) end)
	else
		root:CreateButton(L.KNOWN_REMEMBER, function() ns.RememberPlayer(name, realm, "chosen") end)
	end
end
ns.AcquaintanceMenuEntries = MenuEntries -- (tests)

function ns.InitAcquaintances()
	local events = CreateFrame("Frame")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
	pcall(events.RegisterEvent, events, "FRIENDLIST_UPDATE")
	events:SetScript("OnEvent", function(_, event, _, target)
		if event == "FRIENDLIST_UPDATE" then
			-- (a friend added or removed: the names over the heads read again)
			if On() then Changed() end
		elseif event == "CHAT_MSG_WHISPER_INFORM" then
			if On() then
				local key, name = Key(Clean(target))
				Add(key, name, "whisper")
			end
		elseif not InCombatLockdown() then
			LearnGroup()
		end
	end)
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs(MENU_TAGS) do pcall(Menu.ModifyMenu, tag, MenuEntries) end
	end
end
