-- Layouts on screen. A layout is a positioned container; its groups, free
-- icons and bar holders are our own frames placed by grid math. Membership is
-- the ordered id array on records, and a group icon's cell is its rec.gpos.
-- Rebuilds are coalesced to one pass per frame.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory

local Engine = {}
NS.LayoutEngine = Engine

local WHITE = "Interface\\Buttons\\WHITE8X8"

local layoutFrames = {}   -- [layoutId] = container
local groupFrames = {}    -- [groupId] = container
local barFrames = {}      -- [barId] = holder (the bars runtime fills it)

-- Core\AD_Anchor.lua does all anchoring; these tell it how to find frames.
if NS.Anchor then
    NS.Anchor.RegisterProvider("layout", function(id) return layoutFrames[id] end)
    NS.Anchor.RegisterProvider("group",  function(id) return groupFrames[id] end)
    NS.Anchor.RegisterProvider("bar",    function(id) return barFrames[id] end)
    NS.Anchor.RegisterProvider("icon",   function(id) return Factory.frames[id] end)
    -- While the options window is open, a bar pinned to the target's nameplate
    -- hides (the editor shows a stand-in), so anchoring needs the edit-mode check.
    if NS.Anchor.SetEditModeCheck then
        NS.Anchor.SetEditModeCheck(function() return Engine.IsEditMode() end)
    end
end

-- Half a pixel is a tie that a float rect read tips either way, so rounding
-- leans up by a sliver no common pixel fraction lands on: one spot always
-- snaps to one pixel. Core\AD_Anchor.lua rounds the same way.
local TIE = 0.0058

-- v rounded to whole physical pixels, px frame units each.
local function PixRound(v, px)
    return math.floor(v / px + 0.5 + TIE) * px
end

-- A left edge leans the other way at the tie, so a centred frame's spare
-- pixel falls on its right and below (the bottom leans up), as FloorPx and
-- the aura rows' lean put a centred row's: every centred thing agrees.
local function PixRoundLeft(v, px)
    return math.floor(v / px + 0.5 - TIE) * px
end

-- One physical pixel in UIParent's units, the scale of every engine frame.
local function UIPx()
    local _, screenH = GetPhysicalScreenSize()
    local ppu = (screenH / 768) * (UIParent:GetEffectiveScale() or 1)
    if ppu <= 0 then return nil end
    return 1 / ppu
end

-- Pixel snap for the whole addon; slot sizes and steps are snapped separately.
local function Snap(v)
    local px = UIPx()
    if not px then return v end
    return PixRound(v, px)
end

-- A whole or half pixel count floored to whole pixels, toward the top-left;
-- the sliver only absorbs float error.
local function FloorPx(v)
    local px = UIPx()
    if not px then return v end
    return math.floor(v / px + TIE) * px
end
Engine.Snap, Engine.FloorPx, Engine.PixRound = Snap, FloorPx, PixRound

-- Pixel-exact placement. A CENTER anchor puts the edges on half pixels when the
-- frame is an odd number of pixels across, and a whole-unit offset is a whole
-- pixel only at UI scale 1, so 1px lines blur. Place, read the bottom-left and
-- shift by its sub-pixel remainder, so every edge lands on a physical pixel.
local function SnapPlacement(f, container, x, y)
    f:ClearAllPoints()
    f:SetPoint("CENTER", container, "CENTER", x, y)
    local left, bottom = f:GetLeft(), f:GetBottom()
    if not (left and bottom) then return end
    -- A secret rect (a bar that was on a nameplate) gets no snap math.
    if issecretvalue and (issecretvalue(left) or issecretvalue(bottom)) then return end
    local _, physH = GetPhysicalScreenSize()
    local s = f:GetEffectiveScale() or 1
    if not physH or physH <= 0 or s <= 0 then return end
    local px = (768 / physH) / s           -- one physical pixel in frame units
    local dx = left - PixRoundLeft(left, px)
    local dy = bottom - PixRound(bottom, px)
    if dx ~= 0 or dy ~= 0 then
        f:SetPoint("CENTER", container, "CENTER", x - dx, y - dy)
    end
end

local moveMode = false
local editMode = false   -- true while the options panel is open

-- With the panel open, a record failing its load conditions is still drawn,
-- tagged, when its eye in the panel is on or, for an eye never clicked, when
-- "Show unloaded items while editing" is on, and not while the sidebar lists
-- only this character's items (Store.UnloadedDrawn). A loaded
-- one whose eye hid it (Store.EditHidden) is not drawn while the panel is
-- open. Every load check that decides what the engine draws goes through here.
local function ShowsRec(rec)
    if Store.IsLoaded(rec) then
        return not (editMode and Store.EditHidden(rec))
    end
    return editMode and Store.UnloadedDrawn(rec)
end

-- A record drawn here along with the group and layout it sits in.
local function DrawnHere(rec)
    if not ShowsRec(rec) then return false end
    local g = rec.groupId and Store.Get(rec.groupId)
    if g and not ShowsRec(g) then return false end
    local lay = Store.Get((g and g.layoutId) or rec.layoutId)
    return not (lay and not ShowsRec(lay))
end

-- The "unloaded" tag on a previewed record's frame, edit mode only. It sits
-- above the top-left corner (the Edit chip owns the bottom edge); dy lifts it
-- clear of a group's border. Re-anchored every call: frames are pooled.
local function GhostTag(f, rec, dy)
    local on = editMode and not Store.IsLoaded(rec) and Store.GetSetting("hideGhostMark") ~= true
    local tag = f._adGhostTag
    if not on then
        if tag then tag:Hide() end
        return
    end
    if not tag then
        -- the sidebar's slashed eye, small and amber, on a dark square
        tag = CreateFrame("Frame", nil, f)
        tag:SetSize(14, 14)
        tag.bg = tag:CreateTexture(nil, "BACKGROUND")
        tag.bg:SetAllPoints()
        tag.bg:SetColorTexture(0, 0, 0, 0.75)
        tag.eye = tag:CreateTexture(nil, "OVERLAY")
        tag.eye:SetSize(12, 12)
        tag.eye:SetPoint("CENTER", 0, 0)
        tag.eye:SetTexture(Engine.GHOST_TEX)
        tag.eye:SetVertexColor(0.95, 0.76, 0.31, 1)
        f._adGhostTag = tag
    end
    tag:ClearAllPoints()
    if dy then
        -- a group or layout: just above its corner, clear of its border
        tag:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, dy)
    elseif rec.type == "bar" then
        -- a bar: inside its left end, centred on a thin bar too
        tag:SetPoint("LEFT", f, "LEFT", 1, 0)
    else
        -- an icon: inside its own corner, so a grid of them never stacks
        tag:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    end
    tag:SetFrameLevel(f:GetFrameLevel() + 101)
    tag:Show()
end
Engine.GHOST_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_EyeOff"

-- While the panel is open, chrome goes to HIGH and no display sits above
-- MEDIUM: a bar anchored to a group's top covers its name tab, and one set
-- to DIALOG would out-strata the chrome. Displays are only clamped down, and
-- their own strata come back when the panel closes.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5 }
local CHROME_STRATA = "HIGH"

local function EditStrata(want)
    want = want or "MEDIUM"
    if not editMode then return want end
    if (STRATA_RANK[want] or 3) > STRATA_RANK.MEDIUM then return "MEDIUM" end
    return want
end

-- A bar riding a spell's action button or Cooldown Manager icon goes back to
-- its own spot, strata and level when that target leaves the screen between
-- two rebuilds (Core\AD_Anchor.lua calls it).
if NS.Anchor and NS.Anchor.SetFreePlacer then
    NS.Anchor.SetFreePlacer(function(rec, f)
        local c = f:GetParent()
        if not (c and rec.pos) then return end
        f:SetFrameStrata(EditStrata(Store.Resolve(rec, "frame", "strata")))
        f:SetFrameLevel(Store.Resolve(rec, "frame", "level") or 10)
        SnapPlacement(f, c, rec.pos.x or 0, rec.pos.y or 0)
    end)
end

-- An icon's own size: the group's slot unless Use group scale is off; a free
-- icon uses its width and height (0 = the base) times its scale. Placement,
-- ApplyIconPosition and PlaceCell share it. Position offsets are visual only.
-- Place before ApplyStyle: the border host takes the frame level.
local function MemberSize(rec, baseW, baseH)
    local Rp = function(k) return Store.Resolve(rec, "position", k) end
    local w, h = baseW, baseH
    if not rec.groupId or Rp("useGroupScale") == false then
        local pw, ph = Rp("iconWidth") or 0, Rp("iconHeight") or 0
        if pw > 0 then w = pw end
        if ph > 0 then h = ph end
        local sc = Rp("iconScale") or 1
        w, h = w * sc, h * sc
    end
    return w, h
end

-- The size the engine gives an icon, from the records alone (a group's slot
-- with the same Snap math as PlaceGroup, a free icon's own): the options
-- preview draws the icon at it.
function Engine.IconSize(rec)
    local bw, bh = 36, 36
    local g = rec and rec.groupId and Store.Get(rec.groupId)
    if g and g.groupKind == "reminder" then
        -- an aura reminder: the row's size (Drivers\AD_DriverReminders.lua)
        bw = Snap(math.floor((Store.Resolve(g, "pulse", "auraSize") or 40) + 0.5))
        bh = bw
    elseif g then
        local R = function(field) return Store.Resolve(g, "arrangement", field) end
        local scale = math.floor((R("iconSize") or 36) + 0.5) / 36
        bw = Snap(math.floor((R("iconWidth") or 36) * scale + 0.5))
        bh = Snap(math.floor((R("iconHeight") or 36) * scale + 0.5))
    end
    local w, h = MemberSize(rec, bw, bh)
    return Snap(w), Snap(h)
end

-- Play on screen draws a copy over the icon (UI\AD_IconScreen), so the live
-- frame stays hidden under it through every rebuild.
local function ShowIcon(f, rec)
    local scr = NS.IconScreen
    if scr and scr.Follow(rec, f) then
        f:Hide()
    else
        f:Show()
    end
end

-- An icon's strata and level, from its own settings over its parent's.
local function IconLayer(f, rec, parent)
    local Rp = function(k) return Store.Resolve(rec, "position", k) end
    local strata = Rp("strata")
    if strata and strata ~= "AUTO" then
        f:SetFrameStrata(strata)
    else
        f:SetFrameStrata(parent:GetFrameStrata())
    end
    f:SetFrameLevel(parent:GetFrameLevel() + 2 + (Rp("frameLevel") or 0))
end

-- A free icon: a root, placed by its centre and snapped by measuring.
local function ApplyIconPosition(f, rec, parent, cx, cy, baseW, baseH)
    local Rp = function(k) return Store.Resolve(rec, "position", k) end
    local w, h = MemberSize(rec, baseW, baseH)
    f:SetSize(Snap(w), Snap(h))
    -- Size first, so SnapPlacement measures the final rect.
    SnapPlacement(f, parent, cx + (Rp("offsetX") or 0), cy + (Rp("offsetY") or 0))
    IconLayer(f, rec, parent)
end

-- A group's icon: a whole-pixel size at a corner counted in whole pixels from
-- the parent's top-left (left, top; y down) and never read back, so it rides
-- its group by whole pixels and every pass lands it on the same pixels. A
-- member sized off its slot centres on it. Returns the corner it took.
local function PlaceCell(f, rec, parent, left, top, slotW, slotH)
    local Rp = function(k) return Store.Resolve(rec, "position", k) end
    local w, h = MemberSize(rec, slotW, slotH)
    w, h = Snap(w), Snap(h)
    f:SetSize(w, h)
    local x = Snap(left + FloorPx((slotW - w) / 2) + Snap(Rp("offsetX") or 0))
    local y = Snap(top + FloorPx((slotH - h) / 2) - Snap(Rp("offsetY") or 0))
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    IconLayer(f, rec, parent)
    return x, y
end

-- A group frame is a root: it takes its spot once its size is final and snaps
-- by measuring, so the corner its icons count from sits on a pixel. The anchor
-- post-pass places an anchored one. ox, oy move a shrunk box off the spot.
local function PlaceGroupRoot(group, gf, ox, oy)
    if NS.Anchor and NS.Anchor.ResolveTarget(group) then return end
    local c = gf:GetParent()
    if not c then return end
    local pos = group.pos or {}
    SnapPlacement(gf, c, (pos.x or 0) + (ox or 0), (pos.y or 0) + (oy or 0))
end

-- The anchor and glide code below must stay above its users: a closure only
-- binds locals declared before it.

-- Group anchoring: anchors are relative, so only a cycle is a hazard.

local function PointXY(f, point)
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    if not l then return end
    local x = (point:find("LEFT") and l) or (point:find("RIGHT") and (l + w))
        or (l + w / 2)
    local y = (point:find("BOTTOM") and b) or (point:find("TOP") and (b + h))
        or (b + h / 2)
    return x, y
end

-- Thin wrappers; the cycle guard, resolver and offset writer are in AD_Anchor.
local function ResolveAnchorTarget(grec)
    return NS.Anchor and NS.Anchor.ResolveTarget(grec) or nil
end

-- Post-pass, once every live frame exists (cross-layout too); hence not inline.
local function ApplyAnchors()
    if NS.Anchor then NS.Anchor.ApplyAll() end
end

-- Dragging an anchored group edits its anchor offsets, not pos.
local function SaveAnchoredOffsets(gf, grec)
    if not (NS.Anchor and NS.Anchor.SaveOffsets(grec, gf)) then return false end
    NS.Anchor.Apply(grec, gf)   -- re-place now so the drag reads live
    return true
end

-- Dynamic placement: with the panel closed a dynamic group compacts; with it
-- open every icon is back in its static cell. The inputs are combat-legal on
-- Forever: icon state comes from the factory's state writer, fed by shadow
-- Cooldowns whose IsShown stays plain in combat (SetCooldownFromDurationObject
-- adds no secret aspect), and only our own frames move.

-- Smooth-move glide: a frame-rate-independent exponential ease on one shared
-- driver whose OnUpdate turns off when the last glide lands. A running glide
-- is retargeted from where the icon is now, not from its previous target.
local dynAnims = {}
local dynAnimFrame

local function DynAnimTick(_, dt)
    for fr, a in pairs(dynAnims) do
        if not fr:IsShown() then
            dynAnims[fr] = nil
        else
            local k = 1 - math.exp(-a.rate * (dt or 0))
            if k > 1 then k = 1 elseif k < 0 then k = 0 end
            a.x = a.x + (a.tx - a.x) * k
            a.y = a.y + (a.ty - a.y) * k
            if math.abs(a.tx - a.x) < 0.5 and math.abs(a.ty - a.y) < 0.5 then
                a.x, a.y = a.tx, a.ty
                dynAnims[fr] = nil
            end
            fr:SetPoint("TOPLEFT", a.p, "TOPLEFT", a.x, -a.y)
        end
    end
    if not next(dynAnims) then dynAnimFrame:SetScript("OnUpdate", nil) end
end

-- Glide f from corner (fx, fy) to corner (tx, ty), top-left offsets on p with
-- y down, landing on the target exactly. dur is the time to get about 95% of
-- the way there (rate = 3 / dur).
local function StartDynAnim(f, p, fx, fy, tx, ty, dur)
    local a = dynAnims[f]
    if not a then
        a = {}
        dynAnims[f] = a
    end
    a.p, a.x, a.y, a.tx, a.ty = p, fx, fy, tx, ty
    a.rate = 3 / math.max(0.05, dur or 0.18)
    f:SetPoint("TOPLEFT", p, "TOPLEFT", fx, -fy)
    if not dynAnimFrame then dynAnimFrame = CreateFrame("Frame") end
    dynAnimFrame:SetScript("OnUpdate", DynAnimTick)
end

local fcfsOrders = {}   -- [groupId] = { recId, ... } arrival order, runtime only
local dynCtx = {}       -- [groupId] = what the last full rebuild measured

local function GridShape(rows, cols)
    if rows <= 1 then return "horizontal" end
    if cols <= 1 then return "vertical" end
    return "multi"
end
Engine.GridShape = GridShape

local ALIGN_VALID = {
    horizontal = { left = true, center = true, right = true },
    vertical = { top = true, center = true, bottom = true },
    multi = { top = true, bottom = true, left = true, right = true,
        center_h = true, center_v = true },
}
-- Applied when read, so nothing is rewritten: a one-row "center" reads as
-- center_h once a second row appears, and as "center" again when it goes.
local ALIGN_REMAP = {
    horizontal = { center_h = "center", center_v = "center", top = "left", bottom = "right" },
    vertical = { center_h = "center", center_v = "center", left = "top", right = "bottom" },
    multi = { center = "center_h" },
}

-- Effective alignment and shape. rows and cols default to the configured grid;
-- placement passes the grid it drew; the aura-group pin and options use it too.
function Engine.EffectiveAlignment(group, rows, cols)
    rows = rows or math.max(1, Store.Resolve(group, "arrangement", "rows") or 1)
    cols = cols or math.max(1, Store.Resolve(group, "arrangement", "cols") or 6)
    local shape = GridShape(rows, cols)
    local a = Store.Resolve(group, "arrangement", "alignment") or "center"
    if not ALIGN_VALID[shape][a] then
        a = ALIGN_REMAP[shape][a] or ((shape == "multi") and "center_h" or "center")
    end
    return a, shape
end

-- Busy means the swipe is running: a cooldown, or a totem that is down. A live
-- totem sits in the factory's ready state (it wears the ready glows), so
-- totems invert: "show only what is running" must show the live ones.
local function DynBusy(rec, f)
    if rec.kind == "totem" then return f._adOnCooldown ~= true end
    return f._adOnCooldown == true
end

local function DynDropsOut(rec, f, collapse)
    -- Items, trinkets and ammo their stock hides always close their cell, and
    -- so does a passive trinket in an on-use-only slot.
    if NS.Factory.StockHidden(f, rec) then return true end
    if rec.kind == "trinket" and f._adPassive then return true end
    -- An inert icon gives up its cell under any drop-out rule, aura icons too
    -- (conditions are plain reads). A faded icon keeps its cell.
    if NS.Conditions and NS.Conditions.IsOwnInert(rec) then return true end
    -- Aura holders are occlusion-only: whether the aura is up can't be read in
    -- combat on Forever, so they always keep one cell. Auras that come and go
    -- belong in an Aura Group.
    if rec.kind == "aura" or collapse == "none" then return false end
    if collapse == "ready" then return not DynBusy(rec, f) end
    if collapse == "cooldown" then return DynBusy(rec, f) end
    if collapse == "hidden" then return (f._adStateAlpha or 1) <= 0 end
    return false
end

-- Top-left corner of visual cell (vr, vc), from the full grid's top-left with
-- y down: whole pixels, as every term is.
local function CellXY(ctx, vr, vc)
    return ctx.pad + vc * ctx.stepX, ctx.pad + vr * ctx.stepY
end

-- Packs items along one visual row, left to right, against the aligned edge or
-- centered. A full row lands on the static cells, so Dynamic never nudges it.
-- Corners, as CellXY; centred, an odd leftover pixel goes right.
local function PackRow(ctx, items, align, vr, out)
    local n = #items
    if n == 0 then return end
    local span = n * ctx.stepX - ctx.spacingX
    local x0
    if align == "left" then
        x0 = ctx.pad
    elseif align == "right" then
        x0 = ctx.contentW - ctx.pad - span
    else
        x0 = FloorPx((ctx.contentW - span) / 2)
    end
    local _, y = CellXY(ctx, vr, 0)
    for i, it in ipairs(items) do
        out[it] = { x0 + (i - 1) * ctx.stepX, y }
    end
end

local function PackCol(ctx, items, align, vc, out)
    local n = #items
    if n == 0 then return end
    local span = n * ctx.stepY - ctx.spacingY
    local y0   -- the block's top edge
    if align == "top" then
        y0 = ctx.pad
    elseif align == "bottom" then
        y0 = ctx.contentH - ctx.pad - span
    else
        y0 = FloorPx((ctx.contentH - span) / 2)
    end
    local x = CellXY(ctx, 0, vc)
    for i, it in ipairs(items) do
        out[it] = { x, y0 + (i - 1) * ctx.stepY }
    end
end

-- First come, first served: survivors keep their order, newcomers join at the
-- end in cell order, so a batch arriving together gets a stable order.
local function FcfsList(gid, active)
    local byId, seen, out = {}, {}, {}
    for _, m in ipairs(active) do byId[m.rec.id] = m end
    for _, id in ipairs(fcfsOrders[gid] or {}) do
        local m = byId[id]
        if m and not seen[id] then
            out[#out + 1] = m
            seen[id] = true
        end
    end
    for _, m in ipairs(active) do
        if not seen[m.rec.id] then
            out[#out + 1] = m
            seen[m.rec.id] = true
        end
    end
    local ids = {}
    for i, m in ipairs(out) do ids[i] = m.rec.id end
    fcfsOrders[gid] = ids
    return out
end

-- Where each surviving member goes, as corners on the full grid. One row
-- or column: the order list along the fill direction, aligned. Multi-row: each
-- icon keeps its visual row or column and slides toward the aligned edge.
local function DynTargets(group, ctx, align, shape)
    local collapse = Store.Resolve(group, "arrangement", "dynamicCollapse") or "none"
    local active = {}
    for _, m in ipairs(ctx.members) do
        if not DynDropsOut(m.rec, m.f, collapse) then active[#active + 1] = m end
    end
    local out = {}
    if shape == "multi" then
        local colGravity = align == "top" or align == "bottom" or align == "center_v"
        local lines = {}
        for _, m in ipairs(active) do
            local r = math.floor(m.key / ctx.cols)
            local c = m.key % ctx.cols
            m.vc = (ctx.growthH == "LEFT") and (ctx.cols - 1 - c) or c
            m.vr = (ctx.growthV == "UP") and (ctx.needRows - 1 - r) or r
            local li = colGravity and m.vc or m.vr
            local L = lines[li]
            if not L then
                L = {}
                lines[li] = L
            end
            L[#L + 1] = m
        end
        for li, L in pairs(lines) do
            if colGravity then
                table.sort(L, function(a, b) return a.vr < b.vr end)
                PackCol(ctx, L, (align == "center_v") and "center" or align, li, out)
            else
                table.sort(L, function(a, b) return a.vc < b.vc end)
                PackRow(ctx, L, (align == "center_h") and "center" or align, li, out)
            end
        end
    else
        local list = active   -- already in cell order = priority
        if collapse ~= "none"
            and Store.Resolve(group, "arrangement", "dynamicOrder") == "fcfs" then
            list = FcfsList(group.id, active)
        end
        local rev = (shape == "horizontal" and ctx.growthH == "LEFT")
            or (shape == "vertical" and ctx.growthV == "UP")
        local vis = {}
        for i, m in ipairs(list) do vis[rev and (#list - i + 1) or i] = m end
        if shape == "horizontal" then
            PackRow(ctx, vis, align, 0, out)
        else
            PackCol(ctx, vis, align, 0, out)
        end
    end
    return out
end

-- A group with nothing up: one slot, where the first icon will appear.
local function DynEmptyXY(ctx, align, shape)
    local tmp, lone = {}, {}
    if shape == "horizontal" then
        PackRow(ctx, { lone }, align, 0, tmp)
    elseif shape == "vertical" then
        PackCol(ctx, { lone }, align, 0, tmp)
    else
        local vc = (ctx.growthH == "LEFT") and (ctx.cols - 1) or 0
        local vr = (ctx.growthV == "UP") and (ctx.needRows - 1) or 0
        if align == "top" or align == "bottom" or align == "center_v" then
            PackCol(ctx, { lone }, (align == "center_v") and "center" or align, vc, tmp)
        else
            PackRow(ctx, { lone }, (align == "center_h") and "center" or align, vr, tmp)
        end
    end
    return tmp[lone][1], tmp[lone][2]
end

-- Shrink to content: the survivors' box, its top-left corner on the full grid
-- and its size.
local function DynBox(ctx, targets, align, shape)
    local x1, x2, y1, y2
    for _, t in pairs(targets) do
        if not x1 then
            x1, x2, y1, y2 = t[1], t[1], t[2], t[2]
        else
            if t[1] < x1 then x1 = t[1] end
            if t[1] > x2 then x2 = t[1] end
            if t[2] < y1 then y1 = t[2] end
            if t[2] > y2 then y2 = t[2] end
        end
    end
    if not x1 then
        x1, y1 = DynEmptyXY(ctx, align, shape)
        x2, y2 = x1, y1
    end
    return x1 - ctx.pad, y1 - ctx.pad,
        (x2 - x1) + ctx.slotW + 2 * ctx.pad, (y2 - y1) + ctx.slotH + 2 * ctx.pad
end

-- Places a dynamic group's members, for the full rebuild and the state-edge
-- re-place (ctx is what the last full rebuild measured). Returns true when the
-- container's size changed, so the caller can re-anchor what is pinned to it.
local function DynApply(group, gf, ctx)
    local align, shape = Engine.EffectiveAlignment(group, ctx.needRows, ctx.cols)
    local targets = DynTargets(group, ctx, align, shape)
    -- the box's top-left corner on the full grid, and its size
    local bx, by, w, h = 0, 0, ctx.contentW, ctx.contentH
    if Store.Resolve(group, "arrangement", "dynamicShrink") == true then
        bx, by, w, h = DynBox(ctx, targets, align, shape)
    end
    w, h = math.max(w, Snap(4)), math.max(h, Snap(4))
    local sizeChanged = gf._adDynW ~= w or gf._adDynH ~= h
    gf._adDynW, gf._adDynH = w, h
    gf:SetSize(w, h)
    -- A free group moves by the box's offset, so icons keep their screen spots.
    -- An anchored group keeps its anchor point; the icons sit inside the box.
    PlaceGroupRoot(group, gf, bx + w / 2 - ctx.contentW / 2, ctx.contentH / 2 - by - h / 2)
    local smooth = Store.Resolve(group, "arrangement", "smoothMovement") == true
    local dur = Store.Resolve(group, "arrangement", "smoothDuration") or 0.18
    for _, m in ipairs(ctx.members) do
        local f, rec = m.f, m.rec
        if Factory.frames[rec.id] == f then
            local t = targets[m]
            if t then
                -- Where the icon is now, relative to this pass's box, so a
                -- box that moved doesn't make a standing icon jump.
                local sx, sy = (f._adDynOX or 0) - bx, (f._adDynOY or 0) - by
                local a = dynAnims[f]
                local fromX, fromY
                if a and a.p == gf then
                    fromX, fromY = a.x + sx, a.y + sy
                elseif f._adDynParent == gf and f:IsShown() then
                    fromX, fromY = f._adDynX + sx, f._adDynY + sy
                end
                -- Target corner, computed rather than read back off the frame.
                local tx, ty = PlaceCell(f, rec, gf, t[1] - bx, t[2] - by, ctx.slotW, ctx.slotH)
                if smooth and fromX
                    and (math.abs(fromX - tx) > 0.5 or math.abs(fromY - ty) > 0.5) then
                    StartDynAnim(f, gf, fromX, fromY, tx, ty, dur)
                else
                    dynAnims[f] = nil
                end
                f._adDynParent, f._adDynX, f._adDynY = gf, tx, ty
                f._adDynOX, f._adDynOY = bx, by
                f:Show()
            else
                -- Dropped out: stays attached, so its state edges bring it back.
                dynAnims[f] = nil
                f._adDynParent = nil
                f:Hide()
            end
        end
    end
    return sizeChanged
end

local function EnsureLayoutFrame(rec)
    local f = layoutFrames[rec.id]
    if not f then
        f = CreateFrame("Frame", "ArcUIv2Layout" .. rec.id, UIParent, "BackdropTemplate")
        f:SetSize(2, 2)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f.drag = CreateFrame("Frame", nil, f, "BackdropTemplate")
        f.drag:SetPoint("TOPLEFT", -60, 20)
        f.drag:SetPoint("BOTTOMRIGHT", 60, -20)
        f.drag:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f.drag:SetBackdropColor(0.247, 0.788, 0.949, 0.10)
        f.drag:SetBackdropBorderColor(0.247, 0.788, 0.949, 0.9)
        f.drag:EnableMouse(true)
        f.drag:RegisterForDrag("LeftButton")
        f.drag:Hide()
        f.dragLabel = f.drag:CreateFontString(nil, "OVERLAY")
        f.dragLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        f.dragLabel:SetPoint("TOP", 0, -3)
        f.drag:SetScript("OnDragStart", function()
            if Store.Locked(rec) then return end
            f:StartMoving()
        end)
        f.drag:SetScript("OnDragStop", function()
            if Store.Locked(rec) then return end
            f:StopMovingOrSizing()
            local cx, cy = f:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and ux then
                rec.pos.x = math.floor(cx - ux + 0.5)
                rec.pos.y = math.floor(cy - uy + 0.5)
            end
            Engine.Rebuild()
        end)
        layoutFrames[rec.id] = f
    end
    return f
end

local function EnsureGroupFrame(rec)
    local f = groupFrames[rec.id]
    if not f then
        f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        groupFrames[rec.id] = f
    end
    return f
end

-- Dragged on screen only while editing, never under a lock (on the record,
-- its group or its layout).
local function CanMove(rec)
    return editMode and not Store.Locked(rec)
end

-- Saves a drop: round the offset, store it, then re-place from the stored
-- value so the live anchor and the saved one can't disagree.
local function SaveRelativePosition(f, rec)
    local parent = f:GetParent()
    if not (rec and parent) then return end
    local cx, cy = f:GetCenter()
    local px, py = parent:GetCenter()
    if not (cx and px) then return end
    rec.pos = rec.pos or {}
    -- An icon's saved pos excludes its visual offset, or a drag would bake the
    -- offset in and the rebuild would add it again.
    local offX, offY = 0, 0
    if rec.type == "icon" then
        offX = Store.Resolve(rec, "position", "offsetX") or 0
        offY = Store.Resolve(rec, "position", "offsetY") or 0
    end
    rec.pos.x = math.floor(cx - px - offX + 0.5)
    rec.pos.y = math.floor(cy - py - offY + 0.5)
    SnapPlacement(f, parent, rec.pos.x + offX, rec.pos.y + offY)
end

-- Group edit chrome: a green border and a title bar with the group's name.
-- Click the bar to open the group's options, drag it to move the group. The
-- container stays click-through so gaps between icons never eat clicks.
local GROUP_GREEN = { 0.2, 0.9, 0.2 }
local GROUP_TEXT = { 0.85, 1, 0.85 }
-- The item the editor has open: its Edit chip reads Editing in this yellow,
-- and a group, which has no chip, turns its name this yellow.
local EDIT_YELLOW = { 1, 0.82, 0 }

local function EnsureGroupChrome(gf)
    if gf._adChrome then return gf._adChrome end
    local ch = {}
    local o = CreateFrame("Frame", nil, gf, "BackdropTemplate")
    o:SetPoint("TOPLEFT", -3, 3)
    o:SetPoint("BOTTOMRIGHT", 3, -3)
    o:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    o:SetBackdropColor(0, 0, 0, 0.5)
    o:SetBackdropBorderColor(GROUP_GREEN[1], GROUP_GREEN[2], GROUP_GREEN[3], 0.9)
    o:EnableMouse(false)
    ch.border = o

    -- The group's name as bare text on its own top edge, no box, only as wide
    -- as the name (WireGroupEdit sizes it), so whatever is placed just above
    -- the group stays in view. It is the drag handle; with names off a small
    -- green grip (bar.grip) marks where to grab.
    local bar = CreateFrame("Button", nil, gf)
    bar:SetHeight(12)
    bar:SetPoint("CENTER", o, "TOP", 0, -3)
    bar.grip = bar:CreateTexture(nil, "ARTWORK")
    bar.grip:SetPoint("LEFT", 0, 0)
    bar.grip:SetPoint("RIGHT", 0, 0)
    bar.grip:SetHeight(4)
    bar.grip:SetColorTexture(GROUP_GREEN[1], GROUP_GREEN[2], GROUP_GREEN[3], 0.9)
    bar.grip:Hide()
    bar:RegisterForDrag("LeftButton")
    bar.fs = bar:CreateFontString(nil, "OVERLAY")
    bar.fs:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    bar.fs:SetPoint("CENTER", 0, 0)
    bar.fs:SetTextColor(GROUP_TEXT[1], GROUP_TEXT[2], GROUP_TEXT[3])
    -- with names off the tab is a blank grip: its tooltip names the group
    bar:SetScript("OnEnter", function()
        bar.fs:SetTextColor(1, 1, 0.5)
        -- a locked group says why it does not move
        if (bar.fs:GetText() == "" or bar._adLocked) and bar._adName then
            GameTooltip:SetOwner(bar, "ANCHOR_TOP")
            GameTooltip:SetText(bar._adName, 1, 1, 1)
            if bar._adLocked then
                GameTooltip:AddLine("Locked: it stays where it is. Unlock it beside its eye in the list.",
                    0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end
    end)
    bar:SetScript("OnLeave", function()
        local c = bar._adEditing and EDIT_YELLOW or GROUP_TEXT
        bar.fs:SetTextColor(c[1], c[2], c[3])
        if GameTooltip:IsOwned(bar) then GameTooltip:Hide() end
    end)
    bar:SetScript("OnDragStart", function()
        if gf:IsMovable() then
            gf._adMoving = true
            gf:StartMoving()
        end
    end)
    bar:SetScript("OnDragStop", function()
        -- a drag that never started (a locked group) saves nothing
        if not gf._adMoving then return end
        gf._adMoving = nil
        gf:StopMovingOrSizing()
        local grec = Store.Get(gf._adRecId)
        if grec and Store.Resolve(grec, "anchor", "anchorEnabled") == true
            and SaveAnchoredOffsets(gf, grec) then
            return
        end
        SaveRelativePosition(gf, grec)
    end)
    bar:SetScript("OnClick", function()
        local r = Store.Get(gf._adRecId)
        if r and NS.Options and NS.Options.Select then
            NS.Options.Select("group", r.id)
        end
    end)
    ch.bar = bar
    gf._adChrome = ch
    return ch
end

-- Bars: the engine creates, sizes, places and drags the holder, and
-- NS.Bars.EnsureBar(rec, f) owns everything inside it, alpha included (forced
-- visible in edit mode). The bars runtime loads first; the guard in PlaceBar
-- only covers a missing file.

local BAR_CYAN = { 0.247, 0.788, 0.949 }

-- A bar holder's size, the one path for everything sized from it: scale
-- multiplies width and height rather than calling SetScale, one unit is the
-- floor (a one-pixel line is a legal bar). With the holder, each axis an
-- anchor's Match width / height gave (Core\AD_Anchor.lua keeps it on the frame)
-- replaces the setting, so the bar glows draw around the matched rect.
function Engine.BarSize(rec, f)
    local w = Store.Resolve(rec, "size", "width") or 220
    local h = Store.Resolve(rec, "size", "height") or 16
    local sc = Store.Resolve(rec, "size", "scale") or 1
    w, h = Snap(math.max(1, w * sc)), Snap(math.max(1, h * sc))
    if f then return f._adMatchW or w, f._adMatchH or h end
    return w, h
end

-- A match on the holder changed (gained, followed a resized target, or lost):
-- it takes that size, and the glows, drawn from numbers, follow now rather than
-- on a size callback that may not come.
local function BarMatched(f)
    local rec = Store.Get(f._adRecId)
    if not rec then return end
    f:SetSize(Engine.BarSize(rec, f))
    local G = NS.Bars and NS.Bars.Glow
    if G and G.Sized then G.Sized(rec.id) end
end

local function EnsureBarFrame(rec)
    local f = barFrames[rec.id]
    if not f then
        f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f._adOnMatch = BarMatched
        barFrames[rec.id] = f
    end
    return f
end

local function EnsureBarChrome(f)
    if f._adBarChrome then return f._adBarChrome end
    local ch = {}
    local chip = CreateFrame("Button", nil, f, "BackdropTemplate")
    -- Inside the bar's top-right corner: above the bar it covered whatever
    -- was placed there.
    chip:SetSize(Snap(24), Snap(10))
    chip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Snap(2), -Snap(2))
    chip:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    chip:SetBackdropColor(0.05, 0.10, 0.13, 0.95)
    chip:SetBackdropBorderColor(BAR_CYAN[1], BAR_CYAN[2], BAR_CYAN[3], 0.9)
    chip.fs = chip:CreateFontString(nil, "OVERLAY")
    chip.fs:SetFont(STANDARD_TEXT_FONT, 7, "OUTLINE")
    chip.fs:SetPoint("CENTER", 0, 0)
    chip.fs:SetText("EDIT")
    chip.fs:SetTextColor(BAR_CYAN[1], BAR_CYAN[2], BAR_CYAN[3])
    chip:SetScript("OnClick", function()
        local r = Store.Get(f._adRecId)
        if r and NS.Options and NS.Options.Select then
            NS.Options.Select("bar", r.id)
        end
    end)
    ch.chip = chip
    f._adBarChrome = ch
    return ch
end

-- Widened for the longer word; it grows left from the corner it is pinned to.
local function PaintBarChip(chip, on)
    if (chip._adEditing or false) == on then return end
    chip._adEditing = on
    local c = on and EDIT_YELLOW or BAR_CYAN
    chip:SetSize(Snap(on and 36 or 24), Snap(10))
    chip:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
    chip.fs:SetText(on and "EDITING" or "EDIT")
    chip.fs:SetTextColor(c[1], c[2], c[3])
end

local function WireBarDrag(f)
    if f._adBarDragHooked then return end
    f._adBarDragHooked = true
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        -- Pinned to the target's nameplate: the offset sliders place it, since
        -- its rect can be secret and a drag reads it.
        if self._adPlatePin then return end
        if self:IsMovable() and self:IsMouseEnabled() then
            self._adMoving = true
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        -- a drag that never started (a locked bar, a nameplate pin) saves nothing
        if not self._adMoving then return end
        self._adMoving = nil
        self:StopMovingOrSizing()
        if self._adPlatePin then return end
        local rec = Store.Get(self._adRecId)
        if rec and NS.Anchor and NS.Anchor.IsEnabled(rec)
            and NS.Anchor.SaveOffsets(rec, self) then
            NS.Anchor.Apply(rec, self)
            return
        end
        SaveRelativePosition(self, rec)
    end)
end

local function PlaceBar(rec, container)
    local f = EnsureBarFrame(rec)
    f._adRecId = rec.id
    f:SetParent(container)
    f:SetFrameStrata(EditStrata(Store.Resolve(rec, "frame", "strata")))
    f:SetFrameLevel(Store.Resolve(rec, "frame", "level") or 10)
    -- Its own size, which the free spot below is snapped for; the anchor
    -- post-pass gives a match back in this same rebuild. The glows draw at the
    -- kept match meanwhile, so an unchanged match never redraws them.
    f:SetSize(Engine.BarSize(rec))
    -- A kind with no place on screen (a wheel opens at the cursor): its
    -- runtime still gets the record, the holder stays hidden and anchors nothing.
    local KH = NS.Bars and NS.Bars.KINDS and NS.Bars.KINDS[rec.barKind]
    if KH and KH.noHolder then
        if NS.Anchor then NS.Anchor.Unregister(rec.id) end
        f:EnableMouse(false)
        f:Hide()
        NS.Bars.EnsureBar(rec, f)
        return
    end
    -- Place it free now and register it as an anchor source; the post-pass
    -- re-places it once every frame exists, so a bar can target a group,
    -- another bar, a layout or a named frame regardless of build order.
    if NS.Anchor then NS.Anchor.Register(rec, f) end
    SnapPlacement(f, container, rec.pos.x or 0, rec.pos.y or 0)
    WireBarDrag(f)
    -- An anchored bar stays draggable: the drag edits its offsets, so it never
    -- detaches from its target.
    f:SetMovable(CanMove(rec))
    f:EnableMouse(editMode)
    local ch = EnsureBarChrome(f)
    -- Settings "Edit buttons on screen" can keep the bars' chips away; the
    -- harness's stand-in factory has no reader, so it counts as on.
    ch.chip:SetShown(editMode and (Factory.EditChipsOn == nil or Factory.EditChipsOn("bar")))
    if editMode then
        ch.chip:SetFrameStrata(CHROME_STRATA)
        ch.chip:SetFrameLevel(150)   -- under the group handle's 200
    else
        ch.chip:SetFrameStrata(f:GetFrameStrata())
    end
    if NS.Bars and NS.Bars.EnsureBar then
        NS.Bars.EnsureBar(rec, f)
        f:Show()
    else
        f:Hide()
    end
end

local function ReleaseBar(id)
    if NS.Anchor then NS.Anchor.Unregister(id) end
    if NS.Bars and NS.Bars.Release then NS.Bars.Release(id) end
    local f = barFrames[id]
    if f then f:Hide() end
end

-- Icon drag and drop: into, out of and between groups

-- The group under the dragged icon's center; a group ignores icons it does not
-- take (Store.GroupTakes).
local function FindDropGroup(cx, cy, iconId)
    local rec = Store.Get(iconId)
    for gid, gf in pairs(groupFrames) do
        local grec = Store.Get(gid)
        -- a locked group takes no new icon from the screen
        if grec and gf:IsShown() and not Store.Locked(grec)
            and not (rec and not Store.GroupTakes(grec, rec.kind)) then
            local l, r, t, b = gf:GetLeft(), gf:GetRight(), gf:GetTop(), gf:GetBottom()
            if l and cx >= l - 16 and cx <= r + 16 and cy >= b - 16 and cy <= t + 16 then
                return grec, gf
            end
        end
    end
end

-- Drop indicators: orange square = swap with the occupant, green square =
-- empty cell, green (same group) or cyan (other group) line = insert between
-- slots. TOOLTIP strata, so they draw over everything.
local DropSquare = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
DropSquare:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
DropSquare:SetFrameStrata("TOOLTIP")
DropSquare:SetFrameLevel(9999)
DropSquare:Hide()

local InsertLine = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
InsertLine:SetBackdrop({ bgFile = WHITE })
InsertLine:SetFrameStrata("TOOLTIP")
InsertLine:SetFrameLevel(9999)
InsertLine:Hide()

local function HideDropIndicators()
    DropSquare:Hide()
    InsertLine:Hide()
end

-- A grid group's slot, steps, spacings and padding, each rounded to whole
-- pixels on its own, so every step is the same pixel count at any scale.
-- Placement, the drop mapping and the grow arrows all read these.
local function GridMetrics(group)
    local R = function(field) return Store.Resolve(group, "arrangement", field) end
    -- iconSize is a scale where 36 = 1, applied to the base width and height;
    -- each term rounds to an integer first.
    local scale = math.floor((R("iconSize") or 36) + 0.5) / 36
    local slotW = Snap(math.floor((R("iconWidth") or 36) * scale + 0.5))
    local slotH = Snap(math.floor((R("iconHeight") or 36) * scale + 0.5))
    local spBase = R("spacing") or 2
    local sep = R("separateSpacing") == true
    local spacingX = Snap(sep and (R("spacingX") or spBase) or spBase)
    local spacingY = Snap(sep and (R("spacingY") or spBase) or spBase)
    return slotW, slotH, slotW + spacingX, slotH + spacingY, spacingX, spacingY,
        Snap(R("containerPadding") or 0)
end

-- Oversized members (Use group scale off) widen their column and heighten
-- their row; later columns and rows shift so spacing stays between edges, and
-- the container grows to fit. cells = { [row * cols + col] = rec } in logical
-- cells; results are keyed by visual column and row. Placement and the drop
-- mapping share this, so a drop target always matches a drawn cell.
local function GroupCascade(cells, cols, needRows, slotW, slotH, growthH, growthV)
    local colW, rowH = {}, {}
    for key, rec in pairs(cells) do
        local row = math.floor(key / cols)
        local col = key % cols
        if growthH == "LEFT" then col = (cols - 1) - col end
        if growthV == "UP" then row = (needRows - 1) - row end
        local mw, mh = MemberSize(rec, slotW, slotH)
        mw, mh = Snap(mw), Snap(mh)
        if mw > (colW[col] or slotW) then colW[col] = mw end
        if mh > (rowH[row] or slotH) then rowH[row] = mh end
    end
    local cas = { colW = colW, rowH = rowH, colCum = {}, rowCum = {} }
    local cum = 0
    for c = 0, cols - 1 do
        cas.colCum[c] = cum
        if c < cols - 1 then
            local extra = ((colW[c] or slotW) + (colW[c + 1] or slotW)) / 2 - slotW
            if extra > 0 then cum = cum + Snap(extra) end
        end
    end
    cas.totalExtraW = cum
    cum = 0
    for r = 0, needRows - 1 do
        cas.rowCum[r] = cum
        if r < needRows - 1 then
            local extra = ((rowH[r] or slotH) + (rowH[r + 1] or slotH)) / 2 - slotH
            if extra > 0 then cum = cum + Snap(extra) end
        end
    end
    cas.totalExtraH = cum
    cas.leftOver = Snap(math.max(0, ((colW[0] or slotW) - slotW) / 2))
    cas.rightOver = Snap(math.max(0, ((colW[cols - 1] or slotW) - slotW) / 2))
    cas.topOver = Snap(math.max(0, ((rowH[0] or slotH) - slotH) / 2))
    cas.bottomOver = Snap(math.max(0, ((rowH[needRows - 1] or slotH) - slotH) / 2))
    return cas
end

-- A visual cell's slot corner from the container's TOPLEFT (x right, y down):
-- whole pixels, as every term is.
local function CascadeCorner(cas, col, row, stepX, stepY, pad)
    return pad + cas.leftOver + col * stepX + (cas.colCum[col] or 0),
        pad + cas.topOver + row * stepY + (cas.rowCum[row] or 0)
end

-- A visual cell's centre from the container's TOPLEFT (x right, y down), and
-- the cell's own width and height.
local function CascadeCell(cas, col, row, slotW, slotH, stepX, stepY, pad)
    local x, y = CascadeCorner(cas, col, row, stepX, stepY, pad)
    return x + slotW / 2, y + slotH / 2, cas.colW[col] or slotW, cas.rowH[row] or slotH
end

local function GroupDropInfo(grec, gf, cx, cy, skipId)
    if not (grec and gf) then return nil end
    local R = function(field) return Store.Resolve(grec, "arrangement", field) end
    local slotW, slotH, stepX, stepY, _, _, pad = GridMetrics(grec)
    local gl, gt = gf:GetLeft(), gf:GetTop()
    if not (gl and gt and stepX > 0 and stepY > 0) then return nil end

    local cols = math.max(1, R("cols") or 6)
    local rows = math.max(1, R("rows") or 1)

    -- Occupancy without the dragged icon: cell -> member
    local byCell = {}
    local maxRow = rows - 1
    for _, r in ipairs(Store.IconsOf(grec)) do
        if r.id ~= skipId and r.gpos and ShowsRec(r) then
            byCell[(r.gpos.row or 0) * cols + (r.gpos.col or 0)] = r
            if (r.gpos.row or 0) > maxRow then maxRow = r.gpos.row end
        end
    end
    local needRows = math.max(rows, maxRow + 1)
    -- Lock Grid Size: drops may not target cells beyond the configured grid
    if R("lockGridSize") == true then needRows = rows end

    -- The drawn cells: every shown member, the dragged one included, since
    -- its old cell is still drawn.
    local growthH = R("growthH") or "RIGHT"
    local growthV = R("growthV") or "DOWN"
    local allCells = {}
    for _, r in ipairs(Store.IconsOf(grec)) do
        if r.gpos and ShowsRec(r) and (r.gpos.col or 0) < cols then
            allCells[(r.gpos.row or 0) * cols + (r.gpos.col or 0)] = r
        end
    end
    local cas = GroupCascade(allCells, cols, needRows, slotW, slotH, growthH, growthV)

    -- Visual cell under the cursor: the nearest drawn cell centre.
    local relX = cx - gl
    local relY = gt - cy
    local col, row, bestX, bestY = 0, 0, math.huge, math.huge
    for c = 0, cols - 1 do
        local ccx = CascadeCell(cas, c, 0, slotW, slotH, stepX, stepY, pad)
        local d = math.abs(relX - ccx)
        if d < bestX then bestX, col = d, c end
    end
    for r = 0, needRows - 1 do
        local _, ccy = CascadeCell(cas, 0, r, slotW, slotH, stepX, stepY, pad)
        local d = math.abs(relY - ccy)
        if d < bestY then bestY, row = d, r end
    end

    -- Visual cell to logical cell (undo the growth flips)
    local lCol, lRow = col, row
    if growthH == "LEFT" then lCol = cols - 1 - lCol end
    if growthV == "UP" then lRow = needRows - 1 - lRow end

    local ccx, ccy, cw, ch = CascadeCell(cas, col, row, slotW, slotH, stepX, stepY, pad)
    local cell = { gf = gf, col = col, row = row, slotW = slotW, slotH = slotH,
        stepX = stepX, stepY = stepY, pad = pad,
        x = ccx, y = ccy, w = cw, h = ch }
    local occ = byCell[lRow * cols + lCol]
    if occ then
        return { mode = "swap", row = lRow, col = lCol, occupantId = occ.id,
            frame = Factory.frames[occ.id], cell = cell }
    end
    -- Empty cell: the icon lands here and stays (no packing).
    return { mode = "empty", row = lRow, col = lCol, cell = cell }
end

local function ShowDropIndicator(info, sameGroup)
    if not info then
        HideDropIndicators()
        return
    end
    if info.mode == "empty" and info.cell then
        local cl = info.cell
        DropSquare:ClearAllPoints()
        DropSquare:SetSize(cl.w or cl.slotW, cl.h or cl.slotH)
        DropSquare:SetPoint("CENTER", cl.gf, "TOPLEFT", cl.x, -cl.y)
        DropSquare:SetBackdropColor(0, 1, 0, 0.3)
        DropSquare:SetBackdropBorderColor(0, 1, 0, 0.9)
        DropSquare:Show()
        InsertLine:Hide()
        return
    end
    if not info.frame then
        HideDropIndicators()
        return
    end
    if info.mode == "swap" then
        DropSquare:ClearAllPoints()
        DropSquare:SetPoint("TOPLEFT", info.frame, "TOPLEFT", 0, 0)
        DropSquare:SetPoint("BOTTOMRIGHT", info.frame, "BOTTOMRIGHT", 0, 0)
        DropSquare:SetBackdropColor(1, 0.5, 0, 0.3)
        DropSquare:SetBackdropBorderColor(1, 0.5, 0, 0.9)
        DropSquare:Show()
        InsertLine:Hide()
    else
        local r, g, b
        if sameGroup then r, g, b = 0, 1, 0 else r, g, b = 0, 1, 1 end
        InsertLine:ClearAllPoints()
        InsertLine:SetSize(4, (info.frame:GetHeight() or 36) + 8)
        if info.side == "left" then
            InsertLine:SetPoint("CENTER", info.frame, "LEFT", -1, 0)
        else
            InsertLine:SetPoint("CENTER", info.frame, "RIGHT", 1, 0)
        end
        InsertLine:SetBackdropColor(r, g, b, 0.9)
        InsertLine:Show()
        DropSquare:Hide()
    end
end

local dragState

local function WireIconDrag(f)
    if f._adIconDragHooked then return end
    f._adIconDragHooked = true
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not (self:IsMovable() and self:IsMouseEnabled()) then return end
        -- A hover tooltip must not ride along with the dragged icon.
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        self:StartMoving()
        dragState = { id = self._adRecId }
        self._adOldStrata = self:GetFrameStrata()
        self:SetFrameStrata("TOOLTIP")
        -- Live drop-target highlight while dragging.
        self:SetScript("OnUpdate", function(s)
            local cx, cy = s:GetCenter()
            if not (cx and dragState) then return end
            local grec, gf = FindDropGroup(cx, cy, dragState.id)
            if dragState.lastGF and dragState.lastGF ~= gf and dragState.lastGF._adChrome then
                dragState.lastGF._adChrome.border:SetBackdropBorderColor(
                    GROUP_GREEN[1], GROUP_GREEN[2], GROUP_GREEN[3], 0.9)
            end
            if gf and gf._adChrome then
                gf._adChrome.border:SetBackdropBorderColor(1, 0.95, 0.3, 1)
            end
            dragState.lastGF, dragState.grec = gf, grec
            if grec then
                local drec = Store.Get(dragState.id)
                dragState.info = GroupDropInfo(grec, gf, cx, cy, dragState.id)
                ShowDropIndicator(dragState.info, drec and drec.groupId == grec.id)
            else
                dragState.info = nil
                HideDropIndicators()
            end
        end)
    end)
    f:SetScript("OnDragStop", function(self)
        -- a drag that never started (a locked icon) leaves it where it is
        if not (dragState and dragState.id == self._adRecId) then return end
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        HideDropIndicators()
        if self._adOldStrata then self:SetFrameStrata(self._adOldStrata) end
        local st = dragState
        dragState = nil
        if st and st.lastGF and st.lastGF._adChrome then
            st.lastGF._adChrome.border:SetBackdropBorderColor(
                GROUP_GREEN[1], GROUP_GREEN[2], GROUP_GREEN[3], 0.9)
        end
        local rec = Store.Get(self._adRecId)
        if not rec then Engine.QueueRebuild() return end
        local cx, cy = self:GetCenter()
        local grec = st and st.grec
        -- A group takes over the icon's placement, so it lets go of its anchor
        -- rather than keep one to snap back to once it leaves the group.
        if grec and cx and NS.Anchor and NS.Anchor.IsEnabled(rec) then
            NS.Anchor.PickSet(rec, "none")
        end
        if grec and cx then
            -- Onto an occupied cell of the same group: swap. Otherwise the icon
            -- moves to that cell. An illegal drop snaps back.
            local info = (st and st.info) or GroupDropInfo(grec, groupFrames[grec.id], cx, cy, rec.id)
            local ok
            if not info then
                Engine.QueueRebuild()
                return
            end
            if info.mode == "swap" and info.occupantId then
                if rec.groupId == grec.id then
                    ok = Store.SwapCells(grec.id, rec.id, info.occupantId)
                else
                    -- The occupant moves to the group's first free cell.
                    local occ = Store.Get(info.occupantId)
                    if occ then occ.gpos = nil end
                    ok = Store.MoveIcon(rec.id, grec.id, nil, nil,
                        { row = info.row, col = info.col })
                end
            else
                ok = Store.MoveIcon(rec.id, grec.id, nil, nil,
                    { row = info.row, col = info.col })
            end
            if not ok then
                Engine.QueueRebuild()
            end
        elseif cx then
            -- An anchored free icon keeps its anchor: the drag edits its offsets.
            if NS.Anchor and NS.Anchor.IsEnabled(rec)
                and NS.Anchor.SaveOffsets(rec, self) then
                NS.Anchor.Apply(rec, self)
                return
            end
            -- Outside any group: a free position on the icon's own layout.
            local layoutId = rec.layoutId
            if not layoutId and rec.groupId then
                local g = Store.Get(rec.groupId)
                layoutId = g and g.layoutId
            end
            local lf = layoutId and layoutFrames[layoutId]
            -- `a and f()` keeps only the first return, so py needs a real call.
            local px, py
            if lf then px, py = lf:GetCenter() end
            if px and py then
                Store.MoveIcon(rec.id, nil, layoutId, { x = cx - px, y = cy - py })
            else
                Engine.QueueRebuild()
            end
        else
            Engine.QueueRebuild()
        end
    end)
end

-- Grow arrows round the group open in the editor: bottom adds or removes a
-- row, left and right a column (the title bar holds the top). The clicked edge
-- moves while every icon stays put on screen. They are children of the group
-- at chrome strata, so they hide with it and an anchored bar can't take the
-- click. Every grid group gets all three pairs, aura groups included.
local ARROW_SIZE, ARROW_GAP, ARROW_PAD = 14, 2, 3
local ARROW_ADD = { 0.35, 0.90, 0.35 }
local ARROW_REMOVE = { 0.95, 0.40, 0.40 }
-- x and y: which side of the pair's center line the button sits on
local ARROW_SPECS = {
    { edge = "bottom", add = false, dir = "up",    point = "TOP",   rel = "BOTTOM", x = -1, y = 0 },
    { edge = "bottom", add = true,  dir = "down",  point = "TOP",   rel = "BOTTOM", x = 1,  y = 0 },
    { edge = "left",   add = true,  dir = "left",  point = "RIGHT", rel = "LEFT",   x = 0,  y = 1 },
    { edge = "left",   add = false, dir = "right", point = "RIGHT", rel = "LEFT",   x = 0,  y = -1 },
    { edge = "right",  add = true,  dir = "right", point = "LEFT",  rel = "RIGHT",  x = 0,  y = 1 },
    { edge = "right",  add = false, dir = "left",  point = "LEFT",  rel = "RIGHT",  x = 0,  y = -1 },
}
local ARROW_TIP = {
    bottom = { [true] = "Add a row at the bottom", [false] = "Remove the bottom row" },
    left = { [true] = "Add a column on the left", [false] = "Remove the left column" },
    right = { [true] = "Add a column on the right", [false] = "Remove the right column" },
}

local function ArrowTooltip(b)
    local s = b._adSpec
    GameTooltip:SetOwner(b, "ANCHOR_CURSOR")
    GameTooltip:SetText(ARROW_TIP[s.edge][s.add], 1, 1, 1)
    if not b._adOK then
        local line = (s.edge == "bottom") and "row" or "column"
        local why
        if b._adWhy == "max" then
            why = "Groups stop at " .. (b._adCount or 20) .. " " .. line .. "s."
        elseif b._adWhy == "cap" then
            why = "This group shows up to " .. (b._adCount or 40) .. " auras already."
        elseif b._adWhy == "min" then
            why = "A group needs at least one " .. line .. "."
        elseif b._adWhy == "full" then
            why = "This group holds " .. (b._adCount or 0)
                .. " icons, and they would not fit. Move one out first."
        end
        if why then GameTooltip:AddLine(why, 1, 0.5, 0.5, true) end
    end
    GameTooltip:Show()
end

-- One grid step, with the same Snap math as PlaceGroup.
local function GroupStep(g)
    local _, _, stepX, stepY = GridMetrics(g)
    return stepX, stepY
end

-- Rows the static grid actually draws; an overfull grid grows by rows.
local function DrawnRows(g)
    local rows = math.max(1, Store.Resolve(g, "arrangement", "rows") or 1)
    local cols = math.max(1, Store.Resolve(g, "arrangement", "cols") or 6)
    local maxRow = rows - 1
    for _, r in ipairs(Store.IconsOf(g)) do
        local gp = r.gpos
        if gp and gp.row and gp.col and gp.col < cols and gp.row > maxRow
            and ShowsRec(r) then
            maxRow = gp.row
        end
    end
    return maxRow + 1
end

local function ArrowClick(gf, spec)
    local g = Store.Get(gf._adRecId)
    if not (g and Store.GridEdgeCheck(g.id, spec.edge, spec.add)) then return end
    local stepX, stepY = GroupStep(g)
    local rowsBefore = DrawnRows(g)
    local colsBefore = math.max(1, Store.Resolve(g, "arrangement", "cols") or 6)
    -- a group showing every aura on a unit sizes its own box
    local UA = Store.ShowsAll(g) and NS.DriverUnitAuras or nil
    local box = UA and UA.Plan(g)
    -- An anchored group's position belongs to its anchor.
    local free = not (NS.Anchor and NS.Anchor.ResolveTarget(g))
    if not Store.GridEdge(g.id, spec.edge, spec.add) then return end
    if free and box then
        g.pos = g.pos or {}
        local after = UA.Plan(g)
        if spec.edge == "bottom" then
            g.pos.y = (g.pos.y or 0) - (after.boxH - box.boxH) / 2
        else
            local dx = (after.boxW - box.boxW) / 2
            g.pos.x = (g.pos.x or 0) + ((spec.edge == "left") and -dx or dx)
        end
    elseif free then
        g.pos = g.pos or {}
        if spec.edge == "bottom" then
            -- The box changed at the bottom: hold the top edge.
            g.pos.y = (g.pos.y or 0) - (DrawnRows(g) - rowsBefore) * stepY / 2
        else
            -- Hold the opposite edge: left grows leftward, right rightward.
            local cols = math.max(1, Store.Resolve(g, "arrangement", "cols") or 6)
            local dx = (cols - colsBefore) * stepX / 2
            g.pos.x = (g.pos.x or 0) + ((spec.edge == "left") and -dx or dx)
        end
    end
end

local function EnsureGroupArrows(gf)
    if gf._adArrows then return gf._adArrows end
    local anchor = EnsureGroupChrome(gf).border
    local half = ARROW_SIZE / 2 + ARROW_GAP / 2
    local list = {}
    for i, spec in ipairs(ARROW_SPECS) do
        local b = CreateFrame("Button", nil, gf, "BackdropTemplate")
        b:SetSize(ARROW_SIZE, ARROW_SIZE)
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        local c = spec.add and ARROW_ADD or ARROW_REMOVE
        b._adSpec, b._adColor = spec, c
        b:SetBackdropColor(c[1] * 0.22, c[2] * 0.22, c[3] * 0.22, 0.95)
        b:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
        local ox = (spec.edge == "left" and -ARROW_PAD)
            or (spec.edge == "right" and ARROW_PAD) or spec.x * half
        local oy = (spec.edge == "bottom" and -ARROW_PAD) or spec.y * half
        b:SetPoint(spec.point, anchor, spec.rel, ox, oy)
        -- Arrows use AT.MakeChevron, never a text glyph.
        b.chev = NS.AT.MakeChevron(b)
        b.chev:SetPoint("CENTER", 0, 0)
        b.chev:SetDir(spec.dir)
        b.chev:SetColor(c)
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 1, 1)
            ArrowTooltip(self)
        end)
        b:SetScript("OnLeave", function(self)
            local cc = self._adColor
            self:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.9)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function(self) ArrowClick(gf, self._adSpec) end)
        b:Hide()
        list[i] = b
    end
    gf._adArrows = list
    return list
end

local function UpdateGroupArrows(gf, rec)
    -- a group that places itself (Engine.HandlerFor) has no grid to grow, but
    -- one showing every aura on a unit grows its Rows and Columns (off plates)
    local grows = not Engine.HandlerFor(rec)
        or (Store.ShowsAll(rec) and Store.Resolve(rec, "unitAuras", "unit") ~= "nameplate")
    -- a lock keeps the grid's size as it is too
    local want = editMode and Store.GetSetting("showLayoutArrows") ~= false
        and not Store.Locked(rec)
        and NS.Options ~= nil and NS.Options.SelectedGroupId ~= nil
        and NS.Options.SelectedGroupId() == rec.id
        and grows
    if not (want or gf._adArrows) then return end
    for _, b in ipairs(EnsureGroupArrows(gf)) do
        local s = b._adSpec
        if want then
            b._adOK, b._adWhy, b._adCount = Store.GridEdgeCheck(rec.id, s.edge, s.add)
            b:SetAlpha(b._adOK and 1 or 0.35)
            b:SetFrameStrata(CHROME_STRATA)
            b:SetFrameLevel(200)
            b:Show()
            if GameTooltip:IsOwned(b) then ArrowTooltip(b) end
        else
            b:Hide()
        end
    end
end

-- Selection changed or the setting flipped: move the arrows without a rebuild.
function Engine.RefreshArrows()
    for gid, gf in pairs(groupFrames) do
        local rec = Store.Get(gid)
        if rec and gf:IsShown() then
            UpdateGroupArrows(gf, rec)
        elseif gf._adArrows then
            for _, b in ipairs(gf._adArrows) do b:Hide() end
        end
    end
end

-- A group has no Edit chip, so its name (with names off, its grip) turns
-- yellow while the editor has it open.
local function PaintGroupTab(bar, on)
    if (bar._adEditing or false) == on then return end
    bar._adEditing = on
    local c = on and EDIT_YELLOW or GROUP_TEXT
    bar.fs:SetTextColor(c[1], c[2], c[3])
    local g = on and EDIT_YELLOW or GROUP_GREEN
    bar.grip:SetColorTexture(g[1], g[2], g[3], 0.9)
end

-- The editor's pane refresh calls this on every selection change. Every
-- rebuild does too: it builds the chips of new items, and closing the window
-- ends edit mode through one.
function Engine.RefreshEditing()
    local O = NS.Options
    local id = editMode and O and O.EditingId and O.EditingId() or nil
    for bid, bf in pairs(barFrames) do
        local ch = bf._adBarChrome
        if ch then PaintBarChip(ch.chip, bid == id) end
    end
    for gid, gf in pairs(groupFrames) do
        local ch = gf._adChrome
        if ch then PaintGroupTab(ch.bar, gid == id) end
    end
    if Factory.SetEditing then
        for iid, f in pairs(Factory.frames) do Factory.SetEditing(f, iid == id) end
    end
end

local function WireGroupEdit(gf, rec)
    gf._adRecId = rec.id
    local ch = EnsureGroupChrome(gf)
    -- Settings "Show group names" (on until switched off); off leaves a small
    -- green grip, which still drags the group.
    local named = Store.GetSetting("groupNames") ~= false
    ch.bar._adName = rec.name
    ch.bar.fs:SetText(named and rec.name or "")
    ch.bar.grip:SetShown(not named)
    if named then
        -- a width read of 0 (a first frame) falls back to a width from the name
        local tw = ch.bar.fs:GetStringWidth() or 0
        if tw <= 0 then tw = #(rec.name or "") * 4 end
        ch.bar:SetSize(math.max(36, math.ceil(tw) + 10), 12)
    else
        ch.bar:SetSize(24, 8)
    end
    ch.border:SetFrameLevel(gf:GetFrameLevel())
    -- "Background while editing" (look.editFill): the fill inside the outline
    local fill = Store.Resolve(rec, "look", "editFill")
    if type(fill) == "table" then
        ch.border:SetBackdropColor(fill[1] or 0, fill[2] or 0, fill[3] or 0, fill[4] or 1)
    end
    ch.border:SetShown(editMode)
    ch.bar:SetShown(editMode)
    -- While the panel is open the handle outranks every display, so a bar
    -- anchored on top of the group can't steal the drag.
    if editMode then
        ch.bar:SetFrameStrata(CHROME_STRATA)
        ch.bar:SetFrameLevel(200)
    else
        ch.bar:SetFrameStrata(gf:GetFrameStrata())
        ch.bar:SetFrameLevel(gf:GetFrameLevel() + 1)
    end
    -- The title bar is the drag handle; the container never takes the mouse.
    gf:SetMovable(CanMove(rec))
    gf:EnableMouse(false)
    ch.bar._adLocked = Store.Locked(rec)
    UpdateGroupArrows(gf, rec)
end

-- Group kinds that are not grids place themselves: the Reminder group
-- (Drivers\AD_DriverReminders.lua) is its pulse window. The engine keeps the
-- group's frame, spot, anchor, chrome and load; the handler owns what is
-- inside: place(group, gf, editMode) sizes the frame and fills it on every
-- rebuild, release(group) stops it while the group is not drawn.
Engine.GROUP_KINDS = {}
function Engine.RegisterGroupKind(kind, handler)
    Engine.GROUP_KINDS[kind] = handler
end

-- A grid group a handler takes over whole while claims(group) is true (an aura
-- group showing every aura on a unit, Drivers\AD_DriverUnitAuras.lua). Asked on
-- every rebuild, so a group moves between the grid and the handler with its
-- setting; the same place / release contract as a group kind.
Engine.GROUP_CLAIMS = {}
function Engine.RegisterGroupClaim(handler)
    Engine.GROUP_CLAIMS[#Engine.GROUP_CLAIMS + 1] = handler
end

-- The handler that places this group itself, or nil for the grid.
function Engine.HandlerFor(group)
    local gk = Engine.GROUP_KINDS[group.groupKind]
    if gk then return gk end
    for _, h in ipairs(Engine.GROUP_CLAIMS) do
        if h.claims(group) then return h end
    end
end

-- Drawn by this rebuild: loaded, or previewed while editing (ShowsRec).
Engine.Shows = ShowsRec

-- An icon a group kind places itself (the Reminder group's aura reminders):
-- a grid member's wiring at the handler's spot (a w x h cell whose top-left
-- corner is left, top from parent's top-left, y down, in whole pixels), never
-- dragged, as the handler owns the layout. Returns the frame, or nil
-- (released) when it is not drawn here.
function Engine.PlaceKindIcon(rec, parent, left, top, w, h)
    if not ShowsRec(rec) then
        Factory.Release(rec.id)
        NS.DriverCooldown.Detach(rec.id)
        return nil
    end
    local f = Factory.Ensure(rec)
    f:SetParent(parent)
    f:ClearAllPoints()
    dynAnims[f] = nil
    f._adDynParent = nil
    PlaceCell(f, rec, parent, left, top, w, h)
    Factory.ApplyStyle(f, rec)
    NS.DriverCooldown.Attach(rec, f)
    f:SetMovable(false)
    Factory.ApplyMouse(f, editMode, rec)
    Factory.SetEditMode(f, rec, editMode)
    GhostTag(f, rec)
    ShowIcon(f, rec)
    return f
end

-- The container's own look (Arrangement > Container), off by default; the
-- kinds that place themselves have it too.
local function ContainerLook(group, container)
    local showBorder = Store.Resolve(group, "look", "showBorder")
    local showBg = Store.Resolve(group, "look", "showBackground")
    if showBorder or showBg then
        container:SetBackdrop({
            bgFile = showBg and WHITE or nil,
            edgeFile = showBorder and WHITE or nil,
            edgeSize = 1,
        })
        if showBg then
            local c = Store.Resolve(group, "look", "bgColor") or { 0, 0, 0, 0.6 }
            container:SetBackdropColor(c[1], c[2], c[3], c[4] or 0.6)
        end
        if showBorder then
            local c = Store.Resolve(group, "look", "borderColor") or { 0.11, 0.16, 0.25, 1 }
            container:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
        end
    else
        container:SetBackdrop(nil)
    end
end

-- Grid placement: cols x rows of snapped slots, centered on the container.
local function PlaceGroup(group, container, flowMode)
    local icons = Store.IconsOf(group)
    -- In engine-flow mode the AuraContainer rows render the members, so shown
    -- stays empty and the release loop below frees every holder.
    local shown = {}
    if not flowMode then
        for _, rec in ipairs(icons) do
            if ShowsRec(rec) then shown[#shown + 1] = rec end
        end
    end

    local R = function(field) return Store.Resolve(group, "arrangement", field) end
    local slotW, slotH, stepX, stepY, spacingX, spacingY, pad = GridMetrics(group)
    local cols = math.max(1, R("cols") or 6)
    local rows = math.max(1, R("rows") or 1)

    -- Static grid: each member keeps a cell (rec.gpos), holes are legal and
    -- nothing packs. A member without one (new, collided, imported) takes the
    -- first free cell in member order. Overfull grids grow by rows.
    local occupied = {}
    local pending = {}
    local maxRow = rows - 1
    for _, rec in ipairs(shown) do
        local gp = rec.gpos
        local key = gp and gp.row and gp.col and gp.col < cols
            and (gp.row * cols + gp.col) or nil
        if key and not occupied[key] then
            occupied[key] = rec
            if gp.row > maxRow then maxRow = gp.row end
        else
            pending[#pending + 1] = rec
        end
    end
    for _, rec in ipairs(pending) do
        local k = 0
        while occupied[k] do k = k + 1 end
        occupied[k] = rec
        rec.gpos = { row = math.floor(k / cols), col = k % cols }
        if rec.gpos.row > maxRow then maxRow = rec.gpos.row end
    end
    local needRows = math.max(rows, maxRow + 1)

    local growthH = R("growthH") or "RIGHT"
    local growthV = R("growthV") or "DOWN"

    local cas = GroupCascade(occupied, cols, needRows, slotW, slotH, growthH, growthV)

    -- Closed panel: DynApply places dynamic cooldown groups. Edit sessions draw
    -- the static grid for drag and drop; dynamic aura groups use flowMode.
    local dynamic = (not flowMode) and (not editMode) and group.groupKind ~= "aura"
        and R("dynamicLayout") == true

    local contentW = Snap(cols * slotW + (cols - 1) * spacingX + pad * 2
        + cas.totalExtraW + cas.leftOver + cas.rightOver)
    local contentH = Snap(needRows * slotH + (needRows - 1) * spacingY + pad * 2
        + cas.totalExtraH + cas.topOver + cas.bottomOver)
    container:SetSize(math.max(contentW, Snap(4)), math.max(contentH, Snap(4)))
    ContainerLook(group, container)
    PlaceGroupRoot(group, container, 0, 0)

    if dynamic then
        -- Every member, dropped-out ones too, is sized at its static cell,
        -- styled and attached before DynApply places anything: ApplyStyle
        -- scales texts off the frame's height, the drop-out rule reads the
        -- state the drivers just fed, and state edges bring dropped icons back.
        local members = {}
        for key, rec in pairs(occupied) do
            local row = math.floor(key / cols)
            local col = key % cols
            if growthH == "LEFT" then col = (cols - 1) - col end
            if growthV == "UP" then row = (needRows - 1) - row end
            local f = Factory.Ensure(rec)
            f:SetParent(container)
            f:ClearAllPoints()
            local cl, ct = CascadeCorner(cas, col, row, stepX, stepY, pad)
            PlaceCell(f, rec, container, cl, ct, slotW, slotH)
            Factory.ApplyStyle(f, rec)
            NS.DriverCooldown.Attach(rec, f)
            WireIconDrag(f)
            f:SetMovable(false)
            Factory.ApplyMouse(f, false, rec)
            Factory.SetEditMode(f, rec, false)
            members[#members + 1] = { rec = rec, f = f, key = key }
        end
        table.sort(members, function(a, b) return a.key < b.key end)
        local ctx = { members = members, cols = cols, needRows = needRows,
            slotW = slotW, slotH = slotH, stepX = stepX, stepY = stepY,
            spacingX = spacingX, spacingY = spacingY, pad = pad,
            contentW = contentW, contentH = contentH,
            growthH = growthH, growthV = growthV,
            -- Oversized-member cascade, kept on ctx; DynApply steps uniformly.
            cascade = cas }
        dynCtx[group.id] = ctx
        -- The full grid size was just set above; DynApply may shrink it.
        container._adDynW, container._adDynH = nil, nil
        DynApply(group, container, ctx)
    else
    dynCtx[group.id] = nil
    container._adDynW, container._adDynH = nil, nil
    for key, rec in pairs(occupied) do
        local row = math.floor(key / cols)
        local col = key % cols
        if growthH == "LEFT" then col = (cols - 1) - col end
        if growthV == "UP" then row = (needRows - 1) - row end
        local cl, ct = CascadeCorner(cas, col, row, stepX, stepY, pad)
        local f = Factory.Ensure(rec)
        f:SetParent(container)
        f:ClearAllPoints()
        -- Stop any glide left from play mode, or it would walk the icon off
        -- its static cell after the panel opened.
        dynAnims[f] = nil
        f._adDynParent = nil
        PlaceCell(f, rec, container, cl, ct, slotW, slotH)
        Factory.ApplyStyle(f, rec)
        NS.DriverCooldown.Attach(rec, f)
        -- In edit mode grid icons drag into other groups, within this one, or
        -- out to a free position; otherwise they are click-through.
        WireIconDrag(f)
        f:SetMovable(CanMove(rec))
        Factory.ApplyMouse(f, editMode, rec)
        Factory.SetEditMode(f, rec, editMode)
        GhostTag(f, rec)
        ShowIcon(f, rec)
    end
    end

    for _, rec in ipairs(icons) do
        local isShown = false
        for _, s in ipairs(shown) do
            if s == rec then isShown = true break end
        end
        if not isShown then
            Factory.Release(rec.id)
            NS.DriverCooldown.Detach(rec.id)
        end
    end
end


-- Conditions subjects, registered below every local they read. Layouts and
-- groups take the alpha on their container, which children inherit (aura
-- drivers copy it to their UIParent engines on AD_VISIBILITY). Icons use
-- Factory.ApplyFrameAlpha and redo the mouse only when the blocked answer flips.
if NS.Conditions then
    local C = NS.Conditions
    C.RegisterSubject("layout", {
        each = function(fn)
            for id, lf in pairs(layoutFrames) do
                if lf:IsShown() then fn(id) end
            end
        end,
        apply = function(rec)
            local lf = layoutFrames[rec.id]
            if lf then lf:SetAlpha(C.AlphaFor(rec)) end
        end,
    })
    C.RegisterSubject("group", {
        -- A handler that hides the frame it places still draws the group
        -- (an aura group on enemy nameplates), so its conditions run too.
        each = function(fn)
            for id, gf in pairs(groupFrames) do
                if gf:IsShown() or gf._adPlacer then fn(id) end
            end
        end,
        apply = function(rec)
            local gf = groupFrames[rec.id]
            if gf then gf:SetAlpha(C.AlphaFor(rec)) end
        end,
    })
    C.RegisterSubject("icon", {
        -- Shown icons plus a dynamic group's dropped-out members: those stay
        -- attached while hidden, and an inert one must keep being asked or it
        -- could never come back.
        each = function(fn)
            local seen = {}
            for id, f in pairs(Factory.frames) do
                if f:IsShown() then
                    seen[id] = true
                    fn(id)
                end
            end
            for gid, ctx in pairs(dynCtx) do
                local gf = groupFrames[gid]
                if gf and gf:IsShown() then
                    for _, m in ipairs(ctx.members) do
                        local id = m.rec.id
                        if not seen[id] and Factory.frames[id] == m.f then
                            seen[id] = true
                            fn(id)
                        end
                    end
                end
            end
        end,
        apply = function(rec)
            local f = Factory.frames[rec.id]
            if not f then return end
            Factory.ApplyFrameAlpha(f, rec)
            if (f._adCondBlocked == true) ~= C.MouseBlocked(rec) then
                Factory.ApplyMouse(f, editMode, rec)
            end
        end,
    })
end

function Engine.Rebuild()
    -- One fresh world read for the whole rebuild: placement asks the
    -- conditions (dynamic drop-outs) before their pass runs at the end.
    if NS.Conditions then NS.Conditions.Refresh() end
    local liveLayouts = {}
    for _, layout in ipairs(Store.Layouts()) do
        local container = EnsureLayoutFrame(layout)
        liveLayouts[layout.id] = true
        if ShowsRec(layout) then
            container:ClearAllPoints()
            container:SetPoint("CENTER", UIParent, "CENTER", layout.pos.x or 0, layout.pos.y or 0)
            container:Show()
            container.dragLabel:SetText(Store.LockedSelf(layout) and (layout.name .. "  (locked)") or layout.name)
            container.drag:SetShown(moveMode)
            GhostTag(container, layout, 1)

            local groups, freeIcons, bars = Store.ChildrenOf(layout)
            local liveGroups = {}
            for _, group in ipairs(groups) do
                local gf = EnsureGroupFrame(group)
                liveGroups[group.id] = true
                if ShowsRec(group) then
                    gf:SetParent(container)
                    gf:SetFrameStrata(EditStrata(Store.Resolve(group, "frame", "strata")))
                    gf:SetFrameLevel(Store.Resolve(group, "frame", "level") or 1)
                    gf:ClearAllPoints()
                    gf:SetPoint("CENTER", container, "CENTER", group.pos.x or 0, group.pos.y or 0)
                    -- The post-pass re-places it if it is anchored.
                    if NS.Anchor then NS.Anchor.Register(group, gf) end
                    gf:Show()
                    local gk = Engine.HandlerFor(group)
                    -- a group a handler lets go of (an aura group back on its
                    -- icons) is released by it before the grid draws
                    local was = gf._adPlacer
                    if was and was ~= gk and was.release then was.release(group) end
                    gf._adPlacer = gk
                    if gk then
                        -- a claimed grid group keeps its icons, undrawn
                        if was ~= gk then
                            for _, rec in ipairs(Store.IconsOf(group)) do
                                Factory.Release(rec.id)
                                NS.DriverCooldown.Detach(rec.id)
                            end
                        end
                        gk.place(group, gf, editMode)
                        ContainerLook(group, gf)
                        -- the handler sized it: now the spot, on a pixel
                        PlaceGroupRoot(group, gf, 0, 0)
                    else
                        -- Panel closed and a dynamic aura group: engine-flow
                        -- mode. Holders release and the AuraContainer rows
                        -- show only the auras that are up. With Dynamic off
                        -- the static grid stays in play too, each member
                        -- keeping its cell and missing look.
                        local flowMode = group.groupKind == "aura" and not editMode
                            and NS.DriverAuraGroups ~= nil
                            and NS.DriverAuraGroups.IsAvailable()
                            and Store.Resolve(group, "arrangement", "dynamicLayout") == true
                        PlaceGroup(group, gf, flowMode)
                    end
                    WireGroupEdit(gf, group)
                    GhostTag(gf, group, 4)
                else
                    gf:Hide()
                    local gk = gf._adPlacer or Engine.HandlerFor(group)
                    gf._adPlacer = nil
                    if gk and gk.release then gk.release(group) end
                    for _, rec in ipairs(Store.IconsOf(group)) do
                        Factory.Release(rec.id)
                        NS.DriverCooldown.Detach(rec.id)
                    end
                end
            end
            for gid, gf in pairs(groupFrames) do
                local grec = Store.Get(gid)
                if grec and grec.layoutId == layout.id and not liveGroups[gid] then
                    gf:Hide()
                end
            end

            for _, rec in ipairs(freeIcons) do
                if ShowsRec(rec) then
                    local f = Factory.Ensure(rec)
                    f:SetParent(container)
                    f:ClearAllPoints()
                    ApplyIconPosition(f, rec, container,
                        rec.pos.x or 0, rec.pos.y or 0, 36, 36)
                    -- The post-pass re-places it if it is anchored.
                    if NS.Anchor then NS.Anchor.Register(rec, f) end
                    Factory.ApplyStyle(f, rec)
                    NS.DriverCooldown.Attach(rec, f)
                    WireIconDrag(f)
                    f:SetMovable(CanMove(rec))
                    Factory.ApplyMouse(f, editMode, rec)
                    Factory.SetEditMode(f, rec, editMode)
                    GhostTag(f, rec)
                    ShowIcon(f, rec)
                else
                    if NS.Anchor then NS.Anchor.Unregister(rec.id) end
                    Factory.Release(rec.id)
                    NS.DriverCooldown.Detach(rec.id)
                end
            end

            -- Bars place after groups so group anchoring reads live frames.
            for _, rec in ipairs(bars) do
                if ShowsRec(rec) then
                    PlaceBar(rec, container)
                    local bf = barFrames[rec.id]
                    if bf then GhostTag(bf, rec) end
                else
                    ReleaseBar(rec.id)
                end
            end
        else
            container:Hide()
            local groups, freeIcons, bars = Store.ChildrenOf(layout)
            for _, group in ipairs(groups) do
                local gf = groupFrames[group.id]
                local gk = (gf and gf._adPlacer) or Engine.HandlerFor(group)
                if gf then gf._adPlacer = nil end
                if gk and gk.release then gk.release(group) end
                for _, rec in ipairs(Store.IconsOf(group)) do
                    Factory.Release(rec.id)
                    NS.DriverCooldown.Detach(rec.id)
                end
            end
            for _, rec in ipairs(freeIcons) do
                if NS.Anchor then NS.Anchor.Unregister(rec.id) end
                Factory.Release(rec.id)
                NS.DriverCooldown.Detach(rec.id)
            end
            for _, rec in ipairs(bars) do
                ReleaseBar(rec.id)
            end
        end
    end
    -- Orphan sweep for frames whose records are gone. It runs even when no
    -- layouts remain, or deleting the last layout strands its child frames.
    for lid, f in pairs(layoutFrames) do
        if not Store.Get(lid) then f:Hide() end
    end
    for gid, gf in pairs(groupFrames) do
        if not Store.Get(gid) then gf:Hide() end
    end
    for bid in pairs(barFrames) do
        if not Store.Get(bid) then ReleaseBar(bid) end
    end
    for iconId in pairs(Factory.frames) do
        if not Store.Get(iconId) then
            if NS.Anchor then NS.Anchor.Unregister(iconId) end
            Factory.Release(iconId)
            NS.DriverCooldown.Detach(iconId)
        end
    end
    -- The last word: whichever path drew it, nothing that does not load here
    -- (itself, its group or its layout) stays on screen. The release only
    -- touches our frames and parks the aura slots, so it holds in combat too.
    for iconId, f in pairs(Factory.frames) do
        local rec = f:IsShown() and Store.Get(iconId)
        if rec and not DrawnHere(rec) then
            if NS.Anchor then NS.Anchor.Unregister(iconId) end
            Factory.Release(iconId)
            NS.DriverCooldown.Detach(iconId)
        end
    end
    for bid, bf in pairs(barFrames) do
        local rec = bf:IsShown() and Store.Get(bid)
        if rec and not DrawnHere(rec) then ReleaseBar(bid) end
    end
    -- Post-passes: anchors need every live frame (cross-layout too); then the
    -- conditions pass paints alphas this same frame, so none render stale.
    ApplyAnchors()
    if NS.Conditions then NS.Conditions.Pass() end
    Engine.RefreshEditing()
end

function Engine.QueueRebuild()
    Events.Coalesce("ad_rebuild", Engine.Rebuild)
end

-- A new resolution or UI scale moves the physical pixel grid: every size and
-- corner was rounded to the old one, so the whole layout is placed again.
function Engine.OnScreenChanged()
    Engine.QueueRebuild()
end

function Engine.SetMoveMode(on)
    moveMode = on and true or false
    Engine.QueueRebuild()
end

function Engine.IsMoveMode() return moveMode end

-- Frame getters for sibling modules (the bars engine anchors to layouts).
function Engine.GetLayoutFrame(id) return layoutFrames[id] end
function Engine.GetGroupFrame(id) return groupFrames[id] end
function Engine.GetBarFrame(id) return barFrames[id] end

function Engine.SetEditMode(on)
    editMode = on and true or false
    -- what an eye hid shows again on the next open
    if not editMode then Store.ClearEditHidden() end
    -- First-come order resets on every panel open and close, so a closed panel
    -- builds the dynamic layout from the grid, not the last fight's arrivals.
    wipe(fcfsOrders)
    -- the rebuild also hands Dynamic aura groups between the grid and their
    -- pieces (Drivers\AD_DriverAuraRows.lua claims them in play only)
    Engine.QueueRebuild()
end

function Engine.IsEditMode() return editMode end

function Engine.Init()
    Events.OnMessage("AD_DIRTY", "engine", function() Engine.QueueRebuild() end)
    -- A combat edge restyles nothing: combat conditions run their own pass,
    -- so only the combat-only glows re-check, a frame later, as
    -- InCombatLockdown still reads false while PLAYER_REGEN_DISABLED runs.
    local function CombatEdge()
        Events.Coalesce("ad_combat_glows", function()
            for iconId, f in pairs(Factory.frames) do
                local rec = f:IsShown() and Store.Get(iconId)
                if rec then Factory.CombatGlows(f, rec) end
            end
            if NS.DriverWarn then NS.DriverWarn.ApplyAll() end
        end)
    end
    Events.On("PLAYER_REGEN_DISABLED", "adeng", CombatEdge)
    Events.On("PLAYER_REGEN_ENABLED", "adeng", CombatEdge)
    Events.On("PLAYER_SPECIALIZATION_CHANGED", "adeng", function(_, unit)
        if unit == "player" or unit == nil then Engine.QueueRebuild() end
    end)
    Events.On("PLAYER_ENTERING_WORLD", "adeng", function() Engine.QueueRebuild() end)
    Events.On("UI_SCALE_CHANGED", "adeng", Engine.OnScreenChanged)
    Events.On("DISPLAY_SIZE_CHANGED", "adeng", Engine.OnScreenChanged)
    -- An addon may set UIParent's scale itself (a "pixel perfect" scale), which
    -- fires no event: the layout is placed again after that too.
    hooksecurefunc(UIParent, "SetScale", Engine.OnScreenChanged)
    -- Talent load conditions: on a spec-less client the talent build is the
    -- gate, so a talent change re-runs visibility like a spec swap. The catalog
    -- filters with IsEventValid: RegisterEvent throws on an unknown event, and
    -- several of these don't exist on every client.
    if NS.TalentCatalog then
        for _, e in ipairs(NS.TalentCatalog.ValidEvents()) do
            Events.On(e, "adeng", function() Engine.QueueRebuild() end)
        end
    end
    -- Content events: spell art and overrides change on SPELLS_CHANGED, item
    -- and trinket art on PLAYER_EQUIPMENT_CHANGED (restyling only those kinds).
    Events.On("SPELLS_CHANGED", "adeng", function() Engine.QueueRebuild() end)
    -- Toggle art (aspects, stances, auras) flips with no promised
    -- SPELL_UPDATE_ICON, so re-read only the art on every event the action bar
    -- repaints from, once a frame; Factory.RefreshArt paints only a change.
    local function ArtPass()
        Events.Coalesce("ad_icon_art", function()
            for iconId, f in pairs(Factory.frames) do
                local rec = Store.Get(iconId)
                if rec and rec.kind == "spell" and f.icon and f:IsShown() then
                    Factory.RefreshArt(f, rec)
                end
            end
        end)
    end
    Events.On("ACTIONBAR_UPDATE_STATE", "adeng_art", ArtPass)
    Events.On("UPDATE_SHAPESHIFT_FORM", "adeng_art", ArtPass)
    Events.On("UNIT_AURA", "adeng_art", function(_, unit)
        if unit == "player" then ArtPass() end
    end)
    -- Toggle art is read off the action button (Factory.LiveSpellArt), so the
    -- two events that change it on Forever join in, where the client has them.
    for _, e in ipairs({ "UPDATE_STEALTH", "ACTIONBAR_SLOT_CHANGED" }) do
        if (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(e) then
            Events.On(e, "adeng_art", ArtPass)
        end
    end
    -- Override-form art (Ascendance, proc forms): restyle spell icons.
    Events.On("SPELL_UPDATE_ICON", "adeng", function()
        Events.Coalesce("ad_icon_restyle", function()
            for iconId, f in pairs(Factory.frames) do
                local rec = Store.Get(iconId)
                if rec and rec.kind == "spell" and f:IsShown() then
                    Factory.ApplyStyle(f, rec)
                end
            end
        end)
    end)
    -- Condition edges get the conditions module's alpha-only pass, no rebuild.
    if NS.Conditions then NS.Conditions.Init() end
    -- A state edge (Factory.SetState flipped an icon's drop-out state)
    -- re-places only the live dynamic groups, from the last rebuild's geometry,
    -- once a frame. Edit sessions ignore edges: the panel shows the static grid.
    Events.OnMessage("AD_DYNEDGE", "engine", function()
        Events.Coalesce("ad_dynedge", function()
            if editMode then return end
            local resized = false
            for gid, ctx in pairs(dynCtx) do
                local g, gf = Store.Get(gid), groupFrames[gid]
                -- Check the group and its layout container: an unloaded layout
                -- hides only the container, and its released icons must stay
                -- released. Not IsVisible, which is also false under Alt+Z.
                local lf = gf and gf:GetParent()
                if g and gf and gf:IsShown() and lf and lf:IsShown()
                    and Store.Resolve(g, "arrangement", "dynamicLayout") == true then
                    if DynApply(g, gf, ctx) then resized = true end
                else
                    dynCtx[gid] = nil
                end
            end
            -- Re-anchor what is pinned to a resized box (Match width bars).
            if resized and NS.Anchor then NS.Anchor.ApplyAll() end
        end)
    end)
    Events.On("PLAYER_EQUIPMENT_CHANGED", "adeng", function()
        Events.Coalesce("ad_equip_restyle", function()
            for iconId, f in pairs(Factory.frames) do
                local rec = Store.Get(iconId)
                -- Ammo too: swapping arrow types changes the icon art.
                if rec and (rec.kind == "trinket" or rec.kind == "item"
                    or rec.kind == "ammo") and f:IsShown() then
                    Factory.ApplyStyle(f, rec)
                end
            end
        end)
    end)
end
