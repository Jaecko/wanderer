local _, ns = ...
local L = ns.L

-- Threat: how much a monster is after you, and a word when you lose it.
--
-- Your share of the target's threat, in a group or a dungeon and during a
-- fight, is one of the pieces of the line over the target frame
-- (TargetInfo.lua). Not when the game already writes it there itself (its
-- "threat as a number" setting).
--
-- In dungeons and raids, when a monster that was on you turns to someone
-- else, a short line appears in the middle of the screen with a soft sound.
-- Only for the one holding the monsters (a tank, or no role chosen): for the
-- others, losing a monster is good news.
--
-- The game may keep threat secret from addons; then nothing is said.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local FADE_IN, FADE_OUT = 0.35, 0.9
local ALERT_TIME = 2.2 -- seconds the alert stays before fading
local ALERT_GAP = 1.5 -- seconds between two alerts
local COLORS = { -- by the game's threat status (0 to 3)
	[0] = { 0.75, 0.75, 0.75 }, [1] = { 1, 0.85, 0.3 }, [2] = { 1, 0.55, 0.2 }, [3] = { 1, 0.3, 0.25 },
}

local alert, alertText, driver
local alertTarget, alertShown = 0, 0
local holding = {} -- monster GUID -> true while it is on you
local lastAlert = 0

-- In a group (and whether it is a dungeon or a raid).
local function InGroupContent()
	local inside, kind = Safe(IsInInstance)
	kind = Clean(kind)
	if Clean(inside) and (kind == "party" or kind == "raid") then return true, true end
	return Clean(Safe(IsInGroup)) and true or false, false
end

-- isTanking, status, percent (nil when unknown or secret).
local function Situation(unit)
	if not UnitDetailedThreatSituation then return end
	local tanking, status, percent = Safe(UnitDetailedThreatSituation, "player", unit)
	if U.IsSecret(tanking) or U.IsSecret(status) or U.IsSecret(percent) then return end
	return tanking, status, percent
end

-- The piece for the line over the target frame: text and color, or nil.
function ns.ThreatPiece()
	local db = ns.db
	if not (db and db.enabled and db.threat.show) then return end
	if Clean(Safe(GetCVar, "threatShowNumeric")) == "1" then return end -- the game writes it already
	if not (Clean(Safe(UnitAffectingCombat, "player")) and Clean(Safe(UnitCanAttack, "player", "target"))) then return end
	if not InGroupContent() then return end
	local _, status, percent = Situation("target")
	if not percent then return end
	return L.THREAT_PERCENT:format(math.floor(percent + 0.5)), COLORS[status or 0] or COLORS[0]
end

-- The alert --------------------------------------------------------------------------------

local function Holder()
	local role = Clean(Safe(UnitGroupRolesAssigned, "player"))
	return role == nil or role == "TANK" or role == "NONE"
end

local function Alert(name)
	if GetTime() - lastAlert < ALERT_GAP then return end
	lastAlert = GetTime()
	alertText:SetText(L.THREAT_LOST:format(name or "?"))
	alertShown, alertTarget = 0, 1
	alert:Show()
	driver:Show()
	if SOUNDKIT and SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING then
		pcall(PlaySound, SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING, "SFX")
	end
end

local function OnThreat(unit)
	local db = ns.db
	if not (db and db.enabled and db.threat.alert) then return end
	local _, instance = InGroupContent()
	if not instance or not Holder() then return end
	local guid = Clean(Safe(UnitGUID, unit))
	if not guid then return end
	local tanking = Situation(unit)
	if tanking == nil then return end
	if tanking then
		holding[guid] = true
	elseif holding[guid] then
		holding[guid] = nil
		-- Still fighting (not dead, not reset): it went to someone else.
		if Clean(Safe(UnitAffectingCombat, unit)) and not Clean(Safe(UnitIsDead, unit)) then
			Alert(Clean(Safe(UnitName, unit)))
		end
	end
end

local function OnUpdate(_, elapsed)
	alertShown = alertShown + elapsed
	if alertShown > ALERT_TIME then alertTarget = 0 end
	if ns.Skin.Fade(alert, alertTarget, elapsed, FADE_IN, FADE_OUT) <= 0 and alertTarget == 0 then
		alert:Hide()
		driver:Hide()
	end
end

function ns.InitThreat()
	alert = CreateFrame("Frame", "WandererThreatAlert", UIParent)
	alert:SetFrameStrata("HIGH")
	alert:SetSize(400, 30)
	alert:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	alert:SetAlpha(0)
	alert:Hide()
	if alert.SetIgnoreParentAlpha then alert:SetIgnoreParentAlpha(true) end
	alertText = ns.Skin.CreateText(alert, "GameFontNormalLarge", 1, 0.45, 0.3)
	alertText:SetPoint("CENTER")
	alertText:SetJustifyH("CENTER")

	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", OnUpdate)
	driver:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_REGEN_ENABLED" then
			wipe(holding)
		elseif unit then
			OnThreat(unit)
		end
	end)
end
