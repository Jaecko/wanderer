local _, ns = ...

-- The game's windows Wanderer does not replace (the character's pages, the spells and talents, the collections,
-- the group finder, the friends and the guild, the journal, the trade, the menus, the popups...) and the ones it
-- replaces when you chose the game's window, in Wanderer's colors: they read as Wanderer's own windows. Only
-- their look changes: the game's art is faded out (never taken away: the game draws it again and again, a faded
-- piece stays faded), the chosen style's dark ground and its edge come under them, and their cross, tabs,
-- buttons, lines to write in, lists to choose from, boxes to tick, scroll bars and item squares take the kit's
-- look. Nothing is moved, resized, rebuilt or called: the game does everything as before (GameFrames.lua places
-- them). A frame the game forbids to addons is never touched, a protected one never during a fight. Each piece
-- is dressed once; the windows the game loads later (its Blizzard_ addons) are dressed as they come, the pieces
-- it makes later (a page opened, a list filled) as their window shows or a tab is clicked.
--
-- The pieces on the screen (action buttons, bag bar, menus of a right click): see "On the screen" below.
--
-- Left whole to ElvUI (its skins on) and Aurora (Compat.lua, "gameSkins"). Switched off (Appearance), the
-- game's own look comes back at the next /reload: nothing dressed is undone in place.

local U = ns.Util
local Skin = ns.Skin
local Part = U.Part

local GameSkins = {}
ns.GameSkins = GameSkins

-- The windows, by name (most are made only when the game first loads them). art: pieces of it (pages, panels;
-- names or keys) whose own art is faded too. keep: its own textures that show something (a map, an emblem, a
-- letter's paper), left as the game draws them.
-- (Not dressed on purpose: the quest, gossip, book and quest log windows, whose dark words are written on the
-- game's parchment; the bags, Wanderer Bags' own; the world map.)
-- pages: a page's parchment or light art (a frame's own textures, or one texture; global names or keys down
-- from the window), faded only while every word over it reads on the dark (GameSkins.Page).
local BOOK_PAGES = {}
local CARDS = { "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }
for _, card in ipairs(CARDS) do
	BOOK_PAGES[#BOOK_PAGES + 1] = "BookPage.ProfessionsContentFrame." .. card .. ".Background"
	BOOK_PAGES[#BOOK_PAGES + 1] = "BookPage.ProfessionsContentFrame." .. card .. ".Overlay"
end
local WINDOWS = {
	{ name = "CharacterFrame", art = { "PaperDollFrame", "ReputationFrame", "TokenFrame", "SkillFrame", "HonorFrame", "PVPFrame",
		"PetPaperDollFrame", "CharacterAttributesFrame", "LeftPaneHost", "RightPaneHost" } },
	{ name = "ReputationDetailFrame" }, { name = "TokenFramePopup" },
	-- (its spell book dressed apart, SpellBook below; its talents' and specializations' art as pages)
	{ name = "PlayerSpellsFrame", pages = { "TalentsFrame.Background", "TalentsFrame.BackgroundBorder", "TalentsFrame.DividerHorizontalLeft",
		"TalentsFrame.DividerHorizontalRight", "TalentsFrame.DividerVerticalLeft", "TalentsFrame.DividerVerticalRight",
		"SpecFrame.Background", "SpecFrame.BlackBG" } },
	{ name = "SpellBookFrame" }, { name = "PlayerTalentFrame" }, { name = "TalentFrame" },
	{ name = "ProfessionsBookFrame" },
	{ name = "CollectionsJournal" }, { name = "WardrobeFrame" },
	{ name = "PVEFrame", art = { "LFDParentFrame", "RaidFinderFrame", "PVPUIFrame" } }, { name = "LFGParentFrame" },
	{ name = "FriendsFrame", art = { "WhoFrame", "IgnoreListFrame" } }, { name = "AddFriendFrame" }, { name = "FriendsFriendsFrame" },
	{ name = "RaidInfoFrame" },
	{ name = "CommunitiesFrame", pages = { "CommunitiesFrameGuildDetailsFrameInfo", "CommunitiesFrameGuildDetailsFrameNews",
		"GuildBenefitsFrame.Perks", "GuildBenefitsFrame.Rewards.Bg" } }, { name = "GuildFrame" },
	{ name = "EncounterJournal" },
	{ name = "AchievementFrame" },
	{ name = "ChannelFrame" },
	{ name = "TradeFrame" },
	{ name = "TabardFrame", keep = { "TabardFrameEmblemTopRight", "TabardFrameEmblemBottomRight", "TabardFrameEmblemTopLeft",
		"TabardFrameEmblemBottomLeft" } },
	{ name = "GuildRegistrarFrame" }, { name = "PetitionFrame" },
	{ name = "MacroFrame" }, { name = "KeyBindingFrame" }, { name = "AddonList" },
	{ name = "GameMenuFrame", art = { "Header" } },
	{ name = "HelpFrame" },
	{ name = "ItemSocketingFrame" }, { name = "ItemUpgradeFrame" },
	{ name = "InspectFrame", art = { "InspectPaperDollFrame", "InspectPVPFrame", "InspectTalentFrame", "InspectHonorFrame" } },
	{ name = "DressUpFrame" },
	{ name = "ReadyCheckListenerFrame" },
	{ name = "StaticPopup1", art = { "Border" } }, { name = "StaticPopup2", art = { "Border" } },
	{ name = "StaticPopup3", art = { "Border" } }, { name = "StaticPopup4", art = { "Border" } },
	-- (the ones Wanderer replaces, as they look when you chose the game's window)
	{ name = "MerchantFrame" }, { name = "LootFrame" }, { name = "MailFrame" },
	{ name = "OpenMailFrame", keep = { "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight" } },
	{ name = "AuctionHouseFrame" }, { name = "ClassTrainerFrame" }, { name = "ProfessionsFrame", pages = BOOK_PAGES },
	{ name = "ProfessionsCustomerOrdersFrame" },
	-- (the flight map is drawn on the window's own inner ground)
	{ name = "TaxiFrame", keep = { "InsetBg", "TaxiMap", "TaxiRouteMap" } },
	{ name = "GuildBankFrame" }, { name = "BankFrame" },
	{ name = "TradeSkillFrame" }, { name = "CraftFrame" }, { name = "PetStableFrame" }, { name = "WorldStateScoreFrame" },
}

-- The panels inside a window drawn as a soft card (the game's insets), by their keys.
local INSETS = { "Inset", "InsetRight", "LeftInset", "RightInset", "InsetFrame", "BottomInset" }

local dressed = setmetatable({}, { __mode = "k" }) -- window -> its spec
local looked = setmetatable({}, { __mode = "k" }) -- a piece already looked at (dressed or not)
local own = setmetatable({}, { __mode = "k" }) -- the textures made here (never faded)
local tabs = setmetatable({}, { __mode = "k" }) -- a tab dressed -> its pieces

-- On: Wanderer on, this look chosen, no other addon skinning the game's windows.
local function Active()
	return ns.db and ns.db.enabled and ns.db.label and ns.db.label.gameSkins and ns.Yields("gameSkins") == nil or false
end
GameSkins.Active = Active

local function Forbidden(frame)
	return frame.IsForbidden ~= nil and frame:IsForbidden() and true or false
end

-- A frame that may be dressed now: a frame's table, not forbidden, not one of Wanderer's windows, and a
-- protected one never during a fight.
local function Touchable(frame)
	if type(frame) ~= "table" or not frame.GetObjectType or Forbidden(frame) then return false end
	if Skin.Get(frame) or frame.wandererClose then return false end
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return false end
	return true
end

local function Own(texture)
	own[texture] = true
	return texture
end

local function OwnEdges(edges)
	for _, edge in ipairs(edges) do own[edge] = true end
	return edges
end

local function IsTexture(region)
	return type(region) == "table" and region.IsObjectType ~= nil and region:IsObjectType("Texture")
		and not (region.GetObjectType and region:GetObjectType() == "MaskTexture")
end

-- Every texture of a frame's own faded out (its children's left alone), but those kept and Wanderer's.
local function FadeRegions(frame, keep)
	if not (frame and frame.GetRegions) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsTexture(region) and not own[region] and not (keep and keep[region]) then region:SetAlpha(0) end
	end
end

-- A piece by its key or its global name made of its owner's (e.g. "Left": button.Left or <name>Left).
local function Piece(frame, key)
	local found = Part(frame, key)
	if found then return found end
	local name = frame.GetName and frame:GetName()
	local global = type(name) == "string" and rawget(_G, name .. key)
	return type(global) == "table" and global or nil
end

local function Kind(frame)
	return frame.GetObjectType and frame:GetObjectType()
end

local function Named(frame, pattern)
	local name = frame.GetName and frame:GetName()
	return type(name) == "string" and name:find(pattern) ~= nil
end

local function Words(frame)
	return Piece(frame, "Text") or Part(frame, "text")
end

-- Words written on a button (its label not empty).
local function HasWords(button)
	local words = Words(button)
	if not (words and words.GetText) then return false end
	return U.Clean(U.Safe(words.GetText, words)) ~= nil
end

-- The game's state textures of a button faded out (kept as objects: the game swaps them at each state), but
-- those kept (its icon).
local STATES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
local function FadeStates(button, keep)
	for _, getter in ipairs(STATES) do
		local texture = button[getter] and button[getter](button)
		if IsTexture(texture) and not own[texture] and not (keep and keep[texture]) then texture:SetAlpha(0) end
	end
end

-- Icons --------------------------------------------------------------------------------------------------------

-- A texture drawn from the game's frame art (a tab's plate, a border, a button's ground) rather than a picture
-- of something (an icon): by the name of its file or atlas. (A number tells nothing: not art then.)
local ART_WORDS = { "tab", "border", "frame", "button", "background", "slot", "panel", "highlight", "plate" }
local function IsArt(texture)
	local atlas = texture.GetAtlas and U.Clean(U.Safe(texture.GetAtlas, texture))
	local file = texture.GetTexture and U.Clean(U.Safe(texture.GetTexture, texture))
	local name = type(atlas) == "string" and atlas or (type(file) == "string" and file or nil)
	if not name then return false end
	name = name:lower()
	if name:find("icons[\\/]") then return false end
	for _, word in ipairs(ART_WORDS) do
		if name:find(word, 1, true) then return true end
	end
	return false
end

-- The textures that show what a tab or a button is (its icon), kept as the game draws them while its frame art
-- goes: its icon by key; else, with no words on it, its own state textures when they are not frame art (the
-- icon itself, pressed or greyed). nil when it shows none. (second answer: the main icon)
local ICON_KEYS = { "Icon", "icon", "IconTexture", "iconTexture" }
local function Icons(button)
	local set, main = {}, nil
	for _, key in ipairs(ICON_KEYS) do
		local icon = Piece(button, key)
		if IsTexture(icon) and not own[icon] then
			set[icon] = true
			main = main or icon
		end
	end
	if not main and not HasWords(button) then
		for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
			local texture = button[getter] and button[getter](button)
			if IsTexture(texture) and not own[texture] and not IsArt(texture) then
				set[texture] = true
				main = main or texture
			end
		end
	end
	return main and set or nil, main
end
GameSkins.Icons = Icons

-- An icon by key cropped as the kit's are (its round mask taken off).
local function CropIcon(owner, icon)
	for _, key in ipairs({ "IconMask", "Mask", "CircleMask" }) do
		local mask = Part(owner, key)
		if mask and icon.RemoveMaskTexture then U.Safe(icon.RemoveMaskTexture, icon, mask) end
	end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- Words in one of the palette's roles (the game's own font string: only its color changes).
local function Ink(words, role)
	if type(words) == "table" and words.SetTextColor and not Forbidden(words) then words:SetTextColor(Skin.RGB(role)) end
end

-- Dark words (meant for the game's parchment): one shown in a color too dark to read on Wanderer's ground, or in
-- a color that cannot be read (better the parchment kept than words nobody reads).
local function DarkWords(frame, depth)
	depth = depth or 0
	if depth > 6 or type(frame) ~= "table" or not frame.GetRegions or Forbidden(frame) then return false end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsShown()
			and U.Clean(U.Safe(region.GetText, region)) then
			local r, g, b = U.Safe(region.GetTextColor, region)
			r, g, b = U.Clean(r), U.Clean(g), U.Clean(b)
			if not (type(r) == "number" and type(g) == "number" and type(b) == "number") then return true end
			if 0.299 * r + 0.587 * g + 0.114 * b < 0.4 then return true end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.IsShown and child:IsShown() and DarkWords(child, depth + 1) then return true end
	end
	return false
end
GameSkins.DarkWords = DarkWords

local function FadePieces(frame, keys)
	for _, key in ipairs(keys) do
		local piece = Piece(frame, key)
		if IsTexture(piece) then piece:SetAlpha(0) end
	end
end

-- A thin golden edge around a piece's ground.
local function Edged(frame, alpha, around)
	local r, g, b = Skin.RGB("gold")
	return OwnEdges(Skin.Edges(frame, r, g, b, alpha, around))
end

-- A ground under a piece (its own texture, under all it draws), placed by its owner; its thin edge around it.
local function Ground(frame, sublevel)
	return Own(frame:CreateTexture(nil, "BACKGROUND", nil, sublevel or -8))
end

local function Hover(frame, around)
	local hover = Own(frame:CreateTexture(nil, "HIGHLIGHT"))
	hover:SetAllPoints(around)
	hover:SetColorTexture(1, 1, 1, Skin.HOVER)
	return hover
end

-- Windows ----------------------------------------------------------------------------------------------------

-- A window's ground and edge in the chosen style's colors (again as it shows: the style may have changed).
local function Color(window)
	local look = dressed[window]
	if not (type(look) == "table" and look.ground) then return end
	local r, g, b, a, er, eg, eb, ea = Skin.WindowColors()
	look.ground:SetColorTexture(r, g, b, a)
	look.edges.Color(er, eg, eb, ea)
end

-- A soft card inside a window (the game's inset): its art faded, a light ground and a thin edge (Skin.Panel's).
local function Inset(inset, keep)
	if looked[inset] then return end
	looked[inset] = true
	FadeRegions(inset, keep)
	local nine = Part(inset, "NineSlice")
	if nine and not Forbidden(nine) then nine:SetAlpha(0) end
	local ground = Ground(inset)
	ground:SetAllPoints()
	ground:SetColorTexture(1, 1, 1, 0.035)
	OwnEdges(Skin.Edges(inset, 1, 1, 1, 0.07))
end

local Walk, Pages

-- (pieces made by now dressed, pages whose words now read on the dark faded)
local function WalkSoon(window)
	C_Timer.After(0, function()
		if not dressed[window] then return end
		Walk(window, window, 0)
		Pages(window)
	end)
end

-- Tabs ----------------------------------------------------------------------------------------------------------

-- The tab shown (the game's own mark of it: told chosen, its active art shown, its chosen mark shown, a side
-- tab not darkened, ticked, or the tab disabled the old way).
local function Selected(tab)
	if type(tab.isSelected) == "boolean" then return tab.isSelected end
	local active = Piece(tab, "LeftActive")
	if active and active.IsShown then return active:IsShown() and true or false end
	local disabled = Piece(tab, "LeftDisabled")
	if disabled and disabled.IsShown then return disabled:IsShown() and true or false end
	local mark = Part(tab, "SelectedTexture")
	if IsTexture(mark) then return mark:IsShown() and true or false end
	local hider = Part(tab, "Hider")
	if IsTexture(hider) then return not hider:IsShown() end
	if Kind(tab) == "CheckButton" and tab.GetChecked then return tab:GetChecked() and true or false end
	return tab.IsEnabled ~= nil and not tab:IsEnabled()
end

-- A tab's look: the shown one on a golden ground, underlined in gold (Skin.Tabs' way), the others quiet; an icon
-- tab framed in gold when shown.
local function TabLook(tab)
	local look = tabs[tab]
	if not look then return end
	local chosen = Selected(tab)
	if look.icon then
		look.edges.Color(Skin.RGB("gold", chosen and 0.9 or 0.25))
		return
	end
	if chosen then look.ground:SetColorTexture(Skin.RGB("gold", 0.12)) else look.ground:SetColorTexture(1, 1, 1, 0.04) end
	look.line:SetShown(chosen)
end
GameSkins.TabLook = TabLook

local function TabsLook()
	for tab in pairs(tabs) do TabLook(tab) end
end

local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight",
	"RightHighlight", "LeftDisabled", "MiddleDisabled", "RightDisabled", "TabBg" }

-- A tab followed: its look as the game chooses it (a click, the game's own choice, its chosen mark shown or hidden).
local function Follow(tab, window)
	TabLook(tab)
	-- (a tab clicked: the game shows another page, its pieces dressed as they come)
	tab:HookScript("OnClick", function()
		C_Timer.After(0, TabsLook)
		WalkSoon(window)
	end)
	if type(tab.SetTabSelected) == "function" then hooksecurefunc(tab, "SetTabSelected", TabLook) end
	for _, key in ipairs({ "SelectedTexture", "Hider" }) do
		local mark = Part(tab, key)
		if IsTexture(mark) then
			for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
				if type(mark[method]) == "function" then hooksecurefunc(mark, method, function() TabLook(tab) end) end
			end
		end
	end
end

-- An icon tab's look: a dark square under its icon, a thin golden edge (bright on the one shown), a light under
-- the mouse. Its icon stays the game's.
local function IconLook(tab, icon)
	-- (an icon by key cropped; a state texture left whole: the game sets it again at each state)
	local keyed = false
	for _, key in ipairs(ICON_KEYS) do
		if Piece(tab, key) == icon then keyed = true end
	end
	if keyed then CropIcon(tab, icon) end
	local ground = Ground(tab)
	ground:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
	ground:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
	ground:SetColorTexture(0, 0, 0, 0.35)
	local edges = Edged(tab, 0.25, ground)
	Hover(tab, ground)
	return { ground = ground, edges = edges, icon = true }
end

-- A tab: its art faded (its icon kept when it shows one, e.g. the spell book's skill lines), the kit's look.
local function Tab(tab, window)
	local icons, icon = Icons(tab)
	FadeStates(tab, icons)
	FadePieces(tab, TAB_ART)
	FadeRegions(tab, icons)
	if icon and not HasWords(tab) then
		-- (square icon tabs: their plates too)
		FadePieces(tab, { "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" })
		tabs[tab] = IconLook(tab, icon)
		Follow(tab, window)
		return
	end
	local ground = Ground(tab)
	ground:SetPoint("TOPLEFT", 3, -3)
	ground:SetPoint("BOTTOMRIGHT", -3, 3)
	local edges = Edged(tab, 0.25, ground)
	local line = Own(tab:CreateTexture(nil, "ARTWORK"))
	line:SetPoint("BOTTOMLEFT", ground, "BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT", ground, "BOTTOMRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(Skin.RGB("gold", 0.9))
	Hover(tab, ground)
	tabs[tab] = { ground = ground, line = line, edges = edges }
	Follow(tab, window)
end

-- A side tab (an icon on the window's side: the character's panes, the collections, the group finder, the
-- professions, the communities): its plate, its glow and its chosen frame faded, its icon and its darkening
-- kept, the icon tab's look.
local SIDE_ART = { "TabBg", "Background", "Highlight", "HighlightTexture", "SelectedTexture" }
local function SideTab(tab, window)
	local icons, icon = Icons(tab)
	FadeStates(tab, icons)
	FadePieces(tab, SIDE_ART)
	local checked = Kind(tab) == "CheckButton" and tab.GetCheckedTexture and tab:GetCheckedTexture()
	if IsTexture(checked) and not icons[checked] then checked:SetAlpha(0) end
	tabs[tab] = IconLook(tab, icon)
	Follow(tab, window)
end

-- A side tab by the game's structure: a button with an icon by key and a tab's plate (the old one, the newer
-- large one), or a box to tick with no words whose ground is a tab's art.
local function IsSideTab(piece, kind)
	if not (kind == "Button" or kind == "CheckButton") then return false end
	local icons, icon = Icons(piece)
	if not (icons and icon and icon ~= (piece.GetNormalTexture and piece:GetNormalTexture())) then return false end
	if IsTexture(Piece(piece, "TabBg")) then return true end
	if IsTexture(Part(piece, "Background")) and (Part(piece, "SelectedTexture") or Part(piece, "TabGlow") or Part(piece, "Mask")) then
		return true
	end
	local normal = piece.GetNormalTexture and piece:GetNormalTexture()
	return kind == "CheckButton" and not HasWords(piece) and IsTexture(normal) and IsArt(normal)
end

-- Pieces -------------------------------------------------------------------------------------------------------

-- The cross (and its kin at the top of a window): the game's art faded, Wanderer's glyph in its place (gold
-- under the mouse).
local function Close(button, sign)
	looked[button] = true
	FadeStates(button)
	FadeRegions(button)
	local glyph = Own(Skin.Glyph(button, sign or "close", 11, "OVERLAY"))
	glyph:SetPoint("CENTER")
	button:HookScript("OnEnter", function() glyph:SetVertexColor(Skin.RGB("gold")) end)
	button:HookScript("OnLeave", function() glyph:SetVertexColor(Skin.RGB("label")) end)
end

-- The button making a window larger or smaller (the spell book's): its frame faded, its two buttons drawn as
-- the cross is, an arrow up to make it larger, down to make it smaller.
local function MaxMin(frame)
	FadeRegions(frame)
	for key, sign in pairs({ MaximizeButton = "up", MinimizeButton = "down" }) do
		local button = Part(frame, key)
		if button and Touchable(button) and not looked[button] then Close(button, sign) end
	end
end

-- A small list button showing only its arrow (the spell book's settings, the talents' search options): a dark
-- square with a thin golden edge, Wanderer's arrow over it (gold under the mouse).
local function ArrowDropdown(button)
	if not (button and Touchable(button)) or looked[button] then return end
	looked[button] = true
	FadeStates(button)
	FadePieces(button, { "Arrow", "Background", "Left", "Middle", "Right" })
	local ground = Ground(button)
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.35)
	Edged(button, 0.3, ground)
	Hover(button, ground)
	local glyph = Own(Skin.Glyph(button, "down", 10, "OVERLAY"))
	glyph:SetPoint("CENTER")
	button:HookScript("OnEnter", function() glyph:SetVertexColor(Skin.RGB("gold")) end)
	button:HookScript("OnLeave", function() glyph:SetVertexColor(Skin.RGB("label")) end)
end

-- A button: the kit's quiet one (a faint ground, a thin golden edge, a light under the mouse); its words and its
-- icon the game's.
local function Button(button)
	FadeStates(button, (Icons(button)))
	FadePieces(button, { "Left", "Middle", "Right" })
	local ground = Ground(button)
	ground:SetAllPoints()
	ground:SetColorTexture(1, 1, 1, 0.04)
	Edged(button, 0.3, ground)
	Hover(button, ground)
end

-- A line to write in: a dark band (Skin.CreateInput's), its edge golden while written in.
local function Input(box)
	FadePieces(box, { "Left", "Middle", "Right" })
	local nine = Part(box, "NineSlice")
	if nine and not Forbidden(nine) then nine:SetAlpha(0) end
	local ground = Ground(box)
	-- (the game's art reaches a little left of the box, where its words start)
	ground:SetPoint("TOPLEFT", -5, 0)
	ground:SetPoint("BOTTOMRIGHT", 0, 0)
	ground:SetColorTexture(0, 0, 0, 0.35)
	local edges = Edged(box, 0.12, ground)
	box:HookScript("OnEditFocusGained", function()
		edges.Color(Skin.RGB("gold", 0.55))
		ground:SetColorTexture(0, 0, 0, 0.45)
	end)
	box:HookScript("OnEditFocusLost", function()
		edges.Color(Skin.RGB("gold", 0.12))
		ground:SetColorTexture(0, 0, 0, 0.35)
	end)
end

-- A list to choose from (the game's newer one): a dark band, a thin golden edge; its arrow and words the game's.
local function Dropdown(dropdown)
	local background = Part(dropdown, "Background")
	if IsTexture(background) then background:SetAlpha(0) end
	local ground = Ground(dropdown)
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.35)
	Edged(dropdown, 0.3, ground)
	Hover(dropdown, ground)
end

-- The older list to choose from: its art is wider and taller than its box, the band drawn where the box shows.
local function OldDropdown(dropdown)
	local left, right = Piece(dropdown, "Left"), Piece(dropdown, "Right")
	FadePieces(dropdown, { "Left", "Middle", "Right" })
	local ground = Ground(dropdown)
	ground:SetPoint("TOPLEFT", left or dropdown, "TOPLEFT", 17, left and -17 or -2)
	ground:SetPoint("BOTTOMRIGHT", right or dropdown, "BOTTOMRIGHT", -17, right and 21 or 2)
	ground:SetColorTexture(0, 0, 0, 0.35)
	Edged(dropdown, 0.3, ground)
end

-- A box to tick: a small dark square with a golden edge; the game's tick drawn over it.
local function Check(check)
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local texture = check[getter] and check[getter](check)
		if IsTexture(texture) then texture:SetAlpha(0) end
	end
	local ground = Ground(check)
	ground:SetPoint("TOPLEFT", 5, -5)
	ground:SetPoint("BOTTOMRIGHT", -5, 5)
	ground:SetColorTexture(0, 0, 0, 0.4)
	Edged(check, 0.45, ground)
	Hover(check, ground)
end

-- The arrows of a scroll bar, in the rails' color.
local function Tint(button)
	if not Touchable(button) then return end
	local function Shade(texture)
		if not IsTexture(texture) or own[texture] then return end
		if texture.SetDesaturated then texture:SetDesaturated(true) end
		texture:SetVertexColor(Skin.RGB("kicker"))
	end
	for _, region in ipairs({ button:GetRegions() }) do Shade(region) end
	for _, getter in ipairs(STATES) do Shade(button[getter] and button[getter](button)) end
end

-- A thumb: a thin fill in the rails' color, gold under the mouse (Skin.ScrollBar's).
local function Thumb(holder, around)
	local fill = Own(holder:CreateTexture(nil, "OVERLAY"))
	fill:SetPoint("TOP", around, "TOP", 0, -2)
	fill:SetPoint("BOTTOM", around, "BOTTOM", 0, 2)
	fill:SetWidth(6)
	fill:SetColorTexture(Skin.RGB("kicker", 0.5))
	if holder.HookScript then
		holder:HookScript("OnEnter", function() fill:SetColorTexture(Skin.RGB("gold", 0.75)) end)
		holder:HookScript("OnLeave", function() fill:SetColorTexture(Skin.RGB("kicker", 0.5)) end)
	end
	return fill
end

local function Rail(holder, top, bottom)
	local rail = Own(holder:CreateTexture(nil, "ARTWORK"))
	rail:SetWidth(2)
	rail:SetPoint("TOP", top or holder, top and "BOTTOM" or "TOP")
	rail:SetPoint("BOTTOM", bottom or holder, bottom and "TOP" or "BOTTOM")
	rail:SetColorTexture(Skin.RGB("kicker", 0.22))
	return rail
end

-- The game's newer scroll bar (a track, a thumb, two arrows): the kit's thin golden rail and thumb.
local function ScrollBar(bar)
	FadeRegions(bar)
	local track = Part(bar, "Track")
	if track and Touchable(track) then
		FadeRegions(track)
		Rail(track)
		local thumb = Part(track, "Thumb")
		if thumb and Touchable(thumb) then
			FadeRegions(thumb)
			Thumb(thumb, thumb)
		end
	end
	Tint(Part(bar, "Back"))
	Tint(Part(bar, "Forward"))
end

-- The older scroll bar (a slider between two arrows): the same rail and thumb, drawn over the game's.
local function OldScrollBar(bar)
	local thumb = Piece(bar, "ThumbTexture") or (bar.GetThumbTexture and bar:GetThumbTexture())
	local up, down = Piece(bar, "ScrollUpButton"), Piece(bar, "ScrollDownButton")
	FadeRegions(bar)
	Rail(bar, up, down)
	if IsTexture(thumb) then Thumb(bar, thumb) end
	Tint(up)
	Tint(down)
end

-- An item's square: the game's frame faded, the icon cropped as the kit's are, a thin edge (its quality's border
-- stays the game's).
local function ItemButton(button, icon)
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if IsTexture(normal) then normal:SetAlpha(0) end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	for _, edge in ipairs(OwnEdges(Skin.Edges(button, 1, 1, 1, 0.12))) do edge:SetDrawLayer("ARTWORK", 7) end
end

-- What a piece is (by the game's own structure), dressed accordingly; false when it is none of them.
local function DressPiece(piece, window)
	local kind = Kind(piece)
	local parent = piece.GetParent and piece:GetParent()
	local three = Piece(piece, "Left") and Piece(piece, "Middle") and Piece(piece, "Right")
	if kind == "Button" and (Part(parent, "CloseButton") == piece or Named(piece, "CloseButton$")) then
		Close(piece)
	elseif (kind == "Button" or kind == "CheckButton") and (Piece(piece, "LeftActive") or Piece(piece, "LeftDisabled")
		or (three and Named(piece, "Tab%d+$"))) then
		Tab(piece, window)
	elseif IsSideTab(piece, kind) then
		SideTab(piece, window)
	elseif Part(piece, "MaximizeButton") and Part(piece, "MinimizeButton") then
		MaxMin(piece)
	elseif Part(piece, "Track") and (Part(piece, "Back") or Part(piece, "Forward")) then
		ScrollBar(piece)
	elseif kind == "Slider" and Piece(piece, "ScrollUpButton") then
		OldScrollBar(piece)
	elseif kind == "EditBox" and three then
		Input(piece)
	elseif Part(piece, "Arrow") and IsTexture(Part(piece, "Background")) and Part(piece, "Text") then
		Dropdown(piece)
	elseif kind == "Frame" and three and Piece(piece, "Button") then
		OldDropdown(piece)
	elseif kind == "Button" and three then
		Button(piece)
	elseif kind == "CheckButton" and Words(piece) and (U.Clean(U.Safe(piece.GetWidth, piece)) or 99) <= 40 then
		Check(piece)
	elseif (kind == "Button" or kind == "ItemButton") and Part(piece, "IconBorder")
		and IsTexture(Piece(piece, "IconTexture") or Part(piece, "icon") or Part(piece, "Icon")) then
		ItemButton(piece, Piece(piece, "IconTexture") or Part(piece, "icon") or Part(piece, "Icon"))
	else
		for _, key in ipairs(INSETS) do
			if Part(parent, key) == piece then
				Inset(piece)
				return true
			end
		end
		return false
	end
	return true
end
GameSkins.DressPiece = DressPiece

-- Every piece of a window, down its children (a few levels: lists, pages, panels), each looked at once.
local DEPTH = 10
function Walk(frame, window, depth)
	if depth > DEPTH or not frame.GetChildren then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if Touchable(child) then
			if not looked[child] then
				looked[child] = true
				DressPiece(child, window)
			end
			Walk(child, window, depth + 1)
		end
	end
end

-- The names and keys of a window to a set of its pieces.
local function Pieces(window, list)
	local set = {}
	for _, key in ipairs(list or {}) do
		local piece = Part(window, key) or (type(rawget(_G, key)) == "table" and rawget(_G, key)) or Piece(window, key)
		if piece then set[piece] = true end
	end
	return set
end

-- Pages ----------------------------------------------------------------------------------------------------------

-- A piece of a window by its global name, or by its keys down from the window ("TalentsFrame.Background").
local function Resolve(window, path)
	local global = rawget(_G, path)
	if type(global) == "table" then return global end
	local piece = window
	for key in path:gmatch("[^%.]+") do
		piece = Part(piece, key)
		if not piece then return nil end
	end
	return piece
end

-- A page's parchment or light art (a frame's own textures, or one texture) faded once the words over it read on
-- Wanderer's dark ground (none of them dark); else left as the game draws it, looked at again as it shows.
local paged = setmetatable({}, { __mode = "k" })
local function Page(piece)
	if paged[piece] or Forbidden(piece) then return end
	local gate = IsTexture(piece) and piece:GetParent() or piece
	if not (type(gate) == "table" and gate.IsVisible and gate:IsVisible()) or Forbidden(gate) then return end
	if InCombatLockdown() and gate.IsProtected and gate:IsProtected() then return end
	if DarkWords(gate) then return end
	paged[piece] = true
	if IsTexture(piece) then piece:SetAlpha(0) else FadeRegions(piece) end
end
GameSkins.PageFaded = function(piece) return paged[piece] == true end

function Pages(window)
	local look = dressed[window]
	for _, path in ipairs(look and look.spec.pages or {}) do
		local piece = Resolve(window, path)
		if piece then Page(piece) end
	end
end

-- Dark words left on a page whose parchment went (a line the game writes once in its book's brown): in the
-- palette's soft color.
local function Lighten(frame, depth)
	if depth > 6 or type(frame) ~= "table" or not frame.GetRegions or Forbidden(frame) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then
			local r, g, b = U.Safe(region.GetTextColor, region)
			r, g, b = U.Clean(r), U.Clean(g), U.Clean(b)
			if type(r) == "number" and type(g) == "number" and type(b) == "number" and 0.299 * r + 0.587 * g + 0.114 * b < 0.4 then
				Ink(region, "soft")
			end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do Lighten(child, depth + 1) end
end

-- The spell book -----------------------------------------------------------------------------------------------
-- (the spells page of PlayerSpellsFrame) Its book's parchment faded, and each entry in the palette each time the
-- game draws it (its entries are pooled and drawn again page after page, search after search): a spell's frame
-- faded (its icon, its cooldown and its tint when it cannot be cast stay the game's), a thin edge around its
-- icon, its name in the light text color (gold when a trainer can teach it, quiet when not learned yet), its
-- second line soft; a category's header in gold. With no way to follow the game's drawing, the parchment stays.

local SPELL_ART = { "Border", "TrainableBackplate", "TrainableShadow", "BorderSheen", "BorderShadow" }
local entryHooked = setmetatable({}, { __mode = "k" })
local spellFramed = setmetatable({}, { __mode = "k" })
local hookedFns = setmetatable({}, { __mode = "k" })

-- One entry as the game just drew it: a spell, or a category's header.
local function SpellEntry(entry)
	if type(entry) ~= "table" or Forbidden(entry) then return end
	if InCombatLockdown() and entry.IsProtected and entry:IsProtected() then return end
	local button = Part(entry, "Button")
	local text = Part(entry, "TextContainer")
	if button then
		local name = Part(entry, "Name") or Part(text, "Name")
		local second = Part(entry, "SubName") or Part(text, "SubName")
		if entry.isTrainable then
			Ink(name, "gold")
			Ink(second, "soft")
		elseif entry.isUnlearned then
			Ink(name, "muted")
			Ink(second, "muted")
		else
			Ink(name, "text")
			Ink(second, "soft")
		end
		FadePieces(entry, { "Backplate" })
		if text then FadeRegions(text) end
		FadePieces(button, SPELL_ART)
		local icon = Part(button, "Icon")
		if not spellFramed[button] and IsTexture(icon) and Touchable(button) then
			spellFramed[button] = true
			CropIcon(button, icon)
			for _, edge in ipairs(OwnEdges(Skin.Edges(button, 1, 1, 1, 0.15, icon))) do edge:SetDrawLayer("OVERLAY", 7) end
		end
	elseif Part(entry, "Text") then
		Ink(Part(entry, "Text"), "gold")
		FadePieces(entry, { "Backplate", "Border" })
	end
end

-- An entry followed: its own drawing hooked (unless it came from the game's mixin already hooked), then dressed.
local function FollowEntry(entry)
	if type(entry) ~= "table" then return end
	if not entryHooked[entry] then
		entryHooked[entry] = true
		for _, method in ipairs({ "UpdateVisuals", "UpdateSpellData", "Init" }) do
			local fn = entry[method]
			if type(fn) == "function" and not hookedFns[fn] then hooksecurefunc(entry, method, SpellEntry) end
		end
	end
	SpellEntry(entry)
end

-- The game's mixins of the book's entries hooked once (the entries it makes from now on follow from their first
-- drawing).
local mixinsHooked = false
local function HookMixins()
	if mixinsHooked then return end
	mixinsHooked = true
	for name, method in pairs({ SpellBookItemMixin = "UpdateVisuals", SpellBookHeaderMixin = "Init" }) do
		local mixin = rawget(_G, name)
		if type(mixin) == "table" and type(mixin[method]) == "function" then
			hooksecurefunc(mixin, method, SpellEntry)
			hookedFns[mixin[method]] = true
		end
	end
end

local function SpellBook(window)
	local book = Part(window, "SpellBookFrame")
	local pages = Part(book, "PagedSpellsFrame")
	if not (pages and type(pages.EnumerateFrames) == "function" and Touchable(book)) then return end
	local controls = Part(pages, "PagingControls")
	HookMixins()
	local pending = false
	local function Again()
		pending = false
		if InCombatLockdown() and book.IsProtected and book:IsProtected() then
			U.AfterFight("gameSkinsSpells", Again)
			return
		end
		-- (its parchment, its corners and bookmark, each page's paper)
		FadeRegions(book)
		FadeRegions(pages)
		local views = type(pages.ViewFrames) == "table" and pages.ViewFrames or { Part(pages, "View1") }
		for _, view in ipairs(views) do FadeRegions(view) end
		pcall(function()
			for _, entry in pages:EnumerateFrames() do FollowEntry(entry) end
		end)
		Ink(Part(controls, "PageText"), "soft")
		Lighten(book, 0)
	end
	local function Soon()
		if pending then return end
		pending = true
		C_Timer.After(0, Again)
	end
	for _, hook in ipairs({ { book, "UpdateDisplayedSpells" }, { book, "OnPagedSpellsUpdate" }, { book, "UpdateAllSpellData" },
		{ book, "SetMinimized" }, { window, "SetMinimized" }, { pages, "SetDataProvider" }, { controls, "SetCurrentPage" } }) do
		local owner, method = hook[1], hook[2]
		if type(owner) == "table" and type(owner[method]) == "function" then hooksecurefunc(owner, method, Soon) end
	end
	book:HookScript("OnShow", Soon)
	-- (its skill lines' tabs, added as the character learns them)
	local categories = Part(book, "CategoryTabSystem")
	if categories and type(categories.AddTab) == "function" then hooksecurefunc(categories, "AddTab", function() WalkSoon(window) end) end
	-- the page arrows in the rails' color, the settings' arrow and the talents' search options as Wanderer's
	Tint(Part(controls, "PrevPageButton"))
	Tint(Part(controls, "NextPageButton"))
	ArrowDropdown(Part(book, "SettingsDropdown"))
	ArrowDropdown(Part(Part(window, "TalentsFrame"), "SearchOptionsDropdown"))
	Again()
end

-- The professions book (the book page of the professions window): each card's spells written in the palette
-- each time the game draws them, its missing profession's words too; its parchment then faded as a page.
local function BookSpell(button)
	Ink(Part(button, "spellString"), "text")
	Ink(Part(button, "subSpellString"), "soft")
end

local function ProfessionsBook(window)
	local content = Part(Part(window, "BookPage"), "ProfessionsContentFrame")
	if not content then return end
	for _, key in ipairs(CARDS) do
		local card = Part(content, key)
		if card and Touchable(card) then
			Ink(Part(card, "missingHeader"), "gold")
			Ink(Part(card, "missingText"), "soft")
			for index = 1, 4 do
				local button = Part(card, "SpellButton" .. index)
				if button and not Forbidden(button) then
					if type(button.UpdateButton) == "function" then hooksecurefunc(button, "UpdateButton", BookSpell) end
					BookSpell(button)
				end
			end
		end
	end
end

-- A window's own dressing beyond its pieces, by its name.
local EXTRAS = { PlayerSpellsFrame = SpellBook, ProfessionsFrame = ProfessionsBook }

-- A window dressed: its art faded (its frame, its title bar, its pages' own), its portrait hidden, the
-- chosen style's ground and edge under it, its pieces dressed.
local function DressWindow(window, spec)
	if dressed[window] or not Touchable(window) then return false end
	local keep = Pieces(window, spec.keep)
	looked[window] = true
	FadeRegions(window, keep)
	for _, key in ipairs({ "NineSlice", "PortraitContainer", "PortraitFrame" }) do
		local piece = Part(window, key)
		if piece and not Forbidden(piece) then piece:SetAlpha(0) end
	end
	for _, key in ipairs({ "portrait", "Portrait" }) do
		local piece = Piece(window, key)
		if piece and not Forbidden(piece) and not keep[piece] then piece:SetAlpha(0) end
	end
	local title = Part(window, "TitleContainer")
	if title then FadeRegions(title, keep) end
	for _, key in ipairs({ "Bg", "BG", "Background", "TopTileStreaks", "Border" }) do
		local piece = Part(window, key)
		if piece and not keep[piece] and not Forbidden(piece) then
			if IsTexture(piece) then piece:SetAlpha(0) else FadeRegions(piece, keep) end
		end
	end
	for piece in pairs(Pieces(window, spec.art)) do
		if Touchable(piece) then
			FadeRegions(piece, keep)
			local nine = Part(piece, "NineSlice")
			if nine and not Forbidden(nine) then nine:SetAlpha(0) end
		end
	end
	for _, key in ipairs(INSETS) do
		local inset = Piece(window, key)
		if inset and Touchable(inset) then Inset(inset, keep) end
	end
	local ground = Ground(window)
	ground:SetAllPoints()
	dressed[window] = { spec = spec, ground = ground, edges = OwnEdges(Skin.Edges(window, 1, 1, 1, 0.1)) }
	Color(window)
	window:HookScript("OnShow", function(self)
		Color(self)
		TabsLook()
		WalkSoon(self)
	end)
	local extra = EXTRAS[spec.name]
	if extra then extra(window) end
	Walk(window, window, 0)
	Pages(window)
	TabsLook()
	return true
end
GameSkins.Dressed = function(window) return dressed[window] ~= nil end

-- On the screen ------------------------------------------------------------------------------------------------
-- The pieces that stand on the screen rather than in a window: the action buttons of the bars, the bag bar, the
-- menus of a right click. The game's round art faded, the icon cropped square on a dark ground with a thin dark
-- edge (ElvUI's way); a soft light under the mouse, the pressed and the chosen states as plain tints. The bars'
-- slot settings (BarSlots.lua) set how strong that edge and that ground are. The game's auras are forbidden to
-- addons: left as they are. Action buttons are left to an addon that dresses them (Masque, Bartender4, Dominos),
-- and never touched during a fight (after it).

local screen = setmetatable({}, { __mode = "k" }) -- an action button dressed -> { ground, edges }
GameSkins.ScreenParts = function(button) return screen[button] end

local BAR_ADDONS = { "Masque", "Bartender4", "Dominos" }
local function BarsLeftToOthers()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
	if not loaded then return false end
	for _, name in ipairs(BAR_ADDONS) do
		if U.Safe(loaded, name) then return true end
	end
	return false
end

-- The game's state textures of a button laid square over its icon, in plain tints (again after the game sets
-- its own art back).
local function States(button)
	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	if IsTexture(highlight) then
		highlight:SetColorTexture(1, 1, 1, Skin.HOVER)
		highlight:SetAllPoints(button)
	end
	local pushed = button.GetPushedTexture and button:GetPushedTexture()
	if IsTexture(pushed) then
		pushed:SetColorTexture(0, 0, 0, 0.35)
		pushed:SetAllPoints(button)
	end
	local checked = button.GetCheckedTexture and button:GetCheckedTexture()
	if IsTexture(checked) then
		checked:SetColorTexture(Skin.RGB("gold", 0.3))
		checked:SetAllPoints(button)
	end
	for _, key in ipairs({ "NormalTexture", "SlotBackground", "SlotArt" }) do
		local part = key == "NormalTexture" and button.GetNormalTexture and button:GetNormalTexture() or Part(button, key)
		if IsTexture(part) and not own[part] then part:SetAlpha(0) end
	end
end

local function ActionButton(button)
	if screen[button] or not Touchable(button) or InCombatLockdown() then return end
	local icon = Part(button, "icon") or Piece(button, "Icon")
	if not IsTexture(icon) then return end
	CropIcon(button, icon)
	local ground = Ground(button)
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.55)
	local edges = OwnEdges(Skin.Edges(button, 0, 0, 0, 1))
	for _, edge in ipairs(edges) do edge:SetDrawLayer("ARTWORK", 7) end
	screen[button] = { ground = ground, edges = edges }
	States(button)
	if button.UpdateButtonArt then
		hooksecurefunc(button, "UpdateButtonArt", function(self)
			if InCombatLockdown() then return U.AfterFight("gameSkinsBars", function() States(self) end) end
			States(self)
		end)
	end
end

local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot" }
local function BagButton(button)
	if looked[button] or not Touchable(button) then return end
	local icon = Piece(button, "IconTexture") or Part(button, "icon")
	if not IsTexture(icon) then return end
	looked[button] = true
	CropIcon(button, icon)
	for _, key in ipairs({ "CircleMask", "SlotHighlightTexture" }) do
		local part = Part(button, key)
		if IsTexture(part) and part.SetAlpha then part:SetAlpha(0) end
	end
	local ground = Ground(button)
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.55)
	ItemButton(button, icon)
	States(button)
end

-- A menu of a right click (the game's newer menus): its dark art faded, the windows' ground and edge under it.
local function MenuLook(style)
	if looked[style] or not Active() or not Touchable(style) then return end
	looked[style] = true
	FadeRegions(style)
	local r, g, b, a, er, eg, eb, ea = Skin.WindowColors()
	local ground = Ground(style)
	ground:SetPoint("TOPLEFT", -2, 2)
	ground:SetPoint("BOTTOMRIGHT", 2, 6)
	ground:SetColorTexture(r, g, b, math.max(a or 0.92, 0.92))
	OwnEdges(Skin.Edges(style, er, eg, eb, ea, ground))
end

local menuHooked = false
local function HookMenus()
	local mixin = rawget(_G, "MenuStyle1Mixin")
	if menuHooked or type(mixin) ~= "table" or type(mixin.Generate) ~= "function" then return end
	menuHooked = true
	hooksecurefunc(mixin, "Generate", MenuLook)
end

-- Every piece on the screen the game has made by now, not dressed yet (the action buttons: after a fight).
local function DressScreen()
	HookMenus()
	for _, name in ipairs(BAG_BUTTONS) do
		local button = rawget(_G, name)
		if type(button) == "table" then BagButton(button) end
	end
	if BarsLeftToOthers() then return end
	if InCombatLockdown() then return U.AfterFight("gameSkinsBars", DressScreen) end
	for _, bar in ipairs(ns.BAR_BUTTONS or {}) do
		for index = 1, bar[2] do
			local button = rawget(_G, bar[1] .. index)
			if type(button) == "table" then ActionButton(button) end
		end
	end
	if ns.RefreshBarSlots then ns.RefreshBarSlots() end
end

-- Every window of the list the game has made by now, not dressed yet (one the game protects, met during a
-- fight: after it).
local function Discover()
	if not Active() then return end
	local waiting = false
	for _, spec in ipairs(WINDOWS) do
		local window = rawget(_G, spec.name)
		if type(window) == "table" and not dressed[window] then
			if InCombatLockdown() and window.IsProtected and not Forbidden(window) and window:IsProtected() then
				waiting = true
			else
				DressWindow(window, spec)
			end
		end
	end
	if waiting then U.AfterFight("gameSkins", Discover) end
	DressScreen()
end

local installed = false
local function Install()
	if installed then return end
	installed = true
	-- The game's windows loaded later (its Blizzard_ addons), and those it makes as it opens them.
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", Discover)
	if ShowUIPanel then hooksecurefunc("ShowUIPanel", Discover) end
	if StaticPopup_Show then hooksecurefunc("StaticPopup_Show", Discover) end
	-- A tab chosen by the game itself (a page opened from elsewhere): the tabs' look follows.
	for _, name in ipairs({ "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab" }) do
		if type(rawget(_G, name)) == "function" then hooksecurefunc(name, function(tab) if tabs[tab] then TabLook(tab) end end) end
	end
	if type(rawget(_G, "PanelTemplates_SetTab")) == "function" then hooksecurefunc("PanelTemplates_SetTab", TabsLook) end
end

-- On (and the style changed): the windows dressed, in the style's colors. Off: as they are until the next
-- /reload (the game's art faded in place is never put back from here).
function ns.RefreshGameSkins()
	if not Active() then return end
	Install()
	Discover()
	for window in pairs(dressed) do Color(window) end
end

function ns.InitGameSkins()
	ns.RefreshGameSkins()
end
