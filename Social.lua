local _, ns = ...
local L = ns.L

-- Requests from other players, answered for you:
-- * duels and pet battle duels declined, except from your friends;
-- * group invitations from your friends and guild accepted;
-- * resurrections and summons accepted, never during a fight;
-- * a whisper made of one chosen word brings its sender into your group,
--   when you lead it or have none.

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

local INVITE_AGAIN = 2 -- seconds between two invitations on the word
local lastInvite = 0

local function Trim(text)
	return strtrim(type(text) == "string" and text or ""):lower()
end

local function CanInvite()
	if not Clean(Safe(IsInGroup)) then return true end
	return Clean(Safe(UnitIsGroupLeader, "player")) or Clean(Safe(UnitIsGroupAssistant, "player")) or false
end

-- Who whispered, by the whole name: the chat gives only a first name on WoW Forever (several players may
-- share it), the game's record of that player (by its identity) gives the rest.
local function WholeName(sender, guid)
	sender = Clean(sender)
	if type(sender) ~= "string" or sender == "" then return nil end
	guid = Clean(guid)
	local recorded = guid and GetPlayerInfoByGUID and Clean(select(6, Safe(GetPlayerInfoByGUID, guid)))
	local first = sender:match("^[^%-]+") or sender
	if type(recorded) ~= "string" or #recorded <= #first or recorded:sub(1, #first) ~= first then return sender end
	local realm = sender:match("%-(.+)$")
	if realm and not recorded:find(realm, 1, true) then return recorded .. "-" .. realm end
	return recorded
end
ns.WholeName = WholeName

local HANDLERS = {
	CHAT_MSG_WHISPER = function(db, text, sender, ...)
		if not db.inviteOnWord then return end
		local word = Trim(db.inviteWord)
		if word == "" or Trim(Clean(text)) ~= word or not CanInvite() then return end
		if GetTime() - lastInvite < INVITE_AGAIN then return end
		local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
		-- (the sender's identity: the twelfth value of a whisper)
		local name = WholeName(sender, (select(10, ...)))
		if invite and name then
			lastInvite = GetTime()
			Safe(invite, name)
		end
	end,
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
		-- Accepted: the popup must not decline as it goes.
		local popup = StaticPopup_FindVisible and Safe(StaticPopup_FindVisible, "PARTY_INVITE")
		if popup then popup.inviteAccepted = true end
		HidePopup("PARTY_INVITE")
	end,
	RESURRECT_REQUEST = function(db)
		if not db.acceptResurrect or Fighting() or U.IsSkipping() then return end
		-- (in a raid, the choice stays the player's, as the game leaves it: the raid may want you to wait)
		local _, kind = Safe(IsInInstance)
		if Clean(Safe(IsInRaid)) or Clean(kind) == "raid" then return end
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
