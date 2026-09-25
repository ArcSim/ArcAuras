-- Spell IDs by name, for the aura fields' suggestions: an aura you only see in
-- combat has a secret ID there, the game has no lookup by name, and the spell
-- catalog only holds what you can cast. The first search probes the spell ID
-- range once and keeps the runs that exist; later searches walk only those.

local ADDON, NS = ...

local Names = {}
NS.SpellNames = Names

local BUDGET_MS = 6
Names.floorID = 1500000     -- probe at least this far (Forever has spell 1259705)
Names.emptyTail = 100000    -- then stop after this many empty IDs in a row
Names.minQuery = 3          -- shorter queries match half the game
Names.maxGroups = 200       -- groups collected per query (the panel shows few)

local runs                  -- { s1, e1, s2, e2, ... } once the probe is done
local probe                 -- the probe in progress
local job                   -- the query in progress
local ticking = false

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- One budgeted slice of the probe; true = finished.
local function ProbeStep(deadline)
    local p = probe
    local GetName = C_Spell.GetSpellName
    local id, list = p.nextID, p.list
    while true do
        for _ = 1, 500 do
            if GetName(id) then
                if not p.runStart then p.runStart = id end
                p.lastFound = id
            elseif p.runStart then
                list[#list + 1] = p.runStart
                list[#list + 1] = id - 1
                p.runStart = nil
            end
            id = id + 1
        end
        if id > Names.floorID and id - (p.lastFound or 0) > Names.emptyTail then
            if p.runStart then
                list[#list + 1] = p.runStart
                list[#list + 1] = id - 1
            end
            runs, probe = list, nil
            return true
        end
        if debugprofilestop() >= deadline then
            p.nextID = id
            return false
        end
    end
end

local function Progress()
    if runs then return 100 end
    if not probe then return 0 end
    return math.min(99, math.floor(probe.nextID * 100 / Names.floorID))
end

-- One budgeted slice of the query; true = finished. Each name + icon is one
-- group holding every matching ID (the ranks). Secret names are skipped.
local function QueryStep(deadline)
    local j = job
    local GetName, GetTex = C_Spell.GetSpellName, C_Spell.GetSpellTexture
    local q = j.q
    while j.ri <= #runs do
        local e = runs[j.ri + 1]
        local id = j.id or runs[j.ri]
        while id <= e do
            local nm = GetName(id)
            if nm and not Secret(nm) then
                local low = nm:lower()
                local at = low:find(q, 1, true)
                if at then
                    local tex = GetTex(id)
                    if Secret(tex) then tex = nil end
                    local key = nm .. "\1" .. tostring(tex)
                    local g = j.groups[key]
                    if not g and j.count < Names.maxGroups then
                        g = { name = nm, icon = tex, ids = {},
                            score = (low == q) and 0 or ((at == 1) and 1 or 2) }
                        j.groups[key] = g
                        j.count = j.count + 1
                    end
                    if g then g.ids[#g.ids + 1] = id end
                end
            end
            id = id + 1
            if id % 256 == 0 and debugprofilestop() >= deadline then
                j.id = id
                return false
            end
        end
        j.ri, j.id = j.ri + 2, nil
    end
    return true
end

-- Sort and hand the groups over: whole name, starts-with, contains; then the
-- names you have a spell for; then more ranks; then A-Z. `pick` is the ID a
-- one-ID field should take: the rank you cast, when it is in the group.
local function Finish(j)
    local out = {}
    local known = C_Spell.GetSpellIDForSpellIdentifier
    for _, g in pairs(j.groups) do
        local k = known and known(g.name)
        if Secret(k) then k = nil end
        g.knownID, g.pick = nil, g.ids[1]
        if k then
            for _, id in ipairs(g.ids) do
                if id == k then g.knownID, g.pick = k, k break end
            end
        end
        out[#out + 1] = g
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        local ak, bk = a.knownID ~= nil, b.knownID ~= nil
        if ak ~= bk then return ak end
        if #a.ids ~= #b.ids then return #a.ids > #b.ids end
        if a.name ~= b.name then return a.name < b.name end
        return a.ids[1] < b.ids[1]
    end)
    j.cb("done", out, 100)
end

local Tick
local function Kick()
    if ticking then return end
    ticking = true
    C_Timer.After(0, Tick)
end

Tick = function()
    ticking = false
    if not job then return end
    -- No scanning in combat; look again in a second.
    if InCombatLockdown and InCombatLockdown() then
        ticking = true
        C_Timer.After(1, Tick)
        return
    end
    local deadline = debugprofilestop() + BUDGET_MS
    if not runs then
        if not probe then probe = { nextID = 1, list = {} } end
        if not ProbeStep(deadline) then
            job.cb("loading", nil, Progress())
            Kick()
            return
        end
    end
    if QueryStep(deadline) then
        local j = job
        job = nil
        Finish(j)
        return
    end
    Kick()
end

-- query = the typed text; cb(state, results, pct) with state "loading"
-- (the one-time probe is running, pct done), "short" (fewer than minQuery
-- letters, results empty) or "done" (results sorted). A newer call
-- replaces an unfinished one; the old callback is never called again.
function Names.Search(query, cb)
    local q = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    job = nil
    if #q < Names.minQuery then
        cb("short", {}, Progress())
        return
    end
    job = { q = q, cb = cb, ri = 1, groups = {}, count = 0 }
    Kick()
end

function Names.Cancel() job = nil end

function Names.Ready() return runs ~= nil end
