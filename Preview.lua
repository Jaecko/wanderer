local _, ns = ...
local L = ns.L

-- Live preview: while the settings show the label's pages, a sample label
-- stands beside the settings window and follows every change at once (style,
-- font, opacity, spacing, size). Shown only where there is room for it.

local U = ns.Util

local CHECK_EVERY = 0.2
local GAP = 16
local BASE_WIDTH = 230
local LINES = ns.Skin.SAMPLE_LINES

local holder, preview, skin, kicker, watcher, unitFrames
local texts = {}
local since, signature = 0, nil

-- Beside the settings window (panel): on the right, else on the left; false without room.
local function Place(panel, width)
	local right, left, top = panel:GetRight(), panel:GetLeft(), panel:GetTop()
	local screen = UIParent:GetRight() or 0
	if not (right and left and top) then return false end
	-- (the window drawn at its own scale: its sides on the screen's)
	local ratio = (panel:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	right, left = right * ratio, left * ratio
	holder:ClearAllPoints()
	if right + GAP + width <= screen then
		holder:SetPoint("TOPLEFT", panel, "TOPRIGHT", GAP, -40)
	elseif left - GAP - width >= 0 then
		holder:SetPoint("TOPRIGHT", panel, "TOPLEFT", -GAP, -40)
	else
		return false
	end
	return true
end

-- The sample label drawn with the current settings.
local function Draw()
	local db = ns.db.label
	local scale = db.scale or 1
	local margin = 6 + math.floor((db.padding or 8) / 2)
	local font = ns.Skin.FontPath(db.font)
	local width, height = 0, 0
	for index, line in ipairs(LINES) do
		local text = texts[index]
		if font then text:SetFont(font, math.floor(line[2] * scale + 0.5), "") end
		text:SetText(L[line[1]])
		width = math.max(width, U.Measure(text, "GetStringWidth", 100))
		height = height + U.Measure(text, "GetStringHeight", line[2]) + (index > 1 and 2 or 0)
	end
	texts[1]:ClearAllPoints()
	texts[1]:SetPoint("TOPLEFT", preview, "TOPLEFT", margin, -margin)
	preview:SetSize(math.min(width, 400) + margin * 2, height + margin * 2)
	for _, text in ipairs(texts) do text:SetWidth(math.min(width, 400)) end
	skin:SetFixedStyle(db.style, db.bgOpacity)
	skin:Layout()
	holder:SetSize(math.max(preview:GetWidth(), BASE_WIDTH), preview:GetHeight() + 20)
end

local function Signature()
	local db = ns.db.label
	return table.concat({ tostring(db.style), tostring(db.font), tostring(db.bgOpacity), tostring(db.padding),
		tostring(db.scale) }, "|")
end

-- The unit frames' page: their samples instead of the label (UnitFrames.lua draws them with the same engine).
local function DrawUnitFrames()
	if not unitFrames then
		unitFrames = ns.UnitFramesPreview(holder)
		unitFrames:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
	end
	unitFrames:Draw()
	holder:SetSize(math.max(unitFrames:GetWidth(), BASE_WIDTH), unitFrames:GetHeight() + 20)
end

local function OnUpdate(_, elapsed)
	since = since + elapsed
	if since < CHECK_EVERY then return end
	since = 0
	local host = ns.db and ns.SettingsPreviewHost and ns.SettingsPreviewHost()
	-- (a question asked: the preview, above every window, steps aside for it)
	if not host or ns.Skin.Asking() then
		holder:Hide()
		signature = nil
		return
	end
	local kind = ns.SettingsPreviewKind and ns.SettingsPreviewKind() or "label"
	local units = kind == "unitframes" and ns.UnitFramesPreview ~= nil
	local now = units and ("units|" .. (unitFrames and unitFrames:Signature() or "")) or Signature()
	if now ~= signature then
		signature = now
		preview:SetShown(not units)
		if unitFrames then unitFrames:SetShown(units) end
		if units then DrawUnitFrames() else Draw() end
	end
	holder:SetShown(Place(host, holder:GetWidth()))
end

function ns.InitPreview()
	holder = CreateFrame("Frame", "WandererPreview", UIParent)
	holder:SetFrameStrata("FULLSCREEN_DIALOG")
	holder:Hide()
	kicker = ns.Skin.CreateKicker(holder, L.PREVIEW_TITLE)
	kicker:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	preview, skin = ns.Skin.CreateWindow(nil, nil, holder)
	skin.minOpacity = nil -- (the opacity chosen, as it is: the label's look)
	preview:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
	preview:EnableMouse(false)
	local previous
	for index, line in ipairs(LINES) do
		local text = ns.Skin.CreateText(preview, "GameTooltipText", line[3], line[4], line[5])
		if text.SetWordWrap then text:SetWordWrap(false) end
		if previous then text:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2) end
		texts[index] = text
		previous = text
	end
	preview:Show()
	-- Watches only while the settings window is open (SettingsWindow.lua).
	watcher = CreateFrame("Frame", nil, UIParent)
	watcher:SetScript("OnUpdate", OnUpdate)
	watcher:Hide()
end

function ns.WatchPreview(on)
	if not watcher then return end
	since, signature = CHECK_EVERY, nil
	watcher:SetShown(on and true or false)
	if not on then holder:Hide() end
end
