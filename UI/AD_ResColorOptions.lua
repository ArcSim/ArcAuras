-- AD_ResColorOptions: a resource bar's States table, the bar editor's Conditions > By State. One row per
-- state with what it changes (fill, texts, cost mark, glow), the open row's editor under the table, and
-- Add a state. AD_Options calls Options.ResStateRows while it builds the bar pane; every edit goes through
-- NS.Bars.ResColor.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local RSO = {}
Options.ResStateOptions = RSO

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
RSO.GLOWS = { { value = "off", text = "Off" }, { value = "pixel", text = "Pixel" }, { value = "autocast", text = "Autocast" } }
RSO.AURA_IDS = "Aura name or spell IDs"
RSO.NOTE = "Fill and texts: the highest row that holds wins. A glow shows while its row holds."
-- the table's columns, measured from the row's right edge; power is the For
-- column, on an Automatic power bar only
RSO.COLS = { remove = { w = 22 }, glow = { w = 96 }, mark = { w = 78 }, text = { w = 56 }, fill = { w = 56 },
    power = { w = 76 } }
RSO.GAP = 10
-- the open row per bar
RSO.sel = {}
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
    return (type(nm) == "string" and nm ~= "") and nm or ("spell " .. tostring(id))
end

-- A row in words: what holds it.
function RSO.Label(r)
    local w = r and r.when or "enough"
    local function Names()
        local out = {}
        for _, sid in ipairs(r.rowSpells or {}) do out[#out + 1] = SpellName(sid) end
        return (#out > 0) and table.concat(out, " or ") or nil
    end
    if w == "enough" then
        local n = Names()
        return n and ("Enough for " .. n) or "Enough power for a spell"
    end
    local spellWord = { usable = " is usable", ready = " is ready", recharging = " is recharging",
        cooldown = " is on cooldown" }
    if spellWord[w] then return (Names() or "A spell") .. spellWord[w] end
    if w == "up" or w == "missing" then
        local ids = NS.Store.AuraIDList(r)
        local nm = ids[1] and SpellName(ids[1]) or "An aura"
        if #ids > 1 then nm = nm .. " (+" .. (#ids - 1) .. ")" end
        return nm .. ((w == "up") and " is up" or " is missing")
    end
    if w == "below" or w == "above" then
        local v = tostring(r.value or 0) .. (r.units and "" or "%")
        return ((w == "below") and "Power at or below " or "Power at or above ") .. v
    end
    return "Full power"
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

-- The By State sub-tab is the one open on a resource bar: the preview wears
-- the open row then.
function RSO.Open()
    local ui = Options.ui
    if not (ui and ui.barTab == "Conditions" and ui.selType == "bar") then return false end
    local r = NS.Store.Get(ui.selId)
    if not (r and r.barKind == "resource") then return false end
    return (ui.barSec and ui.barSec.Conditions) == "By State"
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
    local function Row(i) return Rows()[i] end
    -- the open row, kept inside the list
    local function Sel()
        local r = Rec()
        if not r then return nil end
        local n = #Rows()
        if n == 0 then return nil end
        local s = RSO.sel[r.id] or 1
        if s > n then s = n end
        if s < 1 then s = 1 end
        RSO.sel[r.id] = s
        return s
    end
    local function SelRow()
        local s = Sel()
        return s and Row(s), s
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
    -- found by the search; the jump lands on the table
    local function Stamp(row, field, label)
        row._adMeta = { family = "bar", section = "rescolors", field = field, def = { label = label }, baseVis = vis }
    end
    local maxR = (CRm() and CRm().MaxRows()) or 12
    -- a pause point between rows: the window builds in slices
    local function Pause() if Options.BuildYield then Options.BuildYield() end end

    -- The table

    AT.RowDesc(pg, RSO.NOTE, 20, function() return vis() and #Rows() > 0 end)
    local C, GAP = RSO.COLS, RSO.GAP
    -- each cell's right edge, from the row's right
    local right = {}
    do
        local x = 8
        for _, k in ipairs({ "remove", "glow", "mark", "text", "fill", "power" }) do
            right[k] = x
            x = x + C[k].w + GAP
            if k == "fill" then RSO.LABEL_RIGHT = x end
        end
        RSO.LABEL_RIGHT_FOR = x
    end
    -- the state words end at the first cell: For on an Automatic bar, else Fill
    local function LabelRight(on) return on and RSO.LABEL_RIGHT_FOR or RSO.LABEL_RIGHT end
    local function Cell(row, k)
        local f = CreateFrame("Frame", nil, row)
        f:SetSize(C[k].w, 24)
        f:SetPoint("RIGHT", row, "RIGHT", -right[k], 0)
        return f
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
        return vis() and #Rows() > 0 and ForPower(r) and #Powers(r) > 0
    end)
    do
        -- on the first line's middle: more powers than fit wrap under the chips
        local lbl = pv:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 11, "")
        lbl:SetPoint("TOPLEFT", 10, -7)
        lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        lbl:SetText("Preview as")
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
                    b.fs:SetText(it.text or "")
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

    local head = AT.AddRow(pg, 22, function() return vis() and #Rows() > 0 end)
    local forHead
    do
        local fs = Faint(head)
        fs:SetPoint("LEFT", 44, 0)
        fs:SetText("STATE")
        local words = { fill = "FILL", text = "TEXT", mark = "COST MARK", glow = "GLOW" }
        for k, word in pairs(words) do
            local h = Faint(head)
            h:SetPoint("LEFT", Cell(head, k), "LEFT", 0, 0)
            h:SetText(word)
        end
        forHead = Faint(head)
        forHead:SetPoint("LEFT", Cell(head, "power"), "LEFT", 0, 0)
        forHead:SetText("FOR")
    end
    Stamp(head, "resStates", "How the bar looks in each state")
    -- the open row follows the sub-tab into the preview
    head._sync = function()
        forHead:SetShown(ForPower(Rec()))
        KeepPick()
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

    for i = 1, maxR do
        Pause()
        local row = AT.AddRow(pg, 30, function() return vis() and Row(i) ~= nil end)
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
                local r = Rec()
                local d = (dir == "up") and -1 or 1
                if r and CRm().MoveRow(r, i, d) then
                    if RSO.sel[r.id] == i then RSO.sel[r.id] = i + d end
                end
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
            local r = Rec()
            if r then RSO.sel[r.id] = i end
            AT.CloseDropdown()
            AT.LayoutPage(pg)
        end)
        AT.Tooltip(pick, "State", function() return RSO.Label(Row(i)) end)

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
            return "Holds only while the bar shows " .. (PowerInfo(Rec(), g.power)) .. "."
        end)

        -- fill and texts: a swatch, "keep" while the row leaves the bar's own
        local function ColorCell(key)
            local cell = Cell(row, key)
            local sw = AT.MakeSwatch(cell, 40, 16)
            sw:SetPoint("LEFT", 0, 0)
            sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local keep = Faint(sw, 9)
            keep:SetPoint("CENTER", 0, 0)
            keep:SetText("keep")
            local dash = (key == "fill")
                and Dash(cell, "Fill color", "An aura row colors one continuous fill, four rows at most: not pips, runes or essence.")
                or Dash(cell, "Text color", "An aura row cannot color the texts.")
            sw:SetScript("OnClick", function(_, button)
                local r = Rec()
                local g = Row(i)
                if not (r and g) then return end
                if button == "RightButton" then
                    AT.CloseDropdown()
                    Edit(function(S, rec) S.SetRow(rec, i, key, false) end)
                    return
                end
                PickColor(g[key], true, function(v)
                    Edit(function(S, rec) S.SetRow(rec, i, key, v) end)
                end)
            end)
            local word = (key == "fill") and "fill" or "texts"
            AT.Tooltip(sw, (key == "fill") and "Fill color" or "Text color",
                "Click to pick the " .. word .. " color while this row holds. Right-click to keep the bar's own.")
            return { sw = sw, keep = keep, dash = dash, cell = cell }
        end
        local fillC, textC = ColorCell("fill"), ColorCell("text")

        -- the cost mark: spell rows
        local markCell = Cell(row, "mark")
        local mark = AT.MakeCheckbox(markCell)
        mark:SetPoint("LEFT", 0, 0)
        local markDash = Dash(markCell, "Cost mark", "Only a spell row has a cost to mark.")
        mark:SetScript("OnClick", function()
            local g = Row(i)
            if not g then return end
            AT.CloseDropdown()
            Edit(function(S, rec) S.SetRow(rec, i, "mark", not g.mark) end)
        end)
        mark:SetScript("OnEnter", function() mark:SetHover(true) end)
        mark:SetScript("OnLeave", function() mark:SetHover(false) end)
        AT.Tooltip(mark, "Cost mark", "A mark where each spell's cost is met. It shows with Tick marks on (Appearance > Ticks).")

        -- the glow: off, or its style
        local glowCell = Cell(row, "glow")
        local glow = AT.MakeDropdown(owner, glowCell, C.glow.w,
            function()
                local r, g = Rec(), Row(i)
                if not (r and g) then return {} end
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
                Edit(function(S, rec)
                    if v == "off" then
                        S.SetGlow(rec, i, "on", false)
                    else
                        S.SetGlow(rec, i, "on", true)
                        S.SetGlow(rec, i, "style", v)
                    end
                end)
            end)
        glow:SetPoint("LEFT", 0, 0)

        local remove = AT.MakeQuietButton(Cell(row, "remove"), "x", C.remove.w)
        remove:SetPoint("LEFT", 0, 0)
        remove:SetScript("OnClick", function()
            local r = Rec()
            AT.CloseDropdown()
            if r and CRm().RemoveRow(r, i) and (RSO.sel[r.id] or 1) > i then RSO.sel[r.id] = RSO.sel[r.id] - 1 end
            AT.LayoutPage(pg)
        end)
        AT.Tooltip(remove, "Remove", "Removes this state.")

        row._sync = function()
            local r, g = Rec(), Row(i)
            if not (r and g) then return end
            local open = Sel() == i
            openFill:SetShown(open)
            edge:SetShown(open)
            local ink = open and COL.arc or COL.ink
            lbl:SetTextColor(ink[1], ink[2], ink[3])
            lbl:SetText(RSO.Label(g))
            local n = #Rows()
            up:SetShown(i > 1)
            down:SetShown(i < n)
            local on = ForPower(r)
            local lr = LabelRight(on)
            if pick._right ~= lr then
                pick._right = lr
                pick:SetPoint("RIGHT", row, "RIGHT", -lr, 0)
            end
            forCell:SetShown(on)
            if on then
                local name, c
                if g.power ~= nil then name, c = PowerInfo(r, g.power) end
                forFs:SetText(name or RSO.FOR_ALL)
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
            local fillOK = not IsAura(w) or (auraFillOK and (g.fill ~= nil or RSO.AuraFills(Rows(), i) < 4))
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
            Stamp(fillC.sw, "resStateFill", "Fill color")
            Stamp(row, "resStateRow", "State")
        end
    end

    Pause()
    -- the bar's own look, under every row
    local normal = AT.AddRow(pg, 30, function() return vis() and #Rows() > 0 end)
    do
        local line = normal:CreateTexture(nil, "ARTWORK")
        line:SetTexture(AT.WHITE)
        line:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
        line:SetPoint("TOPLEFT", 4, 0)
        line:SetPoint("TOPRIGHT", -4, 0)
        local lbl = normal:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 13, "")
        lbl:SetPoint("LEFT", 44, 0)
        lbl:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        lbl:SetText("Normal")
        local fillCell = Cell(normal, "fill")
        local sub = Faint(normal, 11)
        sub:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        sub:SetPoint("RIGHT", fillCell, "LEFT", -8, 0)
        sub:SetJustifyH("LEFT")
        sub:SetText("the bar's own colors")
        local fillW = Faint(normal, 11)
        fillW:SetPoint("LEFT", fillCell, "LEFT", 0, 0)
        fillW:SetText("own")
        -- an Automatic bar: the fill the previewed power shows
        local sw = AT.MakeSwatch(fillCell, 40, 16)
        sw:SetPoint("LEFT", 0, 0)
        sw:EnableMouse(false)
        sw:Hide()
        local textW = Faint(normal, 11)
        textW:SetPoint("LEFT", Cell(normal, "text"), "LEFT", 0, 0)
        normal._sync = function()
            line:SetHeight(AT.Hairline(normal))
            local r = Rec()
            local follow = r and Store.Resolve(r, "rescolors", "resTextFill") == true
            textW:SetText(follow and "fill" or "own")
            local on = ForPower(r)
            local cr, cg, cb, ca
            if on then
                local pt = PreviewPower()
                local name, c = PowerInfo(r, pt)
                local byPower = Store.Resolve(r, "resource", "usePowerColor") ~= false
                sub:SetText(byPower and ("the power color, " .. name) or "the fill color")
                if NS.Bars.FillColorOf then cr, cg, cb, ca = NS.Bars.FillColorOf(r, pt) end
                if cr == nil and c then cr, cg, cb, ca = c[1], c[2], c[3], 1 end
                if cr ~= nil then sw:SetColor({ cr, cg, cb }, ca or 1) end
            else
                sub:SetText("the bar's own colors")
            end
            fillW:SetShown(not (on and cr ~= nil))
            sw:SetShown(on and cr ~= nil)
        end
    end

    -- Add a state: the pick, then the button, under the table's STATE column
    -- (where the state names start), so the new row's place reads at once and
    -- no label leaves a gap before the column of the toggle below
    RSO.addKind = RSO.addKind or "enough"
    Pause()
    local add = AT.AddRow(pg, 32, function() return vis() and Rec() ~= nil and #Rows() < maxR end)
    do
        local dd = AT.MakeDropdown(owner, add, 220,
            function()
                local out = {}
                local S = NS.Schema
                for _, it in ipairs(RSO.KINDS) do
                    local ok = true
                    if it.value == "up" then ok = S.BarGlowAuraOK(false) end
                    if it.value == "missing" then ok = S.BarGlowAuraOK(true) end
                    if ok then out[#out + 1] = it end
                end
                return out
            end,
            function() return RSO.addKind end,
            function(v) RSO.addKind = v end)
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
        forWord:SetText("for")
        local forDD = AT.MakeDropdown(owner, add, 120,
            function() return ForItems(Rec()) end,
            AddFor,
            function(v)
                local r = Rec()
                RSO.addFor, RSO.addForId = v, r and r.id
            end)
        forDD:SetPoint("LEFT", forWord, "RIGHT", 8, 0)
        local btn = AT.MakeSmallButton(add, "Add state", 84)
        btn:SetPoint("LEFT", dd, "RIGHT", 8, 0)
        btn:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r = Rec()
            local pw = nil
            if ForPower(r) then
                local v = AddFor()
                if v ~= "all" then pw = v end
            end
            local n = r and CRm().AddRow(r, RSO.addKind, pw)
            if n then RSO.sel[r.id] = n end
            AT.LayoutPage(pg)
        end)
        add._sync = function()
            dd.Refresh()
            local on = ForPower(Rec())
            forWord:SetShown(on)
            forDD:SetShown(on)
            if on then forDD.Refresh() end
            if btn._for ~= on then
                btn._for = on
                btn:SetPoint("LEFT", on and forDD or dd, "RIGHT", 8, 0)
            end
        end
        Stamp(add, "resStateAdd", "Add a state")
    end
    Pause()
    -- the texts and the fill's colour, together
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
        function() return vis() and Rec() ~= nil end,
        "The resource texts wear the fill's color, the bar's own or a row's. A row's own text color wins.")
    follow._adMeta = { family = "bar", section = "rescolors", field = "resTextFill",
        def = NS.Schema.bar.rescolors.fields.resTextFill, baseVis = vis }

    -- The open row's editor

    Pause()
    local edVis = function() return vis() and SelRow() ~= nil end
    AT.Section(pg, "State", { visibleFn = edVis })
    local edSec = pg._curSection
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
            local out = {}
            for _, it in ipairs(RSO.KINDS) do
                local ok = true
                if it.value == "up" then ok = S.BarGlowAuraOK(false) end
                if it.value == "missing" then ok = S.BarGlowAuraOK(true) end
                -- no aura engine here: no aura choice, unless it is the one saved
                if ok or it.value == cur then out[#out + 1] = it end
            end
            return out
        end,
        edVis)
    AT.Tooltip(whenRow, "State",
        "Enough power: you could pay its cost now. Usable: the game would let you cast it. Ready: off cooldown.")
    -- the section names the open row, and on an Automatic bar tags its power
    local tag
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
    local whenSync = whenRow._sync
    whenRow._sync = function()
        whenSync()
        local g = SelRow()
        local t = edSec and edSec.title
        if not (g and t) then return end
        local words = RSO.Label(g)
        t:SetText(edSec.boxed and words or string.upper(words))
        local r = Rec()
        local on = ForPower(r)
        if on then
            tag.fs:SetText((g.power ~= nil) and (PowerInfo(r, g.power)) or RSO.FOR_ALL)
            tag:SetWidth(math.ceil(StrW(tag.fs)) + 10)
        end
        tag:SetShown(on)
    end
    Stamp(whenRow, "resStateWhen", "State")
    -- the title hides with its section: the tag goes with it
    RSO.after[pg] = function()
        if tag and tag:IsShown() and not edSec.title:IsShown() then tag:Hide() end
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
        none:SetText("No spell yet: add one below.")
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
    Stamp(addSpell, "resStateSpell", "Add a spell")
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
    Stamp(idRow, "resStateAura", RSO.AURA_IDS)
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

    -- a power row's value: a percent, or power units over the bar's maximum
    local function Units()
        local g = SelRow()
        return g ~= nil and g.units == true
    end
    local function UnitMax()
        local r = Rec()
        local K = NS.Bars.Kit
        local e = r and K and K.live[r.id]
        local mx = e and NS.Bars.PlainMax and NS.Bars.PlainMax(e)
        return (mx and mx > 1) and math.floor(mx) or 200
    end
    Pause()
    local valRow = AT.RowSlider(pg, "Value",
        function()
            local g = SelRow()
            return (g and g.value) or 50
        end,
        function(v) Edit(function(S, r) S.SetRow(r, Sel(), "value", v) end) end,
        1, function() return Units() and math.max(2, UnitMax() - 1) or 99 end, 1, false, valueVis)
    AT.Tooltip(valRow, "Value", "A percent of the bar, or power with In power units on.")
    Stamp(valRow, "resStateValue", "Value")
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
    Stamp(gcol, "resStateGlowColor", "Glow color")
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
