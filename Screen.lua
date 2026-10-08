local _, ns = ...

-- What shows on the screen while playing:
-- * the red messages repeated in fights ("Not enough rage", "Out of range",
--   "No target"...) are filtered; the useful ones (bags full, quests...) stay;
-- * the talking heads (NPCs speaking in a frame) can be closed at once.
-- (The action camera is driven by Core, as a managed console variable.)

local Safe = ns.Util.Safe

-- Names of the game's messages that are filtered.
local FILTERED_ERRORS = {
	"ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "ERR_ITEM_COOLDOWN", "SPELL_FAILED_NOT_READY",
	"ERR_OUT_OF_ENERGY", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_MANA", "ERR_OUT_OF_RUNIC_POWER",
	"ERR_OUT_OF_HOLY_POWER", "ERR_OUT_OF_CHI", "ERR_OUT_OF_COMBO_POINTS", "SPELL_FAILED_NO_COMBO_POINTS",
	"ERR_NO_ATTACK_TARGET", "ERR_GENERIC_NO_TARGET", "SPELL_FAILED_BAD_TARGETS", "ERR_INVALID_ATTACK_TARGET",
	"SPELL_FAILED_TARGETS_DEAD", "ERR_BADATTACKFACING", "ERR_BADATTACKPOS", "SPELL_FAILED_UNIT_NOT_INFRONT",
	"SPELL_FAILED_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE", "SPELL_FAILED_SPELL_IN_PROGRESS",
	"SPELL_FAILED_MOVING", "SPELL_FAILED_CASTER_AURASTATE", "SPELL_FAILED_TARGET_AURASTATE",
}

local filtered = {} -- message text -> true
local gameHandler -- the game's own handler of the error messages
local filtering = false

local function IsFiltered(message)
	return type(message) == "string" and not ns.Util.IsSecret(message) and filtered[message] == true
end

-- The game's messages go through Wanderer's frame: filtered ones are dropped,
-- the others are passed to the game's own handler, unchanged.
local relay = CreateFrame("Frame")
relay:SetScript("OnEvent", function(_, event, errorType, message, ...)
	if IsFiltered(message) then
		-- The red text goes, its voice stays (the game's "Error Speech" option decides).
		local _, soundKitID, voiceID = Safe(GetGameMessageInfo, errorType)
		if voiceID and C_Sound and C_Sound.PlayVocalErrorSound then
			Safe(C_Sound.PlayVocalErrorSound, voiceID)
		elseif soundKitID and PlaySound then
			Safe(PlaySound, soundKitID)
		end
		return
	end
	if gameHandler then gameHandler(UIErrorsFrame, event, errorType, message, ...) end
end)

local function SetFiltering(on)
	if on == filtering or not UIErrorsFrame then return end
	if on then
		gameHandler = gameHandler or UIErrorsFrame:GetScript("OnEvent")
		if not gameHandler then return end
		UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
		relay:RegisterEvent("UI_ERROR_MESSAGE")
	else
		relay:UnregisterEvent("UI_ERROR_MESSAGE")
		UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
	filtering = on
end

-- Talking heads: hooked once, the setting is read every time one speaks.
local talkingHooked = false
local function HookTalkingHead()
	local head = _G.TalkingHeadFrame
	if talkingHooked or not (head and head.PlayCurrent) then return end
	talkingHooked = true
	hooksecurefunc(head, "PlayCurrent", function(self)
		if ns.db and ns.db.enabled and ns.db.world.hideTalkingHead and self.CloseImmediately then
			self:CloseImmediately()
		end
	end)
end

function ns.RefreshScreen()
	local db = ns.db
	SetFiltering(db.enabled and db.world.filterErrors and true or false)
	HookTalkingHead()
end

function ns.InitScreen()
	for _, name in ipairs(FILTERED_ERRORS) do
		local text = _G[name]
		if type(text) == "string" then filtered[text] = true end
	end
	-- The talking heads' window is loaded by the game later.
	local loader = CreateFrame("Frame")
	loader:RegisterEvent("ADDON_LOADED")
	loader:SetScript("OnEvent", HookTalkingHead)
	ns.RefreshScreen()
end
