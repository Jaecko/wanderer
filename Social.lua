local _, ns = ...
local L = ns.L

-- Requests from other players, answered for you:
-- * duels and pet battle duels declined, except from your friends;
-- * group invitations from your friends and guild accepted;
-- * resurrections and summons accepted, never during a fight.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local RESURRECT_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }

local function HidePopup(name)
	if StaticPopup_Hide then Safe(StaticPopup_Hide, name) end
end

local function IsFriendName(name)
	return Clean(name) and C_FriendList and Safe(C_FriendList.GetFriendInfo, name) ~= nil or false
end

-- A friend (in game or Battle.net) or a member of your guild.
local function IsKnown(guid)
	guid = Clean(guid)
	if not guid then return false end
	if C_FriendList and Clean(Safe(C_FriendList.IsFriend, guid)) then return true end
	if C_BattleNet and Safe(C_BattleNet.GetAccountInfoByGUID, guid) then return true end
	return Clean(Safe(IsGuildMember, guid)) and true or false
end

local function Fighting()
	return InCombatLockdown() or (IsEncounterInProgress and Clean(Safe(IsEncounterInProgress))) and true or false
end

local HANDLERS = {
	DUEL_REQUESTED = function(db, name)
		if not db.declineDuels or IsFriendName(name) then return end
		Safe(CancelDuel)
		HidePopup("DUEL_REQUESTED")
		ns.Print(L.MSG_DUEL_DECLINED:format(Clean(name) or "?"))
	end,
	PET_BATTLE_PVP_DUEL_REQUESTED = function(db, name)
		if not db.declineDuels or IsFriendName(name) then return end
		Safe(C_PetBattles and C_PetBattles.CancelPVPDuel)
		HidePopup("PET_BATTLE_PVP_DUEL_REQUESTED")
	end,
	PARTY_INVITE_REQUEST = function(db, _, _, _, _, _, _, inviterGUID)
		if not db.acceptInvites or not IsKnown(inviterGUID) then return end
		Safe(AcceptGroup)
		HidePopup("PARTY_INVITE")
	end,
	RESURRECT_REQUEST = function(db)
		if not db.acceptResurrect or Fighting() then return end
		Safe(AcceptResurrect)
		for _, popup in ipairs(RESURRECT_POPUPS) do HidePopup(popup) end
	end,
	CONFIRM_SUMMON = function(db)
		if not db.acceptSummon or Fighting() then return end
		if C_SummonInfo and C_SummonInfo.ConfirmSummon then Safe(C_SummonInfo.ConfirmSummon) else Safe(ConfirmSummon) end
		HidePopup("CONFIRM_SUMMON")
	end,
}

function ns.InitSocial()
	local frame = CreateFrame("Frame")
	for event in pairs(HANDLERS) do frame:RegisterEvent(event) end
	frame:SetScript("OnEvent", function(_, event, ...)
		local db = ns.db
		if not (db and db.enabled) then return end
		HANDLERS[event](db.social, ...)
	end)
end
