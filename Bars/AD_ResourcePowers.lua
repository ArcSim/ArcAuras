-- Resource powers: the retail power types on the resource bar (holy power, chi,
-- arcane charges, astral power, maelstrom, insanity, fury, essence, soul shards,
-- runes, stagger) and which powers this character can pick. The resource runtime
-- in Bars\AD_Bars.lua asks it at fixed points through Bars.ResPowers; it arms
-- its own events only while a rune or stagger bar lives. Power values can be
-- secret: each goes straight into a sink; only plain maxima and times compare.
local ADDON, NS = ...
local Bars = NS.Bars
if not Bars then return end
local K = Bars.Kit

local RP = {}
Bars.ResPowers = RP

RP.RUNES = 5
RP.SHARDS = 7
RP.ESSENCE = 19
-- Stagger is no Enum.PowerType: a pseudo id above the enum, read from
-- UnitStagger against the player's health.
RP.STAGGER = 100

-- The point powers and the cell count a bar lays out before a plain max has
-- been read (a login under restriction, the editor preview).
RP.POINT_MAX = { [4] = 5, [5] = 6, [7] = 5, [9] = 5, [12] = 5, [16] = 4, [19] = 5 }

-- Rune cells take the spec's colour, as the rune art does.
RP.RUNE_COLORS = { [250] = { 0.77, 0.12, 0.23 }, [251] = { 0.2, 0.6, 1 }, [252] = { 0, 0.8, 0.2 } }

local function Plain(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v)) and type(v) == "number"
end

local function SpecID()
    local SI = C_SpecializationInfo
    local idx = SI and SI.GetSpecialization and SI.GetSpecialization()
    if not idx then return nil end
    local id = SI.GetSpecializationInfo and SI.GetSpecializationInfo(idx)
    return id
end

function RP.IsPoint(pt) return RP.POINT_MAX[pt] ~= nil end

function RP.Pseudo(pt) return pt == RP.STAGGER end

-- the powers whose value this file reads instead of a plain UnitPower
function RP.Owns(pt) return pt == RP.SHARDS or pt == RP.STAGGER end

function RP.FallbackMax(pt)
    if pt == RP.STAGGER then return 100 end
    return RP.POINT_MAX[pt]
end

-- The fill value. Shards come unmodified (tenths), so a Destruction cell fills
-- part way; every warlock spec reads whole tens or tenths on the same scale.
function RP.Current(pt)
    if pt == RP.SHARDS then return UnitPower("player", RP.SHARDS, true) end
    if pt == RP.STAGGER then return UnitStagger and UnitStagger("player") or 0 end
    return nil
end

-- the readout value: whole shards, else the fill value
function RP.TextValue(pt, cur)
    if pt == RP.SHARDS then return UnitPower("player", RP.SHARDS) end
    return cur
end

-- fill units per point: a plain display divisor, tenths for shards
function RP.Scale(pt)
    if pt == RP.SHARDS and UnitPowerDisplayMod then
        local m = UnitPowerDisplayMod(RP.SHARDS)
        if Plain(m) and m > 1 then return m end
    end
    return 1
end

-- a cell's window in fill units: a scaled power fills its cell from empty to
-- full, a whole one flips at the half point
function RP.PipWindow(pt, i)
    local s = RP.Scale(pt)
    if s > 1 then return (i - 1) * s, i * s end
    return i - 0.5, i
end

-- the maximum: stagger runs against the player's health, plain for the player
function RP.Max(pt)
    if pt == RP.STAGGER then return UnitHealthMax("player") end
    return UnitPowerMax("player", pt)
end

function RP.Color(pt)
    if pt ~= RP.RUNES then return nil end
    local c = RP.RUNE_COLORS[SpecID() or 0]
    if c then return c[1], c[2], c[3] end
    return nil
end

-- Stagger's percent of health is handed out plain (GetStaggerPercentage carries
-- no secrecy on any client), the one power whose percent Lua may read.
function RP.PlainPercent(pt)
    if pt ~= RP.STAGGER then return nil end
    local PD = C_PaperDollInfo
    local p = PD and PD.GetStaggerPercentage and PD.GetStaggerPercentage("player")
    if not Plain(p) then return nil end
    return p
end

-- the threshold curve's colour for a pseudo power, from the plain percent (the
-- curve would refuse a secret input)
function RP.CurveColor(pt, curve)
    local p = RP.PlainPercent(pt)
    if not p then return nil end
    return curve:Evaluate(math.max(0, math.min(1, p / 100)))
end

function RP.PercentText(pt)
    local p = RP.PlainPercent(pt)
    if not p then return nil end
    return string.format("%d%%", math.floor(p + 0.5))
end

-- Availability

function RP.Brewmaster()
    if NS.IsForever == true then return false end
    local _, tag = UnitClass("player")
    if tag ~= "MONK" then return false end
    return SpecID() == 268
end

-- true / false: whether this character has the power (a plain max above 0;
-- stagger: a Brewmaster). nil = a secret max, unknown.
function RP.Has(pt, plainMax)
    if pt == RP.STAGGER then return RP.Brewmaster() end
    if plainMax == nil then
        local v = UnitPowerMax("player", pt)
        if not Plain(v) then return nil end
        plainMax = v
    end
    return plainMax > 0
end

-- A retail power the character lacks (a record synced from another class or
-- client) keeps its bar hidden; the classic powers keep their empty bar.
function RP.Missing(pt, plainMax)
    local info = Bars.POWER_ALL[pt]
    if not info or info.classic then return false end
    return RP.Has(pt, plainMax) == false
end

-- What the picker offers on retail: every power the character has now, the
-- class's primary powers and the spec's own. nil on Forever, whose fixed list
-- stays as it is.
function RP.Offered()
    if NS.IsForever == true then return nil end
    local out = {}
    for id, info in pairs(Bars.POWER_ALL) do
        if not info.legacy and RP.Has(id) == true then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- Runes: each pips cell is one rune. A ready rune fills its cell, a recharging
-- one runs the engine's timer fill from GetRuneCooldown's start and duration
-- (plain on every client) through a duration object; a secret answer leaves
-- the cell empty rather than guessing. The generic count feed skips these cells.

function RP.OwnsPips(entry)
    return entry.powerType == RP.RUNES and entry.pipsOn == true and not entry.isPreview
end

local function RuneKey(start, duration, ready)
    if issecretvalue and (issecretvalue(ready) or issecretvalue(start) or issecretvalue(duration)) then
        return "E"
    end
    if ready == true then return "R" end
    if Plain(start) and Plain(duration) and start > 0 and duration > 0 then
        return string.format("T%.3f/%.3f", start, duration), start, duration
    end
    return "E"
end

function RP.FeedRunes(entry)
    if not RP.OwnsPips(entry) or not GetRuneCooldown then return end
    local smooth = K.R(entry.rec, "fill", "smoothing") ~= false
    for i = 1, entry.pipCount or 0 do
        local p = entry.pips[i]
        if p then
            local key, start, duration = RuneKey(GetRuneCooldown(i))
            if p.runeKey ~= key or p.runeSmooth ~= smooth then
                p.runeKey, p.runeSmooth = key, smooth
                local lb = p.litBar
                if key == "R" or key == "E" then
                    lb:SetMinMaxValues(0, 1)      -- also releases a running timer
                    lb:SetValue(key == "R" and 1 or 0)
                else
                    entry.runeDur = entry.runeDur or {}
                    local d = entry.runeDur[i]
                    if not d and C_DurationUtil and C_DurationUtil.CreateDuration then
                        d = C_DurationUtil.CreateDuration()
                        entry.runeDur[i] = d
                    end
                    if d and d.SetTimeFromStart then d:SetTimeFromStart(start, duration) end
                    if not (d and K.FeedStatusBarTimer(lb, d, smooth, false)) then
                        lb:SetMinMaxValues(0, 1)
                        lb:SetValue(0)
                    end
                end
            end
        end
    end
end

-- Essence: the point regenerating fills its cell, a layer under the lit bar.
-- Which cell that is comes from the count without a compare: each layer's
-- alpha is a step curve of the power percent evaluated by UnitPowerPercent
-- (plain or secret, SetAlpha takes both), 1 only while the count sits at that
-- cell minus one. The fill has two paths. Open (C_Secrets says the reads are
-- plain): the engine's timer from UnitPartialPower's fraction and the regen
-- rate, no polling at all. Restricted: UnitPartialPower is a secret, so an
-- 8 Hz ticker hands it to SetValue and the client's interpolation smooths the
-- steps; the ticker lives only while a shown essence bar needs it.
local INTERP_SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local ESS_TICK = 0.125
local essTicker, essIdle = nil, 0
local essGates = {}
local EssSync

local function EssRestricted()
    local CS = C_Secrets
    if not (CS and CS.ShouldUnitPowerBeSecret) then return false end
    local s = CS.ShouldUnitPowerBeSecret("player", RP.ESSENCE)
    -- a secret answer means the restriction is on (Forever hands one out)
    if issecretvalue and issecretvalue(s) then return true end
    return s == true
end

-- the alpha curve of cell i of n: 1 while the count is i-1, the edges half a
-- point away from any count the client can report
local function EssGate(i, n)
    local key = i .. "/" .. n
    local c = essGates[key]
    if c then return c end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    c = C_CurveUtil.CreateCurve()
    local EPS = 0.0001
    local lo, hi = (i - 1.5) / n, (i - 0.5) / n
    if lo > 0 then
        c:AddPoint(0, 0)
        c:AddPoint(lo - EPS, 0)
        c:AddPoint(lo, 1)
    else
        c:AddPoint(0, 1)
    end
    c:AddPoint(hi - EPS, 1)
    c:AddPoint(hi, 0)
    c:AddPoint(1, 0)
    essGates[key] = c
    return c
end

local function EnsureEss(p)
    local ess = p.essBar
    if ess then return ess end
    local f = p.f
    ess = CreateFrame("StatusBar", nil, f)
    ess:SetFrameLevel(f:GetFrameLevel() + 1)
    p.litBar:SetFrameLevel(f:GetFrameLevel() + 2)   -- a lit cell covers its filling layer
    ess:SetAllPoints(p.litBar)
    ess:SetMinMaxValues(0, 1000)
    ess:SetValue(0)
    ess:SetAlpha(0)
    p.essBar = ess
    p.essMask = ess:CreateMaskTexture()
    return ess
end

-- the lit cell's texture, direction and shape, re-run after every LayoutPips
local function StyleEss(entry, p)
    local rec = entry.rec
    local ess = EnsureEss(p)
    local vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    ess:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    ess:SetReverseFill(K.R(rec, "fill", "reverseFill") == true)
    local path = K.ResolveBarTexture(K.R(rec, "fill", "texture"))
    if p.essPath ~= path then
        p.essPath = path
        ess:SetStatusBarTexture(path)
    end
    local shape = K.R(rec, "resource", "pipShape") or "square"
    local rot = (shape == "diamond") and (math.pi / 4) or 0
    -- a texture swap makes a new object: the mask goes on whatever is current
    local tex = ess:GetStatusBarTexture()
    if p.essTex ~= tex then
        p.essTex = tex
        tex:AddMaskTexture(p.essMask)
    end
    tex:SetRotation(rot)
    local m = p.essMask
    m:SetTexture((shape == "circle") and Bars.PIP_CIRCLE_MASK or K.WHITE,
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", (shape == "square") and "NEAREST" or "LINEAR")
    m:ClearAllPoints()
    m:SetRotation(rot)
    m:SetAllPoints(p.maskLit)
end

local function PaintEss(entry, p)
    local r, g, b, a = entry.cr, entry.cg, entry.cb, entry.ca
    if r == nil then return end
    if p.essR == r and p.essG == g and p.essB == b and p.essA == a then return end
    p.essR, p.essG, p.essB, p.essA = r, g, b, a
    p.essBar:SetStatusBarColor(r, g, b, a or 1)
end

-- "S" holds a fraction (the restricted path, a paused regen), "E" is empty;
-- the range write also releases a running timer
local function EssMode(p, ess, mode)
    if p.essMode == mode then return end
    p.essMode = mode
    ess:SetMinMaxValues(0, 1000)
    if mode == "E" then ess:SetValue(0) end
end

local function EssValue(ess, v)
    if INTERP_SMOOTH then ess:SetValue(v, INTERP_SMOOTH) else ess:SetValue(v) end
end

function RP.FeedEssence(entry)
    if entry.isPreview or entry.powerType ~= RP.ESSENCE or not entry.pipsOn then return end
    local n = entry.pipCount or 0
    if n == 0 or not (UnitPartialPower and entry.pips) then return end
    local partial = UnitPartialPower("player", RP.ESSENCE)
    if partial == nil then return end
    local restricted = EssRestricted()
    local cur, rate, second
    if not restricted then
        cur = UnitPower("player", RP.ESSENCE)
        if GetPowerRegenForPowerType then rate, second = GetPowerRegenForPowerType(RP.ESSENCE) end
        -- a secret answer on the open path: this pass takes the restricted one
        if not (Plain(cur) and Plain(partial))
            or (issecretvalue and (issecretvalue(rate) or issecretvalue(second))) then
            restricted = true
        end
    end
    entry.essRestricted = restricted
    local smooth = K.R(entry.rec, "fill", "smoothing") ~= false
    for i = 1, n do
        local p = entry.pips[i]
        if p then
            local ess = EnsureEss(p)
            PaintEss(entry, p)
            if restricted then
                local alpha = 0
                local gate = UnitPowerPercent and EssGate(i, n)
                if gate then alpha = UnitPowerPercent("player", RP.ESSENCE, false, gate) end
                ess:SetAlpha(alpha)
                EssMode(p, ess, "S")
                EssValue(ess, partial)
            elseif i ~= cur + 1 then
                ess:SetAlpha(0)
                EssMode(p, ess, "E")
            elseif second == true then
                -- regen paused: the fraction stands still
                ess:SetAlpha(1)
                EssMode(p, ess, "S")
                ess:SetValue(partial)
            else
                ess:SetAlpha(1)
                local r = (Plain(rate) and rate > 0) and rate or 0.2
                local duration = 1 / r
                local start = GetTime() - (partial / 1000) * duration
                local endT = start + duration
                -- the same end and length within a hair: the timer already runs it
                if p.essMode ~= "T" or math.abs((p.essEnd or 0) - endT) > 0.02
                    or math.abs((p.essLen or 0) - duration) > 0.001 then
                    p.essMode, p.essEnd, p.essLen = "T", endT, duration
                    entry.essDur = entry.essDur or {}
                    local d = entry.essDur[i]
                    if not d and C_DurationUtil and C_DurationUtil.CreateDuration then
                        d = C_DurationUtil.CreateDuration()
                        entry.essDur[i] = d
                    end
                    if d and d.SetTimeFromStart then d:SetTimeFromStart(start, duration) end
                    if not (d and K.FeedStatusBarTimer(ess, d, smooth, false)) then
                        -- no timer engine: the fraction as it stands
                        p.essMode = "S"
                        ess:SetMinMaxValues(0, 1000)
                        ess:SetValue(partial)
                    end
                end
            end
        end
    end
    EssSync()
end

-- the restricted path's tick: one read, every "S" cell of every shown bar
local function EssTick()
    local partial = UnitPartialPower and UnitPartialPower("player", RP.ESSENCE)
    local fed = false
    if partial ~= nil then
        K.ForEach("resource", function(e)
            if e.powerType == RP.ESSENCE and e.pipsOn and e.essRestricted and not e.stateHidden
                and not (NS.Conditions and NS.Conditions.AlphaFor and NS.Conditions.AlphaFor(e.rec) <= 0) then
                for i = 1, e.pipCount or 0 do
                    local p = e.pips[i]
                    if p and p.essBar and p.essMode == "S" then
                        fed = true
                        EssValue(p.essBar, partial)
                    end
                end
            end
        end)
    end
    -- nothing shown for a second: the ticker stops; the next power event restarts it
    if fed then essIdle = 0 else essIdle = essIdle + 1 end
    if essIdle >= 8 and essTicker then
        essTicker:Cancel()
        essTicker = nil
    end
end

function EssSync()
    local want = false
    K.ForEach("resource", function(e)
        if e.powerType == RP.ESSENCE and e.pipsOn and e.essRestricted and not e.stateHidden then want = true end
    end)
    if want and not essTicker then
        if C_Timer and C_Timer.NewTicker then
            essIdle = 0
            essTicker = C_Timer.NewTicker(ESS_TICK, EssTick)
        end
    elseif not want and essTicker then
        essTicker:Cancel()
        essTicker = nil
    end
end

-- the rate moved, or the restriction may have: every essence bar re-decides
local function EssRecheck()
    K.ForEach("resource", function(e)
        if e.powerType == RP.ESSENCE and e.pipsOn then RP.FeedEssence(e) end
    end)
end

-- harness access
function RP.EssTicker() return essTicker end

-- after LayoutPips: the layout re-windows every cell, so the runes feed
-- again; the essence layers take the cells' new dress
function RP.PipsLaid(entry)
    if entry.isPreview then return end
    if RP.OwnsPips(entry) then
        for _, p in ipairs(entry.pips or {}) do p.runeKey = nil end
        RP.FeedRunes(entry)
    elseif entry.powerType == RP.ESSENCE and entry.pipsOn then
        for i = 1, entry.pipCount or 0 do
            local p = entry.pips[i]
            if p then StyleEss(entry, p) end
        end
        RP.FeedEssence(entry)
    end
end

-- the per-refresh hook at the end of ResourceRefresh
function RP.Refresh(entry)
    RP.FeedRunes(entry)
    RP.FeedEssence(entry)
end

-- Events, armed only while a rune or stagger bar lives (own key). Rune changes
-- come with RUNE_POWER_UPDATE, whose payload is secret and never read: every
-- rune is re-read. Stagger moves with health (each staggered hit and tick) and
-- with its aura (a purify, the expiry), so it rides the player's UNIT_HEALTH,
-- UNIT_MAXHEALTH and UNIT_AURA, the aura bursts folded into one refresh.
local armed = {}
local KEY = "adbarsrp"

local function Refresh(pt, bustMax)
    K.ForEach("resource", function(e)
        if e.powerType == pt then
            if bustMax then e.lastMax = nil end
            K.ResourceRefresh(e)
        end
    end)
end

local function Need()
    local runes, stagger, essence = false, false, false
    K.ForEach("resource", function(e)
        if e.powerType == RP.RUNES then runes = true end
        if e.powerType == RP.STAGGER then stagger = true end
        if e.powerType == RP.ESSENCE and e.pipsOn then essence = true end
    end)
    return runes, stagger, essence
end

-- the essence timer follows haste, and the open / restricted choice follows
-- the place and combat (PLAYER_ENTERING_WORLD already refreshes every bar)
local ESS_EVENTS = { "UNIT_SPELL_HASTE", "UNIT_STATS", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA" }

local function EssEvent(_, unit)
    if unit ~= nil and unit ~= "player" then return end
    EssRecheck()
end

local function StaggerAura(_, unit)
    if unit ~= "player" then return end
    if NS.Events.Coalesce then
        NS.Events.Coalesce("adbarsrp_stagger", function() Refresh(RP.STAGGER, false) end)
    else
        Refresh(RP.STAGGER, false)
    end
end

function RP.Sync()
    local runes, stagger, essence = Need()
    if essence and not armed.essence then
        armed.essence = true
        for _, ev in ipairs(ESS_EVENTS) do K.SafeOn(ev, KEY, EssEvent) end
    elseif not essence and armed.essence then
        armed.essence = false
        for _, ev in ipairs(ESS_EVENTS) do NS.Events.Off(ev, KEY) end
    end
    if runes and not armed.runes then
        armed.runes = true
        K.SafeOn("RUNE_POWER_UPDATE", KEY, function() Refresh(RP.RUNES, false) end)
    elseif not runes and armed.runes then
        armed.runes = false
        NS.Events.Off("RUNE_POWER_UPDATE", KEY)
    end
    if stagger and not armed.stagger then
        armed.stagger = true
        K.SafeOn("UNIT_HEALTH", KEY, function(_, unit)
            if unit == "player" then Refresh(RP.STAGGER, false) end
        end)
        K.SafeOn("UNIT_MAXHEALTH", KEY, function(_, unit)
            if unit == "player" then Refresh(RP.STAGGER, true) end
        end)
        K.SafeOn("UNIT_AURA", KEY, StaggerAura)
    elseif not stagger and armed.stagger then
        armed.stagger = false
        NS.Events.Off("UNIT_HEALTH", KEY)
        NS.Events.Off("UNIT_MAXHEALTH", KEY)
        NS.Events.Off("UNIT_AURA", KEY)
    end
end

-- after Bars.Release took the entry out of `live`
function RP.Release(entry)
    for _, p in ipairs(entry.pips or {}) do p.runeKey, p.essMode = nil, nil end
    entry.essRestricted = nil
    RP.Sync()
    EssSync()
end

-- harness access
RP._armed = armed
