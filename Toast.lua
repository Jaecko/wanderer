local _, ns = ...
local L = ns.L

-- A short notice at the top of the screen, in Wanderer's look: a title and a
-- line of text, shown a few seconds then faded. Never during a fight: it
-- waits for the end of it. A notice may take a click (its action), carry lines
-- that each take one, be checked just before it shows (its cause gone: it is
-- dropped) and have a kind: a right click offers to silence that kind, for
-- good on this character (taken back on the Every day page) or for the
-- session. The same notice again merges with the one shown or waiting ("x3"),
-- and two show at once, the second just under the first. The last ones shown
-- are kept for this session only, in Wanderer's card.

local SHOW_TIME = 8
local FADE = 0.9
local LINE_GAP = 4
local ROW_GAP = 3
-- (its two places, the top and the corner over the bags: Place.lua, movable)
local QUEUE_MAX = 6 -- notices waiting at most (after a long fight: the oldest go)
local MAX_LINES = 5 -- lines of their own a notice may carry
local RECENT_MAX = 10 -- notices kept for the card (this session only)
local DONE_ALPHA = 0.55 -- a line whose action was taken
local SLOTS = 2 -- notices shown at once
local STACK_GAP = 6
local SECOND_ALPHA = 0.85
local ROW_COLOR, ROW_HOVER = { 0.92, 0.92, 0.92 }, { 1, 0.82, 0 }
local MAX_WIDTH = 420 -- its words at most this wide: a longer line wraps (the title is cut, whole under the mouse)

local U = ns.Util

local slots = {} -- the notices' frames: { frame, title, text, kicker, icon, tone, count, rows, notice, ... }
local queue = {}
local recent = {} -- the last notices shown, the newest first
local muted = {} -- kinds silenced for this session

local function LinesOf(notice)
	return notice and notice.lines or {}
end

-- The kinds silenced for good on this character: kind -> its words (the title it had).
local function Lasting()
	if not ns.root then return {} end
	local mine = ns.Mine()
	mine.mutedNotices = type(mine.mutedNotices) == "table" and mine.mutedNotices or {}
	return mine.mutedNotices
end

local function Muted(kind)
	return kind ~= nil and (muted[kind] or Lasting()[kind] ~= nil) or false
end

local function Clickable(notice)
	if not notice then return false end
	if notice.onClick or notice.kind then return true end
	for _, line in ipairs(LinesOf(notice)) do
		if line.onClick then return true end
	end
	return false
end

local function Layout(slot)
	local frame, title, text, kicker, icon = slot.frame, slot.title, slot.text, slot.kicker, slot.icon
	local margin = ns.Skin.Margin()
	local withIcon = icon:IsShown()
	local withKicker = (kicker:GetText() or "") ~= ""
	-- (a notice of one line: no room kept for a second)
	local withText = (text:GetText() or "") ~= ""
	local countWidth = slot.count:IsShown() and slot.count:GetWidth() + 6 or 0
	local titleWidth = U.Measure(title, "GetStringWidth", 120)
	local width = math.max(titleWidth + countWidth, withText and U.Measure(text, "GetStringWidth", 120) or 0,
		withKicker and U.Measure(kicker, "GetStringWidth", 60) or 0)
	for _, row in ipairs(slot.rows) do
		if row:IsShown() then width = math.max(width, U.Measure(row.text, "GetStringWidth", 120) + 2) end
	end
	-- (never wider than MAX_WIDTH: the text and the lines wrap, the title is cut)
	width = math.min(width, MAX_WIDTH)
	title:SetWidth(math.min(titleWidth, width - countWidth))
	-- (a title cut: whole under the mouse, the notice taking the mouse for it)
	slot.titleCut = titleWidth > width - countWidth + 0.5
	frame:EnableMouse(Clickable(slot.notice) or slot.titleCut)
	text:SetWidth(width)
	local height = U.Measure(title, "GetStringHeight", 14)
		+ (withText and (LINE_GAP + U.Measure(text, "GetStringHeight", 12)) or 0)
		+ (withKicker and (U.Measure(kicker, "GetStringHeight", 10) + 2) or 0)
	local shownRows = {}
	for _, row in ipairs(slot.rows) do
		if row:IsShown() then
			local rowWidth = math.min(width, U.Measure(row.text, "GetStringWidth", 120) + 2)
			row:SetWidth(rowWidth)
			-- (its words given their width now, so a line that wraps is measured wrapped)
			row.text:SetWidth(rowWidth - 2)
			local rowHeight = U.Measure(row.text, "GetStringHeight", 12) + 2
			row:SetHeight(rowHeight)
			height = height + (shownRows[1] and ROW_GAP or LINE_GAP) + rowHeight
			shownRows[#shownRows + 1] = row
		end
	end
	local left = margin + (withIcon and 24 + 10 or 0)
	frame:SetSize(width + left + margin + 4, math.max(height, withIcon and 24 or 0) + margin * 2)
	local justify = withIcon and "LEFT" or "CENTER"
	for _, piece in ipairs({ kicker, title, text }) do piece:SetJustifyH(justify) end
	kicker:ClearAllPoints()
	title:ClearAllPoints()
	text:ClearAllPoints()
	-- (centered with its count: the pair at the middle)
	local x = withIcon and left or -countWidth / 2
	local point = withIcon and "TOPLEFT" or "TOP"
	local below = withIcon and "BOTTOMLEFT" or "BOTTOM"
	if withKicker then
		kicker:SetPoint(point, frame, point, withIcon and left or 0, -margin)
		title:SetPoint(point, kicker, below, withIcon and 0 or x, -2)
	else
		title:SetPoint(point, frame, point, x, -margin)
	end
	slot.count:ClearAllPoints()
	slot.count:SetPoint("LEFT", title, "RIGHT", 6, 0)
	text:SetPoint(point, title, below, withIcon and 0 or -x, -LINE_GAP)
	-- The lines, one under the other, below the text (or the title).
	local above, gap = withText and text or title, LINE_GAP
	for index, row in ipairs(shownRows) do
		row.text:SetJustifyH(justify)
		row:ClearAllPoints()
		row:SetPoint(point, above, below, (index == 1 and not withText and not withIcon) and -x or 0, -gap)
		above, gap = row, ROW_GAP
	end
	icon:ClearAllPoints()
	icon:SetPoint("LEFT", frame, "LEFT", margin + 2, 0)
	ns.Skin.Get(frame):Layout()
end

-- Whether it still has something to say, read just before it shows: its kind silenced, its time past, its own
-- check false (or failing): dropped, nothing stale is said.
local function Still(notice)
	-- (asked again from the card: shown, its kind silenced or not)
	if notice.kind and Muted(notice.kind) and not notice.replayed then return false end
	if notice.expires and GetTime() > notice.expires then return false end
	if not notice.still then return true end
	local ok, keep = pcall(notice.still)
	return ok and keep ~= false
end

local function Remember(notice)
	for index, known in ipairs(recent) do
		if known == notice then
			table.remove(recent, index)
			break
		end
	end
	notice.at = time()
	table.insert(recent, 1, notice)
	while #recent > RECENT_MAX do table.remove(recent) end
end

-- Its count beside the title ("x3": the same notice came again).
local function ShowCount(slot)
	local count = slot.notice and slot.notice.count or 1
	slot.count:Set(count > 1 and L.TOAST_COUNT:format(count) or nil, "gold")
end

-- Where a slot shows: the first in its place; the second under it (over it in the corner), or in its own place
-- when the first is in the other one.
local function Place(slot)
	local frame, notice = slot.frame, slot.notice
	local key = notice.corner and "toastCorner" or "toastTop"
	local first = slots[1]
	frame:ClearAllPoints()
	if slot.index > 1 and first.frame:IsShown() and first.notice and (first.notice.corner and true or false) == (notice.corner and true or false) then
		if notice.corner then
			frame:SetPoint("BOTTOMRIGHT", first.frame, "TOPRIGHT", 0, STACK_GAP)
		else
			frame:SetPoint("TOP", first.frame, "BOTTOM", 0, -STACK_GAP)
		end
		return
	end
	-- (where you placed it: Place.lua's placing mode)
	ns.PlaceApply(key, frame)
end

local function Fill(slot, notice)
	notice.replayed = nil
	slot.notice = notice
	local frame = slot.frame
	slot.title:SetText(notice.title)
	slot.text:SetText(notice.text or "")
	slot.kicker:SetText(notice.kicker and U.Upper(notice.kicker) or "")
	slot.icon:SetShown(notice.icon ~= nil)
	if notice.icon then slot.icon:SetTexture(notice.icon) end
	local c = ns.Skin.COLORS[notice.tone or "gold"] or ns.Skin.COLORS.gold
	slot.tone:SetColorTexture(c[1], c[2], c[3], 0.7)
	local lines = LinesOf(notice)
	for index, row in ipairs(slot.rows) do
		local line = lines[index]
		row.line = line
		row:SetShown(line ~= nil)
		row:SetAlpha(1)
		if line then
			row.text:SetText(line.text)
			row:EnableMouse(line.onClick ~= nil or notice.kind ~= nil)
		end
	end
	ShowCount(slot)
	frame:SetScale(ns.Skin.Scale())
	Layout(slot)
	Place(slot)
	slot.shownFor, slot.targetAlpha = 0, 1
	slot.showTime = notice.duration or SHOW_TIME
	slot.peak = slot.index > 1 and SECOND_ALPHA or 1
end

local function ShowNext()
	if InCombatLockdown() then return end
	for _, slot in ipairs(slots) do
		-- (the second only beside a first: never alone where the first should be)
		if not slot.frame:IsShown() and (slot.index == 1 or slots[1].frame:IsShown()) then
			while queue[1] and not Still(queue[1]) do table.remove(queue, 1) end
			if not queue[1] then return end
			local notice = table.remove(queue, 1)
			Fill(slot, notice)
			Remember(notice)
			if notice.onShow then notice.onShow() end
			slot.frame:SetAlpha(0)
			slot.frame:Show()
		end
	end
end

-- (a card of its choices open over it: it waits)
local function Held(frame)
	local card = _G.WandererActionCard
	return card and card:IsShown() and card.owner == frame or false
end

local function OnUpdate(slot, elapsed)
	local frame = slot.frame
	-- (a notice under the mouse that takes a click: it waits for it)
	if not ((Clickable(slot.notice) and frame:IsMouseOver()) or Held(frame)) then slot.shownFor = slot.shownFor + elapsed end
	if slot.shownFor >= slot.showTime then slot.targetAlpha = 0 end
	local target = slot.targetAlpha > 0 and slot.peak or 0
	if ns.Skin.Fade(frame, target, elapsed, FADE, FADE) <= 0 and slot.targetAlpha == 0 then
		frame:Hide()
		slot.notice = nil
		ShowNext()
	end
end

-- A slot's notice, let go now (it fades).
local function Dismiss(slot)
	slot.shownFor, slot.targetAlpha = slot.showTime, 0
end

-- A kind silenced (for good: on this character, its words kept for the list): the ones shown go, those waiting
-- too.
local function Mute(kind, words, lasting)
	if lasting then Lasting()[kind] = tostring(words or kind) else muted[kind] = true end
	for index = #queue, 1, -1 do
		if queue[index].kind == kind then table.remove(queue, index) end
	end
	for _, slot in ipairs(slots) do
		if slot.notice and slot.notice.kind == kind then Dismiss(slot) end
	end
end

-- The mouse over what takes a click: the hand, and what a click does.
-- (its tooltip under the whole notice, never over its other lines)
local function Hint(slot, hint)
	if not slot.notice then return end
	if _G.SetCursor then _G.SetCursor("INTERACT_CURSOR") end
	local any = false
	GameTooltip:SetOwner(slot.frame, "ANCHOR_BOTTOM")
	if slot.titleCut then
		local gold = ns.Skin.COLORS.gold
		GameTooltip:AddLine(slot.title:GetText() or "", gold[1], gold[2], gold[3], true)
		any = true
	end
	if hint then
		GameTooltip:AddLine(hint, 1, 1, 1, true)
		any = true
	end
	if slot.notice.kind then
		GameTooltip:AddLine(L.TOAST_MUTE_HINT, ns.Skin.COLORS.muted[1], ns.Skin.COLORS.muted[2], ns.Skin.COLORS.muted[3], true)
		any = true
	end
	if any then GameTooltip:Show() else GameTooltip:Hide() end
end

local function Unhint()
	if _G.ResetCursor then _G.ResetCursor() end
	GameTooltip:Hide()
end

-- A right click: its kind silenced, for good on this character or for this session (a small card of both).
local function AskMute(slot)
	local notice = slot.notice
	local kind = notice and notice.kind
	if not kind then return end
	local words = notice.kindName or notice.title
	ns.Skin.ActionCard(slot.frame, {
		atCursor = true, width = 250,
		rows = {
			{ text = L.TOAST_MUTE_ALWAYS, glyph = "bell", onClick = function() Mute(kind, words, true) end },
			{ text = L.TOAST_MUTE_SESSION, onClick = function() Mute(kind) end },
		},
		foot = L.TOAST_MUTE_WHERE,
	})
end

-- A click: the action (out of a fight only); a right click offers to silence the kind.
local function OnClick(slot, owner, button, line)
	if not slot.notice or InCombatLockdown() then return end
	if button == "RightButton" then
		if not slot.notice.kind then return end
		Unhint()
		return AskMute(slot)
	end
	-- (a line: the notice stays for the others, this one dimmed)
	if line then
		if not line.onClick then return end
		owner:SetAlpha(DONE_ALPHA)
		return line.onClick()
	end
	if not slot.notice.onClick then return end
	local action = slot.notice.onClick
	Unhint()
	Dismiss(slot)
	action()
end

-- The same notice as one shown or waiting (same kind and title; without a kind, the same words too).
local function Same(a, b)
	if a.title ~= b.title or a.kind ~= b.kind then return false end
	return a.kind ~= nil or (a.text or "") == (b.text or "")
end

-- Merged into the one shown or waiting: its count up, its newest words and actions, its time again.
local function Merge(notice)
	for _, slot in ipairs(slots) do
		local shown = slot.notice
		if shown and slot.frame:IsShown() and slot.targetAlpha > 0 and Same(shown, notice) then
			shown.count = (shown.count or 1) + 1
			shown.text, shown.lines = notice.text, notice.lines or shown.lines
			shown.onClick = notice.onClick or shown.onClick
			Fill(slot, shown)
			slot.frame:SetAlpha(slot.peak)
			return true
		end
	end
	for _, queued in ipairs(queue) do
		if Same(queued, notice) then
			queued.count = (queued.count or 1) + 1
			queued.text, queued.lines = notice.text, notice.lines or queued.lines
			queued.onClick = notice.onClick or queued.onClick
			return true
		end
	end
	return false
end

-- options: duration (seconds shown), onShow (called when it appears, e.g. a
-- sound), corner (bottom right of the screen instead of the top), icon (a texture at its left), tone
-- ("gold", "good", "bad", "warn", "blue": the color of its left edge), kicker (who speaks: "Campfire"),
-- wait (seconds it may wait to be shown, e.g. after a fight; else dropped), onClick (a click on it does
-- this, out of a fight; hint: the words of its tooltip), still (read just before it shows: false drops it),
-- kind (a right click silences the notices of this kind; kindName: their name in the list of silenced ones,
-- else the title), lines ({ { text, onClick, hint } }: lines under its text, each with its own click).
function ns.Toast(noticeTitle, noticeText, options)
	if not slots[1] then return end
	options = options or {}
	if options.kind and Muted(options.kind) then return end
	local lines
	for _, line in ipairs(type(options.lines) == "table" and options.lines or {}) do
		if type(line) == "table" and type(line.text) == "string" and line.text ~= "" and (not lines or #lines < MAX_LINES) then
			lines = lines or {}
			lines[#lines + 1] = { text = line.text, onClick = type(line.onClick) == "function" and line.onClick or nil, hint = line.hint }
		end
	end
	local notice = { title = noticeTitle, text = noticeText, duration = options.duration, onShow = options.onShow,
		corner = options.corner, icon = options.icon, tone = options.tone, kicker = options.kicker,
		expires = options.wait and GetTime() + options.wait,
		onClick = type(options.onClick) == "function" and options.onClick or nil, hint = options.hint,
		still = type(options.still) == "function" and options.still or nil, kind = options.kind,
		kindName = type(options.kindName) == "string" and options.kindName or nil, lines = lines }
	if Merge(notice) then return end
	queue[#queue + 1] = notice
	while #queue > QUEUE_MAX do table.remove(queue, 1) end
	ShowNext()
end

-- A notice of this title on screen or still waiting its turn (one dropped from the queue: no longer).
function ns.ToastWaiting(noticeTitle)
	for _, slot in ipairs(slots) do
		if slot.notice and slot.notice.title == noticeTitle and slot.frame:IsShown() then return true end
	end
	for _, queued in ipairs(queue) do
		if queued.title == noticeTitle and Still(queued) then return true end
	end
	return false
end

-- Recent notices (this session only, nothing saved) --------------------------------------------------------

-- The last notices shown, the newest first: { title, text, lines, onClick, at }.
function ns.RecentNotices() return recent end

-- A notice of the list again: its action, else shown once more (if still true to its cause).
function ns.ReplayNotice(notice)
	if not notice or InCombatLockdown() then return end
	if notice.onClick then return notice.onClick() end
	for index, queued in ipairs(queue) do
		if queued == notice then
			table.remove(queue, index)
			break
		end
	end
	notice.expires, notice.replayed, notice.count = nil, true, nil
	queue[#queue + 1] = notice
	ShowNext()
end

-- Silenced for good (this character) ----------------------------------------------------------------------------

-- The kinds silenced for good: { { kind, words } }, by their words.
function ns.SilencedNotices()
	local list = {}
	for kind, words in pairs(Lasting()) do list[#list + 1] = { kind = kind, words = tostring(words) } end
	table.sort(list, function(a, b) return a.words < b.words end)
	return list
end

function ns.UnsilenceNotice(kind)
	Lasting()[kind] = nil
	muted[kind] = nil
	if ns.RefreshSettingsWindow then ns.RefreshSettingsWindow() end
end

-- The list, beside its button (the Every day page): a click on one takes its silence back.
function ns.ShowSilencedNotices(owner)
	local rows = {}
	for _, entry in ipairs(ns.SilencedNotices()) do
		rows[#rows + 1] = { text = entry.words, right = L.RESTORE, glyph = "bell", hint = L.NOTICES_RESTORE_HINT,
			onClick = function() ns.UnsilenceNotice(entry.kind) end }
	end
	if not rows[1] then return nil end
	return ns.Skin.ActionCard(owner, { title = L.NOTICES_SILENCED, rows = rows, width = 280 })
end

-- The frames ----------------------------------------------------------------------------------------------------

local function MakeSlot(index)
	local Skin = ns.Skin
	local frame = Skin.CreateWindow(index == 1 and "WandererToast" or ("WandererToast" .. index), "DIALOG")
	local slot = { index = index, frame = frame, rows = {}, shownFor = 0, targetAlpha = 0, showTime = SHOW_TIME, peak = 1 }
	ns.PlaceApply("toastTop", frame)
	frame:EnableMouse(false)
	slot.title = Skin.CreateText(frame, "GameTooltipHeaderText", 1, 0.82, 0)
	slot.text = Skin.CreateText(frame, "GameTooltipText", 1, 1, 1)
	slot.kicker = Skin.CreateKicker(frame)
	slot.title:SetJustifyH("CENTER")
	if slot.title.SetWordWrap then slot.title:SetWordWrap(false) end
	slot.text:SetJustifyH("CENTER")
	slot.count = Skin.Chip(frame)
	slot.icon = frame:CreateTexture(nil, "ARTWORK")
	slot.icon:SetSize(24, 24)
	slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	slot.icon:Hide()
	slot.tone = frame:CreateTexture(nil, "ARTWORK")
	slot.tone:SetWidth(2)
	slot.tone:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -6)
	slot.tone:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 6)
	slot.tone:SetColorTexture(1, 0.82, 0, 0.7)
	-- The lines of their own: gold under the mouse when they take a click.
	for line = 1, MAX_LINES do
		local row = CreateFrame("Button", nil, frame)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.text = Skin.CreateText(row, "GameTooltipText", ROW_COLOR[1], ROW_COLOR[2], ROW_COLOR[3])
		row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
		row:SetScript("OnClick", function(self, button) OnClick(slot, self, button, self.line) end)
		row:SetScript("OnEnter", function(self)
			if self.line and self.line.onClick then self.text:SetTextColor(ROW_HOVER[1], ROW_HOVER[2], ROW_HOVER[3]) end
			Hint(slot, self.line and self.line.hint)
		end)
		row:SetScript("OnLeave", function(self)
			self.text:SetTextColor(ROW_COLOR[1], ROW_COLOR[2], ROW_COLOR[3])
			Unhint()
		end)
		row:Hide()
		slot.rows[line] = row
	end
	frame:SetScript("OnMouseUp", function(self, button) OnClick(slot, self, button) end)
	frame:SetScript("OnEnter", function(self)
		if slot.notice and (slot.notice.onClick or slot.notice.kind) then
			Hint(slot, slot.notice.hint)
		elseif slot.notice and slot.titleCut then
			-- (nothing to click: the whole title only, no hand)
			ns.Skin.ShowTip(self, { slot.title:GetText() or "" }, "ANCHOR_BOTTOM")
		end
	end)
	frame:SetScript("OnLeave", Unhint)
	frame.noFadeIn = true
	frame:SetScript("OnUpdate", function(_, elapsed) OnUpdate(slot, elapsed) end)
	return slot
end

function ns.InitToast()
	for index = 1, SLOTS do slots[index] = MakeSlot(index) end
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", ShowNext)
end
