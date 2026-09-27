-- AD_RangeOptions: a range bar's band editor, under the Preset row on the bar editor's Tracking tab.
-- AD_Options calls Options.RangeBandRows while it builds the bar pane; every edit goes through
-- NS.RangeBars, which copies a preset into the bar's own bands on the first real change.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

-- vis: when the rows show (a range bar on Tracking). owner: the window the dropdown lists open on.
function Options.RangeBandRows(pg, ctx, vis, owner)
    local AT = NS.AT
    local COL = AT.COL
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
        local row = AT.AddRow(pg, 24, function() return vis() and Check() ~= nil end)
        local lbl = AT.RowLabel(row, "Check " .. j)
        local kind = AT.MakeDropdown(owner, row, 150,
            function()
                local RB, items = NS.RangeBars, {}
                for _, c in ipairs(RB and RB.CHOICES or {}) do items[#items + 1] = { value = c, text = RB.CHOICE_TEXT[c] } end
                return items
            end,
            function()
                local k = Check()
                return k and NS.RangeBars.CheckChoice(k)
            end,
            function(v) Edit(function(RB, r) RB.SetCheckChoice(r, i, j, v) end) end)
        local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        box:SetSize(100, 18)
        AT.Skin(box, COL.well)
        box:SetFont(STANDARD_TEXT_FONT, 11, "")
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
            box:SetText(Shown())
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
                    items[#items + 1] = { value = y, text = y .. " yd" }
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
            kind.Refresh()
            local k = Check()
            local spell = k ~= nil and k.kind == "spell"
            box:SetShown(spell)
            yards:SetShown(not spell)
            if spell and not box:HasFocus() then box:SetText(Shown()) end
            if not spell then yards.Refresh() end
            del:ClearAllPoints()
            del:SetPoint("LEFT", spell and box or yards, "RIGHT", 6, 0)
        end
    end

    for i = 1, maxB do
        if Options.BuildYield then Options.BuildYield() end
        local bandVis = function() return vis() and Band(i) ~= nil end
        AT.Section(pg, "Band " .. i, { visibleFn = bandVis })
        AT.RowInput(pg, "Band text",
            function()
                local b = Band(i)
                return b and b.text or ""
            end,
            function(v) Edit(function(RB, r) RB.SetBandText(r, i, v) end) end,
            bandVis, "What the bar says while the target is in this band.")
        AT.RowColor(pg, "Band color",
            function()
                local b = Band(i)
                return (b and b.color) or { 1, 1, 1, 1 }
            end,
            function(c) Edit(function(RB, r) RB.SetBandColor(r, i, c) end) end,
            bandVis)
        AT.RowToggle(pg, "Show this band",
            function()
                local b = Band(i)
                return b ~= nil and not b.off
            end,
            function(v) Edit(function(RB, r) RB.SetBandOff(r, i, not v) end) end,
            bandVis, "Off: the bar shows its no-band look while the target is in this band.")
        -- the band's checks in words
        local words = AT.AddRow(pg, 20, bandVis)
        local wfs = words:CreateFontString(nil, "OVERLAY")
        wfs:SetFont(STANDARD_TEXT_FONT, 11, "")
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
