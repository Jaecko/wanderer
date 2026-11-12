local _, ns = ...
local L = ns.L

-- Professions, quietly followed: each point gained is said by a short notice
-- (several in a row: one notice, "Mining rises to 75", "+3"). Herbalism and
-- Mining also say what the new rank reaches ("Now within reach: Tin Ore"),
-- named by the game's items, so in your language. A profession at its
-- ceiling (75, 150, 225) is said once: a trainer teaches the next rank. Only events: nothing runs
-- between them.

local U = ns.Util

local SKILL_WAIT = 3 -- seconds: points gained in a row make one notice

-- What a gathering skill reaches: { item, skill needed }, the classic world's herbs and ores (public game
-- facts; to verify in game on Forever).
local GATHERING = {
	[182] = { -- Herbalism
		{ 2447, 1 }, { 765, 1 }, { 2449, 15 }, { 785, 50 }, { 2450, 70 }, { 3820, 85 }, { 2453, 100 },
		{ 3355, 115 }, { 3369, 120 }, { 3356, 125 }, { 3357, 150 }, { 3818, 160 }, { 3821, 170 }, { 3358, 185 },
		{ 3819, 195 }, { 4625, 205 }, { 8831, 210 }, { 8836, 220 }, { 8838, 230 }, { 8839, 235 }, { 8845, 245 },
		{ 8846, 250 }, { 13464, 260 }, { 13463, 270 }, { 13465, 280 }, { 13466, 285 }, { 13467, 290 }, { 13468, 300 },
	},
	[186] = { -- Mining
		{ 2770, 1 }, { 2771, 65 }, { 2775, 75 }, { 2772, 125 }, { 2776, 155 }, { 3858, 175 }, { 7911, 230 },
		{ 11370, 230 }, { 10620, 245 },
	},
}

-- A rank's ceiling with a next rank after it: the level a trainer asks for that next rank (the classic world's;
-- to verify in game on Forever).
local CEILINGS = { [75] = 10, [150] = 20, [225] = 35 }
local CEILING_WAIT = 10 -- seconds after login: the arrival's own notices first

local ranks = {} -- profession name -> its rank
local lines = {} -- profession name -> its skill line
local rising = {} -- profession name -> rank before the points gained in a row
local risingToken = 0

local function Settings()
	local db = ns.db
	return db and db.enabled and db.crafts or nil
end

-- What a gathering skill reaches from one rank to the next: the items' ids (nothing for other professions).
function ns.NewlyGathered(line, from, to)
	local found = {}
	for _, entry in ipairs(GATHERING[line] or {}) do
		if entry[2] > from and entry[2] <= to then found[#found + 1] = entry[1] end
	end
	return found
end

-- Their names, in your language (the ones the game has not loaded yet left out).
local function ReachLine(line, from, to)
	local names = {}
	for _, id in ipairs(ns.NewlyGathered(line, from, to)) do names[#names + 1] = U.ItemName(id) end
	return names[1] and L.CRAFT_GATHER_REACH:format(table.concat(names, ", ")) or nil
end

-- Points gained: one notice for the points of a row.
local function SayRise()
	local settings = Settings()
	for name, from in pairs(rising) do
		local to = ranks[name]
		if to and to > from then
			local parts = {}
			if to - from > 1 then parts[1] = L.CRAFT_SKILL_GAIN:format(to - from) end
			local reach = settings and settings.gatherReach ~= false and ReachLine(lines[name], from, to) or nil
			parts[#parts + 1] = reach
			-- (the points alone are the game's to say: a notice for them only when asked)
			if settings and (settings.skillUps or reach) then ns.Toast(L.CRAFT_SKILL_UP:format(name, to), parts[1] and table.concat(parts, "\n") or nil,
				{ duration = reach and 4 or 2.5, corner = true }) end
		end
	end
	wipe(rising)
end

-- A profession at its ceiling --------------------------------------------------------------------------------

-- Each profession's ceiling now: name -> { most, primary (one of your two trades) }.
local function Ceilings()
	local found = {}
	for _, known in ipairs(U.Professions()) do
		if known.most then found[known.name] = { most = known.most, primary = known.primary } end
	end
	return found
end

-- The ceilings already told to this character: skill line (or name) -> the highest told.
local function Told()
	local root = ns.root
	if not root then return {} end
	local key = ns.CharacterKey()
	root.craftCeilings = type(root.craftCeilings) == "table" and root.craftCeilings or {}
	root.craftCeilings[key] = type(root.craftCeilings[key]) == "table" and root.craftCeilings[key] or {}
	return root.craftCeilings[key]
end

-- At its ceiling with a next rank to learn: said once for each ceiling (a trade: the level the trainer asks,
-- when not reached yet; the others are also taught by books).
local function SayCeilings()
	local settings = Settings()
	if not (settings and settings.ceiling ~= false) then return end
	local ceilings, told = Ceilings(), Told()
	for _, known in ipairs(U.Professions()) do
		local ceiling = ceilings[known.name]
		local most = ceiling and ceiling.most
		local id = known.line or known.name
		local title = most and L.CRAFT_CEILING:format(known.name, most)
		-- (seen only once really shown: one dropped from the queue is said again; one waiting not asked twice)
		if most and CEILINGS[most] and known.rank >= most and (tonumber(told[id]) or 0) < most
			and not (ns.ToastWaiting and ns.ToastWaiting(title)) then
			local text
			if not ceiling.primary then
				text = L.CRAFT_CEILING_BOOK
			elseif (U.Clean(U.Safe(UnitLevel, "player")) or 0) < CEILINGS[most] then
				text = L.CRAFT_CEILING_LEVEL:format(CEILINGS[most])
			else
				text = L.CRAFT_CEILING_TEXT
			end
			local name = known.name
			ns.Toast(title, text, { icon = known.icon, corner = true, duration = 6, kind = "craftCeiling",
				onShow = function()
					local seen = Told()
					if (tonumber(seen[id]) or 0) < most then seen[id] = most end
				end,
				-- (learned meanwhile: nothing to say)
				still = function() local now = Ceilings()[name] return now ~= nil and now.most == most end })
		end
	end
end
local ceilingsAtLogin = U.Debounce(CEILING_WAIT, SayCeilings)
local ceilingsSoon = U.Debounce(SKILL_WAIT + 1, SayCeilings)

local function ReadRanks(first)
	for _, known in ipairs(U.Professions()) do
		local name, rank = known.name, known.rank
		if name and rank then
			local before = ranks[name]
			if not first and before and rank > before then
				local settings = Settings()
				if settings and (settings.skillUps or settings.gatherReach ~= false) then
					rising[name] = rising[name] or before
					-- (the names of what it reaches asked now, ready when the notice comes)
					for _, id in ipairs(ns.NewlyGathered(known.line, before, rank)) do U.LoadItem(id) end
					risingToken = risingToken + 1
					local token = risingToken
					C_Timer.After(SKILL_WAIT, function() if token == risingToken then SayRise() end end)
				end
			end
			ranks[name] = rank
			lines[name] = known.line
		end
	end
	-- (the points' own notice first; at login, after the arrival's)
	if first then ceilingsAtLogin() else ceilingsSoon() end
end

-- The profession's rank in its window --------------------------------------------------------------------------
-- The professions window sometimes comes without its rank bar on Forever: the rank said under its title then
-- ("Leatherworking 8 / 75", a thin gold bar), and only then (the game's own bar shown: nothing of ours).

local rankLine

local function GameRankShown(window)
	local page = window.CraftingPage
	local bar = page and page.RankBar
	return bar and U.Clean(U.Safe(bar.IsVisible, bar)) and true or false
end

-- The profession shown: its name, rank and ceiling (the game's window first, else your professions by name).
local function ShownRank()
	local ui = C_TradeSkillUI
	local info = ui and ui.GetBaseProfessionInfo and U.Safe(ui.GetBaseProfessionInfo)
	if type(info) == "table" then
		local name, rank, top = U.Clean(info.professionName), U.Clean(info.skillLevel), U.Clean(info.maxSkillLevel)
		if name and rank and top and top > 0 then return name, rank, top end
	end
	local title = _G.ProfessionsFrame and _G.ProfessionsFrame.GetTitleText and U.Safe(_G.ProfessionsFrame.GetTitleText, _G.ProfessionsFrame)
	local shown = title and U.Clean(U.Safe(title.GetText, title))
	for _, known in ipairs(U.Professions()) do
		local name, top = known.name, known.most
		if shown and shown:find(name, 1, true) and top and top > 0 then return name, known.rank, top end
	end
end

local function DrawRank()
	local window = _G.ProfessionsFrame
	if not (rankLine and window and window:IsShown()) then return end
	local name, rank, top = ShownRank()
	-- (Wanderer off: nothing of ours on the game's window)
	if not name or GameRankShown(window) or not (ns.db and ns.db.enabled) then
		rankLine:Hide()
		return
	end
	rankLine.text:SetText(L.CRAFT_RANK_LINE:format(name, rank, top))
	rankLine.bar:SetMinMaxValues(0, top)
	rankLine.bar:SetValue(math.min(rank, top))
	rankLine:Show()
end

-- (Wanderer switched off or on, the window open: the line follows at once)
ns.RefreshCrafts = DrawRank

local function BuildRankLine()
	local window = _G.ProfessionsFrame
	if rankLine or not window then return end
	rankLine = CreateFrame("Frame", nil, window)
	rankLine:SetSize(260, 26)
	rankLine:SetPoint("TOPLEFT", window, "TOPLEFT", 66, -60)
	rankLine:SetFrameLevel(window:GetFrameLevel() + 10)
	rankLine.text = ns.Skin.CreateText(rankLine, "GameFontNormalSmall", ns.Skin.RGB("gold"))
	rankLine.text:SetPoint("TOPLEFT")
	local bar = CreateFrame("StatusBar", nil, rankLine)
	bar:SetPoint("TOPLEFT", rankLine.text, "BOTTOMLEFT", 0, -3)
	bar:SetSize(220, 6)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(ns.Skin.RGB("gold", 0.85))
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.45)
	rankLine.bar = bar
	rankLine:Hide()
	window:HookScript("OnShow", function() C_Timer.After(0, DrawRank) end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function() C_Timer.After(0, DrawRank) end)
end

function ns.InitCrafts()
	-- (the professions window loads with the game's own addon: the line made then)
	if _G.ProfessionsFrame then BuildRankLine() else _G.Wanderer.WhenLoaded("Blizzard_Professions", BuildRankLine) end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("SKILL_LINES_CHANGED")
	frame:SetScript("OnEvent", function(_, event) ReadRanks(event == "PLAYER_LOGIN") end)
	ReadRanks(true)
end
