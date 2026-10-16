local _, ns = ...

-- The quest tracker in Wanderer's hand (option, offered at the welcome): the same tracker of the game, in its place, with its clicks,
-- its quest items and its icons (to follow, to hand in), only dressed differently, on nothing (no band, no
-- ground: the world shows through). Its headers in small golden capitals over a fine golden rule fading out;
-- the quests in Wanderer's soft beige, their level in the quest log's color; the objectives paler, their
-- count brighter at the end, the dash before them a quiet golden mark, a done one faded; every word with a
-- soft shadow to stay readable on any ground; the fold buttons quiet until the mouse comes. Sizes stay the
-- game's (its layout counts on them). The game builds its tracker again at each change: dressed again each
-- time (its drawings and the quests' events heard, nothing on a timer). Switched off, the game draws it as before.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "ScenarioObjectiveTracker",
	"AchievementObjectiveTracker", "BonusObjectiveTracker", "WorldQuestObjectiveTracker",
	"ProfessionsRecipeTracker", "MonthlyActivitiesObjectiveTracker", "AdventureObjectiveTracker" }
local TITLE = { 0.88, 0.85, 0.77 }
local OBJECTIVE = { 0.66, 0.62, 0.55 }
local DONE = { 0.42, 0.4, 0.36 }
local COUNT = "|cffe0d6bc" -- an objective's count, brighter
local FOLD_REST = 0.45 -- the fold buttons, at rest

local rules = {} -- header -> its golden rule
local headerText = {} -- header text -> the game's words (given back)
local dressed = setmetatable({}, { __mode = "k" }) -- texts given a shadow (given back)
local folds = setmetatable({}, { __mode = "k" }) -- fold buttons made quiet
local dashes = setmetatable({}, { __mode = "k" }) -- objectives' dashes -> the game's color (given back)
local ready = false

local function On()
	return ns.db and ns.db.enabled and ns.db.world.styledTracker and ObjectiveTrackerFrame and true or false
end

local Part = U.Part

-- Its color, and a soft shadow under it (readable on a bright ground, with nothing behind).
local function Ink(text, c)
	if not (text and text.SetTextColor) then return end
	text:SetTextColor(c[1], c[2], c[3])
	if text.SetShadowColor then
		text:SetShadowColor(0, 0, 0, 0.95)
		text:SetShadowOffset(1, -1)
		dressed[text] = true
	end
end

-- A fold button (the "-" and "+"): quiet at rest, clear under the mouse.
local function Fold(button)
	if not (button and button.SetAlpha) then return end
	if not folds[button] and button.HookScript then
		folds[button] = true
		button:HookScript("OnEnter", function(self) if On() then self:SetAlpha(1) end end)
		button:HookScript("OnLeave", function(self) if On() then self:SetAlpha(FOLD_REST) end end)
	end
	if not (button.IsMouseOver and button:IsMouseOver()) then button:SetAlpha(FOLD_REST) end
end

-- A header: its words in capitals and gold, the game's band gone, a fine golden rule under the words.
local function Header(header, main)
	local text = Part(header, "Text")
	if not text then return end
	local words = Clean(Safe(text.GetText, text))
	if words and words ~= "" then
		local upper = U.Upper(words)
		if words ~= upper then
			headerText[text] = words
			text:SetText(upper)
		end
	end
	local C = ns.Skin.COLORS
	Ink(text, main and C.label or C.gold)
	local ground = Part(header, "Background")
	if ground and ground.SetAlpha then ground:SetAlpha(0) end
	Fold(Part(header, "MinimizeButton"))
	if main then return end
	local rule = rules[header]
	if not rule then
		rule = header:CreateTexture(nil, "ARTWORK")
		rule:SetHeight(1)
		rule:SetWidth(170)
		rule:SetColorTexture(1, 1, 1, 1)
		if CreateColor and rule.SetGradient then
			rule:SetGradient("HORIZONTAL", CreateColor(C.gold[1], C.gold[2], C.gold[3], 0.55), CreateColor(C.gold[1], C.gold[2], C.gold[3], 0))
		else
			rule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.3)
		end
		rules[header] = rule
	end
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
	rule:Show()
end

local function Byte(v) return math.floor(v * 255 + 0.5) end

-- A quest's title: Wanderer's beige, its level ("[24]") in the quest log's color.
local function Title(text)
	local words = Clean(Safe(text.GetText, text))
	Ink(text, TITLE)
	if not words then return end
	local level, rest = words:match("^%[(%d+)%](.*)$")
	if level then
		local r, g, b = ns.World.LevelColor(tonumber(level), true)
		text:SetText(("|cff%02x%02x%02x[%s]|r%s"):format(Byte(r), Byte(g), Byte(b), level, rest))
	end
end

-- An objective: paler words, its count ("3/8") brighter at the end; done ("8/8"), faded whole.
local function Objective(text, dash)
	local words = Clean(Safe(text.GetText, text)) or ""
	local have, need = words:match("(%d+)%s*/%s*(%d+)")
	local done = have and tonumber(have) >= tonumber(need)
	Ink(text, done and DONE or OBJECTIVE)
	if have and not done and not words:find("|c", 1, true) then
		text:SetText((words:gsub("(%d+%s*/%s*%d+)", COUNT .. "%1|r", 1)))
	end
	-- (the dash before it: a quiet golden mark)
	if dash and dash.SetTextColor then
		if not dashes[dash] then dashes[dash] = { dash:GetTextColor() } end
		local C = ns.Skin.COLORS
		dash:SetTextColor(C.gold[1], C.gold[2], C.gold[3], done and 0.3 or 0.6)
	end
end

-- Every block of a module, however deep: a title (HeaderText), objective lines (a Text beside a Dash).
local function Dress(frame, depth)
	if depth > 6 or not (frame and frame.GetChildren) then return end
	local title = Part(frame, "HeaderText")
	if title and title.GetText then Title(title) end
	local text = Part(frame, "Text")
	local dash = Part(frame, "Dash")
	if text and text.GetText and (dash or Part(frame, "Icon") or frame.objectiveKey) then Objective(text, dash) end
	for _, child in ipairs({ frame:GetChildren() }) do Dress(child, depth + 1) end
end

local function DressAll()
	if not On() then return end
	Header(Part(ObjectiveTrackerFrame, "Header") or {}, true)
	for _, name in ipairs(MODULES) do
		local module = _G[name]
		if type(module) == "table" and module.IsShown and module:IsShown() then
			Header(Part(module, "Header") or {}, false)
			Dress(Part(module, "ContentsFrame") or module, 0)
		end
	end
end

function ns.RefreshTrackerLook()
	if not ready then return end
	if On() then
		DressAll()
		return
	end
	for _, rule in pairs(rules) do rule:Hide() end
	for text, words in pairs(headerText) do text:SetText(words) end
	wipe(headerText)
	-- (each text its font's own shadow again; the fold buttons as the game has them)
	for text in pairs(dressed) do
		local font = text.GetFontObject and text:GetFontObject()
		if font then text:SetFontObject(font) end
	end
	for button in pairs(folds) do button:SetAlpha(1) end
	for dash, color in pairs(dashes) do dash:SetTextColor(unpack(color)) end
	wipe(dashes)
	-- (the game draws its tracker again, its own colors; the discreet tracker hides its bands again)
	if ObjectiveTrackerFrame and ObjectiveTrackerFrame.Update then Safe(ObjectiveTrackerFrame.Update, ObjectiveTrackerFrame) end
	if ns.RefreshClean then ns.RefreshClean() end
end

function ns.InitTrackerLook()
	local tracker = ObjectiveTrackerFrame
	if not tracker then return end
	-- Dressed again after the game's drawings: once, at the end of the frame, however many of its parts redrew.
	local pending = false
	local function Again()
		if pending or not On() then return end
		pending = true
		C_Timer.After(0, function()
			pending = false
			DressAll()
		end)
	end
	if tracker.Update then hooksecurefunc(tracker, "Update", Again) end
	for _, name in ipairs(MODULES) do
		local module = _G[name]
		if type(module) == "table" and type(module.Update) == "function" then hooksecurefunc(module, "Update", Again) end
	end
	-- (and when quests change or the world loads: heard, never looked at on a timer)
	local soon = U.Debounce(0.1, function() if On() then DressAll() end end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", soon)
	ready = true
	ns.RefreshTrackerLook()
end
