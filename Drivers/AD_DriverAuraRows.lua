-- Arc Auras, all rights reserved: do not copy or adapt this code into another addon without permission.
-- AD_DriverAuraRows: Dynamic aura groups in play. Every icon is its own piece
-- (one AuraContainer with one aura group), and each grid row (or column) lines
-- its pieces up in the editor's order, packed and aligned. The editor's grid is
-- unchanged: with the options window open the layout engine draws it.
-- The game reads the auras and sizes every piece, so it works in combat:
-- nothing here reads an aura, a rect or a size. Pieces anchor only to pieces
-- or to the group frame (a container with aura groups refuses other frames).
-- An icon set to Show while missing wears its Missing look in the row too:
-- its piece is born in a stage of ours, made with the opt-in template so it
-- may anchor to pieces, and the row steps past it by what it shows
-- (AR.Step).
local ADDON, NS = ...
local Store, Events = NS.Store, NS.Events
local AR = {
    -- [groupId] = { pieces = { [recId] = piece }, copies = { [recId] = piece },
    --   lanes = { ["recId:slot"] = lane } }
    runtimes = {},
    pool = { player = {}, target = {}, pet = {} },   -- pieces no group uses, by unit
    spool = { player = {}, target = {}, pet = {} },  -- the same, born in a stage
    lpool = { player = {}, target = {}, pet = {} },  -- glow lanes no group uses
    placed = {},     -- [groupId] = its group frame while the engine draws it
    pending = false, -- a piece, a filter or a restyle waits for the settle edge
    loadWindowOver = false,
}
NS.DriverAuraRows = AR

-- Frames of ours that anchor to a piece need it from birth (the aura group's
-- forbidden aspect, Blizzard_CustomAuraContainer AddAuraGroup).
AR.OPT_IN = "DisableUntrustedLayoutScriptsTemplate"

AR.KEY = "adPiece"
AR.BASE = { player = "HELPFUL", target = "HARMFUL", pet = "HELPFUL" }
-- A centered row's copy runs at this scale, so on screen it is half as wide
-- as the real row: the real row starts at the copy's left edge.
AR.COPY_SCALE = 0.5

-- Every Dynamic aura group, except one showing every aura on a unit (its own
-- file draws it).
function AR.On(g)
    return g ~= nil and g.groupKind == "aura"
        and Store.Resolve(g, "arrangement", "dynamicLayout") == true
        and not (Store.ShowsAll and Store.ShowsAll(g))
end

function AR.Available()
    local G = NS.DriverAuraGroups
    return G ~= nil and G.IsAvailable()
end

-- In play only: with the window open the grid draws the group for editing.
function AR.Claims(g)
    local E = NS.LayoutEngine
    return AR.Available() and AR.On(g) and not (E and E.IsEditMode and E.IsEditMode())
end

-- Containers are made in the load window, else only out of combat with auras
-- plain: the game blocks creation otherwise.
function AR.CanMake()
    return not (AR.loadWindowOver and (InCombatLockdown() or NS.DriverAuraGroups.AurasSecretNow()))
end

-- How a member wears its Missing look in a row: nil (none: it shows only while
-- its aura is up), "both" (always, a spot of its own) or "missing" (only while
-- the aura is not up). nil where the client cannot draw it.
function AR.MissMode(rec)
    local DA = NS.DriverAura
    if not (DA and DA.EraserAvailable and DA.EraserAvailable()) then return nil end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    if R("auraMissing", "showWhileMissing") ~= true then return nil end
    if (R("auraMissing", "missingAlpha") or 1) <= 0 then return nil end
    if (R("auraActive", "activeAlpha") or 1) <= 0 then return "missing" end
    return "both"
end

-- One container following `unit` with one parked aura group. Its buttons are
-- sized and dressed as the game makes them, from what the piece holds then.
-- staged: the container is born in a stage of its own (it can never be moved
-- into one while auras are secret), its buttons set up for it from birth.
-- lane: a glow lane, whose unwired buttons carry one glow and nothing else.
function AR.Make(unit, staged, lane)
    if not AR.CanMake() then
        AR.pending = true
        return nil
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local st
    if staged then
        st = CreateFrame("Frame", nil, UIParent, AR.OPT_IN)
        st:SetSize(1, 1)
        st:SetFlattensRenderLayers(true)
        -- set before any button exists
        st:SetIsFrameBuffer(true)
        st:Hide()
    end
    local c = CreateFrame("AuraContainer", nil, st or UIParent, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraGroup) ~= "function" then
        if c then c:Hide() end
        if st then st:Hide() end
        return nil
    end
    local G, DA = NS.DriverAuraGroups, NS.DriverAura
    -- shaped like a member-row runtime, so the shared styler reads it as one
    local p = { c = c, unit = unit, buttons = {}, slotRecs = {}, slotDims = {},
        cfg = { iconW = 36, iconH = 36 }, engines = { c }, stage = st, erase = staged and true or nil,
        rowGlows = true, lane = lane and true or nil }
    c:SetSize(1, 1)
    c:SetUnit(unit)
    c:SetEnabled(true)
    c:EnableMouse(false)
    c:Hide()
    c:AddAuraGroup(AR.KEY, AR.BASE[unit], {
        maxFrameCount = 0,
        candidateFilters = { includeSpellIDs = G.ParkMap() },
        initializeFrame = function(b)
            if not p.lane and DA and DA.WireButton then DA.WireButton(b) end
            b:SetSize(p.cfg.iconW, p.cfg.iconH)
            b._adAppliedW, b._adAppliedH = p.cfg.iconW, p.cfg.iconH
            b._adSlotIndex = 1
            b:EnableMouse(false)
            if not b._adCollected then
                b._adCollected = true
                p.buttons[#p.buttons + 1] = b
            end
            -- set at birth: in an instance the button is never restyled
            local er = p.erase and b._adEraser
            if er then
                local m = math.max(p.cfg.iconW, p.cfg.iconH)
                er:ClearAllPoints()
                er:SetPoint("TOPLEFT", b, "TOPLEFT", -m, m)
                er:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", m, -m)
                er:Show()
            end
            if p.lane then
                AR.StyleLane(p, b)
            elseif not p.copy then
                G.StyleSlotButton(b, p)
            end
        end,
        layout = { elementSpacing = 0, lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0 },
    })
    p.sent = { sig = DA.FilterSig(G.ParkMap()), filter = AR.BASE[unit], cap = 0 }
    return p
end

function AR.Take(unit, staged, lane)
    local list = ((lane and AR.lpool) or (staged and AR.spool) or AR.pool)[unit]
    local p = list[#list]
    if p then
        list[#list] = nil
        return p
    end
    return AR.Make(unit, staged, lane)
end

-- Back to the pool, hidden; its filter parks now, or at the settle edge.
function AR.Give(p)
    p.c:Hide()
    p.c:ClearAllPoints()
    p.c:SetScale(1)
    if p.stage then
        p.stage:Hide()
        p.stage:ClearAllPoints()
        AR.StopGlows(p)
    end
    p.rec, p.slotRecs[1], p.copy, p.shape, p.slot, p.rowLanes, p.piece = nil, nil, nil, nil, nil, nil, nil
    if AR.Send(p, nil) then AR.pending = true end
    local list = ((p.lane and AR.lpool) or (p.stage and AR.spool) or AR.pool)[p.unit]
    list[#list + 1] = p
end

-- The piece's filter, ids and frame cap for rec (nil parks it), out of combat
-- only. True when it has to wait.
function AR.Send(p, rec)
    local G, DA = NS.DriverAuraGroups, NS.DriverAura
    local ids, fstr, exempt = G.ParkMap(), AR.BASE[p.unit], false
    if rec then
        local i, f, e = G.MemberMapFor(rec, p.unit)
        if i and i[0] == nil then
            ids, fstr, exempt = i, f or fstr, e
            if p.lane then ids = AR.LaneIDs(rec, p.slot, i) or G.ParkMap() end
        end
    end
    local parked = ids[0] ~= nil
    local cap = 0
    if not parked then
        cap = G.SLOT_CAP[p.unit] or 1
        if p.unit == "target" and not exempt and G.TargetFiltersHonored() ~= true then cap = 0 end
    end
    p.exempt = exempt
    local sig = DA.FilterSig(ids)
    local s = p.sent
    if s.sig == sig and s.filter == fstr and s.cap == cap then return false end
    if InCombatLockdown() then return true end
    local c = p.c
    if parked then c:SetAuraGroupMaxFrameCount(AR.KEY, 0) end
    if s.filter ~= fstr then c:SetAuraGroupFilterString(AR.KEY, fstr) end
    if s.sig ~= sig then c:SetAuraGroupCandidateFilters(AR.KEY, { includeSpellIDs = ids }) end
    if not parked then c:SetAuraGroupMaxFrameCount(AR.KEY, cap) end
    s.sig, s.filter, s.cap = sig, fstr, cap
    return false
end

-- Glow lanes: a glow the row's button cannot draw (one spell picked, or one
-- that waits for combat) gets a container of its own over the piece, which
-- shows its button exactly while that aura is up. Its ids: the piece's own,
-- narrowed to the picked spell and its ranks by name; nil = no lane.
function AR.LaneIDs(rec, slot, pieceIDs)
    if not (rec and slot and NS.DriverAura.RowGlowIDs(rec, slot)) then return nil end
    local suf = (slot > 1) and tostring(slot) or ""
    local pick = tonumber(Store.Resolve(rec, "auraActive", "activeGlowFor" .. suf)) or 0
    if pick <= 0 then return pieceIDs end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(pick)
    local m, n = {}, 0
    for id in pairs(pieceIDs) do
        if id == pick or (name ~= nil and C_Spell.GetSpellName(id) == name) then
            m[id] = true
            n = n + 1
        end
    end
    -- a pick the icon no longer tracks follows every id, as on a free icon
    if n == 0 then return pieceIDs end
    return m
end

-- A lane's button: its one glow, sized as the piece's. At birth, or on an
-- accessible pass (AR.RestyleLane).
function AR.StyleLane(L, b)
    local rec, DA = L.rec, NS.DriverAura
    if not (rec and L.slot) then return end
    local w, h = L.cfg.iconW, L.cfg.iconH
    if b._adAppliedW ~= w or b._adAppliedH ~= h then
        b:SetSize(w, h)
        b._adAppliedW, b._adAppliedH = w, h
    end
    NS.Factory.StyleAuraGlowButton(b, rec, h, { glowSlot = L.slot, w = w, h = h,
        glowOn = DA.RowGlowIDs(rec, L.slot) ~= nil })
end

-- True when a button was locked, so the caller retries at its settle edge.
function AR.RestyleLane(L)
    local locked = false
    for _, b in ipairs(L.buttons) do
        local ok
        if b.CanBeAccessedInContext then ok = b:CanBeAccessedInContext() else ok = not (b.IsForbidden and b:IsForbidden()) end
        if ok then AR.StyleLane(L, b) else locked = true end
    end
    return locked
end

-- A lane's opacity: its group's, and none out of combat for a glow that waits.
function AR.LaneAlpha(L, gf, on, combat)
    local a = 0
    if on and gf then
        a = gf.GetEffectiveAlpha and gf:GetEffectiveAlpha() or gf:GetAlpha() or 1
        if issecretvalue and issecretvalue(a) then a = 1 end
    end
    local suf = (L.slot and L.slot > 1) and tostring(L.slot) or ""
    if L.rec and Store.Resolve(L.rec, "auraActive", "activeGlowCombatOnly" .. suf) == true and not combat then
        a = 0
    end
    L.c:SetAlpha(a)
end

-- A piece's cell is its icon plus the spacing after it along the direction it
-- packs (elementWidth in a row, elementHeight in a column), so pieces touch
-- and the spacing still falls between icons; an empty piece is one unit long.
-- grow: "right" / "left" in a row, "down" / "up" in a column, the side its
-- buttons flow toward from the opposite corner.
AR.CORNER = { right = "TOPLEFT", left = "TOPRIGHT", down = "TOPLEFT", up = "BOTTOMLEFT" }

function AR.Shape(p, w, h, sx, sy, grow)
    -- its lanes copy the flow (AR.PlaceLanes)
    p.grow = grow
    local key = w .. ":" .. h .. ":" .. sx .. ":" .. sy .. ":" .. grow
    if p.shape == key then return end
    p.shape = key
    local c = p.c
    local vertical = grow == "down" or grow == "up"
    c:SetAuraGroupLayout(AR.KEY, { elementSpacing = 0, lineSpacing = 0, groupSpacing = 0,
        groupLineSpacing = 0, elementWidth = vertical and w or (w + sx),
        elementHeight = vertical and (h + sy) or h })
    local AX = AnchorUtil and AnchorUtil.FlowLayoutAxis
    if AX and c.SetFlowLayoutAxis then c:SetFlowLayoutAxis(vertical and AX.Vertical or AX.Horizontal) end
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if FD and c.SetFlowLayoutGrowthDirection then
        c:SetFlowLayoutGrowthDirection(grow == "left" and FD.Left or FD.Right, grow == "up" and FD.Up or FD.Down)
    end
    if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint(AR.CORNER[grow]) end
    if c.SetFlowLayoutPadding then c:SetFlowLayoutPadding(0, 0, 0, 0) end
    if c.SetFlowLayoutMaximumLineSize then c:SetFlowLayoutMaximumLineSize(nil) end
end

-- The loaded aura icons, and the unit whose row a member's aura is drawn on
-- in play (buffs on you or your pet, debuffs on your target); nil = panel only.
function AR.Members(g)
    local out = {}
    for _, rec in ipairs(Store.IconsOf(g)) do
        if rec.kind == "aura" and Store.IsLoaded(rec) then out[#out + 1] = rec end
    end
    return out
end

function AR.UnitOf(rec)
    local G = NS.DriverAuraGroups
    for _, unit in ipairs(G.ENGINE_ORDER) do
        local ids = G.MemberMapFor(rec, unit)
        if ids and ids[0] == nil then return unit end
    end
    return nil
end

-- The grid as the editor draws it (PlaceGroup's cells, nothing written): its
-- box, each member's visual row and column, the steps.
function AR.Grid(g, members)
    local w, h, sx, sy, cols, growthH, growthV = NS.DriverAuraGroups.GroupDims(g)
    local pad = math.max(0, Store.Resolve(g, "arrangement", "containerPadding") or 0)
    local occupied, pending = {}, {}
    for _, rec in ipairs(members) do
        local gp = rec.gpos
        local key = gp and gp.row and gp.col and gp.col < cols and (gp.row * cols + gp.col) or nil
        if key and not occupied[key] then occupied[key] = rec else pending[#pending + 1] = rec end
    end
    for _, rec in ipairs(pending) do
        local k = 0
        while occupied[k] do k = k + 1 end
        occupied[k] = rec
    end
    local rows = math.max(1, Store.Resolve(g, "arrangement", "rows") or 1)
    for k in pairs(occupied) do rows = math.max(rows, math.floor(k / cols) + 1) end
    local cells = {}
    for k, rec in pairs(occupied) do
        local row, col = math.floor(k / cols), k % cols
        if growthH == "LEFT" then col = cols - 1 - col end
        if growthV == "UP" then row = rows - 1 - row end
        cells[#cells + 1] = { rec = rec, row = row, col = col }
    end
    return { w = w, h = h, sx = sx, sy = sy, cols = cols, rows = rows, pad = pad, cells = cells,
        boxW = cols * w + (cols - 1) * sx + pad * 2, boxH = rows * h + (rows - 1) * sy + pad * 2 }
end

-- The direction and where each line's pieces sit: Horizontal packs every row
-- (left / center / right), Vertical every column (top / center / bottom). The
-- stored alignment is read per direction, so a value of the other one reads as
-- center. A single row or column needs no special case: each column of a row
-- holds one piece, and each row of a column one.
function AR.Pack(g)
    local a = Store.Resolve(g, "arrangement", "alignment") or "center"
    if Store.Resolve(g, "arrangement", "dynamicAxis") == "vertical" then
        return "vertical", (a == "top" or a == "bottom") and a or "center"
    end
    return "horizontal", (a == "left" or a == "right") and a or "center"
end

-- A member's size: the grid's cell, or its own once Use group scale is off.
function AR.Dims(rec, grid)
    local Rp = function(f) return Store.Resolve(rec, "position", f) end
    if Rp("useGroupScale") ~= false then return grid.w, grid.h end
    local w, h = grid.w, grid.h
    local iw, ih = Rp("iconWidth") or 0, Rp("iconHeight") or 0
    if iw > 0 then w = iw end
    if ih > 0 then h = ih end
    local sc = Rp("iconScale") or 1
    return math.max(1, math.floor(w * sc + 0.5)), math.max(1, math.floor(h * sc + 0.5))
end

-- The piece for rec in `set` (a group's pieces or its copies), kept while its
-- unit and stage are the same, else taken from the pool; nil while none can be
-- made. staged: rec wears its Missing look in the row.
function AR.Piece(set, rec, unit, staged)
    local p = set[rec.id]
    if p and (p.unit ~= unit or (p.stage ~= nil) ~= (staged == true)) then
        AR.Give(p)
        set[rec.id] = nil
        p = nil
    end
    if not p then
        p = AR.Take(unit, staged)
        if not p then return nil end
        set[rec.id] = p
    end
    p.rec, p.slotRecs[1] = rec, rec
    return p
end

-- How a line is chained, by the way it is built: the point a piece puts on
-- the running edge (near), the one the next hangs from (far), the step's axis
-- and sign, and the growth that hangs back. Columns keep to left-edge points,
-- so an empty piece (one unit wide) never pulls a column sideways.
AR.DIRS = {
    right = { near = "TOPLEFT", far = "TOPRIGHT", dx = 1, dy = 0, back = "left" },
    left = { near = "TOPRIGHT", far = "TOPLEFT", dx = -1, dy = 0, back = "right" },
    down = { near = "TOPLEFT", far = "BOTTOMLEFT", dx = 0, dy = -1, back = "up" },
    up = { near = "BOTTOMLEFT", far = "TOPLEFT", dx = 0, dy = 1, back = "down" },
}

-- One element on the running edge a = { f, pt, x, y }; returns the edge after
-- it. Only while up (mode nil): its piece grows on, a cell while the aura is.
-- "both": a cell always, so the next one skips its piece. "missing": its piece
-- hangs back from the far side of its cell and takes the cell back while the
-- aura is up (+1: the unit an empty piece keeps). q: the piece (none for a
-- "both" copy); st: its stage, on the cell's near side. cell: q's own units.
function AR.Step(q, st, mode, a, dir, cell, e, grid)
    local D = AR.DIRS[dir]
    if st then
        st:ClearAllPoints()
        st:SetPoint(D.near, a.f, a.pt, a.x, a.y)
    end
    if mode == "missing" then
        AR.Shape(q, e.w, e.h, grid.sx, grid.sy, D.back)
        q.c:ClearAllPoints()
        q.c:SetPoint(D.far, a.f, a.pt, a.x + D.dx * (cell + 1), a.y + D.dy * (cell + 1))
        return { f = q.c, pt = D.near, x = 0, y = 0 }
    end
    if q then
        AR.Shape(q, e.w, e.h, grid.sx, grid.sy, dir)
        q.c:ClearAllPoints()
        q.c:SetPoint(D.near, a.f, a.pt, a.x, a.y)
    end
    if mode == "both" then
        return { f = a.f, pt = a.pt, x = a.x + D.dx * cell, y = a.y + D.dy * cell }
    end
    return { f = q.c, pt = D.far, x = 0, y = 0 }
end

-- The half-scale copy of a line (same units, filters, caps and cells; a "both"
-- element's step is constant, so it needs none), chained from `a` back across
-- the line in its own (half) scale. Its far end, or nil while a copy can't be
-- made yet (made at the settle edge).
function AR.CopyLine(rt, list, keepCopy, grid, dir, a, horizontal)
    for i = #list, 1, -1 do
        local e = list[i]
        local q
        if e.mode ~= "both" then
            q = AR.Piece(rt.copies, e.rec, e.unit, false)
            if not q then return nil end
            q.copy = true
            keepCopy[e.rec.id] = true
            q.cfg.iconW, q.cfg.iconH = e.w, e.h
            if AR.Send(q, e.rec) then AR.pending = true end
            q.c:SetScale(AR.COPY_SCALE)
        end
        a = AR.Step(q, nil, e.mode, a, dir, horizontal and (e.w + grid.sx) or (e.h + grid.sy), e, grid)
    end
    return a
end

-- One row, its elements in screen order (left to right). Right chains leftward
-- from the right edge; Left and Center rightward, Center from the far end of
-- the row's half-scale copy, which ends on the group's middle. The trailing
-- spacing in every cell is split off the center by sx / 2.
function AR.LayRow(rt, gf, grid, list, align, rowY, keepCopy)
    local sx, sy = grid.sx, grid.sy
    local n = #list
    if align == "right" then
        local a = { f = gf, pt = "TOPRIGHT", x = -grid.pad, y = rowY }
        for i = n, 1, -1 do
            local e = list[i]
            a = AR.Step(e.p, e.p.stage, e.mode, a, "left", e.w + sx, e, grid)
        end
        return
    end
    local a
    if align == "left" then
        a = { f = gf, pt = "TOPLEFT", x = grid.pad, y = rowY }
    elseif n == 1 then
        -- alone: on the middle, no copy
        local e = list[1]
        AR.Shape(e.p, e.w, e.h, sx, sy, "right")
        e.p.c:ClearAllPoints()
        e.p.c:SetPoint("TOP", gf, "TOP", sx / 2, rowY)
        if e.p.stage then
            e.p.stage:ClearAllPoints()
            e.p.stage:SetPoint("TOP", gf, "TOP", 0, rowY)
        end
        return
    else
        local c = AR.CopyLine(rt, list, keepCopy, grid, "left",
            { f = gf, pt = "TOP", x = 0, y = rowY / AR.COPY_SCALE }, true)
        if c then
            a = { f = c.f, pt = c.pt, x = c.x * AR.COPY_SCALE + sx / 2, y = c.y * AR.COPY_SCALE }
        else
            a = { f = gf, pt = "TOP", x = 0, y = rowY }
        end
    end
    for _, e in ipairs(list) do
        a = AR.Step(e.p, e.p.stage, e.mode, a, "right", e.w + sx, e, grid)
    end
end

-- One column, its elements in screen order (top to bottom), at the column's
-- own x (colX = its left edge). Up chains downward from the top edge, Down
-- upward from the bottom edge; Center downward from the top of the column's
-- half-scale copy, which stands on the group's vertical middle. The trailing
-- spacing in every cell is split off the center by sy / 2.
function AR.LayCol(rt, gf, grid, list, align, colX, keepCopy)
    local sx, sy = grid.sx, grid.sy
    local n = #list
    if align == "bottom" then
        local a = { f = gf, pt = "BOTTOMLEFT", x = colX, y = grid.pad }
        for i = n, 1, -1 do
            local e = list[i]
            a = AR.Step(e.p, e.p.stage, e.mode, a, "up", e.h + sy, e, grid)
        end
        return
    end
    local a
    if align == "top" then
        a = { f = gf, pt = "TOPLEFT", x = colX, y = -grid.pad }
    elseif n == 1 then
        -- alone: on the middle, no copy
        local e = list[1]
        AR.Shape(e.p, e.w, e.h, sx, sy, "down")
        e.p.c:ClearAllPoints()
        e.p.c:SetPoint("LEFT", gf, "LEFT", colX, -sy / 2)
        if e.p.stage then
            e.p.stage:ClearAllPoints()
            e.p.stage:SetPoint("LEFT", gf, "LEFT", colX, 0)
        end
        return
    else
        local c = AR.CopyLine(rt, list, keepCopy, grid, "up",
            { f = gf, pt = "LEFT", x = colX / AR.COPY_SCALE, y = 0 }, false)
        if c then
            a = { f = c.f, pt = c.pt, x = c.x * AR.COPY_SCALE, y = c.y * AR.COPY_SCALE - sy / 2 }
        else
            a = { f = gf, pt = "LEFT", x = colX, y = 0 }
        end
    end
    for _, e in ipairs(list) do
        a = AR.Step(e.p, e.p.stage, e.mode, a, "down", e.h + sy, e, grid)
    end
end

-- A member's Missing look on its stage, drawn as the icon draws its own: the
-- missing art (cropped, padded, greyed, at the Missing alpha), the border and
-- the custom texts kept to the aura's absence.
-- Its glows: AR.PaintGlows.
function AR.PaintLook(p, rec, w, h)
    local F = NS.Factory
    local st = p.stage
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    st:SetSize(w, h)
    local look = p.look
    if not look then
        look = { art = st:CreateTexture(nil, "ARTWORK"), edges = {}, texts = {} }
        for _, k in ipairs({ "top", "bottom", "left", "right" }) do
            local t = st:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(1, 1, 1, 1)
            look.edges[k] = t
        end
        p.look = look
    end
    local kS = h / 36
    local ma = R("auraMissing", "missingAlpha") or 1
    local hide = R("appearance", "forceHideIcon") == true
    local art = look.art
    art:SetTexture(F.GetTexture(rec))
    art:SetTexCoord(F.IconTexCoords(rec))
    local pad = (R("appearance", "padding") or 0) * kS
    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", st, "TOPLEFT", pad, -pad)
    art:SetPoint("BOTTOMRIGHT", st, "BOTTOMRIGHT", -pad, pad)
    art:SetDesaturated(R("auraMissing", "missingDesaturate") ~= false)
    art:SetAlpha(ma)
    art:SetShown(not hide)
    if R("appearance", "borderEnabled") and not hide then
        F.PaintBorderEdges(look.edges, st, rec, ma)
    else
        for _, t in pairs(look.edges) do t:Hide() end
    end
    local ta = (R("auraMissing", "missingPreserveText") ~= false) and 1 or ma
    for i, suf in ipairs({ "", "2", "3" }) do
        local fs = look.texts[i]
        local words = R("label", "labelText" .. suf)
        if R("label", "labelMissingOnly" .. suf) == true and words and words ~= "" then
            if not fs then
                fs = st:CreateFontString(nil, "OVERLAY")
                fs:SetDrawLayer("OVERLAY", 7)
                look.texts[i] = fs
            end
            F.StyleLabel(fs, rec, suf, kS, st)
            fs:SetAlpha(ta)
            fs:Show()
        elseif fs then
            fs:Hide()
        end
    end
end

-- A member's Missing and Always glows on its stage, at its piece's level (the
-- button draws the rest). Frames anchored to the stage take its template.
function AR.PaintGlows(p, combat)
    local rec, look, F = p.rec, p.look, NS.Factory
    if not (rec and look and p.stage and p.lvl) then return end
    local hide = Store.Resolve(rec, "appearance", "forceHideIcon") == true
    local n = (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1
    local gh = look.glow
    if not gh then
        local any = false
        for k = 1, n do any = any or F.HolderGlowOn(rec, k) end
        if hide or not any then return end
        gh = CreateFrame("Frame", nil, p.stage, AR.OPT_IN)
        gh:SetAllPoints(p.stage)
        gh:EnableMouse(false)
        gh._adOptIn = AR.OPT_IN
        look.glow = gh
    end
    gh:SetAlpha(Store.Resolve(rec, "auraMissing", "missingAlpha") or 1)
    for k = 1, n do
        local suf = (k > 1) and tostring(k) or ""
        local on = not hide and F.HolderGlowOn(rec, k)
            and (combat == true or Store.Resolve(rec, "auraActive", "activeGlowCombatOnly" .. suf) ~= true)
        F.SetAuraButtonGlow(gh, rec, on, p.cfg.iconW, p.cfg.iconH, 1, k, p.lvl + 1)
    end
end

-- A pooled piece's glows stop.
function AR.StopGlows(p)
    local gh = p.look and p.look.glow
    if not gh then return end
    for k = 1, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
        NS.Factory.SetAuraButtonGlow(gh, nil, false, nil, nil, nil, k)
    end
end

-- Combat edges: glows that wait for combat follow (the event carries the state).
function AR.OnCombatEdge(state)
    for gid, gf in pairs(AR.placed) do
        local rt = AR.runtimes[gid]
        if rt then
            for _, p in pairs(rt.pieces) do
                if p.stage then AR.PaintGlows(p, state) end
            end
            local g = Store.Get(gid)
            local on = g ~= nil and Store.IsLoaded(g) and gf:IsShown()
            for _, L in pairs(rt.lanes or {}) do AR.LaneAlpha(L, gf, on, state) end
        end
    end
end

-- Shown with the group frame, its fade and level carried over; copies never show.
function AR.Mirror(g, rt, gf)
    local G, DA = NS.DriverAuraGroups, NS.DriverAura
    local on = AR.placed[g.id] ~= nil and Store.IsLoaded(g) and gf ~= nil and gf:IsShown()
    for _, p in pairs(rt.pieces) do
        if p.stage then
            -- the stage carries the fade and level; its piece rides it, a level up
            G.MirrorOnto(p.stage, gf, on)
            p.c:SetShown(on)
            p.c:SetFrameStrata(p.stage:GetFrameStrata())
            local lvl = p.stage:GetFrameLevel()
            if type(lvl) == "number" and not (issecretvalue and issecretvalue(lvl)) then
                p.c:SetFrameLevel(lvl + 1)
                p.lvl = lvl
            end
            AR.PaintGlows(p, DA ~= nil and DA.InCombat ~= nil and DA.InCombat())
        else
            G.MirrorOnto(p.c, gf, on)
        end
    end
    for _, q in pairs(rt.copies) do
        G.MirrorOnto(q.c, gf, on)
        q.c:SetAlpha(0)
    end
    -- lanes sit over every piece's button
    local gl = gf and gf:GetFrameLevel()
    local combat = DA ~= nil and DA.InCombat ~= nil and DA.InCombat()
    for _, L in pairs(rt.lanes or {}) do
        G.MirrorOnto(L.c, gf, on)
        if type(gl) == "number" then L.c:SetFrameLevel(gl + 5) end
        AR.LaneAlpha(L, gf, on, combat)
    end
end

function AR.Place(g, gf, editMode)
    local G = NS.DriverAuraGroups
    local grid = AR.Grid(g, AR.Members(g))
    gf:SetSize(math.max(grid.boxW, 4), math.max(grid.boxH, 4))
    AR.placed[g.id] = gf
    local rt = AR.runtimes[g.id] or { pieces = {}, copies = {}, lanes = {} }
    rt.lanes = rt.lanes or {}
    AR.runtimes[g.id] = rt
    local axis, align = AR.Pack(g)
    local vertical = axis == "vertical"
    -- a line is a row (Horizontal) or a column (Vertical)
    local rows, keep, keepLane = {}, {}, {}
    for _, cell in ipairs(grid.cells) do
        local unit = AR.UnitOf(cell.rec)
        local mode = unit and AR.MissMode(cell.rec)
        local p = unit and AR.Piece(rt.pieces, cell.rec, unit, mode ~= nil)
        if p then
            keep[cell.rec.id] = true
            local w, h = AR.Dims(cell.rec, grid)
            p.cfg.iconW, p.cfg.iconH = w, h
            p.slotDims[1] = { w = w, h = h }
            -- set before the piece's buttons style, so they leave these glows out
            p.rowLanes = AR.Lanes(rt, cell.rec, unit, p, w, h, keepLane)
            if AR.Send(p, cell.rec) then AR.pending = true end
            if p.stage then AR.PaintLook(p, cell.rec, w, h) end
            local line = vertical and cell.col or cell.row
            rows[line] = rows[line] or {}
            table.insert(rows[line], { p = p, rec = cell.rec, unit = unit, row = cell.row, col = cell.col,
                w = w, h = h, mode = mode })
        end
    end
    for id, p in pairs(rt.pieces) do
        if not keep[id] then
            AR.Give(p)
            rt.pieces[id] = nil
        end
    end
    for key, L in pairs(rt.lanes) do
        if not keepLane[key] then
            AR.Give(L)
            rt.lanes[key] = nil
        end
    end
    local keepCopy = {}
    for line, list in pairs(rows) do
        if vertical then
            table.sort(list, function(a, b) return a.row < b.row end)
            AR.LayCol(rt, gf, grid, list, align, grid.pad + line * (grid.w + grid.sx), keepCopy)
        else
            table.sort(list, function(a, b) return a.col < b.col end)
            AR.LayRow(rt, gf, grid, list, align, -(grid.pad + line * (grid.h + grid.sy)), keepCopy)
        end
    end
    for id, q in pairs(rt.copies) do
        if not keepCopy[id] then
            AR.Give(q)
            rt.copies[id] = nil
        end
    end
    AR.PlaceLanes(rt, grid)
    for _, p in pairs(rt.pieces) do
        if G.StyleButtons(p) then AR.pending = true end
    end
    for _, L in pairs(rt.lanes) do
        if AR.RestyleLane(L) then AR.pending = true end
    end
    AR.Mirror(g, rt, gf)
end

-- The lanes rec wants on piece p (kept, swapped or taken from the pool and
-- sent their ids), marked in keepLane; returns the slots they carry, or nil.
function AR.Lanes(rt, rec, unit, p, w, h, keepLane)
    local DA, slots = NS.DriverAura, nil
    for k = 1, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
        if DA.RowGlowIDs(rec, k) then
            local key = rec.id .. ":" .. k
            local L = rt.lanes[key]
            if L and L.unit ~= unit then
                AR.Give(L)
                rt.lanes[key] = nil
                L = nil
            end
            L = L or AR.Take(unit, false, true)
            if L then
                rt.lanes[key] = L
                keepLane[key] = true
                L.rec, L.slot, L.piece = rec, k, p
                L.cfg.iconW, L.cfg.iconH = w, h
                if AR.Send(L, rec) then AR.pending = true end
                slots = slots or {}
                slots[k] = true
            end
        end
    end
    return slots
end

-- Each lane copies its piece's flow from the same corner, so its button lands
-- on the piece's.
function AR.PlaceLanes(rt, grid)
    for _, L in pairs(rt.lanes) do
        local p = L.piece
        if p and p.grow then
            AR.Shape(L, L.cfg.iconW, L.cfg.iconH, grid.sx, grid.sy, p.grow)
            local corner = AR.CORNER[p.grow]
            L.c:ClearAllPoints()
            L.c:SetPoint(corner, p.c, corner, 0, 0)
        end
    end
end

function AR.Release(g)
    local gid = g.id
    AR.placed[gid] = nil
    local rt = AR.runtimes[gid]
    if not rt then return end
    for id, p in pairs(rt.pieces) do
        AR.Give(p)
        rt.pieces[id] = nil
    end
    for id, q in pairs(rt.copies) do
        AR.Give(q)
        rt.copies[id] = nil
    end
    for key, L in pairs(rt.lanes or {}) do
        AR.Give(L)
        rt.lanes[key] = nil
    end
    AR.runtimes[gid] = nil
end

-- Target swaps: re-cap the hostility gate on every target piece and copy, then
-- rescan. An unknown (secret) answer keeps the caps the last plain one set.
function AR.Recap(rescan)
    local G = NS.DriverAuraGroups
    local honored = G.TargetFiltersHonored()
    for _, rt in pairs(AR.runtimes) do
        for _, set in ipairs({ rt.pieces, rt.copies, rt.lanes or {} }) do
            for _, p in pairs(set) do
                if p.unit == "target" and p.rec then
                    if honored ~= nil and p.sent.sig ~= NS.DriverAura.FilterSig(G.ParkMap()) then
                        local cap = (p.exempt or honored) and G.SLOT_CAP.target or 0
                        if p.sent.cap ~= cap then
                            p.c:SetAuraGroupMaxFrameCount(AR.KEY, cap)
                            p.sent.cap = cap
                        end
                    end
                    if rescan and p.c:IsShown() and p.c.UpdateAllAuras then p.c:UpdateAllAuras() end
                end
            end
        end
    end
    return honored ~= nil
end

function AR.OnPet(_, unit)
    if unit ~= nil and not (issecretvalue and issecretvalue(unit)) and unit ~= "player" then return end
    for _, rt in pairs(AR.runtimes) do
        for _, set in ipairs({ rt.pieces, rt.copies, rt.lanes or {} }) do
            for _, p in pairs(set) do
                if p.unit == "pet" and p.c:IsShown() and p.c.UpdateAllAuras then p.c:UpdateAllAuras() end
            end
        end
    end
end

-- Combat end and loading screens: pool pieces still holding a filter park, and
-- a rebuild lands what waited (pieces to make, filters to send, restyles).
function AR.Settle()
    if not InCombatLockdown() then
        for _, pool in ipairs({ AR.pool, AR.spool, AR.lpool }) do
            for _, list in pairs(pool) do
                for _, p in ipairs(list) do AR.Send(p, nil) end
            end
        end
    end
    -- secrecy can lift a beat late: an unknown hostility answer gets two more
    -- tries, then waits for a target change
    if not AR.Recap(false) then
        C_Timer.After(0.3, function()
            if not AR.Recap(false) then C_Timer.After(1, function() AR.Recap(false) end) end
        end)
    end
    if not AR.pending then return end
    AR.pending = false
    local E = NS.LayoutEngine
    if E and E.QueueRebuild then E.QueueRebuild() end
end

-- A deleted group, or one let go of without a rebuild (Dynamic off), is
-- released here.
function AR.Sweep()
    for gid in pairs(AR.runtimes) do
        local g = Store.Get(gid)
        if not (g and AR.On(g) and AR.placed[gid]) then AR.Release(g or { id = gid }) end
    end
end

-- Load window: the pool gets a piece for every icon of every Dynamic aura group,
-- plus the copies a centered row needs, the one time creation is legal in
-- combat or an instance.
function AR.PreBuild()
    if not AR.Available() then return end
    local need = { player = 0, target = 0, pet = 0 }
    -- the pieces born in a stage, for the members wearing a Missing look
    local staged = { player = 0, target = 0, pet = 0 }
    -- and the glow lanes, one per glow its row's button cannot draw
    local lanes = { player = 0, target = 0, pet = 0 }
    local DA = NS.DriverAura
    for _, layout in ipairs(Store.Layouts()) do
        for _, g in ipairs((Store.ChildrenOf(layout))) do
            if AR.On(g) then
                local grid = AR.Grid(g, AR.Members(g))
                local rows = {}
                for _, cell in ipairs(grid.cells) do
                    local unit = AR.UnitOf(cell.rec)
                    if unit then
                        local mode = AR.MissMode(cell.rec)
                        for k = 1, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
                            if DA.RowGlowIDs(cell.rec, k) then lanes[unit] = lanes[unit] + 1 end
                        end
                        local t = mode and staged or need
                        t[unit] = t[unit] + 1
                        local line = AR.Pack(g) == "vertical" and cell.col or cell.row
                        rows[line] = rows[line] or {}
                        table.insert(rows[line], { unit = unit, mode = mode })
                    end
                end
                if select(2, AR.Pack(g)) == "center" then
                    for _, items in pairs(rows) do
                        if #items > 1 then
                            for _, it in ipairs(items) do
                                -- a "both" element's step is constant: no copy
                                if it.mode ~= "both" then need[it.unit] = need[it.unit] + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, set in ipairs({ { need, AR.pool, false }, { staged, AR.spool, true }, { lanes, AR.lpool, false, true } }) do
        for unit, n in pairs(set[1]) do
            local list = set[2][unit]
            while #list < n do
                local p = AR.Make(unit, set[3], set[4])
                if not p then break end
                table.insert(list, p)
            end
        end
    end
end

Events.On("PLAYER_LOGIN", "adar_lw", function() AR.loadWindowOver = true end)
Events.On("PLAYER_REGEN_ENABLED", "adar", AR.Settle)
Events.On("PLAYER_REGEN_DISABLED", "adar_glow", function() AR.OnCombatEdge(true) end)
Events.On("PLAYER_REGEN_ENABLED", "adar_glow", function() AR.OnCombatEdge(false) end)
Events.On("PLAYER_ENTERING_WORLD", "adar", AR.Settle)
Events.On("PLAYER_TARGET_CHANGED", "adar", function() AR.Recap(true) end)
Events.On("UNIT_PET", "adar", AR.OnPet)
Events.OnMessage("AD_DIRTY", "adar", function() Events.Coalesce("adar_sweep", AR.Sweep) end)
-- after every visibility pass: the pieces follow their group frame's alpha
Events.OnMessage("AD_VISIBILITY", "adar", function()
    for gid, gf in pairs(AR.placed) do
        local rt, g = AR.runtimes[gid], Store.Get(gid)
        if rt and g then AR.Mirror(g, rt, gf) end
    end
end)

if NS.LayoutEngine and NS.LayoutEngine.RegisterGroupClaim then
    NS.LayoutEngine.RegisterGroupClaim({ claims = AR.Claims, place = AR.Place, release = AR.Release })
end
