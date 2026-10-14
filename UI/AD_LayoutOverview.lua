-- The layout editor's Overview tab: Size with Mouse under it beside Place, the
-- layout and its center point on a small copy of the screen with its element
-- list, then Anchored to this as a shut fold. BuildLayoutPane (UI\AD_Options.lua)
-- calls Options.BuildLayoutOverview; scale, position and strata live in the
-- store, the element rects and the point in the layout engine. Every store
-- and engine call is checked first, so the tab builds before those exist.
local _, NS = ...
local AT = NS.AT
local COL = AT.COL
local Tr = AT.Tr
local Store = NS.Store
local Options = NS.Options

-- Capitals only for plain Latin words: string.upper would split a multibyte
-- letter, and other scripts have no capitals.
local function Upper(s)
    if type(s) ~= "string" or s:find("[\128-\255]") then return s end
    return s:upper()
end

local OV = {}
Options.LayoutOverview = OV

-- The map takes the screen's shape: up to 600 x 338, as tall as the page
-- leaves room for, and never so wide that the list beside it drops under 180.
OV.MAP_MAX_W, OV.MAP_MAX_H, OV.MAP_MIN_H = 600, 338, 120
OV.LIST_MIN_W = 180
OV.MAP_PAD = 6
OV.ROW_H, OV.ROW_GAP = 24, 3
-- A dashed side has at most this many dashes, so the pool stays small.
OV.DASHES = 24
-- The layout page at the default window (1020 x 760), for a first pass that
-- runs before the page has a size.
OV.DESIGN_W, OV.DESIGN_H = 763, 619
OV.POS_MAX = 2000
OV.SCALE_MIN, OV.SCALE_MAX = 0.5, 2
OV.SCALE_CHIPS = { 0.9, 1, 1.1, 1.25, 1.5 }
-- The center point's cross on the map: each arm this long, in UI units, and
-- how far a set center's dot reaches past its middle pixel.
OV.CROSS, OV.PIN = 5, 1.5
-- A shift moves each element that many layers from its own.
OV.STRATA = {
    { value = "own", text = "Each element's own" },
    { value = "own-1", text = "Each element's own, 1 lower", shift = -1 },
    { value = "own-2", text = "Each element's own, 2 lower", shift = -2 },
    { value = "own+1", text = "Each element's own, 1 higher", shift = 1 },
    { value = "own+2", text = "Each element's own, 2 higher", shift = 2 },
    { value = "BACKGROUND", text = "Background" },
    { value = "LOW", text = "Low" },
    { value = "MEDIUM", text = "Medium" },
    { value = "HIGH", text = "High" },
    { value = "DIALOG", text = "Dialog" },
}
-- the list for a store that has no shifts
OV.STRATA_FIXED = {}
for _, it in ipairs(OV.STRATA) do
    if not it.shift then OV.STRATA_FIXED[#OV.STRATA_FIXED + 1] = it end
end
-- The screen spot a layout keeps its distance from; the middle stores nil.
OV.PINS = {
    { value = "middle", text = "The middle of your screen" },
    { value = "TOP", text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
    { value = "TOPLEFT", text = "Top left" },
    { value = "TOPRIGHT", text = "Top right" },
    { value = "BOTTOMLEFT", text = "Bottom left" },
    { value = "BOTTOMRIGHT", text = "Bottom right" },
}

-- The layout's values

function OV.Scale(l)
    local s = l and Store.LayoutScale and tonumber(Store.LayoutScale(l))
    return s or 1
end

function OV.SetScale(l, s)
    if not (l and Store.SetLayoutScale) then return end
    -- whole percents: a stepped 0.05 drifts in floating point
    s = math.floor((tonumber(s) or 1) * 100 + 0.5) / 100
    s = math.max(OV.SCALE_MIN, math.min(OV.SCALE_MAX, s))
    if s == OV.Scale(l) then return end
    Store.SetLayoutScale(l, s)
end

function OV.Pos(l)
    if not l then return 0, 0 end
    local x, y
    if Store.LayoutPos then
        x, y = Store.LayoutPos(l)
        if type(x) == "table" then x, y = x.x, x.y end
    else
        x, y = l.pos and l.pos.x, l.pos and l.pos.y
    end
    return math.floor((tonumber(x) or 0) + 0.5), math.floor((tonumber(y) or 0) + 0.5)
end

function OV.SetPos(l, x, y)
    if not l then return end
    local function Clamp(v)
        v = math.floor((tonumber(v) or 0) + 0.5)
        return math.max(-OV.POS_MAX, math.min(OV.POS_MAX, v))
    end
    x, y = Clamp(x), Clamp(y)
    local ox, oy = OV.Pos(l)
    if x == ox and y == oy then return end
    -- only the axis that changed: an untouched box must not round a fraction
    -- a pin change left
    local wx, wy = (x ~= ox) and x or nil, (y ~= oy) and y or nil
    if Store.SetLayoutPos then
        Store.SetLayoutPos(l, wx, wy)
        return
    end
    -- the record's own X / Y, as the Position rows wrote them
    l.pos = l.pos or {}
    if wx then l.pos.x = wx end
    if wy then l.pos.y = wy end
    Store.Dirty("style", l.id)
end

local function HasShifts()
    return Store.LayoutStrataShift ~= nil and Store.SetLayoutStrataShift ~= nil
end

function OV.StrataItems()
    return HasShifts() and OV.STRATA or OV.STRATA_FIXED
end

function OV.Strata(l)
    if not l then return "own" end
    local n = HasShifts() and Store.LayoutStrataShift(l)
    if n then
        for _, it in ipairs(OV.STRATA) do
            if it.shift == n then return it.value end
        end
    end
    local v = Store.LayoutStrata and Store.LayoutStrata(l)
    return v or "own"
end

-- A shift clears the fixed layer in the store, a fixed layer the shift;
-- Each element's own clears both.
function OV.SetStrata(l, v)
    if not l then return end
    for _, it in ipairs(OV.STRATA) do
        if it.value == v and it.shift then
            if HasShifts() then Store.SetLayoutStrataShift(l, it.shift) end
            return
        end
    end
    if v == "own" and HasShifts() and Store.LayoutStrataShift(l) then
        Store.SetLayoutStrataShift(l, nil)
    end
    if Store.SetLayoutStrata then Store.SetLayoutStrata(l, (v ~= "own") and v or nil) end
end

function OV.Pin(l)
    local v = l and Store.LayoutPin and Store.LayoutPin(l)
    return v or "middle"
end

-- Through the engine, which keeps the layout where it is on screen.
function OV.SetPin(l, v)
    local E = NS.LayoutEngine
    if not (l and E and E.SetLayoutPin) then return end
    E.SetLayoutPin(l.id, (v ~= "middle") and v or nil)
end

-- The layout's center point: where it sits and where scale grows from, as
-- an offset from the screen's middle.
function OV.Point(l)
    local E = NS.LayoutEngine
    if l and E and E.LayoutPoint then
        local x, y = E.LayoutPoint(l.id)
        x, y = tonumber(x), tonumber(y)
        if x and y then return x, y end
    end
    return OV.Pos(l)
end

-- Center puts the middle of what's shown on the screen's middle, the center
-- point with it; a center the player set goes to the middle itself.
function OV.Center(l)
    if not l then return end
    local E = NS.LayoutEngine
    if E and E.CenterLayout then
        E.CenterLayout(l.id)
    else
        OV.SetPos(l, 0, 0)
    end
end

-- true once the player picked the center point on screen (Use as center)
function OV.CenterSet(l)
    return l ~= nil and Store.LayoutCenterSet ~= nil and Store.LayoutCenterSet(l) == true
end

-- Forget center: Center goes back to centering what's shown; nothing moves.
function OV.ForgetCenter(l)
    if l and Store.SetLayoutCenterSet then Store.SetLayoutCenterSet(l, nil) end
end

-- Names over the boxes: a panel setting the on-screen mode reads too, on
-- until turned off (the board shows them).
function OV.NamesOn()
    local u = Store.UI()
    return not (u and u.layoutNames == false)
end

function OV.SetNames(on)
    local u = Store.UI()
    if u then u.layoutNames = on and true or false end
end

-- The on-screen mode when its file is loaded, else every layout's drag handle.
function OV.Moving()
    local LOS = Options.LayoutOnScreen
    if LOS and LOS.Open then return LOS.IsOpen ~= nil and LOS.IsOpen() == true end
    local E = NS.LayoutEngine
    return E ~= nil and E.IsMoveMode ~= nil and E.IsMoveMode() == true
end

function OV.ToggleMove(l)
    local LOS = Options.LayoutOnScreen
    if LOS and LOS.Open then
        if OV.Moving() and LOS.Close then
            LOS.Close()
        elseif l then
            LOS.Open(l.id)
        end
        return
    end
    local E = NS.LayoutEngine
    if E and E.SetMoveMode and E.IsMoveMode then E.SetMoveMode(not E.IsMoveMode()) end
end

function OV.MoveWord()
    if not OV.Moving() then return "Edit on screen" end
    local LOS = Options.LayoutOnScreen
    return (LOS and LOS.Open) and "Done editing" or "Lock position"
end

-- Every member of the layout, with its place on the screen when the engine
-- shows it: one not loaded here still gets its list row, just no box.
function OV.Elements(l)
    if not l then return {} end
    local E = NS.LayoutEngine
    local rects = (E and E.LayoutElementRects and E.LayoutElementRects(l.id)) or {}
    local byId = {}
    for _, r in ipairs(rects) do
        if r.id ~= nil then byId[r.id] = r end
    end
    local out = {}
    for _, rec in ipairs(Store.MembersOf(l)) do
        out[#out + 1] = byId[rec.id] or { id = rec.id, name = rec.name, kind = rec.type }
        byId[rec.id] = nil
    end
    for _, r in ipairs(rects) do
        if r.id ~= nil and byId[r.id] then out[#out + 1] = r end
    end
    return out
end

function OV.Bounds(l)
    local E = NS.LayoutEngine
    if not (l and E and E.LayoutBounds) then return nil end
    return E.LayoutBounds(l.id)
end

function OV.Screen()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not (w and h and w > 0 and h > 0) then
        w, h = GetPhysicalScreenSize()
        if not (w and h and w > 0 and h > 0) then w, h = 1920, 1080 end
    end
    return w, h
end

-- An element's pill words and its kind colour, as the sidebar shows them.
function OV.KindOf(el)
    local rec = el and el.id and Store.Get(el.id)
    if rec and Options.RecPillText then
        local text, c = Options.RecPillText(rec)
        return text, AT.Mute(c or COL.dim)
    end
    return tostring((el and el.kind) or "Element"), COL.dim
end

local function TextW(fs, fallback)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    if type(w) ~= "number" or w <= 0 then return fallback end
    return math.ceil(w)
end

-- Rows

-- A row of picks drawn as chips, the lit one edged in the accent.
-- opts.label: words before them; opts.column: on the section's control column.
function Options.ChipPickRow(pg, items, get, set, vis, opts)
    opts = opts or {}
    local row = AT.AddRow(pg, 28, vis)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetHeight(20)
    local lbl
    if opts.label then
        lbl = row:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 12, "")
        lbl:SetPoint("LEFT", 10, 0)
        lbl:SetWordWrap(false)
        lbl:SetText(Tr(opts.label))
        holder:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
    elseif not opts.column then
        holder:SetPoint("LEFT", 10, 0)
    end
    local chips, x = {}, 0
    for i, it in ipairs(items) do
        local c = CreateFrame("Button", nil, holder, "BackdropTemplate")
        c:SetHeight(20)
        AT.Skin(c, COL.well, COL.line2)
        c.fs = c:CreateFontString(nil, "OVERLAY")
        c.fs:SetFont(AT.FONT, 11, "")
        c.fs:SetPoint("CENTER", 0, 0)
        local words = Tr(it.text)
        c.fs:SetText(words)
        local w = TextW(c.fs, AT.TextLen(words) * 6) + 18
        c:SetWidth(w)
        c:SetPoint("LEFT", x, 0)
        x = x + w + 6
        c._value = it.value
        c:SetScript("OnClick", function(s)
            AT.CloseDropdown()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
            set(s._value)
        end)
        c:SetScript("OnEnter", function(s)
            s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        end)
        c:SetScript("OnLeave", function() row._sync() end)
        chips[i] = c
    end
    holder:SetWidth(math.max(1, x - 6))
    row._sync = function()
        local cur = get()
        for _, c in ipairs(chips) do
            local on = c._value == cur
            c._on = on
            local f, e, t = COL.well, COL.line2, COL.dim
            if on then f, e, t = COL.sel, COL.arc, COL.ink end
            c:SetBackdropColor(f[1], f[2], f[3], 1)
            c:SetBackdropBorderColor(e[1], e[2], e[3], 1)
            c.fs:SetTextColor(t[1], t[2], t[3])
        end
        if lbl then lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3]) end
    end
    if opts.column then
        row._colCtrl = holder
        row._colTrail = 0
    end
    row._chips = chips
    return row
end

-- One dim line that wraps to its own box (a half-width block's too).
function OV.NoteRow(pg, text, vis, side)
    local row = AT.AddRow(pg, AT.LAY.descH, vis)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -2)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    row._adText = fs
    row._sync = function()
        fs:SetText(Tr((type(text) == "function") and text() or text))
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        local w = row:GetWidth() or 0
        if w < 60 then
            -- unsized on the first pass: the page's share of it
            local pw = pg:GetWidth() or 0
            if pw < 60 then
                pg._sizeUnresolved = true
                pw = OV.DESIGN_W
            end
            w = (side and (pw / 2) or pw) - 24
        end
        fs:SetWidth(w - 20)
        local want = math.max(AT.LAY.descH, math.floor((fs:GetStringHeight() or 12) + 8))
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
        end
    end
    return row
end

-- Edit on screen and Center, then Forget center while a center is set.
function OV.MoveRow(pg, sel, vis, repaint)
    local row = AT.AddRow(pg, 28, vis)
    local move = AT.MakeSmallButton(row, "Edit on screen", 110)
    -- one width for every word it shows, so Center beside it never shifts
    local mw = 0
    for _, s in ipairs({ "Edit on screen", "Done editing", "Lock position" }) do
        local words = Tr(s)
        move.fs:SetText(words)
        mw = math.max(mw, TextW(move.fs, AT.TextLen(words) * 6))
    end
    move.fs:SetText(Tr("Edit on screen"))
    move:SetWidth(math.max(110, mw + 22))
    move:SetPoint("LEFT", 10, 0)
    local center = AT.MakeSmallButton(row, "Center", 64)
    center:SetPoint("LEFT", move, "RIGHT", 8, 0)
    local forget = (AT.MakeQuietButton or AT.MakeSmallButton)(row, "Forget center", 96)
    forget:SetWidth(math.max(96, TextW(forget.fs, 74) + 22))
    forget:SetPoint("LEFT", center, "RIGHT", 8, 0)
    forget:SetScript("OnClick", function()
        AT.CloseDropdown()
        OV.ForgetCenter(sel())
        repaint()
    end)
    AT.Tooltip(forget, "Forget center", "Center goes back to centering what's shown.")
    forget:Hide()
    local function Lit()
        if not OV.Moving() then return end
        move:SetBackdropColor(COL.sel[1], COL.sel[2], COL.sel[3], 1)
        move:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    end
    move:SetScript("OnClick", function()
        AT.CloseDropdown()
        OV.ToggleMove(sel())
        repaint()
    end)
    move:HookScript("OnLeave", Lit)
    center:SetScript("OnClick", function()
        AT.CloseDropdown()
        OV.Center(sel())
        repaint()
    end)
    AT.Tooltip(move, "Edit on screen", function()
        local LOS = Options.LayoutOnScreen
        if LOS and LOS.Open then return "Move, size and anchor this layout's elements right on your screen." end
        return "Shows a drag handle on every layout. Drag it where you want, then lock."
    end)
    AT.Tooltip(center, "Center", function()
        if OV.CenterSet(sel()) then return "Puts the layout's center point in the middle of your screen." end
        return "Puts the middle of what's shown in the middle of your screen. Scale grows from there."
    end)
    row._sync = function()
        forget:SetShown(OV.CenterSet(sel()))
        move.fs:SetText(Tr(OV.MoveWord()))
        if OV.Moving() then
            Lit()
        else
            move:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
            move:SetBackdropBorderColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
        end
    end
    row._adMove, row._adCenter, row._adForget = move, center, forget
    row._adSearch = function() return { "Edit on screen", "Center" } end
    return row
end

-- Nudge < ^ v >, then the X and Y boxes: whole numbers from the spot it's pinned to.
function OV.NudgeRow(pg, sel, vis, repaint)
    local row = AT.AddRow(pg, 28, vis)
    local lbl = AT.RowLabel(row, "Nudge")
    local holder = CreateFrame("Frame", nil, row)
    holder:SetHeight(20)
    local x = 0
    local arrows = {}
    local function Arrow(glyph, dx, dy, title)
        local b = CreateFrame("Button", nil, holder, "BackdropTemplate")
        b:SetSize(20, 20)
        AT.Skin(b, COL.well, COL.line2)
        b.fs = b:CreateFontString(nil, "OVERLAY")
        b.fs:SetFont(AT.FONT, 11, "")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(glyph)
        b:SetPoint("LEFT", x, 0)
        x = x + 24
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            local l = sel()
            if not l then return end
            local n = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
            local px, py = OV.Pos(l)
            OV.SetPos(l, px + dx * n, py + dy * n)
            repaint()
        end)
        b:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
        b:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1) end)
        AT.Tooltip(b, title, "Moves the layout one pixel. Shift-click moves it ten.")
        arrows[#arrows + 1] = b
        return b
    end
    Arrow("<", -1, 0, "Nudge left")
    Arrow("^", 0, 1, "Nudge up")
    Arrow("v", 0, -1, "Nudge down")
    Arrow(">", 1, 0, "Nudge right")
    x = x + 6
    local function Box(word, axis)
        local fs = holder:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 12, "")
        fs:SetPoint("LEFT", x, 0)
        fs:SetText(word)
        x = x + TextW(fs, 8) + 4
        local box = CreateFrame("EditBox", nil, holder, "BackdropTemplate")
        box:SetSize(48, 18)
        box:SetPoint("LEFT", x, 0)
        AT.Skin(box, COL.well)
        box:SetFont(AT.FONT, 11, "")
        box:SetJustifyH("CENTER")
        box:SetTextInsets(4, 4, 0, 0)
        box:SetAutoFocus(false)
        x = x + 48 + 10
        local function Cur()
            local px, py = OV.Pos(sel())
            return (axis == "x") and px or py
        end
        -- Enter and clicking away both commit through focus lost; a word that is
        -- no number puts the value back.
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self)
            AT.BoxText(self, tostring(Cur()))
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
        end)
        box:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
            local l, n = sel(), tonumber(self:GetText())
            if l and n then
                local px, py = OV.Pos(l)
                if axis == "x" then px = n else py = n end
                OV.SetPos(l, px, py)
                repaint()
            end
            AT.BoxText(self, tostring(Cur()))
        end)
        AT.Tooltip(box, word,
            "Where the layout's center point (the cross on the map) sits from the spot it's pinned to, in whole pixels.")
        return box
    end
    local bx = Box("X", "x")
    local by = Box("Y", "y")
    holder:SetWidth(x - 10)
    row._colLabel, row._colCtrl = lbl, holder
    row._sync = function()
        local px, py = OV.Pos(sel())
        if not bx:HasFocus() then AT.BoxText(bx, tostring(px)) end
        if not by:HasFocus() then AT.BoxText(by, tostring(py)) end
        for _, b in ipairs(arrows) do b.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3]) end
    end
    row._adArrows, row._adX, row._adY = arrows, bx, by
    row._adSearch = function() return { "Nudge", "X", "Y" } end
    return row
end

-- The map

local MAP_BG = { 0.031, 0.067, 0.110 }

local function Snap(st, v)
    local px = st.px or 1
    return math.floor(v / px + 0.5) * px
end

function OV.Box(st, i)
    local b = st.boxes[i]
    if b then return b end
    b = CreateFrame("Button", nil, st.map, "BackdropTemplate")
    AT.Skin(b, COL.well, COL.line2)
    b.name = b:CreateFontString(nil, "OVERLAY")
    b.name:SetFont(AT.FONT, 10, "")
    b.name:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 2)
    b.name:SetWordWrap(false)
    b:SetScript("OnClick", function(s) OV.Pick(st, s._id) end)
    b:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    b:SetScript("OnLeave", function(s) OV.PaintBox(st, s) end)
    -- the theme's tooltip look, its title the element's name as the player
    -- typed it (a name never goes to the translator)
    b:HookScript("OnEnter", function(s)
        local body = b._kindWord
        if type(body) ~= "string" or body == "" then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine(b._name or "", 1, 1, 1)
        GameTooltip:AddLine(Tr(body), 0.75, 0.82, 0.92, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    st.boxes[i] = b
    return b
end

function OV.ListRow(st, i)
    local r = st.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, st.list, "BackdropTemplate")
    r:SetHeight(OV.ROW_H)
    AT.Skin(r, COL.well, COL.line)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(AT.WHITE)
    r.mark:SetSize(10, 10)
    r.mark:SetPoint("LEFT", 8, 0)
    r.pill = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.pill:SetHeight(14)
    AT.Skin(r.pill, { 0, 0, 0, 0 }, COL.line2)
    r.pill:SetPoint("RIGHT", -6, 0)
    r.pill.fs = r.pill:CreateFontString(nil, "OVERLAY")
    r.pill.fs:SetFont(AT.FONT, 8, "")
    r.pill.fs:SetPoint("CENTER", 0, 0)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(AT.FONT, 12, "")
    r.name:SetPoint("LEFT", r.mark, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.pill, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnClick", function(s) OV.Pick(st, s._id) end)
    r:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    r:SetScript("OnLeave", function(s) OV.PaintListRow(st, s) end)
    st.rows[i] = r
    return r
end

function OV.Dash(st, i)
    local t = st.dashes[i]
    if t then return t end
    t = st.map:CreateTexture(nil, "ARTWORK")
    t:SetTexture(AT.WHITE)
    st.dashes[i] = t
    return t
end

function OV.PaintBox(st, b)
    local c = b._col or COL.dim
    local on = b._id ~= nil and b._id == st.selId
    local e = on and COL.arc or c
    b:SetBackdropColor(c[1], c[2], c[3], 0.33)
    b:SetBackdropBorderColor(e[1], e[2], e[3], 1)
    local t = on and COL.arc or COL.dim
    b.name:SetTextColor(t[1], t[2], t[3])
end

function OV.PaintListRow(st, r)
    local on = r._id ~= nil and r._id == st.selId
    local f, e = COL.well, COL.line
    if on then f, e = COL.sel, COL.arc end
    r:SetBackdropColor(f[1], f[2], f[3], 1)
    r:SetBackdropBorderColor(e[1], e[2], e[3], 1)
    r.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
end

-- A click on a box or a list row picks it; the same one again lets it go.
function OV.Pick(st, id)
    AT.CloseDropdown()
    if id == nil then return end
    st.selId = (st.selId ~= id) and id or nil
    PlaySound(st.selId and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    OV.Paint(st)
end

-- The layout's outline, dashed, with room over the boxes for their names.
function OV.PaintOutline(st, l, fx, fy)
    local bl, bb, bw, bh = OV.Bounds(l)
    local k = 0
    if bl and bb and bw and bh and bw > 0 and bh > 0 then
        local x = Snap(st, bl * fx - 4)
        local y = Snap(st, (st.sh - bb - bh) * fy - 16)
        local w = Snap(st, bw * fx + 8)
        local h = Snap(st, bh * fy + 20)
        local px = st.px or 1
        local c = OV.Moving() and COL.arc or COL.line2
        local function Side(x0, y0, len, horiz)
            local n = math.max(1, math.min(OV.DASHES, math.floor(len / 7)))
            local seg = len / n
            local d = math.max(2 * px, Snap(st, seg * 0.6))
            for i = 0, n - 1 do
                k = k + 1
                local t = OV.Dash(st, k)
                local off = Snap(st, i * seg)
                t:ClearAllPoints()
                if horiz then
                    t:SetPoint("TOPLEFT", st.map, "TOPLEFT", x0 + off, -y0)
                    t:SetSize(d, px)
                else
                    t:SetPoint("TOPLEFT", st.map, "TOPLEFT", x0, -(y0 + off))
                    t:SetSize(px, d)
                end
                t:SetVertexColor(c[1], c[2], c[3], 1)
                t:Show()
            end
        end
        Side(x, y, w, true)
        Side(x, y + h - px, w, true)
        Side(x, y, h, false)
        Side(x + w - px, y, h, false)
        st.outline = { x = x, y = y, w = w, h = h }
    else
        st.outline = nil
    end
    for i = k + 1, #st.dashes do st.dashes[i]:Hide() end
end

-- The center point as a cyan cross over the boxes and the outline, its
-- middle pixel on the screen's middle lines when the point is at 0, 0.
function OV.PaintPoint(st, l, fx, fy)
    local pt = st.point
    if not l then
        pt:Hide()
        st.pointXY = nil
        return
    end
    local x, y = OV.Point(l)
    local px = st.px or 1
    local arm = math.max(2 * px, Snap(st, OV.CROSS))
    local n = 2 * arm + px
    local cx = Snap(st, ((st.sw or 1) / 2 + x) * fx)
    local cy = Snap(st, ((st.sh or 1) / 2 - y) * fy)
    pt:ClearAllPoints()
    pt:SetPoint("TOPLEFT", st.map, "TOPLEFT", cx - arm, -(cy - arm))
    pt:SetSize(n, n)
    pt.h:ClearAllPoints()
    pt.h:SetPoint("TOPLEFT", pt, "TOPLEFT", 0, -arm)
    pt.h:SetSize(n, px)
    pt.v:ClearAllPoints()
    pt.v:SetPoint("TOPLEFT", pt, "TOPLEFT", arm, 0)
    pt.v:SetSize(px, n)
    pt.h:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    pt.v:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    -- a set center: a filled dot on the cross's middle pixel
    if OV.CenterSet(l) then
        local d = math.min(arm - px, math.max(px, Snap(st, OV.PIN)))
        pt.dot:ClearAllPoints()
        pt.dot:SetPoint("TOPLEFT", pt, "TOPLEFT", arm - d, -(arm - d))
        pt.dot:SetSize(2 * d + px, 2 * d + px)
        pt.dot:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        pt.dot:Show()
    else
        pt.dot:Hide()
    end
    pt:SetFrameLevel(st.map:GetFrameLevel() + 10)
    pt:Show()
    st.pointXY = { x = cx, y = cy }
end

-- Draws the map's boxes, the outline, the list and the Edit button from the
-- engine's rects at the size the last sync measured.
function OV.Paint(st)
    local l = st.env.sel()
    local lid = l and l.id
    if st.layoutId ~= lid then
        st.layoutId, st.selId = lid, nil
    end
    local els = OV.Elements(l)
    local selEl
    for _, el in ipairs(els) do
        if el.id ~= nil and el.id == st.selId then selEl = el end
    end
    if not selEl then st.selId = nil end
    local mapW, mapH = st.mapW or 0, st.mapH or 0
    local sw, sh = st.sw or 1, st.sh or 1
    local fx, fy = mapW / sw, mapH / sh
    st.px = AT.Px(st.map)
    local px = st.px
    st.map:SetBackdropColor(MAP_BG[1], MAP_BG[2], MAP_BG[3], 1)
    st.map:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    -- the screen's middle, faint
    st.hLine:ClearAllPoints()
    st.hLine:SetPoint("TOPLEFT", st.map, "TOPLEFT", 0, -Snap(st, mapH / 2))
    st.hLine:SetSize(mapW, px)
    st.vLine:ClearAllPoints()
    st.vLine:SetPoint("TOPLEFT", st.map, "TOPLEFT", Snap(st, mapW / 2), 0)
    st.vLine:SetSize(px, mapH)
    for _, t in ipairs({ st.hLine, st.vLine }) do
        t:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 0.7)
    end
    local names = OV.NamesOn()
    local nb = 0
    for _, el in ipairs(els) do
        local ew, eh = tonumber(el.width), tonumber(el.height)
        if ew and eh then
            nb = nb + 1
            local b = OV.Box(st, nb)
            local word, c = OV.KindOf(el)
            local x = Snap(st, (tonumber(el.left) or 0) * fx)
            local top = Snap(st, (sh - (tonumber(el.bottom) or 0) - eh) * fy)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", st.map, "TOPLEFT", x, -top)
            b:SetSize(math.max(3 * px, Snap(st, ew * fx)), math.max(3 * px, Snap(st, eh * fy)))
            b._id, b._name, b._kindWord, b._col = el.id, el.name or "?", word, c
            b.name:SetText(b._name)
            b.name:SetShown(names)
            OV.PaintBox(st, b)
            b:Show()
        end
    end
    for i = nb + 1, #st.boxes do st.boxes[i]:Hide() end
    st.shownBoxes = nb
    OV.PaintOutline(st, l, fx, fy)
    OV.PaintPoint(st, l, fx, fy)

    -- the list beside the map
    st.cap:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    local colW = st.colW or OV.LIST_MIN_W
    st.list:SetWidth(math.max(1, colW))
    local y = 0
    for i, el in ipairs(els) do
        local r = OV.ListRow(st, i)
        local word, c = OV.KindOf(el)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", st.list, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", st.list, "TOPRIGHT", 0, -y)
        r.mark:SetVertexColor(c[1], c[2], c[3], 1)
        r.name:SetText(el.name or "?")
        -- the pill fits its drawn words, so a longer language never spills
        local pillWords = Upper(Tr(word))
        r.pill.fs:SetText(pillWords)
        r.pill.fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        r.pill:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
        r.pill:SetWidth(TextW(r.pill.fs, AT.TextLen(pillWords) * 5) + 10)
        r._id = el.id
        OV.PaintListRow(st, r)
        r:Show()
        y = y + OV.ROW_H + OV.ROW_GAP
    end
    for i = #els + 1, #st.rows do st.rows[i]:Hide() end
    st.empty:SetShown(#els == 0)
    st.empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local listH = math.max(1, y - OV.ROW_GAP)
    st.list:SetHeight(listH)
    local room = mapH - 18 - (selEl and 30 or 0)
    st.host:SetHeight(math.max(1, math.min(listH, room)))
    st.host:UpdateScroll()
    if selEl then
        st.edit.fs:SetText(Tr("Edit %s"):format(selEl.name or "?"))
        st.edit:SetWidth(math.min(colW, TextW(st.edit.fs, 60) + 24))
        st.edit:Show()
    else
        st.edit:Hide()
    end
end

-- The map row: the map, then the list column with its caption, the scrolling
-- rows and the Edit button. restFn: the page's height outside the map.
function OV.MapRow(pg, env, vis, restFn)
    local row = AT.AddRow(pg, OV.MAP_MAX_H + 2 * OV.MAP_PAD, vis)
    local st = { env = env, boxes = {}, rows = {}, dashes = {} }
    local map = CreateFrame("Frame", nil, row, "BackdropTemplate")
    map:SetPoint("TOPLEFT", 8, -OV.MAP_PAD)
    AT.Skin(map, MAP_BG, COL.line2)
    map:SetClipsChildren(true)
    st.map = map
    st.hLine = map:CreateTexture(nil, "BORDER", nil, 1)
    st.hLine:SetTexture(AT.WHITE)
    st.vLine = map:CreateTexture(nil, "BORDER", nil, 1)
    st.vLine:SetTexture(AT.WHITE)
    -- hover only, so a click on the cross still reaches the box under it
    local pt = CreateFrame("Frame", nil, map)
    pt.h = pt:CreateTexture(nil, "OVERLAY")
    pt.h:SetTexture(AT.WHITE)
    pt.v = pt:CreateTexture(nil, "OVERLAY")
    pt.v:SetTexture(AT.WHITE)
    pt.dot = pt:CreateTexture(nil, "OVERLAY")
    pt.dot:SetTexture(AT.WHITE)
    pt.dot:Hide()
    if pt.EnableMouseMotion then pt:EnableMouseMotion(true) else pt:EnableMouse(true) end
    AT.Tooltip(pt, "Center point", "Scale grows from here. Drag it in Edit on screen to set it.")
    pt:Hide()
    st.point = pt
    local col = CreateFrame("Frame", nil, row)
    col:SetPoint("TOPLEFT", map, "TOPRIGHT", 14, 0)
    col:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, OV.MAP_PAD)
    st.col = col
    st.cap = col:CreateFontString(nil, "OVERLAY")
    st.cap:SetFont(AT.FONT, 10, "")
    st.cap:SetPoint("TOPLEFT", 0, 0)
    st.cap:SetText(Upper(Tr("In this layout")))
    local host, list = AT.MakeScroll(col)
    host:SetPoint("TOPLEFT", 0, -18)
    host:SetPoint("TOPRIGHT", 0, -18)
    host:SetHeight(1)
    st.host, st.list = host, list
    st.empty = col:CreateFontString(nil, "OVERLAY")
    st.empty:SetFont(AT.FONT, 11, "")
    st.empty:SetPoint("TOPLEFT", 0, -20)
    st.empty:SetText(Tr("Nothing in this layout yet."))
    st.empty:Hide()
    st.edit = AT.MakeSmallButton(col, "Edit", 80)
    st.edit:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -6)
    st.edit.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    st.edit:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = st.selId and Store.Get(st.selId)
        if rec and Options.SelectRecord then Options.SelectRecord(rec) end
    end)
    AT.Tooltip(st.edit, "Edit", "Opens its editor.")
    st.edit:Hide()
    -- sized on every pass: as tall as the page leaves, the screen's shape
    row._sync = function()
        local pgW = pg:GetWidth() or 0
        if pgW < 100 then
            pg._sizeUnresolved = true
            pgW = OV.DESIGN_W
        end
        local rowW = row:GetWidth() or 0
        if rowW < 100 then rowW = pgW - 24 - (pg._scroll and AT.ScrollExtra() or 0) end
        local pgH = pg:GetHeight() or 0
        if pgH < 100 then pgH = OV.DESIGN_H end
        local sw, sh = OV.Screen()
        local aspect = sw / sh
        local mapH = math.floor(math.max(OV.MAP_MIN_H, math.min(OV.MAP_MAX_H, pgH - restFn())))
        local mapW = math.floor(mapH * aspect + 0.5)
        local maxW = math.min(OV.MAP_MAX_W, rowW - 8 - 14 - OV.LIST_MIN_W - 8)
        if mapW > maxW then
            mapW = math.max(160, maxW)
            mapH = math.floor(mapW / aspect + 0.5)
        end
        st.mapW, st.mapH, st.sw, st.sh = mapW, mapH, sw, sh
        st.colW = rowW - 8 - mapW - 14 - 8
        map:SetSize(mapW, mapH)
        local want = mapH + 2 * OV.MAP_PAD
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
        end
        OV.Paint(st)
        if st.namesBox then st.namesBox:SetOn(OV.NamesOn()) end
    end
    row._adState = st
    OV.state = st
    return row, st
end

-- "Show names on screen" at the right of the block's header band, as the
-- board draws it; a palette without bands puts it on a row of its own.
function OV.NamesToggle(pg, sec, vis, repaint)
    local function Flip()
        AT.CloseDropdown()
        OV.SetNames(not OV.NamesOn())
        PlaySound(OV.NamesOn() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        repaint()
    end
    local TIP = "Writes each element's name over its box, here and while you move the layout on screen."
    if not sec.band then
        local row = AT.RowToggle(pg, "Show names on screen", OV.NamesOn, function(v) OV.SetNames(v) end, vis, TIP)
        return row, row._colCtrl
    end
    local t = CreateFrame("Button", nil, sec.band)
    t:SetHeight(18)
    t:SetPoint("RIGHT", -10, 0)
    local cb = AT.MakeCheckbox(t)
    cb:SetPoint("LEFT", 0, 0)
    cb:EnableMouse(false)
    local fs = t:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    fs:SetText(Tr("Show names on screen"))
    fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    t:SetWidth(18 + 6 + TextW(fs, 120) + 2)
    t:SetScript("OnClick", Flip)
    t:SetScript("OnEnter", function() cb:SetHover(true) end)
    t:SetScript("OnLeave", function() cb:SetHover(false) end)
    AT.Tooltip(t, "Show names on screen", TIP)
    cb:SetOn(OV.NamesOn())
    return t, cb
end

-- The tab

local function Shut(sec)
    sec.collapsed, sec.f = true, 0
end

-- env = { win, sel = the selected layout, vis = the Overview tab is open }
function Options.BuildLayoutOverview(pg, env)
    local sel, vis = env.sel, env.vis
    local function Repaint() AT.LayoutPage(pg) end
    local LAY = AT.LAY

    -- Size (left)
    AT.Section(pg, "Size", { visibleFn = vis, side = "L" })
    local sizeSec = pg._curSection
    Options.BuildYield()
    local scale = AT.RowSlider(pg, "Layout scale", function() return OV.Scale(sel()) end,
        function(v) OV.SetScale(sel(), v) end, OV.SCALE_MIN, OV.SCALE_MAX, 0.05, true, vis)
    AT.Tooltip(scale._colCtrl, "Layout scale",
        "Makes the whole layout bigger or smaller, growing from its center point (the cross on the map).")
    Options.BuildYield()
    local chips = {}
    for i, s in ipairs(OV.SCALE_CHIPS) do chips[i] = { value = s, text = math.floor(s * 100 + 0.5) .. "%" } end
    local chipRow = Options.ChipPickRow(pg, chips, function()
        local s = OV.Scale(sel())
        for _, c in ipairs(OV.SCALE_CHIPS) do
            if math.abs(c - s) < 0.001 then return c end
        end
        return s
    end, function(v)
        OV.SetScale(sel(), v)
        Repaint()
    end, vis, { column = true })
    Options.BuildYield()
    OV.NoteRow(pg, "Icons, bars, texts and the gaps between them grow together.", vis, "L")

    -- Mouse (left, under Size): the room beside the taller Place block
    Options.BuildYield()
    AT.Section(pg, "Mouse", { visibleFn = vis, side = "L", under = true })
    local mouseSec = pg._curSection
    Options.BuildYield()
    OV.NoteRow(pg, "Groups and icons can override these.", vis, "L")
    Options.BuildYield()
    Options.SectionRows(pg, "layout", "mouse", sel, vis, { "clickThrough", "showTooltip" })

    -- Place (right)
    Options.BuildYield()
    AT.Section(pg, "Place", { visibleFn = vis, side = "R" })
    local placeSec = pg._curSection
    Options.BuildYield()
    OV.MoveRow(pg, sel, vis, Repaint)
    Options.BuildYield()
    OV.NudgeRow(pg, sel, vis, Repaint)
    Options.BuildYield()
    local pin = AT.RowDropdown(pg, env.win, "Pinned to",
        function() return OV.Pin(sel()) end,
        function(v)
            OV.SetPin(sel(), v)
            Repaint()
        end,
        function() return OV.PINS end, vis)
    AT.Tooltip(pin._colCtrl, "Pinned to",
        "The spot on your screen the layout keeps its distance from when the resolution or UI scale changes.")
    Options.BuildYield()
    local strata = AT.RowDropdown(pg, env.win, "Frame strata",
        function() return OV.Strata(sel()) end,
        function(v) OV.SetStrata(sel(), v) end,
        OV.StrataItems, vis)
    AT.Tooltip(strata._colCtrl, "Frame strata",
        "One layer for every element of this layout, or each element's own layer moved up or down.")
    Options.BuildYield()
    Options.LockRow(pg, sel, vis)
    Options.BuildYield()
    OV.NoteRow(pg, function()
        return OV.Moving() and "Drag the layout anywhere on your screen." or "Moves every element together."
    end, vis, "R")

    -- On your screen (full width)
    Options.BuildYield()
    AT.Section(pg, "On your screen", { visibleFn = vis })
    local mapSec = pg._curSection
    Options.BuildYield()
    local _, namesBox = OV.NamesToggle(pg, mapSec, vis, Repaint)
    Options.BuildYield()
    local mapRow
    -- the page's height outside the map: the rows above, Size and Mouse | Place,
    -- this block's header and gap, the fold shut
    local function Rest()
        local function Shown(r) return (not r._visibleFn) or r._visibleFn() end
        local function BoxH(sec)
            local s = 0
            for _, r in ipairs(sec.rows) do
                if Shown(r) then s = s + (r._h or 0) end
            end
            return s + 5
        end
        local h = 4 + 8
        for _, r in ipairs(pg._rows) do
            if Shown(r) then h = h + (r._h or 0) end
        end
        local left = BoxH(sizeSec)
        if (not mouseSec.visibleFn) or mouseSec.visibleFn() then
            left = left + LAY.gap + LAY.hdr + BoxH(mouseSec)
        end
        h = h + LAY.hdr + math.max(left, BoxH(placeSec)) + LAY.gap
        local above = 0
        for _, r in ipairs(mapSec.rows) do
            if r ~= mapRow and Shown(r) then above = above + (r._h or 0) end
        end
        h = h + LAY.hdr + above + 5 + 2 * OV.MAP_PAD + LAY.gap
        return h + LAY.hdr + LAY.gap
    end
    local st
    mapRow, st = OV.MapRow(pg, env, vis, Rest)
    st.namesBox = (namesBox and namesBox.SetOn) and namesBox or nil
    mapRow._adSearch = mapSec.band and function() return { "Show names on screen" } end or nil
    -- the pools, as many as the fullest layout needs, one element a pause
    local most = 0
    for _, l in ipairs(Store.Layouts()) do most = math.max(most, #Store.MembersOf(l)) end
    for i = 1, most do
        Options.BuildYield()
        OV.Box(st, i)
        OV.ListRow(st, i)
    end
    for i = 1, 4 * OV.DASHES do
        if i % OV.DASHES == 1 then Options.BuildYield() end
        OV.Dash(st, i):Hide()
    end

    -- Anchored to this, a fold shut by default
    Options.BuildYield()
    Options.AnchoredHereRows(pg, sel, vis, { visibleFn = vis, collapsible = true })
    Shut(pg._curSection)
    OV.rows = { scale = scale, chips = chipRow, strata = strata, pin = pin, map = mapRow,
        size = sizeSec, mouse = mouseSec, place = placeSec, screen = mapSec }
end
