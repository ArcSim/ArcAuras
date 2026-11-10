-- AD_RangeOptions: a range bar's band editor, under the Preset row on the bar editor's Tracking tab, and
-- its Distance trigger on the Effects tab. AD_Options calls Options.RangeBandRows and
-- Options.RangeDistanceRows while it builds the bar pane; every edit goes through NS.RangeBars, which
-- copies a preset into the bar's own bands on the first real change.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

-- The Distance trigger's chips: each band's words, in its colour.
local function DistanceChips(r)
    local out = {}
    local RB = NS.RangeBars
    if not RB or r._adMulti then return out end
    for _, b in ipairs(RB.BandsOf(r)) do
        out[#out + 1] = { text = RB.BandText(b), color = b.color }
    end
    return out
end
if Options.BarEffects then
    Options.BarEffects.TRIGGERS["Distance"] = { when = "Colors the bar at each distance band",
        line = "Colors the bar at each distance band", chips = DistanceChips }
end

-- The Distance table: a row per band with its words, colour and Show. The
-- words and checks are edited on Tracking.
function Options.RangeDistanceRows(pg, ctx, vis)
    local AT = NS.AT
    local COL = AT.COL
    local Tr = AT.Tr
    local maxB = (NS.Schema and NS.Schema.RANGE_MAX_BANDS) or 8
    local COLOR_W, SHOW_X = 35, 45
    local function Rec()
        local r = ctx()
        return (r and r.barKind == "range" and not r._adMulti and NS.RangeBars) and r or nil
    end
    local function Bands()
        local r = Rec()
        return r and NS.RangeBars.BandsOf(r) or {}
    end
    local function Edit(fn)
        local r = Rec()
        if r then fn(NS.RangeBars, r) end
        AT.LayoutPage(pg)
    end
    local function Cols(row)
        local f = CreateFrame("Frame", nil, row)
        f:SetSize(SHOW_X + 18, 20)
        f:SetPoint("LEFT", row._ctrlX, 0)
        return f
    end
    local function Faint(parent, text)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 10, "")
        fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        fs:SetText(text)
        return fs
    end

    local head = AT.AddRow(pg, 20, function() return vis() and Rec() ~= nil end)
    do
        local lbl = Faint(head, Tr("Band"))
        lbl:SetPoint("LEFT", 10, 0)
        local cols = Cols(head)
        local colorW = Faint(cols, Tr("Color"))
        colorW:SetPoint("LEFT", 0, 0)
        local showW = Faint(cols, Tr("Show"))
        showW:SetPoint("LEFT", SHOW_X, 0)
        head._colLabel, head._colCtrl = lbl, cols
    end
    -- found by the search under the words the Tracking rows had
    head._adMeta = { family = "bar", section = "range", field = "rangeBandShow",
        def = { label = "Show this band" }, baseVis = vis }

    for i = 1, maxB do
        if Options.BuildYield then Options.BuildYield() end
        local function Band() return Bands()[i] end
        local row = AT.AddRow(pg, 26, function() return vis() and Band() ~= nil end)
        local lbl = AT.RowLabel(row, "")
        local cols = Cols(row)
        local sw = AT.MakeSwatch(cols, COLOR_W, 16)
        sw:SetPoint("LEFT", 0, 0)
        cols._sw = sw
        local show = AT.MakeCheckbox(cols)
        cols._show = show
        show:SetPoint("LEFT", SHOW_X, 0)
        row._colLabel, row._colCtrl = lbl, cols
        sw:SetScript("OnClick", function()
            local BX = Options.BarEffects
            if not (BX and Band()) then return end
            BX.PickColor(function() return Band().color or { 1, 1, 1, 1 } end,
                function(c) Edit(function(RB, r) RB.SetBandColor(r, i, c) end) end)
        end)
        AT.Tooltip(sw, "Band color", "The bar's color while the target is in this band.")
        show:SetScript("OnClick", function()
            local b = Band()
            if not b then return end
            AT.CloseDropdown()
            local off = not b.off
            Edit(function(RB, r) RB.SetBandOff(r, i, off) end)
        end)
        show:SetScript("OnEnter", function() show:SetHover(true) end)
        show:SetScript("OnLeave", function() show:SetHover(false) end)
        AT.Tooltip(show, "Show this band", "Off: the bar shows its no-band look while the target is in this band.")
        row._sync = function()
            local b = Band()
            if not b then return end
            lbl:SetText(NS.RangeBars.BandText(b))
            local c = b.color or { 1, 1, 1, 1 }
            sw:SetColor(c, c[4] or 1)
            show:SetOn(not b.off)
        end
        if i == 1 then
            row._adMeta = { family = "bar", section = "range", field = "rangeBandColor",
                def = { label = "Band color" }, baseVis = vis }
        end
    end
end

-- vis: when the rows show (a range bar on Tracking). owner: the window the dropdown lists open on.
function Options.RangeBandRows(pg, ctx, vis, owner)
    local AT = NS.AT
    local COL = AT.COL
    local Tr = AT.Tr
    local maxB = (NS.Schema and NS.Schema.RANGE_MAX_BANDS) or 8
    local maxC = (NS.Schema and NS.Schema.RANGE_MAX_CHECKS) or 4
    local function Rec()
        local r = ctx()
        return (r and r.barKind == "range" and NS.RangeBars) and r or nil
    end
    local function Bands()
        local r = Rec()
        return r and NS.RangeBars.BandsOf(r) or {}
    end
    local function Band(i) return Bands()[i] end
    -- a check's kind field keeps its English width and grows to the longest
    -- choice in a longer language, so no choice is cut off
    local KIND_W = 150
    local measure
    local function FitKind(dd, items)
        if not measure then
            measure = pg:CreateFontString(nil, "ARTWORK")
            measure:SetFont(AT.FONT, 11, "")
            measure:Hide()
        end
        local widest = 0
        for _, it in ipairs(items) do
            measure:SetText(Tr(it.text) or "")
            local tw = (measure.GetUnboundedStringWidth and measure:GetUnboundedStringWidth())
                or measure:GetStringWidth() or 0
            if type(tw) == "number" and tw > widest then widest = tw end
        end
        local want = math.max(KIND_W, math.ceil(widest) + 30)
        if (dd:GetWidth() or 0) ~= want then dd:SetWidth(want) end
    end
    -- an edit, then the page again at once (the store's refresh comes a frame later)
    local function Edit(fn)
        local r = Rec()
        if r then fn(NS.RangeBars, r) end
        AT.LayoutPage(pg)
    end

    AT.Section(pg, "Bands", { visibleFn = vis })
    AT.RowDesc(pg, "Nearest first: the target is in the first band whose checks all hold.", 20, vis)

    -- One check: its kind on the control column, then a spell box or a distance,
    -- then a quiet x.
    local function CheckRow(i, j)
        local function Check()
            local b = Band(i)
            return b and b.checks and b.checks[j]
        end
        if Options.BuildYield then Options.BuildYield() end
        local row = AT.AddRow(pg, 24, function() return vis() and Check() ~= nil end)
        local lbl = AT.RowLabel(row, Tr("Check %d"):format(j))
        local function KindItems()
            local RB, items = NS.RangeBars, {}
            for _, c in ipairs(RB and RB.CHOICES or {}) do items[#items + 1] = { value = c, text = RB.CHOICE_TEXT[c] } end
            return items
        end
        local kind = AT.MakeDropdown(owner, row, KIND_W, KindItems,
            function()
                local k = Check()
                return k and NS.RangeBars.CheckChoice(k)
            end,
            function(v) Edit(function(RB, r) RB.SetCheckChoice(r, i, j, v) end) end)
        local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        box:SetSize(100, 18)
        AT.Skin(box, COL.well)
        box:SetFont(NS.AT.FONT, 11, "")
        box:SetTextInsets(6, 6, 0, 0)
        box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        box:SetAutoFocus(false)
        box:SetPoint("LEFT", kind, "RIGHT", 6, 0)
        local function Shown()
            local k = Check()
            return (k and k.id) and tostring(k.id) or ""
        end
        box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
        box:SetScript("OnEscapePressed", function()
            AT.BoxText(box, Shown())
            box:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function()
            local DR = NS.DriverRange
            local text = box:GetText() or ""
            Edit(function(RB, r) RB.SetCheckSpell(r, i, j, (DR and DR.ParseSpell(text)) or tonumber(text)) end)
        end)
        AT.Tooltip(box, "Spell", "A spell ID, or the name of a spell you know. The rank you know is checked.")
        local yards = AT.MakeDropdown(owner, row, 80,
            function()
                local items = {}
                for _, y in ipairs((NS.Schema and NS.Schema.RANGE_YARDS) or {}) do
                    items[#items + 1] = { value = y, text = Tr("%s yd"):format(y) }
                end
                return items
            end,
            function()
                local k = Check()
                return k and k.yd
            end,
            function(v) Edit(function(RB, r) RB.SetCheckYards(r, i, j, v) end) end)
        yards:SetPoint("LEFT", kind, "RIGHT", 6, 0)
        local del = AT.MakeQuietButton(row, "x", 22)
        del:SetScript("OnClick", function()
            AT.CloseDropdown()
            Edit(function(RB, r) RB.RemoveCheck(r, i, j) end)
        end)
        AT.Tooltip(del, "Remove", "Removes this check from the band.")
        row._colLabel, row._colCtrl = lbl, kind
        row._sync = function()
            FitKind(kind, KindItems())
            kind.Refresh()
            local k = Check()
            local spell = k ~= nil and k.kind == "spell"
            box:SetShown(spell)
            yards:SetShown(not spell)
            if spell and not box:HasFocus() then AT.BoxText(box, Shown()) end
            if not spell then yards.Refresh() end
            del:ClearAllPoints()
            del:SetPoint("LEFT", spell and box or yards, "RIGHT", 6, 0)
        end
    end

    for i = 1, maxB do
        if Options.BuildYield then Options.BuildYield() end
        local bandVis = function() return vis() and Band(i) ~= nil end
        AT.Section(pg, Tr("Band %d"):format(i), { visibleFn = bandVis })
        -- a preset band's words as the bar draws them; the player's own as typed
        AT.RowInput(pg, "Band text",
            function()
                local b = Band(i)
                return b and NS.RangeBars.BandText(b) or ""
            end,
            function(v) Edit(function(RB, r) RB.SetBandText(r, i, v) end) end,
            bandVis, "What the bar says while the target is in this band.")
        -- the band's checks in words
        local words = AT.AddRow(pg, 20, bandVis)
        local wfs = words:CreateFontString(nil, "OVERLAY")
        wfs:SetFont(NS.AT.FONT, 11, "")
        wfs:SetPoint("LEFT", 10, 0)
        wfs:SetPoint("RIGHT", -10, 0)
        wfs:SetJustifyH("LEFT")
        wfs:SetWordWrap(false)
        wfs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        words._sync = function()
            local b = Band(i)
            wfs:SetText(b and NS.RangeBars.BandWords(b) or "")
        end
        for j = 1, maxC do CheckRow(i, j) end
        AT.RowActions(pg, {
            { label = "Add check", w = 90,
              onClick = function() Edit(function(RB, r) RB.AddCheck(r, i) end) end,
              visibleFn = function()
                  local b = Band(i)
                  return b ~= nil and #(b.checks or {}) < maxC
              end },
            { label = "Move up", w = 80,
              onClick = function() Edit(function(RB, r) RB.MoveBand(r, i, -1) end) end,
              visibleFn = function() return i > 1 end },
            { label = "Move down", w = 90,
              onClick = function() Edit(function(RB, r) RB.MoveBand(r, i, 1) end) end,
              visibleFn = function() return i < #Bands() end },
            { label = "Remove band", w = 100, quiet = true,
              onClick = function() Edit(function(RB, r) RB.RemoveBand(r, i) end) end,
              visibleFn = function() return #Bands() > 1 end },
        }, "left", bandVis)
    end
    AT.Section(pg, nil, { visibleFn = vis })
    AT.RowActions(pg, {
        { label = "Add band", w = 90,
          onClick = function() Edit(function(RB, r) RB.AddBand(r) end) end,
          visibleFn = function() return #Bands() < maxB end },
    }, "left", vis)
end
