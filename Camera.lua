local _, ns = ...

-- The camera comes closer to the character you talk to: conversations,
-- quests, merchants, trainers, bankers, flight masters, auction houses. It
-- frames the character (a hidden setting of the game) and goes back to your
-- own distance once every window of that character is closed. Going from a
-- conversation to its merchant keeps it close: no back and forth.
--
-- The motion is slow and never hurried: a window must stay open a moment
-- before the camera moves (opened and closed at once, nothing happens), and
-- it waits a little after the last one closes. Every move is counted from
-- where Wanderer last sent the camera, never from where it happens to be in
-- the middle of a move, so quick back and forth can't make it drift.
--
-- The player's values are kept in the saved variables while the camera is
-- borrowed: they come back even after a crash.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local DISTANCE = 6 -- closer than this, the camera is left where it is
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

-- saved.zoom: the player's distance; saved.aim: where Wanderer sent the camera.
local function ZoomIn()
	if not (GetCameraZoom and CameraZoomIn) then return end
	local saved = Saved()
	if saved then
		-- Still going back: it comes closer again, from where it was sent.
		if saved.leaving then
			saved.leaving = false
			local aim = saved.aim or saved.zoom
			if aim and aim > DISTANCE then
				Safe(CameraZoomIn, aim - DISTANCE)
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
		Safe(CameraZoomIn, saved.zoom - DISTANCE)
		saved.aim = DISTANCE
	end
end

-- Back to the player's distance; the slow speed stays until the camera is there.
local function ZoomOut()
	local saved = Saved()
	if not saved or saved.leaving then return end
	saved.leaving = true
	local aim = saved.aim or saved.zoom
	local travel = 0
	if saved.zoom and aim and saved.zoom > aim then
		travel = saved.zoom - aim
		Safe(CameraZoomOut, travel)
	end
	saved.aim = saved.zoom
	C_Timer.After(travel / (tonumber(SPEED) or 8) + 0.2, function()
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
end

function ns.InitCamera()
	local frame = CreateFrame("Frame")
	for event in pairs(HOLDS) do frame:RegisterEvent(event) end
	for event in pairs(RELEASES) do frame:RegisterEvent(event) end
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function(_, event)
		if HOLDS[event] then
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
