local _, ns = ...

-- A controller, as the game's own interface for one sees it (Forever's controller interface, the setting
-- "Gamepad interface"): our windows are told to the game's navigation, which then moves from button to
-- button with the cross, clicks with the bottom button and closes with the right one, exactly as on the
-- game's own windows. What a mouse alone did gets a button of the pad: the top button (Y, triangle) is the
-- right click of the button chosen (only where a right click does something of its own: a menu, a point taken
-- back), the right stick scrolls the list under it. Only while one of our windows has the controller's
-- attention, never in a fight (the game's navigation is given back as a fight begins), never with a mouse. A
-- window that opens by itself (a whisper, the list of things to do at login) never takes the controller away
-- from the game: it waits to be chosen. Nothing changes for a keyboard and mouse.

local U = ns.Util
local Skin = ns.Skin
local Safe, Clean = U.Safe, U.Clean

local Pad = {}
ns.Pad = Pad

-- Whether the controller interface is on (the game's own test, else its setting).
function Pad.On()
	local util = _G.InputUtil
	if util and util.IsGamepadUIEnabled then
		local ok, on = pcall(util.IsGamepadUIEnabled)
		if ok then return on and true or false end
	end
	local style = _G.C_InputInterfaceStyle
	local kinds = Enum and Enum.InputDeviceInterfaceType
	if style and style.GetCurrentStyle and kinds and kinds.Gamepad then
		return Clean(Safe(style.GetCurrentStyle)) == kinds.Gamepad
	end
	return false
end
U.UsingPad = Pad.On

-- Left out of the navigation (a part only a mouse can use: a bar dragged, a grip).
function Pad.Ignore(frame)
	if frame and _G.SmartNavigation_MarkFrameIgnored then pcall(_G.SmartNavigation_MarkFrameIgnored, frame) end
end

local function Nav() return _G.SmartNavigation end

-- The button the controller has chosen now (nil: none, or no controller).
function Pad.Current()
	local nav = Nav()
	if not (nav and nav.GetCurrentButton) then return nil end
	local ok, button = pcall(nav.GetCurrentButton, nav)
	if ok and type(button) == "table" then return button end
	return nil
end

-- The window the game's navigation is in now.
local function Active()
	local nav = Nav()
	local info = nav and type(nav.activeInfo) == "table" and nav.activeInfo
	return info and info.frame or nil
end

local function Inside(frame, window)
	while frame do
		if frame == window then return true end
		frame = frame.GetParent and frame:GetParent() or nil
	end
	return false
end

-- Under the mouse, or chosen by the controller (the frame itself or something inside it): what a row shows
-- only while hovered (its buttons, its "⋯") shows for the controller's choice too. (The button the controller
-- is leaving still counts as chosen while it is told so: its highlight already let go says it is leaving.)
function U.Hovered(frame)
	if not frame then return false end
	if frame.IsMouseOver and frame:IsMouseOver() then return true end
	if not Pad.On() then return false end
	local chosen = Pad.Current()
	if chosen and chosen.IsHighlightLocked and chosen:IsHighlightLocked() == false then return false end
	return Inside(chosen, frame)
end

-- Where something opened by the controller should stand: the chosen button's corner (else the mouse's place).
function Pad.Point()
	local button = Pad.On() and Pad.Current()
	if button and button.GetRight then
		local right, top = button:GetRight(), button:GetTop()
		local scale = button:GetEffectiveScale() or 1
		if right and top then return right * scale, top * scale end
	end
	if GetCursorPosition then return GetCursorPosition() end
	return nil, nil
end

-- The chosen button's right click: its own click with the right button, else its mouse up. Only on our buttons
-- marked padRight where they are made (a right click of their own: a menu, a point taken back), never a protected
-- one.
function Pad.RightClick()
	local button = Pad.Current()
	if not (button and button.GetScript and button.padRight) then return false end
	if button.IsProtected and button:IsProtected() then return false end
	local click = button:GetScript("OnClick")
	if click then
		click(button, "RightButton", false)
		return true
	end
	local up = button:GetScript("OnMouseUp")
	if up then
		up(button, "RightButton")
		return true
	end
	return false
end

local focused -- our window with the controller's attention

-- The list under the chosen button scrolled one step (its own wheel; never the window's own, where a wheel
-- means something else: a conversation's pages), then the navigation told.
function Pad.Wheel(delta)
	local frame = Pad.Current()
	while frame and frame ~= focused do
		local wheel = frame.GetScript and frame:GetScript("OnMouseWheel")
		if wheel then
			wheel(frame, delta)
			break
		end
		frame = frame.GetParent and frame:GetParent() or nil
	end
	local nav = Nav()
	if focused and nav and nav.RefreshButtonGroups then pcall(nav.RefreshButtonGroups, nav, focused) end
end

-- The buttons the controller's keys click (named: a binding clicks a button by its name).
local function KeyButton(name, fn)
	local button = CreateFrame("Button", name, UIParent)
	button:SetScript("OnClick", fn)
	return button
end
KeyButton("WandererPadRight", function() Pad.RightClick() end)
KeyButton("WandererPadUp", function() Pad.Wheel(1) end)
KeyButton("WandererPadDown", function() Pad.Wheel(-1) end)

local KEYS = { PAD4 = "WandererPadRight", PADRSTICKUP = "WandererPadUp", PADRSTICKDOWN = "WandererPadDown" }

local windows = setmetatable({}, { __mode = "k" })

local function Bind(window)
	if InCombatLockdown() then return end
	window.padKeys = window.padKeys or CreateFrame("Frame")
	Safe(ClearOverrideBindings, window.padKeys)
	for key, name in pairs(KEYS) do Safe(SetOverrideBindingClick, window.padKeys, true, key, name) end
end

local function Unbind(window)
	if window.padKeys and not InCombatLockdown() then Safe(ClearOverrideBindings, window.padKeys) end
end

local function Manager()
	local mode = _G.GamepadMode
	return mode and mode.FrameControlsManager
end

-- The game's navigation told that a window shows or hides (out of a fight). A window that came by itself, or
-- beside a game window, is offered without being chosen.
local told = setmetatable({}, { __mode = "k" })
-- Held back for now: an addon writing in the game's controller state (its list of windows, its chosen button)
-- may taint it, and the game then blocks its own actions when a window closes (a player's report, 2026-11-08).
-- Off until the blocked actions log (below) and a taint log say what is safe.
local SHARE_WITH_GAME = false

-- Whether the controller's buttons really move in our windows (the words shown count on it).
function Pad.Navigating() return SHARE_WITH_GAME and Pad.On() end

local function Tell(window, shown, quietly)
	if not SHARE_WITH_GAME then return end
	local manager = Manager()
	if not (manager and Pad.On()) or InCombatLockdown() then return end
	if shown then
		local opts = windows[window] or {}
		local quiet = quietly or opts.side or window.quiet
		window.skipGamepadAutoFocus = quiet and true or nil
		if quiet then pcall(manager.FrameShown, manager, window, true, false) else pcall(manager.FrameShown, manager, window) end
		told[window] = true
	elseif told[window] then
		told[window] = nil
		pcall(manager.FrameHidden, manager, window)
	end
end

-- A window of ours the controller can use. opts: { close(window) (the right button; else its cross, else
-- Hide), onFocus(window), side (beside a game window: offered, never chosen by itself) }.
function Skin.PadWindow(window, opts)
	if not window or windows[window] then return end
	opts = opts or {}
	windows[window] = opts
	window.SmartNavigationCloseHandler = function(self)
		local cross = self.closeButton
		if opts.close then
			opts.close(self)
		elseif cross and cross:IsShown() and cross:GetScript("OnClick") then
			cross:GetScript("OnClick")(cross, "LeftButton", false)
		else
			self:Hide()
		end
		return true
	end
	window.FocusGamepad = function(self)
		focused = self
		Bind(self)
		if opts.onFocus then pcall(opts.onFocus, self) end
	end
	window.UnfocusGamepad = function(self)
		if focused == self then focused = nil end
		Unbind(self)
	end
	window:HookScript("OnShow", function(self) Tell(self, true) end)
	window:HookScript("OnHide", function(self)
		if focused == self then focused = nil end
		Unbind(self)
		Tell(self, false)
	end)
	if window:IsShown() then Tell(window, true) end
end

-- One button of a window chosen, only while the game's navigation is in that window (never pulled from
-- another window, never before it is told).
function Pad.Choose(button, window)
	if not SHARE_WITH_GAME then return end
	local nav = Nav()
	if not (button and nav and nav.SelectButton and button:IsVisible()) then return end
	local active = Active()
	if not active or (window and active ~= window) or not Inside(button, active) then return end
	pcall(nav.SelectButton, nav, button)
end

-- A window's buttons read again by the navigation (its content changed in place); the given button chosen
-- only when the choice made in it is gone (a new page), never at each redraw.
function Pad.Refresh(window, button)
	if not SHARE_WITH_GAME then return end
	local nav = Nav()
	if not (nav and Pad.On() and window and window:IsVisible() and Active() == window) then return end
	if nav.RefreshButtonGroups then pcall(nav.RefreshButtonGroups, nav, window) end
	local chosen = Pad.Current()
	if button and not (chosen and chosen:IsVisible() and Inside(chosen, window)) then
		C_Timer.After(0, function() Pad.Choose(button, window) end)
	end
end

-- A fight: the game's navigation given back before it begins (our windows are never left holding the cross
-- and the face buttons), our keys let go; after it, the windows still shown offered again, without being chosen.
-- The controller interface left: our keys let go too.
-- The actions the game blocked for Wanderer or its extensions, kept for a look after a /reload
-- (WandererDB.blocked, the last 20): what was blocked, when, with the controller interface or not, the game's
-- windows open then. The game names the blocked function, never the cause: a taint log tells the rest.
local BLOCKED_KEPT = 20
local function NoteBlocked(event, addon, action)
	if type(addon) ~= "string" or not addon:find("^Wanderer") then return end
	local db = _G.WandererDB
	if type(db) ~= "table" then return end
	db.blocked = type(db.blocked) == "table" and db.blocked or {}
	local shown = {}
	for _, name in ipairs({ "ContainerFrameCombinedBags", "WorldMapFrame", "CharacterFrame", "PlayerSpellsFrame", "GossipFrame",
		"QuestFrame", "MerchantFrame", "MailFrame", "SettingsPanel", "GameMenuFrame" }) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsShown and frame:IsShown() then shown[#shown + 1] = name end
	end
	table.insert(db.blocked, { when = date and date("%Y-%m-%d %H:%M:%S") or "", event = event, addon = addon,
		action = tostring(action), pad = Pad.On(), fight = InCombatLockdown() and true or false, shown = table.concat(shown, ", ") })
	while #db.blocked > BLOCKED_KEPT do table.remove(db.blocked, 1) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "INPUT_DEVICE_INTERFACE_TRANSITION")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then return NoteBlocked(event, ...) end
	if event == "PLAYER_REGEN_DISABLED" then
		for window in pairs(windows) do
			Unbind(window)
			Tell(window, false)
		end
		focused = nil
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		for window in pairs(windows) do
			Unbind(window)
			if window:IsShown() then Tell(window, true, true) end
		end
		return
	end
	local on = Pad.On()
	for window in pairs(windows) do
		if on then
			if window:IsShown() then Tell(window, true, true) end
		else
			Unbind(window)
			told[window] = nil
		end
	end
	if not on then focused = nil end
end)
