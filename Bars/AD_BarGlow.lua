-- Arc Auras, all rights reserved: do not copy or adapt this code into another addon without permission.
-- AD_BarGlow: up to three glows around any bar (Bars.Glow), one module for every kind that draws one.
-- Owns the glow frames and the aura lanes they ride; AD_Bars calls in at fixed points.
-- A kind opts in with one entry in Schema.BAR_GLOW_KINDS (what it tracks of its own, its marks' rung).
-- Aura presence is never read: the game shows a lane's button exactly while its aura is up.
local ADDON, NS = ...
local Bars = NS.Bars
local Store = NS.Store
local Events = NS.Events
local K = Bars.Kit

local G = {}
Bars.Glow = G

-- [barKind] = { own, ownOff, marks }: the one kind table, the schema's
G.KINDS = (NS.Schema and NS.Schema.BAR_GLOW_KINDS) or {}
G.CD_WHEN = { ready = true, recharging = true, cooldown = true }
G.LANE_KINDS = { "up", "miss" }
-- An icon's glow laps its 36 x 36 rect once per period; a bar's lap is
-- stretched by its own perimeter, so both move at the same pixels a second.
G.ICON_PERIM = 144
-- how far past the glow rect the missing lane's button reaches (sparkles overhang)
G.REACH = 32
G.state = {}    -- [barId] = { anchor, cd = {}, up = {}, miss = {}, retired = {}, gen }
G.queue = {}    -- [lane] = parked, filter edits waiting out combat
G.inCombat = InCombatLockdown() and true or false

local function Suf(k) return (k > 1) and tostring(k) or "" end
local function GR(rec, section, field, k) return Store.Resolve(rec, section, field .. Suf(k)) end

function G.Slots() return (NS.Schema and NS.Schema.BAR_GLOW_SLOTS) or 3 end

-- A kind whose glows are its state rows (the kind table's rows: resource
-- bars, Bars\AD_ResColors.lua): glow k is the k-th row that carries a glow,
-- its trigger the row's own state, its look the row's glow.
function G.FromRows(rec)
    local d = rec and G.KINDS[rec.barKind]
    return d ~= nil and d.rows == true
end

-- glow k's row and its place in the list, or nil
function G.Row(rec, k)
    local CRm = Bars.ResColor
    local idx = CRm and CRm.GlowRows(rec)
    local i = idx and idx[k]
    if not i then return nil end
    return CRm.RowsOf(rec)[i], i
end

-- a row's glow as a look, each unset key at the bar glows' default
function G.RowLook(r)
    local g = r and r.glow
    if type(g) ~= "table" then return nil end
    local S = NS.Schema
    local gf = S.bar.glows.fields
    local function V(key)
        local v = g[key]
        if v == nil then v = gf[S.RES_GLOW_KEYS[key]].d end
        return v
    end
    local c = type(g.color) == "table" and g.color or gf.barGlowColor.d
    return {
        when = r.when,
        style = (g.style == "autocast") and "autocast" or "pixel",
        r = c[1] or 1, g = c[2] or 1, b = c[3] or 1, a = (c[4] or 1) * V("intensity"),
        combat = g.combat == true,
        speed = math.max(0.05, V("speed")),
        lines = math.max(1, math.floor(V("lines"))),
        th = math.max(1, math.floor(V("th"))),
        len = V("len"),
        parts = math.max(1, math.floor(V("parts"))),
        scale = V("scale"),
        xo = math.floor(V("xo") + 0.5),
        yo = math.floor(V("yo") + 0.5),
    }
end

function G.Count(rec)
    if G.FromRows(rec) then
        local CRm = Bars.ResColor
        local idx = CRm and CRm.GlowRows(rec)
        return idx and #idx or 0
    end
    local n = tonumber(Store.Resolve(rec, "glows", "barGlowCount")) or 1
    if n < 1 then n = 1 end
    return math.min(G.Slots(), math.floor(n))
end
function G.On(rec, k)
    if G.FromRows(rec) then return G.Row(rec, k) ~= nil end
    return G.KINDS[rec.barKind] ~= nil and k <= G.Count(rec) and GR(rec, "glows", "barGlow", k) == true
end

-- The thing of its own this bar's Track offers first: "aura", "spell" or nil,
-- from the kind table (a cooldown bar in GCD tracker mode has no spell).
function G.OwnFamily(rec)
    local d = rec and G.KINDS[rec.barKind]
    if not (d and d.own) then return nil end
    if d.ownOff and Store.Resolve(rec, "behavior", d.ownOff) == true then return nil end
    return d.own
end

-- a row glow's state other than an aura's is judged by the rows ("row")
function G.When(rec, k)
    if G.FromRows(rec) then
        local r = G.Row(rec, k)
        local w = r and r.when
        return (w == "up" or w == "missing") and w or "row"
    end
    return GR(rec, "glows", "barGlowWhen", k) or "up"
end

-- What glow k tracks, read off its Glow when: "aura" (up, missing) or "spell"
-- (ready, recharging, on cooldown). Saved glows need no Track field of their own.
function G.Family(rec, k)
    return G.CD_WHEN[G.When(rec, k)] and "spell" or "aura"
end

-- What drives glow k: "up" / "miss" (an aura lane), "cd" (a spell's cooldown
-- states), "row" (a state row the rows judge), or nil when its trigger
-- cannot run here.
function G.Kind(rec, k)
    local when = G.When(rec, k)
    if when == "row" then return "row" end
    local S = NS.Schema
    if not S then return nil end
    if G.CD_WHEN[when] then return S.BarGlowCdOK(rec) and "cd" or nil end
    if when == "up" or when == "missing" then
        if not S.BarGlowAuraOK(when == "missing") then return nil end
        return (when == "missing") and "miss" or "up"
    end
    return nil
end

-- glow k's own record, rec.driver.glows[k]: the aura pick and, apart, the
-- spell pick. Made fresh on an aura bar it keeps "This bar's aura", so a
-- spell picked first never turns the aura pick to another one.
function G.GlowRec(rec, k, make)
    if not (rec and rec.driver) then return nil end
    local list = rec.driver.glows
    if type(list) ~= "table" then
        if not make then return nil end
        list = {}
        rec.driver.glows = list
    end
    local g = list[k]
    if type(g) ~= "table" then
        if not make then return nil end
        g = {}
        if G.OwnFamily(rec) == "aura" then g.own = true end
        list[k] = g
    end
    return g
end

-- a bar with an aura of its own watches it unless "Another aura" was picked
function G.AuraOwn(rec, k)
    if G.OwnFamily(rec) ~= "aura" then return false end
    local g = G.GlowRec(rec, k, false)
    return g == nil or g.own == true
end

-- a bar with a spell of its own (a cooldown bar outside GCD tracker mode)
function G.OwnSpell(rec)
    return G.OwnFamily(rec) == "spell"
end

-- The spell glow k's cooldown states read: own (the bar's, unless "Another
-- spell" was picked), else the glow's pick: own, spellID, follow my rank.
function G.CdSpell(rec, k)
    local g = G.GlowRec(rec, k, false)
    if G.OwnSpell(rec) and (g == nil or g.cdOwn ~= false) then return true, nil, nil end
    local sid = g and tonumber(g.cdSpellID)
    if sid and sid <= 0 then sid = nil end
    return false, sid and math.floor(sid), not (g and g.cdFollowRank == false)
end

-- Recharging needs a spell with charges (maxCharges is never secret).
function G.SpellHasCharges(rec, k)
    local own, sid, follow = G.CdSpell(rec, k)
    if own then return G.IsChargeBar(rec) end
    local DC = NS.DriverCooldown
    return sid ~= nil and DC ~= nil and DC.SpellCharges ~= nil and DC.SpellCharges(sid, follow) == true
end

-- A saved Recharging on a spell with no charges: the card says so.
function G.StaleRecharge(rec, k)
    if G.When(rec, k) ~= "recharging" then return false end
    local own, sid = G.CdSpell(rec, k)
    if not (own or sid) then return false end
    return not G.SpellHasCharges(rec, k)
end

-- Track: what the glow follows. "own" (the bar's aura or spell), "aura" or
-- "spell"; several bars at once pick only the kind of thing.
function G.Track(rec, k)
    local fam = G.Family(rec, k)
    if rec._adMulti then return fam end
    if fam == "aura" then return G.AuraOwn(rec, k) and "own" or "aura" end
    return (G.CdSpell(rec, k)) and "own" or "spell"
end

function G.TrackChoices(rec)
    if rec._adMulti then return { "aura", "spell" } end
    local own = G.OwnFamily(rec)
    if own == "aura" then return { "own", "aura", "spell" } end
    if own == "spell" then return { "own", "spell", "aura" } end
    return { "aura", "spell" }
end

-- A new Track: Glow when moves to that thing's first state only when the kind
-- of thing changes; the aura pick and the spell pick stay as they were.
function G.SetTrack(rec, k, v)
    local fam = v
    if v == "own" then fam = G.OwnFamily(rec) end
    if fam ~= "aura" and fam ~= "spell" then return end
    if G.Family(rec, k) ~= fam then
        Store.SetOverride(rec, "glows", "barGlowWhen" .. Suf(k), (fam == "spell") and "ready" or "up")
    end
    if rec._adMulti then return end
    if fam == "aura" and G.OwnFamily(rec) == "aura" then
        local g = G.GlowRec(rec, k, v ~= "own")
        if g then g.own = (v == "own") or nil end
    elseif fam == "spell" and G.OwnSpell(rec) then
        local g = G.GlowRec(rec, k, v ~= "own")
        if g then
            if v == "own" then g.cdOwn = nil else g.cdOwn = false end
        end
    end
end

function G.Look(rec, k)
    if G.FromRows(rec) then return G.RowLook((G.Row(rec, k))) end
    local c = GR(rec, "glows", "barGlowColor", k) or { 0.95, 0.95, 0.32, 1 }
    return {
        when = GR(rec, "glows", "barGlowWhen", k) or "up",
        style = (GR(rec, "glows", "barGlowType", k) == "autocast") and "autocast" or "pixel",
        r = c[1] or 1, g = c[2] or 1, b = c[3] or 1,
        a = (c[4] or 1) * (GR(rec, "glows", "barGlowIntensity", k) or 1),
        combat = GR(rec, "glows", "barGlowCombatOnly", k) == true,
        speed = math.max(0.05, GR(rec, "glows", "barGlowSpeed", k) or 0.25),
        lines = math.max(1, math.floor(GR(rec, "glows", "barGlowLines", k) or 12)),
        th = math.max(1, math.floor(GR(rec, "glows", "barGlowThickness", k) or 2)),
        len = GR(rec, "glows", "barGlowLength", k) or 0,
        parts = math.max(1, math.floor(GR(rec, "glows", "barGlowParticles", k) or 8)),
        scale = GR(rec, "glows", "barGlowScale", k) or 1,
        xo = math.floor((GR(rec, "glows", "barGlowXOffset", k) or 0) + 0.5),
        yo = math.floor((GR(rec, "glows", "barGlowYOffset", k) or 0) + 0.5),
    }
end

-- The aura glow k watches, in the aura icons' shape: an aura bar's own aura
-- unless "Another aura" was picked, else the glow's own record.
function G.Shape(rec, k)
    if G.FromRows(rec) then return (G.Row(rec, k)) or {} end
    if G.AuraOwn(rec, k) then return rec.driver or {} end
    return G.GlowRec(rec, k, false) or {}
end

-- A cooldown bar on a spell with charges.
function G.IsChargeBar(rec)
    if not rec then return false end
    local e = K.live[rec.id]
    if e and e.isCharge ~= nil then return e.isCharge == true end
    -- the spell the bar reads (its rank, its override), as the bar's feed does
    local sid = NS.Store.RecordSpellID(rec.driver)
    local info = sid and C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    local mx = info and info.maxCharges
    if issecretvalue and issecretvalue(mx) then return false end
    return type(mx) == "number" and mx > 1
end

-- True when a glow of this bar rides an aura lane (the login prebuild asks).
function G.WantsLanes(rec)
    if not (rec and rec.type == "bar" and G.KINDS[rec.barKind]) then return false end
    for k = 1, G.Count(rec) do
        if G.On(rec, k) then
            local kd = G.Kind(rec, k)
            if kd == "up" or kd == "miss" then return true end
        end
    end
    return false
end

-- Geometry, never read back from a rect: the size the layout engine gives
-- the holder (Engine.BarSize: the settings, or an anchor's match per axis), a
-- pips row from the numbers LayoutPips laid, the editor pane from the settings
-- on its own grid. Offsets and thickness in whole pixels of the live grid.
function G.BarSize(e)
    if e.pipsOn and e.pipsW and e.pipsH then return e.pipsW, e.pipsH end
    local rec = e.rec
    local LE = NS.LayoutEngine
    -- the live bar, and Play on screen drawn on the live bar's own frame
    if LE and LE.BarSize and (not e.isPreview or (LE.GetBarFrame and LE.GetBarFrame(rec.id) == e.holder)) then
        return LE.BarSize(rec, e.holder)
    end
    local w = Store.Resolve(rec, "size", "width") or 220
    local h = Store.Resolve(rec, "size", "height") or 16
    local sc = Store.Resolve(rec, "size", "scale") or 1
    local px = K.Px(e.shell)
    local function S(v) return math.max(px, math.floor(v / px + 0.5) * px) end
    return S(math.max(1, w * sc)), S(math.max(1, h * sc))
end

function G.Geom(e, look)
    local px = K.Px(e.shell)
    local bw, bh = G.BarSize(e)
    -- an inward offset never turns the rect inside out
    local function Off(n, span)
        local most = math.floor((span / px - 1) / 2)
        if n < -most then n = -most end
        return n * px
    end
    local ox, oy = Off(look.xo, bw), Off(look.yo, bh)
    return { ox = ox, oy = oy, W = bw + 2 * ox, H = bh + 2 * oy, th = Bars.StripPx(e.shell, look.th) }
end

-- corner anchors at whole-pixel offsets
function G.Place(host, rel, gm)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", rel, "TOPLEFT", -gm.ox, gm.oy)
    host:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", gm.ox, -gm.oy)
end

-- The art: the icons' Pixel and Autocast builders, redrawn only when the look
-- or the size changes (a redraw restarts the loops).
function G.Paint(host, look, gm)
    local A = NS.Factory and NS.Factory.GlowArt
    if not A then return end
    local period = (1 / look.speed) * (2 * (gm.W + gm.H)) / G.ICON_PERIM
    local sig = table.concat({ look.style, gm.W, gm.H, gm.th, look.lines, look.len, look.parts,
        look.scale, period, look.r, look.g, look.b, look.a }, ":")
    if host._adBarSig == sig then return end
    host._adBarSig = sig
    A.hide(host, look.style)
    if look.style == "autocast" then
        A.autocast(host, gm.W, gm.H, look.parts, look.scale, period, look.r, look.g, look.b, look.a)
    else
        A.pixel(host, gm.W, gm.H, look.lines, gm.th, period, look.r, look.g, look.b, look.a, look.len)
    end
end

function G.Unpaint(host)
    local A = NS.Factory and NS.Factory.GlowArt
    if A and host._adBarSig then A.hide(host, nil) end
    host._adBarSig = nil
end

-- loops a hidden host held stay as they were; start any that stopped
function G.Wake(host)
    for _, it in ipairs(host._adPix or {}) do
        if it.strip:IsShown() and not it.ag:IsPlaying() then it.ag:Play() end
    end
    for _, it in ipairs(host._adSpk or {}) do
        if it.tex:IsShown() and not it.ag:IsPlaying() then it.ag:Play() end
    end
end

-- Combat-only glows show while the options window is open, as icons' do.
function G.ForCombat()
    return G.inCombat or K.IsEditMode()
end

local function State(id)
    local st = G.state[id]
    if not st then
        st = { cd = {}, row = {}, up = {}, miss = {}, retired = {}, gen = 0 }
        G.state[id] = st
    end
    return st
end

-- Lanes (one container each, made once, never shown or hidden again: a
-- glow switched off parks its filter and goes to alpha 0).

-- Filter edits are data only; sent outside combat, and never resent unchanged.
function G.Refilter(lane, parked)
    if InCombatLockdown() then
        G.queue[lane] = parked and true or false
        return
    end
    G.queue[lane] = nil
    local DA = NS.DriverAura
    local st = lane.st
    local shape = (not parked) and st.rec and G.Shape(st.rec, lane.slot) or nil
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

-- The init window, the one write that always lands: the button follows the
-- bar's rect at its rung. An up lane's glow is drawn on it; a missing lane's
-- button gets the piece that covers its glow.
function G.WireLane(lane, b)
    local st = lane.st
    b:EnableMouse(false)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", st.anchor, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", st.anchor, "BOTTOMRIGHT", 0, 0)
    G.LevelButton(lane, b)
    if lane.kind == "miss" then
        local er = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        er:SetColorTexture(0, 0, 0, 0)
        er:SetBlendMode("DISABLE")
        er:SetPoint("TOPLEFT", lane.host, "TOPLEFT", -G.REACH, G.REACH)
        er:SetPoint("BOTTOMRIGHT", lane.host, "BOTTOMRIGHT", G.REACH, -G.REACH)
        lane.cover = er
        return
    end
    local host = CreateFrame("Frame", nil, b)
    host:EnableMouse(false)
    lane.host = host
    G.PaintUp(lane)
end

function G.LevelButton(lane, b)
    local st = lane.st
    local L = Bars.LADDER
    local lvl = (st.base or 1) + ((lane.kind == "miss") and L.missBtn or L.glow)
    if st.strata then b:SetFrameStrata(st.strata) end
    b:SetFrameLevel(lvl)
    lane.level, lane.strata = lvl, st.strata
end

-- an up lane's glow, on its button (accessible passes only)
function G.PaintUp(lane)
    local host, b = lane.host, lane.frame
    if not (host and b and lane.look and lane.gm) then return end
    host:SetFrameLevel(lane.level or 1)
    G.Place(host, b, lane.gm)
    G.Paint(host, lane.look, lane.gm)
end

-- a missing lane's glow: our own frames, writable any time
function G.PaintMiss(lane)
    local st = lane.st
    if not (lane.look and lane.gm) then return end
    local lvl = (st.base or 1) + Bars.LADDER.glow
    if st.strata then lane.stage:SetFrameStrata(st.strata) end
    lane.stage:SetFrameLevel(lvl)
    lane.host:SetFrameLevel(lvl)
    G.Place(lane.host, st.anchor, lane.gm)
    G.Paint(lane.host, lane.look, lane.gm)
end

-- false = not now (auras secret outside the login window, or no engine)
local function CanCreate()
    local DA = NS.DriverAura
    if not (DA and DA.IsAvailable and DA.IsAvailable() == true) then return false end
    return not (K.AuraSecretNow() and not Bars.loadWindow)
end

-- look, gm: the glow's look and geometry, in place before the button can be born
function G.MakeLane(st, k, kind, shape, unit, harmful, look, gm)
    if not CanCreate() then return nil end
    local DA = NS.DriverAura
    local lane = { kind = kind, slot = k, unit = unit, harmful = harmful, st = st,
        look = look, gm = gm, on = true, combat = look and look.combat }
    local parent
    if kind == "miss" then
        if not DA.EraserAvailable() then return nil end
        local stage = CreateFrame("Frame", nil, UIParent)
        stage:SetFlattensRenderLayers(true)
        -- set before the container is born inside it
        stage:SetIsFrameBuffer(true)
        stage:SetAlpha(0)
        stage:EnableMouse(false)
        stage:SetPoint("TOPLEFT", st.anchor, "TOPLEFT", 0, 0)
        stage:SetPoint("BOTTOMRIGHT", st.anchor, "BOTTOMRIGHT", 0, 0)
        local host = CreateFrame("Frame", nil, stage)
        host:EnableMouse(false)
        lane.stage, lane.host = stage, host
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
    lane.key = "adbarglow" .. k .. "_" .. tostring(st.id) .. "_" .. unit
        .. (harmful and "_h" or "_b") .. "_g" .. st.gen
    local ids = DA.IncludeMap(shape)
    lane.filterSig = DA.FilterSig(ids)
    lane.fstr = DA.FilterForLane(shape, lane)
    -- in place before the slot: its initializer can run inside AddAuraSlot
    st[kind][k] = lane
    c:AddAuraSlot(lane.key, lane.fstr, {
        maxFrameCount = 1,
        initializeFrame = function(b)
            lane.frame = b
            G.WireLane(lane, b)
        end,
        candidateFilters = { includeSpellIDs = ids },
    })
    return lane
end

-- parked for good (its unit or aura type changed): a new lane takes its place
function G.Retire(st, lane)
    lane.on, lane.retired = false, true
    st[lane.kind][lane.slot] = nil
    st.retired[#st.retired + 1] = lane
    G.Refilter(lane, true)
    lane.container:SetAlpha(0)
    if lane.stage then lane.stage:SetAlpha(0) end
end

-- One glow slot's aura lane of `kind`: made, kept in step with the settings
-- and the aura, or parked.
function G.SlotLane(st, e, k, kind, look)
    local lane = st[kind][k]
    if not look then
        if lane and lane.on then
            lane.on = false
            G.Refilter(lane, true)
        end
        return
    end
    local DA = NS.DriverAura
    local shape = G.Shape(e.rec, k)
    local unit, harmful = DA.LaneOf(shape)
    if lane and (lane.unit ~= unit or lane.harmful ~= harmful) then
        G.Retire(st, lane)
        lane = nil
    end
    local gm = G.Geom(e, look)
    if not lane then
        lane = G.MakeLane(st, k, kind, shape, unit, harmful, look, gm)
        if not lane then
            st.pending = true
            return
        end
    end
    lane.look, lane.gm, lane.on, lane.combat = look, gm, true, look.combat
    G.Refilter(lane, false)
    if kind == "miss" then G.PaintMiss(lane) end
    local b = lane.frame
    if b then
        if DA.IsAccessible(b) then
            if lane.level ~= (st.base or 1) + ((kind == "miss") and Bars.LADDER.missBtn or Bars.LADDER.glow)
                or lane.strata ~= st.strata then
                G.LevelButton(lane, b)
            end
            if kind == "up" then G.PaintUp(lane) end
        else
            st.pending = true
        end
    end
end

-- Another spell's states ride a shared watch (DriverCooldown.WatchSpell),
-- one per spell for every glow naming it, keyed per bar and slot.
function G.WatchKey(id, k) return "adbarglow:" .. tostring(id) .. ":" .. k end

function G.Unwatch(st, k)
    local host = st.cd[k]
    if host then host._adWatch = nil end
    local DC = NS.DriverCooldown
    if DC and DC.UnwatchSpell then DC.UnwatchSpell(G.WatchKey(st.id, k)) end
end

-- the watch's change reaches only its own glow
function G.WatchFn(st, k)
    st.wfn = st.wfn or {}
    local fn = st.wfn[k]
    if not fn then
        local id = st.id
        fn = function()
            local s = G.state[id]
            if s and s.entry then G.CdShow(s, k) end
        end
        st.wfn[k] = fn
    end
    return fn
end

-- A cooldown-state glow: a plain frame of ours over the bar.
function G.SlotCd(st, e, k, look)
    local host = st.cd[k]
    if not look then
        if host then
            G.Unpaint(host)
            host:Hide()
            host._adWhen = nil
        end
        G.Unwatch(st, k)
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, e.shell)
        host:EnableMouse(false)
        host:Hide()
        st.cd[k] = host
    end
    if host:GetParent() ~= e.shell then host:SetParent(e.shell) end
    host:SetFrameLevel((st.base or 1) + Bars.LADDER.glow)
    local gm = G.Geom(e, look)
    G.Place(host, e.shell, gm)
    G.Paint(host, look, gm)
    host._adWhen, host._adCombat = look.when, look.combat
    local own, sid, follow = G.CdSpell(e.rec, k)
    host._adOwn = own
    local DC = NS.DriverCooldown
    if own or not sid or not (DC and DC.WatchSpell) then
        G.Unwatch(st, k)
    else
        local key = G.WatchKey(st.id, k)
        DC.WatchSpell(key, sid, follow, G.WatchFn(st, k))
        host._adWatch = key
    end
    G.CdShow(st, k)
end

-- the states glow k reads: the bar's own (CooldownPushState) or its watch's
function G.CdStates(st, host)
    if host._adOwn then
        local e = st.entry
        return e.glowReady, e.glowRech, e.glowCd
    end
    local DC = NS.DriverCooldown
    if host._adWatch and DC and DC.SpellState then return DC.SpellState(host._adWatch) end
    return false, false, false
end

function G.CdShow(st, k)
    local host = st.cd[k]
    if not host then return end
    local e = st.entry
    local want = false
    if host._adWhen ~= nil and e ~= nil then
        local ready, rech, oncd = G.CdStates(st, host)
        want = ((host._adWhen == "ready" and ready) or (host._adWhen == "recharging" and rech)
            or (host._adWhen == "cooldown" and oncd)) and (not host._adCombat or G.ForCombat())
    end
    want = want and true or false
    if want ~= (host:IsShown() == true) then
        host:SetShown(want)
        if want then G.Wake(host) end
    end
end

-- A state row's glow (any row but an aura's): a plain frame of ours over the
-- bar, shown while its row holds (Bars\AD_ResColors.lua judges it, e.crRows).
function G.SlotRow(st, e, k, look, row)
    local host = st.row[k]
    if not look then
        if host then
            G.Unpaint(host)
            host:Hide()
            host._adRow = nil
        end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, e.shell)
        host:EnableMouse(false)
        host:Hide()
        st.row[k] = host
    end
    if host:GetParent() ~= e.shell then host:SetParent(e.shell) end
    host:SetFrameLevel((st.base or 1) + Bars.LADDER.glow)
    local gm = G.Geom(e, look)
    G.Place(host, e.shell, gm)
    G.Paint(host, look, gm)
    host._adRow, host._adCombat = row, look.combat
    G.RowShow(st, k)
end

function G.RowShow(st, k)
    local host = st.row[k]
    if not host then return end
    local e = st.entry
    local rr = e and e.crRows and host._adRow and e.crRows[host._adRow]
    local want = (rr ~= nil and rr.hold == true) and (not host._adCombat or G.ForCombat())
    want = want and true or false
    if want ~= (host:IsShown() == true) then
        host:SetShown(want)
        if want then G.Wake(host) end
    end
end

-- The rows' word that a row's state moved: its glow follows.
function G.RowsHeld(e)
    local st = G.state[e.rec and e.rec.id]
    if not (st and st.entry == e) then return end
    for k in pairs(st.row) do G.RowShow(st, k) end
end

-- The live pass, at the end of every EnsureBar (and a pips bar's resize).
function G.Styled(e)
    if e.isPreview then return end
    local rec = e.rec
    local id = rec.id
    local st = G.state[id]
    local any = false
    if G.KINDS[rec.barKind] then
        for k = 1, G.Count(rec) do
            if G.On(rec, k) then any = true end
        end
    end
    if not (any or st) then return end
    st = st or State(id)
    st.id, st.rec, st.entry = id, rec, e
    -- the size this pass lays, which G.Relayout compares against
    st.w, st.h = G.BarSize(e)
    if not st.anchor then
        st.anchor = CreateFrame("Frame", nil, UIParent)
        st.anchor:EnableMouse(false)
    end
    if st.anchorShell ~= e.shell then
        st.anchorShell = e.shell
        st.anchor:ClearAllPoints()
        st.anchor:SetPoint("TOPLEFT", e.shell, "TOPLEFT", 0, 0)
        st.anchor:SetPoint("BOTTOMRIGHT", e.shell, "BOTTOMRIGHT", 0, 0)
    end
    local lvl = e.shell.fill:GetFrameLevel()
    st.base = (type(lvl) == "number") and lvl or 1
    st.strata = e.shell:GetFrameStrata()
    st.pending = nil
    local n = G.Count(rec)
    st.hasCd, st.combat = false, false
    for k = 1, G.Slots() do
        local kind = (k <= n and G.On(rec, k)) and G.Kind(rec, k) or nil
        local look = kind and G.Look(rec, k) or nil
        if look and look.combat then st.combat = true end
        G.SlotCd(st, e, k, (kind == "cd") and look or nil)
        if kind == "cd" then st.hasCd = true end
        G.SlotRow(st, e, k, (kind == "row") and look or nil, (kind == "row") and select(2, G.Row(rec, k)) or nil)
        G.SlotLane(st, e, k, "up", (kind == "up") and look or nil)
        G.SlotLane(st, e, k, "miss", (kind == "miss") and look or nil)
    end
    G.SyncEvents()
    G.Visible(e)
end

-- The bar's size moved (a pips row laid itself, an anchor's match changed):
-- the glows are laid again by the same pass, only when the numbers differ.
function G.Relayout(e)
    local st = G.state[e.rec and e.rec.id]
    if not (st and st.entry == e) then return end
    local w, h = G.BarSize(e)
    if w ~= st.w or h ~= st.h then G.Styled(e) end
end

-- The layout engine's word that bar `id` took a new size from its anchor's
-- match (Engine.BarSize): the live glows follow at once, and Play on screen's
-- copy when it draws on that bar.
function G.Sized(id)
    local st = G.state[id]
    if st and st.entry then G.Relayout(st.entry) end
    local PV = Bars._PV
    local se = PV and PV.se
    if se and se.rec and se.rec.id == id then G.Preview(se) end
end

-- 12.1.0 shows an unfiltered aura on such a lane: it stays out.
function G.Blind(lane)
    if not NS.AuraEngine1210 then return false end
    local DA = NS.DriverAura
    local st = lane.st
    return DA ~= nil and DA.LaneBlindFor ~= nil and st.rec ~= nil
        and DA.LaneBlindFor(lane.unit, lane.harmful, G.Shape(st.rec, lane.slot)) == true
end

-- The lanes hang off UIParent: they take the bar's shown alpha, the combat
-- gate and, on 12.1.0, the blind check through their own alpha. A shell hidden
-- by a flag that may be secret (e.shellGate, Bars.Kit.ShellAlpha: a castbar's
-- casts that cannot be interrupted) is copied C-side, never read.
function G.Visible(e)
    if e.isPreview then return end
    local st = G.state[e.rec.id]
    if not (st and st.entry == e) then return end
    local a = 0
    local sh = e.shell
    if sh and sh:IsVisible() then
        a = sh:GetEffectiveAlpha() or 1
        if issecretvalue and issecretvalue(a) then
            -- the holder's alpha is ours and plain; the shell's own goes through the gate
            a = (e.holder and e.holder:GetEffectiveAlpha()) or 1
            if issecretvalue(a) then a = 1 end
        end
    end
    local gate = e.shellGate
    local combatOK = G.ForCombat()
    for _, kind in ipairs(G.LANE_KINDS) do
        for _, lane in pairs(st[kind]) do
            local la = a
            if not lane.on or (lane.combat and not combatOK) then la = 0 end
            if kind == "up" and G.Blind(lane) then la = 0 end
            local f = (kind == "up") and lane.container or lane.stage
            if gate ~= nil and la > 0 and f.SetAlphaFromBoolean then
                f:SetAlphaFromBoolean(gate, 0, la)
                -- the next plain write must land
                lane.alpha = nil
            elseif lane.alpha ~= la then
                lane.alpha = la
                f:SetAlpha(la)
            end
            if kind == "miss" then
                local ca = G.Blind(lane) and 0 or 1
                if lane.calpha ~= ca then
                    lane.calpha = ca
                    lane.container:SetAlpha(ca)
                end
            end
        end
    end
    for k in pairs(st.cd) do G.CdShow(st, k) end
    for k in pairs(st.row) do G.RowShow(st, k) end
end

-- The bar's cooldown states, from its two hidden cooldowns (CooldownPushState),
-- kept on the entry: the first push comes before the glows are laid.
function G.CooldownState(e, ready, rech, oncd)
    e.glowReady, e.glowRech, e.glowCd = ready == true, rech == true, oncd == true
    local st = G.state[e.rec.id]
    if not (st and st.hasCd and st.entry == e) then return end
    for k in pairs(st.cd) do G.CdShow(st, k) end
end

-- A target, focus, pet or party swap (Drivers\AD_DriverAura.lua): its lanes re-judge.
function G.SyncUnit(unit)
    for _, st in pairs(G.state) do
        local hit = false
        for _, kind in ipairs(G.LANE_KINDS) do
            for _, lane in pairs(st[kind]) do
                if lane.unit == unit then hit = true end
            end
        end
        if hit and st.entry then G.Visible(st.entry) end
    end
end

-- The bar left (unloaded, removed or rebuilt as another kind): its lanes
-- park and go dark, kept for its return.
function G.Release(e)
    local st = G.state[e.rec and e.rec.id]
    if not (st and st.entry == e) then return end
    st.entry, st.hasCd = nil, false
    for _, kind in ipairs(G.LANE_KINDS) do
        for _, lane in pairs(st[kind]) do
            lane.on = false
            G.Refilter(lane, true)
            lane.alpha = 0
            lane.container:SetAlpha(0)
            if lane.stage then lane.stage:SetAlpha(0) end
        end
    end
    for k, host in pairs(st.cd) do
        G.Unpaint(host)
        host:Hide()
        host._adWhen = nil
        -- a spell watch goes with the bar: no events left behind for it
        G.Unwatch(st, k)
    end
    for _, host in pairs(st.row) do
        G.Unpaint(host)
        host:Hide()
        host._adRow = nil
    end
    G.SyncEvents()
end

-- Events: combat edges only while a glow waits for combat, a filter edit
-- waits it out, or a lane waits for auras to be plain again.
local function EachLive(fn)
    for _, st in pairs(G.state) do
        if st.entry then fn(st) end
    end
end

function G.Settle()
    for lane, parked in pairs(G.queue) do G.Refilter(lane, parked) end
    EachLive(function(st)
        if st.pending and not K.AuraSecretNow() then
            st.pending = nil
            G.Styled(st.entry)
        end
    end)
    G.SyncEvents()
end

function G.SyncEvents()
    local combat, pending = next(G.queue) ~= nil, false
    EachLive(function(st)
        if st.combat then combat = true end
        if st.pending then pending = true end
    end)
    if combat or pending then
        if not G.armed then
            G.armed = true
            G.inCombat = InCombatLockdown() and true or false
            Events.On("PLAYER_REGEN_DISABLED", "adbarglow", function()
                G.inCombat = true
                EachLive(function(st) G.Visible(st.entry) end)
            end)
            Events.On("PLAYER_REGEN_ENABLED", "adbarglow", function()
                G.inCombat = false
                G.Settle()
                EachLive(function(st) if st.entry then G.Visible(st.entry) end end)
            end)
        end
    elseif G.armed then
        G.armed = false
        Events.Off("PLAYER_REGEN_DISABLED", "adbarglow")
        Events.Off("PLAYER_REGEN_ENABLED", "adbarglow")
    end
    if pending and not G.pewArmed then
        G.pewArmed = true
        Events.On("PLAYER_ENTERING_WORLD", "adbarglow", function() G.Settle() end)
    elseif not pending and G.pewArmed then
        G.pewArmed = false
        Events.Off("PLAYER_ENTERING_WORLD", "adbarglow")
    end
end

-- The visibility pass (conditions -> alpha) repaints after every change.
Events.OnMessage("AD_VISIBILITY", "adbarglow", function()
    for _, st in pairs(G.state) do
        if st.entry then G.Visible(st.entry) end
    end
end)

-- Follow my rank (Forever): a rank learned sends a glow's ids again when they
-- changed. Next frame, after the aura driver has forgotten the old ranks.
Events.On("SPELLS_CHANGED", "adbarglow_rank", function()
    if NS.IsForever ~= true or next(G.state) == nil then return end
    Events.Coalesce("adbarglow_rank", function()
        EachLive(function(st)
            for _, kind in ipairs(G.LANE_KINDS) do
                for _, lane in pairs(st[kind]) do
                    if lane.on then G.Refilter(lane, false) end
                end
            end
        end)
        G.SyncEvents()
    end)
end)

-- The editor preview: every switched-on glow, drawn plain around the
-- preview bar while the Glows sub-tab is open (G.PreviewOpen, set by
-- UI\AD_BarGlowOptions.lua). It never touches an engine lane.
function G.Preview(e)
    local open = G.PreviewOpen ~= nil and G.PreviewOpen() == true
    local rec = e.rec
    e.pvGlow = e.pvGlow or {}
    local lvl = e.shell.fill:GetFrameLevel()
    lvl = (type(lvl) == "number") and lvl or 1
    -- a bar whose glows are its rows shows the glow of the row its table has open
    local rows = rec and G.FromRows(rec)
    local sel = rows and Bars.ResColor and Bars.ResColor.previewSel
    for k = 1, G.Slots() do
        local host = e.pvGlow[k]
        local look = (open and rec and G.On(rec, k) and G.Kind(rec, k)) and G.Look(rec, k) or nil
        if look and rows and select(2, G.Row(rec, k)) ~= sel then look = nil end
        if look then
            if not host then
                host = CreateFrame("Frame", nil, e.shell)
                host:EnableMouse(false)
                e.pvGlow[k] = host
            end
            if host:GetParent() ~= e.shell then host:SetParent(e.shell) end
            host:SetFrameLevel(lvl + Bars.LADDER.glow)
            local gm = G.Geom(e, look)
            G.Place(host, e.shell, gm)
            G.Paint(host, look, gm)
            host:Show()
            G.Wake(host)
        elseif host then
            G.Unpaint(host)
            host:Hide()
        end
    end
end

function G.PreviewPark(e)
    for _, host in pairs(e.pvGlow or {}) do
        G.Unpaint(host)
        host:Hide()
    end
end

-- the Glows sub-tab opened or closed: the preview follows at once
function G.PreviewSync()
    local PV = Bars._PV
    if not PV then return end
    if PV.e then G.Preview(PV.e) end
    if PV.se then G.Preview(PV.se) end
end
