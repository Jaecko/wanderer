local _, ns = ...

-- What you changed: every setting of the active profile that is not as its reference (the profile's way to play
-- for the settings a way writes, Wanderer's default for the others: a way just picked is no change), named as
-- the options name it (Options.lua keeps each option's words: ns.OPTION_WORDS), your value beside the
-- reference, a reset per line (back to the reference: the way stays) and one undo for the last reset (its
-- page: SettingsWindow.lua). Nothing else: the whole profile is reset from the settings' home page.

local L = ns.L

local SKIP = { styleVersion = true } -- kept by Wanderer itself, not a choice
local EPSILON = 0.001 -- (a slider's value saved back: the same)

local function Same(a, b)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < EPSILON end
	return a == b
end

-- "LABEL_SCALE", "label.scale": the same words once capitals, dots and underscores are aside.
local function Plain(text) return (text:upper():gsub("[%._]", "")) end

-- An option's words ({ label, page, order, format, choices }) by its path in the profile; nil: not an option
-- the options show (kept by Wanderer itself).
-- (the variables by their plain names: made once for a whole list, not once per setting)
local function ByPlain(known)
	local byPlain = {}
	for variable, words in pairs(known.variables) do byPlain[Plain(variable)] = words end
	return byPlain
end

function ns.OptionWords(path, byPlain)
	local known = ns.OPTION_WORDS
	if not (known and type(path) == "string") then return nil end
	if known.paths[path] then return known.paths[path] end
	byPlain = byPlain or ByPlain(known)
	-- (else by its variable's name: "combatEnemies" is COMBAT_ENEMIES, "zones.city" is ZONE_CITY)
	local plain = Plain(path)
	if byPlain[plain] then return byPlain[plain] end
	local first, rest = path:match("^(%w-)s(%..+)$")
	return first and byPlain[Plain(first .. rest)] or nil
end

-- A path's place in a profile (the active one by default): the table that holds it and its key (nil when a
-- table on the way is missing).
local function Holder(path, root)
	local at, key = root or ns.db, nil
	for part in path:gmatch("[^%.]+") do
		if key then
			at = type(at) == "table" and at[key] or nil
			if type(at) ~= "table" then return nil end
		end
		key = part
	end
	return at, key
end

-- Each setting of the profile ({ path, value, reference }) by DEFAULTS, the scalar ones; the reference is the
-- profile's way's value when the way writes the setting, else the default.
local function Each(fn)
	local function Walk(defaults, values, path)
		for key, default in pairs(defaults) do
			if type(key) == "string" and not SKIP[key] and not key:match("Pos$") then
				local full = path and (path .. "." .. key) or key
				local value
				if type(values) == "table" then value = values[key] end
				if type(default) == "table" then
					Walk(default, value, full)
				else
					local way = ns.WayValue and ns.WayValue(full)
					if way ~= nil then default = way end
					fn(full, value, default)
				end
			end
		end
	end
	if ns.DEFAULTS and ns.db then Walk(ns.DEFAULTS, ns.db) end
end

-- The profile as its references make it (DEFAULTS with the way's values laid over): what a composite choice
-- reads as its reference.
local function Reference()
	local reference = ns.Util.Copy(ns.DEFAULTS)
	Each(function(path, _, value)
		local at, key = Holder(path, reference)
		if at then at[key] = value end
	end)
	return reference
end

-- The settings you changed, in the options' order: { { path, paths, value, default, words } } (paths: every
-- setting the line resets). One choice written in several settings (its words can read it: the fade, the
-- minimap's and the tracker's looks) is one line, its value the choice, all of its settings reset with it.
function ns.ChangedSettings()
	local list, composite, reference = {}, {}, nil
	local byPlain = ns.OPTION_WORDS and ByPlain(ns.OPTION_WORDS)
	Each(function(path, value, default)
		local words = ns.OptionWords(path, byPlain)
		if not words then return end
		if type(words.read) == "function" then
			local entry = composite[words]
			if not entry then
				reference = reference or Reference()
				entry = { path = path, paths = {}, words = words, value = words.read(), default = words.read(reference) }
				composite[words] = entry
			end
			entry.paths[#entry.paths + 1] = path
			if path < entry.path then entry.path = path end
		elseif type(value) == type(default) and not Same(value, default) then
			list[#list + 1] = { path = path, paths = { path }, value = value, default = default, words = words }
		end
	end)
	for _, entry in pairs(composite) do
		if entry.value ~= entry.default then list[#list + 1] = entry end
	end
	table.sort(list, function(a, b)
		if a.words.order ~= b.words.order then return (a.words.order or 0) < (b.words.order or 0) end
		return a.path < b.path
	end)
	return list
end

-- A value as the options say it: on or off, the dropdown's words, the slider's format.
function ns.SettingText(words, value)
	if type(value) == "boolean" then return value and L.CHANGES_ON or L.CHANGES_OFF end
	words = words or {}
	if type(value) == "string" then
		local choices = words.choices
		if type(choices) == "function" then
			local ok, made = pcall(choices)
			choices = ok and made or nil
		end
		for _, choice in ipairs(type(choices) == "table" and choices or {}) do
			if choice[1] == value then return tostring(choice[2]) end
		end
		return value
	end
	if type(value) == "number" then
		local format = words.format
		if type(format) == "function" then
			local ok, text = pcall(format, value)
			if ok and text then return tostring(text) end
		elseif type(format) == "string" then
			local ok, text = pcall(string.format, format, value)
			if ok then return text end
		end
		return value == math.floor(value) and tostring(value) or ("%.2f"):format(value)
	end
	return tostring(value)
end

local function Read(path)
	local at, key = Holder(path)
	if at then return at[key] end
end

-- Every scalar setting as it is now (to tell what a reset touched).
local function Snapshot()
	local values = {}
	Each(function(path, value) values[path] = value end)
	return values
end

-- The last reset: what it changed (path -> { before, after }), in which profile; one at a time.
local undo

local function Refresh()
	if ns.RefreshAll then ns.RefreshAll() end
	if ns.RefreshThemeGrids then pcall(ns.RefreshThemeGrids) end
end

-- One setting back to its reference (its way's value, else its default), as the options would set it (the same
-- in this character's other profiles; a preset or a label level brings its lines with it).
function ns.ResetSetting(path)
	return ns.ResetSettings({ path })
end

-- Several settings back to their references at once (a row, a page): one undo for all of them.
function ns.ResetSettings(paths)
	local defaults = {}
	Each(function(each, _, value) defaults[each] = value end)
	local list = {}
	for _, path in ipairs(type(paths) == "table" and paths or {}) do
		if defaults[path] ~= nil and Holder(path) then list[#list + 1] = path end
	end
	if not list[1] then return false end
	-- (a preset or a label level last: it brings its lines with it, over those reset one by one)
	local last = { preset = 2, ["label.content"] = 1 }
	table.sort(list, function(a, b) return (last[a] or 0) < (last[b] or 0) end)
	local before = Snapshot()
	ns.ChangeEverywhere(function()
		for _, path in ipairs(list) do
			local default = defaults[path]
			if path == "preset" and ns.PRESETS[default] then
				ns.SetPreset(default)
			elseif path == "label.content" and default ~= "custom" and ns.SetLabelContent then
				ns.SetLabelContent(default)
			else
				local at, key = Holder(path)
				if at then at[key] = default end
				-- (a line of names set alone: the preset is your own)
				if path:match("^show%.") then ns.db.preset = "custom" end
			end
		end
	end)
	local after, touched = Snapshot(), {}
	for each, value in pairs(after) do
		if not Same(value, before[each]) then touched[each] = { before = before[each], after = value } end
	end
	undo = { profile = ns.profileName, db = ns.db, touched = touched }
	Refresh()
	return true
end

-- The last reset can be taken back: same profile, and nothing it touched changed since.
function ns.CanUndoReset()
	if not (undo and undo.db == ns.db and undo.profile == ns.profileName) then return false end
	for path, change in pairs(undo.touched) do
		if not Same(Read(path), change.after) then return false end
	end
	return next(undo.touched) ~= nil
end

function ns.UndoReset()
	if not ns.CanUndoReset() then
		undo = nil
		return false
	end
	local touched = undo.touched
	undo = nil
	ns.ChangeEverywhere(function()
		for path, change in pairs(touched) do
			local at, key = Holder(path)
			if at then at[key] = change.before end
		end
	end)
	Refresh()
	return true
end
