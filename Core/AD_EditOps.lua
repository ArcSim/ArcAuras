-- Edit on screen: what the on-screen layout mode does to groups, bars and free
-- icons (move, size, anchor, free, undo). Every change is written to the
-- records and placed by the engine's own passes, so the spot the mode shows is
-- the spot a login, the panel and play show. Nothing writes in combat.
-- Units: UIParent units; rects as left, bottom, width, height.
local ADDON, NS = ...
local Store, Factory = NS.Store, NS.Factory
local Engine, Anchor = NS.LayoutEngine, NS.Anchor

local EO = {}
NS.EditOps = EO

EO.HISTORY_CAP = 50

-- A point's place across and up its frame (0 = left or bottom, 1 = right or top).
local FX = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1,
    BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
local FY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
    BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
-- the anchor kinds whose target is one of these elements
local REC_KIND = { group = true, bar = true, icon = true }
-- the engine's tie lean: one spot always rounds to one pixel
local TIE = 0.0058

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Busy() return InCombatLockdown() == true end

local function R(rec, field) return Store.Resolve(rec, "anchor", field) end

-- Records and frames

-- the layout rec is a top-level member of
local function MemberLayout(rec)
    local lay = rec and Store.LayoutOf(rec)
    if not lay then return nil end
    for _, mid in ipairs(lay.members or {}) do
        if mid == rec.id then return lay end
    end
    return nil
end

local function KindOf(rec)
    if not MemberLayout(rec) then return nil end
    if rec.type == "group" then return "group" end
    if rec.type == "bar" then return (not Anchor.Placeless(rec)) and "bar" or nil end
    if rec.type == "icon" and rec.groupId == nil then return "icon" end
    return nil
end

local function FrameOf(rec)
    if rec.type == "group" then return Engine.GetGroupFrame(rec.id) end
    if rec.type == "bar" then return Engine.GetBarFrame(rec.id) end
    return Factory.frames[rec.id]
end

-- Shown in its layout at a spot we may do math on (a frame on a nameplate can
-- read secret).
local function ShownFrame(rec)
    local f = FrameOf(rec)
    if not (f and f:IsShown()) or f._adPlatePin then return nil end
    local c = f:GetParent()
    if not (c and c:IsShown()) then return nil end
    if not (Plain(f:GetLeft()) and Plain(f:GetBottom())) then return nil end
    return f
end

-- One the mode may move: shown and not riding the cursor.
local function LiveFrame(rec)
    local f = ShownFrame(rec)
    if not f or f._adMousePin then return nil end
    return f
end

-- UIParent units per unit of f: its layout's scale as the client has it.
local function UIPer(f)
    local fs, us = Plain(f:GetEffectiveScale()), Plain(UIParent:GetEffectiveScale())
    if not (fs and us) or fs <= 0 or us <= 0 then return nil end
    return fs / us
end

-- one physical pixel in UIParent units
local function PxUI()
    local _, ph = GetPhysicalScreenSize()
    local us = Plain(UIParent:GetEffectiveScale())
    if not (ph and ph > 0 and us and us > 0) then return nil end
    return 768 / ph / us
end

-- one physical pixel in f's own units
local function PxOf(f)
    local _, ph = GetPhysicalScreenSize()
    local fs = Plain(f:GetEffectiveScale())
    if not (ph and ph > 0 and fs and fs > 0) then return nil end
    return 768 / ph / fs
end

-- v in whole steps of px, halves away from zero
local function Steps(v, px)
    local n = math.floor(math.abs(v) / px + 0.5)
    return ((v < 0) and -n or n) * px
end

-- f's own rect, in its units
local function LiveRect(f)
    local l, b, w, h = Plain(f:GetLeft()), Plain(f:GetBottom()), Plain(f:GetWidth()), Plain(f:GetHeight())
    if not (l and b and w and h) then return nil end
    return l, b, w, h
end

-- rec's rect in its frame's units; a group's is its full grid box, the box a
-- free group's spot centres (a Dynamic one shrinks inside it in play)
local function RectF(rec, f)
    if rec.type ~= "group" then return LiveRect(f) end
    local l, b, w, h = Engine.GroupBox(rec.id)
    l, b, w, h = Plain(l), Plain(b), Plain(w), Plain(h)
    if not (l and b and w and h) then return nil end
    return l, b, w, h
end

local function Pos(rec)
    if type(rec.pos) ~= "table" then rec.pos = {} end
    rec.pos.x, rec.pos.y = tonumber(rec.pos.x) or 0, tonumber(rec.pos.y) or 0
    return rec.pos
end

local function FieldDef(rec, section, field)
    local fam = NS.Schema and NS.Schema[Store.FamilyOf(rec)]
    local sec = fam and fam[section]
    return sec and sec.fields and sec.fields[field] or nil
end

local function OffsetRange(rec, axis)
    local def = FieldDef(rec, "anchor", "anchorOffset" .. axis)
    return (def and def.min) or -2000, (def and def.max) or 2000
end

-- Anchors

-- The frame rec hangs on now, or nil while it sits at its own spot; the cursor
-- leaves it there while the panel is open.
local function PinnedTo(rec)
    if not Anchor.IsEnabled(rec) then return nil end
    if (R(rec, "anchorTargetKind") or "group") == "mouse" and Engine.IsEditMode() then return nil end
    return Anchor.ResolveTarget(rec)
end

-- the element whose frame rec hangs on now (its first pick or a backup)
local function RidesOn(rec)
    if not Anchor.IsEnabled(rec) then return nil end
    local t, kind, n = Anchor.Effective(rec)
    if not (t and REC_KIND[kind]) then return nil end
    if n == 0 then return R(rec, "anchorTargetId") end
    local _, id = Anchor.Backup(rec, n)
    return id
end

-- does id hang, through its chain, on one of set
local function Rides(id, set)
    local seen, cur = {}, Store.Get(id)
    while cur and not seen[cur.id] do
        seen[cur.id] = true
        local t = RidesOn(cur)
        if not t then return false end
        if set[t] then return true end
        cur = Store.Get(t)
    end
    return false
end

-- Runs fn with vals laid over rec's section for the call only: nothing is
-- saved and nothing marks dirty, so a preview reads the placement code itself.
-- Looks never hold the anchor, size or arrangement of what this edits.
local function WithValues(rec, section, vals, fn)
    local made = rec.o[section] == nil
    local sec = rec.o[section] or {}
    rec.o[section] = sec
    local keep = {}
    for k, v in pairs(vals) do
        keep[k] = sec[k]
        sec[k] = v
    end
    local a, b, c, d = fn()
    for k in pairs(vals) do sec[k] = keep[k] end
    if made then rec.o[section] = nil end
    return a, b, c, d
end

-- Where the anchor pass lands f with vals over rec's anchor: its left and top
-- (own units), or nil when it does not pin.
local function Land(rec, f, vals)
    return WithValues(rec, "anchor", vals, function()
        if not Anchor.Apply(rec, f) then return nil end
        local l, b, _, h = LiveRect(f)
        if not l then return nil end
        return l, b + h
    end)
end

-- the two whole numbers round e (one when e is whole), held in the range
local function Candidates(e, lo, hi)
    local r = math.floor(e + 0.5)
    local a, b = r, r
    if math.abs(e - r) >= 1e-3 then a, b = math.floor(e), math.floor(e) + 1 end
    return math.max(lo, math.min(hi, a)), math.max(lo, math.min(hi, b))
end

-- One axis: the candidate landing nearest want, counted in half pixels so read
-- noise can't tip a tie; a tie goes away from prefer, so a nudge moves.
local function Pick(a, la, b, lb, want, px, prefer)
    local da = math.floor(2 * math.abs(la - want) / px + 0.5)
    local db = math.floor(2 * math.abs(lb - want) / px + 0.5)
    if da ~= db then return (da < db) and a or b end
    if prefer and math.abs(b - prefer) > math.abs(a - prefer) then return b end
    return a
end

-- The whole-unit offsets that land f nearest wantL, wantT (its left and top,
-- own units) with vals over rec's anchor, measured from offsets gx, gy (rel:
-- the wants are steps from where gx, gy land). Each axis on its own: the
-- anchor's snap rounds them apart. Returns x, y and true when the range cut.
local function Fit(rec, f, vals, gx, gy, wantL, wantT, prefer, rel)
    local px = PxOf(f)
    if not px then return nil end
    local v = {}
    for k, x in pairs(vals) do v[k] = x end
    v.anchorOffsetX, v.anchorOffsetY = gx, gy
    local l, t = Land(rec, f, v)
    if not l then return nil end
    if rel then wantL, wantT = l + wantL, t + wantT end
    -- the exact offsets, give or take the snap: the two whole numbers round
    -- them hold the best one, and both are measured
    local ex, ey = wantL - (l - gx), wantT - (t - gy)
    local lox, hix = OffsetRange(rec, "X")
    local loy, hiy = OffsetRange(rec, "Y")
    local cut = ex < lox - 0.5 or ex > hix + 0.5 or ey < loy - 0.5 or ey > hiy + 0.5
    local xa, xb = Candidates(ex, lox, hix)
    local ya, yb = Candidates(ey, loy, hiy)
    v.anchorOffsetX, v.anchorOffsetY = xa, ya
    local la, ta = Land(rec, f, v)
    local lb, tb = la, ta
    if xb ~= xa or yb ~= ya then
        v.anchorOffsetX, v.anchorOffsetY = xb, yb
        lb, tb = Land(rec, f, v)
    end
    if not (la and lb) then return nil end
    return Pick(xa, la, xb, lb, wantL, px, prefer and prefer[1]),
        Pick(ya, ta, yb, tb, wantT, px, prefer and prefer[2]), cut
end

-- An anchored element's offsets for a move of dx, dy (its own units, whole
-- pixels): whole units landing nearest; a move that rounds to nothing takes
-- one unit, so a nudge always moves.
local function StepOffsets(rec, f, dx, dy)
    local cx, cy = R(rec, "anchorOffsetX") or 0, R(rec, "anchorOffsetY") or 0
    local ox, oy = Fit(rec, f, {}, cx, cy, dx, dy, { cx, cy }, true)
    if not ox then return nil end
    local lox, hix = OffsetRange(rec, "X")
    local loy, hiy = OffsetRange(rec, "Y")
    if dx ~= 0 and ox == cx then ox = math.max(lox, math.min(hix, cx + ((dx > 0) and 1 or -1))) end
    if dy ~= 0 and oy == cy then oy = math.max(loy, math.min(hiy, cy + ((dy > 0) and 1 or -1))) end
    return ox, oy
end

-- Offsets that put src of the rect l, b, w, h on dst of tf, in f's units: the
-- spot Fit measures from.
local function Guess(f, l, b, w, h, src, tf, dst)
    local tl, tb, tw, th = LiveRect(tf)
    local kf, kt = UIPer(f), UIPer(tf)
    if not (tl and kf and kt) then return 0, 0 end
    local r = kt / kf
    local tx, ty = (tl + FX[dst] * tw) * r, (tb + FY[dst] * th) * r
    return math.floor(l + FX[src] * w - tx + 0.5), math.floor(b + FY[src] * h - ty + 0.5)
end

local function WriteOffsets(rec, x, y)
    Store.SetOverride(rec, "anchor", "anchorOffsetX", x)
    Store.SetOverride(rec, "anchor", "anchorOffsetY", y)
end

-- The pixel the edge keeping a point lands on: a centred spare pixel falls
-- right and below, as everywhere else.
local function LeanLeft(v, px) return math.floor(v / px + 0.5 - TIE) * px end
local function LeanUp(v, px) return math.floor(v / px + 0.5 + TIE) * px end

-- After a size change (the rebuild done): the fixed point back where it was
-- in the rect before, by the element's own spot or anchor offsets.
local function KeepFixed(rec, f, before, fixed)
    local fx, fy = FX[fixed or ""] or 0, FY[fixed or ""] or 1
    local l1, b1, w1, h1 = RectF(rec, f)
    local px = PxOf(f)
    if not (l1 and px) then return end
    local wantL = LeanLeft(before[1] + fx * (before[3] - w1), px)
    local wantB = LeanUp(before[2] + fy * (before[4] - h1), px)
    local dx, dy = Steps(wantL - l1, px), Steps(wantB - b1, px)
    if dx == 0 and dy == 0 then return end
    if PinnedTo(rec) then
        local cx, cy = R(rec, "anchorOffsetX") or 0, R(rec, "anchorOffsetY") or 0
        local fl, fb, _, fh = LiveRect(f)
        if not fl then return end
        local ox, oy = Fit(rec, f, {}, cx, cy, fl + dx, fb + fh + dy)
        if not ox then return end
        WriteOffsets(rec, ox, oy)
    else
        local pos = Pos(rec)
        pos.x, pos.y = pos.x + dx, pos.y + dy
        Store.Dirty("style", rec.id)
    end
    Engine.Rebuild()
end

-- The facing points for rec at l, b, w, h and its target: the sides that face
-- each other along the longer gap between their middles; the point centre on
-- centre.
local function Facing(f, l, b, w, h, kind, trec, tf)
    if kind == "layout" then return "CENTER", "CENTER" end
    local kf, kt = UIPer(f), UIPer(tf)
    local tl, tb, tw, th = RectF(trec, tf)
    if not (kf and kt and tl) then return "TOP", "BOTTOM" end
    local dx = (l + w / 2) * kf - (tl + tw / 2) * kt
    local dy = (b + h / 2) * kf - (tb + th / 2) * kt
    if math.abs(dy) >= math.abs(dx) then
        if dy < 0 then return "TOP", "BOTTOM" end
        return "BOTTOM", "TOP"
    end
    if dx > 0 then return "LEFT", "RIGHT" end
    return "RIGHT", "LEFT"
end

-- what target names for rec: the anchor kind, the target record and its frame
local function TargetOf(rec, target)
    local trec
    if target == "point" then trec = MemberLayout(rec) else trec = Store.Get(target) end
    if not trec then return nil end
    local kind
    if trec.type == "layout" then
        kind = "layout"
    elseif trec.type == "group" or trec.type == "bar" then
        kind = trec.type
    elseif trec.type == "icon" and trec.groupId == nil then
        kind = "icon"
    else
        return nil
    end
    local tf = (kind == "layout") and Engine.GetLayoutFrame(trec.id) or FrameOf(trec)
    return kind, trec, tf
end

local function CanAnchorRec(rec, target)
    if not KindOf(rec) or Store.Locked(rec) then return false end
    local kind, trec, tf = TargetOf(rec, target)
    if not kind or trec.id == rec.id or not Anchor.Allows(rec, kind) then return false end
    if Anchor.Placeless(trec) or Anchor.CreatesCycle(rec.id, trec) then return false end
    -- keeping it in place reads the target's rect
    return tf ~= nil and tf:IsShown() == true and not tf._adPlatePin and LiveRect(tf) ~= nil
end

-- What moves

function EO.Kind(id)
    if Busy() then return false end
    return KindOf(Store.Get(id))
end

function EO.Rect(id)
    if Busy() then return false end
    local rec = Store.Get(id)
    if not KindOf(rec) then return nil end
    local f = ShownFrame(rec)
    local k = f and UIPer(f)
    if not k then return nil end
    local l, b, w, h = RectF(rec, f)
    if not l then return nil end
    return l * k, b * k, w * k, h * k
end

local function MoverList(ids)
    local set, seen, out = {}, {}, {}
    for _, id in ipairs(ids or {}) do set[id] = true end
    for _, id in ipairs(ids or {}) do
        if not seen[id] then
            seen[id] = true
            if not Rides(id, set) then out[#out + 1] = id end
        end
    end
    return out
end

function EO.Movers(ids)
    if Busy() then return false end
    return MoverList(ids)
end

-- the movers of ids on screen, each with its frame; nil when one is locked
local function MoverFrames(ids)
    local out = {}
    for _, id in ipairs(MoverList(ids)) do
        local rec = Store.Get(id)
        if KindOf(rec) then
            if Store.Locked(rec) then return nil end
            local f = LiveFrame(rec)
            if f then out[#out + 1] = { rec = rec, f = f } end
        end
    end
    return out
end

-- a move as whole physical pixels: every mover lands the same pixels further on
local function PixMove(dx, dy)
    local px = PxUI()
    if not px then return 0, 0 end
    return Steps(tonumber(dx) or 0, px), Steps(tonumber(dy) or 0, px)
end

local previewed = {}   -- [frame] = { rec, pin = true } or { rec, orig = point, last = point }

local function SamePoint(a, p, rel, rp, x, y)
    return a ~= nil and a[1] == p and a[2] == rel and a[3] == rp
        and math.abs(a[4] - (x or 0)) < 1e-3 and math.abs(a[5] - (y or 0)) < 1e-3
end

-- Back on its saved spot; one a rebuild placed since stays where it is.
local function Unpreview(f, st)
    if st.pin then
        Anchor.Apply(st.rec, f)
        return
    end
    if SamePoint(st.last, f:GetPoint(1)) then
        local o = st.orig
        f:ClearAllPoints()
        f:SetPoint(o[1], o[2], o[3], o[4], o[5])
    end
end

function EO.Preview(ids, dx, dy)
    if Busy() then return false end
    local list = MoverFrames(ids)
    if not list then return false end
    local mx, my = PixMove(dx, dy)
    local now = {}
    for _, m in ipairs(list) do now[m.f] = true end
    for f, st in pairs(previewed) do
        if not now[f] then
            Unpreview(f, st)
            previewed[f] = nil
        end
    end
    -- a free one off its container (a drag of its own moved it) goes back to
    -- its saved spot first, so the move counts from there
    for _, m in ipairs(list) do
        local _, rel = m.f:GetPoint(1)
        if rel ~= m.f:GetParent() and not PinnedTo(m.rec) then
            Engine.Rebuild()
            wipe(previewed)
            break
        end
    end
    for _, m in ipairs(list) do
        local rec, f = m.rec, m.f
        local k = UIPer(f)
        if k and PinnedTo(rec) then
            local ox, oy = StepOffsets(rec, f, mx / k, my / k)
            if ox then
                Land(rec, f, { anchorOffsetX = ox, anchorOffsetY = oy })
                previewed[f] = { rec = rec, pin = true }
            end
        elseif k then
            -- a free one shifts its own snapped point by whole pixels, which
            -- is where its saved spot plus the move snaps
            local st = previewed[f]
            local p, rel, rp, x, y = f:GetPoint(1)
            if not (st and not st.pin and SamePoint(st.last, p, rel, rp, x, y)) then
                st = { rec = rec, orig = { p, rel, rp, x or 0, y or 0 } }
                previewed[f] = st
            end
            local o = st.orig
            if o[1] then
                local nx, ny = o[4] + mx / k, o[5] + my / k
                f:ClearAllPoints()
                f:SetPoint(o[1], o[2], o[3], nx, ny)
                st.last = { o[1], o[2], o[3], nx, ny }
            end
        end
    end
    return true
end

-- Teardown: it only puts our own frames back, so it runs in combat too.
function EO.EndPreview()
    for f, st in pairs(previewed) do Unpreview(f, st) end
    wipe(previewed)
    return true
end

function EO.Move(ids, dx, dy)
    if Busy() then return false end
    local list = MoverFrames(ids)
    if not list then return false end
    local mx, my = PixMove(dx, dy)
    -- every step from the saved spots before anything is written
    local writes = {}
    for _, m in ipairs(list) do
        local rec, f = m.rec, m.f
        local k = UIPer(f)
        if k and PinnedTo(rec) then
            local ox, oy = StepOffsets(rec, f, mx / k, my / k)
            if ox then writes[#writes + 1] = { rec = rec, ox = ox, oy = oy } end
        elseif k and (mx ~= 0 or my ~= 0) then
            writes[#writes + 1] = { rec = rec, x = mx / k, y = my / k }
        end
    end
    wipe(previewed)
    for _, w in ipairs(writes) do
        if w.ox then
            WriteOffsets(w.rec, w.ox, w.oy)
        else
            -- decimals: a whole unit is a whole pixel at one scale only
            local pos = Pos(w.rec)
            pos.x, pos.y = pos.x + w.x, pos.y + w.y
            Store.Dirty("style", w.rec.id)
        end
    end
    Engine.Rebuild()
    return true
end

-- Snap lines

-- The client's words for a line drawn on screen; NS.AT is looked up late, as
-- an edit-only load has no theme.
local function Tr(s)
    local AT = NS.AT
    if AT and AT.Tr then return AT.Tr(s) end
    return s
end

-- An element's snap line in words, one whole line per edge: the English
-- possessive differs for a name ending in s ("Bars' top").
local EDGE_WORDS = {
    left = { "%s's left edge", "%s' left edge" }, right = { "%s's right edge", "%s' right edge" },
    middle = { "%s's middle", "%s' middle" }, top = { "%s's top", "%s' top" },
    bottom = { "%s's bottom", "%s' bottom" },
}
function EO.EdgeWords(name, edge)
    name = name or "?"
    local f = EDGE_WORDS[edge]
    return Tr(name:match("[sS]$") and f[2] or f[1]):format(name)
end

function EO.SnapLines(layoutId, skipIds)
    if Busy() then return false end
    local out = { xs = {}, ys = {} }
    local lay = Store.Get(layoutId)
    local c = Engine.GetLayoutFrame(layoutId)
    if not (lay and lay.type == "layout" and c and c:IsShown()) then return out end
    local skip = {}
    for _, id in ipairs(skipIds or {}) do skip[id] = true end
    local cx, cy = c:GetCenter()
    local k = UIPer(c)
    cx, cy = Plain(cx), Plain(cy)
    if cx and cy and k then
        out.xs[1] = { at = cx * k, word = Tr("the center point") }
        out.ys[1] = { at = cy * k, word = Tr("the center point") }
    end
    for _, e in ipairs(Engine.LayoutElementRects(layoutId)) do
        if not (skip[e.id] or Rides(e.id, skip)) then
            local nm = e.name
            local mid = EO.EdgeWords(nm, "middle")
            local xs, ys = out.xs, out.ys
            xs[#xs + 1] = { at = e.left, word = EO.EdgeWords(nm, "left") }
            xs[#xs + 1] = { at = e.left + e.width / 2, word = mid }
            xs[#xs + 1] = { at = e.left + e.width, word = EO.EdgeWords(nm, "right") }
            ys[#ys + 1] = { at = e.bottom + e.height, word = EO.EdgeWords(nm, "top") }
            ys[#ys + 1] = { at = e.bottom + e.height / 2, word = mid }
            ys[#ys + 1] = { at = e.bottom, word = EO.EdgeWords(nm, "bottom") }
        end
    end
    return out
end

-- Sizes

-- a group's icon width in its own units: the Reminder group's pulse icon, any
-- other group's grid slot
local function GroupIconUnits(g)
    if g.groupKind == "reminder" then
        return Engine.Snap(math.max(4, Store.Resolve(g, "pulse", "size") or 80), g)
    end
    return (Engine.GridMetrics(g))
end

function EO.Size(id)
    if Busy() then return false end
    local rec = Store.Get(id)
    local kind = KindOf(rec)
    if not kind then return nil end
    local k = Engine.ScaleOf(rec)
    if kind == "group" then return { icon = GroupIconUnits(rec) * k } end
    local w, h
    if kind == "bar" then w, h = Engine.BarSize(rec, FrameOf(rec)) else w, h = Engine.IconSize(rec) end
    return { w = w * k, h = h * k }
end

-- v as a whole number in the field's range (floor: a lower bound of our own);
-- true when that changed the setting
local function SetWhole(rec, section, field, v, floor)
    v = tonumber(v)
    if not v then return false end
    local def = FieldDef(rec, section, field)
    local lo = math.max((def and def.min) or 1, floor or -math.huge)
    v = math.max(lo, math.min((def and def.max) or v, math.floor(v + 0.5)))
    if Store.Resolve(rec, section, field) == v then return false end
    Store.SetOverride(rec, section, field, v)
    return true
end

function EO.Resize(id, w, h, fixed)
    if Busy() then return false end
    local rec = Store.Get(id)
    local kind = KindOf(rec)
    if not (kind == "bar" or kind == "icon") or Store.Locked(rec) then return false end
    local f = LiveFrame(rec)
    local before = f and { RectF(rec, f) }
    if not (before and before[1]) then return false end
    local k = Engine.ScaleOf(rec)
    local changed = false
    if kind == "bar" then
        -- an axis the anchor matches takes the target's size, not this one
        local sc = Store.Resolve(rec, "size", "scale") or 1
        if w and not f._adMatchW then changed = SetWhole(rec, "size", "width", w / k / sc) or changed end
        if h and not f._adMatchH then changed = SetWhole(rec, "size", "height", h / k / sc) or changed end
    else
        -- 0 is the automatic size, so a size from the screen is at least 1
        local sc = Store.Resolve(rec, "position", "iconScale") or 1
        if w then changed = SetWhole(rec, "position", "iconWidth", w / k / sc, 1) or changed end
        if h then changed = SetWhole(rec, "position", "iconHeight", h / k / sc, 1) or changed end
    end
    if changed then
        Engine.Rebuild()
        KeepFixed(rec, f, before, fixed)
    end
    return true
end

-- The whole icon scale (36ths over the icon width) whose slot lands nearest
-- want; slots grow with it, so the nearest sits by the plain ratio.
local function NearestIconSize(g, want)
    local def = FieldDef(g, "arrangement", "iconSize")
    local lo, hi = (def and def.min) or 16, (def and def.max) or 128
    local iw = Store.Resolve(g, "arrangement", "iconWidth") or 36
    if iw <= 0 then return nil end
    local guess = math.floor(want * 36 / iw + 0.5)
    local cur = Store.Resolve(g, "arrangement", "iconSize") or 36
    local best, bestD
    for n = math.max(lo, guess - 3), math.min(hi, guess + 3) do
        local w = WithValues(g, "arrangement", { iconSize = n }, function() return (Engine.GridMetrics(g)) end)
        local d = math.abs(w - want)
        if not best or d < bestD - 1e-6 or (math.abs(d - bestD) <= 1e-6 and math.abs(n - cur) < math.abs(best - cur)) then
            best, bestD = n, d
        end
    end
    return best or math.max(lo, math.min(hi, guess))
end

function EO.SetGroupIcon(id, px, fixed)
    if Busy() then return false end
    local g = Store.Get(id)
    if KindOf(g) ~= "group" or Store.Locked(g) then return false end
    local f = LiveFrame(g)
    local before = f and { RectF(g, f) }
    local want = tonumber(px)
    if not (before and before[1] and want) then return false end
    want = want / Engine.ScaleOf(g)
    local section, field, v
    if g.groupKind == "reminder" then
        section, field = "pulse", "size"
        local def = FieldDef(g, section, field)
        v = math.max((def and def.min) or 32, math.min((def and def.max) or 256, math.floor(want + 0.5)))
    else
        section, field = "arrangement", "iconSize"
        v = NearestIconSize(g, want)
    end
    if not v then return false end
    if Store.Resolve(g, section, field) == v then return true end
    Store.SetOverride(g, section, field, v)
    Engine.Rebuild()
    KeepFixed(g, f, before, fixed)
    return true
end

-- Anchoring

function EO.CanAnchor(id, target)
    if Busy() then return false end
    return CanAnchorRec(Store.Get(id), target)
end

function EO.Anchor(id, target, src, dst)
    if Busy() then return false end
    local rec = Store.Get(id)
    if not CanAnchorRec(rec, target) then return false end
    local f = LiveFrame(rec)
    local l, b, w, h
    if f then l, b, w, h = LiveRect(f) end
    if not l then return false end
    local kind, trec, tf = TargetOf(rec, target)
    local fs, fd = Facing(f, l, b, w, h, kind, trec, tf)
    src = FX[src or ""] and src or fs
    dst = FX[dst or ""] and dst or fd
    local vals = { anchorEnabled = true, anchorTargetKind = kind, anchorTargetId = trec.id,
        anchorSrcPoint = src, anchorDstPoint = dst }
    local gx, gy = Guess(f, l, b, w, h, src, tf, dst)
    local ox, oy, cut = Fit(rec, f, vals, gx, gy, l, b + h)
    if not ox then
        Engine.Rebuild()
        return false
    end
    -- the first pick only: the list after it stays
    Anchor.PickSet(rec, kind .. ":" .. trec.id)
    Store.SetOverride(rec, "anchor", "anchorSrcPoint", src)
    Store.SetOverride(rec, "anchor", "anchorDstPoint", dst)
    WriteOffsets(rec, ox, oy)
    Engine.Rebuild()
    return true, cut
end

function EO.SetPoints(id, src, dst)
    if Busy() then return false end
    local rec = Store.Get(id)
    if not KindOf(rec) or Store.Locked(rec) or not (FX[src or ""] and FX[dst or ""]) then return false end
    -- the cursor and a nameplate have no target point to keep it by
    local kind = R(rec, "anchorTargetKind") or "group"
    if kind == "mouse" or kind == "nameplate" then return false end
    local tf, f = PinnedTo(rec), LiveFrame(rec)
    local l, b, w, h
    if tf and f then l, b, w, h = LiveRect(f) end
    if not l then return false end
    local gx, gy = Guess(f, l, b, w, h, src, tf, dst)
    local ox, oy, cut = Fit(rec, f, { anchorSrcPoint = src, anchorDstPoint = dst }, gx, gy, l, b + h)
    if not ox then
        Engine.Rebuild()
        return false
    end
    Store.SetOverride(rec, "anchor", "anchorSrcPoint", src)
    Store.SetOverride(rec, "anchor", "anchorDstPoint", dst)
    WriteOffsets(rec, ox, oy)
    Engine.Rebuild()
    return true, cut
end

-- Anchor off, its own spot written so it stays where it is. Like the panel's
-- None, the list after the first pick goes too, so none waits hidden.
function EO.Free(id)
    if Busy() then return false end
    local rec = Store.Get(id)
    if not KindOf(rec) or Store.Locked(rec) or not Anchor.IsEnabled(rec) then return false end
    local f = LiveFrame(rec)
    local nx, ny
    if f and PinnedTo(rec) then
        local l, b, w, h = RectF(rec, f)
        local c = f:GetParent()
        local ccx, ccy
        if c then ccx, ccy = c:GetCenter() end
        local kf, kc = UIPer(f), c and UIPer(c)
        ccx, ccy = Plain(ccx), Plain(ccy)
        if l and ccx and ccy and kf and kc then
            -- a matched bar takes its own size back: its top-left stays
            local w1, h1 = w, h
            if rec.type == "bar" then w1, h1 = Engine.BarSize(rec) end
            local r = kc / kf
            nx, ny = l + w1 / 2 - ccx * r, b + h - h1 / 2 - ccy * r
            if rec.type == "icon" then
                nx = nx - (Store.Resolve(rec, "position", "offsetX") or 0)
                ny = ny - (Store.Resolve(rec, "position", "offsetY") or 0)
            end
        end
    end
    Anchor.SlotSet(rec, 1, "none")
    if nx then
        local pos = Pos(rec)
        pos.x, pos.y = nx, ny
    end
    Store.Dirty("style", rec.id)
    Engine.Rebuild()
    return true
end

function EO.AnchorInfo(id)
    if Busy() then return false end
    local rec = Store.Get(id)
    if not (KindOf(rec) and Anchor.IsEnabled(rec)) then return nil end
    -- the pick it sits on now, else its first
    local t, kind, n = Anchor.Effective(rec)
    local tid, frameName
    if t and n and n > 0 then
        kind, tid, frameName = Anchor.Backup(rec, n)
    else
        n = 0
        kind, tid, frameName = R(rec, "anchorTargetKind") or "group", R(rec, "anchorTargetId"), R(rec, "anchorTargetFrame")
    end
    local info = { src = R(rec, "anchorSrcPoint") or "TOP", dst = R(rec, "anchorDstPoint") or "BOTTOM",
        x = R(rec, "anchorOffsetX") or 0, y = R(rec, "anchorOffsetY") or 0,
        kind = kind, slot = n + 1, there = t ~= nil }
    local lay = MemberLayout(rec)
    local trec = tid and Store.Get(tid)
    -- info.name is drawn as it is: a record's or frame's name as named, the
    -- other targets already in the client's words
    if kind == "layout" and lay and tid == lay.id then
        info.to, info.name = "point", Tr("the center point")
    elseif REC_KIND[kind] and trec then
        info.to, info.name = trec.id, trec.name
    else
        info.to = "other"
        if kind == "frame" then
            info.name = frameName
        elseif kind == "mouse" then
            info.name = Tr("the mouse cursor")
        elseif kind == "nameplate" then
            info.name = Tr("the target's nameplate")
        elseif kind == "layout" then
            info.name = trec and trec.name
        else
            info.name = Anchor.SlotWords(rec, n + 1)
        end
        if type(info.name) ~= "string" or info.name == "" then info.name = "?" end
    end
    return info
end

-- What the panel's Position X / Y show: anchor offsets while pinned, else its
-- spot from the layout's center point, or from the screen's middle.
function EO.Measure(id)
    if Busy() then return false end
    local rec = Store.Get(id)
    if not KindOf(rec) then return nil end
    if Anchor.ResolveTarget(rec) then
        return R(rec, "anchorOffsetX") or 0, R(rec, "anchorOffsetY") or 0
    end
    local p = type(rec.pos) == "table" and rec.pos or {}
    local x, y = tonumber(p.x) or 0, tonumber(p.y) or 0
    local ui = Store.UI()
    if ui and ui.posFrom == "screen" then
        local lay = MemberLayout(rec)
        local px, py = Engine.LayoutPoint(lay.id)
        local s = Store.LayoutScale(lay)
        return (px or 0) + s * x, (py or 0) + s * y
    end
    return x, y
end

-- History: per layout, for this session. A change is kept as the paths it
-- touched, so an undo puts back only those and leaves later panel edits be.

local history = {}   -- [layoutId] = { undo = {}, redo = {}, pending = snapshot }
local LAYOUT_KEYS = { "pos", "scale", "strata", "strataShift", "centerSet", "pin" }

local function Copy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth > 32 then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x, depth + 1) end
    return out
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- the layout's own place and every member record, copied
local function Snapshot(lay)
    local s = { [lay.id] = {} }
    for _, k in ipairs(LAYOUT_KEYS) do s[lay.id][k] = Copy(lay[k]) end
    for _, rec in ipairs(Store.MembersOf(lay)) do s[rec.id] = Copy(rec) end
    return s
end

-- every path whose value differs between a and b
local function Diff(a, b, path, out, id)
    local keys = {}
    for k in pairs(a) do keys[k] = true end
    for k in pairs(b) do keys[k] = true end
    for k in pairs(keys) do
        local x, y = a[k], b[k]
        local p = {}
        for i = 1, #path do p[i] = path[i] end
        p[#p + 1] = k
        if type(x) == "table" and type(y) == "table" then
            Diff(x, y, p, out, id)
        elseif not Same(x, y) then
            out[#out + 1] = { id = id, path = p, before = Copy(x), after = Copy(y) }
        end
    end
end

-- Writes v at path inside root, into the tables already there.
local function Put(root, path, v)
    local t = root
    for i = 1, #path - 1 do
        local k = path[i]
        if type(t[k]) ~= "table" then
            if v == nil then return end
            t[k] = {}
        end
        t = t[k]
    end
    t[path[#path]] = Copy(v)
end

-- the layout or a record a change touches carries a lock
local function Blocked(lay, entry)
    if Store.Locked(lay) then return true end
    for _, c in ipairs(entry) do
        local rec = Store.Get(c.id)
        if rec and rec ~= lay and Store.Locked(rec) then return true end
    end
    return false
end

local function Restore(entry, side)
    local touched = {}
    for _, c in ipairs(entry) do
        local rec = Store.Get(c.id)
        if rec then
            Put(rec, c.path, c[side])
            touched[c.id] = true
        end
    end
    for id in pairs(touched) do Store.Dirty("style", id) end
    Engine.Rebuild()
end

local function LayoutRec(id)
    local lay = Store.Get(id)
    return (lay and lay.type == "layout") and lay or nil
end

function EO.Begin(layoutId)
    if Busy() then return false end
    local lay = LayoutRec(layoutId)
    if not lay or Store.Locked(lay) then return false end
    local h = history[layoutId] or { undo = {}, redo = {} }
    history[layoutId] = h
    h.pending = Snapshot(lay)
    return true
end

function EO.Commit(layoutId)
    if Busy() then return false end
    local h, lay = history[layoutId], LayoutRec(layoutId)
    if not (h and h.pending and lay) then return false end
    local was, now, entry = h.pending, Snapshot(lay), {}
    h.pending = nil
    for id, a in pairs(was) do
        if now[id] then Diff(a, now[id], {}, entry, id) end
    end
    if #entry == 0 then return false end
    h.undo[#h.undo + 1] = entry
    while #h.undo > EO.HISTORY_CAP do table.remove(h.undo, 1) end
    wipe(h.redo)
    return true
end

local function Step(layoutId, from, to, side)
    if Busy() then return false end
    local h, lay = history[layoutId], LayoutRec(layoutId)
    local list = h and h[from]
    if not (lay and list and #list > 0) or Blocked(lay, list[#list]) then return false end
    local entry = table.remove(list)
    h.pending = nil
    Restore(entry, side)
    h[to][#h[to] + 1] = entry
    return true
end

function EO.Undo(layoutId) return Step(layoutId, "undo", "redo", "before") end
function EO.Redo(layoutId) return Step(layoutId, "redo", "undo", "after") end

local function CanStep(layoutId, from)
    if Busy() then return false end
    local h, lay = history[layoutId], LayoutRec(layoutId)
    local list = h and h[from]
    return lay ~= nil and list ~= nil and #list > 0 and not Blocked(lay, list[#list])
end

function EO.CanUndo(layoutId) return CanStep(layoutId, "undo") end
function EO.CanRedo(layoutId) return CanStep(layoutId, "redo") end

-- Teardown: it touches nothing on screen, so it runs in combat too.
function EO.ClearHistory()
    wipe(history)
    return true
end
