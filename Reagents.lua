local _, ns = ...
local L = ns.L

-- Over a crafting reagent, one line says which professions use it: "Used in:
-- Alchemy, Tailoring". From the recipes of every profession, and from yours:
-- a profession of yours that knows recipes with it stands out in gold, with
-- how many. Nothing in a fight.
-- The table of recipes comes from LibCrafts-1.0, Copyright (c) 2024 Roman
-- Kharitonov, MIT License (github.com/refaim/libcrafts-1.0).

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local LEARN_DELAY = 0.5 -- the profession's window sends many updates at once: read once

-- The professions of the table below, in its bit order, and a spell that carries each one's name in the game's language.
local PROFESSIONS = {
	{ "Alchemy", 2259 }, { "Blacksmithing", 2018 }, { "Cooking", 2550 }, { "Enchanting", 7411 }, { "Engineering", 4036 },
	{ "First Aid", 3273 }, { "Leatherworking", 2108 }, { "Mining", 2575 }, { "Poisons", 2842 }, { "Tailoring", 3908 },
}

local names = {}
local function ProfessionName(index)
	if not names[index] then
		local spell = C_Spell and C_Spell.GetSpellName
		names[index] = spell and Clean(Safe(spell, PROFESSIONS[index][2])) or PROFESSIONS[index][1]
	end
	return names[index]
end

local function Settings()
	local db = ns.db
	return db and db.enabled and db.tooltips and db.tooltips.reagents
end

-- Per character: its professions (by name), and what each one uses
-- (profession name -> { item id -> recipes known with it }).
local function Mine(key)
	local root = ns.root
	if not root then return { professions = {}, known = {} } end
	root.reagentsKnown = root.reagentsKnown or {}
	key = key or ns.CharacterKey()
	local entry = root.reagentsKnown[key]
	if type(entry) ~= "table" or not entry.known then entry = {} end
	root.reagentsKnown[key] = entry
	entry.professions = entry.professions or {}
	entry.known = entry.known or {}
	return entry
end

-- The profession's window open: the reagents of the recipes it knows.
local function Learn()
	local ui = C_TradeSkillUI
	if not (ui and ui.GetAllRecipeIDs and ui.GetRecipeSchematic and ui.GetBaseProfessionInfo) then return end
	-- Someone else's recipes (a link, the guild): not yours.
	if ui.IsTradeSkillLinked and Clean(Safe(ui.IsTradeSkillLinked)) then return end
	if ui.IsTradeSkillGuild and Clean(Safe(ui.IsTradeSkillGuild)) then return end
	local profession = Safe(ui.GetBaseProfessionInfo)
	local name = type(profession) == "table" and Clean(profession.professionName)
	if not name or name == "" then return end
	local found = {}
	local recipes = Safe(ui.GetAllRecipeIDs)
	for _, id in ipairs(type(recipes) == "table" and recipes or {}) do
		local recipe = Safe(ui.GetRecipeInfo, id)
		if type(recipe) == "table" and Clean(recipe.learned) then
			local schematic = Safe(ui.GetRecipeSchematic, id, false)
			local slots = type(schematic) == "table" and schematic.reagentSlotSchematics
			for _, slot in ipairs(type(slots) == "table" and slots or {}) do
				for _, reagent in ipairs(type(slot.reagents) == "table" and slot.reagents or {}) do
					local item = Clean(reagent.itemID)
					if item then found[item] = (found[item] or 0) + 1 end
				end
			end
		end
	end
	if next(found) then
		local mine = Mine()
		mine.known[name] = found
		mine.professions[name] = true
	end
end

-- The professions this character has now (kept for the others to know); one unlearned is forgotten.
local function ReadProfessions()
	local current = {}
	for _, index in pairs({ Safe(GetProfessions) }) do
		local name = Clean(Safe(GetProfessionInfo, index))
		if name then current[name] = true end
	end
	if not next(current) then return end
	local mine = Mine()
	mine.professions = current
	for name in pairs(mine.known) do
		if not current[name] then mine.known[name] = nil end
	end
end

-- Who uses an item: { { name, mine = this character has it, alt = another of yours has it, count = recipes known } },
-- in the table's order, then the professions that only your recipes know of.
function ns.ReagentUses(item)
	item = tonumber(item)
	local uses = {}
	if not item then return uses end
	local mine = Mine()
	local others = {}
	for key, entry in pairs(ns.root and ns.root.reagentsKnown or {}) do
		if key ~= ns.CharacterKey() and type(entry.professions) == "table" then
			for name in pairs(entry.professions) do others[name] = true end
		end
	end
	local seen = {}
	local function Add(name)
		if seen[name] then return end
		seen[name] = true
		local count = mine.known[name] and mine.known[name][item]
		uses[#uses + 1] = { name = name, mine = mine.professions[name] or count ~= nil, alt = others[name] or false,
			count = count or 0 }
	end
	local mask = ns.REAGENT_PROFESSIONS[item] or 0
	for index in ipairs(PROFESSIONS) do
		if math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then Add(ProfessionName(index)) end
	end
	-- A recipe the table does not know (the game's own): still said.
	for name, items in pairs(mine.known) do
		if items[item] then Add(name) end
	end
	return uses
end

-- "Used in: Alchemy, Tailoring (4)", or nil for what no profession uses.
function ns.ReagentLine(item)
	local parts = {}
	for _, use in ipairs(ns.ReagentUses(item)) do
		parts[#parts + 1] = use.count > 0 and ("|cffffd100%s (%d)|r"):format(use.name, use.count)
			or (use.mine and ("|cffffd100%s|r"):format(use.name) or use.name)
	end
	if not parts[1] then return nil end
	return L.REAGENT_USED_IN:format(table.concat(parts, ", "))
end

function ns.InitReagents()
	local events = CreateFrame("Frame")
	local token = 0
	events:RegisterEvent("PLAYER_LOGIN")
	pcall(events.RegisterEvent, events, "TRADE_SKILL_SHOW")
	pcall(events.RegisterEvent, events, "TRADE_SKILL_LIST_UPDATE")
	pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" then return ReadProfessions() end
		token = token + 1
		local mine = token
		C_Timer.After(LEARN_DELAY, function() if mine == token then Learn() end end)
	end)
	if not (TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) then return end
	-- The line, once per tooltip: true when it was added.
	local function AddReagentLine(tooltip, data)
		if tooltip.wandererReagent or not Settings() or InCombatLockdown() then return false end
		-- The comparison tooltips beside show what you wear: nothing there.
		local name = tooltip.GetName and Clean(Safe(tooltip.GetName, tooltip)) or ""
		if name:find("^ShoppingTooltip") or name:find("^ItemRefShoppingTooltip") then return false end
		local line = ns.ReagentLine(type(data) == "table" and Clean(data.id))
		if not line then return false end
		tooltip.wandererReagent = true
		tooltip:AddLine(line, 0.62, 0.74, 0.86, true)
		return true
	end
	-- A new item shown: its line not added yet.
	if TooltipDataProcessor.AddTooltipPreCall then
		TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Item, function(tooltip) tooltip.wandererReagent = nil end)
	end
	-- Just before the price: under the game's "Crafting Reagent" line.
	local types = Enum.TooltipDataLineType
	if TooltipDataProcessor.AddLinePreCall and types and types.SellPrice then
		TooltipDataProcessor.AddLinePreCall(types.SellPrice, function(tooltip)
			local info = tooltip.processingInfo
			AddReagentLine(tooltip, info and info.tooltipData)
		end)
	end
	-- Nothing to sell it for: at the end.
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		if AddReagentLine(tooltip, data) then tooltip:Show() end
		tooltip.wandererReagent = nil
	end)
end

-- The professions' bits in the table below, for the extensions (Wanderer.Reagents).
ns.REAGENT_BITS = { Alchemy = 1, Blacksmithing = 2, Cooking = 4, Enchanting = 8, Engineering = 16, FirstAid = 32,
	Leatherworking = 64, Mining = 128, Poisons = 256, Tailoring = 512 }

-- (generated by make_reagents.js from LibCrafts-1.0 by refaim, MIT; 435 reagents)
ns.REAGENT_PROFESSIONS = {
	[118] = 1, [159] = 20, [723] = 4, [729] = 4, [730] = 4, [731] = 4, [765] = 1, [769] = 4, [774] = 18, [783] = 64,
	[785] = 1, [814] = 16, [818] = 18, [929] = 512, [1015] = 4, [1080] = 4, [1081] = 4, [1179] = 4, [1206] = 82, [1210] = 90,
	[1288] = 33, [1468] = 4, [1475] = 32, [1529] = 594, [1705] = 18, [2251] = 4, [2312] = 64, [2318] = 594, [2319] = 594, [2320] = 576,
	[2321] = 578, [2324] = 576, [2325] = 576, [2447] = 1, [2449] = 1, [2450] = 1, [2452] = 5, [2453] = 1, [2457] = 64, [2459] = 66,
	[2589] = 562, [2592] = 562, [2596] = 4, [2604] = 512, [2605] = 578, [2665] = 4, [2672] = 4, [2673] = 4, [2674] = 4, [2675] = 4,
	[2677] = 4, [2678] = 4, [2692] = 4, [2770] = 128, [2771] = 128, [2772] = 136, [2775] = 128, [2776] = 128, [2835] = 18, [2836] = 18,
	[2838] = 18, [2840] = 146, [2841] = 18, [2842] = 18, [2880] = 18, [2886] = 4, [2894] = 4, [2924] = 4, [2928] = 256, [2930] = 256,
	[2934] = 64, [2996] = 512, [2997] = 576, [3164] = 1, [3172] = 4, [3173] = 4, [3174] = 4, [3182] = 576, [3355] = 1, [3356] = 73,
	[3357] = 1, [3358] = 1, [3369] = 1, [3371] = 265, [3372] = 265, [3383] = 576, [3389] = 64, [3390] = 64, [3391] = 2, [3404] = 4,
	[3466] = 2, [3470] = 2, [3478] = 2, [3486] = 2, [3575] = 147, [3576] = 128, [3577] = 530, [3667] = 4, [3685] = 4, [3712] = 4,
	[3713] = 4, [3730] = 4, [3731] = 4, [3818] = 257, [3819] = 9, [3820] = 1, [3821] = 5, [3823] = 2, [3824] = 579, [3827] = 512,
	[3829] = 538, [3857] = 128, [3858] = 129, [3859] = 18, [3860] = 19, [3864] = 594, [4096] = 64, [4231] = 64, [4232] = 64, [4233] = 64,
	[4234] = 594, [4235] = 64, [4236] = 64, [4243] = 64, [4246] = 64, [4255] = 2, [4289] = 64, [4291] = 576, [4304] = 594, [4305] = 576,
	[4306] = 562, [4337] = 592, [4338] = 626, [4339] = 528, [4340] = 576, [4341] = 512, [4342] = 513, [4357] = 16, [4359] = 16, [4361] = 16,
	[4363] = 16, [4364] = 16, [4368] = 16, [4371] = 16, [4375] = 16, [4377] = 16, [4382] = 16, [4385] = 16, [4387] = 16, [4389] = 16,
	[4394] = 16, [4399] = 16, [4400] = 16, [4402] = 21, [4404] = 16, [4407] = 16, [4461] = 64, [4470] = 8, [4536] = 4, [4589] = 512,
	[4603] = 4, [4611] = 16, [4625] = 521, [4655] = 4, [5051] = 4, [5082] = 64, [5116] = 64, [5173] = 256, [5373] = 64, [5465] = 4,
	[5466] = 4, [5467] = 4, [5468] = 4, [5469] = 4, [5470] = 4, [5471] = 4, [5498] = 578, [5500] = 586, [5503] = 4, [5504] = 4,
	[5633] = 64, [5635] = 3, [5637] = 75, [5784] = 64, [5785] = 64, [5966] = 2, [6037] = 538, [6048] = 520, [6217] = 8, [6260] = 512,
	[6261] = 512, [6289] = 4, [6291] = 4, [6303] = 4, [6308] = 4, [6317] = 4, [6338] = 8, [6358] = 1, [6359] = 1, [6361] = 4,
	[6362] = 4, [6370] = 9, [6371] = 521, [6470] = 64, [6471] = 64, [6522] = 5, [6530] = 16, [6889] = 4, [7067] = 603, [7068] = 539,
	[7069] = 530, [7070] = 579, [7071] = 576, [7072] = 512, [7075] = 90, [7076] = 603, [7077] = 603, [7078] = 603, [7079] = 600, [7080] = 603,
	[7081] = 10, [7082] = 601, [7191] = 16, [7286] = 64, [7287] = 64, [7387] = 16, [7392] = 72, [7428] = 64, [7909] = 26, [7910] = 530,
	[7911] = 128, [7912] = 18, [7966] = 2, [7971] = 586, [7972] = 539, [7974] = 4, [8146] = 66, [8150] = 84, [8151] = 80, [8152] = 64,
	[8153] = 603, [8154] = 64, [8165] = 64, [8167] = 64, [8168] = 66, [8169] = 64, [8170] = 602, [8171] = 64, [8172] = 64, [8343] = 576,
	[8365] = 4, [8368] = 64, [8831] = 521, [8836] = 1, [8838] = 9, [8839] = 1, [8845] = 1, [8846] = 1, [8923] = 256, [8924] = 256,
	[8925] = 265, [8949] = 64, [8951] = 64, [9060] = 16, [9061] = 20, [9210] = 512, [9224] = 8, [9260] = 1, [9262] = 1, [10026] = 16,
	[10285] = 528, [10286] = 529, [10290] = 512, [10500] = 16, [10502] = 16, [10505] = 16, [10507] = 16, [10543] = 16, [10546] = 16, [10558] = 16,
	[10559] = 16, [10560] = 16, [10561] = 16, [10576] = 16, [10577] = 16, [10586] = 16, [10592] = 16, [10620] = 129, [10647] = 16, [10648] = 16,
	[10938] = 8, [10939] = 8, [10940] = 8, [10978] = 8, [10998] = 8, [11040] = 512, [11082] = 8, [11083] = 8, [11084] = 8, [11128] = 8,
	[11134] = 8, [11135] = 8, [11137] = 520, [11138] = 8, [11139] = 8, [11144] = 8, [11174] = 8, [11175] = 8, [11176] = 521, [11177] = 8,
	[11178] = 8, [11184] = 2, [11185] = 2, [11186] = 2, [11188] = 2, [11291] = 8, [11370] = 128, [11371] = 18, [11382] = 10, [11754] = 74,
	[12037] = 4, [12184] = 4, [12202] = 4, [12203] = 4, [12204] = 4, [12205] = 4, [12206] = 4, [12207] = 4, [12208] = 4, [12223] = 4,
	[12359] = 27, [12360] = 658, [12361] = 18, [12363] = 1, [12364] = 530, [12365] = 18, [12607] = 64, [12644] = 2, [12655] = 18, [12662] = 514,
	[12753] = 66, [12799] = 18, [12800] = 530, [12803] = 603, [12804] = 595, [12808] = 539, [12809] = 586, [12810] = 594, [12811] = 522, [12938] = 1,
	[13422] = 1, [13423] = 1, [13463] = 1, [13464] = 1, [13465] = 1, [13466] = 1, [13467] = 25, [13468] = 521, [13510] = 2, [13512] = 2,
	[13754] = 4, [13755] = 4, [13756] = 4, [13758] = 4, [13759] = 4, [13760] = 4, [13888] = 4, [13889] = 4, [13893] = 4, [13926] = 520,
	[14044] = 64, [14047] = 626, [14048] = 576, [14227] = 592, [14256] = 576, [14341] = 576, [14342] = 576, [14343] = 8, [14344] = 520, [15407] = 80,
	[15408] = 64, [15409] = 64, [15410] = 64, [15412] = 64, [15414] = 64, [15415] = 64, [15416] = 64, [15417] = 66, [15419] = 64, [15420] = 64,
	[15422] = 64, [15423] = 64, [15992] = 16, [15994] = 16, [16000] = 16, [16006] = 16, [16202] = 8, [16203] = 520, [16204] = 8, [16206] = 8,
	[17010] = 722, [17011] = 594, [17012] = 578, [17034] = 8, [17035] = 8, [17194] = 4, [17196] = 4, [17202] = 16, [17203] = 2, [18240] = 576,
	[18255] = 4, [18256] = 9, [18512] = 72, [18562] = 128, [18567] = 128, [18631] = 16, [19441] = 32, [19726] = 594, [19767] = 64, [19768] = 64,
	[19774] = 18, [19943] = 1, [20381] = 64, [20424] = 4, [20498] = 64, [20500] = 64, [20501] = 64, [20520] = 514, [20725] = 10, [21024] = 4,
	[21071] = 4, [21153] = 4, [22202] = 2, [22203] = 2, [22682] = 578,
}
