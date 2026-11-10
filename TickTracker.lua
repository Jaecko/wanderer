local _, ns = ...

-- What Dots.lua (your damage over time on enemies) and Hots.lua (your heals over time on friends) share: your
-- spells followed tick by tick on each unit, the game's auras read to set their true start and length, the
-- ticks seen landing, the casts aimed. Each file keeps only what is its own (who a unit is, where a cast went,
-- what a tick looks like); this one keeps the rest, once.

local U = ns.Util
local Safe, Clean = U.Safe, U.Clean

local TICK_WINDOW = 0.45 -- seconds either side of an expected tick
local AURA_GRACE = 0.7 -- seconds after a cast before a missing aura means the spell did not stay
local ALIGN_EVERY = 0.25 -- seconds between two readings of a unit's auras
local AURAS_TOLD_FOR = 120 -- seconds a reading in a fight that showed your auras vouches for an empty one
local MISSED = 2 -- ticks in a row expected and never seen: resisted, immune, dispelled, gone
local SAMPLES = 5 -- ticks kept to know a spell's real size
local SENT_FOR = 10 -- seconds a cast's aim is kept until the game says it went off
-- (the casts of the fight, the auras, the blows: listened to only while the option is on)
local COMBAT_EVENTS = { "UNIT_COMBAT", "UNIT_AURA" }
local CAST_EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }
local PLATE_EVENTS = { NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true }
local SEEN_AGAIN = { PLAYER_FOCUS_CHANGED = true, PLAYER_TARGET_CHANGED = true, NAME_PLATE_UNIT_ADDED = true,
	NAME_PLATE_UNIT_REMOVED = true, GROUP_ROSTER_UPDATE = true }
local plates = U.ShownPlates -- nameplate token -> true while shown (Util.lua keeps it)

-- spec: data (spell -> its numbers), family (the index of the first rank in them), filter (the auras read),
-- keyOf(unit), looked (units whose blows the game tells, besides the nameplates), size(entry, n),
-- new(data, spell, at, ...), on(), fallback() (the key of a cast with no aim known), and optionally
-- late(entry, n) (seconds more a tick may come late), flight (seconds a first tick may come late), flying(entry),
-- fromAura(data) (an aura read may start one), trustAura (an aura read: never dropped for ticks unseen), wake(soon).
function ns.NewTickTracker(spec)
	local T = { active = {}, ratios = {}, ticksSeen = false }
	local active, ratios = T.active, T.ratios
	local sent = {} -- cast id -> { key, at } or { unknown, at }
	local aligned = {} -- unit's key -> when its auras were last read
	local hits = { at = -1 } -- this instant's blows, by unit token (the same blow is told for each)
	local seen, seenAt = {}, nil
	local FAMILY = spec.family

	function T.Keep(list, value)
		list[#list + 1] = value
		if #list > SAMPLES then table.remove(list, 1) end
	end

	-- The game's own length for it (an aura read): longer, more ticks (talents); shorter, faster ticks.
	function T.Fit(entry, duration)
		if duration >= entry.baseDuration - 0.05 then
			entry.period = entry.basePeriod
			entry.count = math.max(1, math.floor(duration / entry.period + 0.5))
		else
			entry.count = math.max(1, math.floor(entry.baseDuration / entry.basePeriod + 0.5))
			entry.period = duration / entry.count
		end
	end

	-- When tick number n lands (from 1), and how late it may come.
	local function TickAt(entry, n) return entry.start + n * entry.period + entry.drift end
	local function Late(entry, n) return TICK_WINDOW + (spec.late and spec.late(entry, n) or 0) end
	T.TickAt = TickAt

	local function Over(entry, now) return TickAt(entry, entry.count) + Late(entry, entry.count) < now end

	-- Its ticks still to land: neither seen nor gone by (watched, a tick is waited for until its window ends;
	-- not watched, it is gone at its time).
	local function Left(entry, now, watched)
		local total = 0
		for n = 1, entry.count do
			if not entry.heard[n] and TickAt(entry, n) > now - (watched and Late(entry, n) or 0) then
				total = total + spec.size(entry, n)
			end
		end
		return total
	end

	-- Whether the blows a unit takes reach Wanderer now (the units looked at, a nameplate shown): gathered once
	-- an instant (every bar drawn asks).
	local function Watched(key, now)
		if seenAt ~= now then
			wipe(seen)
			seenAt = now
			for _, unit in ipairs(spec.looked) do
				local other = spec.keyOf(unit)
				if other then seen[other] = true end
			end
			for token in pairs(plates) do
				local other = spec.keyOf(token)
				if other then seen[other] = true end
			end
		end
		return seen[key] == true
	end

	-- The ticks passed while the unit was in sight with nothing landing: counted, so a spell resisted, a unit
	-- immune or a dispel lets it go (at any time); the ticks passed while you looked elsewhere count for nothing.
	-- (when the game hides the amounts the ticks tell, in a fight: a tick not heard then says nothing, never a
	-- miss; the spell stays to its end unless its aura says it is gone)
	local BLIND_FOR = 6 -- seconds a hidden amount keeps the ticks unheard
	local function Watch(entry, now, watched)
		local blind = T.blindUntil ~= nil and now < T.blindUntil
		local seeing = not blind and watched and entry.watchedAt and now - entry.watchedAt < 0.6
		for n = entry.checked + 1, entry.count do
			if TickAt(entry, n) + Late(entry, n) >= now then break end
			entry.checked = n
			if entry.something[n] then
				entry.missed = 0
			elseif seeing and not (spec.trustAura and entry.fromAura) then
				entry.missed = entry.missed + 1
			end
		end
		entry.watchedAt = watched and now or nil
	end

	-- Your spells on a unit as the game shows them: first rank -> { spell, expires, duration }, and whether
	-- every aura could be read (only then is a missing one truly gone). nil: nothing readable.
	local function Auras(unit)
		local read = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
		if not read then return nil end
		local found, complete = {}, true
		for index = 1, 40 do
			local aura = Safe(read, unit, index, spec.filter)
			if aura == nil then break end
			if U.IsSecret(aura) or type(aura) ~= "table" then return nil end
			local spell, source = Clean(aura.spellId), aura.sourceUnit
			local data = spell and spec.data[spell]
			if not spell then
				complete = false
			elseif data and not U.IsSecret(source) and (source == nil or source == "player") then
				found[data[FAMILY]] = { spell = spell, expires = Clean(aura.expirationTime), duration = Clean(aura.duration) }
			end
		end
		-- (your auras shown in a fight: an empty reading now means there is none, not that the game hides them)
		if next(found) and InCombatLockdown() then T.aurasToldAt = GetTime() end
		return found, complete
	end

	-- The game's word on your spells on a unit: their true start and length, the ones gone, the ones you put
	-- there without Wanderer seeing the cast (before a reload, from a talent).
	local function Align(key, unit, now)
		-- (a unit with nothing of yours: read once, then again only when its auras change for you)
		if aligned[key] and (not active[key] or now - aligned[key] < ALIGN_EVERY) then return end
		aligned[key] = now
		local auras, complete = Auras(unit)
		if not auras then return end
		local list = active[key] or {}
		for family, entry in pairs(list) do
			local aura = auras[family]
			local start = aura and aura.expires and aura.duration and aura.duration > 0 and aura.expires - aura.duration
			if start and start >= entry.cast - 0.5 then
				if math.abs(start - entry.start) > 0.25 then
					-- (put on again without a cast seen: its ticks start over)
					if entry.fromAura then entry.heard, entry.something, entry.checked, entry.missed, entry.anchored = {}, {}, 0, 0, nil end
					entry.start, entry.drift = start, 0
				end
				entry.fromAura = true
				T.Fit(entry, aura.duration)
			elseif complete and not aura and entry.fromAura and now - entry.cast > AURA_GRACE then
				-- (seen there, now gone: dispelled, pushed off; one never seen is left to its missed ticks, an
				-- empty reading may only be the game keeping them hidden)
				list[family] = nil
			elseif complete and not aura and spec.confirmAura and not entry.fromAura and T.aurasToldAt and now - T.aurasToldAt < AURAS_TOLD_FOR
				and now - entry.cast > AURA_GRACE + (spec.late and spec.late(entry, 1) or 0) then
				-- (cast, the time to land gone by, and the game shows nothing: it did not take)
				list[family] = nil
			end
		end
		for family, aura in pairs(auras) do
			local data = spec.data[aura.spell]
			if not list[family] and aura.expires and aura.duration and aura.duration > 0
				and (not spec.fromAura or spec.fromAura(data)) then
				local entry = spec.new(data, aura.spell, aura.expires - aura.duration)
				entry.fromAura = true
				T.Fit(entry, aura.duration)
				list[family] = entry
			end
		end
		active[key] = next(list) and list or nil
	end
	-- (its auras changed: read again at the next drawing)
	function T.Changed(key) aligned[key] = nil end

	-- A key now standing for another unit (a nameplate token given to the next enemy shown, a new target, a
	-- group token given to someone else): what was followed under it, and when it was read, belonged to the
	-- one before.
	function T.Forget(key)
		active[key], aligned[key] = nil, nil
	end

	-- The spells over by now let go (on units no longer seen too).
	local function Purge(now)
		for key, list in pairs(active) do
			for family, entry in pairs(list) do
				if Over(entry, now) then list[family] = nil end
			end
			if not next(list) then active[key] = nil end
		end
	end

	-- What your spells on a unit (known by key) will still do: the sum of their ticks to come.
	function T.Remaining(key, unit)
		local now = GetTime()
		Align(key, unit, now)
		local list = active[key]
		if not list then return 0, now end
		local watched = Watched(key, now)
		local total = 0
		for family, entry in pairs(list) do
			if T.ticksSeen then Watch(entry, now, watched) end
			if entry.missed >= MISSED or Over(entry, now) then
				list[family] = nil
			else
				total = total + Left(entry, now, watched)
			end
		end
		if not next(list) then active[key] = nil end
		return total, now
	end

	-- Whether anything of yours is still ticking somewhere (else nothing needs drawing).
	function T.Busy()
		Purge(GetTime())
		return next(active) ~= nil
	end

	-- A cast sent at a unit (aim: the unit, false when it cannot be known, a name hidden in a fight).
	function T.Sent(unit, cast)
		local now = GetTime()
		for id, entry in pairs(sent) do
			if now - entry.at > SENT_FOR then sent[id] = nil end
		end
		if unit == false then
			sent[cast] = { unknown = true, at = now }
		else
			sent[cast] = { key = unit and spec.keyOf(unit), at = now }
		end
	end

	-- A cast gone off: a new one on the unit it was aimed at (where it went is not known: left to its aura,
	-- read when it lands, never put on the wrong unit). ...: passed on to spec.new.
	function T.Cast(cast, spell, ...)
		local data = spec.data[spell]
		local aim = cast and sent[cast]
		if cast then sent[cast] = nil end
		if aim and aim.unknown then return end
		local key = aim and aim.key
		if not aim then key = spec.fallback() end
		if not key then return end
		local entry = spec.new(data, spell, GetTime(), ...)
		local list = active[key] or {}
		active[key] = list
		-- (the same spell again, any rank: the new one takes its place, its ticks starting over as the game does;
		-- what was seen of its size stays when it is the same spell, the same points)
		local before = list[data[FAMILY]]
		if before and before.spell == spell and before.combo == entry.combo and before.real then
			entry.real = before.real
			for i, value in ipairs(before.samples) do entry.samples[i] = value end
		end
		list[data[FAMILY]] = entry
		aligned[key] = nil
		if spec.settle then spec.settle(key) end
		if spec.wake then spec.wake() end
	end

	-- The tick of a spell that lands now, if one: its number, and how far from its time.
	function T.Due(entry, now)
		local since = now - entry.start - entry.drift
		if spec.flying and spec.flying(entry) and not entry.something[1] then
			-- (the first tick comes up to a flight late)
			local off = since - entry.period
			if off >= -TICK_WINDOW and off <= spec.flight + TICK_WINDOW then return 1, off end
		end
		local n = math.max(1, math.floor(since / entry.period + 0.5))
		if n > entry.count then return nil end
		local off = since - n * entry.period
		if math.abs(off) > TICK_WINDOW then return nil end
		return n, off
	end

	-- The same blow, told for each unit showing it (the target and its nameplate, you and your party frame):
	-- counted once. Its first telling, or nil when another unit told it first.
	function T.Told(key, signature, unit, now)
		if hits.at ~= now then hits = { at = now } end
		signature = key .. ":" .. signature
		local first = hits[signature]
		if first and first.unit ~= unit then return nil end
		if not first then
			first = { unit = unit, fed = {} }
			hits[signature] = first
		end
		return first
	end

	-- Tick n of it seen landing, off seconds from its time: the first one sets when the others land.
	function T.Heard(entry, n, off)
		entry.heard[n], entry.something[n], entry.missed, T.ticksSeen = true, true, 0, true
		if not entry.anchored then
			entry.anchored = true
			entry.drift = entry.drift + math.max(-TICK_WINDOW, math.min(off, (spec.flight or 0) + TICK_WINDOW))
		end
	end

	-- What a tick was against what was expected, kept for the next casts.
	function T.Ratio(family, ratio)
		ratios[family] = ratios[family] or {}
		T.Keep(ratios[family], math.max(0.3, math.min(3, ratio)))
	end

	-- The events: the units seen again when they change, the spells over let go out of a fight; the fight's
	-- events listened to only while the option is on (T.Sync). handlers: combat(unit, ...), aura(unit, ...),
	-- sent(name, cast, spell), cast(cast, spell), and optionally plate(unit, added), rest() (out of a fight),
	-- and one per other event of spec.events.
	function T.Listen(handlers)
		local frame = CreateFrame("Frame")
		T.frame = frame
		for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
			"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
			pcall(frame.RegisterEvent, frame, event)
		end
		for _, event in ipairs(spec.events or {}) do pcall(frame.RegisterEvent, frame, event) end
		frame:SetScript("OnEvent", function(_, event, unit, ...)
			if SEEN_AGAIN[event] then seenAt = nil end
			if PLATE_EVENTS[event] then
				unit = Clean(unit)
				if unit and handlers.plate then handlers.plate(unit, event == "NAME_PLATE_UNIT_ADDED") end
				return
			end
			if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
				-- (out of a fight: the spells over let go, every unit read again; what each keeps, read again)
				Purge(GetTime())
				wipe(aligned)
				if handlers.rest then handlers.rest() end
				if event == "PLAYER_ENTERING_WORLD" then T.Sync() end
				return
			end
			if handlers[event] then return handlers[event](unit, ...) end
			-- (another addon taking the job since: nothing done)
			if not spec.on() then return end
			if event == "UNIT_COMBAT" then
				-- (an amount the game hides: no tick can be heard for a while)
				local amount = select(3, ...)
				if U.IsSecret(amount) or U.IsSecret((...)) then T.blindUntil = GetTime() + BLIND_FOR end
				return handlers.combat(unit, ...)
			end
			if event == "UNIT_AURA" then return handlers.aura(Clean(unit), ...) end
			if event == "UNIT_SPELLCAST_SENT" then
				local name, cast, spell = ...
				cast, spell = Clean(cast), Clean(spell)
				if cast and spell and spec.data[spell] then handlers.sent(name, cast, spell) end
				return
			end
			if event == "UNIT_SPELLCAST_SUCCEEDED" then
				local cast, spell = ...
				spell = Clean(spell)
				if spell and spec.data[spell] then handlers.cast(Clean(cast), spell) end
			end
		end)
		T.Sync()
	end

	-- The fight's events on while the option is, off else (nothing done hundreds of times a second for nothing).
	local listening
	function T.Sync()
		local frame = T.frame
		if not frame then return end
		local on = spec.on() and true or false
		if on == listening then return end
		listening = on
		for _, event in ipairs(COMBAT_EVENTS) do
			if on then pcall(frame.RegisterEvent, frame, event) else pcall(frame.UnregisterEvent, frame, event) end
		end
		for _, event in ipairs(CAST_EVENTS) do
			if on then pcall(frame.RegisterUnitEvent, frame, event, "player") else pcall(frame.UnregisterEvent, frame, event) end
		end
	end

	return T
end
