local _, ns = ...
local L = ns.L

-- Professions, quietly followed: each point gained is said by a short notice
-- (several in a row: one notice, "Mining rises to 75", "+3"). Only events:
-- nothing runs between them.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local SKILL_WAIT = 3 -- seconds: points gained in a row make one notice

local ranks = {} -- profession name -> its rank
local rising = {} -- profession name -> rank before the points gained in a row
local risingToken = 0

local function Settings()
	local db = ns.db
	return db and db.enabled and db.crafts or nil
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

function ns.InitCrafts()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("SKILL_LINES_CHANGED")
	frame:SetScript("OnEvent", function(_, event) ReadRanks(event == "PLAYER_LOGIN") end)
	ReadRanks(true)
end
