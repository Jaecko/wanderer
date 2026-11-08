local _, ns = ...
local L = ns.L

-- Round button on the minimap edge: left click opens Wanderer's card (Card.lua), right
-- click the options, drag moves it around the minimap.

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local button

local function ButtonSettings()
	local mine = ns.Mine()
	mine.minimap = type(mine.minimap) == "table" and mine.minimap or { angle = 225, hide = false }
	return mine.minimap
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

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(L.ADDON_TITLE)
	GameTooltip:AddLine(L.MINIMAP_PRESET:format(L["PRESET_" .. ns.db.preset:upper()]), 1, 1, 1)
	local muted = ns.Skin.COLORS.muted
	GameTooltip:AddLine(L.MINIMAP_HINT, muted[1], muted[2], muted[3], true)
	GameTooltip:Show()
end

function ns.RefreshMinimapButton()
	ns.RefreshBar()
	if ns.RefreshCard then ns.RefreshCard() end
	if not button then return end
	-- (Wanderer's bar shown: it takes the button's place)
	button:SetShown(not ButtonSettings().hide and not ns.BarActive())
	UpdatePosition()
	button.unread:SetShown(ns.LaunchersWaiting())
end

function ns.InitMinimapButton()
	if not Minimap then return end
	button = CreateFrame("Button", "WandererMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	-- The crest: the icon cut round over a dark disc, a thin golden ring (brighter under the mouse).
	local ground = button:CreateTexture(nil, "BACKGROUND")
	ground:SetSize(26, 26)
	ground:SetPoint("CENTER")
	ground:SetColorTexture(0.03, 0.03, 0.04, 0.85)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(22, 22)
	icon:SetPoint("CENTER")
	local ring = button:CreateTexture(nil, "BORDER")
	ring:SetSize(26, 26)
	ring:SetPoint("CENTER")
	ring:SetTexture("Interface\\Buttons\\WHITE8X8")
	ring:SetVertexColor(1, 0.82, 0, 0.55)
	local round = ns.Skin.RoundMask(button, icon)
	ns.Skin.RoundMask(button, ground)
	ring:SetShown(ns.Skin.RoundMask(button, ring))
	if not round then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	button.ring = ring
	-- A small golden dot: something waits in a window (an extension's count).
	button.unread = button:CreateTexture(nil, "OVERLAY", nil, 2)
	button.unread:SetSize(7, 7)
	button.unread:SetPoint("TOPRIGHT", button, "TOPRIGHT", -6, -6)
	button.unread:SetColorTexture(1, 0.82, 0, 1)
	button.unread:Hide()

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			ns.OpenOptions()
		else
			ns.ShowMenu(self)
		end
	end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		self.ring:SetVertexColor(1, 0.82, 0, 1)
		ShowTooltip(self)
	end)
	button:SetScript("OnLeave", function(self)
		self.ring:SetVertexColor(1, 0.82, 0, 0.55)
		GameTooltip:Hide()
	end)
	ns.RefreshMinimapButton()
end

function ns.SetMinimapButtonShown(shown)
	ButtonSettings().hide = not shown
	ns.RefreshMinimapButton()
end

function ns.IsMinimapButtonShown()
	return not ButtonSettings().hide
end
