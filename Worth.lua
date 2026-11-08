local _, ns = ...

-- What a merchant would give for an item, in its tooltip wherever you are
-- (the game says it at a merchant only): the stack's price when the hovered
-- slot holds several. Nothing over what cannot be sold, nothing twice when
-- the game already says it.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local function Wanted()
	local db = ns.db
	-- (another addon writing it already: once is enough)
	return db and db.enabled and db.tooltips.sellPrice and not ns.Yields("sellPrice") and true or false
end

-- The game's own line, when it is there (at a merchant, or a client that always says it).
local function GameSaysIt(data)
	local kind = Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
	if not (kind and type(data) == "table") then return false end
	for _, line in ipairs(type(data.lines) == "table" and data.lines or {}) do
		if Clean(line.type) == kind then return true end
	end
	return false
end

-- How many the hovered slot holds (a bag's button says it), else one.
local function CountOf(tooltip)
	local owner = tooltip.GetOwner and Safe(tooltip.GetOwner, tooltip)
	local count = type(owner) == "table" and tonumber(Clean(owner.count))
	return (count and count > 1) and count or 1
end

local function AddLine(tooltip, id, data)
	if not Wanted() or GameSaysIt(data) then return false end
	local price = id and U.SellPrice(id)
	if not (price and price > 0) then return false end
	local total = price * CountOf(tooltip)
	-- (written as words with the coins' icons, never with the game's money frame: one made by an addon keeps its
	-- mark, and the game's own prices in it fail after, a quest's reward among them)
	tooltip:AddDoubleLine(SELL_PRICE .. ":", U.Coins(total), 1, 1, 1, 1, 1, 1)
	return true
end

function ns.InitWorth() U.OnItemTooltip(AddLine) end
