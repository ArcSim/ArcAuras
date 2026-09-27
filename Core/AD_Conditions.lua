-- Load conditions and visibility fades for every record type, kept on rec.c.
-- A record failing "who" (Store.IsLoaded) is released; one failing "when" goes
-- inert: invisible, no mouse or sounds, out of its dynamic cell, frames kept.
-- While the options panel is open, everything shows active and fully visible.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local Conditions = {}
NS.Conditions = Conditions

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- World reads

-- Last plain answer per guarded read: a restricted moment returns a secret,
-- and a condition must not flip on a value it can't read.
local lastPlain = {}
local function Plain(key, v)
    if IsSecret(v) then return lastPlain[key] == true end
    local b = v and true or false
    lastPlain[key] = b
    return b
end

-- Combat and encounter state are flags set by their own, always armed events.
-- InCombatLockdown still reads false while PLAYER_REGEN_DISABLED is delivered.
local inCombat = false
local encounterActive = false

-- The stance bar's spell ID names the form; Forever's classic IDs and retail's
-- are both listed. GetShapeshiftFormID is the druid fallback.
local FORM_BY_SPELL = {
    [768] = "cat", [5487] = "bear", [9634] = "bear", [24858] = "moonkin",
    [783] = "travel", [1066] = "travel", [33943] = "travel", [40120] = "travel",
    [33891] = "tree", [114282] = "tree",
    [2457] = "battle", [71] = "defensive", [2458] = "berserker",
    [386164] = "battle", [386208] = "battle", [386196] = "defensive",
    [15473] = "shadowform", [232698] = "shadowform",
}
local FORM_BY_ID = {
    [1] = "cat", [5] = "bear", [8] = "bear", [31] = "moonkin", [35] = "moonkin",
    [3] = "travel", [4] = "travel", [27] = "travel", [29] = "travel",
    [2] = "tree", [36] = "tree",
}
local function CurrentForm()
    local idx = GetShapeshiftForm and GetShapeshiftForm()
    if IsSecret(idx) then return "unknown" end
    if type(idx) ~= "number" or idx == 0 then return "none" end
    if GetShapeshiftFormInfo then
        local _, _, _, spellID = GetShapeshiftFormInfo(idx)
        if type(spellID) == "number" and not IsSecret(spellID) then
            local f = FORM_BY_SPELL[spellID]
            if f then return f end
        end
    end
    if GetShapeshiftFormID then
        local fid = GetShapeshiftFormID()
        if type(fid) == "number" and not IsSecret(fid) then
            local f = FORM_BY_ID[fid]
            if f then return f end
        end
    end
    return "other"
end

local memo = {}
local formMemo

local function Form()
    if not formMemo then formMemo = CurrentForm() end
    return formMemo
end

local function InstanceType()
    if not IsInInstance then return "none" end
    local inside, kind = IsInInstance()
    if IsSecret(inside) or IsSecret(kind) then return lastPlain.instanceType or "none" end
    if not inside then kind = "none" end
    lastPlain.instanceType = kind or "none"
    return lastPlain.instanceType
end

local function GroupKind()
    local raid = IsInRaid and IsInRaid()
    local grp = IsInGroup and IsInGroup()
    if IsSecret(raid) or IsSecret(grp) then return lastPlain.groupKind or "solo" end
    local g = raid and "raid" or (grp and "party" or "solo")
    lastPlain.groupKind = g
    return g
end

-- SecretWhenUnitSpellCastRestricted: the returns are only nil-tested, which a
-- secret allows (the first return is a string, not a boolean).
local function Casting()
    local n = UnitCastingInfo and UnitCastingInfo("player")
    if n then return true end
    n = UnitChannelInfo and UnitChannelInfo("player")
    if n then return true end
    return false
end

local function Flying()
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local gliding = C_PlayerInfo.GetGlidingInfo()
        if not IsSecret(gliding) and gliding == true then return true end
    end
    return Plain("flying", IsFlying and IsFlying())
end

local function InVehicle()
    return Plain("vehicle", UnitInVehicle and UnitInVehicle("player"))
        or Plain("vehicleUI", UnitHasVehicleUI and UnitHasVehicleUI("player"))
        or Plain("taxi", UnitOnTaxi and UnitOnTaxi("player"))
end

local function Dead()
    return Plain("dead", UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end

local function HasTarget()
    return Plain("hasTarget", UnitExists and UnitExists("target"))
end

-- Vocabulary. key: what rec.c stores (saved, so never renamed). text: follows
-- the list name ("Load when", "Fade when"). ev: the events that change it.
-- poll: no event reports it. class: only that class's panel lists it.
-- avail: the client has the system. negOnly: only the never and fade lists.

local CAST_EV = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP" }
local TARGET_EV = { "PLAYER_TARGET_CHANGED", "UNIT_FACTION" }
local GROUP_EV = { "GROUP_ROSTER_UPDATE" }
local PLACE_EV = { "ZONE_CHANGED_NEW_AREA" }   -- plus the always-armed PLAYER_ENTERING_WORLD
local FORM_EV = { "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS" }
local DEAD_EV = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local VEHICLE_EV = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "VEHICLE_UPDATE" }

local function FormIs(name)
    return function() return Form() == name end
end

local VOCAB = {
    { key = "inCombat", cat = "combat", text = "In combat",
        read = function() return inCombat end },
    { key = "outOfCombat", cat = "combat", text = "Out of combat",
        read = function() return not inCombat end },
    { key = "mounted", cat = "move", text = "Mounted",
        ev = { "PLAYER_MOUNT_DISPLAY_CHANGED", "COMPANION_UPDATE" },
        read = function() return Plain("mounted", IsMounted and IsMounted()) end },
    { key = "flying", cat = "move", text = "Flying", poll = true, read = Flying },
    { key = "swimming", cat = "move", text = "Swimming", poll = true,
        read = function() return Plain("swimming", IsSwimming and IsSwimming()) end },
    { key = "vehicle", cat = "move", text = "Vehicle or taxi", ev = VEHICLE_EV,
        read = InVehicle },
    { key = "indoors", cat = "move", text = "Indoors", poll = true,
        read = function() return Plain("indoors", IsIndoors and IsIndoors()) end },
    { key = "outdoors", cat = "move", text = "Outdoors", poll = true,
        read = function() return Plain("outdoors", IsOutdoors and IsOutdoors()) end },
    { key = "dead", cat = "player", text = "Dead or a ghost", ev = DEAD_EV, read = Dead },
    { key = "alive", cat = "player", text = "Alive", ev = DEAD_EV,
        read = function() return not Dead() end },
    { key = "resting", cat = "player", text = "Resting", ev = { "PLAYER_UPDATE_RESTING" },
        read = function() return Plain("resting", IsResting and IsResting()) end },
    { key = "stealthed", cat = "player", text = "Stealthed", ev = { "UPDATE_STEALTH" },
        read = function() return Plain("stealthed", IsStealthed and IsStealthed()) end },
    { key = "casting", cat = "player", text = "Casting", ev = CAST_EV, read = Casting },
    { key = "notCasting", cat = "player", text = "Not casting", ev = CAST_EV,
        read = function() return not Casting() end },
    { key = "hasPet", cat = "player", text = "Pet is out", ev = { "UNIT_PET" },
        read = function() return Plain("hasPet", UnitExists and UnitExists("pet")) end },
    -- SecretWhenUnitIdentityRestricted: Plain keeps the last real answer
    { key = "pvp", cat = "player", text = "PvP flagged",
        ev = { "UNIT_FACTION", "PLAYER_FLAGS_CHANGED" },
        read = function() return Plain("pvp", UnitIsPVP and UnitIsPVP("player")) end },
    { key = "hasTarget", cat = "target", text = "Have a target", ev = TARGET_EV,
        read = HasTarget },
    { key = "noTarget", cat = "target", text = "No target", ev = TARGET_EV,
        read = function() return not HasTarget() end },
    { key = "targetHostile", cat = "target", text = "Target is hostile", ev = TARGET_EV,
        read = function()
            return HasTarget()
                and Plain("targetHostile", UnitCanAttack and UnitCanAttack("player", "target"))
        end },
    { key = "targetFriendly", cat = "target", text = "Target is friendly", ev = TARGET_EV,
        read = function()
            return HasTarget()
                and Plain("targetFriendly", UnitIsFriend and UnitIsFriend("player", "target"))
        end },
    { key = "hasFocus", cat = "target", text = "Have a focus", ev = { "PLAYER_FOCUS_CHANGED" },
        read = function() return Plain("hasFocus", UnitExists and UnitExists("focus")) end },
    { key = "solo", cat = "group", text = "Solo", ev = GROUP_EV,
        read = function() return GroupKind() == "solo" end },
    { key = "party", cat = "group", text = "In a party", ev = GROUP_EV,
        read = function() return GroupKind() == "party" end },
    { key = "raid", cat = "group", text = "In a raid group", ev = GROUP_EV,
        read = function() return GroupKind() == "raid" end },
    { key = "instance", cat = "place", text = "In an instance", ev = PLACE_EV,
        read = function() return InstanceType() ~= "none" end },
    { key = "openWorld", cat = "place", text = "Open world", ev = PLACE_EV,
        read = function() return InstanceType() == "none" end },
    { key = "dungeon", cat = "place", text = "In a dungeon", ev = PLACE_EV,
        read = function() return InstanceType() == "party" end },
    { key = "raidInstance", cat = "place", text = "In a raid instance", ev = PLACE_EV,
        read = function() return InstanceType() == "raid" end },
    { key = "battleground", cat = "place", text = "In a battleground", ev = PLACE_EV,
        read = function() return InstanceType() == "pvp" end },
    { key = "arena", cat = "place", text = "In an arena", ev = PLACE_EV,
        read = function() return InstanceType() == "arena" end },
    { key = "encounter", cat = "place", text = "Boss encounter",
        read = function() return encounterActive end },
    { key = "petBattle", cat = "place", text = "Pet battle",
        avail = function() return C_PetBattles ~= nil and C_PetBattles.IsInBattle ~= nil end,
        ev = { "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE" },
        read = function()
            return Plain("petBattle", C_PetBattles and C_PetBattles.IsInBattle
                and C_PetBattles.IsInBattle())
        end },
    { key = "formCaster", cat = "form", class = "DRUID", text = "Caster form",
        ev = FORM_EV, read = FormIs("none") },
    { key = "formCat", cat = "form", class = "DRUID", text = "Cat Form",
        ev = FORM_EV, read = FormIs("cat") },
    { key = "formBear", cat = "form", class = "DRUID", text = "Bear Form",
        ev = FORM_EV, read = FormIs("bear") },
    { key = "formMoonkin", cat = "form", class = "DRUID", text = "Moonkin Form",
        ev = FORM_EV, read = FormIs("moonkin") },
    -- Travel, Aquatic and the flight forms all read as one
    { key = "formTravel", cat = "form", class = "DRUID", text = "Travel forms",
        ev = FORM_EV, read = FormIs("travel") },
    { key = "formTree", cat = "form", class = "DRUID", text = "Tree of Life",
        ev = FORM_EV, read = FormIs("tree") },
    { key = "stanceBattle", cat = "form", class = "WARRIOR", text = "Battle Stance",
        ev = FORM_EV, read = FormIs("battle") },
    { key = "stanceDefensive", cat = "form", class = "WARRIOR", text = "Defensive Stance",
        ev = FORM_EV, read = FormIs("defensive") },
    { key = "stanceBerserker", cat = "form", class = "WARRIOR", text = "Berserker Stance",
        ev = FORM_EV, read = FormIs("berserker") },
    { key = "stanceNone", cat = "form", class = "WARRIOR", text = "No stance",
        ev = FORM_EV, read = FormIs("none") },
    { key = "shadowform", cat = "form", class = "PRIEST", text = "In Shadowform",
        ev = FORM_EV, read = FormIs("shadowform") },
    { key = "noShadowform", cat = "form", class = "PRIEST", text = "Out of Shadowform",
        ev = FORM_EV, read = function() return Form() ~= "shadowform" end },
    { key = "always", cat = "other", text = "Always", negOnly = true,
        read = function() return true end },
}
Conditions.VOCAB = VOCAB

Conditions.CATEGORIES = {
    { id = "combat", text = "Combat" },
    { id = "move", text = "Movement" },
    { id = "player", text = "Player" },
    { id = "target", text = "Target" },
    { id = "group", text = "Group" },
    { id = "place", text = "Place" },
    { id = "form", text = "Forms and Stances" },
    { id = "other", text = "Other" },
}

local BY_KEY = {}
for _, d in ipairs(VOCAB) do BY_KEY[d.key] = d end
function Conditions.ByKey(key) return BY_KEY[key] end

-- rec.c lists; <list>All = true on the two positive ones means all must hold.
local LISTS = { "loadWhen", "loadNever", "showWhen", "fadeWhen" }
Conditions.LISTS = LISTS
local MATCH_LISTS = { loadWhen = true, showWhen = true }

-- fadeAlpha is 0-1 (0 = hidden); fadeTime and fadeDelay are in seconds.
local FADE_DEFAULT = { fadeAlpha = 0, fadeTime = 0, fadeDelay = 0 }
local FADE_MAX = { fadeAlpha = 1, fadeTime = 3, fadeDelay = 10 }
Conditions.FADE_MAX = FADE_MAX

-- Faction is a "who" condition; these are UnitFactionGroup's English tags.
Conditions.FACTIONS = { "Alliance", "Horde" }

local factionTag
function Conditions.PlayerFaction()
    if factionTag then return factionTag end
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if IsSecret(f) or type(f) ~= "string" or f == "" then return nil end
    factionTag = f
    return f
end

-- Evaluation

local function Is(key)
    local v = memo[key]
    if v == nil then
        local d = BY_KEY[key]
        v = (d ~= nil and d.read() == true) or false
        memo[key] = v
    end
    return v
end

-- Fresh world reads for everything evaluated after this. The engine calls it
-- as a rebuild starts, and every pass calls it.
function Conditions.Refresh()
    wipe(memo)
    formMemo = nil
end

-- Unknown keys (saved by a newer version) stay on the record but decide nothing.
local function SetHas(set)
    if type(set) ~= "table" then return false end
    for key in pairs(set) do
        if BY_KEY[key] then return true end
    end
    return false
end

local function SetAny(set)
    if type(set) ~= "table" then return false end
    for key in pairs(set) do
        if BY_KEY[key] and Is(key) then return true end
    end
    return false
end

local function SetMatch(set, all)
    local n, hit = 0, 0
    for key in pairs(set) do
        if BY_KEY[key] then
            n = n + 1
            if Is(key) then hit = hit + 1 end
        end
    end
    if n == 0 then return true end
    if all then return hit == n end
    return hit > 0
end

local EMPTY = {}

-- Target range, a Visibility rule of its own: full opacity only while the target
-- is in (or out of) range of one spell, besides Full Opacity When. With no target,
-- or a spell that cannot check it, it holds neither way. NS.DriverRange answers.
local function RuleOf(c)
    local mode = c.rangeMode
    local id = tonumber(c.rangeSpell)
    if (mode ~= "in" and mode ~= "out") or not id or id <= 0 then return nil end
    return id, mode
end

function Conditions.RangeRule(rec)
    return RuleOf((rec and rec.c) or EMPTY)
end

-- Without the range engine loaded the rule is left out.
local function RangeHolds(rec)
    local id, mode = Conditions.RangeRule(rec)
    local DR = NS.DriverRange
    if not (id and DR) then return true end
    local v = DR.Spell(id)
    if v == nil then return false end
    return v == (mode == "in")
end

-- The "when" half of the load layer ("who" is Store.IsLoaded). Failing it only
-- makes a record inert, keeping its frames so it can return in combat: aura
-- engine slots can't be created while auras are secret.
local function WhenOK(rec)
    local c = rec.c or EMPTY
    if SetHas(c.loadWhen) and not SetMatch(c.loadWhen, c.loadWhenAll == true) then
        return false
    end
    if SetAny(c.loadNever) then return false end
    return true
end

local function FadeValue(c, k)
    local v = tonumber(c[k])
    if not v then return FADE_DEFAULT[k] end
    if v < 0 then v = 0 elseif v > FADE_MAX[k] then v = FADE_MAX[k] end
    return v
end

-- "Full opacity when" decides if it has entries; "Fade when" always wins.
local function FadeTarget(rec)
    local c = rec.c or EMPTY
    local full = true
    if SetHas(c.showWhen) then full = SetMatch(c.showWhen, c.showWhenAll == true) end
    if full and not RangeHolds(rec) then full = false end
    if full and SetAny(c.fadeWhen) then full = false end
    if full then return 1 end
    return FadeValue(c, "fadeAlpha")
end

local function EditMode()
    local E = NS.LayoutEngine
    return E ~= nil and E.IsEditMode ~= nil and E.IsEditMode() == true
end

-- Fade state per live record: cur (painted alpha), target, inert, wait (end of
-- the delay), since (when the lower target began), rate, time, pass, edit.
local st = {}
local passNo = 0

local Kick   -- forward-declared; Evaluate's delay timer calls it

local function Evaluate(rec, now, edit)
    local s = st[rec.id]
    local fresh = s == nil
    if fresh then
        s = { cur = 1, target = 1, time = 0 }
        st[rec.id] = s
    end
    local wasInert = s.inert
    if edit then
        s.inert, s.target, s.cur, s.wait, s.rate, s.since = false, 1, 1, nil, nil, nil
    else
        s.inert = not WhenOK(rec)
        local c = rec.c or EMPTY
        local target = FadeTarget(rec)
        local time = FadeValue(c, "fadeTime")
        -- A changed fade time re-times whatever glide is left.
        if time ~= s.time then s.time, s.rate = time, nil end
        if fresh or target >= s.cur then
            -- Fading in is instant, and a record seen for the first time starts
            -- settled, so a login plays no fade.
            s.cur, s.target, s.wait, s.rate, s.since = target, target, nil, nil, nil
        else
            -- A lower target waits out the delay (re-read every pass) from when
            -- it began, then glides for the fade time.
            if target ~= s.target then
                s.target, s.rate, s.since = target, nil, now
            end
            local wait = (s.since or now) + FadeValue(c, "fadeDelay")
            if wait > now then
                if s.wait ~= wait then C_Timer.After(wait - now + 0.02, Kick) end
                s.wait = wait
            else
                s.wait = nil
                if s.time <= 0 then s.cur = s.target end
            end
        end
    end
    s.pass, s.edit = passNo, edit
    return wasInert ~= nil and wasInert ~= s.inert
end

-- Fade driver: an OnUpdate that runs only while something glides

local driver = CreateFrame("Frame")
local driving = false
local subjects, subjectOrder = {}, {}

local function ApplyOne(rec)
    local sub = subjects[rec.type]
    if sub and sub.apply then sub.apply(rec) end
end

local function Due(s, now)
    return s.cur > s.target and not (s.wait and now < s.wait)
end

local function Glide(_, elapsed)
    local now = GetTime()
    local gliding, painted = false, false
    for id, s in pairs(st) do
        if Due(s, now) then
            s.wait = nil
            if (s.time or 0) <= 0 then
                s.cur = s.target
            else
                s.rate = s.rate or ((s.cur - s.target) / s.time)
                s.cur = math.max(s.target, s.cur - s.rate * elapsed)
            end
            local rec = Store.Get(id)
            if rec then
                ApplyOne(rec)
                painted = true
            end
            if s.cur > s.target then gliding = true end
        end
    end
    if painted then Events.Fire("AD_VISIBILITY") end
    if not gliding then
        driver:SetScript("OnUpdate", nil)
        driving = false
        -- A finished fade can land on 0: one more pass re-checks the mouse.
        Conditions.Queue()
    end
end

Kick = function()
    if driving then return end
    local now = GetTime()
    for _, s in pairs(st) do
        if Due(s, now) then
            driving = true
            driver:SetScript("OnUpdate", Glide)
            return
        end
    end
end

-- Events, armed only for the conditions live records use

local armed, invalid = {}, {}
local inUse, polled, pollLast = {}, {}, {}
local pollTicker
-- The spells live records' target range rules read.
local rangeUse = {}

local function EventValid(e)
    if invalid[e] then return false end
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(e) then
        invalid[e] = true
        return false
    end
    return true
end

-- Unit events arrive for every unit; only these units move a condition.
local UNIT_ARG = {
    UNIT_ENTERED_VEHICLE = "player", UNIT_EXITED_VEHICLE = "player",
    UNIT_SPELLCAST_START = "player", UNIT_SPELLCAST_STOP = "player",
    UNIT_SPELLCAST_CHANNEL_START = "player", UNIT_SPELLCAST_CHANNEL_STOP = "player",
    UNIT_SPELLCAST_EMPOWER_START = "player", UNIT_SPELLCAST_EMPOWER_STOP = "player",
    UNIT_PET = "player",
    UNIT_FACTION = "either",   -- the PvP flag (player) or hostility (target)
}

local function OnEvent(event, unit)
    local want = UNIT_ARG[event]
    if want == "player" and unit ~= "player" then return end
    if want == "either" and unit ~= "player" and unit ~= "target" then return end
    Conditions.Queue()
    -- A taxi or vehicle can settle a moment after the control events.
    if event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
        C_Timer.After(0.3, Conditions.Queue)
    end
end

local function PollTick()
    local changed = false
    for key in pairs(polled) do
        local v = BY_KEY[key].read() == true
        if pollLast[key] ~= v then
            pollLast[key] = v
            changed = true
        end
    end
    if changed then Conditions.Queue() end
end

local function Arm()
    local want = {}
    wipe(polled)
    for key in pairs(inUse) do
        local d = BY_KEY[key]
        if d.ev then
            for _, e in ipairs(d.ev) do want[e] = true end
        end
        if d.poll then polled[key] = true end
    end
    for e in pairs(want) do
        if not armed[e] and EventValid(e) then
            Events.On(e, "adcond", OnEvent)
            armed[e] = true
        end
    end
    for e in pairs(armed) do
        if not want[e] then
            Events.Off(e, "adcond")
            armed[e] = nil
        end
    end
    -- Flying, swimming, indoors and outdoors have no event, so they poll.
    if next(polled) then
        if not pollTicker then pollTicker = C_Timer.NewTicker(0.3, PollTick) end
    elseif pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
        wipe(pollLast)
    end
    -- The range engine watches the rules' spells by event: no timer.
    local DR = NS.DriverRange
    if DR then
        local list = {}
        for id in pairs(rangeUse) do list[#list + 1] = id end
        if #list > 0 then
            DR.Use("adcond", { spells = list }, Conditions.Queue)
        else
            DR.Drop("adcond")
        end
    end
end

-- Subjects. A record type joins by registering once, from the module that owns
-- its frames: each(fn) calls fn(id) for every live record of the type, and
-- apply(rec) paints one from AlphaFor, IsInert and MouseBlocked.

function Conditions.RegisterSubject(recType, sub)
    if not subjects[recType] then subjectOrder[#subjectOrder + 1] = recType end
    subjects[recType] = sub
end

local function CollectKeys(c)
    for _, list in ipairs(LISTS) do
        local set = c[list]
        if type(set) == "table" then
            for key in pairs(set) do
                if BY_KEY[key] then inUse[key] = true end
            end
        end
    end
    local id = RuleOf(c)
    if id then rangeUse[id] = true end
end

-- Evaluate every live record, then paint, since a painter reads its parents'
-- results. Alphas are written before AD_VISIBILITY fires; listeners read them.
function Conditions.Pass()
    passNo = passNo + 1
    Conditions.Refresh()
    local edit = EditMode()
    local now = GetTime()
    wipe(inUse)
    wipe(rangeUse)
    local flipped = false
    for _, recType in ipairs(subjectOrder) do
        subjects[recType].each(function(id)
            local rec = Store.Get(id)
            if rec and rec.c then
                if Evaluate(rec, now, edit) and rec.type == "icon" then flipped = true end
                CollectKeys(rec.c)
            end
        end)
    end
    for _, recType in ipairs(subjectOrder) do
        local sub = subjects[recType]
        sub.each(function(id)
            local rec = Store.Get(id)
            if rec and rec.c then sub.apply(rec) end
        end)
    end
    for id, s in pairs(st) do
        if s.pass ~= passNo then st[id] = nil end
    end
    Arm()
    Kick()
    -- An icon that went inert or came back leaves or retakes its dynamic
    -- cell; the engine re-places only its dynamic groups.
    if flipped then Events.Fire("AD_DYNEDGE") end
    -- Aura displays hang off UIParent, not these frames, so their drivers
    -- copy the effective alphas whenever they change.
    Events.Fire("AD_VISIBILITY")
end

function Conditions.Queue()
    Events.Coalesce("ad_cond", Conditions.Pass)
end

-- Queries for the painters and drivers

local function OwnInert(rec)
    local s = st[rec.id]
    -- A state painted during an edit session says nothing about play mode.
    if s and s.pass == passNo and not s.edit then return s.inert == true end
    -- Not evaluated yet (mid-rebuild): answer from the live world.
    return not WhenOK(rec)
end

-- Ancestors: an icon's group and layout, a group's or bar's layout.
local function Parents(rec)
    local g = rec.groupId and Store.Get(rec.groupId) or nil
    local lid = rec.layoutId or (g and g.layoutId)
    local l = (lid and lid ~= rec.id) and Store.Get(lid) or nil
    return g, l
end

-- Own when-layer only: an inert icon leaves its dynamic cell.
function Conditions.IsOwnInert(rec)
    if not rec or EditMode() then return false end
    return OwnInert(rec)
end

-- Inert itself or under an inert group or layout: no sounds, no mouse.
function Conditions.IsInert(rec)
    if not rec or EditMode() then return false end
    if OwnInert(rec) then return true end
    local g, l = Parents(rec)
    return (g ~= nil and OwnInert(g)) or (l ~= nil and OwnInert(l))
end

-- Own condition opacity: 0 while inert, else the fade. Frames inherit their
-- parents' alpha, so a painter must not multiply the chain.
function Conditions.AlphaFor(rec)
    if not rec or EditMode() then return 1 end
    if OwnInert(rec) then return 0 end
    local s = st[rec.id]
    if s then return s.cur end
    return FadeTarget(rec)
end

-- The whole chain: an icon under a group faded to nothing ignores the mouse too.
function Conditions.MouseBlocked(rec)
    if not rec or EditMode() then return false end
    if Conditions.AlphaFor(rec) <= 0 then return true end
    local g, l = Parents(rec)
    if g and Conditions.AlphaFor(g) <= 0 then return true end
    if l and Conditions.AlphaFor(l) <= 0 then return true end
    return false
end

-- Editing API for the Load Conditions and Visibility tabs

-- A row is offered when the client has the system. A class-only row shows for
-- its class, or wherever it is checked, so the choice can be seen and cleared.
function Conditions.Offered(d, rec, list)
    if d.avail and not d.avail() then return false end
    if d.negOnly and (list == "loadWhen" or list == "showWhen") then return false end
    if d.class and d.class ~= Store.ClassTag() then
        return rec ~= nil and Conditions.Has(rec, list, d.key)
    end
    return true
end

function Conditions.Has(rec, list, key)
    local set = rec and rec.c and rec.c[list]
    return type(set) == "table" and set[key] == true
end

function Conditions.Count(rec, list)
    local set = rec and rec.c and rec.c[list]
    local n = 0
    if type(set) == "table" then
        for key in pairs(set) do
            if BY_KEY[key] then n = n + 1 end
        end
    end
    return n
end

function Conditions.Toggle(rec, list, key)
    if not (rec and BY_KEY[key]) then return end
    local c = rec.c
    local set = type(c[list]) == "table" and c[list] or {}
    if set[key] then set[key] = nil else set[key] = true end
    c[list] = next(set) and set or nil
    Store.Dirty("load", rec.id)
end

function Conditions.Clear(rec, list)
    if not (rec and rec.c[list]) then return end
    rec.c[list] = nil
    Store.Dirty("load", rec.id)
end

function Conditions.MatchAll(rec, list)
    return rec ~= nil and rec.c[list .. "All"] == true
end

function Conditions.SetMatchAll(rec, list, all)
    if not (rec and MATCH_LISTS[list]) then return end
    rec.c[list .. "All"] = all and true or nil
    Store.Dirty("load", rec.id)
end

function Conditions.GetFade(rec, k)
    return FadeValue(rec and rec.c or EMPTY, k)
end

function Conditions.SetFade(rec, k, v)
    if not (rec and FADE_DEFAULT[k] ~= nil) then return end
    v = tonumber(v) or FADE_DEFAULT[k]
    if v < 0 then v = 0 elseif v > FADE_MAX[k] then v = FADE_MAX[k] end
    if v == FADE_DEFAULT[k] then v = nil end
    if rec.c[k] == v then return end
    rec.c[k] = v
    Store.Dirty("load", rec.id)
end

-- No set means every faction.
function Conditions.FactionOn(rec, fac)
    local set = rec and rec.c and rec.c.factions
    if type(set) ~= "table" then return true end
    return set[fac] == true
end

function Conditions.ToggleFaction(rec, fac)
    if not rec then return end
    local set, full = {}, true
    for _, f in ipairs(Conditions.FACTIONS) do
        if Conditions.FactionOn(rec, f) then set[f] = true end
    end
    if set[fac] then set[fac] = nil else set[fac] = true end
    for _, f in ipairs(Conditions.FACTIONS) do
        if not set[f] then full = false end
    end
    rec.c.factions = (not full) and set or nil
    Store.Dirty("load", rec.id)
end

-- "in", "out", or nil for no target range rule.
function Conditions.SetRangeMode(rec, mode)
    if not rec then return end
    if mode ~= "in" and mode ~= "out" then mode = nil end
    if rec.c.rangeMode == mode then return end
    rec.c.rangeMode = mode
    Store.Dirty("load", rec.id)
end

function Conditions.SetRangeSpell(rec, id)
    if not rec then return end
    id = tonumber(id)
    id = (id and id > 0) and math.floor(id) or nil
    if rec.c.rangeSpell == id then return end
    rec.c.rangeSpell = id
    Store.Dirty("load", rec.id)
end

-- Old "hide when" keys are folded into Fade when by Store.Normalize itself
-- (FoldHideWhen), so that migration never depends on this file having loaded.

-- Shape checks for the rec.c keys this module owns. Store.Normalize calls
-- this after its folds.
function Conditions.Normalize(rec)
    local c = rec.c
    for _, list in ipairs(LISTS) do
        local set = c[list]
        if set ~= nil then
            if type(set) ~= "table" then
                c[list] = nil
            else
                for k, v in pairs(set) do
                    if type(k) ~= "string" or v ~= true then set[k] = nil end
                end
                if next(set) == nil then c[list] = nil end
            end
        end
    end
    if c.loadWhenAll ~= nil and c.loadWhenAll ~= true then c.loadWhenAll = nil end
    if c.showWhenAll ~= nil and c.showWhenAll ~= true then c.showWhenAll = nil end
    for k, dflt in pairs(FADE_DEFAULT) do
        if c[k] ~= nil then
            local v = tonumber(c[k])
            if not v then
                c[k] = nil
            else
                if v < 0 then v = 0 elseif v > FADE_MAX[k] then v = FADE_MAX[k] end
                c[k] = (v ~= dflt) and v or nil
            end
        end
    end
    if c.rangeMode ~= nil and c.rangeMode ~= "in" and c.rangeMode ~= "out" then c.rangeMode = nil end
    if c.rangeSpell ~= nil then
        local id = tonumber(c.rangeSpell)
        c.rangeSpell = (id and id > 0) and math.floor(id) or nil
    end
    -- An empty faction set is legal: it means "nowhere", like classes.
    if c.factions ~= nil then
        if type(c.factions) ~= "table" then
            c.factions = nil
        else
            for k, v in pairs(c.factions) do
                if type(k) ~= "string" or v ~= true then c.factions[k] = nil end
            end
        end
    end
end

-- Init, called from the layout engine's Init

function Conditions.Init()
    inCombat = (InCombatLockdown and InCombatLockdown()) == true
        or Plain("combatInit", UnitAffectingCombat and UnitAffectingCombat("player"))
    encounterActive = (IsEncounterInProgress and IsEncounterInProgress()) == true
    Events.On("PLAYER_REGEN_DISABLED", "adcond_base", function()
        inCombat = true
        Conditions.Queue()
    end)
    Events.On("PLAYER_REGEN_ENABLED", "adcond_base", function()
        inCombat = false
        Conditions.Queue()
    end)
    Events.On("ENCOUNTER_START", "adcond_base", function()
        encounterActive = true
        Conditions.Queue()
    end)
    Events.On("ENCOUNTER_END", "adcond_base", function()
        encounterActive = false
        Conditions.Queue()
    end)
    Events.On("PLAYER_ENTERING_WORLD", "adcond_base", function()
        encounterActive = (IsEncounterInProgress and IsEncounterInProgress()) == true
        Conditions.Queue()
    end)
    -- The one way faction changes mid-session (a Pandaren choosing). It is a
    -- "who" condition, so this is a full load pass.
    if EventValid("NEUTRAL_FACTION_SELECT_RESULT") then
        Events.On("NEUTRAL_FACTION_SELECT_RESULT", "adcond_base", function()
            factionTag = nil
            Store.Dirty("load")
        end)
    end
end
