local _, ns = ...

-- A short notice at the top of the screen, in Wanderer's look: a title and a
-- line of text, shown a few seconds then faded. Never during a fight: it
-- waits for the end of it.

local SHOW_TIME = 8
local FADE = 0.9
local LINE_GAP = 4
local TOP_OFFSET = -120
local CORNER_X, CORNER_Y = -40, 160 -- bottom right, over the bags and the menu

local frame, title, text
local queue = {}
local shownFor, targetAlpha = 0, 0
local showTime = SHOW_TIME

local function Layout()
	local margin = ns.Skin.Margin()
	local width = math.max(ns.Util.Measure(title, "GetStringWidth", 120), ns.Util.Measure(text, "GetStringWidth", 120))
	local height = ns.Util.Measure(title, "GetStringHeight", 14) + LINE_GAP + ns.Util.Measure(text, "GetStringHeight", 12)
	frame:SetSize(width + margin * 2, height + margin * 2)
	title:ClearAllPoints()
	title:SetPoint("TOP", frame, "TOP", 0, -margin)
	text:ClearAllPoints()
	text:SetPoint("TOP", title, "BOTTOM", 0, -LINE_GAP)
	ns.Skin.Get(frame):Layout()
end

local function ShowNext()
	if frame:IsShown() or not queue[1] or InCombatLockdown() then return end
	local notice = table.remove(queue, 1)
	frame:ClearAllPoints()
	if notice.corner then
		frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", CORNER_X, CORNER_Y)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, TOP_OFFSET)
	end
	title:SetText(notice.title)
	text:SetText(notice.text or "")
	frame:SetScale(ns.Skin.Scale())
	Layout()
	shownFor, targetAlpha = 0, 1
	showTime = notice.duration or SHOW_TIME
	if notice.onShow then notice.onShow() end
	frame:SetAlpha(0)
	frame:Show()
end

local function OnUpdate(self, elapsed)
	shownFor = shownFor + elapsed
	if shownFor >= showTime then targetAlpha = 0 end
	if ns.Skin.Fade(self, targetAlpha, elapsed, FADE, FADE) <= 0 and targetAlpha == 0 then
		self:Hide()
		ShowNext()
	end
end

-- options: duration (seconds shown), onShow (called when it appears, e.g. a
-- sound), corner (bottom right of the screen instead of the top).
function ns.Toast(noticeTitle, noticeText, options)
	if not frame then return end
	options = options or {}
	queue[#queue + 1] = { title = noticeTitle, text = noticeText, duration = options.duration, onShow = options.onShow,
		corner = options.corner }
	ShowNext()
end

function ns.InitToast()
	frame = ns.Skin.CreateWindow("WandererToast", "DIALOG")
	frame:SetPoint("TOP", UIParent, "TOP", 0, TOP_OFFSET)
	frame:EnableMouse(false)
	title = ns.Skin.CreateText(frame, "GameTooltipHeaderText", 1, 0.82, 0)
	text = ns.Skin.CreateText(frame, "GameTooltipText", 1, 1, 1)
	title:SetJustifyH("CENTER")
	text:SetJustifyH("CENTER")
	frame:SetScript("OnUpdate", OnUpdate)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", ShowNext)
end
