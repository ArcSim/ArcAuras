local _, ns = ...
if ns.shareOnly then return end

-- The classic look from the picked mockup: dark stone, gold trim, red buttons.
-- Board sizes are drawn 1.17x the game's units; U() turns a board size into game units.
local T = {}
ns.Theme = T

local FONT = "Fonts\\FRIZQT__.TTF"
T.FONT = FONT

T.C = {
    bg = "15110D", frame = "8A6B2A", plaque = "2A1F14", gold = "C9A23A", title = "FFD100", black = "000000",
    insetLine = "4A3A22", inset = "0F0C09", head = "221A11", ink = "E8DCC0", dim = "BFAE8C", faint = "8C7A58",
    rowLine = "241C13", sel = "3B2F1C", red = "7E1212", redTop = "B23A2A", redEdge = "3A0808", input = "0B0907",
    inputLine = "6E5A36", chipOn = "3A2C1A", chipOff = "17120C", chipOffText = "BFA778", catBg = "120E0A",
    box = "15100B", boxLine = "6E5A36", foot = "A88B5A", tabOff = "1E1710", badge = "C41F1F", green = "6FCB7F",
    tipBg = "090C16", tipLine = "5A6478",
}
T.TAG = {
    n = { text = "NEW", fg = "7DCB4F", line = "3D5A26" },
    c = { text = "CHANGED", fg = "FF9D3B", line = "6A4320" },
    o = { text = "CLASSIC", fg = "D8C8A0", line = "6A5A3A" },
    u = { text = "NOT FOUND", fg = "A8A08E", line = "4F483C" },
}
-- where an item comes from (Data.lua D.SOURCE_KINDS)
for key, text in pairs({ raid = "RAID", dungeon = "DUNGEON", quest = "QUEST", world = "WORLD DROP", vendor = "VENDOR",
    mob = "MOB DROP", container = "CONTAINER", crafted = "CRAFTED", gathered = "GATHERED" }) do
    T.TAG[key] = { text = text, fg = "D8C8A0", line = "6A5A3A" }
end
T.QUALITY = { [0] = "9D9D9D", [1] = "FFFFFF", [2] = "1EFF00", [3] = "0070DD", [4] = "A335EE", [5] = "FF8000", [6] = "E6CC80", [7] = "00CCFF" }

function T.U(px)
    return math.floor(px / 1.17 + 0.5)
end
local U = T.U

function T.RGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- an unknown quality (a hidden item's) reads in the panel's quiet ink
function T.QualityHex(q)
    return T.QUALITY[q or 1] or T.C.dim
end

function T.Solid(parent, layer, hex, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetColorTexture(T.RGB(hex))
    return t
end

-- one tooltip of our own for hovering an item: the game's GameTooltip adds comparisons with equipped gear
local itemTip
function T.ItemTip(owner, id)
    if not id then return end
    if not itemTip then
        itemTip = CreateFrame("GameTooltip", "ForeverItemFinderTip", UIParent, "GameTooltipTemplate")
        itemTip:SetFrameStrata("TOOLTIP")
        itemTip:SetClampedToScreen(true)
    end
    itemTip:SetOwner(owner, "ANCHOR_RIGHT")
    itemTip.itemID, itemTip.dataTipFor = id, nil
    -- an item the game cannot draw yet gets the datamined tooltip (Tooltip.lua) until the server sends it; a test run
    -- outside Forever always does, since that client's copy of an old item is not Forever's
    if (not ns.isForever or not C_Item.GetItemInfo(id)) and T.DataTip and T.DataTip(itemTip, id) then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        itemTip:Show()
        return itemTip
    end
    itemTip:SetItemByID(id)
    itemTip:Show()
    return itemTip
end
-- the datamined tooltip up for an item the server just sent: the game's own takes over
function T.ItemArrived(id)
    if ns.isForever and itemTip and itemTip:IsShown() and itemTip.dataTipFor == id and C_Item.GetItemInfo(id) then
        T.ItemTip(itemTip:GetOwner(), id)
    end
end
-- owner: hide only the tip that frame put up (a pop-up timing out leaves a hovered row's tip alone)
function T.HideItemTip(owner)
    if itemTip and (not owner or itemTip:GetOwner() == owner) then itemTip:Hide() end
end
-- an item in this addon's own tooltip was not seen in the game
function T.IsOwnTip(tip)
    return tip ~= nil and tip == itemTip
end

-- a hover shade under the button's text (the HIGHLIGHT layer draws over it and hides the text); it fades in.
-- edge: a thin gold bar on its left, for list choices
function T.Hover(button, hex, edge)
    local t = T.Solid(button, "BACKGROUND", hex, 1)
    t:SetAllPoints()
    t:Hide()
    local bar
    if edge then
        bar = T.Solid(button, "BORDER", T.C.gold)
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        bar:SetWidth(U(3))
        bar:Hide()
    end
    local fade = t:CreateAnimationGroup()
    local a = fade:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.12)
    local function Off()
        fade:Stop()
        t:Hide()
        if bar then bar:Hide() end
    end
    button:HookScript("OnEnter", function()
        t:Show()
        if bar then bar:Show() end
        fade:Play()
    end)
    button:HookScript("OnLeave", Off)
    button:HookScript("OnHide", Off)
    return t, bar
end

-- marks are drawn from two thin bars, never typed as letters
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function Bar(f, w, h)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(WHITE)
    t:SetSize(w, h)
    return t
end

-- a chevron: SetDir("down" / "up")
function T.Chevron(parent, hex)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(12, 12)
    local a1, a2 = Bar(f, 7, 1.5), Bar(f, 7, 1.5)
    function f:SetDir(dir)
        a1:ClearAllPoints()
        a2:ClearAllPoints()
        f.dir = dir
        local s = dir == "up" and -1 or 1
        a1:SetPoint("CENTER", -2, 0.5 * s)
        a1:SetRotation(math.rad(-50 * s))
        a2:SetPoint("CENTER", 2, 0.5 * s)
        a2:SetRotation(math.rad(50 * s))
    end
    function f:SetColor(c)
        local r, g, b = T.RGB(c)
        a1:SetVertexColor(r, g, b, 1)
        a2:SetVertexColor(r, g, b, 1)
    end
    f:SetDir("down")
    f:SetColor(hex or T.C.gold)
    return f
end

-- a cross for close buttons
function T.Cross(parent, size, hex)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local len = size * 1.25
    local a1, a2 = Bar(f, len, 1.75), Bar(f, len, 1.75)
    a1:SetPoint("CENTER")
    a2:SetPoint("CENTER")
    a1:SetRotation(math.rad(45))
    a2:SetRotation(math.rad(-45))
    local r, g, b = T.RGB(hex or T.C.title)
    a1:SetVertexColor(r, g, b, 1)
    a2:SetVertexColor(r, g, b, 1)
    return f
end

local STAR_FILL = ns.MEDIA .. "FIF_Star"
local STAR_LINE = ns.MEDIA .. "FIF_StarLine"
local CHAT_MARK = ns.MEDIA .. "FIF_Chat"
-- the speech bubble of the Link in chat button
function T.ChatMark(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    t:SetTexture(CHAT_MARK)
    t:SetVertexColor(T.RGB(T.C.gold))
    return t
end
function T.Star(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local fill = f:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints()
    fill:SetTexture(STAR_FILL)
    fill:SetVertexColor(T.RGB(T.C.title))
    local line = f:CreateTexture(nil, "OVERLAY")
    line:SetAllPoints()
    line:SetTexture(STAR_LINE)
    f.fill, f.line = fill, line
    function f:SetOn(on, offHex)
        fill:SetShown(on)
        line:SetShown(not on)
        line:SetVertexColor(T.RGB(offHex or T.C.frame))
        f.on = on
    end
    f:SetOn(false)
    return f
end

-- borders in whole physical pixels, so a 1-pixel line never blurs or vanishes at a fractional UI scale; the size
-- holds only for the scale it was set at, so every edge is kept for T.RefitEdges
local edgeList = setmetatable({}, { __mode = "k" })
local function Edge(region, horizontal, pixels)
    edgeList[region] = horizontal and pixels or -pixels
    if PixelUtil and PixelUtil.SetHeight then
        if horizontal then PixelUtil.SetHeight(region, pixels, pixels) else PixelUtil.SetWidth(region, pixels, pixels) end
    else
        if horizontal then region:SetHeight(pixels) else region:SetWidth(pixels) end
    end
end

-- sizes every border again in whole pixels, after a window's scale changed
function T.RefitEdges()
    for region, px in pairs(edgeList) do Edge(region, px > 0, math.abs(px)) end
end

function T.Border(frame, hex, pixels, layer, inset)
    pixels, inset = pixels or 1, inset or 0
    local edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = T.Solid(frame, layer or "BORDER", hex)
        if i <= 2 then
            t:SetPoint(side .. "LEFT", frame, side .. "LEFT", inset, 0)
            t:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", -inset, 0)
            if inset ~= 0 then t:SetPoint(side, frame, side, 0, side == "TOP" and -inset or inset) end
            Edge(t, true, pixels)
        else
            t:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
            Edge(t, false, pixels)
        end
        edges[side] = t
    end
    function edges:SetColor(h)
        local r, g, b = T.RGB(h)
        for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do self[s]:SetColorTexture(r, g, b) end
    end
    return edges
end

function T.Panel(frame, bgHex, lineHex, pixels)
    local bg = T.Solid(frame, "BACKGROUND", bgHex)
    bg:SetAllPoints()
    local border = lineHex and T.Border(frame, lineHex, pixels or 1)
    return bg, border
end

function T.Text(parent, size, hex, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, U(size), "")
    fs:SetTextColor(T.RGB(hex or T.C.ink))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- a flat red button with gold text, lighter on hover
function T.Button(parent, label, w, h, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or U(120), h or U(28))
    local bg = T.Solid(b, "BACKGROUND", T.C.red)
    bg:SetAllPoints()
    local border = T.Border(b, T.C.redEdge, 1)
    border.TOP:SetColorTexture(T.RGB(T.C.redTop))
    local fs = T.Text(b, size or 13, T.C.title)
    fs:SetPoint("CENTER")
    fs:SetText(label)
    b.label = fs
    b:SetScript("OnEnter", function() bg:SetColorTexture(T.RGB("9A1A1A")) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(T.RGB(T.C.red)) end)
    function b:SetLabel(text) fs:SetText(text) end
    if not w then b:SetWidth(math.max(U(60), fs:GetStringWidth() + U(32))) end
    return b
end

function T.EditBox(parent, w, h, numeric)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h or U(24))
    e:SetAutoFocus(false)
    e:SetFont(FONT, U(13), "")
    e:SetTextColor(T.RGB(T.C.ink))
    e:SetTextInsets(U(8), U(8), 0, 0)
    if numeric then e:SetNumeric(true) e:SetMaxLetters(3) end
    T.Panel(e, T.C.input, T.C.inputLine)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local hint = T.Text(e, 13, T.C.faint)
    hint:SetPoint("LEFT", U(8), 0)
    e.hint = hint
    e:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    function e:SetHint(text) hint:SetText(text) end
    return e
end

function T.Check(parent, label, size)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(U(24), U(24))
    local fs = T.Text(c, size or 14, T.C.ink)
    fs:SetPoint("LEFT", c, "RIGHT", U(2), 0)
    fs:SetText(label)
    c.label = fs
    c:SetHitRectInsets(0, -(fs:GetStringWidth() + U(6)), 0, 0)
    return c
end

-- one open list at a time; a press anywhere else closes it (as the game's own menus do), and so does hiding the
-- window. Nothing is laid over the screen to catch that press, so nothing can sit on top of the list's choices.
local openList
local watcher = CreateFrame("Frame")
local function CloseList()
    if openList then
        local l = openList
        openList = nil
        l:Hide()
        if l.owner and l.owner.OnClosed then l.owner:OnClosed() end
    end
    watcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end
watcher:SetScript("OnEvent", function()
    if openList and not openList:IsMouseOver() and not openList.owner:IsMouseOver() then CloseList() end
end)
T.CloseList = CloseList

-- every dropdown made, so a check can measure that no option label is cut off. multi (optional): { isOn(key),
-- toggle(key), label() } makes a pick-several list: each row carries a tick box, a click toggles it and the list
-- stays open, the box shows label()
T.dropdowns = {}
local LIST_ROWS = 12
function T.Dropdown(parent, w, options, get, set, size, multi)
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(w, U(24))
    d.textSize = U(size or 13)
    T.dropdowns[#T.dropdowns + 1] = d
    local _, border = T.Panel(d, T.C.input, T.C.inputLine)
    local fs = T.Text(d, size or 13, T.C.ink)
    fs:SetPoint("LEFT", U(6), 0)
    fs:SetPoint("RIGHT", -U(16), 0)
    local arrow = T.Chevron(d)
    arrow:SetPoint("RIGHT", -U(4), 0)
    d.arrow, d.border = arrow, border
    -- the box answers the mouse: a gold edge while hovered or open
    local function Edge(on) border:SetColor(on and T.C.gold or T.C.inputLine) end
    d:SetScript("OnEnter", function() Edge(true) end)
    d:SetScript("OnLeave", function(self) Edge(openList ~= nil and openList.owner == self) end)
    function d:OnClosed()
        arrow:SetDir("down")
        Edge(self:IsMouseOver())
    end
    d.options = options
    d.multi = multi
    -- boxLabel: a function giving the box its own words instead of the current choice ("+3 more")
    function d:Refresh()
        if multi then fs:SetText(multi.label()) return end
        if self.boxLabel then fs:SetText(self.boxLabel()) return end
        local v = get()
        for _, o in ipairs(self.options) do
            if o[1] == v then fs:SetText(o[2]) return end
        end
        fs:SetText(self.options[1] and self.options[1][2] or "")
    end
    -- the list lives on the screen frame, above every window, so no parent can cover or clip its choices
    local list = CreateFrame("Frame", nil, UIParent)
    list.owner = d
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    list:Hide()
    T.Panel(list, T.C.input, T.C.gold)
    list.rows = {}
    d.list = list
    -- at most LIST_ROWS choices show; a longer list scrolls by wheel or by the bar on its right
    list.offset = 0
    local bar = CreateFrame("Slider", nil, list)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetWidth(U(10))
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    local track = T.Solid(bar, "BACKGROUND", T.C.catBg)
    track:SetAllPoints()
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(T.RGB(T.C.inputLine))
    thumb:SetSize(U(8), U(40))
    bar:SetThumbTexture(thumb)
    -- a click strip wider than the bar, so a near miss still grabs it
    bar:SetHitRectInsets(-U(6), 0, 0, 0)
    list.bar = bar
    local Build
    bar:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= list.offset then
            list.offset = v
            Build()
        end
    end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = list.offset - delta * 2
        Build()
    end)
    function Build()
        local rowH = U(22)
        local n = math.min(#d.options, LIST_ROWS)
        local maxOff = #d.options - n
        list.offset = math.max(0, math.min(maxOff, list.offset))
        local barW = maxOff > 0 and U(12) or 0
        for i = 1, n do
            local o = d.options[list.offset + i]
            local r = list.rows[i]
            if not r then
                r = CreateFrame("Button", nil, list)
                r:SetHeight(rowH)
                T.Hover(r, T.C.sel, true)
                r.text = T.Text(r, size or 13, T.C.ink)
                r.text:SetPoint("LEFT", multi and U(28) or U(10), 0)
                if multi then
                    -- a drawn tick box: an edged square, filled gold while ticked
                    r.box = CreateFrame("Frame", nil, r)
                    r.box:SetSize(U(12), U(12))
                    r.box:SetPoint("LEFT", U(9), 0)
                    T.Panel(r.box, T.C.input, T.C.inputLine)
                    r.tick = T.Solid(r.box, "ARTWORK", T.C.gold)
                    r.tick:SetPoint("TOPLEFT", U(3), -U(3))
                    r.tick:SetPoint("BOTTOMRIGHT", -U(3), U(3))
                end
                r:HookScript("OnEnter", function(self) self.text:SetTextColor(T.RGB("FFFFFF")) end)
                r:HookScript("OnLeave", function(self) self.text:SetTextColor(T.RGB(self.on and T.C.title or T.C.ink)) end)
                list.rows[i] = r
            end
            -- the current choice reads gold (a ticked one, in a pick-several list)
            if multi then r.on = multi.isOn(o[1]) r.tick:SetShown(r.on) else r.on = o[1] == get() end
            r.text:SetTextColor(T.RGB(r.on and T.C.title or T.C.ink))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * rowH)
            r:SetPoint("TOPRIGHT", -1 - barW, -1 - (i - 1) * rowH)
            r.text:SetText(o[2])
            r:SetScript("OnClick", function()
                if multi then
                    multi.toggle(o[1])
                    Build()
                    d:Refresh()
                    return
                end
                CloseList()
                set(o[1])
                d:Refresh()
            end)
            r:Show()
        end
        for i = n + 1, #list.rows do list.rows[i]:Hide() end
        bar:SetMinMaxValues(0, maxOff)
        bar:SetValue(list.offset)
        bar:SetShown(maxOff > 0)
        -- the list is exactly as wide as its box; the bar takes its room from the rows
        list:SetSize(d:GetWidth(), n * rowH + 2)
    end
    d:SetScript("OnClick", function()
        if openList == list then CloseList() return end
        CloseList()
        -- open with the current choice in view
        list.offset = 0
        if not multi then
            for i, o in ipairs(d.options) do
                if o[1] == get() then list.offset = i - math.ceil(LIST_ROWS / 2) end
            end
        end
        Build()
        list:SetScale(d:GetEffectiveScale() / UIParent:GetEffectiveScale())
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -1)
        list:Show()
        list:Raise()
        -- above the rows, so the bar's wider click strip wins over a row's edge
        bar:SetFrameLevel(list:GetFrameLevel() + 3)
        openList = list
        arrow:SetDir("up")
        Edge(true)
        watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    d:SetScript("OnHide", function() if openList == list then CloseList() end end)
    d:Refresh()
    return d
end

-- steady: the drag reads the cursor against where the slider sat when it was pressed, for a slider whose own window
-- moves or scales as the value changes (otherwise the moving track feeds back into the value)
function T.Slider(parent, w, lo, hi, step, get, set, fmt, steady)
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(w, U(16))
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    -- the track in the edge colour: the input colour vanished against the box behind it
    local track = T.Solid(s, "BACKGROUND", T.C.inputLine)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(U(4))
    s.track = track
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(T.RGB(T.C.gold))
    thumb:SetSize(U(10), U(16))
    s:SetThumbTexture(thumb)
    local value = T.Text(s, 13, T.C.ink)
    value:SetPoint("LEFT", s, "RIGHT", U(8), 0)
    s.valueText = value
    s:SetValue(get())
    value:SetText((fmt or "%d"):format(get()))
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        value:SetText((fmt or "%d"):format(v))
        set(v)
    end)
    if steady then
        local grab = CreateFrame("Button", nil, s)
        grab:SetAllPoints()
        s.grab = grab
        local x0, base, span
        local function Apply(v)
            v = math.max(lo, math.min(hi, math.floor(v / step + 0.5) * step))
            if v ~= s:GetValue() then s:SetValue(v) end
        end
        local function Follow()
            Apply(base + (GetCursorPosition() - x0) / span * (hi - lo))
        end
        grab:SetScript("OnMouseDown", function()
            -- screen pixels, fixed for the whole drag
            local eff = s:GetEffectiveScale()
            local left, tw = s:GetLeft() * eff, thumb:GetWidth() * eff
            span = s:GetWidth() * eff - tw
            x0 = GetCursorPosition()
            local at = left + tw / 2 + (s:GetValue() - lo) / (hi - lo) * span
            -- a press beside the thumb moves it under the cursor first
            base = math.abs(x0 - at) > tw / 2 and lo + (x0 - left - tw / 2) / span * (hi - lo) or s:GetValue()
            Apply(base)
            grab:SetScript("OnUpdate", Follow)
        end)
        grab:SetScript("OnMouseUp", function() grab:SetScript("OnUpdate", nil) end)
        grab:SetScript("OnHide", function() grab:SetScript("OnUpdate", nil) end)
    end
    return s
end

-- New / Changed pills and the database filter chips
-- withStar: a filled star before the label (the Favorites chip shows the star and its count, not the word)
function T.Chip(parent, size, withStar)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(U(24))
    local bg = T.Solid(b, "BACKGROUND", T.C.chipOff)
    bg:SetAllPoints()
    local border = T.Border(b, T.C.insetLine, 1)
    local fs = T.Text(b, size or 12, T.C.chipOffText)
    local star
    if withStar then
        star = T.Star(b, U(13))
        star:SetOn(true)
        fs:SetPoint("LEFT", star, "RIGHT", U(4), 0)
        b.star = star
    else
        fs:SetPoint("CENTER")
    end
    b.label = fs
    -- pad: the space each side of the label; a row of chips may narrow it so the row still fits
    b.pad = U(8)
    function b:SetLabel(text)
        fs:SetText(text)
        if star then star:SetPoint("LEFT", self.pad, 0) end
        self:SetWidth(fs:GetStringWidth() + 2 * self.pad + (star and (U(13) + U(4)) or 0))
    end
    function b:SetOn(on)
        self.on = on
        bg:SetColorTexture(T.RGB(on and T.C.chipOn or T.C.chipOff))
        border:SetColor(on and T.C.gold or T.C.insetLine)
        fs:SetTextColor(T.RGB(on and T.C.title or T.C.chipOffText))
        if star then star.fill:SetVertexColor(T.RGB(on and T.C.title or T.C.chipOffText)) end
    end
    return b
end

function T.Tag(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(U(14))
    local border = T.Border(f, "3D5A26", 1)
    local fs = T.Text(f, 10, "7DCB4F")
    fs:SetPoint("CENTER")
    -- text: a tag's own words in that kind's colours (a raid row names its raid)
    function f:Set(kind, text)
        local tag = T.TAG[kind]
        if not tag then self:Hide() return end
        fs:SetText(text or tag.text)
        fs:SetTextColor(T.RGB(tag.fg))
        border:SetColor(tag.line)
        self:SetWidth(fs:GetStringWidth() + U(10))
        self:Show()
    end
    return f
end

-- a titled section: gold heading over a thin line, as on the board
-- with no title the box has no header strip and its content starts at the top (f.top 0)
function T.Section(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    T.Panel(f, T.C.box, T.C.insetLine)
    f.top = 0
    if not title then return f end
    local head = T.Text(f, 12, T.C.title)
    head:SetPoint("TOPLEFT", U(10), -U(6))
    head:SetText(title)
    local line = T.Solid(f, "BORDER", T.C.boxLine)
    line:SetPoint("TOPLEFT", 1, -U(24))
    line:SetPoint("TOPRIGHT", -1, -U(24))
    Edge(line, true, 1)
    f.head = head
    f.top = U(24)
    return f
end

-- a list that only builds the rows that fit; wheel and bar both scroll
function T.List(parent, rowH, makeRow, bindRow)
    local L = CreateFrame("Frame", nil, parent)
    L.rows, L.offset, L.data = {}, 0, {}
    L:EnableMouseWheel(true)
    local bar = CreateFrame("Slider", nil, L)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetWidth(U(10))
    bar:SetValueStep(1)
    local track = T.Solid(bar, "BACKGROUND", T.C.catBg)
    track:SetAllPoints()
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(T.RGB(T.C.inputLine))
    thumb:SetSize(U(8), U(40))
    bar:SetThumbTexture(thumb)
    -- a click strip wider than the bar, so a near miss still grabs it
    bar:SetHitRectInsets(-U(6), 0, 0, 0)
    L.bar = bar
    local function Visible()
        return math.max(1, math.floor((L:GetHeight() or 0) / rowH))
    end
    function L:Refresh()
        local n = Visible()
        local maxOff = math.max(0, #self.data - n)
        if self.offset > maxOff then self.offset = maxOff end
        bar:SetMinMaxValues(0, maxOff)
        bar:SetValue(self.offset)
        bar:SetShown(maxOff > 0)
        for i = 1, n do
            local row = self.rows[i]
            if not row then
                row = makeRow(self)
                row:SetHeight(rowH)
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
            row:SetPoint("TOPRIGHT", maxOff > 0 and -U(12) or 0, -(i - 1) * rowH)
            local item = self.data[self.offset + i]
            if item then bindRow(row, item) row:Show() else row:Hide() end
        end
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
    end
    function L:SetData(data)
        self.data = data or {}
        self:Refresh()
    end
    L:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, self.offset - delta * 2)
        self:Refresh()
    end)
    bar:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= L.offset then L.offset = v L:Refresh() end
    end)
    L:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    return L
end
