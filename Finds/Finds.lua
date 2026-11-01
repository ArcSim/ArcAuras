local _, ns = ...

local F = {}
ns.Finds = F

local MAX_FINDS = 2000      -- the developer build raises it (ns.MAX_FINDS)
local MAX_SOURCES = 4
local MAX_REPORTERS = 8

local db
local sorted          -- newest first, rebuilt only after a change
ns.Listen("DBReady", function()
    db = ns.db.finds
    sorted = nil
end)

-- reporters are counted, never named: a salted hash per install
local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end
function F.ReporterKey(name)
    return tostring(Hash((ns.db and ns.db.salt or "") .. (name or "")))
end

local function SameSource(a, b)
    if a.t ~= b.t then return false end
    if a.npc and b.npc then return a.npc == b.npc end
    return a.n == b.n and a.z == b.z
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function F.Get(id)
    return db and db[id]
end

-- one sighting from this copy or from the network; returns "new", "changed", "updated" or nil
function F.Record(info)
    if not db or not info.id then return end
    local now = info.at or ns.Now()
    local e = db[info.id]
    local status
    if not e then
        e = { id = info.id, k = info.kind or "n", q = info.q, il = info.ilvl, rq = info.req, cl = info.cls, sc = info.sub,
            iv = info.inv, ac = info.ac, nm = info.name, fp = info.fp, by = info.by, at = now, v = ns.Now(), s = {}, rp = {},
            pend = info.pend or nil, demo = info.demo or nil }
        db[info.id] = e
        status = "new"
    else
        if info.fp and e.fp and info.fp ~= e.fp then
            e.k = "c"
            e.fp = info.fp
            e.il, e.q, e.rq = info.ilvl or e.il, info.q or e.q, info.req or e.rq
            status = "changed"
        end
        e.fp = e.fp or info.fp
        e.nm = e.nm or info.name
        e.q, e.il, e.rq = e.q or info.q, e.il or info.ilvl, e.rq or info.req
        e.cl, e.sc, e.iv, e.ac = e.cl or info.cls, e.sc or info.sub, e.iv or info.inv, e.ac or info.ac
        if not e.by and info.by then e.by = info.by end
        if now < e.at then e.at = now end
    end
    if info.mine then e.mine = true end
    if info.reporter then
        local key = F.ReporterKey(info.reporter)
        if not e.rp[key] and Count(e.rp) < MAX_REPORTERS then
            e.rp[key] = true
            status = status or "updated"
        end
    end
    -- a find waiting for a second player shows once it has one
    if e.pend and Count(e.rp) >= 2 then
        e.pend = nil
        status = "new"
    end
    local src = info.src
    if src and src.t and src.t ~= "t" then
        local found
        for _, s in ipairs(e.s) do
            if SameSource(s, src) then found = s break end
        end
        if found then
            found.c = (found.c or 1) + (info.fromNet and 0 or 1)
        elseif #e.s < MAX_SOURCES then
            src.c = src.c or 1
            table.insert(e.s, src)
            status = status or "updated"
        end
    end
    -- when another player's find reached this copy, for the Live Feed's count of finds not looked at yet
    if (status == "new" or status == "changed") and not info.mine then e.got = ns.Now() end
    if status then
        e.v = ns.Now()
        sorted = nil
        F.Prune()
        ns.Signal("FindsChanged", e, status, info)
    end
    return status, e
end

function F.Confirmed(e)
    return e and Count(e.rp or {}) >= 2
end

function F.Reporters(e)
    return e and Count(e.rp or {}) or 0
end

-- takes the given reporters off every find; a find from the network left with none of its reporters goes. Returns how
-- many finds went
function F.DropReporters(keys)
    local gone = 0
    for id, e in pairs(db or {}) do
        local hit = false
        for key in pairs(e.rp or {}) do
            if keys[key] then
                e.rp[key] = nil
                hit = true
            end
        end
        if hit and not e.mine and not e.demo and next(e.rp) == nil then
            db[id] = nil
            gone = gone + 1
        end
    end
    sorted = nil
    return gone
end

-- reporters other than this player (its own sightings are keyed by its name, with or without the realm)
function F.OthersReporting(e, me)
    if not e or not e.rp then return 0 end
    local short = type(me) == "string" and me:match("^[^-]+") or me
    local a, b = F.ReporterKey(me), F.ReporterKey(short)
    local n = 0
    for key in pairs(e.rp) do
        if key ~= a and key ~= b then n = n + 1 end
    end
    return n
end

-- the oldest finds nobody confirmed go first, never this player's own
function F.Prune()
    local n, cap = Count(db), ns.MAX_FINDS or MAX_FINDS
    if n <= cap then return end
    local list = {}
    for _, e in pairs(db) do
        if not e.mine and Count(e.rp) < 2 then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.at < b.at end)
    for i = 1, math.min(#list, n - cap) do db[list[i].id] = nil end
    sorted = nil
end

function F.List()
    if not sorted then
        sorted = {}
        for _, e in pairs(db or {}) do
            if not e.pend then sorted[#sorted + 1] = e end
        end
        table.sort(sorted, function(a, b)
            if a.at ~= b.at then return a.at > b.at end
            return a.id > b.id
        end)
    end
    return sorted
end

function F.Count()
    return #F.List()
end

function F.Invalidate()
    sorted = nil
end

-- the finds a share string carries: every find but sample and unconfirmed ones, newest first, at most SHARE_MAX
local SHARE_MAX = 2000
function F.ShareList()
    local out = {}
    for _, e in ipairs(F.List()) do
        if not e.demo and #out < SHARE_MAX then out[#out + 1] = e end
    end
    return out
end

-- the website tells sharers apart by this, never by name: the same per-install salt as the reporter counts
function F.ShareID()
    return F.ReporterKey("share")
end

-- what this copy holds, small enough for one message. Sample finds from /fif demo never leave this copy: they stay out
-- of the summary, the counts and the pages
function F.Summary()
    local count, sum, newest = 0, 0, 0
    for id, e in pairs(db or {}) do
        if not e.demo then
            count = count + 1
            sum = (sum + id * 31 + #e.s * 7 + (e.k == "c" and 3 or 0)) % 2147483647
            if e.v > newest then newest = e.v end
        end
    end
    return count, sum, newest
end

-- how many finds a catch-up page run would carry in all
function F.CountSince(t, after)
    local n = 0
    for id, e in pairs(db or {}) do
        if e.v > t and id > (after or 0) and not e.demo then n = n + 1 end
    end
    return n
end

-- this player's finds announced when no other copy seemed to be listening (Sync marks them uh), at most limit; also
-- how many more are left
function F.Unheard(limit)
    local out, left = {}, 0
    for _, e in pairs(db or {}) do
        if e.uh and not e.demo then
            if #out < limit then out[#out + 1] = e else left = left + 1 end
        end
    end
    return out, left
end

-- one catch-up page: finds changed after a time with an item id above after, by item id (the same order on every
-- copy, so the next page starts where this one ended), at most limit
function F.Since(t, after, limit)
    local out = {}
    for id, e in pairs(db or {}) do
        if e.v > t and id > (after or 0) and not e.demo then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    if limit and #out > limit then
        for i = #out, limit + 1, -1 do out[i] = nil end
    end
    return out
end
