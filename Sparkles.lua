local _, ns = ...

-- Sparkles: the herb or the vein you come near shows the game's own gathering icon over it (grey when
-- your skill is too low), and quest objects too when asked; never the chairs, the mailboxes and the rest.
-- Nothing is drawn by Wanderer: the icon is the game's, the one its interact key gives world objects. The
-- game shows it on every object or none; Wanderer opens it only over the ones asked for, and lets the game
-- look a little farther ahead. Needs the game's interact key (Options, Controls). The player's own
-- values are kept and given back when it is off, at logout, or when another addon does this job.
-- Out of a fight only: the game locks these settings in one.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local SOFT = "softinteract"
local POLL = 0.25 -- seconds between two looks at the interaction target (some games never say it changed)

-- Held while on, with the value wanted: the game looks for objects farther than your reach (it still
-- stops near 15 yards).
local HELD = { SoftTargetInteractRange = "40", SoftTargetInteractOnlyInRange = "0" }
-- The icon over world objects, and their nameplate that carries it: open only over a chosen object.
local GATES = { "SoftTargetIconGameObject", "SoftTargetNameplateInteract" }

-- The cursor the game gives an object tells what it is (a file, a path or an atlas name).
local CURSORS = { GatherHerbs = "herb", Mine = "ore", UnableGatherHerbs = "herb", UnableMine = "ore" }
local WORDS = { { "herb", "herb" }, { "gather", "herb" }, { "mine", "ore" }, { "mining", "ore" } }

local cursorIds -- file id -> kind, read once
local probe -- a hidden texture the object's cursor is written on
local gate -- true or false as last written, nil: not known
local pending = false -- a change waiting for the end of the fight
local lastGuid, poller

-- What this character asked for (nil settings: off).
local function Settings()
	local db = ns.db
	local own = db and db.sparkles
	if not (db and db.enabled and type(own) == "table") then return nil end
	if not (own.nodes or own.questObjects) then return nil end
	return own
end

-- Another addon doing it (their own sparkles over the same settings, Compat.lua): left to it.
local function LeftToOthers()
	return ns.Yields ~= nil and ns.Yields("nodeSparkle") ~= nil
end

-- The game's interact key is on (its interaction target exists only then).
local function InteractKey()
	local value = tonumber(Clean(Safe(GetCVar, "SoftTargetInteract")))
	return value ~= nil and value > 0
end

local function Active()
	return Settings() ~= nil and not LeftToOthers() and InteractKey()
end

local function Read(name) return Clean(Safe(GetCVar, name)) end

-- Written only when it changes (every write wakes the game's own watchers).
local function Write(name, value)
	local current = Read(name)
	if current == nil or current == value then return end
	ns.WriteCVar(name, value)
end

-- The player's own values, kept for the whole account (the settings are the game's, not a character's);
-- still there after a crash: given back at the next login.
local function Originals()
	ns.root.sparkleCvars = type(ns.root.sparkleCvars) == "table" and ns.root.sparkleCvars or {}
	return ns.root.sparkleCvars
end

local function Same(a, b)
	if a == b then return true end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and y ~= nil and math.abs(x - y) < 0.001
end

-- A held setting changed by you since Wanderer wrote it (the game's options): your value is the one given back.
local function Adopt(name)
	local written, originals = ns.root.sparkleWritten, ns.root.sparkleCvars
	if type(written) ~= "table" or type(originals) ~= "table" or written[name] == nil then return end
	local now = Read(name)
	if now ~= nil and not Same(now, written[name]) then
		originals[name] = now
		written[name] = nil
	end
end

-- Written by Wanderer, remembered (to know a change of yours from its own).
local function HoldWrite(name, value)
	Adopt(name)
	Write(name, value)
	ns.root.sparkleWritten = type(ns.root.sparkleWritten) == "table" and ns.root.sparkleWritten or {}
	ns.root.sparkleWritten[name] = Read(name)
end

local function Hold()
	local originals = Originals()
	for name, value in pairs(HELD) do
		local own = Read(name)
		if own ~= nil then
			if originals[name] == nil then originals[name] = own end
			HoldWrite(name, value)
		end
	end
	for _, name in ipairs(GATES) do
		if originals[name] == nil then originals[name] = Read(name) or false end
		Adopt(name)
	end
end

local function Release()
	gate = nil
	-- (locked in a fight: kept, given back at the next chance)
	if InCombatLockdown() then return end
	local originals = ns.root and ns.root.sparkleCvars
	if type(originals) ~= "table" then return end
	for name in pairs(originals) do
		Adopt(name)
		local value = originals[name]
		if value ~= false then Write(name, value) end
	end
	ns.root.sparkleCvars, ns.root.sparkleWritten = nil, nil
end

-- The icon over the interaction target, or not. A player who has them on everywhere keeps them so.
local function SetGate(open)
	if open == gate or InCombatLockdown() then return end
	local originals = ns.root and ns.root.sparkleCvars
	if type(originals) ~= "table" then return end
	gate = open
	for _, name in ipairs(GATES) do
		Adopt(name)
		local own = originals[name]
		if own and own ~= "0" then
			HoldWrite(name, own)
		elseif own ~= false then
			HoldWrite(name, open and "1" or "0")
		end
	end
end

-- Kind of the object from its cursor ("herb", "ore", or nil).
local function KnownCursors()
	if cursorIds then return cursorIds end
	cursorIds = {}
	if GetFileIDFromPath then
		for file, kind in pairs(CURSORS) do
			local id = Clean(Safe(GetFileIDFromPath, "Interface\\Cursor\\" .. file))
			if type(id) == "number" then cursorIds[id] = kind end
		end
	end
	return cursorIds
end

local function KindOfWords(text)
	if type(text) ~= "string" then return nil end
	text = text:lower()
	for _, pair in ipairs(WORDS) do
		if text:find(pair[1], 1, true) then return pair[2] end
	end
	return nil
end

local function CursorKind(unit)
	if not SetUnitCursorTexture then return nil end
	if not probe then
		probe = UIParent:CreateTexture(nil, "BACKGROUND")
		probe:Hide()
	end
	if not Safe(SetUnitCursorTexture, probe, unit, nil, true) then return nil end
	local texture = Clean(Safe(probe.GetTexture, probe))
	if type(texture) == "number" and KnownCursors()[texture] then return KnownCursors()[texture] end
	return KindOfWords(texture) or KindOfWords(probe.GetAtlas and Clean(Safe(probe.GetAtlas, probe)))
end

local QUEST_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

-- An object one of your quests asks for.
local function ForQuest(unit)
	if C_QuestLog and Clean(Safe(C_QuestLog.UnitIsRelatedToActiveQuest, unit)) == true then return true end
	if not (QUEST_LINE and C_TooltipInfo and C_TooltipInfo.GetUnit) then return false end
	local data = Clean(Safe(C_TooltipInfo.GetUnit, unit))
	for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		if Clean(line.type) == QUEST_LINE then return true end
	end
	return false
end

-- What the interaction target is: "node" (an herb, a vein), "quest", or nil (anything else).
function ns.SparkleKind(unit)
	unit = unit or SOFT
	if Clean(Safe(UnitIsGameObject, unit)) ~= true then return nil end
	if CursorKind(unit) then return "node" end
	if ForQuest(unit) then return "quest" end
	return nil
end

-- The interaction target looked at: the icon opened over a chosen object.
local function Evaluate()
	if InCombatLockdown() then return end
	local own = Active() and Settings()
	if not own then return end
	local kind = ns.SparkleKind(SOFT)
	SetGate((kind == "node" and own.nodes or kind == "quest" and own.questObjects) and true or false)
end

local function Poll(_, elapsed)
	poller.wait = (poller.wait or 0) - elapsed
	if poller.wait > 0 then return end
	poller.wait = POLL
	local guid = Clean(Safe(UnitGUID, SOFT)) or false
	if guid == lastGuid then return end
	lastGuid = guid
	Evaluate()
end

function ns.RefreshSparkles()
	if not ns.root then return end
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	if Active() then
		Hold()
		gate = nil
		lastGuid = nil
		Evaluate()
	else
		Release()
	end
	if poller then poller:SetScript("OnUpdate", Active() and Poll or nil) end
end

local initialized = false
function ns.InitSparkles()
	if initialized then return end
	initialized = true
	poller = CreateFrame("Frame")
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_SOFT_INTERACT_CHANGED" then
			Evaluate()
		elseif event == "PLAYER_REGEN_DISABLED" then
			-- Closed just before the game locks it: no icon left open through the fight.
			if ns.root and ns.root.sparkleCvars then SetGate(false) end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if pending then ns.RefreshSparkles() else Evaluate() end
		elseif event == "PLAYER_LOGOUT" then
			-- The game left as it was found, should Wanderer be gone at the next start.
			Release()
		else
			ns.RefreshSparkles()
		end
	end)
	-- Settings changed, profile switched: brought in line.
	if ns.RefreshAll then hooksecurefunc(ns, "RefreshAll", ns.RefreshSparkles) end
	ns.RefreshSparkles()
end

