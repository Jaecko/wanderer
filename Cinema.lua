local _, ns = ...

-- Fading of the default interface: the portraits, action bars, micro menu
-- (options), bags and experience bar. The rest (minimap, chat, quests, bug
-- report button...) is never touched. Two rules share one engine, the same
-- frames, opacity and delay:
--
-- * Cinematic mode: faded when everything is calm (out of combat, no target).
-- * Interface in combat only: faded whenever you are out of combat, even with
--   a target.
--
-- With both, the frames come back instantly in combat, when the mouse goes
-- over one of them or when a window is open. Typing does not bring them back.

local CHECK_DELAY = 0.1
local FRAMES_EVERY = 2 -- seconds between two looks at which frames exist
-- Seconds of a full fade: slow going away, quicker coming back (a fight, a
-- target), both soft at their ends.
local FADE_OUT_TIME, FADE_IN_TIME = 1.8, 0.45

-- Frames of the default interface that may fade. Missing ones are skipped.
local FADED_FRAMES = {
	-- Portraits
	"PlayerFrame", "PetFrame", "TargetFrame", "FocusFrame",
	-- Action bars
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar",
	-- Micro menu (character, spellbook, talents, options...) and bags
	"MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar", "BagsBar",
	-- Experience, reputation and other status bars
	"StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
	"MainMenuExpBar", "ReputationWatchBar",
}

-- Faded only during a conversation scene (needed the rest of the time: a
-- cast out of a fight, a vehicle to leave): the scene's panel sits there.
local SCENE_FRAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "MainMenuBarVehicleLeaveButton",
	"MultiCastActionBarFrame" }
local SCENE_FADE_TIME = 0.5 -- a conversation begins: out of the way quickly

-- Portraits that stay fully visible while they show someone.
local KEPT_WHILE_SELECTED = { TargetFrame = "target", FocusFrame = "focus" }

local frame
local quietTime, calmTime, sinceCheck = 0, 0, 0
local level = 1 -- current fade: 1 = fully visible
local tween = ns.Util.Tween(1)
local baseAlpha = {} -- frame -> its own alpha before fading
local recovering = false
local playerLevel, playerTween = 1, ns.Util.Tween(1) -- your portrait, softly on its own

local Safe = ns.Util.Safe
local managedList, managedSet = {}, {} -- frames to fade, looked for every FRAMES_EVERY
local sceneOnly = {} -- frame -> true: faded during scenes only
local present = {} -- reused: no new table at each look
local framesAge = FRAMES_EVERY
local wasScene = false
-- Right after a conversation: the interface goes from the scene's opacity
-- straight to the one the settings want, never back to full in between (the
-- character you spoke to, still selected, does not count until you change
-- target).
local afterScene = false

local function IsWindowOpen()
	for _, name in ipairs(UISpecialFrames or {}) do
		local window = _G[name]
		if window and window.IsShown and window:IsShown() then return true end
	end
	return false
end

-- Frames of the list whose parent is also in the list are skipped: fading
-- both would multiply the effect. The game's frames rarely change: looked
-- for every few seconds only.
local function RefreshManagedFrames()
	wipe(present)
	for _, name in ipairs(FADED_FRAMES) do
		local target = _G[name]
		if target and target.SetAlpha then present[target] = true end
	end
	for _, name in ipairs(SCENE_FRAMES) do
		local target = _G[name]
		if target and target.SetAlpha then
			present[target] = true
			sceneOnly[target] = true
		end
	end
	wipe(managedList)
	wipe(managedSet)
	for target in pairs(present) do
		local parent, nested = target.GetParent and target:GetParent(), false
		while parent do
			if present[parent] then nested = true break end
			parent = parent.GetParent and parent:GetParent()
		end
		if not nested then
			managedList[#managedList + 1] = target
			managedSet[target] = true
		end
	end
end

-- True when the mouse is over one of the faded elements (or inside it). A
-- protected frame of the game (pings, the store...) is never looked into: it
-- is none of ours, and the game forbids an addon to climb its parents.
local function FadedUnderMouse()
	local focus = ns.Util.MouseFocus()
	while focus do
		if focus.IsForbidden and focus:IsForbidden() then return nil end
		if managedSet[focus] then return focus end
		local ok, parent = pcall(focus.GetParent, focus)
		focus = ok and parent or nil
	end
	return nil
end

local function IsMouseOverFaded() return FadedUnderMouse() ~= nil end

local function InCombat()
	return ns.inCombat or InCombatLockdown()
end

-- Quiet: out of combat, no window open, the mouse elsewhere (both rules).
local function IsQuiet()
	return not InCombat() and not IsWindowOpen() and not IsMouseOverFaded()
end

local function Active(settings)
	return settings and ns.db.enabled and (settings.enabled or settings.combatOnly or ns.sceneActive)
end

-- Wanted level from both rules.
local function TargetLevel(settings)
	-- A conversation scene: the interface steps out of the picture.
	if ns.sceneActive then return 0 end
	local faded = (settings.enabled and calmTime >= settings.delay)
		or (settings.combatOnly and quietTime >= settings.delay)
	return faded and settings.alpha / 100 or 1
end

-- Your own portrait while you recover (health, or mana for those who use
-- it): you see when to rest, eat or drink. Protected values: never looked into.
local function Recovering()
	local health, most = ns.Util.Clean(Safe(UnitHealth, "player")), ns.Util.Clean(Safe(UnitHealthMax, "player"))
	if health and most and health < most then return true end
	if ns.Util.Clean(Safe(UnitPowerType, "player")) ~= 0 then return false end -- 0: mana
	local mana, full = ns.Util.Clean(Safe(UnitPower, "player", 0)), ns.Util.Clean(Safe(UnitPowerMax, "player", 0))
	return mana and full and mana < full or false
end

-- A portrait showing a selected unit (target, focus) is never faded.
-- Known by the frame itself, never by its name: the game may keep frame names
-- secret now.
local function IsKept(target)
	-- A conversation scene shows its own portrait: the game's one fades too.
	if ns.sceneActive then return false end
	for name, unit in pairs(KEPT_WHILE_SELECTED) do
		if _G[name] == target then return ns.Util.Clean(Safe(UnitExists, unit)) and true or false end
	end
	return false
end

-- Applies the fade level to every managed frame, keeping their own alpha.
local function ApplyLevel()
	for _, target in ipairs(managedList) do
		local wanted = target == _G.PlayerFrame and playerLevel or level
		if sceneOnly[target] then wanted = ns.sceneActive and level or 1 end
		if wanted < 1 and not IsKept(target) then
			if not baseAlpha[target] then baseAlpha[target] = target:GetAlpha() end
			target:SetAlpha(baseAlpha[target] * wanted)
		elseif baseAlpha[target] then
			target:SetAlpha(baseAlpha[target])
			baseAlpha[target] = nil
		end
	end
	-- Frames no longer managed get their own alpha back too.
	for target, alpha in pairs(baseAlpha) do
		if not managedSet[target] then
			target:SetAlpha(alpha)
			baseAlpha[target] = nil
		end
	end
end

local function Reset()
	quietTime, calmTime = 0, 0
	if level ~= 1 or playerLevel ~= 1 then
		level, playerLevel = 1, 1
		tween:Set(1)
		playerTween:Set(1)
		ApplyLevel()
	end
end

local function OnUpdate(_, elapsed)
	local settings = ns.db and ns.db.cinema
	if not Active(settings) then
		Reset()
		frame:Hide()
		return
	end
	if wasScene and not ns.sceneActive then
		afterScene = true
		quietTime, calmTime = math.max(quietTime, settings.delay), math.max(calmTime, settings.delay)
	end
	wasScene = ns.sceneActive and true or false
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= CHECK_DELAY then
		framesAge = framesAge + sinceCheck
		if framesAge >= FRAMES_EVERY then
			framesAge = 0
			RefreshManagedFrames()
		end
		local quiet = IsQuiet()
		quietTime = quiet and (quietTime + sinceCheck) or 0
		calmTime = (quiet and (afterScene or not Safe(UnitExists, "target"))) and (calmTime + sinceCheck) or 0
		recovering = level < 1 and not ns.sceneActive and Recovering() -- in a scene: everything aside
		sinceCheck = 0
	end
	local target = TargetLevel(settings)
	local changed = level ~= target
	local fadeOut = ns.sceneActive and SCENE_FADE_TIME or FADE_OUT_TIME
	if changed then level = tween:Step(target, elapsed, FADE_IN_TIME, fadeOut) end
	local playerTarget = recovering and 1 or level
	if playerLevel ~= playerTarget then
		playerLevel = playerTween:Step(playerTarget, elapsed, FADE_IN_TIME, fadeOut)
		changed = true
	end
	if changed then ApplyLevel() end
end

-- Combat and a new target must never wait for the next check: what they
-- bring back comes back at once.
local function OnEvent(_, event)
	local settings = ns.db and ns.db.cinema
	if not Active(settings) then return end
	afterScene = false
	calmTime = 0
	if event == "PLAYER_REGEN_DISABLED" then
		ns.inCombat = true
		quietTime = 0
	end
	-- What comes back comes back now, softly (the update does the motion);
	-- the target and focus portraits are shown or faded at once.
	frame:Show()
	ApplyLevel()
end

function ns.RefreshCinema()
	if not frame then return end
	if Active(ns.db.cinema) then
		frame:Show()
	else
		Reset()
		frame:Hide()
	end
end

function ns.InitCinema()
	frame = CreateFrame("Frame")
	frame:SetScript("OnUpdate", OnUpdate)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
	frame:SetScript("OnEvent", OnEvent)
	ns.RefreshCinema()
end
