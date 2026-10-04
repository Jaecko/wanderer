local _, ns = ...

-- Above every head (option, on by default): the label stands on the
-- nameplate of what you hover, so Wanderer turns on the nameplates it needs
-- (allies, minor enemies, enemies out of a fight: Core.lua, the player's own
-- settings saved and given back). The plates of allies and critters stay
-- invisible, always, even when turned on in the game's options: they are
-- only where the label stands, the label says the rest. Enemies keep theirs
-- (out of a fight only if the game's options show them then). Plates the game keeps to itself (in instances)
-- are left alone. Nothing runs while no plate is shown.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_EVERY = 0.5 -- plates change rarely (a fight, a plate appearing: events)
local FADE_IN, FADE_OUT = 0.25, 0.6

local driver
local since = 0
local tweens = setmetatable({}, { __mode = "k" }) -- plate -> its tween
local count = 0 -- plates shown
local quiet = setmetatable({}, { __mode = "k" }) -- plate -> true while kept invisible

-- Whether a plate is kept invisible (the label then stands lower, on the head).
function ns.IsPlateQuiet(plate) return quiet[plate] == true end

local function On()
	local db = ns.db
	return db and db.enabled and db.label.allHeads and db.label.anchor == "head" and true or false
end

-- The part of the plate that draws (the game's, or a nameplate addon's).
local function Drawn(plate)
	local drawn = plate.UnitFrame or plate.unitFrame
	return type(drawn) == "table" and drawn.SetAlpha and drawn or nil
end

-- The player's own choice in the game's options (saved before Wanderer wrote).
local function Own(cvar)
	local original = ns.root and ns.root.original
	return original ~= nil and original[cvar] == "1"
end

-- Quiet: allies and critters always; enemies out of a fight unless the
-- player shows them then.
local function Quiet(unit)
	local hostile = Safe(UnitCanAttack, "player", unit)
	if U.IsSecret(hostile) then return false end
	if not hostile then return true end
	if Clean(Safe(UnitClassification, unit)) == "minus" then return not Own("nameplateShowEnemyMinus") end
	-- Enemies: the game shows them in a fight anyway.
	return not Own("nameplateShowAll") and not (ns.inCombat or InCombatLockdown())
end

-- Brings every plate to its wanted opacity, softly. Returns true while a
-- plate is still moving.
local function Update(elapsed)
	local moving = false
	for _, plate in ipairs(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}) do
		local drawn = not (plate.IsForbidden and plate:IsForbidden()) and Drawn(plate)
		local unit = plate.namePlateUnitToken or (drawn and drawn.unit)
		if drawn and unit then
			local wanted = (On() and Quiet(unit)) and 0 or 1
			quiet[plate] = wanted == 0
			local tween = tweens[plate]
			if not tween then
				-- A plate appearing for a quiet character never flashes first.
				tween = U.Tween(wanted)
				tweens[plate] = tween
			end
			local alpha = tween:Step(wanted, elapsed, FADE_IN, FADE_OUT)
			drawn:SetAlpha(alpha)
			if alpha ~= wanted then moving = true end
		end
	end
	return moving
end

local function Wake()
	if driver and (On() or next(tweens)) then driver:Show() end
end

function ns.RefreshPlates()
	if not driver then return end
	Update(0)
	Wake()
end

function ns.InitPlates()
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", function(self, elapsed)
		since = since + elapsed
		if since < CHECK_EVERY then return end
		local moving = Update(since)
		since = 0
		-- Asleep with no plate shown (or the option off and every plate back).
		if count == 0 or (not On() and not moving) then
			if not On() then wipe(tweens) end
			self:Hide()
		end
	end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			count = count + 1
			-- Hidden at once if it should be: no flash of a quiet plate.
			local plate = unit and C_NamePlate and Safe(C_NamePlate.GetNamePlateForUnit, unit)
			if plate then tweens[plate] = nil end
			Update(0)
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			count = math.max(0, count - 1)
		end
		Wake()
	end)
	count = #(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {})
	ns.RefreshPlates()
end
