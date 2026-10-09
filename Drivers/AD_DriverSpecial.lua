-- AD_DriverSpecial: the Arc Procs engine (internally "Special"), ProcTracker's trackers as one Arc Auras driver: the registry, the shared event surface, the resets, the reload persistence, the deck bars' proc marks and the attach front door.
-- Tracker files register at load (SP.Register); a record attaches through SP.Attach with a sink that receives every Read() on change; nothing here draws.
-- Every value a tracker compares stays plain in combat: your own casts, SPELL_UPDATE_COOLDOWN spell IDs, by-spell-ID aura presence and hook firings; a secret payload is dropped before any compare.
local ADDON, NS = ...
if NS.IsForever == true then return end

local SP = {}
NS.Special = SP

SP.defs = {}       -- [id] = the tracker's registry entry
SP.order = {}      -- ids in registration order
SP.attached = {}   -- [recId] = { rec, sink, id }
SP.bound = {}      -- [id] = { [recId] = entry }
SP.counts = {}     -- [id] = attached records
SP.started = {}    -- [id] = true while the tracker runs
SP.pending = {}    -- [id] = state saved before a /reload, applied at Start
-- [id] = { last, fracs, ver }: where each proc of a deck landed, for the deck bars
SP.marks = {}

-- the deck readouts a display can ask for, by name
SP.DECK_TOKENS = { "pos", "left", "drawn", "size", "procs", "procsLeft", "max", "chance", "viol" }

-- Talent and gear changes re-run a running tracker's gate; a tracker that names
-- its own syncEvents follows only those, as each ProcTracker deck file did.
SP.TALENT_EVENTS = { "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }
SP.RESET_EVENTS = { "ENCOUNTER_START", "CHALLENGE_MODE_RESET", "CHALLENGE_MODE_START", "WORLD_STATE_TIMER_START" }
-- registered for the player only, so nobody else's casts or auras reach Lua
SP.UNIT_EVENTS = { UNIT_SPELLCAST_SUCCEEDED = true, UNIT_AURA = true, UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true }
-- the hub's own events stay registered for the session
local OWN = { PLAYER_ENTERING_WORLD = true, PLAYER_LOGOUT = true, PLAYER_LOGIN = true }

-- Plain-value helpers

function SP.Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- a spell ID payload as a number, nil when secret or absent
function SP.SpellID(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

function SP.ConfigID()
    local CT = C_ClassTalents
    return CT and CT.GetActiveConfigID and CT.GetActiveConfigID() or nil
end

function SP.NodeInfo(nodeID)
    local cfg = SP.ConfigID()
    if not cfg then return nil end
    return C_Traits and C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(cfg, nodeID) or nil
end

function SP.SpecID()
    local Store = NS.Store
    return Store and Store.CurSpecID and Store.CurSpecID() or nil
end

-- Deck chance maths

-- The odds that k cards drawn from n holding p procs hold none of them, in
-- the p-term form (a handful of factors, exact in floating point).
local function MissChance(n, p, k)
    if p <= 0 then return 1 end
    if k <= 0 then return 1 end
    if n - k < p then return 0 end
    local miss = 1
    for j = 0, p - 1 do
        miss = miss * (n - k - j) / (n - j)
    end
    return miss
end
SP.MissChance = MissChance

-- A spend that runs off the end of a deck keeps drawing into the next,
-- freshly stocked one. Returns a percentage.
function SP.DeckChance(size, maxProcs, pos, procsHit, spend)
    size = size or 1
    maxProcs = maxProcs or 0
    local K = tonumber(spend) or 0
    if K < 1 then K = 1 end
    local N = size - (pos % size)
    local P = maxProcs - (procsHit or 0)
    if P < 0 then P = 0 end
    if K < N then
        return (1 - MissChance(N, P, K)) * 100
    end
    local miss = (P > 0) and 0 or 1
    local over = K - N
    if over > 0 then
        miss = miss * MissChance(size, maxProcs, over)
    end
    return (1 - miss) * 100
end

-- A decimal matters at the low end: a full Doom Winds deck sits at 4.9%.
function SP.FormatChance(pct, decimals)
    if pct >= 99.95 then return "100%" end
    if decimals ~= false and pct < 10 then return string.format("%.1f%%", pct) end
    return string.format("%.0f%%", pct)
end

-- the default colour for "N procs left": green full, red spent, gold between
function SP.ProcCountTint(left, maxProcs)
    if left <= 0 then return 1, 0, 0 end
    if left >= (maxProcs or 1) then return 0, 1, 0 end
    return 1, 0.82, 0
end

-- The event surface: one frame, ordered listeners per event

local frame = CreateFrame("Frame")
SP.frame = frame
local subs = {}    -- [event] = ordered list of { key, fn }
local busy = {}    -- [event] = true while dispatching

local function Valid(e)
    return (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(e)
end

function SP.Listen(event, key, fn)
    local list = subs[event]
    if not list then
        if not Valid(event) then return false end
        list = {}
        subs[event] = list
        if not OWN[event] then
            if SP.UNIT_EVENTS[event] then frame:RegisterUnitEvent(event, "player") else frame:RegisterEvent(event) end
        end
    end
    for i = 1, #list do
        if list[i].key == key then
            list[i].fn = fn
            list[i].dead = nil
            return true
        end
    end
    list[#list + 1] = { key = key, fn = fn }
    return true
end

local function Compact(event)
    local list = subs[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].dead then table.remove(list, i) end
    end
    if #list == 0 then
        subs[event] = nil
        if not OWN[event] then frame:UnregisterEvent(event) end
    end
end

function SP.Unlisten(event, key)
    local list = subs[event]
    if not list then return end
    for i = 1, #list do
        if list[i].key == key then list[i].dead = true end
    end
    if not busy[event] then Compact(event) end
end

function SP.Listens(event, key)
    local list = subs[event]
    if not list then return false end
    for i = 1, #list do
        if list[i].key == key and not list[i].dead then return true end
    end
    return false
end

-- how many listeners an event has, for the diag and the harness
function SP.ListenerCount(event)
    local n = 0
    for _, s in ipairs(subs[event] or {}) do
        if not s.dead then n = n + 1 end
    end
    return n
end

local function Dispatch(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then SP.OnWorld(...) end
    if event == "PLAYER_LOGOUT" then SP.SaveAll() end
    if event == "PLAYER_LOGIN" then SP.OnLogin() end
    local list = subs[event]
    if not list then return end
    busy[event] = true
    for i = 1, #list do
        local s = list[i]
        if s and not s.dead then s.fn(...) end
    end
    busy[event] = nil
    Compact(event)
end

frame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_LOGIN")

-- The registry

function SP.Register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then return nil end
    if SP.defs[def.id] then return SP.defs[def.id] end
    if type(def.Read) ~= "function" then return nil end
    SP.defs[def.id] = def
    SP.order[#SP.order + 1] = def.id
    SP.bound[def.id] = {}
    SP.counts[def.id] = 0
    return def
end

function SP.Get(id) return SP.defs[id] end

function SP.Each(fn)
    for _, id in ipairs(SP.order) do fn(SP.defs[id], id) end
end

function SP.Wanted(id) return SP.started[id] == true end

-- true when any attached record's driver sets the flag
function SP.Flag(id, key)
    for _, e in pairs(SP.bound[id] or {}) do
        local d = e.rec.driver
        if d and d[key] == true then return true end
    end
    return false
end

-- Attach and update

local function Push(e)
    local def = SP.defs[e.id]
    local read = def.Read(e.rec.driver)
    local sink = e.sink
    if type(sink) == "function" then
        sink(e.rec, read)
    elseif type(sink) == "table" and sink.Update then
        sink.Update(e.rec, read)
    end
end

-- ProcTracker re-runs a deck's gate whenever its icon, bar or sound is switched;
-- a tracker with its own syncEvents does too when a record comes or goes while it
-- keeps running, so a driver flag (forceCDM) counts whatever the attach order
local function DemandChanged(id)
    local def = SP.defs[id]
    if def.syncEvents and def.Sync and SP.started[id] then def.Sync() end
end

function SP.Attach(rec, sink)
    if not (rec and rec.id and rec.driver and sink) then return false end
    local id = rec.driver.tracker or rec.driver.special
    if not (id and SP.defs[id]) then return false end
    local e = SP.attached[rec.id]
    if e and e.id ~= id then
        SP.Detach(rec.id)
        e = nil
    end
    if e then
        e.rec, e.sink = rec, sink
        Push(e)
        return true
    end
    e = { rec = rec, sink = sink, id = id }
    SP.attached[rec.id] = e
    SP.bound[id][rec.id] = e
    SP.counts[id] = SP.counts[id] + 1
    if SP.counts[id] == 1 then
        SP.Start(id)
    else
        DemandChanged(id)
        Push(e)
    end
    return true
end

function SP.Detach(recId)
    local e = SP.attached[recId]
    if not e then return end
    SP.attached[recId] = nil
    SP.bound[e.id][recId] = nil
    SP.counts[e.id] = SP.counts[e.id] - 1
    if SP.counts[e.id] <= 0 then
        SP.counts[e.id] = 0
        SP.Stop(e.id)
    else
        DemandChanged(e.id)
    end
end

-- ProcTracker's bar memory, kept for the session whether a bar shows or not: a
-- count going up marks where the deck stood, a count going down starts over.
local function Mark(id, def)
    local r = def.Read(nil)
    local procs = tonumber(r and r.procs) or 0
    local m = SP.marks[id]
    if not m then
        m = { last = 0, fracs = {}, ver = 0 }
        SP.marks[id] = m
    end
    if procs > m.last then
        local size = tonumber(r.size) or 0
        local f = (size > 0) and ((tonumber(r.pos) or 0) / size) or 0
        for _ = m.last + 1, procs do m.fracs[#m.fracs + 1] = f end
        m.ver = m.ver + 1
    elseif procs < m.last then
        m.fracs = {}
        m.ver = m.ver + 1
    end
    m.last = procs
end

-- a deck restored across a /reload keeps its count; where those procs landed is unknown
local function MarkRestored(id, def)
    if def.procs == nil then return end
    local r = def.Read(nil)
    local m = SP.marks[id] or { ver = 0 }
    m.last, m.fracs, m.ver = tonumber(r and r.procs) or 0, {}, m.ver + 1
    SP.marks[id] = m
end

function SP.Update(id)
    local def = SP.defs[id]
    if def and def.procs ~= nil then Mark(id, def) end
    local list = SP.bound[id]
    if not list then return end
    for _, e in pairs(list) do Push(e) end
end

-- a proc edge, for the sound a display may play
function SP.Proc(id)
    local list = SP.bound[id]
    if not list then return end
    for _, e in pairs(list) do
        local s = e.sink
        if type(s) == "table" and s.Proc then s.Proc(e.rec) end
    end
end

-- Start, stop and the gates

local sharedArmed = false

-- a tracker with its own syncEvents follows those; any other, every talent event
function SP.SyncsOn(def, event)
    if def.syncEvents then return def.syncEvents[event] == true end
    return event ~= "PLAYER_LOGIN"
end

function SP.SyncAll(event)
    for _, id in ipairs(SP.order) do
        local def = SP.defs[id]
        if SP.started[id] and def.Sync and SP.SyncsOn(def, event) then def.Sync() end
    end
end

local function ArmShared(on)
    if on == sharedArmed then return end
    sharedArmed = on
    for _, e in ipairs(SP.TALENT_EVENTS) do
        if on then SP.Listen(e, "sp_sync", function() SP.SyncAll(e) end) else SP.Unlisten(e, "sp_sync") end
    end
end

-- the talent API answers shortly after login, so the gates run again half a second on
function SP.OnLogin()
    C_Timer.After(0.5, function() SP.SyncAll("PLAYER_LOGIN") end)
end

function SP.Start(id)
    local def = SP.defs[id]
    if not def or SP.started[id] then return end
    SP.started[id] = true
    ArmShared(true)
    local saved = SP.pending[id]
    if saved then
        SP.pending[id] = nil
        if def.Load then
            def.Load(saved)
            MarkRestored(id, def)
        end
    end
    if def.Start then def.Start() end
    if def.Sync then def.Sync() end
    SP.Update(id)
end

function SP.Stop(id)
    local def = SP.defs[id]
    if not (def and SP.started[id]) then return end
    SP.started[id] = nil
    if def.Stop then def.Stop() end
    if not next(SP.started) then ArmShared(false) end
end

-- Resets

-- nil reads as on: a key started without the reset chain confirming runs
-- the whole dungeon desynced
function SP.SafeMPlusReset()
    local Store = NS.Store
    local v = Store and Store.GetSetting and Store.GetSetting("specialSafeMPlusReset")
    if v == nil then return true end
    return v == true
end

function SP.SetSafeMPlusReset(on)
    local Store = NS.Store
    if Store and Store.SetSetting then Store.SetSetting("specialSafeMPlusReset", on and true or false) end
end

-- A reset also drops any state still waiting from a /reload, or a tracker that
-- starts later would bring back the counts the reset cleared.
function SP.ResetAll(reason)
    SP.pending = {}
    local MSW = NS.SpecialMSW
    if MSW then MSW.Reset() end
    for _, id in ipairs(SP.order) do
        local def = SP.defs[id]
        if def.Reset then def.Reset() end
    end
    if MSW then MSW.InitFromLive() end
    SP.lastReset = reason
end

function SP.Reset(id)
    SP.pending[id] = nil
    local def = SP.defs[id]
    if def and def.Reset then def.Reset() end
end

local cmResetArmed, cmResetStartTS, cmResetInstID = false, nil, nil
local lastEnterWorldTS = -10

function SP.OnResetEvent(event, a1)
    if event == "ENCOUNTER_START" then
        -- a raid pull resets the server's deck; a Mythic+ boss does not, and
        -- keys are instance type "party"
        local inInst, instType = IsInInstance()
        if inInst and instType == "raid" then SP.ResetAll("raid") end
        return
    end
    if event == "CHALLENGE_MODE_START" then
        if SP.SafeMPlusReset() then SP.ResetAll("keystart") end
        return
    end
    if event == "CHALLENGE_MODE_RESET" then
        cmResetArmed = true
        cmResetStartTS = GetTime()
        cmResetInstID = select(8, GetInstanceInfo())
        return
    end
    if event == "WORLD_STATE_TIMER_START" and cmResetArmed then
        -- only timer 1 consumes the arm; the arm expires on its own past 9 s
        if a1 ~= 1 then
            if (GetTime() - (cmResetStartTS or 0)) > 9 then
                cmResetArmed, cmResetStartTS, cmResetInstID = false, nil, nil
            end
            return
        end
        local inInst, instType = IsInInstance()
        local diff = select(3, GetInstanceInfo())
        local instID = select(8, GetInstanceInfo())
        -- a load-sync re-fire right after entering the world is a skipper
        -- zoning back in, whose deck the server kept
        if inInst and instType == "party" and diff == 8 and instID == cmResetInstID
        and (GetTime() - (cmResetStartTS or 0)) <= 9
        and (GetTime() - lastEnterWorldTS) > 2.5 then
            SP.ResetAll("gate")
        end
        cmResetArmed, cmResetStartTS, cmResetInstID = false, nil, nil
        return
    end
end

-- armed from load, as ProcTracker's reset frame is: a tracker that starts later,
-- or a state waiting for its record, still takes every reset
for _, e in ipairs(SP.RESET_EVENTS) do
    SP.Listen(e, "sp_reset", function(...) SP.OnResetEvent(e, ...) end)
end

-- Persistence across a /reload only: a fresh login drops the saved state,
-- since a relog resets the server's decks

local function SavedKey()
    local Store = NS.Store
    local key = Store and Store.CharKey and Store.CharKey()
    if type(key) ~= "string" or key == "?" or key:sub(-2) == "-?" then return nil end
    return key
end

function SP.SaveAll()
    local db = ArcAurasDB
    local key = SavedKey()
    if type(db) ~= "table" or not key then return end
    local t, any = {}, false
    for _, id in ipairs(SP.order) do
        local def = SP.defs[id]
        local s = def.Save and def.Save()
        if s ~= nil then
            t[id] = s
            any = true
        end
    end
    for id, s in pairs(SP.pending) do
        if t[id] == nil then
            t[id] = s
            any = true
        end
    end
    db.special = db.special or {}
    db.special[key] = any and t or nil
    if not next(db.special) then db.special = nil end
end

function SP.TakeSaved()
    local db = ArcAurasDB
    local key = SavedKey()
    if type(db) ~= "table" or not key or type(db.special) ~= "table" then return end
    local t = db.special[key]
    db.special[key] = nil
    if not next(db.special) then db.special = nil end
    if type(t) ~= "table" then return end
    for id, s in pairs(t) do SP.pending[id] = s end
end

function SP.DropSaved()
    SP.pending = {}
    local db = ArcAurasDB
    local key = SavedKey()
    if type(db) ~= "table" or not key or type(db.special) ~= "table" then return end
    db.special[key] = nil
    if not next(db.special) then db.special = nil end
end

function SP.OnWorld(isLogin, isReload)
    lastEnterWorldTS = GetTime()
    local fresh = isLogin and not isReload
    if fresh then
        SP.DropSaved()
    elseif isReload then
        SP.TakeSaved()
    end
    for _, id in ipairs(SP.order) do
        local def = SP.defs[id]
        if SP.started[id] then
            local saved = SP.pending[id]
            if saved then
                SP.pending[id] = nil
                if def.Load then
                    def.Load(saved)
                    MarkRestored(id, def)
                end
            end
            if def.Sync then def.Sync() end
        end
    end
    if fresh then
        for _, id in ipairs(SP.order) do
            local def = SP.defs[id]
            if def.Reset then def.Reset() end
        end
    end
    for _, id in ipairs(SP.order) do
        if SP.started[id] then SP.Update(id) end
    end
end

-- Diagnostics, as lines for a caller to show

function SP.Diag()
    local out = {}
    for _, id in ipairs(SP.order) do
        local def = SP.defs[id]
        local r = def.Read(nil)
        local line = string.format("%s: %s, %d attached, %s, pos %s / %s, procs %s / %s",
            id, SP.started[id] and "running" or "idle", SP.counts[id] or 0,
            def.Status and def.Status() or "", tostring(r.pos), tostring(r.size),
            tostring(r.procs), tostring(r.max))
        if r.viol then line = line .. ", violations " .. tostring(r.viol) end
        if r.active ~= nil then line = line .. (r.active and ", cooling down" or ", ready") end
        out[#out + 1] = line
    end
    out[#out + 1] = "Safe Mythic+ Reset " .. (SP.SafeMPlusReset() and "on" or "off")
        .. (SP.lastReset and (", last reset: " .. SP.lastReset) or "")
    return out
end
