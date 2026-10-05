-- AD_Home: the window's front page. Your own setup on the left (who you are
-- playing, what loads here, your layouts and what each holds) beside what
-- changed on the right (layout pack updates, the release notes), then the
-- Spotlight packs. UI\AD_Options.lua owns the pane and the sidebar's Home row: it
-- calls Fill once as the window builds, Refresh whenever the page shows,
-- MakeHouse and PaintRailDot for the Home row and OnOpen as the window opens.
-- The sidebar's update tag on a layout row is made and painted here too.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT = NS.AT
local COL = AT.COL
local Store = NS.Store

local HM = { cards = {}, others = {}, ups = {}, packs = {}, gen = 0 }
Options.Home = HM

-- a layout that loads here: the Modules cards' ON green
HM.ON = { 0.35, 0.85, 0.45 }
HM.GAP, HM.HEAD_H = 10, 24
HM.HERO_H, HM.TILE_H, HM.TILE_MIN = 58, 60, 150
-- My Layouts sits beside Updates and What's New from this width, taking
-- LEFT_SHARE of it; narrower, the two stack
HM.TWO_COL, HM.LEFT_SHARE, HM.COL_GAP = 620, 0.55, 18
-- a layout card: the picture gives way to Edit, Export and the eye button,
-- then the eye button drops its words
HM.EDIT_W, HM.EXPORT_W, HM.EYE_ICON_W = 56, 62, 30
HM.CARD_MIN_H = 126
HM.PREV_MIN, HM.PREV_MAX = 120, 172
-- a collection row shows its load conditions from TAG_MIN wide
HM.ROW_H, HM.ROW_MIN, HM.ROW_GAP, HM.TAG_MIN = 30, 180, 6, 260
HM.CALM_H = 36
HM.PACK_H, HM.PACK_MIN, HM.IMG_W, HM.IMG_H = 88, 300, 128, 64
-- a maker's card: its picture, a class crest per pack, the legend from LEGEND_W
HM.MAKER_IMG_W, HM.MAKER_IMG_H = 192, 96
HM.CREST, HM.CREST_W, HM.CREST_H, HM.LEGEND_W = 30, 54, 50, 210
HM.CLASS_ART = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- What's New: the first NOTES_MAX items, each line cut at NOTES_LINES
HM.NOTES_MAX, HM.NOTES_LINES = 4, 2
HM.TILES = { "loaded", "showing", "hidden", "updates" }

-- Small helpers

function HM.Text(parent, size, col)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetJustifyH("LEFT")
    local c = col or COL.ink
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

function HM.Color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

function HM.Width(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    if type(w) ~= "number" or w <= 0 then w = #(fs:GetText() or "") * 6 end
    return w
end

-- the page's buttons are a size up from the editor's
function HM.Big(b, w)
    b:SetHeight(26)
    if w then b:SetWidth(w) end
    b.fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    return b
end

-- the width a page row's content may use: rows sit 2 inside the page and
-- their content 12 in from each side
function HM.Usable(pg)
    local w = pg:GetWidth() or 0
    if w < 60 then
        pg._sizeUnresolved = true
        return nil
    end
    return math.floor(w - 28)
end

-- A word in a small box: outlined in its colour, or filled with dark letters.
-- Set returns the width it took.
function HM.MakeChip(parent, size)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetHeight(size + 7)
    AT.Skin(c, { 0, 0, 0, 0 }, COL.line)
    c.fs = HM.Text(c, size)
    c.fs:SetPoint("CENTER", 0, 0)
    function c:Set(text, col, filled)
        self.fs:SetText(text)
        if filled then
            self:SetBackdropColor(col[1], col[2], col[3], 1)
            HM.Color(self.fs, COL.bg)
        else
            self:SetBackdropColor(0, 0, 0, 0)
            HM.Color(self.fs, col)
        end
        self:SetBackdropBorderColor(col[1], col[2], col[3], 1)
        local w = math.ceil(HM.Width(self.fs)) + 12
        self:SetWidth(w)
        return w
    end
    return c
end

-- A line of text in the accent that lights up under the mouse.
function HM.MakeLink(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.fs = HM.Text(b, 12, COL.arc)
    b.fs:SetPoint("LEFT", 0, 0)
    b.fs:SetText(text)
    b:SetSize(math.ceil(HM.Width(b.fs)) + 2, 18)
    b:SetScript("OnEnter", function() HM.Color(b.fs, COL.ink) end)
    b:SetScript("OnLeave", function() HM.Color(b.fs, COL.arc) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A section title in the accent with a hairline running on to the right, and
-- a link at the far right when one is given. The caller sets the width.
function HM.MakeHead(parent, text, linkText, onLink)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(HM.HEAD_H)
    h.title = HM.Text(h, 11, COL.arc)
    h.title:SetPoint("LEFT", 2, 0)
    h.title:SetText(string.upper(text))
    if linkText then
        h.link = HM.MakeLink(h, linkText, onLink)
        h.link:SetPoint("RIGHT", 0, 0)
    end
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    h.rule:SetHeight(AT.Hairline(h))
    h.rule:SetPoint("LEFT", h.title, "RIGHT", 10, 0)
    if h.link then
        h.rule:SetPoint("RIGHT", h.link, "LEFT", -12, 0)
    else
        h.rule:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    end
    return h
end

-- What there is

-- Your layouts split by whether they load on this character, and in the ones
-- that do, the sidebar's items (groups, bars, free icons) that load and don't.
function HM.Census()
    local c = { loaded = {}, others = {}, showing = 0, hidden = 0, total = 0 }
    for _, lay in ipairs(Store.Layouts()) do
        c.total = c.total + 1
        if Store.IsLoaded(lay) then
            c.loaded[#c.loaded + 1] = lay
            for _, m in ipairs(Store.MembersOf(lay)) do
                if Store.IsLoaded(m) then c.showing = c.showing + 1 else c.hidden = c.hidden + 1 end
            end
        else
            c.others[#c.others + 1] = lay
        end
    end
    return c
end

-- "3 groups, 5 bars, 12 icons": what a layout holds, the icons in its groups too.
function HM.Contents(lay)
    local groups, free, bars = Store.ChildrenOf(lay)
    local icons = #free
    for _, g in ipairs(groups) do icons = icons + #Store.IconsOf(g) end
    local parts = {}
    local function Add(n, one, many)
        if n > 0 then parts[#parts + 1] = n .. " " .. (n == 1 and one or many) end
    end
    Add(#groups, "group", "groups")
    Add(#bars, "bar", "bars")
    Add(icons, "icon", "icons")
    if #parts == 0 then return "Nothing in it yet" end
    return table.concat(parts, ", ")
end

-- the items of a layout that loads here which do not load here
function HM.HiddenIn(lay)
    local n = 0
    for _, m in ipairs(Store.MembersOf(lay)) do
        if not Store.IsLoaded(m) then n = n + 1 end
    end
    return n
end

-- "Arc Slice" and "Hunter, level 30"; a secret or missing answer is left out
function HM.Who()
    local function Plain(v)
        if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
        return v
    end
    local name = Plain(UnitName("player"))
    local cls = Plain(UnitClass("player"))
    local lvl = Plain(UnitLevel("player"))
    local line = cls or ""
    if type(lvl) == "number" and lvl > 0 then
        line = (line ~= "" and (line .. ", ") or "") .. "level " .. lvl
    end
    return name, line
end

-- A layout's classes as name and class colour, when it names one to three;
-- nil when it loads for any class or names more.
function HM.Classes(lay)
    local set = lay.c and lay.c.classes
    if not set then return nil end
    local list = {}
    for tag in pairs(set) do
        local nm = tag
        for _, cls in ipairs(Store.ClassSpecMatrix()) do
            if cls.tag == tag then nm = cls.name end
        end
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
        list[#list + 1] = { name = nm, col = cc and { cc.r, cc.g, cc.b } or COL.dim }
    end
    if #list == 0 or #list > 3 then return nil end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Layout pack updates (UI\AD_Spotlight.lua): every layout with an older copy,
-- and the ones still waiting on Home (Later puts one off).
function HM.Updates()
    local SP = NS.Spotlight
    return (SP and SP.Updates) and SP.Updates() or {}
end

function HM.Pending()
    local SP = NS.Spotlight
    return (SP and SP.Pending) and SP.Pending() or {}
end

-- layout id -> its pack, while that layout's copy is older
function HM.UpdateByLayout()
    local map = {}
    for _, up in ipairs(HM.Updates()) do map[up.layoutId] = up.e end
    return map
end

function HM.HasNews() return #HM.Pending() > 0 end

function HM.Read()
    local upd = {}
    for _, up in ipairs(HM.Updates()) do upd[up.layoutId] = up.e end
    return { census = HM.Census(), pending = HM.Pending(), upd = upd }
end

-- A layout's picture

-- A stage whose textures are reused on every redraw: the picture code draws on
-- whatever CreateTexture hands it, so the stage hands back its spent ones
-- before it makes more (frames and textures are never destroyed).
function HM.PoolStage(parent, w, h)
    local st = CreateFrame("Frame", nil, parent)
    st:SetSize(w, h)
    st._pool, st._used = {}, 0
    local make = st.CreateTexture
    function st:CreateTexture(name, layer, tmpl, sub)
        self._used = self._used + 1
        local t = self._pool[self._used]
        if not t then
            t = make(self, name, layer, tmpl, sub)
            self._pool[self._used] = t
        else
            t:SetDrawLayer(layer or "ARTWORK", sub or 0)
            t:SetTexture(nil)
            t:SetTexCoord(0, 1, 0, 1)
            t:SetVertexColor(1, 1, 1, 1)
            t:ClearAllPoints()
        end
        t:Show()
        return t
    end
    function st:Reset()
        for i = 1, #self._pool do self._pool[i]:Hide() end
        self._used = 0
    end
    return st
end

-- what a card draws: the layout and the items of it that load here
function HM.LiveRecords(lay)
    local recs = { lay }
    for _, m in ipairs(Store.MembersOf(lay)) do
        if Store.IsLoaded(m) then
            recs[#recs + 1] = m
            if m.type == "group" then
                for _, ic in ipairs(Store.IconsOf(m)) do recs[#recs + 1] = ic end
            end
        end
    end
    return recs
end

-- Redrawn when the card shows another layout, at another size, or anything
-- was edited since.
function HM.DrawPreview(c, lay, pw, ph)
    if c._layId == lay.id and c._gen == HM.gen and c._pw == pw then return end
    c._layId, c._gen, c._pw = lay.id, HM.gen, pw
    c.stage:SetSize(pw - 8, ph - 8)
    c.stage:Reset()
    local LP = NS.LayoutPreview
    local ok = LP ~= nil and LP.PartsOf ~= nil
        and LP.DrawParts(c.stage, LP.PartsOf(HM.LiveRecords(lay)), pw - 8, ph - 8)
    c.empty:SetShown(not ok)
end

-- My Layouts: a card for each layout that loads here

function HM.EyeText(lay)
    if Store.EditHidden(lay) then return "Hidden while editing" end
    return "Shown while editing"
end

function HM.MakeCard(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(c, COL.box, COL.line)
    c.box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    c.box:SetPoint("TOPLEFT", 12, -12)
    AT.Skin(c.box, COL.well, COL.line)
    c.stage = HM.PoolStage(c.box, HM.PREV_MAX - 8, HM.PREV_MAX - 8)
    c.stage:SetPoint("CENTER")
    c.empty = HM.Text(c.box, 10, COL.faint)
    c.empty:SetPoint("CENTER")
    c.empty:SetText("Nothing shows yet")
    c.name = HM.Text(c, 16)
    c.name:SetPoint("TOPLEFT", c.box, "TOPRIGHT", 16, -1)
    c.name:SetWordWrap(false)
    c.chips = {}
    c.dot = c:CreateTexture(nil, "ARTWORK")
    c.dot:SetSize(7, 7)
    c.dot:SetPoint("TOPLEFT", c.box, "TOPRIGHT", 16, -28)
    c.dot:SetColorTexture(HM.ON[1], HM.ON[2], HM.ON[3], 1)
    local MOD = Options.Modules
    if MOD and MOD.Round then MOD.Round(c, c.dot) end
    c.state = HM.Text(c, 12, HM.ON)
    c.state:SetPoint("LEFT", c.dot, "RIGHT", 7, 0)
    c.state:SetText("Loaded on this character")
    c.what = HM.Text(c, 12, COL.dim)
    c.what:SetPoint("TOPLEFT", c.box, "TOPRIGHT", 16, -44)
    c.what:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.what:SetJustifyV("TOP")
    c.what:SetWordWrap(true)
    c.what:SetHeight(30)
    c.edit = HM.Big(AT.MakeSmallButton(c, "Edit", HM.EDIT_W))
    HM.Color(c.edit.fs, COL.arc)
    c.edit:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    c.edit:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    c.export = HM.Big(AT.MakeSmallButton(c, "Export", HM.EXPORT_W))
    c.export:SetPoint("LEFT", c.edit, "RIGHT", 8, 0)
    c.edit:SetScript("OnClick", function() if c._lay then Options.OpenLayout(c._lay) end end)
    c.export:SetScript("OnClick", function() if c._lay then Options.OpenExport(c._lay.id) end end)
    -- the sidebar's eye for the layout, with its state in words; the eye
    -- itself takes no mouse, the whole button clicks it
    c.eyeBtn = HM.Big(AT.MakeQuietButton(c, "", HM.EYE_ICON_W))
    c.eyeBtn:SetPoint("LEFT", c.export, "RIGHT", 8, 0)
    c.eye = Options.MakeEye(c.eyeBtn)
    c.eye:EnableMouse(false)
    c.eye:SetPoint("LEFT", 5, 0)
    c.eyeBtn.fs:ClearAllPoints()
    c.eyeBtn.fs:SetPoint("LEFT", c.eye, "RIGHT", 3, 0)
    c.eyeBtn:SetScript("OnClick", function()
        local fn = c.eye:GetScript("OnClick")
        if fn then fn(c.eye) end
    end)
    c.eyeBtn:HookScript("OnLeave", function()
        if c._lay then HM.Color(c.eyeBtn.fs, Store.EditHidden(c._lay) and COL.arc or COL.dim) end
    end)
    AT.Tooltip(c.eyeBtn, function() return c._lay and HM.EyeText(c._lay) end, function()
        if c._lay and Store.EditHidden(c._lay) then
            return "Not drawn on screen for now. Click to show it again. Closing this window shows everything again."
        end
        return "Click to hide this layout on screen while this window is open, so you can get at what sits under it. Closing the window shows it again."
    end)
    return c
end

-- the name, then a chip per class in its colour, all on the name's line
function HM.FillChips(c, lay, avail)
    local list = HM.Classes(lay) or {}
    local widths, total = {}, 0
    for i, cl in ipairs(list) do
        local chip = c.chips[i]
        if not chip then
            chip = HM.MakeChip(c, 10)
            c.chips[i] = chip
        end
        widths[i] = chip:Set(cl.name, cl.col, false)
        total = total + widths[i] + 6
        chip:Show()
    end
    for i = #list + 1, #c.chips do c.chips[i]:Hide() end
    local nameW = math.ceil(HM.Width(c.name)) + 2
    local room = avail - total - (#list > 0 and 6 or 0)
    c.name:SetWidth(math.max(40, math.min(nameW, room)))
    local prev
    for i = 1, #list do
        local chip = c.chips[i]
        chip:ClearAllPoints()
        if prev then
            chip:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            chip:SetPoint("LEFT", c.name, "RIGHT", 10, 0)
        end
        prev = chip
    end
end

-- Sizes the card to w and returns its height: the picture shrinks first,
-- then the eye button keeps only its eye, so the buttons always fit.
function HM.FillCard(c, lay, w)
    c._lay = lay
    Options.PaintEye(c.eye, lay)
    local words = HM.EyeText(lay)
    c.eyeBtn.fs:SetText(words)
    local eyeFull = 5 + 20 + 3 + math.ceil(HM.Width(c.eyeBtn.fs)) + 10
    local full = HM.EDIT_W + 8 + HM.EXPORT_W + 8 + eyeFull
    local pw = math.max(HM.PREV_MIN, math.min(HM.PREV_MAX, w - 40 - full))
    local ph = math.floor(pw * 0.65)
    local h = math.max(HM.CARD_MIN_H, ph + 24)
    c:SetSize(w, h)
    c.box:SetSize(pw, ph)
    local tx = 12 + pw + 16
    local room = w - tx - 12
    c._iconOnly = room < full
    if c._iconOnly then
        c.eyeBtn.fs:SetText("")
        c.eyeBtn:SetWidth(HM.EYE_ICON_W)
    else
        c.eyeBtn:SetWidth(eyeFull)
    end
    c._btnsW = HM.EDIT_W + 8 + HM.EXPORT_W + 8 + (c._iconOnly and HM.EYE_ICON_W or eyeFull)
    HM.Color(c.eyeBtn.fs, Store.EditHidden(lay) and COL.arc or COL.dim)
    c.name:SetText(lay.name or "Layout")
    HM.FillChips(c, lay, room)
    local what = HM.Contents(lay)
    local hid = HM.HiddenIn(lay)
    if hid > 0 then what = what .. ". " .. hid .. " not loaded here" end
    c.what:SetText(what)
    c.edit:ClearAllPoints()
    c.edit:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", tx, 12)
    HM.DrawPreview(c, lay, pw, ph)
    return h
end

-- Also in your collection: a short row for each layout that doesn't load here

function HM.MakeOther(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetHeight(HM.ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    AT.Skin(r, COL.box, COL.line)
    r.name = HM.Text(r, 12)
    r.name:SetPoint("LEFT", 12, 0)
    r.name:SetWordWrap(false)
    r.tag = HM.Text(r, 10, COL.faint)
    r.tag:SetWordWrap(false)
    r.edit = AT.MakeQuietButton(r, "Edit", 50)
    r.edit:SetPoint("RIGHT", -6, 0)
    r.upd = AT.MakeSmallButton(r, "Update", 64)
    r.upd:SetPoint("RIGHT", -6, 0)
    HM.Color(r.upd.fs, COL.arc)
    r:SetScript("OnClick", function() if r._lay then Options.OpenLayout(r._lay) end end)
    r.edit:SetScript("OnClick", function() if r._lay then Options.OpenLayout(r._lay) end end)
    r.upd:SetScript("OnClick", function() HM.Offer(r._pack) end)
    r:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    r:SetScript("OnLeave", function(s) HM.PaintOther(s) end)
    return r
end

function HM.PaintOther(r)
    local edge = r._pack and COL.arcDeep or COL.line
    r:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
end

-- w: the row's width; a narrow row drops its tag and keeps the name
function HM.FillOther(r, lay, pack, w)
    r._lay, r._pack = lay, pack
    r.name:SetText(lay.name or "Layout")
    local btn = pack and r.upd or r.edit
    r.upd:SetShown(pack ~= nil)
    r.edit:SetShown(pack == nil)
    r.tag:ClearAllPoints()
    r.tag:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    local wide = (w or HM.TAG_MIN) >= HM.TAG_MIN
    r.tag:SetShown(wide)
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", 12, 0)
    r.name:SetPoint("RIGHT", wide and r.tag or btn, "LEFT", -8, 0)
    if pack then
        r.tag:SetText("Update out")
        HM.Color(r.tag, COL.arc)
    else
        r.tag:SetText(Store.BadgeText and Store.BadgeText(lay) or "")
        HM.Color(r.tag, COL.faint)
    end
    HM.PaintOther(r)
end

-- a pack's newer string, offered on the Import page for the player's copy
function HM.Offer(e)
    local SP = NS.Spotlight
    if e and SP and SP.Offer then SP.Offer(e) end
end

-- Updates: a card for each layout pack update still waiting

function HM.MakeUpdate(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(c, COL.panel, COL.arcDeep)
    c.chip = HM.MakeChip(c, 8)
    c.chip:Set("LAYOUT PACK", COL.arc, true)
    c.chip:SetPoint("TOPLEFT", 12, -14)
    c.title = HM.Text(c, 14)
    c.title:SetPoint("LEFT", c.chip, "RIGHT", 8, 0)
    c.title:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.title:SetWordWrap(false)
    c.notes = HM.Text(c, 12, COL.dim)
    c.notes:SetPoint("TOPLEFT", 12, -38)
    c.notes:SetJustifyV("TOP")
    c.notes:SetWordWrap(true)
    c.go = HM.Big(AT.MakeSmallButton(c, "Update my copy", 126))
    c.go:SetPoint("BOTTOMLEFT", 12, 12)
    HM.Color(c.go.fs, COL.arc)
    c.later = HM.Big(AT.MakeQuietButton(c, "Later", 70))
    c.later:SetPoint("LEFT", c.go, "RIGHT", 8, 0)
    c.go:SetScript("OnClick", function() HM.Offer(c._e) end)
    c.later:SetScript("OnClick", function()
        local SP = NS.Spotlight
        if c._e and SP and SP.Later then SP.Later(c._e) end
        if Options.RefreshAll then Options.RefreshAll() end
    end)
    AT.Tooltip(c.later, "Later", "Hides this update here until the next version. The tag on the layout in the sidebar stays.")
    return c
end

-- sizes the card to w and returns its height
function HM.FillUpdate(c, up, w)
    local e = up.e
    local lay = Store.Get(up.layoutId)
    c._e = e
    c.title:SetText(e.title)
    local notes = table.concat(e.notes or {}, " ")
    local which = lay and ("Updates your layout " .. (lay.name or "") .. ". Your own sizes and positions stay.") or ""
    c.notes:SetText((notes ~= "" and (notes .. " ") or "") .. which)
    c:SetWidth(w)
    c.notes:SetWidth(w - 24)
    local h = 38 + math.ceil(c.notes:GetStringHeight() or 12) + 12 + 26 + 12
    c:SetHeight(h)
    return h
end

-- What's New: the first few items of the newest release notes, in a box

function HM.MakeNotes(parent, ver)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(box, COL.box, COL.line)
    box._items = {}
    for _, sec in ipairs(ver.sections or {}) do
        for _, it in ipairs(sec.items or {}) do
            if #box._items < HM.NOTES_MAX then
                local t = HM.Text(box, 13)
                t:SetText(it.title or "")
                t:SetWordWrap(false)
                local d = HM.Text(box, 12, COL.dim)
                d:SetJustifyV("TOP")
                d:SetWordWrap(true)
                if d.SetMaxLines then d:SetMaxLines(HM.NOTES_LINES) end
                d:SetText(it.desc or "")
                box._items[#box._items + 1] = { t = t, d = d }
            end
        end
    end
    box.all = HM.MakeLink(box, "All release notes", function()
        local CL = NS.Changelog
        if CL and CL.Show then CL.Show() end
    end)
    return box
end

-- sizes the box to w and returns its height
function HM.LayNotes(box, w)
    box:SetWidth(w)
    local y = 12
    -- a fixed height cuts a long line with an ellipsis where SetMaxLines is missing
    local cap = HM.NOTES_LINES * 15
    for _, it in ipairs(box._items) do
        it.t:ClearAllPoints()
        it.t:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -y)
        it.t:SetWidth(w - 28)
        y = y + 17
        it.d:ClearAllPoints()
        it.d:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -y)
        it.d:SetWidth(w - 28)
        it.d:SetHeight(0)
        local dh = math.min(cap, math.ceil(it.d:GetStringHeight() or 12))
        it.d:SetHeight(dh)
        y = y + dh + 10
    end
    box.all:ClearAllPoints()
    box.all:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -y)
    y = y + 18 + 10
    box:SetHeight(y)
    return y
end

-- Rows

function HM.HeroRow(pg)
    local row = AT.AddRow(pg, HM.HERO_H)
    local ie = HM.Big(AT.MakeSmallButton(row, "Import / Export", 130))
    ie:SetPoint("BOTTOMRIGHT", -12, 8)
    ie:SetScript("OnClick", function() Options.Select("ie") end)
    local new = HM.Big(AT.MakeSmallButton(row, "+ New Layout", 120))
    new:SetPoint("RIGHT", ie, "LEFT", -10, 0)
    HM.Color(new.fs, COL.arc)
    new:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    new:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    new:SetScript("OnClick", function() Options.Select("newlayout") end)
    row.hi = HM.Text(row, 22)
    row.hi:SetPoint("TOPLEFT", 12, -8)
    row.hi:SetPoint("RIGHT", new, "LEFT", -16, 0)
    row.hi:SetWordWrap(false)
    row.who = HM.Text(row, 12, COL.dim)
    row.who:SetPoint("TOPLEFT", row.hi, "BOTTOMLEFT", 0, -7)
    row.who:SetPoint("RIGHT", new, "LEFT", -16, 0)
    row.who:SetWordWrap(false)
    row._sync = function()
        local name, line = HM.Who()
        row.hi:SetText(name and ("Welcome back, " .. name) or "Welcome back")
        row.who:SetText(line)
    end
    HM.hero = row
    return row
end

function HM.MakeTile(parent)
    local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    t:SetHeight(HM.TILE_H)
    AT.Skin(t, COL.box, COL.line)
    t.label = HM.Text(t, 10, COL.faint)
    t.label:SetPoint("TOPLEFT", 14, -9)
    t.value = HM.Text(t, 17)
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -4)
    t.value:SetPoint("RIGHT", t, "RIGHT", -12, 0)
    t.value:SetWordWrap(false)
    t.sub = HM.Text(t, 11, COL.dim)
    t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
    t.sub:SetPoint("RIGHT", t, "RIGHT", -12, 0)
    t.sub:SetWordWrap(false)
    return t
end

-- a tile's caption, value and line
function HM.TileText(key, st)
    local c = st.census
    if key == "loaded" then
        local first = c.loaded[1]
        local v = first and (first.name or "Layout") or "None"
        if #c.loaded > 1 then v = v .. "  +" .. (#c.loaded - 1) end
        return "LOADED HERE", v, #c.loaded .. " of " .. c.total .. (c.total == 1 and " layout" or " layouts")
    elseif key == "showing" then
        return "SHOWING NOW", c.showing .. (c.showing == 1 and " item" or " items"), "groups, bars and icons"
    elseif key == "hidden" then
        return "NOT LOADED HERE", c.hidden .. (c.hidden == 1 and " item" or " items"),
            "not for this character"
    end
    local n, first = #st.pending, st.pending[1]
    return "UPDATES", (n == 0) and "None" or (n .. (n == 1 and " layout pack" or " layout packs")),
        first and (first.e.title .. " has an update")
        or "Everything is up to date"
end

function HM.TilesRow(pg)
    local row = AT.AddRow(pg, HM.TILE_H + 14)
    row._tiles = {}
    for i, key in ipairs(HM.TILES) do
        local t = HM.MakeTile(row)
        t._key = key
        row._tiles[i] = t
    end
    row._sync = function()
        local st = HM.state
        if not st then return end
        for _, t in ipairs(row._tiles) do
            local label, value, sub = HM.TileText(t._key, st)
            t.label:SetText(label)
            t.value:SetText(value)
            t.sub:SetText(sub)
            local hot = t._key == "updates" and #st.pending > 0
            local edge = hot and COL.arcDeep or COL.line
            t:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
            HM.Color(t.label, hot and COL.arc or COL.faint)
        end
        local usable = HM.Usable(pg)
        if not usable then return end
        local cols = 1
        if usable >= 4 * HM.TILE_MIN + 3 * HM.GAP then cols = 4
        elseif usable >= 2 * HM.TILE_MIN + HM.GAP then cols = 2 end
        local tw = math.floor((usable - (cols - 1) * HM.GAP) / cols)
        for i, t in ipairs(row._tiles) do
            local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
            t:SetWidth(tw)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", row, "TOPLEFT", 12 + col * (tw + HM.GAP), -4 - r * (HM.TILE_H + HM.GAP))
        end
        local n = math.ceil(#row._tiles / cols)
        local want = 4 + n * HM.TILE_H + (n - 1) * HM.GAP + 14
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    HM.tiles = row
    return row
end

-- My Layouts in the left column: the cards, the "also in your collection"
-- caption and rows, or a line when there are none. Returns its height.
function HM.LayLeft(row, st, w)
    local L, c = row.L, st.census
    row.headL:ClearAllPoints()
    row.headL:SetPoint("TOPLEFT", L, "TOPLEFT", 0, 0)
    row.headL:SetWidth(w)
    local y = HM.HEAD_H + 8
    for i, lay in ipairs(c.loaded) do
        local card = HM.cards[i]
        if not card then
            card = HM.MakeCard(L)
            HM.cards[i] = card
        end
        local h = HM.FillCard(card, lay, w)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", L, "TOPLEFT", 0, -y)
        card:Show()
        y = y + h + HM.GAP
    end
    for i = #c.loaded + 1, #HM.cards do HM.cards[i]:Hide() end
    row.cap:SetShown(#c.others > 0)
    if #c.others > 0 then
        if #c.loaded > 0 then y = y + 6 end
        row.cap:ClearAllPoints()
        row.cap:SetPoint("TOPLEFT", L, "TOPLEFT", 2, -y)
        y = y + 20
        local cols = (w >= 2 * HM.ROW_MIN + HM.ROW_GAP) and 2 or 1
        local ow = math.floor((w - (cols - 1) * HM.ROW_GAP) / cols)
        for i, lay in ipairs(c.others) do
            local r = HM.others[i]
            if not r then
                r = HM.MakeOther(L)
                HM.others[i] = r
            end
            r:SetWidth(ow)
            HM.FillOther(r, lay, st.upd[lay.id], ow)
            local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", L, "TOPLEFT", col * (ow + HM.ROW_GAP), -(y + line * (HM.ROW_H + HM.ROW_GAP)))
            r:Show()
        end
        y = y + math.ceil(#c.others / cols) * (HM.ROW_H + HM.ROW_GAP)
    end
    for i = #c.others + 1, #HM.others do HM.others[i]:Hide() end
    row.none:SetShown(c.total == 0)
    if c.total == 0 then
        row.none:ClearAllPoints()
        row.none:SetPoint("TOPLEFT", L, "TOPLEFT", 2, -y)
        y = y + 22
    end
    return y
end

-- Updates, then What's New, in the right column. Returns its height.
function HM.LayRight(row, st, w)
    local R = row.R
    row.headU:ClearAllPoints()
    row.headU:SetPoint("TOPLEFT", R, "TOPLEFT", 0, 0)
    row.headU:SetWidth(w)
    local y = HM.HEAD_H + 8
    for i, up in ipairs(st.pending) do
        local c = HM.ups[i]
        if not c then
            c = HM.MakeUpdate(R)
            HM.ups[i] = c
        end
        local h = HM.FillUpdate(c, up, w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
        c:Show()
        y = y + h + HM.GAP
    end
    for i = #st.pending + 1, #HM.ups do HM.ups[i]:Hide() end
    row.calm:SetShown(#st.pending == 0)
    if #st.pending == 0 then
        row.calm:SetWidth(w)
        row.calm:ClearAllPoints()
        row.calm:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
        y = y + HM.CALM_H + HM.GAP
    end
    if row.notes then
        y = y + 10
        row.headN:ClearAllPoints()
        row.headN:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
        row.headN:SetWidth(w)
        y = y + HM.HEAD_H + 8
        row.notes:ClearAllPoints()
        row.notes:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
        y = y + HM.LayNotes(row.notes, w)
    end
    return y
end

-- The page's middle: My Layouts on the left, Updates and What's New on the
-- right, or the one over the other when the page is narrow.
function HM.MainRow(pg)
    local row = AT.AddRow(pg, 200)
    row.L = CreateFrame("Frame", nil, row)
    row.R = CreateFrame("Frame", nil, row)
    row.headL = HM.MakeHead(row.L, "My Layouts")
    row.cap = HM.Text(row.L, 10, COL.faint)
    row.cap:SetText("ALSO IN YOUR COLLECTION")
    row.none = HM.Text(row.L, 12, COL.dim)
    row.none:SetText("No layouts yet. Start one with + New Layout.")
    row.headU = HM.MakeHead(row.R, "Updates")
    row.calm = CreateFrame("Frame", nil, row.R, "BackdropTemplate")
    row.calm:SetHeight(HM.CALM_H)
    AT.Skin(row.calm, COL.box, COL.line)
    row.calm.fs = HM.Text(row.calm, 12, COL.dim)
    row.calm.fs:SetPoint("LEFT", 14, 0)
    row.calm.fs:SetText("Your layouts and layout packs are up to date.")
    local CL = NS.Changelog
    local ver = CL and CL.versions and CL.versions[1]
    if ver then
        row.headN = HM.MakeHead(row.R, "What's New in " .. tostring(ver.version))
        row.notes = HM.MakeNotes(row.R, ver)
    end
    row._sync = function()
        local st = HM.state
        if not st then return end
        local usable = HM.Usable(pg)
        if not usable then return end
        local two = usable >= HM.TWO_COL
        local lw, rw = usable, usable
        if two then
            lw = math.floor((usable - HM.COL_GAP) * HM.LEFT_SHARE)
            rw = usable - HM.COL_GAP - lw
        end
        local lh = HM.LayLeft(row, st, lw)
        local rh = HM.LayRight(row, st, rw)
        row.L:ClearAllPoints()
        row.L:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -4)
        row.L:SetSize(lw, lh)
        row.R:ClearAllPoints()
        if two then
            row.R:SetPoint("TOPLEFT", row, "TOPLEFT", 12 + lw + HM.COL_GAP, -4)
        else
            row.R:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -4 - lh - 8)
        end
        row.R:SetSize(rw, rh)
        row._two = two
        local want = 4 + (two and math.max(lh, rh) or (lh + 8 + rh)) + 10
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    HM.main = row
    return row
end

-- Spotlight: the featured layout packs, a short card each (a maker's packs
-- share one), then the one that asks for yours

function HM.MakePack(parent, t)
    local NL = NS.NewLayout
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetHeight(HM.PACK_H)
    c:RegisterForClicks("LeftButtonUp")
    AT.Skin(c, COL.box, COL.line)
    -- the New Layout page's hover picture reads card.entry.src
    c.entry = { src = t }
    local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    box:SetSize(HM.IMG_W, HM.IMG_H)
    box:SetPoint("LEFT", 12, 0)
    AT.Skin(box, COL.well, COL.line)
    if NL and t.image then
        NL.DrawImage(box, t.image, HM.IMG_W - 2, HM.IMG_H - 2)
    elseif NL then
        local st = CreateFrame("Frame", nil, box)
        st:SetSize(HM.IMG_W - 6, HM.IMG_H - 6)
        st:SetPoint("CENTER")
        NL.DrawEntry(st, t, HM.IMG_W - 6, HM.IMG_H - 6, false)
    end
    c.title = HM.Text(c, 13)
    c.title:SetPoint("TOPLEFT", box, "TOPRIGHT", 12, -1)
    c.title:SetText(t.title or "")
    c.title:SetWordWrap(false)
    c.desc = HM.Text(c, 11, COL.dim)
    c.desc:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
    c.desc:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.desc:SetJustifyV("TOP")
    c.desc:SetWordWrap(true)
    c.desc:SetHeight(28)
    c.desc:SetText(t.desc or "")
    c.state = HM.Text(c, 11, COL.dim)
    c.state:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 12, 0)
    c.state:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.state:SetWordWrap(false)
    -- the maker's link at the end of the state line (UI\AD_Spotlight.lua)
    local SP = NS.Spotlight
    c.link = SP and SP.LinkButton and SP.LinkButton(c, t)
    if c.link then
        c.link:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -10, 10)
        c.state:SetPoint("RIGHT", c.link, "LEFT", -8, 0)
    end
    c:SetScript("OnEnter", function(s)
        s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        if NL then NL.ShowBig(s) end
    end)
    c:SetScript("OnLeave", function(s)
        s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        if NL then NL.HideBig() end
    end)
    c:SetScript("OnClick", function() HM.PickPack(t) end)
    return c
end

function HM.PaintPack(c)
    local t = c.entry.src
    if t.hasUpdate and t.hasUpdate() then
        c.state:SetText("A newer version is out: click to update your copy")
        HM.Color(c.state, COL.arc)
    elseif t.owned and t.owned() then
        c.state:SetText("In your collection")
        HM.Color(c.state, HM.ON)
    else
        c.state:SetText("Use this layout")
        HM.Color(c.state, COL.arc)
    end
end

-- A pack the player has with a newer version out updates their copy; one they
-- have opens the layout made from it; one they don't makes a layout from it.
function HM.PickPack(t)
    local NL, SP = NS.NewLayout, NS.Spotlight
    if NL then NL.HideBig() end
    if t.hasUpdate and t.hasUpdate() then
        t.update()
        return
    end
    if t.owned and t.owned() and SP and SP.LayoutsOf then
        local lid = SP.LayoutsOf(t.key)[1]
        local lay = lid and Store.Get(lid)
        if lay then
            Options.OpenLayout(lay)
            return
        end
    end
    local rec = t.make and t.make()
    if rec then Options.OpenLayout(rec) end
end

-- One card per maker: every pack one maker made, opened on your class (else
-- their newest), a class crest per pack to turn between them.

function HM.ClassName(tag)
    local names = LOCALIZED_CLASS_NAMES_MALE
    local n = type(names) == "table" and tag and names[tag]
    if type(n) == "string" and n ~= "" then return n end
    return tag and (tag:sub(1, 1) .. tag:sub(2):lower()) or ""
end

-- the packs in their cards: a maker's together, a pack with no maker alone
function HM.Makers(list)
    local out, byMaker = {}, {}
    for _, t in ipairs(list) do
        if t.maker and t.packClass then
            local g = byMaker[t.maker]
            if not g then
                g = {}
                byMaker[t.maker] = g
                out[#out + 1] = g
            end
            g[#g + 1] = t
        else
            out[#out + 1] = { t, single = true }
        end
    end
    return out
end

function HM.Newest(packs)
    local best, at = packs[1], -1
    for _, t in ipairs(packs) do
        local v = t.at and t.at() or 0
        if v > at then best, at = t, v end
    end
    return best
end

function HM.Dot(parent, size)
    local d = parent:CreateTexture(nil, "OVERLAY")
    d:SetSize(size, size)
    return d
end

function HM.MakeMaker(parent, packs)
    local NL, SP = NS.NewLayout, NS.Spotlight
    local first = packs[1]
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(c, COL.box, COL.line)
    c.packs, c.maker = packs, first.maker
    c.name = HM.Text(c, 15)
    c.name:SetPoint("TOPLEFT", 12, -10)
    c.name:SetText(first.maker)
    c.count = HM.Text(c, 11, COL.dim)
    c.count:SetPoint("LEFT", c.name, "RIGHT", 10, 0)
    c.count:SetText(#packs == 1 and "A layout for 1 class" or ("Layouts for %d classes"):format(#packs))
    c.link = SP and SP.LinkButton and SP.LinkButton(c, first)
    if c.link then c.link:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -10) end
    c.note = HM.Text(c, 11, COL.dim)
    c.note:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -6)
    c.note:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.note:SetWordWrap(false)
    -- the chosen pack's picture: hovered big, clicked like the button
    c.pic = CreateFrame("Button", nil, c, "BackdropTemplate")
    c.pic:SetSize(HM.MAKER_IMG_W, HM.MAKER_IMG_H)
    c.pic:RegisterForClicks("LeftButtonUp")
    AT.Skin(c.pic, COL.well, COL.line)
    c.pic.entry = { src = first }
    c.pic.stages = {}
    c.pic:SetScript("OnEnter", function(s)
        s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        if NL then NL.ShowBig(s) end
    end)
    c.pic:SetScript("OnLeave", function(s)
        s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        if NL then NL.HideBig() end
    end)
    c.pic:SetScript("OnClick", function() if c.shown then HM.PickPack(c.shown) end end)
    c.title = HM.Text(c, 14)
    c.title:SetPoint("TOPLEFT", c.pic, "TOPRIGHT", 12, -1)
    c.yours = HM.MakeChip(c, 9)
    c.yours:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
    c.desc = HM.Text(c, 11, COL.dim)
    c.desc:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -6)
    c.desc:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.desc:SetJustifyV("TOP")
    c.desc:SetWordWrap(true)
    c.desc:SetHeight(28)
    c.act = HM.Big(AT.MakeSmallButton(c, "Use this layout", 124), 124)
    c.act:SetScript("OnClick", function() if c.shown then HM.PickPack(c.shown) end end)
    c.state = HM.Text(c, 11, COL.dim)
    c.state:SetPoint("BOTTOMLEFT", c.pic, "BOTTOMRIGHT", 12, 6)
    c.state:SetPoint("RIGHT", c.act, "LEFT", -10, 0)
    c.state:SetWordWrap(false)
    c.rule = c:CreateTexture(nil, "ARTWORK")
    c.rule:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    c.rule:SetHeight(AT.Hairline(c))
    c.crests = {}
    for i, t in ipairs(packs) do
        local b = CreateFrame("Button", nil, c)
        b:SetSize(HM.CREST_W, HM.CREST_H)
        b.t = t
        b.ring = CreateFrame("Frame", nil, b, "BackdropTemplate")
        b.ring:SetSize(HM.CREST + 4, HM.CREST + 4)
        b.ring:SetPoint("TOP", 0, -2)
        AT.Skin(b.ring, { 0, 0, 0, 0 }, COL.line)
        b.art = b.ring:CreateTexture(nil, "ARTWORK")
        b.art:SetPoint("TOPLEFT", 2, -2)
        b.art:SetPoint("BOTTOMRIGHT", -2, 2)
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[t.packClass]
        if tc then
            b.art:SetTexture(HM.CLASS_ART)
            b.art:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        else
            b.art:SetColorTexture(COL.panel[1], COL.panel[2], COL.panel[3], 1)
        end
        b.label = HM.Text(b, 10, COL.faint)
        b.label:SetPoint("TOP", b.ring, "BOTTOM", 0, -3)
        b.label:SetText(HM.ClassName(t.packClass))
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        b.bar:SetHeight(2)
        b.bar:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -2)
        b.bar:SetPoint("TOPRIGHT", b.label, "BOTTOMRIGHT", 0, -2)
        b.dot = HM.Dot(b, 7)
        b.dot:SetPoint("CENTER", b.ring, "TOPRIGHT", -2, -2)
        b:SetScript("OnClick", function()
            c.sel = t
            HM.PaintMaker(c)
        end)
        AT.Tooltip(b, t.title or HM.ClassName(t.packClass), function() return HM.PackWords(t) end)
        c.crests[i] = b
    end
    -- what the crests' dots mean
    c.legend = CreateFrame("Frame", nil, c)
    c.legend:SetSize(HM.LEGEND_W, 14)
    c.legend.upText = HM.Text(c.legend, 10, COL.faint)
    c.legend.upText:SetPoint("RIGHT", 0, 0)
    c.legend.upText:SetText("Update out")
    c.legend.up = HM.Dot(c.legend, 7)
    c.legend.up:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    c.legend.up:SetPoint("RIGHT", c.legend.upText, "LEFT", -5, 0)
    c.legend.haveText = HM.Text(c.legend, 10, COL.faint)
    c.legend.haveText:SetPoint("RIGHT", c.legend.up, "LEFT", -14, 0)
    c.legend.haveText:SetText("In your collection")
    c.legend.have = HM.Dot(c.legend, 7)
    c.legend.have:SetColorTexture(HM.ON[1], HM.ON[2], HM.ON[3], 1)
    c.legend.have:SetPoint("RIGHT", c.legend.haveText, "LEFT", -5, 0)
    return c
end

-- a pack's state in words, for its crest's tooltip
function HM.PackWords(t)
    if t.hasUpdate and t.hasUpdate() then return "In your collection. An update is out." end
    if t.owned and t.owned() then return "In your collection." end
    return "Not in your collection yet."
end

-- the card's height: the note line only when your class has no pack here
function HM.MakerH(c)
    return 10 + 18 + (c.noteOn and 17 or 0) + 8 + HM.MAKER_IMG_H + 10 + 1 + 7 + HM.CREST_H + 6
end

-- Picks the pack it shows (the one clicked, else yours, else the newest) and
-- paints the card for it; w is the card's width, when known.
function HM.PaintMaker(c, w)
    local NL = NS.NewLayout
    local mine = Store.ClassTag and Store.ClassTag()
    local yours
    for _, t in ipairs(c.packs) do
        if mine and t.packClass == mine then yours = t end
    end
    local sel = c.sel
    local known = false
    for _, t in ipairs(c.packs) do
        if t == sel then known = true end
    end
    if not known then sel = yours or HM.Newest(c.packs) end
    c.shown = sel
    c.noteOn = yours == nil and mine ~= nil
    c.note:SetText(c.noteOn and ("No %s layout from %s yet, so this shows the newest."):format(HM.ClassName(mine), c.maker) or "")
    c.note:SetShown(c.noteOn)
    local picTop = 10 + 18 + (c.noteOn and 17 or 0) + 8
    c.pic:ClearAllPoints()
    c.pic:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -picTop)
    -- the button on the card's right, level with the picture's foot
    c.act:ClearAllPoints()
    c.act:SetPoint("BOTTOMRIGHT", c, "TOPRIGHT", -12, -(picTop + HM.MAKER_IMG_H))
    -- one picture stage per pack, drawn once
    for key, st in pairs(c.pic.stages) do st:SetShown(key == sel.key) end
    if not c.pic.stages[sel.key] then
        local st = CreateFrame("Frame", nil, c.pic)
        st:SetSize(HM.MAKER_IMG_W - 2, HM.MAKER_IMG_H - 2)
        st:SetPoint("CENTER")
        if NL and sel.image then
            NL.DrawImage(st, sel.image, HM.MAKER_IMG_W - 2, HM.MAKER_IMG_H - 2)
        elseif NL then
            NL.DrawEntry(st, sel, HM.MAKER_IMG_W - 6, HM.MAKER_IMG_H - 6, false)
        end
        c.pic.stages[sel.key] = st
    end
    c.pic.entry.src = sel
    c.title:SetText(HM.ClassName(sel.packClass))
    if sel == yours then
        c.yours:Set("YOUR CLASS", COL.arc, true)
        c.yours:Show()
    else
        c.yours:Hide()
    end
    c.desc:SetText(sel.desc or "")
    if sel.hasUpdate and sel.hasUpdate() then
        c.state:SetText("An update is out")
        HM.Color(c.state, COL.arc)
        c.act.fs:SetText("Update my copy")
    elseif sel.owned and sel.owned() then
        c.state:SetText("In your collection")
        HM.Color(c.state, HM.ON)
        c.act.fs:SetText("Open my copy")
    else
        c.state:SetText("Not in your collection yet")
        HM.Color(c.state, COL.dim)
        c.act.fs:SetText("Use this layout")
    end
    local ruleY = picTop + HM.MAKER_IMG_H + 10
    c.rule:ClearAllPoints()
    c.rule:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -ruleY)
    c.rule:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -ruleY)
    for i, b in ipairs(c.crests) do
        local on = b.t == sel
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + (i - 1) * (HM.CREST_W + 4), -(ruleY + 8))
        local rc = on and COL.arc or COL.line
        b.ring:SetBackdropBorderColor(rc[1], rc[2], rc[3], 1)
        b.art:SetAlpha(on and 1 or 0.6)
        HM.Color(b.label, on and COL.ink or COL.faint)
        b.bar:SetShown(on)
        local t = b.t
        if t.hasUpdate and t.hasUpdate() then
            b.dot:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            b.dot:Show()
        elseif t.owned and t.owned() then
            b.dot:SetColorTexture(HM.ON[1], HM.ON[2], HM.ON[3], 1)
            b.dot:Show()
        else
            b.dot:Hide()
        end
    end
    -- the legend where the crests leave it room
    local crestsW = 12 + #c.crests * (HM.CREST_W + 4)
    c.legend:ClearAllPoints()
    c.legend:SetPoint("RIGHT", c, "TOPRIGHT", -12, -(ruleY + 8 + HM.CREST / 2 + 2))
    c.legend:SetShown(w == nil or w - crestsW - 12 >= HM.LEGEND_W)
end

function HM.PacksRow(pg, list)
    local row = AT.AddRow(pg, HM.PACK_H + 40)
    row.head = HM.MakeHead(row, "Spotlight", "See them all in New Layout", function()
        Options.Select("newlayout")
    end)
    row._cards = {}
    for _, g in ipairs(HM.Makers(list)) do
        row._cards[#row._cards + 1] = g.single and HM.MakePack(row, g[1]) or HM.MakeMaker(row, g)
    end
    local share = CreateFrame("Frame", nil, row, "BackdropTemplate")
    share:SetHeight(HM.PACK_H)
    AT.Skin(share, COL.bg, COL.line2)
    share.title = HM.Text(share, 13)
    share.title:SetPoint("TOPLEFT", 14, -16)
    share.title:SetText("Share your layout")
    share.desc = HM.Text(share, 11, COL.dim)
    share.desc:SetPoint("TOPLEFT", share.title, "BOTTOMLEFT", 0, -6)
    share.desc:SetPoint("RIGHT", share, "RIGHT", -14, 0)
    share.desc:SetJustifyV("TOP")
    share.desc:SetWordWrap(true)
    share.desc:SetText("Made a layout others would like? Post it with a screenshot on the Arc UI Discord.")
    row._cards[#row._cards + 1] = share
    row._share = share
    row._sync = function()
        local usable = HM.Usable(pg)
        local top = 4 + HM.HEAD_H + 8
        local cols = usable and math.max(1, math.floor((usable + HM.GAP) / (HM.PACK_MIN + HM.GAP))) or 1
        local cw = usable and math.floor((usable - (cols - 1) * HM.GAP) / cols) or HM.PACK_MIN
        local function Span(c) return c.packs and math.min(cols, 2) or 1 end
        local function Width(c) return Span(c) * cw + (Span(c) - 1) * HM.GAP end
        for _, c in ipairs(row._cards) do
            if c.packs then HM.PaintMaker(c, usable and Width(c)) elseif c ~= share then HM.PaintPack(c) end
        end
        if not usable then return end
        row.head:ClearAllPoints()
        row.head:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -4)
        row.head:SetWidth(usable)
        -- cards flow into lines, each line as tall as its tallest card
        local lines, line, col = {}, nil, 0
        for _, c in ipairs(row._cards) do
            local span = Span(c)
            if not line or col + span > cols then
                line = { h = 0 }
                lines[#lines + 1] = line
                col = 0
            end
            line[#line + 1] = { c = c, col = col }
            line.h = math.max(line.h, c.packs and HM.MakerH(c) or HM.PACK_H)
            col = col + span
        end
        local y = top
        for li, ln in ipairs(lines) do
            if li > 1 then y = y + HM.GAP end
            for _, it in ipairs(ln) do
                it.c:SetSize(Width(it.c), ln.h)
                it.c:ClearAllPoints()
                it.c:SetPoint("TOPLEFT", row, "TOPLEFT", 12 + it.col * (cw + HM.GAP), -y)
            end
            y = y + ln.h
        end
        local want = y + 16
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    HM.packsRow = row
    return row
end

-- The pane

function HM.Fill(pane, header)
    HM.pane, HM.header = pane, header
    -- the welcome line is this page's title
    header:Hide()
    local pg = AT.NewPage(pane)
    AT.MakeScrollable(pg)
    -- the window's darkest fill, so the cards on it stand out
    pg._bg:SetVertexColor(COL.bg[1], COL.bg[2], COL.bg[3], 1)
    pg:SetPoint("TOPLEFT", 0, 0)
    pg:SetPoint("BOTTOMRIGHT", 0, 0)
    pg:Show()
    HM.pg = pg
    HM.state = HM.Read()
    HM.HeroRow(pg)
    HM.TilesRow(pg)
    HM.MainRow(pg)
    local NL = NS.NewLayout
    if NL and NL.SPOTLIGHT and #NL.SPOTLIGHT > 0 then HM.PacksRow(pg, NL.SPOTLIGHT) end
    -- an edit anywhere redraws the layout pictures the next time Home shows
    if NS.Events and NS.Events.OnMessage then
        NS.Events.OnMessage("AD_DIRTY", "adhome", function() HM.gen = HM.gen + 1 end)
    end
    AT.LayoutPage(pg)
end

function HM.Refresh()
    if not HM.pg then return end
    HM.state = HM.Read()
    AT.LayoutPage(HM.pg)
    if HM.railRow then HM.PaintRailDot(HM.railRow) end
end

-- The window opens on Home once for every layout pack version the player has
-- not been shown yet; otherwise it opens where it was.
function HM.OnOpen()
    local SP = NS.Spotlight
    if SP and SP.TakeUnseen and SP.TakeUnseen() then Options.Select("home") end
end

-- The sidebar

-- The Home row's house, drawn from bars like the theme's chevrons: two for the
-- roof, two walls, a floor and a filled door. :SetColor(c) tints it.
function HM.MakeHouse(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(14, 14)
    f._bars = {}
    local function Bar(w, h, x, y, deg)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(AT.WHITE)
        t:SetSize(w, h)
        t:SetPoint("CENTER", x, y)
        if deg then t:SetRotation(math.rad(deg)) end
        f._bars[#f._bars + 1] = t
    end
    Bar(9, 1.5, -3, 2.5, 45)
    Bar(9, 1.5, 3, 2.5, -45)
    Bar(1.5, 7, -4.5, -2.5)
    Bar(1.5, 7, 4.5, -2.5)
    Bar(10.5, 1.5, 0, -6)
    Bar(2.5, 4, 0, -4)
    function f:SetColor(c)
        for _, t in ipairs(self._bars) do t:SetVertexColor(c[1], c[2], c[3], 1) end
    end
    f:SetColor(COL.ink)
    return f
end

-- A round cyan dot at the Home row's right while a layout pack update waits.
function HM.PaintRailDot(row)
    if not row then return end
    HM.railRow = row
    if not row._adDot then
        local dot = row:CreateTexture(nil, "OVERLAY")
        dot:SetSize(6, 6)
        dot:SetPoint("RIGHT", -10, 0)
        dot:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        local halo = row:CreateTexture(nil, "ARTWORK")
        halo:SetSize(12, 12)
        halo:SetPoint("CENTER", dot, "CENTER", 0, 0)
        halo:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.18)
        local MOD = Options.Modules
        if MOD and MOD.Round then
            MOD.Round(row, dot)
            MOD.Round(row, halo)
        end
        row._adDot, row._adHalo = dot, halo
        AT.Tooltip(row, "Home", function()
            if HM.HasNews() then return "A layout pack you use has a newer version." end
            return "Your layouts, what changed and the Spotlight."
        end)
    end
    local on = HM.HasNews()
    row._adDot:SetShown(on)
    row._adHalo:SetShown(on)
end

-- The tag on a layout's sidebar row while a newer version of the pack it came
-- from is out: an up arrow and "Update", in the accent. A click offers it.
function HM.MakeRailTag(row)
    local b = CreateFrame("Button", nil, row, "BackdropTemplate")
    b:SetHeight(14)
    AT.Skin(b, { 0, 0, 0, 0 }, COL.arcDeep)
    b:SetFrameLevel(row:GetFrameLevel() + 3)
    b.chev = AT.MakeChevron(b)
    b.chev:SetDir("up")
    b.chev:SetColor(COL.arc)
    b.chev:SetPoint("LEFT", 3, 0)
    b.fs = HM.Text(b, 9, COL.arc)
    b.fs:SetPoint("LEFT", b.chev, "RIGHT", 2, 0)
    b:SetScript("OnClick", function() HM.Offer(b._e) end)
    b:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1) end)
    AT.Tooltip(b, "Update available", function()
        local e = b._e
        if not e then return nil end
        return e.title .. " has an update. Click to update this layout; your own sizes and positions stay."
    end)
    return b
end

function HM.PaintRailTag(b, e)
    b._e = e
    b.fs:SetText("Update")
    local w = (b.fs.GetUnboundedStringWidth and b.fs:GetUnboundedStringWidth()) or b.fs:GetStringWidth() or 0
    if type(w) ~= "number" or w <= 0 then w = 12 end
    b:SetWidth(math.ceil(w) + 18)
end
