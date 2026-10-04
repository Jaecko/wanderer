local _, ns = ...
local L = ns.L

-- Addon icons: the other addons' buttons around the minimap go into one
-- drawer, in Wanderer's look, opened from Wanderer's menu. The buttons
-- themselves move (their clicks, right clicks and tooltips work as before);
-- switched off, each one goes back exactly where it was. Never during a
-- fight, and never a protected button.

local CELL, GAP, COLUMNS = 34, 4, 4
local RESCAN_DELAYS = { 2, 6, 15, 30 } -- addons make their buttons late
local CLOSE_AFTER = 1.5 -- seconds without the mouse over the drawer
-- The game's own buttons and Wanderer's stay where they are.
local KEEP_PREFIXES = { "Minimap", "MiniMap", "GameTime", "TimeManager", "QueueStatus", "Expansion",
	"AddonCompartment", "GarrisonLandingPage", "Wanderer", "LFG", "Calendar",
	"WIM" } -- WIM animates its windows toward its button: left where it is

-- Region methods, called directly: the gathered buttons' own are muted.
local SetPoint, ClearAllPoints = UIParent.SetPoint, UIParent.ClearAllPoints
local function Mute() end

local drawer, kicker, empty
local saved = {} -- button -> { parent, points, setPoint, clear, level }
local order = {} -- gathered buttons, by name
local outside = 0

local function Kept(name)
	for _, prefix in ipairs(KEEP_PREFIXES) do
		if name:sub(1, #prefix) == prefix then return true end
	end
	return false
end

-- The buttons of other addons around the minimap.
local function Candidates()
	local list = {}
	for _, holder in ipairs({ Minimap, _G.MinimapBackdrop, MinimapCluster }) do
		if holder and holder.GetChildren then
			for _, child in ipairs({ holder:GetChildren() }) do
				local name = child.GetName and ns.Util.Clean(ns.Util.Safe(child.GetName, child))
				if name and not saved[child] and not Kept(name) and child.IsObjectType and child:IsObjectType("Button")
					and child:IsShown() and not child:IsProtected() then
					list[#list + 1] = child
				end
			end
		end
	end
	return list
end

local function Layout()
	table.sort(order, function(a, b) return (ns.Util.Clean(a:GetName()) or "") < (ns.Util.Clean(b:GetName()) or "") end)
	local margin = ns.Skin.Margin() + 6
	for index, button in ipairs(order) do
		local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
		ClearAllPoints(button)
		SetPoint(button, "CENTER", drawer, "TOPLEFT", margin + CELL / 2 + column * (CELL + GAP),
			-(margin + 18 + CELL / 2 + row * (CELL + GAP)))
	end
	local rows = math.max(1, math.ceil(#order / COLUMNS))
	local columns = math.max(1, math.min(#order, COLUMNS))
	drawer:SetSize(math.max(margin * 2 + columns * CELL + (columns - 1) * GAP, 120),
		margin * 2 + 18 + rows * CELL + (rows - 1) * GAP)
	empty:SetShown(not order[1])
	ns.Skin.Get(drawer):Layout()
end

local function Gather(button)
	local points = {}
	for index = 1, (button:GetNumPoints() or 0) do points[index] = { button:GetPoint(index) } end
	saved[button] = { parent = button:GetParent(), points = points, level = button:GetFrameLevel(),
		setPoint = rawget(button, "SetPoint"), clear = rawget(button, "ClearAllPoints") }
	button:SetParent(drawer)
	button:SetFrameLevel(drawer:GetFrameLevel() + 5)
	-- The addon may place its button again (dragging, minimap shape): not here.
	button.SetPoint, button.ClearAllPoints = Mute, Mute
	order[#order + 1] = button
end

local function Release(button)
	local was = saved[button]
	button.SetPoint, button.ClearAllPoints = was.setPoint, was.clear
	button:SetParent(was.parent)
	button:SetFrameLevel(was.level or 1)
	ClearAllPoints(button)
	for _, point in ipairs(was.points) do SetPoint(button, unpack(point)) end
	saved[button] = nil
end

-- Looks for new buttons (and keeps the drawer in order).
function ns.GatherIcons()
	if not drawer or InCombatLockdown() then return end
	if not (ns.db.enabled and ns.db.world.gatherIcons) then return end
	for _, button in ipairs(Candidates()) do Gather(button) end
	Layout()
end

function ns.CountIcons() return #order end

function ns.ToggleIconDrawer(owner)
	if not drawer then return end
	if drawer:IsShown() then drawer:Hide() return end
	ns.GatherIcons()
	drawer:ClearAllPoints()
	local anchor = owner or MinimapCluster or UIParent
	drawer:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
	drawer:SetScale(ns.Skin.Scale())
	outside = 0
	drawer:Show()
end

function ns.RefreshIcons()
	if not drawer or InCombatLockdown() then return end
	if ns.db.enabled and ns.db.world.gatherIcons then
		ns.GatherIcons()
	else
		for button in pairs(saved) do Release(button) end
		wipe(order)
		drawer:Hide()
	end
end

function ns.InitIcons()
	drawer = ns.Skin.CreateWindow("WandererIconDrawer", "DIALOG")
	drawer:SetPoint("TOPRIGHT", MinimapCluster or UIParent, "TOPLEFT", -6, 0)
	drawer:SetSize(120, 60)
	drawer:EnableMouse(true)
	drawer:SetClampedToScreen(true)
	kicker = ns.Skin.CreateText(drawer, "GameTooltipTextSmall", 0.85, 0.75, 0.5)
	kicker:SetPoint("TOPLEFT", drawer, "TOPLEFT", ns.Skin.Margin() + 6, -(ns.Skin.Margin() + 4))
	kicker:SetText(L.ICONS_TITLE:upper())
	empty = ns.Skin.CreateText(drawer, "GameTooltipTextSmall", 0.6, 0.6, 0.6)
	empty:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -8)
	empty:SetText(L.ICONS_EMPTY)
	if UISpecialFrames then table.insert(UISpecialFrames, "WandererIconDrawer") end
	-- Closes by itself once the mouse has left it a moment.
	drawer:SetScript("OnUpdate", function(self, elapsed)
		if ns.Util.IsMouseOver(self) then
			outside = 0
		else
			outside = outside + elapsed
			if outside > CLOSE_AFTER then self:Hide() end
		end
	end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			drawer:Hide()
		elseif event == "PLAYER_ENTERING_WORLD" then
			for _, delay in ipairs(RESCAN_DELAYS) do C_Timer.After(delay, ns.GatherIcons) end
		else
			ns.GatherIcons()
		end
	end)
end
