-- AD_DriverRange: how far the target is, for range bars, the Visibility rule "target in range of a spell"
-- and spell icons' range tint (DR.WantSpellRange).
-- Spell checks ride SPELL_RANGE_CHECK_UPDATE; item and interact checks have no event, so a 0.2 s pulse reads
-- them only while a consumer needs one and the target is attackable and alive. A secret answer keeps the last state.
local ADDON, NS = ...
local Events = NS.Events

local DR = {}
NS.DriverRange = DR

DR.KEY = "adrange"
DR.PULSE = 0.2
DR.EVENTS = { "SPELL_RANGE_CHECK_UPDATE", "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
    "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE" }
-- The target's own changes: hostility and death.
DR.UNIT_EVENTS = { "UNIT_FACTION", "UNIT_FLAGS", "UNIT_HEALTH" }

-- owners[key] = { spells = typed IDs, sids = rank IDs, items, interact (sets), gate, fn, sig }
DR.owners = {}
-- How many owners want each check; spells by the rank's own ID.
DR.want = { spell = {}, item = {}, interact = {} }
-- true = in range, false = out of range, nil = no answer.
DR.state = { spell = {}, item = {}, interact = {} }
DR.changed = { spell = {}, item = {}, interact = {} }
-- The spell checks the owners want, held in DR.refs under the engine's own key.
DR.enabled = {}
-- Every want of a spell check, by numeric ID: refs[sid] = { [key] = true }. This file turns on
-- and off only these, so one consumer letting go never switches off another's check.
DR.refs = {}
-- fn(sid) of consumers outside the owner list, after a pass that moved sid's answer.
DR.listeners = {}
DR.resolved = {}
DR.harmful = {}
-- bySpell: UnitCanAttack read secret, so a harmful spell's answer decided it.
DR.target = { attackable = false, dead = false, bySpell = false }

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A secret boolean throws on a test, so it answers no.
local function Yes(v)
    return not IsSecret(v) and v == true
end

local function Put(kind, id, v)
    local s = DR.state[kind]
    if s[id] == v then return end
    s[id] = v
    DR.changed[kind][id] = true
    DR.dirty = true
end

-- Calls each owner whose answers changed, once, after the pass that changed them.
local function Notify()
    if not DR.dirty then return end
    local ch = DR.changed
    DR.changed = { spell = {}, item = {}, interact = {} }
    DR.dirty = false
    local due = {}
    for key, o in pairs(DR.owners) do
        local hit = (ch.gate and o.gate) or false
        if not hit then
            for sid in pairs(ch.spell) do if o.sids[sid] then hit = true break end end
        end
        if not hit then
            for id in pairs(ch.item) do if o.items[id] then hit = true break end end
        end
        if not hit then
            for i in pairs(ch.interact) do if o.interact[i] then hit = true break end end
        end
        if hit and o.fn then due[#due + 1] = key end
    end
    for _, key in ipairs(due) do
        local o = DR.owners[key]
        if o and o.fn then o.fn(key) end
    end
    for _, fn in pairs(DR.listeners) do
        for sid in pairs(ch.spell) do fn(sid) end
    end
end
DR.Notify = Notify

-- Spells and ranks

-- The icons' resolve (Store.TrackedSpellID): on ranked realms the rank the player knows by name,
-- then on either client the replacement whose range answers (Mutilate for Sinister Strike, a
-- talent's new Charge). `follow` / `noOverride` are the owning record's Auto rank and Ignore
-- override (nil: a typed spell's default, follow on ranked realms). Cached per typed ID and
-- switches until SPELLS_CHANGED or a talent event.
function DR.Resolve(id, follow, noOverride)
    if IsSecret(id) then return nil end
    local sid = tonumber(id)
    if not sid or sid <= 0 then return nil end
    sid = math.floor(sid)
    if follow == nil then follow = NS.IsForever == true end
    local mode = (follow and 1 or 0) + (noOverride and 2 or 0)
    local per = DR.resolved[mode]
    if not per then
        per = {}
        DR.resolved[mode] = per
    end
    local r = per[sid]
    if r then return r end
    r = NS.Store.TrackedSpellID(sid, follow, noOverride == true) or sid
    per[sid] = r
    return r
end

-- A typed spell: an ID, or the name of a spell the player knows.
function DR.ParseSpell(text)
    if IsSecret(text) then return nil end
    if type(text) == "number" then return (text > 0) and math.floor(text) or nil end
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$")
    if text == "" then return nil end
    local n = tonumber(text)
    if n then return (n > 0) and math.floor(n) or nil end
    local CS = C_Spell
    local id = CS and CS.GetSpellIDForSpellIdentifier and CS.GetSpellIDForSpellIdentifier(text) -- raw-id: a name typed in a box
    if not IsSecret(id) and type(id) == "number" and id > 0 then return id end
    return nil
end

-- One read: true, false, or nil when no check applies (no target, no range); the second return is a secret answer.
local function ReadSpell(sid)
    local CS = C_Spell
    if not (CS and CS.IsSpellInRange) then return nil, false end
    local v = CS.IsSpellInRange(sid, "target")
    if IsSecret(v) then return nil, true end
    if v == true or v == false then return v, false end
    return nil, false
end

-- The first want of an ID turns its check on and reads it once; the last release turns it off
-- and forgets the answer.
local function Want(key, sid, on)
    local refs = DR.refs[sid]
    local CS = C_Spell
    if on then
        if refs then
            refs[key] = true
            return
        end
        DR.refs[sid] = { [key] = true }
        if CS and CS.EnableSpellRangeCheck then CS.EnableSpellRangeCheck(sid, true) end
        local v, secret = ReadSpell(sid)
        if not secret then Put("spell", sid, v) end
        return
    end
    if not (refs and refs[key]) then return end
    refs[key] = nil
    if next(refs) ~= nil then return end
    DR.refs[sid] = nil
    if CS and CS.EnableSpellRangeCheck then CS.EnableSpellRangeCheck(sid, false) end
    Put("spell", sid, nil)
end

local function Harmful(sid)
    local h = DR.harmful[sid]
    if h == nil then
        local CS = C_Spell
        h = true
        if CS and CS.IsSpellHarmful then h = Yes(CS.IsSpellHarmful(sid)) end
        DR.harmful[sid] = h
    end
    return h
end

-- The target

-- A harmful spell's range check answers only against a hostile target.
local function HostileBySpell()
    for sid in pairs(DR.want.spell) do
        if DR.state.spell[sid] ~= nil and Harmful(sid) then return true end
    end
    return false
end

-- fresh: a new target, whose unreadable death state counts as alive.
function DR.ReadGate(fresh)
    local T = DR.target
    local atk = UnitCanAttack and UnitCanAttack("player", "target")
    local a, bySpell
    if IsSecret(atk) then
        a, bySpell = HostileBySpell(), true
    else
        a, bySpell = atk == true, false
    end
    local dead = T.dead
    if fresh then dead = false end
    local d = UnitIsDeadOrGhost and UnitIsDeadOrGhost("target")
    if not IsSecret(d) then dead = d == true end
    T.bySpell = bySpell
    if a ~= T.attackable or dead ~= T.dead then
        T.attackable, T.dead = a, dead
        DR.changed.gate = true
        DR.dirty = true
    end
end

-- Item and interact checks

local function PulseWanted()
    local T = DR.target
    return (next(DR.want.item) ~= nil or next(DR.want.interact) ~= nil)
        and T.attackable == true and T.dead ~= true
end

-- Only against an attackable target: some clients refuse item checks on a friendly unit in combat.
local function PulseRead()
    if C_Item and C_Item.IsItemInRange then
        for id in pairs(DR.want.item) do
            local v = C_Item.IsItemInRange(id, "target")
            if not IsSecret(v) then
                if v == true or v == false then Put("item", id, v) else Put("item", id, nil) end
            end
        end
    end
    if CheckInteractDistance then
        for i in pairs(DR.want.interact) do
            local v = CheckInteractDistance("target", i)
            if not IsSecret(v) then Put("interact", i, v == true or v == 1) end
        end
    end
end

function DR.Pulse()
    PulseRead()
    Notify()
end

function DR.SyncPulse()
    if PulseWanted() then
        if not DR.ticker then
            DR.ticker = C_Timer.NewTicker(DR.PULSE, DR.Pulse)
            PulseRead()
        end
        return
    end
    if DR.ticker then
        DR.ticker:Cancel()
        DR.ticker = nil
    end
    -- Without an attackable, living target these answers mean nothing.
    for id in pairs(DR.state.item) do Put("item", id, nil) end
    for i in pairs(DR.state.interact) do Put("interact", i, nil) end
end

-- Events

-- Every change of target sends SPELL_RANGE_CHECK_UPDATE too; reading here as well
-- leaves no moment on the old target's answers, whatever order they arrive in.
local function OnTarget()
    for sid in pairs(DR.refs) do
        local v, secret = ReadSpell(sid)
        if not secret then Put("spell", sid, v) end
    end
    DR.ReadGate(true)
    local running = DR.ticker ~= nil
    DR.SyncPulse()
    if running and DR.ticker then PulseRead() end
    Notify()
end

local function OnRange(_, ident, inRange, checksRange)
    if IsSecret(ident) or IsSecret(inRange) or IsSecret(checksRange) then return end
    -- The payload names the spell by its numeric ID.
    local sid = tonumber(ident)
    if not (sid and DR.refs[sid]) then return end
    -- isInRange is a leftover whenever checksRange is false.
    local v = nil
    if checksRange == true then v = inRange == true end
    Put("spell", sid, v)
    if DR.target.bySpell and DR.want.spell[sid] then
        DR.ReadGate()
        DR.SyncPulse()
    end
    Notify()
end

-- A learned rank, or a talent that replaces a spell, is a new spell ID.
local function OnSpells()
    DR.resolved = {}
    DR.harmful = {}
    DR.Sync()
    Notify()
end

local function OnUnit()
    DR.ReadGate()
    DR.SyncPulse()
    Notify()
end

local HANDLERS = {
    SPELL_RANGE_CHECK_UPDATE = OnRange, PLAYER_TARGET_CHANGED = OnTarget,
    SPELLS_CHANGED = OnSpells, PLAYER_ENTERING_WORLD = OnTarget,
    TRAIT_CONFIG_UPDATED = OnSpells, PLAYER_TALENT_UPDATE = OnSpells,
}

local function Valid(ev)
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev)
end

function DR.Arm(on)
    if (DR.armed == true) == on then return end
    DR.armed = on
    for _, ev in ipairs(DR.EVENTS) do
        if not on then
            Events.Off(ev, DR.KEY)
        elseif Valid(ev) then
            Events.On(ev, DR.KEY, HANDLERS[ev])
        end
    end
end

-- Its own frame: the client filters these to the target before any Lua runs.
function DR.ArmUnit(on)
    if (DR.unitArmed == true) == on then return end
    DR.unitArmed = on
    local f = DR.unitFrame
    if on and not f then
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", OnUnit)
        DR.unitFrame = f
    end
    if not f then return end
    if on then
        for _, ev in ipairs(DR.UNIT_EVENTS) do
            if Valid(ev) then f:RegisterUnitEvent(ev, "target") end
        end
    else
        f:UnregisterAllEvents()
    end
end

-- The union of every owner's checks: new spell checks turn on and read once, and
-- a check turns off only when its last owner goes.
function DR.Sync()
    local want = { spell = {}, item = {}, interact = {} }
    local gate = false
    for _, o in pairs(DR.owners) do
        o.sids = {}
        for _, id in ipairs(o.spells) do
            local sid = DR.Resolve(id, o.follow, o.noOverride)
            if sid and not o.sids[sid] then
                o.sids[sid] = true
                want.spell[sid] = (want.spell[sid] or 0) + 1
            end
        end
        for id in pairs(o.items) do want.item[id] = (want.item[id] or 0) + 1 end
        for i in pairs(o.interact) do want.interact[i] = (want.interact[i] or 0) + 1 end
        if o.gate then gate = true end
    end
    DR.want = want
    for sid in pairs(DR.enabled) do
        if not want.spell[sid] then
            DR.enabled[sid] = nil
            Want(DR.KEY, sid, false)
        end
    end
    for sid in pairs(want.spell) do
        if not DR.enabled[sid] then
            DR.enabled[sid] = true
            Want(DR.KEY, sid, true)
        end
    end
    for id in pairs(DR.state.item) do
        if not want.item[id] then Put("item", id, nil) end
    end
    for i in pairs(DR.state.interact) do
        if not want.interact[i] then Put("interact", i, nil) end
    end
    local any = next(DR.owners) ~= nil
    DR.Arm(any or next(DR.refs) ~= nil)
    DR.ArmUnit(any and (gate or next(want.item) ~= nil or next(want.interact) ~= nil))
    DR.ReadGate()
    -- a running pulse reads a newly wanted check now, not a tick later
    local running = DR.ticker ~= nil
    DR.SyncPulse()
    if running and DR.ticker then PulseRead() end
end

-- Consumers

local function SetOf(list)
    local s = {}
    for _, v in ipairs(list or {}) do
        local n = (not IsSecret(v)) and tonumber(v)
        if n then s[n] = true end
    end
    return s
end

local function Sig(need)
    local parts = {}
    for _, k in ipairs({ "spells", "items", "interact" }) do
        local l = {}
        for _, v in ipairs(need[k] or {}) do l[#l + 1] = tostring(v) end
        table.sort(l)
        parts[#parts + 1] = table.concat(l, ",")
    end
    parts[#parts + 1] = need.gate and "g" or ""
    parts[#parts + 1] = (need.follow == nil and "" or (need.follow and "r" or "x")) .. (need.noOverride and "o" or "")
    return table.concat(parts, "|")
end

-- need = { spells = IDs, items = IDs, interact = indexes 1-4, gate = true for the target's
-- attackable and dead state, follow / noOverride = the owning record's Auto rank and Ignore
-- override }. fn(owner) runs when an answer it reads changes. Calling again with the same
-- need only swaps fn.
function DR.Use(owner, need, fn)
    need = need or {}
    local sig = Sig(need)
    local o = DR.owners[owner]
    if o and o.sig == sig then
        o.fn = fn
        return
    end
    local spells = {}
    for _, v in ipairs(need.spells or {}) do spells[#spells + 1] = v end
    DR.owners[owner] = { sig = sig, fn = fn, gate = need.gate == true, spells = spells, sids = {},
        items = SetOf(need.items), interact = SetOf(need.interact),
        follow = need.follow, noOverride = need.noOverride == true }
    DR.Sync()
    Notify()
end

function DR.Drop(owner)
    if not DR.owners[owner] then return end
    DR.owners[owner] = nil
    DR.Sync()
    Notify()
end

-- A typed spell against the target: true, false, or nil (no target, or no check applies).
-- follow / noOverride as its owner asked (DR.Resolve).
function DR.Spell(id, follow, noOverride)
    local sid = DR.Resolve(id, follow, noOverride)
    if not sid then return nil end
    if DR.want.spell[sid] then return DR.state.spell[sid] end
    return (ReadSpell(sid))
end

-- For consumers outside the owner list (the cooldown driver's range tint): key is the
-- caller's own name, sid a numeric spell ID taken as given, with no rank or override resolve.
function DR.WantSpellRange(key, sid, on)
    if IsSecret(sid) or type(sid) ~= "number" or sid <= 0 then return end
    Want(key, sid, on == true)
    DR.Arm(next(DR.owners) ~= nil or next(DR.refs) ~= nil)
    Notify()
end

-- A wanted ID's last plain answer: true out of range, false in range, nil unknown.
function DR.SpellOut(sid)
    local v = DR.state.spell[sid]
    if v == nil then return nil end
    return v == false
end

-- fn(sid) runs after a pass that moved a wanted ID's answer; fn nil removes key's listener.
function DR.OnSpellRange(key, fn)
    DR.listeners[key] = fn
end

function DR.Item(id) return DR.state.item[id] end
function DR.Interact(i) return DR.state.interact[i] end

-- The first band whose checks all hold, or nil. A check is { kind, id, inRange }: a
-- check with no answer holds neither way, and a dead target is in no band. `d` is the
-- owning record's driver, whose switches its spells resolve with (as its owner asked).
function DR.Band(bands, d)
    if DR.target.dead then return nil end
    local follow, noOv
    if type(d) == "table" then follow, noOv = NS.Store.AutoRankOn(d), d.ignoreSpellOverride == true end
    for i, b in ipairs(bands or {}) do
        local ok = #b.checks > 0
        for _, c in ipairs(b.checks) do
            local v
            if c[1] == "spell" then
                v = DR.Spell(c[2], follow, noOv)
            elseif c[1] == "item" then
                v = DR.Item(c[2])
            else
                v = DR.Interact(c[2])
            end
            if v == nil or v ~= c[3] then
                ok = false
                break
            end
        end
        if ok then return i, b end
    end
    return nil
end

function DR.Diag()
    local n, parts = 0, {}
    for _ in pairs(DR.owners) do n = n + 1 end
    for sid in pairs(DR.want.spell) do parts[#parts + 1] = sid .. "=" .. tostring(DR.state.spell[sid]) end
    for id in pairs(DR.want.item) do parts[#parts + 1] = "item " .. id .. "=" .. tostring(DR.state.item[id]) end
    for i in pairs(DR.want.interact) do parts[#parts + 1] = "interact " .. i .. "=" .. tostring(DR.state.interact[i]) end
    local T = DR.target
    return ("owners=%d attackable=%s dead=%s bySpell=%s pulse=%s %s"):format(n, tostring(T.attackable),
        tostring(T.dead), tostring(T.bySpell), tostring(DR.ticker ~= nil), table.concat(parts, " "))
end
