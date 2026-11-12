local _, ns = ...
local L = ns.L
local U = ns.Util

-- "More" on Wanderer's bar: a card under the word with every window of the family, each a line with its icon, its
-- name, its count in gold (a soft dot when something waits there), and a star at its end: gold, the word is on the
-- bar; a click on it pins the window to the bar or takes it off. A click on a line opens its window. The bar keeps
-- only what you use every day; the rest is one click away.

local WIDTH, ROW, ICON = 260, 30, 20

local card, rows = nil, {}
local owner

local function Row(index)
	local row = rows[index]
	if row then return row end
	local Skin = ns.Skin
	local C = Skin.COLORS
	row = CreateFrame("Button", nil, card)
	row:SetHeight(ROW)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, ns.Skin.HOVER)
	row.hover:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
	if not Skin.RoundMask(row, row.icon) then row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	row.text = Skin.Text(row, "GameTooltipText", "text")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.count = Skin.CreateText(row, "GameFontNormalSmall", C.gold[1], C.gold[2], C.gold[3])
	row.dot = row:CreateTexture(nil, "OVERLAY")
	row.dot:SetSize(5, 5)
	row.dot:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
	-- The star: on the bar (gold) or not (faint); a click changes it.
	row.pin = Skin.GlyphButton(row, "star", 13, function(self) return self.on and L.BAR_UNPIN or L.BAR_PIN end, function(self)
		ns.SetBarPin(row.key, not self.on)
	end)
	row.pin:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.count:SetPoint("RIGHT", row.pin, "LEFT", -8, 0)
	row.dot:SetPoint("RIGHT", row.pin, "LEFT", -10, 0)
	row.text:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row:SetScript("OnEnter", function(self) self.hover:Show() end)
	row:SetScript("OnLeave", function(self) self.hover:Hide() end)
	row:SetScript("OnClick", function(self)
		ns.Skin.Play("confirm")
		card:Hide()
		if self.open then pcall(self.open) end
	end)
	rows[index] = row
	return row
end

local function Fill()
	local Skin = ns.Skin
	local margin = Skin.Margin() + 6
	local y = margin + 18 + 6
	local windows = ns.BarWindows()
	for index, window in ipairs(windows) do
		local row = Row(index)
		row.key, row.open = window.key, window.open
		row.icon:SetTexture(window.icon)
		row.text:SetText(window.label)
		local ok, count = pcall(window.count)
		count = ok and tonumber(count) or 0
		row.count:SetText(count > 0 and tostring(count) or "")
		local waits = window.attention and select(2, pcall(window.attention)) == true
		row.dot:SetShown(waits and count == 0 or false)
		local on = ns.BarPinned(window.key)
		row.pin.on = on
		row.pin.role = on and "gold" or "muted"
		row.pin:Tint(row.pin.role)
		row.pin:SetAlpha(on and 1 or 0.6)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", card, "TOPLEFT", margin - 6, -y)
		row:SetPoint("RIGHT", card, "RIGHT", -(margin - 6), 0)
		row:Show()
		y = y + ROW
	end
	for index = #windows + 1, #rows do rows[index]:Hide() end
	card.hint:ClearAllPoints()
	card.hint:SetPoint("TOPLEFT", card, "TOPLEFT", margin, -(y + 8))
	card.hint:SetWidth(WIDTH - margin * 2)
	y = y + 8 + U.Measure(card.hint, "GetStringHeight", 12)
	card:SetSize(WIDTH, y + margin)
	Skin.Get(card):Layout()
end

function ns.RefreshBarMore()
	if card and card:IsShown() then Fill() end
end

-- Under its word on the bar; again: closed.
function ns.ToggleBarMore(word)
	local Skin = ns.Skin
	if not card then
		card = Skin.CreateWindow("WandererBarMore", "DIALOG")
		card:EnableMouse(true)
		card:SetClampedToScreen(true)
		local kicker = Skin.CreateKicker(card, L.BAR_MORE_TITLE)
		kicker:SetPoint("TOPLEFT", card, "TOPLEFT", Skin.Margin() + 6, -(Skin.Margin() + 4))
		card.hint = Skin.Text(card, "GameTooltipTextSmall", "muted")
		card.hint:SetText(L.BAR_MORE_STAR)
		card.hint:SetJustifyH("LEFT")
		if UISpecialFrames then table.insert(UISpecialFrames, "WandererBarMore") end
		if Skin.PadWindow then Skin.PadWindow(card) end
		-- (a click elsewhere, or the mouse gone a while: closed, as the other drawers of the bar)
		card:SetScript("OnUpdate", function(self, elapsed)
			if self:IsMouseOver() or (owner and owner:IsMouseOver()) then
				self.away = 0
			else
				self.away = (self.away or 0) + elapsed
				if self.away > 1.2 and not (U.UsingPad and U.UsingPad()) then self:Hide() end
			end
		end)
	end
	if card:IsShown() then card:Hide() return end
	owner = word
	card.away = 0
	card:SetScale(Skin.Scale())
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", word or UIParent, "BOTTOMLEFT", -8, -4)
	Fill()
	card:Show()
end

function ns.BarMoreCard() return card end -- (tests)
