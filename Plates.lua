local _, ns = ...

-- Above every head (option, on by default): the label stands on the
-- nameplate of what you hover, so Wanderer turns on the nameplates it needs
-- (allies, minor enemies, enemies out of a fight: Core.lua, the player's own
-- settings saved and given back). The plates of allies and critters stay
-- invisible, always, even when turned on in the game's options: they are
-- only where the label stands, the label says the rest. Enemies keep theirs
-- (out of a fight only if the game's options show them then). In dungeons,
-- raids and battlegrounds every plate is the game's own, left alone; with
-- another addon drawing the plates (ElvUI, Plater...), every plate is its own.
-- Nothing runs while no plate is shown; only a plate fading is looked at
-- every frame.
--
-- Enemies (option "as you come near"): the same small name over their quiet
-- plate, in the color of their reaction; the game fades the plate with the
-- distance, so the name comes as you come near (out of a fight).
--
-- Your group: since names are hidden, the game cannot color theirs. Over
-- each member's quiet plate, Wanderer writes the name small, in the game's
-- color for your group (option, on by default); never while the game writes
-- it itself, nor under the label.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local CHECK_EVERY = 0.5 -- plates change rarely (a fight, a plate appearing: events)
local FULL_EVERY = 0.15 -- a look at every plate asked by an event: at most this often
local FADE_IN, FADE_OUT = 0.25, 0.6

local driver
local since = 0 -- since the last look at every plate
local dirty = false -- an event asked for a look at every plate
local onNow = false -- On(), as of the last look
local tweens = setmetatable({}, { __mode = "k" }) -- plate -> its tween, while Wanderer holds its opacity
local active = setmetatable({}, { __mode = "k" }) -- plate -> true while it (or its name) fades: stepped every frame
local seen = setmetatable({}, { __mode = "k" }) -- plate -> true once looked at for the character it carries
local count = 0 -- plates shown
local quiet = setmetatable({}, { __mode = "k" }) -- plate -> true while kept invisible
local marks = setmetatable({}, { __mode = "k" }) -- plate -> its group mark (a name)
local MARK_SIZE = 11
local GUILD_MARK_ALPHA = 0.5 -- a guild member's name: there, never loud
local KNOWN_MARK_ALPHA = 0.6 -- a player you have met: the same
local KNOWN_COLOR = { 0.92, 0.88, 0.78 } -- a warm parchment white, apart from the group's and the guild's colors

-- Whether a plate is kept invisible (the label then stands lower, on the head).
function ns.IsPlateQuiet(plate) return quiet[plate] == true end

-- Another addon drawing the nameplates (Compat.lua): its plates are its own, Wanderer neither turns them
-- on nor touches them, and the label stands over them as they are.
local function Yielded() return ns.Yields ~= nil and ns.Yields("nameplates") ~= nil end

local function On()
	local db = ns.db
	if ns.zone == "dungeon" or ns.zone == "raid" or ns.zone == "pvp" then return false end -- the game's own plates there
	if not (db and db.enabled and db.label.allHeads and db.label.anchor == "head") then return false end
	return not Yielded()
end

-- The part of the game's plate that draws (a nameplate addon's own frame is never touched).
local function Drawn(plate)
	local drawn = plate.UnitFrame
	return type(drawn) == "table" and drawn.SetAlpha and drawn or nil
end

-- The player's own choice in the game's options (saved before Wanderer wrote).
local function Own(cvar)
	local original = ns.root and ns.root.original
	return original ~= nil and original[cvar] == "1"
end

-- What a plate's character is, read once while the plate carries it (plate -> { token, hostile, live, minus,
-- player, companion, guildmate, name }): forgotten when the plate comes or goes, the group or the guild
-- changes, or a character's reaction does. Read live, never kept: a reaction or a name the game hides.
local facts = setmetatable({}, { __mode = "k" })

-- A player other than you.
local function OtherPlayer(unit)
	return not Clean(Safe(UnitIsUnit, unit, "player")) and Clean(Safe(UnitIsPlayer, unit)) and true or false
end

local function Facts(plate, unit)
	local f = facts[plate]
	if f and f.token == unit and not f.live then return f end
	f = f or {}
	local hostile, name = Safe(UnitCanAttack, "player", unit), Safe(UnitName, unit)
	f.token, f.name = unit, name
	f.live = U.IsSecret(hostile) or U.IsSecret(name)
	f.secretHostile = U.IsSecret(hostile)
	f.hostile = not f.secretHostile and hostile and true or false
	f.minus = Clean(Safe(UnitClassification, unit)) == "minus"
	f.player = Clean(Safe(UnitIsPlayer, unit)) and true or false
	local other = OtherPlayer(unit)
	f.companion = other and (Clean(Safe(UnitInParty, unit)) or Clean(Safe(UnitInRaid, unit))) and true or false
	-- (a member of your guild, not yourself, out of your group or in it)
	f.guildmate = other and Clean(Safe(UnitIsInMyGuild, unit)) and true or false
	-- (a player this character has met: Acquaintances.lua)
	-- (your group's members: their names follow the group's own setting, never brought back by this one)
	f.known = other and not f.companion and ns.db.knownMarks and ns.IsAcquaintance and ns.IsAcquaintance(unit) and true or false
	facts[plate] = f
	return f
end

-- Quiet: allies and critters always; enemies out of a fight unless the
-- player shows them then.
local function Quiet(f)
	if f.secretHostile then return false end
	if not f.hostile then return true end
	if f.minus then return not Own("nameplateShowEnemyMinus") end
	-- Enemies as you come near, with their health bar: shown, the game fades them with the distance.
	if ns.db.enemyNames == "near" and ns.db.nearNames.show == "bar" then return false end
	-- Enemies: the game shows them in a fight anyway.
	return not Own("nameplateShowAll") and not (ns.inCombat or InCombatLockdown())
end

-- An enemy whose name comes as you come near (out of a fight).
local function NearEnemy(f)
	if ns.db.enemyNames ~= "near" or ns.db.nearNames.show ~= "name" or ns.inCombat then return false end
	return f.hostile
end

local function MarkWanted(f, unit, isQuiet, plate)
	if not isQuiet then return false end
	if not ((ns.db.groupMarks and f.companion) or (ns.db.guildMarks and f.guildmate) or (ns.db.knownMarks and f.known)
		or NearEnemy(f)) then
		return false
	end
	if ns.GameShowsName(unit) then return false end
	-- The label describes this character already: gone at once, never under it.
	if ns.LabelPlate() == plate then return false, true end
	if ns.IsLabelActive() then
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

-- And for your guild (its guild chat).
local function GuildColor()
	local info = ChatTypeInfo and ChatTypeInfo.GUILD
	if info and info.r then return info.r, info.g, info.b end
	return 0.25, 1, 0.25
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

-- Allies' plates kept invisible take no click either (the game's own switch, out of a fight only): the
-- click goes to the world behind. Given back as it was when Wanderer lets them go.
local clickThrough -- the game's value before Wanderer set it, while set
local function ClickThrough(want)
	local api = C_NamePlate
	if not (api and api.SetNamePlateFriendlyClickThrough) or InCombatLockdown() then return end
	if want and clickThrough == nil then
		local own = api.GetNamePlateFriendlyClickThrough and Clean(Safe(api.GetNamePlateFriendlyClickThrough))
		clickThrough = own and true or false
		if not clickThrough then pcall(api.SetNamePlateFriendlyClickThrough, true) end
	elseif not want and clickThrough ~= nil then
		if not clickThrough then pcall(api.SetNamePlateFriendlyClickThrough, false) end
		clickThrough = nil
	end
end

-- Brings one plate (and its name) toward its wanted opacity. Returns true while it is still moving. A plate
-- Wanderer never hid is never written to.
-- A quiet plate the game draws again by itself (the end of a fight, its settings written again): put back at
-- once to the opacity Wanderer holds, never a second seen. (hooked once per plate, a light check)
local held = setmetatable({}, { __mode = "k" }) -- drawn part -> the opacity Wanderer holds it at
local holding = setmetatable({}, { __mode = "k" })
local function Hold(drawn, alpha)
	held[drawn] = alpha
	if holding[drawn] or not hooksecurefunc then return end
	holding[drawn] = true
	hooksecurefunc(drawn, "SetAlpha", function(self, value)
		local want = held[self]
		if want == nil or (self.IsForbidden and self:IsForbidden()) then return end
		-- (the plate handed to someone who can be attacked meanwhile: no longer an ally to keep unseen)
		local unit = rawget(self, "unit")
		if type(unit) == "string" and Clean(Safe(UnitCanAttack, "player", unit)) then
			held[self] = nil
			return
		end
		if U.IsSecret(value) or value ~= want then self:SetAlpha(want) end
	end)
end

local function UpdatePlate(plate, elapsed, on)
	local drawn = not (plate.IsForbidden and plate:IsForbidden()) and Drawn(plate)
	local unit = plate.namePlateUnitToken or (drawn and drawn.unit)
	if not (drawn and unit) then
		active[plate] = nil
		return false
	end
	-- (what the character is: read once while the plate carries it, and only while Wanderer looks after them)
	local f = on and Facts(plate, unit)
	local wanted = (f and Quiet(f)) and 0 or 1
	quiet[plate] = wanted == 0
	if wanted ~= 0 then held[drawn] = nil end -- (shown: never held, whatever it carried before)
	local still = false
	local tween = tweens[plate]
	-- A plate to show, left at nothing (an ally's hold met the game's own reset as it was handed to an enemy):
	-- Wanderer is the only one to set this part's opacity, so it is given back at once.
	if wanted == 1 and not tween then
		local now = Clean(Safe(drawn.GetAlpha, drawn))
		if type(now) == "number" and now < 1 then drawn:SetAlpha(1) end
	end
	if tween or wanted ~= 1 then
		if not tween then
			-- A plate appearing for a quiet character never flashes first; one already seen fades from where it is.
			local now = seen[plate] and Clean(Safe(drawn.GetAlpha, drawn))
			tween = U.Tween(type(now) == "number" and now or wanted)
			tweens[plate] = tween
		end
		local alpha = tween:Step(wanted, elapsed, FADE_IN, FADE_OUT)
		-- (an ally's plate kept invisible: held there; anything else, an enemy's above all, never held)
		Hold(drawn, (wanted == 0 and alpha == 0 and f and not f.hostile and not f.secretHostile) and 0 or nil)
		if Clean(Safe(drawn.GetAlpha, drawn)) ~= alpha then drawn:SetAlpha(alpha) end
		if alpha ~= wanted then
			still = true
		elseif wanted == 1 then
			tweens[plate] = nil -- as the game draws it again: left to the game
		end
	end
	seen[plate] = true
	local markOn, underLabel = false, false
	if f then markOn, underLabel = MarkWanted(f, unit, wanted == 0, plate) end
	if markOn or marks[plate] then
		local mark = Mark(plate)
		local full = 1
		if markOn then
			-- (its words written again only when they change; a name the game hides, each time)
			if f.live or mark.name ~= f.name then
				pcall(mark.SetText, mark, f.name)
				mark.name = not f.live and f.name or nil
			end
			if ns.db.groupMarks and f.companion then
				mark:SetTextColor(PartyColor())
			elseif ns.db.guildMarks and f.guildmate then
				mark:SetTextColor(GuildColor())
				full = GUILD_MARK_ALPHA
			elseif ns.db.knownMarks and f.known then
				mark:SetTextColor(KNOWN_COLOR[1], KNOWN_COLOR[2], KNOWN_COLOR[3])
				full = KNOWN_MARK_ALPHA
			else
				mark:SetTextColor(ns.UnitColor(unit, f.player))
			end
		end
		if underLabel then mark.tween:Set(0) end
		local markAlpha = mark.tween:Step(markOn and full or 0, elapsed, FADE_IN, FADE_OUT)
		if mark:GetAlpha() ~= markAlpha then mark:SetAlpha(markAlpha) end
		mark:SetShown(markAlpha > 0)
		if markAlpha ~= (markOn and full or 0) then still = true end
	end
	active[plate] = still or nil
	return still
end

-- A plate whose opacity Wanderer held, let go as the game draws it (the plate goes to another character next).
-- (a plate handed to another character, or gone: its hold dropped and its opacity given back, held or faded)
local function LetGo(plate)
	local drawn = not (plate.IsForbidden and plate:IsForbidden()) and Drawn(plate)
	local wasHeld = drawn and held[drawn] ~= nil
	if drawn then held[drawn] = nil end
	if not (tweens[plate] or wasHeld) then return end
	tweens[plate] = nil
	if drawn then pcall(drawn.SetAlpha, drawn, 1) end
end

-- A look at every plate shown.
local function Update(elapsed)
	onNow = On()
	ClickThrough(onNow)
	local still = false
	for _, plate in ipairs(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}) do
		if UpdatePlate(plate, elapsed, onNow) then still = true end
	end
	return still
end

-- Only the plates fading, every frame.
local function StepActive(elapsed)
	for plate in pairs(active) do UpdatePlate(plate, elapsed, onNow) end
end

local function Wake()
	if driver and (On() or next(tweens) or clickThrough ~= nil) then driver:Show() end
end

-- Every plate looked at again (an option changed), or, given the label's plate, only that one and the one it
-- left (the label shown: the small name under it steps aside at once).
local labelPlate -- the plate the label stood on, last told
function ns.RefreshPlates(plate)
	if not driver then return end
	if plate then
		onNow = On()
		UpdatePlate(plate, 0, onNow)
		if labelPlate and labelPlate ~= plate then UpdatePlate(labelPlate, 0, onNow) end
		labelPlate = plate
	else
		Update(0)
		since = 0
	end
	Wake()
end

-- (/wanderer plates dump) every plate shown, as Wanderer sees it and decides, over 10 seconds (a look every 2):
-- written into WandererDB.platesDump for a look after a /reload.
function ns.DumpPlates()
	local out = {}
	local function Look(at)
		local cvars = {}
		for _, name in ipairs({ "nameplateShowEnemies", "nameplateShowAll", "nameplateMinAlpha", "nameplateMaxAlpha",
			"nameplateMinAlphaDistance", "nameplateMaxAlphaDistance", "nameplateMaxDistance", "nameplateShowEnemyMinus" }) do
			cvars[#cvars + 1] = name:gsub("nameplate", "") .. "=" .. tostring(Clean(Safe(GetCVar, name)))
		end
		out[#out + 1] = ("t=%d v=%s fight=%s on=%s count=%d | %s"):format(at, tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Wanderer", "Version")), tostring(ns.inCombat), tostring(On()), count, table.concat(cvars, " "))
		for _, plate in ipairs(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}) do
			local drawn = Drawn(plate)
			local unit = plate.namePlateUnitToken or (drawn and drawn.unit)
			local f = facts[plate]
			out[#out + 1] = ("  %s %s | hostile=%s secret=%s canAttack=%s reaction=%s | quiet=%s held=%s tween=%s | drawn=%s plate=%s shown=%s forbidden=%s"):format(
				tostring(unit), tostring(Clean(Safe(UnitName, unit))), tostring(f and f.hostile), tostring(f and f.secretHostile),
				tostring(Clean(Safe(UnitCanAttack, "player", unit))), tostring(Clean(Safe(UnitReaction, unit, "player"))),
				tostring(quiet[plate]), tostring(drawn and held[drawn]), tostring(tweens[plate] ~= nil),
				tostring(drawn and Clean(Safe(drawn.GetAlpha, drawn))), tostring(Clean(Safe(plate.GetAlpha, plate))),
				tostring(Clean(Safe(plate.IsShown, plate))), tostring(plate.IsForbidden and plate:IsForbidden()))
		end
	end
	for at = 0, 10, 2 do
		C_Timer.After(at, function()
			Look(at)
			if at == 10 then
				ns.root.platesDump = out
				ns.Print(ns.L.UF_DUMP_DONE)
			end
		end)
	end
end

-- What the plates know of their characters read again (the players you know changed).
function ns.PlatesForget()
	wipe(facts)
	dirty = true
	Wake()
end

function ns.InitPlates()
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", function(self, elapsed)
		since = since + elapsed
		-- (a fade moving: those plates every frame, for it to be soft; every plate now and then, sooner when
		-- an event asks)
		if next(active) then StepActive(elapsed) end
		if since >= CHECK_EVERY or (dirty and since >= FULL_EVERY) then
			dirty = false
			since = 0
			Update(0)
		end
		-- Asleep with no plate shown, or the option off and every plate back (the clicks given back, else
		-- woken again after the fight).
		if not next(active) and (count == 0 or not onNow) then
			if not onNow then
				for plate in pairs(tweens) do LetGo(plate) end
				ClickThrough(false)
			end
			self:Hide()
		end
	end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	-- (a duel: who may attack you changes without a word from the game's reactions)
	pcall(events.RegisterEvent, events, "DUEL_FINISHED")
	pcall(events.RegisterEvent, events, "DUEL_REQUESTED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	-- (who is in your guild, a character's reaction: what the plates know of them read again)
	pcall(events.RegisterEvent, events, "GUILD_ROSTER_UPDATE")
	pcall(events.RegisterEvent, events, "UNIT_FACTION")
	events:SetScript("OnEvent", function(_, event, unit)
		local plate = (event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED") and unit and C_NamePlate
			and Safe(C_NamePlate.GetNamePlateForUnit, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			count = count + 1
			if plate then
				-- Hidden at once if it should be: no flash of a quiet plate. Only this plate is looked at.
				LetGo(plate)
				seen[plate] = nil
				-- A plate handed to someone else: the name it carried goes at once.
				facts[plate] = nil
				local mark = marks[plate]
				if mark then
					mark.tween:Set(0)
					mark:SetAlpha(0)
					mark:Hide()
					mark.name = nil
				end
				onNow = On()
				UpdatePlate(plate, 0, onNow)
			end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			count = math.max(0, count - 1)
			if plate then
				active[plate] = nil
				facts[plate] = nil
				LetGo(plate)
			end
		elseif event == "UNIT_FACTION" then
			-- (a character's reaction changed: its plate's read again at the next look)
			local changed = unit and C_NamePlate and Safe(C_NamePlate.GetNamePlateForUnit, unit)
			if type(changed) ~= "table" then return end
			facts[changed] = nil
			dirty = true
		else
			-- (the group, the guild: every plate's character read again)
			if event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_REGEN_DISABLED"
				or event == "DUEL_FINISHED" or event == "DUEL_REQUESTED" then wipe(facts) end
			-- (a fight, the group: every plate looked at soon, not on every event)
			dirty = true
		end
		Wake()
	end)
	count = #(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {})
	ns.RefreshPlates()
end
