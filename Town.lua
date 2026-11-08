local _, ns = ...
local L = ns.L

-- Back in a city or at an inn (a rest area entered): one notice gathering
-- what is useful there, a line from each provider that has something to say
-- (the repairs here; the trainer, the shopping list, the mailbox from the
-- extensions). A line may take a click: its window, or the way there on the
-- map. Once for each arrival, never in a fight, the same town not again
-- before a while. Only events: nothing runs between them.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local AGAIN = 600 -- seconds before the same town is told again
local WORN = 50 -- percent: repairs worth a line
local SETTLE = 2 -- seconds after arriving: the place's name set, the mailbox known
local SHOW_TIME = 12
local VERY_WORN = 35 -- percent: the town card off, worth a notice of its own
local REPAIR_AGAIN = 1800 -- seconds before that notice comes again
-- The lines in this order, whoever gave them first (the others after).
local ORDER = { repair = 1, trainer = 2, shopping = 3, mail = 4 }

local providers = {} -- { fn, key }
local told = {} -- place -> when it was last told
local resting = false
local pending = false -- arrived during a fight: told once it is over
local quietUntil = 0 -- (just logged in or reloaded: the resting state's first word is no arrival)
local lastRepair = -REPAIR_AGAIN

-- fn() -> { text, onClick, hint } or nil: a line of the card. key: one provider for that line (a new one takes
-- its place, an extension's over Wanderer's own).
function ns.TownLine(fn, key)
	if type(fn) ~= "function" then return end
	if key then
		for _, known in ipairs(providers) do
			if known.key == key then
				known.fn = fn
				return
			end
		end
	end
	providers[#providers + 1] = { fn = fn, key = key }
end

function ns.TownCardOn()
	local db = ns.db
	return db and db.enabled and db.world.townCard ~= false or false
end

local function Rested() return Clean(Safe(IsResting)) and true or false end

local function Place() return Clean(Safe(GetRealZoneText)) or Clean(Safe(GetZoneText)) end

-- What the providers have to say now, in their order (one failing: left out).
function ns.TownLines()
	local lines = {}
	for index, provider in ipairs(providers) do
		local ok, line = pcall(provider.fn)
		if ok and type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
			lines[#lines + 1] = { text = line.text, onClick = type(line.onClick) == "function" and line.onClick or nil, hint = line.hint,
				alone = type(line.alone) == "table" and line.alone or nil, order = ORDER[provider.key] or 10, index = index }
		end
	end
	table.sort(lines, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.index < b.index
	end)
	return lines
end

local function Arrive()
	if not (ns.TownCardOn() and Rested()) then return end
	if InCombatLockdown() or ns.inCombat then
		pending = true
		return
	end
	pending = false
	local place = Place()
	if not place or (told[place] and GetTime() - told[place] < AGAIN) then return end
	local lines = ns.TownLines()
	if not lines[1] then return end
	told[place] = GetTime()
	-- (a line alone with words of its own for that: a notice of its own, in them)
	local alone = not lines[2] and lines[1].alone
	if alone then
		return ns.Toast(alone.title, alone.text, { kicker = place, onClick = lines[1].onClick, hint = lines[1].hint, kind = "town",
			still = Rested })
	end
	ns.Toast(L.TOWN_TITLE, nil, { kicker = place, lines = lines, duration = SHOW_TIME, kind = "town", still = Rested })
end

-- Wanderer's own lines: the repairs (the repair reminder's, said here now; alone, in its own words), the
-- mailbox (the game's word; Wanderer Mail says more).
ns.TownLine(function()
	local db = ns.db
	if not (db and db.merchant.repairReminder) then return nil end
	local wear = ns.Wear and ns.Wear()
	if not wear or wear >= WORN then return nil end
	return { text = L.TOWN_REPAIR:format(wear), alone = { title = L.REPAIR_TITLE, text = L.REPAIR_TEXT:format(wear) } }
end, "repair")
ns.TownLine(function()
	if Clean(Safe(HasNewMail)) then return { text = L.TOWN_MAIL } end
end, "mail")

-- Back in a city or an inn with worn equipment, the town card off: a smith would be welcome (a notice of its
-- own; the card on, its repair line says it).
local function OnRest()
	local db = ns.db
	if not (db and db.enabled and db.merchant.repairReminder) or not Rested() then return end
	if ns.TownCardOn() then return end
	local wear = ns.Wear and ns.Wear()
	if not wear or wear >= VERY_WORN or GetTime() - lastRepair < REPAIR_AGAIN then return end
	lastRepair = GetTime()
	ns.Toast(L.REPAIR_TITLE, L.REPAIR_TEXT:format(wear), { duration = 5, corner = true })
end

function ns.InitTown()
	local rest = CreateFrame("Frame")
	rest:RegisterEvent("PLAYER_ENTERING_WORLD")
	rest:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	rest:RegisterEvent("PLAYER_UPDATE_RESTING")
	rest:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_UPDATE_RESTING" then return OnRest() end
		C_Timer.After(2, OnRest)
	end)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PLAYER_UPDATE_RESTING")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(_, event, isLogin, isReload)
		if event == "PLAYER_REGEN_ENABLED" then
			-- (once: left the town meanwhile, a later fight brings nothing back)
			if pending then
				pending = false
				C_Timer.After(SETTLE, Arrive)
			end
			return
		end
		local now = Rested()
		-- (logging in or reloading where you rest: no arrival, nor when the game says so a moment later)
		if event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload) then
			resting = now
			quietUntil = GetTime() + SETTLE * 2
			return
		end
		-- (the first word on resting just after it: the state settling, once)
		if event == "PLAYER_UPDATE_RESTING" and quietUntil > 0 then
			local quiet = GetTime() < quietUntil
			quietUntil = 0
			if quiet then
				resting = now
				return
			end
		end
		-- (walking in: at once; after a loading screen, a moment for the place to settle)
		if now and not resting then
			resting = now
			if event == "PLAYER_UPDATE_RESTING" then return Arrive() end
			return C_Timer.After(SETTLE, Arrive)
		end
		resting = now
	end)
	resting = Rested()
end
