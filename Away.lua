local _, ns = ...
local L = ns.L

-- While you are away (the game's "Away" mark, set by itself after a while or
-- with /afk), an ambiance of your choice (option): the interface fades (the
-- chat stays: someone may talk to you) and a quiet card names your character.
--   contemplation  the camera turns slowly around your character;
--   hearth         by the fire: your character sits and rests; the camera
--                  faces them, a little aside, a few yards away, down on the
--                  ground looking up. The game's own campfire can burn in
--                  front of them: a key of Wanderer lights it (the game's
--                  "Basic Campfire") and settles you there. Nothing added;
--   panorama       the camera steps far back and turns over the landscape;
--   journal        a page of the journal: what you lived today.
-- The camera is kept in the game's memory (view 5) when the absence begins,
-- once, and glides back there softly when the ambiance ends. Moving the
-- camera yourself (holding a mouse button to turn it, the wheel to zoom) or a
-- key ends the ambiance at once; a mouse simply moved does not. Still away
-- and quiet for a while, it comes back. The mark gone (moving, acting, /afk), everything is back. Never during
-- a fight, in an instance, on a flight or in a conversation.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

ns.AWAY_STYLES = { "contemplation", "hearth", "panorama", "journal" }

local VIEW = 5 -- the game's camera memory (SaveView/SetView)
local TURN_SPEED = 0.025 -- of the game's camera turning speed: slow, like a film
local STEP_BACK = { contemplation = 3, panorama = 18 } -- yards
local TURNING = { contemplation = true, panorama = true }
local RESUME_AFTER = 30 -- seconds of calm, still away, before the ambiance comes back
local ZOOM_SETTLES = 3 -- seconds for the ambiance's own camera moves to end
local ZOOM_MOVED = 0.5 -- yards: the wheel turned by you
local FADE_IN, FADE_OUT = 1.5, 0.6
local TODAY_LINES = 8
local CHECK_EVERY = 1

-- By the fire: facing the character, a little aside, a few yards away, down
-- on the ground looking up. Every move ends at a fixed place, so the framing
-- is the same each time: the distance from all the way in, the turn by an
-- exact angle (FlipCameraYaw), the height at the ground (the camera goes
-- down until the ground stops it: the game's own limit).
local CLOSE = 11 -- yards: far enough for the character to sit near the horizon, high on the screen
local ALL_THE_WAY = 50 -- yards
local TURN = 165 -- degrees: facing them, a little aside (the fire in front of them seen too)
local DOWN_FOR = 1.5 -- seconds: long enough to reach the ground from anywhere
local LIFT_FOR = 0.05 -- seconds: then lifted a hair, looking less at the sky (the game moves fast here)
local MOVE = 0.5 -- of the game's camera speeds: a slow, smooth move
local SIT_AFTER = 0.3 -- seconds
local CAMPFIRE = 818 -- the game's "Basic Campfire" (cooking)
local CAMPFIRE_CAST = 2.2 -- seconds before sitting down by it

local card, kicker, nameText, line, list
local driver, keys
local style -- the ambiance running, or nil
local since -- when the absence began
local paused = false -- away, but you are here: the ambiance waits
local lastSign = 0 -- the last time you gave a sign
local turning, viewSaved, zoomBefore = false, false, nil
local moves = 0
local cardAlpha, sinceCheck = 0, 0
local viewKept = false -- the camera of before the absence, in the game's memory
local settleAt, settledZoom -- the zoom of the ambiance, watched for the wheel

local function Settings()
	local db = ns.db
	return db and db.enabled and db.away.enabled and db.away or nil
end

local function IsAway()
	return Clean(Safe(UnitIsAFK, "player")) and true or false
end

-- Only in peace: no fight, no instance, no flight, no conversation.
local function Peaceful()
	if InCombatLockdown() or ns.inCombat or ns.sceneActive then return false end
	if Clean(Safe(IsInInstance)) then return false end
	return not Clean(Safe(UnitOnTaxi, "player"))
end

local function Place()
	return Clean(Safe(GetSubZoneText)) or Clean(Safe(GetZoneText))
end

-- The card: who, where, since when; or today's page of the journal.
local function Fill()
	local minutes = math.floor((GetTime() - since) / 60)
	local text = minutes < 1 and L.AWAY_MOMENT or L.AWAY_SINCE:format(minutes)
	local place = Place()
	if place and style ~= "journal" then text = text .. "  ·  " .. place end
	line:SetText(text)
	local rows = {}
	if style == "journal" then
		for _, entry in ipairs(ns.JournalToday and ns.JournalToday(TODAY_LINES) or {}) do
			rows[#rows + 1] = ("|T%s:16:16:0:0|t  %s  |cff8c8070%s|r"):format(entry.icon or "", entry.text, entry.time or "")
		end
		if not rows[1] then rows[1] = "|cffa09080" .. L.AWAY_TODAY_EMPTY .. "|r" end
	end
	list:SetText(table.concat(rows, "\n"))
	list:SetShown(rows[1] ~= nil)
	local margin = ns.Skin.Margin() + 14
	local width = math.max(U.Measure(nameText, "GetStringWidth", 200), U.Measure(line, "GetStringWidth", 160),
		list:IsShown() and U.Measure(list, "GetStringWidth", 300) or 0, U.Measure(kicker, "GetStringWidth", 80))
	local height = U.Measure(kicker, "GetStringHeight", 12) + 6 + U.Measure(nameText, "GetStringHeight", 26) + 6
		+ U.Measure(line, "GetStringHeight", 14) + (list:IsShown() and (14 + U.Measure(list, "GetStringHeight", 100)) or 0)
	card:SetSize(math.min(width, 640) + margin * 2, height + margin * 2)
	ns.Skin.Get(card):Layout()
end

-- Camera ---------------------------------------------------------------------------------

local function CameraSpeed(cvar, default)
	return tonumber(Clean(Safe(GetCVar, cvar)) or "") or default
end

-- A camera move of the game for some time (the game turns at a known speed).
local function Move(start, stop, degrees, speedCVar, default)
	if not (start and stop) then return end
	local token = moves
	Safe(start, MOVE)
	C_Timer.After(degrees / (CameraSpeed(speedCVar, default) * MOVE), function()
		if token == moves then Safe(stop) end
	end)
end

local function CameraAway()
	moves = moves + 1
	-- Kept to come back exactly there: once for the whole absence (a camera
	-- moved during a pause is not the one to come back to).
	if not viewKept then
		viewKept = true
		viewSaved = SaveView ~= nil and SetView ~= nil
		if viewSaved then Safe(SaveView, VIEW) end
		zoomBefore = Clean(Safe(GetCameraZoom))
	end
	settleAt, settledZoom = GetTime() + ZOOM_SETTLES, nil
	if style == "hearth" then
		if CameraZoomIn and CameraZoomOut then
			Safe(CameraZoomIn, ALL_THE_WAY)
			Safe(CameraZoomOut, CLOSE)
		end
		if FlipCameraYaw then
			Safe(FlipCameraYaw, TURN)
		else
			Move(MoveViewRightStart, MoveViewRightStop, TURN, "cameraYawMoveSpeed", 180)
		end
		-- Down to the ground, where the game stops the camera.
		if MoveViewDownStart and MoveViewDownStop then
			local down = moves
			Safe(MoveViewDownStart, MOVE)
			C_Timer.After(DOWN_FOR, function()
				if down ~= moves then return end
				Safe(MoveViewDownStop)
				if not (MoveViewUpStart and MoveViewUpStop) then return end
				Safe(MoveViewUpStart, MOVE)
				C_Timer.After(LIFT_FOR, function() if down == moves then Safe(MoveViewUpStop) end end)
			end)
		end
		-- Seated, resting (the game does it only when it marks you away itself).
		local token = moves
		C_Timer.After(SIT_AFTER, function()
			if token == moves and style == "hearth" and DoEmote then Safe(DoEmote, "SIT") end
		end)
	end
	local back = STEP_BACK[style]
	if back and CameraZoomOut then Safe(CameraZoomOut, back) end
	if TURNING[style] and MoveViewLeftStart then
		Safe(MoveViewLeftStart, TURN_SPEED)
		turning = true
	end
end

-- Back behind the character in one cut (the game's view blend set to instant
-- for that moment), never a slow drift.
-- Back to the camera of before the absence, gliding softly (the game's own
-- move between views).
local function CameraBack()
	moves = moves + 1
	for _, stop in ipairs({ MoveViewRightStop, MoveViewDownStop, MoveViewUpStop, turning and MoveViewLeftStop or nil }) do Safe(stop) end
	turning = false
	settleAt, settledZoom = nil, nil
	if viewSaved then
		Safe(SetView, VIEW)
	elseif zoomBefore and GetCameraZoom then
		local now = Clean(Safe(GetCameraZoom))
		if now and now > zoomBefore and CameraZoomIn then Safe(CameraZoomIn, now - zoomBefore) end
		if now and now < zoomBefore and CameraZoomOut then Safe(CameraZoomOut, zoomBefore - now) end
	end
end

-- The ambiance ------------------------------------------------------------------------------

local function Begin()
	local settings = Settings()
	if style or not settings or not IsAway() or not Peaceful() then return end
	style = settings.style
	paused = false
	since = since or GetTime()
	ns.SetCurtainReason("away", true)
	CameraAway()
	kicker:SetText((style == "journal" and L.AWAY_TODAY or L.AWAY_KICKER):upper())
	nameText:SetText(U.FullName("player") or "")
	card:ClearAllPoints()
	if style == "journal" then
		card:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	elseif style == "hearth" then
		card:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -140, 120) -- aside, the character in the middle
	else
		card:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
	end
	card:SetScale(ns.Skin.Scale())
	Fill()
	cardAlpha = 0
	card:SetAlpha(0)
	card:Show()
	keys:Show()
	driver:Show()
end

-- The ambiance ends; away still, it may come back (pause), or not (end).
local function Finish(pause)
	if style then
		style = nil
		CameraBack()
		ns.SetCurtainReason("away", false)
	end
	paused = pause and IsAway() and Settings() ~= nil or false
	lastSign = GetTime()
	if not paused then
		since = nil
		keys:Hide()
		viewKept, viewSaved, zoomBefore = false, false, nil
	end
end

-- A sign of you: the ambiance steps aside, the camera back behind you.
local function Sign()
	lastSign = GetTime()
	if style then Finish(true) end
end

function ns.RefreshAway()
	if not driver then return end
	if style and (not Settings() or not IsAway()) then Finish(false) end
	if not style and not paused and IsAway() then Begin() end
end

function ns.InitAway()
	ns.InitCampfire()
	card = ns.Skin.CreateWindow("WandererAwayCard", "DIALOG")
	card:EnableMouse(false)
	local margin = ns.Skin.Margin() + 14
	kicker = ns.Skin.CreateText(card, "GameTooltipTextSmall", 0.85, 0.75, 0.5)
	kicker:SetPoint("TOP", card, "TOP", 0, -margin)
	kicker:SetJustifyH("CENTER")
	nameText = ns.Skin.CreateText(card, "GameFontNormalHuge", 1, 0.82, 0)
	nameText:SetPoint("TOP", kicker, "BOTTOM", 0, -6)
	nameText:SetJustifyH("CENTER")
	line = ns.Skin.CreateText(card, "GameTooltipText", 0.9, 0.86, 0.78)
	line:SetPoint("TOP", nameText, "BOTTOM", 0, -6)
	line:SetJustifyH("CENTER")
	list = ns.Skin.CreateText(card, "GameTooltipText", 0.92, 0.9, 0.86)
	list:SetPoint("TOP", line, "BOTTOM", 0, -14)
	list:SetJustifyH("LEFT")
	list:SetSpacing(4)
	card:Hide()

	-- Keys are a sign of you; they still reach the game (never kept).
	keys = CreateFrame("Frame", nil, UIParent)
	keys:Hide()
	if keys.EnableKeyboard then keys:EnableKeyboard(true) end
	if keys.SetPropagateKeyboardInput then keys:SetPropagateKeyboardInput(true) end
	keys:SetScript("OnKeyDown", function() Sign() end)

	-- While away: the card's fades, the time moving on, the signs of you, and
	-- the ambiance back after a quiet while.
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", function(self, elapsed)
		cardAlpha = ns.Skin.Fade(card, style and 1 or 0, elapsed, FADE_IN, FADE_OUT)
		-- The camera moved by you: a mouse button held to turn it, the wheel.
		if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then Sign() end
		if style and settleAt and GetTime() >= settleAt then
			local zoom = Clean(Safe(GetCameraZoom))
			if zoom and not settledZoom then
				settledZoom = zoom
			elseif zoom and math.abs(zoom - settledZoom) > ZOOM_MOVED then
				Sign()
			end
		end
		sinceCheck = sinceCheck + elapsed
		if sinceCheck >= CHECK_EVERY then
			sinceCheck = 0
			if style then Fill() end
			if paused and GetTime() - lastSign >= RESUME_AFTER then Begin() end
		end
		if not style and not paused and cardAlpha <= 0 then
			card:Hide()
			self:Hide()
		end
	end)

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_FLAGS_CHANGED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_FLAGS_CHANGED" and unit ~= "player" then return end
		if event == "PLAYER_REGEN_DISABLED" then return Finish(true) end
		if event == "PLAYER_ENTERING_WORLD" then return Finish(false) end
		if IsAway() then
			if not paused then Begin() end
		else
			Finish(false)
		end
	end)
end

-- By the fire, for real: a key (Key Bindings > Wanderer) lights the game's
-- campfire if you know it (the game lets a key cast it, never an addon by
-- itself), then you sit down by it, away. Without it: you simply settle there.
local campfire, lastLit = nil, 0

local function CampfireReady()
	if not campfire or InCombatLockdown() then return end
	local known = (C_SpellBook and C_SpellBook.IsSpellKnown and Clean(Safe(C_SpellBook.IsSpellKnown, CAMPFIRE)))
		or (IsSpellKnown and Clean(Safe(IsSpellKnown, CAMPFIRE)))
	local name = known and ((C_Spell and C_Spell.GetSpellName and Clean(Safe(C_Spell.GetSpellName, CAMPFIRE)))
		or (GetSpellInfo and Clean((Safe(GetSpellInfo, CAMPFIRE)))))
	campfire:SetAttribute("type", name and "spell" or nil)
	campfire:SetAttribute("spell", name)
	campfire.lights = name ~= nil
end

function ns.InitCampfire()
	local ok, button = pcall(CreateFrame, "Button", "WandererCampfire", UIParent, "SecureActionButtonTemplate")
	if not ok or not button then return end
	campfire = button
	campfire:RegisterForClicks("AnyDown", "AnyUp")
	campfire:HookScript("PostClick", function(self)
		if InCombatLockdown() or GetTime() - lastLit < 1 then return end
		lastLit = GetTime()
		C_Timer.After(self.lights and CAMPFIRE_CAST or 0, function() ns.GoAway() end)
	end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", CampfireReady)
	CampfireReady()
end

-- Away now: your character sits down, then the game's own /afk; to try an
-- ambiance, or for a picture.
function ns.GoAway()
	if IsAway() then return end
	if DoEmote then Safe(DoEmote, "SIT") end
	C_Timer.After(0.6, function()
		if not IsAway() and SendChatMessage then Safe(SendChatMessage, "", "AFK") end
	end)
end
