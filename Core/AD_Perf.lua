-- AD_Perf: an opt-in profiler (/arcperf) showing what this addon spends per event handler and per module function, beside the game's own totals.
-- Off, nothing is wrapped and the dispatcher pays one flag test; on, Core\AD_Events.lua times each handler and the runtime modules' functions are wrapped.
-- It only does arithmetic on debugprofilestop(); wrapped calls pass their arguments and returns through untouched, secrets included.
local ADDON, NS = ...

local Perf = { on = false, stats = {}, keys = {}, wrapped = {}, since = 0, depth = 0, child = {} }
NS.Perf = Perf

-- The modules a fight pays for. The options window, the theme and the tiny
-- store accessors stay out: their cost folds into the callers' own time.
Perf.MODULES = { "Anchor", "Bars", "Castbars", "Conditions", "DriverAura", "DriverAuraGroups",
    "DriverCooldown", "DriverCustom", "DriverEnchant", "DriverRange", "DriverTotem", "DriverUnitAuras",
    "DriverWarn", "EnchantBars", "Factory", "LayoutEngine", "PressHighlight", "RangeBars", "Reminders",
    "Sounds", "Special", "SpecialIcon", "TextElements", "TooltipIDs" }
Perf.TOP = 12
Perf.TOP_AFTER = 6
Perf.OTHER = "EnhanceQoL"
-- Record next fight keeps going this long after combat ends: the settle work
-- that waited for combat runs then.
Perf.TAIL = 2
-- Where the timed calls go: the fight's table, then the tail's.
Perf.after = {}
Perf.cur = Perf.stats

-- WoW's Lua has no table.pack or table.unpack; select("#") keeps a trailing
-- nil return, so a wrapped call hands back exactly what it got.
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

-- One timed call. Nested timed calls subtract from the caller's self time, so
-- a module function's own work is told apart from what it calls.
function Perf.Call(key, fn, ...)
    local d = Perf.depth + 1
    Perf.depth = d
    Perf.child[d] = 0
    local t0 = clock()
    local r = pack(fn(...))
    local total = clock() - t0
    local own = total - Perf.child[d]
    Perf.depth = d - 1
    if d > 1 then Perf.child[d - 1] = Perf.child[d - 1] + total end
    local s = Stat(key)
    s.ms, s.self, s.n = s.ms + total, s.self + own, s.n + 1
    if total > s.peak then s.peak = total end
    return unpack(r, 1, r.n)
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

local function Wrapper(key, fn)
    return function(...) return Perf.Call(key, fn, ...) end
end

function Perf.WrapModules()
    for _, name in ipairs(Perf.MODULES) do
        local t = NS[name]
        if type(t) == "table" then
            for k, v in pairs(t) do
                if type(v) == "function" then
                    Perf.wrapped[#Perf.wrapped + 1] = { t = t, k = k, fn = v }
                    t[k] = Wrapper(name .. "." .. tostring(k), v)
                end
            end
        end
    end
end

-- Each wrapped field gets its own function back, unless something replaced it
-- while profiling ran.
function Perf.Unwrap()
    for i = #Perf.wrapped, 1, -1 do
        local w = Perf.wrapped[i]
        local cur = w.t[w.k]
        if cur ~= nil and cur ~= w.fn then w.t[w.k] = w.fn end
        Perf.wrapped[i] = nil
    end
end

function Perf.Reset()
    wipe(Perf.stats)
    wipe(Perf.after)
    Perf.cur = Perf.stats
    Perf.since = GetTime()
    Perf.endedAt = nil
end

function Perf.On()
    if Perf.on then return end
    Perf.Reset()
    Perf.WrapModules()
    Perf.on = true
end

function Perf.Off()
    if not Perf.on then return end
    Perf.on = false
    Perf.Unwrap()
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
    for _, name in ipairs({ ADDON, Perf.OTHER }) do
        local loaded = not (C_AddOns and C_AddOns.IsAddOnLoaded) or C_AddOns.IsAddOnLoaded(name)
        if loaded then
            out[#out + 1] = ("  %s: recent %s, session %s, peak %s"):format(name,
                Perf.PctText(Perf.AddonPct(name, M.RecentAverageTime)),
                Perf.PctText(Perf.AddonPct(name, M.SessionAverageTime)),
                Perf.PctText(Perf.AddonPct(name, M.PeakTime)))
        end
    end
    if P.GetTopKAddOnsForMetric then
        local top, parts = P.GetTopKAddOnsForMetric(M.RecentAverageTime, 3), {}
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

-- The report as plain text lines: the game's numbers, then ours.
function Perf.Lines()
    local out = {}
    GameLines(out)
    if not next(Perf.stats) and not next(Perf.after) then
        out[#out + 1] = Perf.on and "Recording, nothing seen yet."
            or "Nothing recorded. Press Record next fight, or Start."
        return out
    end
    local stop = Perf.endedAt or GetTime()
    local secs = math.max(stop - Perf.since, 0.001)
    local fight = 0
    for _, s in pairs(Perf.stats) do fight = fight + s.self end
    out[#out + 1] = ""
    out[#out + 1] = ("%s (%.1f s): %.2f ms of own work, %.3f ms per second. Top by own time:"):format(
        Perf.endedAt and "In the fight" or "Recorded", secs, fight, fight / secs)
    RowLines(out, Perf.stats, secs, Perf.TOP)
    if next(Perf.after) then
        local tail = math.max(GetTime() - (Perf.endedAt or GetTime()), 0.001)
        local own = 0
        for _, s in pairs(Perf.after) do own = own + s.self end
        out[#out + 1] = ""
        out[#out + 1] = ("The %.1f s after combat: %.2f ms of own work. Top:"):format(tail, own)
        RowLines(out, Perf.after, tail, Perf.TOP_AFTER)
    end
    return out
end

-- The window (the probe rule: a copyable text box, never chat)

function Perf.Status()
    if Perf.fightArmed and not Perf.on then return "Armed: the next fight is recorded." end
    if Perf.on then return "Recording." end
    return "Off."
end

function Perf.Refresh()
    Perf.text = table.concat(Perf.Lines(), "\n")
    local w = Perf.win
    if not (w and w:IsShown()) then return end
    w.edit:SetText(Perf.text)
    w.status:SetText(Perf.Status())
    w.toggle.fs:SetText(Perf.on and "Stop" or "Start")
    if w.scroll.UpdateScroll then w.scroll:UpdateScroll() end
end

-- Live numbers only while the window shows and a recording runs.
function Perf.Tick(on)
    if on and not Perf.ticker and C_Timer and C_Timer.NewTicker then
        Perf.ticker = C_Timer.NewTicker(1, function()
            if Perf.on then Perf.Refresh() end
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
        w = 680, h = 420, minW = 480, minH = 300, maxW = 1400, maxH = 1100,
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
        if Perf.on then Perf.Off() else Perf.On() end
        Perf.Refresh()
    end)
    Btn("Reset", 70, 332, function() Perf.Reset() Perf.Refresh() end)
    local status = w:CreateFontString(nil, "OVERLAY")
    status:SetFont(STANDARD_TEXT_FONT, 12, "")
    status:SetPoint("BOTTOMLEFT", 414, 18)
    status:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    w.status = status
    w:HookScript("OnShow", function() Perf.Tick(true) Perf.Refresh() end)
    w:HookScript("OnHide", function() Perf.Tick(false) end)
    Perf.win = w
    return w
end

-- Opens the window on the latest report.
function Perf.Report()
    Perf.text = table.concat(Perf.Lines(), "\n")
    local w = Perf.Build()
    if not w then return end
    w:Show()
    Perf.Refresh()
end

-- Record next fight: the fight alone, then the window opens on its report.
function Perf.ArmFight()
    local E = NS.Events
    Perf.fightArmed = true
    E.On("PLAYER_REGEN_DISABLED", "adperf", function()
        if not Perf.fightArmed then return end
        Perf.Off()
        Perf.On()
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
    Perf.Off()
    Perf.Refresh()
end

SLASH_ARCPERF1 = "/arcperf"
SlashCmdList.ARCPERF = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "on" then
        Perf.On()
    elseif cmd == "off" then
        Perf.Off()
    elseif cmd == "reset" then
        Perf.Reset()
    elseif cmd == "fight" then
        Perf.ArmFight()
    end
    Perf.Report()
end
