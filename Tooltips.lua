local _, ns = ...

-- Game tooltips (items, spells, auras, currencies, mounts, toys, world
-- objects...) are drawn by the same engine as Wanderer's label (Skin.lua): same
-- style, border, badge and highlights. This module only tells the engine what
-- a tooltip describes: its icon (badge) and the item's rarity (border color).
-- The content stays Blizzard's.

local TOOLTIPS = {
	"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
	"ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
}

local Safe, Clean = ns.Util.Safe, ns.Util.Clean

local skins = {} -- tooltip -> its skin

local function Enabled()
	return ns.db and ns.db.enabled and ns.db.tooltips.enabled
end

local function IsUsable(tooltip)
	return tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden()) and not tooltip.IsEmbedded
end

-- Spacing and scale shared with the label (Skin metrics): the same space on
-- every side; room at the top only when a badge sits there.
local function SetRoom(tooltip, skin)
	if tooltip.SetScale then tooltip:SetScale(Enabled() and ns.Skin.Scale() or 1) end
	if not tooltip.SetPadding then return end
	if Enabled() then
		local pad = ns.Skin.Padding()
		local top = skin.badge and skin.badge:IsShown() and ns.Skin.TOP_ROOM or 0
		tooltip:SetPadding(pad, pad, pad, pad + top)
		skin.padded = true
	elseif skin.padded then
		tooltip:SetPadding(0, 0, 0, 0)
		skin.padded = nil
	end
end

local function StyleTooltip(tooltip)
	local skin = skins[tooltip]
	if not skin or not IsUsable(tooltip) then return end
	if not Enabled() then
		skin:ClearTopBadge()
		skin:SetHighlight(nil)
	end
	skin:SetActive(Enabled())
	SetRoom(tooltip, skin)
end

-- What the tooltip describes: icon and quality.
local function Describe(data)
	local types = Enum and Enum.TooltipDataType
	if not (types and data) then return end
	local kind, id = data.type, Clean(data.id)
	if not id then return end
	if (kind == types.Item or kind == types.Toy) and C_Item then
		local link = Clean(data.hyperlink)
		local quality = Clean(Safe(C_Item.GetItemQualityByID, link or id))
		return Clean(Safe(C_Item.GetItemIconByID, id)), quality
	elseif kind == types.Spell or kind == types.UnitAura or kind == types.Macro then
		return Clean(Safe(C_Spell and C_Spell.GetSpellTexture, id))
	elseif kind == types.Currency then
		local info = Safe(C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo, id)
		if type(info) == "table" then return Clean(info.iconFileID), Clean(info.quality) end
	elseif kind == types.Mount then
		local _, _, icon = Safe(C_MountJournal and C_MountJournal.GetMountInfoByID, id)
		return Clean(icon)
	end
end

local function QualityColor(quality)
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b = Safe(C_Item.GetItemQualityColor, quality)
		if r then return r, g, b end
	end
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then return color.r, color.g, color.b end
end

local OnCleared

-- Any tooltip of the game gets the engine the first time it is prepared.
local function Track(tooltip)
	if skins[tooltip] or not IsUsable(tooltip) then return skins[tooltip] end
	skins[tooltip] = ns.Skin.Attach(tooltip)
	if ns.WatchTooltip then ns.WatchTooltip(tooltip) end
	tooltip:HookScript("OnShow", StyleTooltip)
	tooltip:HookScript("OnHide", OnCleared)
	if tooltip.HasScript and tooltip:HasScript("OnTooltipCleared") then
		tooltip:HookScript("OnTooltipCleared", OnCleared)
	end
	StyleTooltip(tooltip)
	return skins[tooltip]
end

-- Called once the tooltip is filled: badge and rarity color.
local function OnTooltipData(tooltip, data)
	local skin = Track(tooltip)
	if not skin or not Enabled() or not IsUsable(tooltip) then return end
	local settings = ns.db.tooltips
	local icon, quality = Describe(data)
	if icon and settings.icon then skin:SetTopBadge(icon, nil, true) else skin:ClearTopBadge() end
	-- Every rarity, from poor (grey) and common (white) to legendary.
	local r, g, b
	if settings.quality and quality and quality >= 0 then r, g, b = QualityColor(quality) end
	skin:SetHighlight(r and "quality" or nil, r, g, b)
	SetRoom(tooltip, skin)
end

function OnCleared(tooltip)
	local skin = skins[tooltip]
	if not skin then return end
	skin:ClearTopBadge()
	skin:SetHighlight(nil)
	SetRoom(tooltip, skin)
end

-- Tooltip windows currently on screen, plus other frames of the tooltip layer
-- the game shows (for /wanderer debug).
function ns.VisibleTooltips()
	local list, seen = {}, {}
	for tooltip in pairs(skins) do
		if tooltip:IsShown() then list[#list + 1] = tooltip seen[tooltip] = true end
	end
	if EnumerateFrames then
		local other = EnumerateFrames()
		while other do
			-- Some frames keep their properties secret now: read through Clean, never compared raw.
			local strata = other.GetFrameStrata and Clean(Safe(other.GetFrameStrata, other))
			if not seen[other] and strata == "TOOLTIP" and Clean(Safe(other.IsVisible, other))
				and Clean(Safe(other.GetName, other)) ~= "WandererLabel" then
				list[#list + 1] = other
			end
			other = EnumerateFrames(other)
		end
	end
	return list
end

function ns.RefreshTooltips()
	for tooltip in pairs(skins) do StyleTooltip(tooltip) end
end

-- Tooltips placed at the game's default position follow the cursor instead,
-- like Wanderer's label. Tooltips anchored to a button or an item stay there.
local function OnDefaultAnchor(tooltip, parent)
	if not (Enabled() and ns.db.tooltips.cursor) or not IsUsable(tooltip) then return end
	if not (tooltip.GetAnchorType and tooltip:GetAnchorType() == "ANCHOR_NONE") then return end
	if parent and not (parent.IsForbidden and parent:IsForbidden()) then
		tooltip:SetOwner(parent, "ANCHOR_CURSOR")
	end
end

function ns.InitTooltips()
	for _, name in ipairs(TOOLTIPS) do Track(_G[name]) end
	-- Blizzard sets up the frame of every tooltip here, including ones Wanderer
	-- does not know by name (options, pets, quests...): the engine applies over it.
	if SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip, _, isEmbedded)
			if isEmbedded then return end
			if Track(tooltip) then StyleTooltip(tooltip) end
		end)
	end
	if GameTooltip_SetDefaultAnchor then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
	end
	if TooltipDataProcessor then
		TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, OnTooltipData)
	end
	ns.RefreshTooltips()
end
