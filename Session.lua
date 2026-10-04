local _, ns = ...
local L = ns.L

-- This play session: time, gold, experience, kills and quests, with the
-- averages per hour. Shown on demand (/wanderer bilan) and in the minimap
-- button's tooltip. A gentle reminder to take a break can come every so
-- often (off by default).

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_DELAY = 30 -- seconds between two looks at the clock

local session -- { start, money, xp, kills, quests, lastXP, lastMaxXP, nextBreak }
local sinceCheck = 0

local function Now() return GetTime() end

local Coins = U.Coins

local function Duration(seconds)
	return Safe(SecondsToTime, math.max(seconds, 60), true) or (math.floor(seconds / 60) .. " min")
end

local function Start()
	local xp, maximum = Clean(Safe(UnitXP, "player")) or 0, Clean(Safe(UnitXPMax, "player")) or 0
	session = { start = Now(), money = Clean(Safe(GetMoney)) or 0, xp = 0, kills = 0, quests = 0,
		lastXP = xp, lastMaxXP = maximum }
end

-- Experience gained since the last look, across level ups.
local function OnXP()
	if not session then return end
	local xp, maximum = Clean(Safe(UnitXP, "player")), Clean(Safe(UnitXPMax, "player"))
	if not (xp and maximum) then return end
	local gained = xp - session.lastXP
	if gained < 0 then gained = (session.lastMaxXP - session.lastXP) + xp end -- a new level
	session.xp = session.xp + math.max(gained, 0)
	session.lastXP, session.lastMaxXP = xp, maximum
end

-- Lines of the summary, ready to show.
function ns.SessionSummary()
	if not session then return {} end
	local elapsed = math.max(Now() - session.start, 1)
	local hours = elapsed / 3600
	local money = (Clean(Safe(GetMoney)) or session.money) - session.money
	local lines = { L.SESSION_TIME:format(Duration(elapsed)) }
	lines[#lines + 1] = L.SESSION_MONEY:format(Coins(money), Coins(math.floor(money / hours)))
	if session.xp > 0 then
		lines[#lines + 1] = L.SESSION_XP:format(session.xp, math.floor(session.xp / hours))
		local current, maximum = Clean(Safe(UnitXP, "player")), Clean(Safe(UnitXPMax, "player"))
		if current and maximum and maximum > current then
			local rate = session.xp / elapsed
			lines[#lines + 1] = L.SESSION_NEXT_LEVEL:format(Duration((maximum - current) / rate))
		end
	end
	if session.kills > 0 or session.quests > 0 then
		lines[#lines + 1] = L.SESSION_COUNTS:format(session.kills, session.quests)
	end
	return lines
end

function ns.PrintSession()
	ns.Print(L.SESSION_TITLE)
	for _, line in ipairs(ns.SessionSummary()) do ns.Print("  " .. line) end
end

-- Break reminder: every N minutes of play, if chosen.
local function CheckBreak()
	local every = ns.db and ns.db.enabled and ns.db.session.breakEvery or 0
	if not session or every <= 0 then return end
	local elapsed = Now() - session.start
	session.nextBreak = session.nextBreak or every * 60
	if elapsed >= session.nextBreak then
		session.nextBreak = session.nextBreak + every * 60
		if ns.Toast then ns.Toast(L.BREAK_TITLE, L.BREAK_TEXT:format(Duration(elapsed))) end
	end
end

-- The interval changed: counted again from now.
local watcher -- looks at the clock, only when a break reminder is set

function ns.RefreshSession()
	if session then session.nextBreak = nil end
	sinceCheck = CHECK_DELAY
	if watcher then watcher:SetShown((ns.db.session.breakEvery or 0) > 0) end
end

function ns.InitSession()
	local frame = CreateFrame("Frame")
	watcher = frame
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("PLAYER_XP_UPDATE")
	frame:RegisterEvent("QUEST_TURNED_IN")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			Start()
		elseif event == "PLAYER_XP_UPDATE" then
			OnXP()
		elseif session then
			session.quests = session.quests + 1
		end
	end)
	frame:SetScript("OnUpdate", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed
		if sinceCheck < CHECK_DELAY then return end
		sinceCheck = 0
		CheckBreak()
	end)
	ns.World.OnKill(function() if session then session.kills = session.kills + 1 end end)
	-- Loaded after the login (/reload): the session starts now.
	if IsLoggedIn and IsLoggedIn() then Start() end
	ns.RefreshSession()
end
