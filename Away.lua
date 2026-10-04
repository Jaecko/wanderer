local _, ns = ...
local L = ns.L

-- While you are away (the game's "Away" mark, set by itself after a while or
-- with /afk), an ambiance of your choice (option): the interface fades (the
-- chat stays: someone may talk to you) and a quiet card names your character.
--   contemplation  the camera turns slowly around your character;
--   hearth         by the fire: your character sits and rests; the camera
--                  faces them, a little aside, a few yards away. The game's
--                  own campfire can burn in
--                  front of them: a key of Wanderer lights it (the game's
--                  "Basic Campfire") and settles you there. Nothing added;
--   panorama       the camera steps far back and turns over the landscape;
--   journal        a page of the journal: what you lived today.
-- The camera only turns around your character (the free camera, as with the
-- left mouse button: your character never turns) and changes its distance;
-- Wanderer counts every degree and every yard it moved, and when the
-- ambiance ends it turns them back, softly, to the camera you had. Moving the
-- camera yourself (holding a mouse button to turn it, the wheel to zoom) or a
-- key ends the ambiance at once; a mouse simply moved does not. Still away
-- and quiet for a while, it comes back. The mark gone (moving, acting, /afk), everything is back. Never during
-- a fight, in an instance, on a flight or in a conversation.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

ns.AWAY_STYLES = { "contemplation", "hearth", "panorama", "journal" }

local TURN_SPEED = 0.025 -- of the game's camera turning speed: slow, like a film
local BACK_SPEED = 0.6 -- of the game's camera turning speed: the way back, soft but quick
local FOLLOW = "cameraSmoothStyle" -- the game swinging the camera behind you as you walk: held still meanwhile
local STEP_BACK = { contemplation = 3, panorama = 18 } -- yards
local TURNING = { contemplation = true, panorama = true }
local RESUME_AFTER = 30 -- seconds of calm, still away, before the ambiance comes back
local ZOOM_SETTLES = 3 -- seconds for the ambiance's own camera moves to end
local ZOOM_MOVED = 0.5 -- yards: the wheel turned by you
local FADE_IN, FADE_OUT = 1.5, 0.6
local TODAY_LINES = 8
local CHECK_EVERY = 1

-- By the fire: facing the character, a little aside, a few yards away. The
-- distance is the same each time (from all the way in), the turn an exact
-- angle. The height is left as it is: the game stops a lowered camera at the
-- ground, and a move it stopped could not be undone exactly.
local CLOSE = 11 -- yards: far enough for the character to sit near the horizon, high on the screen
local ALL_THE_WAY = 50 -- yards
local TURN = 165 -- degrees: facing them, a little aside (the fire in front of them seen too)
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
local zoomBefore -- your distance when the ambiance began
local yaw = 0 -- degrees the ambiance turned the camera (right is positive), moves ended
local spin -- the turn going on: direction, degrees a second, start, end
local followBefore -- your setting, while Wanderer holds the camera still
local moves = 0
local cardAlpha, sinceCheck = 0, 0
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

-- The turn going on, in degrees so far (never past its planned end).
local function Turned()
	if not spin then return 0 end
	local elapsed = math.min(GetTime(), spin.ends or math.huge) - spin.start
	return spin.dir * spin.rate * math.max(0, elapsed)
end

local function StopSpin()
	if not spin then return end
	yaw = yaw + Turned()
	Safe(spin.dir > 0 and MoveViewRightStop or MoveViewLeftStop)
	spin = nil
end

-- The camera turns around your character (dir 1: right, -1: left), for some
-- degrees or until stopped. Without the game's turning moves: one exact cut.
local function Spin(dir, speed, degrees)
	StopSpin()
	local start = dir > 0 and MoveViewRightStart or MoveViewLeftStart
	local stop = dir > 0 and MoveViewRightStop or MoveViewLeftStop
	if not (start and stop) then
		if degrees and FlipCameraYaw then
			Safe(FlipCameraYaw, dir * degrees)
			yaw = yaw + dir * degrees
		end
		return
	end
	local rate = CameraSpeed("cameraYawMoveSpeed", 180) * speed
	Safe(start, speed)
	local now = GetTime()
	spin = { dir = dir, rate = rate, start = now, ends = degrees and now + degrees / rate or nil }
	if degrees then
		local this = spin
		C_Timer.After(degrees / rate, function() if spin == this then StopSpin() end end)
	end
end

-- The game's camera following you while you walk: held still while the
-- ambiance owns the camera (every turn is counted), given back after.
local function HoldFollow(on)
	if on and not followBefore then
		followBefore = Clean(Safe(GetCVar, FOLLOW))
		if ns.root then ns.root.awayFollow = followBefore end -- given back even after a crash
		if followBefore and ns.WriteCVar then ns.WriteCVar(FOLLOW, "0") end
	elseif not on and followBefore then
		if ns.WriteCVar then ns.WriteCVar(FOLLOW, followBefore) end
		followBefore = nil
		if ns.root then ns.root.awayFollow = nil end
	end
end

local function CameraAway()
	moves = moves + 1
	-- Counted from the camera you have now: it is the one to come back to.
	StopSpin()
	yaw = 0
	zoomBefore = Clean(Safe(GetCameraZoom))
	HoldFollow(true)
	settleAt, settledZoom = GetTime() + ZOOM_SETTLES, nil
	if style == "hearth" then
		if CameraZoomIn and CameraZoomOut then
			Safe(CameraZoomIn, ALL_THE_WAY)
			Safe(CameraZoomOut, CLOSE)
		end
		Spin(1, MOVE, TURN)
		-- Seated, resting (the game does it only when it marks you away itself).
		local token = moves
		C_Timer.After(SIT_AFTER, function()
			if token == moves and style == "hearth" and DoEmote then Safe(DoEmote, "SIT") end
		end)
	end
	local back = STEP_BACK[style]
	if back and CameraZoomOut then Safe(CameraZoomOut, back) end
	if TURNING[style] then Spin(-1, TURN_SPEED) end
end

-- Back to your camera: every degree turned back the shortest way, softly,
-- and your distance; the game's following given back once it is there.
local function CameraBack()
	moves = moves + 1
	StopSpin()
	settleAt, settledZoom = nil, nil
	local turned = yaw % 360
	if turned > 180 then turned = turned - 360 end
	local done = moves
	local wait = 0
	if math.abs(turned) > 0.5 then
		Spin(turned > 0 and -1 or 1, BACK_SPEED, math.abs(turned))
		wait = math.abs(turned) / (CameraSpeed("cameraYawMoveSpeed", 180) * BACK_SPEED)
	end
	if zoomBefore and GetCameraZoom then
		local now = Clean(Safe(GetCameraZoom))
		if now and now > zoomBefore and CameraZoomIn then Safe(CameraZoomIn, now - zoomBefore) end
		if now and now < zoomBefore and CameraZoomOut then Safe(CameraZoomOut, zoomBefore - now) end
	end
	C_Timer.After(wait + 0.2, function()
		if done ~= moves then return end
		StopSpin()
		yaw = 0
		HoldFollow(false)
	end)
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
	-- A camera left held by a crash: your following setting comes back.
	if ns.root and ns.root.awayFollow then
		if ns.WriteCVar then ns.WriteCVar(FOLLOW, ns.root.awayFollow) end
		ns.root.awayFollow = nil
	end
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
