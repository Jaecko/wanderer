local _, ns = ...

-- A controller (Forever's controller interface, the setting "Gamepad interface"). Our windows have a navigation
-- of their own: the cross moves from button to button, the bottom button clicks, the right one closes, the top one
-- is the chosen button's right click, the right stick scrolls, the triggers go from one open window to the next
-- (the game's own windows taking their turn). Every window of the kit has it, whichever addon made it.
--
-- Nothing is written in the game's controller state (its list of windows, its chosen button, its menus): written
-- from an addon, that state blocks the game's own actions for the rest of the session. Only keys of our own are
-- held, while one of our windows has the controller's attention, never in a fight, never with a mouse. A window
-- that opens by itself (a whisper, the list of things to do at login) never takes the controller away: it waits to
-- be chosen.

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

-- A button of the controller as the game draws it, for the controller plugged in (its own symbols): read from the
-- game's list of icons only, never written. nil when the game has none.
function Pad.Icon(key, size)
	local util = _G.InputIconTextureSetUtility
	if not (util and util.GetNormalActiveInputIconButtonTexture) then return nil end
	local ok, atlas = pcall(util.GetNormalActiveInputIconButtonTexture, key)
	if not ok or type(atlas) ~= "string" or atlas == "" then return nil end
	-- (the game draws them on a wide canvas with a clear border: at 26, as big as the game's own prompts)
	size = size or 26
	return ("|A:%s:%d:%d|a"):format(atlas, size, size)
end

-- What the controller's buttons do, drawn with the game's own icons: { { "PAD1", "CHOOSE" }, { "PADLTRIGGER PADRTRIGGER",
-- "SWITCH" } } (the words: PAD_DO_<word>). nil when an icon is missing: the words said otherwise are kept then.
function Skin.PadKeys(list, size)
	local parts = {}
	for _, entry in ipairs(list) do
		local icons = {}
		for key in entry[1]:gmatch("%S+") do
			local icon = Pad.Icon(key, size)
			if not icon then return nil end
			icons[#icons + 1] = icon
		end
		parts[#parts + 1] = table.concat(icons, "") .. " " .. (ns.L["PAD_DO_" .. entry[2]] or entry[2])
	end
	return table.concat(parts, "     ")
end

-- Left out of the navigation (a part only a mouse can use: a bar dragged, a grip).
function Pad.Ignore(frame)
	if frame then frame.padIgnored = true end
end

local current -- the button chosen now
local active -- our window with the controller's attention
local gameTurn = false -- the game's own window has it (a panel opened after ours, or the triggers)
local fighting = false -- (the event comes just before the game's lock: a window closing then must not take the keys back)

-- The button the controller has chosen now (nil: none, or no controller).
function Pad.Current() return current end

local function Inside(frame, window)
	while frame do
		if frame == window then return true end
		frame = frame.GetParent and frame:GetParent() or nil
	end
	return false
end

-- Under the mouse, or chosen by the controller (the frame itself or something inside it): what a row shows
-- only while hovered (its buttons, its "more") shows for the controller's choice too.
function U.Hovered(frame)
	if not frame then return false end
	if frame.IsMouseOver and frame:IsMouseOver() then return true end
	if not Pad.On() then return false end
	return Inside(current, frame)
end

-- Where something opened by the controller should stand: the chosen button's corner (else the mouse's place).
function Pad.Point()
	local button = Pad.On() and current
	if button and button.GetRight then
		-- (read clean: a button's geometry may be hidden in a fight)
		local right, top = Clean(Safe(button.GetRight, button)), Clean(Safe(button.GetTop, button))
		local scale = button:GetEffectiveScale() or 1
		if type(right) == "number" and type(top) == "number" then return right * scale, top * scale end
	end
	if GetCursorPosition then return GetCursorPosition() end
	return nil, nil
end

-- Something held by the game's cursor (an item taken in hand, a spell): a press then drops it where a mouse
-- would let go of it.
local function CursorHolds()
	local info = _G.GetCursorInfo
	return info ~= nil and Clean(Safe(info)) ~= nil
end

-- A click given by the controller: the button's own click, else what a mouse does on a plain frame. A line to
-- write in opens the controller's keyboard; what holds something in hand is dropped where it stands.
local function Press(button, which)
	if not button or (button.IsEnabled and button:IsEnabled() == false) then return false end
	-- (padClick: what a press does there, when it differs from a mouse's click; false lets the click go on)
	if button.padClick and button.padClick(button, which) ~= false then return true end
	if button.GetObjectType and button:GetObjectType() == "EditBox" then return Pad.Keyboard(button) end
	local drop = button.GetScript and button:GetScript("OnReceiveDrag")
	if drop and CursorHolds() then
		drop(button)
		return true
	end
	if button.Click then
		button:Click(which)
		return true
	end
	local click = button.GetScript and button:GetScript("OnClick")
	if click then
		click(button, which, false)
		return true
	end
	local down, up = button.GetScript and button:GetScript("OnMouseDown"), button.GetScript and button:GetScript("OnMouseUp")
	if down then down(button, which) end
	if up then up(button, which) end
	return (down or up) ~= nil
end

-- What the window in the controller's hands answers itself (a map under its cursor), when it does.
local windows = setmetatable({}, { __mode = "k" }) -- our windows -> their options
local function Answer(name, ...)
	local opts = active and windows[active]
	local fn = opts and opts[name]
	return fn and fn(...) or false
end

function Pad.Click()
	if Answer("click") then return true end
	-- (an item with no name to be bound by: its own first click all the same)
	return Press(current, current and current.padPrimary or "LeftButton")
end

-- The chosen button's right click, only on our buttons marked padRight where they are made (a right click of their
-- own: a menu, a point taken back), never a protected one.
-- The left button: what Alt + click does on the chosen button (its menu of choices: padAlt), or the window's own.
function Pad.Alt()
	if Answer("alt") then return true end
	if current and current.padAlt then
		current.padAlt(current)
		return true
	end
	return false
end

function Pad.RightClick()
	if Answer("right") then return true end
	-- (an item's second click, when it has no name to be bound by)
	if current and current.padSecondary and not current.padRight then return Press(current, current.padSecondary) end
	if not (current and current.padRight) then return false end
	if current.IsProtected and current:IsProtected() then return false end
	return Press(current, "RightButton")
end

-- What a mouse coming over a button or leaving it would do (its tooltip, its highlight).
local function Fire(frame, script, ...)
	local run = _G.ExecuteFrameScript
	if run and pcall(run, frame, script, ...) then return end
	local handler = frame.GetScript and frame:GetScript(script)
	if handler then pcall(handler, frame, ...) end
end

-- Where a frame stands, on the screen's own scale (nil: nowhere yet, or the game keeps it secret).
local function Rect(frame)
	if not frame.GetLeft then return nil end
	local left, right, top, bottom = Clean(Safe(frame.GetLeft, frame)), Clean(Safe(frame.GetRight, frame)),
		Clean(Safe(frame.GetTop, frame)), Clean(Safe(frame.GetBottom, frame))
	if type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then return nil end
	local scale = frame:GetEffectiveScale() or 1
	return left * scale, right * scale, top * scale, bottom * scale
end

local BUTTONS = { Button = true, CheckButton = true, ItemButton = true, DropdownButton = true }

local function Usable(frame)
	-- (padTip: a frame that only has a tooltip, reached to read it: being chosen is its OnEnter)
	if frame.padTip and frame.IsMouseEnabled and frame:IsMouseEnabled() then return true end
	local kind = frame.GetObjectType and frame:GetObjectType()
	if BUTTONS[kind] then
		if frame.IsEnabled and frame:IsEnabled() == false then return false end
		return not (frame.IsMouseClickEnabled and frame:IsMouseClickEnabled() == false)
	end
	-- (a line to write in: the controller's keyboard writes in it)
	if kind == "Slider" or kind == "EditBox" then return not (frame.IsEnabled and frame:IsEnabled() == false) end
	if kind ~= "Frame" or not (frame.IsMouseEnabled and frame:IsMouseEnabled()) then return false end
	return frame:GetScript("OnMouseUp") ~= nil and frame:GetScript("OnDragStart") == nil
end

-- Every button of a window that can be reached now: shown, inside what clips it. A window opened inside another
-- is a window of its own, a piece covering most of the window is its background.
local function Walk(frame, window, area, clipLeft, clipRight, clipTop, clipBottom, found)
	for _, child in ipairs({ frame:GetChildren() }) do
		local skipped = windows[child] or child.padIgnored or (child.IsForbidden and child:IsForbidden()) or not child:IsVisible()
		if not skipped then
			local left, right, top, bottom = Rect(child)
			local innerLeft, innerRight, innerTop, innerBottom = clipLeft, clipRight, clipTop, clipBottom
			if left then
				local x, y = (left + right) / 2, (top + bottom) / 2
				-- (padOutside: a button that stands beside its window on purpose)
				local inside = child.padOutside or (x >= clipLeft and x <= clipRight and y <= clipTop and y >= clipBottom)
				if inside and not child.padPass and child ~= window.closeButton and Usable(child) and (right - left) * (top - bottom) < area * 0.6 then
					found[#found + 1] = { frame = child, left = left, right = right, top = top, bottom = bottom, x = x, y = y }
				end
				if child:GetObjectType() == "ScrollFrame" or (child.DoesClipChildren and child:DoesClipChildren()) then
					innerLeft, innerRight = math.max(clipLeft, left), math.min(clipRight, right)
					innerTop, innerBottom = math.min(clipTop, top), math.max(clipBottom, bottom)
				end
			end
			Walk(child, window, area, innerLeft, innerRight, innerTop, innerBottom, found)
		end
	end
	return found
end

-- How high a frame is drawn: its layer first, then its level in that layer.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function Height(frame)
	local strata = frame.GetFrameStrata and Clean(Safe(frame.GetFrameStrata, frame))
	local level = frame.GetFrameLevel and Clean(Safe(frame.GetFrameLevel, frame))
	return (STRATA[strata] or 3) * 10000 + (type(level) == "number" and level or 0)
end

-- What a mouse could not reach either: a button whose middle lies under another one drawn above it (a box with a
-- button of its own laid over it for the controller), unless one holds the other.
local function Uncovered(found)
	if #found < 2 then return found end
	for _, target in ipairs(found) do target.height = Height(target.frame) end
	local kept = {}
	for _, target in ipairs(found) do
		local covered = false
		for _, other in ipairs(found) do
			if other ~= target and other.height > target.height and target.x >= other.left and target.x <= other.right
				and target.y <= other.top and target.y >= other.bottom
				and not Inside(target.frame, other.frame) and not Inside(other.frame, target.frame) then
				covered = true
				break
			end
		end
		if not covered then kept[#kept + 1] = target end
	end
	return kept
end

local function Targets(window)
	local left, right, top, bottom = Rect(window)
	if not left then return {} end
	-- (a bar is all buttons: none of them is its background)
	local area = windows[window] and windows[window].anySize and math.huge or (right - left) * (top - bottom)
	return Uncovered(Walk(window, window, area, left, right, top, bottom, {}))
end

-- The chosen button's frame around it, and what a mouse over it would show.
local marker
local function Marker()
	if marker then return marker end
	marker = CreateFrame("Frame", nil, UIParent)
	marker:SetFrameStrata("TOOLTIP")
	if marker.SetIgnoreParentAlpha then marker:SetIgnoreParentAlpha(true) end
	local edges = Skin.Edges(marker, ns.Skin.RGB("gold", 1))
	edges[1]:SetHeight(2)
	edges[2]:SetHeight(2)
	edges[3]:SetWidth(2)
	edges[4]:SetWidth(2)
	marker:Hide()
	return marker
end

local closer = CreateFrame("Frame") -- holds every key of ours
local tipHeld = false -- the game's tooltip shows the chosen button's words

local function TipIsOurs(button)
	local tip = _G.GameTooltip
	if tip and tip.IsOwned and Clean(Safe(tip.IsOwned, tip, button)) == true then return true end
	-- (or the help card, Kit.lua: a hint given as words)
	return ns.Skin.HelpOwner ~= nil and ns.Skin.HelpOwner() == button
end
local BindActions, SwitchHint

local function Select(button)
	if button == current then return end
	local leaving = current
	current = button -- (first: what it shows while hovered must see it is no longer chosen)
	if leaving then
		if leaving.UnlockHighlight then Safe(leaving.UnlockHighlight, leaving) end
		Fire(leaving, "OnLeave", false)
	end
	local mark = Marker()
	mark:ClearAllPoints()
	if button then
		mark:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
		mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
		mark:Show()
		if button.LockHighlight then Safe(button.LockHighlight, button) end
		Fire(button, "OnEnter", false)
		tipHeld = TipIsOurs(button)
	else
		mark:Hide()
		tipHeld = false
	end
	BindActions()
	SwitchHint()
end
Pad.Select = Select

local memory = setmetatable({}, { __mode = "k" }) -- window -> its button chosen when the controller left it for another

-- The first button of a window: what the window is for when it says so (padFirst, its items), else the top left one.
-- (a button beside its window, padOutside, is never where the controller starts)
-- (the heading's small buttons, its "?" and its cog, padHeading: last, so a window never opens on their tooltip)
local function Rank(frame)
	if frame.padFirst then return 2 end
	if frame.padHeading then return -1 end
	return (frame.padPrimary ~= nil and not frame.padOutside) and 1 or 0
end

local function First(found)
	local best
	for _, target in ipairs(found) do
		local better = not best
		if best and Rank(target.frame) ~= Rank(best.frame) then
			better = Rank(target.frame) > Rank(best.frame)
		elseif best and math.abs(target.top - best.top) > 4 then
			better = target.top > best.top
		elseif best then
			better = target.left < best.left
		end
		if better then best = target end
	end
	return best and best.frame or nil
end

-- Where the controller starts in a window: where it was before another window took it, else the first button.
local function Start(window, found)
	local remembered = memory[window]
	memory[window] = nil
	if remembered and remembered:IsVisible() and not remembered.padIgnored and Inside(remembered, window) then return remembered end
	return First(found)
end

local DIRECTIONS = {
	up = function(a, b) return b.y - a.y, math.max(0, b.left - a.right, a.left - b.right) end,
	down = function(a, b) return a.y - b.y, math.max(0, b.left - a.right, a.left - b.right) end,
	left = function(a, b) return a.x - b.x, math.max(0, b.bottom - a.top, a.bottom - b.top) end,
	right = function(a, b) return b.x - a.x, math.max(0, b.bottom - a.top, a.bottom - b.top) end,
}

-- The nearest button that way: straight ahead first (a button beside the line counts as much farther).
local function Nearest(direction, found)
	local measure, from = DIRECTIONS[direction], nil
	for _, target in ipairs(found) do
		if target.frame == current then from = target end
	end
	if not from and current then
		-- (a list redrawn: the button chosen may no longer be one that can be chosen, the way on starts from where it is)
		local left, right, top, bottom = Rect(current)
		if left then from = { left = left, right = right, top = top, bottom = bottom, x = (left + right) / 2, y = (top + bottom) / 2 } end
	end
	if not from then return nil end
	local across = direction == "left" or direction == "right"
	local best, bestScore, bestInLine
	for _, target in ipairs(found) do
		-- (a wide title just above is not to the side of what is under it, however near its middle is)
		local over = across and from.x >= target.left and from.x <= target.right
			or not across and from.y >= target.bottom and from.y <= target.top
		if target.frame ~= current and not over then
			local ahead, beside = measure(from, target)
			if ahead > 1 then
				-- (what stands in the same line always comes before what does not)
				local inLine, score = beside == 0, ahead + beside * 4
				if (inLine and not bestInLine) or (inLine == (bestInLine or false) and (not bestScore or score < bestScore)) then
					best, bestScore, bestInLine = target.frame, score, inLine
				end
			end
		end
	end
	return best
end

local function AfterScroll()
	if not (active and current) then return end
	local found, inside, nearest, nearestDistance = Targets(active), false, nil, nil
	local left, right, top, bottom = Rect(current)
	local x, y = left and (left + right) / 2, left and (top + bottom) / 2
	for _, target in ipairs(found) do
		if target.frame == current then inside = true end
		if x then
			local distance = (target.x - x) ^ 2 + (target.y - y) ^ 2
			if not nearestDistance or distance < nearestDistance then nearest, nearestDistance = target.frame, distance end
		end
	end
	if not inside then return Select(nearest) end
	Fire(current, "OnEnter", false)
end

-- The list under the chosen button scrolled one step (its own wheel; never the window's own, where a wheel
-- means something else: a conversation's pages). True when one took it.
local function Scroll(delta)
	if Answer("wheel", delta) then return true end
	local frame = current
	while frame and frame ~= active do
		-- (padAdjust takes the cross's left and right; padWheel: the stick still scrolls it)
		local wheel = (not frame.padAdjust or frame.padWheel) and frame.GetScript and frame:GetScript("OnMouseWheel")
		if wheel then
			wheel(frame, delta * (frame.padStep or 1))
			-- (a moment later, once redrawn: what the chosen row now shows; a row scrolled out of sight is left)
			C_Timer.After(0, AfterScroll)
			return true
		end
		frame = frame.GetParent and frame:GetParent() or nil
	end
	return false
end

function Pad.Wheel(delta) Scroll(delta) end

-- A key of the cross held: again after a moment, then steadily.
local HOLD_FIRST, HOLD_NEXT, HOLD_MOST = 0.35, 0.09, 80
local held, heldWait, heldCount

-- A value changed by the cross's left and right (a slider, a row that says how). padAdjust(button, delta,
-- repeats): repeats, how many times the key held has come again (0 at the press: a value may go faster then).
local function Adjust(delta)
	if not current then return false end
	if current.padAdjust then
		current.padAdjust(current, delta, held and heldCount or 0)
		return true
	end
	if current.GetObjectType and current:GetObjectType() == "Slider" then
		if current.IsEnabled and current:IsEnabled() == false then return false end
		local step = current.GetValueStep and current:GetValueStep() or 1
		current:SetValue(current:GetValue() + delta * (step > 0 and step or 1))
		return true
	end
	return false
end

function Pad.Move(direction)
	if not active then return end
	Answer("onNavigate")
	if (direction == "left" or direction == "right") and Adjust(direction == "right" and 1 or -1) then return end
	local found = Targets(active)
	if not current then return Select(Start(active, found)) end
	local nearest = Nearest(direction, found)
	if nearest then return Select(nearest) end
	if (direction == "up" or direction == "down") and Scroll(direction == "up" and 1 or -1) then
		C_Timer.After(0, function()
			if not active then return end
			local after = Nearest(direction, Targets(active))
			if after then Select(after) end
		end)
	end
end

local function KeyButton(name, fn)
	local button = CreateFrame("Button", name, UIParent)
	button:SetScript("OnClick", fn)
	return button
end

local function Arrow(name, direction)
	local button = KeyButton(name, function(_, _, down)
		if down then
			held, heldWait, heldCount = direction, HOLD_FIRST, 0
			Pad.Move(direction)
		elseif held == direction then
			held = nil
		end
	end)
	button:RegisterForClicks("AnyDown", "AnyUp")
end
Arrow("WandererPadNavUp", "up")
Arrow("WandererPadNavDown", "down")
Arrow("WandererPadNavLeft", "left")
Arrow("WandererPadNavRight", "right")
KeyButton("WandererPadClick", function() Pad.Click() end)
KeyButton("WandererPadRight", function() Pad.RightClick() end)
KeyButton("WandererPadAlt", function() Pad.Alt() end)
KeyButton("WandererPadUp", function() Pad.Wheel(1) end)
KeyButton("WandererPadDown", function() Pad.Wheel(-1) end)
KeyButton("WandererPadClose", function() Pad.Close() end)
KeyButton("WandererPadNext", function() Pad.Cycle(1) end)
KeyButton("WandererPadPrevious", function() Pad.Cycle(-1) end)

local KEYS = { PADDUP = "WandererPadNavUp", PADDDOWN = "WandererPadNavDown", PADDLEFT = "WandererPadNavLeft",
	PADDRIGHT = "WandererPadNavRight", PADRSTICKUP = "WandererPadUp", PADRSTICKDOWN = "WandererPadDown" }

local open = {} -- our windows shown, the last one at the end
local closable = {} -- those the right button closes
local entered = setmetatable({}, { __mode = "k" }) -- pieces of the screen the controller came into (no hiding them)

local function Prune(list)
	for index = #list, 1, -1 do
		if not list[index]:IsShown() then table.remove(list, index) end
	end
end

local function Drop(list, window)
	for index = #list, 1, -1 do
		if list[index] == window then table.remove(list, index) end
	end
end

local function Holds(list, window)
	for _, each in ipairs(list) do
		if each == window then return true end
	end
	return false
end

-- A game's window you can really see: not one one of ours replaces and keeps out of sight (the trainer's, the map's).
local function Seen(frame)
	if not (frame.IsVisible and frame:IsVisible()) or U.IsOffScreen(frame) then return false end
	if frame.GetAlpha and (frame:GetAlpha() or 1) <= 0.01 then return false end
	local left, right, top, bottom = Rect(frame)
	local screenLeft, screenRight, screenTop, screenBottom = Rect(UIParent)
	if not (left and screenLeft) then return true end
	return right > screenLeft and left < screenRight and top > screenBottom and bottom < screenTop
end

-- A window of the game's has the controller's attention, one that can be seen (a bag put away by an addon is not).
local function GameWindow()
	local mode = _G.GamepadMode
	local manager = mode and mode.FrameControlsManager
	local frame = manager and manager.GetActiveFrame and manager:GetActiveFrame()
	return frame and Seen(frame) and frame or nil
end

-- A key of ours, also with the modifiers the game lends the controller's buttons (its settings "Shift", "Ctrl",
-- "Alt" on a button of the pad): held, a click is a Shift + click (a link), a Ctrl + click (tried on), as with a
-- mouse, and the key still comes to us rather than to the game's action bar its modified press is bound to.
local MODIFIERS = { "", "SHIFT-", "CTRL-", "ALT-" }
local function BindKey(key, action)
	for _, modifier in ipairs(MODIFIERS) do Safe(SetOverrideBinding, closer, true, modifier .. key, action) end
end
local function BindClick(key, name, which)
	for _, modifier in ipairs(MODIFIERS) do Safe(SetOverrideBindingClick, closer, true, modifier .. key, name, which) end
end

-- The keys for the button chosen: an item is clicked by its own name, as a mouse would (the game only lets an item
-- be used that way), the rest through a key of ours.
function BindActions()
	if fighting or InCombatLockdown() or not active or gameTurn then return end
	local button = current
	local name = button and button.GetName and button:GetName()
	local direct = name and (button.padPrimary ~= nil or (button.IsProtected and button:IsProtected()))
	-- (what only the game's own key may do: padBinding says which, for now)
	local binding = button and button.padBinding and button.padBinding(button)
	if binding then
		BindKey("PAD1", binding)
	elseif direct then
		BindClick("PAD1", name, button.padPrimary or "LeftButton")
	elseif button or windows[active].click then
		BindClick("PAD1", "WandererPadClick")
	else
		BindKey("PAD1", nil)
	end
	if name and button.padSecondary then
		BindClick("PAD4", name, button.padSecondary)
	else
		BindClick("PAD4", "WandererPadRight")
	end
	-- (the left button, Alt + click, the same for every addon; a window's own use of it comes first)
	local opts = windows[active]
	if not (opts.actions and opts.actions.PAD3) then
		if (button and button.padAlt) or opts.alt then
			BindClick("PAD3", "WandererPadAlt")
		else
			BindKey("PAD3", nil)
		end
	end
end

local Tick

-- Said under the window, what the controller can do there beyond the obvious: the triggers going from one window to
-- another, the left button's choices (Alt + click) on the button chosen.
local switchHint
function SwitchHint()
	local target = active or open[#open]
	local lines = {}
	if Pad.On() and not fighting and target then
		if #open + (GameWindow() and 1 or 0) > 1 then
			lines[#lines + 1] = Skin.PadKeys({ { "PADLTRIGGER PADRTRIGGER", "SWITCH" } }) or ns.L.PAD_SWITCH_HINT
		end
		-- (not when the window binds the left button to something of its own: that says nothing of the button chosen;
		-- nor the chosen button's own lines while the window holds the stick for itself: opts.owns())
		local opts = active and windows[active]
		local own = opts and opts.actions
		local owned = opts and type(opts.owns) == "function" and select(2, pcall(opts.owns)) == true
		if not owned and active and not gameTurn and not (own and own.PAD3) and ((current and current.padAlt) or Answer("hasAlt")) then
			lines[#lines + 1] = Skin.PadKeys({ { "PAD3", current and current.padAltWord or "MORE" } }) or ns.L.PAD_ALT_HINT
		end
		-- (the top button: the chosen one's second click when it has one, else its right click)
		local mine = not owned and active and not gameTurn and current
		if mine and current.padSecondary then
			local words = current.padSecondaryWord and Skin.PadKeys({ { "PAD4", current.padSecondaryWord } })
			if words then lines[#lines + 1] = words end
		elseif mine and current.padRight then
			local words = Skin.PadKeys({ { "PAD4", current.padRightWord or "OPTIONS" } })
			if words then lines[#lines + 1] = words end
		end
	end
	if not lines[1] then
		if switchHint then switchHint:Hide() end
		return
	end
	if not switchHint then
		switchHint = CreateFrame("Frame", "WandererPadSwitchHint", UIParent)
		switchHint:SetFrameStrata("TOOLTIP")
		switchHint.ground = switchHint:CreateTexture(nil, "BACKGROUND")
		switchHint.ground:SetAllPoints()
		switchHint.ground:SetColorTexture(0.055, 0.059, 0.071, 0.85)
		switchHint.text = Skin.Text(switchHint, "GameFontHighlight", "text")
		switchHint.text:SetPoint("CENTER")
	end
	local words = table.concat(lines, "     ")
	if switchHint.words ~= words then
		switchHint.words = words
		switchHint.text:SetText(words)
		switchHint:SetSize(U.Measure(switchHint.text, "GetStringWidth", 160) + 24, 32)
	end
	switchHint:ClearAllPoints()
	switchHint:SetPoint("TOP", target, "BOTTOM", 0, -4)
	switchHint:Show()
end

-- (a window whose own answers changed, a map's cursor taken or left: what is said under it again)
function Skin.PadRefreshHint() SwitchHint() end

-- Whether one of our keys has been passed by the game's.
local function KeyLost(key)
	local holder = _G.GetBindingAction and Clean(Safe(_G.GetBindingAction, key, true))
	return type(holder) == "string" and not holder:find("WandererPad", 1, true)
end


-- The game's own arrow, on a window it believes has the controller: not shown while ours has it (its opacity only,
-- never its state).
local function GameArrow()
	local nav = _G.SmartNavigation
	if nav and nav.SetAlpha then Safe(nav.SetAlpha, nav, active and not gameTurn and 0 or 1) end
end

-- A question of the game's (StaticPopup: gold to pay, an item that binds, a roll that binds) with the controller's
-- attention: the game's own keys answer it (its bottom button yes, its right one no), ours step aside until it is
-- gone, else a press meant for "yes" would click the button chosen behind it. Read only, never written.
local function GamePopup()
	local mode = _G.GamepadMode
	local handler = mode and mode.PopupHandler
	local popup = handler and handler.activePopup
	if popup and popup.IsShown and popup:IsShown() then return popup end
	return nil
end
local popupUp = false -- (the last time it was looked at)

local function Bindings()
	if fighting or InCombatLockdown() then return end
	Prune(open)
	Prune(closable)
	if gameTurn and not open[1] then
		gameTurn = false
		closer:SetScript("OnUpdate", nil)
	end
	Safe(ClearOverrideBindings, closer)
	popupUp = GamePopup() ~= nil
	if popupUp then
		-- (heard again each moment, to come back once it is answered; a key held then is let go by the game)
		held = nil
		closer:SetScript("OnUpdate", Tick)
		if switchHint then switchHint:Hide() end
		return
	end
	GameArrow()
	SwitchHint()
	if not Pad.On() then return end
	if not gameTurn and (closable[1] or active) then
		-- (a window standing with one of the game's: the game's own key closes that one, and ours goes with it)
		local target = active or closable[#closable]
		local binding = windows[target] and windows[target].closeBinding
		if type(binding) == "function" then binding = binding() end
		if binding then
			Safe(SetOverrideBinding, closer, true, "PAD2", binding)
		else
			Safe(SetOverrideBindingClick, closer, true, "PAD2", "WandererPadClose")
		end
	end
	if #open + (GameWindow() and 1 or 0) > 1 then
		Safe(SetOverrideBindingClick, closer, true, "PADRTRIGGER", "WandererPadNext")
		Safe(SetOverrideBindingClick, closer, true, "PADLTRIGGER", "WandererPadPrevious")
	end
	if active and not gameTurn then
		for key, name in pairs(KEYS) do BindClick(key, name) end
		local actions = windows[active] and windows[active].actions
		if actions then
			for key, action in pairs(actions) do Safe(SetOverrideBinding, closer, true, key, action) end
		end
		BindActions()
	end
end

-- A window that does not take the controller by itself (one that came alone: window.padWaits, or window.quiet,
-- set before it is shown; a panel beside a game's window unless it says it takes it). window.padTakes: a window
-- opened silently (the game's own sound rings) that is still the player's doing, the merchant's, the mailbox's.
local function Waits(window)
	local opts = windows[window]
	return window.padWaits or (window.quiet and not window.padTakes) or (opts.side and not opts.takes)
end

local function Eligible()
	for index = #open, 1, -1 do
		local window = open[index]
		if window:IsShown() and not Waits(window) then return window end
	end
	return nil
end

local function Focus(window)
	if window == active and not gameTurn then
		if not window then closer:SetScript("OnUpdate", nil) end
		return Bindings()
	end
	if active then memory[active] = current end
	Select(nil)
	active, held = window, nil
	if window then gameTurn = false end
	closer:SetScript("OnUpdate", (window or gameTurn) and Tick or nil)
	Bindings()
end

local dressed = setmetatable({}, { __mode = "k" }) -- our windows (Skin.PadWindow), not pieces of the screen

local function Leave(window)
	local opts = windows[window]
	entered[window] = nil
	-- (a window of ours entered from the touchpad and left stays one of the windows open: the triggers, the right
	-- button still find it)
	if not (dressed[window] and window:IsShown()) then
		Drop(open, window)
		Drop(closable, window)
	end
	if opts and opts.onLeave then pcall(opts.onLeave, window) end
	if active == window then Focus(Eligible()) else Bindings() end
	memory[window] = nil
end

-- A moment later (what a window draws when it opens, a list redrawn): a button gone is replaced by the nearest one.
local CHECK_EVERY, checkWait, lastX, lastY = 0.15, 0, nil, nil
function Tick(_, elapsed)
	-- (someone passing under the controller's cursor takes the game's tooltip: given back to the chosen button at once)
	if tipHeld and current and not TipIsOurs(current) then
		Fire(current, "OnEnter", false)
		tipHeld = TipIsOurs(current)
	end
	if held then
		heldWait = heldWait - elapsed
		if heldWait <= 0 then
			heldWait, heldCount = HOLD_NEXT, heldCount + 1
			if heldCount > HOLD_MOST then held = nil else Pad.Move(held) end
		end
	end
	checkWait = checkWait - elapsed
	if checkWait > 0 or fighting then return end
	checkWait = CHECK_EVERY
	-- (a question of the game's come or gone: our keys step aside, or come back)
	local popup = GamePopup() ~= nil
	if popup ~= popupUp then
		Bindings()
		if not (popup or active or gameTurn) then closer:SetScript("OnUpdate", nil) end
		return
	end
	if popup then return end
	-- (the game gives its navigation to a window of its own after ours, and its keys then pass before ours: taken back,
	-- the triggers too, also while the game's window has its turn: they are the way back)
	if (#open + (GameWindow() and 1 or 0) > 1 and KeyLost("PADRTRIGGER")) or (active and not gameTurn and KeyLost("PADDRIGHT")) then
		Bindings()
	end
	-- (the game's bags close without a panel being hidden: the turn ends with its window)
	if gameTurn and not GameWindow() then
		gameTurn = false
		return Focus(Eligible())
	end
	if not active or gameTurn then return end
	if not active:IsShown() then return Leave(active) end
	if current and current:IsVisible() and not current.padIgnored and not (current.IsEnabled and current:IsEnabled() == false) then
		local left, right, top, bottom = Rect(current)
		if left then lastX, lastY = (left + right) / 2, (top + bottom) / 2 end
		return
	end
	local found, best, bestDistance = Targets(active), nil, nil
	if current and lastX then
		for _, target in ipairs(found) do
			local distance = (target.x - lastX) ^ 2 + (target.y - lastY) ^ 2
			if not bestDistance or distance < bestDistance then best, bestDistance = target.frame, distance end
		end
	else
		best = Start(active, found)
	end
	-- (a piece of the screen entered with nothing left in it to choose, its last notice gone: left)
	if not best and entered[active] then return Leave(active) end
	Select(best)
end

-- The right button: closes the window the controller is in (or, with none, our last one opened); a piece of the
-- screen is only left, a panel with no cross of its own leaves its place to the game's window.
function Pad.Close()
	Prune(closable)
	-- (opts.leaves: a window entered from the touchpad that the right button only leaves, rolls still waiting)
	if active and (not Holds(closable, active) or (entered[active] and windows[active].leaves)) then return Leave(active) end
	local window = active or closable[#closable]
	if window then window:SmartNavigationCloseHandler() end
end

local function GiveToGame()
	if active then memory[active] = current end
	Select(nil)
	active, gameTurn, held = nil, true, nil
	closer:SetScript("OnUpdate", Tick)
	Bindings()
end

-- The triggers: the next window open, the game's own taking its turn.
function Pad.Cycle(step)
	Prune(open)
	local stops = {}
	for _, window in ipairs(open) do stops[#stops + 1] = window end
	if GameWindow() then stops[#stops + 1] = "game" end
	if #stops < 2 then return end
	local at = 1
	for index, stop in ipairs(stops) do
		if stop == (gameTurn and "game" or active) then at = index end
	end
	local nextStop = stops[(at - 1 + step) % #stops + 1]
	if nextStop == "game" then return GiveToGame() end
	Focus(nextStop)
	-- (as a mouse's click on it: the window chosen comes in front, never left under another one)
	if dressed[nextStop] and not nextStop.hudPiece and Skin.Managed and Skin.Managed(nextStop) and Skin.Front then Skin.Front(nextStop) end
end

local function Opened(window)
	Drop(open, window)
	Drop(closable, window)
	open[#open + 1] = window
	if window.closeButton or not windows[window].side then closable[#closable + 1] = window end
	if Pad.On() and not fighting and not InCombatLockdown() and not Waits(window) then
		Focus(window)
	else
		Bindings()
	end
end

local standing = setmetatable({}, { __mode = "k" }) -- our window -> the game's window it stands in front of

local kept = setmetatable({}, { __mode = "k" }) -- the game's windows kept invisible now
local keeping = setmetatable({}, { __mode = "k" }) -- those already heard

-- The game changes some windows' opacity by itself (the map, while you move): put back at once.
local function KeepInvisible(game)
	kept[game] = true
	Safe(game.SetAlpha, game, 0)
	if keeping[game] then return end
	keeping[game] = true
	hooksecurefunc(game, "SetAlpha", function(self, alpha)
		if kept[self] and alpha ~= 0 then self:SetAlpha(0) end
	end)
end

local function StandDown(window)
	local game = standing[window]
	if not game then return end
	standing[window] = nil
	kept[game] = nil
	Safe(game.SetAlpha, game, 1)
	if windows[window] then windows[window].closeBinding = nil end
end

local function Closed(window)
	window.padWaits = nil
	StandDown(window)
	entered[window] = nil
	Drop(open, window)
	Drop(closable, window)
	if active == window then Focus(Eligible()) else Bindings() end
	memory[window] = nil
end

-- A window of ours the controller can use. opts: { close(window) (the right button; else its cross, else
-- Hide), side (beside a game window: offered, never chosen by itself), owns() (true while the window drives the
-- stick itself, a map's cursor: the chosen button's hints step back; Skin.PadRefreshHint() when it changes) }.
function Skin.PadWindow(window, opts)
	if not window then return end
	if windows[window] then
		-- (a window already known: what is asked for now is added)
		for key, value in pairs(opts or {}) do windows[window][key] = value end
		return
	end
	opts = opts or {}
	windows[window] = opts
	dressed[window] = true
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
	window:HookScript("OnShow", Opened)
	window:HookScript("OnHide", Closed)
	if window:IsShown() then Opened(window) end
end

-- The controller's wheel only knows the game's windows: one of ours stands in front of the game's, which opens as
-- usual and is only made invisible (closing it from here would block the game). The game's own key closes it with
-- the right button, ours goes with it. spec: { micro, binding, wanted(), game(), open(), window() }.
local watching
local function Watch()
	if watching then return end
	watching = C_Timer.NewTicker(0.2, function()
		for window, game in pairs(standing) do
			if not game:IsShown() then window:Hide() end
		end
		if not next(standing) then
			watching:Cancel()
			watching = nil
		end
	end)
end

function Skin.PadStandIn(spec)
	local micro = spec.micro
	if not (micro and micro.HookScript) then return end
	micro:HookScript("OnClick", function()
		if not Pad.On() or fighting or InCombatLockdown() or not spec.wanted() then return end
		-- (in the same moment as the game opens it, never seen; a moment later only if it opens later)
		local function Stand()
			if fighting or InCombatLockdown() then return true end
			local game = spec.game()
			if not (game and game:IsShown()) then return false end
			KeepInvisible(game)
			spec.open()
			local window = spec.window()
			if not (window and window:IsShown() and windows[window]) then
				kept[game] = nil
				Safe(game.SetAlpha, game, 1)
				return true
			end
			standing[window] = game
			windows[window].closeBinding = spec.binding
			Bindings()
			Watch()
			return true
		end
		if not Stand() then C_Timer.After(0, Stand) end
	end)
end

-- A piece of the screen that stays (the quests' list) taken by the controller until the right button. opts:
-- { actions = { key = binding }, onLeave(window) }. False when it cannot be now.
function Skin.PadEnter(window, opts)
	if not window or not Pad.On() or fighting or InCombatLockdown() or not window:IsShown() then return false end
	-- (a window of ours already known keeps its own answers: what is asked now is added)
	local known = windows[window] or {}
	for key, value in pairs(opts or {}) do known[key] = value end
	windows[window] = known
	entered[window] = true
	Drop(open, window)
	open[#open + 1] = window
	Focus(window)
	return true
end

-- Whether the controller is in that window now.
function Skin.PadHolds(window) return Pad.On() and active == window and not gameTurn and not fighting end

-- One button of a window chosen, only while the controller is in that window.
function Pad.Choose(button, window)
	if button and active and (not window or active == window) and button:IsVisible() and Inside(button, active) then Select(button) end
end

-- A window's content changed in place: the given button chosen when the choice made in it is gone (a new page).
function Pad.Refresh(window, button)
	if not (Pad.On() and window and active == window) then return end
	if current and current:IsVisible() and Inside(current, window) then return end
	if button then return C_Timer.After(0, function() Pad.Choose(button, window) end) end
	Select(Start(window, Targets(window)))
end

-- A menu with the controller: a card of ours. (The game's own menus enter its controller state when an addon opens
-- them, and the game then blocks its own actions.) Only what a menu of ours asks for is known; the rest does nothing.
function Pad.Menu(owner, build)
	local rows, title = {}, nil
	local methods = {}
	local function nothing() end
	local function Element(entry)
		return setmetatable({ entry = entry }, { __index = function(_, key) return methods[key] or nothing end })
	end
	local function Add(entry)
		rows[#rows + 1] = entry
		return Element(entry)
	end
	function methods.SetEnabled(self, on) self.entry.disabled = not on end
	function methods.CreateButton(_, text, run, data)
		return Add({ text = text, run = run and function() run(data) end })
	end
	local function Choice(_, text, isChosen, set, data)
		return Add({ text = text, glyph = isChosen and isChosen(data) and "check" or false, run = set and function() set(data) end })
	end
	methods.CreateRadio, methods.CreateCheckbox = Choice, Choice
	function methods.CreateTitle(_, text)
		title = title or text
		return Element({})
	end
	build(owner, Element({}))
	local shown = {}
	for _, entry in ipairs(rows) do
		if not entry.disabled then shown[#shown + 1] = entry end
	end
	Skin.ActionCard(owner, { title = title, rows = shown })
	return true
end

-- The controller's keyboard ------------------------------------------------------------------------------------
-- A line to write in, chosen and pressed with the controller: a keyboard of ours under it (the game has none).
-- Its keys are buttons like any other (the cross goes from one to the next, the bottom button writes); the left
-- button erases, the top one is Enter (the line's own: a search runs, a question is answered), the right one puts the
-- keyboard away and keeps what is written. What is written shows in the line as it goes, and in the keyboard's own
-- line. The letters are the client's language's (KEYBOARD_LETTERS); a line of digits only gets digits.

local KEY, KEY_GAP, KEYS_PER_ROW = 30, 4, 12
local PUNCTUATION = ".,'!?:-()/&"
local keyboard

-- One character at a time (letters with accents and Cyrillic are several bytes).
local function Characters(text)
	local list = {}
	for char in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do list[#list + 1] = char end
	return list
end

local function Preview(input)
	if keyboard then keyboard.preview:SetText((input:GetText() or "") .. Skin.Colorize("|", "gold")) end
end

local function Typed(input)
	-- (as the player's own typing: a search filters, an amount is read)
	local changed = input:GetScript("OnTextChanged")
	if changed then changed(input, true) end
	Preview(input)
end

-- The line written in, still there (its window closed meanwhile: the keyboard goes with it).
local function Line()
	local input = keyboard and keyboard.input
	if input and not input:IsVisible() then
		keyboard:Hide()
		return nil
	end
	return input
end

local function Write(char)
	local input = Line()
	if not input then return end
	local text = input:GetText() or ""
	local most = input.GetMaxLetters and Clean(Safe(input.GetMaxLetters, input)) or 0
	if type(most) == "number" and most > 0 and #Characters(text) >= most then return end
	if keyboard.capitals then
		char = U.Upper(char)
		keyboard.capitals = false
		keyboard.Relabel()
	end
	input:SetText(text .. char)
	Typed(input)
end

local function Erase()
	local input = Line()
	if not input then return end
	local text = input:GetText() or ""
	if text == "" then return end
	input:SetText((text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")))
	Typed(input)
end

-- Enter: the keyboard put away first, then the line's own answer (a question closing with it).
local function Done()
	local input = Line()
	if not input then return end
	keyboard:Hide()
	local enter = input:GetScript("OnEnterPressed")
	if enter then enter(input) end
end

local function KeyboardWindow()
	if keyboard then return keyboard end
	keyboard = Skin.CreateWindow("WandererPadKeyboard", "FULLSCREEN_DIALOG")
	Skin.PadWindow(keyboard, { alt = function() Erase() return true end, right = function() Done() return true end })
	Skin.Closable(keyboard, "WandererPadKeyboard")
	-- (a click elsewhere with a mouse does not put it away: it is the controller's)
	keyboard:SetScript("OnEvent", nil)
	keyboard.keys, keyboard.extra = {}, {}
	keyboard.preview = Skin.Text(keyboard, "ChatFontNormal", "text")
	keyboard.preview:SetJustifyH("LEFT")
	if keyboard.preview.SetWordWrap then keyboard.preview:SetWordWrap(false) end
	local function Mark(button)
		-- (the left and top buttons say what they do, on every key)
		button.padAlt, button.padAltWord = Erase, "ERASE"
		button.padRight, button.padRightWord = true, "DONE"
		return button
	end
	keyboard.Mark = Mark
	local function Special(text, fn, kind)
		local button = Mark(Skin.Button(keyboard, text, fn, kind, 60))
		button:SetHeight(KEY)
		keyboard.extra[#keyboard.extra + 1] = button
		return button
	end
	keyboard.caps = Special(ns.L.KEYBOARD_CAPITALS, function()
		keyboard.capitals = not keyboard.capitals
		keyboard.Relabel()
	end)
	keyboard.space = Special(ns.L.KEYBOARD_SPACE, function() Write(" ") end)
	keyboard.space:SetWidth(150)
	keyboard.erase = Special(ns.L.PAD_DO_ERASE, Erase)
	keyboard.done = Special(ns.L.PAD_DO_DONE, Done, "main")
	function keyboard.Relabel()
		for _, button in ipairs(keyboard.keys) do
			if button:IsShown() then button:SetText(keyboard.capitals and U.Upper(button.char) or button.char) end
		end
		keyboard.caps.caption:SetTextColor(Skin.RGB(keyboard.capitals and "gold" or "kicker"))
	end
	keyboard:HookScript("OnHide", function(self)
		self.input, self.capitals = nil, false
	end)
	return keyboard
end

-- The keyboard laid out for one line: its characters in rows, the special keys under them, placed under the line.
local function Lay(input)
	local board = KeyboardWindow()
	local numeric = input.IsNumeric and Clean(Safe(input.IsNumeric, input)) == true
	local chars = Characters("1234567890")
	if not numeric then
		for _, char in ipairs(Characters(ns.L.KEYBOARD_LETTERS)) do chars[#chars + 1] = char end
		for _, char in ipairs(Characters(PUNCTUATION)) do chars[#chars + 1] = char end
	end
	local margin = Skin.Margin() + 8
	local width = KEYS_PER_ROW * (KEY + KEY_GAP) - KEY_GAP
	board.preview:ClearAllPoints()
	board.preview:SetPoint("TOPLEFT", board, "TOPLEFT", margin, -margin)
	board.preview:SetWidth(width)
	local top = margin + 24
	for index, char in ipairs(chars) do
		local button = board.keys[index]
		if not button then
			button = board.Mark(Skin.Button(board, "", function(self) Write(self.char) end, nil, KEY))
			button:SetSize(KEY, KEY)
			board.keys[index] = button
		end
		button.char = char
		button:SetText(char)
		button:SetWidth(KEY)
		local column, row = (index - 1) % KEYS_PER_ROW, math.floor((index - 1) / KEYS_PER_ROW)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", board, "TOPLEFT", margin + column * (KEY + KEY_GAP), -(top + row * (KEY + KEY_GAP)))
		button:Show()
	end
	for index = #chars + 1, #board.keys do board.keys[index]:Hide() end
	local rows = math.ceil(#chars / KEYS_PER_ROW)
	local y = top + rows * (KEY + KEY_GAP) + 4
	local x = margin
	for _, button in ipairs(board.extra) do
		local shown = not (numeric and (button == board.caps or button == board.space))
		button:SetShown(shown)
		if shown then
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", board, "TOPLEFT", x, -y)
			x = x + button:GetWidth() + KEY_GAP * 2
		end
	end
	-- (what the left and top buttons do is said under it, as under every window: SwitchHint)
	board:SetSize(width + margin * 2, y + KEY + margin)
	board:SetScale(Skin.Scale and Skin.Scale() or 1)
	board:ClearAllPoints()
	board:SetPoint("TOP", input, "BOTTOM", 0, -8)
	board.capitals = false
	board.Relabel()
	return board, chars
end

-- The keyboard for this line (a line of ours, in a window of ours). False when it cannot be now (a fight).
function Pad.Keyboard(input)
	if not (input and input.SetText) or fighting or InCombatLockdown() then return false end
	local board = Lay(input)
	board.input = input
	if input.HasFocus and input:HasFocus() then input:ClearFocus() end
	Preview(input)
	if board:IsShown() then
		Pad.Refresh(board)
	else
		board:Show()
	end
	-- (the first letter chosen, not the first digit: words come before amounts)
	local first = board.keys[11] and board.keys[11]:IsShown() and board.keys[11] or board.keys[1]
	if first then Pad.Choose(first, board) end
	return true
end
Skin.PadKeyboard = Pad.Keyboard

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

-- A panel of the game's opened after our windows: the controller goes to it, a piece of the screen is left. Closed,
-- it comes back to our last window.
if type(_G.ShowUIPanel) == "function" then
	hooksecurefunc("ShowUIPanel", function(window)
		if not Pad.On() or (window and windows[window]) or fighting or InCombatLockdown() then return end
		if window and not Seen(window) then return end -- (kept out of sight for a window of ours: ours keeps the controller)
		-- (our panel inside that very window keeps the controller it just took)
		if active and window and Inside(active, window) then return end
		for piece in pairs(entered) do Leave(piece) end
		if active then GiveToGame() end
	end)
end
-- A question of the game's shown (and given the controller by the game, a moment later): our keys step aside.
if type(_G.StaticPopup_Show) == "function" then
	hooksecurefunc("StaticPopup_Show", function()
		if not Pad.On() or fighting or InCombatLockdown() then return end
		C_Timer.After(0, function()
			if not fighting and not InCombatLockdown() and not popupUp and GamePopup() then Bindings() end
		end)
	end)
end
if type(_G.HideUIPanel) == "function" then
	hooksecurefunc("HideUIPanel", function()
		if not gameTurn or GameWindow() or fighting or InCombatLockdown() then return end
		gameTurn = false
		Focus(Eligible())
	end)
end

-- The controller's touchpad, free in the game: first into a notice shown (a card saying a guild member wrote: its
-- buttons, its cross), then into Wanderer's bar at the top of the screen, from which every addon of ours opens, then
-- out. The bar turned off: Wanderer's card.
local notices = {} -- frames holding notices (Skin.PadNotice)

function Skin.PadNotice(frame)
	if frame then notices[#notices + 1] = frame end
end

local function NoticeShown()
	for _, frame in ipairs(notices) do
		-- (any size: a notice's own button covers it whole)
		local left, right, top, bottom
		if frame:IsVisible() then left, right, top, bottom = Rect(frame) end
		if left and Walk(frame, frame, math.huge, left, right, top, bottom, {})[1] then return frame end
	end
	return nil
end
local homeOwner = CreateFrame("Frame")
local homeSpot
KeyButton("WandererPadHome", function()
	local bar = _G.WandererBar
	if bar and active == bar then return Leave(bar) end
	local inNotice = active and entered[active] and Holds(notices, active)
	if inNotice then Leave(active) end
	local notice = not inNotice and NoticeShown()
	if notice and Skin.PadEnter(notice, { anySize = true }) then return end
	if bar and bar:IsVisible() and Skin.PadEnter(bar, { anySize = true }) then return end
	if inNotice then return end
	if not homeSpot then
		homeSpot = CreateFrame("Frame", nil, UIParent)
		homeSpot:SetSize(1, 1)
		homeSpot:SetPoint("CENTER")
	end
	if ns.ShowMenu then ns.ShowMenu(homeSpot) end
end)

-- The game's swing timers (main hand, off hand, ranged) are not shown with the controller interface: made invisible
-- only, the layout of the keyboard interface stays as it is, and they come back when the controller's interface goes.
local swingsHidden = {}
local function Swings()
	local manager, kinds = _G.EditModeManagerFrame, Enum and Enum.EditModeSystem
	local list = manager and manager.registeredSystemFrames
	local on = Pad.On()
	if type(list) == "table" and kinds and kinds.SwingTimer then
		for _, frame in ipairs(list) do
			if frame.system == kinds.SwingTimer and on then
				Safe(frame.SetAlpha, frame, 0)
				swingsHidden[frame] = true
			end
		end
	end
	if not on then
		for frame in pairs(swingsHidden) do Safe(frame.SetAlpha, frame, 1) end
		wipe(swingsHidden)
	end
end

-- L1 + R1 + up: the game's shortcut to its list of quests is the top button of its shortcuts bar, pressed through
-- PressActionButton like every button of its bars (the button's own script is written again by the game, a hook on it
-- would not last). That button does nothing when the list is put away: heard here, for the list of ours replacing it.
local trackerAnswer
local trackerHeard = false
local function HearTrackerKey()
	local main = _G.GamepadMainActionBarFrame
	if trackerHeard or not trackerAnswer or not (main and main.PressActionButton) then return end
	trackerHeard = true
	hooksecurefunc(main, "PressActionButton", function(self, index, _, down)
		local unit = self.PageUnit
		local bar = unit and unit.ShortcutsActionBar
		if down and trackerAnswer and bar and unit:GetActiveBar() == bar and bar:GetActionButtonByIndex(index) == bar.dpadTopButton then
			trackerAnswer()
		end
	end)
end

function Skin.PadOnTrackerKey(answer)
	trackerAnswer = answer
	HearTrackerKey()
end

local function HomeKey()
	if fighting or InCombatLockdown() then return end
	HearTrackerKey()
	Safe(ClearOverrideBindings, homeOwner)
	Swings()
	if Pad.On() then Safe(SetOverrideBindingClick, homeOwner, false, "PADSOCIAL", "WandererPadHome") end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "INPUT_DEVICE_INTERFACE_TRANSITION")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then return NoteBlocked(event, ...) end
	if event == "PLAYER_ENTERING_WORLD" then return HomeKey() end
	if event == "PLAYER_REGEN_DISABLED" then
		-- (every key given back before the lock; the marker goes with them, the game's windows are seen again)
		for window in pairs(standing) do StandDown(window) end
		-- (the keyboard cannot be used without our keys: put away, what is written stays)
		if keyboard and keyboard:IsShown() then keyboard:Hide() end
		Safe(ClearOverrideBindings, homeOwner)
		Select(nil)
		active, held = nil, nil
		GameArrow()
		fighting = true
		SwitchHint()
		closer:SetScript("OnUpdate", nil)
		Safe(ClearOverrideBindings, closer)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		fighting = false
		gameTurn = false
		HomeKey()
		return Focus(Eligible())
	end
	-- The controller interface taken or left.
	gameTurn = false
	HomeKey()
	-- (an open settings page follows: its words, its rows shown or not)
	if ns.RefreshSettingsWindow then ns.RefreshSettingsWindow() end
	if ns.RefreshCard then ns.RefreshCard() end
	if ns.RefreshLauncherHint then ns.RefreshLauncherHint() end
	-- (in a fight the keys are the game's: nothing taken nor let go now, the fight's end focuses again)
	if fighting or InCombatLockdown() then return end
	if Pad.On() then return Focus(Eligible()) end
	Select(nil)
	active, held = nil, nil
	closer:SetScript("OnUpdate", nil)
	Safe(ClearOverrideBindings, closer)
end)
