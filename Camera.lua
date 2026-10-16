local _, ns = ...

-- The camera comes closer to the character you talk to: conversations,
-- quests, merchants, trainers, bankers, flight masters, auction houses. It
-- frames the character (a hidden setting of the game) and goes back to your
-- own distance once every window of that character is closed. Going from a
-- conversation to its merchant keeps it close: no back and forth.
--
-- The motion is slow and never hurried: a window must stay open a moment
-- before the camera moves (opened and closed at once, nothing happens), and
-- it waits a little after the last one closes. The camera is always sent to
-- a distance (yours, or the close one), counted from where it really is, and
-- put right once it stands still (the game stops it on its way when a
-- conversation opens): a window opened again in the middle of a move never
-- sends it too far (first person) nor back and forth. Your camera settings
-- are given back only once it is at your distance: the game stops the
-- camera where it is when one is written.
--
-- The player's values are kept in the saved variables while the camera is
-- borrowed: they come back even after a crash.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local DISTANCE = 3.5 -- yards, over the shoulder; closer than this, the camera is left where it is
local SPEED = "6" -- slower zoom than the game's, for a soft movement
local SETTINGS = { -- set while the camera is borrowed only
	test_cameraTargetFocusInteractEnable = "1",
	cameraZoomSpeed = SPEED,
}
local HOLD_DELAY = 0.4 -- a window must stay open this long before the camera moves
local RELEASE_DELAY = 1 -- a window may open right after another one

-- Windows of a character: the event that opens one, the one that closes it.
local HOLDS = {
	GOSSIP_SHOW = "gossip", QUEST_GREETING = "quest", QUEST_DETAIL = "quest", QUEST_PROGRESS = "quest",
	QUEST_COMPLETE = "quest", MERCHANT_SHOW = "merchant", TRAINER_SHOW = "trainer", BANKFRAME_OPENED = "bank",
	TAXIMAP_OPENED = "taxi", AUCTION_HOUSE_SHOW = "auction",
}
local RELEASES = {
	GOSSIP_CLOSED = "gossip", QUEST_FINISHED = "quest", MERCHANT_CLOSED = "merchant", TRAINER_CLOSED = "trainer",
	BANKFRAME_CLOSED = "bank", TAXIMAP_CLOSED = "taxi", AUCTION_HOUSE_CLOSED = "auction",
}

local holders = {} -- windows open, kind -> true
local holdToken, releaseToken = 0, 0

local function Saved() return ns.root and ns.root.sceneCamera end

-- A move: from where the camera really is (the game stops it where it is
-- when a conversation opens, or when a camera setting is written), then
-- looked at four times a second; once it stands still, put right if it is
-- not where it was sent (twice at most), then what comes next is done.
local LOOK_EVERY = 0.25 -- seconds
local LOOK_LONGEST = 10 -- seconds: it never waits longer than this
local CORRECTIONS = 2
local move -- the move under way
local ours -- (a zoom asked by Wanderer, not by you)

-- You zoom yourself: your distance is yours, nothing is put right.
if hooksecurefunc and CameraZoomIn and CameraZoomOut then
	local function Yours()
		if not ours and move then move.yours = true end
	end
	hooksecurefunc("CameraZoomIn", Yours)
	hooksecurefunc("CameraZoomOut", Yours)
end

local function Send(distance)
	local seen = Clean(Safe(GetCameraZoom))
	if not (seen and distance) then return end
	ours = true
	if seen > distance + 0.1 and CameraZoomIn then
		Safe(CameraZoomIn, seen - distance)
	elseif seen < distance - 0.1 and CameraZoomOut then
		Safe(CameraZoomOut, distance - seen)
	end
	ours = nil
end

local function Look(this)
	if move ~= this then return end
	-- (one reading per moment: the camera is seen still only after time went by)
	local now = GetTime()
	if this.at and now - this.at < LOOK_EVERY / 2 then return C_Timer.After(LOOK_EVERY, function() Look(this) end) end
	this.at = now
	local seen = Clean(Safe(GetCameraZoom))
	local still = seen and this.last and math.abs(seen - this.last) < 0.02
	this.last = seen
	if not still and GetTime() < this.giveUp then return C_Timer.After(LOOK_EVERY, function() Look(this) end) end
	-- Standing still: not where it was sent (the game stopped it on its way), put right.
	if still and not this.yours and this.tries < CORRECTIONS and math.abs(seen - this.distance) > 0.3
		and GetTime() < this.giveUp then
		this.tries, this.last = this.tries + 1, nil
		Send(this.distance)
		return C_Timer.After(LOOK_EVERY, function() Look(this) end)
	end
	move = nil
	if this.done then this.done() end
end

-- The camera sent to a distance; done (optional) once it is there and still.
local function ZoomTo(distance, done)
	local this = { distance = distance, done = done, tries = 0, giveUp = GetTime() + LOOK_LONGEST }
	move = this
	Send(distance)
	C_Timer.After(LOOK_EVERY, function() Look(this) end)
end

-- saved.zoom: the player's distance; saved.aim: where Wanderer sent the camera.
local function ZoomIn()
	if not (GetCameraZoom and CameraZoomIn) then return end
	local saved = Saved()
	if saved then
		-- Still going back: it comes close again, from where it is now.
		if saved.leaving then
			saved.leaving = false
			if saved.zoom and saved.zoom > DISTANCE then
				ZoomTo(DISTANCE)
				saved.aim = DISTANCE
			end
		end
		return
	end
	saved = { zoom = Clean(Safe(GetCameraZoom)), cvars = {} }
	saved.aim = saved.zoom
	for cvar, value in pairs(SETTINGS) do
		local current = Clean(Safe(GetCVar, cvar))
		if current then
			saved.cvars[cvar] = current
			ns.WriteCVar(cvar, value, true)
		end
	end
	ns.root.sceneCamera = saved
	if saved.zoom and saved.zoom > DISTANCE then
		ZoomTo(DISTANCE)
		saved.aim = DISTANCE
	end
end

-- Back to the player's distance; the slow speed stays until the camera is there.
local function ZoomOut()
	local saved = Saved()
	if not saved or saved.leaving then return end
	saved.leaving = true
	saved.aim = saved.zoom
	-- Your settings given back only once the camera is there: a camera setting
	-- written stops it where it is (it would stay half way).
	ZoomTo(saved.zoom, function()
		-- Borrowed again meanwhile: it will be given back later.
		if Saved() ~= saved or not saved.leaving then return end
		for cvar, value in pairs(saved.cvars) do ns.WriteCVar(cvar, value) end
		ns.root.sceneCamera = nil
	end)
end

-- A window of a character opens: the camera comes closer (only for a
-- character, never for a mailbox or another object).
local function Hold(kind)
	local db = ns.db
	if not (db and db.enabled and db.scene.camera) then return end
	if not (Clean(Safe(UnitExists, "npc")) or Clean(Safe(UnitExists, "questnpc"))) then return end
	holders[kind] = true
	releaseToken = releaseToken + 1
	-- Already close (or going back): it stays, or comes back, at once.
	if Saved() then return ZoomIn() end
	holdToken = holdToken + 1
	local token = holdToken
	C_Timer.After(HOLD_DELAY, function()
		if token == holdToken and next(holders) and not InCombatLockdown() then ZoomIn() end
	end)
end

local function Release(kind)
	if not holders[kind] then return end
	holders[kind] = nil
	if next(holders) then return end
	holdToken = holdToken + 1 -- closed before the camera moved: it won't
	releaseToken = releaseToken + 1
	local token = releaseToken
	C_Timer.After(RELEASE_DELAY, function()
		if token == releaseToken and not next(holders) then ZoomOut() end
	end)
end

-- A camera left by a crash comes back.
local function RestoreAfterCrash()
	local saved = Saved()
	if not saved then return end
	ns.root.sceneCamera = nil
	for cvar, value in pairs(saved.cvars or {}) do ns.WriteCVar(cvar, value) end
	-- Still where Wanderer sent it (a /reload): back to your distance.
	local now = Clean(Safe(GetCameraZoom))
	local aim = saved.aim or saved.zoom
	if now and aim and saved.zoom and saved.zoom > aim and math.abs(now - aim) < 1 and CameraZoomOut then
		Safe(CameraZoomOut, saved.zoom - aim)
	end
end

-- Leaving the game: the settings borrowed go back now (the addon may be off
-- next time); the distance is set again after a /reload.
local function GiveBackSettings()
	local saved = Saved()
	if not saved then return end
	for cvar, value in pairs(saved.cvars or {}) do ns.WriteCVar(cvar, value) end
	saved.cvars = {}
end

function ns.InitCamera()
	local frame = CreateFrame("Frame")
	for event in pairs(HOLDS) do frame:RegisterEvent(event) end
	for event in pairs(RELEASES) do frame:RegisterEvent(event) end
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("PLAYER_LOGOUT")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGOUT" then
			GiveBackSettings()
		elseif HOLDS[event] then
			Hold(HOLDS[event])
		elseif RELEASES[event] then
			Release(RELEASES[event])
		elseif event == "PLAYER_REGEN_DISABLED" then
			-- A fight: the camera is the player's again at once.
			wipe(holders)
			ZoomOut()
		else
			RestoreAfterCrash()
		end
	end)
	-- Loaded after the login (/reload): a camera left by a crash comes back now.
	if IsLoggedIn and IsLoggedIn() then RestoreAfterCrash() end
end
