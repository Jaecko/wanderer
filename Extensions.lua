local _, ns = ...

-- Wanderer's extensions, offered where they are missing: on the welcome
-- screen's last step, in Wanderer's card and in the settings' sidebar (a page each). One already installed
-- (even turned off) is not offered. Its CurseForge address opens ready to copy.

local CHAT_ICON = "Interface\\Icons\\INV_Letter_17"
-- Each one's page on CurseForge (its slug: wanderer-<name>), the one place they are published.
local CURSEFORGE = "https://www.curseforge.com/wow/addons/"

-- In one fixed order (the settings' sidebar, the menu, the welcome): inventory and money, then the world, then
-- the character, then people, then the game.
ns.EXTENSION_OFFERS = {
	{ addon = "WandererBags", name = "Wanderer Bags", icon = "Interface\\Icons\\INV_Misc_Bag_07", text = "EXT_BAGS",
		url = CURSEFORGE .. "wanderer-bags" },
	{ addon = "WandererAuction", name = "Wanderer Auction", icon = "Interface\\Icons\\INV_Misc_Coin_01", text = "EXT_AUCTION",
		url = CURSEFORGE .. "wanderer-auction" },
	{ addon = "WandererMail", name = "Wanderer Mail", icon = "Interface\\Icons\\INV_Letter_15", text = "EXT_MAIL",
		url = CURSEFORGE .. "wanderer-mail" },
	{ addon = "WandererQuests", name = "Wanderer Quests", icon = "Interface\\Icons\\INV_Misc_Book_09", text = "EXT_QUESTS",
		url = CURSEFORGE .. "wanderer-quests" },
	{ addon = "WandererMaps", name = "Wanderer Maps", icon = "Interface\\Icons\\INV_Misc_Map_01", text = "EXT_MAPS",
		url = CURSEFORGE .. "wanderer-maps" },
	{ addon = "WandererBestiary", name = "Wanderer Bestiary", icon = "Interface\\Icons\\Ability_Tracking", text = "EXT_BESTIARY",
		url = CURSEFORGE .. "wanderer-bestiary" },
	{ addon = "WandererTraining", name = "Wanderer Training", icon = "Interface\\Icons\\INV_Misc_Book_11", text = "EXT_TRAINING",
		url = CURSEFORGE .. "wanderer-training" },
	{ addon = "WandererOutfits", name = "Wanderer Outfits", icon = "Interface\\Icons\\INV_Chest_Cloth_21", text = "EXT_OUTFITS",
		url = CURSEFORGE .. "wanderer-outfits" },
	{ addon = "WandererChat", name = "Wanderer Chat", icon = CHAT_ICON, text = "EXT_CHAT",
		url = CURSEFORGE .. "wanderer-chat" },
	{ addon = "WandererProfessions", name = "Wanderer Professions", icon = "Interface\\Icons\\Trade_BlackSmithing", text = "EXT_PROFESSIONS",
		url = CURSEFORGE .. "wanderer-professions" },
}

local function Installed(addon)
	local addons = C_AddOns or {}
	if addons.DoesAddOnExist then
		local ok, exists = pcall(addons.DoesAddOnExist, addon)
		if ok then return exists and true or false end
	end
	if not addons.GetAddOnInfo then return false end
	local ok, name, _, _, _, reason = pcall(addons.GetAddOnInfo, addon)
	return ok and name ~= nil and reason ~= "MISSING"
end

ns.ExtensionInstalled = Installed

function ns.MissingExtensions()
	local list = {}
	for _, offer in ipairs(ns.EXTENSION_OFFERS) do
		if not Installed(offer.addon) then list[#list + 1] = offer end
	end
	return list
end

-- The extensions not installed still offered: not after "stop suggesting them" (an offer's page in the settings),
-- back with "Suggest the other Wanderer addons" (the settings' home page). Each character's own choice; one made
-- for the whole account before 0.45 still holds for a character that never chose.
function ns.OffersWanted()
	local root = ns.root
	if not root then return true end
	local mine = ns.Mine()
	if mine.hideOffers ~= nil then return not mine.hideOffers end
	return not root.hideOffers
end
function ns.SetOffersWanted(on)
	if ns.root then ns.Mine().hideOffers = not on end
end
function ns.StopOffers() ns.SetOffersWanted(false) end

-- The menu's offer: shown while some are missing (not after "stop suggesting them"), "new" while one of
-- them was never seen there.
function ns.OfferInMenu()
	if not ns.OffersWanted() then return nil end
	local missing = ns.MissingExtensions()
	if not missing[1] then return nil end
	ns.root.offersSeen = ns.root.offersSeen or {}
	local new = false
	for _, offer in ipairs(missing) do
		if not ns.root.offersSeen[offer.addon] then new = true end
	end
	return missing, new
end

function ns.OffersSeen()
	ns.root.offersSeen = ns.root.offersSeen or {}
	for _, offer in ipairs(ns.MissingExtensions()) do ns.root.offersSeen[offer.addon] = true end
end

-- Its address, selected, for Ctrl+C.
function ns.OfferExtension(offer)
	ns.Skin.ShowCopy(ns.L.LINK_COPY, offer.url)
end

-- The chat lived in Wanderer before 0.45: what it kept (the lines, the sent messages, the conversations, the
-- bubbles' colors) waits here for Wanderer Chat. Without it, each character is told once, quietly, where its
-- conversations went.
local CHAT_KEPT = { "chatHistory", "chatLog", "messages" }

function ns.ChatWaiting()
	local root = ns.root
	if not root or Installed("WandererChat") then return false end
	local key = ns.CharacterKey()
	for _, name in ipairs(CHAT_KEPT) do
		local mine = type(root[name]) == "table" and root[name][key]
		if type(mine) == "table" and next(mine) ~= nil then return true end
	end
	return type(root.messageColors) == "table" and next(root.messageColors) ~= nil
end

-- Told once by character (a notice, never in a fight: it waits for the end of it). True when told now.
local chatWaitingLater
function ns.TellChatWaiting()
	if not ns.ChatWaiting() then return false end
	local mine = ns.Mine()
	if mine.chatWaitingTold then return false end
	if InCombatLockdown() then
		if not chatWaitingLater then
			chatWaitingLater = CreateFrame("Frame")
			chatWaitingLater:SetScript("OnEvent", function(self)
				self:UnregisterAllEvents()
				ns.TellChatWaiting()
			end)
		end
		chatWaitingLater:RegisterEvent("PLAYER_REGEN_ENABLED")
		return false
	end
	-- Seen only once really shown (one dropped from the queue is told again at a next arrival); one still
	-- waiting is not asked for twice.
	if ns.ToastWaiting and ns.ToastWaiting(ns.L.CHAT_WAITING_TITLE) then return false end
	ns.Toast(ns.L.CHAT_WAITING_TITLE, ns.L.CHAT_WAITING_TEXT, { icon = CHAT_ICON, kicker = "Wanderer", duration = 12,
		onShow = function() mine.chatWaitingTold = true end })
	return true
end
