local _, ns = ...
if ns.shareOnly then return end

local T = ns.Theme
local D = ns.Data
local C = T.C
local U = T.U

local UI = {}
ns.UI = UI

-- a FontString held to a width reports its cut length from GetStringWidth; this is the full text's
local function FullWidth(fs)
    return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
end

local W, H = U(900), U(676)
local BORDER = 3
local win
local tab = "feed"
local selected            -- item id shown on the right
local dirty = true
-- dg: the dungeon or raid picked once Source is Dungeon or Raid ("" = any)
local state = { q = "", minL = nil, maxL = nil, qs = {}, slots = {}, clss = {}, srcs = {}, src = 0, dg = "", kind = "all", cat = "all" }

local function Settings() return ns.settings end

local function ShortDate(t)
    return t and date("%b %d", t) or ""
end
-- the game knows an item's icon only once the server has sent the item: anything drawn before that is asked for
-- once, and GET_ITEM_INFO_RECEIVED redraws it
local asked = {}
local function ItemIcon(id)
    if not asked[id] and C_Item.RequestLoadItemDataByID and not C_Item.GetItemInfo(id) then
        asked[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    -- the game's question mark means it has no art yet: the datamined icon stands in (D.IconOf leaves out art this
    -- client does not hold)
    if not icon or icon == 134400 then icon = D.IconOf(id) or icon end
    return icon or 134400
end

-- what each row stands for: a find (seen in game) or a datamined seed row
local function FindLine(e)
    local s = e.s and e.s[1]
    if s then
        if s.t == "x" then return s.n and ("Inside " .. s.n) or "From a container" end
        local who = s.n or (s.t == "v" and "A vendor") or (s.t == "q" and "A quest") or (s.t == "r" and "Group loot") or
            (s.t == "c" and "Another player's loot") or "Looted"
        return s.z and (who .. ", " .. s.z) or who
    end
    return "Seen in game"
end

local function Status(e)
    local n = ns.Finds.Reporters(e)
    if e.k == "c" and n == 0 then return "Changed" end
    if n <= 1 then return "1 player" end
    return n .. " players"
end

-- the window frame
local function CloseButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(U(24), U(24))
    local ring = b:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints()
    ring:SetColorTexture(T.RGB(C.gold))
    local fill = b:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(T.RGB(C.red))
    local mask1 = b:CreateMaskTexture()
    mask1:SetAllPoints(ring)
    mask1:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ring:AddMaskTexture(mask1)
    local mask2 = b:CreateMaskTexture()
    mask2:SetAllPoints(fill)
    mask2:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fill:AddMaskTexture(mask2)
    local x = T.Cross(b, U(9), C.title)
    x:SetPoint("CENTER")
    b:SetScript("OnEnter", function() fill:SetColorTexture(T.RGB("9A1A1A")) end)
    b:SetScript("OnLeave", function() fill:SetColorTexture(T.RGB(C.red)) end)
    return b
end

local function Tab(parent, label)
    local b = CreateFrame("Button", nil, parent)
    local bg = T.Solid(b, "BACKGROUND", C.tabOff)
    bg:SetAllPoints()
    -- the tab hangs under the frame: no top edge
    local edges = T.Border(b, C.inputLine, 2)
    edges.TOP:Hide()
    local fs = T.Text(b, 14, C.chipOffText)
    fs:SetPoint("CENTER", 0, 0)
    -- the count wears the item rows' NEW tag, so the window has one badge look
    local badge = T.Tag(b)
    badge:Hide()
    b.badge = badge
    function b:Set(text, on, badgeText)
        fs:SetText(text)
        fs:SetTextColor(T.RGB(on and C.title or C.chipOffText))
        bg:SetColorTexture(T.RGB(on and C.chipOn or C.tabOff))
        edges:SetColor(on and C.gold or C.inputLine)
        self:SetHeight(on and U(30) or U(26))
        local w = fs:GetStringWidth() + U(32)
        if badgeText then
            badge:Set("n", badgeText)
            badge:ClearAllPoints()
            badge:SetPoint("LEFT", fs, "RIGHT", U(6), 0)
            badge:Show()
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", U(16), 0)
            w = w + badge:GetWidth() + U(6)
        else
            badge:Hide()
            fs:ClearAllPoints()
            fs:SetPoint("CENTER")
        end
        self:SetWidth(w)
    end
    return b
end

-- favorites: items the player starred to find again, kept for the whole account; never a pop-up or an alert
function UI.IsFavorite(id)
    return id ~= nil and ns.db.favorites ~= nil and ns.db.favorites[id] == true
end
function UI.ToggleFavorite(id)
    if not id then return end
    ns.db.favorites = ns.db.favorites or {}
    ns.db.favorites[id] = (not ns.db.favorites[id]) or nil
    -- starred again, an item is back on the map even if it was taken off before
    if ns.db.favHidden then ns.db.favHidden[id] = nil end
    UI.Refresh()
    ns.Signal("FavoritesChanged")
end

-- rows; withStar: the Item Database's and the Live Feed's rows, with a favorites star at the left edge as in the
-- auction house
local function MakeRow(list, withStar)
    local r = CreateFrame("Button", nil, list)
    local sel = T.Solid(r, "BACKGROUND", C.sel)
    sel:SetAllPoints()
    r.selBorder = T.Border(r, C.gold, 1, "ARTWORK")
    r.sel = sel
    local line = T.Solid(r, "BORDER", C.rowLine)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    local hover = T.Hover(r, "2A2117")
    if withStar then
        -- a click stars or unstars the item without picking the row
        local star = CreateFrame("Button", nil, r)
        star:SetSize(U(20), U(20))
        star:SetPoint("LEFT", U(8), 0)
        star.mark = T.Star(star, U(16))
        star.mark:SetPoint("CENTER")
        star:SetScript("OnClick", function() UI.ToggleFavorite(r.id) end)
        star:SetScript("OnEnter", function(self)
            hover:Show()
            if not self.mark.on then self.mark:SetOn(false, C.gold) end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Favorite", 1, 1, 1)
            GameTooltip:Show()
        end)
        star:SetScript("OnLeave", function(self)
            hover:Hide()
            if not self.mark.on then self.mark:SetOn(false) end
            GameTooltip:Hide()
        end)
        r.star = star
    end
    local iconFrame = CreateFrame("Frame", nil, r)
    iconFrame:SetSize(U(32), U(32))
    iconFrame:SetPoint("LEFT", withStar and U(34) or U(10), 0)
    -- the icon shows the item's tooltip; a click on it still picks the row
    iconFrame:EnableMouse(true)
    iconFrame:SetScript("OnEnter", function(self)
        hover:Show()
        if r.id then T.ItemTip(self, r.id) end
    end)
    iconFrame:SetScript("OnLeave", function(self)
        hover:Hide()
        T.HideItemTip(self)
    end)
    iconFrame:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then r:Click() end
    end)
    -- the one-pixel quality border lies over the icon's edge, so no gap opens between them at any scale
    r.iconBorder = T.Border(iconFrame, "A335EE", 1, "OVERLAY")
    r.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = T.Text(r, 15, "FFFFFF")
    r.name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", U(10), -U(1))
    r.tag = T.Tag(r)
    r.tag:SetPoint("LEFT", r.name, "RIGHT", U(6), 0)
    r.sub = T.Text(r, 12, C.dim)
    r.sub:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", U(10), U(1))
    r.right = T.Text(r, 12, C.dim)
    r.right:SetPoint("TOPRIGHT", -U(10), -U(8))
    r.right:SetJustifyH("RIGHT")
    r.when = T.Text(r, 11, C.faint)
    r.when:SetPoint("BOTTOMRIGHT", -U(10), U(8))
    r.when:SetJustifyH("RIGHT")
    r.sub:SetPoint("RIGHT", r.right, "LEFT", -U(8), 0)
    r:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() return end
        selected = self.id
        UI.Refresh()
    end)
    return r
end

local function BindRow(r, item)
    r.id, r.onClick = item.id, item.onClick
    local on = item.id and item.id == selected
    r.sel:SetShown(on)
    for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do r.selBorder[s]:SetShown(on) end
    r.icon:SetTexture(item.icon or 134400)
    r.iconBorder:SetColor(item.border or T.QualityHex(item.q))
    r.name:SetText(item.name or ("Item " .. (item.id or "")))
    r.name:SetTextColor(T.RGB(item.nameHex or T.QualityHex(item.q)))
    r.tag:Set(item.kind, item.tagText)
    r.sub:SetText(item.line or "")
    r.right:SetText(item.status or "")
    r.when:SetText(item.when or "")
    if r.star then
        r.star:SetShown(item.id ~= nil and not item.onClick)
        r.star.mark:SetOn(UI.IsFavorite(item.id))
    end
    -- the name is as wide as its text with the tag right after it; both stop short of the right column
    local rowW = r:GetWidth()
    if not rowW or rowW <= 0 then rowW = r:GetParent():GetWidth() - U(12) end
    local lead = r.star and (U(34) + U(32) + U(10)) or U(52)
    local room = rowW - lead - U(12) - math.max(r.right:GetStringWidth(), r.when:GetStringWidth()) - U(10)
    if r.tag:IsShown() then room = room - U(6) - r.tag:GetWidth() end
    if room < U(80) then room = U(80) end
    r.name:SetWidth(room)
    r.name:SetWidth(math.min(FullWidth(r.name) + 1, room))
end

-- a seed row's chip: new (hidden ones too), changed (from Classic or by a hotfix) or an old Classic item; finds keep
-- their own kind
local function ChipKind(kind)
    if kind == "o" or kind == "n" then return kind end
    if kind == "x" then return "n" end
    return "c"
end

-- a new item nobody has seen (D.RowNotFound: hidden, or no known drop place and not seen in the beta); a find
-- replaces its seed row, so a found item never reads this
local function NotFound(row)
    return D.IsNotFound(row.id)
end

-- a hidden row takes the game's name and quality once Blizzard releases the item, else its worked-out name, else
-- what it is
local function RowName(row)
    if row.kind ~= "x" then return row.name end
    return C_Item.GetItemInfo(row.id) or D.HiddenName(row)
end

local function RowQuality(row)
    if row.kind ~= "x" then return row.q end
    local _, _, q = C_Item.GetItemInfo(row.id)
    return q or row.q
end

-- a row against the database's filters (st: state): search reads the name and a find's place, the rest is
-- D.FilterPasses
local function PassOthers(st, id, kind, q, req, cls, sub, inv, ac, name, e, mask)
    if st.q ~= "" then
        local hay = (name or ""):lower()
        if e then hay = hay .. " " .. FindLine(e):lower() end
        if not hay:find(st.q, 1, true) then return false end
    end
    return D.FilterPasses(st, id, q, req, cls, sub, inv, ac, mask, e)
end

-- whether a find filter holds anything back (then the feed drops its new-items row and says when nothing matches)
local function Filtered(f)
    return f.quality ~= "any" or f.level ~= "any" or next(f.slots) ~= nil or f.usable or not (f.kinds.n and f.kinds.c)
end

-- whether a find arrived after the feed was last cleared (the Item Database keeps every find either way)
local function AfterClear(e)
    return (e.v or e.at or 0) > (ns.db.feedClearedAt or 0)
end

-- the feed: finds that pass the saved find filter (Data.lua D.FindPasses), newest first, plus one quiet row for
-- datamined additions while nothing is filtered; feedKinds counts what the New / Changed chips would show
local feedKinds = { n = 0, c = 0 }
local feedRows = setmetatable({}, { __mode = "k" })
local function FeedData()
    local data = {}
    local f = Settings().findFilter
    local level = UnitLevel("player") or 1
    local _, classFile = UnitClass("player")
    local mined = (Filtered(f) or (ns.db.minedAt or 0) <= (ns.db.feedClearedAt or 0)) and 0 or UI.NewDatamined()
    local list = ns.Finds.List()
    local minedAt = ns.db.minedAt or 0
    local placed = mined == 0
    feedKinds.n, feedKinds.c = 0, 0
    for _, e in ipairs(list) do
        if not placed and e.at < minedAt then
            placed = true
            table.insert(data, UI.MinedRow(mined))
        end
        if AfterClear(e) and D.FindPasses(f, e, level, classFile, true) then
            local k = e.k == "c" and "c" or "n"
            feedKinds[k] = feedKinds[k] + 1
            if f.kinds[k] then
                -- a find's row is made again only when the find changed, or while the game has not sent its name or icon
                local row = feedRows[e]
                if not row or row.v ~= e.v or not row.name or row.icon == 134400 then
                    row = { id = e.id, q = e.q, name = e.nm or C_Item.GetItemInfo(e.id), icon = ItemIcon(e.id), kind = e.k,
                        line = FindLine(e), status = Status(e), when = ShortDate(e.at), v = e.v }
                    feedRows[e] = row
                end
                table.insert(data, row)
            end
        end
    end
    if not placed then table.insert(data, UI.MinedRow(mined)) end
    return data
end

-- the Live Feed tab's number: the finds the feed is about (discoveries, while its filter keeps to them); and how many
-- of them came from other players since the feed was last looked at (while away, or while the window showed no feed)
local function FeedCount()
    local all = not Settings().findFilter.discoveries
    local seen = ns.db.feedSeenAt or 0
    local n, new = 0, 0
    for _, e in ipairs(ns.Finds.List()) do
        if AfterClear(e) and (all or e.demo or D.IsDiscovery(e.id)) then
            n = n + 1
            if (e.got or 0) > seen then new = new + 1 end
        end
    end
    return n, new
end

function UI.FeedNew()
    if not ns.db then return 0 end
    local _, new = FeedCount()
    return new
end

-- the feed was looked at: its count starts again from now
local function FeedSeen()
    ns.db.feedSeenAt = ns.Now()
    ns.Signal("FeedSeen")
end

function UI.MinedRow(n)
    return { name = n .. " new items added", nameHex = C.title, kind = "n", icon = 134939,
        border = T.C.tipLine, line = "They never pop up. Click to see them in the Item Database.", status = "Database",
        when = ShortDate(ns.db.minedAt), onClick = function()
            state.kind, state.cat = "n", "all"
            UI.Show("db")
        end }
end

-- datamined rows added by an addon update and not looked at yet
function UI.NewDatamined()
    if not ns.db then return 0 end
    if ns.db.demoMined then return ns.db.demoMined end
    return D.AddedSince(ns.db.seedVersion or D.version)
end

-- the database: seed rows by position, finds by negative id; nothing copied per row
local dbCounts = {}
local dbChipCounts = { all = 0, n = 0, c = 0, o = 0, u = 0, f = 0 }
-- a class's subclass count lives under its own number, apart from the class counts (0..20)
local function SubKey(cls, sub) return 100000 + cls * 1000 + (sub or -1) + 1 end

-- the whole list is filtered on every refresh: it reads the shipped index (no line is parsed, no text is made per
-- row) and reads a name only while a search is typed; the result list is refilled in place
local dbRefs = {}
-- whether an item shows a picture (the game's art, else the datamined icon this client holds) or the question mark;
-- kept per item, dropped when the game sends its data
local hasArt, dbLate = {}, {}
local function HasArt(id, row)
    local v = hasArt[id]
    if v == nil then
        local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
        v = (icon ~= nil and icon ~= 134400) or (row and D.IconAt(row) or D.IconOf(id)) ~= nil
        hasArt[id] = v
    end
    return v
end
UI.HasArt = HasArt

-- the database's rows in their order, items without a picture after all the others (each part keeps its order)
local function DbData()
    local data, late = dbRefs, dbLate
    wipe(data)
    wipe(late)
    wipe(dbCounts)
    dbChipCounts.all, dbChipCounts.n, dbChipCounts.c, dbChipCounts.o, dbChipCounts.u, dbChipCounts.f = 0, 0, 0, 0, 0, 0
    local favs = ns.db.favorites or {}
    local catCls, catSub
    if state.cat ~= "all" then
        local c, sb = state.cat:match("^(%-?%d+)/?(%-?%d*)$")
        catCls, catSub = tonumber(c), tonumber(sb)
    end
    local searching = state.q ~= ""
    local inSeed = {}
    -- New holds the new items the beta showed or with a known place, Not Found (u) every other new or hidden one, so New,
    -- Changed, Classic and Not Found add up to All; a favorite (f) can be any kind and counts under Favorites as well
    local function Consider(ref, id, kind, q, req, cls, sub, inv, ac, name, e, mask, notFound, row)
        if not PassOthers(state, id, kind, q, req, cls, sub, inv, ac, name, e, mask) then return end
        if notFound then kind = "u" end
        cls, sub = D.CatOf(cls, sub)
        local inCat = not catCls or (cls == catCls and (not catSub or sub == catSub))
        local fav = favs[id] == true
        if inCat then
            dbChipCounts.all = dbChipCounts.all + 1
            dbChipCounts[kind] = (dbChipCounts[kind] or 0) + 1
            if fav then dbChipCounts.f = dbChipCounts.f + 1 end
        end
        if state.kind ~= "all" and state.kind ~= kind and not (state.kind == "f" and fav) then return end
        dbCounts.all = (dbCounts.all or 0) + 1
        if cls then
            dbCounts[cls] = (dbCounts[cls] or 0) + 1
            local k = SubKey(cls, sub)
            dbCounts[k] = (dbCounts[k] or 0) + 1
        end
        if inCat then
            if HasArt(id, row) then data[#data + 1] = ref else late[#late + 1] = ref end
        end
    end
    -- finds first, newest first
    for _, e in ipairs(ns.Finds.List()) do
        inSeed[e.id] = true
        Consider(-e.id, e.id, e.k, e.q, e.rq, e.cl, e.sc, e.iv, e.ac, searching and (e.nm or C_Item.GetItemInfo(e.id)) or nil, e,
            state.src > 0 and D.FindMask(e) or 0)
    end
    D.ForEachRow(function(pos, id, kind, q, req, cls, sub, inv, ac, nameStart, mask, notFound, row)
        if inSeed[id] then return end
        Consider(pos, id, ChipKind(kind), q, req, cls, sub, inv, ac, searching and D.NameAt(nameStart) or nil, nil, mask, notFound, row)
    end)
    for i = 1, #late do data[#data + 1] = late[i] end
    return data
end

local function DbItem(ref)
    if ref < 0 then
        local e = ns.Finds.Get(-ref)
        if not e then return { name = "?" } end
        return { id = e.id, q = e.q, name = e.nm or C_Item.GetItemInfo(e.id), icon = ItemIcon(e.id), kind = e.k,
            line = D.ItemLine(e.cl, e.sc, e.iv, e.il, e.rq), status = Status(e), when = ShortDate(e.at) }
    end
    local row = D.SeedAt(ref)
    if not row then return { name = "?" } end
    -- an old item's tag says where it comes from, a new or changed one says NEW / NOT FOUND / CHANGED; the right column
    -- only adds what the tag does not
    local src = row.kind == "o" and D.SourceKind(D.MaskOf(row.id))
    -- a raid or dungeon row names the place in its tag (ONY, BRD), from its first source inside one
    local tagText
    if src and (src.key == "raid" or src.key == "dungeon") then
        for _, so in ipairs(D.Sources(row.id)) do
            if so.dungeon and so.dungeon.raid == (src.key == "raid") then tagText = D.DungeonShort(so.dungeon.name) break end
        end
    end
    return { id = row.id, q = RowQuality(row), name = RowName(row), icon = ItemIcon(row.id),
        kind = src and src.key or (NotFound(row) and "u") or ChipKind(row.kind), tagText = tagText,
        line = D.ItemLine(row.cls, row.sub, row.inv, row.ilvl, row.req),
        status = row.beta and "Seen in beta" or "", when = (row.kind == "h") and "Hotfix" or "" }
end

-- the detail side: what the item is, a map of where it drops, its status; the zone tables are refilled per draw
local detail = { zoneList = {}, zoneCount = {}, zoneEntrance = {}, zoneArt = {} }
-- o: a chest, node or fishing pool where it stands; x: a container opened from the bags (no place)
local KIND_OF = { l = "Drop", r = "Group roll", v = "Vendor", q = "Quest", c = "Another player's loot", o = "Looted", x = "Inside" }
-- what a known source does, for the hover card: l mob, v vendor, o object, w world drop, s skinning
local ROLE = { l = "Drops it", v = "Sells it", o = "Holds it", w = "Drops it", s = "Skin it" }
local RANK = { "Elite", "Rare Elite", "Boss", "Rare" }
local MAX_SOURCES = 3
-- pin looks in board px: size, ring width, ring, fill, centre; a source line's dot wears the same colour
local PIN_LOOK = {
    drop = { 10, 2, "3A0A08", "FF4A30" },
    vendor = { 12, 2, "3B2A08", "FFD100" },
    world = { 12, 2, "3A1A00", "FF8A2A" },
    quest = { 12, 2, "0A2440", "4FA3FF" },
    object = { 10, 2, "16300A", "7DCB4F" },
    skin = { 12, 2, "0A302A", "38C5B0" },
    entrance = { 16, 3, "B57CFF", "6B3FB0", "2A1745" },
}
local PIN_HIT = 18
-- spots closer than a drop pin's width at the current zoom share one pin
local PIN_CELL = 10

local function DotHex(look)
    local l = PIN_LOOK[look] or PIN_LOOK.drop
    return look == "entrance" and l[3] or l[4]
end

-- known places carry Forever map numbers; a retail test run moves them onto retail's maps (Data\RetailMaps.lua),
-- and a map retail has no match for is left out rather than drawn on whatever retail numbers the same. A spot near
-- a split zone's border lies inside more than one retail map's rectangle and goes to the one it sits deepest in.
local function RetailSpot(m, x, y)
    local maps = D.retailMaps
    if not maps then return m, x, y end
    local t = maps[m]
    if not t then return end
    local best, bx, by, depth
    for i = 1, #t, 5 do
        local nx, ny = t[i + 1] * x + t[i + 2], t[i + 3] * y + t[i + 4]
        local d = math.min(nx, 1000 - nx, ny, 1000 - ny)
        if d >= 0 and (not depth or d > depth) then best, bx, by, depth = t[i], nx, ny, d end
    end
    return best, bx, by
end

-- the developer's copy draws Forever's own maps on a test run (DevMaps\DevMaps.lua); they go by their own keys so
-- they never meet the client's map of the same number
local DEV_MAP = 100000
local DEV_ART = "Interface\\AddOns\\ForeverItemFinder\\DevMaps\\"
local function DevMap(m)
    return D.devMaps and m and m > DEV_MAP and D.devMaps[m - DEV_MAP] or nil
end

local function OnClientMap(m, x, y)
    if D.devMaps and D.devMaps[m] then return m + DEV_MAP, x, y end
    return RetailSpot(m, x, y)
end

-- the spot on the game's own World Map, which is always the client's
local function GameSpot(m, x, y)
    if DevMap(m) then return RetailSpot(m - DEV_MAP, x, y) end
    return m, x, y
end

local function MapName(m)
    local dev = DevMap(m)
    if dev then return dev[1] end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    return info and info.name
end

-- every way to get the item, player finds first: { left, look (its pins' and dot's), pins = { {m, x, y, look, who} },
-- zone, exact, dungeon, role, who = { name, lv, rank, npc } }; a world drop's pins each name their own mob
-- a drop chance in percent, as short as it reads: 20%, 4.5%, 0.3%, <0.1%
local function Pct(p)
    if p >= 10 then return ("%d%%"):format(math.floor(p + 0.5)) end
    if p >= 0.1 then return (("%.1f"):format(p):gsub("%.0$", "")) .. "%" end
    return "<0.1%"
end

-- a source's drop rate in words: "1.2% in the beta", "4.5% in Classic"; short: just the number
local function RateText(src, short)
    if short then return Pct(src.chance) end
    return Pct(src.chance) .. (src.beta and " in the beta" or " in Classic")
end

local function Entries(e, id, sources)
    local out = {}
    for _, s in ipairs(e and e.s or {}) do
        local how = KIND_OF[s.t] or "Seen"
        local name = s.n or (s.npc and ("NPC " .. s.npc))
        local left = name or (s.t == "x" and "From a container") or how
        if s.lv and s.lv > 0 then left = left .. " (" .. s.lv .. ")" end
        local look = (s.t == "v" and "vendor") or ((s.t == "o" or s.t == "x") and "object") or "drop"
        local pins = {}
        if s.m and s.x and s.y then pins[1] = { m = s.m, x = s.x, y = s.y, look = look } end
        out[#out + 1] = { left = left, look = look, pins = pins, zone = s.z or "", exact = true,
            role = "Seen by a player: " .. how,
            who = { name = name or how, lv = (s.lv and s.lv > 0) and tostring(s.lv) or nil, npc = s.npc } }
    end
    for _, src in ipairs(sources) do
        local t = src.t
        local look = (t == "v" and "vendor") or (t == "w" and "world") or (t == "s" and "skin") or (t == "q" and "quest") or
            ((t == "o" or t == "c" or t == "k") and "object") or "drop"
        local left
        if t == "w" then
            left = "World drop, " .. (src.count or 0) .. " kinds of mobs"
        elseif t == "s" then
            left = "Skinned from " .. (src.count == 1 and "1 kind of beast" or ((src.count or 0) .. " kinds of beasts"))
        elseif t == "c" then
            left = "From " .. (src.name or "?")
        elseif t == "k" then
            left = "Made with " .. src.name .. ((src.skill or 0) > 0 and (" (" .. src.skill .. ")") or "")
        else
            left = (src.name or "?") .. (src.lv and (" (" .. src.lv .. ")") or "")
        end
        -- inside a dungeon the line names it: its only pin is the entrance, on another zone's map. leftShort, without
        -- the dungeon, stands in when that is too long (the caption and the status name the dungeon too)
        local leftShort
        if src.dungeon and #src.pins == 0 then
            leftShort = left .. (src.chance and (", " .. RateText(src, true)) or "")
            left = left .. " in " .. src.dungeon.name
        end
        if src.chance then left = left .. ", " .. RateText(src, true) end
        local pins, dungeon = {}, nil
        for _, p in ipairs(src.pins) do
            local m, x, y = OnClientMap(p.m, p.x, p.y)
            if m then pins[#pins + 1] = { m = m, x = x, y = y, look = look, who = p.npc and p or nil } end
        end
        -- a mob inside a dungeon is pinned at the entrance
        if #src.pins == 0 and src.dungeon then
            local m, x, y = OnClientMap(src.dungeon.m, src.dungeon.x, src.dungeon.y)
            if m then
                dungeon, look = src.dungeon.name, "entrance"
                pins[1] = { m = m, x = x, y = y, look = look }
            end
        end
        local role = ROLE[t]
        if t == "q" then role = "Gives the quest " .. left end
        if t == "w" then role = "One of " .. (src.count or 0) .. " kinds of mobs that drop it" end
        if t == "s" then role = (src.count or 0) == 1 and "Skin it for this" or ("One of " .. src.count .. " kinds of beasts to skin for it") end
        -- a vein or herb: the skill it takes
        if src.gather then role = src.gather end
        if src.chance and role then role = role .. ", " .. RateText(src) end
        if t == "q" then
            left = "Quest: " .. left
            leftShort = leftShort and ("Quest: " .. leftShort)
        end
        if (t == "w" or t == "s") and #pins > 0 then
            -- a world drop or skinning: its count as a line of its own, then one line per zone with the most of its
            -- mobs, each with the mob kept there; a click on a zone opens that zone's map
            out[#out + 1] = { left = left, look = look, pins = {}, header = true }
            for _, p in ipairs(pins) do
                local mob = p.who and (p.who.name .. (p.who.lv and (" (" .. p.who.lv .. ")") or ""))
                out[#out + 1] = { left = MapName(p.m) or "Zone " .. p.m, rightText = mob or "", look = look, pins = { p },
                    role = role, who = p.who }
            end
        else
            -- the same node under two records (two Copper Vein entries with one chance) is one line with every spot
            local same
            for _, en in ipairs(t == "o" and not dungeon and #pins > 0 and out or {}) do
                if en.places and en.left == left then same = en break end
            end
            if same then
                for _, p in ipairs(pins) do same.pins[#same.pins + 1] = p end
                same.places[#same.places + 1] = src
            else
                out[#out + 1] = { left = left, leftShort = leftShort, look = look, pins = pins, dungeon = dungeon, role = role,
                    who = (t == "q" and src.giver) or ((t ~= "w" and t ~= "s" and t ~= "c" and t ~= "k") and src) or nil,
                    places = t == "o" and not dungeon and { src } or nil }
            end
        end
    end
    return out
end

-- an item's spots on the client's own maps, for its pins on the World Map and the minimap (FavPins.lua): m, x, y,
-- look, who, entry (its where line) and dungeon (the name, for a pin at an entrance)
function UI.GameSpots(id)
    local out = {}
    for _, en in ipairs(Entries(ns.Finds.Get(id), id, D.Sources(id))) do
        for _, p in ipairs(en.pins) do
            local m, x, y = GameSpot(p.m, p.x, p.y)
            if m then out[#out + 1] = { m = m, x = x, y = y, look = p.look, who = p.who, entry = en, dungeon = en.dungeon } end
        end
    end
    return out
end

-- an item's name and quality colour as its rows show them
function UI.ItemLabel(id)
    local e, row = ns.Finds.Get(id), D.Seed(id)
    local name = (e and e.nm) or C_Item.GetItemInfo(id) or (row and RowName(row)) or ("Item " .. id)
    local _, _, gameQ = C_Item.GetItemInfo(id)
    return name, T.QualityHex((e and e.q) or (row and row.q) or gameQ)
end
UI.ItemIcon = ItemIcon

-- the short spot a source line ends with: coordinates for one spot, a count for several, the zone for a spot on
-- another map, nothing for a world drop (its pins are a few of many)
local function Spot(en, shown)
    local p = en.pins[1]
    if not p or en.look == "world" then return en.exact and en.zone or "" end
    -- a mob in several zones counts the spots of the zone on the map
    local n, here = 0, nil
    for _, q in ipairs(en.pins) do
        if q.m == shown then n, here = n + 1, here or q end
    end
    if n == 0 then return MapName(p.m) or en.zone or "" end
    if n == 1 then return ("%.1f, %.1f"):format(here.x / 10, here.y / 10) end
    return n .. " spots"
end

-- the status rows, { label, value }: what the item is, how to get it (the first known source; a find with no known
-- source says where it was found), the drop rate for drops (Forever beta's where researched, else Classic's), and
-- who found it
local ITEM_STATUS = { h = "Changed by a hotfix", c = "Changed from Classic", o = "Old Classic item" }
local DROPPED = { l = true, o = true, w = true, r = true, c = true }
local function StatusFacts(e, id, row, hidden, sources)
    local kind = (e and e.k == "c" and "c") or (row and row.kind)
    local item = hidden and "Hidden by Blizzard" or ITEM_STATUS[kind] or "New item"
    -- a worked-out name is never passed off as the real one
    if hidden and row.name ~= "" then item = item .. ", name not confirmed" end
    local how, rate
    local s = sources[1]
    if s then
        local p = s.pins[1]
        local m = p and OnClientMap(p.m, p.x, p.y)
        local at = (s.dungeon and #s.pins == 0 and s.dungeon.name) or (m and MapName(m))
        local there = at and (" in " .. at) or ""
        local t = s.t
        if t == "q" then how = "Quest reward: " .. (s.name or "?") .. (s.lv and (" (" .. s.lv .. ")") or "")
        elseif t == "w" then how = "World drop"
        elseif t == "v" then how = "Sold by " .. (s.name or "a vendor") .. there
        elseif t == "k" then how = "Crafted with " .. (s.name or "a profession") .. ((s.skill or 0) > 0 and (" (" .. s.skill .. ")") or "")
        elseif t == "c" then how = "Inside " .. (s.name or "a container")
        elseif t == "s" then how = "Skinned from " .. ((s.count or 0) == 1 and "1 kind of beast" or ((s.count or 0) .. " kinds of beasts"))
        elseif t == "o" and s.gather then how = (s.gather == "Mining" and "Mined from " or "Gathered from ") .. (s.name or "a node") .. there
        elseif t == "o" then how = "Looted from " .. (s.name or "an object") .. there
        else how = "Drops from " .. (s.name or "a mob") .. there end
        if t == "l" or t == "o" or t == "w" then rate = s.chance and RateText(s):gsub("^%l", string.upper) or "Unknown" end
    end
    local f = e and e.s and e.s[1]
    if not how and f and f.z then
        how = "Found in " .. f.z
        rate = DROPPED[f.t] and "Unknown" or nil
    end
    local found
    if e then
        local who = e.by or ((e.mine and ns.settings.credit ~= "anon") and UnitName("player")) or "Anonymous"
        local n = ns.Finds.Reporters(e)
        found = "By " .. who .. (e.at and (", " .. date("%b %d", e.at)) or "") .. ", " .. n .. (n == 1 and " player" or " players")
    else
        found = (row and row.beta) and "Seen in the beta" or "Not yet in Forever"
    end
    local facts = { { "Item", item }, { "How to get", how or "Not known yet" } }
    if rate then facts[#facts + 1] = { "Drop rate", rate } end
    facts[#facts + 1] = { "Found", found }
    return facts
end

local function HasArt(mapID)
    if DevMap(mapID) then return true end
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    return layers and layers[1] ~= nil
end

-- the client stores an edge tile in the next power of two up from 16
local function FileSize(px)
    local n = 16
    while n < px do n = n * 2 end
    return n
end

-- the zone's own map art in a frame of frameW x frameH, scaled to cover it (the frame shows part of the zone and the
-- view pans over the rest), with every explored area drawn over it (Data\MapOverlays.lua) so the zone shows explored
-- whatever the player has seen. map.w / map.h are the art's size, map.fw / map.fh the frame's; returns the frame's
-- size, or nil when the map has no art
local function DrawMap(map, mapID, frameW, frameH)
    if map.artID == mapID and map.artArea == frameW and map.artMax == frameH then return frameW, frameH end
    map.artID = nil
    local dev = DevMap(mapID)
    local info, tex
    if dev then
        info = { layerWidth = dev[2], layerHeight = dev[3], tileWidth = dev[4], tileHeight = dev[5] }
        tex = {}
        for file in dev[6]:gmatch("%d+") do tex[#tex + 1] = DEV_ART .. file .. ".blp" end
    else
        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
        info = layers and layers[1]
        tex = info and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mapID, 1)
    end
    if not info or type(tex) ~= "table" or #tex == 0 or (info.layerWidth or 0) <= 0 or (info.layerHeight or 0) <= 0 then return end
    local s = math.max(frameW / info.layerWidth, frameH / info.layerHeight)
    local w, h = info.layerWidth * s, info.layerHeight * s
    local cols = math.ceil(info.layerWidth / info.tileWidth)
    local rows = math.ceil(info.layerHeight / info.tileHeight)
    local tw, th = info.tileWidth * s, info.tileHeight * s
    local canvas = map.canvas
    local n = 0
    for row = 1, rows do
        for col = 1, cols do
            n = n + 1
            local t = map.tiles[n]
            if not t then
                t = canvas:CreateTexture(nil, "ARTWORK")
                map.tiles[n] = t
            end
            t:SetTexture(tex[(row - 1) * cols + col])
            t:SetSize(tw, th)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (col - 1) * tw, -(row - 1) * th)
            t:Show()
        end
    end
    for i = n + 1, #map.tiles do map.tiles[i]:Hide() end
    local k = 0
    local over = dev and dev[7] or (D.overlays and D.overlays[mapID])
    for part in (over or ""):gmatch("[^;]+") do
        local v = {}
        for num in part:gmatch("%d+") do v[#v + 1] = tonumber(num) end
        local ow, oh, ox, oy = v[1], v[2], v[3], v[4]
        local across, down = math.ceil(ow / info.tileWidth), math.ceil(oh / info.tileHeight)
        for j = 1, down do
            local ph = j < down and info.tileHeight or (oh - (down - 1) * info.tileHeight)
            local fh = j < down and info.tileHeight or FileSize(ph)
            for c = 1, across do
                local pw = c < across and info.tileWidth or (ow - (across - 1) * info.tileWidth)
                local fw = c < across and info.tileWidth or FileSize(pw)
                local file = v[4 + (j - 1) * across + c]
                if file then
                    k = k + 1
                    local t = map.over[k]
                    if not t then
                        t = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
                        map.over[k] = t
                    end
                    t:SetTexture(dev and (DEV_ART .. file .. ".blp") or file)
                    t:SetSize(pw * s, ph * s)
                    t:SetTexCoord(0, pw / fw, 0, ph / fh)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (ox + (c - 1) * info.tileWidth) * s, -(oy + (j - 1) * info.tileHeight) * s)
                    t:Show()
                end
            end
        end
    end
    for i = k + 1, #map.over do map.over[i]:Hide() end
    map:SetSize(frameW, frameH)
    canvas:SetSize(w, h)
    map.w, map.h, map.fw, map.fh = w, h, frameW, frameH
    map.artID, map.artArea, map.artMax = mapID, frameW, frameH
    return frameW, frameH
end

-- the view over the art: zoom z and the visible window's top left (vx, vy) in zoomed pixels, always inside the art;
-- pins keep their size and follow the art
local MAX_ZOOM, OPEN_ZOOM, OPEN_MARGIN = 4, 2.5, 0.08

local function Clamp(v, lo, hi)
    return v < lo and lo or (v > hi and hi or v)
end

-- the spots that get a pin: the first in each cell of cw x ch (per mille), in the list's order; out is reused
local taken = {}
local function Thin(spots, cw, ch, out)
    wipe(out)
    wipe(taken)
    for _, s in ipairs(spots) do
        local key = math.floor(s.x / cw) * 100000 + math.floor(s.y / ch)
        if not taken[key] then
            taken[key] = true
            out[#out + 1] = s
        end
    end
    return out
end
UI.ThinSpots = Thin
function UI.PinCell() return U(PIN_CELL) end

-- pins for the spots in view (map.spots, thinned again whenever the zoom changes); the rest of the pool hides
local function LayPins(map)
    local w, h, z, vx, vy = map.w, map.h, map.z, map.vx, map.vy
    local fw, fh = map.fw or w, map.fh or h
    if map.thinZ ~= z then
        map.thinZ = z
        Thin(map.spots, U(PIN_CELL) / (w * z) * 1000, U(PIN_CELL) / (h * z) * 1000, map.shown)
    end
    local n, level = 0, map:GetFrameLevel() + 2
    for _, s in ipairs(map.shown) do
        local x, y = s.x / 1000 * w * z - vx, s.y / 1000 * h * z - vy
        if x >= 0 and x <= fw and y >= 0 and y <= fh then
            n = n + 1
            local p = map.pins[n]
            if not p then
                p = UI.NewPin(map)
                map.pins[n] = p
            end
            if p.look ~= s.look or p.styled ~= map.styled then
                UI.StylePin(p, s.look)
                p.styled = map.styled
            end
            p:SetFrameLevel(level)
            p:SetAlpha((not detail.hi or detail.hi == s.si) and 1 or 0.3)
            p.source, p.entry, p.who, p.m, p.x, p.y, p.on = s.si, s.en, s.who, s.m, s.x, s.y, true
            p:ClearAllPoints()
            p:SetPoint("CENTER", map, "TOPLEFT", x, -y)
            p:Show()
        end
    end
    for i = n + 1, #map.pins do
        local p = map.pins[i]
        p.on = false
        p:Hide()
    end
end

local function SetView(map, z, vx, vy)
    local w, h = map.w, map.h
    local fw, fh = map.fw or w, map.fh or h
    z = Clamp(z, 1, MAX_ZOOM)
    vx, vy = Clamp(vx, 0, w * z - fw), Clamp(vy, 0, h * z - fh)
    map.z, map.vx, map.vy = z, vx, vy
    -- a scaled frame reads its offsets in its own scale
    map.canvas:SetScale(z)
    map.canvas:ClearAllPoints()
    map.canvas:SetPoint("TOPLEFT", map, "TOPLEFT", -vx / z, vy / z)
    LayPins(map)
end

-- the opening view: the box of every spot with a margin, at most OPEN_ZOOM, the whole zone when they spread out
local function FitView(map)
    local x0, y0, x1, y1
    for _, s in ipairs(map.spots) do
        local x, y = s.x / 1000, s.y / 1000
        x0, y0 = math.min(x0 or x, x), math.min(y0 or y, y)
        x1, y1 = math.max(x1 or x, x), math.max(y1 or y, y)
    end
    local fw, fh = map.fw or map.w, map.fh or map.h
    if not x0 then return SetView(map, 1, (map.w - fw) / 2, (map.h - fh) / 2) end
    -- the zoom at which the pins' box, with its margin, fits the frame both ways
    local z = math.min(OPEN_ZOOM, fw / (map.w * (x1 - x0 + 2 * OPEN_MARGIN)), fh / (map.h * (y1 - y0 + 2 * OPEN_MARGIN)))
    SetView(map, z, (x0 + x1) / 2 * map.w * z - fw / 2, (y0 + y1) / 2 * map.h * z - fh / 2)
end

local function CursorOnMap(map)
    local x, y = GetCursorPosition()
    local s = map:GetEffectiveScale()
    return x / s - map:GetLeft(), map:GetTop() - y / s
end

-- a round texture: a colour cut by the game's circle mask
local function Dot(parent, sub)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetPoint("CENTER")
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(t)
    t:AddMaskTexture(mask)
    return t
end

-- the hover card of a pin: the mob's portrait once the game has its model, who it is, what it does, where
local card
local function HideCard()
    if card then
        card.pin = nil
        card:Hide()
    end
end
UI.HideCard = HideCard

local function LayCard()
    local face = card.face:IsShown()
    local x = face and (U(8) + U(52) + U(8)) or U(10)
    local y = -U(8)
    local textW = 0
    for _, fs in ipairs({ card.title, card.sub, card.role }) do
        fs:ClearAllPoints()
        if (fs:GetText() or "") ~= "" then
            fs:SetPoint("TOPLEFT", x, y)
            y = y - fs:GetStringHeight() - U(3)
            textW = math.max(textW, fs:GetStringWidth())
        end
    end
    local bottom = face and math.min(y, -(U(8) + U(52) + U(3))) or y
    card.place:ClearAllPoints()
    card.place:SetPoint("TOPLEFT", U(10), bottom - U(2))
    local w = math.max(x + textW, U(10) + card.place:GetStringWidth()) + U(10)
    card:SetSize(math.max(w, U(150)), -bottom + U(2) + card.place:GetStringHeight() + U(8))
end

local function BuildCard()
    card = CreateFrame("Frame", nil, UIParent)
    card:SetFrameStrata("TOOLTIP")
    card:SetClampedToScreen(true)
    T.Panel(card, C.tipBg, C.tipLine)
    card.face = CreateFrame("Frame", nil, card)
    card.face:SetSize(U(52), U(52))
    card.face:SetPoint("TOPLEFT", U(8), -U(8))
    T.Solid(card.face, "BACKGROUND", C.black):SetAllPoints()
    T.Border(card.face, C.tipLine, 1, "OVERLAY")
    card.model = CreateFrame("PlayerModel", nil, card.face)
    card.model:SetPoint("TOPLEFT", 1, -1)
    card.model:SetPoint("BOTTOMRIGHT", -1, 1)
    -- a model the client has to fetch first arrives later; the card grows its portrait then
    card.model:SetScript("OnModelLoaded", function()
        if card:IsShown() and card.npc then
            card.face:Show()
            LayCard()
        end
    end)
    card.title = T.Text(card, 14, "FFFFFF")
    card.sub = T.Text(card, 12, C.dim)
    card.role = T.Text(card, 12, C.ink)
    card.place = T.Text(card, 12, C.dim)
    card:Hide()
end

local function ShowCard(p)
    local en = p.entry
    if not en then return end
    if not card then BuildCard() end
    local who = p.who or en.who or {}
    card.pin = p
    card.title:SetText(who.name or en.left)
    local sub = who.lv and ("Level " .. who.lv) or ""
    local rank = who.rank and RANK[who.rank]
    if rank then sub = sub ~= "" and (sub .. " " .. rank) or rank end
    card.sub:SetText(sub)
    card.role:SetText(en.role or "")
    local zone = MapName(p.m)
    local at = ("%.1f, %.1f"):format(p.x / 10, p.y / 10)
    if en.dungeon then
        card.place:SetText(en.dungeon .. " entrance  " .. at)
    else
        card.place:SetText((zone and (zone .. "  ") or "") .. at)
    end
    card.npc = who.npc
    card.face:Hide()
    card.model:ClearModel()
    if who.npc then
        card.model:SetCreature(who.npc)
        card.model:SetPortraitZoom(1)
        local file = card.model:GetModelFileID()
        if file and file ~= 0 then card.face:Show() end
    end
    card:ClearAllPoints()
    card:SetPoint("BOTTOMLEFT", p, "TOPRIGHT", U(2), U(2))
    card:Show()
    LayCard()
end

-- a map pin: a soft halo, a dark ring, the coloured dot, and for an entrance a dark centre; the mouse area is
-- larger than the dot. Hover shows the card; a click lights its source in the panel (pins on the game's map have none).
local function NewPin(parent)
    local p = CreateFrame("Frame", nil, parent)
    p.glow, p.ring, p.fill, p.core = Dot(p, 1), Dot(p, 2), Dot(p, 3), Dot(p, 4)
    p:EnableMouse(true)
    p:SetScript("OnEnter", ShowCard)
    p:SetScript("OnLeave", HideCard)
    p:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.source then return end
        detail.hi = detail.hi ~= self.source and self.source or nil
        UI.ShowDetail(selected)
    end)
    return p
end
UI.NewPin = NewPin

local function StylePin(p, look)
    local l = PIN_LOOK[look] or PIN_LOOK.drop
    local size, ring = U(l[1]), U(l[2])
    p.look = look
    p:SetSize(math.max(size, U(PIN_HIT)), math.max(size, U(PIN_HIT)))
    p.glow:SetSize(size * 1.8, size * 1.8)
    p.glow:SetColorTexture(T.RGB(l[4]))
    p.glow:SetAlpha(0.3)
    p.ring:SetSize(size, size)
    p.ring:SetColorTexture(T.RGB(l[3]))
    p.fill:SetSize(size - 2 * ring, size - 2 * ring)
    p.fill:SetColorTexture(T.RGB(l[4]))
    p.core:SetShown(l[5] ~= nil)
    if l[5] then
        p.core:SetSize(size * 0.36, size * 0.36)
        p.core:SetColorTexture(T.RGB(l[5]))
    end
end
UI.StylePin = StylePin

-- a zone chip's words: the zone and its spot count, or the dungeon for a zone holding only its entrance
local function ZoneLabel(m)
    local dungeon = detail.zoneEntrance[m]
    if dungeon then return dungeon end
    return (MapName(m) or ("Zone " .. m)) .. " " .. detail.zoneCount[m]
end

-- the shown zone becomes another one: a lit line with no pins there goes dark, so its pins are not looked for
local function PickZone(m)
    local lit = detail.hi and detail.entries and detail.entries[detail.hi]
    local here = false
    for _, p in ipairs(lit and lit.pins or {}) do
        if p.m == m then here = true break end
    end
    if lit and not here then detail.hi = nil end
    detail.zone = m
    UI.ShowDetail(selected)
end

-- the zone chips over the map when the item has pins in more than one zone (the caption names a lone zone): one
-- chip per zone, the shown one lit; a row longer than the map ends in a "+N more" list, the shown zone keeping its chip
local ZONE_GAP = 4
local function LayZones(map, mapID, mapW)
    local list, chips, more = detail.zoneList, map.zoneChips, map.zoneMore
    local on = mapID ~= nil and #list > 1
    map.caption:SetShown(not on)
    for _, c in ipairs(chips) do c:Hide() end
    more:Hide()
    if not on then return end
    local avail = mapW - U(12)
    local widths, total = {}, -U(ZONE_GAP)
    for i, m in ipairs(list) do
        local c = chips[i]
        if not c then
            c = T.Chip(map.top, 11)
            c:SetHeight(U(18))
            c:Hide()
            c.pad = U(6)
            c:SetScript("OnClick", function(self) PickZone(self.m) end)
            chips[i] = c
        end
        c.m = m
        c:SetLabel(ZoneLabel(m))
        c:SetOn(m == mapID)
        widths[i] = c:GetWidth()
        total = total + widths[i] + U(ZONE_GAP)
    end
    -- how many chips fit beside the list; the shown zone takes the last place when it would be in the list
    local fit, hidden = #list, nil
    if total > avail then
        local x = 0
        fit = 0
        hidden = {}
        -- room for the list's box: as wide as the longest zone it could hold
        map.measure:SetText("+" .. #list .. " more")
        local moreW = map.measure:GetStringWidth()
        for _, m in ipairs(list) do
            map.measure:SetText(ZoneLabel(m))
            moreW = math.max(moreW, map.measure:GetStringWidth())
        end
        moreW = moreW + U(10) + U(18)
        for i = 1, #list do
            if x + widths[i] + U(ZONE_GAP) + moreW > avail then break end
            x = x + widths[i] + U(ZONE_GAP)
            fit = i
        end
        fit = math.max(fit, 1)
        local shownAt
        for i, m in ipairs(list) do if m == mapID then shownAt = i end end
        if shownAt and shownAt > fit then
            chips[fit], chips[shownAt] = chips[shownAt], chips[fit]
            list[fit], list[shownAt] = list[shownAt], list[fit]
            widths[fit], widths[shownAt] = widths[shownAt], widths[fit]
        end
        for i = fit + 1, #list do hidden[#hidden + 1] = { list[i], ZoneLabel(list[i]) } end
    end
    local x = U(6)
    for i = 1, fit do
        local c = chips[i]
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", map.top, "TOPLEFT", x, -U(6))
        c:Show()
        x = x + widths[i] + U(ZONE_GAP)
    end
    if hidden then
        more.options = hidden
        local label = "+" .. #hidden .. " more"
        more.boxLabel = function() return label end
        -- the box is as wide as its longest zone, since its list opens exactly as wide as the box
        map.measure:SetText(label)
        local w = map.measure:GetStringWidth()
        for _, o in ipairs(hidden) do
            map.measure:SetText(o[2])
            w = math.max(w, map.measure:GetStringWidth())
        end
        more:SetWidth(w + U(10) + U(18))
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", map.top, "TOPLEFT", x, -U(6))
        more:Refresh()
        more:Show()
    end
end

-- the item box's lines (8 rows, the same for every item) and the map's least height
local TIP_LINES = 8 * U(17)
local MAP_H = U(150)
-- the item's tooltip lines under its name, each { left, right, r, g, b, rr, rg, rb }: the game's own once the server
-- sent the item, else the datamined one (Tooltip.lua), else a note that nothing is known yet
local tipOut = {}
local tipCollect = { n = 0 }
function tipCollect:ClearLines() wipe(tipOut) self.n = 0 end
function tipCollect:AddLine(text, r, g, b)
    self.n = self.n + 1
    if self.n > 1 then tipOut[#tipOut + 1] = { text or "", "", r or 1, g or 1, b or 1, 1, 1, 1 } end
end
function tipCollect:AddDoubleLine(a, b2, r, g, bl, rr, rg, rb)
    self.n = self.n + 1
    if self.n > 1 then tipOut[#tipOut + 1] = { a or "", b2 or "", r or 1, g or 1, bl or 1, rr or 1, rg or 1, rb or 1 } end
end
-- second value: true when the lines are the game's own
local function TipLines(id)
    wipe(tipOut)
    if C_Item.GetItemInfo(id) and C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local data = C_TooltipInfo.GetItemByID(id)
        for i, l in ipairs(data and data.lines or {}) do
            local left, right = l.leftText or "", l.rightText or ""
            -- the sell price line is left out
            local sellWord = type(SELL_PRICE) == "string" and SELL_PRICE or "Sell Price"
            local sale = l.price ~= nil or (type(left) == "string" and left:find(sellWord, 1, true) == 1)
            if i > 1 and not sale and (left ~= "" or right ~= "") then
                local lc, rc = l.leftColor, l.rightColor
                tipOut[#tipOut + 1] = { left, right, lc and lc.r or 1, lc and lc.g or 1, lc and lc.b or 1, rc and rc.r or 1, rc and rc.g or 1, rc and rc.b or 1 }
            end
        end
        if #tipOut > 0 then return tipOut, true end
    end
    if T.DataTip and T.DataTip(tipCollect, id) then return tipOut, false end
    wipe(tipOut)
    tipOut[1] = { "The game has not sent this item yet.", "", 0.5, 0.5, 0.5, 1, 1, 1 }
    return tipOut, false
end

local function ShowDetail(id)
    local d = detail
    local parts = { d.head, d.where, d.status }
    -- the pins are laid out anew: a card left up would describe whatever pin now stands there
    HideCard()
    if not id then
        for _, p in ipairs(parts) do p:Hide() end
        d.empty:Show()
        return
    end
    d.empty:Hide()
    local e = ns.Finds.Get(id)
    if e and e.pend then e = nil end
    local row = D.Seed(id)
    local W = d.frame:GetWidth()

    -- the item box: icon, name, Link in chat and the star on one row, the tooltip's lines under them
    local q = (e and e.q) or (row and RowQuality(row)) or 1
    d.q = q
    d.icon:SetTexture(ItemIcon(id))
    d.iconBorder:SetColor(T.QualityHex(q))
    -- the head's inner width, less the icon and its gap, then Link in chat and the star with their gaps
    d.name:SetWidth(W - U(20) - U(10) - U(30) - U(8) - U(6) - U(22) - U(6) - U(22) - U(10))
    local fav = UI.IsFavorite(id)
    d.fav.bg:SetColorTexture(T.RGB(fav and "3A2C1A" or "17120C"))
    d.fav.edge:SetColor(fav and C.title or C.frame)
    d.fav.mark:SetOn(fav, C.gold)
    d.name:SetText((e and e.nm) or C_Item.GetItemInfo(id) or (row and RowName(row)) or ("Item " .. id))
    d.name:SetTextColor(T.RGB(T.QualityHex(q)))
    local hidden = not e and row and row.kind == "x" and not C_Item.GetItemInfo(id)
    -- the server is asked once per item; its answer redraws the box with the game's own tooltip
    if not C_Item.GetItemInfo(id) and not d.asked[id] and C_Item.RequestLoadItemDataByID then
        d.asked[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    -- a long name wraps and its row grows into the lines' room, never the map's; the icon stays centred on the row
    local rowH = math.max(U(30), d.name:GetStringHeight())
    d.iconFrame:ClearAllPoints()
    d.iconFrame:SetPoint("TOPLEFT", U(10), -(U(8) + (rowH - U(30)) / 2))
    local lines, fromGame = TipLines(id)
    d.tipGame = fromGame
    local function Layout(bodyW)
        local y = 0
        for i, l in ipairs(lines) do
            local fs = d.tipLines[i]
            if not fs then
                fs = { left = T.Text(d.tipBody, 13, "FFFFFF"), right = T.Text(d.tipBody, 13, "FFFFFF") }
                fs.left:SetWordWrap(true)
                fs.left:SetJustifyH("LEFT")
                fs.right:SetJustifyH("RIGHT")
                d.tipLines[i] = fs
            end
            fs.right:SetText(l[2])
            fs.right:SetTextColor(l[6], l[7], l[8])
            local rightW = l[2] ~= "" and (FullWidth(fs.right) + U(8)) or 0
            -- emptied first, so a wrapped height is measured anew at this width, never kept from the last layout
            fs.left:SetText("")
            fs.left:SetWidth(bodyW - rightW)
            fs.left:SetText(l[1])
            fs.left:SetTextColor(l[3], l[4], l[5])
            fs.left:ClearAllPoints()
            fs.left:SetPoint("TOPLEFT", 0, -y)
            fs.right:ClearAllPoints()
            fs.right:SetPoint("TOPRIGHT", 0, -y)
            fs.left:Show()
            fs.right:SetShown(l[2] ~= "")
            y = y + math.max(U(17), fs.left:GetStringHeight())
        end
        for i = #lines + 1, #d.tipLines do
            d.tipLines[i].left:Hide()
            d.tipLines[i].right:Hide()
        end
        return y
    end
    -- the lines take the scroll frame's own width, less a sliver so a last glyph's overhang is never clipped, and
    -- less the bar's room always, so they are laid out once and the right-hand values never move
    d.tipScroll:ClearAllPoints()
    d.tipScroll:SetPoint("TOPLEFT", U(10), -(U(8) + rowH + U(2)))
    d.tipScroll:SetPoint("TOPRIGHT", -U(10), -(U(8) + rowH + U(2)))
    local fullW = d.tipScroll:GetWidth()
    if not fullW or fullW < U(100) then fullW = W - U(20) - U(20) end
    fullW = fullW - U(3)
    d.laidW = W
    local bodyW = fullW - U(14)
    local total = Layout(bodyW)
    d.tipBody:SetSize(bodyW, total)
    if d.tipFor ~= id then
        d.tipFor = id
        d.tipBar:SetValue(0)
        d.tipScroll:SetVerticalScroll(0)
    end
    d.head:Show()

    -- an item's known places are read once while it stays shown: a vein or a common mob has hundreds of spawns
    if d.srcFor ~= id then d.srcFor, d.src = id, D.Sources(id) end
    -- status: one fact per row, a quiet label and the value beside it; a long value wraps instead of being cut
    local facts = StatusFacts(e, id, row, hidden, d.src)
    local valueX = U(10) + U(84) + U(10)
    local valueW = W - U(20) - valueX - U(10)
    local y = d.status.top + U(8)
    for i, r in ipairs(d.rows) do
        local fact = facts[i]
        r.key:SetShown(fact ~= nil)
        r.value:SetShown(fact ~= nil)
        if fact then
            if i > 1 then y = y + U(4) end
            r.key:SetText(fact[1])
            r.value:SetWidth(valueW)
            r.value:SetText(fact[2])
            r.key:SetPoint("TOPLEFT", U(10), -(y + U(3)))
            r.value:SetPoint("TOPLEFT", valueX, -(y + U(3)))
            y = y + math.max(U(19), r.value:GetStringHeight() + U(6))
        end
    end
    local statusH = y + U(8)
    d.status:SetHeight(statusH)

    -- where it drops: the map of the first source with a pin on a map the game can draw, every pin on it, then
    -- one line per source; a clicked line lights its own pins and dims the rest
    if d.shownId ~= id then d.hi, d.zone, d.shownId = nil, nil, id end
    local entries = Entries(e, id, d.src)
    -- kept for the website's builder, which reads each line's spot from them
    d.entries = entries
    -- every zone with pins the game can draw, in the lines' order, with its spot count; a zone holding only a dungeon's
    -- entrance goes by the dungeon's name
    wipe(d.zoneList)
    wipe(d.zoneCount)
    wipe(d.zoneEntrance)
    wipe(d.zoneArt)
    for _, en in ipairs(entries) do
        for _, p in ipairs(en.pins) do
            local m = p.m
            if d.zoneArt[m] == nil then d.zoneArt[m] = HasArt(m) end
            if d.zoneArt[m] then
                if not d.zoneCount[m] then
                    d.zoneList[#d.zoneList + 1] = m
                    d.zoneCount[m] = 0
                end
                d.zoneCount[m] = d.zoneCount[m] + 1
                if p.look ~= "entrance" then
                    d.zoneEntrance[m] = false
                elseif d.zoneEntrance[m] == nil then
                    d.zoneEntrance[m] = en.dungeon
                end
            end
        end
    end
    -- the picked zone chip, else the lit line's first zone, else the first zone
    local mapID = d.zone and d.zoneCount[d.zone] and d.zone
    local lit = d.hi and entries[d.hi]
    for _, p in ipairs(not mapID and lit and lit.pins or {}) do
        if d.zoneArt[p.m] then mapID = p.m break end
    end
    mapID = mapID or d.zoneList[1]
    local nLines = #entries == 0 and 2 or math.min(#entries, MAX_SOURCES + 1)
    -- the item box is one size for every item (TIP_LINES of lines; a long name takes its rows from them). Status ends
    -- just under its rows, and the map, always the full width with its art covering the frame, takes the height that
    -- is left (an item with no map gets an empty frame of the same size); the window is sized so a world drop with its
    -- three zones still gets MAP_H, and only an item with still more below the map gets less
    local shownH = math.max(U(34), TIP_LINES - (rowH - U(30)))
    local headH = U(8) + rowH + U(2) + shownH + U(8)
    local panelH = d.frame:GetHeight()
    local mapBoxH = MAP_H
    if panelH and panelH > 0 then
        local others = U(10) + headH + U(6) + d.where.top + U(8) + U(8) + nLines * U(18) + U(8) + U(8) + statusH + U(10)
        mapBoxH = math.max(U(60), panelH - others)
    end
    local mapW, mapH
    local map = d.map
    if mapID then mapW, mapH = DrawMap(map, mapID, W - U(40), mapBoxH) end
    d.tipScroll:SetHeight(shownH)
    d.tipBar:SetShown(total > shownH)
    d.tipBar:SetMinMaxValues(0, math.max(0, total - shownH))
    d.head:SetHeight(headH)
    for _, p in ipairs(map.pins) do
        p.on = false
        p:Hide()
    end
    wipe(map.spots)
    if mapW then
        map:ClearAllPoints()
        map:SetPoint("TOP", d.where, "TOP", 0, -(d.where.top + U(8)))
        local level = map:GetFrameLevel()
        map.canvas:SetFrameLevel(level + 1)
        map.top:SetFrameLevel(level + 3)
        local dungeon
        -- every spot on this map, the lit source's first so its pins win a shared cell; pins restyle once per draw
        for pass = 1, 2 do
            for si, en in ipairs(entries) do
                if (pass == 1) == (d.hi == si) then
                    for _, pin in ipairs(en.pins) do
                        if pin.m == mapID then
                            pin.si, pin.en = si, en
                            map.spots[#map.spots + 1] = pin
                            if pin.look == "entrance" then dungeon = dungeon or en.dungeon end
                        end
                    end
                end
            end
        end
        map.thinZ, map.styled = nil, (map.styled or 0) + 1
        -- a new item or map opens framed on its pins; a redraw of the same one keeps the player's zoom
        local key = id .. ":" .. mapID .. ":" .. mapW .. ":" .. mapH
        if map.viewKey ~= key then
            map.viewKey = key
            FitView(map)
        else
            SetView(map, map.z, map.vx, map.vy)
        end
        local zone = MapName(mapID) or ""
        map.caption:SetText(dungeon and (zone ~= "" and (zone .. ", " .. dungeon) or dungeon) or zone)
        LayZones(map, mapID, mapW)
        map:Show()
    else
        LayZones(map, nil, 0)
        map:Hide()
    end
    local shown = mapW and mapID
    local lineW = W - U(40)
    for i, line in ipairs(d.whereLines) do
        local left, right, pick
        local en = (i <= MAX_SOURCES or #entries == MAX_SOURCES + 1) and entries[i]
        if #entries == 0 then
            left = (i == 1 and "Not found in game yet") or (i == 2 and "The first player to loot it fills this in") or nil
            right = ""
        elseif en then
            left, right, pick = en.left, en.rightText or Spot(en, shown), not en.header
        elseif i == MAX_SOURCES + 1 and #entries > MAX_SOURCES + 1 then
            left, right = "and " .. (#entries - MAX_SOURCES) .. " more", ""
        end
        local lit = pick and d.hi == i
        -- a dot in its pins' colour; the name gets the room first and the spot gives way before the name is cut
        line.dot:SetShown(pick == true)
        if pick then line.dot:SetColorTexture(T.RGB(DotHex(en.look))) end
        local indent = pick and U(14) or 0
        line.left:ClearAllPoints()
        line.left:SetPoint("LEFT", indent, 0)
        line.left:SetPoint("RIGHT", line.right, "LEFT", -U(6), 0)
        line.left:SetText(left or "")
        if pick and en.leftShort and indent + FullWidth(line.left) > lineW then line.left:SetText(en.leftShort) end
        line.right:SetText(right or "")
        if right and right ~= "" and indent + FullWidth(line.left) + U(6) + FullWidth(line.right) > lineW then
            line.right:SetText("")
        end
        line.left:SetTextColor(T.RGB(lit and "FFFFFF" or C.ink))
        line.bg:SetShown(lit)
        line:EnableMouse(pick == true)
        line:SetShown(left ~= nil)
    end
    local linesTop = d.where.top + U(8) + mapBoxH + U(8)
    for i, line in ipairs(d.whereLines) do
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", d.where, "TOPLEFT", U(10), -(linesTop + (i - 1) * U(18)))
        line:SetPoint("TOPRIGHT", d.where, "TOPRIGHT", -U(10), -(linesTop + (i - 1) * U(18)))
    end
    d.where:SetHeight(linesTop + nLines * U(18) + U(8))
    d.noMap:SetShown(not mapW)
    d.noMap:SetSize(W - U(40), mapBoxH)
    map.mapID = mapW and mapID or nil
    -- a Forever map from the developer's art has a World Map only where the client has that zone
    d.worldBtn:SetShown(mapW ~= nil and (not DevMap(mapID) or not D.retailMaps or D.retailMaps[mapID - DEV_MAP] ~= nil))
    UI.SetWorldBtn()
    d.where:Show()
    d.status:Show()
end
UI.ShowDetail = ShowDetail

-- the Mark on Map button marks the item (WorldPins.lua; FavPins.lua draws it like a favorite) until it is pressed
-- again or another item is marked; the player opens the map. The addon neither opens that map nor drops a map pin:
-- Blizzard's map code run from an addon, or a pin the addon set, is the addon's, and the game then refuses to share
-- the pin. Ctrl+click on an icon drops the game's own. A favorite is on the map already.
local function SetWorldBtn()
    local b = detail.worldBtn
    local on = (ns.FavPins and ns.FavPins.Covers(selected)) or (ns.WorldPins and selected ~= nil and ns.WorldPins.Marked() == selected)
    b:SetLabel(on and "Marked" or "Mark on Map")
    b:SetWidth(math.max(U(60), b.label:GetStringWidth() + U(32)))
    b.on = on
end
UI.SetWorldBtn = SetWorldBtn

function UI.ShowOnWorldMap()
    if not selected or not ns.WorldPins or (ns.FavPins and ns.FavPins.Covers(selected)) then return end
    if ns.WorldPins.Marked() == selected then
        ns.WorldPins.Clear()
    else
        ns.WorldPins.Mark(selected)
    end
    SetWorldBtn()
end

local function BuildDetail(parent)
    local f = CreateFrame("Frame", nil, parent)
    detail.frame = f
    UI.detail = detail
    detail.empty = T.Text(f, 14, C.dim)
    detail.empty:SetPoint("TOPLEFT", U(12), -U(16))
    detail.empty:SetText("Pick an item on the left to see where it drops.")

    -- the item box is the item's full tooltip: a small icon at the left of the name, the Link in chat and favorites
    -- buttons at the right, then the tooltip's lines, which scroll past TIP_MAX so a long tooltip never covers the rest
    -- top corners only: a LEFT or RIGHT point would also pin the middle, and the client would size the height from it
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", U(10), -U(10))
    head:SetPoint("TOPRIGHT", -U(10), -U(10))
    T.Panel(head, C.tipBg, C.tipLine)
    detail.head = head
    local iconFrame = CreateFrame("Frame", nil, head)
    iconFrame:SetSize(U(30), U(30))
    iconFrame:SetPoint("TOPLEFT", U(10), -U(8))
    iconFrame:EnableMouse(true)
    iconFrame:SetScript("OnEnter", function(self) T.ItemTip(self, selected) end)
    iconFrame:SetScript("OnLeave", function() T.HideItemTip() end)
    detail.iconFrame = iconFrame
    detail.iconBorder = T.Border(iconFrame, "A335EE", 1, "OVERLAY")
    detail.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    detail.icon:SetAllPoints()
    detail.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local function SmallButton(tip)
        local b = CreateFrame("Button", nil, head)
        b:SetSize(U(22), U(22))
        b.bg = T.Solid(b, "BACKGROUND", "17120C")
        b.bg:SetAllPoints()
        b.edge = T.Border(b, C.frame)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    -- top right: the favorites star, the same as the star on the item's row, and Link in chat left of it
    local fav = SmallButton("Favorite")
    fav:SetPoint("TOPRIGHT", -U(10), -U(12))
    fav.mark = T.Star(fav, U(13))
    fav.mark:SetPoint("CENTER")
    fav:SetScript("OnClick", function() UI.ToggleFavorite(selected) end)
    detail.fav = fav
    detail.link = SmallButton("Link in chat")
    detail.link:SetPoint("RIGHT", fav, "LEFT", -U(6), 0)
    T.ChatMark(detail.link, U(14)):SetPoint("CENTER")
    detail.name = T.Text(head, 15, "FFFFFF")
    detail.name:SetPoint("LEFT", iconFrame, "RIGHT", U(8), 0)
    detail.name:SetWordWrap(true)

    -- the tooltip's lines: a scroll frame of FontStrings with a bar like a dropdown's (a click strip wider than it)
    local tipScroll = CreateFrame("ScrollFrame", nil, head)
    tipScroll:SetPoint("TOPLEFT", U(10), -U(40))
    tipScroll:SetPoint("TOPRIGHT", -U(10), -U(40))
    local tipBody = CreateFrame("Frame", nil, tipScroll)
    tipBody:SetSize(1, 1)
    tipScroll:SetScrollChild(tipBody)
    local tipBar = CreateFrame("Slider", nil, head)
    tipBar:SetOrientation("VERTICAL")
    tipBar:SetPoint("TOPRIGHT", tipScroll, "TOPRIGHT", 0, 0)
    tipBar:SetPoint("BOTTOMRIGHT", tipScroll, "BOTTOMRIGHT", 0, 0)
    tipBar:SetWidth(U(8))
    tipBar:SetValueStep(1)
    local track = T.Solid(tipBar, "BACKGROUND", C.catBg)
    track:SetAllPoints()
    local thumb = tipBar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(T.RGB(C.frame))
    thumb:SetSize(U(8), U(30))
    tipBar:SetThumbTexture(thumb)
    tipBar:SetHitRectInsets(-U(6), 0, 0, 0)
    tipBar:SetScript("OnValueChanged", function(_, v) tipScroll:SetVerticalScroll(v) end)
    tipScroll:EnableMouseWheel(true)
    tipScroll:SetScript("OnMouseWheel", function(_, delta)
        if not tipBar:IsShown() then return end
        local lo, hi = tipBar:GetMinMaxValues()
        tipBar:SetValue(math.max(lo, math.min(hi, tipBar:GetValue() - delta * U(34))))
    end)
    detail.tipScroll, detail.tipBody, detail.tipBar = tipScroll, tipBody, tipBar
    detail.tipLines, detail.asked = {}, {}
    -- the detail side changes width with the tab beside it: lay the item out again at the new width
    f:SetScript("OnSizeChanged", function(self, w)
        if selected and detail.laidW and math.abs((w or 0) - detail.laidW) > 0.5 and self:IsVisible() then ShowDetail(selected) end
    end)

    -- an item the game has not loaded yet has no link: ask for it, and link it once it arrives
    detail.link:SetScript("OnClick", function()
        if not selected then return end
        local id = selected
        ns.Detect.WhenLoaded(id, function(ok)
            local _, link = C_Item.GetItemInfo(id)
            if not ok or not link then return end
            local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
            if insert and insert(link) then return end
            local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
            if open then open(link) end
        end)
    end)

    -- where it drops: no header strip, the map opens the box (its caption names the zone) and Show on World Map sits
    -- on the map's bottom right corner
    local where = T.Section(f)
    where:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -U(6))
    where:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -U(6))
    detail.where = where
    local map = CreateFrame("Frame", nil, where)
    map:SetClipsChildren(true)
    -- spots: every spot of the item on the drawn map; shown: those that get a pin at the current zoom
    map.tiles, map.over, map.pins, map.spots, map.shown = {}, {}, {}, {}, {}
    map.z, map.vx, map.vy = 1, 0, 0
    -- the art lies on a canvas that zooms and pans inside the clipped map; the frame and caption stay on top
    map.canvas = CreateFrame("Frame", nil, map)
    map.top = CreateFrame("Frame", nil, map)
    map.top:SetAllPoints()
    T.Border(map.top, C.insetLine, 1, "OVERLAY")
    map.caption = T.Text(map.top, 12, C.title, "OVERLAY")
    map.caption:SetPoint("TOPLEFT", U(6), -U(4))
    map.caption:SetShadowOffset(1, -1)
    -- zone chips (LayZones) in the caption's place, the list of the zones past the map's width, and a hidden string
    -- that measures the list's words
    map.zoneChips = {}
    map.zoneMore = T.Dropdown(map.top, U(60), {}, function() return map.mapID end, function(m) PickZone(m) end, 11)
    map.zoneMore:SetHeight(U(18))
    map.zoneMore:Hide()
    map.measure = T.Text(map.top, 11, C.ink)
    map.measure:Hide()
    detail.worldBtn = T.Button(map.top, "Mark on Map", nil, U(18), 11)
    detail.worldBtn:SetPoint("BOTTOMRIGHT", -U(6), U(6))
    detail.worldBtn:SetScript("OnClick", function() UI.ShowOnWorldMap() end)
    detail.worldBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not self.on then
            GameTooltip:SetText("Mark on World Map", 1, 1, 1)
            GameTooltip:AddLine("Draws its spots on your World Map", T.RGB(C.dim))
        elseif ns.FavPins and ns.FavPins.Covers(selected) then
            GameTooltip:SetText("Marked on your World Map", 1, 1, 1)
            GameTooltip:AddLine("Favorites are marked", T.RGB(C.dim))
        else
            GameTooltip:SetText("Marked on your World Map", 1, 1, 1)
            GameTooltip:AddLine("Click to take the marks off", T.RGB(C.dim))
        end
        GameTooltip:Show()
    end)
    detail.worldBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    detail.worldBtn:Hide()
    -- wheel zooms at the cursor, a left drag pans, a right click goes back to the opening view
    map:EnableMouse(true)
    map:EnableMouseWheel(true)
    map:SetScript("OnMouseWheel", function(self, delta)
        if not self.w then return end
        HideCard()
        local cx, cy = CursorOnMap(self)
        local z = Clamp(self.z * (delta > 0 and 1.25 or 0.8), 1, MAX_ZOOM)
        local k = z / self.z
        SetView(self, z, (self.vx + cx) * k - cx, (self.vy + cy) * k - cy)
    end)
    local function Drag(self)
        local cx, cy = CursorOnMap(self)
        SetView(self, self.z, self.drag[3] - (cx - self.drag[1]), self.drag[4] - (cy - self.drag[2]))
    end
    local function StopDrag(self)
        self.drag = nil
        self:SetScript("OnUpdate", nil)
    end
    map:SetScript("OnMouseDown", function(self, button)
        if not self.w then return end
        if button == "LeftButton" then
            HideCard()
            local cx, cy = CursorOnMap(self)
            self.drag = { cx, cy, self.vx, self.vy }
            self:SetScript("OnUpdate", Drag)
        elseif button == "RightButton" then
            FitView(self)
        end
    end)
    map:SetScript("OnMouseUp", StopDrag)
    map:SetScript("OnHide", StopDrag)
    detail.map = map
    -- in place of the map when the item has none, the same size, so nothing below moves
    local noMap = CreateFrame("Frame", nil, where)
    noMap:SetPoint("TOP", where, "TOP", 0, -(where.top + U(8)))
    T.Panel(noMap, C.inset, C.insetLine)
    noMap.text = T.Text(noMap, 12, C.dim)
    noMap.text:SetPoint("CENTER")
    noMap.text:SetText("No map for this item yet")
    noMap:Hide()
    detail.noMap = noMap
    detail.whereLines = {}
    for i = 1, MAX_SOURCES + 1 do
        local line = CreateFrame("Button", nil, where)
        line:SetHeight(U(18))
        line.bg = T.Solid(line, "BACKGROUND", "2A2117")
        line.bg:SetPoint("TOPLEFT", -U(4), 0)
        line.bg:SetPoint("BOTTOMRIGHT", U(4), 0)
        line.bg:Hide()
        line:SetScript("OnClick", function()
            detail.hi = detail.hi ~= i and i or nil
            -- a lit line keeps the map's zone when it has pins there, else opens its own; unlit, the first zone again
            local shown, en = detail.map.mapID, detail.hi and detail.entries and detail.entries[i]
            local stay
            for _, p in ipairs(en and en.pins or {}) do
                if p.m == shown then stay = shown break end
            end
            detail.zone = stay
            ShowDetail(selected)
        end)
        line.dot = Dot(line)
        line.dot:ClearAllPoints()
        line.dot:SetPoint("LEFT", 0, 0)
        line.dot:SetSize(U(8), U(8))
        line.left = T.Text(line, 13, C.ink)
        line.left:SetPoint("LEFT")
        line.right = T.Text(line, 13, C.dim)
        line.right:SetPoint("RIGHT")
        line.right:SetJustifyH("RIGHT")
        line.left:SetPoint("RIGHT", line.right, "LEFT", -U(6), 0)
        detail.whereLines[i] = line
    end

    -- Status: its labelled rows, no header strip
    local status = T.Section(f)
    status:SetPoint("TOPLEFT", where, "BOTTOMLEFT", 0, -U(8))
    status:SetPoint("TOPRIGHT", where, "BOTTOMRIGHT", 0, -U(8))
    detail.status = status
    -- Item, How to get, Drop rate (drops only), Found; ShowDetail places them
    detail.rows = {}
    for i = 1, 4 do
        local key = T.Text(status, 13, C.dim)
        key:SetWidth(U(84))
        local value = T.Text(status, 13, C.ink)
        value:SetWordWrap(true)
        detail.rows[i] = { key = key, value = value }
    end
    return f
end

-- the window
-- the find filter's controls: the Live Feed's strip, and the pop-ups' copy in Options. They read and write whatever
-- table getF() returns, so the Options copy can follow the feed or stand alone. Row one: quality floor, level choice,
-- slots (pick several); row two: "Gear I can use", the custom level range (shown for Custom range only, its room kept)
-- and, withKinds, New / Changed. fc:Sync() reads the table back into the controls.
local function FindFilterControls(parent, getF, base, withKinds, onChange)
    local fc = {}
    fc.quality = T.Dropdown(parent, U(176), { { "any", "Any quality" }, { "uncommon", "Uncommon and better" },
        { "rare", "Rare and better" }, { "epic", "Epic and better" } },
        function() return getF().quality end, function(v) getF().quality = v onChange() end)
    fc.quality:SetPoint("TOPLEFT", U(10), -(base + U(10)))
    fc.level = T.Dropdown(parent, U(150), { { "any", "Any level" }, { "mine", "Up to my level" }, { "near", "Within 10 levels" },
        { "custom", "Custom range" } }, function() return getF().level end, function(v)
            getF().level = v
            fc:Sync()
            onChange()
        end)
    fc.level:SetPoint("LEFT", fc.quality, "RIGHT", U(6), 0)
    local slotOpts = { { "", "Any slot" } }
    for _, inv in ipairs(D.SLOTS) do slotOpts[#slotOpts + 1] = { inv, D.SlotName(inv) } end
    fc.slots = T.Dropdown(parent, U(156), slotOpts, function() end, function() end, nil, {
        isOn = function(k)
            local picked = getF().slots
            if k == "" then return next(picked) == nil end
            return picked[k] == true
        end,
        toggle = function(k)
            local picked = getF().slots
            if k == "" then wipe(picked) elseif picked[k] then picked[k] = nil else picked[k] = true end
            onChange()
        end,
        label = function()
            local n, one = 0, nil
            for k in pairs(getF().slots) do n, one = n + 1, k end
            if n == 0 then return "Any slot" end
            return n == 1 and D.SlotName(one) or (n .. " slots")
        end,
    })
    fc.slots:SetPoint("LEFT", fc.level, "RIGHT", U(6), 0)

    fc.usable = T.Check(parent, "Gear I can use")
    fc.usable:SetPoint("TOPLEFT", U(8), -(base + U(42)))
    fc.usable:SetScript("OnClick", function(self) getF().usable = self:GetChecked() and true or false onChange() end)
    -- either end of the custom range may stay open
    local function RangeBox(key, hint)
        local e = T.EditBox(parent, U(42), U(24), true)
        e:SetTextInsets(U(4), U(4), 0, 0)
        e:SetHint(hint)
        e:SetScript("OnTextChanged", function(self)
            self.hint:SetShown(self:GetText() == "")
            if fc.syncing then return end
            getF()[key] = tonumber(self:GetText())
            onChange()
        end)
        return e
    end
    fc.levelMin = RangeBox("levelMin", "1")
    fc.levelMin:SetPoint("LEFT", fc.usable.label, "RIGHT", U(24), 0)
    fc.dash = T.Text(parent, 13, C.dim)
    fc.dash:SetPoint("LEFT", fc.levelMin, "RIGHT", U(5), 0)
    fc.dash:SetText("-")
    fc.levelMax = RangeBox("levelMax", "60")
    fc.levelMax:SetPoint("LEFT", fc.dash, "RIGHT", U(5), 0)
    if withKinds then
        fc.kinds = {}
        local prev = fc.levelMax
        for _, k in ipairs({ { "n", "New" }, { "c", "Changed" } }) do
            local cb = T.Check(parent, k[2])
            cb:SetPoint("LEFT", prev, "RIGHT", U(24), 0)
            cb.key = k[1]
            cb:SetScript("OnClick", function(self) getF().kinds[k[1]] = self:GetChecked() and true or false onChange() end)
            fc.kinds[#fc.kinds + 1] = cb
            prev = cb.label
        end
    end
    function fc:Sync()
        local f = getF()
        self.syncing = true
        self.quality:Refresh()
        self.level:Refresh()
        self.slots:Refresh()
        self.usable:SetChecked(f.usable)
        for _, w in ipairs({ self.levelMin, self.levelMax, self.dash }) do w:SetShown(f.level == "custom") end
        for _, pair in ipairs({ { self.levelMin, f.levelMin }, { self.levelMax, f.levelMax } }) do
            local text = pair[2] and tostring(pair[2]) or ""
            if pair[1]:GetText() ~= text then pair[1]:SetText(text) end
        end
        for _, cb in ipairs(self.kinds or {}) do cb:SetChecked(f.kinds[cb.key]) end
        self.syncing = false
    end
    fc:Sync()
    return fc
end

-- the Item Database's filter controls, bound to its state st:
-- search (withSearch), level range, quality, slot; class, source and its dungeon / raid pick; then the kind chips
-- (chipDefs: { key, label }). Rows sit base units below the parent's top (board offsets are converted in one step, so
-- the rows land on the same pixels in every copy); onChange runs after every change. Returns the controls.
local function FilterBox(parent, st, base, withSearch, chipDefs, onChange)
    local fb = {}
    local off = withSearch and 32 or 0
    local function At(dy) return -(base + U(dy + off)) end
    if withSearch then
        local searchLabel = T.Text(parent, 13, C.title)
        searchLabel:SetPoint("TOPLEFT", U(10), -(base + U(12)))
        searchLabel:SetText("Search")
        local search = T.EditBox(parent, U(400), U(24))
        search:SetPoint("LEFT", searchLabel, "RIGHT", U(8), 0)
        search:SetPoint("RIGHT", parent, "RIGHT", -U(10), 0)
        search:SetHint("Item name or zone")
        local pending
        search:SetScript("OnTextChanged", function(self)
            self.hint:SetShown(self:GetText() == "")
            st.q = self:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "")
            -- type freely: the list catches up a moment after the last key
            if pending then return end
            pending = true
            C_Timer.After(0.25, function() pending = false onChange() end)
        end)
        fb.search = search
    end

    local levelLabel = T.Text(parent, 13, C.title)
    levelLabel:SetPoint("TOPLEFT", U(10), At(12))
    levelLabel:SetText("Level")
    local function LevelBox(key)
        local e = T.EditBox(parent, U(42), U(24), true)
        e:SetTextInsets(U(4), U(4), 0, 0)
        e:SetText(st[key] and tostring(st[key]) or "")
        e:SetScript("OnTextChanged", function(self)
            self.hint:SetShown(false)
            st[key] = tonumber(self:GetText())
            onChange()
        end)
        return e
    end
    fb.minL = LevelBox("minL")
    fb.minL:SetPoint("LEFT", levelLabel, "RIGHT", U(8), 0)
    local dash = T.Text(parent, 13, C.dim)
    dash:SetPoint("LEFT", fb.minL, "RIGHT", U(5), 0)
    dash:SetText("-")
    fb.maxL = LevelBox("maxL")
    fb.maxL:SetPoint("LEFT", dash, "RIGHT", U(5), 0)
    -- a pick-several list over the set st[key]: its first option (Any ...) clears the set; the box names a single pick
    -- or counts several. after(), if given, runs after each toggle
    local function Multi(w, opts, key, plural, after)
        return T.Dropdown(parent, w, opts, function() end, function() end, nil, {
            isOn = function(k)
                if k == opts[1][1] then return next(st[key]) == nil end
                return st[key][k] == true
            end,
            toggle = function(k)
                local set = st[key]
                if k == opts[1][1] then wipe(set) elseif set[k] then set[k] = nil else set[k] = true end
                if after then after() end
                onChange()
            end,
            label = function()
                local n, one = 0, nil
                for k in pairs(st[key]) do n, one = n + 1, k end
                if n == 0 then return opts[1][2] end
                if n > 1 then return n .. " " .. plural end
                for _, o in ipairs(opts) do if o[1] == one then return o[2] end end
                return opts[1][2]
            end,
        })
    end
    fb.quality = Multi(U(116), { { -1, "Any quality" }, { 0, "Poor" }, { 1, "Common" }, { 2, "Uncommon" },
        { 3, "Rare" }, { 4, "Epic" }, { 5, "Legendary" } }, "qs", "qualities")
    fb.quality:SetPoint("LEFT", fb.maxL, "RIGHT", U(8), 0)
    local slotOpts = { { 0, "Any slot" } }
    for _, inv in ipairs(D.SLOTS) do slotOpts[#slotOpts + 1] = { inv, D.SlotName(inv) } end
    fb.slot = Multi(U(158), slotOpts, "slots", "slots")
    fb.slot:SetPoint("LEFT", fb.quality, "RIGHT", U(6), 0)

    local classOpts = { { "", "Any class" } }
    for _, file in ipairs(D.CLASS_ORDER) do
        classOpts[#classOpts + 1] = { file, (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or (file:sub(1, 1) .. file:sub(2):lower()) }
    end
    fb.class = Multi(U(108), classOpts, "clss", "classes")
    fb.class:SetPoint("TOPLEFT", U(10), At(40))
    local srcOpts = { { 0, "Any source" } }
    for _, k in ipairs(D.SOURCE_KINDS) do srcOpts[#srcOpts + 1] = { k.bit, k.text } end
    -- which dungeon or raid: shown beside Source while Dungeon or Raid is picked, its list the places with listed items
    local dungeon = T.Dropdown(parent, U(212), { { "", "Any dungeon" } }, function() return st.dg end, function(v) st.dg = v onChange() end)
    fb.dungeon = dungeon
    local function SyncDungeon()
        local raid, dg = D.HasBit(st.src, 1), D.HasBit(st.src, 2)
        if not raid and not dg then
            st.dg = ""
            dungeon:Hide()
            return
        end
        local opts = { { "", (raid and dg and "Any raid or dungeon") or (raid and "Any raid") or "Any dungeon" } }
        local kept = false
        for _, isRaid in ipairs({ true, false }) do
            if (isRaid and raid) or (not isRaid and dg) then
                for _, name in ipairs(D.DungeonNames(isRaid)) do
                    opts[#opts + 1] = { name, name }
                    if name == st.dg then kept = true end
                end
            end
        end
        if not kept then st.dg = "" end
        dungeon.options = opts
        dungeon:Refresh()
        dungeon:Show()
    end
    fb.source = Multi(U(112), srcOpts, "srcs", "sources", function()
        local sum = 0
        for b in pairs(st.srcs) do sum = sum + b end
        st.src = sum
        SyncDungeon()
    end)
    fb.source:SetPoint("LEFT", fb.class, "RIGHT", U(6), 0)
    dungeon:SetPoint("LEFT", fb.source, "RIGHT", U(6), 0)
    SyncDungeon()

    -- the chips get a row of their own: with full counts they are wider than what the dropdowns leave
    fb.chips = {}
    local prev
    for _, k in ipairs(chipDefs) do
        -- a third field asks for the star chip: the star and the count in place of a word
        local chip = T.Chip(parent, nil, k[3])
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", U(6), 0) else chip:SetPoint("TOPLEFT", U(10), At(72)) end
        chip.key, chip.text = k[1], k[2]
        chip:SetScript("OnClick", function() st.kind = k[1] onChange() end)
        if k[3] then
            chip:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Favorites", 1, 1, 1)
                GameTooltip:Show()
            end)
            chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        fb.chips[#fb.chips + 1] = chip
        prev = chip
    end
    return fb
end

local function Build()
    win = CreateFrame("Frame", "ForeverItemFinderFrame", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.window = { point, rel, x, y }
    end)
    local pos = ns.db.window
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER") end
    win:SetScale((Settings().winScale or 100) / 100)
    T.Panel(win, C.bg, C.frame, BORDER)
    table.insert(UISpecialFrames, "ForeverItemFinderFrame")
    win:SetScript("OnHide", function()
        T.CloseList()
        HideCard()
        if tab == "feed" then FeedSeen() end
        ns.Signal("WindowHidden")
    end)

    -- title plaque and close button
    local plaque = CreateFrame("Frame", nil, win)
    plaque:SetPoint("TOP", 0, -(BORDER + U(6)))
    T.Panel(plaque, C.plaque, C.gold)
    local title = T.Text(plaque, 16, C.title)
    title:SetPoint("CENTER")
    title:SetText("Forever Item Finder")
    plaque:SetSize(title:GetStringWidth() + U(56), U(28))
    local close = CloseButton(win)
    close:SetPoint("TOPRIGHT", -(BORDER + U(10)), -(BORDER + U(8)))
    close:SetScript("OnClick", function() win:Hide() end)

    -- the inset body
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", BORDER + U(12), -(BORDER + U(40)))
    body:SetPoint("BOTTOMRIGHT", -(BORDER + U(12)), BORDER + U(10) + U(30))
    T.Panel(body, C.inset, C.insetLine)
    UI.body = body

    -- footer
    local dot = T.Solid(win, "ARTWORK", C.green)
    dot:SetSize(U(7), U(7))
    dot:SetPoint("BOTTOMLEFT", BORDER + U(14), BORDER + U(10) + U(11))
    local footText = T.Text(win, 12, C.foot)
    footText:SetPoint("LEFT", dot, "RIGHT", U(6), 0)
    UI.footDot, UI.footText = dot, footText
    local discord = T.Button(win, "Discord", nil, U(22), 12)
    discord:SetPoint("BOTTOMRIGHT", -(BORDER + U(14)), BORDER + U(10) + U(4))
    discord:SetScript("OnClick", function() UI.ShowLink(ns.DISCORD) end)
    -- the finds as a string to paste on the addon's website
    local share = T.Button(win, "Share your finds", nil, U(22), 12)
    share:SetPoint("RIGHT", discord, "LEFT", -U(6), 0)
    share:SetScript("OnClick", function() UI.ShowShare() end)
    UI.discordBtn, UI.shareBtn = discord, share

    -- tabs hanging under the frame
    UI.tabs = {}
    local prev
    for _, key in ipairs({ "feed", "db", "options", "settings" }) do
        local t = Tab(win, key)
        if prev then t:SetPoint("TOPLEFT", prev, "TOPRIGHT", U(4), 0) else t:SetPoint("TOPLEFT", win, "BOTTOMLEFT", U(18), BORDER - 1) end
        t:SetScript("OnClick", function() UI.Show(key) end)
        UI.tabs[key] = t
        prev = t
    end

    -- feed side
    local feed = CreateFrame("Frame", nil, body)
    feed:SetPoint("TOPLEFT", 1, -1)
    feed:SetPoint("BOTTOMLEFT", 1, 1)
    -- as wide as the database
    feed:SetWidth(U(526))
    UI.feedPane = feed
    -- the find filter strip: what the feed shows (and what pops up, while pop-ups follow it)
    local strip = CreateFrame("Frame", nil, feed)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT", -1, 0)
    strip:SetHeight(U(76))
    local stripLine = T.Solid(strip, "BORDER", C.insetLine)
    stripLine:SetPoint("BOTTOMLEFT")
    stripLine:SetPoint("BOTTOMRIGHT")
    stripLine:SetHeight(1)
    UI.feedFilter = FindFilterControls(strip, function() return Settings().findFilter end, 0, false, function() UI.Refresh() end)
    local head = CreateFrame("Frame", nil, feed)
    head:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
    head:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
    head:SetHeight(U(32))
    T.Solid(head, "BACKGROUND", C.head):SetAllPoints()
    local headLine = T.Solid(head, "BORDER", C.insetLine)
    headLine:SetPoint("BOTTOMLEFT")
    headLine:SetPoint("BOTTOMRIGHT")
    headLine:SetHeight(1)
    local headL = T.Text(head, 12, C.title)
    headL:SetPoint("LEFT", U(12), 0)
    headL:SetText("NEWEST FIRST")
    -- New and Changed: each a toggle, both on shows every kind
    UI.feedKinds = {}
    local prevChip = headL
    for _, k in ipairs({ { "n", "New" }, { "c", "Changed" } }) do
        local chip = T.Chip(head)
        chip:SetPoint("LEFT", prevChip, "RIGHT", U(10), 0)
        chip.key, chip.text = k[1], k[2]
        chip:SetScript("OnClick", function()
            local kinds = Settings().findFilter.kinds
            kinds[k[1]] = not kinds[k[1]]
            UI.Refresh()
        end)
        UI.feedKinds[#UI.feedKinds + 1] = chip
        prevChip = chip
    end
    local refresh = T.Button(head, "Refresh", nil, U(20))
    refresh:SetPoint("RIGHT", -U(6), 0)
    refresh:SetScript("OnClick", function() UI.RefreshFeed() end)
    UI.feedRefresh = refresh
    -- empties the feed until new finds arrive; the finds stay in the Item Database and in what you share
    local clear = T.Button(head, "Clear feed", nil, U(20))
    clear:SetPoint("RIGHT", refresh, "LEFT", -U(6), 0)
    clear:SetScript("OnClick", function()
        ns.db.feedClearedAt = ns.Now()
        UI.Refresh()
    end)
    UI.feedClear = clear
    UI.feedCount = T.Text(head, 12, C.title)
    UI.feedCount:SetPoint("RIGHT", clear, "LEFT", -U(10), 0)
    UI.feedList = T.List(feed, U(46), function(list) return MakeRow(list, true) end, BindRow)
    UI.feedList:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    UI.feedList:SetPoint("BOTTOMRIGHT")
    UI.feedEmpty = T.Text(feed, 14, C.dim)
    UI.feedEmpty:SetPoint("TOPLEFT", head, "BOTTOMLEFT", U(12), -U(16))
    UI.feedEmpty:SetText("Nothing new yet. Items you and other players find show up here.")
    local feedLine = T.Solid(feed, "BORDER", C.insetLine)
    feedLine:SetPoint("TOPRIGHT")
    feedLine:SetPoint("BOTTOMRIGHT")
    feedLine:SetWidth(1)

    -- database side
    UI.BuildDatabase(body)

    -- pop-up options, then settings
    UI.BuildOptions(body)
    UI.BuildSettings(body)

    -- the shared detail side
    local det = BuildDetail(body)
    det:SetPoint("TOPRIGHT", -1, -1)
    det:SetPoint("BOTTOMRIGHT", -1, 1)
    UI.detailPane = det

    win:Hide()
end

function UI.BuildDatabase(body)
    local pane = CreateFrame("Frame", nil, body)
    pane:SetPoint("TOPLEFT", 1, -1)
    pane:SetPoint("BOTTOMLEFT", 1, 1)
    pane:SetWidth(U(526))
    UI.dbPane = pane
    local edge = T.Solid(pane, "BORDER", C.insetLine)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)
    local filters = CreateFrame("Frame", nil, pane)
    filters:SetPoint("TOPLEFT")
    filters:SetPoint("TOPRIGHT", -1, 0)
    filters:SetHeight(U(136))
    local fline = T.Solid(filters, "BORDER", C.insetLine)
    fline:SetPoint("BOTTOMLEFT")
    fline:SetPoint("BOTTOMRIGHT")
    fline:SetHeight(1)

    local fb = FilterBox(filters, state, 0, true, { { "all", "All" }, { "n", "New" }, { "c", "Changed" }, { "o", "Classic" },
        { "u", "Not Found" }, { "f", "", true } }, function() UI.Refresh() end)
    UI.search, UI.qualityFilter, UI.sourceFilter, UI.dungeonFilter, UI.chips = fb.search, fb.quality, fb.source, fb.dungeon, fb.chips
    UI.slotFilter, UI.classFilter = fb.slot, fb.class

    local cats = CreateFrame("Frame", nil, pane)
    cats:SetPoint("TOPLEFT", filters, "BOTTOMLEFT")
    cats:SetPoint("BOTTOMLEFT")
    -- wide enough for "One-Handed Swords" and a 3-digit count while the scroll bar takes its U(12)
    cats:SetWidth(U(200))
    T.Solid(cats, "BACKGROUND", C.catBg):SetAllPoints()
    local catLine = T.Solid(cats, "BORDER", C.insetLine)
    catLine:SetPoint("TOPRIGHT")
    catLine:SetPoint("BOTTOMRIGHT")
    catLine:SetWidth(1)
    UI.catList = T.List(cats, U(21), function(list)
        local b = CreateFrame("Button", nil, list)
        local sel = T.Solid(b, "BACKGROUND", C.sel)
        sel:SetAllPoints()
        b.selTex = sel
        T.Hover(b, "2A2117")
        b.label = T.Text(b, 13, C.title)
        b.label:SetPoint("LEFT", U(8), 0)
        b.count = T.Text(b, 12, C.faint)
        b.count:SetPoint("RIGHT", -U(8), 0)
        -- a second click on the picked category folds its types away (its filter stays), a third opens them again
        b:SetScript("OnClick", function(self)
            if self.key == state.cat and not self.sub and self.key ~= "all" then
                state.catShut = not state.catShut
            else
                state.cat, state.catShut = self.key, false
            end
            UI.Refresh()
        end)
        return b
    end, function(b, item)
        b.key, b.sub = item.key, item.sub
        b.selTex:SetShown(item.key == state.cat)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", item.sub and U(16) or U(8), 0)
        b.label:SetPoint("RIGHT", b.count, "LEFT", -U(4), 0)
        b.label:SetText(item.label)
        b.label:SetTextColor(T.RGB(item.key == state.cat and "FFFFFF" or (item.sub and C.ink or C.title)))
        b.label:SetFont(T.FONT, item.sub and U(12) or U(13), "")
        b.count:SetText(item.n > 0 and item.n or "")
    end)
    UI.catList:SetPoint("TOPLEFT", 0, -U(4))
    UI.catList:SetPoint("BOTTOMRIGHT", -1, 0)

    UI.dbList = T.List(pane, U(46), function(list) return MakeRow(list, true) end, BindRow)
    UI.dbList:SetPoint("TOPLEFT", cats, "TOPRIGHT")
    UI.dbList:SetPoint("BOTTOMRIGHT", -1, 0)
    UI.dbEmpty = T.Text(pane, 14, C.dim)
    UI.dbEmpty:SetPoint("TOPLEFT", cats, "TOPRIGHT", U(12), -U(16))
    UI.dbEmpty:SetText("No items match.")
end

local function CatData()
    local data = { { key = "all", label = "All Items", n = dbCounts.all or 0 } }
    local open = not state.catShut and state.cat:match("^(%-?%d+)")
    for _, c in ipairs(D.CATEGORIES) do
        data[#data + 1] = { key = tostring(c.cls), label = c.name, n = dbCounts[c.cls] or 0 }
        if open and tonumber(open) == c.cls then
            for _, s in ipairs(c.subs) do
                data[#data + 1] = { key = c.cls .. "/" .. s[1], label = s[2], n = dbCounts[SubKey(c.cls, s[1])] or 0, sub = true }
            end
        end
    end
    return data
end

-- options
local opt = {}
UI.opt = opt
function UI.PopPreview()
    local finds = ns.Finds.List()
    local recent = {}
    for i = 1, math.min(#finds, 20) do recent[#recent + 1] = finds[i] end
    local s = Settings()
    if not s.popOn then return "Pop-ups are off. Finds still arrive in the feed." end
    if #recent == 0 then return "Nothing found yet to try these settings on." end
    local names = {}
    for _, e in ipairs(recent) do
        if ns.Popup.Passes(e) then names[#names + 1] = e.nm or C_Item.GetItemInfo(e.id) or ("item " .. e.id) end
    end
    if #names == 0 then return "None of your last " .. #recent .. " finds would pop up with these settings." end
    local shown = {}
    for i = 1, math.min(#names, 4) do shown[i] = names[i] end
    return #names .. " of your last " .. #recent .. " finds would pop up: " .. table.concat(shown, ", ") .. (#names > 4 and ", ..." or ".")
end

function UI.BuildOptions(body)
    local pane = CreateFrame("Frame", nil, body)
    pane:SetPoint("TOPLEFT", U(12), -U(12))
    pane:SetPoint("BOTTOMRIGHT", -U(12), U(12))
    UI.optPane = pane
    local s = Settings()
    -- every box is measured from the window's own numbers, so its height fits its content before the first draw
    local paneW = W - 2 * (BORDER + U(12)) - 2 * U(12)
    local paneH = H - (BORDER + U(40)) - (BORDER + U(10) + U(30)) - 2 * U(12)
    local rightW = U(290)
    local leftW = paneW - rightW - U(12)
    local LEFT_DD, RIGHT_DD = U(212), U(170)
    opt.paneH = paneH
    local function Note(parent, w, text)
        local t = T.Text(parent, 13, C.dim)
        t:SetWidth(w)
        t:SetWordWrap(true)
        t:SetJustifyV("TOP")
        t:SetText(text)
        return t
    end

    -- left column: which finds pop up, then spam protection
    local left = T.Section(pane, "Which finds pop up")
    left:SetPoint("TOPLEFT")
    left:SetWidth(leftW)
    local y = left.top + U(8)
    local function Label(parent, text, yy, x)
        local l = T.Text(parent, 14, C.ink)
        l:SetPoint("TOPLEFT", x or U(12), -yy - U(4))
        l:SetText(text)
        return l
    end
    local popOn = T.Check(left, "Show pop-ups")
    popOn:SetPoint("TOPLEFT", U(10), -y)
    popOn:SetChecked(s.popOn)
    popOn:SetScript("OnClick", function(self) s.popOn = self:GetChecked() and true or false UI.RefreshOptions() end)
    opt.popOn = popOn
    y = y + U(28)
    -- pop-ups show what the Live Feed shows; unticked, they get their own copy of the same choices, starting from the
    -- feed's. The controls below edit whichever filter is in use, so following the feed means editing the feed's.
    local follow = T.Check(left, "Same as the Live Feed")
    follow:SetPoint("TOPLEFT", U(10), -y)
    follow:SetChecked(s.popFollow)
    follow:SetScript("OnClick", function(self)
        s.popFollow = self:GetChecked() and true or false
        if not s.popFollow then s.popOwn = CopyTable(s.findFilter) end
        opt.filter:Sync()
        UI.RefreshOptions()
    end)
    opt.follow = follow
    y = y + U(28)
    opt.filter = FindFilterControls(left, function() return s.popFollow and s.findFilter or s.popOwn end, y, true,
        function() UI.RefreshOptions() end)
    UI.popFilter = opt.filter
    y = y + U(80)
    local pline = T.Solid(left, "BORDER", C.insetLine)
    pline:SetPoint("TOPLEFT", U(12), -y)
    pline:SetPoint("TOPRIGHT", -U(12), -y)
    pline:SetHeight(1)
    opt.preview = T.Text(left, 13, C.ink)
    opt.preview:SetPoint("TOPLEFT", U(12), -(y + U(8)))
    opt.preview:SetWidth(leftW - U(24))
    opt.preview:SetWordWrap(true)
    opt.preview:SetJustifyV("TOP")
    opt.left, opt.leftBase = left, y + U(8)

    -- how often pop-ups come; the first choice of each is the addon's own pace
    local timing = T.Section(pane, "Pop-up timing")
    timing:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -U(12))
    timing:SetWidth(leftW)
    local ty = timing.top + U(8)
    local function Row(label, options, key)
        Label(timing, label, ty)
        local d = T.Dropdown(timing, LEFT_DD, options, function() return s[key] end, function(v) s[key] = v end)
        d:SetPoint("TOPLEFT", U(132), -ty)
        ty = ty + U(30)
        return d
    end
    local nextDd = Row("Next find", { { "wait", "Wait in the feed" }, { "replace", "Replace the pop-up" },
        { "rarer", "Rarer one replaces it" } }, "popNext")
    local gapDd = Row("Rate limit", { { "10", "One every 10 seconds" }, { "5", "One every 5 seconds" },
        { "20", "One every 20 seconds" }, { "30", "One every 30 seconds" } }, "popGap")
    local combatDd = Row("In combat", { { "hold", "Hold until combat ends" }, { "show", "Show anyway" } }, "popCombat")
    timing:SetHeight(ty + U(2))
    opt.spam = timing

    -- right column: the pop-up's look, then sharing
    local look = T.Section(pane, "Pop-up look")
    look:SetPoint("TOPRIGHT")
    look:SetWidth(rightW)
    local ly = look.top + U(10)
    local function SmallLabel(text, yy, hex)
        local l = T.Text(look, 13, hex or C.ink)
        l:SetPoint("TOPLEFT", U(10), -yy - U(4))
        l:SetText(text)
        return l
    end
    SmallLabel("Style", ly)
    local style = T.Dropdown(look, RIGHT_DD, { { "compact", "Icon and name" }, { "card", "Stat card" }, { "full", "Full tooltip" } },
        function() return s.popStyle end, function(v) s.popStyle = v UI.RefreshOptions() ns.Popup.Preview() end)
    style:SetPoint("TOPLEFT", U(84), -ly)
    ly = ly + U(30)
    SmallLabel("Size", ly)
    local size = T.Slider(look, U(130), 60, 150, 10, function() return s.popScale end,
        function(v) s.popScale = v ns.Popup.ApplyScale() end, "%d%%")
    size:SetPoint("TOPLEFT", U(84), -(ly + U(4)))
    ly = ly + U(30)
    SmallLabel("Stays for", ly)
    local stay = T.Dropdown(look, RIGHT_DD, { { "5", "5 seconds" }, { "10", "10 seconds" }, { "20", "20 seconds" }, { "close", "Until I close it" } },
        function() return s.popStay end, function(v) s.popStay = v end)
    stay:SetPoint("TOPLEFT", U(84), -ly)
    ly = ly + U(30)
    SmallLabel("Animation", ly)
    local anim = T.Dropdown(look, RIGHT_DD, { { "basic", "Basic" }, { "full", "Basic and shine" }, { "off", "Off" } },
        function() return s.popAnim end, function(v) s.popAnim = v ns.Popup.Preview() end)
    anim:SetPoint("TOPLEFT", U(84), -ly)
    ly = ly + U(30)
    -- what the stat card shows, two to a row
    opt.cardLabel = SmallLabel("Card shows", ly, C.title)
    ly = ly + U(24)
    s.card = s.card or {}
    opt.cardChecks = {}
    for i, part in ipairs({ { "type", "Type and level" }, { "stats", "Stats" }, { "effects", "Effects" }, { "found", "Where found" } }) do
        local cb = T.Check(look, part[2], 13)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        cb:SetPoint("TOPLEFT", U(8) + col * U(140), -(ly + row * U(28)))
        cb:SetChecked(s.card[part[1]])
        cb:SetScript("OnClick", function(self)
            s.card[part[1]] = self:GetChecked() and true or false
            ns.Popup.Preview()
        end)
        opt.cardChecks[i] = cb
    end
    ly = ly + 2 * U(28) + U(4)
    local sound = T.Check(look, "Play a sound", 13)
    sound:SetPoint("TOPLEFT", U(8), -ly)
    sound:SetChecked(s.sound)
    -- which sound: beside the box while sounds are on; picking one plays it
    local soundOpts = {}
    for _, snd in ipairs(ns.Popup.SOUNDS) do soundOpts[#soundOpts + 1] = { snd[1], snd[2] } end
    local soundDd = T.Dropdown(look, U(136), soundOpts, function() return s.soundKit end, function(v)
        s.soundKit = v
        ns.Popup.PlaySound(v)
    end)
    soundDd:SetPoint("TOPLEFT", U(146), -ly)
    soundDd:SetShown(s.sound)
    opt.soundDd = soundDd
    sound:SetScript("OnClick", function(self)
        s.sound = self:GetChecked() and true or false
        soundDd:SetShown(s.sound)
    end)
    ly = ly + U(32)
    local move = T.Button(look, "Move pop-up", nil, U(26))
    move:SetPoint("TOPLEFT", U(10), -ly)
    move:SetScript("OnClick", function() ns.Popup.ToggleMover() end)
    local reset = T.Button(look, "Reset", nil, U(26))
    reset:SetPoint("LEFT", move, "RIGHT", U(8), 0)
    reset:SetScript("OnClick", function() ns.Popup.ResetPosition() end)
    ly = ly + U(26) + U(12)
    look:SetHeight(ly)

    opt.look = look
    local f = opt.filter
    opt.controls = { f.quality, f.level, f.slots, nextDd, gapDd, combatDd, style, stay, anim, soundDd }
end

-- the Settings page: the window itself (its size, where it sits) and how finds are shared
local set = {}
UI.set = set
function UI.BuildSettings(body)
    local pane = CreateFrame("Frame", nil, body)
    pane:SetPoint("TOPLEFT", U(12), -U(12))
    pane:SetPoint("BOTTOMRIGHT", -U(12), U(12))
    UI.setPane = pane
    local s = Settings()
    -- the same two columns as the Pop-up Options page
    local paneW = W - 2 * (BORDER + U(12)) - 2 * U(12)
    local rightW = U(290)
    local leftW = paneW - rightW - U(12)

    local window = T.Section(pane, "Window")
    window:SetPoint("TOPLEFT")
    window:SetWidth(leftW)
    local y = window.top + U(10)
    local sizeLabel = T.Text(window, 13, C.ink)
    sizeLabel:SetPoint("TOPLEFT", U(10), -y - U(4))
    sizeLabel:SetText("Size")
    set.size = T.Slider(window, U(200), 70, 200, 1, function() return s.winScale end, function(v)
        s.winScale = v
        if not win then return end
        -- the top left corner stays put on screen; anchor offsets are in the window's own scale
        local left, top, old = win:GetLeft(), win:GetTop(), win:GetEffectiveScale()
        win:SetScale(v / 100)
        if left and top then
            local k = old / win:GetEffectiveScale()
            win:ClearAllPoints()
            win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * k, top * k)
            ns.db.window = { "TOPLEFT", "BOTTOMLEFT", left * k, top * k }
        end
        T.RefitEdges()
    end, "%d%%", true)
    set.size:SetPoint("TOPLEFT", U(84), -(y + U(4)))
    y = y + U(34)
    local reset = T.Button(window, "Reset position", nil, U(26))
    reset:SetPoint("TOPLEFT", U(10), -y)
    reset:SetScript("OnClick", function()
        ns.db.window = nil
        win:ClearAllPoints()
        win:SetPoint("CENTER")
    end)
    set.reset = reset
    window:SetHeight(y + U(26) + U(12))
    set.window = window

    local share = T.Section(pane, "Sharing")
    share:SetPoint("TOPRIGHT")
    share:SetWidth(rightW)
    local creditLabel = T.Text(share, 13, C.ink)
    creditLabel:SetPoint("TOPLEFT", U(10), -(share.top + U(10) + U(4)))
    creditLabel:SetText("Credit as")
    local credit = T.Dropdown(share, U(170), { { "name", "My character name" }, { "anon", "Anonymous" } },
        function() return s.credit end, function(v) s.credit = v end)
    credit:SetPoint("TOPLEFT", U(84), -(share.top + U(10)))
    local shareText = T.Text(share, 13, C.dim)
    shareText:SetWidth(rightW - U(20))
    shareText:SetWordWrap(true)
    shareText:SetJustifyV("TOP")
    shareText:SetText("Anonymous hides only your name.")
    shareText:SetPoint("TOPLEFT", U(10), -(share.top + U(42)))
    share:SetHeight(share.top + U(42) + shareText:GetStringHeight() + U(10))
    set.share, set.shareText = share, shareText

    -- favorites on the game's World Map and minimap (FavPins.lua)
    local favMap = T.Section(pane, "Favorites on the Map")
    favMap:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, -U(12))
    favMap:SetWidth(leftW)
    local function Row(label, rowY, choices, key)
        local text = T.Text(favMap, 13, C.ink)
        text:SetPoint("TOPLEFT", U(10), -(rowY + U(4)))
        text:SetText(label)
        local dd = T.Dropdown(favMap, U(200), choices, function() return s[key] end, function(v)
            s[key] = v
            if ns.FavPins then ns.FavPins.Refresh() end
        end)
        dd:SetPoint("TOPLEFT", U(84), -rowY)
        return dd
    end
    local fy = favMap.top + U(10)
    set.favPins = Row("Pins", fy, { { "both", "World Map and Minimap" }, { "world", "World Map only" }, { "off", "Off" } }, "favPins")
    fy = fy + U(34)
    set.favLook = Row("Look", fy, { { "icon", "Item icon" }, { "dot", "Dot" } }, "favLook")
    favMap:SetHeight(fy + U(26) + U(12))
    set.favMap = favMap
    set.controls = { credit, set.favPins, set.favLook }

    -- the developer's build only (Dev.lua): pull every find this server's copies hold into the save
    if ns.DEV then
        local dev = T.Section(pane, "Developer")
        dev:SetPoint("TOPLEFT", favMap, "BOTTOMLEFT", 0, -U(12))
        dev:SetWidth(leftW)
        local pull = T.Button(dev, "Load everyone's finds", nil, U(26))
        pull:SetPoint("TOPLEFT", U(10), -(dev.top + U(10)))
        local note = T.Text(dev, 13, C.dim)
        note:SetPoint("LEFT", pull, "RIGHT", U(10), 0)
        local function Saved()
            local n = 0
            for _ in pairs(ns.db.finds or {}) do n = n + 1 end
            return n
        end
        note:SetText(Saved() .. " finds saved")
        pull:SetScript("OnClick", function()
            note:SetText(ns.Sync.CollectAll() and ("Asking this server's copies; " .. Saved() .. " saved") or "Sharing is not on yet")
        end)
        -- what this copy saw done to the sharing channel, for deciding bans (Bans.lua)
        local report = T.Button(dev, "Channel report", nil, U(26))
        report:SetPoint("TOPLEFT", pull, "BOTTOMLEFT", 0, -U(8))
        report:SetScript("OnClick", function() UI.ShowReport() end)
        local count = T.Text(dev, 13, C.dim)
        count:SetPoint("LEFT", report, "RIGHT", U(10), 0)
        local function Count()
            local n = ns.db.report and #ns.db.report or 0
            count:SetText(n == 1 and "1 line" or (n .. " lines"))
        end
        Count()
        ns.Listen("ReportChanged", Count)
        dev:SetHeight(dev.top + U(10) + U(26) + U(8) + U(26) + U(12))
        set.dev, set.pull, set.devNote, set.report, set.reportCount = dev, pull, note, report, count
    end
end

function UI.RefreshOptions()
    if opt.preview then
        opt.preview:SetText(UI.PopPreview())
        -- the box grows with its preview line, so the text never runs into its border
        opt.left:SetHeight(opt.leftBase + opt.preview:GetStringHeight() + U(10))
    end
    if opt.cardChecks then
        -- the card parts only mean something for the stat card
        local on = ns.settings and ns.settings.popStyle == "card"
        for _, cb in ipairs(opt.cardChecks) do
            cb:SetEnabled(on)
            cb.label:SetTextColor(T.RGB(on and C.ink or C.faint))
        end
        opt.cardLabel:SetTextColor(T.RGB(on and C.title or C.faint))
    end
end

-- the feed's rows, chips, count and empty line; true when it picked the first row to show
local function FillFeed()
    local data = FeedData()
    UI.feedList:SetData(data)
    local f = Settings().findFilter
    UI.feedFilter:Sync()
    local shown = (f.kinds.n and feedKinds.n or 0) + (f.kinds.c and feedKinds.c or 0)
    UI.feedCount:SetText(shown .. (shown == 1 and " find" or " finds"))
    for _, chip in ipairs(UI.feedKinds) do
        chip:SetLabel(chip.text .. " " .. feedKinds[chip.key])
        chip:SetOn(f.kinds[chip.key])
    end
    UI.feedEmpty:SetText((Filtered(f) and "No finds match.") or (ns.db.feedClearedAt and "Feed cleared. New finds show up here.") or
        "Nothing new yet. Items you and other players find show up here.")
    UI.feedEmpty:SetShown(#data == 0)
    if not selected and data[1] and data[1].id then
        selected = data[1].id
        UI.feedList:Refresh()
        return true
    end
end

-- refresh everything that shows
function UI.Refresh()
    if not win or not win:IsShown() then dirty = true return end
    dirty = false
    local feedOn, dbOn, optOn, setOn = tab == "feed", tab == "db", tab == "options", tab == "settings"
    local mined = UI.NewDatamined()
    local feedN, feedNew = FeedCount()
    UI.tabs.feed:Set("Live Feed (" .. feedN .. ")", feedOn, feedNew > 0 and (feedNew .. " NEW") or nil)
    UI.tabs.db:Set("Item Database", dbOn, mined > 0 and (mined .. " NEW") or nil)
    UI.tabs.options:Set("Pop-up Options", optOn)
    UI.tabs.settings:Set("Settings", setOn)
    UI.feedPane:SetShown(feedOn)
    UI.dbPane:SetShown(dbOn)
    UI.optPane:SetShown(optOn)
    UI.setPane:SetShown(setOn)
    -- the demo is for showing the addon to others: the developer's box stays out of it
    if set.dev then set.dev:SetShown(not ns.db.demoOn) end
    UI.detailPane:SetShown(not optOn and not setOn)
    UI.detailPane:ClearAllPoints()
    UI.detailPane:SetPoint("TOPRIGHT", -1, -1)
    UI.detailPane:SetPoint("BOTTOMRIGHT", -1, 1)
    UI.detailPane:SetPoint("LEFT", feedOn and UI.feedPane or UI.dbPane, "RIGHT", 0, 0)
    if feedOn then
        FillFeed()
    elseif dbOn then
        local refs = DbData()
        UI.DbListSet(refs)
        UI.dbEmpty:SetShown(#refs == 0)
        UI.catList:SetData(CatData())
        -- with full counts the chips can outgrow the list: their padding narrows a step at a time before the row
        -- would run past it, and nothing is ever cut
        local room = UI.dbPane:GetWidth() - 1 - U(10) - U(10)
        for _, pad in ipairs({ U(8), U(7), U(6), U(5), U(4) }) do
            local x = 0
            for i, chip in ipairs(UI.chips) do
                chip.pad = pad
                chip:SetLabel((chip.text ~= "" and (chip.text .. " ") or "") .. (dbChipCounts[chip.key] or 0))
                x = x + (i > 1 and U(6) or 0) + chip:GetWidth()
            end
            if x <= room then break end
        end
        for _, chip in ipairs(UI.chips) do chip:SetOn(state.kind == chip.key) end
    elseif optOn then
        UI.RefreshOptions()
        for _, c in ipairs(opt.controls or {}) do c:Refresh() end
        -- the feed may have changed the filter the pop-ups follow
        if opt.filter then opt.filter:Sync() end
    else
        for _, c in ipairs(set.controls or {}) do c:Refresh() end
    end
    if not optOn and not setOn then ShowDetail(selected) end
    UI.RefreshFooter()
end

-- finds coming in (a catch-up after login brings hundreds, a few a second): the tab count and the feed take them in;
-- the database shows them on the rows in view and refilters on the player's next click (the costly part), and the
-- detail side redraws only for the item it shows
local function RefreshFinds(touched)
    if not win or not win:IsShown() then dirty = true return end
    local feedN, feedNew = FeedCount()
    UI.tabs.feed:Set("Live Feed (" .. feedN .. ")", tab == "feed", feedNew > 0 and (feedNew .. " NEW") or nil)
    if tab == "feed" then
        if FillFeed() then touched = true end
    elseif tab == "db" then
        local list = UI.dbList
        for i = list.offset + 1, math.min(#list.data, list.offset + 40) do list.data[i] = false end
        list:Refresh()
    end
    if touched and (tab == "feed" or tab == "db") then ShowDetail(selected) end
    UI.RefreshFooter()
end

-- rows are built only for what scrolls into view: the list holds placeholders until then; the placeholder list is
-- refilled in place, so a refresh does not leave a table the size of the database behind
local dbView = {}
-- a set of picks as one stable string
local function SetSig(set)
    local keys = {}
    for k in pairs(set) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return table.concat(keys, ",")
end
function UI.DbListSet(refs)
    local view = dbView
    for i = #refs + 1, #view do view[i] = nil end
    for i = 1, #refs do view[i] = false end
    local list = UI.dbList
    list.data = view
    local origRefresh = list.Refresh
    if not list.lazy then
        list.lazy = true
        list.Refresh = function(self)
            local n = math.max(1, math.floor((self:GetHeight() or 0) / U(46)))
            for i = self.offset + 1, math.min(#self.data, self.offset + n + 1) do
                if self.data[i] == false then
                    self.data[i] = DbItem(self.refs[i])
                end
            end
            origRefresh(self)
        end
    end
    list.refs = refs
    -- the scroll stays put unless the filters changed
    local sig = table.concat({ state.q, tostring(state.minL), tostring(state.maxL), SetSig(state.qs), SetSig(state.slots), SetSig(state.clss),
        state.src, state.dg, state.kind, state.cat }, "|")
    if list.sig ~= sig then list.offset = 0 list.sig = sig end
    list:Refresh()
end

function UI.RefreshFooter()
    if not UI.footText then return end
    local S = ns.Sync
    if S.state == "nochannel" then
        UI.footDot:SetColorTexture(T.RGB(C.badge))
        UI.footText:SetText("Sharing paused: the chat channel is full or unavailable.")
        return
    end
    UI.footDot:SetColorTexture(T.RGB(C.green))
    local where = ns.isForever and "players on your ruleset" or "players on this realm (test run)"
    local heard = S.LastHeard()
    if heard then
        local mins = math.floor((GetTime() - heard) / 60)
        UI.footText:SetText(("Sharing with %s. Synced %s"):format(where, mins < 1 and "just now" or (mins .. " min ago")))
    else
        UI.footText:SetText("Sharing with " .. where .. ".")
    end
end

-- the feed's Refresh: asks the server again for names it has not sent (a few at a time), asks other players for finds
-- this copy missed (Sync keeps that to once a minute), then redraws
function UI.RefreshFeed()
    local asks = 0
    for _, e in ipairs(ns.Finds.List()) do
        if asks >= 30 then break end
        if not C_Item.GetItemInfo(e.id) and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(e.id)
            asks = asks + 1
        end
    end
    ns.Sync.AskAgain()
    UI.Refresh()
end

function UI.Show(which)
    if not win then Build() end
    -- leaving the feed: what it showed counts as seen
    if which and which ~= "feed" and tab == "feed" and win:IsShown() then FeedSeen() end
    tab = which or tab
    if tab == "db" and ns.db then
        ns.db.seedVersion, ns.db.demoMined = D.version, nil
        ns.Signal("DatabaseSeen")
    end
    if tab == "db" and selected and not (ns.Finds.Get(selected) or D.Seed(selected)) then selected = nil end
    win:Show()
    UI.Refresh()
end

function UI.Toggle()
    if win and win:IsShown() then win:Hide() else UI.Show() end
end

function UI.Select(id)
    selected = id
    UI.Show("feed")
end

-- a link the game cannot open: shown selected, ready to copy
function UI.ShowLink(url)
    if not UI.linkBox then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(U(360), U(70))
        f:SetPoint("CENTER", 0, U(120))
        f:SetFrameStrata("DIALOG")
        T.Panel(f, C.bg, C.gold)
        local l = T.Text(f, 12, C.dim)
        l:SetPoint("TOPLEFT", U(10), -U(8))
        l:SetText("Copy the link (Ctrl+C), then close")
        local e = T.EditBox(f, U(340), U(24))
        e:SetPoint("BOTTOMLEFT", U(10), U(10))
        e:SetScript("OnEscapePressed", function() f:Hide() end)
        local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        x:SetPoint("TOPRIGHT", 2, 2)
        f.edit = e
        UI.linkBox = f
    end
    if UI.shareBox then UI.shareBox:Hide() end
    UI.linkBox.edit:SetText(url)
    UI.linkBox:Show()
    UI.linkBox.edit:SetFocus()
    UI.linkBox.edit:HighlightText()
end

-- the developer's channel report, newest first, in a box to copy from (typing in it puts the text back)
function UI.ReportText()
    local r = ns.db and ns.db.report or {}
    if #r == 0 then return "Nothing seen yet. Takeovers of the sharing channel and muted players show up here." end
    local lines = {}
    for i = #r, 1, -1 do lines[#lines + 1] = date("%b %d %H:%M", r[i].t) .. "  " .. r[i].text end
    return table.concat(lines, "\n")
end

function UI.ShowReport()
    if not UI.reportBox then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(U(560), U(330))
        f:SetPoint("CENTER", 0, U(60))
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        T.Panel(f, C.bg, C.gold)
        local title = T.Text(f, 15, C.title)
        title:SetPoint("TOPLEFT", U(12), -U(10))
        title:SetText("Channel report")
        local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        x:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", U(12), -U(40))
        scroll:SetPoint("BOTTOMRIGHT", -U(32), U(48))
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFont(T.FONT, U(12), "")
        box:SetTextColor(T.RGB(C.ink))
        box:SetWidth(U(510))
        scroll:SetScrollChild(box)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        box:SetScript("OnTextChanged", function(self, user)
            if user and self.keep then
                self:SetText(self.keep)
                self:HighlightText()
            end
        end)
        local all = T.Button(f, "Select all", nil, U(26))
        all:SetPoint("BOTTOMLEFT", U(12), U(12))
        all:SetScript("OnClick", function()
            box:SetFocus()
            box:HighlightText()
        end)
        local clear = T.Button(f, "Clear", nil, U(26))
        clear:SetPoint("LEFT", all, "RIGHT", U(8), 0)
        clear:SetScript("OnClick", function()
            ns.db.report = {}
            UI.ShowReport()
        end)
        f.box, f.all, f.clear = box, all, clear
        UI.reportBox = f
    end
    local f = UI.reportBox
    f.box.keep = UI.ReportText()
    f.box:SetText(f.box.keep)
    f:Show()
end

-- Share your finds: the share string to copy (Proto.EncodeShare) and the website to paste it on. The boxes only offer
-- their text: typing in them puts it back.
function UI.ShowShare()
    if not UI.shareBox then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(U(420), U(150))
        f:SetPoint("CENTER", 0, U(120))
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        T.Panel(f, C.bg, C.gold)
        local title = T.Text(f, 15, C.title)
        title:SetPoint("TOPLEFT", U(12), -U(10))
        title:SetText("Share your finds")
        local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        x:SetPoint("TOPRIGHT", 2, 2)
        local step1 = T.Text(f, 12, C.ink)
        step1:SetPoint("TOPLEFT", U(12), -U(38))
        local code = T.EditBox(f, U(396), U(24))
        code:SetPoint("TOPLEFT", U(12), -U(56))
        code:SetMaxLetters(0)
        local step2 = T.Text(f, 12, C.ink)
        step2:SetPoint("TOPLEFT", U(12), -U(90))
        step2:SetText("2. Paste it on the website and press Share:")
        local site = T.EditBox(f, U(396), U(24))
        site:SetPoint("TOPLEFT", U(12), -U(108))
        for _, e in ipairs({ code, site }) do
            e:SetScript("OnEscapePressed", function() f:Hide() end)
            e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            e:HookScript("OnTextChanged", function(self, user)
                if user and self.keep then
                    self:SetText(self.keep)
                    self:HighlightText()
                end
            end)
        end
        f.step1, f.step2, f.code, f.site = step1, step2, code, site
        UI.shareBox = f
    end
    if UI.linkBox then UI.linkBox:Hide() end
    local f = UI.shareBox
    local list = ns.Finds.ShareList()
    local text = #list > 0 and ns.Proto.EncodeShare(ns.Finds.ShareID(), list) or ""
    f.step1:SetText(#list > 0 and ("1. Copy your " .. #list .. (#list == 1 and " find" or " finds") .. " (Ctrl+C):") or
        "Nothing to share yet: finds you and other players make show up here.")
    f.code.keep, f.site.keep = text, ns.SITE
    f.code:SetText(text)
    f.site:SetText(ns.SITE)
    f.code:SetShown(#list > 0)
    f.step2:SetShown(#list > 0)
    f.site:SetShown(#list > 0)
    f:Show()
    if #list > 0 then
        f.code:SetFocus()
        f.code:HighlightText()
    end
end

-- what makes the window redraw
local queued
-- a lone find shows within a moment; a stream of them redraws at most every FINDS_GAP seconds
local FINDS_GAP = 2
local full, touched, lastFinds = false, false, -FINDS_GAP
local function Soon(e)
    if not e then full = true elseif e.id == selected then touched = true end
    if queued then return end
    queued = true
    C_Timer.After(math.max(0.2, lastFinds + FINDS_GAP - GetTime()), function()
        queued, lastFinds = false, GetTime()
        local all, mine = full, touched
        full, touched = false, false
        if all then UI.Refresh() else RefreshFinds(mine) end
    end)
end
ns.Listen("FindsChanged", Soon)
ns.Listen("SyncState", function() UI.RefreshFooter() end)
ns.Listen("ToggleWindow", function() UI.Toggle() end)
ns.Listen("OpenWindow", function(which) UI.Show(which) end)
-- item data arriving redraws the rows it shows on, never the whole list (an open window asks for many items)
local redrawQueued
local function RedrawRows()
    redrawQueued = false
    if not win or not win:IsShown() then return end
    if tab == "db" then
        local list = UI.dbList
        for i = list.offset + 1, math.min(#list.data, list.offset + 40) do list.data[i] = false end
        list:Refresh()
    elseif tab == "feed" then
        UI.Refresh()
    end
end
ns.On("GET_ITEM_INFO_RECEIVED", function(id)
    -- its picture may have come with it: the database places it again on its next refresh
    if hasArt[id] == false then hasArt[id] = nil end
    if not win or not win:IsShown() then return end
    if id == selected then ShowDetail(selected) end
    local list = tab == "db" and UI.dbList or UI.feedList
    local shown = false
    for _, r in ipairs(list.rows or {}) do
        if r.id == id and r:IsShown() then shown = true break end
    end
    if not shown or redrawQueued then return end
    redrawQueued = true
    C_Timer.After(0.2, RedrawRows)
end)
ns.Listen("Login", function()
    D.LocalizeCategories()
    -- a first install starts with nothing "new": later updates count what they add
    if not ns.db.seedVersion then ns.db.seedVersion = D.version end
    if ns.db.dataVersion ~= D.version then
        ns.db.dataVersion = D.version
        ns.db.minedAt = ns.Now()
    end
end)
