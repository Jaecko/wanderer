local _, ns = ...

-- The game's damage meter, as the game draws it, or text only (no
-- frame, no background, no bar: names in their class color and numbers, the
-- controls showing under the mouse). Its own settings (bars, sizes, opacity,
-- in Edit Mode) stay the game's. Shown or not by profile: Core.lua, with the
-- game's settings Wanderer sets (the dungeons' profile shows it).

local FADE_SPEED = 6 -- controls of the text-only look: alpha per second

local entries = {} -- entry -> its original look, once dressed
local watched = setmetatable({}, { __mode = "k" }) -- frames already hooked

local function Look()
	local db = ns.db
	if not (db and db.enabled and db.meter) then return "game" end
	return db.meter.look == "text" and "text" or "game"
end

-- One line: name, value, bar, background, icon. Text only takes the bar, its
-- background and its icon away, the names in Wanderer's font and their class
-- color, the numbers in the game's font (made for them).
-- Only the look of its texts and textures is touched: never the game's own
-- code nor its data (with secret numbers, the game refuses what an addon
-- touched).
local function StyleEntry(entry)
	local bar = entry and entry.StatusBar
	if not (bar and bar.Name and bar.Value) then return end
	local look = Look()
	local saved = entries[entry]
	local regions = { bar:GetStatusBarTexture(), bar.Background, bar.BackgroundEdge }
	-- Another look than the one laid: the line as the game drew it, first.
	if saved and saved.look ~= look then
		for index, text in ipairs({ bar.Name, bar.Value }) do
			local own = saved.texts[index]
			if own.font then text:SetFontObject(own.font) end
			text:SetShadowOffset(own.x, own.y)
			text:SetShadowColor(own.sr, own.sg, own.sb, own.sa)
		end
		bar.Name:SetTextColor(saved.r, saved.g, saved.b)
		for _, region in ipairs(regions) do region:SetAlpha(1) end
		if entry.Icon then entry.Icon:SetShown(entry.showBarIcons and true or false) end
		entries[entry], saved = nil, nil
	end
	if look == "game" then return end
	if not saved then
		local r, g, b = bar.Name:GetTextColor()
		saved = { look = look, r = r, g = g, b = b, texts = {} }
		for index, text in ipairs({ bar.Name, bar.Value }) do
			local x, y = text:GetShadowOffset()
			local sr, sg, sb, sa = text:GetShadowColor()
			saved.texts[index] = { font = text:GetFontObject(), x = x or 0, y = y or 0, sr = sr or 0, sg = sg or 0, sb = sb or 0,
				sa = sa or 0 }
		end
		entries[entry] = saved
	end
	local path = ns.Skin and ns.Skin.FontPath(ns.db.label.font)
	local _, size, flags = bar.Name:GetFont()
	if path and size then bar.Name:SetFont(path, size, flags) end
	do
		for _, region in ipairs(regions) do region:SetAlpha(0) end
		if entry.Icon then entry.Icon:Hide() end
		for _, text in ipairs({ bar.Name, bar.Value }) do
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		-- No bar: the name carries its color (the class's, as the bar had it).
		local color = entry.statusBarColor
		if color and color.GetRGB then bar.Name:SetTextColor(color:GetRGB()) end
	end
end

local function WatchEntry(entry)
	if not entry or watched[entry] then return end
	watched[entry] = true
	-- The game redraws a line often (style, background, each new number): dressed again each time.
	for _, method in ipairs({ "UpdateStyle", "UpdateBackground", "UpdateStatusBarColor" }) do
		if entry[method] then hooksecurefunc(entry, method, StyleEntry) end
	end
	StyleEntry(entry)
end

-- The controls of a window (its menus and buttons), visible or not.
local function Controls(window)
	local list = { window.MinimizeButton, window.SettingsDropdown, window.SessionDropdown }
	local typeDropdown = window.DamageMeterTypeDropdown
	if typeDropdown and typeDropdown.Arrow then list[#list + 1] = typeDropdown.Arrow end
	local container = window.MinimizeContainer
	if container and container.ScrollBar then list[#list + 1] = container.ScrollBar end
	return list
end

-- A window: text only takes its header bar and its background away (its
-- controls fade in under the mouse); else, as the game sets them (not through
-- UpdateBackground: watched here, it would call this again).
local function StyleWindow(window)
	local text = Look() == "text"
	local container = window.MinimizeContainer
	local background = container and container.Background
	if window.Header then window.Header:SetAlpha(text and 0 or 1) end
	if background then
		background:SetAlpha(text and 0 or (window.GetBackgroundAlpha and window:GetBackgroundAlpha() or 1))
	end
	if not text then
		for _, control in ipairs(Controls(window)) do control:SetAlpha(1) end
	end
end

local function WatchWindow(window)
	if not window or watched[window] then return end
	watched[window] = true
	if window.SetupEntry then hooksecurefunc(window, "SetupEntry", function(_, entry) WatchEntry(entry) end) end
	if window.UpdateBackground then hooksecurefunc(window, "UpdateBackground", StyleWindow) end
	if window.ForEachEntryFrame then window:ForEachEntryFrame(WatchEntry) end
	local container = window.MinimizeContainer
	if container then WatchEntry(container.LocalPlayerEntry) end
	StyleWindow(window)
end

local function EachWindow(func)
	local meter = _G.DamageMeter
	if meter and meter.ForEachSessionWindow then meter:ForEachSessionWindow(func) end
end

-- Every window and line dressed again (the look changed, a profile).
function ns.RefreshMeter()
	EachWindow(function(window)
		WatchWindow(window)
		StyleWindow(window)
		if window.ForEachEntryFrame then window:ForEachEntryFrame(StyleEntry) end
		local container = window.MinimizeContainer
		if container and container.LocalPlayerEntry then StyleEntry(container.LocalPlayerEntry) end
	end)
end

-- Text only: the controls show under the mouse, and fade away after.
local fader
local function Fade(_, elapsed)
	local text = Look() == "text"
	EachWindow(function(window)
		local target = (not text or window:IsMouseOver()) and 1 or 0
		for _, control in ipairs(Controls(window)) do
			local alpha = control:GetAlpha()
			if alpha ~= target then
				local step = FADE_SPEED * elapsed
				control:SetAlpha(target > alpha and math.min(target, alpha + step) or math.max(target, alpha - step))
			end
		end
	end)
	if not text then fader:SetScript("OnUpdate", nil) end
end

local function UpdateFader()
	if not fader then fader = CreateFrame("Frame") end
	fader:SetScript("OnUpdate", Look() == "text" and Fade or nil)
end

local function Hook()
	local meter = _G.DamageMeter
	if not meter or watched[meter] then return end
	watched[meter] = true
	if meter.SetupSessionWindow then
		hooksecurefunc(meter, "SetupSessionWindow", function(_, _, data)
			if type(data) == "table" then WatchWindow(data.sessionWindow) end
		end)
	end
	ns.RefreshMeter()
	UpdateFader()
end

function ns.ApplyMeter()
	ns.RefreshMeter()
	UpdateFader()
end

function ns.InitMeter()
	if _G.DamageMeter then return Hook() end
	-- The game's meter loads with its interface: dressed once it is there.
	local loader = CreateFrame("Frame")
	loader:RegisterEvent("ADDON_LOADED")
	loader:RegisterEvent("PLAYER_LOGIN")
	loader:SetScript("OnEvent", function(self)
		if _G.DamageMeter then
			self:UnregisterAllEvents()
			Hook()
		end
	end)
end

-- (tests) The look applied to one line.
ns.StyleMeterEntry = StyleEntry
ns.StyleMeterWindow = StyleWindow
