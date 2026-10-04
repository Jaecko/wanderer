local _, ns = ...
local L = ns.L

-- Options in the game's own settings (Esc > Options > AddOns > Wanderer): a
-- short home page and one page per theme, folded under "Wanderer" in the list.
-- Options that only matter when another one is on are shown under it and
-- greyed out while it is off. Getters always read ns.db, the active profile,
-- so switching profiles only needs a refresh.

local mainCategory -- home page, opened by /wanderer
local category, layout -- page being filled
local settings = {}
ns.PREVIEW_CATEGORIES = {} -- pages beside which the label preview shows

-- The game's search box (top of the Options window) finds Wanderer's options
-- by their own words; each also answers to the name of its page and section.
local pageName, sectionName

local function Searchable(initializer)
	if initializer and initializer.AddSearchTags then
		pcall(initializer.AddSearchTags, initializer, "Wanderer", pageName or "", sectionName or "")
	end
	return initializer
end

local function Header(text)
	sectionName = text
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

-- Starts a page: the home page first, then pages folded under it. Clients
-- without folded pages get every page on the home page, under its title.
local function Page(name)
	pageName, sectionName = name, nil
	if not mainCategory then
		category, layout = Settings.RegisterVerticalLayoutCategory(name)
		mainCategory = category
	elseif Settings.RegisterVerticalLayoutSubcategory then
		category, layout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, name)
	else
		Header(name)
	end
end

local function Button(label, text, tooltip, onClick)
	local initializer = CreateSettingsButtonInitializer(label, text, onClick, tooltip, true)
	layout:AddInitializer(initializer)
	return Searchable(initializer)
end

-- Shows an option under another one, greyed out while isOn() is false.
local function Under(initializer, parent, isOn)
	if initializer and parent and initializer.SetParentInitializer then
		initializer:SetParentInitializer(parent, isOn)
	end
	return initializer
end

local function Proxy(variable, varType, label, default, getter, setter)
	local setting = Settings.RegisterProxySetting(category, "WANDERER_" .. variable, varType, label, default, getter, setter)
	settings[#settings + 1] = setting
	return setting
end

-- Checkbox rows of Wanderer: the text takes the whole width of the row and the
-- box sits at its right end (the game cuts the text at half the width).
-- The game reuses its rows for every setting of the panel: a row keeps the
-- game's own layout whenever it shows another setting.
local wideRows = {} -- initializers of Wanderer's checkboxes
local hookedRows = {} -- rows already watched
local ROW_RIGHT_MARGIN = 24

local function LayoutRow(row, initializer)
	local box, text = row.Checkbox, row.Text
	if not (box and text) then return end
	if not row.wandererBoxPoint then row.wandererBoxPoint = { box:GetPoint(1) } end
	box:ClearAllPoints()
	if wideRows[initializer] then
		box:SetPoint("RIGHT", row, "RIGHT", -ROW_RIGHT_MARGIN, 0)
		text:SetPoint("RIGHT", box, "LEFT", -8, 0)
	else
		box:SetPoint(unpack(row.wandererBoxPoint))
	end
end

local function WatchRow(row)
	if hookedRows[row] or not row.Init then return end
	hookedRows[row] = true
	-- After the game's own set up of the row, for any setting.
	hooksecurefunc(row, "Init", LayoutRow)
end

-- Every control returns its initializer (to put other options under it).
local function Checkbox(variable, label, tooltip, default, getter, setter)
	local setting = Proxy(variable, Settings.VarType.Boolean, label, default, getter, setter)
	local initializer = Searchable(Settings.CreateCheckbox(category, setting, tooltip))
	if initializer and initializer.InitFrame then
		wideRows[initializer] = true
		local initFrame = initializer.InitFrame
		initializer.InitFrame = function(self, row)
			WatchRow(row)
			return initFrame(self, row)
		end
	end
	return initializer
end

-- choices: list of { value, label }, or a function returning it.
local function Dropdown(variable, label, tooltip, default, choices, getter, setter)
	local setting = Proxy(variable, Settings.VarType.String, label, default, getter, setter)
	return Searchable(Settings.CreateDropdown(category, setting, function()
		local container = Settings.CreateControlTextContainer()
		for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
			container:Add(choice[1], choice[2])
		end
		return container:GetData()
	end, tooltip))
end

-- Slider bound to a number of a sub-table of the profile ("label.scale"),
-- with the bounds shared with the checks of saved settings (ns.RANGES).
local function Slider(variable, label, path, format, onChange)
	local section, key = path:match("^(%w+)%.(%w+)$")
	local min, max, step = unpack(ns.RANGES[path])
	local setting = Proxy(variable, Settings.VarType.Number, label, ns.DEFAULTS[section][key],
		function() return ns.db[section][key] end,
		function(value)
			ns.db[section][key] = value
			if onChange then onChange() end
		end)
	local options = Settings.CreateSliderOptions(min, max, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		if type(format) == "function" then return format(value) end
		return format:format(value)
	end)
	return Searchable(Settings.CreateSlider(category, setting, options))
end

-- Checkbox bound to a key of a sub-table of the active profile.
local function TableCheckbox(tableName, key, label, tooltip, onChange)
	return Checkbox(tableName:upper() .. "_" .. key:upper(), label, tooltip, ns.DEFAULTS[tableName][key],
		function() return ns.db[tableName][key] and true or false end,
		function(value)
			ns.db[tableName][key] = value
			if onChange then onChange() end
		end)
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
end

function ns.OpenOptions()
	if mainCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(mainCategory:GetID())
	end
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

local EditBoxOf = ns.Util.EditBoxOf

local function RegisterDialogs()
	if not StaticPopupDialogs then return end
	local function nameDialog(text, onName)
		return {
			text = text, button1 = ACCEPT, button2 = CANCEL, hasEditBox = true,
			timeout = 0, whileDead = true, hideOnEscape = true,
			OnAccept = function(self)
				local name = strtrim(EditBoxOf(self):GetText() or "")
				if name ~= "" then onName(name) end
			end,
			EditBoxOnEnterPressed = function(box)
				local dialog = box:GetParent()
				dialog.button1:Click()
			end,
		}
	end
	StaticPopupDialogs.WANDERER_NEW_PROFILE = nameDialog(L.PROFILE_NEW_PROMPT, function(name)
		ns.root.profiles[name] = ns.root.profiles[name] or {}
		ns.SetProfile(name)
	end)
	StaticPopupDialogs.WANDERER_COPY_PROFILE = nameDialog(L.PROFILE_COPY_PROMPT, function(name)
		ns.CopyProfile(name)
	end)
	StaticPopupDialogs.WANDERER_EXPORT_PROFILE = {
		text = L.PROFILE_EXPORT_PROMPT, button1 = OKAY, hasEditBox = true, editBoxWidth = 350,
		timeout = 0, whileDead = true, hideOnEscape = true,
		OnShow = function(self)
			local box = EditBoxOf(self)
			box:SetText(ns.ExportProfile())
			box:HighlightText()
			box:SetFocus()
		end,
	}
	StaticPopupDialogs.WANDERER_IMPORT_PROFILE = {
		text = L.PROFILE_IMPORT_PROMPT, button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, editBoxWidth = 350,
		timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(self)
			local ok, err = ns.ImportProfile(EditBoxOf(self):GetText(), UniqueName(L.PROFILE_IMPORTED))
			ns.Print(ok and L.IMPORT_DONE:format(ns.profileName) or err)
		end,
	}
	StaticPopupDialogs.WANDERER_RESET_PROFILE = {
		text = L.RESET_PROFILE_PROMPT, button1 = YES, button2 = NO,
		timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
		OnAccept = function() ns.ResetProfile() end,
	}
	StaticPopupDialogs.WANDERER_DELETE_PROFILE = {
		text = L.PROFILE_DELETE_PROMPT, button1 = YES, button2 = NO,
		timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function()
			local name = ns.profileName
			if not ns.DeleteProfile(name) then ns.Print(L.PROFILE_DELETE_DEFAULT) end
		end,
	}
end

local function Popup(name, ...)
	if StaticPopup_Show then StaticPopup_Show(name, ...) end
end

-- Panel ----------------------------------------------------------------------------

local function HomePage()
	Page(L.ADDON_TITLE)
	Header(L.SECTION_GENERAL)
	Checkbox("ENABLED", L.ENABLE, L.ENABLE_DESC, true,
		function() return ns.db.enabled end,
		function(value) ns.SetEnabled(value) end)
	local presetChoices = {}
	for _, preset in ipairs(ns.PRESET_ORDER) do
		presetChoices[#presetChoices + 1] = { preset, L["PRESET_" .. preset:upper()] }
	end
	Dropdown("PRESET", L.PRESET, L.PRESET_DESC, "immersion", presetChoices,
		function() return ns.db.preset end,
		function(value) if value ~= "custom" then ns.SetPreset(value) end end)
	Checkbox("MINIMAP", L.MINIMAP_BUTTON, L.MINIMAP_HINT, true,
		function() return ns.IsMinimapButtonShown and ns.IsMinimapButtonShown() or false end,
		function(value) if ns.SetMinimapButtonShown then ns.SetMinimapButtonShown(value) end end)
	Button(L.KEYBINDS, L.KEYBINDS_BUTTON, L.KEYBINDS_DESC, function()
		if Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
			Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
		end
	end)
	Button(L.WELCOME_SHOW, L.WELCOME_SHOW_BUTTON, L.WELCOME_SHOW_DESC, function()
		-- The options step aside: the welcome screen takes their place.
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		if ns.ShowWelcome then ns.ShowWelcome() end
	end)
	Button(L.NEWS_SHOW, L.NEWS_SHOW_BUTTON, L.NEWS_SHOW_DESC, function()
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		if ns.ShowNews then ns.ShowNews() end
	end)

	-- Where the other settings are.
	Header(L.SECTION_PAGES)

	Header(L.SECTION_RESTORE)
	Button(L.RESTORE, L.RESTORE_BUTTON, L.RESTORE_DESC, function()
		ns.SetEnabled(false)
		ns.Print(L.MSG_RESTORED)
	end)
	Button(L.RESET_PROFILE, L.RESET_PROFILE_BUTTON, L.RESET_PROFILE_DESC, function()
		Popup("WANDERER_RESET_PROFILE", ns.profileName)
	end)

	Header(L.SECTION_DEV)
	Button(L.TEST_WHISPER, L.TEST_WHISPER_BUTTON, L.TEST_WHISPER_DESC, function() ns.WhisperMyself() end)
end

local function NamesPage()
	Page(L.PAGE_NAMES)
	-- Only the categories this game client supports.
	Header(L.SECTION_NAMES)
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

	Header(L.SECTION_COMBAT)
	Checkbox("COMBAT_ENEMIES", L.COMBAT_ENEMIES, L.COMBAT_ENEMIES_DESC, true,
		function() return ns.db.combatEnemies end,
		function(value) ns.db.combatEnemies = value; ns.Apply() end)

	Header(L.SECTION_ZONES)
	local zoneChoices = {}
	for _, choice in ipairs(ns.ZONE_CHOICES) do
		zoneChoices[#zoneChoices + 1] = { choice, choice == "default" and L.ZONE_DEFAULT or L["PRESET_" .. choice:upper()] }
	end
	for _, zone in ipairs(ns.ZONES) do
		Dropdown("ZONE_" .. zone:upper(), L["ZONE_" .. zone:upper()], L.ZONE_DESC, ns.DEFAULTS.zones[zone], zoneChoices,
			function() return ns.db.zones[zone] end,
			function(value) ns.db.zones[zone] = value; ns.Apply() end)
	end

	Header(L.SECTION_REVEAL)
	Dropdown("REVEAL_MODE", L.REVEAL_MODE, L.REVEAL_DESC, "hold",
		{ { "hold", L.REVEAL_HOLD }, { "toggle", L.REVEAL_TOGGLE } },
		function() return ns.db.revealMode end,
		function(value) ns.db.revealMode = value; ns.SetRevealing(false) end)
end

local function LabelPage()
	Page(L.PAGE_LABEL)
	ns.PREVIEW_CATEGORIES[category] = true
	local labelOn = IsOn("label", "enabled")
	local enabled = LabelCheckbox("enabled", L.LABEL_ENABLE, L.LABEL_ENABLE_DESC)

	Header(L.SECTION_LOOK)
	local styleChoices = {}
	for _, style in ipairs(ns.STYLES) do styleChoices[#styleChoices + 1] = { style, L["STYLE_" .. style:upper()] } end
	Under(Dropdown("LABEL_STYLE", L.LABEL_STYLE, L.LABEL_STYLE_DESC, "blizzard", styleChoices,
		function() return ns.db.label.style end,
		function(value) ns.db.label.style = value; ns.RefreshAll() end), enabled, labelOn)
	local fontChoices = {}
	for _, font in ipairs(ns.FONTS) do fontChoices[#fontChoices + 1] = { font.key, L["FONT_" .. font.key:upper()] } end
	Under(Dropdown("LABEL_FONT", L.LABEL_FONT, L.LABEL_FONT_DESC, "default", fontChoices,
		function() return ns.db.label.font end,
		function(value) ns.db.label.font = value; ns.RefreshAll() end), enabled, labelOn)
	Under(Slider("LABEL_SCALE", L.LABEL_SCALE, "label.scale", "%.1f", ns.RefreshAll), enabled, labelOn)
	Under(Slider("LABEL_PADDING", L.LABEL_PADDING, "label.padding", "%d", ns.RefreshAll), enabled, labelOn)
	Under(Slider("LABEL_BG_OPACITY", L.LABEL_BG_OPACITY, "label.bgOpacity", "%d %%", ns.RefreshAll), enabled, labelOn)

	Header(L.SECTION_POSITION)
	Under(Dropdown("LABEL_ANCHOR", L.LABEL_ANCHOR, L.LABEL_ANCHOR_DESC, "head",
		{ { "head", L.ANCHOR_HEAD }, { "cursor", L.ANCHOR_CURSOR } },
		function() return ns.db.label.anchor end,
		function(value) ns.db.label.anchor = value end), enabled, labelOn)
	Under(Slider("LABEL_OFFSET", L.LABEL_OFFSET, "label.offset", "%d"), enabled, labelOn)
	Under(TableCheckbox("label", "allHeads", L.LABEL_ALL_HEADS, L.LABEL_ALL_HEADS_DESC, function()
		ns.Apply()
		ns.RefreshPlates()
	end), enabled, labelOn)
	Under(LabelCheckbox("worldOnly", L.LABEL_WORLD_ONLY, L.LABEL_WORLD_ONLY_DESC), enabled, labelOn)
	Under(LabelCheckbox("hideInCombat", L.LABEL_COMBAT), enabled, labelOn)

	Header(L.SECTION_TARGET)
	TableCheckbox("label", "targetName", L.LABEL_TARGET_NAME, L.LABEL_TARGET_NAME_DESC, ns.RefreshTargetLabel)

	Header(L.SECTION_HIGHLIGHTS)
	LabelCheckbox("highlight", L.LABEL_HIGHLIGHT, L.LABEL_HIGHLIGHT_DESC)
	LabelCheckbox("highlightQuest", L.LABEL_HIGHLIGHT_QUEST, L.LABEL_HIGHLIGHT_QUEST_DESC)
	LabelCheckbox("highlightRelations", L.LABEL_HIGHLIGHT_RELATIONS, L.LABEL_HIGHLIGHT_RELATIONS_DESC)
	LabelCheckbox("highlightRank", L.LABEL_HIGHLIGHT_RANK, L.LABEL_HIGHLIGHT_RANK_DESC)

	Header(L.SECTION_THREAT)
	local threat = LabelCheckbox("threatAlert", L.LABEL_THREAT, L.LABEL_THREAT_DESC)
	local threatOn = IsOn("label", "threatAlert")
	Under(LabelCheckbox("threatSound", L.LABEL_THREAT_SOUND, L.LABEL_THREAT_SOUND_DESC), threat, threatOn)
	Under(LabelCheckbox("threatVignette", L.LABEL_THREAT_VIGNETTE, L.LABEL_THREAT_VIGNETTE_DESC), threat, threatOn)
end

local function ContentPage()
	Page(L.PAGE_CONTENT)
	ns.PREVIEW_CATEGORIES[category] = true
	Header(L.SECTION_PLAYERS)
	LabelCheckbox("showRace", L.LABEL_RACE)
	LabelCheckbox("showClass", L.LABEL_CLASS)
	LabelCheckbox("showSpec", L.LABEL_SPEC, L.LABEL_SPEC_DESC)
	LabelCheckbox("showGuild", L.LABEL_GUILD)
	local faction = LabelCheckbox("showFaction", L.LABEL_FACTION)
	Under(LabelCheckbox("showNPCFaction", L.LABEL_NPC_FACTION, L.LABEL_NPC_FACTION_DESC), faction, IsOn("label", "showFaction"))
	LabelCheckbox("showStatus", L.LABEL_STATUS, L.LABEL_STATUS_DESC)

	Header(L.SECTION_CREATURES)
	LabelCheckbox("showCreatureType", L.LABEL_CREATURE_TYPE, L.LABEL_CREATURE_TYPE_DESC)
	LabelCheckbox("showClassification", L.LABEL_CLASSIFICATION, L.LABEL_CLASSIFICATION_DESC)
	LabelCheckbox("showNPCRole", L.LABEL_NPC_ROLE, L.LABEL_NPC_ROLE_DESC)
	LabelCheckbox("showReputation", L.LABEL_REPUTATION, L.LABEL_REPUTATION_DESC)
	LabelCheckbox("showTameable", L.LABEL_TAMEABLE, L.LABEL_TAMEABLE_DESC)
	LabelCheckbox("showRareKills", L.LABEL_RARE_KILLS, L.LABEL_RARE_KILLS_DESC)
	LabelCheckbox("untagged", L.LABEL_UNTAGGED, L.LABEL_UNTAGGED_DESC)

	Header(L.SECTION_EVERYONE)
	local level = LabelCheckbox("showLevel", L.LABEL_LEVEL)
	Under(LabelCheckbox("showDifficulty", L.LABEL_DIFFICULTY, L.LABEL_DIFFICULTY_DESC), level, IsOn("label", "showLevel"))
	LabelCheckbox("showXP", L.LABEL_XP, L.LABEL_XP_DESC)
	LabelCheckbox("showPortrait", L.LABEL_PORTRAIT, L.LABEL_PORTRAIT_DESC)
	LabelCheckbox("showHealth", L.LABEL_HEALTH, L.LABEL_HEALTH_DESC)
	LabelCheckbox("showTarget", L.LABEL_TARGET, L.LABEL_TARGET_DESC)

	Header(L.SECTION_ACTIONS)
	LabelCheckbox("showProfessions", L.LABEL_PROFESSIONS, L.LABEL_PROFESSIONS_DESC)
	LabelCheckbox("showLoot", L.LABEL_LOOT, L.LABEL_LOOT_DESC)
	LabelCheckbox("showObjects", L.LABEL_OBJECTS, L.LABEL_OBJECTS_DESC)
	LabelCheckbox("showQuests", L.LABEL_QUESTS, L.LABEL_QUESTS_DESC)

	Header(L.SECTION_RP)
	TableCheckbox("rp", "useName", L.RP_NAME, L.RP_NAME_DESC, ns.RefreshLabel)
	TableCheckbox("rp", "showTitle", L.RP_TITLE, nil, ns.RefreshLabel)
	TableCheckbox("rp", "showStatus", L.RP_STATUS, L.RP_STATUS_DESC, ns.RefreshLabel)
end

local function TooltipsPage()
	Page(L.PAGE_TOOLTIPS)
	local styled = TableCheckbox("tooltips", "enabled", L.TOOLTIPS_STYLE, L.TOOLTIPS_STYLE_DESC, ns.RefreshTooltips)
	local styledOn = IsOn("tooltips", "enabled")
	Under(TableCheckbox("tooltips", "cursor", L.TOOLTIPS_CURSOR, L.TOOLTIPS_CURSOR_DESC), styled, styledOn)
	Under(TableCheckbox("tooltips", "icon", L.TOOLTIPS_ICON, L.TOOLTIPS_ICON_DESC), styled, styledOn)
	Under(TableCheckbox("tooltips", "quality", L.TOOLTIPS_QUALITY, L.TOOLTIPS_QUALITY_DESC), styled, styledOn)
	Checkbox("HIDE_TOOLTIP", L.HIDE_TOOLTIP, L.HIDE_TOOLTIP_DESC, false,
		function() return ns.db.hideUnitTooltip end,
		function(value) ns.db.hideUnitTooltip = value end)
end

local function InterfacePage()
	Page(L.PAGE_INTERFACE)
	Header(L.SECTION_FADE)
	local combatOnly = TableCheckbox("cinema", "combatOnly", L.CINEMA_COMBAT_ONLY, L.CINEMA_COMBAT_ONLY_DESC, ns.RefreshCinema)
	TableCheckbox("cinema", "enabled", L.CINEMA_ENABLE, L.CINEMA_ENABLE_DESC, ns.RefreshCinema)
	-- Opacity and delay serve both rules.
	local fading = function() return ns.db and (ns.db.cinema.combatOnly or ns.db.cinema.enabled) and true or false end
	Under(Slider("CINEMA_ALPHA", L.CINEMA_ALPHA, "cinema.alpha", "%d %%"), combatOnly, fading)
	Under(Slider("CINEMA_DELAY", L.CINEMA_DELAY, "cinema.delay", "%d s"), combatOnly, fading)

	Header(L.SECTION_CLEAN)
	TableCheckbox("world", "cleanMinimap", L.CLEAN_MINIMAP, L.CLEAN_MINIMAP_DESC, ns.RefreshClean)
	TableCheckbox("world", "cleanTracker", L.CLEAN_TRACKER, L.CLEAN_TRACKER_DESC, ns.RefreshClean)
	TableCheckbox("world", "gatherIcons", L.GATHER_ICONS, L.GATHER_ICONS_DESC, ns.RefreshIcons)
	TableCheckbox("world", "moveFrames", L.MOVE_FRAMES, L.MOVE_FRAMES_DESC, ns.RefreshGameFrames)

	Header(L.SECTION_THREAT_GROUP)
	TableCheckbox("threat", "show", L.THREAT_SHOW, L.THREAT_SHOW_DESC, ns.RefreshTargetInfo)
	TableCheckbox("threat", "alert", L.THREAT_ALERT, L.THREAT_ALERT_DESC)

	Header(L.SECTION_SCREEN)
	TableCheckbox("world", "filterErrors", L.WORLD_ERRORS, L.WORLD_ERRORS_DESC, ns.RefreshScreen)
	TableCheckbox("world", "hideTalkingHead", L.WORLD_TALKING_HEAD, L.WORLD_TALKING_HEAD_DESC)

end

-- The action bars: their slots, and the Edit Mode layouts that place them.
local function ActionBarsPage()
	Page(L.PAGE_ACTION_BARS)
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
			for _, name in ipairs(ns.EditModeLayouts and ns.EditModeLayouts() or {}) do list[#list + 1] = { name, name } end
			return list
		end,
		function() return ns.db.world.editLayout end,
		function(value)
			ns.db.world.editLayout = value
			ns.ApplyEditLayout()
		end)
end

-- Immersion: the camera, travels, photos, gestures and the sounds of the world.
local function ImmersionPage()
	Page(L.PAGE_IMMERSION)
	Header(L.SECTION_TRAVEL)
	local travel = TableCheckbox("travel", "enabled", L.TRAVEL_ENABLE, L.TRAVEL_ENABLE_DESC)
	Under(TableCheckbox("travel", "camera", L.TRAVEL_CAMERA, L.TRAVEL_CAMERA_DESC), travel, IsOn("travel", "enabled"))
	Button(L.PHOTO, L.PHOTO_BUTTON, L.PHOTO_DESC, function()
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		ns.TogglePhotoMode()
	end)

	Header(L.SECTION_AWAY)
	local away = TableCheckbox("away", "enabled", L.AWAY_ENABLE, L.AWAY_ENABLE_DESC, ns.RefreshAway)
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
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		ns.GoAway()
	end)

	Header(L.SECTION_GESTURES)
	TableCheckbox("gestures", "read", L.GESTURES_READ, L.GESTURES_READ_DESC)
	TableCheckbox("gestures", "levelUp", L.GESTURES_LEVEL, L.GESTURES_LEVEL_DESC)
	TableCheckbox("gestures", "greet", L.GESTURES_GREET, L.GESTURES_GREET_DESC)

	Header(L.SECTION_CAMERA)
	TableCheckbox("world", "actionCam", L.WORLD_ACTION_CAM, L.WORLD_ACTION_CAM_DESC, ns.RefreshAll)

	Header(L.SECTION_SOUNDS)
	local sounds = TableCheckbox("sounds", "enabled", L.SOUNDS_ENABLE, L.SOUNDS_ENABLE_DESC, ns.RefreshSounds)
	Under(Button(L.SOUNDS_LIST, L.SOUNDS_LIST_BUTTON, L.SOUNDS_LIST_DESC, function() ns.EditSounds() end),
		sounds, IsOn("sounds", "enabled"))
end

local function ConversationsPage()
	Page(L.PAGE_CONVERSATIONS)
	Header(L.SECTION_SCENE)
	local scene = TableCheckbox("scene", "enabled", L.SCENE_ENABLE, L.SCENE_ENABLE_DESC, ns.RefreshScene)
	Under(Slider("SCENE_TEXT_SIZE", L.SCENE_TEXT_SIZE, "scene.textSize", "%d"), scene, IsOn("scene", "enabled"))
	TableCheckbox("scene", "camera", L.SCENE_CAMERA, L.SCENE_CAMERA_DESC)

	Header(L.SECTION_QUESTS)
	TableCheckbox("quest", "autoAccept", L.QUEST_AUTO_ACCEPT, L.QUEST_AUTO_ACCEPT_DESC)
	TableCheckbox("quest", "autoTurnIn", L.QUEST_AUTO_TURNIN, L.QUEST_AUTO_TURNIN_DESC)
	TableCheckbox("quest", "bestReward", L.QUEST_BEST_REWARD, L.QUEST_BEST_REWARD_DESC)

	Header(L.SECTION_DIALOGUES)
	TableCheckbox("quest", "skipGossip", L.QUEST_SKIP_GOSSIP, L.QUEST_SKIP_GOSSIP_DESC)
end

local function MerchantsPage()
	Page(L.PAGE_MERCHANTS)
	Header(L.SECTION_MERCHANT)
	TableCheckbox("merchant", "sellJunk", L.MERCHANT_SELL_JUNK, L.MERCHANT_SELL_JUNK_DESC)
	local repair = TableCheckbox("merchant", "repair", L.MERCHANT_REPAIR, L.MERCHANT_REPAIR_DESC)
	Under(TableCheckbox("merchant", "guildRepair", L.MERCHANT_GUILD_REPAIR, L.MERCHANT_GUILD_REPAIR_DESC),
		repair, IsOn("merchant", "repair"))

	Header(L.SECTION_TRAINERS)
	TableCheckbox("trainer", "learnAll", L.TRAINER_LEARN_ALL_OPTION, L.TRAINER_LEARN_ALL_DESC, ns.RefreshTrainer)

	Header(L.SECTION_LOOT)
	TableCheckbox("loot", "fast", L.LOOT_FAST, L.LOOT_FAST_DESC)
end

local function AdventurePage()
	Page(L.PAGE_ADVENTURE)
	Header(L.SECTION_JOURNAL)
	local journal = TableCheckbox("journal", "enabled", L.JOURNAL_ENABLE, L.JOURNAL_ENABLE_DESC)
	local journalOn = IsOn("journal", "enabled")
	Under(Button(L.JOURNAL_OPEN, L.JOURNAL_OPEN_BUTTON, L.JOURNAL_OPEN_DESC, function() ns.ToggleJournal() end),
		journal, journalOn)
	Under(TableCheckbox("journal", "notices", L.JOURNAL_NOTICES, L.JOURNAL_NOTICES_DESC), journal, journalOn)
	Under(TableCheckbox("journal", "sound", L.JOURNAL_SOUND, L.JOURNAL_SOUND_DESC), journal, journalOn)
	Under(TableCheckbox("journal", "deaths", L.JOURNAL_DEATHS, L.JOURNAL_DEATHS_DESC), journal, journalOn)

	Header(L.SECTION_FISHING)
	TableCheckbox("fishing", "doubleClick", L.FISHING_DOUBLE_CLICK, L.FISHING_DOUBLE_CLICK_DESC)

	Header(L.SECTION_SESSION)
	Slider("SESSION_BREAK", L.SESSION_BREAK, "session.breakEvery",
		function(value) return value == 0 and L.NEVER or L.MINUTES:format(value) end, ns.RefreshSession)
	Button(L.SESSION_SHOW, L.SESSION_SHOW_BUTTON, L.SESSION_SHOW_DESC, function() ns.PrintSession() end)
end

local function SocialPage()
	Page(L.PAGE_SOCIAL)
	Header(L.SECTION_REQUESTS)
	TableCheckbox("social", "declineDuels", L.SOCIAL_DUELS, L.SOCIAL_DUELS_DESC)
	TableCheckbox("social", "acceptInvites", L.SOCIAL_INVITES, L.SOCIAL_INVITES_DESC)
	TableCheckbox("social", "acceptResurrect", L.SOCIAL_RESURRECT, L.SOCIAL_RESURRECT_DESC)
	TableCheckbox("social", "acceptSummon", L.SOCIAL_SUMMON, L.SOCIAL_SUMMON_DESC)

	Header(L.SECTION_MESSAGES)
	local messages = TableCheckbox("messages", "enabled", L.MESSAGES_ENABLE, L.MESSAGES_ENABLE_DESC, ns.RefreshMinimapButton)
	local messagesOn = IsOn("messages", "enabled")
	Under(TableCheckbox("messages", "popup", L.MESSAGES_POPUP, L.MESSAGES_POPUP_DESC), messages, messagesOn)
	Under(TableCheckbox("messages", "hideInChat", L.MESSAGES_HIDE_CHAT, L.MESSAGES_HIDE_CHAT_DESC), messages, messagesOn)
	Under(TableCheckbox("messages", "sound", L.MESSAGES_SOUND, L.MESSAGES_SOUND_DESC), messages, messagesOn)
	Under(Button(L.MESSAGES_OPEN, L.MESSAGES_OPEN_BUTTON, nil, function() ns.ToggleMessages() end), messages, messagesOn)

	Header(L.SECTION_CHAT)
	TableCheckbox("chat", "group", L.CHAT_TAB_GROUP, L.CHAT_TAB_GROUP_DESC)
	TableCheckbox("chat", "guild", L.CHAT_TAB_GUILD, L.CHAT_TAB_GUILD_DESC)
	TableCheckbox("chat", "whispers", L.CHAT_TAB_WHISPERS, L.CHAT_TAB_WHISPERS_DESC)
	TableCheckbox("chat", "arrowHistory", L.CHAT_ARROWS, L.CHAT_ARROWS_DESC, ns.RefreshChatComfort)
	TableCheckbox("chat", "copyButton", L.CHAT_COPY_BUTTON, L.CHAT_COPY_BUTTON_DESC, ns.RefreshChatComfort)
	Button(L.CHAT_TABS, L.CHAT_TABS_BUTTON, L.CHAT_TABS_DESC, function() ns.CreateChatTabs() end)
end

local function ProfilesPage()
	Page(L.PAGE_PROFILES)
	Dropdown("PROFILE", L.PROFILE, L.PROFILE_DESC, "Default",
		function()
			local list = {}
			for _, name in ipairs(ns.ListProfiles()) do list[#list + 1] = { name, name } end
			return list
		end,
		function() return ns.profileName end,
		function(value) ns.SetProfile(value) end)
	Button(L.PROFILE_NEW, L.PROFILE_NEW, nil, function() Popup("WANDERER_NEW_PROFILE") end)
	Button(L.PROFILE_COPY, L.PROFILE_COPY, nil, function() Popup("WANDERER_COPY_PROFILE") end)
	Button(L.PROFILE_DELETE, L.PROFILE_DELETE, nil, function() Popup("WANDERER_DELETE_PROFILE") end)

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
	Button(L.PROFILE_EXPORT, L.PROFILE_EXPORT, L.PROFILE_EXPORT_DESC, function() Popup("WANDERER_EXPORT_PROFILE") end)
	Button(L.PROFILE_IMPORT, L.PROFILE_IMPORT, L.PROFILE_IMPORT_DESC, function() Popup("WANDERER_IMPORT_PROFILE") end)
end

function ns.InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
	RegisterDialogs()
	HomePage()
	-- First folded page: the predefined styles (cards with previews).
	if ns.RegisterThemesPage and Settings.RegisterVerticalLayoutSubcategory then ns.RegisterThemesPage(mainCategory) end
	for _, page in ipairs({ NamesPage, LabelPage, ContentPage, TooltipsPage, InterfacePage, ActionBarsPage, ImmersionPage,
		ConversationsPage, MerchantsPage, AdventurePage, SocialPage, ProfilesPage }) do
		page()
	end
	Settings.RegisterAddOnCategory(mainCategory)
end
