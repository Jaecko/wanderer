local _, ns = ...

-- The game's windows (map, character, bags, spells, merchants, mail...) can
-- be moved (option): the title bar drags a window anywhere, and it opens
-- there every time. Nothing else changes: they look as the game draws them,
-- nothing is added. The full screen map stays where the game puts it, and
-- windows without the game's title bar are not dragged. A window already
-- open stays where it is when another opens or closes (the game would push
-- it aside), with a title bar or not, known by name or not. Switched off,
-- they go back where the game puts them when they open next.
--
-- Every window shares the map's layer (Skin.Front), the option on or off:
-- the one opened or clicked last is in front, the map like the others,
-- whatever the game names them (a window is found as it appears). The
-- game's placing is only heard once the option is on.
--
-- Another addon that places and sizes the map itself (Compat.lua, "mapSize")
-- keeps it: the map is then neither dragged nor placed here.

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

-- Where you put them, this character's.
local function Points()
	local root = ns.root or ns.db
	local mine = ns.root and ns.Mine() or root
	if not mine.framePoints then
		mine.framePoints = {}
		-- (kept in the profile before: this character's own only, the others' left to them)
		if ns.db and ns.db.world and type(ns.db.world.framePoints) == "table" then
			for name, point in pairs(ns.db.world.framePoints) do mine.framePoints[name] = mine.framePoints[name] or point end
			ns.db.world.framePoints = nil
		end
	end
	return mine.framePoints
end

-- The full screen map stays the game's.
local function MapLeftToOther(window)
	return window == _G.WorldMapFrame and ns.Yields("mapSize") ~= nil
end

local function Movable(window)
	if not On() or U.IsOffScreen(window) or MapLeftToOther(window) then return false end
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
	local name = window:GetName()
	if name and point and x and y then Points()[name] = { point, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

-- A window followed: kept where it stands while it is open (the game would push it aside when another
-- opens), every one of them; dragged by its title bar when it has the game's (else it stays where the game
-- opens it).
local function Take(window)
	if taken[window] or not (window.HookScript and window.GetNumPoints) or MapLeftToOther(window) then return end
	taken[window] = true
	-- Opening again: where it stood before is forgotten, it opens where the game (or you) put it. (Never a hook
	-- on the hiding of a game's window: the controller interface hooks it too, and does protected work there.)
	window:HookScript("OnShow", function()
		held[window] = nil
		Place(window)
	end)
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
-- action bars, the chat, the portraits...). A window the game protects is never touched (an addon may
-- not even ask whether it is shown).
local function IsWindow(frame)
	if frame.IsForbidden and frame:IsForbidden() then return false end
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
		if not frame or (frame.IsForbidden and frame:IsForbidden()) then return nil end
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
					-- (every 2 s, never in a fight: the windows opened by the game are caught by its own hooks)
					watch = C_Timer.NewTicker(2, function()
						if not window:IsShown() then
							watch:Cancel()
							watch = nil
						elseif not InCombatLockdown() then
							Beside()
						end
					end)
				end)
			end
		end
	end
end

local Install

function ns.RefreshGameFrames()
	if On() then
		Install()
		TakeAll()
		PlaceAll()
	end
	-- (Off: back where the game puts them when they open next, the bags too. Never by calling the game's placing
	-- from here: its first run builds the game's list of bags, and built by an addon that list blocks the game's
	-- own actions in the controller interface.)
end

-- Any window the game opens as a panel (not only those of the list): in front, and while the option is on,
-- followed too, kept where it stands (heard before the placing below: its place is known when the next one
-- opens).
local function Listen()
	if ShowUIPanel then
		hooksecurefunc("ShowUIPanel", function(window)
			if type(window) ~= "table" then return end
			if On() then Take(window) end
			ns.Skin.Front(window)
		end)
	end
	LayerAll()
end

-- The game's placing heard (only once the option is on: nothing hooked before).
local installed = false
function Install()
	if installed then return end
	installed = true
	-- The game places its windows (and the bags) when one opens or closes (its placing is its own: what
	-- opens and closes them is what can be heard).
	for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
		if _G[name] then hooksecurefunc(name, PlaceAll) end
	end
	if UpdateContainerFrameAnchors then hooksecurefunc("UpdateContainerFrameAnchors", PlaceAll) end
end

function ns.InitGameFrames()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	pcall(events.RegisterEvent, events, "GLOBAL_MOUSE_DOWN")
	events:SetScript("OnEvent", function(_, event)
		if event == "GLOBAL_MOUSE_DOWN" then
			-- (a click on a window, or on the map: in front)
			local window = Clicked()
			if window and window ~= ns.Skin.InFront() then ns.Skin.Front(window) end
			return
		end
		LayerAll()
		if On() then TakeAll() end
	end)
	Listen()
	ns.RefreshGameFrames()
end
