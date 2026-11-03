local _, ns = ...
if ns.shareOnly then return end

-- Tracked items on the game's own maps: the favorites (Settings, Favorites on the Map) and the Mark on Map item
-- (WorldPins.lua). Their spots on the World Map while it shows their zone, a plate per zone on a continent, and the
-- near ones on the minimap. Items inside one dungeon or raid share its entrance pin, which counts them. Hover names the
-- item and where it comes from; clicks go through to the map, so Ctrl+click drops the game's own pin there.
local T = ns.Theme
local C, U = T.C, T.U
local F = {}
ns.FavPins = F

-- an item icon's size on the World Map and on the minimap
local ICON, MINI_ICON = 16, 13
-- the minimap's width in yards at each zoom step, outdoors and indoors
local OUTDOOR = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { 300, 240, 180, 120, 80, 50 }

local byMap = {}
local dirty = true

local function S() return ns.settings or {} end
local function Mode() return S().favPins or "both" end
local function Look() return S().favLook or "icon" end

-- the items on the map: the favorites while Pins is on, less those taken off it (they stay favorites), and the Mark
-- on Map item whatever the setting
local function Tracked()
    local ids, out = {}, {}
    if ns.stopped then return out end
    local hidden = ns.db.favHidden or {}
    if Mode() ~= "off" then
        for id in pairs(ns.db.favorites or {}) do
            if not hidden[id] then ids[id] = true end
        end
    end
    local marked = ns.WorldPins and ns.WorldPins.Marked()
    if marked then ids[marked] = true end
    for id in pairs(ids) do out[#out + 1] = id end
    return out
end

-- each item's map records, made once from its spots and kept: the item data never changes in play, and a find of the
-- item drops them (FindsChanged). byMap holds its own spots by client map, gates its spots at dungeon entrances.
local records = {}
local function RecordsOf(id)
    local c = records[id]
    if c then return c end
    c = { byMap = {}, gates = {} }
    local seen = {}
    for _, s in ipairs(ns.UI.GameSpots(id)) do
        local key = s.m .. ":" .. s.x .. ":" .. s.y
        if not seen[key] then
            seen[key] = true
            if s.dungeon then
                c.gates[#c.gates + 1] = s
            else
                local list = c.byMap[s.m]
                if not list then
                    list = {}
                    c.byMap[s.m] = list
                end
                list[#list + 1] = { m = s.m, x = s.x, y = s.y, id = id, look = s.look, entry = s.entry, who = s.who }
            end
        end
    end
    records[id] = c
    return c
end

-- tracked items by client map: a record per spot, and one per dungeon entrance listing every item inside; ix numbers
-- the item for the pin thinning
local zoneCache
local function Build()
    dirty = false
    wipe(byMap)
    zoneCache = nil
    if not ns.db or not ns.UI or not ns.UI.GameSpots then return end
    local entrances = {}
    for ix, id in ipairs(Tracked()) do
        local c = RecordsOf(id)
        for m, recs in pairs(c.byMap) do
            local list = byMap[m]
            if not list then
                list = {}
                byMap[m] = list
            end
            for _, r in ipairs(recs) do
                r.ix = ix
                list[#list + 1] = r
            end
        end
        for _, s in ipairs(c.gates) do
            local key = s.m .. ":" .. s.x .. ":" .. s.y
            local g = entrances[key]
            if not g then
                g = { m = s.m, x = s.x, y = s.y, dungeon = s.dungeon, look = s.look, items = {}, ix = ix }
                entrances[key] = g
                local list = byMap[s.m]
                if not list then
                    list = {}
                    byMap[s.m] = list
                end
                list[#list + 1] = g
            end
            g.items[#g.items + 1] = { id = id, entry = s.entry }
        end
    end
    -- an entrance holding one favorite is that favorite's own pin
    for _, g in pairs(entrances) do
        if #g.items == 1 then g.id, g.entry = g.items[1].id, g.items[1].entry end
    end
end

local function Tip(p)
    local r = p.rec
    if not r then return end
    -- one item: the finder's own item tooltip, with where it comes from and the pin hint under the item's lines
    if not (r.items and #r.items > 1) then
        local tip = T.ItemTip(p, r.id)
        if not tip then return end
        local en, who = r.entry, r.who or (r.entry and r.entry.who)
        local from
        if en and en.rightText == nil then
            from = en.left
        elseif who and who.name then
            from = who.name .. (who.lv and (" (" .. who.lv .. ")") or "")
        end
        if from then tip:AddLine(from, 1, 1, 1) end
        if not p.mini then tip:AddLine("Ctrl+click to drop a map pin", T.RGB(C.dim)) end
        tip:Show()
        return
    end
    GameTooltip:SetOwner(p, "ANCHOR_RIGHT")
    if r.items and #r.items > 1 then
        GameTooltip:AddLine(r.dungeon, T.RGB(C.title))
        for _, it in ipairs(r.items) do
            local name, hex = ns.UI.ItemLabel(it.id)
            local who = it.entry and it.entry.who
            local qr, qg, qb = T.RGB(hex)
            GameTooltip:AddDoubleLine(name, who and who.name or "", qr, qg, qb, 0.8, 0.8, 0.8)
        end
    else
        local name, hex = ns.UI.ItemLabel(r.id)
        GameTooltip:AddLine(name, T.RGB(hex))
        -- where it comes from as its where line reads it (a dungeon's names the dungeon); a world drop's zone line
        -- names the mob kept there
        local en, who = r.entry, r.who or (r.entry and r.entry.who)
        local from
        if en and en.rightText == nil then
            from = en.left
        elseif who and who.name then
            from = who.name .. (who.lv and (" (" .. who.lv .. ")") or "")
        end
        if from then GameTooltip:AddLine(from, 1, 1, 1) end
    end
    if not p.mini then GameTooltip:AddLine("Ctrl+click to drop a map pin", T.RGB(C.dim)) end
    GameTooltip:Show()
end

-- the window's pin with an icon face on top; Style shows one or the other. Only hover is the pin's: a click is handed
-- on to the map under it, as the map's own pins do
local function NewPin(parent)
    local p = ns.UI.NewPin(parent)
    p:SetPropagateMouseClicks(true)
    local face = CreateFrame("Frame", nil, p)
    face:SetPoint("CENTER")
    face.icon = face:CreateTexture(nil, "ARTWORK")
    face.icon:SetAllPoints()
    face.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    face.edge = T.Border(face, C.gold, 1, "OVERLAY")
    p.face = face
    p.count = T.Text(p, 11, "FFFFFF")
    p.count:SetPoint("CENTER")
    p:SetScript("OnEnter", Tip)
    p:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        T.HideItemTip(self)
    end)
    p:SetScript("OnMouseUp", nil)
    return p
end

-- an entrance with several favorites wears the entrance look and their count; any other pin the item's icon, or the
-- window's dot for its source
-- a pin keeps its look until what it shows changes: kind (1 icon, 2 entrance count, 3 dot), what (item, count, look),
-- size, and styleGen (a refresh or an icon the game just sent); compared field by field, no key built per frame
local styleGen = 0
local function Style(p, r, size)
    local group = r.items ~= nil and #r.items > 1
    local icon = Look() == "icon" and not group
    local kind = icon and 1 or group and 2 or 3
    local what = icon and r.id or group and #r.items or r.look
    if p.sKind == kind and p.sWhat == what and p.sSize == size and p.sGen == styleGen then return end
    p.sKind, p.sWhat, p.sSize, p.sGen = kind, what, size, styleGen
    if icon then
        p.glow:Hide()
        p.ring:Hide()
        p.fill:Hide()
        p.core:Hide()
        p:SetSize(size + U(4), size + U(4))
        p.face:SetSize(size, size)
        p.face.icon:SetTexture(ns.UI.ItemIcon(r.id))
        local _, hex = ns.UI.ItemLabel(r.id)
        p.face.edge:SetColor(hex)
        p.face:Show()
        p.count:Hide()
    else
        ns.UI.StylePin(p, group and "entrance" or r.look)
        p.glow:Show()
        p.ring:Show()
        p.fill:Show()
        p.face:Hide()
        p.count:SetShown(group)
        if group then
            p.core:Hide()
            p.count:SetText(tostring(#r.items))
        end
    end
end

-- the World Map: pins on its canvas for the shown zone, undoing its zoom so they keep their size
local worldPins, taken, kept, thinFor = {}, {}, {}, {}
local hooked

-- a continent shows a plate on each of its zones that holds tracked items (the favorites on the map and the Mark on
-- Map item): up to three of their icons and a count past that; hover lists them, a click goes through to the map.
-- A plate stands on the zone's spot nearest the middle of its spots: a zone's map box reaches over its neighbours, so
-- the box's middle can lie in another zone, and the click would open that one.
local BADGE_ICONS, BADGE_LIST = 3, 12
local badges = {}

-- the zones holding tracked items, worked out once per build (a zoom calls back on every step): their items by name,
-- the spot a plate stands on, and the zone's map info, asked of the game once
local function Zones()
    if zoneCache then return zoneCache end
    zoneCache = {}
    local names = {}
    local function Name(id)
        local n = names[id]
        if not n then
            n = ns.UI.ItemLabel(id)
            names[id] = n
        end
        return n
    end
    for m, list in pairs(byMap) do
        if #list > 0 then
            local z = { m = m, ids = {}, has = {} }
            local sx, sy = 0, 0
            for _, r in ipairs(list) do
                sx, sy = sx + r.x, sy + r.y
                for _, it in ipairs(r.items or { r }) do
                    if it.id and not z.has[it.id] then
                        z.has[it.id] = true
                        z.ids[#z.ids + 1] = it.id
                    end
                end
            end
            local ax, ay, best = sx / #list, sy / #list, nil
            for _, r in ipairs(list) do
                local d = (r.x - ax) ^ 2 + (r.y - ay) ^ 2
                if not best or d < best then best, z.x, z.y = d, r.x, r.y end
            end
            table.sort(z.ids, function(a, b) return Name(a) < Name(b) end)
            z.info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
            zoneCache[#zoneCache + 1] = z
        end
    end
    return zoneCache
end

local function BadgeTip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.zone or "", T.RGB(C.title))
    for i, id in ipairs(b.ids) do
        if i > BADGE_LIST then
            GameTooltip:AddLine("and " .. (#b.ids - BADGE_LIST) .. " more", T.RGB(C.dim))
            break
        end
        local name, hex = ns.UI.ItemLabel(id)
        GameTooltip:AddLine(name, T.RGB(hex))
    end
    GameTooltip:Show()
end

local function NewBadge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:EnableMouse(true)
    -- a click is handed on to the map, so the continent still opens the zone under it
    b:SetPropagateMouseClicks(true)
    -- bare icons on the map, no frame around them
    b.faces = {}
    for i = 1, BADGE_ICONS do
        local f = CreateFrame("Frame", nil, b)
        f:SetSize(U(ICON), U(ICON))
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        -- each icon shows its item's tooltip; a click still goes on to the map
        f:EnableMouse(true)
        f:SetPropagateMouseClicks(true)
        f:SetScript("OnEnter", function(self) T.ItemTip(self, self.id) end)
        f:SetScript("OnLeave", function(self) T.HideItemTip(self) end)
        b.faces[i] = f
    end
    b.more = T.Text(b, 12, "FFFFFF")
    b.more:SetShadowOffset(1, -1)
    b:SetScript("OnEnter", BadgeTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function FillBadge(b, z)
    if b.z == z and b.gen == styleGen then return end
    b.z, b.gen = z, styleGen
    local ids = z.ids
    b.ids = ids
    local gap, k = U(2), math.min(#ids, BADGE_ICONS)
    for i, f in ipairs(b.faces) do
        f:SetShown(i <= k)
        f.id = ids[i]
        if i <= k then
            f.icon:SetTexture(ns.UI.ItemIcon(ids[i]))
            f:ClearAllPoints()
            f:SetPoint("LEFT", (i - 1) * (U(ICON) + gap), 0)
        end
    end
    local w = k * U(ICON) + (k - 1) * gap
    b.more:SetShown(#ids > k)
    if #ids > k then
        b.more:SetText("+" .. (#ids - k))
        b.more:ClearAllPoints()
        b.more:SetPoint("LEFT", w + gap, 0)
        w = w + gap + b.more:GetStringWidth()
    end
    b:SetSize(w, U(ICON))
end

-- The map's own layers start at frame level 2000 with the explored-area art, fog and quest areas, which are opaque
-- and would cover anything under them; the pins go on its dig-site layer, above that art and under its icons. Read
-- from the map's level table, never by calling its code.
local function PinLevel(wm, canvas)
    local mgr = wm.pinFrameLevelsManager
    local defs = mgr and mgr.definitions
    local def = defs and defs.PIN_FRAME_LEVEL_DIG_SITE
    if def and def.overrideType then def = defs[def.overrideType] end
    return (def and def.startLevel) or (canvas:GetFrameLevel() + 2100)
end
F.PinLevel = PinLevel

local function LayBadges(canvas, mapID, scale, cw, ch, level)
    local n = 0
    -- while the place counts are on, each zone's count row carries these icons itself (PlacePins.lua)
    if mapID and C_Map.GetMapRectOnMap and not (ns.PlacePins and ns.PlacePins.On()) then
        for _, z in ipairs(Zones()) do
            local info = #z.ids > 0 and z.info
            if info and info.parentMapID == mapID then
                local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(z.m, mapID)
                if minX and maxX and minY and maxY then
                    n = n + 1
                    local b = badges[n]
                    if not b then
                        b = NewBadge(canvas)
                        badges[n] = b
                    end
                    b.zone = info.name
                    FillBadge(b, z)
                    b:SetFrameLevel(level)
                    b:SetScale(1 / scale)
                    -- the first icon sits on the spot, the rest run to its right
                    local px = minX + z.x / 1000 * (maxX - minX)
                    local py = minY + z.y / 1000 * (maxY - minY)
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", canvas, "TOPLEFT", px * cw - U(ICON) / 2, -py * ch)
                    b.cx, b.cy = px * cw - U(ICON) / 2 + b:GetWidth() / 2, py * ch
                    b:Show()
                end
            end
        end
    end
    for i = n + 1, #badges do badges[i]:Hide() end
end

local function LayWorld()
    if dirty then Build() end
    local wm = WorldMapFrame
    local canvas = wm and wm.GetCanvas and wm:GetCanvas()
    local mapID = canvas and wm:IsShown() and wm:GetMapID()
    local list = mapID and byMap[mapID]
    local n = 0
    local scale = mapID and wm:GetCanvasScale()
    if not scale or scale <= 0 then scale = 1 end
    local cw, ch, level = 0, 0, 0
    if canvas then cw, ch, level = canvas:GetWidth() * scale, canvas:GetHeight() * scale, PinLevel(wm, canvas) end
    LayBadges(canvas, mapID, scale, cw, ch, level)
    if list then
        -- thinned again only when the zoom crosses a step of a quarter: a zoom animation calls back on every frame, and
        -- between steps the same pins only move. The step rounds down, so the pins are never thinned finer than the zoom
        -- shows them (no two overlap)
        local q = math.floor(math.log(scale) / math.log(1.25) + 1e-9)
        local w, h = canvas:GetWidth(), canvas:GetHeight()
        if thinFor.list ~= list or thinFor.q ~= q or thinFor.gen ~= styleGen or thinFor.w ~= w or thinFor.h ~= h then
            thinFor.list, thinFor.q, thinFor.gen, thinFor.w, thinFor.h = list, q, styleGen, w, h
            local qs = 1.25 ^ q
            local cell = Look() == "icon" and U(ICON) or ns.UI.PinCell()
            local cx, cy = cell / (w * qs) * 1000, cell / (h * qs) * 1000
            wipe(taken)
            wipe(kept)
            for _, r in ipairs(list) do
                -- one item's spots closer than a pin share it; other items keep their own (a number key, no text made
                -- per spot)
                local key = r
                if not (r.items and #r.items > 1) then key = r.ix * 1e12 + math.floor(r.x / cx) * 1e6 + math.floor(r.y / cy) end
                if not taken[key] then
                    taken[key] = true
                    kept[#kept + 1] = r
                end
            end
        end
        local size = U(ICON)
        for _, r in ipairs(kept) do
            n = n + 1
            local p = worldPins[n]
            if not p then
                p = NewPin(canvas)
                worldPins[n] = p
            end
            p.rec, p.m, p.x, p.y = r, r.m, r.x, r.y
            Style(p, r, size)
            p:SetFrameLevel(level)
            p:SetScale(1 / scale)
            p:ClearAllPoints()
            p.cx, p.cy = r.x / 1000 * cw, r.y / 1000 * ch
            p:SetPoint("CENTER", canvas, "TOPLEFT", p.cx, -p.cy)
            p:Show()
        end
    end
    for i = n + 1, #worldPins do worldPins[i]:Hide() end
    -- the place counts lay out after the favorites, around them
    if ns.PlacePins then ns.PlacePins.Lay() end
end

-- the favorites' plates and pins on the shown map, where the place counts must not stand: centre and size, in the
-- pins' own units
-- the tracked items of each zone, names in order, for the place counts' rows: { m = client map, ids }
function F.ZoneMarks()
    if dirty then Build() end
    return Zones()
end

function F.Obstacles()
    local out = {}
    for _, list in ipairs({ badges, worldPins }) do
        for _, f in ipairs(list) do
            if f:IsShown() and f.cx then out[#out + 1] = { x = f.cx, y = f.cy, w = f:GetWidth(), h = f:GetHeight() } end
        end
    end
    return out
end

local function Hook()
    local wm = WorldMapFrame
    if hooked == wm or not wm or not wm.GetCanvas then return end
    hooked = wm
    if wm.OnMapChanged then hooksecurefunc(wm, "OnMapChanged", LayWorld) end
    if wm.OnCanvasScaleChanged then hooksecurefunc(wm, "OnCanvasScaleChanged", LayWorld) end
    wm:HookScript("OnShow", LayWorld)
    wm:HookScript("OnShow", function() F.SyncMapButton() end)
end

-- the minimap: the favorites of the player's zone, re-placed only when the player moved, turned or zoomed
local miniPins, last = {}, {}
local zone, driver, rotate

local function HideMini(from)
    for i = from or 1, #miniPins do miniPins[i]:Hide() end
end

-- the player's place on the zone map, 0..1, from two plain numbers; the game's own reading when the worked-out one
-- did not match it
local function PlayerOnMap(z)
    if z.fallback then
        local pos = C_Map.GetPlayerMapPosition(z.map, "player")
        if not pos then return end
        return pos:GetXY()
    end
    local a, b = UnitPosition("player")
    if not a then return end
    if z.swap then a, b = b, a end
    a, b = a - z.ox, b - z.oy
    return z.c1 * a + z.c2 * b, z.c3 * a + z.c4 * b
end

local function MiniUpdate()
    local z = zone
    if not z then return end
    local mx, my = PlayerOnMap(z)
    local facing = rotate and GetPlayerFacing() or 0
    local zoom = Minimap:GetZoom() or 0
    local indoor = IsIndoors() and true or false
    local w = Minimap:GetWidth()
    if mx == last.x and my == last.y and facing == last.f and zoom == last.z and indoor == last.i and w == last.w then return end
    last.x, last.y, last.f, last.z, last.i, last.w = mx, my, facing, zoom, indoor, w
    if not mx or not facing or not w or w <= 0 then
        HideMini()
        return
    end
    local yards = (indoor and INDOOR or OUTDOOR)[zoom + 1] or OUTDOOR[1]
    local perYard = w / yards
    local edge = w / 2 - U(MINI_ICON) / 2
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local cs, sn = math.cos(facing), math.sin(facing)
    -- only the spots within reach: gathered again when the player has walked a quarter of the minimap's width from
    -- where they were gathered, or the zoom changed (a zone can hold thousands of spots; a frame looks at a few)
    local reach = yards * 0.75
    local dx, dy = ((z.nearX or -1e9) - mx) * z.wide, ((z.nearY or -1e9) - my) * z.tall
    if z.nearYards ~= yards or dx * dx + dy * dy > (yards / 4) ^ 2 then
        z.nearX, z.nearY, z.nearYards = mx, my, yards
        local near = z.near
        wipe(near)
        local far = (reach + yards / 4) ^ 2
        for _, r in ipairs(z.list) do
            local east, north = (r.x / 1000 - mx) * z.wide, (my - r.y / 1000) * z.tall
            if east * east + north * north <= far then near[#near + 1] = r end
        end
    end
    local n = 0
    local size = U(MINI_ICON)
    for _, r in ipairs(z.near) do
        local east, north = (r.x / 1000 - mx) * z.wide, (my - r.y / 1000) * z.tall
        -- a turning minimap keeps the player's facing up: the spots turn the other way
        if rotate then east, north = east * cs + north * sn, north * cs - east * sn end
        local sx, sy = east * perYard, north * perYard
        local inside
        if square then inside = math.abs(sx) <= edge and math.abs(sy) <= edge else inside = sx * sx + sy * sy <= edge * edge end
        if inside then
            n = n + 1
            local p = miniPins[n]
            if not p then
                p = NewPin(Minimap)
                p.mini = true
                miniPins[n] = p
            end
            p.rec = r
            Style(p, r, size)
            p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
            p:ClearAllPoints()
            p:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
            p:Show()
        end
    end
    HideMini(n + 1)
end

-- a zone with favorites runs the minimap check every frame; any other zone, or an instance, runs nothing
local function SetupMini()
    if dirty then Build() end
    zone = nil
    local m = Mode() == "both" and Minimap and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local list = m and byMap[m]
    if list and #list > 0 and C_Map.GetWorldPosFromMapPos and C_Map.GetMapWorldSize and C_Map.GetPlayerMapPosition then
        -- the map's corner and its two edges in world coordinates turn a world position into the map's 0..1
        local _, o = C_Map.GetWorldPosFromMapPos(m, CreateVector2D(0, 0))
        local _, ex = C_Map.GetWorldPosFromMapPos(m, CreateVector2D(1, 0))
        local _, ey = C_Map.GetWorldPosFromMapPos(m, CreateVector2D(0, 1))
        local wide, tall = C_Map.GetMapWorldSize(m)
        local ax, ay = ex and o and ex.x - o.x, ex and o and ex.y - o.y
        local bx, by = ey and o and ey.x - o.x, ey and o and ey.y - o.y
        local det = ax and bx and (ax * by - ay * bx)
        if det and det ~= 0 and wide and wide > 0 and tall and tall > 0 then
            local z = { map = m, list = list, near = {}, wide = wide, tall = tall, ox = o.x, oy = o.y,
                c1 = by / det, c2 = -bx / det, c3 = -ay / det, c4 = ax / det }
            -- checked once against the game's own reading; the other order of the two numbers, else the game's reading
            local pos = C_Map.GetPlayerMapPosition(m, "player")
            local px, py
            if pos then px, py = pos:GetXY() end
            local function Off()
                local mx, my = PlayerOnMap(z)
                return not mx or math.abs(mx - px) > 0.01 or math.abs(my - py) > 0.01
            end
            if px and Off() then
                z.swap = true
                if Off() then z.swap, z.fallback = nil, true end
            end
            zone = z
        end
    end
    wipe(last)
    if zone then
        if not driver then driver = CreateFrame("Frame", nil, Minimap) end
        driver:SetScript("OnUpdate", MiniUpdate)
    else
        if driver then driver:SetScript("OnUpdate", nil) end
        HideMini()
    end
end

-- a favorite is already on the World Map, so Show on World Map leaves its spots to these icons
function F.Covers(id)
    return id ~= nil and Mode() ~= "off" and ns.db ~= nil and ns.db.favorites ~= nil and ns.db.favorites[id] == true and
        not (ns.db.favHidden and ns.db.favHidden[id])
end

-- the World Map's own button under the game's two at its top right: what the place counts count (while they are on,
-- PlacePins.lua), then a list of every item with marks on the map, a tick box each. A favorite taken off the map
-- stays a favorite (ns.db.favHidden); the Mark on Map item comes off.
local mapBtn, panel
local ROW = U(22)

local function Listed()
    local out = {}
    if ns.stopped then return out end
    local marked = ns.WorldPins and ns.WorldPins.Marked()
    -- with Pins off in Settings no favorite is on the map to choose from
    for id in pairs(Mode() ~= "off" and ns.db and ns.db.favorites or {}) do
        if id ~= marked then out[#out + 1] = { id = id, fav = true, name = ns.UI.ItemLabel(id) } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    if marked then table.insert(out, 1, { id = marked, name = ns.UI.ItemLabel(marked) }) end
    return out
end

local function IsShownOnMap(item)
    if item.fav then return Mode() ~= "off" and not (ns.db.favHidden and ns.db.favHidden[item.id]) end
    return ns.WorldPins and ns.WorldPins.Marked() == item.id
end

local function CountsOn() return ns.PlacePins ~= nil and ns.PlacePins.On() end

local function FillPanel()
    if not panel or not panel:IsShown() then return end
    local items = Listed()
    local top = 0
    local counts = CountsOn()
    panel.countsTitle:SetShown(counts)
    for i, r in ipairs(panel.countRows) do
        r:SetShown(counts)
        if counts then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", U(2), -(U(30) + (i - 1) * ROW))
            r:SetPoint("TOPRIGHT", -U(2), -(U(30) + (i - 1) * ROW))
            r.tick:SetShown(ns.PlacePins.IsShown(r.key))
        end
    end
    if counts then top = U(30) + #panel.countRows * ROW + U(6) end
    local marks = #items > 0
    panel.marksTitle:SetShown(marks)
    panel.list:SetShown(marks)
    panel.marksTitle:ClearAllPoints()
    panel.marksTitle:SetPoint("TOPLEFT", U(10), -(top + U(8)))
    panel.list:ClearAllPoints()
    panel.list:SetPoint("TOPLEFT", U(2), -(top + U(30)))
    panel.list:SetPoint("BOTTOMRIGHT", -U(2), U(6))
    local n = marks and math.max(1, math.min(#items, 10)) or 0
    panel:SetHeight(marks and (top + U(30) + n * ROW + U(8)) or (top + U(4)))
    if marks then panel.list:SetData(items) end
end

local function Toggle(item)
    if item.fav then
        ns.db.favHidden = ns.db.favHidden or {}
        ns.db.favHidden[item.id] = (not ns.db.favHidden[item.id]) or nil
    elseif ns.WorldPins then
        ns.WorldPins.Clear()
    end
    F.Refresh()
    if ns.UI.SetWorldBtn and ns.UI.detail and ns.UI.detail.worldBtn then ns.UI.SetWorldBtn() end
end

local function MakeRow(list)
    local r = CreateFrame("Button", nil, list)
    T.Hover(r, C.sel, true)
    r.box = CreateFrame("Frame", nil, r)
    r.box:SetSize(U(12), U(12))
    r.box:SetPoint("LEFT", U(8), 0)
    T.Panel(r.box, C.input, C.inputLine)
    r.tick = T.Solid(r.box, "ARTWORK", C.gold)
    r.tick:SetPoint("TOPLEFT", U(3), -U(3))
    r.tick:SetPoint("BOTTOMRIGHT", -U(3), U(3))
    r.face = CreateFrame("Frame", nil, r)
    r.face:SetSize(U(16), U(16))
    r.face:SetPoint("LEFT", U(26), 0)
    r.icon = r.face:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.edge = T.Border(r.face, C.gold, 1, "OVERLAY")
    r.text = T.Text(r, 13, C.ink)
    r.text:SetPoint("LEFT", r.face, "RIGHT", U(6), 0)
    r.text:SetPoint("RIGHT", -U(6), 0)
    r.text:SetJustifyH("LEFT")
    r:SetScript("OnClick", function(self)
        if self.item then Toggle(self.item) FillPanel() end
    end)
    return r
end

local function BindRow(r, item)
    r.item = item
    local name, hex = ns.UI.ItemLabel(item.id)
    r.icon:SetTexture(ns.UI.ItemIcon(item.id))
    r.edge:SetColor(hex)
    r.text:SetText(name)
    r.text:SetTextColor(T.RGB(hex))
    r.tick:SetShown(IsShownOnMap(item))
end

local function BuildMapButton(wm, container)
    mapBtn = CreateFrame("Button", nil, wm)
    mapBtn:SetSize(31, 31)
    mapBtn:SetFrameLevel(container:GetFrameLevel() + 50)
    local icon = mapBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ns.MEDIA .. "FIF_Minimap")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local mask = mapBtn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local ring = mapBtn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    mapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever Item Finder", 1, 1, 1)
        GameTooltip:AddLine("Choose what shows on the map", T.RGB(C.dim))
        GameTooltip:Show()
    end)
    mapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel = CreateFrame("Frame", nil, mapBtn)
    panel:SetWidth(U(250))
    panel:SetPoint("TOPRIGHT", mapBtn, "TOPLEFT", -U(4), 0)
    -- the map's own icons sit thousands of levels up on its canvas; the panel goes over all of them
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:EnableMouse(true)
    T.Panel(panel, C.bg, C.gold)
    panel.countsTitle = T.Text(panel, 13, C.title)
    panel.countsTitle:SetPoint("TOPLEFT", U(10), -U(8))
    panel.countsTitle:SetText("Item counts")
    panel.countRows = {}
    for i, o in ipairs(ns.PlacePins and ns.PlacePins.ShowOptions() or {}) do
        local r = CreateFrame("Button", nil, panel)
        r:SetHeight(ROW)
        T.Hover(r, C.sel, true)
        r.box = CreateFrame("Frame", nil, r)
        r.box:SetSize(U(12), U(12))
        r.box:SetPoint("LEFT", U(8), 0)
        T.Panel(r.box, C.input, C.inputLine)
        r.tick = T.Solid(r.box, "ARTWORK", C.gold)
        r.tick:SetPoint("TOPLEFT", U(3), -U(3))
        r.tick:SetPoint("BOTTOMRIGHT", -U(3), U(3))
        r.text = T.Text(r, 13, C.ink)
        r.text:SetPoint("LEFT", r.box, "RIGHT", U(8), 0)
        r.text:SetText(o[2])
        r.key = o[1]
        r:SetScript("OnClick", function(self)
            ns.PlacePins.ToggleShow(self.key)
            FillPanel()
        end)
        panel.countRows[i] = r
    end
    panel.marksTitle = T.Text(panel, 13, C.title)
    panel.marksTitle:SetText("Marks on your map")
    panel.list = T.List(panel, ROW, MakeRow, BindRow)
    panel:Hide()
    mapBtn:SetScript("OnClick", function()
        panel:SetShown(not panel:IsShown())
        FillPanel()
    end)
    F.mapBtn, F.panel = mapBtn, panel
end

-- under the game's own buttons, however many it shows; only while something is marked
local function SyncMapButton()
    local wm = WorldMapFrame
    local container = wm and wm.GetCanvasContainer and wm:GetCanvasContainer()
    if not container then return end
    if not mapBtn then BuildMapButton(wm, container) end
    local below = (wm.WorldMapTrackingOptionsButton and 1 or 0) + (wm.WorldMapTrackingPinButton and 1 or 0)
    mapBtn:ClearAllPoints()
    mapBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -2 - 32 * below)
    local any = #Listed() > 0 or CountsOn()
    mapBtn:SetShown(any)
    if not any then panel:Hide() end
    FillPanel()
end
F.SyncMapButton = SyncMapButton

function F.Refresh()
    dirty = true
    styleGen = styleGen + 1
    Hook()
    LayWorld()
    SetupMini()
    SyncMapButton()
end

-- read by the developer's probe (DevProbe.lua); nothing here changes them
function F.State()
    return { hooked = hooked, dirty = dirty, byMap = byMap, records = records, worldPins = worldPins, badges = badges,
        tracked = Tracked() }
end

ns.Listen("FavoritesChanged", F.Refresh)
ns.Listen("Login", function()
    rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    F.Refresh()
end)
local function IsTracked(id)
    return id ~= nil and ns.db ~= nil and ((ns.db.favorites and ns.db.favorites[id]) or (ns.WorldPins and ns.WorldPins.Marked() == id))
end
-- events in bursts (the game sends every favorite's item data at once after login or a reveal; finds arrive from the
-- network) cost one redraw on the next frame, not one each
local soon, rebuild
local function Later()
    if soon then return end
    soon = true
    C_Timer.After(0, function()
        soon = false
        if rebuild then
            rebuild = false
            F.Refresh()
        else
            styleGen = styleGen + 1
            zoneCache = nil
            LayWorld()
            wipe(last)
        end
    end)
end
-- a find of a tracked item can bring a new spot: its records are made again
ns.Listen("FindsChanged", function(e)
    if e and IsTracked(e.id) then
        records[e.id] = nil
        rebuild = true
        Later()
    end
end)
-- an icon or name the game had not sent yet: the pins take it, nothing is rebuilt
ns.On("GET_ITEM_INFO_RECEIVED", function(id)
    if IsTracked(id) then Later() end
end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" then Hook() end
end)
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, function() if ns.db then SetupMini() end end)
end
ns.On("CVAR_UPDATE", function(name)
    if name == "rotateMinimap" or name == "ROTATE_MINIMAP" then
        rotate = GetCVar("rotateMinimap") == "1"
        wipe(last)
    end
end)
