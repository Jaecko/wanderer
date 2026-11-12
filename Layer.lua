local _, ns = ...
local L = ns.L

-- The layer you play on, for who wants to know it (option, on): never shown on the screen, one line in the
-- tooltip of the zone's name by the minimap. The game does not say it; the creatures around do: the
-- fifth part of their identity is the layer's number ("Creature-0-4170-0-12-..." : 12). Read from the
-- creatures you point at, target or see a nameplate of, out of a fight and out of an instance; taken
-- only when two different creatures agree, let go at each new zone and each loading screen.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local layer -- the number agreed on (nil: not known yet)
local last -- { layer, creature } of the last creature read

local function On() return ns.db and ns.db.enabled and ns.db.world.layer and true or false end

local function Forget()
	layer, last = nil, nil
end

local function Read(unit)
	if not On() or InCombatLockdown() or Clean(Safe(IsInInstance)) then return end
	local guid = Clean(Safe(UnitGUID, unit))
	if type(guid) ~= "string" then return end
	local kind, zone, spawn = guid:match("^(%a+)%-%d+%-%d+%-%d+%-(%d+)%-%d+%-(%x+)$")
	if kind ~= "Creature" and kind ~= "Vehicle" then return end
	zone = tonumber(zone)
	if not (zone and zone > 0 and spawn) then return end
	-- (the same creature twice proves nothing; two different ones on the same number do)
	if last and last.layer == zone and last.creature ~= spawn then layer = zone end
	last = { layer = zone, creature = spawn }
end

-- The line under a zone's tooltip ("Layer 12"), when the layer is known.
function ns.AddLayerLine(tooltip)
	if not (On() and layer and tooltip) then return end
	tooltip:AddLine(L.LAYER_LINE:format(layer), ns.Skin.RGB("muted"))
end

function ns.InitLayer()
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		pcall(frame.RegisterEvent, frame, event)
	end
	frame:SetScript("OnEvent", function(_, event, unit)
		if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then return Forget() end
		Read(event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or event == "PLAYER_TARGET_CHANGED" and "target" or unit)
	end)
	-- The game's own zone name by the minimap (Wanderer's band says it itself, MinimapLook.lua).
	local zone = (MinimapCluster and MinimapCluster.ZoneTextButton) or _G.MinimapZoneTextButton
	if type(zone) == "table" and zone.HookScript then
		zone:HookScript("OnEnter", function(self)
			if not (layer and On() and GameTooltip:IsOwned(self)) then return end
			ns.AddLayerLine(GameTooltip)
			GameTooltip:Show()
		end)
	end
end
