local _, ns = ...

-- Fishing with a double right click on the world, when a fishing pole is in
-- your hands: the second click casts. While the line is in the water, a
-- double right click pulls it (interacts with the bobber).
--
-- The fishing told (option): the label over the bobber says what happens
-- (the line lands, the wait, the last seconds) with the time left, and a
-- short notice tells each catch (a fine one in its color, a streak) and the
-- count of the session; a line without a lure
-- says so. Option: while the line is in the water, the music and the ambience
-- step back for the splash to be heard, then come back as they were. The game
-- never tells addons when a fish bites (checked in WoW Forever: no event, no
-- change of the bobber's tooltip): the bobber's dive and its splash do.
--
-- Casting needs one of the game's secure buttons: for the second click only,
-- the right button is bound to it, and the binding removes itself in the
-- secure environment once the button is clicked. Nothing is ever bound
-- during a fight.
--
-- No pole in hand, an extension may put one there (Wanderer Outfits, W.OnFishingNoPole(fn)): asked as the
-- first click of what may be a double click is let go (a short click on the world, out of a fight, standing
-- still: fn("first"), true when it takes the pole in hand), so the game equips it before the second click casts, in the same gesture (the game
-- handles the two asks in their order; only near a place this character has fished from, never over a character or
-- an object). The second click then casts as with a pole (fn("cast")); no second click
-- in time: fn("cancel") (the extension may give your weapons back). A double click already begun without it
-- (an older extension, a slow first click): fn("now"), the pole in hand for the next double click.

local L = ns.L
local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local DOUBLE_CLICK = 0.4 -- seconds between the two clicks
local SHORT_CLICK = 0.25 -- a first click held longer turns the camera: no pole asked
local POLE_COMING = 1.5 -- seconds a pole asked for may take to come in hand (the cast bound all the same)
local MIN_GAP = 0.04 -- shorter: one click seen twice
local RECAST_GUARD = 0.5 -- never two casts in a row
local BUTTON_NAME = "WandererFishingButton"


local FISHING_SPELLS = U.FISHING_SPELLS
local LANDED_TIME = 2.5 -- seconds the line is said to land
local MISSED_LEFT = 1 -- seconds left at most when a line ends by itself
local MISSED_WAIT = 0.5 -- seconds a catch may still come before the fish is said gone

local button
local lastClick, lastCast = 0, 0
-- The line in the water: active, start/finish (ms), result ("caught" or
-- "missed"), ended (time), catches of the session, casts (for the words).
local status = { catches = 0, casts = 0, streak = 0 }
local STREAK_EVERY = 5 -- a streak is greeted every 5 catches in a row
local SPLASH_SHARE = 0.3 -- the music and the ambience while the line is in the water
function ns.FishingStatus() return status end
local interactBound = false
local downAt, firstPending = 0, false -- the right button's last press; a first click that may ask for a pole
local poleAsked = 0 -- when the pole was asked for on a first click (0: not)
local overSomething = false -- the right button pressed over a character or an object (an NPC, a mailbox...)

-- The places this character has fished from (world x, y, continent): the pole is taken in hand by itself only
-- near one of them, never by a double click on the ground anywhere. A line cast from a new place (the pole
-- taken by hand) adds it.
local SPOT_REACH = 40 -- yards around a remembered place
local SPOT_SAME = 15 -- closer: the same place
local SPOTS_KEPT = 150

local function Spots()
	local mine = ns.Mine()
	mine.fishingSpots = type(mine.fishingSpots) == "table" and mine.fishingSpots or {}
	return mine.fishingSpots
end

local function NearSpot(reach)
	local x, y, continent = U.Here()
	if not x then return false end
	for _, spot in ipairs(Spots()) do
		if spot[3] == continent and (spot[1] - x) ^ 2 + (spot[2] - y) ^ 2 <= reach * reach then return true end
	end
	return false
end

local function RememberSpot()
	local x, y, continent = U.Here()
	if not x or NearSpot(SPOT_SAME) then return end
	local spots = Spots()
	spots[#spots + 1] = { x, y, continent }
	while #spots > SPOTS_KEPT do table.remove(spots, 1) end
end
ns.FishingRememberSpot = RememberSpot

-- A character under the cursor (an NPC to talk to, a corpse to skin): a click on it never asks for the pole.
-- (objects are not counted: a school of fish has a tooltip too, and is where you fish; the soft target is not
-- where the mouse points, it is not counted either)
local function OverSomething()
	return Clean(Safe(UnitExists, "mouseover")) and true or false
end

-- The pole may come by itself: nothing under the cursor, a place you have fished from.
local function PoleMayCome()
	return not overSomething and NearSpot(SPOT_REACH)
end

local function KnownFishingSpell()
	local isKnown = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown
	if not isKnown then return end
	for _, id in ipairs(FISHING_SPELLS) do
		if Clean(Safe(isKnown, id)) then return id end
	end
end

local HasFishingPole = U.HasFishingPole

local function IsFishing()
	return U.IsFishingSpell(select(8, Safe(UnitChannelInfo, "player")))
end

-- Somewhere you can cast a line from (withoutPole: a pole in hand not asked).
local function CanCast(withoutPole)
	if IsFishing() or not (withoutPole or HasFishingPole()) then return false end
	for _, blocked in ipairs({ IsMounted, IsFlying, IsFalling, IsSwimming, IsPlayerMoving, IsStealthed }) do
		if Clean(Safe(blocked)) then return false end
	end
	return (Clean(Safe(HasFullControl)) and true or false) and (Clean(Safe(GetNumLootItems)) or 0) == 0
end

-- The spell the button casts: by its name, the game picks your highest rank (a rank learned since: no reload).
local function CastSpell(spell)
	local named = C_Spell and C_Spell.GetSpellName and Clean(Safe(C_Spell.GetSpellName, spell))
		or (GetSpellInfo and Clean(Safe(GetSpellInfo, spell)))
	return named or spell
end

-- The secure button that casts, made once out of combat.
local function Button()
	if button or InCombatLockdown() then return button end
	local spell = KnownFishingSpell()
	if not spell then return end
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "spell")
	button:SetAttribute("spell", CastSpell(spell))
	-- Removes the binding on the press that casts (down or up, as the game
	-- casts its action buttons: see OnMouseDown).
	SecureHandlerWrapScript(button, "PostClick", button, [[
		if (down and self:GetAttribute("castsOnDown")) or (not down and not self:GetAttribute("castsOnDown")) then
			self:ClearBindings()
		end
	]])
	return button
end

local function OnMouseDown(mouseButton)
	if mouseButton ~= "RightButton" then return end
	firstPending = false
	if InCombatLockdown() then return end
	overSomething = OverSomething()
	local db = ns.db
	if not (db and db.enabled and db.fishing.doubleClick) or not U.IsOverWorld() then return end
	local now = GetTime()
	local gap = now - lastClick
	lastClick, downAt = now, now
	-- (a first click: its release may ask for the pole)
	firstPending = gap > DOUBLE_CLICK or gap < MIN_GAP
	if gap < MIN_GAP or gap > DOUBLE_CLICK or now - lastCast < RECAST_GUARD then return end
	lastClick = 0
	if IsFishing() then
		-- Pull the line: the right button interacts until it is released.
		local owner = Button()
		if owner then
			Safe(SetOverrideBinding, owner, true, "BUTTON2", "INTERACTTARGET")
			interactBound = true
		end
	elseif CanCast() or (now - poleAsked < POLE_COMING and CanCast(true)) then
		-- (a pole asked for on the first click: on its way, the game equips it before this cast)
		local coming = not HasFishingPole()
		local owner = Button()
		if owner then
			owner:SetAttribute("castsOnDown", Clean(Safe(GetCVarBool, "ActionButtonUseKeyDown")) and true or false)
			Safe(SetOverrideBindingClick, owner, true, "BUTTON2", BUTTON_NAME)
			lastCast = now
			if coming or poleAsked > 0 then
				poleAsked = 0
				if ns.fishingNoPole then pcall(ns.fishingNoPole, "cast") end
			end
		end
	elseif ns.fishingNoPole and not U.IsSkipping() and CanCast(true) and PoleMayCome() then
		-- No pole in hand, none asked on the first click: an extension may put one (the next double click casts).
		lastCast = now
		pcall(ns.fishingNoPole, "now")
	end
end

-- A short first click on the world let go, no pole in hand: the pole asked for now, so that a second click casts
-- with it; none in time: said too (the extension may give your weapons back).
local function AskPole()
	firstPending = false
	if not ns.fishingNoPole or U.IsSkipping() or InCombatLockdown() then return end
	local db = ns.db
	if not (db and db.enabled and db.fishing.doubleClick) or not U.IsOverWorld() then return end
	local now = GetTime()
	if now - downAt > SHORT_CLICK or now - lastCast < RECAST_GUARD or HasFishingPole() or IsFishing() then return end
	if IsMouselooking and Clean(Safe(IsMouselooking)) then return end
	if not CanCast(true) or not PoleMayCome() then return end
	-- (the extension says whether it takes the pole in hand: true; else nothing is waited for)
	local ok, took = pcall(ns.fishingNoPole, "first")
	if not (ok and took) then return end
	poleAsked = now
	C_Timer.After(DOUBLE_CLICK + 0.2, function()
		if poleAsked ~= now then return end
		poleAsked = 0
		if ns.fishingNoPole then pcall(ns.fishingNoPole, "cancel") end
	end)
end

local function OnMouseUp(mouseButton)
	if firstPending and mouseButton == "RightButton" then AskPole() end
	if interactBound and mouseButton == "RightButton" and not InCombatLockdown() then
		interactBound = false
		Safe(ClearOverrideBindings, button)
	end
end

-- The splash heard: the music and the ambience lowered while the line is in
-- the water, given back after (and at the next login after a crash).
local function Splash(on)
	if on then
		if ns.db.enabled and ns.db.fishing.splash then ns.LowerVolumes("fishVolumes", SPLASH_SHARE) end
	else
		ns.RestoreVolumes("fishVolumes")
	end
end

-- The catch as the notice says it: a fine one in its color.
local function CatchName(link, name)
	local quality = link and select(3, U.ItemInfo(link))
	if not (quality and quality >= 2) then return name end
	return U.Colorize(name, U.QualityColor(quality))
end

local function Told()
	local db = ns.db
	return db and db.enabled and db.fishing.tell
end

-- The line cast, ended, or a catch in the loot window.
local function OnLine(event, unit)
	if event == "UNIT_SPELLCAST_CHANNEL_START" and unit == "player" and IsFishing() then
		local _, _, _, start, finish = Safe(UnitChannelInfo, "player")
		status.active, status.start, status.finish = true, Clean(start), Clean(finish)
		status.result, status.ended, status.item = nil, nil, nil
		status.casts = status.casts + 1
		RememberSpot()
		-- A pole without a lure: said on the bobber.
		status.noLure = not Clean(Safe(GetWeaponEnchantInfo))
		Splash(true)
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" and unit == "player" and status.active then
		status.active, status.ended = false, GetTime()
		Splash(false)
		-- Gone by itself to the end: the fish got away (a click, a move: nothing to say).
		local left = status.finish and status.finish / 1000 - GetTime() or 0
		if left <= MISSED_LEFT and not status.result then
			-- (a click in the last second also stops the line, its loot window comes just after)
			local ended = status.ended
			C_Timer.After(MISSED_WAIT, function()
				if status.ended ~= ended or status.result then return end
				status.result, status.streak = "missed", 0
				if Told() then ns.Toast(L.FISH_MISSED, nil, { duration = 2.5, corner = true }) end
			end)
		end
	elseif event == "LOOT_OPENED" and Clean(Safe(IsFishingLoot)) then
		status.catches, status.streak = status.catches + 1, status.streak + 1
		status.result, status.ended = "caught", GetTime()
		local _, item = Safe(GetLootSlotInfo, 1)
		status.item = Clean(item)
		-- (the fast loot may have emptied the window already: what it saw in it)
		local seen = ns.lastLoot
		local link = Clean(Safe(GetLootSlotLink, 1))
		if not status.item and seen and GetTime() - seen.at < 1 then status.item, link = seen.name, seen.link end
		if Told() then
			local said = L.FISH_COUNT:format(status.catches)
			if status.streak % STREAK_EVERY == 0 then
				said = L.FISH_STREAK:format(status.streak)
			end
			local name = status.item and CatchName(link, status.item)
			ns.Toast(name and L.FISH_CAUGHT_ITEM:format(name) or L.FISH_CAUGHT, said, { duration = 3, corner = true })
		end
	end
end

-- What the label says over the bobber: text, the line still in the water.
function ns.FishingWords()
	if not Told() then return end
	local now = GetTime()
	if status.active and status.start and status.finish then
		local elapsed, left = now - status.start / 1000, status.finish / 1000 - now
		if elapsed < LANDED_TIME then return L.FISH_LANDED, true end
		if left < 4 then return L.FISH_LATE, true end
		return L["FISH_WATCH_" .. (status.casts % 3 + 1)], true
	end
end

function ns.InitFishing()
	Splash(false) -- a session ended with the line in the water: the sounds back
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
	frame:RegisterEvent("GLOBAL_MOUSE_UP")
	frame:RegisterEvent("LOOT_OPENED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(frame.RegisterEvent, frame, "SPELLS_CHANGED")
	-- (your own casts only, not every unit's around)
	for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
		if frame.RegisterUnitEvent then frame:RegisterUnitEvent(event, "player") else frame:RegisterEvent(event) end
	end
	frame:SetScript("OnEvent", function(_, event, arg)
		if event == "GLOBAL_MOUSE_DOWN" then OnMouseDown(arg)
		elseif event == "GLOBAL_MOUSE_UP" then OnMouseUp(arg)
		elseif event == "PLAYER_REGEN_ENABLED" then OnMouseUp("RightButton")
		elseif event == "SPELLS_CHANGED" then
			-- (a rank learned: the button casts it, set again out of a fight)
			local spell = button and KnownFishingSpell()
			local function Set() button:SetAttribute("spell", CastSpell(spell)) end
			if spell and InCombatLockdown() then U.AfterFight("fishingSpell", Set) elseif spell then Set() end
		else OnLine(event, arg) end
	end)
end
