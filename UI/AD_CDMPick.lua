-- AD_CDMPick: the From Cooldown Manager card's pick window: which entries come in, and what each Tracked Buff becomes.
-- Owns the window; UI\AD_CDMMirrorOptions.lua opens it from the card and Core\AD_CDMMirror.lua builds the picks (M.Build).
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local Tr = NS.AT.Tr

local CP = {}
Options.CDMPick = CP

-- two columns: the auras left, the cooldowns right
CP.LEFT = { "TrackedBuff", "TrackedBar" }
CP.RIGHT = { "Essential", "Utility" }
CP.PAD, CP.COL_W, CP.COL_GAP = 10, 430, 20
CP.W = 2 * CP.PAD + 2 * CP.COL_W + CP.COL_GAP
CP.CAP_H, CP.ROW_H, CP.SEC_GAP, CP.FOOT_H = 22, 34, 10, 40
CP.ICON = 24
-- a row: tick, icon, name, then the pill (and a Tracked Buff's dropdown) on the right
CP.CB_X, CP.ICON_X, CP.TEXT_X, CP.RIGHT_X = 8, 34, 66, 8
CP.DD_W, CP.LOOK_W = 118, 137
CP.DIM = 0.45
CP.AS = { { value = "aura", text = "Aura" }, { value = "totem", text = "Totem only" } }
CP.LOOKS = { { value = "its", text = "Its look" }, { value = "arc", text = "Arc Auras look" } }

CP.on, CP.as = {}, {}
CP.look = "its"

function CP.IsOpen()
    return CP.win ~= nil and CP.win:IsShown() == true
end

-- A font string's whole width, never its cut-off one.
function CP.TextW(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth()
    return type(w) == "number" and w or 0
end

-- What one entry is called and drawn with, from the piece a build makes of it.
function CP.Words(p)
    local M = NS.CDMMirror
    if p.kind == "item" then
        local item = M.CategoryStartItem(p.spellCategoryID)
        return Tr(M.ItemName(p.spellCategoryID)), item and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)
    end
    if p.kind == "trinket" then
        return Tr(p.slot == 14 and "Trinket 2" or "Trinket 1"), GetInventoryItemTexture and GetInventoryItemTexture("player", p.slot)
    end
    local sid = (p.aura and p.aura.spellID) or p.art or p.spellID
    local art = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid) -- raw-id: the entry's own picture
    return p.name or M.NameOf(sid) or tostring(sid), art
end

-- the pill an entry's row shows: what it becomes
function CP.Pill(e)
    if e.tracked then return Options.IconPillText(CP.as[e.id] == "totem" and "totem" or "aura") end
    if e.p.kind == "aurabar" then return Options.RecPillText({ type = "bar", barKind = "aura", barMode = "duration" }) end
    return Options.IconPillText(e.p.kind)
end

-- The window's bars from the Cooldown Manager as it stands, each entry once.
function CP.Read()
    local plan, why = NS.CDMMirror.PickList()
    if not plan then return nil, why end
    local bars = {}
    for _, part in ipairs(plan) do
        local list = {}
        for i, id in ipairs(part.ids) do
            local p = part.pieces[i]
            local name, art = CP.Words(p)
            list[#list + 1] = { id = id, p = p, name = name, art = art, tracked = part.viewer.cat == "TrackedBuff" }
        end
        bars[part.viewer.cat] = { viewer = part.viewer, list = list }
    end
    return bars
end

-- every bar the window lists, shown or empty, in its column's order
function CP.Viewer(cat)
    for _, v in ipairs(NS.CDMMirror.VIEWERS) do
        if v.cat == cat then return v end
    end
end

function CP.Entries()
    local out = {}
    for _, cols in ipairs({ CP.LEFT, CP.RIGHT }) do
        for _, cat in ipairs(cols) do
            local b = CP.bars and CP.bars[cat]
            for _, e in ipairs(b and b.list or {}) do out[#out + 1] = e end
        end
    end
    return out
end

-- picks for M.Build: true, "totem" for a Tracked Buff picked Totem only, nil left out
function CP.Picks()
    local picks, n = {}, 0
    for _, e in ipairs(CP.Entries()) do
        if CP.on[e.id] then
            picks[e.id] = (e.tracked and CP.as[e.id] == "totem") and "totem" or true
            n = n + 1
        end
    end
    return picks, n
end

-- The card in its hover look while the window is open, at rest otherwise.
function CP.PaintCard()
    local NL, MO = NS.NewLayout, NS.CDMMirrorOptions
    local row = NL and NL.tplRow
    for _, c in ipairs(row and row._cards or {}) do
        if MO and c.entry == MO.entry then NL.Paint(c, CP.IsOpen() or (c:IsMouseOver() == true)) end
    end
end

-- One row: tick, the entry's picture, its name, its pill; a Tracked Buff adds
-- its Aura / Totem only dropdown. A click on the row ticks it.
function CP.MakeRow(parent)
    local AT, COL = NS.AT, NS.AT.COL
    local r = CreateFrame("Button", nil, parent)
    r:RegisterForClicks("LeftButtonUp")
    r:SetHeight(CP.ROW_H)
    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(COL.sel[1], COL.sel[2], COL.sel[3], 1)
    r.hover:Hide()
    r.cb = AT.MakeCheckbox(r)
    r.cb:SetPoint("LEFT", CP.CB_X, 0)
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetColorTexture(0, 0, 0, 1)
    r.edge:SetSize(CP.ICON, CP.ICON)
    r.edge:SetPoint("LEFT", CP.ICON_X, 0)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:SetSize(CP.ICON - 2, CP.ICON - 2)
    r.icon:SetPoint("CENTER", r.edge, "CENTER", 0, 0)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(AT.FONT, 13, "")
    r.name:SetJustifyH("LEFT")
    -- a long spell name takes a second line rather than being cut
    r.name:SetWordWrap(true)
    if r.name.SetMaxLines then r.name:SetMaxLines(2) end
    r.name:SetPoint("LEFT", CP.TEXT_X, 0)
    r.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    r.pill = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.pill:SetHeight(13)
    AT.Skin(r.pill, COL.box, COL.line)
    r.pill.fs = r.pill:CreateFontString(nil, "OVERLAY")
    r.pill.fs:SetFont(AT.FONT, 9, "")
    r.pill.fs:SetPoint("CENTER", 0, 0)
    r.dd = AT.MakeDropdown(CP.win, r, CP.DD_W, function() return CP.AS end,
        function() return CP.as[r._adId] end,
        function(v) CP.as[r._adId] = v end,
        function() CP.FillPill(r) end)
    r.dd:SetPoint("RIGHT", -CP.RIGHT_X, 0)
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    r.line:SetPoint("BOTTOMLEFT", 0, 0)
    r.line:SetPoint("BOTTOMRIGHT", 0, 0)
    local function Flip() CP.Flip(r._adId) end
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

-- The pill beside the name says what the entry becomes; a row left out dims
-- and drops its pill.
function CP.FillPill(r)
    local AT = NS.AT
    local e = r._adEntry
    local on = CP.on[e.id] == true
    local text, c = CP.Pill(e)
    r.pill.fs:SetText(Tr(text))
    r.pill:SetWidth(math.ceil(CP.TextW(r.pill.fs)) + 10)
    AT.PaintPill(r.pill, r.pill.fs, c, 0.45)
    r.pill:ClearAllPoints()
    if e.tracked then
        r.pill:SetPoint("RIGHT", r.dd, "LEFT", -8, 0)
    else
        r.pill:SetPoint("RIGHT", -CP.RIGHT_X, 0)
    end
    r.pill:SetShown(on)
    r.cb:SetOn(on)
    local a = on and 1 or CP.DIM
    r.icon:SetAlpha(a)
    r.edge:SetAlpha(a)
    r.name:SetAlpha(a)
end

function CP.FillRow(r, e, last)
    local AT = NS.AT
    r._adId, r._adEntry = e.id, e
    r.icon:SetTexture(e.art)
    r.name:SetText(e.name)
    r.dd:SetShown(e.tracked)
    if e.tracked then r.dd.Refresh() end
    CP.FillPill(r)
    -- the name stops short of the pill and the dropdown, never under them
    local right = CP.RIGHT_X + (e.tracked and (CP.DD_W + 8) or 0) + r.pill:GetWidth() + 8
    r.name:SetWidth(math.max(40, CP.COL_W - CP.TEXT_X - right))
    r.line:SetHeight(AT.Hairline(r))
    r.line:SetShown(not last)
end

-- A bar's titled box: its caption strip with All / None, then its rows or a
-- quiet line when the Cooldown Manager has none; returns its height.
function CP.MakeSection(parent)
    local AT, COL = NS.AT, NS.AT.COL
    local s = {}
    s.cap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    s.cap:SetSize(CP.COL_W, CP.CAP_H)
    AT.Skin(s.cap, COL.btn, COL.line2)
    s.cap.fs = s.cap:CreateFontString(nil, "OVERLAY")
    s.cap.fs:SetFont(AT.FONT, 10, "")
    s.cap.fs:SetPoint("LEFT", 9, 0)
    s.cap.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local function Word(text, fn)
        local b = CreateFrame("Button", nil, s.cap)
        b.fs = b:CreateFontString(nil, "OVERLAY")
        b.fs:SetFont(AT.FONT, 10, "")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(Tr(text))
        b:SetSize(math.ceil(CP.TextW(b.fs)) + 6, CP.CAP_H)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function() b.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]) end)
        b:SetScript("OnLeave", function() CP.PaintWords(s) end)
        return b
    end
    s.none = Word("None", function() CP.SetAll(s, false) end)
    s.none:SetPoint("RIGHT", -6, 0)
    s.all = Word("All", function() CP.SetAll(s, true) end)
    s.all:SetPoint("RIGHT", s.none, "LEFT", -6, 0)
    s.box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    s.box:SetWidth(CP.COL_W)
    s.box:SetPoint("TOPLEFT", s.cap, "BOTTOMLEFT", 0, 0)
    AT.Skin(s.box, COL.box, COL.line2)
    s.box._atEdges.top:Hide()
    s.empty = s.box:CreateFontString(nil, "OVERLAY")
    s.empty:SetFont(AT.FONT, 11, "")
    s.empty:SetPoint("LEFT", 10, 0)
    s.empty:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    s.pool = {}
    return s
end

-- All / None light while they hold
function CP.PaintWords(s)
    local COL = NS.AT.COL
    local all, none = #s.list > 0, #s.list > 0
    for _, e in ipairs(s.list) do
        if CP.on[e.id] then none = false else all = false end
    end
    local a = all and COL.arc or COL.dim
    local n = none and COL.arc or COL.dim
    s.all.fs:SetTextColor(a[1], a[2], a[3])
    s.none.fs:SetTextColor(n[1], n[2], n[3])
end

function CP.FillSection(s, cat)
    local AT = NS.AT
    local v = CP.Viewer(cat)
    local b = CP.bars and CP.bars[cat]
    s.cat, s.list = cat, b and b.list or {}
    local word = Tr(v.name)
    s.cap.fs:SetText(word:find("[\128-\255]") and word or word:upper())
    local any = #s.list > 0
    s.all:SetShown(any)
    s.none:SetShown(any)
    s.empty:SetShown(not any)
    s.empty:SetText(Tr("Your Cooldown Manager has no %s."):format(word))
    local e = AT.Hairline(s.box)
    local y = 0
    for i, ent in ipairs(s.list) do
        local r = s.pool[i]
        if not r then
            r = CP.MakeRow(s.box)
            s.pool[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", s.box, "TOPLEFT", e, -y)
        r:SetPoint("TOPRIGHT", s.box, "TOPRIGHT", -e, -y)
        CP.FillRow(r, ent, i == #s.list)
        r:Show()
        y = y + CP.ROW_H
    end
    for i = #s.list + 1, #s.pool do s.pool[i]:Hide() end
    local h = (any and y or CP.ROW_H) + e
    s.box:SetHeight(h)
    CP.PaintWords(s)
    return CP.CAP_H + h
end

function CP.SetAll(s, on)
    NS.AT.CloseDropdown()
    for _, e in ipairs(s.list) do CP.on[e.id] = on or nil end
    for _, r in ipairs(s.pool) do
        if r:IsShown() then CP.FillPill(r) end
    end
    CP.PaintWords(s)
    PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    CP.SyncCount()
end

function CP.Flip(id)
    if not id then return end
    NS.AT.CloseDropdown()
    CP.on[id] = (not CP.on[id]) or nil
    for _, s in ipairs(CP.secs or {}) do
        for _, r in ipairs(s.pool) do
            if r._adId == id and r:IsShown() then CP.FillPill(r) end
        end
        CP.PaintWords(s)
    end
    PlaySound(CP.on[id] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    CP.SyncCount()
end

-- Builds the window once; every open refills it.
function CP.Build()
    if CP.win then return CP.win end
    local AT, COL = NS.AT, NS.AT.COL
    local win = AT.CreateWindow(nil, {
        w = CP.W, h = 300, minW = CP.W, minH = 120, resizable = false,
        scaleH = Options.MAIN_H, title = Tr("From Cooldown Manager"),
    })
    CP.win = win
    win:Hide()
    win:HookScript("OnHide", function() CP.Teardown() end)
    -- Esc shuts this window only, never the options window under it
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
    CP.secs = {}
    for c, cols in ipairs({ CP.LEFT, CP.RIGHT }) do
        for i in ipairs(cols) do
            local s = CP.MakeSection(win)
            s.col, s.slot = c, i
            CP.secs[#CP.secs + 1] = s
        end
    end
    local foot = win:CreateTexture(nil, "ARTWORK")
    foot:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    foot:SetPoint("BOTTOMLEFT", 1, CP.FOOT_H)
    foot:SetPoint("BOTTOMRIGHT", -1, CP.FOOT_H)
    foot:SetHeight(AT.Hairline(win))
    CP.foot = foot
    local lookFs = win:CreateFontString(nil, "OVERLAY")
    lookFs:SetFont(AT.FONT, 11, "")
    lookFs:SetPoint("LEFT", win, "BOTTOMLEFT", CP.PAD, CP.FOOT_H / 2)
    lookFs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    lookFs:SetText(Tr("Look"))
    CP.lookFs = lookFs
    local look = AT.MakeDropdown(win, win, CP.LOOK_W, function() return CP.LOOKS end,
        function() return CP.look end, function(v) CP.look = v end)
    look:SetPoint("LEFT", lookFs, "RIGHT", 10, 0)
    -- in the foot its list opens upward, inside the window
    look:HookScript("OnClick", function()
        local list = AT.openDropdown
        if list and list._owner == look then
            list:ClearAllPoints()
            list:SetPoint("BOTTOMRIGHT", look, "TOPRIGHT", 0, 1)
        end
    end)
    CP.lookDD = look
    local create = AT.MakeSmallButton(win, "Create layout", 110)
    create:SetPoint("BOTTOMRIGHT", -CP.PAD, (CP.FOOT_H - 22) / 2)
    create.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    create:SetScript("OnClick", function() CP.Create() end)
    CP.createBtn = create
    local cancel = AT.MakeQuietButton(win, "Cancel", 64)
    cancel:SetPoint("RIGHT", create, "LEFT", -7, 0)
    cancel:SetScript("OnClick", function() win:Hide() end)
    CP.cancelBtn = cancel
    local count = win:CreateFontString(nil, "OVERLAY")
    count:SetFont(AT.FONT, 11, "")
    count:SetPoint("RIGHT", cancel, "LEFT", -10, 0)
    count:SetJustifyH("RIGHT")
    CP.count = count
    return win
end

-- Places the sections in their columns and sizes the window to the taller one.
function CP.Layout()
    local AT, win = NS.AT, CP.win
    local top = 1 + 30 + CP.PAD
    local colH = { 0, 0 }
    for _, s in ipairs(CP.secs) do
        local cat = (s.col == 1 and CP.LEFT or CP.RIGHT)[s.slot]
        local gap = colH[s.col] > 0 and CP.SEC_GAP or 0
        s.cap:ClearAllPoints()
        s.cap:SetPoint("TOPLEFT", win, "TOPLEFT", CP.PAD + (s.col - 1) * (CP.COL_W + CP.COL_GAP), -(top + colH[s.col] + gap))
        colH[s.col] = colH[s.col] + gap + CP.FillSection(s, cat)
    end
    local h = top + math.max(colH[1], colH[2]) + CP.PAD + CP.FOOT_H + 1
    win:SetHeight(h)
    CP.h = h
    CP.lookDD.Refresh()
    if win:IsShown() then AT.SnapWindow(win) end
    CP.SyncCount()
end

function CP.SyncCount()
    local COL = NS.AT.COL
    local _, n = CP.Picks()
    local total = #CP.Entries()
    local c = n > 0 and COL.ink or COL.faint
    CP.count:SetText(n > 0 and Tr("%d of %d to import"):format(n, total) or Tr("Nothing picked"))
    CP.count:SetTextColor(c[1], c[2], c[3])
    CP.createBtn:SetEnabled(n > 0)
    CP.createBtn:SetAlpha(n > 0 and 1 or CP.DIM)
end

-- Opens fresh over the page: every entry ticked, every Tracked Buff as Aura,
-- the Cooldown Manager's look, so Create alone builds what the card always
-- built. Nothing to build: the card's line says why.
function CP.Open()
    if InCombatLockdown() or CP.IsOpen() then return end
    local AT, MO = NS.AT, NS.CDMMirrorOptions
    AT.CloseDropdown()
    local bars, why = CP.Read()
    if not bars then
        if MO then MO.Say(MO.SAY[why] or MO.SAY.read) end
        return
    end
    local win = CP.Build()
    CP.bars = bars
    wipe(CP.on)
    wipe(CP.as)
    for _, e in ipairs(CP.Entries()) do
        CP.on[e.id] = true
        if e.tracked then CP.as[e.id] = "aura" end
    end
    CP.look = "its"
    CP.Layout()
    local main = _G.ArcUIv2Options
    win:ClearAllPoints()
    if main and main:IsShown() then
        win:SetFrameLevel(main:GetFrameLevel() + 40)
        win:SetPoint("TOP", main, "TOP", 0, -math.max(8, math.floor(((main:GetHeight() or 0) - CP.h) / 2)))
        if not CP.hooked then
            -- the options window going (closed, or combat) takes this one with it
            CP.hooked = true
            main:HookScript("OnHide", function()
                if CP.IsOpen() then CP.win:Hide() end
            end)
        end
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    if win.SetPropagateKeyboardInput then win:SetPropagateKeyboardInput(true) end
    win:Show()
    CP.PaintCard()
end

-- Every exit (Cancel, the x, Esc, Create, the options window closing) ends
-- here: nothing picked is kept and the card goes back to rest.
function CP.Teardown()
    NS.AT.CloseDropdown()
    wipe(CP.on)
    wipe(CP.as)
    CP.bars = nil
    CP.PaintCard()
end

-- The picks into a new layout, then the turn-off question, as the card asked before.
function CP.Create()
    local picks, n = CP.Picks()
    if n == 0 then return nil end
    local MO = NS.CDMMirrorOptions
    local look = CP.look == "its"
    CP.win:Hide()
    local rec, why = NS.CDMMirror.Build(look, picks)
    if not rec then
        if MO then MO.Say(MO.SAY[why] or MO.SAY.read) end
        return nil
    end
    Options.OpenLayout(rec)
    if MO then MO.OfferOff() end
    return rec
end
