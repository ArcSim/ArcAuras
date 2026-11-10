-- AD_ResColorOptions: a resource bar's States table, the bar editor's Effects triggers Power, Spells and
-- Auras. One row per state with what it changes (fill, texts, cost mark, glow), the open row's editor under
-- the table, and Add a state. AD_Options calls Options.ResStateRows while it builds the bar pane; every edit
-- goes through NS.Bars.ResColor.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local Tr = NS.AT.Tr

local RSO = {}
Options.ResStateOptions = RSO

-- Capitals only for plain Latin words: string.upper would split a multibyte
-- letter, and other scripts have no capitals.
local function Upper(s)
    if type(s) ~= "string" or s:find("[\128-\255]") then return s end
    return s:upper()
end

-- The states, in the Add pick's order: a spell's, an aura's, the power's.
-- The aura ones need the aura engine (missing: the client that can draw a
-- look only while it is gone).
RSO.KINDS = {
    { value = "enough", text = "Enough power for a spell" },
    { value = "usable", text = "A spell is usable" },
    { value = "ready", text = "A spell is ready" },
    { value = "recharging", text = "A spell is recharging" },
    { value = "cooldown", text = "A spell is on cooldown" },
    { value = "up", text = "An aura is up" },
    { value = "missing", text = "An aura is missing" },
    { value = "below", text = "Power at or below a value" },
    { value = "above", text = "Power at or above a value" },
    { value = "full", text = "Full power" },
}
-- The triggers that draw this table. A trigger only filters which rows it
-- shows: a row keeps its place in the saved list, so what wins never changes.
RSO.VIEWS = {
    Power = { below = true, above = true, full = true },
    Spells = { enough = true, usable = true, ready = true, recharging = true, cooldown = true },
    Auras = { up = true, missing = true },
}
RSO.VIEW_ORDER = { "Power", "Spells", "Auras" }
-- a power row's rule, on the row itself
RSO.RULES = { { value = "below", text = "At or below" }, { value = "above", text = "At or above" },
    { value = "full", text = "Full power" } }
RSO.GLOWS = { { value = "off", text = "Off" }, { value = "pixel", text = "Pixel" }, { value = "autocast", text = "Autocast" } }
RSO.AURA_IDS = "Aura name or spell IDs"
RSO.NOTE = "Fill and texts: the highest row that holds wins. A glow shows while its row holds."
-- the table's columns, measured from the row's right edge; power is the For
-- column, on an Automatic power bar only
RSO.COLS = { remove = { w = 20 }, move = { w = 30 }, glow = { w = 76 }, mark = { w = 62 }, text = { w = 40 },
    fill = { w = 40 }, power = { w = 52 } }
RSO.GAP = 8
-- a Power row's own controls, left of its first cell: the room beside the trigger list is tight
RSO.RULE_W, RSO.VALUE_W, RSO.ROW_LEFT = 88, 36, 206
-- a power row's value steps by this, and stays in 1 to 99 as a percent
RSO.VALUE_STEP = 5
-- the open row per bar
RSO.sel = {}
-- the state each trigger's Add pick is on
RSO.addKinds = {}
-- an Automatic bar's row for every power, and the look of a row for another
-- power than the one previewed: still there and still clickable
RSO.FOR_ALL = "All powers"
RSO.DIM = 0.42
-- page -> what runs after each layout of it
RSO.after = RSO.after or {}

local function CRm() return NS.Bars and NS.Bars.ResColor end

-- An Automatic power bar: each row can be for one power.
local function ForPower(rec)
    local C = CRm()
    return rec ~= nil and C ~= nil and C.ForPower ~= nil and C.ForPower(rec) == true
end

-- the powers a row can be for: { value, text, color }
local function Powers(rec)
    local C = CRm()
    return (rec and C and C.PowersFor and C.PowersFor(rec)) or {}
end

-- the power the table and the preview show: the picked one, else the one in use
local function PreviewPower()
    local C = CRm()
    local pt = C and C.previewPower
    if pt == nil and UnitPowerType then pt = UnitPowerType("player") end
    return pt
end

-- a power's name and colour, the bar's own list first
local function PowerInfo(rec, pt)
    for _, it in ipairs(Powers(rec)) do
        if it.value == pt then return it.text, it.color end
    end
    local info = NS.Bars and NS.Bars.POWER_ALL and NS.Bars.POWER_ALL[pt]
    if info then return info.name, info.color end
    return tostring(pt), nil
end

-- a For pick's items: each power, the saved one even off the list, then all
local function ForItems(rec, keep)
    local out, has = {}, false
    for _, it in ipairs(Powers(rec)) do
        out[#out + 1] = { value = it.value, text = it.text }
        if it.value == keep then has = true end
    end
    if keep ~= nil and not has then out[#out + 1] = { value = keep, text = (PowerInfo(rec, keep)) } end
    out[#out + 1] = { value = "all", text = RSO.FOR_ALL }
    return out
end

local function StrW(fs)
    return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

-- The picked power is let go: the preview and the Add pick follow the power
-- in use again.
function RSO.ClearPreview()
    RSO.addFor, RSO.pvId = nil, nil
    local C = CRm()
    if not (C and C.previewPower ~= nil) then return end
    C.previewPower = nil
    if NS.Bars.PreviewRepaint then NS.Bars.PreviewRepaint() end
end

-- the words a spell ID is shown by
local function SpellName(id)
    local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed ID, for the row's words
    return (type(nm) == "string" and nm ~= "") and nm or Tr("spell %s"):format(tostring(id))
end

-- A spell state's line, with the spells' names or without: one whole line each.
RSO.SPELL_WORDS = {
    usable = { "%s is usable", "A spell is usable" }, ready = { "%s is ready", "A spell is ready" },
    recharging = { "%s is recharging", "A spell is recharging" },
    cooldown = { "%s is on cooldown", "A spell is on cooldown" },
}

-- A row in words, as drawn: what holds it.
function RSO.Label(r)
    local w = r and r.when or "enough"
    local function Names()
        local n
        for _, sid in ipairs(r.rowSpells or {}) do
            n = n and Tr("%s or %s"):format(n, SpellName(sid)) or SpellName(sid)
        end
        return n
    end
    if w == "enough" then
        local n = Names()
        return n and Tr("Enough for %s"):format(n) or Tr("Enough power for a spell")
    end
    local sw = RSO.SPELL_WORDS[w]
    if sw then
        local n = Names()
        return n and Tr(sw[1]):format(n) or Tr(sw[2])
    end
    if w == "up" or w == "missing" then
        local ids = NS.Store.AuraIDList(r)
        if not ids[1] then return Tr((w == "up") and "An aura is up" or "An aura is missing") end
        local nm = SpellName(ids[1])
        if #ids > 1 then nm = nm .. " (+" .. (#ids - 1) .. ")" end
        return ((w == "up") and Tr("%s is up") or Tr("%s is missing")):format(nm)
    end
    if w == "below" or w == "above" then
        local v = tostring(r.value or 0) .. (r.units and "" or "%")
        return ((w == "below") and Tr("Power at or below %s") or Tr("Power at or above %s")):format(v)
    end
    return Tr("Full power")
end

-- The colour picker on a cell: a pick writes, a cancel puts back what was
-- there (nil: the bar's own).
local function PickColor(c, alpha, set)
    local AT = NS.AT
    AT.CloseDropdown()
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    local had = type(c) == "table"
    if not had then c = (NS.Schema and NS.Schema.RES_COLOR_DEFAULT) or { 0.66, 0.42, 1, 1 } end
    local was = { c[1], c[2], c[3], c[4] or 1 }
    local ready, last = false, nil
    local function pick()
        if not ready then return end
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local v = { r, g, b, alpha and (ColorPickerFrame:GetColorAlpha() or was[4]) or 1 }
        if last and last[1] == v[1] and last[2] == v[2] and last[3] == v[3] and last[4] == v[4] then return end
        last = v
        set(v)
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c[1], g = c[2], b = c[3], hasOpacity = alpha, opacity = alpha and was[4] or nil,
        swatchFunc = pick, opacityFunc = alpha and pick or nil,
        cancelFunc = function() set(had and was or false) end,
    })
    ready = true
    if not had then pick() end
end

-- How many aura rows above row i colour the fill: four lanes at most.
function RSO.AuraFills(rows, i)
    local n = 0
    for k = 1, i - 1 do
        local r = rows[k]
        if r and (r.when == "up" or r.when == "missing") and type(r.fill) == "table" then n = n + 1 end
    end
    return n
end

-- The trigger the table is drawn for, or nil.
function RSO.View()
    local ui = Options.ui
    local s = ui and ui.barSec and ui.barSec.Effects
    return (s ~= nil and RSO.VIEWS[s] ~= nil) and s or nil
end

local function InView(row, view)
    local v = RSO.VIEWS[view]
    return v ~= nil and row ~= nil and v[row.when or "enough"] == true
end
RSO.InView = InView

function RSO.CountIn(rows, view)
    local n = 0
    for i = 1, #rows do
        if InView(rows[i], view) then n = n + 1 end
    end
    return n
end

-- The saved place of the view's n-th row.
function RSO.Slot(rows, view, n)
    local k = 0
    for i = 1, #rows do
        if InView(rows[i], view) then
            k = k + 1
            if k == n then return i end
        end
    end
    return nil
end

-- The view's row at saved place s, else the next one, else the last before it.
function RSO.Near(rows, view, s)
    for i = s, #rows do
        if InView(rows[i], view) then return i end
    end
    for i = math.min(s, #rows), 1, -1 do
        if InView(rows[i], view) then return i end
    end
    return nil
end

-- The view's nearest row above (dir -1) or below (dir 1) saved place i.
function RSO.Step(rows, view, i, dir)
    local k = i + dir
    while rows[k] do
        if InView(rows[k], view) then return k end
        k = k + dir
    end
    return nil
end

-- Swaps a row with its nearest neighbour in the view; the rows the view does
-- not draw stay where they are.
function RSO.MoveInView(CR, rec, view, i, dir)
    local to = RSO.Step(CR.List(rec), view, i, dir)
    if not (to and CR.MoveRow(rec, i, to - i)) then return false end
    local sel = RSO.sel[rec.id]
    if sel == i then
        RSO.sel[rec.id] = to
    elseif sel == to then
        RSO.sel[rec.id] = i
    end
    return true
end

-- What a trigger's Add offers: its own kinds the client can draw.
function RSO.AddItems(view)
    local out = {}
    local v, S = RSO.VIEWS[view], NS.Schema
    if not v then return out end
    for _, it in ipairs(RSO.KINDS) do
        local ok = v[it.value] == true
        if ok and it.value == "up" then ok = S.BarGlowAuraOK(false) end
        if ok and it.value == "missing" then ok = S.BarGlowAuraOK(true) end
        if ok then out[#out + 1] = it end
    end
    return out
end

function RSO.AddKind(view)
    local items = RSO.AddItems(view)
    local k = RSO.addKinds[view]
    for _, it in ipairs(items) do
        if it.value == k then return k end
    end
    return items[1] and items[1].value or nil
end

function RSO.Has(rec, view)
    local C = CRm()
    return C ~= nil and RSO.CountIn(C.List(rec), view) > 0
end

-- Auras is offered where the client can draw one, or a saved row needs a home.
function RSO.AurasOffered(rec)
    return #RSO.AddItems("Auras") > 0 or RSO.Has(rec, "Auras")
end

-- The first trigger holding a row: where a link to the table lands.
function RSO.FirstView(rec)
    for _, v in ipairs(RSO.VIEW_ORDER) do
        if rec and RSO.Has(rec, v) then return v end
    end
    return RSO.VIEW_ORDER[1]
end

-- Remove trigger: this trigger's rows only.
function RSO.RemoveView(rec, view)
    local C = CRm()
    if not C then return end
    local rows = C.List(rec)
    for i = #rows, 1, -1 do
        if InView(rows[i], view) then C.RemoveRow(rec, i) end
    end
end

-- The Power trigger's chips: each row's rule, with its fill's dot.
function RSO.PowerChips(rec)
    local C = CRm()
    local out = {}
    for _, g in ipairs(C and C.List(rec) or {}) do
        if InView(g, "Power") then
            local word = (g.when == "full") and Tr("Full")
                or Tr((g.when == "below") and "under %s" or "over %s"):format(tostring(g.value or 0))
            out[#out + 1] = { text = word, color = type(g.fill) == "table" and g.fill or nil }
        end
    end
    return out
end

do
    local BX = Options.BarEffects
    if BX then
        BX.TRIGGERS["Power"] = { when = "Colors the bar at each power level", line = "Colors the bar at each power level",
            on = function(r) return RSO.Has(r, "Power") end, chips = RSO.PowerChips,
            remove = function(r) RSO.RemoveView(r, "Power") end }
        BX.TRIGGERS["Spells"] = { when = "While a spell is ready, usable or affordable",
            line = "While a spell is ready, usable or affordable",
            on = function(r) return RSO.Has(r, "Spells") end,
            remove = function(r) RSO.RemoveView(r, "Spells") end }
        BX.TRIGGERS["Auras"] = { when = "While an aura is up or missing", line = "While an aura is up or missing",
            on = function(r) return RSO.Has(r, "Auras") end,
            remove = function(r) RSO.RemoveView(r, "Auras") end }
    end
end

-- One of the table's triggers is open on a resource bar: the preview wears the
-- open row then.
function RSO.Open()
    local ui = Options.ui
    if not (ui and ui.barTab == "Effects" and ui.selType == "bar") then return false end
    local r = NS.Store.Get(ui.selId)
    if not (r and r.barKind == "resource") then return false end
    return RSO.View() ~= nil
end

-- vis: the block's own gate. owner: the window the dropdown lists open on.
function Options.ResStateRows(pg, ctx, vis, owner)
    local AT = NS.AT
    local COL = AT.COL
    local Store = NS.Store
    local DA = NS.DriverAura
    local BGO = Options.BarGlowOptions
    local ET = Options.EditorTabs
    local function Rec()
        local r = ctx()
        return (r and r.barKind == "resource" and not r._adMulti and CRm()) and r or nil
    end
    local function Rows()
        local r = Rec()
        return r and CRm().List(r) or {}
    end
    -- a table row is the open trigger's i-th row; Raw is its place in the saved list
    local function Raw(i) return RSO.Slot(Rows(), RSO.View(), i) end
    local function Row(i)
        local k = Raw(i)
        return k and Rows()[k] or nil
    end
    local function Seen() return RSO.CountIn(Rows(), RSO.View()) end
    local function PowerView() return RSO.View() == "Power" end
    -- the open row, kept inside the open trigger; its pick is left alone, so
    -- coming back to a trigger finds it
    local function Sel()
        local r = Rec()
        if not r then return nil end
        return RSO.Near(Rows(), RSO.View(), RSO.sel[r.id] or 1)
    end
    local function SelRow()
        local s = Sel()
        return s and Rows()[s] or nil, s
    end
    -- an edit, then the page again at once (the store's refresh comes a frame later)
    local function Edit(fn)
        local r = Rec()
        if r then fn(CRm(), r) end
        AT.LayoutPage(pg)
    end
    -- the open row's aura pick, written on the row itself (a look's own copy)
    local function AuraEdit(fn)
        local r, s = Rec(), Sel()
        local g = r and s and CRm().MutRow(r, s)
        if not g then return end
        fn(g)
        CRm().Touched(r)
        AT.LayoutPage(pg)
    end
    local function Kind(r) return r and r.when or "enough" end
    local function IsSpell(w) return CRm() ~= nil and CRm().SPELL[w] == true end
    local function IsAura(w) return w == "up" or w == "missing" end
    -- found by the search; the jump lands on the table. view: the trigger it
    -- lands on (the table is one set of rows drawn for all three)
    local function Stamp(row, field, label, view)
        local base = vis
        if view then base = function() return vis() and RSO.View() == view end end
        row._adMeta = { family = "bar", section = "rescolors", field = field, def = { label = label }, baseVis = base }
    end
    local maxR = (CRm() and CRm().MaxRows()) or 12
    -- a pause point between rows: the window builds in slices
    local function Pause() if Options.BuildYield then Options.BuildYield() end end
    -- the largest value a power row takes
    local function UnitMax()
        local r = Rec()
        local K = NS.Bars.Kit
        local e = r and K and K.live[r.id]
        local mx = e and NS.Bars.PlainMax and NS.Bars.PlainMax(e)
        return (mx and mx > 1) and math.floor(mx) or 200
    end
    -- the editor's section and the power tag on its title
    local edSec, tag

    -- The table

    AT.RowDesc(pg, RSO.NOTE, 20, function() return vis() and not PowerView() and Seen() > 0 end)
    -- Power draws its header and Normal even with no row yet
    local function TableVis() return vis() and Rec() ~= nil and (PowerView() or Seen() > 0) end
    local C, GAP = RSO.COLS, RSO.GAP
    -- each cell's right edge, from the row's right
    local right, powerRight = {}, {}
    do
        local x = 8
        for _, k in ipairs({ "remove", "glow", "mark", "text", "fill", "power" }) do
            right[k] = x
            x = x + C[k].w + GAP
            if k == "fill" then RSO.LABEL_RIGHT = x end
        end
        RSO.LABEL_RIGHT_FOR = x
        -- Power: no cost mark, the arrows between Glow and the x
        x = 8
        for _, k in ipairs({ "remove", "move", "glow", "text", "fill", "power" }) do
            powerRight[k] = x
            x = x + C[k].w + GAP
        end
        RSO.POWER_RIGHT = powerRight
    end
    -- the state words end at the first cell: For on an Automatic bar, else Fill
    local function LabelRight(on) return on and RSO.LABEL_RIGHT_FOR or RSO.LABEL_RIGHT end
    local function Cell(row, k)
        local f = CreateFrame("Frame", nil, row)
        f:SetSize(C[k].w, 24)
        f:SetPoint("RIGHT", row, "RIGHT", -right[k], 0)
        row._cells = row._cells or {}
        row._cells[k] = f
        return f
    end
    -- a row's cells on Power's columns or the other triggers'
    local function LayCells(row, power)
        if row._power == power then return end
        row._power = power
        local at = power and powerRight or right
        for k, f in pairs(row._cells) do
            if at[k] then f:SetPoint("RIGHT", row, "RIGHT", -at[k], 0) end
        end
    end
    -- a cell this row has no look for: a dash that says why
    local function Dash(cell, title, body)
        local f = CreateFrame("Frame", nil, cell)
        f:SetSize(18, 22)
        f:SetPoint("LEFT", 0, 0)
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 12, "")
        fs:SetPoint("LEFT", 0, 0)
        fs:SetTextColor(COL.line2[1], COL.line2[2], COL.line2[3])
        fs:SetText("-")
        AT.Tooltip(f, title, body)
        return f
    end
    local function Faint(parent, size)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, size or 10, "")
        fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        fs:SetWordWrap(false)
        return fs
    end

    -- the picked power is the bar's it was picked on, while By State shows
    local function KeepPick()
        local C2 = CRm()
        if not (C2 and C2.previewPower ~= nil) then return end
        local r = Rec()
        if not (r and RSO.pvId == r.id and RSO.Open() and vis() and ForPower(r)) then RSO.ClearPreview() end
    end

    -- Preview as: the power the table and the preview show, a chip per power
    local pv = AT.AddRow(pg, 26, function()
        local r = Rec()
        return vis() and Seen() > 0 and ForPower(r) and #Powers(r) > 0
    end)
    do
        -- on the first line's middle: more powers than fit wrap under the chips
        local lbl = pv:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 11, "")
        lbl:SetPoint("TOPLEFT", 10, -7)
        lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        lbl:SetText(Tr("Preview as"))
        local chips = {}
        local function Paint(b)
            local on, hot = b._on, b._hot
            local bg = on and COL.sel or COL.well
            local e = (on or hot) and COL.arc or COL.line2
            local ink = on and COL.ink or COL.dim
            b:SetBackdropColor(bg[1], bg[2], bg[3], 1)
            b:SetBackdropBorderColor(e[1], e[2], e[3], 1)
            b.fs:SetTextColor(ink[1], ink[2], ink[3])
        end
        local function Chip(j)
            if chips[j] then return chips[j] end
            local b = CreateFrame("Button", nil, pv, "BackdropTemplate")
            b:SetHeight(20)
            AT.Skin(b, COL.well, COL.line2)
            local box = b:CreateTexture(nil, "ARTWORK")
            box:SetTexture(AT.WHITE)
            box:SetVertexColor(0, 0, 0, 1)
            box:SetSize(10, 10)
            box:SetPoint("LEFT", 9, 0)
            b.sq = b:CreateTexture(nil, "OVERLAY")
            b.sq:SetTexture(AT.WHITE)
            b.sq:SetSize(8, 8)
            b.sq:SetPoint("CENTER", box, "CENTER", 0, 0)
            b.fs = b:CreateFontString(nil, "OVERLAY")
            b.fs:SetFont(AT.FONT, 11, "")
            b.fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
            b.fs:SetWordWrap(false)
            b:SetScript("OnEnter", function() b._hot = true Paint(b) end)
            b:SetScript("OnLeave", function() b._hot = false Paint(b) end)
            b:SetScript("OnClick", function()
                local C2, r = CRm(), Rec()
                if not (C2 and r) then return end
                AT.CloseDropdown()
                C2.previewPower, RSO.pvId = b._pt, r.id
                if NS.Bars.PreviewRepaint then NS.Bars.PreviewRepaint() end
                AT.LayoutPage(pg)
            end)
            chips[j] = b
            return b
        end
        pv._sync = function()
            KeepPick()
            local r = Rec()
            local list = (r and ForPower(r)) and Powers(r) or {}
            local cur = PreviewPower()
            local x0 = 10 + math.ceil(StrW(lbl)) + 12
            local maxW = math.max(x0 + 160, (pv:GetWidth() or 0) - 8)
            local x, y, lines = x0, 0, 1
            for j = 1, math.max(#list, #chips) do
                local it = list[j]
                if it then
                    local b = Chip(j)
                    b._pt, b._on = it.value, it.value == cur
                    b.fs:SetText(Tr(it.text or ""))
                    local c = it.color or { 1, 1, 1 }
                    b.sq:SetVertexColor(c[1], c[2], c[3], 1)
                    local w = math.ceil(StrW(b.fs)) + 34
                    b:SetWidth(w)
                    if x > x0 and x + w > maxW then
                        x, y, lines = x0, y + 24, lines + 1
                    end
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", pv, "TOPLEFT", x, -3 - y)
                    x = x + w + 6
                    Paint(b)
                    b:Show()
                elseif chips[j] then
                    chips[j]:Hide()
                end
            end
            local h = 2 + lines * 24
            if pv._h ~= h then
                pv._h = h
                pv:SetHeight(h)
            end
        end
    end

    local head = AT.AddRow(pg, 22, TableVis)
    local forHead, stateHead, markHead
    do
        stateHead = Faint(head)
        stateHead:SetPoint("LEFT", 44, 0)
        stateHead:SetText(Upper(Tr("State")))
        local words = { fill = "Fill", text = "Text", mark = "Cost mark", glow = "Glow" }
        for k, word in pairs(words) do
            local h = Faint(head)
            h:SetPoint("LEFT", Cell(head, k), "LEFT", 0, 0)
            h:SetText(Upper(Tr(word)))
            if k == "mark" then markHead = h end
        end
        forHead = Faint(head)
        forHead:SetPoint("LEFT", Cell(head, "power"), "LEFT", 0, 0)
        forHead:SetText(Upper(Tr("For")))
    end
    Stamp(head, "resStates", "How the bar looks in each state", "Power")
    -- the open row follows the trigger into the preview
    local function SyncPreview()
        local C2 = CRm()
        if not C2 then return end
        local r = Rec()
        local want = (r and RSO.Open() and vis()) and Sel() or nil
        local wantId = want and r.id or nil
        if C2.previewSel ~= want or C2.previewSelId ~= wantId then
            C2.previewSel, C2.previewSelId = want, wantId
            if NS.Bars.PreviewRepaint then NS.Bars.PreviewRepaint() end
        end
    end
    -- the editor's section names the open row, and on an Automatic bar tags its
    -- power; Power has no State row, so the header carries this
    local function SyncTitle()
        local g = SelRow()
        local t = edSec and edSec.title
        if not (g and t) then return end
        local words = RSO.Label(g)
        t:SetText(edSec.boxed and words or Upper(words))
        local r = Rec()
        local on = ForPower(r)
        if on then
            tag.fs:SetText(Tr((g.power ~= nil) and (PowerInfo(r, g.power)) or RSO.FOR_ALL))
            tag:SetWidth(math.ceil(StrW(tag.fs)) + 10)
        end
        tag:SetShown(on)
    end
    head._sync = function()
        forHead:SetShown(ForPower(Rec()))
        local power = PowerView()
        if head._power ~= power then
            LayCells(head, power)
            stateHead:SetPoint("LEFT", power and 10 or 44, 0)
            stateHead:SetText(Upper(Tr(power and "Power" or "State")))
        end
        markHead:SetShown(not power)
        KeepPick()
        SyncPreview()
        SyncTitle()
    end

    Pause()
    -- the bar's own look, the Power table's first line
    local normal = AT.AddRow(pg, 30, function() return vis() and Rec() ~= nil and PowerView() end)
    do
        local line = normal:CreateTexture(nil, "ARTWORK")
        line:SetTexture(AT.WHITE)
        line:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
        line:SetPoint("BOTTOMLEFT", 4, 0)
        line:SetPoint("BOTTOMRIGHT", -4, 0)
        local lbl = normal:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 13, "")
        lbl:SetPoint("LEFT", 10, 0)
        lbl:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        lbl:SetText(Tr("Normal"))
        local fillCell = Cell(normal, "fill")
        local sub = Faint(normal, 11)
        sub:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        sub:SetPoint("RIGHT", fillCell, "LEFT", -8, 0)
        sub:SetJustifyH("LEFT")
        sub:SetText(Tr("the bar's own colors"))
        local fillW = Faint(normal, 11)
        fillW:SetPoint("LEFT", fillCell, "LEFT", 0, 0)
        fillW:SetText(Tr("own"))
        -- an Automatic bar: the fill the previewed power shows
        local sw = AT.MakeSwatch(fillCell, 40, 16)
        sw:SetPoint("LEFT", 0, 0)
        sw:EnableMouse(false)
        sw:Hide()
        local textW = Faint(normal, 11)
        textW:SetPoint("LEFT", Cell(normal, "text"), "LEFT", 0, 0)
        LayCells(normal, true)
        normal._sync = function()
            line:SetHeight(AT.Hairline(normal))
            local r = Rec()
            local follow = r and Store.Resolve(r, "rescolors", "resTextFill") == true
            textW:SetText(Tr(follow and "fill" or "own"))
            local on = ForPower(r)
            local cr, cg, cb, ca
            if on then
                local pt = PreviewPower()
                local name, c = PowerInfo(r, pt)
                local byPower = Store.Resolve(r, "resource", "usePowerColor") ~= false
                sub:SetText(byPower and Tr("the power color, %s"):format(Tr(name)) or Tr("the fill color"))
                if NS.Bars.FillColorOf then cr, cg, cb, ca = NS.Bars.FillColorOf(r, pt) end
                if cr == nil and c then cr, cg, cb, ca = c[1], c[2], c[3], 1 end
                if cr ~= nil then sw:SetColor({ cr, cg, cb }, ca or 1) end
            else
                sub:SetText(Tr("the bar's own colors"))
            end
            fillW:SetShown(not (on and cr ~= nil))
            sw:SetShown(on and cr ~= nil)
        end
    end
    -- the search's "Value": the values sit on Power's rows, under this one
    Stamp(normal, "resStateValue", "Value", "Power")

    for i = 1, maxR do
        Pause()
        local row = AT.AddRow(pg, 30, function() return vis() and Row(i) ~= nil end)
        -- a pick made now acts on the row it was made on, whatever the view is by then
        local function Open(k)
            local r = Rec()
            if r and k then RSO.sel[r.id] = k end
        end
        -- the open row: a raised fill and an accent edge
        local openFill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        openFill:SetTexture(AT.WHITE)
        openFill:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], 0.5)
        openFill:SetPoint("TOPLEFT", 4, 0)
        openFill:SetPoint("BOTTOMRIGHT", -4, 0)
        local edge = row:CreateTexture(nil, "ARTWORK")
        edge:SetTexture(AT.WHITE)
        edge:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        edge:SetPoint("TOPLEFT", 4, 0)
        edge:SetPoint("BOTTOMLEFT", 4, 0)
        edge:SetWidth(2)
        -- move up, move down
        local function Arrow(dir, x)
            local b = CreateFrame("Button", nil, row)
            b:SetSize(16, 22)
            b:SetPoint("LEFT", x, 0)
            local ch = AT.MakeChevron(b)
            ch:SetPoint("CENTER", 0, 0)
            ch:SetDir(dir)
            b._ch = ch
            b:SetScript("OnClick", function()
                local r, k = Rec(), Raw(i)
                if r and k then RSO.MoveInView(CRm(), r, RSO.View(), k, (dir == "up") and -1 or 1) end
                AT.CloseDropdown()
                AT.LayoutPage(pg)
            end)
            AT.Tooltip(b, (dir == "up") and "Move up" or "Move down",
                (dir == "up") and "Wins over the rows below it." or nil)
            return b
        end
        local up, down = Arrow("up", 8), Arrow("down", 24)
        -- the state's words: a click opens the row
        local pick = CreateFrame("Button", nil, row)
        pick:SetPoint("LEFT", 44, 0)
        pick:SetPoint("RIGHT", row, "RIGHT", -RSO.LABEL_RIGHT, 0)
        pick._right = RSO.LABEL_RIGHT
        pick:SetHeight(26)
        local lbl = pick:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 13, "")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetPoint("RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        pick:SetScript("OnClick", function()
            Open(Raw(i))
            AT.CloseDropdown()
            AT.LayoutPage(pg)
        end)
        AT.Tooltip(pick, "State", function() return RSO.Label(Row(i)) end)

        -- Power's own cells: the rule, the value and its unit
        local rule = AT.MakeDropdown(owner, row, RSO.RULE_W,
            function() return RSO.RULES end,
            function()
                local g = Row(i)
                return g and g.when or "below"
            end,
            function(v) Edit(function(S, r) S.SetRow(r, Raw(i), "when", v) end) end)
        rule:SetPoint("LEFT", 10, 0)
        local function PutValue(v)
            local g, k = Row(i), Raw(i)
            if not (g and k and v) then return end
            local top = g.units and math.max(2, UnitMax() - 1) or 99
            v = math.max(1, math.min(top, v))
            Edit(function(S, r) S.SetRow(r, k, "value", v) end)
        end
        local dec = AT.MakeSmallButton(row, "-", 20)
        dec:SetPoint("LEFT", rule, "RIGHT", 6, 0)
        local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        box:SetSize(RSO.VALUE_W, 20)
        AT.Skin(box, COL.well)
        box:SetFont(AT.FONT, 11, "")
        box:SetJustifyH("CENTER")
        box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        box:SetAutoFocus(false)
        box:SetPoint("LEFT", dec, "RIGHT", 2, 0)
        local inc = AT.MakeSmallButton(row, "+", 20)
        inc:SetPoint("LEFT", box, "RIGHT", 2, 0)
        local unit = Faint(row, 11)
        unit:SetPoint("LEFT", inc, "RIGHT", 4, 0)
        dec:SetScript("OnClick", function()
            local g = Row(i)
            if g then PutValue((g.value or 0) - RSO.VALUE_STEP) end
        end)
        inc:SetScript("OnClick", function()
            local g = Row(i)
            if g then PutValue((g.value or 0) + RSO.VALUE_STEP) end
        end)
        box:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            self:ClearFocus()
            PutValue(v)
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            AT.LayoutPage(pg)
        end)
        AT.Tooltip(box, "Value", "A percent of the bar, or power with In power units on.")
        row._adValueBox = box

        -- For: the power the row holds on, edged in its colour
        local forCell = Cell(row, "power")
        local forChip = CreateFrame("Frame", nil, forCell, "BackdropTemplate")
        forChip:SetHeight(16)
        forChip:SetPoint("LEFT", 0, 0)
        AT.Skin(forChip, { 0, 0, 0, 0 }, COL.line2)
        forChip:EnableMouse(true)
        local forFs = forChip:CreateFontString(nil, "OVERLAY")
        forFs:SetFont(AT.FONT, 10, "")
        forFs:SetPoint("LEFT", 6, 0)
        forFs:SetPoint("RIGHT", -6, 0)
        forFs:SetJustifyH("LEFT")
        forFs:SetWordWrap(false)
        AT.Tooltip(forChip, "For", function()
            local g = Row(i)
            if not g then return nil end
            if g.power == nil then return "Holds on every power." end
            return Tr("Holds only while the bar shows %s."):format(Tr((PowerInfo(Rec(), g.power))))
        end)

        -- fill and texts: a swatch, "keep" while the row leaves the bar's own
        local function ColorCell(key)
            local cell = Cell(row, key)
            local sw = AT.MakeSwatch(cell, 40, 16)
            sw:SetPoint("LEFT", 0, 0)
            sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local keep = Faint(sw, 9)
            keep:SetPoint("CENTER", 0, 0)
            keep:SetText(Tr("keep"))
            local dash = (key == "fill")
                and Dash(cell, "Fill color", "An aura row colors one continuous fill, four rows at most: not pips, runes or essence.")
                or Dash(cell, "Text color", "An aura row cannot color the texts.")
            sw:SetScript("OnClick", function(_, button)
                local r, k = Rec(), Raw(i)
                local g = k and Rows()[k]
                if not (r and g) then return end
                if button == "RightButton" then
                    AT.CloseDropdown()
                    Edit(function(S, rec) S.SetRow(rec, k, key, false) end)
                    return
                end
                PickColor(g[key], true, function(v)
                    Edit(function(S, rec) S.SetRow(rec, k, key, v) end)
                end)
            end)
            AT.Tooltip(sw, (key == "fill") and "Fill color" or "Text color", (key == "fill")
                and "Click to pick the fill color while this row holds. Right-click to keep the bar's own."
                or "Click to pick the texts color while this row holds. Right-click to keep the bar's own.")
            return { sw = sw, keep = keep, dash = dash, cell = cell }
        end
        local fillC, textC = ColorCell("fill"), ColorCell("text")

        -- the cost mark: spell rows
        local markCell = Cell(row, "mark")
        local mark = AT.MakeCheckbox(markCell)
        mark:SetPoint("LEFT", 0, 0)
        local markDash = Dash(markCell, "Cost mark", "Only a spell row has a cost to mark.")
        mark:SetScript("OnClick", function()
            local g, k = Row(i), Raw(i)
            if not g then return end
            AT.CloseDropdown()
            Edit(function(S, rec) S.SetRow(rec, k, "mark", not g.mark) end)
        end)
        mark:SetScript("OnEnter", function() mark:SetHover(true) end)
        mark:SetScript("OnLeave", function() mark:SetHover(false) end)
        AT.Tooltip(mark, "Cost mark", "A mark where each spell's cost is met. It shows with Tick marks on (Appearance > Ticks).")

        -- the glow: off, or its style
        local glowCell = Cell(row, "glow")
        local glow = AT.MakeDropdown(owner, glowCell, C.glow.w,
            function()
                local r, g = Rec(), Row(i)
                -- no row: Off, the word its field reads
                if not (r and g) then return { RSO.GLOWS[1] } end
                local max = (NS.Schema and NS.Schema.BAR_GLOW_SLOTS) or 3
                -- a bar draws three glows: a fourth row can only stay off
                if not g.glow and CRm().GlowCount(r) >= max then return { RSO.GLOWS[1] } end
                return RSO.GLOWS
            end,
            function()
                local g = Row(i)
                return (g and type(g.glow) == "table") and (g.glow.style or "pixel") or "off"
            end,
            function(v)
                local k = Raw(i)
                -- the picked glow's color and tuning sit in the row's editor
                Open(k)
                Edit(function(S, rec)
                    if v == "off" then
                        S.SetGlow(rec, k, "on", false)
                    else
                        S.SetGlow(rec, k, "on", true)
                        S.SetGlow(rec, k, "style", v)
                    end
                end)
            end)
        glow:SetPoint("LEFT", 0, 0)

        local remove = AT.MakeQuietButton(Cell(row, "remove"), "x", C.remove.w)
        remove:SetPoint("LEFT", 0, 0)
        remove:SetScript("OnClick", function()
            local r, k = Rec(), Raw(i)
            AT.CloseDropdown()
            if r and k and CRm().RemoveRow(r, k) and (RSO.sel[r.id] or 1) > k then RSO.sel[r.id] = RSO.sel[r.id] - 1 end
            AT.LayoutPage(pg)
        end)
        AT.Tooltip(remove, "Remove", "Removes this state.")

        -- Power: the rule and value lead, the arrows sit by the x, and a click
        -- on the empty row opens it
        local function LayRow(power)
            if row._power == power then return end
            LayCells(row, power)
            up:ClearAllPoints()
            down:ClearAllPoints()
            if power then
                down:SetPoint("RIGHT", row, "RIGHT", -powerRight.move, 0)
                up:SetPoint("RIGHT", down, "LEFT", 0, 0)
                pick:SetPoint("LEFT", 0, 0)
                pick:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                pick:SetFrameLevel(row:GetFrameLevel())
                pick._right = nil
            else
                up:SetPoint("LEFT", 8, 0)
                down:SetPoint("LEFT", 24, 0)
                pick:SetPoint("LEFT", 44, 0)
                pick:SetFrameLevel(row:GetFrameLevel() + 1)
            end
        end

        row._sync = function()
            local r, g = Rec(), Row(i)
            if not (r and g) then return end
            local k = Raw(i)
            local power = PowerView()
            LayRow(power)
            local open = Sel() == k
            openFill:SetShown(open)
            edge:SetShown(open)
            local ink = open and COL.arc or COL.ink
            lbl:SetTextColor(ink[1], ink[2], ink[3])
            lbl:SetText(RSO.Label(g))
            lbl:SetShown(not power)
            local n = Seen()
            up:SetShown(i > 1)
            down:SetShown(i < n)
            local on = ForPower(r)
            local lr = LabelRight(on)
            if not power and pick._right ~= lr then
                pick._right = lr
                pick:SetPoint("RIGHT", row, "RIGHT", -lr, 0)
            end
            rule:SetShown(power)
            if power then rule.Refresh() end
            local valued = power and g.when ~= "full"
            dec:SetShown(valued)
            box:SetShown(valued)
            inc:SetShown(valued)
            unit:SetShown(valued)
            if valued then
                if not box:HasFocus() then box:SetText(tostring(g.value or 0)) end
                unit:SetText(g.units and Tr("pts") or "%")
            end
            markCell:SetShown(not power)
            forCell:SetShown(on)
            if on then
                local name, c
                if g.power ~= nil then name, c = PowerInfo(r, g.power) end
                forFs:SetText(Tr(name or RSO.FOR_ALL))
                local ink = name and COL.ink or COL.dim
                forFs:SetTextColor(ink[1], ink[2], ink[3])
                local e = c or COL.line2
                forChip:SetBackdropBorderColor(e[1], e[2], e[3], 1)
                forChip:SetWidth(math.min(C.power.w, math.ceil(StrW(forFs)) + 12))
            end
            row:SetAlpha((on and g.power ~= nil and g.power ~= PreviewPower()) and RSO.DIM or 1)
            local w = Kind(g)
            local S = NS.Schema
            local auraFillOK = S and S.ResColorsOK and S.ResColorsOK(r)
            -- the fifth aura row on would have no lane of its own
            local fillOK = not IsAura(w) or (auraFillOK and (g.fill ~= nil or RSO.AuraFills(Rows(), k) < 4))
            for key, cc in pairs({ fill = fillC, text = textC }) do
                local ok = (key == "fill") and fillOK or not IsAura(w)
                local c = g[key]
                cc.sw:SetShown(ok)
                cc.dash:SetShown(not ok)
                if ok then
                    if type(c) == "table" then
                        cc.sw:SetColor(c, c[4] or 1)
                        cc.sw.tex:Show()
                        cc.keep:Hide()
                    else
                        cc.sw.tex:Hide()
                        cc.keep:Show()
                    end
                end
            end
            local spell = IsSpell(w)
            mark:SetShown(spell)
            markDash:SetShown(not spell)
            if spell then mark:SetOn(g.mark == true) end
            glow.Refresh()
        end
        if i == 1 then
            Stamp(fillC.sw, "resStateFill", "Fill color", "Power")
            Stamp(row, "resStateRow", "State", "Power")
        end
    end

    -- Add a state: the pick, then the button, under the table's STATE column
    -- (where the state names start), so the new row's place reads at once and
    -- no label leaves a gap before the column of the toggle below. Power has
    -- no pick: its rule is on the row.
    Pause()
    local add = AT.AddRow(pg, 32, function()
        return vis() and Rec() ~= nil and #Rows() < maxR and #RSO.AddItems(RSO.View()) > 0
    end)
    do
        local dd = AT.MakeDropdown(owner, add, 220,
            function() return RSO.AddItems(RSO.View()) end,
            function() return RSO.AddKind(RSO.View()) end,
            function(v) RSO.addKinds[RSO.View()] = v end)
        dd:SetPoint("LEFT", 44, 0)
        -- an Automatic bar: the power the new row is for, the previewed one
        -- until picked
        local function AddFor()
            local r, pt = Rec(), PreviewPower()
            if RSO.addFor ~= nil and r and RSO.addForId == r.id then return RSO.addFor end
            for _, it in ipairs(Powers(r)) do
                if it.value == pt then return pt end
            end
            return "all"
        end
        local forWord = add:CreateFontString(nil, "OVERLAY")
        forWord:SetFont(AT.FONT, 11, "")
        forWord:SetPoint("LEFT", dd, "RIGHT", 8, 0)
        forWord:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        forWord:SetText(Tr("for"))
        local forDD = AT.MakeDropdown(owner, add, 120,
            function() return ForItems(Rec()) end,
            AddFor,
            function(v)
                local r = Rec()
                RSO.addFor, RSO.addForId = v, r and r.id
            end)
        forDD:SetPoint("LEFT", forWord, "RIGHT", 8, 0)
        local btn = AT.MakeSmallButton(add, "+ Add state", 96)
        btn:SetPoint("LEFT", dd, "RIGHT", 8, 0)
        btn:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r = Rec()
            local pw = nil
            if ForPower(r) then
                local v = AddFor()
                if v ~= "all" then pw = v end
            end
            local n = r and CRm().AddRow(r, RSO.AddKind(RSO.View()), pw)
            if n then RSO.sel[r.id] = n end
            AT.LayoutPage(pg)
        end)
        add._sync = function()
            local power = PowerView()
            dd:SetShown(not power)
            if not power then dd.Refresh() end
            local on = ForPower(Rec())
            forWord:SetShown(on)
            forDD:SetShown(on)
            if on then forDD.Refresh() end
            local at = (power and "power" or "state") .. (on and "for" or "")
            if btn._at ~= at then
                btn._at = at
                forWord:ClearAllPoints()
                if power then forWord:SetPoint("LEFT", 10, 0) else forWord:SetPoint("LEFT", dd, "RIGHT", 8, 0) end
                btn:ClearAllPoints()
                if on then
                    btn:SetPoint("LEFT", forDD, "RIGHT", 8, 0)
                elseif power then
                    btn:SetPoint("LEFT", 10, 0)
                else
                    btn:SetPoint("LEFT", dd, "RIGHT", 8, 0)
                end
            end
        end
        Stamp(add, "resStateAdd", "Add a state", "Power")
    end
    Pause()
    -- the texts and the fill's colour, together
    local function FollowVis() return vis() and Rec() ~= nil and PowerView() end
    local follow = AT.RowToggle(pg, "Texts take the bar's color",
        function()
            local r = Rec()
            return r ~= nil and Store.Resolve(r, "rescolors", "resTextFill") == true
        end,
        function(v)
            local r = Rec()
            if r then Store.SetOverride(r, "rescolors", "resTextFill", v and true or false) end
            AT.LayoutPage(pg)
        end,
        FollowVis,
        "The resource texts wear the fill's color, the bar's own or a row's. A row's own text color wins.")
    follow._adMeta = { family = "bar", section = "rescolors", field = "resTextFill",
        def = NS.Schema.bar.rescolors.fields.resTextFill,
        baseVis = function() return vis() and RSO.View() == "Power" end }

    -- The open row's editor

    Pause()
    -- Power's rule and value are on the row: a row with nothing left to tune has no editor
    local edVis = function()
        local g = SelRow()
        if not (vis() and g ~= nil) then return false end
        if not PowerView() then return true end
        return ForPower(Rec()) or g.when ~= "full" or type(g.glow) == "table"
    end
    AT.Section(pg, "State", { visibleFn = edVis })
    edSec = pg._curSection
    local spellVis = function()
        local g = SelRow()
        return edVis() and g ~= nil and IsSpell(Kind(g))
    end
    local auraVis = function()
        local g = SelRow()
        return edVis() and g ~= nil and IsAura(Kind(g))
    end
    local valueVis = function()
        local g = SelRow()
        local w = Kind(g)
        return edVis() and g ~= nil and (w == "below" or w == "above")
    end
    local glowVis = function()
        local g = SelRow()
        return edVis() and g ~= nil and type(g.glow) == "table"
    end

    local whenRow = AT.RowDropdown(pg, owner, "State",
        function() return Kind((SelRow())) end,
        function(v) Edit(function(S, r) S.SetRow(r, Sel(), "when", v) end) end,
        function()
            local cur = Kind((SelRow()))
            local S = NS.Schema
            local v = RSO.VIEWS[RSO.View()] or {}
            local out = {}
            for _, it in ipairs(RSO.KINDS) do
                -- a row stays in its trigger
                local ok = v[it.value] == true
                if ok and it.value == "up" then ok = S.BarGlowAuraOK(false) end
                if ok and it.value == "missing" then ok = S.BarGlowAuraOK(true) end
                -- no aura engine here: no aura choice, unless it is the one saved
                if ok or it.value == cur then out[#out + 1] = it end
            end
            return out
        end,
        function() return edVis() and not PowerView() end)
    AT.Tooltip(whenRow, "State",
        "Enough power: you could pay its cost now. Usable: the game would let you cast it. Ready: off cooldown.")
    if edSec and edSec.title then
        tag = CreateFrame("Frame", nil, edSec.band or edSec.hit or pg, "BackdropTemplate")
        tag:SetHeight(14)
        AT.Skin(tag, { 0, 0, 0, 0 }, COL.focus)
        tag.fs = tag:CreateFontString(nil, "OVERLAY")
        tag.fs:SetFont(AT.FONT, 9, "")
        tag.fs:SetPoint("CENTER", 0, 0)
        tag.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        tag:SetPoint("LEFT", edSec.title, "RIGHT", 8, 0)
        tag:Hide()
    end
    Stamp(whenRow, "resStateWhen", "State", "Spells")
    -- the title hides with its section: the tag goes with it; a trigger with
    -- no row draws no header, so the preview lets go of the row here too
    RSO.after[pg] = function()
        if tag and tag:IsShown() and not edSec.title:IsShown() then tag:Hide() end
        SyncPreview()
    end

    Pause()
    -- an Automatic bar: the power the open row holds on
    local forRow = AT.RowDropdown(pg, owner, "For",
        function()
            local g = SelRow()
            return (g and g.power ~= nil) and g.power or "all"
        end,
        function(v) Edit(function(S, r) S.SetRow(r, Sel(), "power", (v ~= "all") and v or nil) end) end,
        function() return ForItems(Rec(), (SelRow() or {}).power) end,
        function() return edVis() and ForPower(Rec()) end)
    AT.Tooltip(forRow, "For", "The power this row holds on. All powers: whatever power the bar shows.")
    -- as wide as State's above it: the two read as one pair
    do
        local forDD, whenDD = forRow._colCtrl, whenRow._colCtrl
        local function Match()
            local w = whenDD:GetWidth() or 0
            if w > (forDD:GetWidth() or 0) then forDD:SetWidth(w) end
        end
        local forSync = forRow._sync
        forRow._sync = function()
            forSync()
            Match()
        end
        forDD:HookScript("OnClick", function()
            Match()
            local l = AT.openDropdown
            if l and l._owner == forDD then l:SetWidth(forDD:GetWidth()) end
        end)
    end

    Pause()
    -- a spell row's spells: one chip each, a click takes it away
    local chips = AT.AddRow(pg, 30, spellVis)
    do
        local lbl = AT.RowLabel(chips, "Spells")
        -- the section's measured column: the page pins this marker there (its
        -- middle on the row's middle, the row's height tall, so its top is the
        -- row's), and the chips and the empty note ride on it like every other
        -- control
        local col = CreateFrame("Frame", nil, chips)
        col:SetSize(1, 30)
        col:SetPoint("LEFT", chips._ctrlX, 0)
        chips._colCtrl = col
        local none = Faint(chips, 11)
        none:SetPoint("LEFT", col, "LEFT", 0, 0)
        none:SetText(Tr("No spell yet: add one below."))
        local btns = {}
        chips._sync = function()
            local g = SelRow()
            local list = (g and g.rowSpells) or {}
            none:SetShown(#list == 0)
            local _, _, _, x0 = col:GetPoint(1)
            x0 = tonumber(x0) or chips._ctrlX
            local maxW = math.max(160, (chips:GetWidth() or 0) - x0 - 12)
            local x, y, lines = 0, 0, 1
            for j = 1, math.max(#list, #btns) do
                local b = btns[j]
                if j <= #list then
                    if not b then
                        b = AT.MakeQuietButton(chips, "", 60)
                        b:SetScript("OnClick", function()
                            AT.CloseDropdown()
                            Edit(function(S, r) S.RemoveSpell(r, Sel(), j) end)
                        end)
                        AT.Tooltip(b, "Remove this spell", "The row holds for any spell left in it.")
                        btns[j] = b
                    end
                    b.fs:SetText(SpellName(list[j]) .. "  x")
                    local w = math.ceil((b.fs:GetStringWidth() or 40) + 16)
                    b:SetWidth(w)
                    if x > 0 and x + w > maxW then
                        x, y, lines = 0, y + 26, lines + 1
                    end
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", col, "TOPLEFT", x, -4 - y)
                    b:Show()
                    x = x + w + 6
                elseif b then
                    b:Hide()
                end
            end
            local h = 4 + lines * 26
            if #list == 0 then h = 30 end
            col:SetHeight(h)
            if chips._h ~= h then
                chips._h = h
                chips:SetHeight(h)
            end
            lbl:ClearAllPoints()
            lbl:SetPoint("TOPLEFT", 10, -9)
        end
    end
    local function SpellAdd(v)
        local id = BGO and BGO.ParseSpell(v) or tonumber(v)
        if not id then return end
        Edit(function(S, r) S.AddSpell(r, Sel(), id) end)
    end
    Pause()
    local addSpell
    addSpell = AT.RowInput(pg, "Add a spell", function() return "" end,
        function(v)
            SpellAdd(v)
            if addSpell._colCtrl then addSpell._colCtrl:SetText("") end
        end,
        function()
            local g = SelRow()
            return spellVis() and #((g and g.rowSpells) or {}) < ((CRm() and CRm().MaxSpells()) or 8)
        end,
        "Type the spell's name and click it below, or type its ID and press Enter. Any of the row's spells counts.",
        "name or ID")
    Pause()
    if BGO and BGO.SpellSuggest then
        local Suggest = BGO.SpellSuggest(pg, function() return addSpell._visibleFn() end,
            function()
                local eb = addSpell._colCtrl
                return eb and eb:GetText() or ""
            end,
            function(id)
                Edit(function(S, r) S.AddSpell(r, Sel(), id) end)
                if addSpell._colCtrl then addSpell._colCtrl:SetText("") end
            end)
        if addSpell._colCtrl then
            addSpell._colCtrl:HookScript("OnTextChanged", function(_, userInput)
                if userInput then Suggest(false) end
            end)
        end
        addSpell._adSuggest = Suggest
    end
    addSpell._adCommit = SpellAdd
    Stamp(addSpell, "resStateSpell", "Add a spell", "Spells")
    Pause()
    AT.RowToggle(pg, "Follow my rank",
        function()
            local g = SelRow()
            return g == nil or g.follow ~= false
        end,
        function(v) Edit(function(S, r) S.SetRow(r, Sel(), "follow", v) end) end,
        function() return spellVis() and NS.IsForever == true end,
        "Follows the rank of each spell you know, so a newly trained rank keeps working.")

    -- an aura row's aura: the aura bar's Tracking rows on the row
    local function IDsText()
        local g = SelRow()
        return g and table.concat(Store.AuraIDList(g), ", ") or ""
    end
    local function AuraCommit(v)
        local ids = Options.ParseSpellIDs(v)
        if #ids == 0 or table.concat(ids, ", ") == IDsText() then return end
        AuraEdit(function(g) Options.SetAuraSpellIDs(g, ids) end)
    end
    Pause()
    local idRow = AT.RowInput(pg, RSO.AURA_IDS, IDsText, AuraCommit, auraVis,
        "Type the aura's name and click one to add its ID, or type IDs separated by commas or spaces. Any of them counts.",
        "e.g. 102560, 390414")
    local function AuraAdd(v)
        local r, s = Rec(), Sel()
        local g = r and s and CRm().MutRow(r, s)
        if not g then return end
        if Options.AddAuraSpellID(g, v) then CRm().Touched(r) end
        if idRow._colCtrl then idRow._colCtrl:SetText(IDsText()) end
        AT.LayoutPage(pg)
    end
    -- a name typed after the IDs already in the box is what is searched
    local function Typed()
        local eb = idRow._colCtrl
        local t = eb and eb:GetText() or ""
        if t:find("%a") then t = t:gsub("^[%d%s,;]+", "") end
        return t
    end
    Pause()
    local AuraSuggest = Options.AuraSuggestPanel and Options.AuraSuggestPanel(pg, auraVis, Typed, AuraAdd,
        false, nil, true)
    if AuraSuggest and idRow._colCtrl then
        idRow._colCtrl:HookScript("OnTextChanged", function(_, userInput)
            if userInput then AuraSuggest(false) end
        end)
    end
    idRow._adCommit, idRow._adAdd, idRow._adSuggest = AuraCommit, AuraAdd, AuraSuggest
    Stamp(idRow, "resStateAura", RSO.AURA_IDS, "Auras")
    Pause()
    AT.RowToggle(pg, "Follow my rank",
        function()
            local g = SelRow()
            return g == nil or g.followRank ~= false
        end,
        function(v) AuraEdit(function(g) if v then g.followRank = nil else g.followRank = false end end) end,
        function() return auraVis() and NS.IsForever == true end,
        Options.FOLLOW_RANK_DESC)
    Pause()
    AT.RowDropdown(pg, owner, "Aura type",
        function()
            local g = SelRow()
            return (g and g.auraType) or "buff"
        end,
        function(v)
            AuraEdit(function(g)
                -- keep the unit it watches now, moved off one this type cannot match on
                local unit = DA.ShapeOf(g)
                g.auraType = v
                if not Options.AuraUnitAllowed(g, unit, v) then unit = "target" end
                g.unit = unit
            end)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        auraVis)
    Pause()
    local unitRow = AT.RowDropdown(pg, owner, "On unit",
        function() return (DA.ShapeOf((SelRow()) or {})) end,
        function(v) AuraEdit(function(g) g.unit = v end) end,
        function()
            local g = SelRow() or {}
            return Options.AuraUnitItems(g, nil, (DA.ShapeOf(g)))
        end,
        auraVis)
    AT.Tooltip(unitRow, "On unit", "Who carries the aura: a buff on you, a debuff on your target, or another unit.")
    Pause()
    AT.RowDropdown(pg, owner, "Cast by",
        function()
            local _, _, caster = DA.ShapeOf((SelRow()) or {})
            return caster or "any"
        end,
        function(v)
            AuraEdit(function(g)
                g.caster = (v ~= "any") and v or nil
                g.ownOnly = nil
            end)
        end,
        function() return Options.AURA_CASTER_ITEMS end,
        auraVis)

    -- a power row's value counts a percent, or power units over the bar's maximum
    local function Units()
        local g = SelRow()
        return g ~= nil and g.units == true
    end
    Pause()
    AT.RowToggle(pg, "In power units",
        function() return Units() end,
        function(v) Edit(function(S, r) S.SetRow(r, Sel(), "units", v) end) end,
        valueVis, "The value counts power (45 energy, 2000 mana) instead of a percent of the bar.")

    -- the row's glow: its colour and gate, then the tuning in a fold
    local function GlowGet(key, dflt)
        local g = SelRow()
        local v = g and type(g.glow) == "table" and g.glow[key]
        if v == nil then
            local f = NS.Schema.RES_GLOW_KEYS[key]
            v = f and NS.Schema.bar.glows.fields[f].d
        end
        if v == nil then v = dflt end
        return v
    end
    local function GlowSet(key, v) Edit(function(S, r) S.SetGlow(r, Sel(), key, v) end) end
    Pause()
    local gcol = AT.RowColor(pg, "Glow color",
        function()
            local g = SelRow()
            local c = g and type(g.glow) == "table" and g.glow.color
            return c or NS.Schema.bar.glows.fields.barGlowColor.d
        end,
        function(c) GlowSet("color", { c[1], c[2], c[3], c[4] or 1 }) end,
        glowVis, { alpha = true })
    Stamp(gcol, "resStateGlowColor", "Glow color", "Power")
    Pause()
    AT.RowToggle(pg, "Glow only in combat",
        function() return GlowGet("combat", false) == true end,
        function(v) GlowSet("combat", v) end,
        glowVis, "The glow waits for combat; out of combat the bar shows without it.")
    Pause()
    local fold = ET and ET.NewFold(pg, "resStateGlow", "glow", ctx)
    local function Tuning(label, key, lo, hi, step, fmt, when)
        Pause()
        local gate = function()
            if not glowVis() then return false end
            local g = SelRow()
            local style = (g and g.glow and g.glow.style) or "pixel"
            return when == nil or when == style
        end
        local rowVis = fold and fold:Add(glowVis, gate, function()
            local g = SelRow()
            return g ~= nil and type(g.glow) == "table" and g.glow[key] ~= nil
        end) or gate
        AT.RowSlider(pg, label, function() return GlowGet(key, lo) end,
            function(v) GlowSet(key, v) end, lo, hi, step, fmt or false, rowVis)
    end
    local gf = NS.Schema.bar.glows.fields
    Tuning("Speed", "speed", gf.barGlowSpeed.min, gf.barGlowSpeed.max, 0.05, "%.2f")
    Tuning("Lines", "lines", gf.barGlowLines.min, gf.barGlowLines.max, 1, nil, "pixel")
    Tuning("Thickness", "th", gf.barGlowThickness.min, gf.barGlowThickness.max, 1, nil, "pixel")
    Tuning("Line length (0 = auto)", "len", gf.barGlowLength.min, gf.barGlowLength.max, 1, nil, "pixel")
    Tuning("Particles", "parts", gf.barGlowParticles.min, gf.barGlowParticles.max, 1, nil, "autocast")
    Tuning("Size", "scale", gf.barGlowScale.min, gf.barGlowScale.max, 0.05, "%.2f", "autocast")
    Tuning("Intensity", "intensity", gf.barGlowIntensity.min, gf.barGlowIntensity.max, 0.05, "%.2f")
    Tuning("X offset", "xo", gf.barGlowXOffset.min, gf.barGlowXOffset.max, 1)
    Tuning("Y offset", "yo", gf.barGlowYOffset.min, gf.barGlowYOffset.max, 1)

    -- the preview follows the sub-tab as it opens and closes
    local G = NS.Bars and NS.Bars.Glow
    if G and not RSO.wrapped then
        RSO.wrapped = true
        local was = G.PreviewOpen
        G.PreviewOpen = function()
            return (was ~= nil and was() == true) or RSO.Open()
        end
    end
    if hooksecurefunc and not RSO.hooked then
        RSO.hooked = true
        hooksecurefunc(AT, "LayoutPage", function(p)
            local after = RSO.after[p]
            if after then after() end
            if p ~= pg then return end
            local open = RSO.Open()
            if open ~= RSO.lastOpen then
                RSO.lastOpen = open
                -- a picked power is for By State only
                if not open then RSO.ClearPreview() end
                if G and G.PreviewSync then G.PreviewSync() end
            end
        end)
    end
    -- the window shut or another editor: the picked power goes too
    if pg.HookScript then pg:HookScript("OnHide", function() RSO.ClearPreview() end) end
end
