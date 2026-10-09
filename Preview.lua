local _, ns = ...
local L = ns.L

-- Live preview: while the options show the label's pages, a sample label
-- stands beside the options window and follows every change at once (style,
-- font, opacity, spacing, size). Shown only where there is room for it.

local U = ns.Util

local CHECK_EVERY = 0.2
local GAP = 16
local BASE_WIDTH = 230
local LINES = ns.Skin.SAMPLE_LINES

local holder, preview, skin, kicker
local texts = {}
local since, signature = 0, nil

-- The page the options window shows, whatever this version of the game calls it.
local function CurrentCategory()
	local panel = SettingsPanel
	if not panel then return end
	if panel.GetCurrentCategory then
		local ok, current = pcall(panel.GetCurrentCategory, panel)
		if ok and current then return current end
	end
	local list = panel.GetCategoryList and panel:GetCategoryList()
	if list and list.GetCurrentCategory then
		local ok, current = pcall(list.GetCurrentCategory, list)
		if ok then return current end
	end
end

-- Beside the options window: on the right, else on the left; nil without room.
local function Place(width)
	local panel = SettingsPanel
	local right, left, top = panel:GetRight(), panel:GetLeft(), panel:GetTop()
	local screen = UIParent:GetRight() or 0
	if not (right and left and top) then return false end
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

local function OnUpdate(_, elapsed)
	since = since + elapsed
	if since < CHECK_EVERY then return end
	since = 0
	local wanted = ns.db and SettingsPanel and SettingsPanel:IsShown()
		and ns.PREVIEW_CATEGORIES[CurrentCategory() or false]
	if not wanted then
		holder:Hide()
		signature = nil
		return
	end
	local now = Signature()
	if now ~= signature then
		signature = now
		Draw()
	end
	holder:SetShown(Place(holder:GetWidth()))
end

function ns.InitPreview()
	holder = CreateFrame("Frame", "WandererPreview", UIParent)
	holder:SetFrameStrata("FULLSCREEN_DIALOG")
	holder:Hide()
	kicker = ns.Skin.CreateKicker(holder, L.PREVIEW_TITLE)
	kicker:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	preview, skin = ns.Skin.CreateWindow(nil, nil, holder)
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
	-- Watches only while the options window is open.
	local watcher = CreateFrame("Frame", nil, UIParent)
	watcher:SetScript("OnUpdate", OnUpdate)
	watcher:Hide()
	if SettingsPanel and SettingsPanel.HookScript then
		SettingsPanel:HookScript("OnShow", function() since = CHECK_EVERY watcher:Show() end)
		SettingsPanel:HookScript("OnHide", function() watcher:Hide() holder:Hide() signature = nil end)
	end
end
