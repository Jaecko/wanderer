local _, ns = ...
local L = ns.L

-- One quiet line over the game's target frame, in Wanderer's look, for what
-- the target frame does not say: a monster on you that nobody has hit yet,
-- your share of its threat in a group. Pieces are joined on one line
-- ("Not yours yet · Threat 72 %"); nothing to say, nothing shown.
--
-- Over the frame, not under it: below, the game shows the target's buffs,
-- debuffs and its own target. Fades in and out softly; checked a few times a
-- second during a fight only.

local U = ns.Util

local FADE_IN, FADE_OUT = 0.35, 0.8
local CHECK_EVERY = 0.25
local SEPARATOR = "|cff8c8c8c  ·  |r"
local UNTAGGED_ICON = "|TInterface\\Icons\\Ability_SteelMelee:12:12:0:0:64:64:5:59:5:59|t "
local UNTAGGED_COLOR = { 1, 0.6, 0.2 }

local frame, skin, text, driver
local wanted, since = 0, 0

local function Hex(color)
	local function byte(value) return math.floor(value * 255 + 0.5) end
	return ("|cff%02x%02x%02x"):format(byte(color[1]), byte(color[2]), byte(color[3]))
end

-- The pieces of the line, in order of importance.
local function Pieces()
	local pieces = {}
	if ns.IsUntaggedOnYou and ns.IsUntaggedOnYou("target") then
		pieces[#pieces + 1] = UNTAGGED_ICON .. Hex(UNTAGGED_COLOR) .. L.UNTAGGED_MARK .. "|r"
	end
	if ns.ThreatPiece then
		local threat, color = ns.ThreatPiece()
		if threat then pieces[#pieces + 1] = Hex(color) .. threat .. "|r" end
	end
	return pieces
end

local function Update()
	local target = _G.TargetFrame
	-- A conversation scene: the target frame steps aside, this line with it.
	local pieces = (target and target:IsShown() and not ns.sceneActive) and Pieces() or {}
	if not pieces[1] then
		wanted = 0
		return
	end
	text:SetText(table.concat(pieces, SEPARATOR))
	local margin = ns.Skin.Padding() + 4
	frame:SetSize(U.Measure(text, "GetStringWidth", 120) + margin * 2, U.Measure(text, "GetStringHeight", 12) + margin * 2)
	frame:ClearAllPoints()
	-- Centered over the name and the bars (the portrait is on the right).
	frame:SetPoint("BOTTOM", target, "TOP", -24, -2)
	frame:SetScale(ns.Skin.Scale())
	skin:Layout()
	wanted = 1
	if not frame:IsShown() then
		frame:SetAlpha(0)
		frame:Show()
	end
end

local function OnUpdate(_, elapsed)
	since = since + elapsed
	if since >= CHECK_EVERY then
		since = 0
		Update()
	end
	if ns.Skin.Fade(frame, wanted, elapsed, FADE_IN, FADE_OUT) <= 0 and wanted == 0 then
		frame:Hide()
		-- Out of a fight with nothing to say: asleep until the next event.
		if not InCombatLockdown() then driver:Hide() end
	end
end

function ns.RefreshTargetInfo()
	if not frame then return end
	Update()
	driver:Show()
end

function ns.InitTargetInfo()
	frame, skin = ns.Skin.CreateWindow("WandererTargetInfo", "MEDIUM")
	frame:EnableMouse(false)
	text = ns.Skin.CreateText(frame, "GameTooltipTextSmall", 0.95, 0.92, 0.85)
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	if text.SetWordWrap then text:SetWordWrap(false) end
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", OnUpdate)
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }) do
		driver:RegisterEvent(event)
	end
	driver:SetScript("OnEvent", function()
		Update()
		driver:Show()
	end)
end
