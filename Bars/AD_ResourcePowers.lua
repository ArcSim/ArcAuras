-- Resource powers: the retail power types on the resource bar (holy power, chi,
-- arcane charges, astral power, maelstrom, insanity, fury, essence, soul shards,
-- runes, stagger, Maelstrom Weapon, soul fragments) and which powers this
-- character can pick. The resource runtime in Bars\AD_Bars.lua asks it at fixed
-- points through Bars.ResPowers; it arms its own events only while a bar that
-- needs them lives. Power values can be secret: each goes straight into a
-- sink; only plain maxima and times compare.
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
-- Class resources the game keeps as an aura or a spell's count, pseudo ids
-- like stagger. Blizzard leaves these readable by spell ID; the value still
-- only ever reaches sinks.
RP.MSW = 101          -- Enhancement's Maelstrom Weapon stacks
RP.FRAGMENTS = 102    -- Vengeance's soul fragments: Soul Cleave's count
RP.DEVOURER = 103     -- Devourer's soul fragments: Dark Heart, or Silence the Whispers in Void Metamorphosis

-- the spec each aura-held resource belongs to
RP.SPEC_OF = { [101] = 263, [102] = 581, [103] = 1480 }

local UPI = Constants and Constants.UnitPowerSpellIDs or {}
local SPELL = {
    msw = 344179, soulCleave = 228477, fragments = 203981, glutton = 1247534,
    darkHeart = UPI.DARK_HEART_SPELL_ID or 1225789,
    whispers = UPI.SILENCE_THE_WHISPERS_SPELL_ID or 1227702,
    voidMeta = UPI.VOID_METAMORPHOSIS_SPELL_ID or 1217607,
}
RP.SPELL = SPELL

-- The point powers and the cell count a bar lays out before a plain max has
-- been read (a login under restriction, the editor preview).
RP.POINT_MAX = { [4] = 5, [5] = 6, [7] = 5, [9] = 5, [12] = 5, [16] = 4, [19] = 5, [101] = 10, [102] = 6 }

-- Rune cells take the spec's colour, as the rune art does.
RP.RUNE_COLORS = { [250] = { 0.77, 0.12, 0.23 }, [251] = { 0.2, 0.6, 1 }, [252] = { 0, 0.8, 0.2 } }
-- Devourer's bar turns blue in Void Metamorphosis, as Blizzard's does.
RP.META_COLOR = { 0.11, 0.34, 0.71 }

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

-- Restricted content hides an aura that is not NeverSecret: the lookup's nil
-- then means unknown, not gone.
local function AuraHidden(spellID)
    local S = C_Secrets
    if not (S and S.ShouldAurasBeSecret) then return false end
    local v = S.ShouldAurasBeSecret()
    if not ((issecretvalue and issecretvalue(v)) or v == true) then return false end
    return not (S.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel
        and S.GetSpellAuraSecrecy(spellID) == Enum.SecrecyLevel.NeverSecret)
end

-- the stack count of one of your auras: 0 when it is gone, nil when it is
-- unknown (hidden, or handed back secret: its fields cannot be read then)
local function AuraStacks(spellID)
    local UA = C_UnitAuras
    local a = UA and UA.GetPlayerAuraBySpellID and UA.GetPlayerAuraBySpellID(spellID)
    if a == nil then
        if AuraHidden(spellID) then return nil end
        return 0
    end
    if issecretvalue and issecretvalue(a) then return nil end
    local n = a.applications
    if n == nil then return 0 end
    return n
end

-- a presence test only, so a secret aura still counts as there
local function InVoidMeta()
    local UA = C_UnitAuras
    if not (UA and UA.GetPlayerAuraBySpellID) then return false end
    return UA.GetPlayerAuraBySpellID(SPELL.voidMeta) ~= nil
end

local function MaxStacks(spellID)
    local f = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
    local m = f and f(spellID)
    if Plain(m) and m > 0 then return m end
    return nil
end

-- Devourer's cap when the game's answer is secret: Soul Glutton lowers it
local function DevourerFallback()
    local SB = C_SpellBook
    local known
    if SB and SB.IsSpellKnown then known = SB.IsSpellKnown(SPELL.glutton)
    elseif IsPlayerSpell then known = IsPlayerSpell(SPELL.glutton) end
    return (known == true) and 35 or 50
end

function RP.IsPoint(pt) return RP.POINT_MAX[pt] ~= nil end

-- no Enum.PowerType: UnitPower, UnitPowerMax and UnitPowerPercent never see it
function RP.Pseudo(pt) return pt ~= nil and pt >= RP.STAGGER end

-- the powers whose value this file reads instead of a plain UnitPower
function RP.Owns(pt) return pt == RP.SHARDS or RP.Pseudo(pt) end

function RP.FallbackMax(pt)
    if pt == RP.STAGGER then return 100 end
    if pt == RP.DEVOURER then return DevourerFallback() end
    return RP.POINT_MAX[pt]
end

-- The fill value. Shards come unmodified (tenths), so a Destruction cell fills
-- part way; every warlock spec reads whole tens or tenths on the same scale.
function RP.Current(pt)
    if pt == RP.SHARDS then return UnitPower("player", RP.SHARDS, true) end
    if pt == RP.STAGGER then return UnitStagger and UnitStagger("player") or 0 end
    if pt == RP.MSW then return AuraStacks(SPELL.msw) end
    if pt == RP.FRAGMENTS then
        if not (C_Spell and C_Spell.GetSpellCastCount) then return 0 end
        return C_Spell.GetSpellCastCount(SPELL.soulCleave)
    end
    if pt == RP.DEVOURER then
        return AuraStacks(InVoidMeta() and SPELL.whispers or SPELL.darkHeart)
    end
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

-- the maximum: stagger runs against the player's health, plain for the player;
-- the aura-held ones take the game's stack cap, else their fixed count
function RP.Max(pt)
    if pt == RP.STAGGER then return UnitHealthMax("player") end
    if pt == RP.MSW then return MaxStacks(SPELL.msw) or RP.POINT_MAX[pt] end
    if pt == RP.FRAGMENTS then return RP.POINT_MAX[pt] end
    if pt == RP.DEVOURER then
        if InVoidMeta() then
            local c = GetCollapsingStarCost and GetCollapsingStarCost()
            if Plain(c) and c > 0 then return c end
        end
        return MaxStacks(SPELL.darkHeart) or DevourerFallback()
    end
    return UnitPowerMax("player", pt)
end

function RP.Color(pt)
    if pt == RP.DEVOURER and InVoidMeta() then
        local c = RP.META_COLOR
        return c[1], c[2], c[3]
    end
    if pt ~= RP.RUNES then return nil end
    local c = RP.RUNE_COLORS[SpecID() or 0]
    if c then return c[1], c[2], c[3] end
    return nil
end

-- The percent Lua may read, for the colour curve and the percent text: stagger's
-- of health (GetStaggerPercentage carries no secrecy on any client), an
-- aura-held count over its cap while both read plain. Vengeance falls back to
-- its aura's stacks when Soul Cleave's count is secret.
function RP.PlainPercent(pt)
    if pt == RP.STAGGER then
        local PD = C_PaperDollInfo
        local p = PD and PD.GetStaggerPercentage and PD.GetStaggerPercentage("player")
        if not Plain(p) then return nil end
        return p
    end
    if not RP.SPEC_OF[pt] then return nil end
    local cur, max = RP.Current(pt), RP.Max(pt)
    if pt == RP.FRAGMENTS and not Plain(cur) then cur = AuraStacks(SPELL.fragments) end
    if not (Plain(cur) and Plain(max) and max > 0) then return nil end
    return math.min(100, cur / max * 100)
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
-- stagger: a Brewmaster; an aura-held one: its spec). nil = a secret max, unknown.
function RP.Has(pt, plainMax)
    if pt == RP.STAGGER then return RP.Brewmaster() end
    local spec = RP.SPEC_OF[pt]
    if spec then return NS.IsForever ~= true and SpecID() == spec end
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

-- Destruction's shards read in tenths ("3.4"), as Blizzard's bar shows them.
-- The client scales the unmodified percent to shards C-side and the font
-- string formats it, so a secret count never reaches Lua.
local shardCurves = {}

function RP.Decimal(entry)
    return entry.powerType == RP.SHARDS and NS.IsForever ~= true and SpecID() == 267
        and K.R(entry.rec, "text", "resWholeShards") ~= true
end

-- true when it wrote the text (or the text is hidden); false: no plain cap or
-- no reading yet, so the caller writes whole shards instead
function RP.ShardText(fs, max, withMax)
    if not (fs and UnitPowerPercent and C_CurveUtil and C_CurveUtil.CreateCurve) then return false end
    if not (Plain(max) and max > 0) then return false end
    local c = shardCurves[max]
    if not c then
        c = C_CurveUtil.CreateCurve()
        c:AddPoint(0, 0)
        c:AddPoint(1, max)
        shardCurves[max] = c
    end
    local v = UnitPowerPercent("player", RP.SHARDS, true, c)
    if v == nil then return false end
    if not fs:IsShown() then return true end
    if withMax then fs:SetFormattedText("%.1f / %d", v, max) else fs:SetFormattedText("%.1f", v) end
    return true
end

-- Runes: each cell (pips) or stretch of the bar (bar style, Bars\AD_ResourceCells.lua)
-- is one rune, in Blizzard's order unless the bar keeps rune i in cell i:
-- ready runes first, then the soonest back. A ready rune fills its cell, a
-- recharging one runs the engine's timer fill from GetRuneCooldown's start and
-- duration (plain on every client) through a duration object, and its
-- countdown rides the same object; a secret answer leaves the cell empty
-- rather than guessing, and sorts last. The generic count feed skips pips cells.

function RP.OwnsPips(entry)
    return entry.powerType == RP.RUNES and entry.pipsOn == true and not entry.isPreview
end

-- the cells a rune or essence bar feeds: its pips, or its bar-style slots
local function Cells(entry)
    if entry.isPreview then return nil, 0 end
    if entry.pipsOn then return entry.pips, entry.pipCount or 0 end
    if entry.rsOn then return entry.rslots, entry.rsCount or 0 end
    return nil, 0
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

-- The recharge shade (Bars\AD_ResourceCells.lua): the bar's own recharge
-- colour, else the cell's lit colour (PaintPips keeps it as p.pr..p.pa) at
-- half brightness.
function RP.RechargeColor(entry, c)
    return Bars.ResCells.RechargeColor(entry, c)
end

-- each rune cell wears the recharge shade while its timer runs
function RP.TintRunes(entry)
    if entry.powerType ~= RP.RUNES then return end
    local cells, n = Cells(entry)
    if not cells then return end
    for i = 1, n do
        local c = cells[i]
        if c and c.pr ~= nil and c.rbar then
            local want = c.runeKey ~= nil and c.runeKey:sub(1, 1) == "T"
            if c.tinted ~= want then
                c.tinted = want
                if want then
                    local r, g, b, a = RP.RechargeColor(entry, c)
                    c.rbar:SetStatusBarColor(r, g, b, a)
                else
                    c.rbar:SetStatusBarColor(c.pr, c.pg, c.pb, c.pa)
                end
            end
        end
    end
end

local RUNE_RANK = { R = 3, T = 2, E = 1 }
local function RuneBefore(a, b)
    if a.rank ~= b.rank then return a.rank > b.rank end
    if a.start and b.start and a.start ~= b.start then return a.start < b.start end
    return a.i < b.i
end
local runeReads, runeOrder = {}, {}

function RP.FeedRunes(entry)
    if entry.powerType ~= RP.RUNES or not GetRuneCooldown then return end
    local cells, n = Cells(entry)
    if not cells then return end
    local RC = Bars.ResCells
    local smooth = K.R(entry.rec, "fill", "smoothing") ~= false
    local drain = RC.Drain(entry)
    for i = 1, n do
        local rd = runeReads[i] or {}
        runeReads[i] = rd
        rd.i = i
        rd.key, rd.start, rd.duration = RuneKey(GetRuneCooldown(i))
        rd.rank = RUNE_RANK[rd.key:sub(1, 1)]
        runeOrder[i] = rd
    end
    for i = n + 1, #runeOrder do runeOrder[i] = nil end
    if K.R(entry.rec, "resource", "runeOrder") ~= "fixed" then table.sort(runeOrder, RuneBefore) end
    for i = 1, n do
        local c = cells[i]
        local rd = runeOrder[i]
        if c and rd and c.rbar then
            local key, start, duration = rd.key, rd.start, rd.duration
            if c.runeKey ~= key or c.runeSmooth ~= smooth or c.runeDrain ~= drain then
                c.runeKey, c.runeSmooth, c.runeDrain = key, smooth, drain
                local lb = c.rbar
                if key == "R" or key == "E" then
                    lb:SetMinMaxValues(0, 1)      -- also releases a running timer
                    lb:SetValue(key == "R" and 1 or 0)
                    RC.Text(entry, c, nil)
                else
                    local d = RC.Dur(entry, "runeDur", i)
                    if d and d.SetTimeFromStart then d:SetTimeFromStart(start, duration) end
                    if not (d and K.FeedStatusBarTimer(lb, d, smooth, drain)) then
                        lb:SetMinMaxValues(0, 1)
                        lb:SetValue(0)
                    end
                    RC.Text(entry, c, d)
                end
            end
        end
    end
    RP.TintRunes(entry)
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

-- the lit cell's texture, shape and the recharge direction, re-run after every LayoutPips
local function StyleEss(entry, p)
    Bars.ResCells.StyleLayer(entry, p, EnsureEss(p), "essMask", true)
end

-- the essence layer of a cell: a pips cell's own, a bar-style slot's bar
local function EssLayer(entry, c)
    if entry.pipsOn then return c.essBar end
    return c.bar
end

-- the filling cell wears the recharge shade, as a recharging rune does
local function PaintEss(entry, c, ess)
    local r, g, b, a = RP.RechargeColor(entry, c)
    if r == nil then return end
    if c.essR == r and c.essG == g and c.essB == b and c.essA == a then return end
    c.essR, c.essG, c.essB, c.essA = r, g, b, a
    ess:SetStatusBarColor(r, g, b, a or 1)
end

-- "S" holds a fraction (the restricted path, a paused regen), "E" is empty;
-- the range write also releases a running timer, and the countdown goes
local function EssMode(entry, c, ess, mode)
    if c.essMode == mode then return end
    c.essMode = mode
    ess:SetMinMaxValues(0, 1000)
    if mode == "E" then ess:SetValue(0) end
    Bars.ResCells.Text(entry, c, nil)
end

local function EssValue(ess, v)
    if INTERP_SMOOTH then ess:SetValue(v, INTERP_SMOOTH) else ess:SetValue(v) end
end

function RP.FeedEssence(entry)
    if entry.powerType ~= RP.ESSENCE then return end
    local cells, n = Cells(entry)
    if not cells or n == 0 or not UnitPartialPower then return end
    local partial = UnitPartialPower("player", RP.ESSENCE)
    if partial == nil then return end
    local RC = Bars.ResCells
    local drain = RC.Drain(entry)
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
        local c = cells[i]
        local ess = c and (entry.pipsOn and EnsureEss(c) or c.bar)
        if ess then
            PaintEss(entry, c, ess)
            if restricted then
                -- no plain fraction or rate: no timer, so no countdown either
                local alpha = 0
                local gate = UnitPowerPercent and EssGate(i, n)
                if gate then alpha = UnitPowerPercent("player", RP.ESSENCE, false, gate) end
                ess:SetAlpha(alpha)
                EssMode(entry, c, ess, "S")
                EssValue(ess, partial)
            elseif i ~= cur + 1 then
                ess:SetAlpha(0)
                EssMode(entry, c, ess, "E")
            elseif second == true then
                -- regen paused: the fraction stands still
                ess:SetAlpha(1)
                EssMode(entry, c, ess, "S")
                ess:SetValue(partial)
            else
                ess:SetAlpha(1)
                local r = (Plain(rate) and rate > 0) and rate or 0.2
                local duration = 1 / r
                local start = GetTime() - (partial / 1000) * duration
                local endT = start + duration
                -- the same end and length within a hair: the timer already runs it
                if c.essMode ~= "T" or c.essDrain ~= drain or math.abs((c.essEnd or 0) - endT) > 0.02
                    or math.abs((c.essLen or 0) - duration) > 0.001 then
                    c.essMode, c.essEnd, c.essLen, c.essDrain = "T", endT, duration, drain
                    local d = RC.Dur(entry, "essDur", i)
                    if d and d.SetTimeFromStart then d:SetTimeFromStart(start, duration) end
                    if d and K.FeedStatusBarTimer(ess, d, smooth, drain) then
                        RC.Text(entry, c, d)
                    else
                        -- no timer engine: the fraction as it stands
                        c.essMode = "S"
                        ess:SetMinMaxValues(0, 1000)
                        ess:SetValue(partial)
                        RC.Text(entry, c, nil)
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
            if e.powerType == RP.ESSENCE and e.essRestricted and not e.stateHidden
                and not (NS.Conditions and NS.Conditions.AlphaFor and NS.Conditions.AlphaFor(e.rec) <= 0) then
                local cells, n = Cells(e)
                for i = 1, n do
                    local c = cells[i]
                    local ess = c and EssLayer(e, c)
                    if ess and c.essMode == "S" then
                        fed = true
                        EssValue(ess, partial)
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
        if e.powerType == RP.ESSENCE and (e.pipsOn or e.rsOn) and e.essRestricted and not e.stateHidden then want = true end
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
        if e.powerType == RP.ESSENCE and (e.pipsOn or e.rsOn) then RP.FeedEssence(e) end
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

-- after the bar-style slots were laid (Bars\AD_ResourceCells.lua): every slot
-- is fed afresh, and the events follow the slots coming or going
function RP.SlotsLaid(entry)
    if entry.isPreview then return end
    for _, s in ipairs(entry.rslots or {}) do
        s.runeKey, s.essMode, s.tinted, s.essR = nil, nil, nil, nil
    end
    RP.FeedRunes(entry)
    RP.FeedEssence(entry)
    RP.Sync()
end

-- the per-refresh hook at the end of ResourceRefresh
function RP.Refresh(entry)
    RP.FeedRunes(entry)
    RP.FeedEssence(entry)
end

-- Events, armed only while a bar needs them (own key). Rune changes come with
-- RUNE_POWER_UPDATE, whose payload is secret and never read: every rune is
-- re-read. Stagger moves with health (each staggered hit and tick) and with
-- its aura (a purify, the expiry), so it rides the player's UNIT_HEALTH,
-- UNIT_MAXHEALTH and UNIT_AURA. The aura-held resources ride the player's
-- UNIT_AURA too, Vengeance also SPELL_UPDATE_USES (Soul Cleave's count); the
-- bursts fold into one refresh and no payload is read.
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
    local need = {}
    K.ForEach("resource", function(e)
        local pt = e.powerType
        if pt == RP.RUNES then need.runes = true end
        if pt == RP.STAGGER then need.stagger = true end
        if pt == RP.ESSENCE and (e.pipsOn or e.rsOn) then need.essence = true end
        if RP.SPEC_OF[pt] then need.auras = true end
        if pt == RP.FRAGMENTS then need.uses = true end
    end)
    return need
end

-- every bar the player's auras move: stagger and the aura-held resources
local function RefreshAuraBars()
    K.ForEach("resource", function(e)
        local pt = e.powerType
        if (pt == RP.STAGGER and armed.stagger) or RP.SPEC_OF[pt] then K.ResourceRefresh(e) end
    end)
end

local function Later(key, fn)
    if NS.Events.Coalesce then NS.Events.Coalesce(key, fn) else fn() end
end

-- the essence timer follows haste, and the open / restricted choice follows
-- the place and combat (PLAYER_ENTERING_WORLD already refreshes every bar)
local ESS_EVENTS = { "UNIT_SPELL_HASTE", "UNIT_STATS", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA" }

local function EssEvent(_, unit)
    if unit ~= nil and unit ~= "player" then return end
    EssRecheck()
end

-- a secret unit token cannot be compared: it may be the player's
local function AuraEvent(_, unit)
    if not (issecretvalue and issecretvalue(unit)) and unit ~= "player" then return end
    Later("adbarsrp_aura", RefreshAuraBars)
end

local function UsesEvent()
    Later("adbarsrp_uses", function() Refresh(RP.FRAGMENTS, false) end)
end

function RP.Sync()
    local need = Need()
    if need.essence and not armed.essence then
        armed.essence = true
        for _, ev in ipairs(ESS_EVENTS) do K.SafeOn(ev, KEY, EssEvent) end
    elseif not need.essence and armed.essence then
        armed.essence = false
        for _, ev in ipairs(ESS_EVENTS) do NS.Events.Off(ev, KEY) end
    end
    if need.runes and not armed.runes then
        armed.runes = true
        K.SafeOn("RUNE_POWER_UPDATE", KEY, function() Refresh(RP.RUNES, false) end)
    elseif not need.runes and armed.runes then
        armed.runes = false
        NS.Events.Off("RUNE_POWER_UPDATE", KEY)
    end
    if need.stagger and not armed.stagger then
        armed.stagger = true
        K.SafeOn("UNIT_HEALTH", KEY, function(_, unit)
            if unit == "player" then Refresh(RP.STAGGER, false) end
        end)
        K.SafeOn("UNIT_MAXHEALTH", KEY, function(_, unit)
            if unit == "player" then Refresh(RP.STAGGER, true) end
        end)
    elseif not need.stagger and armed.stagger then
        armed.stagger = false
        NS.Events.Off("UNIT_HEALTH", KEY)
        NS.Events.Off("UNIT_MAXHEALTH", KEY)
    end
    local aura = need.stagger or need.auras
    if aura and not armed.aura then
        armed.aura = true
        K.SafeOn("UNIT_AURA", KEY, AuraEvent)
    elseif not aura and armed.aura then
        armed.aura = false
        NS.Events.Off("UNIT_AURA", KEY)
    end
    if need.uses and not armed.uses then
        armed.uses = true
        K.SafeOn("SPELL_UPDATE_USES", KEY, UsesEvent)
    elseif not need.uses and armed.uses then
        armed.uses = false
        NS.Events.Off("SPELL_UPDATE_USES", KEY)
    end
    -- charged points and Blizzard's own bar follow the same bars
    if Bars.ResCells then Bars.ResCells.Sync() end
end

-- after Bars.Release took the entry out of `live`
function RP.Release(entry)
    for _, p in ipairs(entry.pips or {}) do p.runeKey, p.essMode, p.tinted = nil, nil, nil end
    for _, s in ipairs(entry.rslots or {}) do s.runeKey, s.essMode, s.tinted = nil, nil, nil end
    entry.essRestricted = nil
    if Bars.ResCells then Bars.ResCells.Release(entry) end
    RP.Sync()
    EssSync()
end

-- harness access
RP._armed = armed
