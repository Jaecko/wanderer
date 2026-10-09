local _, ns = ...
local L = ns.L

-- Round button on the minimap edge: left click opens Wanderer's menu, right
-- click the reminders, drag moves it around the minimap.

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local button

local function ButtonSettings()
	ns.root.minimap = ns.root.minimap or { angle = 225, hide = false }
	return ns.root.minimap
end

local function UpdatePosition()
	local angle = math.rad(ButtonSettings().angle)
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = Minimap:GetCenter()
	if not cx then return end
	ButtonSettings().angle = math.deg(atan2(y / scale - cy, x / scale - cx))
	UpdatePosition()
end

-- The menu of the button (and of the game's addon list on the minimap): the
-- windows and modes of Wanderer one click away.
function ns.ShowMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.OpenOptions() end
	GameTooltip:Hide()
	MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
		root:CreateTitle(L.ADDON_TITLE)
		-- Every day: what is left to do, who wrote, what an item is worth to you.
		local pending = ns.TodoPending and ns.TodoPending() or 0
		root:CreateButton(pending > 0 and L.TODO_TITLE_COUNT:format(pending) or L.TODO_TITLE, function() ns.ToggleTodo() end)
		if ns.db.messages.enabled then
			local unread = ns.UnreadMessages()
			root:CreateButton(unread > 0 and L.MENU_MESSAGES_UNREAD:format(unread) or L.MESSAGES_TITLE,
				function() ns.ToggleMessages() end)
		end
		if ns.db.tooltips.upgrade then root:CreateButton(L.WEIGHTS_TITLE, function() ns.ToggleWeights() end) end
		-- Tools of the moment.
		root:CreateDivider()
		root:CreateButton(L.MENU_PHOTO, function() ns.TogglePhotoMode() end)
		if ns.db.world.gatherIcons then
			ns.GatherIcons()
			root:CreateButton(L.MENU_ICONS:format(ns.CountIcons()), function() ns.ToggleIconDrawer(button) end)
		end
		-- Settings.
		root:CreateDivider()
		root:CreateCheckbox(L.MENU_ENABLED, function() return ns.db.enabled end,
			function() ns.SetEnabled(not ns.db.enabled) end)
		root:CreateButton(L.MENU_OPTIONS, function() ns.OpenOptions() end)
		-- Help.
		root:CreateDivider()
		root:CreateButton(L.WELCOME_SHOW, function() ns.ShowWelcome() end)
		root:CreateButton(L.NEWS_SHOW, function() ns.ShowNews() end)
		root:CreateButton(L.MENU_RELOAD, function() ReloadUI() end)
	end)
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(L.ADDON_TITLE)
	GameTooltip:AddLine(L.MINIMAP_PRESET:format(L["PRESET_" .. ns.db.preset:upper()]), 1, 1, 1)
	GameTooltip:AddLine(L.MINIMAP_HINT, 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

function ns.RefreshMinimapButton()
	if ns.RefreshChatWhisperButton then ns.RefreshChatWhisperButton() end
	if not button then return end
	button:SetShown(not ButtonSettings().hide)
	UpdatePosition()
	button.unread:SetShown(ns.db.messages.enabled and ns.UnreadMessages and ns.UnreadMessages() > 0 or false)
end

function ns.InitMinimapButton()
	if not Minimap then return end
	button = CreateFrame("Button", "WandererMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	-- A small golden dot: private messages are waiting.
	button.unread = button:CreateTexture(nil, "OVERLAY", nil, 2)
	button.unread:SetSize(7, 7)
	button.unread:SetPoint("TOPRIGHT", button, "TOPRIGHT", -6, -6)
	button.unread:SetColorTexture(1, 0.82, 0, 1)
	button.unread:Hide()
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			ns.ToggleTodo()
		else
			ns.ShowMenu(self)
		end
	end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ns.RefreshMinimapButton()
end

function ns.SetMinimapButtonShown(shown)
	ButtonSettings().hide = not shown
	ns.RefreshMinimapButton()
end

function ns.IsMinimapButtonShown()
	return not ButtonSettings().hide
end
