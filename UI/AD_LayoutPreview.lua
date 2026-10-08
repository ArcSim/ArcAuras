-- AD_LayoutPreview: a shared layout drawn small from its share string, with its
-- real icons and bar colours at their real places, for the New Layout cards.
-- It works on a decoded copy (Store.Peek) and never looks anything up in the account.
local ADDON, NS = ...

local LP = {}
NS.LayoutPreview = LP

-- Load When keys that pick one of several rows sharing a place: a druid form
-- or a warrior stance. Any other key (alive, combat) never hides a part.
LP.STATE_PREFIX = { "^form", "^stance" }
-- A part starting this far under everything above it opens a new cluster; the
-- picture shows the biggest one, so a reminder row parked far away stays out.
LP.GAP = 80
-- the inner part of an icon's art, without the baked-in edge
LP.CROP = 0.07
-- Bar kinds the picture leaves out: they show only while you cast or swing,
-- and the picture is the layout at rest.
LP.SKIP_BARS = { cast = true, swing = true }

-- parts per share string, worked out once
LP.cache = {}

-- A record's value: its own setting, else the schema default for its kind.
-- Layout looks are not followed (a shared layout carries its looks on the
-- items themselves).
function LP.Val(rec, section, field)
    local o = rec.o and rec.o[section]
    if o and o[field] ~= nil then return o[field] end
    local S = NS.Store
    local fam = NS.Schema[S.FamilyOf(rec)]
    local def = fam and fam[section] and fam[section].fields[field]
    if def and def.dk then
        local v = def.dk[S.KindOf(rec)]
        if v ~= nil then return v end
    end
    return def and def.d
end

function LP.StateKeys(rec)
    local out
    for k, on in pairs(rec.c and rec.c.loadWhen or {}) do
        if on and type(k) == "string" then
            for _, p in ipairs(LP.STATE_PREFIX) do
                if k:find(p) then
                    out = out or {}
                    out[k] = true
                end
            end
        end
    end
    return out
end

-- The form or stance the picture shows: the one of the group with the most
-- icons among those that swap by state (first in the string on a tie).
function LP.Scene(recs, members)
    local best, most
    for _, r in ipairs(recs) do
        local keys = r.type == "group" and LP.StateKeys(r)
        local n = keys and #(members[r.id] or {}) or 0
        if keys and (not most or n > most) then best, most = keys, n end
    end
    return best
end

function LP.Shows(rec, scene)
    local keys = LP.StateKeys(rec)
    if not keys or not scene then return true end
    for k in pairs(keys) do
        if scene[k] then return true end
    end
    return false
end

-- an icon record's art, or nil
function LP.IconArt(rec)
    local custom = LP.Val(rec, "appearance", "customIcon")
    if type(custom) == "number" and custom > 0 then return custom end
    local d = rec.driver or {}
    if d.itemID and C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(d.itemID)
    end
    if rec.kind == "trinket" and d.slotID and GetInventoryItemTexture then
        return GetInventoryItemTexture("player", d.slotID)
    end
    -- what the icon wears: an aura's first typed aura, a custom icon's art
    -- pick, else the spell it reads (the one resolve)
    local St, sid = NS.Store
    if rec.kind == "aura" or rec.kind == "groupbuff" then
        sid = St.TrackedAuraIDs(d)[1]
    elseif rec.kind == "timer" then
        sid = d.spellID -- raw-id: the custom icon's art pick
    else
        sid = St.RecordSpellID(d)
    end
    if sid and C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(sid)
    end
    return nil
end

-- A point of a rect { l, b, w, h }.
function LP.PointXY(r, point)
    local x = (point:find("LEFT") and r.l) or (point:find("RIGHT") and (r.l + r.w)) or (r.l + r.w / 2)
    local y = (point:find("BOTTOM") and r.b) or (point:find("TOP") and (r.b + r.h)) or (r.b + r.h / 2)
    return x, y
end

-- How a Dynamic cooldown group packs in play with every icon up: true to pack
-- columns (else rows), and the alignment along them; nil for a static grid or
-- an aura group (drawn as one row of its first icons). The engine's alignment
-- by grid shape (Engine.EffectiveAlignment), read here from the record alone.
LP.ALIGN_VALID = {
    horizontal = { left = true, center = true, right = true },
    vertical = { top = true, center = true, bottom = true },
    multi = { top = true, bottom = true, left = true, right = true, center_h = true, center_v = true },
}
LP.ALIGN_REMAP = {
    horizontal = { center_h = "center", center_v = "center", top = "left", bottom = "right" },
    vertical = { center_h = "center", center_v = "center", left = "top", right = "bottom" },
    multi = { center = "center_h" },
}

function LP.PackRule(g, rows, cols)
    if g.groupKind == "aura" or LP.Val(g, "arrangement", "dynamicLayout") ~= true then return nil end
    local a = LP.Val(g, "arrangement", "alignment") or "center"
    local shape = (rows <= 1 and "horizontal") or (cols <= 1 and "vertical") or "multi"
    if not LP.ALIGN_VALID[shape][a] then
        a = LP.ALIGN_REMAP[shape][a] or ((shape == "multi") and "center_h" or "center")
    end
    local byCol = shape == "vertical" or a == "top" or a == "bottom" or a == "center_v"
    if a == "center_h" or a == "center_v" then a = "center" end
    return byCol, a
end

-- A group's grid as the engine draws it (cells by gpos, a Dynamic cooldown
-- group's rows or columns packed and aligned as in play; an aura group as one
-- row of its first icons): its size and each icon's centre offset.
function LP.GroupShape(g, icons)
    local function A(f) return LP.Val(g, "arrangement", f) end
    local scale = math.floor((A("iconSize") or 36) + 0.5) / 36
    local slotW = math.floor((A("iconWidth") or 36) * scale + 0.5)
    local slotH = math.floor((A("iconHeight") or 36) * scale + 0.5)
    local base = A("spacing") or 2
    local sep = A("separateSpacing") == true
    local sx = sep and (A("spacingX") or base) or base
    local sy = sep and (A("spacingY") or base) or base
    local pad = A("containerPadding") or 0
    local cols = math.max(1, A("cols") or 6)
    local cells = {}
    if g.groupKind == "aura" then
        local n = math.min(#icons, cols)
        for i = 1, n do cells[#cells + 1] = { rec = icons[i], col = i - 1, row = 0 } end
        cols = math.max(1, n)
    else
        local occupied, pending = {}, {}
        for _, ic in ipairs(icons) do
            local gp = ic.gpos
            local key = gp and gp.row and gp.col and gp.col < cols and (gp.row * cols + gp.col) or nil
            if key and not occupied[key] then occupied[key] = ic else pending[#pending + 1] = ic end
        end
        for _, ic in ipairs(pending) do
            local k = 0
            while occupied[k] do k = k + 1 end
            occupied[k] = ic
        end
        for key, ic in pairs(occupied) do
            cells[#cells + 1] = { rec = ic, col = key % cols, row = math.floor(key / cols) }
        end
    end
    local rows = math.max(1, A("rows") or 1)
    for _, c in ipairs(cells) do
        if c.row + 1 > rows then rows = c.row + 1 end
    end
    local w = cols * slotW + (cols - 1) * sx + pad * 2
    local h = rows * slotH + (rows - 1) * sy + pad * 2
    local left, up = A("growthH") == "LEFT", A("growthV") == "UP"
    for _, c in ipairs(cells) do
        c.vc = left and (cols - 1 - c.col) or c.col
        c.vr = up and (rows - 1 - c.row) or c.row
        c.x = -w / 2 + pad + c.vc * (slotW + sx) + slotW / 2
        c.y = h / 2 - pad - c.vr * (slotH + sy) - slotH / 2
    end
    -- Dynamic: each row (or column) closes its holes against the aligned edge,
    -- or centred, in its screen order
    local byCol, mode = LP.PackRule(g, rows, cols)
    if mode then
        local lines = {}
        for _, c in ipairs(cells) do
            local li = byCol and c.vc or c.vr
            lines[li] = lines[li] or {}
            table.insert(lines[li], c)
        end
        for _, L in pairs(lines) do
            if byCol then
                table.sort(L, function(a, b) return a.vr < b.vr end)
                local span = #L * (slotH + sy) - sy
                local y0 = (mode == "top" and h / 2 - pad) or (mode == "bottom" and -h / 2 + pad + span) or span / 2
                for i, c in ipairs(L) do c.y = y0 - (i - 1) * (slotH + sy) - slotH / 2 end
            else
                table.sort(L, function(a, b) return a.vc < b.vc end)
                local span = #L * (slotW + sx) - sx
                local x0 = (mode == "left" and -w / 2 + pad) or (mode == "right" and w / 2 - pad - span) or -span / 2
                for i, c in ipairs(L) do c.x = x0 + (i - 1) * (slotW + sx) + slotW / 2 end
            end
        end
    end
    return { w = w, h = h, slotW = slotW, slotH = slotH, cells = cells, pad = pad }
end

-- Every shown group and bar as a rect in screen units around the screen
-- centre, anchors followed to shown targets the way the engine does (a
-- target that is not drawn leaves the part at its own place).
function LP.Parts(text)
    if LP.cache[text] ~= nil then return LP.cache[text] or nil end
    local payload = NS.Store.Peek(text)
    if not payload then
        LP.cache[text] = false
        return nil
    end
    local parts = LP.PartsOf(payload.records)
    LP.cache[text] = parts
    return parts
end

-- The same from records in hand (a string's, or the player's own layout with
-- the items it holds), read only and never cached.
function LP.PartsOf(records)
    local recs, byId, members = {}, {}, {}
    for _, r in ipairs(records) do
        if type(r) == "table" and r.id ~= nil then
            recs[#recs + 1] = r
            byId[r.id] = r
        end
    end
    for _, r in ipairs(recs) do
        if r.type == "group" then
            local list = {}
            for _, mid in ipairs(r.members or {}) do
                local m = byId[mid]
                if m and m.type == "icon" then list[#list + 1] = m end
            end
            members[r.id] = list
        end
    end
    local scene = LP.Scene(recs, members)
    local parts, byRec = {}, {}
    for _, r in ipairs(recs) do
        local lay = r.layoutId ~= nil and byId[r.layoutId]
        local drawn = (r.type == "group" or r.type == "bar") and LP.Shows(r, scene)
        local KH = r.type == "bar" and NS.Bars and NS.Bars.KINDS and NS.Bars.KINDS[r.barKind]
        if r.type == "bar" and LP.SKIP_BARS[r.barKind] then drawn = false end
        if drawn and not (KH and KH.noHolder) then
            local p = { rec = r, lay = lay }
            if r.type == "group" then
                p.shape = LP.GroupShape(r, members[r.id] or {})
                p.w, p.h = p.shape.w, p.shape.h
            else
                local sc = LP.Val(r, "size", "scale") or 1
                p.w = math.max(1, (LP.Val(r, "size", "width") or 193) * sc)
                p.h = math.max(1, (LP.Val(r, "size", "height") or 24) * sc)
            end
            parts[#parts + 1] = p
            byRec[r.id] = p
        end
    end
    local function Free(p)
        local lp = p.lay and p.lay.pos or {}
        local pos = p.rec.pos or {}
        local cx = (lp.x or 0) + (pos.x or 0)
        local cy = (lp.y or 0) + (pos.y or 0)
        p.l, p.b = cx - p.w / 2, cy - p.h / 2
    end
    local busy = {}
    local function Place(p)
        if p.l then return end
        if busy[p] then Free(p) return end
        busy[p] = true
        local r = p.rec
        local function N(f) return LP.Val(r, "anchor", f) end
        local kind = N("anchorTargetKind") or "group"
        local target = N("anchorEnabled") == true and kind ~= "frame" and kind ~= "mouse"
            and kind ~= "nameplate" and byRec[N("anchorTargetId") or 0]
        if target and target ~= p then
            Place(target)
            if N("anchorMatchWidth") == true or N("anchorMatchHeight") == true then
                local pad2 = (target.rec.type == "group" and kind == "group") and 2 * (target.shape.pad or 0) or 0
                if N("anchorMatchWidth") == true then
                    p.w = math.max(1, target.w - pad2 + (N("anchorMatchWidthAdjust") or 0))
                end
                if N("anchorMatchHeight") == true then
                    p.h = math.max(1, target.h - pad2 + (N("anchorMatchHeightAdjust") or 0))
                end
            end
            local src, dst = N("anchorSrcPoint") or "TOP", N("anchorDstPoint") or "BOTTOM"
            local tx, ty = LP.PointXY(target, dst)
            local sx = tx + (N("anchorOffsetX") or 0)
            local sy = ty + (N("anchorOffsetY") or 0)
            local fx, fy = LP.PointXY({ l = 0, b = 0, w = p.w, h = p.h }, src)
            p.l, p.b = sx - fx, sy - fy
        else
            Free(p)
        end
        busy[p] = nil
    end
    for _, p in ipairs(parts) do Place(p) end
    return parts
end

-- The biggest cluster of parts, top to bottom, and its bounds.
function LP.Cluster(parts)
    local list = {}
    for _, p in ipairs(parts) do list[#list + 1] = p end
    table.sort(list, function(a, b) return a.b + a.h > b.b + b.h end)
    local groups, cur, low = {}, nil, nil
    for _, p in ipairs(list) do
        if not cur or (p.b + p.h) < low - LP.GAP then
            cur = {}
            groups[#groups + 1] = cur
            low = p.b
        end
        cur[#cur + 1] = p
        if p.b < low then low = p.b end
    end
    local best
    for _, g in ipairs(groups) do
        if not best or #g > #best then best = g end
    end
    if not best then return nil end
    local l, r, t, b
    for _, p in ipairs(best) do
        l = (not l or p.l < l) and p.l or l
        r = (not r or p.l + p.w > r) and (p.l + p.w) or r
        t = (not t or p.b + p.h > t) and (p.b + p.h) or t
        b = (not b or p.b < b) and p.b or b
    end
    return best, l, r, t, b
end

-- Draws the layout into stage (w x h), centred and scaled to fit: bars as
-- their fill colour over a dark back, icons as their art. Returns true when
-- something was drawn.
function LP.Draw(stage, text, w, h)
    return LP.DrawParts(stage, LP.Parts(text), w, h)
end

function LP.DrawParts(stage, parts, w, h)
    if not parts or #parts == 0 then return false end
    local list, l, r, t, b = LP.Cluster(parts)
    if not list or r <= l or t <= b then return false end
    local s = math.min(w / (r - l), h / (t - b))
    local ox = math.floor((w - (r - l) * s) / 2)
    local oy = math.floor((h - (t - b) * s) / 2)
    local GC = NS.Options and NS.Options.GROUP_COLORS or {}
    local COL = NS.AT.COL
    local function Box(layer, sub, x0, y0, bw, bh)
        local tex = stage:CreateTexture(nil, layer, nil, sub)
        local px = ox + math.floor((x0 - l) * s + 0.5)
        local py = oy + math.floor((t - y0) * s + 0.5)
        tex:SetSize(math.max(1, math.floor(bw * s + 0.5)), math.max(1, math.floor(bh * s + 0.5)))
        tex:SetPoint("TOPLEFT", stage, "TOPLEFT", px, -py)
        return tex
    end
    for _, p in ipairs(list) do
        if p.rec.type == "bar" then
            local back = Box("ARTWORK", 0, p.l, p.b + p.h, p.w, p.h)
            back:SetColorTexture(0, 0, 0, 0.6)
            local c = LP.Val(p.rec, "fill", "color") or COL.arc
            local fill = Box("ARTWORK", 1, p.l, p.b + p.h, p.w, p.h)
            fill:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
        else
            local sh = p.shape
            local cx, cy = p.l + p.w / 2, p.b + p.h / 2
            for _, cell in ipairs(sh.cells) do
                local x0 = cx + cell.x - sh.slotW / 2
                local y0 = cy + cell.y + sh.slotH / 2
                local tex = Box("ARTWORK", 2, x0, y0, sh.slotW, sh.slotH)
                local art = LP.IconArt(cell.rec)
                if art then
                    tex:SetTexture(art)
                    tex:SetTexCoord(LP.CROP, 1 - LP.CROP, LP.CROP, 1 - LP.CROP)
                else
                    local c = NS.AT.Mute(GC[p.rec.groupKind] or COL.arc)
                    tex:SetColorTexture(c[1], c[2], c[3], 0.9)
                end
            end
        end
    end
    return true
end
