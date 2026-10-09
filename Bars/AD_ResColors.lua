-- Arc Auras, all rights reserved: do not copy or adapt this code into another addon without permission.
-- AD_ResColors: a resource bar's states (Conditions > By State), one ordered list of rows. A row
-- holds while a spell has enough power, is usable, ready, recharging or on cooldown, while an aura
-- is up or missing, or while the power is at or below a value, at or above it, or full; it can
-- colour the fill and the texts, mark its spells' costs and glow. Fill and text: the highest row
-- that holds wins. Each glow shows while its row holds. Cost marks always show.
-- Bars\AD_Bars.lua asks CR.Pick for the fill colour and reads e.crText, and calls Styled, Visible
-- and Release at fixed points; Bars\AD_BarGlow.lua draws the glows of the rows CR.GlowRows names.
-- Aura presence is never read: an aura row's colour rides an engine lane of its own, as a bar
-- glow does. Power is never compared in Lua: a power row asks a curve of its own.
local ADDON, NS = ...
local Bars = NS.Bars
if not Bars then return end
local K = Bars.Kit
local Store = NS.Store
local Events = NS.Events

local CR = {}
Bars.ResColor = CR

CR.KEY = "adrescolor"
CR.WHEN = { "enough", "usable", "ready", "recharging", "cooldown", "up", "missing", "below", "above", "full" }
CR.SPELL = { enough = true, usable = true, ready = true, recharging = true, cooldown = true }
-- read off a shared spell watch's cooldown states
CR.CD = { ready = true, recharging = true, cooldown = true }
-- read off usability (IsSpellUsable is plain)
CR.USAB = { enough = true, usable = true }
CR.AURA = { up = true, missing = true }
CR.POWER = { below = true, above = true, full = true }
CR.LANE_KINDS = { "up", "miss" }
-- usability passes while power moves out of combat, at most this often
CR.USAB_GAP = 0.25
CR.MASK = "Interface\\Buttons\\WHITE8X8"
-- how far past the fill a missing layer's covering piece reaches
CR.REACH = 2
-- a power row's step, as the old band curves stepped
CR.EPS = 0.0001
CR.state = {}    -- [barId] = { rect, mask, up = {}, miss = {}, retired = {}, gen, entry, base, strata }
CR.queue = {}    -- [lane] = parked, filter edits waiting out combat
CR.watched = {}  -- [barId] = { [watch key] = true }
-- the row the editor's table has open: the preview wears it
CR.previewSel = nil

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function Yes(v) return not IsSecret(v) and v == true end

function CR.MaxRows() return (NS.Schema and NS.Schema.RES_STATE_MAX) or 12 end
function CR.MaxSpells() return (NS.Schema and NS.Schema.RES_STATE_SPELLS) or 8 end
function CR.MaxAuraFills() return (NS.Schema and NS.Schema.RES_AURA_FILL_MAX) or 4 end
local function Default() return (NS.Schema and NS.Schema.RES_COLOR_DEFAULT) or { 0.66, 0.42, 1, 1 } end

-- A record the rows belong to: one resource bar, never a proxy of several.
local function Own(rec)
    return rec ~= nil and rec.type == "bar" and rec.barKind == "resource" and not rec._adMulti
        and not rec._adLayoutTier and not rec._adDefaults
end

-- The rows in play: the look in play's own, else the bar's. Old colour
-- settings become rows first (Store.ConvertResStates, once per bar).
function CR.RowsOf(rec)
    if not Own(rec) then return nil end
    Store.ConvertResStates(rec)
    local LK = NS.Looks
    local list = (LK and LK.Rows(rec)) or (rec.driver and rec.driver.resColors)
    if type(list) ~= "table" or #list == 0 then return nil end
    return list
end

local function ColorOf(c, d)
    d = d or Default()
    if type(c) ~= "table" then c = d end
    return { tonumber(c[1]) or d[1], tonumber(c[2]) or d[2], tonumber(c[3]) or d[3], tonumber(c[4]) or 1 }
end

-- a spell row's spell as the game is asked about it: the rank you know
-- (unless pinned) and its override
local function RowSpell(sid, follow)
    sid = tonumber(sid)
    if not sid or sid <= 0 then return nil end
    sid = math.floor(sid)
    return Store.TrackedSpellID(sid, NS.IsForever == true and follow ~= false, false) or sid
end

-- The rows as the runtime reads them. An aura row colours the fill only on a
-- bar with one continuous fill, and only the first few (one lane each).
local function Build(list, rec)
    local S = NS.Schema
    local okFill = S ~= nil and S.ResColorsOK ~= nil and S.ResColorsOK(rec)
    local out, slot = {}, 0
    for _, r in ipairs(list) do
        if type(r) == "table" and #out < CR.MaxRows() then
            local w = Store.RES_STATE_WHEN[r.when] and r.when or "enough"
            local rr = { k = #out + 1, when = w, src = r, lua = not CR.AURA[w], glow = r.glow ~= nil,
                fill = (type(r.fill) == "table") and ColorOf(r.fill) or nil,
                text = (not CR.AURA[w] and type(r.text) == "table") and ColorOf(r.text, { 1, 1, 1, 1 }) or nil }
            if CR.SPELL[w] then
                rr.rowSpells = type(r.rowSpells) == "table" and r.rowSpells or {}
                rr.follow = r.follow
            end
            if CR.AURA[w] and rr.fill then
                if okFill and slot < CR.MaxAuraFills() then
                    slot = slot + 1
                    rr.slot = slot
                else
                    rr.fill = nil
                end
            end
            -- a row read each pass: one that changes something while it holds
            rr.needs = rr.lua and (rr.fill ~= nil or rr.text ~= nil or rr.glow)
            out[#out + 1] = rr
        end
    end
    return out
end

-- The share of the bar a power row names (0..1), or nil when it can never
-- hold: a percent, or power units over the plain cached max. As the old bands
-- drew, nothing holds at 0 or past the full bar but Full power.
local function RowShare(e, rr)
    if rr.when == "full" then return 1 end
    local v = tonumber(rr.src.value) or 0
    local p
    if rr.src.units then
        local mx = Bars.PlainMax and Bars.PlainMax(e)
        if not (mx and mx > 0) then return nil end
        p = v / mx
    else
        p = v / 100
    end
    if p <= 0 or p >= 1 then return nil end
    return p
end

-- One power row's curve: alpha 1 where it holds. UnitPowerPercent evaluates
-- it C-side, so the possibly secret value never reaches Lua; cached by share.
local function PowerCurve(rr, p)
    if rr.curve and rr.curveP == p then return rr.curve end
    local curve = C_CurveUtil.CreateColorCurve()
    local EPS = CR.EPS
    -- points rise along 0..1: a step's edge past either end is left out
    local last
    local function P(x, a)
        if x < 0 or x > 1 or (last and x <= last) then return end
        last = x
        curve:AddPoint(x, CreateColor(1, 1, 1, a))
    end
    if rr.when == "below" then
        P(0, 1) P(p, 1) P(p + EPS, 0) P(1, 0)
    elseif rr.when == "above" then
        P(0, 0) P(p - EPS, 0) P(p, 1) P(1, 1)
    else
        P(0, 0) P(1 - EPS, 0) P(1, 1)
    end
    rr.curve, rr.curveP = curve, p
    return curve
end

local function PowerHolds(e, rr)
    local p = RowShare(e, rr)
    if not p then return false end
    if e.isPreview then
        -- the preview's sample is plain: its share of the bar (PV.PaintResource)
        local s = e.pvShare
        if not s then return false end
        if rr.when == "below" then return s <= p end
        if rr.when == "above" then return s >= p end
        return s >= 1 - CR.EPS
    end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and K.CurveRGBA) then return false end
    local _, _, _, a = K.CurveRGBA(e, PowerCurve(rr, p))
    -- restricted power reads secret: no row holds, as no band drew
    return a ~= nil and a > 0.5
end

-- A spell row's state now: any of its spells. Usability is plain (no secret
-- annotation in the 12.1 docs); "enough" is a spell you know that is not
-- short of its power; the cooldown states ride the shared spell watch.
local function SpellHolds(rr)
    local w = rr.when
    if CR.CD[w] then
        local DC = NS.DriverCooldown
        if not (DC and DC.SpellState) then return false end
        for _, key in ipairs(rr.watches or {}) do
            local ready, rech, oncd = DC.SpellState(key)
            if (w == "ready" and ready == true) or (w == "recharging" and rech == true)
                or (w == "cooldown" and oncd == true) then
                return true
            end
        end
        return false
    end
    local CS = C_Spell
    if not (CS and CS.IsSpellUsable) then return false end
    for _, sid in ipairs(rr.rowSpells or {}) do
        local eff = RowSpell(sid, rr.follow)
        if eff then
            local usable, short = CS.IsSpellUsable(eff)
            if w == "usable" then
                if Yes(usable) then return true end
            elseif not IsSecret(short) and Store.KnowsSpell(eff) ~= false and short ~= true then
                return true
            end
        end
    end
    return false
end

-- Every row's state, then the fill colour of the highest row that holds (nil:
-- the bar's own) and the texts' (e.crText). The fill's winner (e.crWin)
-- darkens the aura rows under it; e.crColor is kept for the fold's second
-- lap. The editor's preview wears the row its table has open, and its power
-- rows follow the sample.
function CR.Pick(e)
    local rows = e.crRows
    if not rows then
        e.crColor, e.crText = nil, nil
        return nil
    end
    local pv = e.isPreview == true
    local sel = pv and CR.previewSel or nil
    local win, col, txt, moved = nil, nil, nil, false
    for k, rr in ipairs(rows) do
        local h = false
        if pv then
            h = (sel == k) or (CR.POWER[rr.when] == true and PowerHolds(e, rr))
        elseif rr.needs then
            if CR.POWER[rr.when] then h = PowerHolds(e, rr) else h = SpellHolds(rr) end
        end
        if rr.hold ~= h then
            rr.hold = h
            moved = true
        end
        if h then
            -- an aura row's colour is its lane's; in the preview it is the open row's
            if not col and rr.fill and (rr.lua or pv) then win, col = k, rr.fill end
            if not txt and rr.text then txt = rr.text end
        end
    end
    e.crColor, e.crText = col, txt
    if e.crWin ~= win then
        e.crWin = win
        CR.Visible(e)
    end
    if moved and not pv and Bars.Glow and Bars.Glow.RowsHeld then Bars.Glow.RowsHeld(e) end
    return col
end

-- a live bar's colour again, after a row's state may have moved; `always`:
-- after a restyle, which may have taken its last row away
local function Recolor(e, always)
    if (e.crRows or always) and not e.isPreview and K.live[e.rec.id] == e then K.ResourceRefresh(e) end
end

function CR.RecolorAll()
    for _, e in pairs(K.live) do
        if e.crUsab then Recolor(e) end
    end
end

-- The cooldown states ride the shared spell watch (DriverCooldown.WatchSpell),
-- one owner per bar, row and spell.
function CR.WatchFn(id)
    CR.wfn = CR.wfn or {}
    local fn = CR.wfn[id]
    if not fn then
        fn = function()
            local e = K.live[id]
            if e then Recolor(e) end
        end
        CR.wfn[id] = fn
    end
    return fn
end

local function SyncWatches(id, rows)
    local DC = NS.DriverCooldown
    if not (DC and DC.WatchSpell) then return end
    local old, now = CR.watched[id], {}
    for k, rr in ipairs(rows or {}) do
        rr.watches = nil
        if CR.CD[rr.when] and rr.needs then
            for j, sid in ipairs(rr.rowSpells or {}) do
                local key = CR.KEY .. ":" .. tostring(id) .. ":" .. k .. ":" .. j
                DC.WatchSpell(key, sid, rr.follow, CR.WatchFn(id))
                now[key] = true
                rr.watches = rr.watches or {}
                rr.watches[#rr.watches + 1] = key
            end
        end
    end
    for key in pairs(old or {}) do
        if not now[key] then DC.UnwatchSpell(key) end
    end
    CR.watched[id] = next(now) and now or nil
end

-- Cost marks: every spell of a row with its mark on, in the rank and form the
-- game uses now (Bars\AD_Bars.lua lays them with the ticks).
function CR.MarkSpells(rec)
    local out, seen
    for _, r in ipairs(CR.RowsOf(rec) or {}) do
        if r.mark and CR.SPELL[r.when] then
            for _, sid in ipairs(r.rowSpells or {}) do
                local eff = RowSpell(sid, r.follow)
                if eff and not (seen and seen[eff]) then
                    seen = seen or {}
                    seen[eff] = true
                    out = out or {}
                    out[#out + 1] = eff
                end
            end
        end
    end
    return out
end

function CR.HasMarks(rec)
    for _, r in ipairs(CR.RowsOf(rec) or {}) do
        if r.mark and r.rowSpells then return true end
    end
    return false
end

-- Glows: the rows that carry one, in order, as many as a bar glows
-- (Bars\AD_BarGlow.lua: glow k is the k-th of these).
function CR.GlowRows(rec)
    local out
    local max = (NS.Schema and NS.Schema.BAR_GLOW_SLOTS) or 3
    for i, r in ipairs(CR.RowsOf(rec) or {}) do
        if type(r.glow) == "table" and not (out and #out >= max) then
            out = out or {}
            out[#out + 1] = i
        end
    end
    return out
end

-- Lanes: one engine container per aura row that colours the fill, made once
-- and never shown or hidden again (a row gone parks its filter and goes to
-- alpha 0). An up row's colour is on its button; a missing row's is on our own
-- frames, which its button's piece covers. Both are the bar's texture in the
-- row's colour, masked to the fill texture, so they follow the power with no
-- Lua per change. A lane is a slot: the first aura fill row is slot 1.

local function State(id)
    local st = CR.state[id]
    if not st then
        st = { up = {}, miss = {}, retired = {}, gen = 0 }
        CR.state[id] = st
    end
    return st
end

-- Slot s's place over the fill: the first on top.
function CR.Rung(s)
    return Bars.LADDER.rule + 2 * (CR.MaxAuraFills() - s)
end

-- Our frames on UIParent that every layer anchors to, re-pointed at the
-- current shell with no button write: rect = the fill's rect, mask = the fill
-- texture (how far the power reaches).
local function Followers(st, e)
    if not st.rect then
        st.rect = CreateFrame("Frame", nil, UIParent)
        st.rect:EnableMouse(false)
        st.mask = CreateFrame("Frame", nil, UIParent)
        st.mask:EnableMouse(false)
    end
    local sh = e.shell
    if st.rectOf ~= sh.fill then
        st.rectOf = sh.fill
        st.rect:ClearAllPoints()
        st.rect:SetPoint("TOPLEFT", sh.fill, "TOPLEFT", 0, 0)
        st.rect:SetPoint("BOTTOMRIGHT", sh.fill, "BOTTOMRIGHT", 0, 0)
    end
    -- a texture swap hands the fill a new texture object
    if st.maskOf ~= sh.fillTex then
        st.maskOf = sh.fillTex
        st.mask:ClearAllPoints()
        st.mask:SetPoint("TOPLEFT", sh.fillTex, "TOPLEFT", 0, 0)
        st.mask:SetPoint("BOTTOMRIGHT", sh.fillTex, "BOTTOMRIGHT", 0, 0)
    end
end

-- the look a layer wears: the bar's texture, turned as the fill turns, in the row's colour
local function LookOf(e, rr)
    local rec = e.rec
    local standing = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    return { path = K.ResolveBarTexture(K.R(rec, "fill", "texture")),
        rot = standing and K.R(rec, "fill", "rotateTexture") == true, c = rr.fill }
end

-- the bar's texture over the fill's rect, cut to the power's reach
local function MakeLayer(host, st)
    local L = {}
    L.tex = host:CreateTexture(nil, "ARTWORK")
    L.tex:SetPoint("TOPLEFT", st.rect, "TOPLEFT", 0, 0)
    L.tex:SetPoint("BOTTOMRIGHT", st.rect, "BOTTOMRIGHT", 0, 0)
    L.mask = host:CreateMaskTexture()
    L.mask:SetTexture(CR.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    L.mask:SetPoint("TOPLEFT", st.mask, "TOPLEFT", 0, 0)
    L.mask:SetPoint("BOTTOMRIGHT", st.mask, "BOTTOMRIGHT", 0, 0)
    L.tex:AddMaskTexture(L.mask)
    return L
end

local function LookSig(look)
    local c = look.c
    return look.path .. (look.rot and ":r:" or ":l:") .. c[1] .. "," .. c[2] .. "," .. c[3] .. "," .. (c[4] or 1)
end

local function PaintLayer(L, look)
    local sig = LookSig(look)
    if L.sig == sig then return end
    local c = look.c
    L.sig = sig
    L.tex:SetTexture(look.path)
    if look.rot then L.tex:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0) else L.tex:SetTexCoord(0, 1, 0, 1) end
    L.tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

-- Filter edits are data only; sent outside combat, never resent unchanged.
function CR.Refilter(lane, parked)
    if InCombatLockdown() then
        CR.queue[lane] = parked and true or false
        return
    end
    CR.queue[lane] = nil
    local DA = NS.DriverAura
    local shape = (not parked) and lane.shape or nil
    if not shape then parked = true end
    local c = lane.container
    if not parked and c.SetAuraSlotFilterString then
        local f = DA.FilterForLane(shape, lane)
        if lane.fstr ~= f then
            lane.fstr = f
            c:SetAuraSlotFilterString(lane.key, f)
        end
    end
    local ids = parked and { [0] = true } or DA.IncludeMap(shape)
    local sig = DA.FilterSig(ids)
    if lane.filterSig ~= sig then
        lane.filterSig = sig
        c:SetAuraSlotCandidateFilters(lane.key, { includeSpellIDs = ids })
    end
end

function CR.LevelButton(lane, b)
    local st = lane.st
    local lvl = (st.base or 1) + CR.Rung(lane.slot) + ((lane.kind == "miss") and 1 or 0)
    if st.strata then b:SetFrameStrata(st.strata) end
    b:SetFrameLevel(lvl)
    lane.level, lane.strata = lvl, st.strata
end

-- The init window, the one write that always lands: the button covers the
-- fill. An up row's layer is drawn on it; a missing row's button gets the
-- piece that covers its layer.
function CR.WireLane(lane, b)
    local st = lane.st
    b:EnableMouse(false)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", st.rect, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", st.rect, "BOTTOMRIGHT", 0, 0)
    CR.LevelButton(lane, b)
    if lane.kind == "miss" then
        local er = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        er:SetColorTexture(0, 0, 0, 0)
        er:SetBlendMode("DISABLE")
        er:SetPoint("TOPLEFT", st.rect, "TOPLEFT", -CR.REACH, CR.REACH)
        er:SetPoint("BOTTOMRIGHT", st.rect, "BOTTOMRIGHT", CR.REACH, -CR.REACH)
        lane.cover = er
        return
    end
    lane.layer = MakeLayer(b, st)
    if lane.look then PaintLayer(lane.layer, lane.look) end
end

-- a missing row's layer: our own frames, writable any time
function CR.PaintMiss(lane)
    local st = lane.st
    if not lane.look then return end
    local lvl = (st.base or 1) + CR.Rung(lane.slot)
    if st.strata then lane.stage:SetFrameStrata(st.strata) end
    lane.stage:SetFrameLevel(lvl)
    lane.host:SetFrameLevel(lvl)
    PaintLayer(lane.layer, lane.look)
end

-- false = not now (auras secret outside the login window, or no engine)
local function CanCreate()
    local DA = NS.DriverAura
    if not (DA and DA.IsAvailable and DA.IsAvailable() == true) then return false end
    return not (K.AuraSecretNow() and not Bars.loadWindow)
end

function CR.MakeLane(st, s, kind, shape, unit, harmful, look)
    if not CanCreate() then return nil end
    local DA = NS.DriverAura
    local lane = { kind = kind, slot = s, unit = unit, harmful = harmful, st = st,
        look = look, shape = shape, on = true }
    local parent
    if kind == "miss" then
        if not DA.EraserAvailable() then return nil end
        local stage = CreateFrame("Frame", nil, UIParent)
        stage:SetFlattensRenderLayers(true)
        -- set before the container is born inside it
        stage:SetIsFrameBuffer(true)
        stage:SetAlpha(0)
        stage:EnableMouse(false)
        stage:SetPoint("TOPLEFT", st.rect, "TOPLEFT", 0, 0)
        stage:SetPoint("BOTTOMRIGHT", st.rect, "BOTTOMRIGHT", 0, 0)
        local host = CreateFrame("Frame", nil, stage)
        host:EnableMouse(false)
        lane.stage, lane.host = stage, host
        lane.layer = MakeLayer(host, st)
        parent = stage
    end
    local c = DA.CreateIconContainer(unit, parent)
    if not c then
        if lane.stage then lane.stage:SetIsFrameBuffer(false) end
        return nil
    end
    c:SetAlpha(kind == "miss" and 1 or 0)
    lane.container = c
    st.gen = st.gen + 1
    lane.key = "adrescolor" .. s .. "_" .. tostring(st.id) .. "_" .. unit
        .. (harmful and "_h" or "_b") .. "_g" .. st.gen
    local ids = DA.IncludeMap(shape)
    lane.filterSig = DA.FilterSig(ids)
    lane.fstr = DA.FilterForLane(shape, lane)
    -- in place before the slot: its initializer can run inside AddAuraSlot
    st[kind][s] = lane
    c:AddAuraSlot(lane.key, lane.fstr, {
        maxFrameCount = 1,
        initializeFrame = function(b)
            lane.frame = b
            CR.WireLane(lane, b)
        end,
        candidateFilters = { includeSpellIDs = ids },
    })
    return lane
end

-- parked for good (its unit or aura type changed): a new lane takes its place
function CR.Retire(st, lane)
    lane.on, lane.retired = false, true
    st[lane.kind][lane.slot] = nil
    st.retired[#st.retired + 1] = lane
    CR.Refilter(lane, true)
    lane.container:SetAlpha(0)
    if lane.stage then lane.stage:SetAlpha(0) end
end

-- Slot s's aura lane of `kind`: made, kept in step with its row and the
-- bar's look, or parked.
function CR.SlotLane(st, e, s, kind, rr)
    local lane = st[kind][s]
    if not rr then
        if lane and lane.on then
            lane.on = false
            CR.Refilter(lane, true)
        end
        return
    end
    local DA = NS.DriverAura
    local shape = rr.src
    local unit, harmful = DA.LaneOf(shape)
    if lane and (lane.unit ~= unit or lane.harmful ~= harmful) then
        CR.Retire(st, lane)
        lane = nil
    end
    local look = LookOf(e, rr)
    if not lane then
        lane = CR.MakeLane(st, s, kind, shape, unit, harmful, look)
        if not lane then
            st.pending = true
            return
        end
    end
    lane.look, lane.shape, lane.on, lane.row = look, shape, true, rr.k
    CR.Refilter(lane, false)
    if kind == "miss" then CR.PaintMiss(lane) end
    local b = lane.frame
    if b then
        if DA.IsAccessible(b) then
            if lane.level ~= (st.base or 1) + CR.Rung(s) + ((kind == "miss") and 1 or 0)
                or lane.strata ~= st.strata then
                CR.LevelButton(lane, b)
            end
            if kind == "up" and lane.layer then PaintLayer(lane.layer, look) end
        elseif kind == "up" and lane.layer and lane.layer.sig ~= LookSig(look) then
            -- a new look waits for a pass where the button can be written
            st.pending = true
        end
    end
end

-- The live pass, at the end of every EnsureBar; a preview takes only the rows.
function CR.Styled(e)
    local rec = e.rec
    local id = rec.id
    local list = CR.RowsOf(rec)
    local rows = list and Build(list, rec) or nil
    -- crUsab: a row reads usability (its events); crAura: one rides a lane
    e.crRows, e.crUsab, e.crAura = rows, false, false
    if not rows then e.crColor, e.crText, e.crWin = nil, nil, nil end
    local bySlot = {}
    for _, rr in ipairs(rows or {}) do
        if rr.needs and CR.USAB[rr.when] then e.crUsab = true end
        if rr.slot then
            e.crAura = true
            bySlot[rr.slot] = rr
        end
    end
    if e.isPreview then return end
    SyncWatches(id, rows)
    local st = CR.state[id]
    if not (e.crAura or st) then
        CR.SyncEvents()
        Recolor(e, true)
        return
    end
    st = st or State(id)
    st.id, st.entry = id, e
    Followers(st, e)
    local lvl = e.shell.fill:GetFrameLevel()
    st.base = (type(lvl) == "number") and lvl or 1
    st.strata = e.shell:GetFrameStrata()
    st.pending = nil
    for s = 1, CR.MaxAuraFills() do
        local rr = bySlot[s]
        CR.SlotLane(st, e, s, "up", (rr and rr.when == "up") and rr or nil)
        CR.SlotLane(st, e, s, "miss", (rr and rr.when == "missing") and rr or nil)
    end
    CR.SyncEvents()
    CR.Visible(e)
    Recolor(e, true)
end

-- 12.1.0 shows an unfiltered aura on such a lane: it stays out.
local function Blind(lane)
    if not NS.AuraEngine1210 then return false end
    local DA = NS.DriverAura
    return DA ~= nil and DA.LaneBlindFor ~= nil and lane.shape ~= nil
        and DA.LaneBlindFor(lane.unit, lane.harmful, lane.shape) == true
end

-- The lanes hang off UIParent: they take the bar's shown alpha and, on
-- 12.1.0, the blind check through their own alpha; a row under the fill's
-- winner stays dark. A shell hidden by a secret flag is copied C-side.
function CR.Visible(e)
    if e.isPreview then return end
    local st = CR.state[e.rec.id]
    if not (st and st.entry == e) then return end
    local a = 0
    local sh = e.shell
    if sh and sh:IsVisible() then
        a = sh:GetEffectiveAlpha() or 1
        if IsSecret(a) then
            a = (e.holder and e.holder:GetEffectiveAlpha()) or 1
            if IsSecret(a) then a = 1 end
        end
    end
    local gate = e.shellGate
    for _, kind in ipairs(CR.LANE_KINDS) do
        for _, lane in pairs(st[kind]) do
            local la = a
            if not lane.on or (e.crWin ~= nil and (lane.row or 0) > e.crWin) then la = 0 end
            if kind == "up" and Blind(lane) then la = 0 end
            local f = (kind == "up") and lane.container or lane.stage
            if gate ~= nil and la > 0 and f.SetAlphaFromBoolean then
                f:SetAlphaFromBoolean(gate, 0, la)
                lane.alpha = nil
            elseif lane.alpha ~= la then
                lane.alpha = la
                f:SetAlpha(la)
            end
            if kind == "miss" then
                local ca = Blind(lane) and 0 or 1
                if lane.calpha ~= ca then
                    lane.calpha = ca
                    lane.container:SetAlpha(ca)
                end
            end
        end
    end
end

-- A target, focus, pet or party swap (Drivers\AD_DriverAura.lua): its lanes re-judge.
function CR.SyncUnit(unit)
    for _, st in pairs(CR.state) do
        local hit = false
        for _, kind in ipairs(CR.LANE_KINDS) do
            for _, lane in pairs(st[kind]) do
                if lane.unit == unit then hit = true end
            end
        end
        if hit and st.entry then CR.Visible(st.entry) end
    end
end

-- The bar left (unloaded, removed, rebuilt as another kind): its lanes park
-- and go dark, kept for its return; its watches go.
function CR.Release(e)
    if e.isPreview then return end
    local id = e.rec and e.rec.id
    if id then SyncWatches(id, nil) end
    e.crRows, e.crWin, e.crColor, e.crText = nil, nil, nil, nil
    local st = id and CR.state[id]
    if st and st.entry == e then
        st.entry = nil
        for _, kind in ipairs(CR.LANE_KINDS) do
            for _, lane in pairs(st[kind]) do
                lane.on = false
                CR.Refilter(lane, true)
                lane.alpha = 0
                lane.container:SetAlpha(0)
                if lane.stage then lane.stage:SetAlpha(0) end
            end
        end
    end
    CR.SyncEvents()
end

local function EachLive(fn)
    for _, st in pairs(CR.state) do
        if st.entry then fn(st) end
    end
end

function CR.Settle()
    for lane, parked in pairs(CR.queue) do CR.Refilter(lane, parked) end
    EachLive(function(st)
        if st.pending and not K.AuraSecretNow() then
            st.pending = nil
            CR.Styled(st.entry)
        end
    end)
    CR.SyncEvents()
end

-- Events: usability while a live bar has a row that reads it; the combat
-- edges while a filter edit or a lane waits.
function CR.SyncEvents()
    local usab = false
    for _, e in pairs(K.live) do
        if e.crUsab then usab = true end
    end
    if usab and not CR.usabArmed then
        CR.usabArmed = true
        Events.On("SPELL_UPDATE_USABLE", CR.KEY, function()
            Events.CoalesceCapped("adrescolor_usab", CR.RecolorAll, CR.USAB_GAP)
        end)
        -- a target swap moves what is usable at once
        Events.On("PLAYER_TARGET_CHANGED", CR.KEY, function()
            Events.CoalesceCapped("adrescolor_usab", CR.RecolorAll, CR.USAB_GAP, true)
        end)
    elseif not usab and CR.usabArmed then
        CR.usabArmed = false
        Events.Off("SPELL_UPDATE_USABLE", CR.KEY)
        Events.Off("PLAYER_TARGET_CHANGED", CR.KEY)
    end
    local waits = next(CR.queue) ~= nil
    EachLive(function(st) if st.pending then waits = true end end)
    if waits and not CR.settleArmed then
        CR.settleArmed = true
        Events.On("PLAYER_REGEN_ENABLED", CR.KEY, function() CR.Settle() end)
        Events.On("PLAYER_ENTERING_WORLD", CR.KEY, function() CR.Settle() end)
    elseif not waits and CR.settleArmed then
        CR.settleArmed = false
        Events.Off("PLAYER_REGEN_ENABLED", CR.KEY)
        Events.Off("PLAYER_ENTERING_WORLD", CR.KEY)
    end
end

-- True when a row of this bar rides an aura lane, for its fill or its glow
-- (the login prebuild asks).
function CR.WantsLanes(rec)
    local S = NS.Schema
    local okFill = S ~= nil and S.ResColorsOK ~= nil and S.ResColorsOK(rec)
    for _, r in ipairs(CR.RowsOf(rec) or {}) do
        if CR.AURA[r.when] and ((okFill and type(r.fill) == "table") or type(r.glow) == "table") then
            return true
        end
    end
    return false
end

-- The visibility pass (conditions -> alpha) repaints after every change.
Events.OnMessage("AD_VISIBILITY", CR.KEY, function()
    for _, st in pairs(CR.state) do
        if st.entry then CR.Visible(st.entry) end
    end
end)

-- Follow my rank (Forever): a rank learned sends a row's ids again when they
-- changed. Next frame, after the aura driver has forgotten the old ranks.
Events.On("SPELLS_CHANGED", "adrescolor_rank", function()
    if NS.IsForever ~= true or next(CR.state) == nil then return end
    Events.Coalesce("adrescolor_rank", function()
        EachLive(function(st)
            for _, kind in ipairs(CR.LANE_KINDS) do
                for _, lane in pairs(st[kind]) do
                    if lane.on then CR.Refilter(lane, false) end
                end
            end
        end)
        CR.SyncEvents()
    end)
end)

-- Editing. The table shows the rows the bar wears for the look being edited
-- (the look's own, else the bar's); the first edit to a look without rows of
-- its own copies the bar's into it. An edit that changes nothing is skipped,
-- any other marks the bar for one style refresh.
function CR.List(rec)
    if not Own(rec) then return {} end
    Store.ConvertResStates(rec)
    local LK = NS.Looks
    local l = LK and LK.EditRows(rec, false)
    if not l then l = rec.driver and rec.driver.resColors end
    return type(l) == "table" and l or {}
end

local function Mut(rec)
    local LK = NS.Looks
    local l = LK and LK.EditRows(rec, true)
    if l then return l end
    rec.driver = rec.driver or {}
    if type(rec.driver.resColors) ~= "table" then rec.driver.resColors = {} end
    return rec.driver.resColors
end

local function Changed(rec)
    if Store and Store.Dirty then Store.Dirty("style", rec.id) end
end

-- A new row of `when` at the end: its first look picked so it shows at once (a
-- spell or aura row colours the fill, a power row the fill as well).
function CR.AddRow(rec, when)
    if not Own(rec) then return false end
    Store.ConvertResStates(rec)
    if not Store.RES_STATE_WHEN[when] then when = "enough" end
    local l = Mut(rec)
    if #l >= CR.MaxRows() then return false end
    local d = Default()
    local r = { when = when, fill = { d[1], d[2], d[3], d[4] or 1 } }
    if when == "below" or when == "above" then r.value = (when == "below") and 20 or 80 end
    l[#l + 1] = r
    Changed(rec)
    return #l
end

function CR.RemoveRow(rec, i)
    if not Own(rec) then return false end
    local l = Mut(rec)
    if not l[i] then return false end
    table.remove(l, i)
    Changed(rec)
    return true
end

-- delta -1 = one place up (wins over more), 1 = one down.
function CR.MoveRow(rec, i, delta)
    if not Own(rec) then return false end
    local l = Mut(rec)
    local j = i + delta
    if not (l[i] and l[j]) then return false end
    l[i], l[j] = l[j], l[i]
    Changed(rec)
    return true
end

local function SameColor(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for n = 1, 4 do
        if (a[n] or 1) ~= (b[n] or 1) then return false end
    end
    return true
end

-- key "when": one of CR.WHEN; "fill" / "text": { r, g, b, a } or false (keep
-- the bar's own); "mark": a spell row's cost mark; "value": a power row's
-- value; "units": its value in power units; "follow": false pins the spells'
-- rank. The aura pick's fields (spellID / spellIDs, auraType, unit, caster,
-- followRank) are the aura icons' shape, written by the editor's shared aura
-- rows on the row itself.
function CR.SetRow(rec, i, key, v)
    if not Own(rec) then return false end
    local cur = CR.List(rec)[i]
    if not cur then return false end
    if key == "when" then
        if not Store.RES_STATE_WHEN[v] or cur.when == v then return false end
    elseif key == "fill" or key == "text" then
        if key == "text" and CR.AURA[cur.when] then return false end
        v = (type(v) == "table") and { tonumber(v[1]) or 1, tonumber(v[2]) or 1, tonumber(v[3]) or 1,
            tonumber(v[4]) or 1 } or nil
        if SameColor(cur[key], v) then return false end
    elseif key == "mark" then
        v = (v == true and CR.SPELL[cur.when]) and true or nil
        if cur.mark == v then return false end
    elseif key == "value" then
        v = tonumber(v)
        if not v then return false end
        v = math.max(0, math.floor(v + 0.5))
        if cur.value == v then return false end
    elseif key == "units" then
        v = (v == true) or nil
        if cur.units == v then return false end
    elseif key == "follow" then
        if v ~= false then v = nil end
        if cur.follow == v then return false end
    else
        return false
    end
    local r = Mut(rec)[i]
    r[key] = v
    if key == "when" then
        if (v == "below" or v == "above") and r.value == nil then r.value = (v == "below") and 20 or 80 end
        -- an aura row's state is never read: no text colour, no cost mark
        if CR.AURA[v] then r.text = nil end
        if not CR.SPELL[v] then r.mark = nil end
    end
    Changed(rec)
    return true
end

-- A spell row's spells: one more (to the cap, never twice), or one fewer.
function CR.AddSpell(rec, i, sid)
    if not Own(rec) then return false end
    sid = tonumber(sid)
    local cur = CR.List(rec)[i]
    if not (sid and sid > 0 and cur and CR.SPELL[cur.when]) then return false end
    sid = math.floor(sid)
    local have = type(cur.rowSpells) == "table" and cur.rowSpells or {}
    for _, s in ipairs(have) do
        if s == sid then return false end
    end
    if #have >= CR.MaxSpells() then return false end
    local r = Mut(rec)[i]
    r.rowSpells = type(r.rowSpells) == "table" and r.rowSpells or {}
    r.rowSpells[#r.rowSpells + 1] = sid
    Changed(rec)
    return true
end

function CR.RemoveSpell(rec, i, j)
    if not Own(rec) then return false end
    local cur = CR.List(rec)[i]
    if not (cur and type(cur.rowSpells) == "table" and cur.rowSpells[j]) then return false end
    local r = Mut(rec)[i]
    table.remove(r.rowSpells, j)
    if #r.rowSpells == 0 then r.rowSpells = nil end
    Changed(rec)
    return true
end

-- How many rows glow: a bar draws three glows at most.
function CR.GlowCount(rec)
    local n = 0
    for _, x in ipairs(CR.List(rec)) do
        if type(x.glow) == "table" then n = n + 1 end
    end
    return n
end

-- A row's glow: on (the bar glows' look to start), off, or one of its look's
-- keys (style, color, combat, and Schema.RES_GLOW_KEYS). Off keeps nothing.
function CR.SetGlow(rec, i, key, v)
    if not Own(rec) then return false end
    local cur = CR.List(rec)[i]
    if not cur then return false end
    if key == "on" then
        local has = type(cur.glow) == "table"
        if (v and has) or (not v and not has) then return false end
        if v and CR.GlowCount(rec) >= ((NS.Schema and NS.Schema.BAR_GLOW_SLOTS) or 3) then return false end
        Mut(rec)[i].glow = v and { style = "pixel" } or nil
    else
        if type(cur.glow) ~= "table" then return false end
        if key == "style" then v = (v == "autocast") and "autocast" or "pixel" end
        if key == "combat" then v = (v == true) or nil end
        local old = cur.glow[key]
        if key == "color" then
            if SameColor(old, v) then return false end
        elseif old == v then
            return false
        end
        local r = Mut(rec)[i]
        r.glow[key] = v
        r.glow = Store.CleanRowGlow(r.glow)
    end
    Changed(rec)
    return true
end

-- The row the editor's shared aura rows write their pick into (the look's own
-- copy while a look is edited), then the word that it changed.
function CR.MutRow(rec, i)
    if not (Own(rec) and CR.List(rec)[i]) then return nil end
    return Mut(rec)[i]
end

function CR.Touched(rec)
    if Own(rec) then Changed(rec) end
end
