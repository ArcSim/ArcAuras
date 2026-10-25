-- AD_ProcsPick: the New Layout page's Arc Procs card and its pick window (retail only).
-- Owns the card (NL.AddOwnCard, first after the templates) and the window; Create makes every pick through Options.SpecialCreate, the Add window's own path.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local Tr = NS.AT.Tr

local PK = {}
Options.ProcsPick = PK

-- the new layout's and its group's name
PK.NAME = "Arc Procs"
PK.W, PK.PAD, PK.GAP = 512, 10, 10
PK.CAP_H, PK.ROW_H, PK.FOLD_H, PK.FOOT_H = 22, 40, 22, 40
PK.ICON = 26
-- the window's top under the options window's top, while it fits there
PK.TOP = 125
-- a row: tick, icon and words, each 9 apart
PK.CB_X, PK.ICON_X, PK.TEXT_X, PK.RIGHT = 9, 36, 71, 9
-- where the group and the deck bars land, for a screen 900 units tall
PK.GROUP_Y, PK.BAR_Y, PK.BAR_STEP = -40, -107, 54
-- a disabled Create
PK.DIM = 0.45

PK.picks = {}
PK.fold = false
PK.mine, PK.other = {}, {}

function PK.On()
    local SO = Options.Special
    return SO ~= nil and SO.On() == true
end

function PK.IsOpen()
    return PK.win ~= nil and PK.win:IsShown() == true
end

-- The player's class's trackers and the every-class ones, then every other
-- class's, each in the registry's order.
function PK.Lists()
    local SO, SP = Options.Special, NS.Special
    local mine, other = {}, {}
    if not (SO and SP) then return mine, other end
    SP.Each(function(def, id)
        if SO.ForClass(def) then mine[#mine + 1] = id else other[#other + 1] = id end
    end)
    return mine, other
end

-- ticked to start: a tracker written for the current spec
function PK.ForSpec(def)
    local spec = NS.Store.CurSpecID()
    if not (spec and def and def.specs) then return false end
    for _, s in ipairs(def.specs) do
        if s == spec then return true end
    end
    return false
end

-- the words beside a name: the spec for the class's own, "Every class" for
-- one of no class, the class and spec for another class's
function PK.Sub(def, mine)
    local SO = Options.Special
    if not mine then return SO.WhoWords(def) end
    if def.class == nil then return Tr("Every class") end
    return SO.SpecWords(def)
end

function PK.Makes(def)
    return Options.Special.CanBar(def) and Tr("Icon and bar") or Tr("Icon")
end

-- the picks in the window's order: the class's, then the fold's
function PK.Picked()
    local out = {}
    for _, list in ipairs({ PK.mine, PK.other }) do
        for _, id in ipairs(list) do
            if PK.picks[id] then out[#out + 1] = id end
        end
    end
    return out
end

-- A layout name nobody uses yet: the name, then "name 2", "name 3", ...
function PK.FreeName(base)
    local taken = {}
    for _, l in ipairs(NS.Store.Layouts()) do taken[l.name] = true end
    if not taken[base] then return base end
    for i = 2, 999 do
        local n = ("%s %d"):format(base, i)
        if not taken[n] then return n end
    end
    return base
end

-- The card's picture: three of the player's Arc Procs (the spec's first) over
-- a deck bar with a mark for each proc drawn.
function PK.CardIcons()
    local SP = NS.Special
    local mine = PK.Lists()
    local out = {}
    for pass = 1, 2 do
        for _, id in ipairs(mine) do
            local spec = PK.ForSpec(SP.Get(id))
            if #out < 3 and ((pass == 1) == spec) then out[#out + 1] = id end
        end
    end
    return out
end

function PK.DrawCard(stage)
    local AT, COL, SP, SI = NS.AT, NS.AT.COL, NS.Special, NS.SpecialIcon
    stage._adIcons = {}
    for i, id in ipairs(PK.CardIcons()) do
        local x = 38 + (i - 1) * 30
        local edge = stage:CreateTexture(nil, "ARTWORK")
        edge:SetColorTexture(0, 0, 0, 1)
        edge:SetSize(24, 24)
        edge:SetPoint("TOPLEFT", stage, "TOPLEFT", x, -4)
        local t = stage:CreateTexture(nil, "OVERLAY")
        t:SetTexture(SI and SI.ArtOf(SP.Get(id)))
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t:SetSize(22, 22)
        t:SetPoint("TOPLEFT", stage, "TOPLEFT", x + 1, -5)
        stage._adIcons[i] = t
    end
    -- the fill and the marks sit on the bar's own frame, above its box
    local bar = CreateFrame("Frame", nil, stage, "BackdropTemplate")
    bar:SetSize(84, 9)
    bar:SetPoint("TOPLEFT", stage, "TOPLEFT", 38, -38)
    AT.Skin(bar, COL.well, COL.line2)
    local amber = AT.Mute(Options.ICON_PILL_COLORS.special)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(amber[1], amber[2], amber[3], 0.9)
    fill:SetSize(46, 7)
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar._adMarks = {}
    for i, dx in ipairs({ 21, 42, 63 }) do
        local m = bar:CreateTexture(nil, "OVERLAY")
        m:SetColorTexture(COL.ink[1], COL.ink[2], COL.ink[3], 0.9)
        m:SetSize(2, 13)
        m:SetPoint("TOPLEFT", bar, "TOPLEFT", dx, 2)
        bar._adMarks[i] = m
    end
    stage._adBar, bar._adFill = bar, fill
end

-- The card in its hover look while the window is open, at rest otherwise.
function PK.PaintCard()
    local NL = NS.NewLayout
    local row = NL and NL.tplRow
    for _, c in ipairs(row and row._cards or {}) do
        if c.entry == PK.entry then NL.Paint(c, PK.IsOpen() or (c:IsMouseOver() == true)) end
    end
end

-- A font string's whole width, never its cut-off one.
function PK.TextW(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth()
    return type(w) == "number" and w or 0
end

-- One pick row: tick, the tracker's art, name, its spec or class, what it
-- makes, and the Arc Procs tab's line under them. A click anywhere ticks it.
function PK.MakeRow(parent)
    local AT, COL = NS.AT, NS.AT.COL
    local r = CreateFrame("Button", nil, parent)
    r:RegisterForClicks("LeftButtonUp")
    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(COL.sel[1], COL.sel[2], COL.sel[3], 1)
    r.hover:Hide()
    r.cb = AT.MakeCheckbox(r)
    r.cb:SetPoint("LEFT", PK.CB_X, 0)
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetColorTexture(0, 0, 0, 1)
    r.edge:SetSize(PK.ICON, PK.ICON)
    r.edge:SetPoint("LEFT", PK.ICON_X, 0)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:SetSize(PK.ICON - 2, PK.ICON - 2)
    r.icon:SetPoint("CENTER", r.edge, "CENTER", 0, 0)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(AT.FONT, 13, "")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    r.sub = r:CreateFontString(nil, "OVERLAY")
    r.sub:SetFont(AT.FONT, 10, "")
    r.sub:SetWordWrap(false)
    r.sub:SetPoint("LEFT", r.name, "RIGHT", 7, 0)
    r.sub:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    r.pill = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.pill:SetHeight(13)
    AT.Skin(r.pill, COL.box, COL.line)
    r.pill.fs = r.pill:CreateFontString(nil, "OVERLAY")
    r.pill.fs:SetFont(AT.FONT, 9, "")
    r.pill.fs:SetPoint("CENTER", 0, 0)
    r.note = r:CreateFontString(nil, "OVERLAY")
    r.note:SetFont(AT.FONT, 10, "")
    r.note:SetJustifyH("LEFT")
    r.note:SetJustifyV("TOP")
    r.note:SetWordWrap(true)
    r.note:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    r.line:SetPoint("BOTTOMLEFT", 0, 0)
    r.line:SetPoint("BOTTOMRIGHT", 0, 0)
    local function Flip() PK.Flip(r._adId) end
    r:SetScript("OnClick", Flip)
    r.cb:SetScript("OnClick", Flip)
    local function Hot(on)
        r.hover:SetShown(on)
        r.cb:SetHover(on)
    end
    r:SetScript("OnEnter", function() Hot(true) end)
    r:SetScript("OnLeave", function() Hot(false) end)
    r.cb:HookScript("OnEnter", function() Hot(true) end)
    r.cb:HookScript("OnLeave", function() Hot(false) end)
    return r
end

-- A row's words and height for tracker id at width w: the note wraps rather
-- than being cut, and the spec words move under the name when the name line
-- cannot hold them beside the pill.
function PK.FillRow(r, id, mine, w)
    local SO, SP, SI, AT = Options.Special, NS.Special, NS.SpecialIcon, NS.AT
    local def = SP.Get(id)
    r._adId = id
    r.icon:SetTexture(SI and SI.ArtOf(def))
    r.name:SetText(Tr(def.name))
    local sub = PK.Sub(def, mine)
    local note = Tr(SO.NOTES[id] or "")
    r.pill.fs:SetText(PK.Makes(def))
    r.pill:SetWidth(math.ceil(PK.TextW(r.pill.fs)) + 10)
    AT.PaintPill(r.pill, r.pill.fs, Options.ICON_PILL_COLORS.special, 0.45)
    local room = w - PK.TEXT_X - PK.RIGHT - r.pill:GetWidth() - 8
    r.sub:SetText(sub)
    local beside = sub == "" or PK.TextW(r.name) + 7 + PK.TextW(r.sub) <= room
    r.sub:SetShown(beside)
    if not beside then note = sub .. ". " .. note end
    r.note:SetText(note)
    r.note:SetWidth(w - PK.TEXT_X - PK.RIGHT)
    r._adBeside = beside
    local noteH = math.ceil(r.note:GetStringHeight() or 12)
    local content = 15 + 2 + noteH
    local h = math.max(PK.ROW_H, content + 10)
    local top = math.floor((h - content) / 2)
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", PK.TEXT_X, -top)
    r.name:SetHeight(15)
    r.pill:ClearAllPoints()
    r.pill:SetPoint("TOPRIGHT", -PK.RIGHT, -(top + 1))
    r.note:ClearAllPoints()
    r.note:SetPoint("TOPLEFT", PK.TEXT_X, -(top + 17))
    r:SetHeight(h)
    r._adH = h
    r.cb:SetOn(PK.picks[id] == true)
    return h
end

-- A box of rows under a header: its rows from the pool, one under another,
-- a line between them; returns the box's height.
function PK.FillBox(box, pool, ids, mine)
    local AT = NS.AT
    local e = AT.Hairline(box)
    local w = (box:GetWidth() or 0) - 2 * e
    local y = 0
    for i, id in ipairs(ids) do
        local r = pool[i]
        if not r then
            r = PK.MakeRow(box)
            pool[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", box, "TOPLEFT", e, -y)
        r:SetPoint("TOPRIGHT", box, "TOPRIGHT", -e, -y)
        r:SetWidth(w)
        y = y + PK.FillRow(r, id, mine, w)
        r.line:SetHeight(AT.Hairline(r))
        r.line:SetShown(i < #ids)
        r:Show()
    end
    for i = #ids + 1, #pool do pool[i]:Hide() end
    local h = y + e
    box:SetHeight(h)
    return h
end

-- Builds the window once; every open refills it.
function PK.Build()
    if PK.win then return PK.win end
    local AT, COL = NS.AT, NS.AT.COL
    local word = Tr(PK.NAME)
    local rest = word:match("^Arc(%s.+)$")
    local win = AT.CreateWindow(nil, {
        w = PK.W, h = 300, minW = PK.W, minH = 120, resizable = false,
        scaleH = Options.MAIN_H, title = rest and AT.Brand("Arc", rest) or word,
    })
    PK.win = win
    win:Hide()
    win:HookScript("OnHide", function() PK.Teardown() end)
    -- Esc shuts this window only, never the options window under it; the
    -- switch is restricted in combat, where the options window is closed
    win:EnableKeyboard(true)
    win:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    local innerW = PK.W - 2 * PK.PAD
    local cap = CreateFrame("Frame", nil, win, "BackdropTemplate")
    cap:SetSize(innerW, PK.CAP_H)
    cap:SetPoint("TOPLEFT", PK.PAD, -(31 + PK.PAD))
    AT.Skin(cap, COL.btn, COL.line2)
    cap.fs = cap:CreateFontString(nil, "OVERLAY")
    cap.fs:SetFont(AT.FONT, 10, "")
    cap.fs:SetPoint("LEFT", 9, 0)
    cap.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    PK.cap = cap
    local mineBox = CreateFrame("Frame", nil, win, "BackdropTemplate")
    mineBox:SetWidth(innerW)
    mineBox:SetPoint("TOPLEFT", cap, "BOTTOMLEFT", 0, 0)
    AT.Skin(mineBox, COL.box, COL.line2)
    mineBox._atEdges.top:Hide()
    PK.mineBox, PK.minePool = mineBox, {}
    local fold = CreateFrame("Button", nil, win, "BackdropTemplate")
    fold:SetSize(innerW, PK.FOLD_H)
    fold:SetPoint("TOPLEFT", mineBox, "BOTTOMLEFT", 0, -PK.GAP)
    AT.Skin(fold, COL.head, COL.line)
    fold.arrow = AT.MakeChevron(fold)
    fold.arrow:SetPoint("LEFT", 7, 0)
    fold.fs = fold:CreateFontString(nil, "OVERLAY")
    fold.fs:SetFont(AT.FONT, 11, "")
    fold.fs:SetPoint("LEFT", fold.arrow, "RIGHT", 6, 0)
    local function PaintFold(hot)
        local c = hot and COL.ink or COL.title
        fold.fs:SetTextColor(c[1], c[2], c[3])
        fold.arrow:SetColor(hot and COL.ink or COL.chev)
        local f = hot and COL.btnHover or COL.head
        fold:SetBackdropColor(f[1], f[2], f[3], 1)
    end
    PaintFold(false)
    fold:SetScript("OnEnter", function() PaintFold(true) end)
    fold:SetScript("OnLeave", function() PaintFold(false) end)
    fold:SetScript("OnClick", function() PK.ToggleFold() end)
    PK.foldBtn = fold
    local otherBox = CreateFrame("Frame", nil, win, "BackdropTemplate")
    otherBox:SetWidth(innerW)
    otherBox:SetPoint("TOPLEFT", fold, "BOTTOMLEFT", 0, 0)
    AT.Skin(otherBox, COL.box, COL.line)
    otherBox._atEdges.top:Hide()
    PK.otherBox, PK.otherPool = otherBox, {}
    local foot = win:CreateTexture(nil, "ARTWORK")
    foot:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    foot:SetPoint("BOTTOMLEFT", 1, PK.FOOT_H)
    foot:SetPoint("BOTTOMRIGHT", -1, PK.FOOT_H)
    foot:SetHeight(AT.Hairline(win))
    PK.foot = foot
    local count = win:CreateFontString(nil, "OVERLAY")
    count:SetFont(AT.FONT, 11, "")
    count:SetPoint("LEFT", win, "BOTTOMLEFT", PK.PAD, PK.FOOT_H / 2)
    PK.count = count
    local create = AT.MakeSmallButton(win, "Create layout", 110)
    create:SetPoint("BOTTOMRIGHT", -PK.PAD, (PK.FOOT_H - 22) / 2)
    create.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    create:SetScript("OnClick", function() PK.Create() end)
    PK.createBtn = create
    local cancel = AT.MakeQuietButton(win, "Cancel", 64)
    cancel:SetPoint("RIGHT", create, "LEFT", -7, 0)
    cancel:SetScript("OnClick", function() win:Hide() end)
    PK.cancelBtn = cancel
    return win
end

-- Places the boxes and sizes the window to them; a shown window keeps its
-- top and grows down.
function PK.Layout()
    local AT, win = NS.AT, PK.win
    local h = 1 + 30 + PK.PAD + PK.CAP_H + PK.FillBox(PK.mineBox, PK.minePool, PK.mine, true)
    local any = #PK.other > 0
    PK.foldBtn:SetShown(any)
    PK.otherBox:SetShown(any and PK.fold)
    if any then
        PK.foldBtn.fs:SetText(Tr("Other classes (%d)"):format(#PK.other))
        PK.foldBtn.arrow:SetDir(PK.fold and "down" or "right")
        h = h + PK.GAP + PK.FOLD_H
        if PK.fold then h = h + PK.FillBox(PK.otherBox, PK.otherPool, PK.other, false) end
    end
    h = h + PK.GAP + PK.FOOT_H + 1
    win:SetHeight(h)
    PK.h = h
    if win:IsShown() then AT.SnapWindow(win) end
    PK.SyncCount()
end

function PK.SyncCount()
    local COL = NS.AT.COL
    local n = #PK.Picked()
    local c = n > 0 and COL.ink or COL.faint
    PK.count:SetText(n > 0 and Tr("%d picked"):format(n) or Tr("Nothing picked"))
    PK.count:SetTextColor(c[1], c[2], c[3])
    PK.createBtn:SetEnabled(n > 0)
    PK.createBtn:SetAlpha(n > 0 and 1 or PK.DIM)
end

function PK.Flip(id)
    if not id then return end
    NS.AT.CloseDropdown()
    PK.picks[id] = (not PK.picks[id]) or nil
    for _, pool in ipairs({ PK.minePool or {}, PK.otherPool or {} }) do
        for _, r in ipairs(pool) do
            if r._adId == id then r.cb:SetOn(PK.picks[id] == true) end
        end
    end
    PlaySound(PK.picks[id] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    PK.SyncCount()
end

-- the fold keeps its ticks while shut
function PK.ToggleFold()
    NS.AT.CloseDropdown()
    PK.fold = not PK.fold
    PlaySound(PK.fold and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    PK.Layout()
end

-- Opens fresh: the class's list with the current spec's ticked, the other
-- classes' in a shut fold, over the page under the options window's top.
function PK.Open()
    if InCombatLockdown() or not PK.On() or PK.IsOpen() then return end
    local AT, SP = NS.AT, NS.Special
    AT.CloseDropdown()
    local win = PK.Build()
    PK.mine, PK.other = PK.Lists()
    wipe(PK.picks)
    for _, id in ipairs(PK.mine) do
        if PK.ForSpec(SP.Get(id)) then PK.picks[id] = true end
    end
    PK.fold = false
    local nm = UnitClass("player")
    nm = type(nm) == "string" and nm or ""
    PK.cap.fs:SetText(nm:find("[\128-\255]") and nm or nm:upper())
    PK.Layout()
    local main = _G.ArcUIv2Options
    win:ClearAllPoints()
    if main and main:IsShown() then
        win:SetFrameLevel(main:GetFrameLevel() + 40)
        local room = math.floor((main:GetHeight() or 0) - PK.h - 8)
        win:SetPoint("TOP", main, "TOP", 0, -math.max(8, math.min(PK.TOP, room)))
        if not PK.hooked then
            -- the options window going (closed, or combat) takes this one with it
            PK.hooked = true
            main:HookScript("OnHide", function()
                if PK.IsOpen() then PK.win:Hide() end
            end)
        end
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    if win.SetPropagateKeyboardInput then win:SetPropagateKeyboardInput(true) end
    win:Show()
    PK.PaintCard()
end

-- Every exit (Cancel, the x, Esc, Create, the options window closing) ends
-- here: nothing picked is kept and the card goes back to rest.
function PK.Teardown()
    NS.AT.CloseDropdown()
    wipe(PK.picks)
    PK.fold = false
    PK.PaintCard()
end

-- The Arc Procs layout: one Icon Group of the picks, made as the Add window
-- makes them, and a deck bar for each pick with a deck; then it opens.
function PK.Create()
    local ids = PK.Picked()
    if #ids == 0 then return nil end
    local S, SO, SP = NS.Store, Options.Special, NS.Special
    local layout = S.NewLayout(PK.FreeName(PK.NAME))
    local group = S.NewGroup(layout.id, PK.NAME, "cooldown")
    local hgt = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(hgt) ~= "number" or hgt <= 0 then hgt = 768 end
    local k = hgt / 900
    group.pos = { x = 0, y = math.floor(PK.GROUP_Y * k + 0.5) }
    for _, id in ipairs(ids) do
        Options.SpecialCreate({ cat = "Arc Procs", specialId = id }, group.id, layout.id)
    end
    local n = 0
    for _, id in ipairs(ids) do
        if SO.CanBar(SP.Get(id)) then
            local bar = Options.SpecialCreate({ cat = "Arc Procs", specialId = id, specialAs = "bar" }, nil, layout.id)
            if bar then
                bar.pos = { x = 0, y = math.floor((PK.BAR_Y - n * PK.BAR_STEP) * k + 0.5) }
                n = n + 1
            end
        end
    end
    local ui = S.UI()
    ui.expanded = ui.expanded or {}
    ui.expanded[group.id] = true
    S.Dirty("tree")
    PK.win:Hide()
    Options.OpenLayout(layout, "Overview")
    return layout
end

PK.entry = {
    title = "Arc Procs",
    desc = "Pick your class's Arc Procs: each an icon in one group, plus a deck bar where it has a deck.",
    first = true,
    avail = function() return PK.On() end,
    draw = function(stage) PK.DrawCard(stage) end,
    pick = function() PK.Open() end,
    lit = function() return PK.IsOpen() end,
}
if NS.NewLayout and NS.NewLayout.AddOwnCard then NS.NewLayout.AddOwnCard(PK.entry) end
