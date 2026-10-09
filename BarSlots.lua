local _, ns = ...

-- The action bar slots, lighter (options, page Action bars): the frame around
-- each button and the background of its slot, each to its own opacity (0:
-- gone); the icons on them stay exactly as the game shows them. At 100 %
-- nothing is touched at all.
-- Never during a fight: what the game redraws meanwhile is set again after.

local BARS = { -- the game's buttons, by the name of their first one, and how many
	{ "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 }, { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 },
	{ "MultiBar6Button", 12 }, { "MultiBar7Button", 12 }, { "StanceButton", 10 }, { "PetActionButton", 10 },
}
local PARTS = { NormalTexture = "border", SlotBackground = "background", SlotArt = "background" }

local hooked = setmetatable({}, { __mode = "k" })
local applied -- the opacities last set ({ border, background }), nil: the game's own

local function Wanted()
	local db = ns.db
	local bars = db and db.enabled and db.bars
	local function Value(key) return bars and math.max(0, math.min(100, bars[key] or 100)) / 100 or 1 end
	return { border = Value("border"), background = Value("background") }
end

local function Paint(button, alphas)
	for key, kind in pairs(PARTS) do
		local part = button[key]
		if key == "NormalTexture" and button.GetNormalTexture then part = button:GetNormalTexture() or part end
		if part and part.SetAlpha then part:SetAlpha(alphas[kind]) end
	end
end

local function EachButton(fn)
	for _, bar in ipairs(BARS) do
		for i = 1, bar[2] do
			local button = _G[bar[1] .. i]
			if button then fn(button) end
		end
	end
end

function ns.RefreshBarSlots()
	if InCombatLockdown() then return end
	local alphas = Wanted()
	local untouched = alphas.border >= 1 and alphas.background >= 1
	if untouched and applied == nil then return end -- the game's own: untouched
	EachButton(function(button)
		Paint(button, alphas)
		-- The game redraws a button's art now and then: set again right after.
		if not hooked[button] and button.UpdateButtonArt then
			hooked[button] = true
			hooksecurefunc(button, "UpdateButtonArt", function(self)
				if applied and not InCombatLockdown() then Paint(self, applied) end
			end)
		end
	end)
	applied = not untouched and alphas or nil
end

function ns.InitBarSlots()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
	events:RegisterEvent("PET_BAR_UPDATE")
	local pending = false
	events:SetScript("OnEvent", function(_, event)
		if event ~= "PLAYER_ENTERING_WORLD" and event ~= "PLAYER_REGEN_ENABLED" and applied == nil then return end
		-- Out of a fight or a loading screen: at once; slot changes: once for many.
		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then return ns.RefreshBarSlots() end
		if pending then return end
		pending = true
		C_Timer.After(0, function()
			pending = false
			ns.RefreshBarSlots()
		end)
	end)
end
