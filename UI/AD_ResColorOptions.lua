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
-- the table's columns, measured from the row's right edge
RSO.COLS = { remove = { w = 22 }, glow = { w = 96 }, mark = { w = 78 }, text = { w = 56 }, fill = { w = 56 } }
RSO.GAP = 10
-- the open row per bar
RSO.sel = {}

local function CRm() return NS.Bars and NS.Bars.ResColor end

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

    -- The table

    AT.RowDesc(pg, RSO.NOTE, 20, function() return vis() and #Rows() > 0 end)
    local C, GAP = RSO.COLS, RSO.GAP
    -- each cell's right edge, from the row's right
    local right = {}
    do
        local x = 8
        for _, k in ipairs({ "remove", "glow", "mark", "text", "fill" }) do
            right[k] = x
            x = x + C[k].w + GAP
        end
        RSO.LABEL_RIGHT = x
    end
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

    local head = AT.AddRow(pg, 22, function() return vis() and #Rows() > 0 end)
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
    end
    Stamp(head, "resStates", "How the bar looks in each state")
    -- the open row follows the sub-tab into the preview
    head._sync = function()
        local C2 = CRm()
        if not C2 then return end
        local r = Rec()
        local want = (r and RSO.Open() and vis()) and Sel() or nil
        if C2.previewSel ~= want then
            C2.previewSel = want
            if NS.Bars.PreviewRepaint then NS.Bars.PreviewRepaint() end
        end
    end

    for i = 1, maxR do
        if Options.BuildYield then Options.BuildYield() end
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
        local sub = Faint(normal, 11)
        sub:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        sub:SetText("the bar's own colors")
        local fillW = Faint(normal, 11)
        fillW:SetPoint("LEFT", Cell(normal, "fill"), "LEFT", 0, 0)
        fillW:SetText("own")
        local textW = Faint(normal, 11)
        textW:SetPoint("LEFT", Cell(normal, "text"), "LEFT", 0, 0)
        normal._sync = function()
            line:SetHeight(AT.Hairline(normal))
            local r = Rec()
            local follow = r and Store.Resolve(r, "rescolors", "resTextFill") == true
            textW:SetText(follow and "fill" or "own")
        end
    end

    -- Add a state: the pick, then the button, under the table's STATE column
    -- (where the state names start), so the new row's place reads at once and
    -- no label leaves a gap before the column of the toggle below
    RSO.addKind = RSO.addKind or "enough"
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
        local btn = AT.MakeSmallButton(add, "Add state", 84)
        btn:SetPoint("LEFT", dd, "RIGHT", 8, 0)
        btn:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r = Rec()
            local n = r and CRm().AddRow(r, RSO.addKind)
            if n then RSO.sel[r.id] = n end
            AT.LayoutPage(pg)
        end)
        add._sync = dd.Refresh
        Stamp(add, "resStateAdd", "Add a state")
    end
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
    -- the section names the open row
    local whenSync = whenRow._sync
    whenRow._sync = function()
        whenSync()
        local g = SelRow()
        local t = edSec and edSec.title
        if not (g and t) then return end
        local words = RSO.Label(g)
        t:SetText(edSec.boxed and words or string.upper(words))
    end
    Stamp(whenRow, "resStateWhen", "State")

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
    local AuraSuggest = Options.AuraSuggestPanel and Options.AuraSuggestPanel(pg, auraVis, Typed, AuraAdd,
        false, nil, true)
    if AuraSuggest and idRow._colCtrl then
        idRow._colCtrl:HookScript("OnTextChanged", function(_, userInput)
            if userInput then AuraSuggest(false) end
        end)
    end
    idRow._adCommit, idRow._adAdd, idRow._adSuggest = AuraCommit, AuraAdd, AuraSuggest
    Stamp(idRow, "resStateAura", RSO.AURA_IDS)
    AT.RowToggle(pg, "Follow my rank",
        function()
            local g = SelRow()
            return g == nil or g.followRank ~= false
        end,
        function(v) AuraEdit(function(g) if v then g.followRank = nil else g.followRank = false end end) end,
        function() return auraVis() and NS.IsForever == true end,
        Options.FOLLOW_RANK_DESC)
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
    local unitRow = AT.RowDropdown(pg, owner, "On unit",
        function() return (DA.ShapeOf((SelRow()) or {})) end,
        function(v) AuraEdit(function(g) g.unit = v end) end,
        function()
            local g = SelRow() or {}
            return Options.AuraUnitItems(g, nil, (DA.ShapeOf(g)))
        end,
        auraVis)
    AT.Tooltip(unitRow, "On unit", "Who carries the aura: a buff on you, a debuff on your target, or another unit.")
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
    local valRow = AT.RowSlider(pg, "Value",
        function()
            local g = SelRow()
            return (g and g.value) or 50
        end,
        function(v) Edit(function(S, r) S.SetRow(r, Sel(), "value", v) end) end,
        1, function() return Units() and math.max(2, UnitMax() - 1) or 99 end, 1, false, valueVis)
    AT.Tooltip(valRow, "Value", "A percent of the bar, or power with In power units on.")
    Stamp(valRow, "resStateValue", "Value")
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
    local gcol = AT.RowColor(pg, "Glow color",
        function()
            local g = SelRow()
            local c = g and type(g.glow) == "table" and g.glow.color
            return c or NS.Schema.bar.glows.fields.barGlowColor.d
        end,
        function(c) GlowSet("color", { c[1], c[2], c[3], c[4] or 1 }) end,
        glowVis, { alpha = true })
    Stamp(gcol, "resStateGlowColor", "Glow color")
    AT.RowToggle(pg, "Glow only in combat",
        function() return GlowGet("combat", false) == true end,
        function(v) GlowSet("combat", v) end,
        glowVis, "The glow waits for combat; out of combat the bar shows without it.")
    local fold = ET and ET.NewFold(pg, "resStateGlow", "glow", ctx)
    local function Tuning(label, key, lo, hi, step, fmt, when)
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
            if p ~= pg then return end
            local open = RSO.Open()
            if open ~= RSO.lastOpen then
                RSO.lastOpen = open
                if G and G.PreviewSync then G.PreviewSync() end
            end
        end)
    end
end
