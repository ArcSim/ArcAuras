-- AD_LayoutOnScreen: Edit on screen. The options fold to their title bar;
-- the layout gets a dashed outline with corners that scale it from its center
-- point, each element an outline and a name tag, the point a cross that asks
-- before it moves it, and a toolbar with Undo and Redo. Element editing
-- (drags, handles, anchors, the strips) is AD_LayoutEditTools. Every exit
-- (Done, Escape, the window closing or unfolding, combat, a delete, another
-- pick, a logout, Edit) tears down, twice safe.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store, Events = NS.AT, NS.Store, NS.Events
local COL = AT.COL
local ui = Options.ui
local WHITE = AT.WHITE
local Tr = AT.Tr

local LOS = { open = false, pool = {}, more = {}, ate = {} }
Options.LayoutOnScreen = LOS

-- Sizes are the board's px as UI units: the outlines and tags in the
-- screen's units, the toolbar at the options window's scale.
local PAD, PAD_TOP = 22, 10   -- the layout outline round its elements, plus room for their tags
local OUT, OUT_ON = 3, 4      -- an element's outline: 2 off it at rest, 3 picked, 1 wide
local DASH = 3                -- a dash and the gap after it
local TAG_H = 14
local BAR_W, ROW_H = 980, 28
local SCALE_MIN, SCALE_MAX = 0.5, 2
local IDLE, IDLE_A = { 0.498, 0.659, 0.784 }, 0.55   -- an element's outline at rest
local DONE_EDGE = { 0.122, 0.431, 0.541 }
local CROSS, CROSS_HIT = 6, 9   -- the center point's arm and its grab box's half, in UI units
local PIN = 2                   -- a set center's dot reaches this far past the cross's middle
local CORNER_GRAB = 3           -- a corner's grab reaches this far past its square
local CORNER_MIN = 4            -- a press this close to the point gives no ratio to scale by
local FIT_ROOM = 32             -- chrome keeps this much of the screen's width free
local KEY = "adlayoutscreen"
local HINT = "Drag an element to move it, its handles to size it; the outline moves all, corners scale, the cross sets the center. Alt drags free."
local HINT_PICK = "Click the element to anchor to, or the cross for the center point."
local ASK = "Use this as the layout's center?"
local HINT_LOCKED = "Locked in place: no dragging. Arrows nudge by one pixel, Shift by ten."
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local UNDO_DIM = 0.4

local function Engine() return NS.LayoutEngine end

function LOS.IsOpen() return LOS.open end

-- Undo steps. One step is open at a time: a held corner, the scale track
-- and a handle drag hold theirs from press to drop; anything else is a step
-- of its own. Without the edit ops the writes still happen, unrecorded.
function LOS.Begin(owner)
    local EO = NS.EditOps
    if LOS.session or not (LOS.layoutId and EO and EO.Begin) then return false end
    -- refused in combat or under a lock: no step to hold
    if EO.Begin(LOS.layoutId) ~= true then return false end
    LOS.session = { lid = LOS.layoutId, owner = owner or true }
    return true
end

-- owner nil ends whatever step is open; true when the step was recorded
function LOS.End(owner)
    local s = LOS.session
    if not s or (owner ~= nil and s.owner ~= owner) then return false end
    LOS.session = nil
    local EO = NS.EditOps
    return EO ~= nil and EO.Commit ~= nil and EO.Commit(s.lid) == true
end

function LOS.Change(fn, ...)
    local mine = LOS.Begin("change")
    fn(...)
    if mine then LOS.End("change") end
end

-- the picked elements: the first, then the rest in the order picked
function LOS.Picked()
    local out = {}
    if LOS.selId ~= nil then out[1] = LOS.selId end
    for _, id in ipairs(LOS.more) do out[#out + 1] = id end
    return out
end

function LOS.IsPicked(id)
    if id == nil then return false end
    if id == LOS.selId then return true end
    for _, x in ipairs(LOS.more) do
        if x == id then return true end
    end
    return false
end

function LOS.SetPicks(first, rest)
    LOS.selId = first
    LOS.more = rest or {}
end

-- the element tools hold the mouse or wait for an anchor's target
local function ToolsBusy()
    local LT = LOS.Tools
    return LT ~= nil and LT.Busy ~= nil and LT.Busy() == true
end

function LOS.Layout()
    return LOS.layoutId and Store.Get(LOS.layoutId) or nil
end

-- Reads and writes

function LOS.GetPos(layout)
    if Store.LayoutPos then
        local x, y = Store.LayoutPos(layout)
        if type(x) == "table" then x, y = x.x, x.y end
        if x ~= nil or y ~= nil then return tonumber(x) or 0, tonumber(y) or 0 end
    end
    local p = layout.pos or {}
    return tonumber(p.x) or 0, tonumber(p.y) or 0
end

-- whole numbers, as the panel's Position rows save them, and only on an axis
-- whose whole number changed: an untouched one must not round a fraction a
-- pin change left
function LOS.SetPos(x, y)
    local layout = LOS.Layout()
    if not (LOS.open and layout) then return end
    local ox, oy = LOS.GetPos(layout)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local wx = (x ~= math.floor(ox + 0.5)) and x or nil
    local wy = (y ~= math.floor(oy + 0.5)) and y or nil
    if wx == nil and wy == nil then return end
    if Store.SetLayoutPos then
        Store.SetLayoutPos(layout, wx, wy)
        return
    end
    layout.pos = layout.pos or {}
    layout.pos.x, layout.pos.y = wx or ox, wy or oy
    Store.Dirty("style", layout.id)
end

function LOS.NudgeNow(dx, dy)
    local layout = LOS.Layout()
    if not layout then return end
    local x, y = LOS.GetPos(layout)
    LOS.SetPos(x + dx, y + dy)
end

function LOS.Nudge(dx, dy) LOS.Change(LOS.NudgeNow, dx, dy) end

-- The center point: where scale grows from, from the screen's middle in
-- UIParent units. Without the engine's own read it is the layout's spot.
function LOS.Point(layout)
    local E = Engine()
    if E and E.LayoutPoint then
        local x, y = E.LayoutPoint(layout.id)
        x, y = tonumber(x), tonumber(y)
        if x and y then return x, y end
    end
    return LOS.GetPos(layout)
end

-- the middle of what's shown on the screen's middle, the point with it
function LOS.CenterNow()
    local layout = LOS.Layout()
    if not (LOS.open and layout) then return end
    local E = Engine()
    if E and E.CenterLayout then
        E.CenterLayout(layout.id)
    else
        LOS.SetPos(0, 0)
    end
end

function LOS.Center() LOS.Change(LOS.CenterNow) end

function LOS.GetScale(layout)
    local v = Store.LayoutScale and tonumber(Store.LayoutScale(layout))
    return v or 1
end

-- steps of 5%, kept as twentieths so 115% never reads 114%
function LOS.StepScale(v)
    local lo, hi = Store.LAYOUT_SCALE_MIN or SCALE_MIN, Store.LAYOUT_SCALE_MAX or SCALE_MAX
    v = math.floor((tonumber(v) or 1) * 20 + 0.5) / 20
    if v < lo then v = lo elseif v > hi then v = hi end
    return v
end

function LOS.SetScale(v)
    local layout = LOS.Layout()
    if not (LOS.open and layout and Store.SetLayoutScale) then return end
    Store.SetLayoutScale(layout, LOS.StepScale(v))
end

local function Pct(v) return math.floor(v * 100 + 0.5) .. "%" end

-- the cross waiting on the prompt lets go of its spot, nothing saved
local function DropPending()
    LOS.pending = nil
    if LOS.prompt then LOS.prompt:Hide() end
end

-- the resize cursor, put back by whoever set it
local function ResizeCursor(on)
    on = on == true
    if not SetCursor or (LOS.cursorOn == true) == on then return end
    LOS.cursorOn = on
    SetCursor(on and "UI_RESIZE_CURSOR" or nil)
end

function LOS.CenterSet(layout)
    return layout ~= nil and Store.LayoutCenterSet ~= nil and Store.LayoutCenterSet(layout) == true
end

-- the Overview tab's names setting: on until turned off
function LOS.NamesOn()
    local u = Store.UI()
    return not (u and u.layoutNames == false)
end

function LOS.ToggleNames()
    local u = Store.UI()
    if u then u.layoutNames = not LOS.NamesOn() end
    LOS.Redraw()
end

-- every record in the layout, a group's members too
function LOS.Count(layout)
    local n = 0
    for _, rec in ipairs(Store.MembersOf and Store.MembersOf(layout) or {}) do
        n = n + 1
        if rec.type == "group" and Store.GroupMembers then n = n + #Store.GroupMembers(rec) end
    end
    return n
end

local function Num(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

function LOS.Rects(id)
    local E = Engine()
    local list = E and E.LayoutElementRects and E.LayoutElementRects(id)
    local out = {}
    for _, r in ipairs(type(list) == "table" and list or {}) do
        if r.id and Num(r.left) and Num(r.bottom) and Num(r.width) and Num(r.height) then
            out[#out + 1] = r
        end
    end
    return out
end

-- The engine's box for the layout, else the rects' union, else a point on the
-- layout's centre: an empty layout still gets an outline to drag.
function LOS.Bounds(id, rects, ox, oy)
    local E = Engine()
    if E and E.LayoutBounds then
        local l, b, w, h = E.LayoutBounds(id)
        if type(l) == "table" then l, b, w, h = l.left, l.bottom, l.width, l.height end
        if Num(l) and Num(b) and Num(w) and Num(h) then return l, b, w, h end
    end
    if #rects == 0 then return ox, oy, 0, 0 end
    local l, b, r, t = math.huge, math.huge, -math.huge, -math.huge
    for _, e in ipairs(rects) do
        l, b = math.min(l, e.left), math.min(b, e.bottom)
        r, t = math.max(r, e.left + e.width), math.max(t, e.bottom + e.height)
    end
    return l, b, r - l, t - b
end

-- Drawing

-- A dashed outline t pixels thick (1 when nil) on f's edges. w and h are
-- whole physical pixels, P one pixel in f's units, so every dash lands on the
-- grid. Laid again only when the size changes; a colour change only tints.
local function Dashes(f, w, h, P, col, t)
    t = t or 1
    f.dashes = f.dashes or {}
    if f._dw ~= w or f._dh ~= h or f._dp ~= P or f._dt ~= t then
        f._dw, f._dh, f._dp, f._dt = w, h, P, t
        local d = math.max(1, math.floor(DASH / P + 0.5))
        local n = 0
        local function put(x, y, dw, dh)
            n = n + 1
            local tex = f.dashes[n]
            if not tex then
                tex = f:CreateTexture(nil, "OVERLAY")
                tex:SetTexture(WHITE)
                f.dashes[n] = tex
            end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", f, "TOPLEFT", x * P, -y * P)
            tex:SetSize(dw * P, dh * P)
            tex:Show()
        end
        for x = 0, w - 1, 2 * d do
            put(x, 0, math.min(d, w - x), t)
            put(x, h - t, math.min(d, w - x), t)
        end
        for y = 0, h - 1, 2 * d do
            put(0, y, t, math.min(d, h - y))
            put(w - t, y, t, math.min(d, h - y))
        end
        for i = n + 1, #f.dashes do f.dashes[i]:Hide() end
        f._dn = n
    end
    for i = 1, f._dn do f.dashes[i]:SetVertexColor(col[1], col[2], col[3], 1) end
end

-- A solid 1-pixel outline d pixels outside f's w x h pixel box, a in alpha.
local function Ring(f, w, h, P, col, a, d)
    local W, H = w + 2 * d, h + 2 * d
    local function put(tex, x, y, tw, th)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", (x - d) * P, -(y - d) * P)
        tex:SetSize(tw * P, th * P)
        tex:SetVertexColor(col[1], col[2], col[3], a)
        tex:Show()
    end
    local r = f.ring
    put(r[1], 0, 0, W, 1)
    put(r[2], 0, H - 1, W, 1)
    put(r[3], 0, 1, 1, H - 2)
    put(r[4], W - 1, 1, 1, H - 2)
end

local function Text(parent, size, col)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetTextColor(col[1], col[2], col[3])
    return fs
end

local function Width(fs) return math.ceil(fs:GetStringWidth() or 0) end

local function Button(parent, label, h, size, onClick)
    local b = AT.MakeSmallButton(parent, label)
    b:SetHeight(h)
    b.fs:SetFont(AT.FONT, size, "")
    b:SetScript("OnClick", onClick)
    return b
end

-- the primary button: the selected fill and a teal edge, cyan on hover
local function Primary(b)
    local function Rest()
        b:SetBackdropColor(COL.sel[1], COL.sel[2], COL.sel[3], 1)
        b:SetBackdropBorderColor(DONE_EDGE[1], DONE_EDGE[2], DONE_EDGE[3], 1)
    end
    Rest()
    b:HookScript("OnLeave", Rest)
end

-- the board's small square button: a glyph or a chevron in the dim colour
local function Square(parent, glyph, onClick)
    local b = AT.MakeSmallButton(parent, glyph or "", 26)
    b:SetSize(26, 26)
    b.fs:SetFont(AT.FONT, 13, "")
    b.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    b:SetScript("OnClick", onClick)
    return b
end

-- the drawing helpers the element tools share
LOS.UI = { Dashes = Dashes, Text = Text, Width = Width, Button = Button, Primary = Primary,
    Square = Square, ResizeCursor = ResizeCursor }

-- A press on an element goes to the element tools; without them it picks.
function LOS.Press(f, button)
    local LT = LOS.Tools
    if LT and LT.Press then return LT.Press(f, button) end
    if button == "LeftButton" then LOS.Pick(f.recId) end
end

function LOS.Release(f, button)
    local LT = LOS.Tools
    if LT and LT.Release then LT.Release(f, button) end
end

-- a name tag the others crowded out shows while its element is hovered
function LOS.Hover(f, on)
    f.hover = on == true
    local tag = f.tag
    if f.tagSkip and LOS.NamesOn() then
        if on then
            tag:ClearAllPoints()
            tag:SetPoint("BOTTOMLEFT", LOS.root, "CENTER", f.tagX, f.tagY)
            tag:SetFrameLevel(f.tagLvl)
            tag:Show()
        else
            tag:Hide()
        end
    end
    local LT = LOS.Tools
    if LT and LT.Hover then LT.Hover(f, on) end
end

local function Element(i)
    local f = LOS.pool[i]
    if f then return f end
    f = CreateFrame("Frame", nil, LOS.root)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(self, button) LOS.Press(self, button) end)
    f:SetScript("OnMouseUp", function(self, button) LOS.Release(self, button) end)
    f:SetScript("OnEnter", function(self) LOS.Hover(self, true) end)
    f:SetScript("OnLeave", function(self) LOS.Hover(self, false) end)
    f.ring = {}
    for k = 1, 4 do
        f.ring[k] = f:CreateTexture(nil, "OVERLAY")
        f.ring[k]:SetTexture(WHITE)
    end
    -- a shown name tag takes a press as its element does; the redraw turns
    -- its mouse on only while it shows in a spot of its own
    local tag = CreateFrame("Frame", nil, LOS.root)
    tag.bg = tag:CreateTexture(nil, "BACKGROUND")
    tag.bg:SetAllPoints()
    tag.bg:SetColorTexture(COL.bg[1], COL.bg[2], COL.bg[3], 0.85)
    tag.fs = Text(tag, 11, COL.word)
    tag.fs:SetPoint("LEFT", 5, 0)
    tag:EnableMouse(false)
    tag:SetScript("OnMouseDown", function(_, button) LOS.Press(f, button) end)
    tag:SetScript("OnMouseUp", function(_, button) LOS.Release(f, button) end)
    tag:SetScript("OnEnter", function()
        local LT = LOS.Tools
        if LT and LT.Hover then LT.Hover(f, true) end
    end)
    tag:SetScript("OnLeave", function()
        local LT = LOS.Tools
        if LT and LT.Hover then LT.Hover(f, false) end
    end)
    f.tag = tag
    LOS.pool[i] = f
    return f
end

function LOS.BuildHUD()
    if LOS.root then return end
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(1, 1)
    root:SetFrameStrata("DIALOG")
    root:SetFrameLevel(10)
    root:Hide()
    LOS.root = root

    -- The layout's outline: its fill and edge, and the drag handle.
    local bf = CreateFrame("Frame", nil, root)
    bf.fill = bf:CreateTexture(nil, "BACKGROUND")
    bf.fill:SetAllPoints()
    bf.fill:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.05)
    bf:EnableMouse(true)
    bf:RegisterForDrag("LeftButton")
    bf:SetScript("OnDragStart", function()
        LOS.dragSeq = (LOS.dragSeq or 0) + 1
        LOS.DragStart()
    end)
    bf:SetScript("OnDragStop", function() LOS.DragStop() end)
    -- a click on its empty space is the screen's background: it lets go of
    -- the picks; one that became a drag does not
    bf:SetScript("OnMouseDown", function() LOS.bgSeq = LOS.dragSeq end)
    bf:SetScript("OnMouseUp", function(_, button)
        local LT = LOS.Tools
        if button == "LeftButton" and LOS.bgSeq == LOS.dragSeq and LT and LT.Background then LT.Background() end
        LOS.bgSeq = nil
    end)
    LOS.bounds = bf

    -- The corner squares scale the layout from its center point; each grabs a
    -- little past its square so it is easy to hit.
    LOS.corners = {}
    for i = 1, 4 do
        local c = CreateFrame("Frame", nil, root)
        c.edge = c:CreateTexture(nil, "BACKGROUND")
        c.edge:SetAllPoints()
        c.edge:SetColorTexture(COL.bg[1], COL.bg[2], COL.bg[3], 1)
        c.inner = c:CreateTexture(nil, "ARTWORK")
        c.inner:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        c.left = (i == 1 or i == 3)
        c:EnableMouse(true)
        c:RegisterForDrag("LeftButton")
        c:SetHitRectInsets(-CORNER_GRAB, -CORNER_GRAB, -CORNER_GRAB, -CORNER_GRAB)
        c:SetScript("OnDragStart", function(self) LOS.CornerDragStart(self) end)
        c:SetScript("OnDragStop", function() LOS.CornerDragStop() end)
        c:SetScript("OnEnter", function() if LOS.CanResize() then ResizeCursor(true) end end)
        c:SetScript("OnLeave", function() if not LOS.corner then ResizeCursor(false) end end)
        LOS.corners[i] = c
    end

    -- the scale a corner drag is at, off the outline's bottom right
    local rd = CreateFrame("Frame", nil, root)
    AT.Skin(rd, COL.bg, COL.arc)
    rd:SetClampedToScreen(true)
    rd.fs = Text(rd, 11, COL.ink)
    rd.fs:SetPoint("CENTER")
    rd:Hide()
    LOS.readout = rd

    local lt = CreateFrame("Frame", nil, root)
    AT.Skin(lt, COL.sel, COL.arc)
    lt.fs = Text(lt, 12, COL.ink)
    lt.fs:SetPoint("LEFT", 9, 0)
    LOS.layoutTag = lt

    -- The center point: a cyan cross on a dark edge in a grab box of its
    -- own, so it drags alone where it sits over an element.
    local mk = CreateFrame("Frame", nil, root)
    mk:EnableMouse(true)
    mk:SetMovable(true)
    mk:SetClampedToScreen(true)
    mk:RegisterForDrag("LeftButton")
    mk:SetScript("OnDragStart", function() LOS.PointDragStart() end)
    mk:SetScript("OnDragStop", function() LOS.PointDragStop() end)
    -- waiting for an anchor's target, a press on the cross picks the point
    -- and the drag that may follow it is eaten
    mk:SetScript("OnMouseDown", function(_, button)
        local LT = LOS.Tools
        if button == "LeftButton" and LT and LT.pickFor ~= nil and LT.PickTarget then
            LOS.pressAte = true
            LT.PickTarget("point")
        end
    end)
    mk:SetScript("OnMouseUp", function() LOS.pressAte = nil end)
    mk:SetScript("OnEnter", function()
        local LT = LOS.Tools
        if LT and LT.HoverPoint then LT.HoverPoint(true) end
    end)
    mk:SetScript("OnLeave", function()
        local LT = LOS.Tools
        if LT and LT.HoverPoint then LT.HoverPoint(false) end
    end)
    mk.halo, mk.bar = {}, {}
    for i = 1, 2 do
        mk.halo[i] = mk:CreateTexture(nil, "BACKGROUND")
        mk.halo[i]:SetColorTexture(COL.bg[1], COL.bg[2], COL.bg[3], 0.9)
        mk.bar[i] = mk:CreateTexture(nil, "ARTWORK")
        mk.bar[i]:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    end
    -- a set center: a filled dot on the middle, over the bars
    mk.dotHalo = mk:CreateTexture(nil, "BACKGROUND", nil, 1)
    mk.dotHalo:SetColorTexture(COL.bg[1], COL.bg[2], COL.bg[3], 0.9)
    mk.dot = mk:CreateTexture(nil, "ARTWORK", nil, 1)
    mk.dot:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    mk:Hide()
    LOS.marker = mk

    -- A dropped cross asks before it becomes the center.
    local pr = CreateFrame("Frame", nil, root)
    AT.Skin(pr, COL.bg, COL.arc)
    pr:EnableMouse(true)
    pr:SetClampedToScreen(true)
    pr.fs = Text(pr, 12, COL.ink)
    pr.fs:SetText(Tr(ASK))
    pr.use = Button(pr, "Use as center", 22, 12, function() LOS.UseCenter() end)
    Primary(pr.use)
    -- the board's quiet button: the answer that changes nothing
    pr.back = (AT.MakeQuietButton or AT.MakeSmallButton)(pr, "Put it back")
    pr.back:SetHeight(22)
    pr.back.fs:SetFont(AT.FONT, 12, "")
    pr.back:SetScript("OnClick", function() LOS.PutBack() end)
    pr:Hide()
    LOS.prompt = pr
end

function LOS.BuildToolbar()
    if LOS.toolbar then return end
    local tb = CreateFrame("Frame", nil, UIParent)
    tb:SetFrameStrata("FULLSCREEN_DIALOG")
    tb:SetSize(BAR_W, 84)
    tb:EnableMouse(true)
    AT.Skin(tb, COL.bg, COL.arc)
    tb:Hide()
    LOS.toolbar = tb
    local r1, r2 = -25, -59   -- each row's middle: 1 edge + 10 padding + 28 rows 6 apart

    -- row 1: the mode's label, the name and count on the left, Scale on the right
    tb.mode = Text(tb, 12, COL.arc)
    -- capitals only for plain Latin words
    local mode = Tr("Edit on screen")
    tb.mode:SetText(mode:find("[\128-\255]") and mode or mode:upper())
    tb.mode:SetPoint("LEFT", tb, "TOPLEFT", 15, r1)
    -- the layout being edited, a pick of every layout drawn here; its pullout
    -- hangs off the toolbar, so it draws over it at its strata
    if AT.MakeDropdown then
        tb.pick = AT.MakeDropdown(tb, tb, nil, LOS.LayoutItems, function() return LOS.layoutId end,
            function(v) LOS.Switch(v) end)
        tb.pick:SetHeight(26)
        tb.pick:SetPoint("LEFT", tb.mode, "RIGHT", 10, 0)
    else
        tb.name = Text(tb, 16, COL.ink)
        tb.name:SetPoint("LEFT", tb.mode, "RIGHT", 10, 0)
    end
    local pill = CreateFrame("Frame", nil, tb)
    AT.Skin(pill, { 0, 0, 0, 0 }, COL.line2)
    pill:SetHeight(16)
    pill:SetPoint("LEFT", tb.pick or tb.name, "RIGHT", 10, 0)
    pill.fs = Text(pill, 12, COL.dim)
    pill.fs:SetPoint("CENTER")
    tb.count = pill

    -- the layout's X and Y at the row's right end, then 100% and the scale
    tb.yBox = LOS.NumBox(tb, "y")
    tb.yBox:SetPoint("RIGHT", tb, "TOPRIGHT", -15, r1)
    tb.yLbl = Text(tb, 14, COL.dim)
    tb.yLbl:SetText("Y")
    tb.yLbl:SetPoint("RIGHT", tb.yBox, "LEFT", -8, 0)
    tb.xBox = LOS.NumBox(tb, "x")
    tb.xBox:SetPoint("RIGHT", tb.yLbl, "LEFT", -10, 0)
    tb.xLbl = Text(tb, 14, COL.dim)
    tb.xLbl:SetText("X")
    tb.xLbl:SetPoint("RIGHT", tb.xBox, "LEFT", -8, 0)
    tb.reset = Button(tb, "100%", 26, 13, function() LOS.Change(LOS.SetScale, 1) end)
    tb.reset:SetPoint("RIGHT", tb.xLbl, "LEFT", -10, 0)
    tb.plus = Square(tb, "+", function()
        local layout = LOS.Layout()
        if layout then LOS.Change(LOS.SetScale, LOS.GetScale(layout) + 0.05) end
    end)
    tb.plus:SetPoint("RIGHT", tb.reset, "LEFT", -10, 0)
    local val = CreateFrame("Frame", nil, tb)
    AT.Skin(val, COL.well, COL.line2)
    val:SetSize(54, 26)
    val:SetPoint("RIGHT", tb.plus, "LEFT", -10, 0)
    tb.scaleText = Text(val, 14, COL.ink)
    tb.scaleText:SetPoint("CENTER")
    tb.minus = Square(tb, "-", function()
        local layout = LOS.Layout()
        if layout then LOS.Change(LOS.SetScale, LOS.GetScale(layout) - 0.05) end
    end)
    tb.minus:SetPoint("RIGHT", val, "LEFT", -10, 0)

    -- the board's track: a fill from the left, no knob
    local s = CreateFrame("Slider", nil, tb)
    AT.Skin(s, COL.well, COL.line2)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(140, 8)
    s:SetPoint("RIGHT", tb.minus, "LEFT", -10, 0)
    s:SetThumbTexture(WHITE)
    local th = s:GetThumbTexture()
    th:SetSize(8, 8)
    th:SetVertexColor(0, 0, 0, 0)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetTexture(WHITE)
    s.fill:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    s.fill:SetPoint("TOPLEFT", 1, -1)
    s.fill:SetHeight(6)
    s:SetMinMaxValues(SCALE_MIN, SCALE_MAX)
    s:SetValueStep(0.05)
    s:SetObeyStepOnDrag(true)
    -- the layout rescales at most every AT.SLIDER_DRAG_EVERY while dragged
    local write = AT.SliderDrag(s, function(v) LOS.Change(LOS.SetScale, v) end)
    s:SetScript("OnValueChanged", function(_, v)
        LOS.Fill(v)
        if tb.settingUp then return end
        write(v)
    end)
    -- a slide is one undo step from press to release; hooked after the drag's
    -- own, so its last write lands inside the step
    s:HookScript("OnMouseDown", function() LOS.Begin("track") end)
    s:HookScript("OnMouseUp", function() LOS.End("track") end)
    tb.slider = s
    tb.scaleLbl = Text(tb, 14, COL.dim)
    tb.scaleLbl:SetText(Tr("Scale"))
    tb.scaleLbl:SetPoint("RIGHT", s, "LEFT", -10, 0)

    -- row 2: the hint on the left; Undo, Redo, a rule, Center, names, Done
    tb.hint = Text(tb, 13, COL.faint)
    tb.hint:SetPoint("LEFT", tb, "TOPLEFT", 15, r2)
    tb.done = Button(tb, "Done", ROW_H, 14, function() LOS.Close() end)
    tb.done:SetPoint("RIGHT", tb, "TOPRIGHT", -15, r2)
    Primary(tb.done)
    tb.names = Button(tb, "Hide names", ROW_H, 14, function() LOS.ToggleNames() end)
    tb.names:SetPoint("RIGHT", tb.done, "LEFT", -8, 0)
    tb.center = Button(tb, "Center", ROW_H, 14, function() LOS.Center() end)
    tb.center:SetPoint("RIGHT", tb.names, "LEFT", -8, 0)
    tb.rule = tb:CreateTexture(nil, "ARTWORK")
    tb.rule:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    tb.rule:SetPoint("RIGHT", tb.center, "LEFT", -8, 0)
    tb.redo = Button(tb, "Redo", ROW_H, 14, function() LOS.Redo() end)
    tb.redo:SetPoint("RIGHT", tb.rule, "LEFT", -8, 0)
    tb.undo = Button(tb, "Undo", ROW_H, 14, function() LOS.Undo() end)
    tb.undo:SetPoint("RIGHT", tb.redo, "LEFT", -8, 0)
    if AT.Tooltip then
        AT.Tooltip(tb.undo, "Undo", "Ctrl+Z")
        AT.Tooltip(tb.redo, "Redo", "Ctrl+Y")
    end

    -- The mode's keys are kept from the game; every other key goes on to it.
    -- The switch is restricted in combat, which ends the mode anyway.
    tb:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not LOS.Key(key))
    end)
    -- a key held from before (a movement key) must reach the game on release
    tb:SetScript("OnKeyUp", function(self, key)
        if InCombatLockdown() then return end
        local ate = LOS.ate[key]
        LOS.ate[key] = nil
        self:SetPropagateKeyboardInput(not (ARROWS[key] or key == "ESCAPE" or ate))
    end)
end

-- One key: true when the mode used it. Ctrl+Z undoes, Ctrl+Y or
-- Ctrl+Shift+Z redoes; arrows nudge the picks, else the layout (Shift 10);
-- Escape steps back one thing.
function LOS.Key(key)
    if IsControlKeyDown and IsControlKeyDown() and (key == "Z" or key == "Y") then
        LOS.ate[key] = true
        if key == "Y" or IsShiftKeyDown() then LOS.Redo() else LOS.Undo() end
        return true
    end
    local a = ARROWS[key]
    if a then
        local step = IsShiftKeyDown() and 10 or 1
        local LT = LOS.Tools
        if not (LT and LT.NudgePicked and LT.NudgePicked(a[1] * step, a[2] * step)) then
            LOS.Nudge(a[1] * step, a[2] * step)
        end
        return true
    end
    if key == "ESCAPE" then
        LOS.Escape()
        return true
    end
    return false
end

-- A waiting cross goes back, then a drag, an anchor pick or the picks let
-- go; with none of them Escape ends the mode.
function LOS.Escape()
    if LOS.pending then return LOS.PutBack() end
    local LT = LOS.Tools
    if LT and LT.Escape and LT.Escape() then return end
    LOS.Close()
end

-- Undo and Redo: never mid-drag or with a step open. A waiting cross goes
-- back and an anchor pick ends, as the board does.
function LOS.Step(which)
    local EO = NS.EditOps
    if not (LOS.open and LOS.layoutId and EO and EO[which]) or InCombatLockdown() then return end
    local LT = LOS.Tools
    if LOS.session or LOS.dragging or LOS.pointDrag or LOS.corner or (LT and LT.drag) then return end
    DropPending()
    if LT and LT.CancelPick then LT.CancelPick() end
    EO[which](LOS.layoutId)
    LOS.Redraw()
end

function LOS.Undo() LOS.Step("Undo") end
function LOS.Redo() LOS.Step("Redo") end

function LOS.CanStep(which)
    local EO = NS.EditOps
    return LOS.layoutId ~= nil and EO ~= nil and EO[which] ~= nil and EO[which](LOS.layoutId) == true
end

-- Chrome is the options window's size, smaller only when the screen is
-- too narrow for it.
function LOS.ChromeScale(w)
    local Fold = Options.Fold
    local s = (Fold and Fold.win and Fold.win:GetScale()) or 1
    local room = UIParent:GetWidth() or 0
    if room > FIT_ROOM and w and w > 0 and w * s > room - FIT_ROOM then s = (room - FIT_ROOM) / w end
    return s
end

-- The layout's X or Y: Enter or a click away saves a typed whole number,
-- held in the panel's range, as one undo step and only when it changed.
-- Escape puts it back; an exit saves nothing (the mode is shut first).
function LOS.NumBox(parent, axis)
    local box = CreateFrame("EditBox", nil, parent)
    AT.Skin(box, COL.well, COL.line2)
    box:SetSize(54, 26)
    box:SetFont(AT.FONT, 14, "")
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetJustifyH("CENTER")
    box:SetTextInsets(4, 4, 0, 0)
    box:SetAutoFocus(false)
    local function Shown()
        local layout = LOS.Layout()
        if not layout then return end
        local x, y = LOS.GetPos(layout)
        box:SetText(tostring(math.floor((axis == "x" and x or y) + 0.5)))
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        self._revert = true
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
        local n = tonumber(self:GetText())
        local layout = LOS.Layout()
        if LOS.open and layout and n and not self._revert then
            local OV = Options.LayoutOverview
            local lim = (OV and OV.POS_MAX) or 2000
            n = math.max(-lim, math.min(lim, math.floor(n + 0.5)))
            local x, y = LOS.GetPos(layout)
            x, y = math.floor(x + 0.5), math.floor(y + 0.5)
            if axis == "x" and n ~= x then
                LOS.Change(LOS.SetPos, n, y)
            elseif axis == "y" and n ~= y then
                LOS.Change(LOS.SetPos, x, n)
            end
        end
        self._revert = nil
        Shown()
    end)
    if AT.Tooltip then
        AT.Tooltip(box, axis == "x" and "X" or "Y", "The layout's distance from the spot it's pinned to, in whole units.")
    end
    return box
end

-- a box being typed in lets go and keeps what was saved
function LOS.DropBoxes()
    local tb = LOS.toolbar
    if not tb then return end
    for _, box in ipairs({ tb.xBox, tb.yBox }) do
        if box:HasFocus() then
            box._revert = true
            box:ClearFocus()
        end
    end
end

function LOS.Fill(v)
    local s = LOS.toolbar and LOS.toolbar.slider
    if not s then return end
    local w = math.floor(((tonumber(v) or 1) - SCALE_MIN) / (SCALE_MAX - SCALE_MIN) * 138 + 0.5)
    if w < 1 then
        s.fill:Hide()
    else
        s.fill:SetWidth(math.min(w, 138))
        s.fill:Show()
    end
end

-- The widest of fs's words, its own words put back.
local function Widest(fs, words)
    local keep, w = fs:GetText(), 0
    for _, s in ipairs(words) do
        fs:SetText(Tr(s))
        w = math.max(w, Width(fs))
    end
    fs:SetText(keep)
    return w
end

-- Widths follow the words; the bar keeps the board's 980 unless the game font
-- needs more, and sits on the pixel grid at the top. The hint's row is as
-- wide as its longest words, so the bar never changes width with them.
function LOS.LayoutToolbar()
    local tb = LOS.toolbar
    tb.count:SetWidth(Width(tb.count.fs) + 14)
    tb.reset:SetWidth(Width(tb.reset.fs) + 22)
    tb.center:SetWidth(Width(tb.center.fs) + 30)
    tb.done:SetWidth(Width(tb.done.fs) + 30)
    tb.undo:SetWidth(Width(tb.undo.fs) + 30)
    tb.redo:SetWidth(Width(tb.redo.fs) + 30)
    -- one width for both words, so the buttons beside it never shift
    local nw = Widest(tb.names.fs, { "Hide names", "Show names" }) + 30
    tb.names:SetWidth(nw)
    local hw = Widest(tb.hint, { HINT, HINT_PICK, HINT_LOCKED })
    local nameW = tb.pick and tb.pick:GetWidth() or Width(tb.name)
    local row1 = 15 + Width(tb.mode) + 10 + nameW + 10 + tb.count:GetWidth() + 20 + Width(tb.scaleLbl)
        + 10 + 140 + 10 + 26 + 10 + 54 + 10 + 26 + 10 + tb.reset:GetWidth()
        + 10 + Width(tb.xLbl) + 8 + 54 + 10 + Width(tb.yLbl) + 8 + 54 + 15
    local row2 = 15 + hw + 16 + tb.undo:GetWidth() + 8 + tb.redo:GetWidth() + 8 + 1 + 8
        + tb.center:GetWidth() + 8 + nw + 8 + tb.done:GetWidth() + 15
    local w = math.max(BAR_W, row1, row2)
    local s = LOS.ChromeScale(w)
    if tb._w == w and tb._s == s then return end
    tb._w, tb._s = w, s
    tb:SetScale(s)
    -- a hairline at the bar's own scale, so it never falls between pixels
    tb.rule:SetSize((AT.Hairline or AT.Px)(tb), 20)
    tb:SetSize(w, 84)
    tb:ClearAllPoints()
    tb:SetPoint("TOP", UIParent, "TOP", 0, -16)
    AT.SnapWindow(tb)
end

function LOS.SyncToolbar(layout)
    local tb = LOS.toolbar
    if tb.pick then tb.pick.Refresh() else tb.name:SetText(layout.name or "") end
    tb.count.fs:SetText(Tr("%s elements"):format(LOS.Count(layout)))
    local v = LOS.GetScale(layout)
    tb.scaleText:SetText(Pct(v))
    tb.settingUp = true
    tb.slider:SetValue(v)
    tb.settingUp = false
    LOS.Fill(v)
    local x, y = LOS.GetPos(layout)
    if not tb.xBox:HasFocus() then tb.xBox:SetText(tostring(math.floor(x + 0.5))) end
    if not tb.yBox:HasFocus() then tb.yBox:SetText(tostring(math.floor(y + 0.5))) end
    tb.names.fs:SetText(Tr(LOS.NamesOn() and "Hide names" or "Show names"))
    local LT = LOS.Tools
    local hint = HINT
    if LT and LT.pickFor ~= nil then
        hint = HINT_PICK
    elseif Store.Locked(layout) then
        hint = HINT_LOCKED
    end
    tb.hint:SetText(Tr(hint))
    tb.undo:SetAlpha(LOS.CanStep("CanUndo") and 1 or UNDO_DIM)
    tb.redo:SetAlpha(LOS.CanStep("CanRedo") and 1 or UNDO_DIM)
    LOS.LayoutToolbar()
end

-- The cross round the point (mx, my) in root units: whole pixels, t thick,
-- the dark edge one pixel round each bar, the box as the grab area. (ox, oy)
-- is the root's centre, which every offset counts from. pinned: a set
-- center, a filled dot on the middle.
function LOS.PlaceMarker(mx, my, P, ox, oy, pinned)
    local function S(v) return math.floor(v / P + 0.5) end
    local t = math.max(1, S(1))
    local a = S(CROSS)
    local hh = math.max(S(CROSS_HIT), a + 1)
    local c0 = math.floor(mx / P - t / 2 + 0.5)
    local r0 = math.floor(my / P - t / 2 + 0.5)
    local n = 2 * hh + t
    local mk = LOS.marker
    LOS.markX = mx
    mk:ClearAllPoints()
    mk:SetPoint("TOPLEFT", LOS.root, "CENTER", (c0 - hh) * P - ox, (r0 + hh + t) * P - oy)
    mk:SetSize(n * P, n * P)
    local function Put(tex, x, y, w, h)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", mk, "TOPLEFT", x * P, -y * P)
        tex:SetSize(w * P, h * P)
    end
    Put(mk.bar[1], hh - a, hh, 2 * a + t, t)
    Put(mk.bar[2], hh, hh - a, t, 2 * a + t)
    Put(mk.halo[1], hh - a - 1, hh - 1, 2 * a + t + 2, t + 2)
    Put(mk.halo[2], hh - 1, hh - a - 1, t + 2, 2 * a + t + 2)
    if pinned then
        local d = math.max(1, math.min(S(PIN), a - 1))
        Put(mk.dot, hh - d, hh - d, t + 2 * d, t + 2 * d)
        Put(mk.dotHalo, hh - d - 1, hh - d - 1, t + 2 * d + 2, t + 2 * d + 2)
        mk.dot:Show()
        mk.dotHalo:Show()
    else
        mk.dot:Hide()
        mk.dotHalo:Hide()
    end
end

-- The prompt beside the waiting cross, on the side the screen has room for.
-- The cross is on whole pixels, so whole-pixel offsets and sizes keep every
-- edge of the prompt and its buttons on them too.
function LOS.PlacePrompt(P, base)
    local pr, mk = LOS.prompt, LOS.marker
    local function S(v) return math.floor(v / P + 0.5) end
    local ph, bh = S(32), S(22)
    local by = math.floor((ph - bh) / 2)
    local ux = S(9 + Width(pr.fs) + 10)
    local uw, bw = S(Width(pr.use.fs) + 22), S(Width(pr.back.fs) + 22)
    local bx = ux + uw + S(6)
    local pw = bx + bw + S(9)
    pr.fs:ClearAllPoints()
    pr.fs:SetPoint("LEFT", pr, "LEFT", S(9) * P, 0)
    pr.use:ClearAllPoints()
    pr.use:SetPoint("TOPLEFT", pr, "TOPLEFT", ux * P, -by * P)
    pr.use:SetSize(uw * P, bh * P)
    pr.back:ClearAllPoints()
    pr.back:SetPoint("TOPLEFT", pr, "TOPLEFT", bx * P, -by * P)
    pr.back:SetSize(bw * P, bh * P)
    local n = S(mk:GetHeight() or 0)
    local dy, gap = math.floor((ph - n) / 2), S(6)
    local room = UIParent:GetWidth() or 0
    pr:ClearAllPoints()
    if room > 0 and (LOS.markX or 0) + (n / 2 + gap + pw) * P > room then
        pr:SetPoint("TOPRIGHT", mk, "TOPLEFT", -gap * P, dy * P)
    else
        pr:SetPoint("TOPLEFT", mk, "TOPRIGHT", gap * P, dy * P)
    end
    pr:SetSize(pw * P, ph * P)
    pr:SetFrameLevel(base + 25)
    pr:Show()
end

-- The corner drag's scale off the outline's bottom right, as the board has
-- it, on whole pixels off the outline's; one width for every value, so it
-- never jumps.
function LOS.PlaceReadout(P)
    local cd, rd = LOS.corner, LOS.readout
    if not (cd and rd and LOS.root) then return end
    local function S(v) return math.floor(v / P + 0.5) end
    rd.fs:SetText("200%")
    local rw, rh = S(Width(rd.fs) + 12), S(18)
    rd.fs:SetText(Pct(cd.last))
    rd:ClearAllPoints()
    rd:SetPoint("TOPLEFT", LOS.bounds, "BOTTOMRIGHT", S(10) * P, -S(6) * P)
    rd:SetSize(rw * P, rh * P)
    rd:SetFrameLevel(LOS.root:GetFrameLevel() + 25)
    rd:Show()
end

function LOS.Redraw()
    if not LOS.open then return end
    local layout = LOS.Layout()
    -- deleted, or no longer drawn here: the mode ends
    if not layout then return LOS.Close() end
    local E = Engine()
    local box = E and E.GetLayoutFrame and E.GetLayoutFrame(layout.id)
    if box and not box:IsShown() then return LOS.Close() end
    local origin = box or UIParent
    local root = LOS.root
    -- Everything hangs off the layout's centre, so a drag of the layout
    -- carries the outlines along with no per-frame work.
    root:ClearAllPoints()
    root:SetPoint("CENTER", origin, "CENTER", 0, 0)
    local ox, oy = origin:GetCenter()
    local k = (origin:GetEffectiveScale() or 1) / (root:GetEffectiveScale() or 1)
    ox, oy = (ox or 0) * k, (oy or 0) * k
    local P = AT.Px(root)
    local function S(v) return math.floor(v / P + 0.5) end
    local base = root:GetFrameLevel()

    local rects = LOS.Rects(layout.id)
    local l, b, w, h = LOS.Bounds(layout.id, rects, ox, oy)
    local bl, bb = S(l - PAD), S(b - PAD)
    local br, bt = S(l + w + PAD), S(b + h + PAD + PAD_TOP)
    local bf = LOS.bounds
    bf:ClearAllPoints()
    bf:SetPoint("TOPLEFT", root, "CENTER", bl * P - ox, bt * P - oy)
    bf:SetSize((br - bl) * P, (bt - bb) * P)
    bf:SetFrameLevel(base + 1)
    Dashes(bf, br - bl, bt - bb, P, COL.arc)
    -- the corner squares: 9 cyan inside a 1 dark edge, on each corner
    local cs = S(11)
    for i, c in ipairs(LOS.corners) do
        local cx = (i == 1 or i == 3) and (bl - S(5)) or (br - S(4))
        local cy = (i <= 2) and (bt + S(5)) or (bb + S(4))
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", root, "CENTER", cx * P - ox, cy * P - oy)
        c:SetSize(cs * P, cs * P)
        c:SetFrameLevel(base + 6)
        c.inner:ClearAllPoints()
        c.inner:SetPoint("TOPLEFT", P, -P)
        c.inner:SetPoint("BOTTOMRIGHT", -P, P)
    end
    local lt = LOS.layoutTag
    lt.fs:SetText((layout.name or "") .. "  " .. Pct(LOS.GetScale(layout)))
    lt:ClearAllPoints()
    lt:SetPoint("BOTTOMLEFT", root, "CENTER", bl * P - ox, (bt + S(4)) * P - oy)
    lt:SetSize(S(Width(lt.fs) + 18) * P, S(18) * P)
    lt:SetFrameLevel(base + 10)
    -- the center point is the container's centre; a cross being dragged
    -- stays under the cursor, one waiting on the prompt where it was dropped
    local mk = LOS.marker
    if not LOS.pointDrag then
        local mx, my = ox, oy
        local p = LOS.pending
        if p then
            local ux, uy = UIParent:GetCenter()
            local ku = (UIParent:GetEffectiveScale() or 1) / (root:GetEffectiveScale() or 1)
            mx, my = (ux or 0) * ku + p.x, (uy or 0) * ku + p.y
        elseif not box then
            local px, py = LOS.Point(layout)
            mx, my = ox + px, oy + py
        end
        LOS.PlaceMarker(mx, my, P, ox, oy, not p and LOS.CenterSet(layout))
    end
    mk:SetFrameLevel(base + 15)
    mk:Show()
    if LOS.pending then LOS.PlacePrompt(P, base) else LOS.prompt:Hide() end
    LOS.PlaceReadout(P)

    -- a picked element that left the layout lets go
    local byId, frames = {}, {}
    for _, r in ipairs(rects) do byId[r.id] = r end
    local keep = {}
    for _, id in ipairs(LOS.Picked()) do
        if byId[id] then keep[#keep + 1] = id end
    end
    local rest = {}
    for i = 2, #keep do rest[#rest + 1] = keep[i] end
    LOS.SetPicks(keep[1], rest)

    -- The outline: solid, 2 off the element at rest, 3 off in cyan picked.
    -- The frame (the press area) is the resting outline's box.
    local names = LOS.NamesOn()
    local o, on4 = S(OUT), S(OUT_ON)
    for i, r in ipairs(rects) do
        local f = Element(i)
        local el, eb = S(r.left) - o, S(r.bottom) - o
        local ew, eh = S(r.left + r.width) + o - el, S(r.bottom + r.height) + o - eb
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", root, "CENTER", el * P - ox, eb * P - oy)
        f:SetSize(ew * P, eh * P)
        f:SetFrameLevel(base + 5)
        f.recId, f.recName, f.recKind = r.id, r.name, r.kind
        f.px = { el, eb, ew, eh }
        frames[r.id] = f
        local on = LOS.IsPicked(r.id)
        if on then
            Ring(f, ew, eh, P, COL.arc, 1, on4 - o)
        else
            Ring(f, ew, eh, P, IDLE, IDLE_A, 0)
        end
        f:Show()
        local c = on and COL.arc or COL.word
        f.tag.fs:SetText(r.name or "")
        f.tag.fs:SetTextColor(c[1], c[2], c[3])
    end
    for i = #rects + 1, #LOS.pool do
        LOS.pool[i]:Hide()
        LOS.pool[i].tag:Hide()
        LOS.pool[i].tag:EnableMouse(false)
    end

    -- Name tags: above the element, else below it, else hidden with the name
    -- shown on hover, so no two overlap. The picked ones claim their spots first.
    local order, placed = {}, {}
    for _, id in ipairs(LOS.Picked()) do order[#order + 1] = frames[id] end
    for i = 1, #rects do
        local f = LOS.pool[i]
        if not LOS.IsPicked(f.recId) then order[#order + 1] = f end
    end
    local function Clear(x, y, tw, th)
        for _, q in ipairs(placed) do
            if x < q[1] + q[3] and q[1] < x + tw and y < q[2] + q[4] and q[2] < y + th then return false end
        end
        return true
    end
    local th = S(TAG_H)
    for _, f in ipairs(order) do
        local tag, px = f.tag, f.px
        local tw = S(Width(tag.fs) + 10)
        local x, up, down = px[1] + o, px[2] + px[4], px[2] - th
        tag:SetSize(tw * P, th * P)
        f.tagX, f.tagY, f.tagLvl = x * P - ox, up * P - oy, base + 11
        local y
        if Clear(x, up, tw, th) then
            y = up
        elseif Clear(x, down, tw, th) then
            y = down
        end
        f.tagSkip = (y == nil)
        tag:ClearAllPoints()
        if y then
            placed[#placed + 1] = { x, y, tw, th }
            tag:SetPoint("BOTTOMLEFT", root, "CENTER", x * P - ox, y * P - oy)
            tag:SetFrameLevel(base + 10)
            tag:SetShown(names)
        else
            tag:SetPoint("BOTTOMLEFT", root, "CENTER", f.tagX, f.tagY)
            tag:SetFrameLevel(f.tagLvl)
            tag:SetShown(names and f.hover == true)
        end
        tag:EnableMouse(names and y ~= nil)
    end

    local LT = LOS.Tools
    if LT and LT.Draw then
        LT.Draw({ layout = layout, P = P, ox = ox, oy = oy, base = base, rects = rects, byId = byId,
            frames = frames })
    end
    LOS.SyncToolbar(layout)
end

-- Picks and edits

-- picks one element alone
function LOS.Pick(id)
    if not LOS.open then return end
    LOS.SetPicks(id, {})
    LOS.Redraw()
end

-- Edit ends the mode first, so the editor opens on the unfolded window, then
-- takes the sidebar's own path for the record.
function LOS.Edit(id)
    local rec = id and Store.Get(id)
    LOS.Close()
    if not rec then return end
    if rec.type == "group" then
        ui.grpMode = "grp"
        Options.Select("group", rec.id)
    elseif Options.SelectIconHome then
        Options.SelectIconHome(rec)
    end
end

-- The drag

-- The drag moves the engine's own layout frame, so the elements and the
-- outlines move live. The drop saves the move as a whole-number offset from
-- where it started, one undo step. Lock in place holds on screen; the
-- arrows still move it. No drag while the element tools are busy.
function LOS.DragStart()
    local layout = LOS.Layout()
    local E = Engine()
    local box = E and E.GetLayoutFrame and E.GetLayoutFrame(LOS.layoutId)
    if not (LOS.open and layout and box) or LOS.dragging or LOS.pointDrag or LOS.corner or InCombatLockdown()
        or ToolsBusy() then
        return
    end
    if Store.Locked(layout) then return end
    -- another drag answers a waiting cross with Put it back
    LOS.PutBack()
    if not LOS.open then return end
    LOS.dragX, LOS.dragY = box:GetCenter()
    box:StartMoving()
    LOS.dragging = box
    if NS.Pins then NS.Pins.DragStart() end
end

function LOS.DragStop()
    local box = LOS.dragging
    if not box then return end
    LOS.dragging = nil
    box:StopMovingOrSizing()
    if NS.Pins then NS.Pins.DragStop() end
    local x1, y1 = box:GetCenter()
    local layout = LOS.Layout()
    if layout and LOS.dragX and x1 then
        local k = (box:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local x, y = LOS.GetPos(layout)
        LOS.Change(LOS.SetPos, x + (x1 - LOS.dragX) * k, y + (y1 - LOS.dragY) * k)
    end
    LOS.dragX, LOS.dragY = nil, nil
    -- the mover left the frame on its own anchor: a drop that saved no change
    -- still goes back onto the saved spot, on the pixel grid
    local E = Engine()
    if E and E.QueueRebuild then E.QueueRebuild() end
end

-- The cross's drag moves only the cross. The drop keeps it where it landed,
-- a whole number of units from the spot the layout is pinned to, and asks;
-- only Use as center sets the point there, and nothing else on screen moves.
-- Lock in place holds the point too.
function LOS.PointDragStart()
    local layout = LOS.Layout()
    local E = Engine()
    local mk = LOS.marker
    if not (LOS.open and layout and mk and E and E.SetLayoutPoint) then return end
    if LOS.dragging or LOS.pointDrag or LOS.corner or InCombatLockdown() or Store.Locked(layout) then return end
    if LOS.pressAte or ToolsBusy() then return end
    local x, y = mk:GetCenter()
    if not (x and y) then return end
    -- a waiting cross dragged again goes on from where it waits
    local p = LOS.pending
    if p then
        LOS.pointBaseX, LOS.pointBaseY = p.x, p.y
    else
        LOS.pointBaseX, LOS.pointBaseY = LOS.Point(layout)
    end
    DropPending()
    LOS.pointX, LOS.pointY = x, y
    mk:StartMoving()
    LOS.pointDrag = mk
end

function LOS.PointDragStop()
    local mk = LOS.pointDrag
    if not mk then return end
    LOS.pointDrag = nil
    mk:StopMovingOrSizing()
    local x1, y1 = mk:GetCenter()
    local layout = LOS.Layout()
    if LOS.open and layout and x1 and y1 and LOS.pointX and LOS.pointBaseX then
        -- the cross hangs off UIParent's child, so its units scale only by
        -- that, never by the layout's scale
        local k = (mk:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local px, py = LOS.Point(layout)
        -- rounded in the store's units, whole from the pinned spot (the point
        -- less the stored spot), so Use as center lands the point where the
        -- cross waits; an axis moved under half a unit stays exactly on its
        -- base, so a drop back is the point itself, a fraction included
        local gx, gy = LOS.GetPos(layout)
        local function Drop(base, d, a)
            if math.abs(d) < 0.5 then return base end
            return math.floor(base - a + d + 0.5) + a
        end
        local x = Drop(LOS.pointBaseX, (x1 - LOS.pointX) * k, px - gx)
        local y = Drop(LOS.pointBaseY, (y1 - LOS.pointY) * k, py - gy)
        -- dropped back on a center already set: nothing to ask
        if not (x == px and y == py and LOS.CenterSet(layout)) then LOS.pending = { x = x, y = y } end
    end
    LOS.pointX, LOS.pointY, LOS.pointBaseX, LOS.pointBaseY = nil, nil, nil, nil
    -- the mover left the cross on its own anchor: the redraw puts it on the
    -- pixel grid, where it waits or back on the point
    LOS.Redraw()
end

-- Use as center: the point goes where the cross waits, marked as set, so
-- Center puts that point on the screen's middle from now on.
function LOS.UseCenter()
    local p, layout, E = LOS.pending, LOS.Layout(), Engine()
    DropPending()
    if not (LOS.open and p and layout and E and E.SetLayoutPoint) then return end
    if InCombatLockdown() or Store.Locked(layout) then return LOS.Redraw() end
    LOS.Change(function()
        if Store.SetLayoutCenterSet then Store.SetLayoutCenterSet(layout, true) end
        E.SetLayoutPoint(layout.id, p.x, p.y)
    end)
    LOS.Redraw()
end

-- Put it back: the cross returns to the point, nothing saved.
function LOS.PutBack()
    local had = LOS.pending ~= nil
    DropPending()
    if had and LOS.open then LOS.Redraw() end
end

-- A corner drag: the scale the press had times how much farther from the
-- point the cursor is now, in 5% steps, growing from the point. Each new step
-- is written once (a write rebuilds); the drop keeps the last, and the whole
-- drag is one undo step.

function LOS.CanResize()
    local layout = LOS.Layout()
    return LOS.open and layout ~= nil and Store.SetLayoutScale ~= nil and not InCombatLockdown()
        and not Store.Locked(layout) and not ToolsBusy()
end

-- The center point in the cursor's units (the screen's, at scale 1).
function LOS.PointOnScreen(layout)
    local E = Engine()
    local box = E and E.GetLayoutFrame and E.GetLayoutFrame(layout.id)
    if box then
        local x, y = box:GetCenter()
        if x and y then
            local s = box:GetEffectiveScale() or 1
            return x * s, y * s
        end
    end
    local ux, uy = UIParent:GetCenter()
    if not (ux and uy) then return nil end
    local px, py = LOS.Point(layout)
    local s = UIParent:GetEffectiveScale() or 1
    return (ux + px) * s, (uy + py) * s
end

function LOS.CornerDragStart(c)
    local layout = LOS.Layout()
    if not (c and layout and GetCursorPosition and LOS.CanResize()) then return end
    if LOS.dragging or LOS.pointDrag or LOS.corner then return end
    local px, py = LOS.PointOnScreen(layout)
    local cx, cy = GetCursorPosition()
    if not (px and py and cx and cy) then return end
    local dx, dy = cx - px, cy - py
    local d0 = math.sqrt(dx * dx + dy * dy)
    if d0 < CORNER_MIN then return end
    LOS.PutBack()
    if not LOS.open then return end
    local k = LOS.GetScale(layout)
    LOS.corner = { frame = c, px = px, py = py, d0 = d0, k0 = k, last = k, step = LOS.Begin("corner") }
    c:SetScript("OnUpdate", LOS.CornerTick)
    ResizeCursor(true)
    LOS.PlaceReadout(AT.Px(LOS.root))
end

-- runs only while a corner is held
function LOS.CornerTick()
    local cd, layout = LOS.corner, LOS.Layout()
    if not cd then return end
    if not (LOS.open and layout) or InCombatLockdown() then return LOS.CornerEnd() end
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return end
    local dx, dy = cx - cd.px, cy - cd.py
    local v = LOS.StepScale(cd.k0 * math.sqrt(dx * dx + dy * dy) / cd.d0)
    if v == cd.last then return end
    cd.last = v
    LOS.SetScale(v)
    LOS.SyncToolbar(layout)
    LOS.PlaceReadout(AT.Px(LOS.root))
end

-- ends a corner drag where it is: the last step written stays
function LOS.CornerEnd()
    local cd = LOS.corner
    if not cd then return end
    LOS.corner = nil
    cd.frame:SetScript("OnUpdate", nil)
    if LOS.readout then LOS.readout:Hide() end
    ResizeCursor(false)
    if cd.step then LOS.End("corner") end
    return cd
end

function LOS.CornerDragStop()
    if not LOS.corner then return end
    LOS.CornerTick()
    local cd = LOS.CornerEnd()
    -- still over the handle: its cursor stays
    local c = cd and cd.frame
    if c and c.IsMouseOver and c:IsMouseOver() and LOS.CanResize() then ResizeCursor(true) end
end

-- Open and the one teardown

-- The toolbar's layout pick: every layout drawn on this character, in the
-- sidebar's order (the ones that load here, then an unloaded one its eye
-- draws). The one being edited always lists.
function LOS.LayoutItems()
    local out, later, has = {}, {}, false
    local list = (Store.Layouts and Store.Layouts()) or {}
    for _, l in ipairs(list) do
        local it = { value = l.id, text = l.name or "" }
        if not Store.IsLoaded or Store.IsLoaded(l) then
            out[#out + 1] = it
        elseif l.id == LOS.layoutId or (Store.UnloadedDrawn and Store.UnloadedDrawn(l)) then
            later[#later + 1] = it
        end
        if l.id == LOS.layoutId then has = true end
    end
    for _, it in ipairs(later) do out[#out + 1] = it end
    local cur = LOS.Layout()
    if cur and not has then out[#out + 1] = { value = cur.id, text = cur.name or "" } end
    return out
end

-- a pick moves the mode to that layout: the open path's retarget, never in combat
function LOS.Switch(id)
    if not LOS.open or id == nil or id == LOS.layoutId or InCombatLockdown() then return end
    LOS.Open(id)
end

-- An options-time tool: never in combat, only with the window open.
function LOS.Open(layoutId)
    if InCombatLockdown() then return false end
    local layout = layoutId and Store.Get(layoutId)
    local Fold = Options.Fold
    if not (layout and layout.type == "layout" and Fold and Fold.win and Fold.win:IsShown()) then
        return false
    end
    -- already open: the outlines move to this layout, the fold stays; a
    -- waiting cross, a held corner, the picks and any element drag belonged
    -- to the last one
    local LT = LOS.Tools
    if LOS.open then
        DropPending()
        LOS.CornerEnd()
        LOS.DropBoxes()
        if LT and LT.Teardown then LT.Teardown() end
        LOS.End()
        LOS.layoutId = layout.id
        LOS.SetPicks(nil, {})
        LOS.Redraw()
        return LOS.open
    end
    LOS.BuildHUD()
    LOS.BuildToolbar()
    LOS.layoutId = layout.id
    LOS.SetPicks(nil, {})
    LOS.open = true
    AT.CloseDropdown()
    Fold.Set(true)
    -- the engine hides each group's own name tab and Edit chips meanwhile
    local E = Engine()
    if E and E.SetScreenEditing then E.SetScreenEditing(true) end
    Events.On("PLAYER_REGEN_DISABLED", KEY, function() LOS.Close() end)
    Events.On("PLAYER_LOGOUT", KEY, function() LOS.Close() end)
    if not LOS.winHooked then
        LOS.winHooked = true
        Fold.win:HookScript("OnHide", function() LOS.Close() end)
    end
    local tb = LOS.toolbar
    -- the toolbar is panel chrome: the window's size, re-placed at it
    tb._w, tb._s = nil, nil
    LOS.root:Show()
    tb:Show()
    tb:EnableKeyboard(true)
    tb:SetPropagateKeyboardInput(true)
    LOS.Redraw()
    return LOS.open
end

function LOS.Teardown()
    local was = LOS.open
    LOS.open = false
    -- an element drag ends unsaved; the tools' overlays and strips go
    local LT = LOS.Tools
    if LT and LT.Teardown then LT.Teardown() end
    local box = LOS.dragging
    if box then
        LOS.dragging, LOS.dragX, LOS.dragY = nil, nil, nil
        box:StopMovingOrSizing()
        if NS.Pins then NS.Pins.DragStop() end
        -- an unfinished drag saves nothing: the rebuild puts the layout back
        local E = Engine()
        if E and E.QueueRebuild then E.QueueRebuild() end
    end
    -- an unfinished cross drag saves nothing: the next open places it again
    local mk = LOS.pointDrag
    if mk then
        LOS.pointDrag, LOS.pointX, LOS.pointY = nil, nil, nil
        mk:StopMovingOrSizing()
    end
    LOS.pointBaseX, LOS.pointBaseY = nil, nil
    -- a held corner keeps the last step it wrote; a waiting cross is put back
    LOS.CornerEnd()
    DropPending()
    ResizeCursor(false)
    LOS.pressAte, LOS.bgSeq = nil, nil
    -- the layout pick's pullout goes with the toolbar
    if was then AT.CloseDropdown() end
    -- a step still open (the scale track) is kept, then the session's
    -- history goes
    LOS.End()
    local EO = NS.EditOps
    if was and EO and EO.ClearHistory then EO.ClearHistory() end
    for k in pairs(LOS.ate) do LOS.ate[k] = nil end
    local tb = LOS.toolbar
    if tb then
        LOS.DropBoxes()
        tb:EnableKeyboard(false)
        tb:Hide()
    end
    if LOS.root then
        LOS.root:Hide()
        for _, f in ipairs(LOS.pool) do
            f:Hide()
            f.tag:Hide()
            f.tag:EnableMouse(false)
            f.hover = false
        end
        LOS.marker:Hide()
        LOS.readout:Hide()
        LOS.prompt:Hide()
    end
    LOS.SetPicks(nil, {})
    LOS.layoutId = nil
    local E = Engine()
    if was and E and E.SetScreenEditing then E.SetScreenEditing(false) end
    Events.Off("PLAYER_REGEN_DISABLED", KEY)
    Events.Off("PLAYER_LOGOUT", KEY)
    -- the options come back when they are still open
    local Fold = Options.Fold
    if was and Fold and Fold.folded and Fold.win and Fold.win:IsShown() then Fold.Set(false) end
end

function LOS.Close() LOS.Teardown() end

-- Exits wired once at load

-- the outlines follow every rebuild (scale, position, contents)
local Eng = NS.LayoutEngine
if Eng and Eng.Rebuild then
    hooksecurefunc(Eng, "Rebuild", function()
        if LOS.open then LOS.Redraw() end
    end)
end

-- the window unfolded by its own button ends the mode
if Options.Fold and Options.Fold.Set then
    hooksecurefunc(Options.Fold, "Set", function()
        if LOS.open and not Options.Fold.folded then LOS.Close() end
    end)
end

-- a pick outside this layout (another layout, a page of the panel) ends it
local function SelLayoutId()
    local t, id = ui.selType, ui.selId
    if t == "layout" or t == "free" then return id end
    if t == "group" or t == "bar" then
        local r = Store.Get(id)
        return r and r.layoutId
    end
    return nil
end
if Options.Select then
    hooksecurefunc(Options, "Select", function()
        if LOS.open and SelLayoutId() ~= LOS.layoutId then LOS.Close() end
    end)
end
