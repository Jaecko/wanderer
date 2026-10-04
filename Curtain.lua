local _, ns = ...
local L = ns.L

-- The curtain: the whole interface fades away, Wanderer's own windows stay
-- (they ignore the interface's opacity). Two reasons draw it:
--
-- Travel: on a flight master's route, a moment after taking off, the
-- interface fades, the camera steps back and a title card names the
-- destination. Moving the mouse brings the interface back for a moment.
--
-- Photo: a key (or /wanderer photo) hides everything but the label of what
-- you hover. The same key, Escape or a fight brings everything back.
--
-- Never during a fight; every reason is cleared when one starts. On a flight
-- the chat stays: someone may be talking to you.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local FADE_OUT, FADE_IN = 2, 0.8 -- seconds of a full fade
local TRAVEL_DELAY = 3 -- after taking off
local PEEK_TIME = 4 -- interface back after the mouse moved
local PEEK_DISTANCE = 12 -- pixels the mouse must move
local TRAVEL_ZOOM = 8 -- yards the camera steps back
local CARD_TIME = 5

local reasons = {} -- reason -> true
local current, target = 1, 1
local tween = U.Tween(1)
local peekUntil = 0
local lastX, lastY
local travelZoom -- camera distance before the flight
local destination
local card, cardText, cardShown = nil, nil, 0
local driver
local chatKept = {} -- chat frame -> true while it ignores the fading
local minimapHidden = false

-- The minimap's content (your arrow, the quest areas, the points) is drawn
-- by the game and ignores opacity: once everything has faded, the minimap
-- itself steps out, and comes back as soon as the interface does.
local MINIMAP_GONE = 0.03
local function MinimapAway(away)
	local minimap = _G.Minimap
	if away == minimapHidden or not (minimap and minimap.SetShown) then return end
	if not pcall(minimap.SetShown, minimap, not away) then return end
	minimapHidden = away
end

-- The chat windows, their tabs, their dock and the typing line.
local function ChatFrames()
	local list = { _G.GeneralDockManager, _G.ChatFrameMenuButton, _G.ChatFrameChannelButton }
	for index = 1, (NUM_CHAT_WINDOWS or 10) do
		for _, suffix in ipairs({ "", "Tab", "EditBox" }) do list[#list + 1] = _G["ChatFrame" .. index .. suffix] end
	end
	return list
end

local function KeepChat(on)
	if on then
		for _, chat in pairs(ChatFrames()) do
			if type(chat) == "table" and chat.SetIgnoreParentAlpha and not chatKept[chat]
				and not (chat.IsIgnoringParentAlpha and chat:IsIgnoringParentAlpha()) then
				chat:SetIgnoreParentAlpha(true)
				chatKept[chat] = true
			end
		end
	else
		for chat in pairs(chatKept) do chat:SetIgnoreParentAlpha(false) end
		wipe(chatKept)
	end
end

local function Wanted()
	if InCombatLockdown() then return 1 end
	if next(reasons) == nil then return 1 end
	if reasons.travel and not reasons.photo and GetTime() < peekUntil then return 1 end
	return 0
end

local function SetReason(reason, on)
	reasons[reason] = on or nil
	target = Wanted()
	driver:Show()
end

-- Other reasons (being away): the same curtain.
function ns.SetCurtainReason(reason, on) SetReason(reason, on) end

-- Photo mode ---------------------------------------------------------------------------

function ns.IsPhotoMode() return reasons.photo == true end

function ns.TogglePhotoMode()
	if InCombatLockdown() then return end
	SetReason("photo", not reasons.photo)
	if reasons.photo then ns.Print(L.MSG_PHOTO_ON) end
end

function Wanderer_TogglePhoto() ns.TogglePhotoMode() end

-- Travel -------------------------------------------------------------------------------

local function ShowCard()
	if not destination then return end
	cardText:SetText(destination)
	card:SetScale(ns.Skin.Scale())
	local margin = ns.Skin.Margin() + 10
	local width = math.max(U.Measure(cardText, "GetStringWidth", 200), U.Measure(card.kicker, "GetStringWidth", 80))
	card:SetSize(math.min(width + margin * 2, 700), U.Measure(cardText, "GetStringHeight", 24)
		+ U.Measure(card.kicker, "GetStringHeight", 12) + 6 + margin * 2)
	ns.Skin.Get(card):Layout()
	card:SetAlpha(0)
	card:Show()
	cardShown = 0
end

local function StartTravel()
	if not (ns.db and ns.db.enabled and ns.db.travel.enabled) then return end
	if not Clean(Safe(UnitOnTaxi, "player")) then return end
	SetReason("travel", true)
	ShowCard()
	if ns.db.travel.camera and GetCameraZoom and CameraZoomOut then
		travelZoom = Clean(Safe(GetCameraZoom))
		Safe(CameraZoomOut, TRAVEL_ZOOM)
	end
end

local function EndTravel()
	if not reasons.travel and not travelZoom then return end
	SetReason("travel", false)
	destination = nil
	if travelZoom and GetCameraZoom and CameraZoomIn then
		local now = Clean(Safe(GetCameraZoom))
		if now and now > travelZoom then Safe(CameraZoomIn, now - travelZoom) end
	end
	travelZoom = nil
end

-- Motion -------------------------------------------------------------------------------

local function OnUpdate(self, elapsed)
	-- The mouse moved during a flight: the interface comes back a moment.
	if reasons.travel and not reasons.photo then
		local x, y = GetCursorPosition()
		if lastX and (math.abs(x - lastX) + math.abs(y - lastY)) > PEEK_DISTANCE then peekUntil = GetTime() + PEEK_TIME end
		lastX, lastY = x, y
	end
	target = Wanted()
	-- Photo hides everything; a flight or an absence keeps the chat.
	local keep = (reasons.travel or reasons.away) and not reasons.photo and true or false
	if keep ~= (next(chatKept) ~= nil) then KeepChat(keep) end
	if current ~= target then
		current = tween:Step(target, elapsed, FADE_IN, FADE_OUT)
		UIParent:SetAlpha(current)
	end
	MinimapAway(current <= MINIMAP_GONE and target == 0)
	if card:IsShown() then
		cardShown = cardShown + elapsed
		local alpha = cardShown < 1 and cardShown or (cardShown > CARD_TIME and math.max(0, 1 - (cardShown - CARD_TIME)) or 1)
		card:SetAlpha(alpha)
		if cardShown > CARD_TIME + 1 then card:Hide() end
	end
	if current == target and next(reasons) == nil and not card:IsShown() then self:Hide() end
end

-- Everything back at once (a fight, a loading screen).
local function Clear()
	KeepChat(false)
	MinimapAway(false)
	wipe(reasons)
	current, target = 1, 1
	tween:Set(1)
	UIParent:SetAlpha(1)
end

function ns.InitCurtain()
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", OnUpdate)

	card = ns.Skin.CreateWindow("WandererTravelCard", "DIALOG")
	card:SetPoint("TOP", UIParent, "TOP", 0, -150)
	card:EnableMouse(false)
	card.kicker = ns.Skin.CreateText(card, "GameTooltipTextSmall", 0.85, 0.75, 0.5)
	card.kicker:SetPoint("TOP", card, "TOP", 0, -(ns.Skin.Margin() + 10))
	card.kicker:SetJustifyH("CENTER")
	card.kicker:SetText(L.TRAVEL_KICKER:upper())
	cardText = ns.Skin.CreateText(card, "GameFontNormalHuge", 1, 0.82, 0)
	cardText:SetPoint("TOP", card.kicker, "BOTTOM", 0, -6)
	cardText:SetJustifyH("CENTER")
	if cardText.SetWordWrap then cardText:SetWordWrap(false) end

	-- The destination chosen at the flight master.
	if TakeTaxiNode then
		hooksecurefunc("TakeTaxiNode", function(index)
			destination = Clean(Safe(TaxiNodeName, index))
			if destination then destination = destination:gsub(",.*$", "") end
		end)
	end
	-- Escape leaves the photo mode (the game menu opens on an empty screen otherwise).
	if GameMenuFrame and GameMenuFrame.HookScript then
		GameMenuFrame:HookScript("OnShow", function()
			if reasons.photo then SetReason("photo", false) end
		end)
	end

	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_REGEN_DISABLED",
		"PLAYER_ENTERING_WORLD" }) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_CONTROL_LOST" then
			C_Timer.After(TRAVEL_DELAY, StartTravel)
		elseif event == "PLAYER_CONTROL_GAINED" then
			EndTravel()
		elseif event == "PLAYER_REGEN_DISABLED" then
			EndTravel()
			Clear()
		else
			-- A loading screen: nothing stays hidden by mistake.
			EndTravel()
			Clear()
			if Clean(Safe(UnitOnTaxi, "player")) then C_Timer.After(TRAVEL_DELAY, StartTravel) end
		end
	end)
end
