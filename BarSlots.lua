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
ns.BAR_BUTTONS = BARS -- (the game skins dress the same buttons: GameSkins.lua)
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
	-- Dressed square (GameSkins.lua): the game's art stays faded, the dressing's edge and ground take the opacities.
	local look = ns.GameSkins and ns.GameSkins.ScreenParts and ns.GameSkins.ScreenParts(button)
	if look then
		look.ground:SetAlpha(alphas.background)
		for _, edge in ipairs(look.edges) do edge:SetAlpha(alphas.border) end
		return
	end
	for key, kind in pairs(PARTS) do
		local part = button[key]
		if key == "NormalTexture" and button.GetNormalTexture then part = button:GetNormalTexture() or part end
		if part and part.SetAlpha then part:SetAlpha(alphas[kind]) end
	end
end

local function EachButton(fn)
	for _, bar in ipairs(ns.BAR_BUTTONS or BARS) do
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
	local soon = ns.Util.Debounce(0, function() ns.RefreshBarSlots() end)
	events:SetScript("OnEvent", function(_, event)
		if event ~= "PLAYER_ENTERING_WORLD" and event ~= "PLAYER_REGEN_ENABLED" and applied == nil then return end
		-- Out of a fight or a loading screen: at once; slot changes: once for many.
		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then return ns.RefreshBarSlots() end
		soon()
	end)
end

-- Which bars show (2 to 8), as the game's own options page sets them: each character's, kept by the game. What was
-- just chosen is remembered a moment (the game does the same): the server sends the bars back a little later,
-- and a second choice made meanwhile must not undo the first. Never during a fight (the bars are the game's
-- protected frames).
local TOGGLES_FRESH = 10 -- seconds a choice is trusted over what the game says
local toggles, togglesAt = nil, -100

local function Toggles()
	if toggles and GetTime() - togglesAt <= TOGGLES_FRESH then return toggles end
	if not GetActionBarToggles then return {} end
	return { GetActionBarToggles() }
end

-- Bar 2 to 8 shown (index 1 to 7 of the game's list).
function ns.ActionBarShown(index)
	return Toggles()[index] and true or false
end

function ns.SetActionBarShown(index, shown)
	if not SetActionBarToggles then return false end
	if InCombatLockdown() then
		ns.Print(ns.L.SETTINGS_KEY_COMBAT)
		return false
	end
	toggles = Toggles()
	for at = 1, 8 do toggles[at] = toggles[at] and true or false end
	toggles[index] = shown and true or false
	togglesAt = GetTime()
	return (pcall(SetActionBarToggles, unpack(toggles)))
end

-- The game forcing which bars show (some of its rules): nothing to choose then.
function ns.ActionBarsForced()
	local rules = _G.C_GameRules
	return rules and rules.IsMultiActionBarVisibilityForced and ns.Util.Safe(rules.IsMultiActionBarVisibilityForced) and true or false
end
