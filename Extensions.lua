local _, ns = ...

-- Wanderer's extensions, offered where they are missing: on the welcome
-- screen's last step and on the options' home page. One already installed
-- (even turned off) is not offered. Its address opens ready to copy.

ns.EXTENSION_OFFERS = {
	{ addon = "WandererBags", name = "Wanderer Bags", icon = "Interface\\Icons\\INV_Misc_Bag_07", text = "EXT_BAGS",
		url = "https://wanderer-addon.com/#bags" },
	{ addon = "WandererAuction", name = "Wanderer Auction", icon = "Interface\\Icons\\INV_Misc_Coin_01", text = "EXT_AUCTION",
		url = "https://wanderer-addon.com/#auction" },
	{ addon = "WandererQuests", name = "Wanderer Quests", icon = "Interface\\Icons\\INV_Misc_Book_09", text = "EXT_QUESTS",
		url = "https://wanderer-addon.com/#quests" },
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

function ns.MissingExtensions()
	local list = {}
	for _, offer in ipairs(ns.EXTENSION_OFFERS) do
		if not Installed(offer.addon) then list[#list + 1] = offer end
	end
	return list
end

-- Its address, selected, for Ctrl+C.
function ns.OfferExtension(offer)
	if StaticPopup_Show then StaticPopup_Show("WANDERER_LINK", nil, nil, offer.url) end
end
