local _, ns = ...

-- The game's windows (map, character, bags, spells, merchants, mail...) can
-- be moved (option): the title bar drags a window anywhere, and it opens
-- there every time. Nothing else changes: they look as the game draws them,
-- nothing is added. The full screen map stays where the game puts it, and
-- windows without the game's title bar are left alone. Switched off, every
-- window goes back where the game puts it.

local U = ns.Util
local Safe = U.Safe

-- The windows, by name (many are loaded by the game only when first opened).
local WINDOWS = { "WorldMapFrame", "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "ProfessionsBookFrame",
	"CollectionsJournal", "PVEFrame", "FriendsFrame", "CommunitiesFrame", "EncounterJournal", "MerchantFrame",
	"MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame", "TradeFrame", "ClassTrainerFrame", "ProfessionsFrame",
	"AuctionHouseFrame", "ContainerFrameCombinedBags", "DressUpFrame", "ItemTextFrame", "QuestLogPopupDetailFrame",
	"InspectFrame", "MacroFrame", "AddonList", "WardrobeFrame", "ItemSocketingFrame", "ItemUpgradeFrame",
	"ProfessionsCustomerOrdersFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "TaxiFrame",
	"GossipFrame", "QuestFrame" }

local taken = {} -- window -> true
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
	if not On() then return false end
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

-- After the game has placed its windows, each goes back to its own place.
local function PlaceAll()
	if not On() then return end
	for window in pairs(taken) do Place(window) end
end

local function Remember(window)
	local point, _, _, x, y = window:GetPoint(1)
	if point and x and y then Points()[window:GetName()] = { point, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

local function Take(window)
	if taken[window] then return end
	-- The map's title bar is on a frame of its own.
	local chrome = type(window.BorderFrame) == "table" and window.BorderFrame or window
	local handle = chrome.TitleContainer
	if not (type(handle) == "table" and handle.RegisterForDrag) then return end -- no title bar: left alone
	taken[window] = true
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
	end)
	window:HookScript("OnShow", function() Place(window) end)
end

local function TakeAll()
	for _, name in ipairs(WINDOWS) do
		local window = _G[name]
		if type(window) == "table" and window.GetObjectType then Take(window) end
	end
end

function ns.RefreshGameFrames()
	if On() then
		TakeAll()
		PlaceAll()
	elseif not InCombatLockdown() then
		-- Back where the game puts them.
		if UpdateUIPanelPositions then pcall(UpdateUIPanelPositions) end
		if UpdateContainerFrameAnchors then pcall(UpdateContainerFrameAnchors) end
	end
end

function ns.InitGameFrames()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:SetScript("OnEvent", function() if On() then TakeAll() end end)
	-- The game places its windows (and the bags) when they open.
	if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", PlaceAll) end
	if UpdateContainerFrameAnchors then hooksecurefunc("UpdateContainerFrameAnchors", PlaceAll) end
	ns.RefreshGameFrames()
end
