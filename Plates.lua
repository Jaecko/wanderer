local _, ns = ...

-- Above every head (option, on by default): the label stands on the
-- nameplate of what you hover, so Wanderer turns on the nameplates it needs
-- (allies, minor enemies, enemies out of a fight: Core.lua, the player's own
-- settings saved and given back). The plates of allies and critters stay
-- invisible, always, even when turned on in the game's options: they are
-- only where the label stands, the label says the rest. Enemies keep theirs
-- (out of a fight only if the game's options show them then). In dungeons,
-- raids and battlegrounds every plate is the game's own, left alone.
-- Nothing runs while no plate is shown.
--
-- Your group: since names are hidden, the game cannot color theirs. Over
-- each member's quiet plate, Wanderer writes the name small, in the game's
-- color for your group (option, on by default); never while the game writes
-- it itself, nor under the label.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_EVERY = 0.5 -- plates change rarely (a fight, a plate appearing: events)
local FADE_IN, FADE_OUT = 0.25, 0.6

local driver
local since = 0
local tweens = setmetatable({}, { __mode = "k" }) -- plate -> its tween
local count = 0 -- plates shown
local quiet = setmetatable({}, { __mode = "k" }) -- plate -> true while kept invisible
local marks = setmetatable({}, { __mode = "k" }) -- plate -> its group mark (a name)
local MARK_SIZE = 10

-- Whether a plate is kept invisible (the label then stands lower, on the head).
function ns.IsPlateQuiet(plate) return quiet[plate] == true end

local function On()
	local db = ns.db
	if ns.zone == "dungeon" or ns.zone == "raid" or ns.zone == "pvp" then return false end -- the game's own plates there
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

-- A member of your group, other than you.
local function Companion(unit)
	if Clean(Safe(UnitIsUnit, unit, "player")) or not Clean(Safe(UnitIsPlayer, unit)) then return false end
	return (Clean(Safe(UnitInParty, unit)) or Clean(Safe(UnitInRaid, unit))) and true or false
end

local function MarkWanted(unit, isQuiet, plate)
	if not (isQuiet and ns.db.groupMarks and Companion(unit)) then return false end
	if ns.GameShowsName and ns.GameShowsName(unit) then return false end
	-- The label describes this character already: gone at once, never under it.
	if ns.LabelPlate and ns.LabelPlate() == plate then return false, true end
	if ns.IsLabelActive and ns.IsLabelActive() then
		local hovered, own = Clean(Safe(UnitGUID, "mouseover")), Clean(Safe(UnitGUID, unit))
		if (hovered and hovered == own) or Clean(Safe(UnitIsUnit, "mouseover", unit)) then return false, true end
	end
	return true
end

-- The game's own color for your group (its party chat), raid members alike.
local function PartyColor()
	local info = ChatTypeInfo and ChatTypeInfo.PARTY
	if info and info.r then return info.r, info.g, info.b end
	return 0.67, 0.67, 1
end

local function Mark(plate)
	local mark = marks[plate]
	if mark then return mark end
	mark = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	local font, _, flags = mark:GetFont()
	if font then mark:SetFont(font, MARK_SIZE, flags) end
	mark:SetShadowOffset(1, -1)
	mark:SetShadowColor(0, 0, 0, 0.9)
	mark:SetPoint("BOTTOM", plate, "BOTTOM", 0, 2)
	mark:SetAlpha(0)
	mark.tween = U.Tween(0)
	marks[plate] = mark
	return mark
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
			local markOn, underLabel = MarkWanted(unit, wanted == 0, plate)
			if markOn or marks[plate] then
				local mark = Mark(plate)
				if markOn then
					pcall(mark.SetText, mark, (Safe(UnitName, unit)))
					mark:SetTextColor(PartyColor())
				end
				if underLabel then mark.tween = U.Tween(0) end
				local markAlpha = mark.tween:Step(markOn and 1 or 0, elapsed, FADE_IN, FADE_OUT)
				mark:SetAlpha(markAlpha)
				mark:SetShown(markAlpha > 0)
				if markAlpha ~= (markOn and 1 or 0) then moving = true end
			end
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
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
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
