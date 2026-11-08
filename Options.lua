local _, ns = ...
local L = ns.L

-- Wanderer's settings, declared once: each page, its sections and its rows (a switch, a slider, a list, a
-- button), drawn by Wanderer's own settings window (SettingsWindow.lua). Options that only matter when
-- another one is on sit under it, greyed while it is off. Getters always read ns.db, the active profile,
-- so switching profiles only needs a refresh.
-- Each setting is also registered with the game's settings (a proxy setting, by page), out of its panel:
-- the game's own panel shows a single page that opens Wanderer's window.

local HAS_GAME = Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting and true or false
local mainCategory -- the game's first page (never added to its panel)
local category, layout -- the game's page being filled
local settings = {}
-- The pages, in order: { key, name, group ("wanderer", "extensions", "more"), rows, preview, addon }.
-- A row: { kind ("header", "check", "slider", "dropdown", "button"), label, desc, get, set, parent, isOn,
-- yield, partial, page, section, initializer (the game's) }.
ns.SETTINGS_PAGES = {}
-- Each option's words ({ label, page, order, format, choices }) by its variable and, when known, by its path in
-- the profile ("label.scale"): "What you changed" (Changes.lua) names the settings with them.
ns.OPTION_WORDS = { variables = {}, paths = {} }

-- How a page reads, the same for all of them (Wanderer's and the extensions'): first the switch that turns the
-- feature on, then the few rows most players want, then two or three sections at most (appearance, then the
-- automations, off by default), the rest folded under "More settings".
--
-- Header(text, { advanced = true }): the rows after it, up to the next Header, are less used. The window draws
-- them at the bottom of the page, folded under one quiet "More settings" row (a click unfolds them, remembered
-- for this character); the search still finds them, unfolding the page. An older Wanderer ignores the table:
-- the rows are simply shown.

local page, pageName, sectionName
local advanced = false -- the rows declared now are folded (an advanced section)
local order = 0

local function AddRow(row)
	row.page, row.section = page, sectionName
	row.advanced = advanced or nil
	page.rows[#page.rows + 1] = row
	return row
end

local function Header(text, options)
	sectionName = text
	advanced = type(options) == "table" and options.advanced and true or false
	if layout then layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end
	return AddRow({ kind = "header", label = text })
end

-- Starts a page: the home page first, then the others (folded under it in the game's settings).
local function Page(name, key, group)
	pageName, sectionName, advanced = name, nil, false
	page = { key = key, name = name, group = group or "wanderer", rows = {} }
	ns.SETTINGS_PAGES[#ns.SETTINGS_PAGES + 1] = page
	if not HAS_GAME then return page end
	if not mainCategory then
		category, layout = Settings.RegisterVerticalLayoutCategory(name)
		mainCategory = category
	elseif Settings.RegisterVerticalLayoutSubcategory then
		category, layout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, name)
	end
	return page
end

local function Button(label, text, tooltip, onClick)
	local row = AddRow({ kind = "button", label = label, text = text, desc = tooltip, onClick = onClick })
	if layout and CreateSettingsButtonInitializer then
		row.initializer = CreateSettingsButtonInitializer(label, text, onClick, tooltip, true)
		layout:AddInitializer(row.initializer)
	end
	return row
end

-- A shortcut of the home page (never found by the search, never in the game's settings): a button doing
-- something (onClick), or a setting of another page shown here too (Mirror: its variable, filled once every
-- page is declared, see LinkMirrors).
local function Shortcut(label, text, desc, onClick)
	return AddRow({ kind = "button", label = label, text = text, desc = desc, onClick = onClick, shortcut = true })
end

local function Mirror(variable, label, desc)
	return AddRow({ kind = "mirror", mirrorOf = variable, label = label, desc = desc, shortcut = true })
end

-- Each mirror takes its setting's control and value; one not found (a page missing) is left out.
local function LinkMirrors()
	local byVariable = {}
	for _, each in ipairs(ns.SETTINGS_PAGES) do
		for _, row in ipairs(each.rows) do
			if row.variable then byVariable[row.variable] = row end
		end
	end
	for _, each in ipairs(ns.SETTINGS_PAGES) do
		for index = #each.rows, 1, -1 do
			local row = each.rows[index]
			if row.kind == "mirror" then
				local source = byVariable[row.mirrorOf]
				if source then
					for _, field in ipairs({ "kind", "get", "set", "choices", "min", "max", "step", "text", "parent", "isOn", "yield", "partial" }) do
						row[field] = source[field]
					end
					row.label, row.desc = row.label or source.label, row.desc or source.desc
				else
					table.remove(each.rows, index)
				end
			end
		end
	end
end

-- Shows an option under another one, greyed out while isOn() is false.
local function Under(row, parent, isOn)
	if not (type(row) == "table" and type(parent) == "table") then return row end
	row.parent, row.isOn = parent, isOn
	if row.initializer and parent.initializer and row.initializer.SetParentInitializer then
		row.initializer:SetParentInitializer(parent.initializer, isOn)
	end
	return row
end

-- A setting changed: in every profile of this character (ns.ChangeEverywhere). Registered with the game too.
local function Proxy(variable, varType, label, default, getter, setter)
	local set = function(value) ns.ChangeEverywhere(function() setter(value) end) end
	local setting
	if HAS_GAME then
		setting = Settings.RegisterProxySetting(category, "WANDERER_" .. variable, varType, label, default, getter, set)
		settings[#settings + 1] = setting
	end
	-- (its words and page, for "What you changed": Changes.lua)
	order = order + 1
	ns.OPTION_WORDS.variables[variable] = { label = label, page = pageName, order = order }
	return setting, set
end

-- An option whose job another addon may do (Compat.lua): greyed while it does, with who does it, and found
-- by that addon's name too. partial: only part of the job is left to it (the option stays usable). job: one
-- job, or a list of jobs (any of them left to another addon greys it).
local function Yield(row, job, partial)
	if type(row) == "table" then row.yield, row.partial = job, partial end
	return row
end

-- An option that only works while another one is on, maybe another addon's (isOn(): it is; words: what it
-- needs, named as its own page names it): greyed while it is off, "Needs: words" under it.
local function Needs(row, isOn, words)
	if type(row) == "table" and type(isOn) == "function" then row.needs = { isOn = isOn, words = words } end
	return row
end

-- Every control returns its row (to put other options under it).
local function Checkbox(variable, label, tooltip, default, getter, setter)
	local setting, set = Proxy(variable, HAS_GAME and Settings.VarType.Boolean, label, default, getter, setter)
	local row = AddRow({ kind = "check", variable = variable, label = label, desc = tooltip, get = getter, set = set })
	if setting then row.initializer = Settings.CreateCheckbox(category, setting, tooltip) end
	return row
end

-- choices: list of { value, label }, or a function returning it.
local function Dropdown(variable, label, tooltip, default, choices, getter, setter)
	local setting, set = Proxy(variable, HAS_GAME and Settings.VarType.String, label, default, getter, setter)
	ns.OPTION_WORDS.variables[variable].choices = choices
	local row = AddRow({ kind = "dropdown", variable = variable, label = label, desc = tooltip, get = getter, set = set,
		choices = choices })
	if setting then
		row.initializer = Settings.CreateDropdown(category, setting, function()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
				container:Add(choice[1], choice[2])
			end
			return container:GetData()
		end, tooltip)
	end
	return row
end

-- One choice written in several settings of the profile (a dropdown with a getter): its paths named by its
-- words, and read(profile) gives the choice, so "What you changed" shows one line, in the choice's words
-- (Changes.lua).
local function Composite(variable, read, paths)
	local words = ns.OPTION_WORDS.variables[variable]
	if not words then return end
	words.read = read
	for _, path in ipairs(paths) do ns.OPTION_WORDS.paths[path] = words end
end

-- A value as a slider says it (its format: a pattern, or a function).
local function SliderText(format, value)
	if type(format) == "function" then return tostring(format(value)) end
	return format:format(value)
end

-- Slider bound to a number of a sub-table of the profile ("label.scale"),
-- with the bounds shared with the checks of saved settings (ns.RANGES).
local function Slider(variable, label, path, format, onChange)
	local section, key = ns.Util.SplitPath(path)
	local min, max, step = unpack(ns.RANGES[path])
	local getter = function() return ns.db[section][key] end
	local setting, set = Proxy(variable, HAS_GAME and Settings.VarType.Number, label, ns.DEFAULTS[section][key], getter,
		function(value)
			ns.db[section][key] = value
			if onChange then onChange() end
		end)
	local words = ns.OPTION_WORDS.variables[variable]
	words.format, ns.OPTION_WORDS.paths[path] = format, words
	local row = AddRow({ kind = "slider", variable = variable, label = label, get = getter, set = set, min = min, max = max,
		step = step, text = function(value) return SliderText(format, value) end })
	if setting then
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, row.text)
		row.initializer = Settings.CreateSlider(category, setting, options)
	end
	return row
end

-- Checkbox bound to a key of a sub-table of the active profile.
local function TableCheckbox(tableName, key, label, tooltip, onChange)
	local variable = tableName:upper() .. "_" .. key:upper()
	local row = Checkbox(variable, label, tooltip, ns.DEFAULTS[tableName][key],
		function() return ns.db[tableName][key] and true or false end,
		function(value)
			ns.db[tableName][key] = value
			if onChange then onChange() end
		end)
	ns.OPTION_WORDS.paths[tableName .. "." .. key] = ns.OPTION_WORDS.variables[variable]
	return row
end

local function LabelCheckbox(key, label, tooltip)
	return TableCheckbox("label", key, label, tooltip, ns.RefreshLabel)
end

-- isOn() for an option of the profile: section.key.
local function IsOn(section, key)
	return function() return ns.db and ns.db[section][key] and true or false end
end

function ns.RefreshOptions()
	for _, setting in ipairs(settings) do
		if setting.NotifyUpdate then pcall(setting.NotifyUpdate, setting) end
	end
	if ns.RefreshSettingsWindow then ns.RefreshSettingsWindow() end
end

-- Profile dialogs -----------------------------------------------------------------

local function UniqueName(base)
	local name, i = base, 2
	while ns.root.profiles[name] do
		name = ("%s %d"):format(base, i)
		i = i + 1
	end
	return name
end

-- A Pawn scale pasted; a profile pasted; the profile reset; the profile deleted: each asked first.
local function ImportScale()
	ns.Skin.AskText(L.UPGRADE_IMPORT_PROMPT, "", function(text)
		local ok, result = ns.ImportPawnScale(text)
		ns.Print(ok and L.UPGRADE_IMPORT_DONE:format(result.name) or result)
		ns.RefreshWeights()
	end, 0)
end

local function ImportProfileAsk()
	ns.Skin.AskText(L.PROFILE_IMPORT_PROMPT, "", function(text)
		local ok, err = ns.ImportProfile(text, UniqueName(L.PROFILE_IMPORTED))
		ns.Print(ok and L.IMPORT_DONE:format(ns.profileName) or err)
	end, 0)
end

local function ResetAsk()
	ns.Skin.Ask(L.RESET_PROFILE_PROMPT:format(ns.profileName), function() ns.ResetProfile() end)
end

local function DeleteAsk()
	ns.Skin.Ask(L.PROFILE_DELETE_PROMPT:format(ns.profileName or ""), function()
		if not ns.DeleteProfile(ns.profileName) then ns.Print(L.PROFILE_DELETE_OWN) end
	end)
end

-- Pages ------------------------------------------------------------------------------

-- Before another window opens in their place: the settings step aside (Wanderer's window and the game's).
local function CloseSettings()
	if ns.CloseSettingsWindow then ns.CloseSettingsWindow() end
	if not (SettingsPanel and SettingsPanel:IsShown()) then return end
	if SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel)
	elseif HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
end
ns.CloseSettings = CloseSettings

local function HomePage()
	Page(L.ADDON_TITLE, "home")
	Checkbox("ENABLED", L.ENABLE, L.ENABLE_DESC, true,
		function() return ns.db.enabled end,
		function(value) ns.SetEnabled(value) end)

	-- Start here: the choices that change the most, each also on its own page.
	Header(L.SECTION_START)
	Shortcut(L.PAGE_THEMES, L.START_CHOOSE, L.START_STYLE_DESC, function() ns.OpenOptions("themes") end)
	-- (the way of this character on its button: its name, "Customised" or none yet)
	Shortcut(L.PAGE_PLAYSTYLES, function() return ns.PlaystyleWords() end, L.START_PLAYSTYLE_DESC, function() ns.OpenOptions("playstyles") end)
	Mirror("PRESET", L.SECTION_NAMES, L.PRESET_DESC)
	TableCheckbox("world", "bar", L.BAR_SHOW, L.BAR_SHOW_DESC, function() ns.SetBarShown(ns.db.world.bar) end)
	Checkbox("MINIMAP", L.MINIMAP_BUTTON, L.MINIMAP_HINT, true,
		function() return ns.IsMinimapButtonShown() end,
		function(value) ns.SetMinimapButtonShown(value) end)
	Mirror("WORLD_MOVEFRAMES")
	Shortcut(L.PLACING_TITLE, L.PLACING_BUTTON, L.START_PLACE_DESC, function()
		CloseSettings()
		ns.PlaceMode()
	end)
	Button(L.WELCOME_SHOW, L.WELCOME_SHOW_BUTTON, L.WELCOME_SHOW_DESC, function()
		-- (the settings step aside: the welcome screen takes their place)
		CloseSettings()
		ns.ShowWelcome()
	end)

	-- (the extensions not installed yet: in the sidebar, a page each, see FinishOptions; this character can stop
	-- them there and have them back here)
	Checkbox("EXT_SUGGEST", L.EXT_SUGGEST, L.EXT_SUGGEST_DESC, true,
		function() return ns.OffersWanted() end,
		function(value)
			ns.SetOffersWanted(value)
			if ns.RefreshSettingsNav then ns.RefreshSettingsNav() end
		end)
end

-- The predefined styles: cards with previews, drawn by the window (Themes.lua). (no rows: the game keeps
-- its name only)
local function ThemesPage()
	pageName, sectionName, advanced = L.PAGE_THEMES, nil, false
	ns.SETTINGS_PAGES[#ns.SETTINGS_PAGES + 1] = { key = "themes", name = L.PAGE_THEMES, group = "wanderer", rows = {} }
	if mainCategory and Settings.RegisterCanvasLayoutSubcategory then
		Settings.RegisterCanvasLayoutSubcategory(mainCategory, CreateFrame("Frame"), L.PAGE_THEMES)
	end
end

-- The ways to play: the cards of Playstyles.lua, drawn by the window (no rows either).
local function PlaystylesPage()
	pageName, sectionName, advanced = L.PAGE_PLAYSTYLES, nil, false
	ns.SETTINGS_PAGES[#ns.SETTINGS_PAGES + 1] = { key = "playstyles", name = L.PAGE_PLAYSTYLES, group = "wanderer", rows = {} }
	if mainCategory and Settings.RegisterCanvasLayoutSubcategory then
		Settings.RegisterCanvasLayoutSubcategory(mainCategory, CreateFrame("Frame"), L.PAGE_PLAYSTYLES)
	end
end

-- The names over the heads: a preset, who shows in a fight and near you; one by one; by place (folded).
local function NamesPage()
	Page(L.PAGE_NAMES, "names")
	local presetChoices = {}
	for _, preset in ipairs(ns.PRESET_ORDER) do
		presetChoices[#presetChoices + 1] = { preset, L["PRESET_" .. preset:upper()] }
	end
	Dropdown("PRESET", L.PRESET, L.PRESET_DESC, "immersion", presetChoices,
		function() return ns.db.preset end,
		function(value) if value ~= "custom" then ns.SetPreset(value) end end)
	Checkbox("COMBAT_ENEMIES", L.COMBAT_ENEMIES, L.COMBAT_ENEMIES_DESC, ns.DEFAULTS.combatEnemies,
		function() return ns.db.combatEnemies end,
		function(value) ns.db.combatEnemies = value; ns.Apply() end)
	local enemyChoices = {}
	for _, choice in ipairs(ns.ENEMY_NAMES) do enemyChoices[#enemyChoices + 1] = { choice, L["ENEMY_NAMES_" .. choice:upper()] } end
	local enemyNames = Yield(Dropdown("ENEMY_NAMES", L.ENEMY_NAMES, L.ENEMY_NAMES_DESC, "names", enemyChoices,
		function() return ns.db.enemyNames end,
		function(value)
			ns.db.enemyNames = value
			ns.Apply()
			ns.RefreshPlates()
		end), "nameplates", true)
	local near = function() return ns.db.enemyNames == "near" end
	Under(Yield(Dropdown("NEAR_SHOW", L.NEAR_SHOW, L.NEAR_SHOW_DESC, "bar", { { "bar", L.NEAR_SHOW_BAR }, { "name", L.NEAR_SHOW_NAME } },
		function() return ns.db.nearNames.show end,
		function(value)
			ns.db.nearNames.show = value
			ns.RefreshPlates()
		end), "nameplates"), enemyNames, near)
	Under(Yield(Slider("NEAR_DISTANCE", L.NEAR_DISTANCE, "nearNames.distance", L.NEAR_DISTANCE_FORMAT, ns.Apply), "nameplates"),
		enemyNames, near)
	-- (written on the plates Wanderer keeps invisible: left with them to a nameplate addon)
	Yield(Checkbox("GROUP_MARKS", L.GROUP_MARKS, L.GROUP_MARKS_DESC, true,
		function() return ns.db.groupMarks end,
		function(value) ns.db.groupMarks = value; ns.RefreshPlates() end), "nameplates")
	Yield(Checkbox("GUILD_MARKS", L.GUILD_MARKS, L.GUILD_MARKS_DESC, true,
		function() return ns.db.guildMarks end,
		function(value) ns.db.guildMarks = value; ns.RefreshPlates() end), "nameplates")
	Yield(Checkbox("KNOWN_MARKS", L.KNOWN_MARKS, L.KNOWN_MARKS_DESC, false,
		function() return ns.db.knownMarks end,
		function(value)
			ns.db.knownMarks = value
			if value and ns.LearnGroupAcquaintances then ns.LearnGroupAcquaintances() end
			if ns.PlatesForget then ns.PlatesForget() end
			ns.RefreshPlates()
		end), "nameplates")
	Dropdown("REVEAL_MODE", L.REVEAL_MODE, L.REVEAL_DESC, "hold",
		{ { "hold", L.REVEAL_HOLD }, { "toggle", L.REVEAL_TOGGLE } },
		function() return ns.db.revealMode end,
		function(value) ns.db.revealMode = value; ns.SetRevealing(false) end)

	-- Only the categories this game client supports.
	Header(L.SECTION_NAMES_EACH)
	for _, cat in ipairs(ns.CATEGORIES) do
		if ns.IsCategoryAvailable(cat) then
			local key = cat.key
			Checkbox("SHOW_" .. key:upper(), L["CAT_" .. key], L.CAT_DESC, false,
				function() return ns.db.show[key] and true or false end,
				function(value)
					ns.db.show[key] = value
					ns.db.preset = "custom"
					ns.Apply()
					ns.RefreshOptions()
				end)
		end
	end

	Header(L.SECTION_ZONES, { advanced = true })
	local zoneChoices = {}
	for _, choice in ipairs(ns.ZONE_CHOICES) do
		zoneChoices[#zoneChoices + 1] = { choice, choice == "default" and L.ZONE_DEFAULT or L["PRESET_" .. choice:upper()] }
	end
	for _, zone in ipairs(ns.ZONES) do
		Dropdown("ZONE_" .. zone:upper(), L["ZONE_" .. zone:upper()], L.ZONE_DESC, ns.DEFAULTS.zones[zone], zoneChoices,
			function() return ns.db.zones[zone] end,
			function(value) ns.db.zones[zone] = value; ns.Apply() end)
	end
end

-- A line of the label's content: set alone, the level becomes "custom".
local function ContentCheckbox(key, label, tooltip)
	return TableCheckbox("label", key, label, tooltip, function()
		ns.db.label.content = "custom"
		ns.RefreshLabel()
		ns.RefreshOptions()
	end)
end

-- The label: what it says and where, its look, its lights and alert; its lines one by one (folded).
local function LabelPage()
	Page(L.PAGE_LABEL, "label")
	page.preview = true
	local labelOn = IsOn("label", "enabled")
	local enabled = LabelCheckbox("enabled", L.LABEL_ENABLE, L.LABEL_ENABLE_DESC)
	-- Three levels; the lines, for whoever wants to set them one by one, under the fold.
	local levels = {}
	for _, level in ipairs(ns.LABEL_CONTENT_ORDER) do levels[#levels + 1] = { level, L["LABEL_CONTENT_" .. level:upper()] } end
	Under(Dropdown("LABEL_CONTENT", L.LABEL_CONTENT, L.LABEL_CONTENT_DESC, "complete", levels,
		function() return ns.db.label.content end,
		function(value)
			if value ~= "custom" then ns.SetLabelContent(value) else ns.db.label.content = value end
			ns.RefreshOptions()
		end), enabled, labelOn)
	Under(Dropdown("LABEL_ANCHOR", L.LABEL_ANCHOR, L.LABEL_ANCHOR_DESC, "head",
		{ { "head", L.ANCHOR_HEAD }, { "cursor", L.ANCHOR_CURSOR } },
		function() return ns.db.label.anchor end,
		function(value) ns.db.label.anchor = value end), enabled, labelOn)
	Checkbox("HIDE_TOOLTIP", L.HIDE_TOOLTIP, L.HIDE_TOOLTIP_DESC, ns.DEFAULTS.hideUnitTooltip,
		function() return ns.db.hideUnitTooltip end,
		function(value) ns.db.hideUnitTooltip = value end)
	Under(LabelCheckbox("combatLight", L.LABEL_COMBAT_LIGHT, L.LABEL_COMBAT_LIGHT_DESC), enabled, labelOn)
	Under(LabelCheckbox("hideInCombat", L.LABEL_COMBAT, L.LABEL_COMBAT_DESC), enabled, labelOn)

	Header(L.SECTION_LOOK)
	local styleChoices = {}
	for _, style in ipairs(ns.STYLES) do styleChoices[#styleChoices + 1] = { style, L["STYLE_" .. style:upper()] } end
	-- (the style, the font, the size and the spacing are also those of the tooltips and Wanderer's windows: never
	-- greyed with the label; only its background follows the label alone)
	Dropdown("LABEL_STYLE", L.LABEL_STYLE, L.LABEL_STYLE_DESC, "blizzard", styleChoices,
		function() return ns.db.label.style end,
		function(value) ns.db.label.style = value; ns.RefreshAll() end)
	local fontChoices = {}
	for _, font in ipairs(ns.FONTS) do fontChoices[#fontChoices + 1] = { font.key, L["FONT_" .. font.key:upper()] } end
	Dropdown("LABEL_FONT", L.LABEL_FONT, L.LABEL_FONT_DESC, "default", fontChoices,
		function() return ns.db.label.font end,
		function(value) ns.db.label.font = value; ns.RefreshAll() end)
	Slider("LABEL_SCALE", L.LABEL_SCALE, "label.scale", "%.1f", ns.RefreshAll)
	Slider("LABEL_PADDING", L.LABEL_PADDING, "label.padding", "%d", ns.RefreshAll)
	Under(Slider("LABEL_BG_OPACITY", L.LABEL_BG_OPACITY, "label.bgOpacity", "%d %%", ns.RefreshAll), enabled, labelOn)

	Header(L.SECTION_HIGHLIGHTS)
	LabelCheckbox("highlight", L.LABEL_HIGHLIGHT, L.LABEL_HIGHLIGHT_DESC)
	LabelCheckbox("highlightQuest", L.LABEL_HIGHLIGHT_QUEST, L.LABEL_HIGHLIGHT_QUEST_DESC)
	LabelCheckbox("highlightRelations", L.LABEL_HIGHLIGHT_RELATIONS, L.LABEL_HIGHLIGHT_RELATIONS_DESC)
	LabelCheckbox("highlightRank", L.LABEL_HIGHLIGHT_RANK, L.LABEL_HIGHLIGHT_RANK_DESC)

	Header(L.SECTION_THREAT)
	local threat = LabelCheckbox("threatAlert", L.LABEL_THREAT, L.LABEL_THREAT_DESC)
	local threatOn = IsOn("label", "threatAlert")
	Under(LabelCheckbox("threatSound", L.LABEL_THREAT_SOUND, L.LABEL_THREAT_SOUND_DESC), threat, threatOn)

	-- Folded: where exactly, then each line of what it says.
	Header(L.SECTION_POSITION, { advanced = true })
	Under(Slider("LABEL_OFFSET", L.LABEL_OFFSET, "label.offset", "%d"), enabled, labelOn)
	Under(Yield(TableCheckbox("label", "allHeads", L.LABEL_ALL_HEADS, L.LABEL_ALL_HEADS_DESC, function()
		ns.Apply()
		ns.RefreshPlates()
	end), "nameplates"), enabled, labelOn)
	Under(LabelCheckbox("worldOnly", L.LABEL_WORLD_ONLY, L.LABEL_WORLD_ONLY_DESC), enabled, labelOn)
	Under(LabelCheckbox("stickyTarget", L.LABEL_STICKY_TARGET, L.LABEL_STICKY_TARGET_DESC), enabled, labelOn)

	Header(L.SECTION_PLAYERS, { advanced = true })
	ContentCheckbox("showRace", L.LABEL_RACE)
	ContentCheckbox("showClass", L.LABEL_CLASS)
	ContentCheckbox("showSpec", L.LABEL_SPEC, L.LABEL_SPEC_DESC)
	ContentCheckbox("shiftDetails", L.LABEL_DETAILS, L.LABEL_DETAILS_DESC)
	ContentCheckbox("showGuild", L.LABEL_GUILD)
	local faction = ContentCheckbox("showFaction", L.LABEL_FACTION)
	Under(ContentCheckbox("showNPCFaction", L.LABEL_NPC_FACTION, L.LABEL_NPC_FACTION_DESC), faction, IsOn("label", "showFaction"))
	ContentCheckbox("showStatus", L.LABEL_STATUS, L.LABEL_STATUS_DESC)

	Header(L.SECTION_CREATURES, { advanced = true })
	ContentCheckbox("showCreatureType", L.LABEL_CREATURE_TYPE, L.LABEL_CREATURE_TYPE_DESC)
	ContentCheckbox("showClassification", L.LABEL_CLASSIFICATION, L.LABEL_CLASSIFICATION_DESC)
	ContentCheckbox("showNPCRole", L.LABEL_NPC_ROLE, L.LABEL_NPC_ROLE_DESC)
	ContentCheckbox("showReputation", L.LABEL_REPUTATION, L.LABEL_REPUTATION_DESC)
	ContentCheckbox("showTameable", L.LABEL_TAMEABLE, L.LABEL_TAMEABLE_DESC)
	ContentCheckbox("untagged", L.LABEL_UNTAGGED, L.LABEL_UNTAGGED_DESC)

	Header(L.SECTION_EVERYONE, { advanced = true })
	local level = ContentCheckbox("showLevel", L.LABEL_LEVEL)
	Under(ContentCheckbox("showDifficulty", L.LABEL_DIFFICULTY, L.LABEL_DIFFICULTY_DESC), level, IsOn("label", "showLevel"))
	ContentCheckbox("showXP", L.LABEL_XP, L.LABEL_XP_DESC)
	ContentCheckbox("showPortrait", L.LABEL_PORTRAIT, L.LABEL_PORTRAIT_DESC)
	ContentCheckbox("showHealth", L.LABEL_HEALTH, L.LABEL_HEALTH_DESC)
	ContentCheckbox("showPower", L.LABEL_POWER, L.LABEL_POWER_DESC)
	ContentCheckbox("showTarget", L.LABEL_TARGET, L.LABEL_TARGET_DESC)
	ContentCheckbox("showCasts", L.LABEL_CASTS, L.LABEL_CASTS_DESC)

	Header(L.SECTION_ACTIONS, { advanced = true })
	ContentCheckbox("showProfessions", L.LABEL_PROFESSIONS, L.LABEL_PROFESSIONS_DESC)
	ContentCheckbox("showLoot", L.LABEL_LOOT, L.LABEL_LOOT_DESC)
	ContentCheckbox("showObjects", L.LABEL_OBJECTS, L.LABEL_OBJECTS_DESC)
	ContentCheckbox("showQuests", L.LABEL_QUESTS, L.LABEL_QUESTS_DESC)

	Header(L.SECTION_RP, { advanced = true })
	TableCheckbox("rp", "leaveCard", L.RP_LEAVE_CARD, L.RP_LEAVE_CARD_DESC, ns.RefreshLabel)
	TableCheckbox("rp", "useName", L.RP_NAME, L.RP_NAME_DESC, ns.RefreshLabel)
	TableCheckbox("rp", "showTitle", L.RP_TITLE, nil, ns.RefreshLabel)
	TableCheckbox("rp", "showStatus", L.RP_STATUS, L.RP_STATUS_DESC, ns.RefreshLabel)
end

-- The game's tooltips: Wanderer's look, the lines added on items; on the portraits (folded).
local function TooltipsPage()
	Page(L.PAGE_TOOLTIPS, "tooltips")
	local styled = Yield(TableCheckbox("tooltips", "enabled", L.TOOLTIPS_STYLE, L.TOOLTIPS_STYLE_DESC, ns.RefreshTooltips), "tooltip")
	local styledOn = IsOn("tooltips", "enabled")
	Under(TableCheckbox("tooltips", "cursor", L.TOOLTIPS_CURSOR, L.TOOLTIPS_CURSOR_DESC), styled, styledOn)
	Under(TableCheckbox("tooltips", "icon", L.TOOLTIPS_ICON, L.TOOLTIPS_ICON_DESC), styled, styledOn)
	Under(TableCheckbox("tooltips", "quality", L.TOOLTIPS_QUALITY, L.TOOLTIPS_QUALITY_DESC), styled, styledOn)

	Header(L.SECTION_TOOLTIP_LINES)
	Yield(TableCheckbox("tooltips", "sellPrice", L.TOOLTIPS_SELL_PRICE, L.TOOLTIPS_SELL_PRICE_DESC), "sellPrice")
	TableCheckbox("tooltips", "reagents", L.TOOLTIPS_REAGENTS, L.TOOLTIPS_REAGENTS_DESC)
	-- (Pawn there: it alone judges the items, the scales with it)
	local upgrade = Yield(TableCheckbox("tooltips", "upgrade", L.TOOLTIPS_UPGRADE, L.TOOLTIPS_UPGRADE_DESC), "upgradeArrows")
	Under(Yield(Button(L.WEIGHTS_OPEN, L.WEIGHTS_OPEN_BUTTON, L.WEIGHTS_OPEN_DESC, function()
		CloseSettings()
		ns.ToggleWeights()
	end), "upgradeArrows"), upgrade, IsOn("tooltips", "upgrade"))
	Under(Yield(TableCheckbox("tooltips", "calculatedWeights", L.CALC_USE, L.CALC_USE_DESC, function()
		ns.ComparisonChanged()
		ns.RefreshWeights()
	end), "upgradeArrows"), upgrade, IsOn("tooltips", "upgrade"))
	Under(Yield(Button(L.UPGRADE_IMPORT, L.UPGRADE_IMPORT_BUTTON, L.UPGRADE_IMPORT_DESC, ImportScale), "upgradeArrows"),
		upgrade, IsOn("tooltips", "upgrade"))

	Header(L.SECTION_TOOLTIP_LABEL, { advanced = true })
	LabelCheckbox("ownPortrait", L.LABEL_OWN_PORTRAIT, L.LABEL_OWN_PORTRAIT_DESC)
	Checkbox("HIDE_TARGET_TOOLTIP", L.HIDE_TARGET_TOOLTIP, L.HIDE_TARGET_TOOLTIP_DESC, true,
		function() return ns.db.hideTargetTooltip end,
		function(value) ns.db.hideTargetTooltip = value end)
end

-- The screen: the game's windows; the minimap and the tracker; the fade when calm; signs in the world; Wanderer's
-- windows (folded).
local function InterfacePage()
	Page(L.PAGE_INTERFACE, "interface")
	Header(L.SECTION_GAME_WINDOWS)
	Yield(TableCheckbox("world", "moveFrames", L.MOVE_FRAMES, L.MOVE_FRAMES_DESC, ns.RefreshGameFrames), "mapSize", true)
	TableCheckbox("world", "hideTalkingHead", L.WORLD_TALKING_HEAD, L.WORLD_TALKING_HEAD_DESC)
	Yield(TableCheckbox("world", "filterErrors", L.WORLD_ERRORS, L.WORLD_ERRORS_DESC, ns.RefreshScreen), "errors")

	Header(L.SECTION_MINIMAP_TRACKER)
	local looks = {}
	for _, key in ipairs(ns.LOOK_CHOICES) do looks[#looks + 1] = { key, L["LOOK_" .. key:upper()] } end
	Yield(Dropdown("MINIMAP_LOOK", L.MINIMAP_LOOK, L.MINIMAP_LOOK_DESC, "game", looks,
		function() return ns.MinimapLook() end, function(value) ns.SetMinimapLook(value) end), "minimapLook")
	-- (Wanderer Quests' own list in the game's place: nothing of the game's to dress)
	Yield(Dropdown("TRACKER_LOOK", L.TRACKER_LOOK, L.TRACKER_LOOK_DESC, "game", looks,
		function() return ns.TrackerLook() end, function(value) ns.SetTrackerLook(value) end), "trackerLook")
	Composite("MINIMAP_LOOK", ns.MinimapLook, { "world.cleanMinimap", "world.styledMinimap" })
	Composite("TRACKER_LOOK", ns.TrackerLook, { "world.cleanTracker", "world.styledTracker" })
	Yield(TableCheckbox("world", "gatherIcons", L.GATHER_ICONS, L.GATHER_ICONS_DESC, ns.RefreshIcons), "minimapButtons")
	TableCheckbox("world", "layer", L.LAYER_OPTION, L.LAYER_OPTION_DESC)

	-- One choice for the fade (never, when calm, out of a fight), written in its two settings (cinema.enabled,
	-- cinema.combatOnly: the ways to play and the profiles by place keep them); opacity and delay under it.
	Header(L.SECTION_FADE)
	local fadeChoices = {}
	for _, key in ipairs(ns.FADE_CHOICES) do fadeChoices[#fadeChoices + 1] = { key, L["CINEMA_MODE_" .. key:upper()] } end
	local fade = Dropdown("CINEMA_MODE", L.CINEMA_MODE, L.CINEMA_MODE_DESC, "none", fadeChoices,
		function() return ns.FadeMode() end, function(value) ns.SetFadeMode(value) end)
	fade.segmented = true
	Composite("CINEMA_MODE", ns.FadeMode, { "cinema.enabled", "cinema.combatOnly" })
	local fading = function() return ns.db and ns.FadeMode() ~= "none" end
	Under(Slider("CINEMA_ALPHA", L.CINEMA_ALPHA, "cinema.alpha", "%d %%"), fade, fading)
	Under(Slider("CINEMA_DELAY", L.CINEMA_DELAY, "cinema.delay", "%d s"), fade, fading)

	Header(L.SECTION_IN_WORLD)
	local nodes = Yield(TableCheckbox("sparkles", "nodes", L.SPARKLE_NODES, L.SPARKLE_NODES_DESC, ns.RefreshSparkles), "nodeSparkle")
	Under(Yield(TableCheckbox("sparkles", "questObjects", L.SPARKLE_QUEST_OBJECTS, L.SPARKLE_QUEST_OBJECTS_DESC,
		ns.RefreshSparkles), "nodeSparkle"), nodes, IsOn("sparkles", "nodes"))
	Yield(TableCheckbox("world", "lootSparkle", L.LOOT_SPARKLE, L.LOOT_SPARKLE_DESC, ns.Apply), "lootSparkle")

	-- Wanderer's own windows: the size of their words (rarely changed: folded).
	Header(L.SECTION_WINDOWS, { advanced = true })
	Slider("LABEL_TEXT_SCALE", L.LABEL_TEXT_SCALE, "label.textScale", "%.2f", function()
		ns.Skin.ApplyFont()
		ns.RefreshAll()
	end)
end

-- The unit frames (UnitFrames.lua, Portraits.lua): the switch, what the game decides, the three looks; the bars,
-- the portraits; frame by frame and the rarer touches (folded). Every choice in view, the preview beside it.
local function UnitFramesPage()
	Page(L.PAGE_UNIT_FRAMES, "unitframes")
	page.preview = "unitframes"
	local function Apply() ns.ApplyUnitFrames() end
	local switch = Yield(TableCheckbox("unitFrames", "enabled", L.UF_ENABLE, L.UF_ENABLE_DESC, Apply), "unitFrames")
	local on = IsOn("unitFrames", "enabled")
	AddRow({ kind = "block", build = function(canvas) return ns.UnitFramesGameCard(canvas) end })
	AddRow({ kind = "block", build = function(canvas) return ns.UnitFramesPresetBlock(canvas) end })
	-- A row of choices (every one in view) for a setting of the look; under the switch.
	local function Choice(field, label, desc, list)
		local variable = "UF_" .. field:upper()
		local choices = function()
			local made = {}
			for _, value in ipairs(type(list) == "function" and list() or list) do
				made[#made + 1] = { value, L["UF_" .. field:upper() .. "_" .. value:upper()] }
			end
			return made
		end
		local row = Dropdown(variable, label, desc, ns.DEFAULTS.unitFrames[field], choices,
			function() return ns.db.unitFrames[field] end,
			function(value)
				ns.db.unitFrames[field] = value
				Apply()
			end)
		row.segmented = true
		ns.OPTION_WORDS.paths["unitFrames." .. field] = ns.OPTION_WORDS.variables[variable]
		return Under(row, switch, on)
	end
	local function Health()
		local list = {}
		for _, value in ipairs(ns.UF_CHOICES.health) do
			-- (the gradient only where the game colours a hidden health itself)
			if value ~= "gradient" or ns.UnitFramesGradient() or ns.db.unitFrames.health == "gradient" then list[#list + 1] = value end
		end
		return list
	end

	Header(L.UF_SECTION_BARS)
	Choice("health", L.UF_HEALTH, L.UF_HEALTH_DESC, Health)
	Choice("texture", L.UF_TEXTURE, L.UF_TEXTURE_DESC, ns.UF_CHOICES.texture)
	Choice("ground", L.UF_GROUND, L.UF_GROUND_DESC, ns.UF_CHOICES.ground)
	Choice("power", L.UF_POWER, L.UF_POWER_DESC, ns.UF_CHOICES.power)
	Choice("art", L.UF_ART, L.UF_ART_DESC, ns.UF_CHOICES.art)
	Choice("texts", L.UF_TEXTS, L.UF_TEXTS_DESC, ns.UF_CHOICES.texts)
	-- (the block's thickness: Ink lines only, where the bars are Wanderer's)
	local thickness = Choice("thickness", L.UF_THICKNESS, L.UF_THICKNESS_DESC, ns.UF_CHOICES.thickness)
	thickness.isOn = function() return ns.db.unitFrames.enabled and ns.db.unitFrames.art == "lines" end
	Under(TableCheckbox("unitFrames", "lowHealth", L.UF_LOW_HEALTH, L.UF_LOW_HEALTH_DESC, Apply), switch, on)
	local castInBlock = TableCheckbox("unitFrames", "castInBlock", L.UF_CAST_IN_BLOCK, L.UF_CAST_IN_BLOCK_DESC, Apply)
	castInBlock.isOn = function() return ns.db.unitFrames.enabled and ns.db.unitFrames.art == "lines" end
	castInBlock.parent = switch

	Header(L.UF_SECTION_PORTRAITS)
	Choice("ring", L.UF_RING, L.UF_RING_DESC, ns.UF_CHOICES.ring)
	Choice("badge", L.UF_BADGE, L.UF_BADGE_DESC, ns.UF_CHOICES.badge)
	Choice("iconStyle", L.UF_ICONSTYLE, L.UF_ICONSTYLE_DESC, ns.UF_CHOICES.iconStyle)
	Under(TableCheckbox("unitFrames", "greyDead", L.UF_GREY_DEAD, L.UF_GREY_DEAD_DESC, Apply), switch, on)

	-- Folded: what each portrait shows, frame by frame; which frames; the rarer touches.
	Header(L.UF_SECTION_SHOWS, { advanced = true })
	for _, key in ipairs(ns.UF_SHOWS) do
		local variable = "UF_SHOW_" .. key:upper()
		local choices = {}
		for _, value in ipairs(ns.UF_CHOICES.show) do choices[#choices + 1] = { value, L["UF_SHOW_" .. value:upper()] } end
		local row = Dropdown(variable, L["UF_SHOW_ROW_" .. key:upper()], key == "party" and L.UF_SHOW_PARTY_DESC or L.UF_SHOW_DESC,
			"game", choices,
			function() return ns.db.unitFrames.show[key] end,
			function(value)
				ns.db.unitFrames.show[key] = value
				Apply()
			end)
		row.segmented = true
		ns.OPTION_WORDS.paths["unitFrames.show." .. key] = ns.OPTION_WORDS.variables[variable]
		Under(row, switch, on)
	end
	Header(L.UF_SECTION_FRAMES, { advanced = true })
	local JOBS = { group = "unitFramesGroup", castBars = "unitFramesCasts" }
	for _, key in ipairs(ns.UF_FRAMES) do
		local variable = "UF_FRAME_" .. key:upper()
		local row = Checkbox(variable, L["UF_FRAME_" .. key:upper()], key == "group" and L.UF_FRAME_GROUP_DESC or nil, true,
			function() return ns.db.unitFrames.frames[key] ~= false end,
			function(value)
				ns.db.unitFrames.frames[key] = value and true or false
				Apply()
			end)
		ns.OPTION_WORDS.paths["unitFrames.frames." .. key] = ns.OPTION_WORDS.variables[variable]
		if JOBS[key] then Yield(row, JOBS[key]) end
		Under(row, switch, on)
	end
	Header(L.UF_SECTION_TOUCHES, { advanced = true })
	Under(TableCheckbox("unitFrames", "shortNumbers", L.UF_SHORT_NUMBERS, L.UF_SHORT_NUMBERS_DESC, Apply), switch, on)
	Under(TableCheckbox("unitFrames", "quarterMarks", L.UF_QUARTER_MARKS, L.UF_QUARTER_MARKS_DESC, Apply), switch, on)
	Under(TableCheckbox("unitFrames", "colourBlind", L.UF_COLOUR_BLIND, L.UF_COLOUR_BLIND_DESC, Apply), switch, on)
	Under(TableCheckbox("unitFrames", "wanderer", L.UF_FOLLOW, L.UF_FOLLOW_DESC, Apply), switch, on)
end

-- The action bars: which ones, their slots, and the Edit Mode layouts that place them.
local function ActionBarsPage()
	Page(L.PAGE_ACTION_BARS, "bars")
	-- (a first section named as the page: no title of its own)
	Header(L.PAGE_ACTION_BARS)
	-- (which bars show is the game's own option: never a second switch here, its page a click away)
	Button(L.BARS_SHOWN_GAME, L.BARS_SHOWN_GAME_BUTTON, L.BARS_SHOWN_GAME_DESC, function() ns.OpenGameActionBars() end)
	-- (Wanderer's fade dims the bars out of combat: said here, its setting one click away)
	AddRow({ kind = "button", label = L.BARS_FADE, desc = L.BARS_FADE_DESC,
		text = function()
			local fade = ns.BarsFade and ns.BarsFade()
			return fade == "combat" and L.BARS_FADE_COMBAT or fade == "calm" and L.BARS_FADE_CALM or L.BARS_FADE_NONE
		end,
		onClick = function() ns.OpenOptions("interface") end })

	Header(L.SECTION_SLOTS)
	Slider("BARS_BORDER", L.BARS_BORDER, "bars.border", "%d %%", ns.RefreshBarSlots)
	Slider("BARS_BACKGROUND", L.BARS_BACKGROUND, "bars.background", "%d %%", ns.RefreshBarSlots)

	Header(L.SECTION_LAYOUT)
	Button(L.LAYOUT_STACKED_OPTION, L.LAYOUT_MAKE_BUTTON, L.LAYOUT_STACKED_DESC, function() ns.MakeLayout("stacked") end)
	Button(L.LAYOUT_CLEAN_OPTION, L.LAYOUT_MAKE_BUTTON, L.LAYOUT_CLEAN_DESC, function() ns.MakeLayout("clean") end)
	Button(L.LAYOUT_BLIZZARD_OPTION, L.LAYOUT_MAKE_BUTTON, L.LAYOUT_BLIZZARD_DESC, function() ns.MakeLayout("blizzard") end)
	Dropdown("EDIT_LAYOUT", L.EDIT_LAYOUT, L.EDIT_LAYOUT_DESC, "",
		function()
			local list = { { "", L.EDIT_LAYOUT_KEEP } }
			for _, name in ipairs(ns.EditModeLayouts()) do list[#list + 1] = { name, name } end
			return list
		end,
		function() return ns.db.world.editLayout end,
		function(value)
			ns.db.world.editLayout = value
			ns.ApplyEditLayout()
		end)
end

-- Conversations: the scenes and the reading window, the quests in them, what is done for you (off).
local function ConversationsPage()
	Page(L.PAGE_CONVERSATIONS, "conversations")
	-- (another addon showing the conversations: the scene, its camera and its hush are left to it)
	-- (Spoken installed: the scenes follow its voice, said where the scenes are switched on)
	local sceneDesc = ns.SpokenLoaded and ns.SpokenLoaded() and (L.SCENE_ENABLE_DESC .. "\n\n" .. L.SCENE_SPOKEN_HINT) or L.SCENE_ENABLE_DESC
	local scene = Yield(TableCheckbox("scene", "enabled", L.SCENE_ENABLE, sceneDesc, ns.RefreshScene), "scenes")
	Under(Yield(Slider("SCENE_TEXT_SIZE", L.SCENE_TEXT_SIZE, "scene.textSize", "%d"), "scenes"), scene, IsOn("scene", "enabled"))
	Under(Yield(Slider("SCENE_BG_OPACITY", L.SCENE_BG_OPACITY, "scene.bgOpacity", "%d %%", ns.RefreshScene), "scenes"), scene,
		IsOn("scene", "enabled"))
	Yield(TableCheckbox("scene", "hush", L.SCENE_HUSH, L.SCENE_HUSH_DESC), "scenes")
	Yield(TableCheckbox("scene", "reader", L.SCENE_READER, L.SCENE_READER_DESC, ns.RefreshReader), "books")
	Yield(TableCheckbox("scene", "parchment", L.SCENE_PARCHMENT, L.SCENE_PARCHMENT_DESC, ns.RefreshScene), "scenes", true)
	local camera = Yield(TableCheckbox("scene", "camera", L.SCENE_CAMERA, L.SCENE_CAMERA_DESC), { "scenes", "camera" })
	Under(Yield(TableCheckbox("scene", "cameraShops", L.SCENE_CAMERA_SHOPS, L.SCENE_CAMERA_SHOPS_DESC), { "scenes", "camera" }),
		camera, IsOn("scene", "camera"))
	Under(Yield(TableCheckbox("scene", "cameraFrame", L.SCENE_CAMERA_FRAME, L.SCENE_CAMERA_FRAME_DESC), { "scenes", "camera" }),
		camera, IsOn("scene", "camera"))

	Header(L.QUESTS)
	TableCheckbox("quest", "tags", L.QUEST_TAGS, L.QUEST_TAGS_DESC)
	TableCheckbox("quest", "bestReward", L.QUEST_BEST_REWARD, L.QUEST_BEST_REWARD_DESC)

	Header(L.SECTION_AUTOMATIONS)
	Yield(TableCheckbox("quest", "autoAccept", L.QUEST_AUTO_ACCEPT, L.QUEST_AUTO_ACCEPT_DESC), "questAuto")
	Yield(TableCheckbox("quest", "autoTurnIn", L.QUEST_AUTO_TURNIN, L.QUEST_AUTO_TURNIN_DESC), "questAuto")
	Yield(TableCheckbox("quest", "skipGossip", L.QUEST_SKIP_GOSSIP, L.QUEST_SKIP_GOSSIP_DESC), "skipGossip")
end

-- Immersion: travels, photos, the away ambiance, the camera, the emotes; gestures; the sounds (folded).
local function ImmersionPage()
	Page(L.PAGE_IMMERSION, "immersion")
	-- (an extension naming the flight itself, Wanderer Maps: the card's title is its, the fade and the camera stay)
	local travel = Yield(TableCheckbox("travel", "enabled", L.TRAVEL_ENABLE, L.TRAVEL_ENABLE_DESC,
		function() ns.RefreshCurtain() end), "flightCard", true)
	Under(Yield(TableCheckbox("travel", "camera", L.TRAVEL_CAMERA, L.TRAVEL_CAMERA_DESC), "camera"), travel,
		IsOn("travel", "enabled"))
	local away = Yield(TableCheckbox("away", "enabled", L.AWAY_ENABLE, L.AWAY_ENABLE_DESC, ns.RefreshAway), "away")
	Under(Dropdown("AWAY_STYLE", L.AWAY_STYLE, L.AWAY_STYLE_DESC, "hearth",
		function()
			local list = {}
			for _, key in ipairs(ns.AWAY_STYLES) do list[#list + 1] = { key, L["AWAY_STYLE_" .. key:upper()] } end
			return list
		end,
		function() return ns.db.away.style end,
		function(value)
			ns.db.away.style = value
			ns.RefreshAway()
		end), away, IsOn("away", "enabled"))
	Button(L.AWAY_TRY, L.AWAY_TRY_BUTTON, L.AWAY_TRY_DESC, function()
		CloseSettings()
		ns.GoAway()
	end)
	Button(L.PHOTO, L.PHOTO_BUTTON, L.PHOTO_DESC, function()
		CloseSettings()
		ns.TogglePhotoMode()
	end)
	Yield(TableCheckbox("world", "actionCam", L.WORLD_ACTION_CAM, L.WORLD_ACTION_CAM_DESC, ns.RefreshAll), "camera")
	TableCheckbox("world", "calmMotion", L.WORLD_CALM_MOTION, L.WORLD_CALM_MOTION_DESC)
	TableCheckbox("emotes", "enabled", L.EMOTES_BAR, L.EMOTES_BAR_DESC, ns.RefreshEmotes)

	Header(L.SECTION_GESTURES)
	TableCheckbox("gestures", "sitAtFire", L.GESTURES_SIT_FIRE, L.GESTURES_SIT_FIRE_DESC)
	TableCheckbox("gestures", "read", L.GESTURES_READ, L.GESTURES_READ_DESC)
	TableCheckbox("gestures", "levelUp", L.GESTURES_LEVEL, L.GESTURES_LEVEL_DESC)
	TableCheckbox("gestures", "greet", L.GESTURES_GREET, L.GESTURES_GREET_DESC)

	Header(L.SECTION_SOUNDS, { advanced = true })
	local sounds = TableCheckbox("sounds", "enabled", L.SOUNDS_ENABLE, L.SOUNDS_ENABLE_DESC, ns.RefreshSounds)
	Under(Button(L.SOUNDS_LIST, L.SOUNDS_LIST_BUTTON, L.SOUNDS_LIST_DESC, function() ns.EditSounds() end),
		sounds, IsOn("sounds", "enabled"))
end

-- Every day: merchants and trainers; loot; professions and fishing; what is done by hand (off); the todo
-- list (folded).
local function PracticalPage()
	Page(L.PAGE_PRACTICAL, "practical")
	Yield(TableCheckbox("merchant", "sellJunk", L.MERCHANT_SELL_JUNK, L.MERCHANT_SELL_JUNK_DESC), "sellJunk")
	local repair = Yield(TableCheckbox("merchant", "repair", L.MERCHANT_REPAIR, L.MERCHANT_REPAIR_DESC), "repair")
	Under(Yield(TableCheckbox("merchant", "guildRepair", L.MERCHANT_GUILD_REPAIR, L.MERCHANT_GUILD_REPAIR_DESC), "repair"),
		repair, IsOn("merchant", "repair"))
	TableCheckbox("merchant", "repairReminder", L.REPAIR_REMINDER, L.REPAIR_REMINDER_DESC)
	TableCheckbox("world", "townCard", L.TOWN_CARD, L.TOWN_CARD_DESC)
	Yield(TableCheckbox("merchant", "provisions", L.PROVISIONS_OPTION, L.PROVISIONS_OPTION_DESC, ns.RefreshProvisions), "restock")
	-- (an extension showing the trainers in its own window, Wanderer Training: its buttons buy there)
	Yield(TableCheckbox("trainer", "learnAll", L.TRAINER_LEARN_ALL_OPTION, L.TRAINER_LEARN_ALL_DESC, ns.RefreshTrainer), "trainerWindow")

	Header(L.SECTION_LOOT)
	Yield(TableCheckbox("loot", "fast", L.LOOT_FAST, L.LOOT_FAST_DESC), "fastLoot")
	-- The loot feed (LootFeed.lua): what you pick up, one line each.
	local feed = Yield(TableCheckbox("loot", "feed", L.LOOT_FEED, L.LOOT_FEED_DESC, ns.RefreshLootFeed), "lootFeed")
	local feedOn = IsOn("loot", "feed")
	local qualities = {}
	for quality = 0, 4 do qualities[#qualities + 1] = { tostring(quality), L["LOOT_FEED_QUALITY_" .. quality] } end
	Under(Dropdown("LOOT_FEED_QUALITY", L.LOOT_FEED_QUALITY, L.LOOT_FEED_QUALITY_DESC, "1", qualities,
		function() return tostring(ns.db.loot.feedQuality) end,
		function(value) ns.db.loot.feedQuality = tonumber(value) or 1 end), feed, feedOn)
	Under(TableCheckbox("loot", "feedMoney", L.LOOT_FEED_MONEY, L.LOOT_FEED_MONEY_DESC), feed, feedOn)
	Under(TableCheckbox("loot", "feedReceived", L.LOOT_FEED_RECEIVED, L.LOOT_FEED_RECEIVED_DESC), feed, feedOn)
	Under(Slider("LOOT_FEED_TIME", L.LOOT_FEED_TIME, "loot.feedTime", "%d s"), feed, feedOn)

	Header(L.SECTION_CRAFTS)
	TableCheckbox("fishing", "doubleClick", L.FISHING_DOUBLE_CLICK, L.FISHING_DOUBLE_CLICK_DESC)
	-- (Wanderer Outfits' pole, taken and given back by this double click: shown here too when it is installed)
	Mirror("OUTFITS_POLEONCAST")
	Mirror("OUTFITS_WEAPONSONMOUNT")
	TableCheckbox("fishing", "tell", L.FISHING_TELL, L.FISHING_TELL_DESC)
	TableCheckbox("fishing", "splash", L.FISHING_SPLASH, L.FISHING_SPLASH_DESC)
	TableCheckbox("crafts", "gatherReach", L.CRAFTS_GATHER_REACH, L.CRAFTS_GATHER_REACH_DESC)
	TableCheckbox("crafts", "ceiling", L.CRAFTS_CEILING, L.CRAFTS_CEILING_DESC)
	TableCheckbox("crafts", "skillUps", L.CRAFTS_SKILL_UPS, L.CRAFTS_SKILL_UPS_DESC)

	-- What the game makes you do by hand, done for you: off until asked.
	Header(L.SECTION_AUTOMATIONS)
	TableCheckbox("hands", "bagsClosed", L.HANDS_BAGS, L.HANDS_BAGS_DESC)
	TableCheckbox("hands", "standUp", L.HANDS_STAND, L.HANDS_STAND_DESC)
	Yield(TableCheckbox("hands", "easyDestroy", L.HANDS_DESTROY, L.HANDS_DESTROY_DESC), "easyDestroy")

	-- The kinds of notices silenced for good on this character (a right click on one): taken back here; the
	-- reminders. One quiet section for both.
	Header(L.SECTION_NOTICES_REMINDERS, { advanced = true })
	AddRow({ kind = "button", label = L.NOTICES_SILENCED, desc = L.NOTICES_SILENCED_DESC,
		text = function() local count = #ns.SilencedNotices() return count > 0 and L.NOTICES_MANAGE:format(count) or L.NOTICES_NONE end,
		onClick = function(owner) ns.ShowSilencedNotices(owner) end, usable = function() return ns.SilencedNotices()[1] ~= nil end })
	Button(L.TODO_TITLE, L.OPEN, L.TODO_OPEN_DESC, function()
		CloseSettings()
		ns.ToggleTodo()
	end)
	Checkbox("TODO_AT_LOGIN", L.TODO_AT_LOGIN, L.TODO_AT_LOGIN_DESC, true,
		function() return not (ns.root and ns.Mine().todoAtLogin == false) end,
		function(value)
			-- (ticked: nil, the default)
			if value then ns.Mine().todoAtLogin = nil else ns.Mine().todoAtLogin = false end
		end)
end

-- In a group and in a fight: threat, the blessings to cast again, the dungeon's door; the damage meter; your
-- damage over time.
local function GroupPage()
	Page(L.PAGE_GROUP, "group")
	TableCheckbox("threat", "show", L.THREAT_SHOW, L.THREAT_SHOW_DESC, ns.RefreshTargetInfo)
	TableCheckbox("threat", "alert", L.THREAT_ALERT, L.THREAT_ALERT_DESC)
	TableCheckbox("buffs", "remind", L.BUFF_REMIND, L.BUFF_REMIND_DESC)
	TableCheckbox("world", "threshold", L.THRESHOLD, L.THRESHOLD_DESC)

	-- The game's damage meter: shown by profile (the dungeons' one: shown), text only is Wanderer's.
	Header(L.SECTION_METER)
	local meter = Dropdown("METER_SHOW", L.METER_SHOW, L.METER_SHOW_DESC, "own",
		{ { "own", L.METER_SHOW_OWN }, { "on", L.METER_SHOW_ON }, { "off", L.METER_SHOW_OFF } },
		function() return ns.db.meter.show end,
		function(value)
			ns.db.meter.show = value
			ns.Apply()
		end)
	Under(Yield(Dropdown("METER_LOOK", L.METER_LOOK, L.METER_LOOK_DESC, "game",
		{ { "game", L.METER_LOOK_GAME }, { "text", L.METER_LOOK_TEXT } },
		function() return ns.db.meter.look end,
		function(value)
			ns.db.meter.look = value
			ns.ApplyMeter()
		end), "meterLook"), meter, function() return ns.db.meter.show ~= "off" end)

	Header(L.SECTION_DOTS)
	local dots = Yield(TableCheckbox("dots", "enabled", L.DOTS_ENABLE, L.DOTS_ENABLE_DESC, ns.RefreshDots), "dots")
	-- (where it shows, then the skull: each part on unless turned off)
	for _, part in ipairs({ "target", "focus", "tot", "plates", "mark" }) do
		local key = "DOTS_" .. part:upper()
		Under(Yield(TableCheckbox("dots", part, L[key], L[key .. "_DESC"], ns.RefreshDots), "dots"), dots,
			IsOn("dots", "enabled"))
	end
	local hots = TableCheckbox("hots", "enabled", L.HOTS_ENABLE, L.HOTS_ENABLE_DESC, ns.RefreshHots)
	-- (where it shows, then the plus: each part on unless turned off)
	for _, part in ipairs({ "player", "group", "target", "plates", "mark" }) do
		local key = "HOTS_" .. part:upper()
		Under(TableCheckbox("hots", part, L[key], L[key .. "_DESC"], ns.RefreshHots), hots, IsOn("hots", "enabled"))
	end
end

-- What other players ask of you: each answer off until asked.
local function SocialPage()
	Page(L.PAGE_SOCIAL, "social")
	TableCheckbox("social", "acceptInvites", L.SOCIAL_INVITES, L.SOCIAL_INVITES_DESC)
	TableCheckbox("social", "acceptResurrect", L.SOCIAL_RESURRECT, L.SOCIAL_RESURRECT_DESC)
	TableCheckbox("social", "acceptSummon", L.SOCIAL_SUMMON, L.SOCIAL_SUMMON_DESC)
	TableCheckbox("social", "declineDuels", L.SOCIAL_DUELS, L.SOCIAL_DUELS_DESC)
	local inviteWord = TableCheckbox("social", "inviteOnWord", L.SOCIAL_INVITE_WORD, L.SOCIAL_INVITE_WORD_DESC)
	Under(Button(L.SOCIAL_INVITE_WORD_PICK, L.SOCIAL_INVITE_WORD_BUTTON, L.SOCIAL_INVITE_WORD_PICK_DESC, function()
		ns.Skin.AskText(L.SOCIAL_INVITE_WORD_PROMPT, ns.db.social.inviteWord or "", function(word)
			-- (a button, not a setting's control: carried to every profile of this character here)
			ns.ChangeEverywhere(function() ns.db.social.inviteWord = word end)
		end, 24)
	end), inviteWord, IsOn("social", "inviteOnWord"))
end

-- Profiles: the one in use and its care, your characters; a profile by place; sharing.
local function ProfilesPage()
	Page(L.PAGE_PROFILES, "profiles", "more")
	-- (the game's Defaults button: back to this character's own profile)
	Dropdown("PROFILE", L.PROFILE, L.PROFILE_DESC, (ns.root.ownProfile or {})[ns.CharacterKey()] or ns.profileName,
		function()
			local list = {}
			for _, name in ipairs(ns.ListProfiles()) do list[#list + 1] = { name, name } end
			return list
		end,
		function() return ns.profileName end,
		function(value) ns.SetProfile(value) end)
	Button(L.PROFILE_NEW, L.PROFILE_NEW_BUTTON, L.PROFILE_NEW_DESC, function()
		ns.Skin.AskText(L.PROFILE_NEW_PROMPT, "", function(name)
			ns.root.profiles[name] = ns.root.profiles[name] or {}
			ns.SetProfile(name)
		end)
	end)
	Button(L.PROFILE_COPY, L.PROFILE_COPY_BUTTON, L.PROFILE_COPY_DESC, function() ns.Skin.AskText(L.PROFILE_COPY_PROMPT, "", ns.CopyProfile) end)
	-- (a character's own profile is never deleted: greyed while it is the one in use)
	local delete = Button(L.PROFILE_DELETE, L.REMOVE, L.PROFILE_DELETE_DESC, DeleteAsk)
	delete.usable = function() return ns.profileName ~= ns.OwnProfile() end
	Button(L.RESET_PROFILE, L.RESET_PROFILE_BUTTON, L.RESET_PROFILE_DESC, ResetAsk)
	Button(L.CHARACTERS_TITLE, L.OPEN, L.CHARACTERS_DESC, function()
		CloseSettings()
		ns.ToggleCharacters()
	end)

	-- A profile for each kind of place, switched by itself on arrival.
	Header(L.SECTION_PLACES)
	Button(L.PLACE_PROFILES_MAKE, L.PLACE_PROFILES_MAKE_BUTTON, L.PLACE_PROFILES_MAKE_DESC, function() ns.MakePlaceProfiles() end)
	for _, zone in ipairs(ns.ZONES) do
		Dropdown("PLACE_" .. zone:upper(), L["ZONE_" .. zone:upper()], L.PLACE_PROFILE_DESC, "",
			function()
				local list = { { "", L.PLACE_PROFILE_OWN } }
				for _, name in ipairs(ns.ListProfiles()) do list[#list + 1] = { name, name } end
				return list
			end,
			function() return ns.PlaceProfiles()[zone] or "" end,
			function(value)
				ns.PlaceProfiles()[zone] = value ~= "" and value or nil
				ns.UpdatePlaceProfile()
			end)
	end
	Header(L.SECTION_SHARE)
	Button(L.PROFILE_EXPORT, L.PROFILE_EXPORT, L.PROFILE_EXPORT_DESC, function() ns.Skin.ShowCopy(L.PROFILE_EXPORT_PROMPT, ns.ExportProfile()) end)
	Button(L.PROFILE_IMPORT, L.PROFILE_IMPORT, L.PROFILE_IMPORT_DESC, ImportProfileAsk)
end

-- The game's settings ------------------------------------------------------------------

-- Its panel (Esc > Options > AddOns > Wanderer): one page saying where the settings are, a button opening them.
local function LauncherPage()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory and CreateFrame) then return end
	local Skin = ns.Skin
	local frame = CreateFrame("Frame")
	local kicker = Skin.CreateKicker(frame, L.ADDON_TITLE)
	kicker:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -24)
	local title = Skin.CreateText(frame, "GameFontNormalHuge", 1, 0.82, 0)
	title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
	title:SetText(L.SETTINGS_TITLE)
	local text = Skin.Text(frame, "GameTooltipText", "soft")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
	text:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
	text:SetText(L.SETTINGS_LAUNCHER_DESC)
	local open = Skin.Button(frame, L.SETTINGS_LAUNCHER_BUTTON, function()
		CloseSettings()
		ns.OpenOptions()
	end, "main", 260)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -22)
	local hint = Skin.Text(frame, "GameTooltipTextSmall", "muted")
	hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -12)
	hint:SetText(L.SETTINGS_LAUNCHER_HINT)
	local launcher = Settings.RegisterCanvasLayoutCategory(frame, L.ADDON_TITLE)
	if launcher and launcher.AddSearchTags then pcall(launcher.AddSearchTags, launcher, "Wanderer") end
	Settings.RegisterAddOnCategory(launcher)
end

function ns.InitOptions()
	HomePage()
	ThemesPage()
	PlaystylesPage()
	for _, each in ipairs({ NamesPage, LabelPage, TooltipsPage, InterfacePage, UnitFramesPage, ActionBarsPage, ConversationsPage, ImmersionPage,
		PracticalPage, GroupPage, SocialPage }) do
		each()
	end
end

-- Once logged in (the extensions are loaded by then): their pages, the profiles last, the game's page.
local finished = false
function ns.FinishOptions()
	if finished or not ns.SETTINGS_PAGES[1] then return end
	finished = true
	-- (Toggle: a check box whose value the extension keeps itself, e.g. for each character; Yield: an option
	-- whose job another addon may do, see Compat.lua; Header(text, { advanced = true }): the rows after it
	-- folded under "More settings", see the top of this file)
	local tools = { Header = Header, Checkbox = TableCheckbox, Toggle = Checkbox, Slider = Slider, Dropdown = Dropdown,
		Button = Button, Under = Under, IsOn = IsOn, CloseSettings = CloseSettings, Yield = Yield, Needs = Needs }
	for _, extension in ipairs(ns.EXTENSIONS) do
		if extension.options then
			-- (named the same way for all of them: the extension's own name, without "Wanderer")
			local name = extension.addon and ns.Util.Clean(ns.Util.Safe(C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata, extension.addon, "Title"))
			name = type(name) == "string" and name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^Wanderer%s+", "") or extension.title
			Page(name ~= "" and name or extension.title, "ext:" .. tostring(extension.key), "extensions").addon = extension.addon
			local ok, problem = pcall(extension.options, tools)
			if not ok and ns.debug then ns.Print(tostring(problem)) end
		end
	end
	-- (the mirrors linked once every page is there, the extensions' too: a mirror of a missing one is dropped)
	LinkMirrors()
	-- The extensions not installed: a page each (one card: what it does, its address), muted in the sidebar.
	for _, offer in ipairs(ns.MissingExtensions()) do
		ns.SETTINGS_PAGES[#ns.SETTINGS_PAGES + 1] = { key = "offer:" .. offer.addon, name = (offer.name:gsub("^Wanderer%s+", "")),
			group = "extensions", rows = {}, offer = offer }
	end
	ProfilesPage()
	LauncherPage()
end
