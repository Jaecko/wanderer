local _, ns = ...
local L = ns.L

-- A game window and Wanderer's in its place (the merchant, the loot, the rolls): while a visit lasts,
-- the game's window stays open out of sight (every one of its features still there, the game's own clicks on
-- the bags too), Wanderer's shows. A button in Wanderer's window brings the game's back, a link above the
-- game's comes back to Wanderer's; the one chosen is kept for this character (its setting). A visit may also
-- keep the game's window for this time only (master loot, a window closed by hand): never remembered.

local U = ns.Util
local Skin = ns.Skin

-- spec: { frame() (the game's window, nil while it does not exist), wanted() (Wanderer's window chosen),
-- choose(on) (that choice kept), link (the words of the link above the game's window), linkTip,
-- point { point, relativePoint, x, y } (where that link stands against the game's window), onWanderer(),
-- onGame() (each side shown) }.
-- Returns a swap: swap:Start() (a visit begins), swap:End(), swap:Wanderer() (Wanderer's window is the one used
-- now), swap:UseGame(remember), swap:UseWanderer(remember), swap:GameOnce() (the game's for this visit only),
-- swap:Place() (the game's window put where it belongs again).
function ns.Swap(spec)
	local swap = { visiting = false, game = false }
	local place, link, hooked

	local function On() return ns.db and ns.db.enabled and spec.wanted() and true or false end

	-- (decided before the game shows its window: its first frame already out of sight)
	local function Away() return On() and not swap.game end

	local function Link()
		local frame = spec.frame()
		if link or not frame then return link end
		link = Skin.SmallButton(UIParent, Skin.GlyphText("chevron", "label") .. " " .. spec.link, function() swap:UseWanderer(true) end,
			spec.linkTip)
		link:SetFrameStrata("HIGH")
		local point = spec.point or { "BOTTOMRIGHT", "TOPRIGHT", 0, 4 }
		link:SetPoint(point[1], frame, point[2], point[3], point[4])
		link:Hide()
		return link
	end

	-- (once for the game's window; a window made anew by the game is hooked anew)
	function swap:Hook()
		local frame = spec.frame()
		if not frame or frame == hooked then return end
		hooked = frame
		place = Skin.AsideGameWindow(frame, Away)
		-- (a window the game opens then places again, the loot by its Edit Mode spot: out of sight as soon as its
		-- opening is over, before it is drawn, never a frame in its spot)
		if type(frame.Open) == "function" then
			hooksecurefunc(frame, "Open", function() if place and Away() then place() end end)
		end
		if link then
			link:ClearAllPoints()
			local point = spec.point or { "BOTTOMRIGHT", "TOPRIGHT", 0, 4 }
			link:SetPoint(point[1], frame, point[2], point[3], point[4])
		end
	end

	function swap:Place()
		self:Hook()
		if place then place() end
		-- (the link back whenever the game's window is the one on the screen during a visit)
		local frame = spec.frame()
		local shown = self.visiting and ns.db and ns.db.enabled and not Away() and frame and frame:IsShown()
		if shown or link then
			local made = Link()
			if made then made:SetShown(shown and true or false) end
		end
	end

	function swap:Wanderer() return self.visiting and Away() end

	function swap:Start()
		self.visiting = true
		self:Place()
		-- (the game's window may come a moment after the event that opened the visit)
		C_Timer.After(0, function() if self.visiting then self:Place() end end)
	end

	function swap:End()
		self.visiting, self.game = false, false
		if link then link:Hide() end
		self:Place()
	end

	-- The game's window for this visit only (nothing remembered).
	function swap:GameOnce()
		self.game = true
		self:Place()
		if spec.onGame then spec.onGame() end
	end

	function swap:UseGame(remember)
		if remember then spec.choose(false) end
		self:GameOnce()
	end

	function swap:UseWanderer(remember)
		if remember then spec.choose(true) end
		self.game = false
		self:Place()
		if self.visiting and spec.onWanderer then spec.onWanderer() end
	end

	return swap
end

-- The button of a Wanderer window that brings the game's own window back (kept for the next visits).
function ns.SwapButton(window, swap, tip)
	local button = Skin.SmallButton(window, Skin.GlyphText("move", "label") .. " " .. L.GAME_WINDOW, function() swap:UseGame(true) end,
		tip or L.SWAP_GAME_DESC)
	return button
end

-- A choice kept in every profile of this character (a setting).
function ns.KeepChoice(section, key, on)
	local function Set() if ns.db and type(ns.db[section]) == "table" then ns.db[section][key] = on and true or false end end
	if ns.ChangeEverywhere then ns.ChangeEverywhere(Set) else Set() end
	if ns.RefreshOptions then U.Try(ns.RefreshOptions) end
end
