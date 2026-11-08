local _, ns = ...
local L = ns.L

-- Welcome screen: shown once for each character, on its first arrival in the
-- world with Wanderer. Three choices and it is done: what Wanderer is about
-- (and the key that shows every name), the look, the way you play, then what
-- it sets out with. Further pages wait there for who wants them: a quieter
-- interface, the look of the interface (the bar, the movable windows), what
-- is this character's own (what you play, the profiles by place, the action
-- bars), the extensions. One step at a time, with Back, Next and Not now, and
-- the dots to go straight to a step.
-- A character met after others opens on one choice: like your main character
-- (a copy of its settings, its own from then on) or set up apart.
-- Reopened with /wanderer welcome or from the options.

local U = ns.Util

local WIDTH, HEIGHT = 620, 640
local CREST_SIZE = 44
local CARD_GAP = 10
local ROW_HEIGHT = 46
local DOT_SIZE, DOT_GAP = 8, 8
local MORE_GAP = 10 -- between the dots of the way and the further ones
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local SHOW_DELAY = 2 -- seconds after arriving, once the screen has settled
local SHOW_DELAY_BESIDE = 7 -- with Naowh Forever, after its own first window (it comes at 5)
local AFTER_OTHER = 1 -- seconds after another addon's first window closed
local LIKE_HEIGHT, APART_HEIGHT = 92, 64
local SUMMARY_LINE = 16
-- The way to the road: three choices, then what this character sets out with (READY, where it may end).
local ESSENTIAL = { "intro", "look", "play", "ready" }
local READY = #ESSENTIAL
-- Further, for who wants them: after READY, the extensions' page last (when some are missing).
local MORE = { "interface", "appearance", "character" }
local STEPS = {} -- every page in order (made with the window)
local function BuildSteps()
	for index = #STEPS, 1, -1 do STEPS[index] = nil end
	for _, key in ipairs(ESSENTIAL) do STEPS[#STEPS + 1] = key end
	for _, key in ipairs(MORE) do STEPS[#STEPS + 1] = key end
	if ns.OffersWanted() and ns.MissingExtensions()[1] then STEPS[#STEPS + 1] = "extensions" end
end
local LAYOUT_KEYS = { "stacked", "clean", "blizzard" }
local SMALL_CARD = 56
local REVEAL = "WANDERER_REVEAL" -- the key that shows every name while held
local REVEAL_HEIGHT = 66
local REVEAL_ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"
local HIGHLIGHTS = {
	{ "Interface\\CURSOR\\Point", "WELCOME_HIGHLIGHT_NAMES" },
	{ "Interface\\Icons\\INV_Misc_Note_06", "WELCOME_HIGHLIGHT_SCENES" },
	{ "Interface\\Icons\\INV_Misc_Spyglass_03", "WELCOME_HIGHLIGHT_ITEMS" },
}
-- The quieter interface: options from several pages, gathered for the start.
local INTERFACE = {
	{ "world.gatherIcons", "GATHER_ICONS" },
	{ "travel.enabled", "TRAVEL_ENABLE" },
	{ "scene.enabled", "SCENE_ENABLE" },
}
-- The look of your interface: a quiet bar, the game's windows where you put them (each with a short line here,
-- the whole of it in its tooltip); then the minimap's and the quest tracker's look, one choice of three each, as
-- in the settings (Clean.lua's).
local APPEARANCE = {
	{ "world.bar", "BAR_SHOW", "WELCOME_BAR_DESC" },
	{ "world.moveFrames", "MOVE_FRAMES", "WELCOME_MOVE_FRAMES_DESC" },
}
-- (a choice among a few: its words, its getter by profile, its setter; keys and their words prefix, the looks'
-- by default; yield: its job, greyed as in the settings while another addon does it)
local LOOKS = {
	{ "MINIMAP_LOOK", function(profile) return ns.MinimapLook(profile) end, function(value) ns.SetMinimapLook(value) end,
		yield = "minimapLook" },
	{ "TRACKER_LOOK", function(profile) return ns.TrackerLook(profile) end, function(value) ns.SetTrackerLook(value) end,
		yield = "trackerLook" },
}
-- The fade, one choice of three as in the settings (Cinema.lua's), on the quieter interface's page.
local FADE = { "CINEMA_MODE", function(profile) return ns.FadeMode(profile) end, function(value) ns.SetFadeMode(value) end,
	keys = ns.FADE_CHOICES, words = "CINEMA_MODE_" }
local function LookWords(look, key) return L[(look.words or "LOOK_") .. tostring(key):upper()] end
-- What another character's settings bring, shown before the copy: the switches told, the looks named.
local LIKE_PREVIEW = {
	{ "world.bar", "BAR_SHOW" }, { "world.moveFrames", "MOVE_FRAMES" }, { "scene.enabled", "SCENE_ENABLE" },
}
-- A character's own settings outside its profile, copied with it: where its windows stand, the minimap
-- button, the reminders' size and their opening at login (not its weights or its trade: those are its own).
local MINE_COPIED = { "framePoints", "spots", "minimap", "todoSize", "todoAtLogin" }
local TIPS = {
	{ "Interface\\CURSOR\\Point", "WELCOME_TIP_HOVER" },
	{ "Interface\\Icons\\INV_Misc_Spyglass_02", "WELCOME_TIP_REVEAL" },
	{ "Interface\\Icons\\INV_Misc_Book_09", "WELCOME_TIP_MINIMAP" },
	{ "Interface\\Icons\\INV_Misc_Note_01", "WELCOME_TIP_COMMAND" },
}

-- Seen once by each character (part of what it sets is the character's own). Before 0.45 one mark said it
-- for the whole account: every character known then (by anything Wanderer kept for it) had seen it, and gets
-- the news of the release, never the welcome again.
function ns.Welcomed()
	local root = ns.root
	if not root then return true end
	if root.welcomed then
		local by = type(root.welcomedBy) == "table" and root.welcomedBy or {}
		root.welcomedBy = by
		by[ns.CharacterKey()] = true
		for _, name in ipairs(ns.BY_CHARACTER or {}) do
			if name ~= "welcomedBy" and type(root[name]) == "table" then
				for key in pairs(root[name]) do
					if type(key) == "string" then by[key] = true end
				end
			end
		end
		root.welcomed = nil
	end
	return type(root.welcomedBy) == "table" and root.welcomedBy[ns.CharacterKey()] and true or false
end

function ns.SetWelcomed()
	local root = ns.root
	if not root then return end
	root.welcomedBy = type(root.welcomedBy) == "table" and root.welcomedBy or {}
	root.welcomedBy[ns.CharacterKey()] = true
end

-- Like another character ------------------------------------------------------------------

-- A place's profile for this character, named as Core names them: the place, then its own profile's name.
local PLACE_KINDS = { world = true, city = true, dungeon = true }
local function PlaceName(zone, own)
	return L["PLACE_PROFILE_" .. zone:upper()] .. " (" .. own .. ")"
end

local undo -- what this character had before a copy, while the welcome is open
local copiedFrom -- the name of the character copied

-- Another character's settings copied into this one's own: its profile, its profiles by place (named for this
-- one), where its windows stand. A copy, never a link: changed here, it stays here. Never in a fight.
function ns.CopyCharacterSettings(from)
	local root = ns.root
	local source = ns.CharacterProfile(from)
	local me = ns.CharacterKey()
	if not source or from == me or InCombatLockdown() then return false end
	-- (copied again from another one: from what this character had first)
	if undo then ns.UndoCharacterCopy() end
	local own = ns.OwnProfile()
	local map = ns.PlaceProfiles()
	local mine = ns.Mine()
	-- (kept to be put back while the welcome is open)
	undo = { chosen = root.profileKeys[me], own = own, profiles = { [own] = U.Copy(root.profiles[own]) }, places = U.Copy(map), mine = {} }
	for _, name in ipairs(MINE_COPIED) do undo.mine[name] = U.Copy(mine[name]) end
	local function Keep(name)
		if undo.profiles[name] == nil then undo.profiles[name] = root.profiles[name] and U.Copy(root.profiles[name]) or false end
	end
	root.profiles[own] = U.Copy(root.profiles[source])
	-- The places: each of its profiles copied once (raids and battlegrounds follow the dungeons' copy).
	local theirs = type(root.placeProfiles) == "table" and type(root.placeProfiles[from]) == "table" and root.placeProfiles[from] or {}
	local made = {}
	for zone in pairs(map) do map[zone] = nil end
	local zones = { "world", "city", "dungeon" }
	for zone in pairs(theirs) do
		if not PLACE_KINDS[zone] then zones[#zones + 1] = zone end
	end
	for _, zone in ipairs(zones) do
		local name = theirs[zone]
		if name and root.profiles[name] then
			if not made[name] then
				made[name] = PLACE_KINDS[zone] and PlaceName(zone, own) or (name .. " (" .. own .. ")")
				Keep(made[name])
				root.profiles[made[name]] = U.Copy(root.profiles[name])
			end
			map[zone] = made[name]
		end
	end
	local theirMine = type(root.mine) == "table" and type(root.mine[from]) == "table" and root.mine[from] or {}
	for _, name in ipairs(MINE_COPIED) do mine[name] = U.Copy(theirMine[name]) end
	local who = root.characters and root.characters[from]
	copiedFrom = type(who) == "table" and who.name or from
	ns.SetProfile(own)
	ns.UpdatePlaceProfile()
	-- Its Edit Mode layout, when it was one of Wanderer's the game keeps for each character: made here too.
	local layout = type(root.profiles[own].world) == "table" and root.profiles[own].world.editLayout
	if layout and layout ~= "" and ns.EditModeLayouts and not tContains(ns.EditModeLayouts(), layout) then
		for _, key in ipairs(LAYOUT_KEYS) do
			if ns.LayoutName(key) == layout then ns.MakeLayout(key) end
		end
	end
	ns.RefreshAll()
	ns.RefreshThemeGrids()
	return true
end

-- The copy taken back: this character as it was before (while the welcome is open).
function ns.UndoCharacterCopy()
	if not undo or InCombatLockdown() then return false end
	local root = ns.root
	for name, profile in pairs(undo.profiles) do root.profiles[name] = profile or nil end
	local map = ns.PlaceProfiles()
	for zone in pairs(map) do map[zone] = nil end
	for zone, name in pairs(undo.places) do map[zone] = name end
	local mine = ns.Mine()
	for _, name in ipairs(MINE_COPIED) do mine[name] = undo.mine[name] end
	local chosen = undo.chosen and root.profiles[undo.chosen] and undo.chosen or undo.own
	undo, copiedFrom = nil, nil
	ns.SetProfile(chosen)
	ns.UpdatePlaceProfile()
	ns.RefreshAll()
	ns.RefreshThemeGrids()
	return true
end

local window
local pages, dots = {}, {}
local current = 1
local refreshers = {} -- one per page, run when it shows


-- Pieces --------------------------------------------------------------------------------

-- A choice card: background, golden when chosen, title and up to two lines.
local function Card(parent, title, text, height)
	local card = CreateFrame("Button", nil, parent)
	card:SetHeight(height)
	card.background = card:CreateTexture(nil, "BACKGROUND")
	card.background:SetAllPoints()
	card.hover = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, 0.06)
	card.hover:Hide()
	card.check = card:CreateTexture(nil, "OVERLAY")
	card.check:SetSize(18, 18)
	card.check:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
	ns.Skin.GlyphOn(card.check, "check")
	card.title = ns.Skin.CreateText(card, "GameTooltipText")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
	card.title:SetPoint("RIGHT", card.check, "LEFT", -4, 0)
	if card.title.SetWordWrap then card.title:SetWordWrap(false) end
	card.title:SetText(title)
	card.text = ns.Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.text:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 6)
	card.text:SetJustifyV("TOP")
	if card.text.SetMaxLines then card.text:SetMaxLines(2) end
	card.text:SetText(text)
	-- (card.Preview(): what the choice brings, told in its tooltip before it is made)
	card:SetScript("OnEnter", function(self)
		self.hover:Show()
		if not self.Preview then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		self.Preview()
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function(self)
		self.hover:Hide()
		if self.Preview then GameTooltip:Hide() end
	end)
	function card:SetChosen(chosen)
		if chosen then
			self.background:SetColorTexture(1, 0.82, 0, 0.16)
			self.title:SetTextColor(1, 0.82, 0)
		else
			local c = ns.Skin.COLORS.text
			self.background:SetColorTexture(1, 1, 1, 0.04)
			self.title:SetTextColor(c[1], c[2], c[3])
		end
		self.check:SetShown(chosen)
	end
	return card
end

-- A line of icon and text.
local function IconLine(parent, icon, text, anchor, offset)
	local texture = parent:CreateTexture(nil, "ARTWORK")
	texture:SetSize(18, 18)
	texture:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -offset)
	texture:SetTexture(icon)
	if texture.SetTexCoord and icon:find("Icons") then texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	local line = ns.Skin.Text(parent, "GameTooltipText", "text")
	line:SetPoint("LEFT", texture, "RIGHT", 10, 0)
	line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	if line.SetWordWrap then line:SetWordWrap(false) end
	line:SetText(text)
	return texture, line
end

-- Each page: a title, a line saying what it is for, its content below.
local function Page(step, titleKey, textKey)
	local page = CreateFrame("Frame", nil, window)
	page:SetPoint("TOPLEFT", window.top, "TOPLEFT", 0, 0)
	page:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -(ns.Skin.Margin() + 8), 56)
	page:Hide()
	page.title = ns.Skin.CreateText(page, "GameTooltipHeaderText", 1, 0.82, 0)
	page.title:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	page.title:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	if page.title.SetWordWrap then page.title:SetWordWrap(false) end
	page.title:SetText(L[titleKey])
	page.text = ns.Skin.Text(page, "GameTooltipTextSmall", "soft")
	page.text:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)
	page.text:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.text:SetText(textKey and L[textKey] or "")
	page.rule = page:CreateTexture(nil, "ARTWORK")
	page.rule:SetColorTexture(1, 0.82, 0, 0.2)
	page.rule:SetHeight(1)
	page.rule:SetPoint("TOPLEFT", page.text, "BOTTOMLEFT", 0, -8)
	page.rule:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	pages[step] = page
	return page
end

-- Steps ---------------------------------------------------------------------------------

-- Previews --------------------------------------------------------------------------------

-- A value of a profile by its path ("world.bar").
local function ValueIn(values, path)
	local section, field = U.SplitPath(path)
	if section then return type(values[section]) == "table" and values[section][field] end
	return values[path]
end

local function OnOff(on) return on and L.WELCOME_ON or L.WELCOME_OFF end

-- A tooltip line in two halves (what, then how).
local function Pair(left, right)
	if GameTooltip.AddDoubleLine then
		GameTooltip:AddDoubleLine(left, right, 0.9, 0.88, 0.8, 1, 0.82, 0)
	else
		GameTooltip:AddLine(left .. ": " .. right, 0.9, 0.88, 0.8)
	end
end

-- The character a new one would copy: the one picked, else the main one.
local likeFrom
local function LikeCandidates() return ns.CopyableCharacters() end
local function LikeWho()
	local list = LikeCandidates()
	for _, who in ipairs(list) do
		if who.key == likeFrom then return who, list end
	end
	local main = ns.MainCharacter(list)
	likeFrom = main and main.key
	return main, list
end

-- On a character not welcomed yet, while others have their settings: the choice comes first.
local function OffersLike()
	return not ns.Welcomed() and LikeCandidates()[1] ~= nil
end

local ShowStep

-- The reveal key ------------------------------------------------------------------------------------------
-- Names stay quiet over heads: a key held shows them all. Told on the first page, and set right there (the
-- game's own key binding, saved as the game saves it).

local function RevealKey()
	local key = GetBindingKey and GetBindingKey(REVEAL)
	return type(key) == "string" and key ~= "" and key or nil
end

local function KeyWords(key) return ns.Skin.KeyText(key) end

-- The reveal on this key (as the Keys page sets one: SettingsWindow.lua's ns.SetKey): true, or false and the
-- action the key does already (asked first, as on the Keys page).
function ns.SetRevealKey(key)
	if type(key) ~= "string" or key == "" or InCombatLockdown() then return false end
	local action = GetBindingAction and GetBindingAction(key)
	if type(action) == "string" and action ~= "" and action ~= REVEAL then return false, action end
	return ns.SetKey(REVEAL, key)
end

-- A card: the key told (or none yet), a button to choose it; the next key pressed is the one (Escape: no change).
local function RevealCard(parent, anchor)
	local card = ns.Skin.Panel(parent)
	card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)
	card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	card:SetHeight(REVEAL_HEIGHT)
	local icon = ns.Skin.Icon(card, 34)
	icon:SetPoint("LEFT", card, "LEFT", 12, 0)
	icon:Set(REVEAL_ICON)
	local said
	local button, listener
	local title = ns.Skin.Text(card, "GameTooltipText", "gold")
	local text = ns.Skin.Text(card, "GameTooltipTextSmall", "soft")
	local function Refresh()
		local key = RevealKey()
		title:SetText(key and L.WELCOME_REVEAL_BOUND:format(KeyWords(key)) or L.WELCOME_REVEAL_TITLE)
		local listening = listener and listener:Listening()
		text:SetText(said or (listening and L.WELCOME_REVEAL_PRESS_DESC) or (key and L.WELCOME_REVEAL_BOUND_DESC)
			or L.WELCOME_REVEAL_DESC)
		button:SetText(listening and L.WELCOME_REVEAL_PRESS or (key and L.WELCOME_REVEAL_CHANGE or L.WELCOME_REVEAL_PICK))
		button:Fit()
	end
	button = ns.Skin.Button(card, L.WELCOME_REVEAL_PICK, function()
		said = nil
		-- (keys are never set in a fight)
		if not listener:Listening() and InCombatLockdown() then return ns.Skin.Play("refuse") end
		listener:Set(not listener:Listening())
	end, nil, 120)
	button:SetHeight(26)
	button:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	-- (the kit's listening: Escape, the modifiers, a fight, one at a time; your keys are never taken in a fight)
	listener = ns.Skin.KeyListener(button, { onChange = Refresh, onKey = function(full)
		local done, other = ns.SetRevealKey(full)
		if done then
			said = nil
			ns.Skin.Play("confirm")
		elseif other then
			-- (another action's key: asked first, as on the Keys page)
			ns.Skin.Ask(L.SETTINGS_KEY_TAKEN:format(KeyWords(full), ns.Skin.BindingName(other), ns.Skin.BindingName(REVEAL)), function()
				if ns.SetKey(REVEAL, full) then ns.Skin.Play("confirm") end
				Refresh()
			end)
		else
			ns.Skin.Play("refuse")
		end
		Refresh()
	end })
	-- (the page left, the window closed: what was said goes; the listening stops with the button)
	card:SetScript("OnHide", function() said = nil end)
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 0)
	title:SetPoint("RIGHT", button, "LEFT", -12, 0)
	title:SetJustifyH("LEFT")
	if title.SetWordWrap then title:SetWordWrap(false) end
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	text:SetPoint("RIGHT", button, "LEFT", -12, 0)
	text:SetJustifyH("LEFT")
	if text.SetMaxLines then text:SetMaxLines(2) end
	card.Refresh, card.button = Refresh, button
	Refresh()
	return card
end

local function IntroPage()
	local page = Page("intro", "WELCOME_TITLE")
	page.title:SetFontObject(ns.Skin.FontFor("GameFontNormalHuge"))
	page.title:SetTextColor(1, 0.82, 0)
	page.text:SetFontObject(ns.Skin.FontFor("GameTooltipText"))
	page.text:SetTextColor(unpack(ns.Skin.COLORS.text))
	page.text:SetText(L.WELCOME_INTRO)
	-- The first character: what Wanderer is about.
	local first = CreateFrame("Frame", nil, page)
	first:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", 0, 0)
	first:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
	local previous = page.rule
	for index, line in ipairs(HIGHLIGHTS) do
		previous = IconLine(first, line[1], L[line[2]], previous, index == 1 and 18 or 12)
	end
	local reveal = RevealCard(first, previous)
	-- Another one: like your main character, or set up apart.
	local alt = CreateFrame("Frame", nil, page)
	alt:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", 0, 0)
	alt:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
	local like = Card(alt, "", L.WELCOME_LIKE_DESC, LIKE_HEIGHT)
	like:SetPoint("TOPLEFT", alt, "TOPLEFT", 0, -14)
	like:SetPoint("RIGHT", alt, "RIGHT", 0, 0)
	like.facts = ns.Skin.Text(like, "GameTooltipTextSmall", "muted")
	like.facts:SetPoint("BOTTOMLEFT", like, "BOTTOMLEFT", 10, 8)
	like.facts:SetPoint("RIGHT", like, "RIGHT", -10, 0)
	like.facts:SetJustifyH("LEFT")
	if like.facts.SetWordWrap then like.facts:SetWordWrap(false) end
	like.text:SetPoint("BOTTOMRIGHT", like, "BOTTOMRIGHT", -10, 24)
	like.Preview = function()
		local who = LikeWho()
		local profile = who and ns.root.profiles[ns.CharacterProfile(who.key) or ""]
		if type(profile) ~= "table" then return end
		GameTooltip:AddLine(L.WELCOME_LIKE_TIP:format(who.name), 1, 0.82, 0)
		for _, entry in ipairs(LIKE_PREVIEW) do Pair(L[entry[2]], OnOff(ValueIn(profile, entry[1]))) end
		for _, look in ipairs({ FADE, LOOKS[1], LOOKS[2] }) do Pair(L[look[1]], LookWords(look, look[2](profile))) end
		local places = type(ns.root.placeProfiles) == "table" and ns.root.placeProfiles[who.key]
		Pair(L.WELCOME_PLACES, OnOff(type(places) == "table" and next(places) ~= nil))
		local muted = ns.Skin.COLORS.muted
		GameTooltip:AddLine(L.WELCOME_LIKE_COPY, muted[1], muted[2], muted[3], true)
	end
	like:SetScript("OnClick", function()
		if not likeFrom or not ns.CopyCharacterSettings(likeFrom) then
			ns.Skin.Play("refuse")
			return
		end
		ns.Skin.Play("confirm")
		ShowStep(READY)
	end)
	-- Another one to copy, picked from the list (remembered as your main).
	local pickRow = CreateFrame("Frame", nil, alt)
	pickRow:SetHeight(26)
	pickRow:SetPoint("TOPLEFT", like, "BOTTOMLEFT", 0, -8)
	pickRow:SetPoint("RIGHT", alt, "RIGHT", 0, 0)
	local pickLabel = ns.Skin.Text(pickRow, "GameTooltipTextSmall", "muted")
	pickLabel:SetPoint("LEFT", pickRow, "LEFT", 4, 0)
	if pickLabel.SetWordWrap then pickLabel:SetWordWrap(false) end
	pickLabel:SetText(L.WELCOME_LIKE_PICK)
	local pick = ns.Skin.Dropdown(pickRow, function()
		local choices = {}
		for _, who in ipairs(LikeCandidates()) do
			choices[#choices + 1] = { id = who.key, label = who.level and L.WELCOME_LIKE_ENTRY:format(who.name, who.level) or who.name }
		end
		return choices
	end, function() return likeFrom end, function(key)
		likeFrom = key
		ns.SetMainCharacter(key, true)
		ns.RefreshWelcome()
	end, nil, 160)
	pick:SetHeight(24)
	pick:SetPoint("LEFT", pickLabel, "RIGHT", 10, 0)
	ns.Skin.Tooltip(pick, L.WELCOME_LIKE_PICK_DESC)
	local apart = Card(alt, L.WELCOME_APART, L.WELCOME_APART_DESC, APART_HEIGHT)
	apart:SetScript("OnClick", function()
		ns.Skin.Play("click")
		ShowStep(2)
	end)
	page.like, page.apart, page.pick = like, apart, pick
	refreshers.intro = function()
		local who = OffersLike() and LikeWho()
		first:SetShown(not who)
		alt:SetShown(who and true or false)
		page.text:SetText(who and L.WELCOME_ALT_INTRO or L.WELCOME_INTRO)
		if not who then return reveal.Refresh() end
		like.title:SetText(L.WELCOME_LIKE:format(who.name))
		local facts = {}
		if who.level then facts[#facts + 1] = L.WELCOME_LIKE_LEVEL:format(who.level) end
		if who.seen then facts[#facts + 1] = U.AgoWords(time() - who.seen) end
		like.facts:SetText(table.concat(facts, "  ·  "))
		like:SetChosen(false)
		apart:SetChosen(false)
		pick:Refresh()
		-- (the list only when there is another one to pick)
		local several = #LikeCandidates() > 1
		pickRow:SetShown(several)
		apart:ClearAllPoints()
		apart:SetPoint("TOPLEFT", several and pickRow or like, "BOTTOMLEFT", 0, several and -14 or -CARD_GAP)
		apart:SetPoint("RIGHT", alt, "RIGHT", 0, 0)
	end
end

-- The look: the label's style, then the unit frames' (UnitFrames.lua): offered as cards, nothing chosen for you
-- (the game's own frames until one is picked).
local function LookPage()
	local page = Page("look", "WELCOME_STEP_LOOK", "WELCOME_LOOK_DESC")
	local grid = ns.CreateThemeGrid(page, { columns = 3, cardHeight = 96, quiet = true })
	local caption = ns.Skin.Caps(page, L.WELCOME_UNIT_FRAMES, "kicker")
	caption:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", 0, -12)
	caption:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	local frames = ns.UnitFramesCards and ns.UnitFramesCards(page, { withGame = true, cardHeight = 74 })
	refreshers.look = function()
		local width = page:GetWidth() > 0 and page:GetWidth() or WIDTH - 2 * (ns.Skin.Margin() + 8)
		grid:Layout(page.rule, width, 12)
		grid:Refresh()
		caption:ClearAllPoints()
		caption:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", 0, -(12 + grid:Height() + 14))
		caption:SetPoint("RIGHT", page, "RIGHT", 0, 0)
		-- (another addon drawing the unit frames: nothing offered here)
		local yielded = ns.Yields("unitFrames") ~= nil
		caption:SetShown(frames ~= nil and not yielded)
		if not frames then return end
		for _, card in ipairs(frames.cards) do card:SetShown(not yielded) end
		if yielded then return end
		frames:Layout(caption, width, 8)
		frames:Refresh()
	end
end

-- The way you play: six cards (Playstyles.lua), a click applies one at once (the character is new: nothing
-- asked), another click switches cleanly; keys 1 to 6 too. The panel under them tells the one under the mouse.
local function PlayPage()
	local page = Page("play", "WELCOME_STEP_PLAY", "WELCOME_PLAY_DESC")
	local function Pick(key)
		if ns.ApplyPlaystyle(key) then ns.Skin.Play("click") else ns.Skin.Play("refuse") end
	end
	local grid = ns.CreatePlaystyleGrid(page, {
		keys = true, recommend = true, onPick = Pick,
		-- (the extensions' page, when it is one of the steps)
		onGet = function()
			for index, key in ipairs(STEPS) do
				if key == "extensions" then
					ns.Skin.Play("click")
					return ShowStep(index)
				end
			end
		end,
	})
	page.grid = grid
	-- Keys 1 to 6 pick a card while the page shows; every other key goes on to the game. Out of a fight only.
	local function Listen(on)
		if page.EnableKeyboard then page:EnableKeyboard(on and true or false) end
		if on and page.SetPropagateKeyboardInput then pcall(page.SetPropagateKeyboardInput, page, true) end
	end
	page:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then return end
		local index = not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) and tonumber(key)
		local way = index and ns.PLAYSTYLE_ORDER[index]
		if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, not way) end
		if way then Pick(way) end
	end)
	page:SetScript("OnKeyUp", function(self)
		if not InCombatLockdown() and self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, true) end
	end)
	page:SetScript("OnShow", function() Listen(not InCombatLockdown()) end)
	page:SetScript("OnHide", function() Listen(false) end)
	page:RegisterEvent("PLAYER_REGEN_DISABLED")
	page:RegisterEvent("PLAYER_REGEN_ENABLED")
	page:SetScript("OnEvent", function(self, event) Listen(event == "PLAYER_REGEN_ENABLED" and self:IsShown()) end)
	refreshers.play = function()
		local width = page:GetWidth() > 0 and page:GetWidth() or WIDTH - 2 * (ns.Skin.Margin() + 8)
		grid:Layout(page.rule, width, 10)
	end
end

-- A switch: a quiet row, checked when on; get() and set(on).
local function RowSwitch(page, key, get, set, previous, descKey)
	local row = CreateFrame("Button", nil, page)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == page.rule and -10 or -4)
	row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.hover:Hide()
	-- The kit's check box (the whole row answers the clicks).
	row.check = ns.Skin.Check(row, "", get, set)
	row.check:EnableMouse(false)
	row.check:SetWidth(row.check.box:GetWidth())
	row.check:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -6)
	row.title = ns.Skin.CreateText(row, "GameTooltipText")
	row.title:SetPoint("TOPLEFT", row.check.box, "TOPRIGHT", 10, 1)
	row.title:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.text = ns.Skin.Text(row, "GameTooltipTextSmall", "muted")
	row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	for _, text in ipairs({ row.title, row.text }) do
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	row.title:SetText(L[key])
	row.text:SetText(L[descKey or (key .. "_DESC")])
	function row:Refresh()
		local on = get() and true or false
		self.check:Refresh()
		local c = ns.Skin.COLORS[on and "text" or "soft"]
		self.title:SetTextColor(c[1], c[2], c[3])
	end
	row:SetScript("OnClick", function(self)
		set(not get())
		self:Refresh()
		ns.Skin.Play("click")
	end)
	row:SetScript("OnEnter", function(self)
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L[key])
		GameTooltip:AddLine(L[key .. "_DESC"], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	return row
end

-- A switch bound to a setting of the profile ("world.cleanMinimap").
local function SwitchRow(page, path, key, previous, descKey)
	local section, field = U.SplitPath(path)
	return RowSwitch(page, key, function() return ns.db[section][field] end, function(on)
		ns.ChangeEverywhere(function() ns.db[section][field] = on end)
		ns.RefreshAll()
	end, previous, descKey)
end

-- A look chosen among three (the game's, discreet, Wanderer's style): its name and line at the left, the choices
-- at the right, the one now in gold.
local function LookRow(page, look, previous)
	local row = CreateFrame("Frame", nil, page)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)
	row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	local list = {}
	for _, key in ipairs(look.keys or ns.LOOK_CHOICES) do list[#list + 1] = { key, LookWords(look, key) } end
	row.choices = ns.Skin.Choices(row, list, function(value)
		ns.ChangeEverywhere(function() look[3](value) end)
		ns.RefreshAll()
	end, 26)
	row.choices:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.title = ns.Skin.Text(row, "GameTooltipText", "text")
	row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -7)
	row.title:SetPoint("RIGHT", row.choices, "LEFT", -12, 0)
	row.text = ns.Skin.Text(row, "GameTooltipTextSmall", "muted")
	row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.text:SetPoint("RIGHT", row.choices, "LEFT", -12, 0)
	for _, text in ipairs({ row.title, row.text }) do
		text:SetJustifyH("LEFT")
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	row.title:SetText(L[look[1]])
	row.text:SetText(L[look[1] .. "_DESC"])
	row:EnableMouse(true)
	ns.Skin.Tooltip(row, { L[look[1]], L[look[1] .. "_DESC"] })
	function row:Refresh()
		self.choices:Select(look[2]())
		-- (left to another addon: greyed, its "Done by" line in place of the description)
		local taken = look.yield and ns.YieldText and ns.YieldText(look.yield)
		self:SetAlpha(taken and 0.45 or 1)
		for _, button in ipairs(self.choices.buttons) do button:SetEnabled(not taken) end
		self.text:SetText(taken or L[look[1] .. "_DESC"])
	end
	return row
end

-- The quieter interface: its switches, then the fade's choice of three.
local function InterfacePage()
	local page = Page("interface", "WELCOME_STEP_INTERFACE", "WELCOME_INTERFACE_DESC")
	local rows, previous = {}, page.rule
	for _, entry in ipairs(INTERFACE) do
		previous = SwitchRow(page, entry[1], entry[2], previous)
		rows[#rows + 1] = previous
	end
	rows[#rows + 1] = LookRow(page, FADE, previous)
	refreshers.interface = function()
		for _, row in ipairs(rows) do row:Refresh() end
	end
end

local function AppearancePage()
	local page = Page("appearance", "WELCOME_STEP_APPEARANCE", "WELCOME_APPEARANCE_DESC")
	local rows, previous = {}, page.rule
	for _, entry in ipairs(APPEARANCE) do
		previous = SwitchRow(page, entry[1], entry[2], previous, entry[3])
		rows[#rows + 1] = previous
	end
	for _, look in ipairs(LOOKS) do
		previous = LookRow(page, look, previous)
		rows[#rows + 1] = previous
	end
	refreshers.appearance = function()
		for _, row in ipairs(rows) do row:Refresh() end
	end
end

-- What is this character's own: how you play it, the profiles by place, the layout of the bars and the
-- bars shown (the game keeps an active layout for each character).
local function CharacterPage()
	local page = Page("character", "WELCOME_STEP_CHARACTER", "WELCOME_CHARACTER_DESC")
	local playRow = CreateFrame("Frame", nil, page)
	playRow:SetHeight(26)
	playRow:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", 0, -6)
	playRow:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	local playLabel = ns.Skin.CreateText(playRow, "GameTooltipText")
	playLabel:SetPoint("LEFT", playRow, "LEFT", 6, 0)
	playLabel:SetText(L.PLAY_CHOICE)
	if playLabel.SetWordWrap then playLabel:SetWordWrap(false) end
	local play = ns.Skin.Dropdown(playRow, ns.PlayChoices, function() return ns.PlayChoice() end, function(id) ns.PlayChoice(id) end,
		L.PLAY_CHOICE_PICK, 160, nil, L.PLAY_CHOICE_DESC)
	play:SetHeight(24)
	play:SetPoint("LEFT", playLabel, "RIGHT", 12, 0)
	-- (the profile on its own line under it: two lists side by side would leave the window in some languages)
	local profileRow = CreateFrame("Frame", nil, page)
	profileRow:SetHeight(26)
	profileRow:SetPoint("TOPLEFT", playRow, "BOTTOMLEFT", 0, -4)
	profileRow:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	local profileLabel = ns.Skin.CreateText(profileRow, "GameTooltipText")
	profileLabel:SetPoint("LEFT", profileRow, "LEFT", 6, 0)
	profileLabel:SetText(L.PROFILE)
	if profileLabel.SetWordWrap then profileLabel:SetWordWrap(false) end
	local profile = ns.Skin.Dropdown(profileRow, function()
		local choices = {}
		for _, name in ipairs(ns.ListProfiles()) do choices[#choices + 1] = { id = name, label = name } end
		return choices
	end, function() return ns.profileName end, function(name)
		ns.SetProfile(name)
		ns.RefreshWelcome()
	end, nil, 120, 220, L.PROFILE_DESC)
	profile:SetHeight(24)
	profile:SetPoint("LEFT", profileLabel, "RIGHT", 12, 0)
	local places = RowSwitch(page, "WELCOME_PLACES", function() return next(ns.PlaceProfiles()) ~= nil end, function(on)
		if on then ns.MakePlaceProfiles() else ns.ClearPlaceProfiles() end
	end, profileRow)
	local layoutCaption = ns.Skin.Text(page, "GameTooltipTextSmall", "label")
	layoutCaption:SetPoint("TOPLEFT", places, "BOTTOMLEFT", 6, -8)
	layoutCaption:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	layoutCaption:SetJustifyH("LEFT")
	layoutCaption:SetText(L.SECTION_LAYOUT_BARS)
	if layoutCaption.SetWordWrap then layoutCaption:SetWordWrap(false) end
	local cards = {}
	for index, key in ipairs(LAYOUT_KEYS) do
		local card = Card(page, ns.LayoutName(key), L["LAYOUT_" .. key:upper() .. "_DESC"], SMALL_CARD)
		if card.text.SetMaxLines then card.text:SetMaxLines(1) end
		card.key = key
		card:SetScript("OnClick", function()
			if ns.MakeLayout(key) then ns.Skin.Play("click") end
			for _, other in ipairs(cards) do other:SetChosen(ns.db.world.editLayout == ns.LayoutName(other.key)) end
		end)
		cards[index] = card
	end
	-- (which bars show is the game's own option: said here, the game's settings a click away)
	local barsButton = ns.Skin.SmallButton(page, L.BARS_SHOWN_GAME_BUTTON, function()
		ns.Skin.Play("click")
		ns.OpenGameActionBars()
	end, L.BARS_SHOWN_GAME_DESC)
	barsButton:SetPoint("TOPRIGHT", cards[#cards], "BOTTOMRIGHT", 0, -10)
	local barsCaption = ns.Skin.Text(page, "GameTooltipTextSmall", "label")
	barsCaption:SetText(L.BARS_SHOWN_GAME)
	barsCaption:SetPoint("LEFT", cards[1], "LEFT", 6, 0)
	barsCaption:SetPoint("TOP", barsButton, "TOP", 0, 0)
	barsCaption:SetPoint("BOTTOM", barsButton, "BOTTOM", 0, 0)
	barsCaption:SetPoint("RIGHT", barsButton, "LEFT", -8, 0)
	barsCaption:SetJustifyH("LEFT")
	if barsCaption.SetWordWrap then barsCaption:SetWordWrap(false) end
	refreshers.character = function()
		local width = page:GetWidth() > 0 and page:GetWidth() or WIDTH - 2 * (ns.Skin.Margin() + 8)
		play:Refresh()
		profile:Refresh()
		places:Refresh()
		local cardWidth = math.floor((width - 2 * CARD_GAP) / 3)
		for index, card in ipairs(cards) do
			card:SetWidth(cardWidth)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", layoutCaption, "BOTTOMLEFT", -6 + (index - 1) * (cardWidth + CARD_GAP), -6)
			card:SetChosen(ns.db.world.editLayout == ns.LayoutName(card.key))
		end
	end
end

-- Many missing: one quiet line each (its icon, its name, what it does in a few words, the whole of it in its
-- tooltip), so that all of them fit on the page.
local EXT_COMPACT, EXT_ROW, EXT_ROW_GAP = 4, 30, 4
local function ExtensionRow(page, offer, previous, first)
	local row = ns.Skin.Panel(page)
	row:SetHeight(EXT_ROW)
	row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, first and -12 or -EXT_ROW_GAP)
	row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	local icon = ns.Skin.Icon(row, 22)
	icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	icon:Set(offer.icon, 1)
	local get = ns.Skin.SmallButton(row, L.EXT_GET_BUTTON, function() ns.OfferExtension(offer) end)
	get:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	local text = ns.Skin.Text(row, "GameTooltipTextSmall", "soft")
	text:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	text:SetPoint("RIGHT", get, "LEFT", -10, 0)
	text:SetJustifyH("LEFT")
	if text.SetWordWrap then text:SetWordWrap(false) end
	text:SetText(ns.Skin.Colorize(offer.name, "gold") .. "  " .. L[offer.text .. "_SHORT"])
	row:EnableMouse(true)
	ns.Skin.Tooltip(row, { offer.name, L[offer.text] })
	return row
end

-- The extensions not installed yet: each with its icon, what it does, its address a click away.
local function ExtensionsPage()
	local page = Page("extensions", "WELCOME_STEP_EXTENSIONS", "WELCOME_EXTENSIONS_DESC")
	local previous = page.rule
	local missing = ns.MissingExtensions()
	for index, offer in ipairs(missing) do
		if #missing > EXT_COMPACT then
			previous = ExtensionRow(page, offer, previous, index == 1)
		else
			local card = ns.Skin.Panel(page)
			card:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, index == 1 and -14 or -10)
			card:SetPoint("RIGHT", page, "RIGHT", 0, 0)
			local icon = ns.Skin.Icon(card, 36)
			icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
			icon:Set(offer.icon, 1)
			local name = ns.Skin.Text(card, "GameTooltipText", "gold")
			name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
			name:SetText(offer.name)
			local get = ns.Skin.Button(card, L.EXT_GET_BUTTON, function() ns.OfferExtension(offer) end)
			get:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
			local text = ns.Skin.Text(card, "GameTooltipTextSmall", "soft")
			text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
			text:SetPoint("RIGHT", get, "LEFT", -10, 0)
			text:SetJustifyH("LEFT")
			text:SetText(L[offer.text])
			card:SetHeight(math.max(56, 24 + U.Measure(text, "GetStringHeight", 30) + 16))
			previous = card
		end
	end
end

-- A setting of the active profile ("world.bar").
local function Setting(path) return ValueIn(ns.db, path) end

-- The last step: what this character sets out with (two columns on a soft card), a few words of advice, the
-- options, and while a copy is fresh, a way to take it back.
local function ReadyPage()
	local page = Page("ready", "WELCOME_STEP_READY", "WELCOME_READY_DESC")
	local summary = ns.Skin.Panel(page)
	summary:SetPoint("TOPLEFT", page.rule, "BOTTOMLEFT", 0, -12)
	summary:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	summary:SetHeight(24 + 3 * SUMMARY_LINE + 2 * 6)
	local left = CreateFrame("Frame", nil, summary)
	left:SetPoint("TOPLEFT", summary, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", summary, "BOTTOM", -6, 0)
	local right = CreateFrame("Frame", nil, summary)
	right:SetPoint("TOPLEFT", summary, "TOP", 6, 0)
	right:SetPoint("BOTTOMRIGHT", summary, "BOTTOMRIGHT", 0, 0)
	local lines = {}
	local function Column(column, list)
		local previous
		for _, entry in ipairs(list) do
			local line = ns.Skin.SummaryLine(column, previous, L[entry[1]])
			line.value:SetJustifyH("RIGHT")
			line.label:SetPoint("RIGHT", line.value, "LEFT", -8, 0)
			line.label:SetJustifyH("LEFT")
			for _, text in ipairs({ line.label, line.value }) do
				if text.SetWordWrap then text:SetWordWrap(false) end
			end
			line.Value = entry[2]
			lines[#lines + 1] = line
			previous = line
		end
	end
	Column(left, {
		{ "WELCOME_SUM_LOOK", function()
			local theme = ns.CurrentTheme()
			return theme and L["STYLE_" .. theme:upper()] or L.WELCOME_SUM_CUSTOM
		end },
		{ "WELCOME_SUM_WAY", function()
			if copiedFrom then return L.WELCOME_LIKE:format(copiedFrom) end
			local way = ns.CurrentPlaystyle()
			return way == "" and L.WELCOME_SUM_NONE or ns.PlaystyleWords(way)
		end },
		{ "WELCOME_SUM_LIGHTER", function()
			local on = 0
			for _, entry in ipairs(INTERFACE) do
				if Setting(entry[1]) then on = on + 1 end
			end
			if ns.FadeMode() ~= "none" then on = on + 1 end
			return L.WELCOME_SUM_COUNT:format(on, #INTERFACE + 1)
		end },
	})
	Column(right, {
		{ "BAR_SHOW", function() return OnOff(Setting("world.bar")) end },
		{ "MOVE_FRAMES", function() return OnOff(Setting("world.moveFrames")) end },
		{ "WELCOME_PLACES", function() return OnOff(next(ns.PlaceProfiles()) ~= nil) end },
	})
	local tipsCaption = ns.Skin.Caps(page, L.WELCOME_TIPS)
	tipsCaption:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -16)
	tipsCaption:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	tipsCaption:SetJustifyH("LEFT")
	if tipsCaption.SetWordWrap then tipsCaption:SetWordWrap(false) end
	local previous = tipsCaption
	local revealTip
	for index, tip in ipairs(TIPS) do
		local line
		previous, line = IconLine(page, tip[1], L[tip[2]], previous, index == 1 and 10 or 12)
		if tip[2] == "WELCOME_TIP_REVEAL" then revealTip = line end
	end
	local options = ns.Skin.Button(page, L.WELCOME_OPTIONS, function()
		window:Hide()
		ns.OpenOptions()
	end, nil, 140)
	options:SetHeight(24)
	options:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -20)
	local takeBack = ns.Skin.Button(page, L.WELCOME_UNDO, function()
		if ns.UndoCharacterCopy() then ShowStep(1) end
	end, nil, 120)
	takeBack:SetHeight(24)
	takeBack:SetPoint("LEFT", options, "RIGHT", 8, 0)
	ns.Skin.Tooltip(takeBack, L.WELCOME_UNDO_DESC)
	local later = ns.Skin.Text(page, "GameTooltipTextSmall", "muted")
	later:SetPoint("LEFT", options, "RIGHT", 12, 0)
	later:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	if later.SetWordWrap then later:SetWordWrap(false) end
	later:SetText(L.WELCOME_LATER)
	page.summary, page.takeBack = lines, takeBack
	refreshers.ready = function()
		page.text:SetText(copiedFrom and L.WELCOME_READY_COPIED:format(copiedFrom) or L.WELCOME_READY_DESC)
		for _, line in ipairs(lines) do line.value:SetText(line.Value()) end
		-- (the reveal's key, once chosen: named)
		local key = RevealKey()
		revealTip:SetText(key and L.WELCOME_TIP_REVEAL_BOUND:format(KeyWords(key)) or L.WELCOME_TIP_REVEAL)
		takeBack:SetShown(undo ~= nil)
		later:ClearAllPoints()
		later:SetPoint("LEFT", undo and takeBack or options, "RIGHT", 12, 0)
		later:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	end
end

-- Navigation ----------------------------------------------------------------------------

-- The shown step drawn again (the game said its layouts again).
function ns.RefreshWelcome()
	if not (window and window:IsShown()) then return end
	local refresh = refreshers[STEPS[current]]
	if refresh then refresh() end
end

-- The pages counted on the way (the three choices and the road), the further ones apart, marked fainter.
function ShowStep(step)
	current = math.max(1, math.min(#STEPS, step))
	local further = current > READY
	for index, key in ipairs(STEPS) do
		pages[key]:SetShown(index == current)
		local done = index <= current and (index <= READY or further)
		dots[index].mark:SetColorTexture(1, done and 0.82 or 1, done and 0 or 1, done and 0.9 or (index > READY and 0.15 or 0.25))
	end
	local refresh = refreshers[STEPS[current]]
	if refresh then refresh() end
	window.back:SetShown(current > 1)
	-- The road (or the last further page): setting out closes; from the road, the further pages for who wants them.
	local ends = current == READY or current == #STEPS
	window.next:SetText(ends and L.WELCOME_START or L.WELCOME_NEXT)
	window.more:SetShown(current == READY and #STEPS > READY)
	window.skip:SetShown(not ends)
	window.skip:SetLabel(further and L.WELCOME_DONE or L.WELCOME_SKIP)
	window.counter:SetText(further and L.WELCOME_MORE_COUNT:format(current - READY, #STEPS - READY)
		or L.WELCOME_STEP_COUNT:format(current, READY))
end

-- (seen: marked once it hides, whatever closed it)
local function Close()
	window:Hide()
end

local function FooterButton(text, onClick, main)
	local button = ns.Skin.Button(window, text, onClick, main and "main" or nil, 110)
	button:SetHeight(26)
	return button
end

local function CreateWindow()
	window = ns.Skin.CreateWindow("WandererWelcome", "DIALOG")
	window:SetSize(WIDTH, HEIGHT)
	ns.Skin.Dress(window, nil, nil, Close)
	local margin = ns.Skin.Margin() + 8

	-- The crest and the name, on every step.
	local crest = window:CreateTexture(nil, "ARTWORK")
	crest:SetSize(CREST_SIZE, CREST_SIZE)
	crest:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	crest:SetTexture(ICON)
	local ring = window:CreateTexture(nil, "BORDER")
	ring:SetSize(CREST_SIZE + 4, CREST_SIZE + 4)
	ring:SetPoint("CENTER", crest, "CENTER")
	ring:SetTexture("Interface\\Buttons\\WHITE8X8")
	ring:SetVertexColor(1, 0.82, 0, 0.55)
	ns.Skin.RoundMask(window, crest)
	ring:SetShown(ns.Skin.RoundMask(window, ring))
	local name = ns.Skin.CreateText(window, "GameTooltipHeaderText", 1, 0.82, 0)
	name:SetPoint("LEFT", crest, "RIGHT", 12, 6)
	name:SetPoint("RIGHT", window, "RIGHT", -40, 0)
	if name.SetWordWrap then name:SetWordWrap(false) end
	name:SetText(L.ADDON_TITLE)
	window.counter = ns.Skin.Text(window, "GameTooltipTextSmall", "muted")
	window.counter:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	window.counter:SetPoint("RIGHT", window, "RIGHT", -40, 0)
	window.top = CreateFrame("Frame", nil, window)
	window.top:SetSize(1, 1)
	window.top:SetPoint("TOPLEFT", crest, "BOTTOMLEFT", 0, -16)

	BuildSteps()
	IntroPage()
	LookPage()
	PlayPage()
	ReadyPage()
	InterfacePage()
	AppearancePage()
	CharacterPage()
	if tContains(STEPS, "extensions") then ExtensionsPage() end

	-- Progress dots (each one names its step and goes straight to it) and the way forward.
	for index, key in ipairs(STEPS) do
		local dot = CreateFrame("Button", nil, window)
		dot:SetSize(DOT_SIZE + DOT_GAP, DOT_SIZE + DOT_GAP)
		-- (the further pages a little apart, their dots smaller)
		local further = index > READY
		dot:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT",
			margin - DOT_GAP / 2 + (index - 1) * (DOT_SIZE + DOT_GAP) + (further and MORE_GAP or 0), margin + 9 - DOT_GAP / 2)
		dot.mark = dot:CreateTexture(nil, "ARTWORK")
		dot.mark:SetSize(further and DOT_SIZE - 2 or DOT_SIZE, further and DOT_SIZE - 2 or DOT_SIZE)
		dot.mark:SetPoint("CENTER", dot, "CENTER", 0, 0)
		dot:SetScript("OnClick", function()
			if index ~= current then
				ns.Skin.Play("click")
				ShowStep(index)
			end
		end)
		ns.Skin.Tooltip(dot, function() return pages[key].title:GetText() end, "ANCHOR_TOP")
		dots[index] = dot
	end
	window.next = FooterButton(L.WELCOME_NEXT, function()
		if current == READY or current == #STEPS then Close() else ShowStep(current + 1) end
	end)
	window.next:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	window.back = FooterButton(L.WELCOME_BACK, function() ShowStep(current - 1) end)
	window.back:SetPoint("RIGHT", window.next, "LEFT", -8, 0)
	-- From the road: the further pages.
	window.more = FooterButton(L.WELCOME_MORE, function() ShowStep(READY + 1) end)
	window.more:SetPoint("RIGHT", window.back, "LEFT", -8, 0)
	ns.Skin.Tooltip(window.more, L.WELCOME_MORE_DESC, "ANCHOR_TOP")
	-- (a real button, quiet, in line with Back and Next)
	window.skip = ns.Skin.SmallButton(window, L.WELCOME_SKIP, Close, nil, 26)
	window.skip:SetPoint("LEFT", dots[#STEPS], "RIGHT", 16, 0)

	-- Seen once closed by you; hidden with the whole interface (a new character's opening film, the screen
	-- hidden by the game), it is still to come: it shows again with the interface.
	window:HookScript("OnHide", function(self)
		if self:IsShown() then return end
		ns.SetWelcomed()
		-- (a copy kept: no taking it back once closed)
		undo, copiedFrom = nil, nil
	end)
	window:HookScript("OnShow", function(self)
		-- On a small screen (or a large interface scale), the window shrinks to fit.
		self:SetScale(ns.Skin.FitScale(self))
		-- (the extensions no more suggested, or all installed since the window was made: their page goes, its dot too)
		if STEPS[#STEPS] == "extensions" and not (ns.OffersWanted() and ns.MissingExtensions()[1]) then
			pages.extensions:Hide()
			dots[#STEPS]:Hide()
			STEPS[#STEPS] = nil
			self.skip:ClearAllPoints()
			self.skip:SetPoint("LEFT", dots[#STEPS], "RIGHT", 16, 0)
		end
		ShowStep(1)
	end)
	ns.Skin.Get(window):Layout()
end

function ns.ShowWelcome()
	if not ns.root or InCombatLockdown() then return end
	if not window then CreateWindow() end
	if window:IsShown() then ShowStep(1) else window:Show() end
end

-- Another addon's first window (Naowh Forever's, Spoken's), open now: ours waits until it closes.
local NAOWH_WINDOW_KEY = "setupWindow"
local naowhWindow
function ns.OtherWelcome()
	local spoken = _G.SpokenWelcomeFrame
	if type(spoken) == "table" and spoken.IsShown and spoken:IsShown() then return spoken end
	if not _G.NaowhForever then return nil end
	if not naowhWindow then
		-- (its window has no name: known by the place it keeps, among the screen's windows)
		local ok, found = pcall(function()
			for _, child in ipairs({ UIParent:GetChildren() }) do
				if child.positionKey == NAOWH_WINDOW_KEY then return child end
			end
		end)
		naowhWindow = ok and found or nil
	end
	if naowhWindow and naowhWindow:IsShown() then return naowhWindow end
end

-- fn run now, or a moment after the other addon's first window has closed.
local waiting = {}
function ns.AfterOtherWelcome(fn)
	local other = ns.OtherWelcome()
	if not other then return fn() end
	if not waiting[other] then
		waiting[other] = {}
		other:HookScript("OnHide", function(self)
			local list = waiting[self]
			waiting[self] = {}
			C_Timer.After(AFTER_OTHER, function()
				for _, later in ipairs(list) do ns.AfterOtherWelcome(later) end
			end)
		end)
	end
	table.insert(waiting[other], fn)
end

function ns.InitWelcome()
	if ns.Welcomed() then return end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- Never over a fight, nor over another addon's first window: it waits for the next quiet moment.
	local function Due()
		return not ns.Welcomed() and not (window and window:IsShown())
	end
	frame:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		if ns.Welcomed() then return end
		C_Timer.After(_G.NaowhForever and SHOW_DELAY_BESIDE or SHOW_DELAY, function()
			if not Due() then return end
			if InCombatLockdown() then
				self:RegisterEvent("PLAYER_REGEN_ENABLED")
				return
			end
			ns.AfterOtherWelcome(function()
				if not Due() then return end
				if InCombatLockdown() then
					self:RegisterEvent("PLAYER_REGEN_ENABLED")
				else
					ns.ShowWelcome()
				end
			end)
		end)
	end)
end
