local _, ns = ...

-- Fishing with a double right click on the world, when a fishing pole is in
-- your hands: the second click casts. While the line is in the water, a
-- double right click pulls it (interacts with the bobber).
--
-- Casting needs one of the game's secure buttons: for the second click only,
-- the right button is bound to it, and the binding removes itself in the
-- secure environment once the button is clicked. Nothing is ever bound
-- during a fight.

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

local button
local lastClick, lastCast = 0, 0
local interactBound = false

local function KnownFishingSpell()
	local spellBook = C_SpellBook
	for _, id in ipairs(FISHING_SPELLS) do
		if spellBook and Clean(Safe(spellBook.IsSpellKnown, id)) then return id end
		if not spellBook and Clean(Safe(IsSpellKnown, id)) then return id end
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

function ns.InitFishing()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
	frame:RegisterEvent("GLOBAL_MOUSE_UP")
	frame:SetScript("OnEvent", function(_, event, mouseButton)
		if event == "GLOBAL_MOUSE_DOWN" then OnMouseDown(mouseButton) else OnMouseUp(mouseButton) end
	end)
end
