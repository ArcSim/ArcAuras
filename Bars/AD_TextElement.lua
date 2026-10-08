-- Arc Auras, all rights reserved: do not copy or adapt this code into another addon without permission.
-- Text elements (barKind "text"): one line of text in a box, fed by the source
-- the player picks (words, power, health, combo points, ammo, pet happiness,
-- the target's range band, the clock, a spell's cooldown or charges, an aura's
-- time or stacks on a unit, rules of its own, another custom item's value, or
-- custom words on a spell's or an aura's state), on the bars runtime's shell
-- through Bars.RegisterKind and Bars.Kit.
-- Every value the game keeps secret goes straight into a text sink (SetText,
-- SetFormattedText, C_StringUtil's joins, a Cooldown's own countdown, an aura
-- button's text bindings); nothing here reads, compares or converts one.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R
local Schema = NS.Schema
local TX = {}
NS.TextElements = TX
TX.KEY = "adbarstext"
-- the range engine's owner prefix, one owner per element
TX.RANGE_OWNER = "adtext"
-- a rule-driven timer's readout moves this often while it runs
TX.TICK = 0.1
-- a spell's countdown re-reads this long after the GCD hid it (the icon
-- driver's fallback: the GCD spell's own numbers are dead on Forever)
TX.GCD_RETRY = 0.3
TX.MOOD = { [1] = "Unhappy", [2] = "Content", [3] = "Happy" }
-- how far past the box the missing words reach (outline, shadow)
TX.ERASE_PAD = 4
TX.UNITS = { "player", "target", "focus", "pet" }
TX.fonts = {}      -- [name] = Font, one per element
TX.armed = {}      -- [event] = true while registered under TX.KEY
TX.countFmts = {}  -- [prefix|suffix] = the stack count's rule formatter

local SOURCES = {}
for _, s in ipairs(Schema.TEXT_SOURCES or {}) do SOURCES[s] = true end
local NUMERIC = { power = true, health = true, combo = true, ammo = true, spellCharges = true, auraStacks = true }
local COUNTED = { combo = true, ammo = true, spellCharges = true }
local TIMED = { spellCd = true, auraTime = true }
local AURA = { auraTime = true, auraStacks = true }
local CUSTOM = { rules = true, custom = true }
-- words, not a value: typed, or custom words on a spell's or an aura's state
local WORDS = { static = true, spellText = true, auraText = true }
local SPELL_WHEN, AURA_WHEN = {}, {}
for _, w in ipairs(Schema.TEXT_SPELL_WHEN or {}) do SPELL_WHEN[w] = true end
for _, w in ipairs(Schema.TEXT_AURA_WHEN or {}) do AURA_WHEN[w] = true end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

function TX.Source(rec)
    local d = rec and rec.driver
    local s = d and d.source
    return SOURCES[s] and s or "static"
end

-- The format rows' gates (Schema.TextNumeric / TextCounted / TextTimed read
-- these): a rule-driven readout is a count, a time or both.
function TX.NumericSource(rec)
    local s = TX.Source(rec)
    if CUSTOM[s] then return (rec.driver.show or "stacks") ~= "left" end
    if s == "power" or s == "health" then return (rec.driver.show or "current") ~= "percent" end
    return NUMERIC[s] == true
end

function TX.CountedSource(rec)
    local s = TX.Source(rec)
    if CUSTOM[s] then return (rec.driver.show or "stacks") ~= "left" end
    return COUNTED[s] == true
end

function TX.TimedSource(rec)
    local s = TX.Source(rec)
    if CUSTOM[s] then return (rec.driver.show or "stacks") ~= "stacks" end
    return TIMED[s] == true
end

function TX.AuraSource(rec)
    return AURA[TX.Source(rec)] == true
end

-- The prefix and suffix rows: a value this element writes. Never on words of
-- your own nor on a countdown the game draws (neither shows them); typed words
-- keep a prefix they already have, so it stays editable.
function TX.ValueSource(rec)
    local s = TX.Source(rec)
    if s == "spellText" or s == "auraText" or s == "spellCd" or s == "auraTime" then return false end
    if s == "static" then
        if not rec.o then return false end
        return (R(rec, "textel", "prefix") or "") ~= "" or (R(rec, "textel", "suffix") or "") ~= ""
    end
    return true
end

function TX.Words(rec)
    return rec.driver.text or ""
end

-- The state custom words show on: the states the icons glow on. A spell's
-- defaults to ready, an aura's to while it is up.
function TX.When(rec)
    local s, w = TX.Source(rec), rec.driver.when
    if s == "spellText" then return SPELL_WHEN[w] and w or "ready" end
    if s == "auraText" then return AURA_WHEN[w] and w or "up" end
    return nil
end

-- How an aura's words show; "none" where missing words could not hide and would mislead.
function TX.AuraWordsMode(rec)
    local w = TX.When(rec)
    if w == "missing" then
        local DA = NS.DriverAura
        return (DA and DA.EraserAvailable and DA.EraserAvailable()) and "missing" or "none"
    end
    return w
end

-- True when the element needs an aura slot: an aura's time or stacks, or its
-- words on any state but Always.
function TX.SlotSource(rec)
    local s = TX.Source(rec)
    if AURA[s] then return true end
    if s ~= "auraText" then return false end
    local m = TX.AuraWordsMode(rec)
    return m == "up" or m == "time" or m == "missing"
end

-- The share of the aura's time left the words show under, as the aura glows
-- reckon it: a percent, or seconds against the aura's length typed in (nil =
-- no length, so no gate: the words show while the aura is up).
function TX.GateFrac(rec)
    local d = rec.driver
    if d.timeUnit == "sec" then
        local len = tonumber(d.auraLen)
        if not (len and len > 0) then return nil end
        return math.min(1, (tonumber(d.timeSec) or 5) / len)
    end
    return (tonumber(d.timePct) or 30) / 100
end

-- Text style

function TX.FontObject(e)
    if not CreateFont then return nil end
    local name = "ArcAurasTextFont_" .. tostring(e.rec.id)
    local fo = TX.fonts[name]
    if not fo then
        fo = CreateFont(name)
        TX.fonts[name] = fo
    end
    return fo
end

function TX.Rounding(rec)
    local v = R(rec, "textel", "rounding")
    if v == "up" or v == "down" then return v end
    local F = NS.Factory
    return (F and F.TimerRounding and F.TimerRounding()) or "up"
end

-- The one style writer for every string this element owns: its own, the
-- countdown widget's and the aura button's. The face goes on a Font object,
-- which reaches a string the engine has locked; a bad file falls back to the
-- default face through the bars' probe.
function TX.StyleText(e, fs)
    local rec = e.rec
    local size = R(rec, "textel", "size") or 14
    local outline = R(rec, "textel", "outline") or "OUTLINE"
    local flags = (outline ~= "NONE") and outline or ""
    local path = Bars.ResolveFont(R(rec, "textel", "font"))
    if K.ProvenFontPath then path = K.ProvenFontPath(path, size, flags) end
    local fo = TX.FontObject(e)
    local target = fo or fs
    target:SetFont(path, size, flags)
    if R(rec, "textel", "shadow") == true then
        target:SetShadowColor(0, 0, 0, 1)
        target:SetShadowOffset(1, -1)
    else
        target:SetShadowOffset(0, 0)
    end
    if fo and fs:GetFontObject() ~= fo then fs:SetFontObject(fo) end
    local c = R(rec, "textel", "color") or { 1, 1, 1, 1 }
    local jh = R(rec, "textel", "justifyH") or "CENTER"
    local jv = R(rec, "textel", "justifyV") or "MIDDLE"
    -- the object carries the look too: the countdown widget re-applies it on
    -- every start, which resets the string's own colour
    if fo then
        fo:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        fo:SetJustifyH(jh)
        fo:SetJustifyV(jv)
    end
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH(jh)
    fs:SetJustifyV(jv)
end

-- Writing

-- The one writer of the element's own string. A secret value reaches it
-- through C_StringUtil, which rounds and joins C-side; a plain one is joined
-- here. numeric: the value is a number (a secret one is rounded to a string
-- first; a secret string, an abbreviation, is joined as it is).
function TX.Write(e, v, numeric)
    local fs = e.txFS
    -- a secret (a name, a formatted number) is never compared, only passed on
    if not IsSecret(v) and (v == nil or v == "") then
        fs:SetText("")
        return
    end
    local rec = e.rec
    local pre = R(rec, "textel", "prefix") or ""
    local suf = R(rec, "textel", "suffix") or ""
    if pre == "" and suf == "" then
        fs:SetText(v)
        return
    end
    if IsSecret(v) then
        local SU = C_StringUtil
        if SU and SU.WrapString then
            local s = v
            if numeric and SU.RoundToNearestString then s = SU.RoundToNearestString(s) end
            fs:SetText(SU.WrapString(s, pre, suf))
        else
            fs:SetText(v)
        end
        return
    end
    fs:SetText(pre .. tostring(v) .. suf)
end

-- A plain count as words: "" when blank at zero, short when asked.
function TX.CountText(e, n)
    if type(n) ~= "number" then return "" end
    if n == 0 and R(e.rec, "textel", "blankAtZero") == true then return "" end
    if R(e.rec, "textel", "numFormat") == "abbreviated" and AbbreviateNumbers then
        return tostring(AbbreviateNumbers(n))
    end
    return tostring(n)
end

-- A count or an amount that can be secret (power, health, charges): blank at
-- zero through TruncateWhenZero, short through AbbreviateNumbers, else the
-- number itself; each a sink.
function TX.Number(e, v)
    if v == nil then
        TX.Write(e, nil)
        return
    end
    if not IsSecret(v) then
        TX.Write(e, TX.CountText(e, v), false)
        return
    end
    local rec = e.rec
    if R(rec, "textel", "blankAtZero") == true and C_StringUtil and C_StringUtil.TruncateWhenZero then
        TX.Write(e, C_StringUtil.TruncateWhenZero(v), false)
        return
    end
    if R(rec, "textel", "numFormat") == "abbreviated" and AbbreviateNumbers then
        TX.Write(e, AbbreviateNumbers(v), false)
        return
    end
    TX.Write(e, v, true)
end

-- A percent the game scales to 0..100 (secret or not) written C-side, the
-- health bar's own path; the prefix and suffix ride the format string.
function TX.Percent(e, v)
    local fs = e.txFS
    if v == nil then
        fs:SetText("")
        return
    end
    local rec = e.rec
    local pre = (R(rec, "textel", "prefix") or ""):gsub("%%", "%%%%")
    local suf = (R(rec, "textel", "suffix") or ""):gsub("%%", "%%%%")
    fs:SetFormattedText(pre .. "%.0f%%" .. suf, v)
end

-- A plain number of seconds in the element's countdown format.
function TX.Countdown(e, t)
    local F = NS.Factory
    if not (F and F.FormatCountdown) then return tostring(math.floor(t + 0.5)) end
    local rec = e.rec
    local decTo = (R(rec, "textel", "decimals") == true) and (R(rec, "textel", "decimalsBelow") or 10) or 0
    return F.FormatCountdown(t, decTo, R(rec, "textel", "abbrev") or 0, TX.Rounding(rec) == "down")
end

-- The countdown widget's and the aura duration's formatter: decimals, M:SS and
-- the rounding, from the same Factory recipe the bars use. stock: what the
-- widget draws on its own ("up" a Cooldown, "down" the aura engine).
function TX.TimerFormatter(e, stock)
    local F = NS.Factory
    if not (F and F.TimerFormatter) then return nil end
    local rec = e.rec
    local decTo = (R(rec, "textel", "decimals") == true) and (R(rec, "textel", "decimalsBelow") or 10) or 0
    return F.TimerFormatter(decTo, nil, R(rec, "textel", "abbrev") or 0, stock, TX.Rounding(rec))
end

-- The aura stack count from 1 with the prefix and suffix baked in: the engine
-- formats C-side, so the count is never read.
function TX.CountFormatter(e)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local rec = e.rec
    local pre = (R(rec, "textel", "prefix") or ""):gsub("%%", "%%%%")
    local suf = (R(rec, "textel", "suffix") or ""):gsub("%%", "%%%%")
    local key = pre .. "|" .. suf
    local f = TX.countFmts[key]
    if f then return f end
    f = C_StringUtil.CreateNumericRuleFormatter()
    if not f then return nil end
    f:AddBreakpoint({ threshold = 0, format = "" })
    f:AddBreakpoint({ threshold = 1, format = pre .. "%d" .. suf })
    TX.countFmts[key] = f
    return f
end

-- Sources

function TX.PowerType(rec)
    local pt = rec.driver.powerType
    if pt == nil or pt < 0 then pt = (UnitPowerType and UnitPowerType("player")) or 0 end
    return pt
end

function TX.PaintStatic(e)
    TX.Write(e, e.rec.driver.text, false)
end

function TX.PaintPower(e)
    local rec = e.rec
    local pt = TX.PowerType(rec)
    local show = rec.driver.show or "current"
    if show == "percent" then
        local scale = K.HealthScale()
        if scale and UnitPowerPercent then
            TX.Percent(e, UnitPowerPercent("player", pt, false, scale))
        else
            TX.Write(e, nil)
        end
    elseif show == "max" then
        TX.Number(e, UnitPowerMax and UnitPowerMax("player", pt))
    else
        -- shards read in tenths for the bar's fill: the text takes whole shards
        local RP = Bars.ResPowers
        local cur = K.ResourceCurrent(pt)
        if RP and RP.Owns(pt) then cur = RP.TextValue(pt, cur) end
        TX.Number(e, cur)
    end
end

function TX.PaintHealth(e)
    local rec = e.rec
    local unit = rec.driver.unit or "player"
    local show = rec.driver.show or "current"
    if show == "percent" then
        local scale = K.HealthScale()
        if scale and UnitHealthPercent then
            TX.Percent(e, UnitHealthPercent(unit, true, scale))
        else
            TX.Write(e, nil)
        end
    elseif show == "max" then
        TX.Number(e, UnitHealthMax and UnitHealthMax(unit))
    else
        TX.Number(e, UnitHealth and UnitHealth(unit))
    end
end

-- The separator between a first name and a surname, the game's own.
function TX.NameSeparator()
    local C = Constants and Constants.CharacterNameSeparatorConsts
    local sep = C and C.CHARACTERNAME_SURNAME_SEPARATOR
    return (type(sep) == "string" and not IsSecret(sep)) and sep or " "
end

-- The unit's name. On Forever another player's name comes in two parts and
-- shows joined, as the game shows it; on retail the second part is a realm,
-- left out. Names read secret where unit identity is restricted, so the parts
-- are joined C-side (WrapString drops the separator with no surname).
function TX.PaintName(e)
    local first, last = UnitName(e.rec.driver.unit or "player")
    if not IsSecret(first) and (first == nil or first == "") then
        TX.Write(e, nil)
        return
    end
    local SU = C_StringUtil
    if NS.IsForever == true and SU and SU.WrapString and (IsSecret(last) or (type(last) == "string" and last ~= "")) then
        first = SU.WrapString(first, nil, SU.WrapString(last, TX.NameSeparator(), nil))
    end
    TX.Write(e, first, false)
end

-- A unit's health or name hides while the unit is not there (an empty party
-- slot, no target), as health bars do; never the player's, and never while the
-- options are open (the sample shows). UnitExists can read secret in combat on
-- Forever: then the host's alpha is set from it C-side.
function TX.UnitGate(e)
    local host = e.txHost
    if not host then return end
    local s = TX.Source(e.rec)
    local unit = (s == "health" or s == "name") and (e.rec.driver.unit or "player") or "player"
    if unit == "player" or K.IsEditMode() or not UnitExists then
        host:SetAlpha(1)
        return
    end
    local ex = UnitExists(unit)
    if IsSecret(ex) then
        if host.SetAlphaFromBoolean then host:SetAlphaFromBoolean(ex, 1, 0) else host:SetAlpha(1) end
    else
        host:SetAlpha(ex and 1 or 0)
    end
end

function TX.PaintCombo(e)
    TX.Number(e, K.ResourceCurrent(4))
end

function TX.PaintAmmo(e)
    local F = NS.Factory
    TX.Number(e, F and F.AmmoCount and F.AmmoCount())
end

function TX.PaintMood(e)
    local C = NS.Conditions
    local m = C and C.PetMood and C.PetMood()
    TX.Write(e, m and TX.MOOD[m] or nil, false)
end

function TX.ClockText()
    if type(GameTime_GetTime) == "function" then
        local s = GameTime_GetTime(false)
        if type(s) == "string" then return s end
    end
    if type(date) == "function" then return date("%H:%M") end
    return nil
end

function TX.PaintClock(e)
    TX.Write(e, TX.ClockText(), false)
end

-- The range band: the bands of a range bar the element names, else the class
-- preset; the range engine answers which holds (Bars\AD_RangeBar.lua).
function TX.RangeBands(rec)
    local RB = NS.RangeBars
    if not RB then return nil end
    local from = rec.driver.rangeFrom
    local src = from and NS.Store and NS.Store.Get(from)
    if src and src.type == "bar" and src.barKind == "range" then return RB.BandsOf(src) end
    return RB.PresetBands({ driver = {} }, RB.DefaultPreset())
end

function TX.WatchRange(e)
    local DR, RB = NS.DriverRange, NS.RangeBars
    local list = TX.RangeBands(e.rec)
    e.txBandList = list
    e.txBands = (list and RB) and RB.EngineBands(list) or nil
    if not (DR and e.txBands) then return end
    local id = e.rec.id
    DR.Use(TX.RANGE_OWNER .. id, RB.Need(e.txBands, e.rec.driver), function()
        local cur = K.live[id]
        if cur then TX.Paint(cur) end
    end)
end

function TX.BandText(e)
    local DR = NS.DriverRange
    local list, bands = e.txBandList, e.txBands
    if not (DR and list and bands) then return nil end
    local i = DR.Band(bands, e.rec.driver)
    local b = i and list[i]
    if not b or b.off then return nil end
    return b.text
end

function TX.PaintRange(e)
    TX.Write(e, TX.BandText(e), false)
end

-- A spell's cooldown: the countdown draws itself from the duration object,
-- so the time is never read. The spell resolves as the icons' does, with the
-- record's own Auto rank and Ignore override.
function TX.EffSpell(rec)
    return NS.Store.RecordSpellID(rec.driver)
end

function TX.EnsureCD(e)
    if e.txCD then return e.txCD end
    local cd = CreateFrame("Cooldown", nil, e.txHost, "CooldownFrameTemplate")
    cd:SetAllPoints(e.txHost)
    cd:SetDrawSwipe(false)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(false)
    if cd.SetMinimumCountdownDuration then cd:SetMinimumCountdownDuration(0) end
    cd:EnableMouse(false)
    cd:Show()
    e.txCD = cd
    return cd
end

function TX.StyleCD(e)
    local cd = TX.EnsureCD(e)
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs then
        TX.StyleText(e, fs)
        fs:ClearAllPoints()
        fs:SetAllPoints(cd)
        -- the widget re-applies its countdown Font object on every start:
        -- hand it ours by name and the face sticks
        local fo = TX.FontObject(e)
        if fo and cd.SetCountdownFont and cd._adFontName ~= fo:GetName() then
            cd._adFontName = fo:GetName()
            cd:SetCountdownFont(fo:GetName())
        end
    end
    if cd.SetCountdownFormatter then
        local fmt = TX.TimerFormatter(e, "up")
        local sig = fmt or "stock"
        if cd._adFmtSig ~= sig then
            cd._adFmtSig = sig
            cd:SetCountdownFormatter(fmt)
        end
    end
end

-- One re-read after the GCD hid the countdown: a real cooldown started under
-- it comes with no event of its own at the GCD's end.
function TX.RetryAfterGCD(e)
    if e.txGcdQueued then return end
    e.txGcdQueued = true
    local id = e.rec.id
    C_Timer.After(TX.GCD_RETRY, function()
        local cur = K.live[id]
        if not cur then return end
        cur.txGcdQueued = nil
        local s = TX.Source(cur.rec)
        if s == "spellCd" then
            TX.FeedCooldown(cur)
        elseif s == "spellText" then
            TX.PaintSpellText(cur)
        end
    end)
end

function TX.FeedCooldown(e)
    local cd = TX.EnsureCD(e)
    local rec = e.rec
    local sid = TX.EffSpell(rec)
    if not (sid and C_Spell and C_Spell.GetSpellCooldownDuration) then
        cd:Clear()
        e.txCdOn = nil
        return
    end
    -- isOnGCD (never secret) keeps the global cooldown out; a toggle that is
    -- on (isEnabled false) counts as ready, as on the icons
    local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
    local onGcd = info and info.isOnGCD
    if IsSecret(onGcd) then onGcd = nil end
    onGcd = (onGcd == true)
    local en = info and info.isEnabled
    if IsSecret(en) then en = nil end
    local DC = NS.DriverCooldown
    local wandLock = DC ~= nil and DC.WandLocked ~= nil and DC.WandLocked() and not DC.IsWandShot(sid)
    -- a running countdown keeps its timing through the wand's lock
    if wandLock and e.txCdOn and cd:IsShown() then return end
    local dur
    local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    if ch and (ch.maxCharges or 0) > 1 and C_Spell.GetSpellChargeDuration then
        dur = C_Spell.GetSpellChargeDuration(sid, true)
    else
        dur = C_Spell.GetSpellCooldownDuration(sid, true)
    end
    if dur and not onGcd and not wandLock and en ~= false then
        cd:SetCooldownFromDurationObject(dur, true)
        e.txCdOn = true
    else
        cd:Clear()
        e.txCdOn = nil
    end
    if onGcd and not wandLock then TX.RetryAfterGCD(e) end
end

-- The charge count: a secret goes to the sink as the charge icons write it.
function TX.PaintCharges(e)
    local sid = TX.EffSpell(e.rec)
    local ch = sid and C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    -- nil charge info is transient (mid-GCD): the last text stays, as on the icons
    if not ch then return end
    TX.Number(e, ch.currentCharges)
end

-- A spell's words on one of its states. Every read is plain in combat: a
-- hidden cooldown's IsShown (the GCD kept out, a charge spell on cooldown only
-- with no charge left), IsSpellUsable, and the proc overlay's events.
function TX.EnsureShadow(e)
    if e.txShadow then return e.txShadow end
    local sh = K.MakeShadow()
    local id = e.rec.id
    sh:SetScript("OnCooldownDone", function()
        local cur = K.live[id]
        if not (cur and TX.Source(cur.rec) == "spellText") then return end
        if TX.When(cur.rec) == "usable" then TX.ReadUsable(cur) end
        TX.SyncHidden(cur)
    end)
    e.txShadow = sh
    return sh
end

function TX.FeedShadow(e)
    local sh = TX.EnsureShadow(e)
    local sid = TX.EffSpell(e.rec)
    if not (sid and C_Spell and C_Spell.GetSpellCooldownDuration) then
        sh:Clear()
        return
    end
    local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
    local onGcd = info and info.isOnGCD
    if IsSecret(onGcd) then onGcd = nil end
    local en = info and info.isEnabled
    if IsSecret(en) then en = nil end
    local DC = NS.DriverCooldown
    local wandLock = DC ~= nil and DC.WandLocked ~= nil and DC.WandLocked() and not DC.IsWandShot(sid)
    if wandLock and sh:IsShown() == true then return end
    local dur = C_Spell.GetSpellCooldownDuration(sid, true)
    if dur and onGcd ~= true and not wandLock and en ~= false then
        sh:SetCooldownFromDurationObject(dur, true)
    else
        sh:Clear()
    end
    if onGcd == true and not wandLock then TX.RetryAfterGCD(e) end
end

-- A secret answer keeps the last one.
function TX.ReadUsable(e)
    local sid = TX.EffSpell(e.rec)
    if not (sid and C_Spell and C_Spell.IsSpellUsable) then return end
    local u = C_Spell.IsSpellUsable(sid)
    if IsSecret(u) then return end
    e.txUsable = (u == true)
end

-- The tracked spell, the rank or form it resolves to, or another rank of it
-- (the same name, on either client): a proc overlay can name any of them.
function TX.SameSpell(rec, sid)
    if type(sid) ~= "number" then return false end
    return NS.Store.SpellMatch(rec.driver.spellID, sid, TX.EffSpell(rec), true)
end

-- The first answer; the overlay events keep it after. Asked of every form the
-- one matcher knows the spell by (resolved, typed, override, base).
function TX.ReadProc(e)
    local O = C_SpellActivationOverlay
    if not (O and O.IsSpellOverlayed) then return end
    local on = false
    for _, sid in ipairs(NS.Store.WantKeys(e.rec.driver.spellID, TX.EffSpell(e.rec), false)) do
        local v = O.IsSpellOverlayed(sid)
        if not IsSecret(v) and v == true then on = true end
    end
    e.txProc = on
end

function TX.OnProc(sid, on)
    if IsSecret(sid) then return end
    K.ForEach("text", function(e)
        local rec = e.rec
        if TX.Source(rec) == "spellText" and TX.When(rec) == "proc" and TX.SameSpell(rec, sid) then
            e.txProc = on
            TX.SyncHidden(e)
        end
    end)
end

-- Usable is the usable glow's: castable, the resources there and the real
-- cooldown back.
function TX.SpellOn(e)
    local w = TX.When(e.rec)
    if w == "always" then return true end
    if w == "proc" then return e.txProc == true end
    local cd = e.txShadow ~= nil and e.txShadow:IsShown() == true
    if w == "cooldown" then return cd end
    if w == "usable" then return e.txUsable == true and not cd end
    return not cd
end

function TX.PaintSpellText(e)
    local w = TX.When(e.rec)
    if w ~= "always" and w ~= "proc" then TX.FeedShadow(e) end
    if w == "usable" then TX.ReadUsable(e) end
    if w == "proc" and e.txProc == nil then TX.ReadProc(e) end
    e.txFS:SetText(TX.Words(e.rec))
    TX.SyncHidden(e)
end

-- A rule-driven value: this element's own state in the custom engine, or the
-- custom item it points at. Timers are our own GetTime numbers.
function TX.CustomState(e)
    local CU = NS.DriverCustom
    if not CU then return nil end
    local rec = e.rec
    local id = (TX.Source(rec) == "rules") and rec.id or rec.driver.srcId
    return id and CU.Get(id) or nil
end

-- Its own triggers (the rules on its Triggers tab) decide when it shows, per
-- its Show while. Always, the default, shows it all the time, and so does a
-- text with no rules yet.
function TX.HasRules(rec)
    local r = rec and rec.driver and rec.driver.rules
    return type(r) == "table" and #r > 0
end

function TX.TriggerHidden(e)
    local rec = e.rec
    local w = rec.driver.showWhile
    if w == nil or w == "always" or not TX.HasRules(rec) then return false end
    local CU = NS.DriverCustom
    local st = CU and CU.Get(rec.id)
    if not st then return false end
    return not CU.Active(st)
end

-- Hidden by state: a spell's words off their state, or its own triggers. Aura words need no flag.
function TX.StateHidden(e)
    local rec = e.rec
    if TX.Source(rec) == "spellText" and TX.EffSpell(rec) and not TX.SpellOn(e) then return true end
    return TX.TriggerHidden(e)
end

function TX.SyncHidden(e)
    local h = TX.StateHidden(e)
    if (e.stateHidden == true) ~= h then
        e.stateHidden = h
        K.ApplyVisibility(e)
    end
end

function TX.PaintCustom(e)
    local st = TX.CustomState(e)
    if not st then
        TX.Write(e, nil)
        return
    end
    local rec = e.rec
    local show = rec.driver.show or "stacks"
    local left = st.endAt and (st.endAt - GetTime()) or nil
    if left and left <= 0 then left = nil end
    local leftText = left and TX.Countdown(e, left) or nil
    if show == "left" then
        TX.Write(e, leftText, false)
    elseif show == "both" then
        local words = TX.CountText(e, st.stacks or 0)
        if leftText then words = (words ~= "" and (words .. " ") or "") .. "(" .. leftText .. ")" end
        TX.Write(e, words, false)
    else
        TX.Number(e, st.stacks or 0)
    end
end

-- One 0.1 s ticker while a rule-driven time left is on screen, none otherwise.
function TX.SyncTicker()
    local want = false
    K.ForEach("text", function(e)
        if CUSTOM[TX.Source(e.rec)] and (e.rec.driver.show or "stacks") ~= "stacks" then
            local st = TX.CustomState(e)
            if st and st.endAt and GetTime() < st.endAt then want = true end
        end
    end)
    if want and not TX.ticker and C_Timer and C_Timer.NewTicker then
        TX.ticker = C_Timer.NewTicker(TX.TICK, TX.TickCustom)
    elseif not want and TX.ticker then
        TX.ticker:Cancel()
        TX.ticker = nil
    end
end

function TX.TickCustom()
    K.ForEach("text", function(e)
        if CUSTOM[TX.Source(e.rec)] and (e.rec.driver.show or "stacks") ~= "stacks" then TX.PaintCustom(e) end
    end)
    TX.SyncTicker()
end

-- The custom engine's paint told every text that reads that state.
function TX.OnCustomPaint(st)
    K.ForEach("text", function(e)
        if CUSTOM[TX.Source(e.rec)] and TX.CustomState(e) == st then TX.PaintCustom(e) end
        if e.rec.id == st.id then TX.SyncHidden(e) end
    end)
    TX.SyncTicker()
end

-- An aura's time or stacks: one engine slot whose button is bare but for our
-- string, handed to the engine's own text binding, so the aura's time and
-- count never reach Lua. The recipe is the aura bars' (Bars\AD_Bars.lua).
function TX.AuraSig(e)
    local DA = NS.DriverAura
    local rec = e.rec
    local d = rec.driver
    local unit, harmful = DA.ShapeOf(d)
    local filter = DA.FilterForLane(d, { harmful = harmful })
    local ids = DA.IncludeMap(d)
    local which = TX.Source(rec)
    local fmt, how
    if which == "auraTime" then
        fmt = TX.TimerFormatter(e, "down")
    elseif which == "auraStacks" then
        fmt = TX.CountFormatter(e)
    else
        how = TX.AuraWordsMode(rec)
    end
    -- the ids, the words and the gate's share stay out: an edit reaches the
    -- live slot with them
    local sig = table.concat({ unit, tostring(harmful), filter, which, tostring(fmt), tostring(how) }, "|")
    return sig, unit, filter, ids, fmt
end

function TX.ParkAura(sub)
    if sub.container.SetAuraSlotCandidateFilters then
        sub.container:SetAuraSlotCandidateFilters(sub.key, { includeSpellIDs = { [0] = true } })
    end
    sub.container:Hide()
    -- the missing words would stay up otherwise
    if sub.stage then sub.stage:Hide() end
end

-- The box in plain numbers: the record's size, never a read of the shell.
function TX.BoxSize(rec)
    local sc = R(rec, "size", "scale") or 1
    return (R(rec, "size", "width") or 140) * sc, (R(rec, "size", "height") or 24) * sc
end

-- Words under a share of the aura's time left: a clip frame on the fill of a
-- hidden bar the engine fills with the time gone, the aura glows' gate
-- (Core\AD_Factory.lua ApplyTimeGate), so the time never reaches Lua. The fill
-- stays short of the words until the share is crossed, then covers them.
function TX.GateClip(b, th)
    local gb = CreateFrame("StatusBar", nil, b)
    gb:SetStatusBarTexture(K.WHITE)
    gb:SetStatusBarColor(1, 1, 1, 0)
    gb:EnableMouse(false)
    b:SetDurationBar(gb, {
        interpolation = Enum.StatusBarInterpolation.Immediate,
        direction = Enum.StatusBarTimerDirection.ElapsedTime,
    })
    local fill = gb:GetStatusBarTexture()
    local clip = CreateFrame("Frame", nil, th)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    return gb, clip
end

-- The gate's geometry for the share now set (an edit moves it on the live
-- slot, never a new one). The range g .. g + 0.0002 flips the fill; with
-- L = gw / 0.0005 and the -g * L shift, a range the engine resets to 0 .. 1
-- still crosses the words within 0.05% of the aura's life. No length typed in
-- for seconds: open at once, the words show while the aura is up.
function TX.PlaceGate(sub, rec)
    local gb, b = sub.gateBar, sub.button
    if not (gb and b) then return end
    local W, H = TX.BoxSize(rec)
    local E = math.max(W, H)
    local gw, gh = W + 2 * E, H + 2 * E
    local L = math.min(120000, gw / 0.0005)
    local g = 1 - (TX.GateFrac(rec) or 1)
    gb:ClearAllPoints()
    gb:SetSize(L, gh)
    gb:SetPoint("LEFT", b, "CENTER", -gw / 2 - g * L, 0)
    gb:SetMinMaxValues(g, g + 0.0002)
end

local function GateReady(b)
    return b.SetDurationBar ~= nil and Enum ~= nil and Enum.StatusBarTimerDirection ~= nil
        and Enum.StatusBarInterpolation ~= nil
end

-- The button's string is written on an accessible pass only; the next one catches up.
function TX.PaintAuraText(e)
    local rec = e.rec
    local words = TX.Words(rec)
    if not TX.SlotSource(rec) then
        e.txFS:SetText((TX.AuraWordsMode(rec) == "always") and words or "")
        return
    end
    e.txFS:SetText("")
    local sub = e.txAura
    if not sub then return end
    if sub.missFS then sub.missFS:SetText(words) end
    local DA = NS.DriverAura
    if sub.fs and (not (DA and DA.IsAccessible) or DA.IsAccessible(sub.button)) then sub.fs:SetText(words) end
end

-- Creates the slot once per recipe; false means retry on a later rebuild
-- (engine absent, or auras secret outside the login window).
function TX.EnsureAura(e)
    local DA = NS.DriverAura
    if not (DA and K.AuraEngineUp()) then return false end
    local rec = e.rec
    local sig, unit, filter, ids, fmt = TX.AuraSig(e)
    local sub = e.txAura
    if sub then
        if sub.sig == sig then
            -- the ids are pure data: an edit reaches the live slot
            local fsig = DA.FilterSig(ids)
            if sub.filterSig ~= fsig then
                sub.filterSig = fsig
                sub.container:SetAuraSlotCandidateFilters(sub.key, { includeSpellIDs = ids })
            end
            return true
        end
        -- a new recipe cannot be made while auras are secret: the old slot
        -- keeps running (a stale look beats a dead text); a rebuild swaps it
        if K.AuraSecretNow() and not Bars.loadWindow then return true end
        TX.ParkAura(sub)
        e.txAura = nil
    end
    if K.AuraSecretNow() and not Bars.loadWindow then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local shell = e.shell
    local which = TX.Source(rec)
    local mode = (which == "auraText") and TX.AuraWordsMode(rec) or nil
    -- parented to the shell: the holder's opacity and conditions reach the
    -- engine-drawn text through it
    local parent, stage, missFS = shell, nil, nil
    if mode == "missing" then
        -- words and container share one stage
        stage = CreateFrame("Frame", nil, shell)
        stage:SetAllPoints(shell)
        stage:SetFrameLevel(shell.overlay:GetFrameLevel() + 2)
        stage:SetFlattensRenderLayers(true)
        stage:SetIsFrameBuffer(true)
        missFS = stage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        missFS:SetWordWrap(false)
        missFS:SetAllPoints(shell)
        parent = stage
    end
    local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraSlot) ~= "function" then
        if stage then stage:Hide() end
        return false
    end
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    c:SetUnit(unit)
    c:SetEnabled(true)
    c:Show()
    e.txAuraGen = (e.txAuraGen or 0) + 1
    local key = "adtext" .. rec.id .. "_g" .. e.txAuraGen
    sub = { container = c, key = key, sig = sig, unit = unit, which = which, mode = mode,
        stage = stage, missFS = missFS, filterSig = DA.FilterSig(ids) }
    e.txAura = sub
    if missFS then
        TX.StyleText(e, missFS)
        missFS:SetText(TX.Words(rec))
        if TX.StandIn(e) then stage:SetAlpha(0) end
    end
    local id = rec.id
    c:AddAuraSlot(key, filter, {
        maxFrameCount = 1,
        initializeFrame = function(b)
            local cur = K.live[id]
            if not (cur and cur.txAura == sub) then return end
            b:EnableMouse(false)
            b:ClearAllPoints()
            b:SetAllPoints(cur.shell)
            sub.button = b
            if sub.mode == "missing" then
                -- born erasing: an engine button takes no restyle in an instance
                local pad = TX.ERASE_PAD
                local er = b:CreateTexture(nil, "BACKGROUND", nil, -8)
                er:SetColorTexture(0, 0, 0, 0)
                er:SetBlendMode("DISABLE")
                er:SetPoint("TOPLEFT", cur.shell, "TOPLEFT", -pad, pad)
                er:SetPoint("BOTTOMRIGHT", cur.shell, "BOTTOMRIGHT", pad, -pad)
                return
            end
            -- the string rides a host on the button (the engine takes only a
            -- descendant of it), above the shell's overlay
            local th = CreateFrame("Frame", nil, b)
            th:SetAllPoints(cur.shell)
            th:SetFrameLevel(cur.shell.overlay:GetFrameLevel() + 2)
            sub.host = th
            -- born put away while a sample stands in (edit mode)
            if TX.StandIn(cur) then th:SetAlpha(0) end
            local holder = th
            if sub.mode == "time" and GateReady(b) then
                sub.gateBar, holder = TX.GateClip(b, th)
                TX.PlaceGate(sub, cur.rec)
            end
            local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetWordWrap(false)
            fs:SetAllPoints(th)
            sub.fs = fs
            -- the font before the binding: the binding writes text at once
            TX.StyleText(cur, fs)
            if sub.which == "auraTime" then
                b:SetDurationText(fs, fmt and { textFormatter = fmt } or {})
            elseif sub.which == "auraStacks" then
                local o = {}
                -- count from 1; 12.1.0 does not know the field and shows from 2
                if not NS.OldAuraEngine then o.minApplications = 1 end
                if fmt then o.formatter = fmt end
                b:SetApplicationCount(fs, o)
            else
                fs:SetText(TX.Words(cur.rec))
            end
        end,
        candidateFilters = { includeSpellIDs = ids },
    })
    if type(c.UpdateAllAuras) == "function" then c:UpdateAllAuras() end
    return true
end

-- A unit token keeps its name when it points at someone new, and a container
-- re-reads only on its own unit's aura events: nudge it on a swap.
function TX.NudgeAuras(unit)
    K.ForEach("text", function(e)
        local sub = e.txAura
        if sub and sub.unit == unit and type(sub.container.UpdateAllAuras) == "function" then
            sub.container:UpdateAllAuras()
        end
    end)
end

TX.PAINT = {
    static = TX.PaintStatic, power = TX.PaintPower, health = TX.PaintHealth, name = TX.PaintName, combo = TX.PaintCombo,
    ammo = TX.PaintAmmo, petMood = TX.PaintMood, range = TX.PaintRange, clock = TX.PaintClock,
    spellCd = TX.FeedCooldown, spellCharges = TX.PaintCharges, rules = TX.PaintCustom,
    custom = TX.PaintCustom, spellText = TX.PaintSpellText, auraText = TX.PaintAuraText,
}

-- While the options are open a text never vanishes: a sample stands in for live values and words.
local STAND_VALUE = { spellCd = true, spellCharges = true, auraTime = true, auraStacks = true }
function TX.StandIn(e)
    if e.isPreview or not K.IsEditMode() then return false end
    local rec = e.rec
    local s = TX.Source(rec)
    if STAND_VALUE[s] or TX.SlotSource(rec) then return true end
    if s == "spellText" or s == "auraText" then
        return TX.Words(rec) == "" or TX.AuraWordsMode(rec) == "none"
    end
    return false
end

function TX.Paint(e)
    if e.isPreview then return end
    TX.UnitGate(e)
    if TX.StandIn(e) then
        TX.PreviewApply(e)
        return
    end
    local fn = TX.PAINT[TX.Source(e.rec)]
    if fn then fn(e) end
    -- a plain value that came out blank (no ammo, no target) stands in too
    if K.IsEditMode() and e.txFS:IsShown() then
        local t = e.txFS:GetText()
        if not IsSecret(t) and (t == nil or t == "") then TX.PreviewApply(e) end
    end
end

-- Events: each source arms only what it needs, while an element with that
-- source is live; the handlers repaint the elements that read the event.

local function PaintWhere(key, pred)
    NS.Events.Coalesce("adtext_" .. key, function()
        K.ForEach("text", function(e)
            if pred(e) then TX.Paint(e) end
        end)
    end)
end

local function SourceIs(s)
    return function(e) return TX.Source(e.rec) == s end
end

-- the power events name the type: only the elements on that power repaint
local function PowerPred(token)
    return function(e)
        local s = TX.Source(e.rec)
        if s == "combo" then return token == nil or token == "COMBO_POINTS" end
        if s ~= "power" then return false end
        local info = Bars.POWER_ALL and Bars.POWER_ALL[TX.PowerType(e.rec)]
        return token == nil or info == nil or info.token == token
    end
end

local function HealthPred(unit)
    return function(e)
        return TX.Source(e.rec) == "health" and (unit == nil or (e.rec.driver.unit or "player") == unit)
    end
end

-- a unit's health and name texts (nil: every one), what a swap of the unit repaints
local function UnitPred(unit)
    return function(e)
        local s = TX.Source(e.rec)
        return (s == "health" or s == "name") and (unit == nil or (e.rec.driver.unit or "player") == unit)
    end
end

-- the sources that read a spell's cooldown
local SPELL_READ = { spellCd = true, spellCharges = true, spellText = true }
local function SpellPred(e)
    return SPELL_READ[TX.Source(e.rec)] == true
end

local function UsablePred(e)
    return TX.Source(e.rec) == "spellText" and TX.When(e.rec) == "usable"
end

TX.HANDLERS = {
    UNIT_POWER_FREQUENT = function(_, unit, token)
        if unit ~= "player" then return end
        if IsSecret(token) then token = nil end
        PaintWhere("power", PowerPred(token))
    end,
    UNIT_POWER_UPDATE = function(_, unit, token)
        if unit ~= "player" then return end
        if IsSecret(token) then token = nil end
        PaintWhere("power", PowerPred(token))
    end,
    UNIT_MAXPOWER = function(_, unit)
        if unit ~= "player" then return end
        PaintWhere("power", PowerPred(nil))
    end,
    UNIT_DISPLAYPOWER = function(_, unit)
        if unit ~= "player" then return end
        PaintWhere("power", SourceIs("power"))
    end,
    UPDATE_SHAPESHIFT_FORM = function() PaintWhere("power", SourceIs("power")) end,
    UNIT_HEALTH = function(_, unit)
        if IsSecret(unit) then unit = nil end
        PaintWhere("health", HealthPred(unit))
    end,
    UNIT_MAXHEALTH = function(_, unit)
        if IsSecret(unit) then unit = nil end
        PaintWhere("health", HealthPred(unit))
    end,
    PLAYER_TARGET_CHANGED = function()
        PaintWhere("target", function(e)
            local s = TX.Source(e.rec)
            local onUnit = (s == "health" or s == "name") and (e.rec.driver.unit or "player") == "target"
            return onUnit or s == "combo" or UsablePred(e)
        end)
        TX.NudgeAuras("target")
    end,
    PLAYER_FOCUS_CHANGED = function()
        PaintWhere("focus", UnitPred("focus"))
        TX.NudgeAuras("focus")
    end,
    UNIT_PET = function(_, unit)
        if unit ~= nil and unit ~= "player" and not IsSecret(unit) then return end
        PaintWhere("pet", function(e)
            local s = TX.Source(e.rec)
            return ((s == "health" or s == "name") and (e.rec.driver.unit or "player") == "pet") or s == "petMood"
        end)
        TX.NudgeAuras("pet")
    end,
    UNIT_NAME_UPDATE = function(_, unit)
        if IsSecret(unit) then unit = nil end
        PaintWhere("name", function(e)
            return TX.Source(e.rec) == "name" and (unit == nil or (e.rec.driver.unit or "player") == unit)
        end)
    end,
    -- a party slot can point at someone new, or at no one
    GROUP_ROSTER_UPDATE = function()
        PaintWhere("roster", function(e)
            local s = TX.Source(e.rec)
            return (s == "health" or s == "name") and tostring(e.rec.driver.unit or ""):match("^party") ~= nil
        end)
    end,
    UNIT_HAPPINESS = function() PaintWhere("mood", SourceIs("petMood")) end,
    UNIT_INVENTORY_CHANGED = function(_, unit)
        if unit ~= nil and unit ~= "player" and not IsSecret(unit) then return end
        PaintWhere("ammo", SourceIs("ammo"))
    end,
    BAG_UPDATE_DELAYED = function() PaintWhere("ammo", SourceIs("ammo")) end,
    PLAYER_EQUIPMENT_CHANGED = function() PaintWhere("ammo", SourceIs("ammo")) end,
    SPELL_UPDATE_COOLDOWN = function() PaintWhere("spell", SpellPred) end,
    -- a charge spell's countdown rides its recharge: both sources re-read
    SPELL_UPDATE_CHARGES = function() PaintWhere("spell", SpellPred) end,
    SPELLS_CHANGED = function() PaintWhere("spell", SpellPred) end,
    -- usability news comes in bursts: a frame at a time
    SPELL_UPDATE_USABLE = function() PaintWhere("usable", UsablePred) end,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = function(_, sid) TX.OnProc(sid, true) end,
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = function(_, sid) TX.OnProc(sid, false) end,
    -- your own cast lands its cooldown before SPELL_UPDATE_COOLDOWN inside a
    -- charge GCD: the elements on that spell re-read now
    UNIT_SPELLCAST_SUCCEEDED = function(_, unit, _, spellID)
        if unit ~= "player" then return end
        -- Forever: the first point on a new mob can come with no power event
        -- (the count stays the same), and the cast fires before the count
        -- updates: paint a frame later, and again for a late server update
        if TX.comboCast then
            PaintWhere("combo", SourceIs("combo"))
            C_Timer.After(Bars.COMBO_LATE, function() PaintWhere("combo", SourceIs("combo")) end)
        end
        if IsSecret(spellID) then return end
        K.ForEach("text", function(e)
            if SpellPred(e) and NS.Store.SpellMatch(e.rec.driver.spellID, spellID, TX.EffSpell(e.rec)) then
                TX.Paint(e)
            end
        end)
    end,
}

-- The events each source needs; the power ones follow the power's own rate.
function TX.Needs()
    local n = {}
    K.ForEach("text", function(e)
        local rec = e.rec
        local s = TX.Source(rec)
        if s == "power" then
            local info = Bars.POWER_ALL and Bars.POWER_ALL[TX.PowerType(rec)]
            n[(info and info.frequent) and "UNIT_POWER_FREQUENT" or "UNIT_POWER_UPDATE"] = true
            n.UNIT_MAXPOWER = true
            if (rec.driver.powerType or -1) < 0 then
                n.UNIT_DISPLAYPOWER, n.UPDATE_SHAPESHIFT_FORM = true, true
            end
        elseif s == "combo" then
            n.UNIT_POWER_FREQUENT, n.UNIT_MAXPOWER = true, true
            if NS.IsForever == true then
                n.PLAYER_TARGET_CHANGED, n.UNIT_SPELLCAST_SUCCEEDED, n.comboCast = true, true, true
            end
        elseif s == "health" or s == "name" then
            if s == "health" then n.UNIT_HEALTH, n.UNIT_MAXHEALTH = true, true else n.UNIT_NAME_UPDATE = true end
            local u = rec.driver.unit or "player"
            if u == "target" then n.PLAYER_TARGET_CHANGED = true
            elseif u == "focus" then n.PLAYER_FOCUS_CHANGED = true
            elseif u == "pet" then n.UNIT_PET = true
            elseif tostring(u):match("^party") then n.GROUP_ROSTER_UPDATE = true end
        elseif s == "ammo" then
            n.UNIT_INVENTORY_CHANGED, n.BAG_UPDATE_DELAYED, n.PLAYER_EQUIPMENT_CHANGED = true, true, true
        elseif s == "petMood" then
            n.UNIT_HAPPINESS, n.UNIT_PET = true, true
        elseif s == "spellCd" or s == "spellCharges" or (s == "spellText" and TX.When(rec) ~= "always") then
            n.SPELL_UPDATE_COOLDOWN, n.SPELL_UPDATE_CHARGES, n.SPELLS_CHANGED = true, true, true
            n.UNIT_SPELLCAST_SUCCEEDED = true
            local w = TX.When(rec)
            if w == "usable" then n.SPELL_UPDATE_USABLE, n.PLAYER_TARGET_CHANGED = true, true end
            if w == "proc" then
                n.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW, n.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true, true
            end
        elseif TX.SlotSource(rec) then
            local u = e.txAura and e.txAura.unit or NS.DriverAura and NS.DriverAura.ShapeOf(rec.driver)
            if u == "target" then n.PLAYER_TARGET_CHANGED = true
            elseif u == "focus" then n.PLAYER_FOCUS_CHANGED = true
            elseif u == "pet" then n.UNIT_PET = true end
        elseif s == "clock" then
            n.clock = true
        elseif CUSTOM[s] then
            n.custom = true
        end
        if TX.HasRules(rec) then n.custom = true end
    end)
    return n
end

function TX.TickClock()
    K.ForEach("text", function(e)
        if TX.Source(e.rec) == "clock" then TX.PaintClock(e) end
    end)
end

-- Arms and disarms against what the live elements need; run after every
-- ensure and release.
function TX.Sync()
    local n = TX.Needs()
    TX.comboCast = n.comboCast == true
    for ev, fn in pairs(TX.HANDLERS) do
        if n[ev] and not TX.armed[ev] then
            TX.armed[ev] = true
            K.SafeOn(ev, TX.KEY, fn)
        elseif not n[ev] and TX.armed[ev] then
            TX.armed[ev] = nil
            NS.Events.Off(ev, TX.KEY)
        end
    end
    if n.clock and not TX.clock and C_Timer and C_Timer.NewTicker then
        TX.clock = C_Timer.NewTicker(1, TX.TickClock)
    elseif not n.clock and TX.clock then
        TX.clock:Cancel()
        TX.clock = nil
    end
    local CU = NS.DriverCustom
    if CU and CU.Watch then
        if n.custom and not TX.watching then
            TX.watching = true
            CU.Watch(TX.KEY, TX.OnCustomPaint)
        elseif not n.custom and TX.watching then
            TX.watching = nil
            CU.Unwatch(TX.KEY)
        end
    end
    if not n.custom then TX.SyncTicker() end
end

-- Kind registry hooks

function TX.Build(e)
    if e.txHost then return end
    local shell = e.shell
    local host = CreateFrame("Frame", nil, shell)
    host:SetAllPoints(shell)
    host:SetFrameLevel(shell.overlay:GetFrameLevel() + 1)
    host:EnableMouse(false)
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(host)
    bg:SetTexture(K.WHITE)
    bg:Hide()
    local fs = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetAllPoints(host)
    fs:SetWordWrap(false)
    e.txHost, e.txBG, e.txFS = host, bg, fs
end

-- What another source held: the range watch, the rules sink, the aura slot,
-- the countdown.
function TX.DropOthers(e, keep)
    local id = e.rec.id
    if keep ~= "range" and NS.DriverRange then NS.DriverRange.Drop(TX.RANGE_OWNER .. id) end
    if keep ~= "rules" and NS.DriverCustom and NS.DriverCustom.DetachText then NS.DriverCustom.DetachText(id) end
    -- an aura's words on Always keep no slot: parked, its missing words go too
    if e.txAura and not (keep and TX.SlotSource(e.rec)) then
        TX.ParkAura(e.txAura)
        e.txAura = nil
    end
    if keep ~= "spellCd" and e.txCD then
        e.txCD:Clear()
        e.txCdOn = nil
    end
    if keep ~= "spellText" then
        if e.txShadow then e.txShadow:Clear() end
        e.txProc, e.txUsable = nil, nil
    end
end

function TX.Ensure(e)
    local s = TX.Source(e.rec)
    TX.DropOthers(e, s)
    if s == "range" then
        TX.WatchRange(e)
    elseif TX.SlotSource(e.rec) then
        TX.EnsureAura(e)
    end
    TX.Sync()
    -- the sink attaches after the watcher is armed: its first paint reaches us
    if (s == "rules" or TX.HasRules(e.rec)) and NS.DriverCustom and NS.DriverCustom.AttachText then
        NS.DriverCustom.AttachText(e.rec, e)
    end
    TX.Paint(e)
    if CUSTOM[s] then TX.SyncTicker() end
    e.stateHidden = TX.StateHidden(e)
    K.ApplyVisibility(e)
end

function TX.Refresh(e)
    TX.Paint(e)
    e.stateHidden = TX.StateHidden(e)
    K.ApplyVisibility(e)
end

function TX.Release(e)
    TX.DropOthers(e, nil)
    e.txGcdQueued = nil
    TX.Sync()
end

-- ApplyStyle draws the bar's chrome: put every piece of it away, then dress
-- the string (and the countdown's or the aura button's while accessible).
function TX.Styled(e)
    local shell, rec = e.shell, e.rec
    shell.fill:Hide()
    shell.bg:Hide()
    for _, t in pairs(shell.edges) do t:Hide() end
    if shell.borderF then shell.borderF:Hide() end
    shell.sheen:Hide()
    local s = TX.Source(rec)
    local slot = TX.SlotSource(rec)
    local stand = TX.StandIn(e)
    TX.StyleText(e, e.txFS)
    e.txFS:SetShown(e.isPreview or stand or not slot)
    -- a countdown the game draws leaves the own string blank, whatever the
    -- last source wrote on it (the preview paints its sample after this)
    if (slot or s == "spellCd") and not stand then e.txFS:SetText("") end
    -- the live strings step aside while a sample stands in
    if e.txCD then e.txCD:SetAlpha(stand and 0 or 1) end
    local live = e.txAura
    if live and live.stage then live.stage:SetAlpha(stand and 0 or 1) end
    if live and live.host then
        local DA = NS.DriverAura
        if not (DA and DA.IsAccessible) or DA.IsAccessible(live.button) then live.host:SetAlpha(stand and 0 or 1) end
    end
    local bg = e.txBG
    if R(rec, "textel", "bgShow") == true then
        local c = R(rec, "textel", "bgColor") or { 0, 0, 0, 0.5 }
        bg:SetVertexColor(c[1], c[2], c[3], c[4] or 0.5)
        bg:Show()
    else
        bg:Hide()
    end
    if s == "spellCd" then TX.StyleCD(e) end
    local sub = e.txAura
    if sub and sub.fs then
        local DA = NS.DriverAura
        if not (DA and DA.IsAccessible) or DA.IsAccessible(sub.button) then
            TX.StyleText(e, sub.fs)
            TX.PlaceGate(sub, rec)
        end
    end
    -- the missing words are ours: always styled
    if sub and sub.missFS then TX.StyleText(e, sub.missFS) end
end

function TX.Diag(e)
    local t = e.txFS and e.txFS.GetText and e.txFS:GetText()
    if IsSecret(t) then t = "<secret>" end
    return ("%s [text %s] value=%s aura=%s cd=%s when=%s hidden=%s"):format(tostring(e.rec.name),
        TX.Source(e.rec), tostring(t), tostring(e.txAura ~= nil), tostring(e.txCdOn == true),
        tostring(TX.When(e.rec)), tostring(e.stateHidden == true))
end

-- Editor preview: the text with a sample value in its font and box.

function TX.PreviewModes()
    return { { key = "static", text = "Preview", tip = "The text with a sample value, in its font, colour and box." } }
end

-- The Name text's sample: the unit's own name while it reads plain, else who it is.
TX.SAMPLE_NAMES = { player = "Your name", target = "Target", focus = "Focus", pet = "Pet",
    party1 = "Party 1", party2 = "Party 2", party3 = "Party 3", party4 = "Party 4" }
function TX.SampleName(rec)
    local unit = rec.driver.unit or "player"
    local nm = UnitName and UnitName(unit)
    if not IsSecret(nm) and type(nm) == "string" and nm ~= "" then return nm end
    return TX.SAMPLE_NAMES[unit] or "Name"
end

function TX.SampleText(e)
    local rec = e.rec
    local s = TX.Source(rec)
    local show = rec.driver.show
    if s == "static" then return rec.driver.text or "Text", false end
    if WORDS[s] then return rec.driver.text or "Custom text", false end
    if s == "power" then
        if show == "percent" then return "62%", false end
        return (show == "max") and 5000 or 3100, true
    elseif s == "health" then
        if show == "percent" then return "65%", false end
        return (show == "max") and 12000 or 7800, true
    elseif s == "name" then return TX.SampleName(rec), false
    elseif s == "combo" then return 3, true
    elseif s == "ammo" then return 400, true
    elseif s == "petMood" then return "Happy", false
    elseif s == "range" then
        local list = TX.RangeBands(rec)
        return (list and list[1] and list[1].text) or "IN RANGE", false
    elseif s == "clock" then return TX.ClockText() or "12:00", false
    elseif s == "spellCd" or s == "auraTime" then return TX.Countdown(e, 8), false
    elseif s == "spellCharges" then return 2, true
    elseif s == "auraStacks" then return 3, true
    end
    -- rules or another custom item: stacks, time left or both
    show = show or "stacks"
    if show == "left" then return TX.Countdown(e, 7.2), false end
    if show == "both" then return TX.CountText(e, 3) .. " (" .. TX.Countdown(e, 7.2) .. ")", false end
    return 3, true
end

function TX.PreviewApply(e)
    local v, count = TX.SampleText(e)
    -- a spell's or an aura's words, and the countdowns the game draws, are
    -- written as they are, as they paint live
    local s = TX.Source(e.rec)
    if s == "spellText" or s == "auraText" or s == "spellCd" or s == "auraTime" then
        e.txFS:SetText(v)
        return
    end
    if count then
        TX.Write(e, TX.CountText(e, v), false)
    else
        TX.Write(e, v, false)
    end
end

-- What the sidebar and the layout cards say about an element.
function TX.Describe(rec)
    local s = TX.Source(rec)
    local d = rec.driver or {}
    if s == "static" then return (d.text and d.text ~= "") and ('"' .. d.text .. '"') or "words" end
    if s == "spellText" or s == "auraText" then
        local nm = d.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(d.spellID) -- raw-id: the typed spell, as the editor shows it
        if IsSecret(nm) or type(nm) ~= "string" then nm = nil end
        local what = nm or (d.spellID and tostring(d.spellID)) or ((s == "spellText") and "no spell" or "no aura")
        local WL = (s == "spellText") and Schema.TEXT_SPELL_WHEN_LABELS or Schema.TEXT_AURA_WHEN_LABELS
        local when = ((WL and WL[TX.When(rec)]) or ""):lower()
        local words = (d.text and d.text ~= "") and ('"' .. d.text .. '"') or "no words yet"
        return words .. " (" .. what .. ", " .. when .. ")"
    end
    local L = Schema.TEXT_SOURCE_LABELS or {}
    local base = L[s] or s
    local unit = d.unit or "player"
    if (s == "health" or s == "name") and unit ~= "player" then
        local O = NS.Options
        base = base .. " of " .. ((O and O.HealthUnitLabel and O.HealthUnitLabel(unit)) or tostring(unit))
    end
    if s == "power" or s == "health" then
        local SL = Schema.TEXT_SHOW_LABELS or {}
        base = base .. ", " .. (SL[d.show or "current"] or d.show or "current"):lower()
    elseif s == "spellCd" or s == "spellCharges" then
        local nm = d.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(d.spellID) -- raw-id: the typed spell, as the editor shows it
        if IsSecret(nm) then nm = nil end
        base = base .. ": " .. (nm or (d.spellID and ("spell " .. d.spellID)) or "no spell")
    elseif AURA[s] then
        base = base .. ": " .. (d.spellID and tostring(d.spellID) or "no aura")
    elseif s == "rules" then
        local n = type(d.rules) == "table" and #d.rules or 0
        base = base .. ", " .. n .. (n == 1 and " rule" or " rules")
    end
    return base
end

Bars.RegisterKind("text", {
    Build = TX.Build,
    Ensure = TX.Ensure,
    Refresh = TX.Refresh,
    Release = TX.Release,
    Styled = TX.Styled,
    Diag = TX.Diag,
    ownsName = true,
    PreviewModes = TX.PreviewModes,
    PreviewApply = TX.PreviewApply,
})
