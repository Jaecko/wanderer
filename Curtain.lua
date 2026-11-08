local _, ns = ...
local L = ns.L

-- The curtain: the whole interface fades away, Wanderer's own windows stay
-- (they ignore the interface's opacity). Two reasons draw it:
--
-- Travel: on a flight master's route, a moment after taking off, the
-- interface fades, the camera steps back and a title card names the
-- destination, then stays all the way, discreet. The interface comes back
-- only while the mouse is over one of its parts.
--
-- Photo: a key (or /wanderer photo) hides everything but the label of what
-- you hover. The same key, Escape or a fight brings everything back.
--
-- The names key held (WANDERER_REVEAL) brings the interface back meanwhile,
-- but in the photo.
--
-- Never during a fight; every reason is cleared when one starts. On a flight
-- the chat is left to its own behavior.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local FADE_OUT, FADE_IN = 2, 0.8 -- seconds of a full fade
local TRAVEL_DELAY = 3 -- after taking off
local PEEK_TIME = 2 -- seconds the interface stays after the mouse left it
local TRAVEL_ZOOM = 8 -- yards the camera steps back
local CARD_TIME = 12 -- seconds the destination is shown fully
local CARD_REST = 0.35 -- its opacity after, all the way to the landing
local CHECK_EVERY = 0.1 -- seconds between looks at the mouse and the reasons (the fade itself moves every frame)

local reasons = {} -- reason -> true
local current, target = 1, 1
local tween = U.Tween(1)
local peekUntil = 0
local destination -- name of the flight's end
local card, cardText, cardShown = nil, nil, 0
local driver
local chatKept = {} -- chat frame -> true while it ignores the fading
local minimapHidden = false
local sinceCheck = 0

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
	-- The names key held: the interface back meanwhile (never in the photo, asked for on purpose).
	if ns.revealing and not reasons.photo then return 1 end
	if reasons.travel and not reasons.photo and GetTime() < peekUntil then return 1 end
	return 0
end

local function SetReason(reason, on)
	reasons[reason] = on or nil
	target = Wanted()
	sinceCheck = CHECK_EVERY -- the chat looked at on the next frame
	driver:Show()
end

-- Other reasons (being away): the same curtain.
function ns.SetCurtainReason(reason, on) SetReason(reason, on) end

-- Photo mode ---------------------------------------------------------------------------

function ns.IsPhotoMode() return reasons.photo == true end -- (tests)

function ns.TogglePhotoMode()
	if InCombatLockdown() then return end
	SetReason("photo", not reasons.photo)
	if reasons.photo then ns.Print(L.MSG_PHOTO_ON) end
end

function Wanderer_TogglePhoto() ns.TogglePhotoMode() end

-- Travel -------------------------------------------------------------------------------

-- (an extension naming the flight itself, Wanderer Maps' flight line: the title is its; the fade and the camera stay)
local function ShowCard()
	if not destination or ns.Yields("flightCard") then return end
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

-- travelZoom (this character's, ns.Kept): your distance before the camera stepped back (kept
-- through a /reload). The landing goes back to it (a step back blocked at the
-- farthest distance would cost yards otherwise).
local function StartTravel()
	if reasons.travel then return end
	if not (ns.db and ns.db.enabled and ns.db.travel.enabled) then return end
	if not Clean(Safe(UnitOnTaxi, "player")) then return end
	SetReason("travel", true)
	ShowCard()
	-- (another addon driving the camera, DynamicCam: left to it)
	-- (the calm movements: the camera left where it is)
	if ns.db.travel.camera and CameraZoomOut and not ns.Kept("travelZoom") and not (ns.Yields and ns.Yields("camera"))
		and not ns.CalmMotion() then
		-- (a dialogue's camera still coming back: the distance it keeps for you, not the one on the way)
		local scene = ns.Kept("sceneCamera")
		local zoom = scene and scene.zoom or Clean(Safe(GetCameraZoom))
		if zoom then
			ns.Keep("travelZoom", zoom)
			Safe(CameraZoomOut, TRAVEL_ZOOM)
			ns.CameraNotice()
		end
	end
end

local function EndTravel()
	local kept = ns.Kept("travelZoom")
	if not reasons.travel and not kept then return end
	SetReason("travel", false)
	if not Clean(Safe(UnitOnTaxi, "player")) then destination = nil end
	card:Hide()
	-- Still flying (a loading screen): the camera stays back.
	if kept and not Clean(Safe(UnitOnTaxi, "player")) then
		local before, now = kept, Clean(Safe(GetCameraZoom))
		if now and now > before and CameraZoomIn then Safe(CameraZoomIn, now - before) end
		if now and now < before and CameraZoomOut then Safe(CameraZoomOut, before - now) end
		ns.Keep("travelZoom", nil)
	end
end

-- (Wanderer or its travel mode switched off in flight: the interface back at once, the camera at the landing)
function ns.RefreshCurtain()
	if reasons.travel and not (ns.db and ns.db.enabled and ns.db.travel.enabled) then EndTravel() end
end

-- Motion -------------------------------------------------------------------------------

-- A box taking your keys (the chat's line, a search).
local function Typing() return GetCurrentKeyBoardFocus and Safe(GetCurrentKeyBoardFocus) ~= nil or false end

-- The mouse where the minimap stepped out (hidden, it no longer answers the mouse: the world is under it).
local function OverHiddenMinimap()
	return minimapHidden and (U.IsMouseOver(_G.Minimap) or U.IsMouseOver(_G.MinimapCluster)) or false
end

local function OnUpdate(self, elapsed)
	-- During a flight the interface stays away, whatever the mouse does, and
	-- comes back only while the mouse is over one of its parts (invisible, they
	-- still answer the mouse), a moment longer after.
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= CHECK_EVERY then
		sinceCheck = 0
		-- (or while you type: the chat's line is never written blind)
		-- (the minimap stepped out once faded: its place under the mouse brings everything back, as the other parts)
		if reasons.travel and not reasons.photo and (not U.IsOverWorld() or Typing() or OverHiddenMinimap()) then
			peekUntil = GetTime() + PEEK_TIME
		end
		target = Wanted()
		-- Photo hides everything; an absence keeps the chat. A flight leaves it alone (it fades by itself).
		local keep = reasons.away and not reasons.photo and true or false
		if keep ~= (next(chatKept) ~= nil) then KeepChat(keep) end
	end
	if current ~= target then
		current = tween:Step(target, elapsed, FADE_IN, FADE_OUT)
		UIParent:SetAlpha(current)
	end
	MinimapAway(current <= MINIMAP_GONE and target == 0)
	if card:IsShown() then
		cardShown = cardShown + elapsed
		-- Fully at first, then discreet all the way: it goes when you land.
		local alpha = cardShown < 1 and cardShown
			or (cardShown > CARD_TIME and math.max(CARD_REST, 1 - (cardShown - CARD_TIME) * (1 - CARD_REST)) or 1)
		if card:GetAlpha() ~= alpha then card:SetAlpha(alpha) end
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
	ns.root.flights = nil -- flight times, no longer kept
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", OnUpdate)

	card = ns.Skin.CreateWindow("WandererTravelCard", "DIALOG")
	ns.Placeable({ key = "travelCard", label = function() return L.PLACING_TRAVEL end, frame = card, size = { 300, 70 },
		scale = function() return ns.Skin.Scale() end, default = { "TOP", "TOP", 0, -150 },
		enabled = function() return ns.db and ns.db.enabled and ns.db.travel.enabled and true or false end })
	ns.PlaceApply("travelCard", card)
	card:EnableMouse(false)
	card.kicker = ns.Skin.CreateKicker(card, L.TRAVEL_KICKER)
	card.kicker:SetPoint("TOP", card, "TOP", 0, -(ns.Skin.Margin() + 10))
	card.kicker:SetJustifyH("CENTER")
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
