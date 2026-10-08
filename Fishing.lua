local _, ns = ...

-- Fishing with a double right click on the world, when a fishing pole is in
-- your hands: the second click casts. While the line is in the water, a
-- double right click pulls it (interacts with the bobber).
--
-- The fishing told (option): the label over the bobber says what happens
-- (the line lands, the wait, the last seconds) with the time left, and a
-- short notice tells each catch (a fine one in its color, a new species for
-- the journal, a streak) and the count of the session; a line without a lure
-- says so. Option: while the line is in the water, the music and the ambience
-- step back for the splash to be heard, then come back as they were. The game
-- never tells addons when a fish bites (checked in WoW Forever: no event, no
-- change of the bobber's tooltip): the bobber's dive and its splash do.
--
-- Casting needs one of the game's secure buttons: for the second click only,
-- the right button is bound to it, and the binding removes itself in the
-- secure environment once the button is clicked. Nothing is ever bound
-- during a fight.

local L = ns.L
local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local DOUBLE_CLICK = 0.4 -- seconds between the two clicks
local MIN_GAP = 0.04 -- shorter: one click seen twice
local RECAST_GUARD = 0.5 -- never two casts in a row
local BUTTON_NAME = "WandererFishingButton"
local FISHING_POLE = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
local MAIN_HAND = INVSLOT_MAINHAND or 16

-- Spells of fishing across the versions of the game.
local FISHING_SPELLS = { 131474, 131490, 131476, 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410, 158743 }

local LANDED_TIME = 2.5 -- seconds the line is said to land
local MISSED_LEFT = 1 -- seconds left at most when a line ends by itself

local button
local lastClick, lastCast = 0, 0
-- The line in the water: active, start/finish (ms), result ("caught" or
-- "missed"), ended (time), catches of the session, casts (for the words).
local status = { catches = 0, casts = 0, streak = 0 }
local STREAK_EVERY = 5 -- a streak is greeted every 5 catches in a row
local SPLASH_SHARE = 0.3 -- the music and the ambience while the line is in the water
local SPLASH_CVARS = { "Sound_MusicVolume", "Sound_AmbienceVolume" }
function ns.FishingStatus() return status end
local interactBound = false

local function KnownFishingSpell()
	local isKnown = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown
	if not isKnown then return end
	for _, id in ipairs(FISHING_SPELLS) do
		if Clean(Safe(isKnown, id)) then return id end
	end
end

local function HasFishingPole()
	local item = Clean(Safe(GetInventoryItemID, "player", MAIN_HAND))
	if not item then return false end
	local subclass = select(7, Safe(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, item))
	return subclass == FISHING_POLE
end

local function IsFishing()
	local spell = select(8, Safe(UnitChannelInfo, "player"))
	spell = Clean(spell)
	if not spell then return false end
	for _, id in ipairs(FISHING_SPELLS) do
		if id == spell then return true end
	end
	return false
end

-- Somewhere you can cast a line from.
local function CanCast()
	if IsFishing() or not HasFishingPole() then return false end
	for _, blocked in ipairs({ IsMounted, IsFlying, IsFalling, IsSwimming, IsPlayerMoving, IsStealthed }) do
		if Clean(Safe(blocked)) then return false end
	end
	return (Clean(Safe(HasFullControl)) and true or false) and (Clean(Safe(GetNumLootItems)) or 0) == 0
end

-- The secure button that casts, made once out of combat.
local function Button()
	if button or InCombatLockdown() then return button end
	local spell = KnownFishingSpell()
	if not spell then return end
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "spell")
	button:SetAttribute("spell", spell)
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
	if mouseButton ~= "RightButton" or InCombatLockdown() then return end
	local db = ns.db
	if not (db and db.enabled and db.fishing.doubleClick) or not U.IsOverWorld() then return end
	local now = GetTime()
	local gap = now - lastClick
	lastClick = now
	if gap < MIN_GAP or gap > DOUBLE_CLICK or now - lastCast < RECAST_GUARD then return end
	lastClick = 0
	if IsFishing() then
		-- Pull the line: the right button interacts until it is released.
		local owner = Button()
		if owner then
			Safe(SetOverrideBinding, owner, true, "BUTTON2", "INTERACTTARGET")
			interactBound = true
		end
	elseif CanCast() then
		local owner = Button()
		if owner then
			owner:SetAttribute("castsOnDown", Clean(Safe(GetCVarBool, "ActionButtonUseKeyDown")) and true or false)
			Safe(SetOverrideBindingClick, owner, true, "BUTTON2", BUTTON_NAME)
			lastCast = now
		end
	end
end

local function OnMouseUp(mouseButton)
	if interactBound and mouseButton == "RightButton" and not InCombatLockdown() then
		interactBound = false
		Safe(ClearOverrideBindings, button)
	end
end

-- The splash heard: the music and the ambience lowered while the line is in
-- the water, given back after (and at the next login after a crash).
local function Splash(on)
	local root = ns.root
	if not (root and ns.WriteCVar) then return end
	if on then
		if root.fishVolumes or not (ns.db.enabled and ns.db.fishing.splash) then return end
		root.fishVolumes = {}
		for _, cvar in ipairs(SPLASH_CVARS) do
			local value = tonumber(Safe(GetCVar, cvar))
			if value then
				root.fishVolumes[cvar] = tostring(value)
				ns.WriteCVar(cvar, tostring(value * SPLASH_SHARE))
			end
		end
	elseif root.fishVolumes then
		for cvar, value in pairs(root.fishVolumes) do ns.WriteCVar(cvar, value) end
		root.fishVolumes = nil
	end
end

-- The catch as the notice says it: a fine one in its color.
local function CatchName(link, name)
	local quality = link and Clean(select(3, Safe(GetItemInfo, link)))
	local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and color.hex and (color.hex .. name .. "|r") or name
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
		-- A pole without a lure: said on the bobber.
		status.noLure = not Clean(Safe(GetWeaponEnchantInfo))
		Splash(true)
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" and unit == "player" and status.active then
		status.active, status.ended = false, GetTime()
		Splash(false)
		-- Gone by itself to the end: the fish got away (a click, a move: nothing to say).
		local left = status.finish and status.finish / 1000 - GetTime() or 0
		if left <= MISSED_LEFT and not status.result then
			status.result, status.streak = "missed", 0
			if Told() and ns.Toast then ns.Toast(L.FISH_MISSED, nil, { duration = 2.5, corner = true }) end
		end
	elseif event == "LOOT_OPENED" and Clean(Safe(IsFishingLoot)) then
		status.catches, status.streak = status.catches + 1, status.streak + 1
		status.result, status.ended = "caught", GetTime()
		local icon, item = Safe(GetLootSlotInfo, 1)
		status.item = Clean(item)
		local new = status.item and ns.JournalCatch and ns.JournalCatch(status.item, Clean(icon))
		if Told() and ns.Toast then
			local said = L.FISH_COUNT:format(status.catches)
			if new then
				said = L.FISH_NEW
			elseif status.streak % STREAK_EVERY == 0 then
				said = L.FISH_STREAK:format(status.streak)
			end
			local name = status.item and CatchName(Clean(Safe(GetLootSlotLink, 1)), status.item)
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
	for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "LOOT_OPENED" }) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, arg)
		if event == "GLOBAL_MOUSE_DOWN" then OnMouseDown(arg)
		elseif event == "GLOBAL_MOUSE_UP" then OnMouseUp(arg)
		else OnLine(event, arg) end
	end)
end
