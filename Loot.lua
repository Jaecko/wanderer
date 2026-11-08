local _, ns = ...

-- Instant loot: when the game loots automatically (its own "Auto Loot"
-- option, or the modifier key that reverses it), every item is taken at
-- once instead of waiting for the loot window to fill. Another addon looting
-- as fast does it alone (Compat.lua).

local Safe = ns.Util.Safe

local LOOT_DELAY = 0.3 -- the game sends LOOT_READY more than once per corpse
local lastLoot = 0

local function GameLootsAutomatically(autoLoot)
	if type(autoLoot) == "boolean" then return autoLoot end
	local option = Safe(GetCVarBool, "autoLootDefault") and true or false
	local reversed = Safe(IsModifiedClick, "AUTOLOOTTOGGLE") and true or false
	return option ~= reversed
end

local function OnLootReady(_, _, autoLoot)
	if not (ns.db and ns.db.enabled and ns.db.loot.fast) or ns.Yields("fastLoot") then return end
	if not GameLootsAutomatically(autoLoot) then return end
	local now = GetTime()
	if now - lastLoot < LOOT_DELAY then return end
	lastLoot = now
	-- (what the first slot held, for the fishing notice: the window is empty by the time it reads it)
	local _, name = Safe(GetLootSlotInfo, 1)
	ns.lastLoot = { name = ns.Util.Clean(name), link = ns.Util.Clean(Safe(GetLootSlotLink, 1)), at = now }
	for slot = (Safe(GetNumLootItems) or 0), 1, -1 do Safe(LootSlot, slot) end
end

function ns.InitLoot()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("LOOT_READY")
	frame:SetScript("OnEvent", OnLootReady)
end
