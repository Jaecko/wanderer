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
local SEPARATOR = U.SEPARATOR
local UNTAGGED_ICON = "|T" .. ns.UNTAGGED_ICON .. ":12:12:0:0:64:64:5:59:5:59|t "
local UNTAGGED_COLOR = ns.Skin.COLORS.warn

local frame, skin, text, driver
local wanted, since = 0, 0

local function Hex(color) return U.ColorCode(color[1], color[2], color[3]) end

-- The pieces of the line, in order of importance.
local function Pieces()
	local pieces = {}
	if ns.IsUntaggedOnYou("target") then
		pieces[#pieces + 1] = UNTAGGED_ICON .. Hex(UNTAGGED_COLOR) .. L.UNTAGGED_MARK .. "|r"
	end
	local threat, color = ns.ThreatPiece()
	if threat then pieces[#pieces + 1] = Hex(color) .. threat .. "|r" end
	return pieces
end

-- The target's frame shown: the game's, or the one of a unit frames addon that hides it (ElvUI, Shadowed Unit
-- Frames, PitBull); the game's portrait on the right asks the line a little to the left. nil: none shown.
local OTHER_TARGET_FRAMES = { "ElvUF_Target", "SUFUnittarget", "PitBull4_Frames_Target" }
local function TargetAnchor()
	local game = _G.TargetFrame
	-- (seen, not only shown: unit frames addons hide the game's by giving it a hidden parent)
	if game and game:IsVisible() then return game, -24 end
	for _, name in ipairs(OTHER_TARGET_FRAMES) do
		local other = _G[name]
		if type(other) == "table" and other.IsVisible and other:IsVisible() then return other, 0 end
	end
end

local function Update()
	local target, offset = TargetAnchor()
	-- A conversation scene: the target frame steps aside, this line with it.
	local pieces = (target and not ns.sceneActive) and Pieces() or {}
	if not pieces[1] then
		wanted = 0
		return
	end
	text:SetText(table.concat(pieces, SEPARATOR))
	local margin = ns.Skin.Padding() + 4
	frame:SetSize(U.Measure(text, "GetStringWidth", 120) + margin * 2, U.Measure(text, "GetStringHeight", 12) + margin * 2)
	frame:ClearAllPoints()
	-- Centered over the name and the bars (the portrait is on the right).
	frame:SetPoint("BOTTOM", target, "TOP", offset, -2)
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
	frame, skin = ns.Skin.CreateWindow("WandererTargetInfo", "MEDIUM", nil, true)
	frame:EnableMouse(false)
	text = ns.Skin.CreateText(frame, "GameTooltipText", ns.Skin.RGB("text"))
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	if text.SetWordWrap then text:SetWordWrap(false) end
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", OnUpdate)
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		driver:RegisterEvent(event)
	end
	-- The threat on your target only, and read at the next check (it changes many times a second).
	local THREAT = { UNIT_THREAT_LIST_UPDATE = true, UNIT_THREAT_SITUATION_UPDATE = true }
	for event in pairs(THREAT) do
		driver:RegisterUnitEvent(event, "target")
	end
	driver:SetScript("OnEvent", function(_, event)
		if THREAT[event] then since = CHECK_EVERY else Update() end
		driver:Show()
	end)
end
