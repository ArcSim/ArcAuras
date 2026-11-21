-- UI\AD_GearListWindow.lua: the gear list window: every piece that beats your gear, folded by where you get it, the
-- dungeon you are in first and open.
-- Draws NS.GearList; opened from the Gear Value page or "/arcauras gear".
local ADDON, NS = ...

local UI = {}
NS.GearListUI = UI

-- sizes from the picked board (canvas row 7)
UI.W, UI.H = 820, 760
UI.BAR_H, UI.HERE_H, UI.FOOT_H = 44, 50, 30
UI.GROUP_H, UI.SUB_H, UI.ROW_H, UI.GAP, UI.PAD = 34, 26, 36, 6, 12
UI.SLOT_W, UI.WHERE_W, UI.GAIN_W, UI.INDENT = 70, 190, 74, 32
UI.GOLD = { 0.949, 0.831, 0.608 }
UI.UP = { 0.357, 0.839, 0.541 }
UI.rows, UI.boxes = {}, {}

local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end

local function Text(parent, size, justify)
    local AT = NS.AT
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- A gain in the scale's unit: "+9 SP".
function UI.GainText(d, scale)
    local G = NS.GearValue
    local unit = (G and G.Unit(scale)) or Tr("points")
    return "+" .. (G and G.Num(d) or tostring(d)) .. " " .. unit
end

function UI.Build()
    if UI.win then return UI.win end
    local AT = NS.AT
    local COL = AT.COL
    local w = AT.CreateWindow("ArcAurasGearList", { title = "Gear Checklist", w = UI.W, h = UI.H, minW = 520, minH = 420,
        maxW = 1000, maxH = 1100 })
    UI.win = w
    w:Hide()

    local bar = CreateFrame("Frame", nil, w)
    bar:SetPoint("TOPLEFT", 1, -31)
    bar:SetPoint("TOPRIGHT", -1, -31)
    bar:SetHeight(UI.BAR_H)
    -- the two views on the theme's tabs, sitting on the bar's foot
    UI.tabs = AT.TabRow(bar)
    UI.tabs:SetPoint("TOPLEFT", 16, -(UI.BAR_H - 24))
    UI.tabs:SetPoint("TOPRIGHT", -16, -(UI.BAR_H - 24))
    UI.tabs:SetHeight(24)
    local label = Text(bar, 12)
    label:SetText(Tr("Scale"))
    Color(label, COL.faint)
    UI.scaleDD = AT.MakeDropdown(w, bar, 180, function()
        local out = {}
        for _, s in ipairs(NS.GearList.Scales()) do out[#out + 1] = { value = s.id, text = s.name } end
        return out
    end, function()
        local s = NS.GearList.Scale()
        return s and s.id
    end, function(v) NS.GearList.SetScale(v) end)
    UI.scaleDD:SetPoint("RIGHT", -16, 0)
    label:SetPoint("RIGHT", UI.scaleDD, "LEFT", -10, 0)
    UI.count = Text(bar, 12, "RIGHT")
    UI.count:SetPoint("RIGHT", label, "LEFT", -18, 0)
    Color(UI.count, COL.dim)
    local rule = bar:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)

    -- the dungeon he is in, on its own band
    local here = CreateFrame("Frame", nil, w, "BackdropTemplate")
    here:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
    here:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    here:SetHeight(UI.HERE_H)
    AT.Skin(here, COL.panel, COL.line2)
    UI.hereTitle = Text(here, 14)
    UI.hereTitle:SetPoint("TOPLEFT", 16, -9)
    Color(UI.hereTitle, UI.GOLD)
    UI.hereSub = Text(here, 11)
    UI.hereSub:SetPoint("TOPLEFT", UI.hereTitle, "BOTTOMLEFT", 0, -3)
    Color(UI.hereSub, COL.dim)
    UI.hereNote = Text(here, 11, "RIGHT")
    UI.hereNote:SetPoint("RIGHT", -16, 0)
    Color(UI.hereNote, COL.faint)

    local foot = CreateFrame("Frame", nil, w, "BackdropTemplate")
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(UI.FOOT_H)
    AT.Skin(foot, COL.well, COL.line)
    UI.footLeft = Text(foot, 11)
    UI.footLeft:SetPoint("LEFT", 16, 0)
    Color(UI.footLeft, COL.faint)
    -- clear of the window's resize grip in the corner
    UI.footRight = Text(foot, 11, "RIGHT")
    UI.footRight:SetPoint("RIGHT", -22, 0)
    Color(UI.footRight, COL.faint)

    local host, content = AT.MakeScroll(w)
    host:SetPoint("TOPLEFT", here, "BOTTOMLEFT", UI.PAD, -8)
    host:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", -UI.PAD - AT.ScrollW, 10)
    UI.host, UI.content = host, content
    host:SetScript("OnSizeChanged", function()
        host:UpdateScroll()
        UI.Refresh()
    end)
    -- the empty and waiting states, in the list's place
    UI.empty = Text(w, 12, "CENTER")
    UI.empty:SetPoint("TOP", here, "BOTTOM", 0, -40)
    UI.empty:SetWidth(UI.W - 80)
    UI.empty:SetWordWrap(true)
    Color(UI.empty, COL.dim)
    UI.here = here
    UI.BuildMyList(w, bar, foot)
    w:HookScript("OnShow", function()
        NS.GearList.Build()
        UI.Refresh()
    end)
    return w
end

-- The tab words, written out so the key scan sees them; the tab row shows them as given.
function UI.TabWord(key)
    if key == "list" then return Tr("My List") end
    return Tr("Upgrades")
end

-- My List (the row 6 board's page): a heading with the progress, then a table, one row per slot.
UI.MY_HERO_H, UI.MY_HEAD_H, UI.MY_ROW_H, UI.MY_PAD = 74, 26, 34, 14
UI.MY_GOT_W, UI.MY_SLOT_W, UI.MY_WORN_W, UI.MY_GAIN_W, UI.MY_PCT_W = 34, 92, 250, 110, 70
UI.myRows = {}

local function Caps(s)
    if type(s) ~= "string" or s:find("[\128-\255]") then return s end
    return s:upper()
end

function UI.BuildMyList(w, bar, foot)
    local AT = NS.AT
    local COL = AT.COL
    local v = CreateFrame("Frame", nil, w)
    v:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
    v:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0)
    v:Hide()
    UI.myView = v
    local hero = CreateFrame("Frame", nil, v)
    hero:SetPoint("TOPLEFT")
    hero:SetPoint("TOPRIGHT")
    hero:SetHeight(UI.MY_HERO_H)
    v.title = Text(hero, 24)
    v.title:SetPoint("TOPLEFT", 20, -16)
    Color(v.title, UI.GOLD)
    v.title:SetText(Tr("My List"))
    v.sub = Text(hero, 12)
    v.sub:SetPoint("TOPLEFT", v.title, "BOTTOMLEFT", 0, -4)
    Color(v.sub, COL.dim)
    v.sub:SetText(Tr("Per slot, the best piece you can get outside raids, and where it comes from"))
    v.barBg = CreateFrame("Frame", nil, hero, "BackdropTemplate")
    v.barBg:SetSize(220, 6)
    v.barBg:SetPoint("BOTTOMRIGHT", -20, 22)
    AT.Skin(v.barBg, COL.well, COL.line)
    v.barFill = v.barBg:CreateTexture(nil, "ARTWORK")
    v.barFill:SetPoint("TOPLEFT")
    v.barFill:SetPoint("BOTTOMLEFT")
    v.barFill:SetColorTexture(UI.UP[1], UI.UP[2], UI.UP[3], 1)
    v.prog = Text(hero, 13, "RIGHT")
    v.prog:SetPoint("BOTTOMRIGHT", v.barBg, "TOPRIGHT", 0, 6)
    Color(v.prog, COL.ink)
    -- the table: a box, its column heads on a raised strip, the rows scrolling under them
    local box = CreateFrame("Frame", nil, v, "BackdropTemplate")
    box:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 16, 0)
    box:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -16, 14)
    AT.Skin(box, COL.box, COL.line2)
    v.box = box
    local hair = AT.Hairline(box)
    local head = CreateFrame("Frame", nil, box, "BackdropTemplate")
    head:SetPoint("TOPLEFT", hair, -hair)
    head:SetPoint("TOPRIGHT", -hair, -hair)
    head:SetHeight(UI.MY_HEAD_H)
    AT.Skin(head, COL.btn, COL.btn)
    local foot2 = head:CreateTexture(nil, "OVERLAY")
    foot2:SetPoint("BOTTOMLEFT")
    foot2:SetPoint("BOTTOMRIGHT")
    foot2:SetHeight(hair)
    foot2:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    v.head = head
    v.heads = {}
    for i, word in ipairs({ Tr("Got"), Tr("Slot"), Tr("You wear"), Tr("Best you can get"), Tr("Gain"), Tr("Vs worn") }) do
        local fs = Text(head, 11, (i >= 5) and "RIGHT" or "LEFT")
        Color(fs, COL.dim)
        fs:SetText(Caps(word))
        v.heads[i] = fs
    end
    local host, content = AT.MakeScroll(box)
    host:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -hair - AT.ScrollW, hair)
    host:SetScript("OnSizeChanged", function()
        host:UpdateScroll()
        UI.Refresh()
    end)
    v.host, v.content = host, content
end

-- The worn column's width: the board's 250 where the window is as wide as the board, less where it is not.
function UI.MyCols(rowW)
    local fixed = UI.MY_GOT_W + UI.MY_SLOT_W + UI.MY_GAIN_W + UI.MY_PCT_W + 2 * UI.MY_PAD
    local worn = math.min(UI.MY_WORN_W, math.floor((rowW - fixed) * 0.45))
    local x = UI.MY_PAD
    return { got = x, slot = x + UI.MY_GOT_W, worn = x + UI.MY_GOT_W + UI.MY_SLOT_W, wornW = worn,
        best = x + UI.MY_GOT_W + UI.MY_SLOT_W + worn,
        bestW = rowW - (x + UI.MY_GOT_W + UI.MY_SLOT_W + worn) - UI.MY_GAIN_W - UI.MY_PCT_W - UI.MY_PAD - 10 }
end

function UI.MyRow(i)
    local row = UI.myRows[i]
    if row then return row end
    local AT = NS.AT
    local COL = AT.COL
    row = CreateFrame("Button", nil, UI.myView.content)
    row:SetHeight(UI.MY_ROW_H)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    row.hl:Hide()
    row.rule = row:CreateTexture(nil, "BORDER")
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(AT.Hairline(row))
    row.rule:SetColorTexture(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    row.tick = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.tick:SetSize(18, 18)
    row.tick:SetPoint("LEFT", UI.MY_PAD, 0)
    AT.Skin(row.tick, COL.well, COL.steel)
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetAtlas("checkmark-minimal")
    row.check:SetDesaturated(true)
    row.check:SetVertexColor(UI.UP[1], UI.UP[2], UI.UP[3], 1)
    row.check:SetSize(18, 18)
    row.check:SetPoint("CENTER", row.tick, "CENTER")
    row.tick:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        if id then NS.GearList.SetHas(id, not NS.GearList.Has(id)) end
    end)
    row.slot = Text(row, 11)
    Color(row.slot, COL.faint)
    row.worn = Text(row, 12)
    Color(row.worn, COL.dim)
    row.name = Text(row, 13)
    row.from = Text(row, 11)
    Color(row.from, COL.faint)
    row.gain = Text(row, 14, "RIGHT")
    Color(row.gain, UI.UP)
    row.pct = Text(row, 12, "RIGHT")
    Color(row.pct, COL.dim)
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.id then UI.Tip(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
        end
    end)
    UI.myRows[i] = row
    return row
end

function UI.RefreshMyList(scale)
    local AT, GL, G = NS.AT, NS.GearList, NS.GearValue
    local COL = AT.COL
    local v = UI.myView
    local rows, n = GL.MyList(scale)
    v.prog:SetText(n.up == 0 and Tr("Nothing here beats your gear")
        or string.format(n.up == 1 and Tr("%d of %d upgrade got") or Tr("%d of %d upgrades got"), n.got, n.up))
    local frac = n.up > 0 and (n.got / n.up) or 0
    v.barFill:SetWidth(math.max(0.001, v.barBg:GetWidth() * frac))
    v.barFill:SetShown(frac > 0)
    UI.footRight:SetText(string.format(Tr("%d of %d slots already at their best"), n.done, n.slots))
    local rowW = math.max(300, v.host:GetWidth() or 600)
    -- the heads span the scroll bar's lane too: their right columns sit that much further in
    local c = UI.MyCols(rowW)
    local lane = AT.ScrollW
    local hd = v.heads
    hd[1]:ClearAllPoints() hd[1]:SetPoint("LEFT", c.got, 0)
    hd[2]:ClearAllPoints() hd[2]:SetPoint("LEFT", c.slot, 0)
    hd[3]:ClearAllPoints() hd[3]:SetPoint("LEFT", c.worn, 0)
    hd[4]:ClearAllPoints() hd[4]:SetPoint("LEFT", c.best, 0)
    hd[5]:ClearAllPoints() hd[5]:SetPoint("RIGHT", -(UI.MY_PAD + UI.MY_PCT_W + lane), 0)
    hd[5]:SetWidth(UI.MY_GAIN_W)
    hd[6]:ClearAllPoints() hd[6]:SetPoint("RIGHT", -(UI.MY_PAD + lane), 0)
    hd[6]:SetWidth(UI.MY_PCT_W)
    local QC = ITEM_QUALITY_COLORS or {}
    local cache = GL.Cache()
    for i, r in ipairs(rows) do
        local row = UI.MyRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -(i - 1) * UI.MY_ROW_H)
        row:SetWidth(rowW)
        row:Show()
        local e = r.best
        row.id = e and e.id or nil
        row.places = e and e.places or nil
        row.link = e and cache and cache[e.id] and cache[e.id].l or nil
        row.slot:ClearAllPoints()
        row.slot:SetPoint("LEFT", c.slot, 0)
        row.slot:SetWidth(UI.MY_SLOT_W - 4)
        row.slot:SetText(Caps(r.word))
        row.worn:ClearAllPoints()
        row.worn:SetPoint("LEFT", c.worn, 0)
        row.worn:SetWidth(c.wornW - 10)
        row.worn:SetText(r.worn ~= "" and r.worn or Tr("Empty slot"))
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", c.best, 0)
        row.from:ClearAllPoints()
        row.from:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.gain:ClearAllPoints()
        row.gain:SetPoint("RIGHT", -(UI.MY_PAD + UI.MY_PCT_W), 0)
        row.gain:SetWidth(UI.MY_GAIN_W)
        row.pct:ClearAllPoints()
        row.pct:SetPoint("RIGHT", -UI.MY_PAD, 0)
        row.pct:SetWidth(UI.MY_PCT_W)
        if e then
            local has = GL.Has(e.id)
            row.tick:Show()
            row.tick:SetBackdropBorderColor(has and UI.UP[1] or COL.steel[1], has and UI.UP[2] or COL.steel[2],
                has and UI.UP[3] or COL.steel[3], 1)
            row.check:SetShown(has)
            row:SetAlpha(has and 0.5 or 1)
            row.name:SetText(e.name or "")
            local q = QC[e.q or 1] or { r = 1, g = 1, b = 1 }
            row.name:SetTextColor(q.r, q.g, q.b)
            row.name:SetWidth(0)
            local nw = math.min(row.name:GetStringWidth() or 0, c.bestW)
            row.name:SetWidth(math.max(1, nw))
            row.from:SetWidth(math.max(1, c.bestW - nw - 10))
            row.from:SetText(r.from or "")
            row.gain:SetText(UI.GainText(e.gain.d, scale))
            local pct = G and G.Pct and G.Pct(e.gain.d, e.gain.was)
            row.pct:SetText(pct and G.PctText(pct) or "")
        else
            -- nothing within reach beats what he wears there
            row.tick:Hide()
            row.check:Show()
            row:SetAlpha(0.75)
            row.name:SetWidth(c.bestW)
            row.name:SetText(Tr("Best you can get"))
            Color(row.name, UI.UP)
            row.from:SetText("")
            row.gain:SetText("")
            row.pct:SetText("")
        end
    end
    for i = #rows + 1, #UI.myRows do UI.myRows[i]:Hide() end
    v.content:SetSize(rowW, math.max(1, #rows * UI.MY_ROW_H))
    v.host:UpdateScroll()
end

-- A row of the list; one frame serves a place, a boss line or a piece.
function UI.Row(i)
    local row = UI.rows[i]
    if row then return row end
    local AT = NS.AT
    local COL = AT.COL
    row = CreateFrame("Button", nil, UI.content, "BackdropTemplate")
    row:RegisterForClicks("LeftButtonUp")
    -- every kind recolours the one skin (its border stays clear: the group's box draws the edge); a line on top
    -- parts a boss line or a piece from the row above
    AT.Skin(row, COL.box, COL.line)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row.top = row:CreateTexture(nil, "BORDER")
    row.top:SetPoint("TOPLEFT")
    row.top:SetPoint("TOPRIGHT")
    row.top:SetHeight(AT.Hairline(row))
    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.chev = AT.MakeChevron(row)
    row.chev:SetPoint("LEFT", UI.PAD, 0)
    row.tick = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.tick:SetSize(16, 16)
    row.tick:SetPoint("LEFT", UI.INDENT, 0)
    AT.Skin(row.tick, COL.well, COL.steel)
    row.tick.mark = row.tick:CreateTexture(nil, "OVERLAY")
    row.tick.mark:SetPoint("TOPLEFT", 3, -3)
    row.tick.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    row.tick.mark:SetColorTexture(UI.UP[1], UI.UP[2], UI.UP[3], 1)
    row.tick:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        if id then NS.GearList.SetHas(id, not NS.GearList.Has(id)) end
    end)
    row.name = Text(row, 13)
    row.slot = Text(row, 11)
    Color(row.slot, COL.faint)
    row.where = Text(row, 11)
    Color(row.where, COL.dim)
    row.gain = Text(row, 13, "RIGHT")
    Color(row.gain, UI.UP)
    row.count = Text(row, 11, "RIGHT")
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.kind == "item" then UI.Tip(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if self.kind == "group" then
            local m = NS.GearList.Mine()
            if m then m.open[self.key] = not self.open end
            UI.Refresh()
        elseif self.kind == "item" and IsModifiedClick and IsModifiedClick("CHATLINK") and self.link then
            if ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
        end
    end)
    UI.rows[i] = row
    return row
end

-- A group's box: the edge around its strip and the rows it opens to.
function UI.Box(i)
    local box = UI.boxes[i]
    if box then return box end
    local AT = NS.AT
    box = CreateFrame("Frame", nil, UI.content, "BackdropTemplate")
    box:SetFrameLevel(math.max(0, UI.content:GetFrameLevel()))
    AT.Skin(box, AT.COL.box, AT.COL.line2)
    UI.boxes[i] = box
    return box
end

-- A piece's tooltip: the game's own (Gear Value adds its lines), then every place it comes from.
function UI.Tip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.link then GameTooltip:SetHyperlink(row.link) elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(row.id) end
    local places = row.places or {}
    if #places > 0 then
        GameTooltip:AddLine(" ")
        for i, p in ipairs(places) do
            if i > 6 then break end
            GameTooltip:AddLine(UI.PlaceText(p), 0.70, 0.78, 0.88)
        end
    end
    GameTooltip:Show()
end

function UI.PlaceText(p)
    if p.k == "drop" then
        local chance = (type(p.p) == "number" and p.p > 0) and (" " .. (p.p >= 10 and math.floor(p.p + 0.5) or (math.floor(p.p * 10 + 0.5) / 10)) .. "%") or ""
        return (p.place or "") .. ": " .. (p.who or "") .. chance
    end
    if p.k == "quest" then return Tr("Quest") .. ": " .. (p.who or "") end
    if p.k == "craft" then return Tr("Crafted") .. ": " .. (p.who or "") .. ((p.skill and p.skill > 0) and (" " .. p.skill) or "") end
    if p.k == "vendor" or p.k == "box" then return Tr("Sold by") .. ": " .. (p.who or "") end
    if p.k == "mob" or p.k == "chest" then return Tr("Drops from") .. ": " .. (p.who or "") end
    return Tr("World drop")
end

-- What a piece's row says about where to get it, under its group.
function UI.WhereText(g, e, block)
    local GL = NS.GearList
    if block then
        local c = GL.ChanceText(block, e.id)
        return c ~= "" and (c .. " " .. Tr("drop")) or Tr("drop")
    end
    for _, kind in ipairs({ g.key }) do
        for _, p in ipairs(e.places) do
            if (kind == "quest" and p.k == "quest") then return Tr("Quest") .. ": " .. p.who end
            if (kind == "craft" and p.k == "craft") then return p.who .. ((p.skill and p.skill > 0) and (" " .. p.skill) or "") end
            if (kind == "vendor" and (p.k == "vendor" or p.k == "box")) then return p.who end
        end
    end
    for _, p in ipairs(e.places) do
        if p.k == "mob" or p.k == "chest" then return p.who end
    end
    return Tr("Any mob, or the AH")
end

local function Place(row, x, y, w, h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", UI.content, "TOPLEFT", x, -y)
    row:SetSize(w, h)
    row:Show()
end

local function Fill(row, c, a) row:SetBackdropColor(c[1], c[2], c[3], a or 1) end
local function Tex(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a or 1) end

function UI.Refresh()
    local w = UI.win
    if not (w and w:IsShown()) then return end
    local AT, GL, G = NS.AT, NS.GearList, NS.GearValue
    local COL = AT.COL
    local scale = GL.Scale()
    if UI.scaleDD and UI.scaleDD.Refresh then UI.scaleDD:Refresh() end
    local mine = GL.Mine()
    local tab = (mine and mine.tab == "list") and "list" or "ups"
    UI.tab = tab
    UI.tabs:Set({ UI.TabWord("ups"), UI.TabWord("list") }, UI.TabWord(tab), function(name)
        local mm = GL.Mine()
        if mm then mm.tab = (name == UI.TabWord("list")) and "list" or nil end
        UI.Refresh()
    end)
    local used = 0
    local function Rows() used = used + 1 return UI.Row(used) end
    UI.empty:SetText("")
    local groups = {}
    local ready = false
    if not GL.Available() then
        UI.empty:SetText(NS.IsForever and Tr("The gear list needs Gear Value and the Item Finds module on.")
            or Tr("The gear list is for WoW Forever."))
    elseif not scale then
        UI.empty:SetText(Tr("Show a scale for this talent group on the Gear Value page first."))
    elseif not GL.cands then
        UI.empty:SetText(Tr("Gathering every piece within reach..."))
    else
        ready = true
        if tab == "ups" then groups = GL.Groups(scale) end
    end
    -- one view at a time: the upgrades by place, or My List by slot
    local onList = tab == "list"
    UI.here:SetShown(not onList)
    UI.host:SetShown(not onList)
    UI.count:SetShown(not onList)
    UI.myView:SetShown(onList and ready)
    if onList then
        for i = 1, #UI.rows do UI.rows[i]:Hide() end
        for i = 1, #UI.boxes do UI.boxes[i]:Hide() end
        local left = GL.Left and GL.Left() or 0
        UI.footLeft:SetText(left > 0 and string.format(Tr("Reading items: %d left"), left)
            or (scale and string.format(Tr("Gains on %s against the gear you wear"), scale.name) or ""))
        UI.footRight:SetText("")
        if ready then UI.RefreshMyList(scale) end
        return
    end
    UI.footRight:SetText(Tr("Drop chances: the item finder's data"))
    -- the count, the band, the footer
    local total = 0
    for _, g in ipairs(groups) do total = total + #g.list end
    UI.count:SetText(scale and GL.cands and string.format(Tr("%d pieces beat your gear on %s"), total, scale.name) or "")
    local hereGroup
    for _, g in ipairs(groups) do if g.here then hereGroup = g end end
    if GL.here and hereGroup then
        UI.hereTitle:SetText(string.format(#hereGroup.list == 1 and Tr("In %s: %d piece for you") or Tr("In %s: %d pieces for you"),
            GL.here.name, #hereGroup.list))
        UI.hereSub:SetText(string.format(Tr("Best: %s %s"), hereGroup.list[1].name, UI.GainText(hereGroup.list[1].gain.d, scale)))
    elseif GL.here then
        UI.hereTitle:SetText(string.format(Tr("Nothing in %s beats your gear"), GL.here.name))
        UI.hereSub:SetText(Tr("Try the other places below"))
    else
        UI.hereTitle:SetText(Tr("Not in a dungeon"))
        UI.hereSub:SetText(Tr("The one you enter comes first"))
    end
    local S = NS.Store
    UI.hereNote:SetText((S and S.GetSetting and S.GetSetting("gearTracker")) and Tr("Its tracker is on while you are inside") or "")
    local left = GL.Left and GL.Left() or 0
    UI.footLeft:SetText(left > 0 and string.format(Tr("Reading items: %d left"), left)
        or (scale and string.format(Tr("Gains on %s against the gear you wear"), scale.name) or ""))

    -- each place is a box: its strip, then (open) its boss lines and pieces inside the box's edge
    local cw = math.max(200, (UI.host:GetWidth() or (UI.W - 40)))
    local hair = AT.Hairline(UI.content)
    local rw = cw - 2 * hair
    local right = UI.PAD + UI.GAIN_W
    local nameW = math.max(80, rw - (UI.INDENT + 16 + 10) - (right + 10 + UI.WHERE_W + 10 + UI.SLOT_W + 10))
    local y = 0
    local m = GL.Mine() or { open = {} }
    local QC = ITEM_QUALITY_COLORS or {}
    local boxes = 0
    for _, g in ipairs(groups) do
        local open = m.open[g.key]
        if open == nil then open = g.here end
        boxes = boxes + 1
        local box = UI.Box(boxes)
        local top = y
        y = y + hair
        local row = Rows()
        row.kind, row.key, row.open, row.id, row.link, row.places = "group", g.key, open, nil, nil, nil
        Place(row, hair, y, rw, UI.GROUP_H)
        y = y + UI.GROUP_H
        Fill(row, open and COL.btn or COL.box)
        Tex(row.hl, COL.btnHover)
        row.top:Hide()
        row:SetAlpha(1)
        row.chev:Show()
        row.chev:SetDown(open)
        row.tick:Hide()
        row.name:SetFont(NS.AT.FONT, 14, "")
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", UI.PAD + 10 + 10, 0)
        row.name:SetWidth(rw - 240)
        row.name:SetText(g.here and (g.name .. "  " .. Tr("(you are here)")) or g.name)
        Color(row.name, g.here and UI.GOLD or COL.ink)
        row.slot:SetText("")
        row.where:SetText("")
        row.count:ClearAllPoints()
        row.count:SetPoint("RIGHT", -(right + 10), 0)
        Color(row.count, COL.dim)
        row.count:SetText(string.format(#g.list == 1 and Tr("%d piece") or Tr("%d pieces"), #g.list))
        row.gain:SetFont(NS.AT.FONT, 12, "")
        row.gain:ClearAllPoints()
        row.gain:SetPoint("RIGHT", -UI.PAD, 0)
        row.gain:SetWidth(UI.GAIN_W)
        row.gain:SetText(UI.GainText(g.best, scale))
        if open then
            local function Item(e, where)
                local r = Rows()
                r.kind, r.id, r.places, r.link = "item", e.id, e.places, nil
                local cache = GL.Cache()
                r.link = cache and cache[e.id] and cache[e.id].l or nil
                Place(r, hair, y, rw, UI.ROW_H)
                y = y + UI.ROW_H
                Fill(r, COL.box, 0)
                Tex(r.hl, COL.panel)
                Tex(r.top, COL.panel)
                r.top:Show()
                r.chev:Hide()
                local has = GL.Has(e.id)
                r.tick:Show()
                r.tick:SetBackdropBorderColor(has and UI.UP[1] or COL.steel[1], has and UI.UP[2] or COL.steel[2],
                    has and UI.UP[3] or COL.steel[3], 1)
                r.tick.mark:SetShown(has)
                r:SetAlpha(has and 0.5 or 1)
                r.name:SetFont(NS.AT.FONT, 13, "")
                r.name:ClearAllPoints()
                r.name:SetPoint("LEFT", UI.INDENT + 16 + 10, 0)
                r.name:SetWidth(nameW)
                r.name:SetText(e.name or "")
                local q = QC[e.q or 1] or { r = 1, g = 1, b = 1 }
                r.name:SetTextColor(q.r, q.g, q.b)
                r.slot:ClearAllPoints()
                r.slot:SetPoint("RIGHT", -(right + 10 + UI.WHERE_W + 10), 0)
                r.slot:SetWidth(UI.SLOT_W)
                r.slot:SetText(e.slot or "")
                r.where:ClearAllPoints()
                r.where:SetPoint("RIGHT", -(right + 10), 0)
                r.where:SetWidth(UI.WHERE_W)
                r.where:SetText(where)
                r.count:SetText("")
                r.gain:SetFont(NS.AT.FONT, 13, "")
                r.gain:ClearAllPoints()
                r.gain:SetPoint("RIGHT", -UI.PAD, 0)
                r.gain:SetWidth(UI.GAIN_W)
                r.gain:SetText(UI.GainText(e.gain.d, scale))
            end
            if g.blocks then
                for _, b in ipairs(g.blocks) do
                    local s = Rows()
                    s.kind, s.id, s.places, s.link = "sub", nil, nil, nil
                    Place(s, hair, y, rw, UI.SUB_H)
                    y = y + UI.SUB_H
                    Fill(s, COL.well)
                    Tex(s.hl, COL.well)
                    Tex(s.top, COL.line)
                    s.top:Show()
                    s:SetAlpha(1)
                    s.chev:Hide()
                    s.tick:Hide()
                    s.name:SetFont(NS.AT.FONT, 12, "")
                    s.name:ClearAllPoints()
                    s.name:SetPoint("LEFT", UI.INDENT, 0)
                    s.name:SetWidth(rw - UI.INDENT - 160)
                    local nm = b.bosses[1] .. (#b.bosses > 1 and string.format(Tr(" and %d more"), #b.bosses - 1) or "")
                    s.name:SetText(nm)
                    Color(s.name, b.killed and COL.faint or COL.dim)
                    s.slot:SetText("")
                    s.where:SetText("")
                    s.count:ClearAllPoints()
                    s.count:SetPoint("RIGHT", -UI.PAD, 0)
                    Color(s.count, COL.faint)
                    s.count:SetText(b.killed and Tr("killed") or (#b.bosses > 1 and Tr("one loot table") or ""))
                    s.gain:SetText("")
                    for _, e in ipairs(b.entries) do Item(e, UI.WhereText(g, e, b)) end
                end
            else
                for _, e in ipairs(g.list) do Item(e, UI.WhereText(g, e)) end
            end
        end
        y = y + hair
        Place(box, 0, top, cw, y - top)
        y = y + UI.GAP
    end
    for i = used + 1, #UI.rows do UI.rows[i]:Hide() end
    for i = boxes + 1, #UI.boxes do UI.boxes[i]:Hide() end
    UI.content:SetSize(cw, math.max(1, y))
    UI.host:UpdateScroll()
end

function UI.Open()
    UI.Build():Show()
end

function UI.Toggle()
    local w = UI.Build()
    w:SetShown(not w:IsShown())
end
