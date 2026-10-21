-- AD_Perf: an opt-in profiler (/arcperf) showing what this addon spends per event handler and per module function, beside the game's own totals.
-- Off, nothing is wrapped and the dispatcher pays one flag test; on, Core\AD_Events.lua times each handler and every runtime module's functions are wrapped.
-- It only does arithmetic on debugprofilestop(); wrapped calls pass their arguments and returns through untouched, secrets included.
-- The game's own per-tick count for this addon runs beside ours, so whatever the wrappers cannot see shows up as "not traced".
local ADDON, NS = ...

local Perf = { on = false, stats = {}, keys = {}, wrapped = {}, since = 0, depth = 0, child = {}, meta = {} }
NS.Perf = Perf

-- Every module table on the namespace is wrapped, and its sub-module tables
-- one level down, except these: the options window and its pages, the theme,
-- the store's tiny accessors (their cost folds into the callers' own time),
-- the dispatcher (it times its own handlers), one-shot importers and data.
Perf.SKIP = { Perf = true, Events = true, Store = true, Schema = true, AT = true, Options = true,
    Changelog = true, Spotlight = true, NewLayout = true, LayoutPreview = true, LayoutFollow = true,
    IconScreen = true, ItemSets = true, FramePicker = true, CDMMirrorOptions = true,
    ImportArcUI = true, Migrate = true, MigratePT = true, SpellCatalog = true, TalentCatalog = true }
Perf.TOP = 12
Perf.TOP_AFTER = 6
Perf.TOP_GAME = 5
Perf.TOP_DEEP = 15
Perf.TOP_OTHERS = 10
-- seconds between live refreshes of the window while recording: rewriting the
-- report's long text costs time the recording would otherwise count as ours
Perf.REFRESH = 5
-- Record next fight keeps going this long after combat ends: the settle work
-- that waited for combat runs then.
Perf.TAIL = 2
-- Where the timed calls go: the fight's table, then the tail's.
Perf.after = {}
Perf.cur = Perf.stats

-- WoW's Lua has no table.pack or table.unpack; select("#") keeps a trailing
-- nil return, so the open probe's marked calls hand back exactly what they got.
local unpack = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local clock = debugprofilestop

local function Stat(key)
    local t = Perf.cur
    local s = t[key]
    if not s then
        s = { ms = 0, self = 0, n = 0, peak = 0 }
        t[key] = s
    end
    return s
end

-- Per recording table: the game's count for this addon summed over the ticks,
-- and the profiler's own bookkeeping, which the game counts as ours too.
local function Meta(t)
    local m = Perf.meta[t]
    if not m then
        m = { game = 0, ticks = 0, over = 0 }
        Perf.meta[t] = m
    end
    return m
end

-- One timed call. Nested timed calls subtract from the caller's self time, so
-- a module function's own work is told apart from what it calls. The
-- bookkeeping around it leaves the caller's own time too and is reported as
-- the profiler's cost. The returns pass through as a vararg: a table per call
-- would be garbage, and collecting it lands on the addon's time unseen.
local function Done(d, key, enter, t0, ...)
    local total = clock() - t0
    local own = total - Perf.child[d]
    Perf.depth = d - 1
    local s = Stat(key)
    s.ms, s.self, s.n = s.ms + total, s.self + own, s.n + 1
    if total > s.peak then s.peak = total end
    local full = clock() - enter
    if d > 1 then Perf.child[d - 1] = Perf.child[d - 1] + full end
    local m = Meta(Perf.cur)
    m.over = m.over + full - total
    return ...
end

function Perf.Call(key, fn, ...)
    local enter = clock()
    local d = Perf.depth + 1
    Perf.depth = d
    Perf.child[d] = 0
    return Done(d, key, enter, clock(), fn(...))
end

-- A handler at the top of a stack: a call that errored out never unwound, so
-- every dispatch starts from zero.
function Perf.Top(key, fn, ...)
    Perf.depth = 0
    return Perf.Call(key, fn, ...)
end

-- The dispatcher's label for an event or message and a subscriber key, built
-- once per pair.
function Perf.Key(kind, name, key)
    local byName = Perf.keys[name]
    if not byName then
        byName = {}
        Perf.keys[name] = byName
    end
    local k = byName[key]
    if not k then
        k = kind .. " " .. tostring(name) .. " > " .. tostring(key)
        byName[key] = k
    end
    return k
end

-- A wrapper someone kept a reference to stays cheap after Off.
local function Wrapper(key, fn)
    return function(...)
        if Perf.on then return Perf.Call(key, fn, ...) end
        return fn(...)
    end
end

-- Timers and hooks run outside the dispatcher and the module tables. Each
-- runtime file reaches them through these stand-ins
-- (local C_Timer = NS.Perf.Timers("Bars")): off, a timer is the game's own
-- and a hook costs one extra call; recording, each is timed under the line
-- that set it, or its file and the hooked method.
local ADDON_PAT = ADDON:gsub("%p", "%%%0")

-- The first line of ours on the stack that is not this file, as "file:line".
local function Caller()
    local s = debugstack and debugstack(2, 6, 0)
    -- secret across a secure frame: no string work on it
    if type(s) ~= "string" or (issecretvalue and issecretvalue(s)) then return nil end
    for file, line in s:gmatch("[/\\]" .. ADDON_PAT .. "[/\\]([^\"%]:\n]-%.lua)[\"%]]*:(%d+)") do
        file = file:gsub("\\", "/")
        if file ~= "Core/AD_Perf.lua" then return file .. ":" .. line end
    end
    return nil
end

function Perf.Timers(file)
    local T = {}
    function T.After(secs, fn)
        if Perf.on then
            local t0 = clock()
            fn = Wrapper("timer " .. (Caller() or file), fn)
            local m = Meta(Perf.cur)
            m.over = m.over + clock() - t0
        end
        return C_Timer.After(secs, fn)
    end
    -- a ticker outlives any one recording: timed whenever one runs
    function T.NewTicker(secs, fn, n)
        return C_Timer.NewTicker(secs, Wrapper("ticker " .. (Caller() or file), fn), n)
    end
    return T
end

function Perf.Hooks(file)
    return function(a, b, c)
        if c == nil and type(b) == "function" then
            return hooksecurefunc(a, Wrapper("hook " .. file .. " " .. tostring(a), b))
        end
        return hooksecurefunc(a, b, Wrapper("hook " .. file .. " " .. tostring(b), c))
    end
end

-- Frames built on the game's aura buttons take the button's lock once the
-- engine has it (in combat and instances): from then on every call into one
-- throws, though IsForbidden still says false. Built through this stand-in,
-- such a frame is marked `_adHanded` from its parent's line while the parent
-- is still open (a frame can only be built on an open one), and the sweep
-- reads the mark (a plain field) before it calls anything.
local function UnderEngine(p)
    while p and p ~= UIParent do
        if p._adHanded then return true end
        if p.GetObjectType and p:GetObjectType() == "AuraContainer" then return true end
        p = p.GetParent and p:GetParent()
    end
    return false
end
Perf.UnderEngine = UnderEngine

function Perf.CreateFrame(kind, name, parent, ...)
    local fr = CreateFrame(kind, name, parent, ...)
    if kind == "AuraContainer" or (parent and UnderEngine(parent)) then fr._adHanded = true end
    return fr
end

-- Every frame a file makes, counted for the session (frames are never freed,
-- so a count that keeps climbing between reports is a leak); the game's aura
-- containers and the frames built on them apart.
Perf.madeBy, Perf.made, Perf.madeHanded, Perf.containers = {}, 0, 0, 0
function Perf.Frames(file)
    return function(kind, name, parent, ...)
        local fr = Perf.CreateFrame(kind, name, parent, ...)
        Perf.made = Perf.made + 1
        Perf.madeBy[file] = (Perf.madeBy[file] or 0) + 1
        if kind == "AuraContainer" then Perf.containers = Perf.containers + 1 end
        if fr._adHanded then Perf.madeHanded = Perf.madeHanded + 1 end
        return fr
    end
end

-- The session's frames as one line: the total, the files that made the most.
function Perf.FramesLine()
    if Perf.made == 0 then return nil end
    local list = {}
    for file, n in pairs(Perf.madeBy) do list[#list + 1] = { file, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local top = {}
    for i = 1, math.min(6, #list) do top[#top + 1] = ("%s %d"):format(list[i][1], list[i][2]) end
    local line = ("Frames we made this session: %d (%s); %d on the game's aura buttons, %d aura containers."):format(
        Perf.made, table.concat(top, ", "), Perf.madeHanded, Perf.containers)
    -- target and focus slots switched off while their side shows them nothing
    local DA = NS.DriverAura
    if DA and DA.SideCensus then
        local n, off = DA.SideCensus()
        line = line .. (" %d target or focus aura slots, %d of them off for the unit's side."):format(n, off)
    end
    return line
end

-- Tables that are not ours to touch: every global table (a Blizzard mixin or
-- another addon's table must never run our wrappers) and every shared library.
local function Foreign()
    local set = {}
    for _, v in pairs(_G) do
        if type(v) == "table" then set[v] = true end
    end
    if LibStub and type(LibStub.libs) == "table" then
        for _, lib in pairs(LibStub.libs) do set[lib] = true end
    end
    return set
end

-- A plain table of functions: no metatable (objects keep their methods there)
-- and not a widget.
local function IsModule(t, foreign)
    return type(t) == "table" and not foreign[t] and getmetatable(t) == nil and rawget(t, 0) == nil
end

-- The module tables, then their sub-module tables one level down (capitalised
-- keys: Bars.ManaRegen, Bars.Spark), each once, as { t = table, name = label }.
function Perf.ModuleTables(skip)
    local foreign, seen, list = Foreign(), { [NS] = true }, {}
    for name in pairs(skip or {}) do
        if type(NS[name]) == "table" then seen[NS[name]] = true end
    end
    for name, t in pairs(NS) do
        if type(name) == "string" and not (skip and skip[name]) and IsModule(t, foreign) and not seen[t] then
            seen[t] = true
            list[#list + 1] = { t = t, name = name }
        end
    end
    for i = 1, #list do
        local m = list[i]
        for k, v in pairs(m.t) do
            if type(k) == "string" and k:find("^%u") and IsModule(v, foreign) and not seen[v] then
                seen[v] = true
                list[#list + 1] = { t = v, name = m.name .. "." .. k }
            end
        end
    end
    return list
end

function Perf.WrapModules(skip)
    local list = Perf.ModuleTables(skip or Perf.SKIP)
    for _, m in ipairs(list) do
        for k, v in pairs(m.t) do
            if type(v) == "function" then
                local w = Wrapper(m.name .. "." .. tostring(k), v)
                Perf.wrapped[#Perf.wrapped + 1] = { t = m.t, k = k, fn = v, w = w }
                m.t[k] = w
            end
        end
    end
    Perf.moduleCount = #list
end

-- Each wrapped field gets its own function back, unless something replaced it
-- while profiling ran.
function Perf.Unwrap()
    for i = #Perf.wrapped, 1, -1 do
        local w = Perf.wrapped[i]
        if w.t[w.k] == w.w then w.t[w.k] = w.fn end
        Perf.wrapped[i] = nil
    end
end

function Perf.Reset()
    Perf.hudPeak = nil
    wipe(Perf.stats)
    wipe(Perf.after)
    wipe(Perf.meta)
    Perf.cur = Perf.stats
    Perf.since = GetTime()
    Perf.endedAt = nil
    Perf.measureLines = nil
end

function Perf.On(skip)
    -- an M+ run being measured is never reset by another mode
    if Perf.on or Perf.runArmed or Perf.runMeasuring then return end
    Perf.Reset()
    Perf.WrapModules(skip)
    if not Perf.swept then Perf.SweepAll() end
    Perf.on = true
    -- the game's count for this frame holds the setup above, not the addon's work
    Perf.skipSample = true
    Perf.Sampling(true)
end

function Perf.Off()
    if not Perf.on then return end
    Perf.on = false
    Perf.Sampling(false)
    Perf.Unwrap()
    Perf.Unswap()
end

-- The game's own numbers for an addon: recent average, session average and the
-- peak, in ms per frame; nil where the profiler is off or the addon is absent.
function Perf.Game(name)
    local P, M = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if not (P and P.GetAddOnMetric and M) then return nil end
    if P.IsEnabled and not P.IsEnabled() then return nil end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded(name) then return nil end
    return P.GetAddOnMetric(name, M.RecentAverageTime), P.GetAddOnMetric(name, M.SessionAverageTime),
        P.GetAddOnMetric(name, M.PeakTime)
end

-- The rows for the report: every key by self time, most first.
function Perf.Rows(t)
    local rows = {}
    for key, s in pairs(t or Perf.stats) do rows[#rows + 1] = { key = key, s = s } end
    table.sort(rows, function(a, b) return a.s.self > b.s.self end)
    return rows
end

-- The addon list's own percentages (Blizzard_AddOnList AddonList.lua
-- GetAddonMetricPercent / GetOverallMetric / FormatProfilerPercent): an addon's
-- share is its time over the game's time with every other addon taken out;
-- "all addons" is their time over the game's.
function Perf.PctText(pct)
    if not pct then return "-" end
    if pct >= 1 then return ("%.0f%%"):format(pct) end
    if pct >= 0.1 then return ("%.1f%%"):format(pct) end
    if pct >= 0.01 then return ("%.2f%%"):format(pct) end
    return "0%"
end

local function Profiler()
    local P, M = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if not (P and M and P.GetAddOnMetric and P.GetOverallMetric and P.GetApplicationMetric) then return nil end
    if P.IsEnabled and not P.IsEnabled() then return nil end
    return P, M
end

-- The game's own count for this addon, added up tick by tick while recording.
local function Sample()
    local t0 = clock()
    local m = Meta(Perf.cur)
    local P, M = Profiler()
    if Perf.skipSample then
        Perf.skipSample = false
    elseif P and M.LastTime then
        local last = P.GetAddOnMetric(ADDON, M.LastTime)
        if type(last) == "number" then
            m.game, m.ticks = m.game + last, m.ticks + 1
            m.secMs = (m.secMs or 0) + last
        end
        -- once a second: the addon list's own figure (its highest, its average)
        -- and the second's log, the game's count and that figure, kept as it goes
        local now = GetTime()
        if not m.pctAt or now - m.pctAt >= 1 then
            local first = m.pctAt == nil
            m.pctAt = now
            local pct = Perf.AddonPct(ADDON, M.RecentAverageTime)
            if pct then
                m.pctN, m.pctSum = (m.pctN or 0) + 1, (m.pctSum or 0) + pct
                if not m.pctMax or pct > m.pctMax then m.pctMax, m.pctMaxAt = pct, now - (Perf.since or now) end
            end
            if not first then
                m.secLog = m.secLog or {}
                local n = #m.secLog
                m.secLog[n + 1] = math.floor((m.secMs or 0) * 10 + 0.5) / 10
                m.secLog[n + 2] = pct and (math.floor(pct * 100 + 0.5) / 100) or -1
                m.secLog[n + 3] = (InCombatLockdown and InCombatLockdown()) and 1 or 0
            end
            m.secMs = 0
        end
    end
    if Perf.on then Perf.SweepStep() end
    m.over = m.over + clock() - t0
end

function Perf.Sampling(on)
    if on and not Perf.sampler then Perf.sampler = CreateFrame("Frame") end
    if Perf.sampler then Perf.sampler:SetScript("OnUpdate", on and Sample or nil) end
end

function Perf.AddonPct(name, metric)
    local P = Profiler()
    if not P then return nil end
    local app, all, one = P.GetApplicationMetric(metric), P.GetOverallMetric(metric), P.GetAddOnMetric(name, metric)
    if not (app and all and one) then return nil end
    local rel = app - all + one
    if rel <= 0 then return nil end
    return one / rel * 100
end

function Perf.OverallPct(metric)
    local P = Profiler()
    if not P then return nil end
    local app = P.GetApplicationMetric(metric)
    if not (app and app > 0) then return nil end
    return (P.GetOverallMetric(metric) or 0) / app * 100
end

local function GameLines(out)
    local P, M = Profiler()
    if not P then
        out[#out + 1] = "The game's profiler is off, so there are no game numbers."
        return
    end
    out[#out + 1] = ("Game CPU, as the addon list shows it: all addons average %s, peak %s"):format(
        Perf.PctText(Perf.OverallPct(M.SessionAverageTime)), Perf.PctText(Perf.OverallPct(M.PeakTime)))
    out[#out + 1] = ("  %s: recent %s, session %s, peak %s"):format(ADDON,
        Perf.PctText(Perf.AddonPct(ADDON, M.RecentAverageTime)),
        Perf.PctText(Perf.AddonPct(ADDON, M.SessionAverageTime)),
        Perf.PctText(Perf.AddonPct(ADDON, M.PeakTime)))
    if P.GetTopKAddOnsForMetric then
        local top, parts = P.GetTopKAddOnsForMetric(M.RecentAverageTime, Perf.TOP_GAME), {}
        for _, r in ipairs(top or {}) do
            parts[#parts + 1] = ("(%s) %s"):format(Perf.PctText(Perf.AddonPct(r.addOnName, M.RecentAverageTime)),
                tostring(r.addOnName))
        end
        if #parts > 0 then out[#out + 1] = "  Top now: " .. table.concat(parts, ", ") end
    end
end

-- One table's rows: own work, share of this addon's work, calls, peak.
local function RowLines(out, t, secs, top)
    local total = 0
    local rows = Perf.Rows(t)
    for _, r in ipairs(rows) do total = total + r.s.self end
    for i = 1, math.min(top, #rows) do
        local s = rows[i].s
        out[#out + 1] = ("%2d. %s: own %.2f ms (%s of ours), %d calls (%.1f/s), peak %.3f ms"):format(
            i, rows[i].key, s.self, Perf.PctText(total > 0 and s.self / total * 100 or 0), s.n, s.n / secs, s.peak)
    end
    return total
end

-- The addon list's figure for this addon as it moved through a recording
-- (Sample reads it once a second); nil before a whole second.
function Perf.ListLine(m)
    if not (m and m.pctN and m.pctN > 0) then return nil end
    return ("The addon list's figure for %s through it: highest %s (%.0f s in), average %s."):format(ADDON,
        Perf.PctText(m.pctMax), m.pctMaxAt or 0, Perf.PctText(m.pctSum / m.pctN))
end

-- The second-by-second log (Sample): "<second>s <ms of ours> <addon list %>",
-- " c" on a second spent in combat, for the saved report; nil before a whole second.
function Perf.SecondsText(m)
    local log = m and m.secLog
    if not (log and #log > 0) then return nil end
    local out = {}
    for i = 1, #log, 3 do
        local pct = log[i + 1]
        out[#out + 1] = ("%ds %.1f %s%s"):format((i + 2) / 3, log[i], pct >= 0 and ("%.2f"):format(pct) or "-",
            log[i + 2] == 1 and " c" or "")
    end
    return table.concat(out, ", ")
end

-- The log's seconds in and out of combat: what each costs a second.
function Perf.CombatLine(m)
    local log = m and m.secLog
    if not (log and #log > 0) then return nil end
    local inMs, inN, outMs, outN = 0, 0, 0, 0
    for i = 1, #log, 3 do
        if log[i + 2] == 1 then inMs, inN = inMs + log[i], inN + 1 else outMs, outN = outMs + log[i], outN + 1 end
    end
    return ("In combat %.1f ms a second over %d s; out of combat %.1f ms a second over %d s."):format(
        inN > 0 and inMs / inN or 0, inN, outN > 0 and outMs / outN or 0, outN)
end

-- The game's count beside ours for one recording table: what the wrappers
-- cannot see is the rest.
local function CoverageLines(out, t, secs)
    local m = Perf.meta[t]
    if not (m and m.ticks > 0) then return end
    local traced = 0
    for _, s in pairs(t) do traced = traced + s.self end
    local rest = math.max(m.game - traced - m.over, 0)
    out[#out + 1] = ("The game counted %.2f ms (%.3f ms per second): traced %.2f ms, the profiler's own work %.2f ms, not traced %.2f ms (%s)."):format(
        m.game, m.game / secs, traced, m.over, rest, Perf.PctText(m.game > 0 and rest / m.game * 100 or 0))
    out[#out + 1] = Perf.ListLine(m)
    if rest > traced and rest > 1 then
        out[#out + 1] = "Not traced: our hooks on the game's frame scripts, the event dispatch, garbage collection. /arcperf deep lists frames by file."
    end
end

-- What kind of entry point the traced time came in by.
Perf.KINDS = {
    { "event", "event handlers" }, { "message", "event handlers" }, { "next frame", "event handlers" },
    { "script", "frame scripts" }, { "hook", "hooks" }, { "timer", "timers" }, { "ticker", "timers" },
}
local KIND_ORDER = { "event handlers", "functions", "frame scripts", "hooks", "timers" }

local function KindLines(out, t, secs)
    local sum, calls = {}, 0
    for key, s in pairs(t) do
        calls = calls + s.n
        local kind = "functions"
        for _, k in ipairs(Perf.KINDS) do
            if key:sub(1, #k[1] + 1) == k[1] .. " " then
                kind = k[2]
                break
            end
        end
        sum[kind] = (sum[kind] or 0) + s.self
    end
    local parts = {}
    for _, kind in ipairs(KIND_ORDER) do
        if sum[kind] then parts[#parts + 1] = ("%s %.2f ms"):format(kind, sum[kind]) end
    end
    if #parts > 0 then out[#out + 1] = "Traced by kind: " .. table.concat(parts, ", ") .. "." end
    -- each timed call pays bookkeeping, part of it outside what is measured
    out[#out + 1] = ("Timed calls: %d, %.0f per second."):format(calls, calls / secs)
end

-- Deep view: the game's script profiler (the scriptProfile setting) times every
-- frame's scripts and every function. Ours are told by where each frame was
-- made and by the namespace walk; nothing is wrapped.
-- The path inside this addon's folder, or nil for anyone else's frame (a
-- folder whose name only starts with ours included).
local function Site(loc)
    if type(loc) ~= "string" or (issecretvalue and issecretvalue(loc)) then return nil end
    local _, e = loc:find("[/\\]" .. ADDON_PAT .. "[/\\]")
    if not e then return nil end
    return (loc:sub(e + 1):gsub("\\", "/"))
end

-- Frame scripts: our frames' per-frame and event scripts. While recording each
-- is swapped for a timed one, frame by frame, ours told by where the frame was
-- made. Only these two: setting a script drops any hook on it, and nothing
-- hooks them on our frames. The dispatcher times its own handlers and the
-- profiler's frames are its own work, so theirs stay as they are.
Perf.SCRIPTS = { "OnUpdate", "OnEvent" }
Perf.SCRIPT_SKIP = { ["Core/AD_Events.lua"] = true, ["Core/AD_Perf.lua"] = true }
-- frames looked at per frame while recording: new frames and scripts set
-- since are picked up as the walk goes round
Perf.SWEEP_STEP = 50
Perf.siteOf = {}    -- [frame] = "file:line" where it was made, or false
Perf.swapped = {}   -- [frame] = { [script] = { fn = its own, w = timed } }
Perf.ours, Perf.timedScripts = 0, 0
local isTimed = {}  -- [timed script] = true
local timedFor = {} -- [key] = { [fn] = timed script }

local function TimedScript(key, fn)
    local byFn = timedFor[key]
    if not byFn then
        byFn = {}
        timedFor[key] = byFn
    end
    local w = byFn[fn]
    if not w then
        w = Wrapper(key, fn)
        byFn[fn] = w
        isTimed[w] = true
    end
    return w
end

local function SweepFrame(f)
    -- a frame on the game's aura buttons (Perf.CreateFrame) is never called into
    if f._adHanded then return end
    -- asked on every visit: the game's own buttons turn forbidden once the
    -- secure aura container takes them
    if f.IsForbidden and f:IsForbidden() then return end
    local site = Perf.siteOf[f]
    if site == nil then
        site = false
        if f.GetSourceLocation then
            local s = Site(f:GetSourceLocation())
            if s and not Perf.SCRIPT_SKIP[s:match("^(.-):%d+$") or s] then
                site = s
                Perf.ours = Perf.ours + 1
            end
        end
        Perf.siteOf[f] = site
    end
    if not site or (f.IsProtected and f:IsProtected()) then return end
    for _, script in ipairs(Perf.SCRIPTS) do
        local fn = f:HasScript(script) and f:GetScript(script)
        if fn and not isTimed[fn] then
            local w = TimedScript("script " .. site .. " " .. script, fn)
            f:SetScript(script, w)
            local byScript = Perf.swapped[f]
            if not byScript then
                byScript = {}
                Perf.swapped[f] = byScript
            end
            if not byScript[script] then Perf.timedScripts = Perf.timedScripts + 1 end
            byScript[script] = { fn = fn, w = w }
        end
    end
end

-- Every frame at once: Start and Record next fight do it out of combat, so the
-- long frame lands before the pull.
function Perf.SweepAll()
    if not EnumerateFrames then return end
    local f = EnumerateFrames()
    while f do
        SweepFrame(f)
        f = EnumerateFrames(f)
    end
    Perf.cursor, Perf.swept = nil, true
end

-- A slice of the walk, every frame while recording.
function Perf.SweepStep()
    if not EnumerateFrames then return end
    local f = Perf.cursor
    for _ = 1, Perf.SWEEP_STEP do
        f = EnumerateFrames(f)
        if not f then break end
        SweepFrame(f)
    end
    Perf.cursor = f
end

-- Each script goes back, unless something set another one since. A frame that
-- turned forbidden or protected keeps its timed one, which costs nothing off.
function Perf.Unswap()
    for f, byScript in pairs(Perf.swapped) do
        if not (f:IsForbidden() or f:IsProtected()) then
            for script, r in pairs(byScript) do
                if f:GetScript(script) == r.w then f:SetScript(script, r.fn) end
            end
        end
    end
    wipe(Perf.swapped)
    wipe(Perf.siteOf)
    Perf.cursor, Perf.swept = nil, false
    -- the report after Off still says how many were timed
    Perf.lastOurs, Perf.lastTimed = Perf.ours, Perf.timedScripts
    Perf.ours, Perf.timedScripts = 0, 0
end

local function DeepRows(t, top, out, fmt)
    local rows = {}
    for key, s in pairs(t) do rows[#rows + 1] = { key = key, s = s } end
    table.sort(rows, function(a, b) return a.s.ms > b.s.ms end)
    for i = 1, math.min(top, #rows) do out[#out + 1] = fmt(i, rows[i].key, rows[i].s) end
end

-- The busiest frames that are not ours, a short list kept in order: a hook we
-- put on someone else's frame runs inside that frame's time.
local function KeepTop(list, row, top)
    local i = #list + 1
    while i > 1 and list[i - 1].ms < row.ms do i = i - 1 end
    if i <= top then
        table.insert(list, i, row)
        if #list > top then list[#list] = nil end
    end
end

local function Short(loc)
    if type(loc) ~= "string" then return "?" end
    return (loc:gsub("^.-[/\\][Aa]dd[Oo]ns[/\\]", ""))
end

function Perf.DeepLines()
    if not Perf.deep then return Perf.deepLines end
    if UpdateAddOnCPUUsage then UpdateAddOnCPUUsage() end
    local secs = math.max(GetTime() - (Perf.deepSince or GetTime()), 0.001)
    local total = (GetAddOnCPUUsage and GetAddOnCPUUsage(ADDON)) or 0
    local sites, matched, others = {}, 0, {}
    local f = EnumerateFrames and EnumerateFrames()
    while f do
        if not (f.IsForbidden and f:IsForbidden()) and f.GetSourceLocation then
            local loc = f:GetSourceLocation()
            local site = Site(loc)
            local ms, n = GetFrameCPUUsage(f, false)
            if site then
                matched = matched + 1
                if type(ms) == "number" and ms > 0 then
                    local s = sites[site]
                    if not s then
                        s = { ms = 0, n = 0, frames = 0 }
                        sites[site] = s
                    end
                    s.ms, s.n, s.frames = s.ms + ms, s.n + (tonumber(n) or 0), s.frames + 1
                end
            elseif type(ms) == "number" and ms > 0 then
                local name = (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or "?"
                KeepTop(others, { name = tostring(name), loc = Short(loc), ms = ms, n = tonumber(n) or 0 }, Perf.TOP_OTHERS)
            end
        end
        f = EnumerateFrames(f)
    end
    -- the real functions, also while a recording has them wrapped
    local orig, funcs = {}, {}
    for _, w in ipairs(Perf.wrapped) do orig[w.w] = w.fn end
    for _, m in ipairs(Perf.ModuleTables(nil)) do
        for k, v in pairs(m.t) do
            if type(v) == "function" then
                local ms, n = GetFunctionCPUUsage(orig[v] or v, false)
                if type(ms) == "number" and ms > 0 then
                    funcs[m.name .. "." .. tostring(k)] = { ms = ms, n = tonumber(n) or 0 }
                end
            end
        end
    end
    local function Pct(ms) return Perf.PctText(total > 0 and ms / total * 100 or 0) end
    -- the profiler's own reports run inside this addon too
    local own = 0
    for key, s in pairs(funcs) do
        if key:find("^Perf%.") then own = own + s.ms end
    end
    local out = { "", ("Deep view, the game's script profiler (%.1f s): this addon %.2f ms, %.3f ms per second;"
        .. " without the profiler's own reports %.3f ms per second."):format(secs, total, total / secs,
        math.max(total - own, 0) / secs) }
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        local kb = GetAddOnMemoryUsage(ADDON)
        if type(kb) == "number" and type(Perf.deepMem) == "number" then
            out[#out + 1] = ("Memory: %.0f KB now, %.0f KB when the deep view started."):format(kb, Perf.deepMem)
        end
    end
    local q = NS.Events and NS.Events.RunPending
    local qms, qn = nil, nil
    if q then qms, qn = GetFunctionCPUUsage(q, true) end
    if type(qms) == "number" then
        out[#out + 1] = ("Work queued for the next frame, with everything it runs: %.2f ms (%s), %d runs."):format(
            qms, Pct(qms), tonumber(qn) or 0)
    end
    out[#out + 1] = ("Frame scripts by the file that made the frame, each with what it calls (%d of our frames seen):"):format(matched)
    DeepRows(sites, Perf.TOP_DEEP, out, function(i, key, s)
        return ("%2d. %s: %.2f ms (%s), %d calls, %d frames"):format(i, key, s.ms, Pct(s.ms), s.n, s.frames)
    end)
    out[#out + 1] = "Functions by their own time:"
    DeepRows(funcs, Perf.TOP_DEEP, out, function(i, key, s)
        return ("%2d. %s: %.2f ms (%s), %d calls"):format(i, key, s.ms, Pct(s.ms), s.n)
    end)
    out[#out + 1] = "The busiest frames that are not ours (any addon or the game; a hook of ours counts inside them):"
    for i, r in ipairs(others) do
        out[#out + 1] = ("%2d. %s (%s): %.2f ms, %d calls"):format(i, r.name, r.loc, r.ms, r.n)
    end
    return out
end

-- /arcperf deep: on (the counters start from zero), then off with the last
-- numbers kept in the report.
function Perf.Deep()
    if Perf.deep then
        Perf.deepLines = Perf.DeepLines()
        Perf.deep = false
        return
    end
    if not (GetCVarBool and GetCVarBool("scriptProfile")) then
        Perf.deepLines = { "", "The deep view needs the game's script profiler, which slows every addon while it is on:",
            "/console scriptProfile 1, then /reload, then /arcperf deep. Afterwards /console scriptProfile 0 and /reload." }
        return
    end
    if ResetCPUUsage then ResetCPUUsage() end
    Perf.deep, Perf.deepSince, Perf.deepLines = true, GetTime(), nil
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        Perf.deepMem = GetAddOnMemoryUsage(ADDON)
    end
end

-- The report as plain text lines: the game's numbers, then ours, then the
-- deep view when it has numbers.
function Perf.Lines()
    local out = {}
    for _, line in ipairs(Perf.openLines or {}) do out[#out + 1] = line end
    -- a report reads the game's numbers before its own work (Perf.Report)
    if Perf.snap then
        for _, line in ipairs(Perf.snap) do out[#out + 1] = line end
    else
        GameLines(out)
    end
    for _, line in ipairs(Perf.measureLines or {}) do out[#out + 1] = line end
    if Perf.measureLines then
        -- nothing else to show
    elseif not next(Perf.stats) and not next(Perf.after) then
        out[#out + 1] = Perf.on and "Recording, nothing seen yet."
            or "Nothing recorded. Press Record next fight, or Start."
        out[#out + 1] = Perf.ListLine(Perf.meta[Perf.stats])
        out[#out + 1] = Perf.FramesLine()
    else
        local stop = Perf.endedAt or GetTime()
        local secs = math.max(stop - Perf.since, 0.001)
        local fight = 0
        for _, s in pairs(Perf.stats) do fight = fight + s.self end
        out[#out + 1] = ""
        out[#out + 1] = ("%s (%.1f s): %.2f ms of own work, %.3f ms per second, %d modules traced. Top by own time:"):format(
            Perf.endedAt and "In the fight" or "Recorded", secs, fight, fight / secs, Perf.moduleCount or 0)
        RowLines(out, Perf.stats, secs, Perf.TOP)
        KindLines(out, Perf.stats, secs)
        CoverageLines(out, Perf.stats, secs)
        local ours, timed = Perf.ours, Perf.timedScripts
        if not Perf.swept then ours, timed = Perf.lastOurs, Perf.lastTimed end
        if ours and ours > 0 then
            out[#out + 1] = ("Frame scripts: %d timed on our frames (%d frames of ours found by where they were made)."):format(
                timed or 0, ours)
        elseif ours then
            out[#out + 1] = "Frame scripts: the game did not say which frames are ours, so they are not timed; /arcperf deep covers them."
        end
        out[#out + 1] = Perf.FramesLine()
        if next(Perf.after) then
            local tail = math.max(GetTime() - (Perf.endedAt or GetTime()), 0.001)
            local own = 0
            for _, s in pairs(Perf.after) do own = own + s.self end
            out[#out + 1] = ""
            out[#out + 1] = ("The %.1f s after combat: %.2f ms of own work. Top:"):format(tail, own)
            RowLines(out, Perf.after, tail, Perf.TOP_AFTER)
            KindLines(out, Perf.after, tail)
            CoverageLines(out, Perf.after, tail)
        end
    end
    for _, line in ipairs(Perf.deepLines or {}) do out[#out + 1] = line end
    return out
end

-- The window (the probe rule: a copyable text box, never chat)

function Perf.Status()
    local s = "Off."
    if Perf.openArmed and not Perf.openRec then
        s = "Armed: open the options panel now."
    elseif Perf.openRec then
        s = "Recording the options open."
    elseif Perf.runMeasuring then
        s = ("Measuring this M+ run (%d s)."):format(math.floor(GetTime() - (Perf.since or GetTime())))
    elseif Perf.runArmed then
        s = "Armed: the next M+ key is measured, from its start to its end."
    elseif Perf.measuring then
        s = "Measuring this fight."
    elseif Perf.measureArmed then
        s = "Armed: the next fight is measured."
    elseif Perf.fightArmed and not Perf.on then
        s = "Armed: the next fight is recorded."
    elseif Perf.on then
        s = "Recording."
    end
    if Perf.deep then s = s .. " Deep view on." end
    if Perf.savedAt and not Perf.on then s = s .. " Saved; /reload writes it to disk." end
    return s
end

-- The addon list's figure for this addon on screen while profiling: one
-- line, read once a second, its highest since profiling started beside it,
-- dragged anywhere (ArcAurasDB.perfHud keeps the spot). Up while a recording,
-- a measure or an M+ run is armed or running, or pinned by /arcperf hud;
-- hidden, it reads nothing.
Perf.HUD_SECS = 1

function Perf.HudWanted()
    return Perf.hudPinned or Perf.on or Perf.measuring or Perf.measureArmed or Perf.fightArmed
        or Perf.runMeasuring or Perf.runArmed or false
end

function Perf.HudText()
    local P, M = Profiler()
    if not P then return "|cff3fc9f2Arc|r Auras: the game's profiler is off" end
    local pct = Perf.AddonPct(ADDON, M.RecentAverageTime)
    if pct and (not Perf.hudPeak or pct > Perf.hudPeak) then Perf.hudPeak = pct end
    return ("|cff3fc9f2Arc|r Auras  %s   |cffb3c7e0highest %s|r"):format(Perf.PctText(pct), Perf.PctText(Perf.hudPeak))
end

local function HudPlace(f)
    local at = type(ArcAurasDB) == "table" and ArcAurasDB.perfHud
    f:ClearAllPoints()
    if type(at) == "table" and type(at.x) == "number" and type(at.y) == "number" then
        f:SetPoint(at.p or "CENTER", UIParent, at.p or "CENTER", at.x, at.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

function Perf.HudBuild()
    if Perf.hud then return Perf.hud end
    local AT = NS.AT
    local f = CreateFrame("Frame", "ArcAurasPerfHud", UIParent)
    f:SetSize(200, 24)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    if AT and AT.Skin then AT.Skin(f, AT.COL.bg, AT.COL.line2) end
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    fs:SetPoint("CENTER")
    f.text = fs
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and ux and type(ArcAurasDB) == "table" then
            ArcAurasDB.perfHud = { p = "CENTER", x = math.floor(x - ux + 0.5), y = math.floor(y - uy + 0.5) }
        end
        HudPlace(self)
    end)
    if AT and AT.Tooltip then
        AT.Tooltip(f, "Arc Auras CPU", "The addon list's figure for Arc Auras, once a second. Drag to move it.")
    end
    HudPlace(f)
    f:Hide()
    Perf.hud = f
    return f
end

function Perf.HudPaint()
    local f = Perf.hud
    if not (f and f:IsShown()) then return end
    f.text:SetText(Perf.HudText())
    local w = f.text:GetStringWidth()
    if type(w) == "number" and w > 0 then f:SetWidth(math.max(160, math.ceil(w) + 20)) end
end

-- Shows or hides it with the profiling state; one ticker only while it shows.
function Perf.HudSync()
    local want = Perf.HudWanted()
    if want then
        local f = Perf.HudBuild()
        if not f:IsShown() then
            f:Show()
            Perf.HudPaint()
        end
        if not Perf.hudTicker and C_Timer and C_Timer.NewTicker then
            Perf.hudTicker = C_Timer.NewTicker(Perf.HUD_SECS, Perf.HudPaint)
        end
    else
        if Perf.hud then Perf.hud:Hide() end
        if Perf.hudTicker then
            Perf.hudTicker:Cancel()
            Perf.hudTicker = nil
        end
    end
end

-- A recording counts the window's refresh as the profiler's own work.
function Perf.Refresh()
    local t0 = clock()
    Perf.HudSync()
    Perf.text = table.concat(Perf.Lines(), "\n")
    local w = Perf.win
    if w and w:IsShown() then
        w.edit:SetText(Perf.text)
        w.status:SetText(Perf.Status())
        w.toggle.fs:SetText(Perf.on and "Stop" or "Start")
        if w.run then w.run.fs:SetText(Perf.runArmed and "Stop M+ run" or "Record M+ run") end
        if w.scroll.UpdateScroll then w.scroll:UpdateScroll() end
    end
    if Perf.on then
        local m = Meta(Perf.cur)
        m.over = m.over + clock() - t0
    end
end

-- Live numbers only while the window shows and a recording runs.
function Perf.Tick(on)
    if on and not Perf.ticker and C_Timer and C_Timer.NewTicker then
        Perf.ticker = C_Timer.NewTicker(Perf.REFRESH, function()
            if Perf.on and not Perf.openRec then Perf.Refresh() end
        end)
    elseif not on and Perf.ticker then
        Perf.ticker:Cancel()
        Perf.ticker = nil
    end
end

function Perf.Build()
    local AT = NS.AT
    if Perf.win or not (AT and AT.CreateWindow) then return Perf.win end
    local w = AT.CreateWindow("ArcAurasPerf", {
        w = 760, h = 420, minW = 640, minH = 300, maxW = 1400, maxH = 1100,
        title = "|cff3fc9f2Arc|r Auras performance",
        onResize = function() Perf.Refresh() end,
    })
    w:SetFrameStrata("DIALOG")
    local edit = CreateFrame("EditBox", nil, w)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(620)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- read-only: a typed change puts the report back
    edit:SetScript("OnTextChanged", function(self, typed)
        if typed then self:SetText(Perf.text or "") end
    end)
    local scroll = AT.MakeScroll(w, edit)
    scroll:SetPoint("TOPLEFT", 14, -42)
    scroll:SetPoint("BOTTOMRIGHT", -18, 50)
    scroll:HookScript("OnSizeChanged", function(_, sw) if sw and sw > 0 then edit:SetWidth(sw - 8) end end)
    w.edit, w.scroll = edit, scroll

    local function Btn(label, width, x, fn)
        local b = AT.MakeSmallButton(w, label, width)
        b:SetPoint("BOTTOMLEFT", x, 12)
        b:SetScript("OnClick", fn)
        return b
    end
    Btn("Select all", 90, 14, function() edit:SetFocus() edit:HighlightText() end)
    Btn("Record next fight", 140, 110, function() Perf.ArmFight() Perf.Refresh() end)
    w.toggle = Btn("Start", 70, 256, function()
        if Perf.on then
            Perf.Off()
            Perf.Refresh()
            Perf.Save("recording")
            Perf.Refresh()
            return
        end
        Perf.On()
        Perf.Refresh()
    end)
    Btn("Reset", 70, 332, function() Perf.Reset() Perf.Refresh() end)
    w.run = Btn("Record M+ run", 112, 408, function()
        if Perf.runArmed then Perf.CancelRun() else Perf.ArmRun() end
        Perf.Refresh()
    end)
    AT.Tooltip(w.run, "Record M+ run", "Measures a whole key, nothing traced: now if one runs, else from the next key's start to its end.")
    local status = w:CreateFontString(nil, "OVERLAY")
    status:SetFont(STANDARD_TEXT_FONT, 12, "")
    status:SetPoint("BOTTOMLEFT", 526, 18)
    status:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    w.status = status
    w:HookScript("OnShow", function() Perf.Tick(true) Perf.Refresh() end)
    w:HookScript("OnHide", function() Perf.Tick(false) end)
    Perf.win = w
    return w
end

-- Opens the window on the latest report. The game's numbers are read first:
-- the deep scan and the window's text would otherwise land in the "recent"
-- average the report prints.
function Perf.Report()
    local game = {}
    GameLines(game)
    Perf.snap = game
    if Perf.deep then Perf.deepLines = Perf.DeepLines() end
    Perf.text = table.concat(Perf.Lines(), "\n")
    local w = Perf.Build()
    if w then
        w:Show()
        Perf.Refresh()
    end
    Perf.snap = nil
end

-- Record next fight: the fight alone, then the window opens on its report.
function Perf.ArmFight()
    local E = NS.Events
    if Perf.runArmed or Perf.runMeasuring then return end
    if Perf.measureArmed then Perf.CancelMeasure() end
    Perf.fightArmed = true
    -- our frames' scripts are found now, out of combat, not at the pull
    if not Perf.swept then Perf.SweepAll() end
    E.On("PLAYER_REGEN_DISABLED", "adperf", function()
        if not Perf.fightArmed then return end
        if Perf.on then Perf.Reset() else Perf.On() end
        -- with the game's script profiler on, the deep view covers the fight too
        if not Perf.deep and GetCVarBool and GetCVarBool("scriptProfile") then
            Perf.Deep()
            Perf.fightDeep = true
        end
    end)
    E.On("PLAYER_REGEN_ENABLED", "adperf", function()
        if not (Perf.fightArmed and Perf.on) then return end
        Perf.fightArmed = false
        E.Off("PLAYER_REGEN_DISABLED", "adperf")
        E.Off("PLAYER_REGEN_ENABLED", "adperf")
        -- the work that waited for combat to end lands in its own table
        Perf.endedAt = GetTime()
        Perf.cur = Perf.after
        C_Timer.After(Perf.TAIL, Perf.EndFight)
    end)
end

-- The tail is over: the window opens on the fight and its aftermath.
function Perf.EndFight()
    if not Perf.on then return end
    Perf.Report()
    if Perf.fightDeep and Perf.deep then
        Perf.fightDeep = false
        Perf.Deep()
    end
    Perf.Off()
    Perf.Refresh()
    Perf.Save("fight")
    Perf.Refresh()
end

-- /arcperf measure: the next fight with nothing traced, only the game's own
-- count for this addon frame by frame, so the number is what a player pays (a
-- recording's wrappers raise it). The sampler's own reads are taken out.
function Perf.CancelMeasure()
    local E = NS.Events
    Perf.measureArmed, Perf.measuring = false, false
    E.Off("PLAYER_REGEN_DISABLED", "adperf_measure")
    E.Off("PLAYER_REGEN_ENABLED", "adperf_measure")
    if not (Perf.on or Perf.runMeasuring) then Perf.Sampling(false) end
end

function Perf.ArmMeasure()
    local E = NS.Events
    if Perf.on or Perf.runArmed or Perf.runMeasuring then return end
    if Perf.fightArmed then
        Perf.fightArmed = false
        E.Off("PLAYER_REGEN_DISABLED", "adperf")
        E.Off("PLAYER_REGEN_ENABLED", "adperf")
    end
    Perf.measureArmed = true
    E.On("PLAYER_REGEN_DISABLED", "adperf_measure", function()
        if not Perf.measureArmed or Perf.on then return end
        Perf.measureArmed = false
        Perf.Reset()
        Perf.measuring = true
        -- the frame the pull came in holds the arming, not the fight
        Perf.skipSample = true
        Perf.Sampling(true)
    end)
    E.On("PLAYER_REGEN_ENABLED", "adperf_measure", function()
        if not Perf.measuring then return end
        Perf.CancelMeasure()
        Perf.MeasureLines("fight")
        Perf.Report()
        Perf.Save("measure")
        Perf.Refresh()
    end)
end

-- What a measure found: its ms, per second and per frame (the sampler's own
-- reads taken out), the addon list's figure through it, the split in and out
-- of combat, and the session's frames. what: "fight", "M+ run (completed)"...
function Perf.MeasureLines(what)
    Perf.endedAt = GetTime()
    local m = Perf.meta[Perf.stats] or { game = 0, ticks = 0, over = 0 }
    local secs = math.max(Perf.endedAt - Perf.since, 0.001)
    local own = math.max(m.game - m.over, 0)
    Perf.measureLines = { "", ("Measured %s (%.1f s, nothing traced): %.2f ms, %.3f ms per second, %.3f ms per frame over %d frames (own sampling %.2f ms out)."):format(
        what, secs, own, own / secs, own / math.max(m.ticks, 1), m.ticks, m.over) }
    local L = Perf.measureLines
    L[#L + 1] = Perf.ListLine(m)
    L[#L + 1] = Perf.CombatLine(m)
    L[#L + 1] = Perf.FramesLine()
end

-- /arcperf mplus, the Record M+ run button: a whole key measured with nothing
-- traced, from its start (at once when a key already runs, its countdown
-- included) to its end: done, reset, or a loading screen out of it. A reload
-- in the middle saves what it has (the logout save) and carries on after it
-- (ArcAurasDB.perfRun) while the key still runs.
Perf.RUN_EVENTS = { "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD" }

function Perf.KeyRuns()
    local CM = C_ChallengeMode
    local on = CM and CM.IsChallengeModeActive and CM.IsChallengeModeActive()
    if issecretvalue and issecretvalue(on) then return false end
    return on == true
end

local function RunFlag(on)
    if type(ArcAurasDB) == "table" then ArcAurasDB.perfRun = on or nil end
end

local function RunStart()
    Perf.Reset()
    Perf.runMeasuring = true
    Perf.skipSample = true
    Perf.Sampling(true)
    RunFlag(true)
    Perf.Refresh()
end

function Perf.CancelRun()
    local E = NS.Events
    Perf.runArmed, Perf.runMeasuring = false, false
    for _, e in ipairs(Perf.RUN_EVENTS) do E.Off(e, "adperf_run") end
    RunFlag(nil)
    if not (Perf.on or Perf.measuring) then Perf.Sampling(false) end
end

function Perf.EndRun(why)
    if not Perf.runMeasuring then return end
    Perf.CancelRun()
    Perf.MeasureLines("M+ run (" .. why .. ")")
    Perf.Report()
    Perf.Save("M+ run")
    Perf.Refresh()
end

-- After a reload: a run that was measuring carries on while its key runs.
function Perf.ResumeRun()
    if type(ArcAurasDB) ~= "table" or not ArcAurasDB.perfRun then return end
    if Perf.KeyRuns() then Perf.ArmRun() else ArcAurasDB.perfRun = nil end
end

function Perf.ArmRun()
    local E = NS.Events
    if Perf.on or Perf.runArmed then return end
    if Perf.fightArmed then
        Perf.fightArmed = false
        E.Off("PLAYER_REGEN_DISABLED", "adperf")
        E.Off("PLAYER_REGEN_ENABLED", "adperf")
    end
    if Perf.measureArmed or Perf.measuring then Perf.CancelMeasure() end
    Perf.runArmed = true
    E.On("CHALLENGE_MODE_START", "adperf_run", function()
        if Perf.runArmed and not Perf.runMeasuring then RunStart() end
    end)
    E.On("CHALLENGE_MODE_COMPLETED", "adperf_run", function() Perf.EndRun("completed") end)
    E.On("CHALLENGE_MODE_RESET", "adperf_run", function() Perf.EndRun("reset") end)
    E.On("PLAYER_ENTERING_WORLD", "adperf_run", function()
        if Perf.runMeasuring and not Perf.KeyRuns() then Perf.EndRun("left the dungeon") end
    end)
    if Perf.KeyRuns() then RunStart() end
end

-- Every finished report also goes into the saved variables, newest first, so
-- it outlives the session and can be read outside the game. The newest few
-- also keep every row, not just the report's top ones:
-- "own ms <tab> total ms <tab> calls <tab> peak ms <tab> key".
Perf.KEEP = 10
Perf.KEEP_ROWS = 3
local function RowsText(t)
    local out = {}
    for _, r in ipairs(Perf.Rows(t)) do
        out[#out + 1] = ("%.3f\t%.3f\t%d\t%.3f\t%s"):format(r.s.self, r.s.ms, r.s.n, r.s.peak, r.key)
    end
    return out
end
function Perf.Save(kind)
    local db = ArcAurasDB
    if type(db) ~= "table" or not Perf.text then return end
    if type(db.perfLog) ~= "table" then db.perfLog = {} end
    local lines = {}
    for line in (Perf.text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    local version, build = nil, nil
    if GetBuildInfo then version, build = GetBuildInfo() end
    table.insert(db.perfLog, 1, {
        kind = kind,
        at = time and time() or nil,
        when = date and date("%Y-%m-%d %H:%M:%S") or nil,
        who = tostring(name) .. "-" .. tostring(realm),
        client = (NS.IsForever and "Forever " or "retail ") .. tostring(version) .. "." .. tostring(build),
        lines = lines,
        rows = next(Perf.stats) and RowsText(Perf.stats) or nil,
        rowsAfter = next(Perf.after) and RowsText(Perf.after) or nil,
        -- every second of it: the game's count for us (ms) and the addon list's figure (%)
        seconds = Perf.SecondsText(Perf.meta[Perf.stats]),
    })
    for i = #db.perfLog, Perf.KEEP + 1, -1 do db.perfLog[i] = nil end
    -- the full rows are big: only the newest few keep them
    for i = Perf.KEEP_ROWS + 1, #db.perfLog do
        db.perfLog[i].rows, db.perfLog[i].rowsAfter, db.perfLog[i].seconds = nil, nil, nil
    end
    Perf.savedAt = GetTime()
end

-- The open probe (/arcperf open): from the moment the options window starts
-- to load (or shows), every frame for OPEN_SECS seconds: the frame's time,
-- this addon's time in it (the game's own count), the options build's slice
-- and the pane it was on, the page layouts and window refreshes that ran, and
-- Lua memory; the module table runs beside it, the Edit chips included. The
-- report says whether a slow frame was this addon's work or the game's.
Perf.OPEN_SECS = 3
Perf.OPEN_WORST = 25
-- traced for the probe beyond the usual modules: the Edit chips and the
-- New Layout page's helpers; the options window and the theme stay out (their
-- builders pause mid-call)
Perf.OPEN_SKIP = {}
for k, v in pairs(Perf.SKIP) do Perf.OPEN_SKIP[k] = v end
Perf.OPEN_SKIP.IconScreen, Perf.OPEN_SKIP.LayoutPreview, Perf.OPEN_SKIP.Spotlight = nil, nil, nil

function Perf.OpenNote(kind, ms)
    local r = Perf.openRec
    if not r then return end
    r[kind .. "N"] = r[kind .. "N"] + 1
    r[kind .. "Ms"] = r[kind .. "Ms"] + ms
end

local function OptionsStarted()
    local O = NS.Options
    local L = O and O.Loader
    if L and L.Busy and L.Busy() then return true end
    local w = _G.ArcUIv2Options
    return w ~= nil and w:IsShown() == true
end

-- The step list: what ran, in order, with its time, from arming until a few
-- seconds into the recording (the open's first frames). Frame ends are marked
-- by the probe's own per-frame script.
Perf.MARK_SECS = 3
Perf.MARK_MAX = 600
function Perf.Mark(label)
    local m = Perf.marks
    if not m or #m >= Perf.MARK_MAX then return end
    m[#m + 1] = { label, clock(), collectgarbage("count") }
end

-- the calls that open the window, marked on their way in and out
local OPEN_CALLS = { "Toggle", "Open" }
function Perf.MarkOpenCalls(on)
    local O = NS.Options
    if not O then return end
    Perf.openCalls = Perf.openCalls or {}
    for _, k in ipairs(OPEN_CALLS) do
        if on and not Perf.openCalls[k] and type(O[k]) == "function" then
            local base = O[k]
            Perf.openCalls[k] = base
            O[k] = function(...)
                Perf.Mark("Options." .. k .. " starts")
                local ret = pack(base(...))
                Perf.Mark("Options." .. k .. " returns")
                return unpack(ret, 1, ret.n)
            end
        elseif not on and Perf.openCalls[k] then
            O[k] = Perf.openCalls[k]
            Perf.openCalls[k] = nil
        end
    end
end

function Perf.ArmOpen()
    Perf.Off()
    Perf.openArmed, Perf.openRec, Perf.openLines = true, nil, nil
    -- every wrap made now, so the open's own frames carry none of it
    Perf.On(Perf.OPEN_SKIP)
    Perf.marks, Perf.marking = {}, true
    Perf.MarkOpenCalls(true)
    Perf.openDriver = Perf.openDriver or CreateFrame("Frame")
    Perf.openDriver:SetScript("OnUpdate", Perf.OpenTick)
end

function Perf.OpenStart()
    Perf.openArmed = false
    -- the table counts the open from here: what ran while armed is cleared
    Perf.Reset()
    Perf.Mark("probe: the load started, recording")
    local r = { start = GetTime(), frames = {}, mem = collectgarbage("count"),
        lpN = 0, lpMs = 0, rfN = 0, rfMs = 0 }
    Perf.openRec = r
    -- every page layout, timed (its callers read AT.LayoutPage at call time)
    local AT = NS.AT
    if AT and AT.LayoutPage and not Perf.openLayout then
        local base = AT.LayoutPage
        Perf.openLayout = base
        AT.LayoutPage = function(...)
            local t0 = clock()
            local ret = pack(base(...))
            Perf.OpenNote("lp", clock() - t0)
            return unpack(ret, 1, ret.n)
        end
    end
    -- the report window waits for the end: it would sit over the options window
    if Perf.win then Perf.win:Hide() end
end

function Perf.OpenTick(_, elapsed)
    if Perf.openArmed and not Perf.openRec then
        if not OptionsStarted() then return end
        Perf.OpenStart()
        return
    end
    local r = Perf.openRec
    if not r then return end
    local now = GetTime()
    if Perf.marking then
        Perf.Mark(("frame ends (%.0f ms)"):format((elapsed or 0) * 1000))
        if now - r.start >= Perf.MARK_SECS then Perf.marking = false end
    end
    local Pf, M = Profiler()
    local addon = Pf and M.LastTime and Pf.GetAddOnMetric(ADDON, M.LastTime)
    local O = NS.Options
    local L = O and O.Loader
    local w = _G.ArcUIv2Options
    local mem = collectgarbage("count")
    r.frames[#r.frames + 1] = {
        t = now - r.start, dt = (elapsed or 0) * 1000,
        addon = type(addon) == "number" and addon or nil,
        slice = L and L.sliceMs, bg = L and L.sliceBg, pane = O and O.buildingPane,
        lpN = r.lpN, lpMs = r.lpMs, rfN = r.rfN, rfMs = r.rfMs,
        mem = mem - r.mem, shown = w ~= nil and w:IsShown() == true,
    }
    if L then L.sliceMs, L.sliceBg = nil, nil end
    r.lpN, r.lpMs, r.rfN, r.rfMs, r.mem = 0, 0, 0, 0, mem
    if not r.shownAt and w and w:IsShown() then r.shownAt = now - r.start end
    if now - r.start >= Perf.OPEN_SECS then Perf.OpenStop() end
end

function Perf.OpenStop()
    if Perf.openDriver then Perf.openDriver:SetScript("OnUpdate", nil) end
    Perf.marking = false
    Perf.MarkOpenCalls(false)
    local AT = NS.AT
    if Perf.openLayout and AT then AT.LayoutPage = Perf.openLayout end
    Perf.openLayout = nil
    local r = Perf.openRec
    Perf.openRec = nil
    if r then Perf.openLines = Perf.OpenLines(r) end
    Perf.endedAt = GetTime()
    Perf.Report()
    Perf.Off()
    Perf.Refresh()
    Perf.Save("options open")
    Perf.Refresh()
end

local function F1(v) return v and ("%.1f"):format(v) or "-" end

function Perf.OpenLines(r)
    local out, fr = {}, r.frames
    local n = #fr
    if n == 0 then return { "Options open probe: no frames recorded." } end
    local total, worst, over33, over100 = 0, 0, 0, 0
    local addonAll, addonSlow, slowAll, build, buildBg = 0, 0, 0, 0, 0
    local lpN, lpMs, rfN, rfMs, grow, gcSteps = 0, 0, 0, 0, 0, 0
    local haveAddon = false
    for _, f in ipairs(fr) do
        total = total + f.dt
        if f.dt > worst then worst = f.dt end
        if f.dt > 33.4 then over33 = over33 + 1 end
        if f.dt > 100 then over100 = over100 + 1 end
        if f.addon then
            haveAddon = true
            addonAll = addonAll + f.addon
            if f.dt > 33.4 then addonSlow, slowAll = addonSlow + f.addon, slowAll + f.dt end
        end
        if f.slice then
            if f.bg then buildBg = buildBg + f.slice else build = build + f.slice end
        end
        lpN, lpMs, rfN, rfMs = lpN + f.lpN, lpMs + f.lpMs, rfN + f.rfN, rfMs + f.rfMs
        if f.mem > 0 then grow = grow + f.mem end
        if f.mem < -1024 then gcSteps = gcSteps + 1 end
    end
    local secs = math.max(fr[n].t, 0.001)
    out[#out + 1] = ("Options open probe: %.1f s from the first load, %d frames, the window showed after %s s."):format(
        secs, n, r.shownAt and ("%.2f"):format(r.shownAt) or "-")
    out[#out + 1] = ("  Frames: %.0f fps on average, the slowest %.0f ms; %d over 33 ms (under 30 fps), %d over 100 ms."):format(
        n / math.max(total / 1000, 0.001), worst, over33, over100)
    if haveAddon then
        out[#out + 1] = ("  This addon, as the game counts it: %.0f ms in all; in the frames over 33 ms it was %.0f%% of their time."):format(
            addonAll, slowAll > 0 and (100 * addonSlow / slowAll) or 0)
    else
        out[#out + 1] = "  This addon, as the game counts it: not available (the game's addon profiler is off)."
    end
    out[#out + 1] = ("  The options build: %.0f ms while it loaded, %.0f ms in the background."):format(build, buildBg)
    out[#out + 1] = ("  Page layouts: %d, %.0f ms. Window refreshes: %d, %.0f ms."):format(lpN, lpMs, rfN, rfMs)
    out[#out + 1] = ("  Lua memory: +%.1f MB made, %d frames where a garbage collection freed over 1 MB."):format(
        grow / 1024, gcSteps)
    -- each second: fps, this addon's ms, the build's ms
    out[#out + 1] = ""
    out[#out + 1] = "Each second (fps / this addon ms / build ms):"
    local line, sec = {}, 0
    local cnt, sAddon, sBuild, sDt = 0, 0, 0, 0
    local function Flush()
        if cnt > 0 then
            line[#line + 1] = ("%ds %d/%s/%.0f"):format(sec, math.floor(cnt / math.max(sDt / 1000, 0.001) + 0.5),
                haveAddon and ("%.0f"):format(sAddon) or "-", sBuild)
        end
        if #line >= 6 then
            out[#out + 1] = "  " .. table.concat(line, "   ")
            line = {}
        end
    end
    for _, f in ipairs(fr) do
        local s = math.floor(f.t)
        if s ~= sec then
            Flush()
            sec, cnt, sAddon, sBuild, sDt = s, 0, 0, 0, 0
        end
        cnt, sDt = cnt + 1, sDt + f.dt
        sAddon = sAddon + (f.addon or 0)
        sBuild = sBuild + (f.slice or 0)
    end
    Flush()
    if #line > 0 then out[#out + 1] = "  " .. table.concat(line, "   ") end
    -- the slowest frames
    local order = {}
    for i = 1, n do order[i] = i end
    table.sort(order, function(a, b) return fr[a].dt > fr[b].dt end)
    out[#out + 1] = ""
    out[#out + 1] = ("The %d slowest frames (second, frame ms, this addon ms, build ms [pane], layouts n/ms, refreshes n/ms, memory KB, window):"):format(
        math.min(Perf.OPEN_WORST, n))
    for i = 1, math.min(Perf.OPEN_WORST, n) do
        local f = fr[order[i]]
        out[#out + 1] = ("  %5.2f  %6.1f  %6s  %6s %-10s %d/%s  %d/%s  %+.0f  %s"):format(
            f.t, f.dt, F1(f.addon), F1(f.slice), f.slice and ("[" .. tostring(f.pane or (f.bg and "bg" or "open")) .. "]") or "",
            f.lpN, F1(f.lpMs), f.rfN, F1(f.rfMs), f.mem, f.shown and "shown" or "loading")
    end
    -- the open's steps: each with the time since the one before and the Lua
    -- memory it made; a long gap is work no step names (another script, the
    -- game's own work, a garbage collection)
    local m = Perf.marks or {}
    if #m > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "The open, step by step (ms since the step before, ms since the open call, memory KB):"
        local t0 = m[1][2]
        for i, e in ipairs(m) do
            local gap = (i > 1) and (e[2] - m[i - 1][2]) or 0
            local mem = (i > 1) and (e[3] - m[i - 1][3]) or 0
            out[#out + 1] = ("  %8.1f  %8.1f  %+7.0f  %s%s"):format(gap, e[2] - t0, mem, e[1],
                gap >= 50 and "   <<" or "")
        end
    end
    out[#out + 1] = ""
    return out
end

-- Only the first open after a reload builds the window, so a probe asked for
-- once it exists reloads the UI and arms itself for the next one (a saved flag
-- carries it over).
function Perf.AskOpen()
    local S = NS.Store
    if _G.ArcUIv2Options and S and S.SetSetting and ReloadUI then
        S.SetSetting("perfOpenArm", true)
        ReloadUI()
        return
    end
    Perf.ArmOpen()
    Perf.Report()
end

if NS.Events and NS.Events.On then
    NS.Events.On("PLAYER_ENTERING_WORLD", "adperf_open", function()
        NS.Events.Off("PLAYER_ENTERING_WORLD", "adperf_open")
        local S = NS.Store
        if not (S and S.GetSetting and S.GetSetting("perfOpenArm")) then return end
        S.SetSetting("perfOpenArm", nil)
        Perf.ArmOpen()
        Perf.Report()
    end)
end

SLASH_ARCPERF1 = "/arcperf"
SlashCmdList.ARCPERF = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "open" then
        Perf.AskOpen()
        return
    end
    local ended
    if cmd == "on" then
        Perf.On()
    elseif cmd == "off" then
        ended = Perf.on and "recording"
        Perf.Off()
    elseif cmd == "reset" then
        Perf.Reset()
    elseif cmd == "fight" then
        Perf.ArmFight()
    elseif cmd == "measure" then
        Perf.ArmMeasure()
    elseif cmd == "hud" then
        Perf.hudPinned = not Perf.hudPinned
        Perf.HudSync()
        return
    elseif cmd == "mplus" then
        if Perf.runArmed then Perf.CancelRun() else Perf.ArmRun() end
    elseif cmd == "deep" then
        ended = Perf.deep and "deep view"
        Perf.Deep()
    end
    Perf.Report()
    if ended then
        Perf.Save(ended)
        Perf.Refresh()
    end
end

-- A recording cut short by a logout or a reload is kept as far as it got.
if NS.Events and NS.Events.On then
    NS.Events.On("PLAYER_LOGOUT", "adperf_save", function()
        if not (Perf.on or Perf.deep or Perf.measuring or Perf.runMeasuring) then return end
        if Perf.deep then Perf.deepLines = Perf.DeepLines() end
        if Perf.runMeasuring then
            Perf.MeasureLines("M+ run, part (a reload; it carries on after it)")
        elseif Perf.measuring then
            Perf.MeasureLines("fight, cut short")
        end
        Perf.text = table.concat(Perf.Lines(), "\n")
        Perf.Save("cut short by logout")
    end)
    -- a run that was measuring when the game reloaded carries on while its key runs
    NS.Events.On("PLAYER_ENTERING_WORLD", "adperf_runresume", function()
        NS.Events.Off("PLAYER_ENTERING_WORLD", "adperf_runresume")
        Perf.ResumeRun()
    end)
end
