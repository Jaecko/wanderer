local _, ns = ...

-- Where your heals over time show (Hots.lua follows them): on your friends' health bars (your own frame, your
-- party's frames and the game's group and raid frames, your target and focus when friendly, friendly
-- nameplates), a soft green band starting where the health ends, the part your spells are about to restore;
-- beside it, a small plus that fills up as that healing covers what is missing: whole, they will be topped,
-- no need to cast more. Never on enemies.
--
-- The game draws the heals being cast (its incoming heals, after the health) on its own frames: the band
-- starts after them, so nothing is drawn twice. Those heals are the spells still in your hands and in other
-- healers': your heals over time are not among them. The game's hidden numbers (health, incoming heals) go
-- straight to the bars: the game compares, Wanderer never reads them.
--
-- Nothing of the game's frames is changed: Wanderer's own pieces lie over them, made outside a fight when the
-- frame under them is protected.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

-- (the health bands' pieces, DotBars.lua's: the bars found, the bands laid and tinted, the driver)
local Parts = ns.HealthBands
local Walk, IsBar, Level, Hide = Parts.Walk, Parts.IsBar, Parts.Level, Parts.Hide
local BAND_COLOR = { 0.2, 0.6, 0.35, 0.5 } -- a deep green, darker and quieter than the game's incoming heals
local EDGE_COLOR = { 0.56, 0.88, 0.64, 0.95 } -- the kit's green, where the band ends
local MARK_COLOR = EDGE_COLOR -- the plus: the same green as that line
local WHITE = Parts.WHITE

-- The unit frames, by unit: the setting that shows them.
local FRAMES = {
	{ unit = "player", setting = "player", frame = "PlayerFrame" },
	{ unit = "target", setting = "target", frame = "TargetFrame" },
	{ unit = "focus", setting = "target", frame = "FocusFrame" },
}

-- The game's group and raid frames, by name (others are told when the game gives them a unit).
local COMPACT_NAMES = {}
for i = 1, 5 do COMPACT_NAMES[#COMPACT_NAMES + 1] = "CompactPartyFrameMember" .. i end
for i = 1, 40 do COMPACT_NAMES[#COMPACT_NAMES + 1] = "CompactRaidFrame" .. i end
for group = 1, 8 do
	for i = 1, 5 do COMPACT_NAMES[#COMPACT_NAMES + 1] = "CompactRaidGroup" .. group .. "Member" .. i end
end

local overlays = setmetatable({}, { __mode = "k" }) -- a health bar -> its overlay
local compact = setmetatable({}, { __mode = "k" }) -- the game's group and raid frames known
local plateUnits = U.ShownPlates -- nameplate token -> true while shown (Util.lua keeps it)
local driver

-- (each part on unless turned off; the plus too)
local function Setting(key) return Parts.Option("hots", key) end

-- A bar that fills from left to right (the band follows the health that way; any other, nothing on it).
local function Plain(bar)
	local orientation = bar.GetOrientation and Clean(Safe(bar.GetOrientation, bar))
	if orientation == "VERTICAL" then return false end
	local reverse = bar.GetReverseFill and Clean(Safe(bar.GetReverseFill, bar))
	return not reverse
end

-- Drawing ----------------------------------------------------------------------------------------------

-- The band: from where the health (and the game's incoming heals) end, on over what your spells will restore;
-- cut at the bar's end. lead: the game's incoming heals again, unseen, for the band to start after them.
local function Band(bar)
	local band = CreateFrame("Frame", nil, bar)
	-- (exactly the part of the bar the eye sees, cut to it: never above or below its fill)
	Parts.Cover(band, bar)
	band:SetFrameLevel(Level(bar) + 2)
	local health = Parts.HealthFill(bar)
	local width = Clean(Safe(bar.GetWidth, bar)) or 100
	local lead = CreateFrame("StatusBar", nil, band)
	lead:SetPoint("TOPLEFT", health, "TOPRIGHT")
	lead:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT")
	lead:SetWidth(width)
	lead:SetStatusBarTexture(WHITE)
	lead:SetAlpha(0)
	local fill = CreateFrame("StatusBar", nil, band)
	fill:SetWidth(width)
	fill:SetStatusBarTexture(WHITE)
	fill:SetStatusBarColor(unpack(BAND_COLOR))
	local edge = fill:CreateTexture(nil, "OVERLAY")
	edge:SetTexture(WHITE)
	edge:SetVertexColor(unpack(EDGE_COLOR))
	edge:SetWidth(1)
	edge:SetPoint("TOPRIGHT", fill:GetStatusBarTexture(), "TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT", fill:GetStatusBarTexture(), "BOTTOMRIGHT")
	band:Hide()
	return { bar = bar, band = band, lead = lead, fill = fill, health = health, edge = edge }
end


-- Where the band starts: after the health, or after the game's incoming heals.
local function StartAfter(overlay, texture)
	if overlay.after == texture then return end
	overlay.after = texture
	overlay.fill:ClearAllPoints()
	overlay.fill:SetPoint("TOPLEFT", texture, "TOPRIGHT")
	overlay.fill:SetPoint("BOTTOMLEFT", texture, "BOTTOMRIGHT")
end

-- The plus, small and fine (arms a fifth of its size), filling up from below in the band's edge green; a faint one
-- behind it, on a thin dark edge to read on any bar. Each arm is a bar of the whole sign's height, seen only through its arm (the across one fills in the
-- middle of the way up).
local function Plus(parent, size, level)
	local mark = CreateFrame("Frame", nil, parent)
	mark:SetSize(size, size)
	mark:SetFrameLevel(level)
	local thick = math.max(1, math.floor(size / 5 + 0.5))
	mark.arms = {}
	for _, upright in ipairs({ true, false }) do
		local w, h = upright and thick or size, upright and size or thick
		local shade = mark:CreateTexture(nil, "BACKGROUND")
		shade:SetColorTexture(0, 0, 0, 0.4)
		shade:SetSize(w + 2, h + 2)
		shade:SetPoint("CENTER")
		local dim = mark:CreateTexture(nil, "BORDER")
		dim:SetColorTexture(MARK_COLOR[1], MARK_COLOR[2], MARK_COLOR[3], 0.18)
		dim:SetSize(w, h)
		dim:SetPoint("CENTER")
		local window = CreateFrame("Frame", nil, mark)
		window:SetSize(w, h)
		window:SetPoint("CENTER")
		window:SetClipsChildren(true)
		window:SetFrameLevel(level + 1)
		local arm = CreateFrame("StatusBar", nil, window)
		arm:SetAllPoints(mark)
		arm:SetOrientation("VERTICAL")
		arm:SetStatusBarTexture(WHITE)
		arm:SetStatusBarColor(unpack(MARK_COLOR))
		mark.arms[#mark.arms + 1] = arm
	end
	mark:Hide()
	return mark
end


-- What a friend misses (nil: not known; the game's hidden number when it hides it, for the plus to compare).
local function Missing(unit)
	local missing = Safe(UnitHealthMissing, unit)
	if U.IsSecret(missing) or type(missing) == "number" then return missing end
	local health, most = Clean(Safe(UnitHealth, unit)), Clean(Safe(UnitHealthMax, unit))
	if type(health) == "number" and type(most) == "number" then return most - health end
	return nil
end

-- The plus: shown while your heals cover part of what is missing; whole, all of it.
local function Mark(overlay, unit, left)
	local mark = overlay.mark
	if not mark then return end
	local missing = Setting("mark") and Missing(unit)
	-- (nothing missing, or not known: nothing to cover)
	if not U.IsSecret(missing) and (type(missing) ~= "number" or missing <= 0) then return mark:Hide() end
	for _, arm in ipairs(mark.arms) do
		if not pcall(arm.SetMinMaxValues, arm, 0, missing) then return mark:Hide() end
		arm:SetValue(left)
	end
	mark:Show()
end

-- The band moved onto the fill seen now (Wanderer's block over the game's place, or the game's own).
local function Follow(overlay)
	local health = Parts.HealthFill(overlay.bar)
	if not health or health == overlay.health then return end
	overlay.health, overlay.after = health, nil
	overlay.lead:ClearAllPoints()
	overlay.lead:SetPoint("TOPLEFT", health, "TOPRIGHT")
	overlay.lead:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT")
	Parts.Cover(overlay.band, overlay.bar)
end

-- One overlay for one friend: shown while your spells on it still have healing to give.
local function Paint(overlay, unit, predicts)
	local left = ns.HotsLeft(unit, true)
	if left <= 0 then return Hide(overlay) end
	Follow(overlay)
	local width = Clean(Safe(overlay.bar.GetWidth, overlay.bar))
	if width and width > 0 then
		overlay.fill:SetWidth(width)
		overlay.lead:SetWidth(width)
	end
	-- (the hidden maximum straight to the bar)
	local most = Safe(UnitHealthMax, unit)
	if (not U.IsSecret(most) and type(most) ~= "number") or not pcall(overlay.fill.SetMinMaxValues, overlay.fill, 0, most) then return Hide(overlay) end
	overlay.fill:SetValue(left)
	-- After the game's incoming heals where it draws them (none told: right after the health).
	local after = overlay.health
	local incoming = predicts and Safe(UnitGetIncomingHeals, unit)
	if (U.IsSecret(incoming) or (type(incoming) == "number" and incoming > 0))
		and pcall(overlay.lead.SetMinMaxValues, overlay.lead, 0, most) and pcall(overlay.lead.SetValue, overlay.lead, incoming) then
		after = overlay.lead:GetStatusBarTexture()
	end
	StartAfter(overlay, after)
	Parts.Tint(overlay, unit, "hot", BAND_COLOR, EDGE_COLOR)
	overlay.band:Show()
	Mark(overlay, unit, left)
	return true
end

-- An overlay for a bar, made once (not in a fight over a protected frame: then at the next drawing after it).
local function OverlayFor(bar, place)
	local overlay = overlays[bar]
	if overlay then return overlay end
	if not Plain(bar) then return nil end
	local parent = place and place.parent
	if Clean(Safe(InCombatLockdown)) and (Clean(Safe(bar.IsProtected, bar)) or (parent and Clean(Safe(parent.IsProtected, parent)))) then
		return nil
	end
	overlay = Band(bar)
	if place then
		local mark = Plus(parent or bar, place.size, Level(bar) + 4)
		mark:SetPoint(place.point, place.to or bar, place.toPoint, place.x or 0, place.y or 0)
		overlay.mark = mark
	end
	overlays[bar] = overlay
	return overlay
end

-- The bars ---------------------------------------------------------------------------------------------

-- Whether the game draws its incoming heals on this bar (then the band starts after them).
local function Predicts(bar, frame)
	return Walk(bar, "MyHealPredictionBar") ~= nil or Walk(frame, "myHealPredictionBar") ~= nil
		or Walk(frame, "myHealPrediction") ~= nil
end

local function PlayerBar()
	local fromGame = PlayerFrame_GetHealthBar and Safe(PlayerFrame_GetHealthBar)
	return IsBar(fromGame) or IsBar(Walk(_G, "PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar"))
		or IsBar(_G.PlayerFrameHealthBar)
end

local function PlayerPortrait()
	local portrait = Walk(_G, "PlayerFrame", "PlayerFrameContainer", "PlayerPortrait") or _G.PlayerPortrait
	return type(portrait) == "table" and type(portrait.GetCenter) == "function" and portrait or nil
end

-- Where a plus goes: beside a bar, inside a bar (the same tables every drawing).
local BESIDE = { size = 9, point = "LEFT", toPoint = "RIGHT", x = 3 }
local INSIDE = { size = 9, point = "RIGHT", toPoint = "RIGHT", x = -2 }

-- Each bar to draw now: { bar, unit, frame, place } (place: where its plus goes). The same list every drawing.
local list, spare = {}, {}
local function Add(bar, unit, frame, place)
	if bar and unit and not list[bar] then
		list[bar] = true
		local entry = table.remove(spare) or {}
		entry.bar, entry.unit, entry.frame, entry.place = bar, unit, frame, place
		list[#list + 1] = entry
	end
end

-- Where the plus of a unit frame goes: by its portrait (one table per frame, its fields set again each drawing).
local function PortraitPlace(entry, portrait)
	if not portrait then return nil end
	-- (Ink lines: the medallion's level tab sits in the bottom corner towards the bars, the plus in the other one:
	-- bottom left on your frame, bottom right on the others, which are in mirror; down with the medallion when the
	-- target's auras stand above it)
	local lines = ns.UnitFramesLines and ns.UnitFramesLines()
	local right = lines and entry.unit ~= "player"
	local frame = _G[entry.frame]
	-- (the target's and the focus's frames are both "target" kinds for the unit frames)
	local drop = lines and ns.UnitFramesDrop and ns.UnitFramesDrop({ kind = entry.unit == "player" and "player" or "target", frame = frame }) or 0
	local place = entry.place or { size = 13, point = "CENTER" }
	entry.place = place
	place.parent, place.to = frame, portrait
	place.toPoint, place.x, place.y = right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -8 or 8, 8 - drop
	return place
end

local function Collect()
	for index = #list, 1, -1 do
		local entry = list[index]
		list[entry.bar], list[index] = nil, nil
		spare[#spare + 1] = entry
	end
	for _, entry in ipairs(FRAMES) do
		if Setting(entry.setting) then
			local bar, portrait
			if entry.unit == "player" then
				bar, portrait = PlayerBar(), PlayerPortrait()
			else
				bar, portrait = Parts.FrameBar(entry), Parts.Portrait(entry)
			end
			Add(bar, entry.unit, _G[entry.frame], PortraitPlace(entry, portrait))
		end
	end
	if Setting("group") then
		for i = 1, 4 do
			local member = Walk(_G, "PartyFrame", "MemberFrame" .. i) or _G["PartyMemberFrame" .. i]
			if type(member) == "table" and Clean(Safe(member.IsVisible, member)) then
				local bar = IsBar(Walk(member, "HealthBarContainer", "HealthBar")) or IsBar(Walk(member, "healthbar"))
					or IsBar(_G["PartyMemberFrame" .. i .. "HealthBar"])
				local unit = Clean(rawget(member, "unit")) or ("party" .. i)
				Add(bar, unit, member, BESIDE)
			end
		end
		for frame in pairs(compact) do
			if not (frame.IsForbidden and frame:IsForbidden()) and Clean(Safe(frame.IsVisible, frame)) then
				local unit = Clean(rawget(frame, "displayedUnit")) or Clean(rawget(frame, "unit"))
				-- (the nameplates are the game's compact frames too: theirs below)
				if type(unit) == "string" and not unit:find("^nameplate") then
					Add(IsBar(rawget(frame, "healthBar")), unit, frame, INSIDE)
				end
			end
		end
	end
	if Setting("plates") then
		-- (asked once a drawing, not for every plate)
		local yielded = ns.Yields and ns.Yields("nameplates") ~= nil
		for unit in pairs(plateUnits) do
			if Clean(Safe(UnitCanAssist, "player", unit)) then Add(Parts.PlateBar(unit, yielded), unit, nil, BESIDE) end
		end
	end
	return list
end

-- The game's group and raid frames there now (by name; the others when they get a unit).
local function Scan()
	for _, name in ipairs(COMPACT_NAMES) do
		local frame = _G[name]
		if type(frame) == "table" then compact[frame] = true end
	end
end

-- The driver ---------------------------------------------------------------------------------------------

local function HideAll()
	for _, overlay in pairs(overlays) do Hide(overlay) end
	if driver then driver.Keep(false) end
end

local drawn = {} -- this drawing's overlays
local function Draw()
	if not ns.HotsOn() then return HideAll() end
	local shown = false
	wipe(drawn)
	-- (each friend shown asked, even with nothing known of yours: an aura read may bring one)
	for _, entry in ipairs(Collect()) do
		local overlay = OverlayFor(entry.bar, entry.place)
		-- (its plus where the place says now: the look may have moved it)
		local place = entry.place
		local key = place and (tostring(place.toPoint) .. ":" .. tostring(place.x) .. ":" .. tostring(place.y))
		if overlay and overlay.mark and place and overlay.toPoint ~= key then
			overlay.toPoint = key
			overlay.mark:ClearAllPoints()
			overlay.mark:SetPoint(place.point, place.to or entry.bar, place.toPoint, place.x or 0, place.y or 0)
		end
		if overlay and not drawn[overlay] then
			drawn[overlay] = true
			if Paint(overlay, entry.unit, Predicts(entry.bar, entry.frame)) then shown = true end
		end
	end
	for _, overlay in pairs(overlays) do
		if not drawn[overlay] then Hide(overlay) end
	end
	-- (asleep while nothing of yours ticks anywhere)
	if driver then driver.Keep(shown or ns.HotsBusy()) end
end

function ns.HotBarsWake(soon) if driver then driver.Wake(soon) end end
function ns.HotBarsRefresh() if driver then driver.Refresh() end end

function ns.InitHotBars()
	driver = Parts.NewDriver(Draw, ns.HotsOn, HideAll, { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
		"PLAYER_REGEN_ENABLED" }, function(event)
		if event == "GROUP_ROSTER_UPDATE" then Scan() end
	end)
	Scan()
	-- (a frame the game gives a unit to: known from then; nothing of it changed)
	if hooksecurefunc and CompactUnitFrame_SetUnit then
		hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
			if type(frame) == "table" then compact[frame] = true end
		end)
	end
end
