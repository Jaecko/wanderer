local _, ns = ...

-- The game's windows (map, character, bags, spells, merchants, mail...) can
-- be moved (option): the title bar drags a window anywhere, and it opens
-- there every time. Nothing else changes: they look as the game draws them,
-- nothing is added. The full screen map stays where the game puts it, and
-- windows without the game's title bar are left alone. A window already
-- open stays where it is when another opens or closes (the game would push
-- it aside, under the one you moved): every window, with a title bar or not, known by name or not. Switched off, every window goes back
-- where the game puts it. Every window is on the map's layer (Skin.Front): the one opened or clicked last
-- in front, the map as much as the others (Skin.Front), whatever the game names them: a window opened as
-- it pleases the game is found as it appears, a click on any of them brings it in front.

local U = ns.Util
local Safe = U.Safe

-- The windows, by name (many are loaded by the game only when first opened).
local WINDOWS = { "WorldMapFrame", "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "ProfessionsBookFrame",
	"CollectionsJournal", "PVEFrame", "FriendsFrame", "CommunitiesFrame", "EncounterJournal", "MerchantFrame",
	"MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame", "TradeFrame", "ClassTrainerFrame", "ProfessionsFrame",
	"AuctionHouseFrame", "ContainerFrameCombinedBags", "DressUpFrame", "ItemTextFrame", "QuestLogPopupDetailFrame",
	"InspectFrame", "MacroFrame", "AddonList", "WardrobeFrame", "ItemSocketingFrame", "ItemUpgradeFrame",
	"ProfessionsCustomerOrdersFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "TaxiFrame",
	"GossipFrame", "QuestFrame", "TradeSkillFrame", "CraftFrame", "QuestLogFrame", "TalentFrame",
	"PlayerTalentFrame", "LootFrame", "PetStableFrame", "KeyBindingFrame", "HelpFrame", "LFGParentFrame", "WorldStateScoreFrame" }

local taken = {} -- window -> true
local held = {} -- window -> its points, while it stays open
local moving

local function On()
	return ns.db and ns.db.enabled and ns.db.world.moveFrames and true or false
end

local function Points()
	ns.db.world.framePoints = ns.db.world.framePoints or {}
	return ns.db.world.framePoints
end

-- The full screen map stays the game's.
local function Movable(window)
	if not On() or U.IsOffScreen(window) then return false end
	if window.IsMaximized and Safe(window.IsMaximized, window) then return false end
	-- Never tried where the game forbids it.
	return not (InCombatLockdown() and window.IsProtected and Safe(window.IsProtected, window))
end

local function Place(window)
	local saved = ns.db and Points()[window:GetName() or ""]
	if not (saved and window:IsShown() and Movable(window)) then return end
	window:ClearAllPoints()
	window:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
end

-- Where a window stands now (to keep it there).
local function Hold(window)
	local points = {}
	for index = 1, window:GetNumPoints() do points[index] = { window:GetPoint(index) } end
	held[window] = points[1] and points or nil
end

local function PutBack(window)
	local points = held[window]
	if not points then return end
	window:ClearAllPoints()
	for _, point in ipairs(points) do window:SetPoint(point[1], point[2], point[3], point[4], point[5]) end
end

-- After the game has placed its windows (one opened or closed: current): each moved one goes back to its
-- own place, each one already open stays where it was (the one just opened takes the place the game gave
-- it); where they stand is kept for the next time.
local function PlaceAll(current)
	if not On() then return end
	for window in pairs(taken) do
		if window:IsShown() and Movable(window) then
			if Points()[window:GetName() or ""] then
				Place(window)
			elseif window ~= current then
				PutBack(window)
			end
			Hold(window)
		end
	end
end

local function Remember(window)
	local point, _, _, x, y = window:GetPoint(1)
	if point and x and y then Points()[window:GetName()] = { point, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

-- A window followed: kept where it stands while it is open (the game would push it aside when another
-- opens), every one of them; dragged by its title bar when it has the game's (else it stays where the game
-- opens it).
local function Take(window)
	if taken[window] or not (window.HookScript and window.GetNumPoints) then return end
	taken[window] = true
	window:HookScript("OnShow", function() Place(window) end)
	-- Closed: it opens next time where the game (or you) put it.
	window:HookScript("OnHide", function() held[window] = nil end)
	if window:IsShown() and not held[window] then Hold(window) end
	-- The map's title bar is on a frame of its own.
	local chrome = type(window.BorderFrame) == "table" and window.BorderFrame or window
	local handle = chrome.TitleContainer
	if not (type(handle) == "table" and handle.RegisterForDrag) then return end -- no title bar: not dragged
	if handle.EnableMouse then handle:EnableMouse(true) end
	handle:RegisterForDrag("LeftButton")
	handle:HookScript("OnDragStart", function()
		if not Movable(window) then return end
		window:SetMovable(true)
		window:SetClampedToScreen(true)
		window:StartMoving()
		moving = window
	end)
	handle:HookScript("OnDragStop", function()
		if moving ~= window then return end
		moving = nil
		window:StopMovingOrSizing()
		if window.SetUserPlaced then window:SetUserPlaced(false) end -- the place is Wanderer's to keep
		Remember(window)
		Hold(window)
	end)
end

local function TakeAll()
	for _, name in ipairs(WINDOWS) do
		local window = _G[name]
		if type(window) == "table" and window.GetObjectType then Take(window) end
	end
end

-- A window of the game's open on the screen: a named panel with its close button or its title (not the
-- action bars, the chat, the portraits...).
local function IsWindow(frame)
	if frame == _G.WorldMapFrame or not (frame.IsShown and frame:IsShown()) then return false end
	if ns.Skin.Managed(frame) then return true end
	local name = frame.GetName and U.Clean(Safe(frame.GetName, frame))
	if not name then return false end
	if UIPanelWindows and UIPanelWindows[name] then return true end
	return type(frame.CloseButton) == "table" or type(frame.TitleContainer) == "table" or type(frame.TitleText) == "table"
end

-- While the map is open: a window that appears beside it, whatever its name, comes in front as it opens.
local watch
local open = setmetatable({}, { __mode = "k" }) -- windows open at the last look
-- (quiet: only noted, the windows already open when the map opens stay behind it)
local function Beside(quiet)
	if not (UIParent and UIParent.GetChildren) then return end
	local now = {}
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if IsWindow(frame) then
			now[frame] = true
			if On() then Take(frame) end
			if not (quiet or open[frame]) then ns.Skin.Front(frame) end
		end
	end
	wipe(open)
	for frame in pairs(now) do open[frame] = true end
end

-- The window under a click: the map, or a window of the screen (climbing from the piece clicked).
local function Clicked()
	local frame = U.MouseFocus()
	local map = _G.WorldMapFrame
	for _ = 1, 30 do
		if not frame then return nil end
		if frame == map or (frame.GetParent and frame:GetParent() == UIParent and IsWindow(frame)) then return frame end
		frame = frame.GetParent and frame:GetParent() or nil
	end
end

-- Each of the list in front as it opens (the others: as the game opens them, below); the map watched while
-- it is open.
local layered = {}
local function LayerAll()
	for _, name in ipairs(WINDOWS) do
		local window = _G[name]
		if type(window) == "table" and window.HookScript and not layered[window] then
			layered[window] = true
			window:HookScript("OnShow", function(self) ns.Skin.Front(self) end)
			if name == "WorldMapFrame" then
				window:HookScript("OnShow", function()
					Beside(true)
					if watch then watch:Cancel() end
					watch = C_Timer.NewTicker and C_Timer.NewTicker(1, function() Beside() end) or nil
				end)
				window:HookScript("OnHide", function()
					if watch then watch:Cancel() end
					watch = nil
				end)
			end
		end
	end
end

local waiting = false -- turned off during a fight: done after it

function ns.RefreshGameFrames()
	waiting = false
	if On() then
		TakeAll()
		PlaceAll()
	elseif InCombatLockdown() then
		waiting = true
	else
		-- Back where the game puts them: the windows when they open next, the bags now.
		if UpdateContainerFrameAnchors then pcall(UpdateContainerFrameAnchors) end
	end
end

function ns.InitGameFrames()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(events.RegisterEvent, events, "GLOBAL_MOUSE_DOWN")
	events:SetScript("OnEvent", function(_, event)
		if event == "GLOBAL_MOUSE_DOWN" then
			-- (a click on a window, or on the map: in front)
			local window = Clicked()
			if window and window ~= ns.Skin.InFront() then ns.Skin.Front(window) end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if waiting then ns.RefreshGameFrames() end
			return
		end
		LayerAll()
		if On() then TakeAll() end
	end)
	-- Any window the game opens as a panel (not only those of the list): followed too, kept where it stands
	-- (heard before the placing below: its place is known when the next one opens), and in front.
	if ShowUIPanel then
		hooksecurefunc("ShowUIPanel", function(window)
			if type(window) ~= "table" then return end
			if On() then Take(window) end
			ns.Skin.Front(window)
		end)
	end
	-- The game places its windows (and the bags) when one opens or closes (its placing is its own: what
	-- opens and closes them is what can be heard).
	for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
		if _G[name] then hooksecurefunc(name, PlaceAll) end
	end
	LayerAll()
	if UpdateContainerFrameAnchors then hooksecurefunc("UpdateContainerFrameAnchors", PlaceAll) end
	ns.RefreshGameFrames()
end
