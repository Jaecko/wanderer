local _, ns = ...
local L = ns.L

-- The minimap in Wanderer's hand (option, offered at the welcome): its edge melts into the world (a soft round mask, no ring); the
-- group finder's eye, the day and night and the mail stand apart from it, smaller, quieter; under it, the
-- zone in small golden capitals over a fine golden rule, the time and where you stand on one line, on a dark
-- band fading at both ends. The game's own zone band, clock and coordinates step aside (their place is
-- taken, nothing is lost: a click on the time opens the game's clock). Nothing else changes; switched off,
-- every piece goes back exactly as the game drew it. The map is moved up against the top of the screen. Never a protected frame during a fight.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local FADE_MASK = "Interface\\AddOns\\Wanderer\\Media\\MinimapFade"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local AGAIN = 2 -- seconds: the game places some pieces again (the eye, the mail): placed back (only if moved)
local SEARCH_AGAIN = 10 -- seconds between two looks for the game's coordinates, while not found
local REST, NEAR = 0.8, 1
-- The pieces around, placed outside the edge (angle in degrees from the right, counterclockwise; scale).
local AROUND = {
	eye = { angle = 225, scale = 0.6, out = 12 },
	time = { angle = 40, scale = 0.55, out = 8 },
	mail = { angle = 140, scale = 0.7, out = 8 },
}
local EYE_NAMES = { "LFGMinimapFrame", "MiniMapLFGFrame", "QueueStatusButton", "QueueStatusMinimapButton" }

local info, driver
local kept = {} -- frame -> how the game had it { points, scale, alpha, mouse }
local coords -- the game's coordinates text (found by what it says)
local since, sinceAgain = 0, 0
local searched, tries = 0, 0 -- when the coordinates were looked for last, how many times (six at most)
local masked = false

local function On()
	return ns.db and ns.db.enabled and ns.db.world.styledMinimap and Minimap and MinimapCluster and true or false
end

local function Free(frame)
	return frame and frame.ClearAllPoints and not (InCombatLockdown() and frame.IsProtected and frame:IsProtected())
end

-- How the game had a piece, kept once (to give it back).
local function Keep(frame)
	if kept[frame] then return end
	local points = {}
	for index = 1, (frame:GetNumPoints() or 0) do points[index] = { frame:GetPoint(index) } end
	kept[frame] = { points = points, scale = frame:GetScale(), alpha = frame:GetAlpha(),
		mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() }
end

local function GiveBack(frame)
	local was = kept[frame]
	if not (was and Free(frame)) then return end
	frame:ClearAllPoints()
	for _, point in ipairs(was.points) do frame:SetPoint(unpack(point)) end
	frame:SetScale(was.scale or 1)
	frame:SetAlpha(was.alpha or 1)
	if frame.EnableMouse and was.mouse ~= nil then frame:EnableMouse(was.mouse) end
	kept[frame] = nil
end

-- A piece outside the edge, smaller.
local function Around(frame, spec)
	if not Free(frame) then return end
	Keep(frame)
	frame:SetScale(spec.scale)
	-- (on the screen: the map's edge, then the piece's own units)
	local radius = (Minimap:GetWidth() / 2) * Minimap:GetEffectiveScale() + spec.out * frame:GetEffectiveScale()
	radius = radius / frame:GetEffectiveScale()
	local angle = math.rad(spec.angle)
	local x, y = math.cos(angle) * radius, math.sin(angle) * radius
	-- (already there: left alone)
	local point, anchor, _, nowX, nowY = frame:GetPoint(1)
	if point == "CENTER" and anchor == Minimap and math.abs((nowX or 0) - x) < 0.5 and math.abs((nowY or 0) - y) < 0.5 then return end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- A piece stepping aside: unseen, not in the way of the mouse.
local function Aside(frame)
	if not (frame and frame.SetAlpha) or not Free(frame) then return end
	Keep(frame)
	frame:SetAlpha(0)
	if frame.EnableMouse then frame:EnableMouse(false) end
end

local Part = U.Part

-- The pieces, as the game names them (this game, and the others it was built from).
local function Eye()
	for _, name in ipairs(EYE_NAMES) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetObjectType then return frame end
	end
end

local function Mail()
	return Part(Part(MinimapCluster, "IndicatorFrame"), "MailFrame") or Part(_G, "MiniMapMailFrame")
end

local function ZoneBand()
	return { Part(MinimapCluster, "ZoneTextButton") or Part(_G, "MinimapZoneTextButton"), Part(MinimapCluster, "BorderTop"),
		Part(_G, "MinimapBorderTop") }
end

-- The game's coordinates: the text that reads "26.2, 41.8" around the minimap, wherever it is.
local COORDS = "^%s*%-?%d+[%.,]?%d*%s*[,;/]%s*%-?%d+[%.,]?%d*%s*$"
local function FindCoords(frame, depth)
	if not frame or depth > 4 then return nil end
	for _, region in ipairs({ frame:GetRegions() }) do
		local text = region.GetText and Clean(Safe(region.GetText, region))
		if type(text) == "string" and text:match(COORDS) then return region end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child ~= info then
			local found = FindCoords(child, depth + 1)
			if found then return found end
		end
	end
end

-- Under the map ---------------------------------------------------------------------------------

local function Clock()
	if GameTime_GetTime then
		local text = Clean(Safe(GameTime_GetTime, true))
		if text then return text end
	end
	return date("%H:%M")
end

local function Position()
	local map = C_Map and Clean(Safe(C_Map.GetBestMapForUnit, "player"))
	local point = map and Safe(C_Map.GetPlayerMapPosition, map, "player")
	if not point then return nil end
	local x, y = Safe(point.GetXY, point)
	x, y = Clean(x), Clean(y)
	if not (x and y) or (x == 0 and y == 0) then return nil end
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

local function DrawInfo()
	local zone = Clean(Safe(GetMinimapZoneText)) or Clean(Safe(GetZoneText)) or ""
	info.zone:SetText(U.Upper(zone))
	local where = Position()
	info.line:SetText(where and (Clock() .. "   ·   " .. where) or Clock())
end

local function MakeInfo()
	local C = ns.Skin.COLORS
	info = CreateFrame("Button", "WandererMinimapInfo", MinimapCluster)
	info:SetSize(220, 44)
	info:RegisterForClicks("AnyUp")
	-- The band: dark in its middle, fading to nothing at both ends.
	for index, side in ipairs({ "LEFT", "RIGHT" }) do
		local half = info:CreateTexture(nil, "BACKGROUND")
		half:SetPoint("TOP")
		half:SetPoint("BOTTOM")
		half:SetPoint(side)
		half:SetPoint(index == 1 and "RIGHT" or "LEFT", info, "CENTER")
		half:SetColorTexture(1, 1, 1, 1)
		local dark, clear = CreateColor and CreateColor(0.02, 0.02, 0.03, 0.62), CreateColor and CreateColor(0.02, 0.02, 0.03, 0)
		if dark and half.SetGradient then
			half:SetGradient("HORIZONTAL", index == 1 and clear or dark, index == 1 and dark or clear)
		else
			half:SetColorTexture(0.02, 0.02, 0.03, 0.4)
		end
	end
	info.zone = info:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	info.zone:SetPoint("TOP", info, "TOP", 0, -7)
	info.zone:SetWidth(210)
	info.zone:SetWordWrap(false)
	info.zone:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
	-- The fine golden rule, fading at both ends.
	for index, side in ipairs({ "LEFT", "RIGHT" }) do
		local rule = info:CreateTexture(nil, "ARTWORK")
		rule:SetHeight(1)
		rule:SetPoint("TOP", info.zone, "BOTTOM", 0, -4)
		rule:SetPoint(index == 1 and "RIGHT" or "LEFT", info, "CENTER")
		rule:SetWidth(80)
		rule:SetColorTexture(1, 1, 1, 1)
		local gold, clear = CreateColor and CreateColor(C.gold[1], C.gold[2], C.gold[3], 0.55),
			CreateColor and CreateColor(C.gold[1], C.gold[2], C.gold[3], 0)
		if gold and rule.SetGradient then
			rule:SetGradient("HORIZONTAL", index == 1 and clear or gold, index == 1 and gold or clear)
		else
			rule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.3)
		end
		info["rule" .. side] = rule
	end
	info.line = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info.line:SetPoint("TOP", info.ruleLEFT, "BOTTOM", 0, -5)
	info.line:SetPoint("LEFT", info, "LEFT", 0, 0)
	info.line:SetPoint("RIGHT", info, "RIGHT", 0, 0)
	info.line:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
	info:SetAlpha(REST)
	info:SetScript("OnEnter", function(self)
		self:SetAlpha(NEAR)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(Clean(Safe(GetZoneText)) or "", 1, 0.82, 0)
		local sub = Clean(Safe(GetSubZoneText))
		if sub and sub ~= "" then GameTooltip:AddLine(sub, 1, 1, 1) end
		GameTooltip:AddLine(L.MINIMAP_INFO_HINT, 0.55, 0.53, 0.46, true)
		GameTooltip:Show()
	end)
	info:SetScript("OnLeave", function(self)
		self:SetAlpha(REST)
		GameTooltip:Hide()
	end)
	-- (a click: the game's clock, as its own time button would)
	info:SetScript("OnClick", function()
		local clock = _G.TimeManagerClockButton
		if TimeManager_Toggle then Safe(TimeManager_Toggle) elseif clock and clock.Click then Safe(clock.Click, clock) end
	end)
	info:Hide()
end

-- Applying ---------------------------------------------------------------------------------------

-- The map moved up: as much room above it as on its right, for a quiet balance; only up, from where the
-- game lays it out (its size, its distance from the right edge, the buttons of the game: theirs). What moves
-- is the map's own holder (the map with it), else the map.
local function Top()
	local holder = Part(MinimapCluster, "MinimapContainer") or Minimap
	if not Free(holder) or not (UIParent:GetTop() and UIParent:GetRight() and Minimap:GetTop()) then return end
	Keep(holder)
	-- (from where it stands now: the rest of the way, nothing when it is there already)
	local screen, map = UIParent:GetEffectiveScale(), Minimap:GetEffectiveScale()
	local right = math.max(0, UIParent:GetRight() * screen - Minimap:GetRight() * map)
	local rise = (UIParent:GetTop() * screen - right - Minimap:GetTop() * map) / holder:GetEffectiveScale()
	if math.abs(rise) < 0.5 then return end
	local now = {}
	for index = 1, holder:GetNumPoints() do now[index] = { holder:GetPoint(index) } end
	holder:ClearAllPoints()
	for _, point in ipairs(now) do
		holder:SetPoint(point[1], point[2], point[3], point[4] or 0, (point[5] or 0) + rise)
	end
end

local function Place()
	Top()
	Around(Eye(), AROUND.eye)
	Around(_G.GameTimeFrame, AROUND.time)
	Around(Mail(), AROUND.mail)
	for _, part in pairs(ZoneBand()) do Aside(part) end
	Aside(_G.TimeManagerClockButton)
	if not coords and tries < 6 and GetTime() - searched >= SEARCH_AGAIN then
		searched, tries = GetTime(), tries + 1
		coords = FindCoords(MinimapCluster, 0)
	end
	if coords and coords.SetAlpha then
		Keep(coords)
		coords:SetAlpha(0)
	end
	-- (the ring and the borders of the game: gone, the edge melts)
	for _, part in pairs({ Part(_G, "MinimapCompassTexture"), Part(_G, "MinimapBorder"), Part(Part(_G, "MinimapBackdrop"), "MinimapBorder") }) do
		if part.SetAlpha then
			Keep(part)
			part:SetAlpha(0)
		end
	end
end

local function OnUpdate(_, elapsed)
	since, sinceAgain = since + elapsed, sinceAgain + elapsed
	if since >= 0.5 then
		since = 0
		DrawInfo()
	end
	if sinceAgain >= AGAIN then
		sinceAgain = 0
		Place()
	end
end

function ns.RefreshMinimapLook()
	if not info then return end
	if On() then
		if not masked and Minimap.SetMaskTexture then
			Safe(Minimap.SetMaskTexture, Minimap, FADE_MASK)
			masked = true
		end
		info:ClearAllPoints()
		info:SetPoint("TOP", Minimap, "BOTTOM", 0, -6)
		info:Show()
		searched, tries = -SEARCH_AGAIN, 0 -- (asked again: the coordinates looked for at once)
		Place()
		DrawInfo()
		driver:Show()
	else
		driver:Hide()
		info:Hide()
		if masked and Minimap.SetMaskTexture then
			Safe(Minimap.SetMaskTexture, Minimap, ROUND_MASK)
			masked = false
		end
		for frame in pairs(kept) do GiveBack(frame) end
		coords, searched = nil, 0
		-- (the discreet minimap, when asked, hides the ring again)
		if ns.RefreshClean then ns.RefreshClean() end
	end
end

function ns.InitMinimapLook()
	if not (Minimap and MinimapCluster) then return end
	MakeInfo()
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", OnUpdate)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function() ns.RefreshMinimapLook() end)
	ns.RefreshMinimapLook()
end
