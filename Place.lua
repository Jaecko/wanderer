local _, ns = ...
local L = ns.L

-- Placing the pieces Wanderer and its extensions lay on the screen (not the windows: those are dragged by
-- themselves): the notices, the emote bar, the chat's line, the route's arrow... One mode for them all, out
-- of a fight: each piece shows a golden frame with its name (a piece hidden now: a frame of its usual size),
-- dragged where you want, holding to the screen's edges and middle and to the other pieces; a right click
-- puts it back in its place. Done, Escape or a fight ends it. Every place is this character's.
--
-- A piece registers once (ns.Placeable, W.Placeable for the extensions): spec = { key, label, frame (or a
-- function giving it, nil while it is not made), default = { point, relPoint, x, y } against the screen (or a
-- function giving it), size = { width, height } when the frame says none, scale() when the piece takes its
-- scale only when shown, live = false when the frame is shared and says nothing of this piece's size,
-- enabled() false: not offered now, onMoved(point, x, y), reset(), load() and save(spot) when the piece
-- keeps its place itself }. It is put in its place by ns.PlaceApply(key, frame).

local SNAP = 8 -- how near a line a piece is held to it
local MOVE_FROM = 3 -- pixels before a press becomes a drag
local FALLBACK_SIZE = { 160, 40 }
local VEIL_ALPHA = 0.25
local GUIDE_ALPHA, CENTER_ALPHA = 0.55, 0.12
-- Where a point stands on a box, from its left and its bottom.
local FACTORS = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
	RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local registry, order = {}, {}
local mode, panel, resetAll
local proxies = {}
local guides = {}
local dragging -- { proxy, dx, dy, x, y, moved }

local function Round(value) return math.floor(value + 0.5) end

local function Screen()
	return UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
end

-- A function's answer, a value as it is.
local function Read(value)
	if type(value) ~= "function" then return value end
	local ok, result = pcall(value)
	return ok and result or nil
end

local function FrameOf(spec)
	local frame = Read(spec.frame)
	return type(frame) == "table" and frame.SetPoint and frame or nil
end

local function SpotName(spec) return spec.spot or ("place:" .. spec.key) end

-- The place chosen by this character: { point, relPoint, x, y }, or nil.
local function Saved(spec)
	local saved
	if spec.load then
		saved = Read(spec.load)
	elseif ns.root then
		saved = ns.Spots()[SpotName(spec)]
	end
	if type(saved) ~= "table" or not FACTORS[saved[1]] then return nil end
	return { saved[1], saved[1], tonumber(saved[2]) or 0, tonumber(saved[3]) or 0 }
end

-- Its place by default: { point, relPoint, x, y } ({ point, x, y } taken too).
local function Default(spec)
	local spot = Read(spec.default)
	if type(spot) ~= "table" or not FACTORS[spot[1]] then return { "CENTER", "CENTER", 0, 0 } end
	if type(spot[2]) ~= "string" then return { spot[1], spot[1], tonumber(spot[2]) or 0, tonumber(spot[3]) or 0 } end
	return { spot[1], FACTORS[spot[2]] and spot[2] or spot[1], tonumber(spot[3]) or 0, tonumber(spot[4]) or 0 }
end

local function Spot(spec) return Saved(spec) or Default(spec) end

local function Write(spec, spot)
	if spec.save then
		pcall(spec.save, spot)
	elseif ns.root then
		ns.Spots()[SpotName(spec)] = spot
	end
end

-- A piece in its place (the frame given, else its own). False: not known, or nothing to place.
function ns.PlaceApply(key, frame)
	local spec = registry[key]
	frame = frame or (spec and FrameOf(spec))
	if not (spec and frame) then return false end
	-- (never a protected frame in a fight)
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return false end
	local spot = Spot(spec)
	frame:ClearAllPoints()
	frame:SetPoint(spot[1], UIParent, spot[2], spot[3], spot[4])
	return true
end

-- Its place now: point, relPoint, x, y (the frame's own units), and whether it was chosen.
function ns.PlaceSpot(key)
	local spec = registry[key]
	if not spec then return nil end
	local saved = Saved(spec)
	local spot = saved or Default(spec)
	return spot[1], spot[2], spot[3], spot[4], saved ~= nil
end

-- The pieces known, in the order they came: { key, label }.
function ns.Placeables()
	local list = {}
	for _, key in ipairs(order) do list[#list + 1] = { key = key, label = Read(registry[key].label) or key } end
	return list
end

local function Enabled(spec)
	if spec.enabled == nil then return true end
	return Read(spec.enabled) and true or false
end

-- Its size and scale on the screen (the screen's units): width, height, scale, and whether it is seen now.
local function Geometry(spec)
	local frame = FrameOf(spec)
	local uiScale = UIParent:GetEffectiveScale() or 1
	local scale = tonumber(Read(spec.scale))
	if not scale and frame then scale = (frame:GetEffectiveScale() or uiScale) / (uiScale > 0 and uiScale or 1) end
	if not scale or scale <= 0 then scale = 1 end
	local width, height
	if frame and spec.live ~= false then width, height = frame:GetWidth(), frame:GetHeight() end
	if not (width and height and width > 4 and height > 4) then
		local size = Read(spec.size) or FALLBACK_SIZE
		width, height = size[1] or FALLBACK_SIZE[1], size[2] or FALLBACK_SIZE[2]
	end
	local seen = frame and spec.live ~= false and frame:IsVisible() and (frame:GetAlpha() or 0) > 0.05 or false
	return width * scale, height * scale, scale, seen and true or false
end

-- The mode ----------------------------------------------------------------------------------------------------

local function Guide(index, vertical)
	local guide = guides[index]
	if not guide then
		guide = mode:CreateTexture(nil, "OVERLAY")
		local gold = ns.Skin.COLORS.gold
		guide:SetColorTexture(gold[1], gold[2], gold[3], GUIDE_ALPHA)
		guides[index] = guide
	end
	guide:ClearAllPoints()
	if vertical then guide:SetWidth(1) else guide:SetHeight(1) end
	return guide
end

local function HideGuides()
	for _, guide in ipairs(guides) do guide:Hide() end
end

-- The proxy put at left, bottom (the screen's units).
local function Put(proxy, left, bottom)
	proxy.left, proxy.bottom = left, bottom
	proxy:ClearAllPoints()
	proxy:SetPoint("BOTTOMLEFT", mode, "BOTTOMLEFT", left, bottom)
end

-- Where a piece's place puts its proxy: left, bottom.
local function ProxyCorner(spot, width, height, scale)
	local screenWidth, screenHeight = Screen()
	local own, other = FACTORS[spot[1]], FACTORS[spot[2]]
	local x = other[1] * screenWidth + spot[3] * scale
	local y = other[2] * screenHeight + spot[4] * scale
	return x - own[1] * width, y - own[2] * height
end

local function Lay(proxy)
	local spec = registry[proxy.key]
	local width, height, scale, seen = Geometry(spec)
	proxy.width, proxy.height, proxy.scale = width, height, scale
	proxy:SetSize(width, height)
	proxy.ground:SetColorTexture(0.02, 0.02, 0.03, seen and 0.35 or 0.72)
	proxy.name:SetText(Read(spec.label) or spec.key)
	proxy.note:SetText(seen and "" or L.PLACING_HIDDEN)
	proxy.note:SetShown(not seen and height >= 34)
	Put(proxy, ProxyCorner(Spot(spec), width, height, scale))
end

-- Held to the nearest line within reach: the screen's edges and middle, the other pieces' edges and middles.
-- Returns left, bottom and the lines held to (x, y; nil: none, or an edge of the screen).
local function Snap(proxy, left, bottom)
	local screenWidth, screenHeight = Screen()
	local width, height = proxy.width, proxy.height
	left = math.max(0, math.min(left, screenWidth - width))
	bottom = math.max(0, math.min(bottom, screenHeight - height))
	local xs, ys = { 0, screenWidth / 2, screenWidth }, { 0, screenHeight / 2, screenHeight }
	for _, other in ipairs(proxies) do
		if other ~= proxy and other:IsShown() and other.left then
			for _, share in ipairs({ 0, 0.5, 1 }) do
				xs[#xs + 1] = other.left + share * other.width
				ys[#ys + 1] = other.bottom + share * other.height
			end
		end
	end
	local function Best(start, size, lines)
		local found, shift
		for _, line in ipairs(lines) do
			for _, share in ipairs({ 0, 0.5, 1 }) do
				local delta = line - (start + share * size)
				if math.abs(delta) <= SNAP and (not shift or math.abs(delta) < math.abs(shift)) then found, shift = line, delta end
			end
		end
		return found, shift or 0
	end
	local lineX, shiftX = Best(left, width, xs)
	local lineY, shiftY = Best(bottom, height, ys)
	left, bottom = left + shiftX, bottom + shiftY
	if lineX == 0 or lineX == screenWidth then lineX = nil end
	if lineY == 0 or lineY == screenHeight then lineY = nil end
	return left, bottom, lineX, lineY
end

local function ShowGuides(lineX, lineY)
	HideGuides()
	if lineX then
		local guide = Guide(1, true)
		guide:SetPoint("TOP", mode, "TOPLEFT", lineX, 0)
		guide:SetPoint("BOTTOM", mode, "BOTTOMLEFT", lineX, 0)
		guide:Show()
	end
	if lineY then
		local guide = Guide(2, false)
		guide:SetPoint("LEFT", mode, "BOTTOMLEFT", 0, lineY)
		guide:SetPoint("RIGHT", mode, "BOTTOMRIGHT", 0, lineY)
		guide:Show()
	end
end

-- The piece itself where it is now, and whoever owns it told.
local function Apply(spec)
	ns.PlaceApply(spec.key)
	if spec.onMoved then
		local spot = Spot(spec)
		pcall(spec.onMoved, spot[1], spot[3], spot[4])
	end
end

-- The proxy's place kept: against the same point of the screen as before (a piece growing from its top
-- still grows from it), in the piece's own units.
local function Commit(proxy)
	local spec = registry[proxy.key]
	local point = Spot(spec)[1]
	local factor = FACTORS[point]
	local screenWidth, screenHeight = Screen()
	local x = (proxy.left + factor[1] * proxy.width - factor[1] * screenWidth) / proxy.scale
	local y = (proxy.bottom + factor[2] * proxy.height - factor[2] * screenHeight) / proxy.scale
	Write(spec, { point, Round(x), Round(y) })
	Apply(spec)
	Lay(proxy)
end

local function ResetOne(key)
	local spec = registry[key]
	if not spec then return end
	Write(spec, nil)
	if spec.reset then pcall(spec.reset) end
	Apply(spec)
	for _, proxy in ipairs(proxies) do
		if proxy.key == key and proxy:IsShown() then Lay(proxy) end
	end
end

local function Cursor()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale() or 1
	if scale <= 0 then scale = 1 end
	return (x or 0) / scale, (y or 0) / scale
end

local function OnUpdate()
	if not dragging then return end
	local x, y = Cursor()
	if not dragging.moved and math.abs(x - dragging.x) < MOVE_FROM and math.abs(y - dragging.y) < MOVE_FROM then return end
	dragging.moved = true
	local proxy = dragging.proxy
	local left, bottom, lineX, lineY = Snap(proxy, x - dragging.dx, y - dragging.dy)
	Put(proxy, left, bottom)
	ShowGuides(lineX, lineY)
end

local function Hover(proxy, on)
	local gold = ns.Skin.COLORS.gold
	proxy.edges.Color(gold[1], gold[2], gold[3], on and 1 or 0.7)
end

local function Proxy()
	local proxy = CreateFrame("Button", nil, mode)
	proxy:SetFrameLevel((mode:GetFrameLevel() or 1) + 5)
	proxy.ground = proxy:CreateTexture(nil, "BACKGROUND")
	proxy.ground:SetAllPoints()
	proxy.edges = ns.Skin.Edges(proxy)
	Hover(proxy, false)
	proxy.name = ns.Skin.Text(proxy, "GameFontNormal", "gold")
	proxy.name:SetPoint("CENTER", proxy, "CENTER", 0, 0)
	if proxy.name.SetWordWrap then proxy.name:SetWordWrap(false) end
	proxy.note = ns.Skin.Text(proxy, "GameFontHighlightSmall", "muted")
	proxy.note:SetPoint("TOP", proxy.name, "BOTTOM", 0, -2)
	proxy:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	proxy:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local x, y = Cursor()
		dragging = { proxy = self, dx = x - (self.left or 0), dy = y - (self.bottom or 0), x = x, y = y }
	end)
	proxy:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			ns.Skin.Play("click")
			ResetOne(self.key)
			return
		end
		local was = dragging
		dragging = nil
		HideGuides()
		if was and was.proxy == self and was.moved then Commit(self) end
	end)
	proxy:SetScript("OnEnter", function(self)
		Hover(self, true)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self.name:GetText() or "", ns.Skin.COLORS.gold[1], ns.Skin.COLORS.gold[2], ns.Skin.COLORS.gold[3])
		GameTooltip:AddLine(L.PLACING_PIECE_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	proxy:SetScript("OnLeave", function(self)
		Hover(self, false)
		GameTooltip:Hide()
	end)
	return proxy
end

-- Every piece offered now, a proxy each.
local function LayAll()
	local used = 0
	for _, key in ipairs(order) do
		local spec = registry[key]
		if Enabled(spec) then
			used = used + 1
			proxies[used] = proxies[used] or Proxy()
			local proxy = proxies[used]
			proxy.key = key
			proxy:Show()
			Lay(proxy)
		end
	end
	for index = used + 1, #proxies do proxies[index]:Hide() end
	return used
end

local function Leave()
	if not (mode and mode:IsShown()) then return end
	dragging = nil
	HideGuides()
	mode:Hide()
	if panel:IsShown() then panel:Hide() end
	ns.Skin.Play("close")
end

-- Every piece back, asked first (the question over the placing mode's layers, so it is seen and answered).
local function ResetAll()
	ns.Skin.Ask(L.PLACING_RESET_ASK, function()
		for _, key in ipairs(order) do ResetOne(key) end
	end, nil, { strata = "TOOLTIP" })
end

local function Build()
	mode = CreateFrame("Frame", "WandererPlacing", UIParent)
	mode:SetAllPoints(UIParent)
	mode:SetFrameStrata("FULLSCREEN")
	if mode.SetIgnoreParentAlpha then mode:SetIgnoreParentAlpha(true) end
	mode:Hide()
	local veil = mode:CreateTexture(nil, "BACKGROUND")
	veil:SetAllPoints()
	veil:SetColorTexture(0, 0, 0, VEIL_ALPHA)
	-- The screen's middle, faint: the lines a piece is most often lined up with.
	local gold = ns.Skin.COLORS.gold
	local across = mode:CreateTexture(nil, "BORDER")
	across:SetColorTexture(gold[1], gold[2], gold[3], CENTER_ALPHA)
	across:SetHeight(1)
	across:SetPoint("LEFT", mode, "LEFT", 0, 0)
	across:SetPoint("RIGHT", mode, "RIGHT", 0, 0)
	local down = mode:CreateTexture(nil, "BORDER")
	down:SetColorTexture(gold[1], gold[2], gold[3], CENTER_ALPHA)
	down:SetWidth(1)
	down:SetPoint("TOP", mode, "TOP", 0, 0)
	down:SetPoint("BOTTOM", mode, "BOTTOM", 0, 0)
	mode:SetScript("OnUpdate", OnUpdate)
	mode:RegisterEvent("PLAYER_REGEN_DISABLED")
	mode:SetScript("OnEvent", Leave)

	panel = ns.Skin.CreateWindow("WandererPlacingPanel", "FULLSCREEN_DIALOG")
	local cross = ns.Skin.Dress(panel, { "CENTER", UIParent, "CENTER", 0, -20 }, nil, Leave)
	local kicker, title, margin = ns.Skin.Header(panel, nil, L.PLACING_TITLE)
	local hint = ns.Skin.Text(panel, "GameTooltipText", "soft")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	hint:SetWidth(300)
	hint:SetJustifyH("LEFT")
	hint:SetText(L.PLACING_HINT)
	local done = ns.Skin.Button(panel, L.PLACING_DONE, Leave, "main", 110)
	resetAll = ns.Skin.SmallButton(panel, L.PLACING_RESET_ALL, ResetAll)
	done:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -margin, margin)
	resetAll:SetPoint("RIGHT", done, "LEFT", -10, 0)
	local hintHeight = ns.Util.Measure(hint, "GetStringHeight", 30)
	local top = ns.Util.Measure(kicker, "GetStringHeight", 10) + 3 + ns.Util.Measure(title, "GetStringHeight", 16)
	panel:SetSize(300 + margin * 2, margin + top + 8 + hintHeight + 16 + 36 + margin)
	panel.cross = cross
	panel.wandererSounds = true -- (the mode's own sound on leaving, once)
	-- (Escape and the cross close the panel: the mode with it)
	panel:HookScript("OnHide", Leave)
	ns.Skin.Get(panel):Layout()
end

-- The mode, out of a fight.
function ns.PlaceMode()
	if InCombatLockdown() then
		ns.Print(L.PLACING_COMBAT)
		return false
	end
	if not mode then Build() end
	if mode:IsShown() then return true end
	-- (the settings closed: the screen seen whole)
	if ns.CloseSettings then ns.CloseSettings() end
	mode:Show()
	if LayAll() == 0 then
		mode:Hide()
		ns.Print(L.PLACING_NOTHING)
		return false
	end
	panel:Show()
	ns.Skin.Play("open")
	return true
end

function ns.PlacingActive() return mode ~= nil and mode:IsShown() end
ns.LeavePlaceMode = Leave

-- A piece registered (again: its spec replaced). True when taken.
function ns.Placeable(spec)
	if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then return false end
	if not registry[spec.key] then order[#order + 1] = spec.key end
	registry[spec.key] = spec
	if ns.PlacingActive() then LayAll() end
	return true
end

-- (tests: a proxy by its piece, a drag from a point to another)
function ns.PlaceProxy(key)
	for _, proxy in ipairs(proxies) do
		if proxy.key == key and proxy:IsShown() then return proxy end
	end
end
ns.PlaceSnap = Snap

-- The core's own pieces ------------------------------------------------------------------------------------------
-- (the notices: one frame for both, placed by Toast.lua as each one shows; their size here, as a frame shows
-- none of a notice not shown)

ns.Placeable({
	key = "toastTop", label = function() return L.PLACING_TOAST_TOP end, size = { 320, 64 }, live = false,
	scale = function() return ns.db and ns.Skin.Scale() or 1 end,
	default = { "TOP", "TOP", 0, -120 },
})
ns.Placeable({
	key = "toastCorner", label = function() return L.PLACING_TOAST_CORNER end, size = { 300, 64 }, live = false,
	scale = function() return ns.db and ns.Skin.Scale() or 1 end,
	default = { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 160 },
})

-- For the extensions (Wanderer's API): a piece of theirs registered, put in its place, the mode opened.
if _G.Wanderer then
	_G.Wanderer.Placeable = function(spec) return ns.Placeable(spec) end
	_G.Wanderer.PlaceApply = function(key, frame) return ns.PlaceApply(key, frame) end
	_G.Wanderer.PlaceMode = function() return ns.PlaceMode() end
end
