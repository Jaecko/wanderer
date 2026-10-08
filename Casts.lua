local _, ns = ...

-- A line of the label for a spell being cast or channelled: its icon, its
-- name and a thin bar for its progress, in the game's colors. Protected
-- values (in a fight, in instances) are shown as they are, never looked into.
-- One for the character described, one for whoever it looks at (Label.lua).

local U = ns.Util
local Safe, Clean, IsSecret, Measure = U.Safe, U.Clean, U.IsSecret, U.Measure

local ICON = 14
local BAR_HEIGHT = 3
local GAP = 2 -- between the name and the bar, as between the label's lines
local FALLBACK_WIDTH = 160
local COLORS = { cast = { 1, 0.7, 0 }, channel = { 0, 1, 0 }, locked = { 0.7, 0.7, 0.7 } } -- as the game's cast bars

local Cast = {}
Cast.__index = Cast

-- The bar moves with the clock (each frame).
function Cast:Tick()
	if not (self.active and self.timed) then return end
	local now = GetTime() * 1000
	if self.start then
		local share = math.min(math.max((now - self.start) / (self.finish - self.start), 0), 1)
		self.bar:SetValue(self.channel and 1 - share or share)
	else
		-- Protected times: the bar takes them as they are, and the clock.
		pcall(self.bar.SetValue, self.bar, now)
	end
end

-- What the unit casts or channels right now (never yours: your own bar says it).
function Cast:Read(unit, enabled)
	self.active = false
	if not enabled or Clean(Safe(UnitIsUnit, unit, "player")) then return false end
	local channel = false
	local name, _, texture, start, finish, _, _, locked = Safe(UnitCastingInfo, unit)
	if not IsSecret(name) and name == nil then
		name, _, texture, start, finish, _, locked = Safe(UnitChannelInfo, unit)
		channel = true
	end
	if not IsSecret(name) and name == nil then return false end
	if not pcall(self.text.SetText, self.text, name) then return false end
	self.icon.wanted = (IsSecret(texture) or texture ~= nil) and pcall(self.icon.SetTexture, self.icon, texture) or false
	local color = Clean(locked) and COLORS.locked or (channel and COLORS.channel or COLORS.cast)
	self.bar:SetStatusBarColor(color[1], color[2], color[3])
	self.channel = channel
	if IsSecret(start) or IsSecret(finish) then
		self.start, self.finish = nil, nil
		self.timed = pcall(self.bar.SetMinMaxValues, self.bar, start, finish)
	else
		self.start, self.finish = Clean(start), Clean(finish)
		self.timed = self.start ~= nil and self.finish ~= nil and self.finish > self.start
		self.bar:SetMinMaxValues(0, 1)
	end
	self.active = true
	self:Tick()
	return true
end

-- Shown or hidden; its size (icon and name, the bar under them).
-- widthOf: how the label measures a text.
function Cast:Size(widthOf)
	local shown = self.active and true or false
	self.text:SetShown(shown)
	self.icon:SetShown(shown and self.icon.wanted or false)
	self.bar:SetShown(shown and self.timed or false)
	if not shown then return 0, 0 end
	local iconSpace = self.icon.wanted and ICON + 4 or 0
	local width = iconSpace + widthOf(self.text, FALLBACK_WIDTH)
	local height = math.max(self.icon.wanted and ICON or 0, Measure(self.text, "GetStringHeight", 10))
	if self.timed then height = height + GAP + BAR_HEIGHT end
	return width, height
end

-- Under anchor, from its left edge, as wide as the label. Returns the part
-- the next one goes under.
function Cast:Place(anchor, x, gap)
	local height = self.icon.wanted and ICON or 0
	self.icon:ClearAllPoints()
	self.icon:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -gap)
	self.text:ClearAllPoints()
	if self.icon.wanted then
		self.text:SetPoint("LEFT", self.icon, "RIGHT", 4, 0)
	else
		self.text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -gap)
	end
	height = math.max(height, Measure(self.text, "GetStringHeight", 10))
	self.bar:ClearAllPoints()
	self.bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -(gap + height + GAP))
	self.bar:SetPoint("RIGHT", self.frame, "RIGHT", -ns.Skin.Margin(), 0)
	return self.timed and self.bar or (self.icon.wanted and self.icon or self.text)
end

ns.Casts = {}

function ns.Casts.New(frame)
	local self = setmetatable({ active = false, frame = frame }, Cast)
	self.icon = frame:CreateTexture(nil, "ARTWORK")
	self.icon:SetSize(ICON, ICON)
	self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	self.text = ns.Skin.CreateText(frame, "GameTooltipTextSmall", 1, 1, 1)
	self.bar = CreateFrame("StatusBar", nil, frame)
	self.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	self.bar:SetHeight(BAR_HEIGHT)
	local background = self.bar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.6)
	self.icon:Hide()
	self.text:Hide()
	self.bar:Hide()
	return self
end
