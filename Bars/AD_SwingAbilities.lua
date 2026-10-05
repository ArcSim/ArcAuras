-- AD_SwingAbilities: next-swing abilities (Raptor Strike, Heroic Strike, Cleave, Maul) marked on a main-hand swing bar.
-- Owns the markers, their rulers, window curves and shadows; the bars runtime calls in through Bars.SwingAbil when it styles or releases a swing bar.
-- A spell's cooldown start and duration are secret in combat on Forever, so the remaining time only ever reaches SetValue and EvaluateRemainingDuration.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.SwingClock and K.MakeShadow) then return end
local Events = NS.Events

local SA = {}
Bars.SwingAbil = SA

local KEY = "adswingabil"
local MAIN_HAND, OFF_HAND = 0, 1
local EVENTS = { "PLAYER_SWING", "SPELL_UPDATE_COOLDOWN", "CURRENT_SPELL_CAST_CHANGED", "SPELLS_CHANGED" }
local COL = {
    gold  = { 1.00, 0.82, 0.20 },
    amber = { 1.00, 0.55, 0.15 },
    green = { 0.30, 0.95, 0.35 },
    cyan  = { 0.247, 0.788, 0.949 },
    red   = { 0.90, 0.25, 0.25 },
}
-- A window curve ramps over EPS seconds; the last window never closes.
local EPS, BIG = 0.001, 1e6
-- Tick to icon in UI units; each further ability sits one icon further out.
local GAP = 6
-- The editor preview's samples: 0 is the swing's start, 1 where it lands;
-- kind names the marker (its switch and its colour in L.col).
local SAMPLES = {
    stay = {
        { at = 0.28, kind = "queued" },
        { at = 0.56, kind = "later", badge = "+1" },
        { at = 0.84, kind = "ready" },
    },
    jump = {
        { at = 0.22, kind = "now" },
        { at = 0.56, kind = "later", badge = "+1" },
        { at = 1, kind = "queued" },
    },
    -- plus a queued one riding the preview's own fill
    follow = {
        { at = 0.56, kind = "later", badge = "+1" },
        { at = 0.84, kind = "ready" },
    },
}
local armed = false

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A stored colour, else the default; opacity 1 when it gives none.
local function ColorOf(c, d)
    if type(c) ~= "table" then c = d end
    return { tonumber(c[1]) or d[1], tonumber(c[2]) or d[2], tonumber(c[3]) or d[3], tonumber(c[4]) or 1 }
end

-- A secret boolean throws on a test, so it answers no.
local function Yes(v)
    return not IsSecret(v) and v == true
end

local function Wanted(rec)
    return rec.barKind == "swing" and ((rec.driver and rec.driver.swingType) or 0) == MAIN_HAND
        and K.R(rec, "fill", "swingAbilities") == true
end

-- The spellbook's answer; the older globals wrap it. A client with neither
-- counts every spell as known.
local function Known(sid)
    local SB = C_SpellBook
    if SB and SB.IsSpellKnown then return Yes(SB.IsSpellKnown(sid)) end
    if not (IsPlayerSpell or IsSpellKnown) then return true end
    return Yes(IsPlayerSpell and IsPlayerSpell(sid)) or Yes(IsSpellKnown and IsSpellKnown(sid))
end

-- Ranks are separate spell IDs on ranked realms: the spell's name finds the
-- rank the player knows. Returns the ID to track and whether it is known.
local function Resolve(id)
    local sid = tonumber(id)
    if not sid or sid <= 0 then return nil end
    local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
    if C_Spell.GetSpellIDForSpellIdentifier and not IsSecret(nm) and type(nm) == "string" and nm ~= "" then
        local rid = C_Spell.GetSpellIDForSpellIdentifier(nm)
        if not IsSecret(rid) and type(rid) == "number" and rid > 0 then return rid, Known(rid) end
    end
    return sid, Known(sid)
end
-- the swing colours find their ranks the same way
SA.Resolve = Resolve

-- Every rank of a spell the player knows, lowest first: { { id, rank } },
-- rank nil when the game names none. Forever's spellbook lists every rank
-- (Core\AD_SpellCatalog.lua relies on it); "<name>(Rank N)" through the
-- resolver backs it up, kept only when the spell's own rank text agrees.
-- Retail has no ranks: a spell is its one rank. Cached by name until the
-- spellbook changes (SA.ForgetRanks).
local MAX_RANK = 20
local rankCache = {}

local function RankText(v)
    if IsSecret(v) or type(v) ~= "string" then return nil end
    return tonumber(v:match("(%d+)"))
end

local function RankOf(sid)
    return RankText(C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(sid))
end

local function Ranks(id)
    local sid = tonumber(id)
    local nm = sid and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
    if IsSecret(nm) or type(nm) ~= "string" or nm == "" then return {} end
    if rankCache[nm] then return rankCache[nm] end
    local out, seen = {}, {}
    local function Add(rid, n)
        if seen[rid] or not Known(rid) then return end
        seen[rid] = true
        out[#out + 1] = { id = rid, rank = n }
    end
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if bank and SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        for li = 1, SB.GetNumSpellBookSkillLines() or 0 do
            local line = SB.GetSpellBookSkillLineInfo(li)
            if line and line.itemIndexOffset and line.numSpellBookItems then
                for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local item = SB.GetSpellBookItemInfo(i, bank)
                    local rid = item and (item.spellID or item.actionID)
                    if type(rid) == "number" and not IsSecret(rid) and C_Spell.GetSpellName(rid) == nm then
                        Add(rid, RankText(item.subName) or RankOf(rid))
                    end
                end
            end
        end
    end
    if C_Spell.GetSpellIDForSpellIdentifier then
        for n = 1, MAX_RANK do
            local rid = C_Spell.GetSpellIDForSpellIdentifier(("%s(Rank %d)"):format(nm, n))
            if not IsSecret(rid) and type(rid) == "number" and rid > 0 then
                local own = RankOf(rid)
                if own == nil or own == n then Add(rid, n) end
            end
        end
    end
    table.sort(out, function(a, b) return (a.rank or MAX_RANK + 1) < (b.rank or MAX_RANK + 1) end)
    rankCache[nm] = out
    return out
end
SA.Ranks = Ranks

function SA.ForgetRanks()
    rankCache = {}
end

-- The spell IDs whose queue counts for an ability. pick: 0 (or nil) any rank
-- the player knows, -1 the highest (the one its name resolves to), n that
-- rank, the highest while that rank is not known.
function SA.QueueIDs(id, pick)
    local sid = Resolve(id)
    if not sid then return {} end
    pick = tonumber(pick) or 0
    if pick == 0 then
        local out, has = {}, false
        for _, r in ipairs(Ranks(id)) do
            out[#out + 1] = r.id
            if r.id == sid then has = true end
        end
        if not has then out[#out + 1] = sid end
        return out
    elseif pick > 0 then
        for _, r in ipairs(Ranks(id)) do
            if r.rank == pick then return { r.id } end
        end
    end
    return { sid }
end

-- Queued on the next swing at any of these ranks.
local function Queued(ids)
    if not (C_Spell.IsCurrentSpell and ids) then return false end
    for _, q in ipairs(ids) do
        if Yes(C_Spell.IsCurrentSpell(q)) then return true end
    end
    return false
end

-- list: every typed ability (the preview wears their icons); tracked: the
-- ones the player knows, one marker row each. Each one's rank pick
-- (rec.driver.swingAbilRanks, by position) says which queued ranks count.
local function ResolveList(L, rec)
    local ids = rec.driver and rec.driver.swingAbilIDs
    local picks = rec.driver and rec.driver.swingAbilRanks
    local list, tracked = {}, {}
    if type(ids) == "table" then
        for i, id in ipairs(ids) do
            local sid, known = Resolve(id)
            if sid then
                local a = { sid = sid, icon = (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or 134400,
                    qids = SA.QueueIDs(id, type(picks) == "table" and picks[i] or 0) }
                list[#list + 1] = a
                if known then tracked[#tracked + 1] = a end
            end
        end
    end
    L.list, L.tracked = list, tracked
end

local function NewCurve()
    local c = C_CurveUtil.CreateCurve()
    if c.SetType and Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
    return c
end

-- 1 while the remaining time is inside [lo, hi), 0 outside it.
local function SetWindow(c, lo, hi)
    c:ClearPoints()
    c:AddPoint(lo - EPS, 0)
    c:AddPoint(lo, 1)
    c:AddPoint(hi - EPS, 1)
    c:AddPoint(hi, 0)
end

-- A marker's geometry, from settings and whole pixels only. The tick rides
-- its ruler's fill edge, and nothing on that chain is ever read back: an edge
-- placed by a secret value has a secret rect.
local function Shape(L, m)
    local bar, t, half = m.bar, m.tick, L.half
    m:SetFrameLevel(L.level + 1)
    bar:SetFrameLevel(L.level + 2)
    bar:ClearAllPoints()
    -- half a tick in from each end, so a tick at either end stays on the bar
    if L.vertical then
        bar:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -half)
        bar:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, half)
    else
        bar:SetPoint("TOPLEFT", m, "TOPLEFT", half, 0)
        bar:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -half, 0)
    end
    bar:SetOrientation(L.vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(L.flip)
    t:ClearAllPoints()
    if L.vertical then
        local edge = L.flip and "BOTTOM" or "TOP"
        t:SetPoint("TOPLEFT", m.tex, edge .. "LEFT", 0, half)
        t:SetPoint("BOTTOMRIGHT", m.tex, edge .. "RIGHT", 0, -half)
    else
        local edge = L.flip and "LEFT" or "RIGHT"
        t:SetPoint("TOPLEFT", m.tex, "TOP" .. edge, -half, 0)
        t:SetPoint("BOTTOMRIGHT", m.tex, "BOTTOM" .. edge, half, 0)
    end
    -- above a flat bar, right of a standing one
    local sz = L.iconSize
    local lift = L.gap + (m.row - 1) * sz
    m.icon:ClearAllPoints()
    m.icon:SetSize(sz, sz)
    if L.vertical then
        m.icon:SetPoint("LEFT", t, "RIGHT", lift, 0)
    else
        m.icon:SetPoint("BOTTOM", t, "TOP", 0, lift)
    end
    m.rim:ClearAllPoints()
    m.rim:SetPoint("TOPLEFT", m.icon, "TOPLEFT", -half, half)
    m.rim:SetPoint("BOTTOMRIGHT", m.icon, "BOTTOMRIGHT", half, -half)
end

-- A queued marker riding a swing: its tick sits on that fill's moving edge,
-- so the game carries it to where the swing lands with no reads. Shape puts
-- the icon on the tick, so the icon rides too.
local function Ride(L, m, tex, reverse)
    local t, half = m.tick, L.half
    t:ClearAllPoints()
    if L.vertical then
        local edge = reverse and "BOTTOM" or "TOP"
        t:SetPoint("TOPLEFT", tex, edge .. "LEFT", 0, half)
        t:SetPoint("BOTTOMRIGHT", tex, edge .. "RIGHT", 0, -half)
    else
        local edge = reverse and "LEFT" or "RIGHT"
        t:SetPoint("TOPLEFT", tex, "TOP" .. edge, -half, 0)
        t:SetPoint("BOTTOMRIGHT", tex, "BOTTOM" .. edge, half, 0)
    end
    m:SetAlpha(1)
    m:Show()
end

-- row: which ability's icon row the marker's icon sits on.
local function NewMark(L, row)
    local m = CreateFrame("Frame", nil, L.host)
    m:SetAllPoints(L.host)
    m:EnableMouse(false)
    m:Hide()
    m.row = row
    m.bar = CreateFrame("StatusBar", nil, m)
    m.bar:EnableMouse(false)
    m.bar:SetStatusBarTexture(K.WHITE)
    m.bar:SetStatusBarColor(0, 0, 0, 0)
    m.bar:SetMinMaxValues(0, 1)
    m.tex = m.bar:GetStatusBarTexture()
    m.tick = m:CreateTexture(nil, "OVERLAY", nil, 3)
    m.rim = m:CreateTexture(nil, "OVERLAY", nil, 4)
    m.rim:SetColorTexture(0, 0, 0, 0.9)
    m.icon = m:CreateTexture(nil, "OVERLAY", nil, 5)
    m.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    m.badge = m:CreateFontString(nil, "OVERLAY")
    m.badge:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    m.badge:SetPoint("LEFT", m.icon, "RIGHT", 1, 0)
    L.marks[#L.marks + 1] = m
    Shape(L, m)
    return m
end

-- The marker's colour on its tick and count; the icon wears it too, or keeps
-- the spell's own colours with the marker's colour as its outline. The
-- colour's opacity reaches all of them.
local function Paint(L, m, icon, color, badge)
    local a = color[4] or 1
    m.tick:SetColorTexture(color[1], color[2], color[3], 0.95 * a)
    m.icon:SetTexture(icon)
    if L.ownIcons then
        m.icon:SetVertexColor(1, 1, 1)
        m.rim:SetColorTexture(color[1], color[2], color[3], a)
    else
        m.icon:SetVertexColor(color[1], color[2], color[3])
        m.rim:SetColorTexture(0, 0, 0, 0.9 * a)
    end
    m.icon:SetAlpha(a)
    if badge then
        m.badge:SetText(badge)
        m.badge:SetTextColor(color[1], color[2], color[3], a)
        m.badge:Show()
    else
        m.badge:Hide()
    end
end

-- A marker at a plain point of the swing.
local function Place(m, at)
    m.bar:SetMinMaxValues(0, 1)
    m.bar:SetValue(at)
    m:SetAlpha(1)
    m:Show()
end

local function HideSlot(S)
    for _, m in ipairs(S.rulers) do m:Hide() end
    S.endGo:Hide()
    S.endFar:Hide()
    S.spot:Hide()
    S.ride:Hide()
end

local function HideLive(L)
    for _, S in pairs(L.slots) do HideSlot(S) end
end

local function HidePreview(L)
    for _, m in ipairs(L.pv) do m:Hide() end
    if L.pvRide then L.pvRide:Hide() end
end

-- The widgets live on the shell, which can outlive the entry that built them.
local function Ensure(shell)
    local L = shell._adSA
    if L then return L end
    L = { slots = {}, marks = {}, pv = {}, list = {}, tracked = {}, gen = 0 }
    L.host = CreateFrame("Frame", nil, shell)
    L.host:EnableMouse(false)
    shell._adSA = L
    return L
end

-- One set of markers per tracked ability. The shadow's OnCooldownDone stamps
-- the plain moment it came back; a feed's own zero span is ignored.
local function EnsureSlot(L, i)
    local S = L.slots[i]
    if S then return S end
    S = { rulers = {}, curves = {}, fedAt = 0 }
    S.endGo = NewMark(L, i)
    S.endFar = NewMark(L, i)
    S.spot = NewMark(L, i)
    S.ride = NewMark(L, i)
    S.farCurve = NewCurve()
    S.shadow = K.MakeShadow()
    S.shadow:SetScript("OnCooldownDone", function()
        if not L.on then return end
        local t = GetTime()
        if t - S.fedAt > 0.05 then
            S.readyAt = t
            if Events then Events.Coalesce(KEY, SA.PaintAll) end
        end
    end)
    L.slots[i] = S
    return S
end

-- One ruler per swing from this one to n ahead.
local function Rulers(L, S, i, n)
    for k = #S.rulers + 1, n + 1 do
        S.rulers[k] = NewMark(L, i)
        S.curves[k] = NewCurve()
    end
end

local function PaintSlot(L, i, a, sStart, sDur, now)
    local S = EnsureSlot(L, i)
    if S.sid ~= a.sid then
        S.sid, S.readyAt, S.lastCDSeen = a.sid, nil, nil
    end
    local e = now - sStart
    -- The GCD-free duration, so another ability's GCD never reads as this
    -- one's cooldown; the shadow's IsShown answers plainly.
    local dur = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(a.sid, true)
    local onCD
    if dur then
        S.fedAt = now
        S.shadow:SetCooldownFromDurationObject(dur, true)
        onCD = S.shadow:IsShown() == true
    else
        local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(a.sid)
        onCD = info ~= nil and Yes(info.isActive) and not Yes(info.isOnGCD)
    end
    -- The ready moment as a plain stamp: the shadow's own, else the first
    -- paint that sees it ready. Never seen on cooldown = ready before this swing.
    if onCD then
        S.lastCDSeen = now
    elseif not S.lastCDSeen then
        S.readyAt = S.readyAt or 0
    elseif not S.readyAt or S.readyAt < S.lastCDSeen then
        S.readyAt = now
    end
    -- Queued (its marker on) or ready: one marker. A queued one with its
    -- marker off shows as ready while it is off cooldown.
    local queued = L.queuedOn and Queued(a.qids or { a.sid })
    if queued or not onCD then
        HideSlot(S)
        if not (queued or L.readyOn) then return end
        local col = queued and L.col.queued or L.col.ready
        -- riding: queued only; a ready one stays where it came back
        if queued and L.place == "follow" and L.rideTex then
            Paint(L, S.ride, a.icon, col, nil)
            Ride(L, S.ride, L.rideTex, L.rideRev)
            return
        end
        local m, at
        if L.place == "jump" then
            m, at = S.endGo, 1
        else
            -- where it came back in this swing, or the start when earlier
            m, at = S.spot, 0
            if S.readyAt and S.readyAt > sStart then at = math.min(1, (S.readyAt - sStart) / sDur) end
        end
        Paint(L, m, a.icon, col, nil)
        Place(m, at)
        return
    end
    if not (dur and L.cdOn) then
        HideSlot(S)
        return
    end
    -- Swing k's ruler spans the remaining times that end inside swing k, so its
    -- fill edge stands where the cooldown ends; its window curve shows it only
    -- for the swing that holds it. Both hold until the next swing or change.
    local R = dur:GetRemainingDuration()
    local n = L.ahead
    Rulers(L, S, i, n)
    for k = 0, n do
        local m, c = S.rulers[k + 1], S.curves[k + 1]
        local lo, hi = k * sDur - e, (k + 1) * sDur - e
        m.bar:SetMinMaxValues(lo, hi)
        m.bar:SetValue(R)
        Paint(L, m, a.icon, k == 0 and L.col.now or L.col.later, (k > 0 and L.badgeOn) and ("+" .. k) or nil)
        SetWindow(c, lo, hi)
        m:SetAlpha(dur:EvaluateRemainingDuration(c))
        m:Show()
    end
    for k = n + 2, #S.rulers do S.rulers[k]:Hide() end
    S.endGo:Hide()
    S.spot:Hide()
    -- a queued one that just fired: its rider would keep following the fill
    S.ride:Hide()
    local far = S.endFar
    if not L.farOn then
        far:Hide()
        return
    end
    Paint(L, far, a.icon, L.col.far, nil)
    far.bar:SetMinMaxValues(0, 1)
    far.bar:SetValue(1)
    SetWindow(S.farCurve, (n + 1) * sDur - e, BIG)
    far:SetAlpha(dur:EvaluateRemainingDuration(S.farCurve))
    far:Show()
end

-- The fill a queued marker rides: the main hand's, or the off-hand track's
-- while it runs and was asked for or lands first. Both clocks are plain.
local function RideTarget(e, L, mhEnd)
    local o = e.oh
    local ohRuns = o ~= nil and o.active and o.running and o.endTime ~= nil
    if ohRuns and (L.follow == "oh" or (L.follow == "first" and o.endTime < mhEnd)) then
        return o.follow:GetStatusBarTexture(), o.reverse
    end
    return e.shell.fill:GetStatusBarTexture(), L.mainRev
end

-- Markers draw only while the bar's own swing clock runs.
local function PaintLive(e)
    local L = e.sa
    if not (L and L.on) then return end
    local sStart, sDur, sEnd = K.SwingClock(e)
    if not sStart or not (C_CurveUtil and C_CurveUtil.CreateCurve) then
        HideLive(L)
        return
    end
    L.rideTex, L.rideRev = RideTarget(e, L, sEnd)
    local now = GetTime()
    for i, a in ipairs(L.tracked) do PaintSlot(L, i, a, sStart, sDur, now) end
    for i, S in pairs(L.slots) do
        if i > #L.tracked then HideSlot(S) end
    end
end

-- The samples follow the bar's switches and colours: a marker switched off
-- has no sample.
local function PaintPreview(L, e)
    if L.place == "follow" and L.queuedOn then
        L.pvRide = L.pvRide or NewMark(L, 1)
        local a = L.list[1]
        Paint(L, L.pvRide, a and a.icon or 134400, L.col.queued, nil)
        Ride(L, L.pvRide, e.shell.fill:GetStatusBarTexture(), L.mainRev)
    elseif L.pvRide then
        L.pvRide:Hide()
    end
    local set = SAMPLES[L.place] or SAMPLES.stay
    for i, s in ipairs(set) do
        local m = L.pv[i]
        if not m then
            m = NewMark(L, 1)
            L.pv[i] = m
        end
        if L.show[s.kind] then
            local a = L.list[i] or L.list[1]
            Paint(L, m, a and a.icon or 134400, L.col[s.kind], L.badgeOn and s.badge or nil)
            Place(m, s.at)
        else
            m:Hide()
        end
    end
    -- a shorter sample set leaves no sample from the last one behind
    for i = #set + 1, #L.pv do L.pv[i]:Hide() end
end

function SA.PaintAll()
    K.ForEach("swing", function(e)
        if e.sa and e.sa.on then PaintLive(e) end
    end)
end

local function AnyLive()
    local any = false
    K.ForEach("swing", function(e)
        if e.sa and e.sa.on and K.SwingClock(e) then any = true end
    end)
    return any
end

local function OnSwing(_, duration, swingType)
    if IsSecret(duration) or IsSecret(swingType) then return end
    -- an off-hand swing can change which swing lands first
    if swingType == OFF_HAND then
        local ride = false
        K.ForEach("swing", function(e)
            local L = e.sa
            if L and L.on and L.place == "follow" and L.follow ~= "mh" then ride = true end
        end)
        if ride then Events.Coalesce(KEY, SA.PaintAll) end
        return
    end
    if swingType ~= MAIN_HAND then return end
    if type(duration) ~= "number" or duration <= 0 then return end
    K.ForEach("swing", function(e)
        local L = e.sa
        if L and L.on then
            L.gen = L.gen + 1
            local gen = L.gen
            -- a swing that lands with no new one after it leaves nothing to mark
            C_Timer.After(duration + 0.05, function()
                if L.gen == gen and not K.SwingClock(e) then HideLive(L) end
            end)
        end
    end)
    -- next frame: the bars runtime starts the swing clock in its own handler
    Events.Coalesce(KEY, SA.PaintAll)
end

local function OnCooldown()
    if AnyLive() then Events.Coalesce(KEY, SA.PaintAll) end
end

-- A learned rank is a new spell ID.
local function OnSpells()
    Events.Coalesce(KEY .. "_spells", function()
        SA.ForgetRanks()
        K.ForEach("swing", function(e)
            if e.sa and e.sa.on then ResolveList(e.sa, e.rec) end
        end)
        SA.PaintAll()
    end)
end

-- Listening while a live bar has abilities typed in, known yet or not: a
-- login can resolve them before the spellbook has loaded.
function SA.SyncEvents()
    local want = false
    if C_SwingTimer and Events then
        K.ForEach("swing", function(e)
            if e.sa and e.sa.on and #e.sa.list > 0 then want = true end
        end)
    end
    if want == armed then return end
    armed = want
    if want then
        Events.On("PLAYER_SWING", KEY, OnSwing)
        Events.On("SPELL_UPDATE_COOLDOWN", KEY, OnCooldown)
        K.SafeOn("CURRENT_SPELL_CAST_CHANGED", KEY, OnCooldown)
        Events.On("SPELLS_CHANGED", KEY, OnSpells)
    else
        for _, ev in ipairs(EVENTS) do Events.Off(ev, KEY) end
    end
end

local function Stop(L)
    L.on = false
    L.gen = L.gen + 1
    HideLive(L)
    HidePreview(L)
    for _, S in pairs(L.slots) do S.shadow:Clear() end
    L.host:Hide()
end

-- Called at the end of every style pass, after the off-hand track and the
-- closing halves have laid the main fill.
function SA.Styled(e)
    local shell, rec = e.shell, e.rec
    if not Wanted(rec) then
        if shell._adSA then Stop(shell._adSA) end
        e.sa = nil
        SA.SyncEvents()
        return
    end
    local L = Ensure(shell)
    e.sa = L
    L.on = true
    -- the main fill's rect, which the off-hand track or the closing halves may have cut
    L.host:ClearAllPoints()
    L.host:SetAllPoints(shell.fill)
    L.level = shell.overlay:GetFrameLevel() + 1
    L.host:SetFrameLevel(L.level)
    L.host:Show()
    L.vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    -- Rulers run from a swing's start to where it lands: the fill's own way,
    -- or against it on a drain bar, whose edge travels back.
    local drain = (K.R(rec, "fill", "fillMode") or "drain") == "drain"
    L.flip = (K.R(rec, "fill", "reverseFill") == true) ~= drain
    L.place = K.R(rec, "fill", "swingAbilPlace") or "stay"
    -- which markers show (each on unless switched off), their colours and
    -- whether the icons keep the spell's own colours
    L.cdOn = K.R(rec, "fill", "swingAbilCD") ~= false
    L.badgeOn = K.R(rec, "fill", "swingAbilBadge") ~= false
    L.farOn = L.cdOn and K.R(rec, "fill", "swingAbilFar") ~= false
    L.readyOn = K.R(rec, "fill", "swingAbilReady") ~= false
    L.queuedOn = K.R(rec, "fill", "swingAbilQueued") ~= false
    L.show = { now = L.cdOn, later = L.cdOn, ready = L.readyOn, queued = L.queuedOn }
    L.ownIcons = K.R(rec, "fill", "swingAbilTint") == "own"
    L.col = {
        now = ColorOf(K.R(rec, "fill", "swingAbilColorNow"), COL.gold),
        later = ColorOf(K.R(rec, "fill", "swingAbilColorLater"), COL.amber),
        far = ColorOf(K.R(rec, "fill", "swingAbilColorFar"), COL.red),
        ready = ColorOf(K.R(rec, "fill", "swingAbilColorReady"), COL.green),
        queued = ColorOf(K.R(rec, "fill", "swingAbilColorQueued"), COL.cyan),
    }
    L.follow = K.R(rec, "fill", "swingAbilFollow") or "mh"
    -- the real fill's direction: a riding tick sits on its moving edge
    L.mainRev = K.R(rec, "fill", "reverseFill") == true
    local ahead = tonumber(K.R(rec, "fill", "swingAbilAhead")) or 4
    L.ahead = math.max(1, math.min(6, math.floor(ahead)))
    local px = K.Px(shell)
    -- two pixels across, each at least one of this frame's own
    L.half = Bars.StripPx(shell, 1)
    L.iconSize = math.max(px, math.floor((K.R(rec, "fill", "swingAbilIconSize") or 25) / px + 0.5) * px)
    L.gap = math.floor(GAP / px + 0.5) * px
    ResolveList(L, rec)
    for _, m in ipairs(L.marks) do Shape(L, m) end
    if e.isPreview then
        HideLive(L)
        PaintPreview(L, e)
    else
        HidePreview(L)
        PaintLive(e)
    end
    SA.SyncEvents()
end

function SA.Release(e)
    if e.sa then Stop(e.sa) end
    e.sa = nil
    SA.SyncEvents()
end

-- Editing a bar's own list: rec.driver.swingAbilIDs (spell IDs in order) and
-- rec.driver.swingAbilRanks (each one's rank pick, by position, nil while
-- every pick is "any rank"). Every edit marks the bar for one style refresh.
function SA.Max()
    return (NS.Schema and NS.Schema.SWING_ABIL_MAX) or 8
end

-- { { id, rank } } in order, rank 0 for any rank.
function SA.List(rec)
    local d = rec and rec.driver
    local ids, picks = d and d.swingAbilIDs, d and d.swingAbilRanks
    local out = {}
    if type(ids) ~= "table" then return out end
    for i, id in ipairs(ids) do
        out[#out + 1] = { id = id, rank = (type(picks) == "table" and tonumber(picks[i])) or 0 }
    end
    return out
end

local function Write(rec, list)
    rec.driver = rec.driver or {}
    local ids, picks, any = {}, {}, false
    for i, a in ipairs(list) do
        ids[i], picks[i] = a.id, a.rank or 0
        if picks[i] ~= 0 then any = true end
    end
    rec.driver.swingAbilIDs = (#ids > 0) and ids or nil
    rec.driver.swingAbilRanks = any and picks or nil
    if NS.Store and NS.Store.Dirty then NS.Store.Dirty("style", rec.id) end
end

-- false when the list is full or already holds that spell
function SA.Add(rec, id)
    id = tonumber(id)
    if not (rec and id and id > 0) then return false end
    local list = SA.List(rec)
    if #list >= SA.Max() then return false end
    for _, a in ipairs(list) do
        if a.id == id then return false end
    end
    list[#list + 1] = { id = math.floor(id), rank = 0 }
    Write(rec, list)
    return true
end

function SA.Remove(rec, i)
    local list = SA.List(rec)
    if not list[i] then return false end
    table.remove(list, i)
    Write(rec, list)
    return true
end

-- pick: 0 any rank, -1 the highest, n that rank
function SA.SetRank(rec, i, pick)
    local list = SA.List(rec)
    pick = math.floor(tonumber(pick) or 0)
    if not list[i] or list[i].rank == pick then return false end
    list[i].rank = pick
    Write(rec, list)
    return true
end
