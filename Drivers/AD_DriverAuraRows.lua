-- AD_DriverAuraRows: Dynamic aura groups in play. Every icon is its own piece
-- (one AuraContainer with one aura group), and each grid row (or column) lines
-- its pieces up in the editor's order, packed and aligned. The editor's grid is
-- unchanged: with the options window open the layout engine draws it.
-- The game reads the auras and sizes every piece, so it works in combat:
-- nothing here reads an aura, a rect or a size. Pieces anchor only to pieces
-- or to the group frame (a container with aura groups refuses other frames).
local ADDON, NS = ...
local Store, Events = NS.Store, NS.Events

local AR = {
    runtimes = {},   -- [groupId] = { pieces = { [recId] = piece }, copies = { [recId] = piece } }
    pool = { player = {}, target = {}, pet = {} },   -- pieces no group uses, by unit
    placed = {},     -- [groupId] = its group frame while the engine draws it
    pending = false, -- a piece, a filter or a restyle waits for the settle edge
    loadWindowOver = false,
}
NS.DriverAuraRows = AR

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

-- One container following `unit` with one parked aura group. Its buttons are
-- sized and dressed as the game makes them, from what the piece holds then.
function AR.Make(unit)
    if not AR.CanMake() then
        AR.pending = true
        return nil
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local c = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraGroup) ~= "function" then
        if c then c:Hide() end
        return nil
    end
    local G, DA = NS.DriverAuraGroups, NS.DriverAura
    -- shaped like a member-row runtime, so the shared styler reads it as one
    local p = { c = c, unit = unit, buttons = {}, slotRecs = {}, slotDims = {},
        cfg = { iconW = 36, iconH = 36 }, engines = { c } }
    c:SetSize(1, 1)
    c:SetUnit(unit)
    c:SetEnabled(true)
    c:EnableMouse(false)
    c:Hide()
    c:AddAuraGroup(AR.KEY, AR.BASE[unit], {
        maxFrameCount = 0,
        candidateFilters = { includeSpellIDs = G.ParkMap() },
        initializeFrame = function(b)
            if DA and DA.WireButton then DA.WireButton(b) end
            b:SetSize(p.cfg.iconW, p.cfg.iconH)
            b._adAppliedW, b._adAppliedH = p.cfg.iconW, p.cfg.iconH
            b._adSlotIndex = 1
            b:EnableMouse(false)
            if not b._adCollected then
                b._adCollected = true
                p.buttons[#p.buttons + 1] = b
            end
            if not p.copy then G.StyleSlotButton(b, p) end
        end,
        layout = { elementSpacing = 0, lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0 },
    })
    p.sent = { sig = DA.FilterSig(G.ParkMap()), filter = AR.BASE[unit], cap = 0 }
    return p
end

function AR.Take(unit)
    local list = AR.pool[unit]
    local p = list[#list]
    if p then
        list[#list] = nil
        return p
    end
    return AR.Make(unit)
end

-- Back to the pool, hidden; its filter parks now, or at the settle edge.
function AR.Give(p)
    p.c:Hide()
    p.c:ClearAllPoints()
    p.c:SetScale(1)
    p.rec, p.slotRecs[1], p.copy, p.shape = nil, nil, nil, nil
    if AR.Send(p, nil) then AR.pending = true end
    local list = AR.pool[p.unit]
    list[#list + 1] = p
end

-- The piece's filter, ids and frame cap for rec (nil parks it), out of combat
-- only. True when it has to wait.
function AR.Send(p, rec)
    local G, DA = NS.DriverAuraGroups, NS.DriverAura
    local ids, fstr, exempt = G.ParkMap(), AR.BASE[p.unit], false
    if rec then
        local i, f, e = G.MemberMapFor(rec, p.unit)
        if i and i[0] == nil then ids, fstr, exempt = i, f or fstr, e end
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

-- A piece's cell is its icon plus the spacing after it along the direction it
-- packs (elementWidth in a row, elementHeight in a column), so pieces touch
-- and the spacing still falls between icons; an empty piece is one unit long.
-- grow: "right" / "left" in a row, "down" / "up" in a column, the side its
-- buttons flow toward from the opposite corner.
AR.CORNER = { right = "TOPLEFT", left = "TOPRIGHT", down = "TOPLEFT", up = "BOTTOMLEFT" }

function AR.Shape(p, w, h, sx, sy, grow)
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
-- unit is the same, else taken from the pool; nil while none can be made.
function AR.Piece(set, rec, unit)
    local p = set[rec.id]
    if p and p.unit ~= unit then
        AR.Give(p)
        set[rec.id] = nil
        p = nil
    end
    if not p then
        p = AR.Take(unit)
        if not p then return nil end
        set[rec.id] = p
    end
    p.rec, p.slotRecs[1] = rec, rec
    return p
end

-- The half-scale copy of a line (same units, filters, caps and cells), built
-- from the line's far end back, each copy placed by place(q, previous); the
-- copy nearest the line's start, or nil while one can't be made yet (made at
-- the settle edge).
function AR.CopyLine(rt, list, keepCopy, grid, grow, place)
    local prevq, q1
    for i = #list, 1, -1 do
        local e = list[i]
        local q = AR.Piece(rt.copies, e.rec, e.unit)
        if not q then return nil end
        q.copy = true
        keepCopy[e.rec.id] = true
        q.cfg.iconW, q.cfg.iconH = e.w, e.h
        if AR.Send(q, e.rec) then AR.pending = true end
        AR.Shape(q, e.w, e.h, grid.sx, grid.sy, grow)
        q.c:SetScale(AR.COPY_SCALE)
        q.c:ClearAllPoints()
        place(q, prevq)
        prevq, q1 = q, q
    end
    return q1
end

-- One row, its pieces in screen order (left to right). Right chains leftward
-- from the right edge; Left and Center rightward, Center from the left edge
-- of the row's half-scale copy, which ends on the group's middle. The trailing
-- spacing in every cell is split off the center by sx / 2.
function AR.LayRow(rt, gf, grid, list, align, rowY, keepCopy)
    local sx, sy = grid.sx, grid.sy
    local n = #list
    if align == "right" then
        local prev
        for i = n, 1, -1 do
            local e = list[i]
            AR.Shape(e.p, e.w, e.h, sx, sy, "left")
            e.p.c:ClearAllPoints()
            if prev then
                e.p.c:SetPoint("TOPRIGHT", prev.c, "TOPLEFT", 0, 0)
            else
                e.p.c:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -grid.pad, rowY)
            end
            prev = e.p
        end
        return
    end
    for _, e in ipairs(list) do AR.Shape(e.p, e.w, e.h, sx, sy, "right") end
    local first = list[1].p.c
    first:ClearAllPoints()
    if align == "left" then
        first:SetPoint("TOPLEFT", gf, "TOPLEFT", grid.pad, rowY)
    elseif n == 1 then
        first:SetPoint("TOP", gf, "TOP", sx / 2, rowY)
    else
        local q1 = AR.CopyLine(rt, list, keepCopy, grid, "left", function(q, prevq)
            if prevq then
                q.c:SetPoint("TOPRIGHT", prevq.c, "TOPLEFT", 0, 0)
            else
                -- offsets are in the copy's own (half) scale
                q.c:SetPoint("TOPRIGHT", gf, "TOP", 0, rowY / AR.COPY_SCALE)
            end
        end)
        if q1 then
            first:SetPoint("TOPLEFT", q1.c, "TOPLEFT", sx / 2, 0)
        else
            first:SetPoint("TOPLEFT", gf, "TOP", 0, rowY)
        end
    end
    for i = 2, n do
        local c = list[i].p.c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", list[i - 1].p.c, "TOPRIGHT", 0, 0)
    end
end

-- One column, its pieces in screen order (top to bottom), at the column's own
-- x (colX = its left edge). Up chains downward from the top edge, Down upward
-- from the bottom edge; Center downward from the top of the column's
-- half-scale copy, which stands on the group's vertical middle. The trailing
-- spacing in every cell is split off the center by sy / 2.
function AR.LayCol(rt, gf, grid, list, align, colX, keepCopy)
    local sx, sy = grid.sx, grid.sy
    local n = #list
    if align == "bottom" then
        local prev
        for i = n, 1, -1 do
            local e = list[i]
            AR.Shape(e.p, e.w, e.h, sx, sy, "up")
            e.p.c:ClearAllPoints()
            if prev then
                e.p.c:SetPoint("BOTTOMLEFT", prev.c, "TOPLEFT", 0, 0)
            else
                e.p.c:SetPoint("BOTTOMLEFT", gf, "BOTTOMLEFT", colX, grid.pad)
            end
            prev = e.p
        end
        return
    end
    for _, e in ipairs(list) do AR.Shape(e.p, e.w, e.h, sx, sy, "down") end
    local first = list[1].p.c
    first:ClearAllPoints()
    if align == "top" then
        first:SetPoint("TOPLEFT", gf, "TOPLEFT", colX, -grid.pad)
    elseif n == 1 then
        first:SetPoint("LEFT", gf, "LEFT", colX, -sy / 2)
    else
        local mid = colX + grid.w / 2
        local q1 = AR.CopyLine(rt, list, keepCopy, grid, "up", function(q, prevq)
            if prevq then
                q.c:SetPoint("BOTTOM", prevq.c, "TOP", 0, 0)
            else
                -- offsets are in the copy's own (half) scale
                q.c:SetPoint("BOTTOM", gf, "LEFT", mid / AR.COPY_SCALE, 0)
            end
        end)
        if q1 then
            first:SetPoint("TOP", q1.c, "TOP", 0, -sy / 2)
        else
            first:SetPoint("TOPLEFT", gf, "LEFT", colX, 0)
        end
    end
    for i = 2, n do
        local c = list[i].p.c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", list[i - 1].p.c, "BOTTOMLEFT", 0, 0)
    end
end

-- Shown with the group frame, its fade and level carried over; copies never show.
function AR.Mirror(g, rt, gf)
    local G = NS.DriverAuraGroups
    local on = AR.placed[g.id] ~= nil and Store.IsLoaded(g) and gf ~= nil and gf:IsShown()
    for _, p in pairs(rt.pieces) do G.MirrorOnto(p.c, gf, on) end
    for _, q in pairs(rt.copies) do
        G.MirrorOnto(q.c, gf, on)
        q.c:SetAlpha(0)
    end
end

function AR.Place(g, gf, editMode)
    local G = NS.DriverAuraGroups
    local grid = AR.Grid(g, AR.Members(g))
    gf:SetSize(math.max(grid.boxW, 4), math.max(grid.boxH, 4))
    AR.placed[g.id] = gf
    local rt = AR.runtimes[g.id] or { pieces = {}, copies = {} }
    AR.runtimes[g.id] = rt
    local axis, align = AR.Pack(g)
    local vertical = axis == "vertical"
    -- a line is a row (Horizontal) or a column (Vertical)
    local rows, keep = {}, {}
    for _, cell in ipairs(grid.cells) do
        local unit = AR.UnitOf(cell.rec)
        local p = unit and AR.Piece(rt.pieces, cell.rec, unit)
        if p then
            keep[cell.rec.id] = true
            local w, h = AR.Dims(cell.rec, grid)
            p.cfg.iconW, p.cfg.iconH = w, h
            p.slotDims[1] = { w = w, h = h }
            if AR.Send(p, cell.rec) then AR.pending = true end
            local line = vertical and cell.col or cell.row
            rows[line] = rows[line] or {}
            table.insert(rows[line], { p = p, rec = cell.rec, unit = unit, row = cell.row, col = cell.col, w = w, h = h })
        end
    end
    for id, p in pairs(rt.pieces) do
        if not keep[id] then
            AR.Give(p)
            rt.pieces[id] = nil
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
    for _, p in pairs(rt.pieces) do
        if G.StyleButtons(p) then AR.pending = true end
    end
    AR.Mirror(g, rt, gf)
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
    AR.runtimes[gid] = nil
end

-- Target swaps: re-cap the hostility gate on every target piece and copy, then
-- rescan. An unknown (secret) answer keeps the caps the last plain one set.
function AR.Recap(rescan)
    local G = NS.DriverAuraGroups
    local honored = G.TargetFiltersHonored()
    for _, rt in pairs(AR.runtimes) do
        for _, set in ipairs({ rt.pieces, rt.copies }) do
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
        for _, set in ipairs({ rt.pieces, rt.copies }) do
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
        for _, list in pairs(AR.pool) do
            for _, p in ipairs(list) do AR.Send(p, nil) end
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
    for _, layout in ipairs(Store.Layouts()) do
        for _, g in ipairs((Store.ChildrenOf(layout))) do
            if AR.On(g) then
                local grid = AR.Grid(g, AR.Members(g))
                local rows = {}
                for _, cell in ipairs(grid.cells) do
                    local unit = AR.UnitOf(cell.rec)
                    if unit then
                        need[unit] = need[unit] + 1
                        local line = AR.Pack(g) == "vertical" and cell.col or cell.row
                        rows[line] = rows[line] or {}
                        table.insert(rows[line], unit)
                    end
                end
                if select(2, AR.Pack(g)) == "center" then
                    for _, units in pairs(rows) do
                        if #units > 1 then
                            for _, unit in ipairs(units) do need[unit] = need[unit] + 1 end
                        end
                    end
                end
            end
        end
    end
    for unit, n in pairs(need) do
        while #AR.pool[unit] < n do
            local p = AR.Make(unit)
            if not p then break end
            table.insert(AR.pool[unit], p)
        end
    end
end

Events.On("PLAYER_LOGIN", "adar_lw", function() AR.loadWindowOver = true end)
Events.On("PLAYER_REGEN_ENABLED", "adar", AR.Settle)
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
