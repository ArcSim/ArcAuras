local _, ns = ...
if ns.shareOnly then return end

-- Place counts on the game's World Map. A continent shows one row per zone: the icons of the player's marked items
-- there, then our mark and the count of its items (its own and its dungeons' together, each item once); an opened
-- zone shows its own marker at the top and one on each dungeon entrance.
-- Settings: placePins on / off, placeShow picks what counts (new, changed, Classic, marked items whatever their kind).
-- The markers are our own frames on the map's canvas. A continent marker hands its click on to the map, which opens
-- the zone itself (moving the map from addon code would taint it); the zone's own marker and an entrance marker open
-- the Item Database on that place (UI.ShowPlace).
local D, T = ns.Data, ns.Theme
local C, U = T.C, T.U
local P = {}
ns.PlacePins = P

local KINDS = { "n", "c", "o" }
local SHOW_ORDER = { { "n", "New" }, { "c", "Changed" }, { "o", "Classic" }, { "f", "Marked" } }
local NOUN = { n = "new", c = "changed", o = "Classic", f = "marked" }
local PIC, H, GAP = 16, 20, 4
local MARK_ICONS, MARK_LIST = 3, 12
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
local RAID_EDGE, GATE_EDGE, ZONE_EDGE = C.redTop, C.gold, C.frame

local function S() return ns.settings or {} end
local function On() return S().placePins == "on" and not ns.stopped end
local function Shown()
    local s = S().placeShow
    if type(s) ~= "table" then s = ns.DEFAULTS.placeShow end
    return s
end

-- n new (hidden included), o an old Classic item, c every other change: the same three the data counts
local function KindOf(kind) return kind == "o" and "o" or ((kind == "n" or kind == "x") and "n" or "c") end

-- the client's map for one of Forever's (a retail test run moves them; a map it has no match for drops out)
local function ClientSpot(m, x, y)
    if not m then return end
    if ns.UI and ns.UI.ClientSpot then return ns.UI.ClientSpot(m, x or 500, y or 500) end
    return m, x, y
end

-- the zone a client map belongs to: itself or the ancestor right under a continent, asked of the game once per map
local zoneOf = {}
local function ZoneOf(m)
    if not m then return end
    local z = zoneOf[m]
    if z ~= nil then return z or nil end
    local cur = m
    for _ = 1, 8 do
        local info = cur and C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
        if not info then break end
        local parent = info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
        if parent and parent.mapType == CONTINENT then z = cur break end
        cur = info.parentMapID
    end
    zoneOf[m] = z or false
    return z
end

local function NewCounts() return { n = { 0, 0, 0, 0 }, c = { 0, 0, 0, 0 }, o = { 0, 0, 0, 0 } } end
local function Triple(s)
    local a, b, c = (s or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

-- the places: zones[clientMap] = { own = counts per kind {items, world, mob, quest}, all = {n, c, o}, marksOwn,
-- marksAll, gates = {names} }, dungeons[name] = { zone, t = {n, c, o}, raid, m, x, y, marks }. The shipped counts
-- (Data\Places.lua) plus finds of items with no known place, rebuilt only after a change
local places, dirty = nil, true

local function Zone(z)
    local e = places.zones[z]
    if not e then
        e = { own = NewCounts(), all = { n = 0, c = 0, o = 0 }, marksOwn = {}, marksAll = {}, gates = {} }
        places.zones[z] = e
    end
    return e
end

local function Dungeon(name)
    local e = places.dungeons[name]
    if not e then
        local d = D.DungeonNamed(name)
        local m, x, y = ClientSpot(d and d.m, d and d.x, d and d.y)
        e = { name = name, zone = ZoneOf(m), t = { n = 0, c = 0, o = 0 }, raid = d and d.raid or false, m = m, x = x, y = y,
            marks = {} }
        places.dungeons[name] = e
        if e.zone then table.insert(Zone(e.zone).gates, name) end
    end
    return e
end

local function LoadShipped()
    for line in (D.places or ""):gmatch("[^\n]+") do
        local f = {}
        for v in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
        if f[1] == "z" then
            local z = ZoneOf(ClientSpot(tonumber(f[2])))
            if z then
                local e = Zone(z)
                for col = 3, 6 do
                    local a, b, c = Triple(f[col])
                    local i = col - 2
                    e.own.n[i], e.own.c[i], e.own.o[i] = e.own.n[i] + a, e.own.c[i] + b, e.own.o[i] + c
                end
                local a, b, c = Triple(f[7])
                e.all.n, e.all.c, e.all.o = e.all.n + a, e.all.c + b, e.all.o + c
            end
        elseif f[1] == "d" and f[2] ~= "" then
            local e = Dungeon(f[2])
            local a, b, c = Triple(f[4])
            e.t.n, e.t.c, e.t.o = e.t.n + a, e.t.c + b, e.t.o + c
        elseif f[1] == "i" then
            local z = ZoneOf(ClientSpot(tonumber(f[2])))
            if z then
                places.codes[z] = places.codes[z] or {}
                table.insert(places.codes[z], f[3])
            end
        elseif f[1] == "j" then
            places.codes["d:" .. f[2]] = { f[3] }
        end
    end
end

-- a zone's own items (key: its client map) or a dungeon's (key "d:" .. name) as a set, unpacked from Data\Places.lua
-- the first time the database asks (see place_counts.lua); the same items the counts come from
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #ALPHABET do VALUE[ALPHABET:byte(i)] = i - 1 end
local function ZoneSet(z)
    local set = places.sets[z]
    if set then return set end
    set = {}
    for _, code in ipairs(places.codes[z] or {}) do
        local id, d, mul = 0, 0, 1
        for i = 1, #code do
            local g = VALUE[code:byte(i)]
            if g >= 32 then
                d, mul = d + (g - 32) * mul, mul * 32
            else
                id = id + d + g * mul
                set[id] = true
                d, mul = 0, 1
            end
        end
    end
    places.sets[z] = set
    return set
end

-- where a find was seen: zones and dungeons, from its sources (a dungeon's own zone text names it)
local function FindPlaces(e, zones, dungeons)
    for _, s in ipairs(e.s or {}) do
        local d = s.z and D.DungeonNamed(s.z)
        if d then
            dungeons[d.name] = true
        else
            local z = ZoneOf(s.m)
            if z then zones[z] = s.t == "l" and 3 or 1 end
        end
    end
end

-- a find of an item the data knows no place for counts where it was seen: this is how the counts grow after launch
local function AddFinds()
    if not ns.Finds then return end
    for _, e in ipairs(ns.Finds.List()) do
        if not e.demo and not D.HasSources(e.id) then
            local row = D.Seed(e.id)
            local k = KindOf(row and row.kind or e.k)
            local zones, dungeons = {}, {}
            FindPlaces(e, zones, dungeons)
            local inAll = {}
            for z, col in pairs(zones) do
                local ze = Zone(z)
                ze.own[k][1] = ze.own[k][1] + 1
                if col > 1 then ze.own[k][col] = ze.own[k][col] + 1 end
                inAll[z] = true
            end
            for name in pairs(dungeons) do
                local de = Dungeon(name)
                de.t[k] = de.t[k] + 1
                if de.zone then inAll[de.zone] = true end
            end
            for z in pairs(inAll) do Zone(z).all[k] = Zone(z).all[k] + 1 end
        end
    end
end

-- the player's own marks: favorites and the Mark on Map item, each with its kind, where its sources or finds put it
local function AddMarks()
    local ids = {}
    for id in pairs(ns.db and ns.db.favorites or {}) do ids[id] = true end
    local marked = ns.WorldPins and ns.WorldPins.Marked()
    if marked then ids[marked] = true end
    for id in pairs(ids) do
        local row = D.Seed(id)
        local find = ns.Finds and ns.Finds.Get(id)
        local k = KindOf(row and row.kind or (find and find.k) or "n")
        local zones, dungeons = {}, {}
        for _, s in ipairs(D.Sources(id)) do
            for _, p in ipairs(s.pins or {}) do
                local z = ZoneOf(ClientSpot(p.m, p.x, p.y))
                if z then zones[z] = true end
            end
            if s.dungeon and s.dungeon.name then dungeons[s.dungeon.name] = true end
        end
        if find and not D.HasSources(id) then FindPlaces(find, zones, dungeons) end
        local inAll = {}
        for z in pairs(zones) do
            table.insert(Zone(z).marksOwn, k)
            inAll[z] = true
        end
        for name in pairs(dungeons) do
            local de = Dungeon(name)
            table.insert(de.marks, k)
            if de.zone then inAll[de.zone] = true end
        end
        for z in pairs(inAll) do table.insert(Zone(z).marksAll, k) end
    end
end

local function Build()
    places = { zones = {}, dungeons = {}, codes = {}, sets = {} }
    LoadShipped()
    AddFinds()
    AddMarks()
    dirty = false
end

-- what one place counts under the Show picks; a marked item of a kind already shown is counted once
local function MarkExtra(show, marks)
    if not show.f then return 0 end
    local n = 0
    for _, k in ipairs(marks) do if not show[k] then n = n + 1 end end
    return n
end
local function Count(show, t, marks)
    local n = MarkExtra(show, marks)
    for _, k in ipairs(KINDS) do
        if show[k] then n = n + (type(t[k]) == "table" and t[k][1] or t[k]) end
    end
    return n
end

local function Fmt(n)
    local s = tostring(n)
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then return s end
    end
end

local function Picked(show)
    local out = {}
    for _, o in ipairs(SHOW_ORDER) do if show[o[1]] then out[#out + 1] = o end end
    return out
end

local function Items(show, n)
    local picked = Picked(show)
    local noun = #picked == 1 and (NOUN[picked[1][1]] .. " ") or ""
    return Fmt(n) .. " " .. noun .. (n == 1 and "item" or "items")
end

-- "98 items: 23 new, 75 changed" when more than one kind is shown, else "23 new items"
local function CountLine(show, t, marks)
    local n = Count(show, t, marks)
    local parts = {}
    for _, k in ipairs(KINDS) do
        local v = type(t[k]) == "table" and t[k][1] or t[k]
        if show[k] and v > 0 then parts[#parts + 1] = Fmt(v) .. " " .. NOUN[k] end
    end
    local extra = MarkExtra(show, marks)
    if extra > 0 then parts[#parts + 1] = Fmt(extra) .. " marked" end
    if #Picked(show) > 1 and #parts > 0 then return Items(show, n) .. ": " .. table.concat(parts, ", ") end
    return Items(show, n)
end

-- markers: our art, the count, and on a continent a small entrance icon when the zone has dungeons or raids
local markers, used = {}, 0

-- the Item Database on a marker's place, holding the kinds the map counts when it was clicked
local function Open(m)
    local show, kinds = Shown(), {}
    for k, v in pairs(show) do kinds[k] = v end
    local picked = Picked(show)
    local noun = #picked == 1 and (NOUN[picked[1][1]] .. " ") or ""
    if not (ns.UI and ns.UI.ShowPlace) then return end
    if m.dungeon then
        ns.UI.ShowPlace({ dungeon = m.dungeon.name, name = m.dungeon.name, kinds = kinds, noun = noun })
    elseif m.zoneID then
        ns.UI.ShowPlace({ zone = m.zoneID, name = m.name, kinds = kinds, noun = noun })
    end
end

local function Tip(m)
    local show, z, d = Shown(), m.zone, m.dungeon
    GameTooltip:SetOwner(m, m.top and "ANCHOR_BOTTOM" or "ANCHOR_RIGHT")
    if d then
        GameTooltip:AddLine(d.name .. (d.raid and " (raid)" or ""), T.RGB(C.title))
        GameTooltip:AddLine(CountLine(show, d.t, d.marks), T.RGB(C.title))
        GameTooltip:AddLine("Click to list them in the Item Database", T.RGB(C.faint))
    elseif z and m.top then
        -- the zone's own marker, opened: how its items come
        GameTooltip:AddLine(m.name or "", T.RGB(C.title))
        GameTooltip:AddLine(CountLine(show, z.own, z.marksOwn), T.RGB(C.title))
        local function Src(i)
            local n = 0
            for _, k in ipairs(KINDS) do if show[k] then n = n + z.own[k][i] end end
            return n
        end
        local extra = MarkExtra(show, z.marksOwn)
        local rest = math.max(0, Count(show, z.own, z.marksOwn) - extra - Src(2) - Src(3) - Src(4))
        for _, l in ipairs({ { "World drops", Src(2) }, { "Mob drops", Src(3) }, { "Quest rewards", Src(4) },
            { "Vendors, containers, crafts", rest } }) do
            GameTooltip:AddDoubleLine(l[1], Fmt(l[2]), T.RGB(C.dim))
        end
        if extra > 0 then GameTooltip:AddDoubleLine("Marked, not shown otherwise", Fmt(extra), T.RGB(C.dim)) end
        GameTooltip:AddLine("Click to list them in the Item Database", T.RGB(C.faint))
    elseif z then
        -- the continent's marker: the zone's own items, then each dungeon and raid inside it
        GameTooltip:AddLine(m.name or "", T.RGB(C.title))
        GameTooltip:AddLine(CountLine(show, z.all, z.marksAll), T.RGB(C.title))
        GameTooltip:AddDoubleLine("In the zone", Fmt(Count(show, z.own, z.marksOwn)), T.RGB(C.dim))
        for _, name in ipairs(z.gates) do
            local de = places.dungeons[name]
            local n = de and Count(show, de.t, de.marks) or 0
            if n > 0 then GameTooltip:AddDoubleLine(name .. (de.raid and " (raid)" or ""), Fmt(n), T.RGB(C.dim)) end
        end
        -- the marked items whose icons lead the row
        for i, id in ipairs(m.markIds or {}) do
            if i > MARK_LIST then
                GameTooltip:AddLine("and " .. (#m.markIds - MARK_LIST) .. " more", T.RGB(C.dim))
                break
            end
            local itemName, hex = ns.UI.ItemLabel(id)
            GameTooltip:AddLine(itemName, T.RGB(hex))
        end
        GameTooltip:AddLine(m.outside and "Click the dot on the zone to open it" or "Click to open the zone", T.RGB(C.faint))
    end
    GameTooltip:Show()
end

-- big: the zone's own marker, larger so it is not missed
local function NewMarker(parent, big)
    local m = CreateFrame("Frame", nil, parent)
    m:EnableMouse(true)
    m.big = big
    m.bg, m.edge = T.Panel(m, C.input, ZONE_EDGE)
    m.bg:SetAlpha(0.86)
    m.pic = m:CreateTexture(nil, "ARTWORK")
    m.pic:SetTexture(ns.MEDIA .. "FIF_MapPin")
    m.pic:SetSize(U(big and PIC + 4 or PIC), U(big and PIC + 4 or PIC))
    m.pic:SetPoint("LEFT", U(3), 0)
    m.label = T.Text(m, big and 14 or 12, C.ink)
    m.label:SetPoint("LEFT", m.pic, "RIGHT", U(GAP), 0)
    m.gate = m:CreateTexture(nil, "ARTWORK")
    m.gate:SetSize(U(14), U(14))
    -- marked items' icons, bare, ahead of our mark
    m.faces = {}
    for i = 1, MARK_ICONS do
        local f = CreateFrame("Frame", nil, m)
        f:SetSize(U(PIC), U(PIC))
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        -- hover shows that item's own tooltip; a click goes on to the row and the map
        f:EnableMouse(true)
        if f.SetPropagateMouseClicks then f:SetPropagateMouseClicks(true) end
        f:SetScript("OnEnter", function(self) T.ItemTip(self, self.id) end)
        f:SetScript("OnLeave", function(self) T.HideItemTip(self) end)
        m.faces[i] = f
    end
    m.more = T.Text(m, 12, "FFFFFF")
    m:SetScript("OnEnter", Tip)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.opens then Open(self) end
    end)
    return m
end

-- passes: the map gets the click (a continent marker: the map opens the zone); else the marker keeps it
local function SetPasses(m, passes)
    if m.passes == passes then return end
    m.passes = passes
    if m.SetPropagateMouseClicks then m:SetPropagateMouseClicks(passes) end
end

-- a zone's marker: its marked items' icons (up to three and a count past that), then our art and the count; an
-- entrance's marker: the game's entrance icon (dungeon or raid), then the count
local function Fill(m, e)
    m.name = e.name
    m.label:SetText(e.text)
    m.edge:SetColor(e.edge)
    m.pic:SetShown(not e.entrance)
    m.gate:SetShown(e.entrance == true)
    m.label:ClearAllPoints()
    local ids = e.marks or {}
    m.markIds = ids
    local k, x = math.min(#ids, MARK_ICONS), U(3)
    for i, f in ipairs(m.faces) do
        f:SetShown(i <= k)
        f.id = ids[i]
        if i <= k then
            f.icon:SetTexture(ns.UI.ItemIcon(ids[i]))
            f:ClearAllPoints()
            f:SetPoint("LEFT", x, 0)
            x = x + U(PIC) + U(2)
        end
    end
    m.more:SetShown(#ids > k)
    if #ids > k then
        m.more:SetText("+" .. (#ids - k))
        m.more:ClearAllPoints()
        m.more:SetPoint("LEFT", x, 0)
        x = x + m.more:GetStringWidth() + U(2)
    end
    if k > 0 then x = x + U(GAP) end
    m.pic:ClearAllPoints()
    m.pic:SetPoint("LEFT", x, 0)
    local w
    if e.entrance then
        m.gate:SetAtlas(e.gate == "raid" and "Raid" or "Dungeon")
        m.gate:ClearAllPoints()
        m.gate:SetPoint("LEFT", U(3), 0)
        m.label:SetPoint("LEFT", m.gate, "RIGHT", U(GAP), 0)
        w = U(3) + U(14) + U(GAP) + m.label:GetStringWidth()
    else
        m.label:SetPoint("LEFT", m.pic, "RIGHT", U(GAP), 0)
        w = x + U(m.big and PIC + 4 or PIC) + U(GAP) + m.label:GetStringWidth()
    end
    m:SetSize(w + U(m.big and 10 or 6), U(m.big and H + 6 or H))
end

-- leader lines from a moved marker back to a dot on its own spot
local leaders, usedLeaders, holder = {}, 0, nil

local function Leader(x1, y1, x2, y2)
    usedLeaders = usedLeaders + 1
    local l = leaders[usedLeaders]
    if not l then
        l = { line = holder:CreateLine(nil, "ARTWORK"), dot = holder:CreateTexture(nil, "OVERLAY") }
        l.line:SetThickness(1)
        l.line:SetColorTexture(T.RGB(C.ink))
        l.dot:SetSize(U(5), U(5))
        l.dot:SetColorTexture(T.RGB(C.title))
        leaders[usedLeaders] = l
    end
    l.line:SetStartPoint("TOPLEFT", holder, x1, -y1)
    l.line:SetEndPoint("TOPLEFT", holder, x2, -y2)
    l.dot:ClearAllPoints()
    l.dot:SetPoint("CENTER", holder, "TOPLEFT", x1, -y1)
    l.line:Show()
    l.dot:Show()
end

local function Overlaps(a, b)
    return math.abs(a.x - b.x) < (a.w + b.w) / 2 and math.abs(a.y - b.y) < (a.h + b.h) / 2
end

-- markers that would overlap are pushed apart along the axis that needs less, until none touch. A fixed one (the
-- zone's own) stays put. keep(a) says whether a may stand where it moved (a continent's marker must stay over its own
-- zone, or the click going through would open the neighbour); a move it refuses is given to the other marker
local function Declutter(list, cw, ch, keep)
    for _ = 1, 40 do
        local moved = false
        for i = 1, #list do
            for j = i + 1, #list do
                local a, b = list[i], list[j]
                local ox = (a.w + b.w) / 2 + U(3) - math.abs(a.x - b.x)
                local oy = (a.h + b.h) / 2 + U(2) - math.abs(a.y - b.y)
                if ox > 0 and oy > 0 and not (a.fixed and b.fixed) then
                    local horiz = ox < oy
                    local need = (horiz and ox or oy) + 0.5
                    local dir = horiz and (a.x <= b.x and -1 or 1) or (a.y <= b.y and -1 or 1)
                    local function Try(f, d)
                        if f.fixed then return false end
                        local ox0, oy0 = f.x, f.y
                        if horiz then f.x = f.x + d else f.y = f.y + d end
                        f.x = math.min(cw - f.w / 2 - 2, math.max(f.w / 2 + 2, f.x))
                        f.y = math.min(ch - f.h / 2 - 2, math.max(f.h / 2 + 2, f.y))
                        if keep and not keep(f) then f.x, f.y = ox0, oy0 return false end
                        return f.x ~= ox0 or f.y ~= oy0
                    end
                    local okA = not a.fixed and not b.fixed and Try(a, dir * need / 2)
                    local okB = not a.fixed and not b.fixed and Try(b, -dir * need / 2)
                    if not okA and not okB then
                        okA = Try(a, dir * need) or Try(b, -dir * need)
                    end
                    moved = moved or okA or okB
                end
            end
        end
        if not moved then break end
    end
end

-- a spot inside each zone on the continent, where a click opens that zone: the middle of its box when that is the
-- zone, else the nearest point of a grid over the box that is (a zone's box reaches over its neighbours)
local inside = {}
local function SpotIn(z, cont)
    local key = cont * 1e6 + z
    local s = inside[key]
    if s ~= nil then return s or nil end
    local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(z, cont)
    if not minX then inside[key] = false return end
    local function Is(x, y)
        local info = C_Map.GetMapInfoAtPosition(cont, x, y)
        return info and info.mapID == z
    end
    local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
    if Is(cx, cy) then
        s = { cx, cy }
    else
        local best
        for i = 1, 9 do
            for j = 1, 9 do
                local x, y = minX + (maxX - minX) * i / 10, minY + (maxY - minY) * j / 10
                local d = (x - cx) ^ 2 + (y - cy) ^ 2
                if (not best or d < best) and Is(x, y) then best, s = d, { x, y } end
            end
        end
        s = s or { cx, cy }
    end
    inside[key] = s
    return s
end

local function PinLevel(wm, canvas)
    if ns.FavPins and ns.FavPins.PinLevel then return ns.FavPins.PinLevel(wm, canvas) end
    return canvas:GetFrameLevel() + 2100
end

local function Place(canvas, scale, level, entry)
    used = used + 1
    local m = markers[used]
    if not m then
        m = NewMarker(canvas)
        markers[used] = m
    end
    m.zone, m.dungeon, m.top = entry.zone, entry.dungeon, entry.top
    Fill(m, entry)
    entry.m, entry.w, entry.h = m, m:GetWidth(), m:GetHeight()
    m:SetFrameLevel(level)
    m:SetScale(1 / scale)
    return m
end

-- the zone's own marker: at the top of the map's visible part, so panning or zooming never takes it away
local banner

local function Lay()
    used, usedLeaders = 0, 0
    local bannerOn = false
    local wm = WorldMapFrame
    local canvas = wm and wm.GetCanvas and wm:GetCanvas()
    local mapID = canvas and wm:IsShown() and On() and wm:GetMapID()
    if mapID then
        if dirty or not places then Build() end
        local show = Shown()
        local scale = wm:GetCanvasScale()
        if not scale or scale <= 0 then scale = 1 end
        local cw, ch = canvas:GetWidth() * scale, canvas:GetHeight() * scale
        local level = PinLevel(wm, canvas)
        if not holder then holder = CreateFrame("Frame", nil, canvas) end
        holder:SetFrameLevel(level)
        holder:SetScale(1 / scale)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", canvas, "TOPLEFT")
        holder:SetSize(cw, ch)
        holder:Show()
        local info = C_Map.GetMapInfo(mapID)
        -- the favorites' plates and pins (FavPins lays them out first) stay where they are; the counts step around them
        local list = {}
        for _, o in ipairs(ns.FavPins and ns.FavPins.Obstacles and ns.FavPins.Obstacles() or {}) do
            list[#list + 1] = { fixed = true, obstacle = true, x = o.x, y = o.y, w = o.w, h = o.h }
        end
        if info and info.mapType == CONTINENT then
            -- the favorites' and Mark on Map icons go in the row of their zone
            local marksIn = {}
            for _, mz in ipairs(ns.FavPins and ns.FavPins.ZoneMarks and ns.FavPins.ZoneMarks() or {}) do
                local z = ZoneOf(mz.m)
                if z and #mz.ids > 0 then
                    local list = marksIn[z] or {}
                    marksIn[z] = list
                    for _, id in ipairs(mz.ids) do list[#list + 1] = id end
                end
            end
            local zonesHere = {}
            for z in pairs(places.zones) do zonesHere[z] = true end
            for z in pairs(marksIn) do zonesHere[z] = true end
            for z in pairs(zonesHere) do
                local e = places.zones[z] or Zone(z)
                local zi = C_Map.GetMapInfo(z)
                local here = zi and zi.parentMapID == mapID
                local n = here and Count(show, e.all, e.marksAll) or 0
                local spot = here and (n > 0 or marksIn[z]) and SpotIn(z, mapID)
                if spot then
                    local entry = { zone = e, zoneID = z, name = zi.name, text = Fmt(n), edge = ZONE_EDGE, marks = marksIn[z],
                        x0 = spot[1] * cw, y0 = spot[2] * ch }
                    entry.x, entry.y = entry.x0, entry.y0
                    list[#list + 1] = entry
                    Place(canvas, scale, level, entry)
                end
            end
            local function Over(f)
                local hit = C_Map.GetMapInfoAtPosition(mapID, f.x / cw, f.y / ch)
                return hit ~= nil and hit.mapID == (f.zoneID or 0)
            end
            Declutter(list, cw, ch, Over)
            -- a zone too small to hold its marker clear of the rest (a city beside a favorite's plate): that marker
            -- alone steps out of it; it then takes the click itself (doing nothing) so the click never opens the
            -- neighbour, and its tooltip points at the dot on its zone
            local stuck = {}
            for _, a in ipairs(list) do
                if not a.fixed then
                    for _, b in ipairs(list) do
                        if a ~= b and Overlaps(a, b) then stuck[a] = true break end
                    end
                end
            end
            if next(stuck) then
                for _, f in ipairs(list) do f.held = not f.fixed and not stuck[f] end
                for _, f in ipairs(list) do if f.held then f.fixed = true end end
                Declutter(list, cw, ch)
                for _, f in ipairs(list) do if f.held then f.fixed, f.held = nil, nil end end
                for f in pairs(stuck) do f.outside = not Over(f) end
            end
        else
            local e = places.zones[mapID]
            local container = wm.GetCanvasContainer and wm:GetCanvasContainer()
            if e and container then
                local name = info and info.name or ""
                if not banner then banner = NewMarker(container, true) end
                banner.zone, banner.zoneID, banner.dungeon, banner.top, banner.opens = e, mapID, nil, true, true
                Fill(banner, { name = name, edge = C.gold,
                    text = "|cff" .. C.title .. name .. "|r  " .. Items(show, Count(show, e.own, e.marksOwn)) })
                banner:SetFrameLevel(level + 600)
                banner:ClearAllPoints()
                banner:SetPoint("TOP", container, "TOP", 0, -U(12))
                bannerOn = true
                for _, name in ipairs(e.gates) do
                    local de = places.dungeons[name]
                    local n = de and de.m == mapID and de.x and Count(show, de.t, de.marks) or 0
                    if n > 0 then
                        local entry = { dungeon = de, entrance = true, name = name, text = Fmt(n), gate = de.raid and "raid" or "dungeon",
                            edge = de.raid and RAID_EDGE or GATE_EDGE, x0 = de.x / 1000 * cw, y0 = de.y / 1000 * ch }
                        entry.x, entry.y = entry.x0, entry.y0
                        list[#list + 1] = entry
                        Place(canvas, scale, level, entry)
                    end
                end
                Declutter(list, cw, ch)
            end
        end
        for _, f in ipairs(list) do
            if f.m then
                f.m.outside = f.outside
                -- a continent marker over its own zone hands the click to the map; an entrance opens the database;
                -- a marker that had to step out of its zone keeps the click and does nothing
                f.m.zoneID, f.m.opens = f.zoneID, f.entrance == true
                SetPasses(f.m, f.zoneID ~= nil and not f.outside)
                f.m:ClearAllPoints()
                f.m:SetPoint("CENTER", canvas, "TOPLEFT", f.x, -f.y)
                f.m:Show()
                if not f.top and math.abs(f.x - f.x0) + math.abs(f.y - f.y0) > U(10) then Leader(f.x0, f.y0, f.x, f.y) end
            end
        end
    elseif holder then
        holder:Hide()
    end
    if banner then banner:SetShown(bannerOn) end
    for i = used + 1, #markers do markers[i]:Hide() end
    for i = usedLeaders + 1, #leaders do
        leaders[i].line:Hide()
        leaders[i].dot:Hide()
    end
end

-- the Show pick: in the addon's own map button (FavPins.lua) and in Settings
local function ShowLabel()
    local picked = Picked(Shown())
    if #picked == 0 then return "Show: nothing" end
    if #picked == #SHOW_ORDER then return "Show: all" end
    if #picked > 2 then return "Show: " .. picked[1][2] .. ", " .. picked[2][2] .. " +" .. (#picked - 2) end
    local names = {}
    for _, o in ipairs(picked) do names[#names + 1] = o[2] end
    return "Show: " .. table.concat(names, ", ")
end
P.ShowLabel = ShowLabel

function P.ShowOptions() return { { "n", "New items" }, { "c", "Changed items" }, { "o", "Classic items" }, { "f", "Marked items" } } end

function P.ToggleShow(k)
    local s = S()
    local cur = Shown()
    local copy = {}
    for key, v in pairs(cur) do copy[key] = v end
    copy[k] = not copy[k]
    s.placeShow = copy
    P.Refresh()
end

-- plain: the box under a "Show" label in Settings says only the picks
function P.NewShowBox(parent, w, plain)
    return T.Dropdown(parent, w, P.ShowOptions(), function() end, function() end, nil, {
        isOn = function(k) return Shown()[k] == true end,
        toggle = P.ToggleShow,
        label = plain and function()
            local text = ShowLabel():gsub("^Show: ", "")
            return text:sub(1, 1):upper() .. text:sub(2)
        end or ShowLabel,
    })
end

function P.SyncShow()
    if ns.FavPins and ns.FavPins.SyncMapButton then ns.FavPins.SyncMapButton() end
end

function P.On() return On() end
function P.IsShown(k) return Shown()[k] == true end
-- the map's changes reach Lay through FavPins.lua's hooks, after the favorites are laid out
P.Lay = Lay

function P.Refresh()
    dirty = true
    Lay()
    P.SyncShow()
end

-- whether an item belongs to a place the database was opened on (UI.ShowPlace): place = { zone = clientMap } or
-- { dungeon = name }, with the kinds the map counted; finds of items with no known place count where they were seen
function P.InPlace(place, id, kind, e)
    if dirty or not places then Build() end
    local inside
    inside = ZoneSet(place.zone or ("d:" .. place.dungeon))[id] == true
    if not inside and e and not D.HasSources(id) then
        local zones, dungeons = {}, {}
        FindPlaces(e, zones, dungeons)
        inside = (place.zone and zones[place.zone] ~= nil) or (place.dungeon ~= nil and dungeons[place.dungeon] == true)
    end
    if not inside then return false end
    if place.kinds[KindOf(kind)] then return true end
    local marked = (ns.db and ns.db.favorites and ns.db.favorites[id]) or (ns.WorldPins and ns.WorldPins.Marked() == id)
    return place.kinds.f == true and marked and true or false
end

-- the Item Database's Zone filter: every zone with items, by name, and a pick of one (all kinds; the chips narrow it)
function P.ZoneOptions()
    if dirty or not places then Build() end
    local list = {}
    for z in pairs(places.zones) do
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(z)
        if info and info.name and places.codes[z] then list[#list + 1] = { z, info.name } end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    table.insert(list, 1, { "", "Any zone" })
    return list
end

function P.ZonePick(z)
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(z)
    return { zone = z, name = info and info.name or "", kinds = { n = true, c = true, o = true }, noun = "", picked = true }
end

-- read by the tests; nothing here changes them
function P.State()
    if dirty or not places then Build() end
    return { places = places, markers = markers, used = used, leaders = leaders, usedLeaders = usedLeaders, holder = holder, banner = banner,
        count = function(t, marks) return Count(Shown(), t, marks) end }
end

ns.Listen("Login", P.Refresh)
ns.Listen("FavoritesChanged", P.Refresh)
-- finds arrive in bursts: one rebuild on the next frame
local soon
ns.Listen("FindsChanged", function()
    dirty = true
    if soon then return end
    soon = true
    C_Timer.After(0, function()
        soon = false
        Lay()
    end)
end)
