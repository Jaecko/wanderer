local _, ns = ...

-- The characters of this account, as Wanderer met them: name, realm, class,
-- faction, level, gold, when last seen. Kept in the account's saved variables
-- and read by the extensions (your gold on every character, what another
-- one carries, a letter's recipient). Nothing is guessed: a character is
-- known once it has logged in with Wanderer.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local function Ledger()
	local root = ns.root
	if not root then return nil end
	root.characters = type(root.characters) == "table" and root.characters or {}
	return root.characters
end

-- The account's overview: rested experience, professions, their cooldowns ----------------------------------
-- Read while a character plays and kept with its line; while it is away, its rested experience grows as the
-- game makes it grow (5 % of a level each 8 hours in an inn or a city, a quarter of that elsewhere, a level and
-- a half at most): an estimate until it logs in again.
local RESTED_RATE = 0.05 / (8 * 3600) -- of a level, each second resting
local RESTED_OUTSIDE = 0.25
local RESTED_MOST = 1.5
local CEILING_TOP = 300 -- the last rank of a profession: no trainer above it
local LETTERS_SOON = 3 * 86400 -- letters leaving within three days: said on the row

-- The cooldowns of professions worth a look from another character: the transmutes (one cooldown for all),
-- the mooncloth, the salt shaker (an item's).
local COOLDOWNS = {
	{ spells = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566 }, cut = true },
	{ spells = { 18560 } },
	{ item = 15846 },
}

-- When a cooldown ends (time()), from the game's start and duration (GetTime()); now when it is not running.
local function ReadyAt(start, duration)
	start, duration = Clean(start), Clean(duration)
	if not (start and duration) then return nil end
	if start <= 0 or duration <= 2 then return time() end -- (a global cooldown aside)
	return time() + math.max(0, math.floor(start + duration - GetTime()))
end

local function SpellReadyAt(id)
	local api = C_Spell and C_Spell.GetSpellCooldown
	if api then
		local info = Safe(api, id)
		if type(info) == "table" then return ReadyAt(info.startTime, info.duration) end
		return nil
	end
	return ReadyAt(Safe(GetSpellCooldown, id))
end

-- This character's cooldowns it can use: { { name, ready } } (ready: time()).
local function Cooldowns()
	local list = {}
	for _, cooldown in ipairs(COOLDOWNS) do
		if cooldown.item then
			if U.ItemCount(cooldown.item) > 0 then
				local api = C_Container and C_Container.GetItemCooldown or GetItemCooldown
				local ready = ReadyAt(Safe(api, cooldown.item))
				local name = U.ItemName(cooldown.item)
				if ready and name then list[#list + 1] = { name = name, ready = ready } end
			end
		else
			for _, id in ipairs(cooldown.spells) do
				if Clean(Safe(IsPlayerSpell, id)) then
					local name = Clean(Safe(C_Spell and C_Spell.GetSpellName, id))
					-- ("Transmute: Arcanite": the words before the colon name them all)
					if name and cooldown.cut then name = name:match("^(.-)%s*:") or name:match("^(.-)\239\188\154") or name end
					local ready = SpellReadyAt(id)
					if name and name ~= "" and ready then list[#list + 1] = { name = name, ready = ready } end
					break
				end
			end
		end
	end
	return list
end

-- This character's professions: { { name, rank, max } }.
local function Crafts()
	local list = {}
	for _, index in pairs({ Safe(GetProfessions) }) do
		local name, _, rank, max = Safe(GetProfessionInfo, index)
		name, rank, max = Clean(name), Clean(rank), Clean(max)
		if name and rank then list[#list + 1] = { name = name, rank = rank, max = max or 0 } end
	end
	return list
end

-- A profession at its ceiling: a trainer teaches the next rank.
function ns.AtCeiling(craft)
	local rank, max = tonumber(craft.rank), tonumber(craft.max)
	return rank ~= nil and max ~= nil and max > 0 and max < CEILING_TOP and rank >= max
end

-- A character's rested experience, as a share of a level (1.5 at most), and whether it is estimated (away
-- since it was read); nil when unknown or at the last level.
function ns.RestedShare(entry, now)
	if type(entry) ~= "table" then return nil end
	local rested, most = tonumber(entry.rested), tonumber(entry.xpMax)
	if not (rested and most and most > 0) then return nil end
	now = now or time()
	local share = rested / most
	local since = now - (tonumber(entry.restedAt) or now)
	local estimated = since > 60
	if estimated then share = share + since * RESTED_RATE * (entry.resting and 1 or RESTED_OUTSIDE) end
	return math.min(RESTED_MOST, share), estimated
end

-- The extensions' lines in a character's hover (W.CharacterLine): fn(character key) -> { text, r, g, b, chip } or
-- nil. key: one provider for that kind of line (a new one takes its place).
local providers = {}

function ns.CharacterLine(fn, key) U.Provide(providers, fn, key) end

local function Provided(key)
	for _, known in ipairs(providers) do
		if known.key == key then return true end
	end
	return false
end

-- (until Wanderer Mail gives its own line: its letters leaving, read as it kept them; gone once it does)
local function Letters(key)
	local account = rawget(_G, "WandererMailAccountDB")
	local letters = type(account) == "table" and type(account.letters) == "table" and account.letters
	local entry = letters and letters[key]
	local leaves = type(entry) == "table" and tonumber(entry.leaves)
	if leaves and leaves > time() then return leaves, tonumber(entry.count) or 1 end
end

-- The extensions' lines of a character, in their order (one failing: left out).
function ns.CharacterLines(key)
	local lines = {}
	for _, provider in ipairs(providers) do
		local ok, line = pcall(provider.fn, key)
		if ok and type(line) == "table" and type(line.text) == "string" and line.text ~= "" then lines[#lines + 1] = line end
	end
	return lines
end

-- This character, as it is now (level: the new one, from PLAYER_LEVEL_UP; UnitLevel still says the old one).
local function Note(level)
	local ledger = Ledger()
	if not ledger then return end
	local key = ns.CharacterKey()
	local entry = type(ledger[key]) == "table" and ledger[key] or {}
	ledger[key] = entry
	-- (its whole name: WoW Forever's names may have several words)
	entry.name = Clean(U.FullName("player")) or Clean(Safe(UnitName, "player")) or entry.name
	entry.realm = Clean(Safe(GetRealmName)) or entry.realm
	local _, class = Safe(UnitClass, "player")
	entry.class = Clean(class) or entry.class
	entry.faction = Clean(Safe(UnitFactionGroup, "player")) or entry.faction
	entry.level = Clean(level) or Clean(Safe(UnitLevel, "player")) or entry.level
	entry.money = Clean(Safe(GetMoney)) or entry.money
	entry.seen = time()
	-- Its rested experience now, and where it rests (an inn, a city: the faster way).
	local last = Clean(Safe(GetMaxPlayerLevel)) or 60
	local most = Clean(Safe(UnitXPMax, "player"))
	if (tonumber(entry.level) or 0) < last and most and most > 0 then
		entry.rested, entry.xpMax = Clean(Safe(GetXPExhaustion)) or 0, most
		entry.resting = Clean(Safe(IsResting)) and true or nil
		entry.restedAt = entry.seen
	else
		entry.rested, entry.xpMax, entry.resting, entry.restedAt = nil, nil, nil, nil
	end
	local crafts = Crafts()
	if crafts[1] or not entry.crafts then entry.crafts = crafts end
	entry.cooldowns = Cooldowns()
end

-- Every character known, the last seen first: { key, name, realm, class, faction, level, money, seen, me, main }.
-- `others`: without this one.
function ns.Characters(others)
	local list = {}
	local me = ns.CharacterKey()
	for key, entry in pairs(Ledger() or {}) do
		if type(entry) == "table" and entry.name and not (others and key == me) then
			list[#list + 1] = { key = key, name = entry.name, realm = entry.realm, class = entry.class, faction = entry.faction,
				level = entry.level, money = entry.money, seen = entry.seen, me = key == me, main = entry.main == true, entry = entry }
		end
	end
	table.sort(list, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
	return list
end

-- The profile a character plays with outside the places' own: the one it chose, else its own (nil: none yet).
function ns.CharacterProfile(key)
	local root = ns.root
	if not (root and key and type(root.profiles) == "table") then return nil end
	local chosen = type(root.profileKeys) == "table" and root.profileKeys[key]
	if chosen and root.profiles[chosen] then return chosen end
	local own = type(root.ownProfile) == "table" and root.ownProfile[key]
	if own and root.profiles[own] then return own end
end

-- The other characters whose settings this one can copy (each has a profile), the last seen first.
function ns.CopyableCharacters()
	local list = {}
	for _, who in ipairs(ns.Characters(true)) do
		if ns.CharacterProfile(who.key) then list[#list + 1] = who end
	end
	return list
end

-- A character's place in the order of creation: the counter of its identity in the game (made earlier, lower).
local function Made(key)
	local counter = type(key) == "string" and key:match("^Player%-%d+%-(%x+)$")
	return counter and tonumber(counter, 16) or math.huge
end

-- The main character among a list (every one known by default): the one you marked, else the highest level,
-- then the oldest, then the last seen.
function ns.MainCharacter(list)
	list = list or ns.Characters()
	for _, who in ipairs(list) do
		if who.main then return who end
	end
	local best
	for _, who in ipairs(list) do
		if not best then
			best = who
		else
			local level, bestLevel = tonumber(who.level) or 0, tonumber(best.level) or 0
			if level > bestLevel or (level == bestLevel and Made(who.key) < Made(best.key)) then best = who end
		end
	end
	return best
end

-- Marked as your main character (on: true or false; nil: the other way round); one at a time.
function ns.SetMainCharacter(key, on)
	local ledger = Ledger()
	local entry = ledger and key and ledger[key]
	if type(entry) ~= "table" then return end
	if on == nil then on = not entry.main end
	for _, other in pairs(ledger) do
		if type(other) == "table" then other.main = nil end
	end
	entry.main = on and true or nil
end

-- A character let go (deleted, or not yours any more): its line gone, and all it kept with it.
-- (the extensions told, to let go of what they keep for it: W.OnCharacterForgotten(fn(key)))
local forgotten = U.Signal()
function ns.OnCharacterForgotten(fn)
	if type(fn) == "function" then forgotten.On(fn) end
end

function ns.ForgetCharacter(key)
	local root = ns.root
	if not (root and key) then return end
	for _, name in ipairs(ns.BY_CHARACTER) do
		if type(root[name]) == "table" then root[name][key] = nil end
	end
	forgotten.Fire(key)
end

-- The window: every character, the richest first; a line for all of them. A right click on a row (or its "⋯")
-- gives a small card: mark the main character, the one a new character can copy (its chip gold when marked, grey
-- when found by itself), or forget another one (asked first).
local ROWS, WIDTH = 8, 660
local window, list

local function Sorted()
	local all = ns.Characters()
	table.sort(all, function(a, b) return (a.money or 0) > (b.money or 0) end)
	return all
end

local function ClassColor(class)
	local r, g, b = U.ClassColor(class)
	return r and { r, g, b } or nil
end

-- A character's lines on hover: its realm, rested experience, professions (at their ceiling in gold), cooldowns,
-- letters leaving; then what a click does. Also what its row says at once (a chip), if anything.
local function Overview(who)
	local L, Skin, entry, now = ns.L, ns.Skin, who.entry or {}, time()
	local tip, chip = { who.realm or who.name }, nil
	local share, estimated = ns.RestedShare(entry, now)
	if share then
		tip[#tip + 1] = (estimated and L.CHARACTERS_RESTED_ABOUT or L.CHARACTERS_RESTED_TIP):format(math.floor(share * 100 + 0.5))
	end
	for _, craft in ipairs(type(entry.crafts) == "table" and entry.crafts or {}) do
		local line = L.CHARACTERS_CRAFT:format(craft.name, craft.rank, craft.max)
		if ns.AtCeiling(craft) then line = line .. "  " .. Skin.Colorize(L.CHARACTERS_CEILING, "gold") end
		tip[#tip + 1] = line
	end
	for _, cooldown in ipairs(type(entry.cooldowns) == "table" and entry.cooldowns or {}) do
		local ready = tonumber(cooldown.ready) or now
		if ready <= now then
			tip[#tip + 1] = Skin.Colorize(L.CHARACTERS_COOLDOWN_READY:format(cooldown.name), "gold")
			chip = chip or L.CHARACTERS_CHIP_READY
		else
			tip[#tip + 1] = L.CHARACTERS_COOLDOWN_IN:format(cooldown.name, U.Ago(ready - now))
		end
	end
	for _, line in ipairs(ns.CharacterLines(who.key)) do
		local r, g, b = tonumber(line.r), tonumber(line.g), tonumber(line.b)
		tip[#tip + 1] = r and g and b and U.Colorize(line.text, r, g, b) or line.text
		if type(line.chip) == "string" and line.chip ~= "" then chip = line.chip end
	end
	local leaves, count
	if not Provided("mail") then leaves, count = Letters(who.key) end
	if leaves then
		local words = (count == 1 and L.CHARACTERS_LETTER_ONE or L.CHARACTERS_LETTERS):format(U.Ago(leaves - now))
		tip[#tip + 1] = Skin.Colorize(words, "warn")
		if leaves - now <= LETTERS_SOON then chip = L.CHARACTERS_CHIP_LETTERS end
	end
	tip[#tip + 1] = Skin.Colorize(U.UsingPad() and L.CHARACTERS_MAIN_TIP_PAD or L.CHARACTERS_MAIN_TIP, "muted")
	return tip, chip
end

local function Draw()
	if not (window and window:IsShown()) then return end
	local all = Sorted()
	local offset = list:Clamp(#all)
	local total = 0
	for _, who in ipairs(all) do total = total + (who.money or 0) end
	local main = #all > 1 and ns.MainCharacter(all)
	for index, row in ipairs(list.rows) do
		local who = all[offset + index]
		if who then
			local tip, ready = Overview(who)
			local entry = { name = who.name, color = ClassColor(who.class), icon = false, tip = tip, key = who.key, who = who }
			local isMain = main and main.key == who.key
			-- (the main character's chip first; else what is ready or leaving; else this one, "you")
			local chip, tone = ready, "gold"
			if isMain then chip, tone = ns.L.CHARACTERS_MAIN, who.main and "gold" or "grey"
			elseif not chip and who.me then chip, tone = ns.L.CHARACTERS_CHIP_YOU, "grey" end
			local share = ns.RestedShare(who.entry)
			local rested = share and ("%d %%"):format(math.floor(share * 100 + 0.5)) or ""
			if share and share >= RESTED_MOST then rested = ns.Skin.Colorize(rested, "gold") end
			row:Fill(entry, who.me, { level = tostring(who.level or ""), rested = rested, money = U.Coins(who.money or 0),
				seen = who.seen and U.AgoWords(time() - who.seen) or "" }, chip, tone)
		else
			row:Fill(nil)
		end
	end
	list.empty:SetShown(#all <= 1)
	window.total:SetText(#all > 1 and ns.L.CHARACTERS_TOTAL:format(U.Coins(total)) or "")
end

-- A character's card (right click, "⋯"): main or not, forget (another one, asked first).
local function CharacterCard(row, who)
	local L, Skin = ns.L, ns.Skin
	local rows = {
		{ text = who.main and L.CHARACTERS_MAIN_UNMARK or L.CHARACTERS_MAIN_MARK, glyph = "star", onClick = function()
			ns.SetMainCharacter(who.key, not who.main)
			Draw()
		end },
	}
	if not who.me then
		rows[#rows + 1] = { text = L.CHARACTERS_FORGET, glyph = "close", role = "bad", onClick = function()
			Skin.Ask(L.CHARACTERS_FORGET_ASK:format(who.name), function()
				ns.ForgetCharacter(who.key)
				Draw()
			end)
		end }
	end
	Skin.ActionCard(row, { title = who.name, rows = rows, atCursor = true })
end

local function Create()
	local Skin = ns.Skin
	window = Skin.CreateWindow("WandererCharacters", "MEDIUM")
	Skin.Sounds(window, Skin.SOUNDS.open, Skin.SOUNDS.close)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "charactersPos")
	local _, title, margin = Skin.Header(window, "Wanderer", ns.L.CHARACTERS_TITLE, { settings = "profiles" })
	Skin.Help(window, ns.L.CHARACTERS_HELP, "HEADING")
	list = Skin.Table(window, {
		width = WIDTH - margin * 2, rows = ROWS, icon = false, nameTitle = ns.L.CHARACTERS_COL_NAME,
		columns = {
			{ key = "level", title = ns.L.CHARACTERS_COL_LEVEL, width = 50 },
			{ key = "rested", title = ns.L.CHARACTERS_COL_RESTED, width = 60 },
			{ key = "money", title = ns.L.CHARACTERS_COL_GOLD, width = 110 },
			{ key = "seen", title = ns.L.CHARACTERS_COL_SEEN, width = 80 },
			-- (the room of the row's "⋯")
			{ key = "more", title = "", width = Skin.ROW_MORE - 10 },
		},
		onClick = function(entry, mouse)
			local row
			for _, shown in ipairs(list.rows) do
				if shown.entry == entry then row = shown end
			end
			if mouse == "RightButton" and row then CharacterCard(row, entry.who) end
		end,
		onDraw = Draw,
		-- (its right click: the character's card, the pad's top button)
		padRight = true,
	})
	for _, row in ipairs(list.rows) do
		Skin.RowMore(row, function(owner) if owner.entry and owner.entry.who then CharacterCard(owner, owner.entry.who) end end)
	end
	list:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	list.empty:SetText(ns.L.CHARACTERS_EMPTY)
	window.total = Skin.Text(window, "GameTooltipText", "gold")
	window.total:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -Skin.SCROLL_WIDTH, -8)
	window.total:SetJustifyH("RIGHT")
	window:SetSize(WIDTH, margin * 2 + 30 + 12 + list:GetHeight() + 8 + 18)
	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.Scale())
		Note()
		Draw()
	end)
	Skin.Get(window):Layout()
end

function ns.ToggleCharacters()
	if not ns.root then return end
	if not window then Create() end
	window:SetShown(not window:IsShown())
end

function ns.InitCharacters()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT", "PLAYER_UPDATE_RESTING",
		"SKILL_LINES_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, level)
		Note(event == "PLAYER_LEVEL_UP" and level or nil)
		Draw()
	end)
end
