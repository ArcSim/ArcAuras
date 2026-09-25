-- Arc UI theme: window chrome, controls and a row layout engine for hand-built
-- options panels. A panel is CreateWindow -> NewPage -> Section -> rows ->
-- LayoutPage. Everything hangs off one table (AT) because a big single-file
-- addon can sit near Lua's 200-local limit.

local AT = {}

-- Other addons carry copies of this file, generated from it by the
-- arc-theme-sync tool, which compares this number to find stale copies.
-- Bump it on every change and never edit a copy.
AT.VERSION = 16

AT.WHITE = "Interface\\Buttons\\WHITE8X8"
AT.DISCORD = "https://discord.gg/yMZmnFjUTd"

AT.COL = {
    bg       = { 0.043, 0.059, 0.102 },  -- window body, always opaque
    panel    = { 0.063, 0.094, 0.153 },  -- title bar, pullouts, header bars
    well     = { 0.039, 0.067, 0.125 },  -- sunken input fields and dropdowns
    line     = { 0.114, 0.165, 0.247 },  -- 1px borders and hairlines
    line2    = { 0.165, 0.231, 0.341 },  -- brighter: window outline, checkbox
    box      = { 0.055, 0.078, 0.130 },  -- section box fill, a step above bg
    ink      = { 0.950, 0.970, 1.000 },  -- near-white primary text
    dim      = { 0.700, 0.780, 0.880 },  -- secondary text, hints, idle tabs
    faint    = { 0.550, 0.650, 0.780 },  -- placeholder text, off-state knob
    arc      = { 0.247, 0.788, 0.949 },  -- the accent (#3FC9F2)
    arcDeep  = { 0.078, 0.353, 0.451 },  -- deep teal, hover borders
    btn      = { 0.110, 0.161, 0.243 },  -- raised navy button fill
    btnHover = { 0.150, 0.205, 0.295 },  -- button fill on hover
    steel    = { 0.298, 0.400, 0.549 },  -- button border, cyan on hover
    blurple  = { 0.345, 0.396, 0.949 },  -- Discord #5865F2
}

-- Layout constants, in pixels. Spacing comes from the row height, not padding.
AT.LAY = {
    rowH = 24, descH = 20, hdr = 22,
    ctrl = 230,          -- fallback when a section can't measure its column
    gap  = 18,           -- between section blocks; any less and a titled
                         -- block doesn't read as separate from the one above
    fieldW = 180,
    sliderW = 110,       -- the slider; with the [-][value][+] stepper
                         -- the cluster is ~190px, like ArcSkin's range rows
}

local COL, WHITE, LAY = AT.COL, AT.WHITE, AT.LAY

-- One physical pixel in a frame's effective UI units. A literal edgeSize = 1
-- rounds to zero on one side at fractional effective scales, so edges are
-- sized in real pixels.
function AT.Px(f)
    local _, physH = GetPhysicalScreenSize()
    local scale = (f and f.GetEffectiveScale and f:GetEffectiveScale())
        or (UIParent:GetEffectiveScale()) or 1
    if not physH or physH <= 0 or scale <= 0 then return 1 end
    return (768 / physH) / scale
end

-- Hairline width for a frame: one device pixel when a UI unit is a whole
-- number of device pixels. At a fractional scale a one-pixel strip can fall
-- between two pixel columns and vanish, so there it is two, which always
-- covers one solid column. Skin borders use it; SetUIScale re-applies it.
AT.skinned = AT.skinned or setmetatable({}, { __mode = "k" })
function AT.Hairline(f)
    local px = AT.Px(f)
    -- The frame's own total factor, not AT.uiScale: auto-fit alone is
    -- fractional on most screens.
    local v = (AT.ScaleFactor and AT.ScaleFactor(f)) or (AT.uiScale or 1)
    if math.abs(v - math.floor(v + 0.5)) < 0.01 then return px end
    return px * 2
end

-- Panel scale: a personal multiplier on top of auto-fit. It scales the whole
-- window, so text and controls grow together and the layout holds. The 0.85
-- default sits a touch below the auto-fit target.
AT.uiScale = 0.85
AT.windows = AT.windows or {}

-- Auto-fit. At one unit per physical pixel a window covers designH / physH of
-- the screen (37% at 1440p, 25% at 4K). Instead, a panel built REF_H units
-- tall fills TARGET_H of the screen height at any resolution or UI scale.
AT.TARGET_H = 0.60        -- share of screen height a reference panel fills
AT.REF_H = 540            -- design height of a typical options panel
AT.MAX_W, AT.MAX_H = 0.94, 0.92   -- hard caps as a share of the screen

-- On-screen height is design height * scale (in UIParent units), so the scale
-- for TARGET_H is TARGET_H * UIParent height / design height. Auto-fit, the
-- saved uiScale and a large design size multiply, so the result is capped
-- against both screen axes last: a panel can't grow past the screen.
function AT.FitScale(designW, designH)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if not (uw and uh and uh > 0) then return AT.Px(UIParent) * (AT.uiScale or 1) end
    if not designH or designH <= 0 then return AT.Px(UIParent) * (AT.uiScale or 1) end
    -- Against max(this window, REF_H): a taller window shrinks to the target
    -- instead of overflowing, and a small popup keeps the reference scale so
    -- it stays in proportion to the main panel.
    local ref = designH > AT.REF_H and designH or AT.REF_H
    local s = (AT.TARGET_H * uh / ref) * (AT.uiScale or 1)
    -- Floor at the pixel-perfect scale first, then cap: flooring after the
    -- caps could push an oversized window back past the screen.
    local floor = AT.Px(UIParent)
    if s < floor then s = floor end
    local capH = AT.MAX_H * uh / designH
    if s > capH then s = capH end
    if designW and designW > 0 then
        local capW = AT.MAX_W * uw / designW
        if s > capW then s = capW end
    end
    return s
end

-- The scale a window gets from the size it was designed at.
function AT.ScaleFor(w)
    if not w then return AT.Px(UIParent) * (AT.uiScale or 1) end
    return AT.FitScale(w._designW, w._designH)
end

-- Device pixels per UI unit of a frame, a window or any child. Read this, not
-- AT.uiScale, to know whether units land on whole pixels: auto-fit is
-- fractional on most screens (1.6 at 1440p) with the slider at 1.
function AT.ScaleFactor(f)
    local _, physH = GetPhysicalScreenSize()
    if not physH or physH <= 0 then return AT.uiScale or 1 end
    local s = (f and f.GetEffectiveScale and f:GetEffectiveScale())
        or (UIParent and UIParent:GetEffectiveScale()) or 1
    return s * (physH / 768)
end

-- Scale of a default-sized panel, for callers with no window in hand.
function AT.WinScale()
    return AT.FitScale(460, 540)
end

function AT.SetUIScale(v)
    v = tonumber(v) or 1
    if v < 0.7 then v = 0.7 elseif v > 2 then v = 2 end
    AT.uiScale = v
    for _, w in ipairs(AT.windows) do
        if w and w.SetScale then
            -- Each window's scale comes from its own design size and clamp.
            local target = AT.ScaleFor(w)
            -- A SetPoint offset is in the frame's own scaled space (screen
            -- position = offset * scale), so rescaling alone slides the window
            -- toward its anchor; re-offsetting by the ratio keeps it put.
            local old = w:GetScale() or 1
            local ratio = (target > 0) and (old / target) or 1
            local pt, rel, relPt, x, y = w:GetPoint()
            w:SetScale(target)
            if pt and x and y and ratio ~= 1 then
                w:ClearAllPoints()
                w:SetPoint(pt, rel or UIParent, relPt or pt, x * ratio, y * ratio)
            end
            if w:IsShown() then AT.SnapWindow(w) end
        end
    end
    -- Edge strips were sized for the old scale; re-size them once per change.
    for f in pairs(AT.skinned) do
        local e = f._atEdges
        if e then
            local px = AT.Hairline(f)
            e.top:SetHeight(px)
            e.bottom:SetHeight(px)
            e.left:SetWidth(px)
            e.right:SetWidth(px)
        end
    end
end

-- Flat fill plus a one-pixel edge. The edge is four color-texture strips, not
-- a backdrop edge: a backdrop edge drops a side when the frame rests at a
-- fractional pixel position, while plain textures stay whole. The frame's
-- SetBackdropBorderColor is replaced to recolor the strips.
local EDGE_KEYS = { "top", "bottom", "left", "right" }
function AT.Skin(f, bg, borderCol)
    if not f._atEdges then
        f:SetBackdrop({ bgFile = WHITE })
        local e = {}
        for _, k in ipairs(EDGE_KEYS) do
            local t = f:CreateTexture(nil, "BORDER")
            t:SetColorTexture(1, 1, 1, 1)
            -- Default texel sampling on purpose: snapping a one-pixel strip
            -- to the grid can collapse it to zero rows at some fractional
            -- positions. Unsnapped, it only renders a little soft there.
            e[k] = t
        end
        e.top:SetPoint("TOPLEFT", 0, 0)
        e.top:SetPoint("TOPRIGHT", 0, 0)
        e.bottom:SetPoint("BOTTOMLEFT", 0, 0)
        e.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
        e.left:SetPoint("TOPLEFT", 0, 0)
        e.left:SetPoint("BOTTOMLEFT", 0, 0)
        e.right:SetPoint("TOPRIGHT", 0, 0)
        e.right:SetPoint("BOTTOMRIGHT", 0, 0)
        f._atEdges = e
        f.SetBackdropBorderColor = function(self, r, g, b, a)
            for _, t in pairs(self._atEdges) do
                t:SetVertexColor(r, g, b, a or 1)
            end
        end
    end
    AT.skinned[f] = true
    local px = AT.Hairline(f)
    f._atEdges.top:SetHeight(px)
    f._atEdges.bottom:SetHeight(px)
    f._atEdges.left:SetWidth(px)
    f._atEdges.right:SetWidth(px)
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    local b = borderCol or COL.line
    f:SetBackdropBorderColor(b[1], b[2], b[3], 1)
end

-- Pins a window's rect to the physical pixel grid, so everything inside has
-- an aligned origin and hairlines stay whole at rest.
function AT.SnapWindow(p)
    local px = AT.Px(p)
    local l, t = p:GetLeft(), p:GetTop()
    if not (l and t) or px <= 0 then return end
    local function S(v) return math.floor(v / px + 0.5) * px end
    local w, h = p:GetWidth(), p:GetHeight()
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", S(l), S(t))
    p:SetSize(S(w), S(h))
end
local Skin = AT.Skin

-- One dropdown pullout open at a time, panel-wide. Windows close it on
-- mouse down and on hide.
AT.openDropdown = nil
function AT.CloseDropdown()
    if AT.openDropdown then AT.openDropdown:Hide(); AT.openDropdown = nil end
end

-- Controls

-- Square checkbox. Only the mark toggles; the box never recolours. The
-- checkmark-minimal atlas is green, so it is desaturated before tinting. The
-- 20px mark overhangs the 18px box slightly, as Blizzard's does.
function AT.MakeCheckbox(parent)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(18, 18); Skin(c, COL.well, COL.line2)
    c.check = c:CreateTexture(nil, "OVERLAY")
    c.check:SetAtlas("checkmark-minimal")
    c.check:SetDesaturated(true)
    c.check:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    c.check:SetSize(20, 20); c.check:SetPoint("CENTER"); c.check:Hide()
    c.glow = c:CreateTexture(nil, "ARTWORK")
    c.glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    c.glow:SetBlendMode("ADD")
    c.glow:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 0.55)
    c.glow:SetPoint("TOPLEFT", -3, 3); c.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    c.glow:Hide()
    function c:SetHover(on) self.glow:SetShown(on and true or false) end
    function c:SetOn(on) self.check:SetShown(on and true or false) end
    return c
end

-- Raised button: navy fill and a steel border, cyan only on hover.
function AT.MakeSmallButton(parent, label, w)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 92, 22); Skin(b, COL.btn, COL.steel)
    local bevel = b:CreateTexture(nil, "ARTWORK")
    bevel:SetTexture(WHITE); bevel:SetVertexColor(1, 1, 1, 0.06)
    bevel:SetPoint("TOPLEFT", 1, -1); bevel:SetPoint("TOPRIGHT", -1, -1); bevel:SetHeight(1)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    b.fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    b.fs:SetPoint("CENTER")
    b.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    b.fs:SetText(label or "")
    b:SetScript("OnEnter", function()
        b:SetBackdropColor(COL.btnHover[1], COL.btnHover[2], COL.btnHover[3], 1)
        b:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    end)
    b:SetScript("OnLeave", function()
        b:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        b:SetBackdropBorderColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
    end)
    return b
end

-- Quiet button for secondary or destructive actions, so they don't compete
-- with the primary one. Same geometry, so mixed rows line up; the fill and
-- text drop a step and lift to the normal look on hover.
function AT.MakeQuietButton(parent, label, w)
    local b = AT.MakeSmallButton(parent, label, w)
    b:SetBackdropColor(0, 0, 0, 0)
    b:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    b.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    b:SetScript("OnEnter", function()
        b:SetBackdropColor(COL.btnHover[1], COL.btnHover[2], COL.btnHover[3], 1)
        b:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        b.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    end)
    b:SetScript("OnLeave", function()
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
        b.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    end)
    return b
end

function AT.MakeSwatch(parent, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 24, h or 14); Skin(b, COL.well)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetTexture(WHITE)
    b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    function b:SetColor(c) self.tex:SetVertexColor(c[1], c[2], c[3], 1) end
    b:SetScript("OnEnter", function() b:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1) end)
    b:SetScript("OnLeave", function() b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
    return b
end

-- Chevron drawn from two rotated 1.5px bars, for dropdowns and tree carets.
-- :SetDown(true) points down, false points right; :SetDir("up" / "down" /
-- "left" / "right") points any way; :SetColor(c) tints it. Mouse-transparent.
function AT.MakeChevron(parent)
    local arrow = CreateFrame("Frame", nil, parent)
    arrow:SetSize(12, 12)
    local a1 = arrow:CreateTexture(nil, "OVERLAY")
    a1:SetTexture(WHITE); a1:SetSize(7, 1.5)
    local a2 = arrow:CreateTexture(nil, "OVERLAY")
    a2:SetTexture(WHITE); a2:SetSize(7, 1.5)
    function arrow:SetDown(down)
        a1:ClearAllPoints(); a2:ClearAllPoints()
        if down then
            a1:SetPoint("CENTER", -2, 0.5); a1:SetRotation(math.rad(-50))
            a2:SetPoint("CENTER", 2, 0.5); a2:SetRotation(math.rad(50))
        else
            -- the same shape turned a quarter: tip on the right
            a1:SetPoint("CENTER", -0.5, 2); a1:SetRotation(math.rad(-40))
            a2:SetPoint("CENTER", -0.5, -2); a2:SetRotation(math.rad(40))
        end
    end
    -- the two missing directions are the mirror images of SetDown's pair
    function arrow:SetDir(dir)
        if dir == "down" or dir == "right" then
            arrow:SetDown(dir == "down")
            return
        end
        a1:ClearAllPoints(); a2:ClearAllPoints()
        if dir == "up" then
            a1:SetPoint("CENTER", -2, -0.5); a1:SetRotation(math.rad(50))
            a2:SetPoint("CENTER", 2, -0.5); a2:SetRotation(math.rad(-50))
        else
            -- "left": tip on the left
            a1:SetPoint("CENTER", 0.5, 2); a1:SetRotation(math.rad(40))
            a2:SetPoint("CENTER", 0.5, -2); a2:SetRotation(math.rad(-40))
        end
    end
    function arrow:SetColor(c)
        a1:SetVertexColor(c[1], c[2], c[3], 1)
        a2:SetVertexColor(c[1], c[2], c[3], 1)
    end
    arrow:SetDown(true); arrow:SetColor(COL.arc)
    return arrow
end

-- Drag handle between two panes. axis "x": a 12-wide vertical strip dragged
-- sideways; "y": a 12-tall one dragged up and down. The caller anchors it and
-- gets cb.onStart(), cb.onDrag(delta) and cb.onStop(); delta is in the strip's
-- units from the press point, right and up positive.
function AT.MakeSplitter(parent, axis, cb)
    cb = cb or {}
    local s = CreateFrame("Frame", nil, parent)
    s:EnableMouse(true)
    if axis == "x" then s:SetWidth(12) else s:SetHeight(12) end
    s.line = s:CreateTexture(nil, "ARTWORK")
    s.dots = {}
    for i = -1, 1 do
        local d = s:CreateTexture(nil, "OVERLAY")
        d:SetSize(3, 3)
        if axis == "x" then d:SetPoint("CENTER", 0, i * 6)
        else d:SetPoint("CENTER", i * 6, 0) end
        s.dots[#s.dots + 1] = d
    end
    local function place()
        local px = AT.Hairline(s)
        s.line:ClearAllPoints()
        if axis == "x" then
            s.line:SetPoint("TOP", 0, 0); s.line:SetPoint("BOTTOM", 0, 0); s.line:SetWidth(px)
        else
            s.line:SetPoint("LEFT", 0, 0); s.line:SetPoint("RIGHT", 0, 0); s.line:SetHeight(px)
        end
    end
    local function paint(hot)
        local l = hot and COL.arc or COL.line
        s.line:SetColorTexture(l[1], l[2], l[3], 1)
        local c = hot and COL.arc or COL.faint
        for _, d in ipairs(s.dots) do d:SetColorTexture(c[1], c[2], c[3], hot and 1 or 0.85) end
    end
    place()
    paint(false)
    s:SetScript("OnShow", place)
    s:SetScript("OnEnter", function() paint(true) end)
    s:SetScript("OnLeave", function() if not s._drag then paint(false) end end)
    s:SetScript("OnMouseDown", function()
        s._drag = true
        paint(true)
        local x0, y0 = GetCursorPosition()
        local sc = s:GetEffectiveScale()
        if cb.onStart then cb.onStart() end
        s:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local d = ((axis == "x") and (x - x0) or (y - y0)) / sc
            if d ~= s._last then
                s._last = d
                if cb.onDrag then cb.onDrag(d) end
            end
        end)
    end)
    s:SetScript("OnMouseUp", function()
        s._drag, s._last = nil, nil
        s:SetScript("OnUpdate", nil)
        paint(false)
        if cb.onStop then cb.onStop() end
    end)
    return s
end

function AT.MakeDropdown(owner, parent, w, itemsFn, get, set, onSelect)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or LAY.fieldW, 20); Skin(b, COL.well)
    local vf = b:CreateFontString(nil, "OVERLAY")
    vf:SetFont(STANDARD_TEXT_FONT, 11, "")
    vf:SetPoint("LEFT", 8, 0); vf:SetPoint("RIGHT", -18, 0); vf:SetJustifyH("LEFT")
    -- itemsFn() -> { {value=,text=}, ... }, re-read on every open. The field
    -- is one line: bounded text wraps by default and would spill over the box.
    vf:SetWordWrap(false)
    vf:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    local arrow = AT.MakeChevron(b)
    arrow:SetPoint("RIGHT", -5, 0)
    b:SetScript("OnEnter", function() b:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1) end)
    b:SetScript("OnLeave", function() b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)

    -- With no w, the field fits the longest option name plus insets, clamped
    -- to 80-300 so a runaway name can't eat the row. The pullout copies the
    -- field width.
    local function SizeToItems(items)
        if w then return end
        local fs = AT._measureFS
        if not fs then
            fs = UIParent:CreateFontString(nil, "ARTWORK")
            fs:SetFont(STANDARD_TEXT_FONT, 11, ""); fs:Hide()
            AT._measureFS = fs
        end
        local widest = 0
        for _, it in ipairs(items or itemsFn() or {}) do
            fs:SetText(it.text or "")
            local tw = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth())
                or fs:GetStringWidth() or 0
            if tw > widest then widest = tw end
        end
        -- The insets take 26 (8 text + 18 chevron): round up and keep a few
        -- pixels of slack so the text never touches the bound.
        local want = math.ceil(widest) + 30
        if want < 80 then want = 80 end
        if want > 300 then want = 300 end
        b:SetWidth(want)
    end

    -- Re-reads the value and re-sizes to the current items: a list that
    -- depends on the selected record holds only a placeholder at build time.
    -- LayoutPage calls this on every sync through row._sync.
    function b.Refresh()
        local cur = get()
        local items = itemsFn() or {}
        SizeToItems(items)
        for _, it in ipairs(items) do
            if it.value == cur then vf:SetText(it.text) return end
        end
        vf:SetText(cur ~= nil and tostring(cur) or "")
    end
    b.Refresh()

    b:SetScript("OnClick", function()
        if AT.openDropdown and AT.openDropdown._owner == b then AT.CloseDropdown() return end
        AT.CloseDropdown()
        local items = itemsFn() or {}
        SizeToItems(items)
        local vis = math.min(#items, 12)
        local list = CreateFrame("Frame", nil, owner, "BackdropTemplate")
        list:SetFrameLevel(owner:GetFrameLevel() + 30)
        list:SetWidth(b:GetWidth()); list:SetHeight(vis * 20 + 2)
        Skin(list, COL.panel, COL.arcDeep)
        list:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -1)
        list._owner = b
        list:EnableMouse(true); list:EnableMouseWheel(true)
        local off, maxOff = 0, math.max(0, #items - vis)
        for i, it in ipairs(items) do
            if it.value == get() then off = math.min(maxOff, math.max(0, i - 1)) end
        end
        local rows = {}
        for i = 1, vis do
            local ib = CreateFrame("Button", nil, list)
            ib:SetHeight(20)
            ib:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
            ib:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 20)
            ib:SetHighlightTexture(WHITE)
            ib:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.5)
            ib.t = ib:CreateFontString(nil, "OVERLAY")
            ib.t:SetFont(STANDARD_TEXT_FONT, 11, "")
            ib.t:SetPoint("LEFT", 8, 0); ib.t:SetPoint("RIGHT", -6, 0); ib.t:SetJustifyH("LEFT")
            ib.t:SetWordWrap(false)
            rows[i] = ib
        end
        local function draw()
            for i = 1, vis do
                local it, ib = items[i + off], rows[i]
                if it then
                    ib.t:SetText(it.text)
                    if it.value == get() then ib.t:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
                    else ib.t:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]) end
                    ib:SetScript("OnClick", function()
                        set(it.value); b.Refresh(); AT.CloseDropdown()
                        if onSelect then onSelect(it.value) end
                    end)
                    ib:Show()
                else ib:Hide() end
            end
        end
        list:SetScript("OnMouseWheel", function(_, d)
            off = math.min(maxOff, math.max(0, off - d * 3)); draw()
        end)
        draw()
        AT.openDropdown = list
    end)
    return b
end

-- Window chrome

-- Scroll region: a plain ScrollFrame with a thin track and a thumb shown only
-- on overflow. Returns host, content: set the content's height after laying
-- out its children, then call host:UpdateScroll(). Pass an existing region (a
-- multiline EditBox) as child to scroll it instead of a new frame.
function AT.MakeScroll(parent, child)
    local host = CreateFrame("ScrollFrame", nil, parent)
    local content = child or CreateFrame("Frame", nil, host)
    if not child then content:SetSize(1, 1) end
    host:SetScrollChild(content)
    local track = CreateFrame("Frame", nil, host, "BackdropTemplate")
    track:SetWidth(5)
    track:SetPoint("TOPRIGHT", host, "TOPRIGHT", 2, 0)
    track:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 2, 0)
    Skin(track, COL.well, COL.well)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 0.8)
    thumb:SetPoint("TOPLEFT", 0, 0)
    thumb:SetPoint("TOPRIGHT", 0, 0)
    track:Hide()
    function host:UpdateScroll()
        local viewH = host:GetHeight() or 0
        local contentH = content:GetHeight() or 0
        local over = contentH - viewH
        if over <= 1 or viewH <= 0 then
            host:SetVerticalScroll(0)
            track:Hide()
            return
        end
        track:Show()
        local cur = math.min(host:GetVerticalScroll() or 0, over)
        if cur < 0 then cur = 0 end
        host:SetVerticalScroll(cur)
        local thumbH = math.max(20, viewH * (viewH / contentH))
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", 0, -(viewH - thumbH) * (cur / over))
        thumb:SetPoint("TOPRIGHT", 0, -(viewH - thumbH) * (cur / over))
    end
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function(_, delta)
        local viewH = host:GetHeight() or 0
        local over = ((content:GetHeight() or 0)) - viewH
        if over <= 0 then return end
        local cur = (host:GetVerticalScroll() or 0) - delta * 32
        if cur < 0 then cur = 0 elseif cur > over then cur = over end
        host:SetVerticalScroll(cur)
        host:UpdateScroll()
        AT.CloseDropdown()
    end)
    host:SetScript("OnSizeChanged", function() host:UpdateScroll() end)
    return host, content
end

function AT.CreateWindow(globalName, opts)
    opts = opts or {}
    local minW, minH = opts.minW or 400, opts.minH or 480
    local p = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    p:SetSize(math.max(minW, opts.w or 460), math.max(minH, opts.h or 540))
    p:SetPoint("CENTER", 0, 40)
    -- Pages clip rather than scroll, so minW / minH matter. The design size
    -- drives this window's own fit and clamp (AT.FitScale).
    p._designW = math.max(minW, opts.w or 460)
    p._designH = math.max(minH, opts.h or 540)
    p:SetScale(AT.ScaleFor(p))
    AT.windows[#AT.windows + 1] = p
    p:RegisterEvent("UI_SCALE_CHANGED")
    p:RegisterEvent("DISPLAY_SIZE_CHANGED")
    p:SetScript("OnEvent", function(self)
        -- the screen itself changed, so the clamp has to be recomputed
        self:SetScale(AT.ScaleFor(self))
        if self:IsShown() then AT.SnapWindow(self) end
    end)
    p:SetFrameStrata("DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
    p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        AT.SnapWindow(self)
    end)
    p:SetScript("OnMouseDown", AT.CloseDropdown)
    p:SetScript("OnHide", AT.CloseDropdown)
    p:SetScript("OnShow", function(self) AT.SnapWindow(self) end)
    Skin(p, COL.bg, COL.line2)
    if globalName then tinsert(UISpecialFrames, globalName) end

    local bar = CreateFrame("Frame", nil, p, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(30)
    Skin(bar, COL.panel)
    local t1 = bar:CreateFontString(nil, "OVERLAY")
    t1:SetFont(STANDARD_TEXT_FONT, 14, ""); t1:SetPoint("LEFT", 12, 0)
    t1:SetText(opts.title or "|cff3fc9f2Arc|r|cffd5e2f2 Addon|r")
    if opts.version then
        local ver = bar:CreateFontString(nil, "OVERLAY")
        ver:SetFont(STANDARD_TEXT_FONT, 10, "")
        ver:SetPoint("LEFT", t1, "RIGHT", 8, -1)
        ver:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        ver:SetText(opts.version)
    end
    local close = CreateFrame("Button", nil, bar, "BackdropTemplate")
    close:SetSize(18, 18); close:SetPoint("RIGHT", -6, 0); Skin(close, COL.well, COL.line2)
    local cx = close:CreateFontString(nil, "OVERLAY")
    cx:SetFont(STANDARD_TEXT_FONT, 12, ""); cx:SetPoint("CENTER", 0, 0); cx:SetText("x")
    cx:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    close:SetScript("OnEnter", function()
        cx:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        close:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    end)
    close:SetScript("OnLeave", function()
        cx:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        close:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    end)
    close:SetScript("OnClick", function() p:Hide() end)
    p.titleBar, p.titleText = bar, t1

    if opts.resizable ~= false then
        p:SetResizable(true)
        if p.SetResizeBounds then p:SetResizeBounds(minW, minH, opts.maxW or 900, opts.maxH or 1000) end
        local grip = CreateFrame("Button", nil, p)
        grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:EnableMouse(true)
        local gt = grip:CreateTexture(nil, "OVERLAY")
        gt:SetAllPoints(); gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        gt:SetVertexColor(COL.faint[1], COL.faint[2], COL.faint[3], 0.8)
        grip:SetScript("OnEnter", function() gt:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
        grip:SetScript("OnLeave", function() gt:SetVertexColor(COL.faint[1], COL.faint[2], COL.faint[3], 0.8) end)
        local sizing
        grip:SetScript("OnMouseDown", function()
            AT.CloseDropdown()
            -- Pin the top-left first: a CENTER-anchored frame grows
            -- symmetrically, so sizing from the corner would lurch the window.
            local l, t = p:GetLeft(), p:GetTop()
            if l and t then
                p:ClearAllPoints()
                p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            end
            -- Manual sizing instead of StartSizing: on a scaled window the
            -- client can compute StartSizing's grab offset in the wrong
            -- coordinate space, and the frame balloons as the drag begins.
            local cx, cy = GetCursorPosition()
            sizing = { w = p:GetWidth(), h = p:GetHeight(), x = cx, y = cy }
            local maxW, maxH = opts.maxW or 900, opts.maxH or 1000
            grip:SetScript("OnUpdate", function()
                if not sizing then return end
                local nx, ny = GetCursorPosition()
                local es = p:GetEffectiveScale()
                if not es or es <= 0 then return end
                local w = sizing.w + (nx - sizing.x) / es
                local h = sizing.h - (ny - sizing.y) / es
                if w < minW then w = minW elseif w > maxW then w = maxW end
                if h < minH then h = minH elseif h > maxH then h = maxH end
                p:SetSize(w, h)
            end)
        end)
        grip:SetScript("OnMouseUp", function()
            grip:SetScript("OnUpdate", nil)
            sizing = nil
            AT.SnapWindow(p)
            if opts.onResize then opts.onResize(p:GetWidth(), p:GetHeight()) end
            if p.RefreshActive then p:RefreshActive() end
        end)
    end
    -- Frames are created shown, so a toggle-style opener would close the new
    -- window at once. It starts hidden; the caller shows it.
    p:Hide()
    return p
end

-- Chip tabs on one continuous cyan line. tabs = { "General", "Alerts" }; the
-- caller makes each pages[name] with NewPage. Returns select(name).
function AT.AddTabs(p, tabs, pages, y)
    y = y or -34
    p._tabs = {}
    local x = 10
    local function repaint(active)
        for name, d in pairs(p._tabs) do
            local sel = (name == active)
            pages[name]:SetShown(sel)
            if sel then
                Skin(d.chip, COL.panel, COL.arc)
                d.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
                if pages[name].Refresh then pages[name]:Refresh() end
            else
                Skin(d.chip, COL.well, COL.line)
                d.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
            end
        end
        p._activeTab = active
    end
    local function select(name) repaint(name) end
    for _, name in ipairs(tabs) do
        local tb = CreateFrame("Button", nil, p, "BackdropTemplate")
        tb:SetHeight(24)
        local fs = tb:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 12, ""); fs:SetPoint("CENTER"); fs:SetText(name)
        tb:SetWidth(math.max(70, (fs:GetStringWidth() or 40) + 22))
        tb:SetPoint("TOPLEFT", x, y); x = x + tb:GetWidth() + 3
        tb:SetScript("OnClick", function() AT.CloseDropdown(); select(name) end)
        tb:SetScript("OnEnter", function()
            if p._activeTab ~= name then
                tb:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
                fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            end
        end)
        tb:SetScript("OnLeave", function()
            if p._activeTab ~= name then
                tb:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
                fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
            end
        end)
        p._tabs[name] = { chip = tb, fs = fs }
    end
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    line:SetPoint("TOPLEFT", 10, y - 25); line:SetPoint("TOPRIGHT", -10, y - 25)
    line:SetHeight(1)
    p.SelectTab = select
    function p:RefreshActive()
        if self._activeTab and pages[self._activeTab] and pages[self._activeTab].Refresh then
            pages[self._activeTab]:Refresh()
        end
    end
    return select
end

-- Row engine

function AT.NewPage(parent)
    local pg = CreateFrame("Frame", nil, parent)
    -- One flat panel-colored body per page, so section boxes nest inside it
    -- instead of floating on the bare window background.
    pg._bg = pg:CreateTexture(nil, "BACKGROUND", nil, -8)
    pg._bg:SetTexture(WHITE)
    pg._bg:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    pg._bg:SetAllPoints()
    pg._rows, pg._sections, pg._curSection = {}, {}, nil
    function pg:Refresh() AT.LayoutPage(self) end
    pg:Hide()
    return pg
end

function AT.AddRow(pg, h, visibleFn)
    local sec = pg._curSection
    local row = CreateFrame("Frame", nil, (sec and sec.box) or pg)
    h = h or LAY.rowH
    row:SetHeight(h); row._h = h; row._visibleFn = visibleFn
    -- The row's page, so a control that had to guess its size on the first
    -- pass (a tab strip) can ask for the next-frame re-pass.
    row._pg = pg
    row._ctrlX = (sec and sec.ctrlX) or LAY.ctrl
    if sec then sec.rows[#sec.rows + 1] = row else pg._rows[#pg._rows + 1] = row end
    return row
end

function AT.RowLabel(row, text)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, ""); fs:SetPoint("LEFT", 10, 0)
    fs:SetWordWrap(false); fs:SetJustifyH("LEFT")
    fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]); fs:SetText(text)
    return fs
end

-- Tab strip: chips on one cyan line. Unselected chips sit under the line (+1)
-- so it hides their bottom edges; the selected one sits above it (+3) with no
-- bottom edge, opening into the page below. Chips wrap when the strip is too
-- narrow. Set() is pooled and idempotent: call it from a _sync.
function AT.TabRow(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip._tabs = {}
    strip._lineF = CreateFrame("Frame", nil, strip)
    strip._lineF:SetPoint("TOPLEFT", 0, -23)
    strip._lineF:SetPoint("TOPRIGHT", 0, -23)
    strip._lineF:SetHeight(1)
    strip._line = strip._lineF:CreateTexture(nil, "OVERLAY")
    strip._line:SetTexture(WHITE)
    strip._line:SetAllPoints()
    strip._line:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 0.9)
    local function Edge(t)
        local e = t:CreateTexture(nil, "OVERLAY")
        e:SetTexture(WHITE)
        return e
    end
    local function PaintIdle(tb)
        if tb._active then return end
        tb.bg:SetVertexColor(COL.well[1], COL.well[2], COL.well[3], 1)
        tb.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        for _, e in ipairs({ tb.eL, tb.eT, tb.eR, tb.eB }) do
            e:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
            e:Show()
        end
    end
    function strip:Set(names, active, onClick, fontSize)
        self._lineF:SetFrameLevel(self:GetFrameLevel() + 2)
        -- The selected chip's fill: the window bg, or set strip._openFill =
        -- COL.panel when the strip sits on a panel-bodied page.
        local open = self._openFill or COL.bg
        local chipH = 24
        local x, rowY = 0, 0
        -- On the first layout pass the strip has no width yet, so walk up the
        -- parents. Only the strip's own width is reliable: a parent's can be
        -- wider, and the 500 fallback is a number. Either counts as a guess.
        local maxW, guessed
        local probe = self
        for depth = 1, 4 do
            if not probe then break end
            local w = probe:GetWidth()
            if w and w > 50 then
                maxW = w
                if depth > 1 then guessed = true end
                break
            end
            probe = probe:GetParent()
        end
        if not maxW then guessed = true end
        maxW = (maxW or 500) - 4
        for i = 1, math.max(#names, #self._tabs) do
            local name, tb = names[i], self._tabs[i]
            if name and not tb then
                tb = CreateFrame("Button", nil, self)
                tb.bg = tb:CreateTexture(nil, "BACKGROUND")
                tb.bg:SetTexture(WHITE)
                tb.bg:SetAllPoints()
                tb.fs = tb:CreateFontString(nil, "OVERLAY")
                tb.fs:SetPoint("CENTER", 0, 0)
                tb.eL, tb.eT, tb.eR, tb.eB = Edge(tb), Edge(tb), Edge(tb), Edge(tb)
                tb.eL:SetPoint("TOPLEFT"); tb.eL:SetPoint("BOTTOMLEFT"); tb.eL:SetWidth(1)
                tb.eT:SetPoint("TOPLEFT"); tb.eT:SetPoint("TOPRIGHT"); tb.eT:SetHeight(1)
                tb.eR:SetPoint("TOPRIGHT"); tb.eR:SetPoint("BOTTOMRIGHT"); tb.eR:SetWidth(1)
                tb.eB:SetPoint("BOTTOMLEFT"); tb.eB:SetPoint("BOTTOMRIGHT"); tb.eB:SetHeight(1)
                self._tabs[i] = tb
            end
            if tb then
                if name then
                    tb:SetHeight(chipH)
                    tb.fs:SetFont(STANDARD_TEXT_FONT, fontSize or 12, "")
                    tb.fs:SetText(name)
                    -- A FontString can measure 0 right after SetFont:
                    -- estimate, and count it as a guess.
                    local sw = tb.fs:GetStringWidth()
                    if type(sw) == "number" and sw <= 0 then
                        sw = #name * (fontSize or 12) * 0.55
                        guessed = true
                    end
                    local w = math.floor((sw or 40) + 24 + 0.5)
                    tb:SetWidth(w)
                    if x + w > maxW and x > 0 then x = 0; rowY = rowY - (chipH + 4) end
                    tb:ClearAllPoints()
                    tb:SetPoint("TOPLEFT", x, rowY)
                    x = x + w + 5
                    local on = (name == active)
                    tb._active = on
                    tb:SetFrameLevel(self:GetFrameLevel() + (on and 3 or 1))
                    if on then
                        -- open bottom: fill continuous with whatever sits
                        -- under the line, arc side/top edges
                        tb.bg:SetVertexColor(open[1], open[2], open[3], 1)
                        tb.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
                        tb.eL:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1); tb.eL:Show()
                        tb.eT:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1); tb.eT:Show()
                        tb.eR:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1); tb.eR:Show()
                        tb.eB:Hide()
                    else
                        PaintIdle(tb)
                    end
                    tb:SetScript("OnClick", function()
                        AT.CloseDropdown()
                        if onClick then onClick(name) end
                    end)
                    tb:SetScript("OnEnter", function(s)
                        if not s._active then
                            for _, e in ipairs({ s.eL, s.eT, s.eR, s.eB }) do
                                e:SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
                            end
                            s.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
                        end
                    end)
                    tb:SetScript("OnLeave", function(s) PaintIdle(s) end)
                    tb:Show()
                else
                    tb:Hide()
                end
            end
        end
        -- Pin the line to the last chip row's bottom edge, 1px up so it
        -- overlays the chip bottoms.
        local h = -rowY + chipH
        self._lineF:ClearAllPoints()
        self._lineF:SetPoint("TOPLEFT", 0, -(h - 1))
        self._lineF:SetPoint("TOPRIGHT", 0, -(h - 1))
        -- A guess lays the page out again on the next frame (LayoutPage's
        -- capped re-pass). Only for a row that will show: a hidden one would
        -- use up the page's three tries.
        if guessed then
            local row = self:GetParent()
            local pg = row and row._pg
            if pg and ((not row._visibleFn) or row._visibleFn()) then
                pg._sizeUnresolved = true
            end
        end
        return h, guessed == true
    end
    return strip
end

function AT.Tooltip(region, title, body)
    region:HookScript("OnEnter", function(self)
        -- A body function that returns nil means no tooltip right now. Two
        -- steps on purpose: `f() or body` would hand back the function.
        local b = body
        if type(b) == "function" then b = b() end
        if type(b) ~= "string" or b == "" then return end
        local t = title
        if type(t) == "function" then t = t() end
        if type(t) ~= "string" then t = "" end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(t, 1, 1, 1)
        GameTooltip:AddLine(b, 0.75, 0.82, 0.92, true)
        GameTooltip:Show()
    end)
    region:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- opts = { visibleFn, side = "L"/"R", ctrlX, collapsible = false, store = table }
-- A collapsible section has a clickable header bar, arrow on the left; shut,
-- it keeps a cyan underline. Its open/shut state is saved in `store` (any
-- table you own) under the title.
function AT.Section(pg, text, opts)
    opts = opts or {}
    local titled = (text ~= nil and text ~= "")
    -- A plain section is an invisible layout container on the page's one
    -- panel, set apart by its header and spacing rather than a box.
    local box = CreateFrame("Frame", nil, pg, "BackdropTemplate")
    box:SetClipsChildren(true)
    local sec = {
        box = box, rows = {}, visibleFn = opts.visibleFn, side = opts.side,
        ctrlX = opts.ctrlX or LAY.ctrl, collapsed = false, f = 1, store = opts.store,
    }
    if titled and opts.collapsible then
        -- A collapsible section is a real box: something you open and shut
        -- has to show what it contains.
        local bar = CreateFrame("Button", nil, pg, "BackdropTemplate")
        bar:SetHeight(LAY.hdr); Skin(bar, COL.panel, COL.line)
        local arrow = AT.MakeChevron(bar)
        arrow:SetPoint("LEFT", 7, 0)
        local title = bar:CreateFontString(nil, "OVERLAY")
        title:SetFont(STANDARD_TEXT_FONT, 11, "")
        title:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
        title:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3]); title:SetText(text)
        local rule = bar:CreateTexture(nil, "OVERLAY")
        rule:SetTexture(WHITE)
        rule:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        rule:SetPoint("BOTTOMLEFT", 1, 1); rule:SetPoint("BOTTOMRIGHT", -1, 1)
        rule:SetHeight(1); rule:Hide()
        -- the body is a real container while it is open
        Skin(box, COL.box, COL.line)
        sec.hit, sec.title, sec.arrow, sec.rule = bar, title, arrow, rule
        sec.boxed = true
        local function paint(hot)
            local c = hot and COL.ink or COL.arc
            title:SetTextColor(c[1], c[2], c[3])
            arrow:SetColor(c)
            local f = hot and COL.btnHover or COL.panel
            bar:SetBackdropColor(f[1], f[2], f[3], 1)
        end
        bar:SetScript("OnEnter", function() paint(true) end)
        bar:SetScript("OnLeave", function() paint(false) end)
        bar:SetScript("OnClick", function()
            AT.CloseDropdown()
            sec.collapsed = not sec.collapsed
            if sec.store then
                sec.store.secCollapsed = sec.store.secCollapsed or {}
                sec.store.secCollapsed[text] = sec.collapsed or nil
            end
            PlaySound(sec.collapsed and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
                                     or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
            sec.page = pg
            AT.anims = AT.anims or {}
            AT.anims[sec] = true
            if not AT.animDriver then
                AT.animDriver = CreateFrame("Frame")
                AT.animDriver:SetScript("OnUpdate", function(drv, elapsed)
                    local pages, any = {}, false
                    for s in pairs(AT.anims) do
                        local target = s.collapsed and 0 or 1
                        local f = s.f or (1 - target)
                        local step = elapsed / 0.16
                        if f < target then f = math.min(target, f + step)
                        else f = math.max(target, f - step) end
                        s.f = f
                        if f == target then AT.anims[s] = nil else any = true end
                        if s.page then pages[s.page] = true end
                    end
                    for p2 in pairs(pages) do AT.LayoutPage(p2) end
                    if not any then drv:SetScript("OnUpdate", nil); AT.animDriver = nil end
                end)
            end
        end)
        if sec.store and (sec.store.secCollapsed or {})[text] then
            sec.collapsed, sec.f = true, 0
        end
    elseif titled then
        local t = pg:CreateFontString(nil, "OVERLAY")
        t:SetFont(STANDARD_TEXT_FONT, 10, "")
        t:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        t:SetText(string.upper(text))
        sec.title = t
        -- A 10px title alone doesn't read as a boundary, so a hairline under
        -- it spans the section and gives the block a visible top edge.
        local hr = pg:CreateTexture(nil, "ARTWORK")
        hr:SetTexture(WHITE)
        hr:SetVertexColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
        sec.hr = hr
        -- No buttons on a section title: a header sits right under the
        -- previous section's content, so a button there has no clear owner.
        -- Actions go in rows (AT.RowButton).
    end
    pg._sections[#pg._sections + 1] = sec
    pg._curSection = sec
    return box
end

-- Page scrolling in place: LayoutPage flows everything from pg._startY, so a
-- scroll offsets _startY and clips the page. Pages get re-parented at runtime
-- (the icon editor moves between panes), which a scroll child would have to
-- follow; an offset doesn't care.
function AT.MakeScrollable(pg)
    if not pg or pg._scroll then return pg end
    pg:SetClipsChildren(true)
    pg:EnableMouseWheel(true)
    pg._scrollOff = 0
    local track = CreateFrame("Frame", nil, pg, "BackdropTemplate")
    track:SetWidth(5)
    track:SetPoint("TOPRIGHT", -1, -3)
    track:SetPoint("BOTTOMRIGHT", -1, 3)
    Skin(track, COL.well, COL.well)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 0.8)
    thumb:SetPoint("TOPLEFT", 0, 0)
    thumb:SetPoint("TOPRIGHT", 0, 0)
    track:Hide()
    local function overflow()
        local viewH = pg:GetHeight() or 0
        return math.max(0, (pg._contentH or 0) - viewH), viewH
    end
    pg._scroll = {
        track = track,
        overflow = overflow,
        paint = function()
            local over, viewH = overflow()
            if over <= 1 or viewH <= 0 then track:Hide() return end
            -- Set on every paint: a re-parented page takes a new base level,
            -- and a level fixed at build time would sink under the rows.
            track:SetFrameLevel(pg:GetFrameLevel() + 30)
            track:Show()
            local th = math.max(20, viewH * (viewH / (pg._contentH or viewH)))
            local travel = math.max(0, viewH - th - 6)
            local t = -travel * ((pg._scrollOff or 0) / over)
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPLEFT", 0, t)
            thumb:SetPoint("TOPRIGHT", 0, t)
        end,
    }
    pg:SetScript("OnMouseWheel", function(_, delta)
        local over = overflow()
        if over <= 0 then return end
        local cur = (pg._scrollOff or 0) - delta * 36
        if cur < 0 then cur = 0 elseif cur > over then cur = over end
        if cur == pg._scrollOff then return end
        pg._scrollOff = cur
        AT.CloseDropdown()
        AT.LayoutPage(pg)
    end)
    return pg
end

-- Flows the rows, sizes each box to its visible rows and aligns controls on
-- one column per section; call it after anything shows or hides a row. Each
-- pass runs row._sync (builders set it; custom rows set their own) and hides
-- any row or section whose visibleFn returns false.
function AT.LayoutPage(pg)
    if not (pg and pg._sections) then return end
    if pg._scroll then
        -- Clamped against the last measured content; it is one pass stale only
        -- when content shrinks under the scroll, and the next pass fixes it.
        local over = pg._scroll.overflow()
        local off = pg._scrollOff or 0
        if off > over then off = over elseif off < 0 then off = 0 end
        pg._scrollOff = off
        pg._startY = -4 + off
    end
    local y = pg._startY or -4
    for _, row in ipairs(pg._rows) do
        if row._sync then row._sync() end
        if (not row._visibleFn) or row._visibleFn() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 2, y); row:SetPoint("TOPRIGHT", -2, y)
            row:Show(); y = y - row._h
        else row:Hide() end
    end
    local pairTopY, pairBottomY
    for _, sec in ipairs(pg._sections) do
        local side = sec.side
        if sec.visibleFn and not sec.visibleFn() then
            if sec.hit then sec.hit:Hide() end
            if sec.title then sec.title:Hide() end
            if sec.hr then sec.hr:Hide() end
            sec.box:Hide()
            if side == "L" then pairTopY, pairBottomY = y, y
            elseif side == "R" then pairTopY, pairBottomY = nil, nil end
        else
            -- A section with every row hidden paints nothing: no title, no
            -- empty box, no gap.
            local anyVis = false
            for _, r in ipairs(sec.rows) do
                if (not r._visibleFn) or r._visibleFn() then anyVis = true break end
            end
            if not anyVis then
                if sec.hit then sec.hit:Hide() end
                if sec.title then sec.title:Hide() end
                if sec.hr then sec.hr:Hide() end
                sec.box:Hide()
                if side == "L" then pairTopY, pairBottomY = y, y
                elseif side == "R" then pairTopY, pairBottomY = nil, nil end
            else
            local topY = (side == "R" and pairTopY) or y
            local hdrH = 0
            local function span(f, top)
                f:ClearAllPoints()
                if side == "L" then
                    f:SetPoint("TOPLEFT", 6, top); f:SetPoint("TOPRIGHT", pg, "TOP", -6, top)
                elseif side == "R" then
                    f:SetPoint("TOPLEFT", pg, "TOP", 6, top); f:SetPoint("TOPRIGHT", -6, top)
                else
                    f:SetPoint("TOPLEFT", 6, top); f:SetPoint("TOPRIGHT", -6, top)
                end
            end
            if sec.hit then
                span(sec.hit, topY); sec.hit:Show(); hdrH = LAY.hdr
                -- A hidden section hides its title too; show it again with
                -- the bar.
                if sec.title then sec.title:Show() end
                sec.arrow:SetDown(not sec.collapsed)
                sec.rule:SetShown(sec.collapsed)
            elseif sec.title then
                sec.title:ClearAllPoints()
                if side == "R" then sec.title:SetPoint("TOPLEFT", pg, "TOP", 12, topY - 2)
                else sec.title:SetPoint("TOPLEFT", 12, topY - 2) end
                sec.title:Show(); hdrH = LAY.hdr
                if sec.hr then
                    span(sec.hr, topY - hdrH + 5)   -- same edges as the box
                    sec.hr:SetHeight(AT.Hairline(pg))
                    sec.hr:Show()
                end
            end
            local boxTop = topY - hdrH
            span(sec.box, boxTop)

            -- Sync before measuring: a label that arrives in _sync would
            -- otherwise be measured empty and squeeze the column.
            for _, r in ipairs(sec.rows) do
                if r._sync then r._sync() end
            end
            -- Unbounded width: GetStringWidth reports the truncated width,
            -- and the column would ratchet down pass after pass.
            local col
            for _, r in ipairs(sec.rows) do
                if r._colLabel and ((not r._visibleFn) or r._visibleFn()) then
                    local fs = r._colLabel
                    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth())
                           or fs:GetStringWidth() or 0
                    w = 10 + w + 16
                    if not col or w > col then col = w end
                end
            end
            local by = -2
            for _, row in ipairs(sec.rows) do
                if (not row._visibleFn) or row._visibleFn() then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", sec.box, "TOPLEFT", 6, by)
                    row:SetPoint("TOPRIGHT", sec.box, "TOPRIGHT", -6, by)
                    row:Show(); by = by - row._h
                else row:Hide() end
            end
            if col then
                -- An anchored frame has no width until the client lays it
                -- out, so on the first pass the box measures 0. Derive it
                -- from the page (sized by the window) with span()'s insets.
                local bw = sec.box:GetWidth() or 0
                if bw <= 60 then
                    local pw = pg:GetWidth() or 0
                    if pw > 60 then
                        bw = (side and (pw / 2) or pw) - 12
                    end
                end
                -- Still unknown: ask for one more pass on the next frame.
                if bw <= 60 then pg._sizeUnresolved = true end
                if bw > 60 then
                    -- Cap the column so the widest control fits: the box
                    -- clips its children, so an overhanging one is cut off.
                    local widest = 34
                    for _, r in ipairs(sec.rows) do
                        if r._colCtrl and ((not r._visibleFn) or r._visibleFn()) then
                            local cw = r._colCtrl:GetWidth() or 0
                            if cw > widest then widest = cw end
                        end
                    end
                    local cap = bw - widest - 12
                    if col > cap then col = math.max(12, cap) end
                end
                for _, r in ipairs(sec.rows) do
                    if r._colCtrl then
                        r._colCtrl:ClearAllPoints()
                        r._colCtrl:SetPoint("LEFT", r, "LEFT", col, 0)
                        -- _colFill = true stretches the control to the row's
                        -- right edge; a frame stops it at that frame.
                        if r._colFill == true then
                            r._colCtrl:SetPoint("RIGHT", r, "RIGHT", -12, 0)
                        elseif r._colFill then
                            r._colCtrl:SetPoint("RIGHT", r._colFill, "LEFT", -8, 0)
                        end
                        if r._colLabel then r._colLabel:SetPoint("RIGHT", r, "LEFT", col - 6, 0) end
                    end
                end
            end
            local fullH = math.max(10, -by + 3)
            local f = sec.f or 1
            local shownH = (f >= 1) and fullH or math.max(2, math.floor(fullH * f + 0.5))
            sec.box:SetShown(not (sec.collapsed and f <= 0))
            sec.box:SetHeight(shownH)
            local bottom = boxTop - (sec.box:IsShown() and shownH or 0) - LAY.gap
            if side == "L" then pairTopY, pairBottomY, y = topY, bottom, bottom
            elseif side == "R" then y = math.min(pairBottomY or bottom, bottom); pairTopY, pairBottomY = nil, nil
            else y = bottom end
            end
        end
    end
    -- _contentH is the full laid-out height, so add the scroll offset back.
    pg._contentH = -y + 8 + (pg._scrollOff or 0)
    if pg._scroll then pg._scroll.paint() end

    -- Something was laid out against an unresolved width, so run once more
    -- on the next frame. One re-pass is queued at a time, three in a row at
    -- most, so a page that can never resolve (hidden, zero-width parent)
    -- doesn't spin. The count resets after a pass that resolves.
    if pg._sizeUnresolved then
        if not pg._relayoutQueued and (pg._relayoutTries or 0) < 3 then
            pg._relayoutQueued = true
            pg._relayoutTries = (pg._relayoutTries or 0) + 1
            C_Timer.After(0, function()
                pg._relayoutQueued = nil
                pg._sizeUnresolved = nil
                if pg:IsShown() then AT.LayoutPage(pg) end
            end)
        end
    else
        pg._relayoutTries = nil
    end
end

-- Row builders

-- The checkbox sits next to its label until LayoutPage aligns it to the
-- column. The whole row clicks; desc becomes a hover tooltip.
function AT.RowToggle(pg, label, get, set, visibleFn, desc)
    local row = AT.AddRow(pg, LAY.rowH, visibleFn)
    local lbl = AT.RowLabel(row, label)
    local cb = AT.MakeCheckbox(row)
    cb:SetPoint("LEFT", lbl, "RIGHT", 14, 0)
    cb:SetOn(get())
    local function flip()
        AT.CloseDropdown()
        set(not get()); cb:SetOn(get())
        PlaySound(get() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                         or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        AT.LayoutPage(pg)
    end
    cb:SetScript("OnClick", flip)
    row:EnableMouse(true); row:SetScript("OnMouseUp", flip)
    row:HookScript("OnEnter", function() cb:SetHover(true) end)
    row:HookScript("OnLeave", function() cb:SetHover(false) end)
    -- The checkbox is a child Button that takes the mouse, so hover and the
    -- tooltip are hooked on it too.
    cb:HookScript("OnEnter", function() cb:SetHover(true) end)
    cb:HookScript("OnLeave", function() cb:SetHover(false) end)
    if desc then AT.Tooltip(row, label, desc); AT.Tooltip(cb, label, desc) end
    row._colLabel, row._colCtrl = lbl, cb
    row._sync = function() cb:SetOn(get()) end
    return row
end

-- desc and hint may be strings or functions. hint is dim placeholder text
-- shown while the box is empty: it shows what is in effect without
-- pre-filling, which would save a value the user never set. live = true
-- commits on every user keystroke or paste, not only on focus lost.
function AT.RowInput(pg, label, get, set, visibleFn, desc, hint, live)
    local row = AT.AddRow(pg, LAY.rowH, visibleFn)
    local lbl = AT.RowLabel(row, label)
    -- A fixed 160 wide on the control column, not pinned to the row's far
    -- edge where the field drifts away from its label.
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetSize(160, 18); box:SetPoint("LEFT", row._ctrlX, 0); Skin(box, COL.well)
    box:SetFont(STANDARD_TEXT_FONT, 11, ""); box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]); box:SetAutoFocus(false)
    box:SetText(get() or "")
    local hintFS
    if hint then
        hintFS = box:CreateFontString(nil, "OVERLAY")
        hintFS:SetFont(STANDARD_TEXT_FONT, 11, "")
        hintFS:SetPoint("LEFT", 6, 0); hintFS:SetPoint("RIGHT", -6, 0)
        hintFS:SetJustifyH("LEFT")
        hintFS:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    end
    local function syncHint()
        if not hintFS then return end
        hintFS:SetText(((type(hint) == "function") and hint()) or hint or "")
        hintFS:SetShown((box:GetText() or "") == "")
    end
    syncHint()
    box:SetScript("OnTextChanged", function(self, userInput)
        syncHint()
        if live and userInput then set(self:GetText() or "") end
    end)
    -- The box takes the mouse too, so the tooltip is hooked on it as well.
    if desc then AT.Tooltip(row, label, desc); AT.Tooltip(box, label, desc) end
    local function commit() set(box:GetText() or ""); box:SetText(get() or ""); syncHint() end
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function() box:SetText(get() or ""); box:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1) end)
    box:SetScript("OnEditFocusLost", function() commit(); box:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
    row._colLabel, row._colCtrl = lbl, box
    row._sync = function()
        if not box:HasFocus() then box:SetText(get() or "") end
        syncHint()
    end
    return row
end

function AT.RowDropdown(pg, owner, label, get, set, itemsFn, visibleFn, onSelect)
    local row = AT.AddRow(pg, LAY.rowH, visibleFn)
    local lbl = AT.RowLabel(row, label)
    local dd = AT.MakeDropdown(owner, row, nil, itemsFn, get, set, onSelect)
    dd:SetPoint("LEFT", row._ctrlX, 0)
    row._colLabel, row._colCtrl = lbl, dd
    row._sync = dd.Refresh
    return row
end

function AT.RowColor(pg, label, get, set, visibleFn)
    local row = AT.AddRow(pg, LAY.rowH, visibleFn)
    local lbl = AT.RowLabel(row, label)
    local sw = AT.MakeSwatch(row)
    sw:SetPoint("LEFT", row._ctrlX, 0)
    local function refresh() sw:SetColor(get()) end
    refresh()
    sw:SetScript("OnClick", function()
        AT.CloseDropdown()
        local c = get()
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c[1], g = c[2], b = c[3], hasOpacity = false,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    set({ r, g, b }); refresh()
                end,
                cancelFunc = function() set({ c[1], c[2], c[3] }); refresh() end,
            })
        end
    end)
    row._colLabel, row._colCtrl = lbl, sw
    row._sync = refresh
    return row
end

-- A fixed, Blizzard-length slider with a [-][value][+] stepper after it.
-- minV and maxV may be functions, re-read on every sync, so the range can
-- follow the record.
function AT.RowSlider(pg, label, get, set, minV, maxV, step, isPct, visibleFn)
    local row = AT.AddRow(pg, LAY.rowH, visibleFn)
    local lbl = AT.RowLabel(row, label)
    local s = CreateFrame("Slider", nil, row, "BackdropTemplate")
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    local settingUp = true
    -- isPct: true shows a 0-1 value as a percent; a format string ("%.2f")
    -- shows the raw value with it and takes typed values as they are.
    local fmtStr = type(isPct) == "string" and isPct or nil
    if fmtStr then isPct = false end
    local function fmt(v)
        v = tonumber(v) or 0
        if fmtStr then return fmtStr:format(v)
        elseif isPct then return ("%.0f"):format(v * 100)
        elseif step < 1 then return ("%.1f"):format(v)
        else return ("%d"):format(math.floor(v + 0.5)) end
    end
    local function bounds()
        local lo = (type(minV) == "function") and minV() or minV
        local hi = (type(maxV) == "function") and maxV() or maxV
        lo, hi = tonumber(lo) or 0, tonumber(hi) or 0
        if hi < lo then hi = lo end
        return lo, hi
    end
    local function clamp(v)
        local lo, hi = bounds()
        if v < lo then v = lo elseif v > hi then v = hi end
        if step >= 1 then v = math.floor(v + 0.5) end
        return v
    end
    local function refresh()
        settingUp = true
        local lo, hi = bounds()
        s:SetMinMaxValues(lo, hi)
        s:SetValue(math.max(lo, math.min(hi, get() or 0)))
        if not box:HasFocus() then box:SetText(fmt(get() or 0)) end
        settingUp = false
    end
    local function setVal(v) set(clamp(v)); refresh() end
    local function arrow(glyph, delta)
        local b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(14, 14); Skin(b, COL.well)
        local g = b:CreateFontString(nil, "OVERLAY")
        g:SetFont(STANDARD_TEXT_FONT, 11, ""); g:SetPoint("CENTER")
        g:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3]); g:SetText(glyph)
        b:SetScript("OnClick", function() AT.CloseDropdown(); setVal((get() or (bounds())) + delta) end)
        b:SetScript("OnEnter", function() b:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1) end)
        b:SetScript("OnLeave", function() b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
        return b
    end
    local plus = arrow("+", step)
    local minus = arrow("-", -step)
    box:SetSize(38, 16); Skin(box, COL.well)
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetJustifyH("CENTER"); box:SetAutoFocus(false)
    local function commitTyped(self)
        local n = tonumber(self:GetText())
        if n then if isPct then n = n / 100 end setVal(n) else refresh() end
    end
    box:SetScript("OnEnterPressed", function(self) commitTyped(self); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", commitTyped)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    s:SetOrientation("HORIZONTAL"); s:SetHeight(10)
    s:SetWidth(LAY.sliderW)
    s:SetPoint("LEFT", row._ctrlX, 0)
    minus:SetPoint("LEFT", s, "RIGHT", 8, 0)
    box:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    plus:SetPoint("LEFT", box, "RIGHT", 2, 0)
    Skin(s, COL.well)
    s:SetThumbTexture(WHITE)
    local th = s:GetThumbTexture()
    th:SetSize(8, 10); th:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    s:SetMinMaxValues(bounds()); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    s:SetScript("OnValueChanged", function(_, v)
        if settingUp then return end
        if step >= 1 then v = math.floor(v + 0.5) end
        if not box:HasFocus() then box:SetText(fmt(v)) end
        set(v)
    end)
    refresh()
    row._colLabel, row._colCtrl = lbl, s
    row._sync = refresh
    return row
end

-- An action row: the button sits on the control column like any control.
-- rowLabel (optional, preferred) puts text on the left so the row reads as
-- part of its section; quiet = true for secondary or destructive actions.
function AT.RowButton(pg, label, onClick, visibleFn, w, rowLabel, quiet)
    local row = AT.AddRow(pg, LAY.rowH, visibleFn)
    local b = (quiet and AT.MakeQuietButton or AT.MakeSmallButton)(row, label, w or 150)
    b:SetScript("OnClick", function() AT.CloseDropdown(); onClick() end)
    if rowLabel then
        local lbl = AT.RowLabel(row, rowLabel)
        row._colLabel = lbl
    end
    -- LayoutPage pins _colCtrl to the column, label or not.
    row._colCtrl = b
    row.button = b
    return row
end

-- Several related buttons on one line, aligned to one edge.
-- list = { { label = s, onClick = fn, quiet = bool, visibleFn = fn, w = n }, ... }
-- align = "right" (default) or "left"
function AT.RowActions(pg, list, align, visibleFn)
    local row = AT.AddRow(pg, LAY.rowH + 4, visibleFn)
    local made = {}
    for i, spec in ipairs(list) do
        local b = (spec.quiet and AT.MakeQuietButton or AT.MakeSmallButton)(row, spec.label, spec.w or 150)
        b:SetScript("OnClick", function() AT.CloseDropdown() spec.onClick() end)
        made[i] = { btn = b, vis = spec.visibleFn }
    end
    -- Re-packed every pass, so a button showing or hiding leaves no hole.
    row._sync = function()
        local shown = {}
        for _, m in ipairs(made) do
            if (not m.vis) or m.vis() then shown[#shown + 1] = m.btn else m.btn:Hide() end
        end
        local prev
        for _, b in ipairs(shown) do
            b:ClearAllPoints()
            if align == "left" then
                if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
                else b:SetPoint("LEFT", 12, 0) end
            else
                if prev then b:SetPoint("RIGHT", prev, "LEFT", -8, 0)
                else b:SetPoint("RIGHT", -12, 0) end
            end
            b:Show()
            prev = b
        end
    end
    return row
end

-- A hairline between two parts of one section that don't need two headers.
function AT.RowDivider(pg, visibleFn)
    local row = AT.AddRow(pg, 9, visibleFn)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetVertexColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    line:SetPoint("LEFT", 12, 0)
    line:SetPoint("RIGHT", -12, 0)
    line:SetHeight(1)
    row._sync = function() line:SetHeight(AT.Hairline(row)) end
    return row
end

function AT.RowDesc(pg, text, h, visibleFn)
    local row = AT.AddRow(pg, h or LAY.descH, visibleFn)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -2)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3]); fs:SetText(text)
    -- The text wraps and the row grows to hold it (h is a minimum). The width
    -- comes from the page: the row itself is unsized on the first pass.
    row._minH = h or LAY.descH
    row._sync = function()
        local w = pg:GetWidth() or 0
        -- No width yet: flag the page so LayoutPage runs again once it exists.
        if w < 60 then pg._sizeUnresolved = true return end
        fs:SetWidth(w - 36)
        local want = math.max(row._minH, math.floor((fs:GetStringHeight() or 12) + 8))
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    return row
end

-- Discord footer

-- Addons cannot open URLs, so the button shows a copy popup with the invite
-- selected for Ctrl+C. Reserve ~34px at the window bottom for the footer band.
function AT.AddDiscordFooter(p, globalName)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    line:SetPoint("BOTTOMLEFT", 10, 32); line:SetPoint("BOTTOMRIGHT", -10, 32)
    line:SetHeight(1)
    local b = CreateFrame("Button", nil, p, "BackdropTemplate")
    b:SetSize(84, 20); b:SetPoint("BOTTOMLEFT", 10, 9); Skin(b, COL.well)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, ""); fs:SetPoint("CENTER")
    fs:SetText("|cff7289DADiscord|r")
    local hint = p:CreateFontString(nil, "OVERLAY")
    hint:SetFont(STANDARD_TEXT_FONT, 11, "")
    hint:SetPoint("LEFT", b, "RIGHT", 10, 0)
    hint:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    hint:SetText("Questions or help? Join the Arc UI Discord")
    b:SetScript("OnEnter", function()
        b:SetBackdropBorderColor(COL.blurple[1], COL.blurple[2], COL.blurple[3], 1)
    end)
    b:SetScript("OnLeave", function()
        b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
    end)
    b:SetScript("OnClick", function()
        if not AT.copyPopup then
            local d = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
            d:SetSize(300, 70); d:SetFrameStrata("FULLSCREEN_DIALOG"); d:SetToplevel(true)
            Skin(d, COL.panel, COL.arc)
            local t = d:CreateFontString(nil, "OVERLAY")
            t:SetFont(STANDARD_TEXT_FONT, 12, ""); t:SetPoint("TOP", 0, -10)
            t:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            t:SetText("Press Ctrl+C to copy, then open it in your browser")
            local eb = CreateFrame("EditBox", nil, d, "BackdropTemplate")
            eb:SetSize(272, 22); eb:SetPoint("TOP", 0, -32); Skin(eb, COL.well)
            eb:SetFont(STANDARD_TEXT_FONT, 12, ""); eb:SetTextInsets(6, 6, 0, 0)
            eb:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]); eb:SetAutoFocus(false)
            eb:SetScript("OnEscapePressed", function() d:Hide() end)
            eb:SetScript("OnEnterPressed", function() d:Hide() end)
            eb:SetScript("OnEditFocusLost", function() d:Hide() end)
            if globalName then tinsert(UISpecialFrames, globalName) end
            d.box = eb; AT.copyPopup = d
        end
        AT.copyPopup:ClearAllPoints()
        AT.copyPopup:SetPoint("CENTER", p, "CENTER", 0, 0)
        AT.copyPopup:Show(); AT.copyPopup:Raise()
        AT.copyPopup.box:SetText(AT.DISCORD)
        AT.copyPopup.box:SetFocus(); AT.copyPopup.box:HighlightText()
    end)
    return b
end

-- A toc-loaded file's return value is discarded, so AT goes on the addon
-- namespace.
local _ADDON, NS = ...
NS.AT = AT
