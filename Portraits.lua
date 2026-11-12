local _, ns = ...

-- The portraits' part of the unit frames' look (UnitFrames.lua): on the game's portraits, a thin ring in the
-- class colour of players or the attitude of creatures (gold for you in Ink lines), a small class badge on the
-- faces of other players, the face greyed while dead, a ghost or offline, the class icons in the look's style
-- (the game's, the 2004 circles or engraved in ink) and, frame by frame, a face or a class icon where the game's
-- own choice is not wanted. The game's choice (Options > Interface: class icons for you, for the others) stays
-- the rule: "As the game" follows it, never a copy of it. No 3D.
-- Wanderer's own portraits (the label, the scenes) follow the same choice and style (ns.SetPortrait).

local U = ns.Util
local Safe, Clean, IsSecret = U.Safe, U.Clean, U.IsSecret

local RING = "Interface\\AddOns\\Wanderer\\Media\\PortraitRing"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local INK_TINT = ns.Skin.COLORS.kicker -- the kit's kicker: an icon engraved on the dark look
local GOLD = { 0.78, 0.68, 0.42 } -- your ring: a quiet, desaturated gold
local RING_ALPHA, DIM_ALPHA = 0.8, 0.3
local GREY = 0.6
-- Which row of "what each shows" a frame follows.
local ROWS = { player = "player", target = "target", focus = "target", boss = "target", party = "party", tot = "tot", pet = "tot" }

local function Look()
	return ns.UnitFramesOn and ns.UnitFramesOn() and ns.db.unitFrames or nil
end

-- A class icon in a style ("game", "classic", "ink") on a texture: true when drawn.
function ns.DrawClassIcon(texture, class, style)
	if type(class) ~= "string" then return false end
	local coords = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]
	local atlas = "classicon-" .. class:lower()
	if style == "classic" and coords or not U.HasAtlas(atlas) then
		if not coords then return false end
		texture:SetTexture(CIRCLES)
		texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		texture:SetAtlas(atlas)
	end
	local ink = style == "ink"
	if texture.SetDesaturated then texture:SetDesaturated(ink) end
	if ink then texture:SetVertexColor(INK_TINT[1], INK_TINT[2], INK_TINT[3]) else texture:SetVertexColor(1, 1, 1) end
	return true
end

-- The game shows a class icon for this unit (Options > Interface: you, the other players).
local function GameIcon(unit)
	if not Clean(Safe(UnitIsPlayer, unit)) then return false end
	local mine = Clean(Safe(UnitIsUnit, unit, "player"))
	return Clean(Safe(GetCVar, mine and "ReplaceMyPlayerPortrait" or "ReplaceOtherPlayerPortraits")) == "1"
end

-- What a portrait shows for a unit ("face" or "icon"): the game's choice, else the frame's exception (row).
local function Shows(unit, row, look)
	if not Clean(Safe(UnitIsPlayer, unit)) then return "face" end
	local want = look and type(look.show) == "table" and row and look.show[row] or "game"
	if want == "face" or want == "icon" then return want end
	return GameIcon(unit) and "icon" or "face"
end

local function ClassOf(unit)
	local _, class = Safe(UnitClass, unit)
	return Clean(class)
end

-- Wanderer's own portraits (where: "label", "scene"): a face, or the class icon in the look's style when the
-- game (or the frame's exception) shows one and Wanderer's portraits follow the look. True: an icon.
function ns.SetPortrait(texture, unit, where)
	local look = Look()
	if look and look.wanderer ~= false then
		local mine = Clean(Safe(UnitIsUnit, unit, "player"))
		local class = ClassOf(unit)
		if class and Shows(unit, mine and "player" or "target", look) == "icon" and ns.DrawClassIcon(texture, class, look.iconStyle) then
			return true
		end
	end
	-- (a face: the coordinates and the colour as a face wants them, whatever was there before)
	if texture.SetTexCoord and where ~= "scene" then texture:SetTexCoord(0, 1, 0, 1) end
	if texture.SetDesaturated then texture:SetDesaturated(false) end
	texture:SetVertexColor(1, 1, 1)
	Safe(SetPortraitTexture, texture, unit)
	return false
end

-- The game's portraits ---------------------------------------------------------------------------------------

local states = setmetatable({}, { __mode = "k" }) -- a game portrait -> what Wanderer changed on it
local overlays = setmetatable({}, { __mode = "k" }) -- a unit frame -> its ring and badge
local byFrame = setmetatable({}, { __mode = "k" }) -- a unit frame -> its entry

local function PortraitOf(frame)
	local walk = ns.UnitFramesWalk
	local portrait = walk(frame, "portrait") or walk(frame, "TargetFrameContainer", "Portrait") or walk(frame, "PlayerFrameContainer", "PlayerPortrait")
		or walk(frame, "Portrait")
	return type(portrait) == "table" and not IsSecret(portrait) and type(portrait.SetTexture) == "function" and portrait or nil
end
ns.UnitFramePortrait = PortraitOf

local function State(portrait)
	local state = states[portrait]
	if not state then
		local r, g, b = Safe(portrait.GetVertexColor, portrait)
		state = { vertex = { Clean(r) or 1, Clean(g) or 1, Clean(b) or 1 } }
		states[portrait] = state
	end
	return state
end

-- The portrait as the game draws it (its own choice of face or icon), our changes taken back.
local function GameDraw(frame, portrait, unit)
	local state = states[portrait]
	if not state then return end
	states[portrait] = nil
	if not (state.changed or state.grey) then return end
	if portrait.SetTexCoord then portrait:SetTexCoord(0, 1, 0, 1) end
	if portrait.SetDesaturated then portrait:SetDesaturated(false) end
	portrait:SetVertexColor(unpack(state.vertex))
	if not (unit and Clean(Safe(UnitExists, unit))) then return end
	if GameIcon(unit) then
		ns.DrawClassIcon(portrait, ClassOf(unit), "game")
		portrait:SetVertexColor(unpack(state.vertex))
	else
		Safe(SetPortraitTexture, portrait, unit, rawget(frame, "disablePortraitMask"))
	end
end

-- The ring and the badge of a frame: textures of the portrait's own frame, in the portrait's layer just over it,
-- so the game's level circle, rest and combat icons, raid mark and dragons stay over them, where the game put
-- them. They fade with the frame.
local function Overlay(entry, portrait)
	local overlay = overlays[entry.frame]
	if overlay then return overlay end
	local holder = Safe(portrait.GetParent, portrait)
	if type(holder) ~= "table" or IsSecret(holder) or not holder.CreateTexture then return nil end
	local layer, sublevel = Safe(portrait.GetDrawLayer, portrait)
	layer, sublevel = Clean(layer) or "ARTWORK", Clean(sublevel) or 0
	local function Over(step) return math.min(7, sublevel + step) end
	overlay = { textures = {} }
	overlay.ring = holder:CreateTexture(nil, layer, nil, Over(1))
	overlay.ring:SetTexture(RING)
	overlay.ring:SetAllPoints(portrait)
	local small = entry.kind == "small" or entry.kind == "party"
	local size = small and 12 or 16
	overlay.rim = holder:CreateTexture(nil, layer, nil, Over(2))
	overlay.rim:SetTexture(DISC)
	overlay.rim:SetVertexColor(0.055, 0.059, 0.071, 0.9)
	overlay.rim:SetSize(size + 2, size + 2)
	overlay.badge = holder:CreateTexture(nil, layer, nil, Over(3))
	overlay.badge:SetSize(size, size)
	-- (the top inner corner, towards the bars: never the bottom left of the skull, the plus and the level circle,
	-- nor the raid mark's top)
	local inner = (entry.kind == "target" or entry.kind == "boss") and "TOPLEFT" or "TOPRIGHT"
	local x = inner == "TOPLEFT" and size * 0.3 or -size * 0.3
	overlay.badge:SetPoint("CENTER", portrait, inner, x, -size * 0.3)
	overlay.rim:SetPoint("CENTER", overlay.badge, "CENTER")
	overlay.textures = { overlay.ring, overlay.rim, overlay.badge }
	for _, texture in ipairs(overlay.textures) do texture:Hide() end
	overlays[entry.frame] = overlay
	return overlay
end

-- (tests) a frame's ring and badge.
function ns.PortraitOverlayOf(frame) return overlays[frame] end

local function HideOverlay(frame)
	local overlay = overlays[frame]
	if not overlay then return end
	for _, texture in ipairs(overlay.textures) do texture:Hide() end
end

-- A colour quieted for a ring: a little toward grey, never loud.
local function Quiet(r, g, b)
	return r * 0.75 + 0.12, g * 0.75 + 0.12, b * 0.75 + 0.12
end

-- The ring's colour: your gold, a player's class, a creature's attitude (the game's own colour for it); nil when
-- hidden from Wanderer (never a wrong colour).
local function RingColor(entry, unit, look)
	if look.ring == "off" then return nil end
	if look.ring == "gold" and entry.key == "player" then return GOLD[1], GOLD[2], GOLD[3] end
	if Clean(Safe(UnitIsPlayer, unit)) then
		local r, g, b = U.ClassColor(ClassOf(unit))
		if r then return Quiet(r, g, b) end
		return nil
	end
	local r, g, b = Safe(_G.UnitSelectionColor, unit)
	r, g, b = Clean(r), Clean(g), Clean(b)
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then return Quiet(r, g, b) end
	return nil
end

-- The medallion (Ink lines): a rounded square at the game's portrait's place and size, a 2 px ink border (1 px on
-- the small frames), the face (or the class icon where the game, or the frame's exception, shows one), the level in
-- a small dark tab at the bottom corner away from the bars (none on the small frames), the class badge in the top
-- corner towards the bars; dead, a ghost or offline: greyed. The border takes the elite's gold or the rare's silver
-- (the game's dragon, drawn for a round portrait, unseen meanwhile), else the block's quiet tints (threat, combat).
-- The game's round portrait, its level circle and its level stay unseen while it stands, given back after.

local SQUARE = "Interface\\AddOns\\Wanderer\\Media\\PortraitSquare"
local NARROW = "Fonts\\ARIALN.TTF"
local TAB_GROUND = { 0.055, 0.059, 0.071, 0.92 }
local LEVEL_COLOR = { 0.95, 0.93, 0.9 }
local REST_COLOR = ns.Skin.COLORS.gold
local REST_WORDS = "Zz"
local ELITE_EDGE, RARE_EDGE = { 0.78, 0.62, 0.25, 1 }, { 0.7, 0.72, 0.76, 1 }
local medals = setmetatable({}, { __mode = "k" }) -- a unit frame -> its medallion
local SMALL = { small = true, party = true }
local FACE_CROP = 0.08 -- the edge of the game's face left out on each side

-- The game's level circles anywhere in a frame (found by their picture: the paths differ from frame to frame),
-- looked for once per frame.
local LEVEL_ATLAS = "SmallCircle"
local circles = setmetatable({}, { __mode = "k" })
local LOOK_AGAIN = 10 -- seconds before a frame where no circle was found is searched again (never on every drawing)
local function LevelCircles(frame)
	local kept = circles[frame]
	if kept and (kept[1] or GetTime() < (kept.again or 0)) then return kept end
	local found, depth = {}, 0
	local function Search(node)
		depth = depth + 1
		if depth <= 6 and type(node) == "table" and node.GetRegions then
			for _, region in ipairs({ Safe(node.GetRegions, node) }) do
				local atlas = type(region) == "table" and region.GetAtlas and Clean(Safe(region.GetAtlas, region))
				if type(atlas) == "string" and atlas:find(LEVEL_ATLAS, 1, true) then found[#found + 1] = region end
			end
			if node.GetChildren then
				for _, child in ipairs({ Safe(node.GetChildren, node) }) do Search(child) end
			end
		end
		depth = depth - 1
	end
	Search(frame)
	-- (none found yet: looked for again a little later, a circle the game sets up later is not missed)
	if not found[1] then found.again = GetTime() + LOOK_AGAIN end
	circles[frame] = found
	return found
end

-- The game's pieces the medallion stands in for.
local function GameRegions(entry, portrait)
	local walk = ns.UnitFramesWalk
	local frame = entry.frame
	-- (each frame has only some of these: the list keeps those it has, no gap for a missing one)
	local list = {}
	local function Add(region) if region then list[#list + 1] = region end end
	Add(portrait)
	Add(walk(frame, "PlayerFrameContent", "PlayerFrameContentMain", "LevelBackgroundCircle"))
	if frame == _G.PlayerFrame then
		Add(_G.PlayerLevelText)
		-- (the game's resting signs: the medallion's own tab says it)
		Add(walk(frame, "PlayerFrameContent", "PlayerFrameContentContextual", "PlayerRestLoop"))
		Add(_G.PlayerRestIcon)
		Add(_G.PlayerRestGlow)
	end
	Add(walk(frame, "TargetFrameContent", "TargetFrameContentMain", "LevelBackgroundCircle"))
	Add(walk(frame, "TargetFrameContent", "TargetFrameContentMain", "LevelText"))
	Add(walk(frame, "TargetFrameContainer", "BossPortraitFrameTexture"))
	for _, circle in ipairs(LevelCircles(frame)) do Add(circle) end
	return list
end

local function LevelWords(unit)
	local level = Clean(Safe(UnitLevel, unit))
	if type(level) ~= "number" then return nil end
	return level > 0 and tostring(level) or "??"
end

local function MakeMedallion(entry, portrait)
	local small = SMALL[entry.kind]
	local bar = ns.UnitFramesWalk(entry.frame, "healthbar")
	local medal = CreateFrame("Frame", nil, entry.frame)
	local level = type(bar) == "table" and bar.GetFrameLevel and Clean(Safe(bar.GetFrameLevel, bar))
	medal:SetFrameLevel((type(level) == "number" and level or 5) + 3)
	medal:SetAllPoints(portrait)
	medal.border = medal:CreateTexture(nil, "BACKGROUND")
	medal.border:SetAllPoints(medal)
	medal.border:SetTexture(SQUARE)
	local inset = small and 1 or 2
	medal.face = medal:CreateTexture(nil, "ARTWORK")
	medal.face:SetPoint("TOPLEFT", medal, "TOPLEFT", inset, -inset)
	medal.face:SetPoint("BOTTOMRIGHT", medal, "BOTTOMRIGHT", -inset, inset)
	if medal.CreateMaskTexture and medal.face.AddMaskTexture then
		local mask = medal:CreateMaskTexture()
		mask:SetTexture(SQUARE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(medal.face)
		medal.face:AddMaskTexture(mask)
	end
	-- (the badge in the top corner towards the bars; the level tab in the bottom corner away from them)
	local towards = (entry.kind == "target" or entry.kind == "boss") and "LEFT" or "RIGHT"
	local away = towards == "LEFT" and "RIGHT" or "LEFT"
	local size = small and 10 or 14
	medal.rim = medal:CreateTexture(nil, "OVERLAY")
	medal.rim:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	medal.rim:SetVertexColor(0.055, 0.059, 0.071, 0.9)
	medal.rim:SetSize(size + 2, size + 2)
	medal.badge = medal:CreateTexture(nil, "OVERLAY", nil, 1)
	medal.badge:SetSize(size, size)
	medal.badge:SetPoint("TOP" .. towards, medal, "TOP" .. towards, towards == "LEFT" and inset + 1 or -(inset + 1), -(inset + 1))
	medal.rim:SetPoint("CENTER", medal.badge, "CENTER")
	if not small then
		-- (the level in the bottom corner towards the bars, inside the portrait; resting in the top corner away)
		local function Tab(point, color)
			local tab = CreateFrame("Frame", nil, medal)
			tab:SetFrameLevel(medal:GetFrameLevel() + 1)
			tab:SetSize(20, 14)
			tab:SetPoint(point, medal, point, point:find("LEFT") and inset or -inset, point:find("TOP") and -inset or inset)
			tab.ground = tab:CreateTexture(nil, "BACKGROUND")
			tab.ground:SetAllPoints()
			tab.ground:SetTexture(SQUARE)
			tab.ground:SetVertexColor(unpack(TAB_GROUND))
			tab.text = tab:CreateFontString(nil, "OVERLAY")
			pcall(tab.text.SetFont, tab.text, NARROW, 10, "")
			tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
			tab.text:SetTextColor(unpack(color))
			tab.text:SetShadowOffset(1, -1)
			tab.text:SetShadowColor(0, 0, 0, 1)
			return tab
		end
		medal.tab = Tab("BOTTOM" .. towards, LEVEL_COLOR)
		medal.rest = Tab("TOP" .. away, REST_COLOR)
		medal.rest.text:SetText(REST_WORDS)
		medal.rest:Hide()
	end
	medals[entry.frame] = medal
	return medal
end

-- The game's hit text (damage and heals over your portrait and your pet's): carried over the medallion while it
-- stands, given back to its own frame after.
local HIT_TEXTS = { PlayerFrame = "PlayerHitIndicator", PetFrame = "PetHitIndicator" }
local function HitText(frame)
	local text = rawget(frame, "feedbackText")
	if type(text) ~= "table" then
		local name = Clean(Safe(frame.GetName, frame))
		text = HIT_TEXTS[name] and _G[HIT_TEXTS[name]]
	end
	if type(text) == "table" and text.SetParent and text.GetParent then return text end
	return nil
end

local function LiftHitText(entry, medal)
	local text = HitText(entry.frame)
	if not text then return end
	if not medal.lift then
		medal.lift = CreateFrame("Frame", nil, medal)
		medal.lift:SetAllPoints(medal)
		medal.lift:SetFrameLevel(medal:GetFrameLevel() + 5)
	end
	local parent = Safe(text.GetParent, text)
	if parent == medal.lift then return end
	medal.hitText, medal.hitHome = text, parent
	Safe(text.SetParent, text, medal.lift)
end

local function DropHitText(medal)
	local text, home = medal.hitText, medal.hitHome
	medal.hitText, medal.hitHome = nil, nil
	if text and type(home) == "table" and Safe(text.GetParent, text) == medal.lift then Safe(text.SetParent, text, home) end
end

local function Unmedallion(entry, portrait)
	local medal = medals[entry.frame]
	if not (medal and medal:IsShown()) then return end
	DropHitText(medal)
	medal:Hide()
	for _, region in ipairs(GameRegions(entry, portrait)) do ns.UnitFramesShowArt(region) end
end

local function Medallion(entry, portrait, unit, look)
	local medal = medals[entry.frame]
	if not medal then
		if Clean(Safe(InCombatLockdown)) and Clean(Safe(entry.frame.IsProtected, entry.frame)) then return end
		medal = MakeMedallion(entry, portrait)
	end
	for _, region in ipairs(GameRegions(entry, portrait)) do ns.UnitFramesHideArt(region) end
	-- (the target's auras above it: the medallion comes down with the whole composition, UnitFrames.lua)
	local drop = ns.UnitFramesDrop and ns.UnitFramesDrop(entry) or 0
	medal:ClearAllPoints()
	medal:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, -drop)
	medal:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, -drop)
	medal:Show()
	LiftHitText(entry, medal)
	-- The face, or the class icon where the game (or the exception) shows one.
	local face = medal.face
	local class = ClassOf(unit)
	if Shows(unit, ROWS[entry.key], look) == "icon" and class and ns.DrawClassIcon(face, class, look.iconStyle) then
		medal.icon = true
	else
		medal.icon = false
		-- (the game's face unmasked, square, a little closer: it fills the whole medallion)
		if face.SetTexCoord then face:SetTexCoord(FACE_CROP, 1 - FACE_CROP, FACE_CROP, 1 - FACE_CROP) end
		if face.SetDesaturated then face:SetDesaturated(false) end
		face:SetVertexColor(1, 1, 1)
		Safe(SetPortraitTexture, face, unit, true)
	end
	local gone = Clean(Safe(UnitIsDeadOrGhost, unit)) or (Clean(Safe(UnitIsPlayer, unit)) and Safe(UnitIsConnected, unit) == false)
	if gone and look.greyDead ~= false then
		if face.SetDesaturated then face:SetDesaturated(true) end
		face:SetVertexColor(0.6, 0.6, 0.6)
	end
	-- The border: elite gold, rare silver, else the block's quiet tint.
	local classification = Clean(Safe(UnitClassification, unit))
	local edge
	if classification == "elite" or classification == "worldboss" then edge = ELITE_EDGE
	elseif classification == "rare" or classification == "rareelite" then edge = RARE_EDGE end
	if edge then
		medal.border:SetVertexColor(edge[1], edge[2], edge[3], edge[4])
	elseif ns.UnitFramesEdgeColor then
		medal.border:SetVertexColor(ns.UnitFramesEdgeColor(entry, unit))
	else
		medal.border:SetVertexColor(0, 0, 0, 0.9)
	end
	-- The badge on another player's face (never an icon on an icon).
	local badge = class and not medal.icon and Clean(Safe(UnitIsPlayer, unit)) and not Clean(Safe(UnitIsUnit, unit, "player"))
		and (look.badge == "all" or (look.badge == "others" and entry.key ~= "player"))
	badge = badge and ns.DrawClassIcon(medal.badge, class, look.iconStyle)
	medal.badge:SetShown(badge and true or false)
	medal.rim:SetShown(badge and true or false)
	-- Resting (you only): its tab.
	if medal.rest then
		medal.rest:SetShown(entry.key == "player" and Clean(Safe(IsResting)) and true or false)
	end
	-- The level: the game's figure ("??" when it hides it as too high).
	if medal.tab then
		local words = LevelWords(unit)
		medal.tab:SetShown(words ~= nil)
		if words then medal.tab.text:SetText(words) end
	end
end

-- (tests) a frame's medallion.
function ns.PortraitMedallionOf(frame) return medals[frame] end

local function Restyle(entry)
	local frame = entry.frame
	local portrait = PortraitOf(frame)
	if not portrait then return end
	local unit = ns.UnitFrameUnit(entry)
	local look = ns.UnitFramesFrameOn(entry.key) and Look()
	if not look or not Clean(Safe(UnitExists, unit)) then
		if not look then
			Unmedallion(entry, portrait)
			GameDraw(frame, portrait, unit)
		end
		return HideOverlay(frame)
	end
	-- Ink lines: the medallion in the portrait's place (the ring is Fine's and Classic's).
	if ns.UnitFramesLines and ns.UnitFramesLines() then
		HideOverlay(frame)
		GameDraw(frame, portrait, unit)
		return Medallion(entry, portrait, unit, look)
	end
	Unmedallion(entry, portrait)
	local state = State(portrait)
	local class = ClassOf(unit)
	local shows = Shows(unit, ROWS[entry.key], look)
	local gameIcon = GameIcon(unit)
	-- The picture: a class icon in the look's style, or a face where the game put an icon.
	if shows == "icon" and class then
		state.changed = ns.DrawClassIcon(portrait, class, look.iconStyle) or state.changed
	elseif state.changed or gameIcon then
		if portrait.SetTexCoord then portrait:SetTexCoord(0, 1, 0, 1) end
		if portrait.SetDesaturated then portrait:SetDesaturated(false) end
		portrait:SetVertexColor(unpack(state.vertex))
		Safe(SetPortraitTexture, portrait, unit, rawget(frame, "disablePortraitMask"))
		state.changed = gameIcon
	end
	-- Dead, a ghost or offline: greyed (facts the frame already knows; no added sign).
	local gone = Clean(Safe(UnitIsDeadOrGhost, unit)) or (Clean(Safe(UnitIsPlayer, unit)) and Safe(UnitIsConnected, unit) == false)
	if gone and look.greyDead ~= false then
		if portrait.SetDesaturated then portrait:SetDesaturated(true) end
		portrait:SetVertexColor(GREY, GREY, GREY)
		state.grey = true
	elseif state.grey then
		state.grey = false
		local ink = shows == "icon" and look.iconStyle == "ink"
		if portrait.SetDesaturated then portrait:SetDesaturated(ink) end
		if ink then portrait:SetVertexColor(unpack(INK_TINT)) else portrait:SetVertexColor(unpack(state.vertex)) end
	end
	local overlay = Overlay(entry, portrait)
	if not overlay then return end
	local dim = (gone or Clean(Safe(UnitIsTapDenied, unit))) and DIM_ALPHA or RING_ALPHA
	local r, g, b = RingColor(entry, unit, look)
	overlay.ring:SetShown(r ~= nil)
	if r then overlay.ring:SetVertexColor(r, g, b, dim) end
	-- The badge: on a player's face (never an icon on an icon), others' or yours too.
	local badge = class and shows == "face" and Clean(Safe(UnitIsPlayer, unit))
		and (look.badge == "all" or (look.badge == "others" and entry.key ~= "player"))
	badge = badge and ns.DrawClassIcon(overlay.badge, class, look.iconStyle)
	overlay.badge:SetShown(badge and true or false)
	overlay.rim:SetShown(badge and true or false)
	overlay.badge:SetAlpha(gone and DIM_ALPHA or 1)
end

-- Every portrait drawn again (UnitFrames.lua calls it with the bars).
function ns.ApplyPortraits()
	if not ns.UnitFrameEntries then return end
	for _, entry in ipairs(ns.UnitFrameEntries()) do
		byFrame[entry.frame] = entry
		Restyle(entry)
	end
end

local soon = false
local function Soon()
	if soon then return end
	soon = true
	C_Timer.After(0, function()
		soon = false
		ns.ApplyPortraits()
	end)
end

local EVENTS = { "UNIT_PORTRAIT_UPDATE", "PORTRAITS_UPDATED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UNIT_FLAGS", "UNIT_CONNECTION", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"UNIT_HEALTH", "UNIT_TARGET", "CVAR_UPDATE", "UNIT_PET", "UNIT_MODEL_CHANGED", "UNIT_CLASSIFICATION_CHANGED",
	"UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

function ns.InitPortraits()
	if type(_G.UnitFramePortrait_Update) == "function" then
		-- (after the game drew it: the look laid on that same texture)
		hooksecurefunc("UnitFramePortrait_Update", function(frame)
			local entry = type(frame) == "table" and byFrame[frame]
			if entry and Look() then Restyle(entry) end
		end)
	end
	local frame = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
	frame:SetScript("OnEvent", function(_, event, unit)
		if not Look() then return end
		-- (a unit's event: only for the units of the frames drawn here, UnitFrames.lua's set)
		unit = Clean(unit)
		if event:sub(1, 5) == "UNIT_" and not ns.UF_UNITS[unit or ""] then return end
		-- (a health, many times a second in a fight: only the frames showing that unit)
		if event == "UNIT_HEALTH" then
			for drawn, entry in pairs(byFrame) do
				local shown = drawn and ns.UnitFrameUnit(entry)
				if shown == unit or Clean(Safe(UnitIsUnit, shown, unit)) then
					-- (all a health can change here: dead, tapped; a portrait is not rendered again for each blow)
					local mark = (Clean(Safe(UnitIsDeadOrGhost, unit)) and 1 or 0) + (Clean(Safe(UnitIsTapDenied, unit)) and 2 or 0)
					if entry.healthMark ~= mark then
						entry.healthMark = mark
						Restyle(entry)
					end
				end
			end
			return
		end
		-- (another unit may be shown now: its dead or tapped state is read again at its next health)
		for _, entry in pairs(byFrame) do entry.healthMark = nil end
		-- (the unit frames' look on: it draws the portraits with the bars on its own events)
		if ns.UF_EVENTS and ns.UF_EVENTS[event] and ns.UnitFramesOn() then return end
		Soon()
	end)
end
