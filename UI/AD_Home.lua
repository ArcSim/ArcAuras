-- AD_Home: the window's front page. A main column with your own setup (who
-- you are playing, what loads here, your layouts) and the Spotlight packs,
-- beside a rail with what changed (layout pack updates one at a time, the
-- release notes); a narrow page stacks the rail under the main column.
-- UI\AD_Options.lua owns the pane and the sidebar's Home row: it calls Fill
-- once as the window builds, Refresh whenever the page shows, MakeHouse and
-- PaintRailDot for the Home row and OnOpen as the window opens. The sidebar's
-- update tag on a layout row is made and painted here too.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT = NS.AT
local COL = AT.COL
local Store = NS.Store

local HM = { cards = {}, others = {}, gen = 0 }
Options.Home = HM

-- a layout that loads here: the Modules cards' ON green
HM.ON = { 0.35, 0.85, 0.45 }
HM.GAP, HM.HEAD_H = 10, 24
-- a heading's chevron: the theme's, 12 square, its title CHEV_GAP to its right
HM.CHEV, HM.CHEV_GAP = 12, 6
HM.HERO_H, HM.TILE_H, HM.TILE_MIN = 58, 60, 150
-- a tile's words start 14 in and stop 12 short of its right edge
HM.TILE_PAD = 26
-- the rail keeps RAIL_W beside a main column of at least MAIN_MIN; a
-- narrower page stacks the rail under the main column
HM.RAIL_W, HM.MAIN_MIN, HM.COL_GAP = 340, 340, 18
HM.TWO_COL = HM.MAIN_MIN + HM.COL_GAP + HM.RAIL_W
-- before a column's second section, and between stacked columns
HM.SEC_GAP = 14
-- a layout card: the picture gives way to Edit, Export and the eye button,
-- then the eye button drops its words
HM.EDIT_W, HM.EXPORT_W, HM.EYE_ICON_W = 56, 62, 30
HM.CARD_MIN_H = 126
HM.PREV_MIN, HM.PREV_MAX = 120, 172
-- a collection row shows its load conditions from TAG_MIN wide
HM.ROW_H, HM.ROW_MIN, HM.ROW_GAP, HM.TAG_MIN = 30, 180, 6, 260
HM.CALM_H = 36
HM.PACK_H, HM.IMG_W, HM.IMG_H = 88, 128, 64
-- a maker's card: its picture gives way from MAKER_IMG_W to MAKER_IMG_MIN
-- wide (always 2:1), a class crest per pack, the share strip at its foot
HM.MAKER_IMG_W, HM.MAKER_IMG_MIN = 256, 128
HM.CREST, HM.CREST_W, HM.CREST_H = 30, 54, 50
HM.STRIP_H = 36
HM.CLASS_ART = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- the rail's update card: the pack's picture, a dot per waiting update
HM.UPD_IMG_W, HM.UPD_IMG_H, HM.DOT, HM.DOT_PITCH = 112, 56, 8, 12
-- Update all asks for a second press within ARM_S seconds
HM.ARM_S = 4
-- What's New: the first NOTES_MAX items, each cut at NOTES_LINES lines
HM.NOTES_MAX, HM.NOTES_LINES = 5, 2
HM.TILES = { "loaded", "showing", "hidden", "updates" }

-- Small helpers

function HM.Text(parent, size, col)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
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
    b.fs:SetFont(AT.FONT, 12, "")
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

-- a button as wide as its words need, never under minW
function HM.Fit(b, minW)
    local w = math.max(minW or 0, math.ceil(HM.Width(b.fs)) + 20)
    b:SetWidth(w)
    return w
end

-- a lead button: its words and its border in the lead colours (the accent in
-- the classic palette), the border kept when the mouse leaves
function HM.Arc(b)
    HM.Color(b.fs, COL.lead)
    b:SetBackdropBorderColor(COL.leadEdge[1], COL.leadEdge[2], COL.leadEdge[3], 1)
    b:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.leadEdge[1], COL.leadEdge[2], COL.leadEdge[3], 1) end)
    return b
end

-- Lets a text wrap at w and returns its height, so nothing in it is cut.
function HM.Wrap(fs, w)
    fs:SetWidth(w)
    fs:SetWordWrap(true)
    return math.ceil(fs:GetStringHeight() or 12)
end

-- a colour as the hex digits a |c code takes
function HM.Hex(c)
    return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
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
-- a link at the far right when one is given. The caller sets the width. The
-- title and its rule are one click target that folds the section `key`, the
-- theme's chevron at the title's left; the link keeps its own click.
function HM.MakeHead(parent, text, linkText, onLink, key)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(HM.HEAD_H)
    h._key = key
    local top = math.floor((HM.HEAD_H - HM.CHEV) / 2)
    h.chev = AT.MakeChevron(h)
    h.chev:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -top)
    h.title = HM.Text(h, 11, COL.title)
    h.title:SetPoint("LEFT", h.chev, "RIGHT", HM.CHEV_GAP, 0)
    h.title:SetText(string.upper(text))
    if linkText then
        h.link = HM.MakeLink(h, linkText, onLink)
        h.link:SetPoint("RIGHT", 0, 0)
    end
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetColorTexture(COL.hair[1], COL.hair[2], COL.hair[3], 1)
    h.rule:SetHeight(AT.Hairline(h))
    h.rule:SetPoint("LEFT", h.title, "RIGHT", 10, 0)
    if h.link then
        h.rule:SetPoint("RIGHT", h.link, "LEFT", -12, 0)
    else
        h.rule:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    end
    -- the target ends where the rule does, so the link (or the Updates pager)
    -- past it never folds anything; the rule's right end sits mid-heading
    h.hit = CreateFrame("Button", nil, h)
    h.hit:SetHeight(HM.HEAD_H)
    h.hit:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.hit:SetPoint("TOPRIGHT", h.rule, "RIGHT", 0, top + HM.CHEV / 2)
    h.hit:RegisterForClicks("LeftButtonUp")
    h.hit:SetScript("OnEnter", function()
        h._hot = true
        HM.PaintHead(h)
    end)
    h.hit:SetScript("OnLeave", function()
        h._hot = nil
        HM.PaintHead(h)
    end)
    h.hit:SetScript("OnClick", function() HM.Toggle(key) end)
    HM.PaintHead(h)
    return h
end

-- The Home sections the player folded, kept for the account in the window's
-- store (Store.UI().homeShut[key]); every one is open until its heading is
-- clicked.
function HM.Shut(key)
    local u = Store.UI and Store.UI()
    return key ~= nil and u ~= nil and u.homeShut ~= nil and u.homeShut[key] == true
end

-- A heading's click folds or opens its section; the page lays itself out again
-- so what follows moves up or back down.
function HM.Toggle(key)
    local u = Store.UI and Store.UI()
    if not (key and u) then return end
    local set = u.homeShut or {}
    local shut = not set[key]
    set[key] = shut or nil
    u.homeShut = next(set) and set or nil
    AT.CloseDropdown()
    PlaySound(shut and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
    HM.Refresh()
end

-- Open, the chevron points down; folded, right. Under the mouse the title and
-- the chevron brighten to the text colour, as the theme's folding sections do.
function HM.PaintHead(h)
    HM.Color(h.title, h._hot and COL.ink or COL.title)
    h.chev:SetColor(h._hot and COL.ink or COL.chev)
    h.chev:SetDown(not HM.Shut(h._key))
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

-- all: every update out, the ones put off with Later too
function HM.Read()
    return { census = HM.Census(), pending = HM.Pending(), all = HM.Updates() }
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
    HM.Color(c.edit.fs, COL.lead)
    c.edit:SetBackdropBorderColor(COL.leadEdge[1], COL.leadEdge[2], COL.leadEdge[3], 1)
    c.edit:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.leadEdge[1], COL.leadEdge[2], COL.leadEdge[3], 1) end)
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
    -- two lines fill the row's height
    if r.name.SetMaxLines then r.name:SetMaxLines(2) end
    r.tag = HM.Text(r, 10, COL.faint)
    r.tag:SetWordWrap(false)
    -- Edit only: a pack update is offered in the rail and on the sidebar row
    r.edit = AT.MakeSmallButton(r, "Edit", 50)
    HM.Fit(r.edit, 50)
    r.edit:SetPoint("RIGHT", -6, 0)
    r.tag:SetPoint("RIGHT", r.edit, "LEFT", -8, 0)
    r:SetScript("OnClick", function() if r._lay then Options.OpenLayout(r._lay) end end)
    r.edit:SetScript("OnClick", function() if r._lay then Options.OpenLayout(r._lay) end end)
    r:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    r:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
    return r
end

-- the room a row w wide leaves its name, with its tag beside it or without
function HM.NameRoom(r, w, tagged)
    local room = w - 12 - 8 - r.edit:GetWidth() - 6
    if tagged then room = room - math.ceil(HM.Width(r.tag)) - 8 end
    return room
end

-- w: the row's width. The tag shows only on a row TAG_MIN wide whose name
-- still fits beside it; a name too long for its line takes a second one.
function HM.FillOther(r, lay, w)
    r._lay = lay
    r.name:SetText(lay.name or "Layout")
    r.tag:SetText(Store.BadgeText and Store.BadgeText(lay) or "")
    local nameW = math.ceil(HM.Width(r.name))
    local wide = w >= HM.TAG_MIN and (r.tag:GetText() or "") ~= "" and nameW <= HM.NameRoom(r, w, true)
    r.tag:SetShown(wide)
    local room = math.max(20, HM.NameRoom(r, w, wide))
    r.name:SetWidth(room)
    r.name:SetWordWrap(nameW > room)
end

-- a pack's newer string, offered on the Import page for the player's copy
function HM.Offer(e)
    local SP = NS.Spotlight
    if e and SP and SP.Offer then SP.Offer(e) end
end

-- Later: off Home until the pack's next version; the sidebar tag stays
function HM.PutOff(e)
    local SP = NS.Spotlight
    if e and SP and SP.Later then SP.Later(e) end
    if Options.RefreshAll then Options.RefreshAll() end
end

-- Updates: the waiting ones one at a time in a card, paged from the heading

-- A pack's picture in `pic`: a stage per pack, drawn once at w x h. Returns
-- the stage it shows.
function HM.ShowPicture(pic, t, w, h)
    local NL = NS.NewLayout
    for key, st in pairs(pic.stages) do st:SetShown(key == t.key) end
    local st = pic.stages[t.key]
    if not st then
        st = CreateFrame("Frame", nil, pic)
        st:SetSize(w - 2, h - 2)
        st:SetPoint("CENTER")
        if NL and t.image then
            NL.DrawImage(st, t.image, w - 2, h - 2)
        elseif NL then
            NL.DrawEntry(st, t, w - 6, h - 6, false)
        end
        pic.stages[t.key] = st
    end
    st:Show()
    return st
end

-- An arrow button for the heading; at either end it rests dimmed, takes no
-- click and keeps its border under the mouse.
function HM.MakeArrow(parent, dir)
    local b = AT.MakeSmallButton(parent, "", 22)
    b.chev = AT.MakeChevron(b)
    b.chev:SetDir(dir)
    b.chev:SetColor(COL.ink)
    b.chev:SetPoint("CENTER", 0, 0)
    b:HookScript("OnEnter", function(s)
        if s._off then
            s:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
            s:SetBackdropBorderColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
        end
    end)
    return b
end

function HM.PaintArrow(b, off)
    b._off = off
    b:SetAlpha(off and 0.35 or 1)
    if b.SetEnabled then b:SetEnabled(not off) end
end

-- the card turns to the i-th waiting update (HM.updIndex lasts the session)
function HM.GoUpdate(i)
    HM.updIndex = i
    HM.Refresh()
end

function HM.StepUpdate(d)
    local n = HM.state and #HM.state.pending or 0
    local i = (HM.updIndex or 1) + d
    if i >= 1 and i <= n then HM.GoUpdate(i) end
end

-- a round dot for one waiting update; a click turns the card to it
function HM.MakeDot(parent)
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(HM.DOT_PITCH, HM.DOT_PITCH)
    d.tex = d:CreateTexture(nil, "ARTWORK")
    d.tex:SetTexture(AT.WHITE)
    d.tex:SetSize(HM.DOT, HM.DOT)
    d.tex:SetPoint("CENTER", 0, 0)
    local MOD = Options.Modules
    if MOD and MOD.Round then MOD.Round(d, d.tex) end
    d:SetScript("OnClick", function(s) if s._i then HM.GoUpdate(s._i) end end)
    AT.Tooltip(d, function() return d._up and d._up.e.title end, function()
        local lay = d._up and Store.Get(d._up.layoutId)
        return lay and ("Updates " .. (lay.name or "")) or nil
    end)
    return d
end

function HM.MakeUpdCard(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(c, COL.box, COL.line)
    c.pic = CreateFrame("Frame", nil, c, "BackdropTemplate")
    c.pic:SetSize(HM.UPD_IMG_W, HM.UPD_IMG_H)
    c.pic:SetPoint("TOPLEFT", 14, -12)
    AT.Skin(c.pic, COL.well, COL.line)
    c.pic.stages = {}
    c.title = HM.Text(c, 14)
    c.which = HM.Text(c, 10, COL.faint)
    c.notes = HM.Text(c, 11, COL.dim)
    c.notes:SetJustifyV("TOP")
    c.go = HM.Arc(AT.MakeSmallButton(c, "Update my copy", 100))
    HM.Fit(c.go, 100)
    c.later = AT.MakeQuietButton(c, "Later", 56)
    HM.Fit(c.later, 56)
    c.go:SetScript("OnClick", function() HM.Offer(c._e) end)
    c.later:SetScript("OnClick", function() HM.PutOff(c._e) end)
    AT.Tooltip(c.later, "Later", "Hides this update here until the next version. The tag on the layout in the sidebar stays.")
    c.dots = {}
    return c
end

-- Sizes the card to w for the i-th waiting update and returns its height.
-- The words wrap, the buttons fit their words; Later drops under Update my
-- copy when the two leave no room, and the dots take a line of their own when
-- they don't fit beside the buttons (none at all past that).
function HM.FillUpdCard(c, list, i, w)
    local up = list[i]
    local e, lay = up.e, Store.Get(up.layoutId)
    c._e = e
    c:SetWidth(w)
    HM.ShowPicture(c.pic, e, HM.UPD_IMG_W, HM.UPD_IMG_H)
    local tx = 14 + HM.UPD_IMG_W + 12
    local tw = math.max(40, w - tx - 14)
    c.title:SetText(e.title or "")
    c.which:SetText("Updates " .. ((lay and lay.name) or "your layout"))
    local th, wh = HM.Wrap(c.title, tw), HM.Wrap(c.which, tw)
    -- the title and its layout centred beside the picture
    local block = th + 3 + wh
    local top = 12 + math.max(0, math.floor((HM.UPD_IMG_H - block) / 2))
    c.title:ClearAllPoints()
    c.title:SetPoint("TOPLEFT", c, "TOPLEFT", tx, -top)
    c.which:ClearAllPoints()
    c.which:SetPoint("TOPLEFT", c, "TOPLEFT", tx, -(top + th + 3))
    local inner = w - 28
    local y = 12 + math.max(HM.UPD_IMG_H, block) + 10
    local notes = table.concat(e.notes or {}, " ")
    c.notes:SetText(notes)
    c.notes:SetShown(notes ~= "")
    if notes ~= "" then
        c.notes:ClearAllPoints()
        c.notes:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -y)
        y = y + HM.Wrap(c.notes, inner) + 10
    end
    local gw, lw = c.go:GetWidth(), c.later:GetWidth()
    c.go:ClearAllPoints()
    c.go:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -y)
    c.later:ClearAllPoints()
    local used
    if gw + 6 + lw <= inner then
        c.later:SetPoint("TOPLEFT", c, "TOPLEFT", 14 + gw + 6, -y)
        used = gw + 6 + lw
    else
        y = y + 22 + 6
        c.later:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -y)
        used = lw
    end
    local bottom = y + 22
    local n = #list
    for k = 1, n do
        local d = c.dots[k]
        if not d then
            d = HM.MakeDot(c)
            c.dots[k] = d
        end
        d._i, d._up = k, list[k]
        local col = (k == i) and COL.arc or COL.line
        d.tex:SetVertexColor(col[1], col[2], col[3], 1)
    end
    for k = n + 1, #c.dots do c.dots[k]:Hide() end
    local need = n * HM.DOT_PITCH
    local dy
    if need <= inner - used - 8 then
        dy = y + (22 - HM.DOT_PITCH) / 2
    elseif need <= inner then
        dy = bottom + 4
        bottom = dy + HM.DOT_PITCH
    end
    for k = 1, n do
        local d = c.dots[k]
        d:SetShown(dy ~= nil)
        if dy then
            d:ClearAllPoints()
            d:SetPoint("TOPLEFT", c, "TOPLEFT", w - 14 - need + (k - 1) * HM.DOT_PITCH, -dy)
        end
    end
    local h = bottom + 12
    c:SetHeight(h)
    return h
end

-- Update all is armed for ARM_S seconds by a first press
function HM.Armed()
    return HM.armAt ~= nil and GetTime() - HM.armAt <= HM.ARM_S
end

-- Every update the pager shows takes it with the default parts, so Size &
-- Position stays the player's; one put off with Later waits, as Later says. A
-- string that no longer reads, or one that matches nothing here (it would come
-- in as a second copy), is left out. Returns how many it updated.
function HM.UpdateAll()
    local n = 0
    for _, up in ipairs(HM.Pending()) do
        local plan = Store.PlanUpdate(up.e.text)
        if plan and plan.relation ~= "new" then
            Store.ApplyUpdate(plan, { targetLayoutId = up.layoutId })
            n = n + 1
        end
    end
    return n
end

-- A first press arms Update all and the caption asks for a second; a second
-- within ARM_S seconds runs it. Left alone, it disarms.
function HM.PressUpdateAll()
    if HM.Armed() then
        HM.armAt = nil
        HM.UpdateAll()
        if Options.RefreshAll then Options.RefreshAll() end
        return
    end
    local at = GetTime()
    HM.armAt = at
    C_Timer.After(HM.ARM_S, function()
        if HM.armAt == at then
            HM.armAt = nil
            HM.Refresh()
        end
    end)
    HM.Refresh()
end

-- What's New: the newest release's version, then its first items in the
-- accent with their descriptions dim, in a box

function HM.MakeNotes(parent, ver)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(box, COL.box, COL.line)
    box.ver = HM.Text(box, 11, COL.faint)
    box.ver:SetText("Version " .. tostring(ver.version))
    box._items = {}
    for _, sec in ipairs(ver.sections or {}) do
        for _, it in ipairs(sec.items or {}) do
            if #box._items < HM.NOTES_MAX then
                local t = HM.Text(box, 12, COL.title)
                local d = HM.Text(box, 11, COL.dim)
                for _, fs in ipairs({ t, d }) do
                    fs:SetJustifyV("TOP")
                    fs:SetWordWrap(true)
                    if fs.SetMaxLines then fs:SetMaxLines(HM.NOTES_LINES) end
                end
                t:SetText(it.title or "")
                d:SetText(it.desc or "")
                box._items[#box._items + 1] = { t = t, d = d }
            end
        end
    end
    return box
end

-- One line of a note at y, cut at NOTES_LINES lines of lineH; a fixed height
-- cuts it with an ellipsis where SetMaxLines is missing. Returns its height.
function HM.LayNote(box, fs, y, w, lineH)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -y)
    fs:SetWidth(w - 28)
    fs:SetHeight(0)
    local h = math.min(HM.NOTES_LINES * lineH, math.ceil(fs:GetStringHeight() or lineH))
    fs:SetHeight(h)
    return h
end

-- sizes the box to w and returns its height
function HM.LayNotes(box, w)
    box:SetWidth(w)
    box.ver:ClearAllPoints()
    box.ver:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12)
    box.ver:SetWidth(w - 28)
    local y = 12 + 14 + 8
    for _, it in ipairs(box._items) do
        y = y + HM.LayNote(box, it.t, y, w, 15) + 2
        y = y + HM.LayNote(box, it.d, y, w, 14) + 9
    end
    y = y + 3
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
    HM.Color(new.fs, COL.lead)
    new:SetBackdropBorderColor(COL.leadEdge[1], COL.leadEdge[2], COL.leadEdge[3], 1)
    new:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.leadEdge[1], COL.leadEdge[2], COL.leadEdge[3], 1) end)
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
    -- the words get the tile's width less HM.TILE_PAD in TilesRow, one line each
    t.label = HM.Text(t, 10, COL.faint)
    t.label:SetPoint("TOPLEFT", 14, -9)
    t.label:SetWordWrap(false)
    t.value = HM.Text(t, 17)
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -4)
    t.value:SetWordWrap(false)
    t.sub = HM.Text(t, 11, COL.dim)
    t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
    t.sub:SetWordWrap(false)
    return t
end

-- A tile's caption, its value's forms longest first (a narrow tile takes the
-- first that fits: the loaded layout's name gives way to a count), its line.
function HM.TileText(key, st)
    local c = st.census
    if key == "loaded" then
        local n, first = #c.loaded, c.loaded[1]
        local sub = n .. " of " .. c.total .. (c.total == 1 and " layout" or " layouts")
        if not first then return "LOADED HERE", { "None" }, sub end
        local name = first.name or "Layout"
        local forms = {}
        if n > 1 then forms[1] = name .. "  +" .. (n - 1) end
        forms[#forms + 1] = name
        forms[#forms + 1] = n .. (n == 1 and " layout" or " layouts")
        return "LOADED HERE", forms, sub
    elseif key == "showing" then
        return "SHOWING NOW", { c.showing .. (c.showing == 1 and " item" or " items") }, "groups, bars and icons"
    elseif key == "hidden" then
        return "NOT LOADED HERE", { c.hidden .. (c.hidden == 1 and " item" or " items") },
            "not for this character"
    end
    local n = #st.pending
    if n == 0 then return "UPDATES", { "None" }, "Everything is up to date" end
    return "UPDATES", { n .. (n == 1 and " layout" or " layouts") }, (n == 1) and "has an update" or "have an update"
end

-- Four tiles to a line where every tile's words fit, else two, else one, so
-- no word is ever cut.
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
            local label, forms, sub = HM.TileText(t._key, st)
            t._forms = forms
            t.label:SetText(label)
            t.sub:SetText(sub)
            -- the shortest form sets how narrow the tile may go
            t.value:SetText(forms[#forms])
            t._need = math.ceil(math.max(HM.Width(t.label), HM.Width(t.value), HM.Width(t.sub))) + HM.TILE_PAD
            local hot = t._key == "updates" and #st.pending > 0
            local edge = hot and COL.focus or COL.line
            t:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
            HM.Color(t.label, hot and COL.arc or COL.faint)
        end
        local usable = HM.Usable(pg)
        if not usable then return end
        local cols = 1
        for _, n in ipairs({ 4, 2 }) do
            local w = math.floor((usable - (n - 1) * HM.GAP) / n)
            local fits = w >= HM.TILE_MIN
            for _, t in ipairs(row._tiles) do
                if t._need > w then fits = false end
            end
            if fits then
                cols = n
                break
            end
        end
        local tw = math.floor((usable - (cols - 1) * HM.GAP) / cols)
        local inner = tw - HM.TILE_PAD
        for i, t in ipairs(row._tiles) do
            for _, form in ipairs(t._forms) do
                t.value:SetText(form)
                if HM.Width(t.value) <= inner then break end
            end
            t.label:SetWidth(inner)
            t.value:SetWidth(inner)
            t.sub:SetWidth(inner)
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

-- The main column: My Layouts (a card per layout that loads here, then the
-- "also in your collection" rows, or a line when there are none), then the
-- Spotlight. A folded section keeps its heading alone. Returns its height.
function HM.LayMain(row, st, w)
    local M, c = row.M, st.census
    row.headL:ClearAllPoints()
    row.headL:SetPoint("TOPLEFT", M, "TOPLEFT", 0, 0)
    row.headL:SetWidth(w)
    HM.PaintHead(row.headL)
    local shut = HM.Shut(row.headL._key)
    local loaded, others = c.loaded, c.others
    if shut then loaded, others = {}, {} end
    local y = HM.HEAD_H + (shut and 0 or 8)
    for i, lay in ipairs(loaded) do
        local card = HM.cards[i]
        if not card then
            card = HM.MakeCard(M)
            HM.cards[i] = card
        end
        local h = HM.FillCard(card, lay, w)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", M, "TOPLEFT", 0, -y)
        card:Show()
        y = y + h + HM.GAP
    end
    for i = #loaded + 1, #HM.cards do HM.cards[i]:Hide() end
    row.cap:SetShown(#others > 0)
    if #others > 0 then
        if #loaded > 0 then y = y + 6 end
        row.cap:ClearAllPoints()
        row.cap:SetPoint("TOPLEFT", M, "TOPLEFT", 2, -y)
        y = y + 20
        -- two to a line where the column holds two and every name fits its half
        local cols = (w >= 2 * HM.ROW_MIN + HM.ROW_GAP) and 2 or 1
        local half = math.floor((w - HM.ROW_GAP) / 2)
        for i, lay in ipairs(others) do
            local r = HM.others[i]
            if not r then
                r = HM.MakeOther(M)
                HM.others[i] = r
            end
            r.name:SetText(lay.name or "Layout")
            if math.ceil(HM.Width(r.name)) > HM.NameRoom(r, half, false) then cols = 1 end
        end
        local ow = math.floor((w - (cols - 1) * HM.ROW_GAP) / cols)
        for i, lay in ipairs(others) do
            local r = HM.others[i]
            r:SetWidth(ow)
            HM.FillOther(r, lay, ow)
            local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", M, "TOPLEFT", col * (ow + HM.ROW_GAP), -(y + line * (HM.ROW_H + HM.ROW_GAP)))
            r:Show()
        end
        y = y + math.ceil(#others / cols) * (HM.ROW_H + HM.ROW_GAP)
    end
    for i = #others + 1, #HM.others do HM.others[i]:Hide() end
    local none = c.total == 0 and not shut
    row.none:SetShown(none)
    if none then
        row.none:ClearAllPoints()
        row.none:SetPoint("TOPLEFT", M, "TOPLEFT", 2, -y)
        y = y + 22
    end
    y = y + HM.SEC_GAP
    return y + HM.LaySpot(row.spot, M, y, w)
end

-- The rail: the waiting updates one at a time (the heading pages through
-- them), or a calm box, then What's New. A folded section keeps its heading
-- alone, and folded Updates drops its pager with the card. Returns its height.
function HM.LayRail(row, st, w)
    local R, h = row.R, row.headU
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", R, "TOPLEFT", 0, 0)
    h:SetWidth(w)
    HM.PaintHead(h)
    local list = st.pending
    local n = #list
    local shut = HM.Shut(h._key)
    local some = n > 0 and not shut
    h.pos:SetShown(some)
    h.prev:SetShown(some)
    h.next:SetShown(some)
    if some then
        h.rule:SetPoint("RIGHT", h.pos, "LEFT", -10, 0)
    else
        h.rule:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    end
    row.upd:SetShown(some)
    row.capU:SetShown(some)
    row.all:SetShown(some)
    local calm = n == 0 and not shut
    row.calm:SetShown(calm)
    if n == 0 then HM.updIndex = nil end
    local y = HM.HEAD_H + (shut and 0 or 8)
    if calm then
        row.calm:SetWidth(w)
        row.calm:ClearAllPoints()
        row.calm:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
        y = y + HM.CALM_H + HM.GAP
    elseif some then
        -- a shorter list (Later, an update made) pulls the index back inside it
        local i = math.max(1, math.min(HM.updIndex or 1, n))
        HM.updIndex = i
        h.pos:SetText(i .. " of " .. n)
        HM.PaintArrow(h.prev, i <= 1)
        HM.PaintArrow(h.next, i >= n)
        local ch = HM.FillUpdCard(row.upd, list, i, w)
        row.upd:ClearAllPoints()
        row.upd:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
        y = y + ch + 8
        -- what an update keeps, or Update all asking for its second press
        local armed = HM.Armed()
        row.capU:SetText(armed and ("Press again to update all " .. #st.pending) or "Your own sizes and positions stay.")
        HM.Color(row.capU, armed and COL.arc or COL.faint)
        local capH = HM.Wrap(row.capU, math.max(40, w - 2 - row.all:GetWidth() - 10))
        local lineH = math.max(22, capH)
        row.capU:ClearAllPoints()
        row.capU:SetPoint("TOPLEFT", R, "TOPLEFT", 2, -(y + math.floor((lineH - capH) / 2)))
        row.all:ClearAllPoints()
        row.all:SetPoint("TOPRIGHT", R, "TOPRIGHT", 0, -(y + math.floor((lineH - 22) / 2)))
        y = y + lineH + HM.GAP
    end
    if row.notes then
        y = y + HM.SEC_GAP
        row.headN:ClearAllPoints()
        row.headN:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
        row.headN:SetWidth(w)
        HM.PaintHead(row.headN)
        y = y + HM.HEAD_H
        local open = not HM.Shut(row.headN._key)
        row.notes:SetShown(open)
        if open then
            y = y + 8
            row.notes:ClearAllPoints()
            row.notes:SetPoint("TOPLEFT", R, "TOPLEFT", 0, -y)
            y = y + HM.LayNotes(row.notes, w)
        end
    end
    return y
end

-- The page's body: the main column (My Layouts, the Spotlight) and the rail
-- (Updates, What's New) at its right, or under it on a narrow page.
function HM.MainRow(pg)
    local row = AT.AddRow(pg, 200)
    row.M = CreateFrame("Frame", nil, row)
    row.R = CreateFrame("Frame", nil, row)
    row.headL = HM.MakeHead(row.M, "My Layouts", nil, nil, "layouts")
    row.cap = HM.Text(row.M, 10, COL.faint)
    row.cap:SetText("ALSO IN YOUR COLLECTION")
    row.none = HM.Text(row.M, 12, COL.dim)
    row.none:SetText("No layouts yet. Start one with + New Layout.")
    local NL = NS.NewLayout
    row.spot = HM.MakeSpot(row.M, (NL and NL.SPOTLIGHT) or {})
    -- the heading pages through the waiting updates
    local h = HM.MakeHead(row.R, "Updates", nil, nil, "updates")
    h.next = HM.MakeArrow(h, "right")
    h.next:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.prev = HM.MakeArrow(h, "left")
    h.prev:SetPoint("RIGHT", h.next, "LEFT", -4, 0)
    h.pos = HM.Text(h, 11, COL.dim)
    h.pos:SetPoint("RIGHT", h.prev, "LEFT", -8, 0)
    h.prev:SetScript("OnClick", function() HM.StepUpdate(-1) end)
    h.next:SetScript("OnClick", function() HM.StepUpdate(1) end)
    row.headU = h
    row.upd = HM.MakeUpdCard(row.R)
    row.capU = HM.Text(row.R, 11, COL.faint)
    row.capU:SetJustifyV("TOP")
    row.all = AT.MakeQuietButton(row.R, "Update all", 80)
    HM.Fit(row.all, 80)
    row.all:SetScript("OnClick", function() HM.PressUpdateAll() end)
    AT.Tooltip(row.all, "Update all", "Updates every layout that has a pack update. Press twice.")
    row.calm = CreateFrame("Frame", nil, row.R, "BackdropTemplate")
    row.calm:SetHeight(HM.CALM_H)
    AT.Skin(row.calm, COL.box, COL.line)
    row.calm.mark = row.calm:CreateTexture(nil, "ARTWORK")
    row.calm.mark:SetAtlas("checkmark-minimal")
    row.calm.mark:SetDesaturated(true)
    row.calm.mark:SetVertexColor(HM.ON[1], HM.ON[2], HM.ON[3], 1)
    row.calm.mark:SetSize(16, 16)
    row.calm.mark:SetPoint("LEFT", 12, 0)
    row.calm.fs = HM.Text(row.calm, 12, COL.dim)
    row.calm.fs:SetPoint("LEFT", row.calm.mark, "RIGHT", 8, 0)
    row.calm.fs:SetText("Your layouts are up to date.")
    local CL = NS.Changelog
    local ver = CL and CL.versions and CL.versions[1]
    if ver then
        row.headN = HM.MakeHead(row.R, "What's New", "All notes", function()
            if CL.Show then CL.Show() end
        end, "notes")
        row.notes = HM.MakeNotes(row.R, ver)
    end
    row._sync = function()
        local st = HM.state
        if not st then return end
        local usable = HM.Usable(pg)
        if not usable then return end
        local two = usable >= HM.TWO_COL
        local mw, rw = usable, usable
        if two then
            rw = HM.RAIL_W
            mw = usable - HM.COL_GAP - rw
        end
        local mh = HM.LayMain(row, st, mw)
        local rh = HM.LayRail(row, st, rw)
        row.M:ClearAllPoints()
        row.M:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -4)
        row.M:SetSize(mw, mh)
        row.R:ClearAllPoints()
        if two then
            row.R:SetPoint("TOPLEFT", row, "TOPLEFT", 12 + mw + HM.COL_GAP, -4)
        else
            row.R:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -4 - mh - HM.SEC_GAP)
        end
        row.R:SetSize(rw, rh)
        row._two = two
        local want = 4 + (two and math.max(mh, rh) or (mh + HM.SEC_GAP + rh)) + 10
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    HM.main = row
    return row
end

-- The Spotlight, in the main column under My Layouts: the featured layout
-- packs, a card per maker (a pack with no maker has a short card of its own),
-- then the strip that asks for yours

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
    -- PaintMaker places and sizes the rest, for the pack it shows
    c.note = HM.Text(c, 11, COL.dim)
    c.note:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -6)
    c.note:SetJustifyV("TOP")
    -- the chosen pack's picture: hovered big, clicked like the button
    c.pic = CreateFrame("Button", nil, c, "BackdropTemplate")
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
    c.title:SetJustifyV("TOP")
    c.yours = HM.MakeChip(c, 9)
    c.desc = HM.Text(c, 11, COL.dim)
    c.desc:SetJustifyV("TOP")
    c.act = HM.Arc(HM.Big(AT.MakeSmallButton(c, "Use this layout", 124), 124))
    c.act:SetScript("OnClick", function() if c.shown then HM.PickPack(c.shown) end end)
    c.state = HM.Text(c, 11, COL.dim)
    c.state:SetJustifyV("TOP")
    c.rule = c:CreateTexture(nil, "ARTWORK")
    c.rule:SetColorTexture(COL.hair[1], COL.hair[2], COL.hair[3], 1)
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
        -- another pack can take more or fewer lines: the whole page lays out again
        b:SetScript("OnClick", function()
            c.sel = t
            HM.Refresh()
        end)
        AT.Tooltip(b, t.title or HM.ClassName(t.packClass), function() return HM.PackWords(t) end)
        c.crests[i] = b
    end
    -- the ask for yours at the card's foot, shown on the Spotlight's last card
    c.strip = HM.MakeStrip(c, false, false)
    c.strip:Hide()
    return c
end

-- a pack's state in words, for its crest's tooltip
function HM.PackWords(t)
    if t.hasUpdate and t.hasUpdate() then return "In your collection. An update is out." end
    if t.owned and t.owned() then return "In your collection." end
    return "Not in your collection yet."
end

-- Picks the pack the card shows (the one clicked, else yours, else the
-- newest), paints the card for it w wide and returns its height. Giving way,
-- in order: the picture shrinks to MAKER_IMG_MIN, the chip marking your class
-- drops under the title, the button drops under the state line, and the
-- crests take a second line; every text wraps rather than being cut.
function HM.PaintMaker(c, w)
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
    c.pic.entry.src = sel
    local inner = w - 24
    c.noteOn = yours == nil and mine ~= nil
    c.note:SetText(c.noteOn and ("No %s layout from %s yet, so this shows the newest."):format(HM.ClassName(mine), c.maker) or "")
    c.note:SetShown(c.noteOn)
    local top = 10 + 18
    if c.noteOn then top = top + 6 + HM.Wrap(c.note, inner) end
    top = top + 8
    c.title:SetText(sel.title or HM.ClassName(sel.packClass))
    local chipW = 0
    if sel == yours then
        chipW = c.yours:Set("YOUR CLASS", COL.arc, true)
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
    local actW = HM.Fit(c.act, 124)
    local titleW = math.ceil(HM.Width(c.title))
    local stateW = math.ceil(HM.Width(c.state))
    -- the picture: as big as the words beside it leave room for, 2:1 in whole units
    local want = math.max(titleW + ((chipW > 0) and (8 + chipW) or 0), stateW + 10 + actW)
    local pw = math.max(HM.MAKER_IMG_MIN, math.min(HM.MAKER_IMG_W, inner - 16 - want))
    pw = pw - pw % 2
    local ph = pw / 2
    c.pic:SetSize(pw, ph)
    c.pic:ClearAllPoints()
    c.pic:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -top)
    -- a stage per pack, drawn once at full size and scaled to the picture
    local st = HM.ShowPicture(c.pic, sel, HM.MAKER_IMG_W, HM.MAKER_IMG_W / 2)
    st:SetScale(pw / HM.MAKER_IMG_W)
    local tx = 12 + pw + 16
    local tw = math.max(60, w - tx - 12)
    local th = HM.Wrap(c.title, math.min(titleW + 2, tw))
    c.title:ClearAllPoints()
    c.title:SetPoint("TOPLEFT", c, "TOPLEFT", tx, -top)
    local ty = top + th
    c.yours:ClearAllPoints()
    if chipW > 0 then
        if titleW + 8 + chipW <= tw then
            c.yours:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
        else
            c.yours:SetPoint("TOPLEFT", c, "TOPLEFT", tx, -(ty + 4))
            ty = ty + 4 + c.yours:GetHeight()
        end
    end
    c.desc:ClearAllPoints()
    c.desc:SetPoint("TOPLEFT", c, "TOPLEFT", tx, -(ty + 6))
    ty = ty + 6 + HM.Wrap(c.desc, tw)
    -- the state and the button sit on the picture's foot, or under the words
    -- when those run longer; on one line where both fit
    local one = stateW + 10 + actW <= tw
    local sh = HM.Wrap(c.state, one and (tw - actW - 10) or tw)
    local foot = math.max(top + ph, ty + 8 + (one and 26 or (sh + 6 + 26)))
    c.act:ClearAllPoints()
    c.state:ClearAllPoints()
    if one then
        c.act:SetPoint("BOTTOMRIGHT", c, "TOPRIGHT", -12, -foot)
        c.state:SetPoint("TOPLEFT", c, "TOPLEFT", tx, -(foot - 13 - math.floor(sh / 2)))
    else
        c.act:SetPoint("BOTTOMLEFT", c, "TOPLEFT", tx, -foot)
        c.state:SetPoint("TOPLEFT", c, "TOPLEFT", tx, -(foot - 26 - 6 - sh))
    end
    local ruleY = foot + 10
    c.rule:ClearAllPoints()
    c.rule:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -ruleY)
    c.rule:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -ruleY)
    -- the crests share the card's width, a second line where it holds fewer
    local n = #c.crests
    local per = math.max(1, math.min(n, math.floor(inner / HM.CREST_W)))
    local cw = math.floor(inner / per)
    for i, b in ipairs(c.crests) do
        local on = b.t == sel
        local col, line = (i - 1) % per, math.floor((i - 1) / per)
        b:SetSize(cw, HM.CREST_H)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + col * cw, -(ruleY + 8 + line * (HM.CREST_H + 4)))
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
    local lines = math.ceil(n / per)
    local h = ruleY + 8 + lines * HM.CREST_H + (lines - 1) * 4 + 8
    if c.strip:IsShown() then
        local sh2 = HM.LayStrip(c.strip, w)
        c.strip:ClearAllPoints()
        c.strip:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -h)
        h = h + sh2
    end
    return h
end

-- An upload mark drawn from bars like the house: a stem and its arrowhead
-- rising out of an open tray. :SetColor(c) tints it.
function HM.MakeUpload(parent)
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
    Bar(1.5, 7, 0, 1.5)
    Bar(5, 1.5, -1.6, 3.5, 45)
    Bar(5, 1.5, 1.6, 3.5, -45)
    Bar(1.5, 4, -5, -3.5)
    Bar(1.5, 4, 5, -3.5)
    Bar(11.5, 1.5, 0, -5.5)
    function f:SetColor(c)
        for _, t in ipairs(self._bars) do t:SetVertexColor(c[1], c[2], c[3], 1) end
    end
    f:SetColor(COL.arc)
    return f
end

-- The ask for the player's own layout: the upload mark, the words (the first
-- sentence brighter) and Copy link for the Arc UI Discord. Inside a maker
-- card it is the card's tinted foot under a hairline; `boxed`, it stands as
-- its own box. `featured`: the words while there are no packs to show.
function HM.MakeStrip(parent, boxed, featured)
    local s = CreateFrame("Frame", nil, parent, boxed and "BackdropTemplate" or nil)
    if boxed then AT.Skin(s, COL.box, COL.line) end
    s.tint = s:CreateTexture(nil, "BACKGROUND", nil, 1)
    s.tint:SetTexture(AT.WHITE)
    s.tint:SetAllPoints()
    s.tint:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 0.06)
    if not boxed then
        s.rule = s:CreateTexture(nil, "ARTWORK")
        s.rule:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
        s.rule:SetHeight(AT.Hairline(s))
        s.rule:SetPoint("TOPLEFT", 0, 0)
        s.rule:SetPoint("TOPRIGHT", 0, 0)
    end
    s.glyph = HM.MakeUpload(s)
    s.glyph:SetPoint("LEFT", 12, 0)
    s.copy = HM.Arc(AT.MakeSmallButton(s, "Copy link", 70))
    HM.Fit(s.copy, 70)
    s.copy:SetPoint("RIGHT", -12, 0)
    s.copy:SetScript("OnClick", function(b)
        local SP = NS.Spotlight
        if SP and SP.ShowLink then SP.ShowLink(AT.DISCORD, "Arc UI Discord", b) end
    end)
    s.fs = HM.Text(s, 11, COL.dim)
    s.fs:SetPoint("LEFT", s.glyph, "RIGHT", 8, 0)
    local first = featured and "Your layout could be featured here." or "Your layout could be next."
    s.fs:SetText("|cff" .. HM.Hex(COL.ink) .. first .. "|r Share it on the Arc UI Discord with a screenshot.")
    return s
end

-- sizes the strip to w and returns its height: the words wrap beside Copy link
function HM.LayStrip(s, w)
    local tw = math.max(40, w - 12 - 14 - 8 - 10 - s.copy:GetWidth() - 12)
    local h = math.max(HM.STRIP_H, HM.Wrap(s.fs, tw) + 16)
    s:SetSize(w, h)
    return h
end

-- The Spotlight's heading ("Browse all layouts" opens New Layout while there
-- are packs), its cards and the ask for yours: the foot of the last card when
-- that is a maker's, else its own box. With no packs for this game yet
-- (retail) the box alone asks to be featured here.
function HM.MakeSpot(parent, list)
    local sp = { cards = {} }
    sp.head = HM.MakeHead(parent, "Arc Auras Layout Spotlight", (#list > 0) and "Browse all layouts" or nil, function()
        Options.Select("newlayout")
    end, "spotlight")
    for _, g in ipairs(HM.Makers(list)) do
        sp.cards[#sp.cards + 1] = g.single and HM.MakePack(parent, g[1]) or HM.MakeMaker(parent, g)
    end
    local last = sp.cards[#sp.cards]
    if last and last.packs then
        last.strip:Show()
    else
        sp.share = HM.MakeStrip(parent, true, #list == 0)
    end
    return sp
end

-- Lays the Spotlight out in `parent` from y0 down, w wide, one card to a
-- line; folded, the heading alone. Returns its height.
function HM.LaySpot(sp, parent, y0, w)
    sp.head:ClearAllPoints()
    sp.head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y0)
    sp.head:SetWidth(w)
    HM.PaintHead(sp.head)
    local open = not HM.Shut(sp.head._key)
    for _, c in ipairs(sp.cards) do c:SetShown(open) end
    if sp.share then sp.share:SetShown(open) end
    if not open then return HM.HEAD_H end
    local y = y0 + HM.HEAD_H + 8
    for _, c in ipairs(sp.cards) do
        local h = HM.PACK_H
        if c.packs then h = HM.PaintMaker(c, w) else HM.PaintPack(c) end
        c:SetSize(w, h)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        y = y + h + HM.GAP
    end
    if sp.share then
        local h = HM.LayStrip(sp.share, w)
        sp.share:ClearAllPoints()
        sp.share:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        y = y + h + HM.GAP
    end
    return y - y0
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
