-- AD_LoadRulesOptions: the Level and Zone section of every item's Load Conditions tab.
-- AD_Options' ConditionRows calls Options.LoadRuleRows behind a nil check; every write goes through NS.LoadRules.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

-- The rule in words: the level, the zone rule, then where you are now.
-- Translated, as drawn: zone names go in as they are.
function Options.LoadRuleText(r)
    local Tr, LR = NS.AT.Tr, NS.LoadRules
    local c = (r and r.c) or {}
    local lo, hi = tonumber(c.levelMin), tonumber(c.levelMax)
    local parts = {}
    if lo and hi then
        parts[1] = (lo == hi) and Tr("Level %d only."):format(lo) or Tr("Levels %d to %d."):format(lo, hi)
    elseif lo then
        parts[1] = Tr("Level %d and up."):format(lo)
    elseif hi then
        parts[1] = Tr("Level %d and below."):format(hi)
    else
        parts[1] = Tr("Any level.")
    end
    local listed = type(c.zones) == "table" and c.zones[1] ~= nil
    if c.zoneMode == "in" and listed then
        parts[2] = Tr("Only in the zones below.")
    elseif c.zoneMode == "out" and listed then
        parts[2] = Tr("Never in the zones below.")
    elseif c.zoneMode then
        parts[2] = Tr("Add a zone to use the zone rule.")
    else
        parts[2] = Tr("Any zone.")
    end
    local lv = LR.Level()
    local here = LR.Here()
    if lv and here ~= nil then
        parts[3] = Tr("You are level %d, in %s."):format(lv, LR.EntryName(here))
    end
    return table.concat(parts, " ")
end

function Options.LoadRuleRows(pg, ctx, tabVisible, uiStore, owner)
    local AT, COL, LR = NS.AT, NS.AT.COL, NS.LoadRules
    if not LR then return end
    local vis = function() return tabVisible() and ctx() ~= nil end
    AT.Section(pg, "Level and Zone", { collapsible = true, store = uiStore, visibleFn = vis })
    do
        local row = AT.AddRow(pg, 24, vis)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 11, "")
        fs:SetPoint("TOPLEFT", 10, -4)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        row._sync = function()
            local r = ctx()
            if not r then return end
            fs:SetText(Options.LoadRuleText(r))
            local w = row:GetWidth() or 0
            if w < 90 then w = (pg:GetWidth() or 0) - 24 end
            if w > 90 then fs:SetWidth(w - 20) end
            local want = math.max(24, math.floor((fs:GetStringHeight() or 12) + 10))
            if row._h ~= want then
                row._h = want
                row:SetHeight(want)
            end
        end
        row._adSearch = function() return { "Level and Zone", "Level", "Zone" } end
        row._adText = fs
    end
    local function Level(key)
        return function()
            local r = ctx()
            local v = r and r.c[key]
            return v and tostring(v) or ""
        end
    end
    AT.RowInput(pg, "Lowest level", Level("levelMin"),
        function(v)
            local r = ctx()
            if not r then return end
            LR.SetLevelMin(r, v)
            AT.LayoutPage(pg)
        end,
        vis, "Loads only from this level up. Leave it empty for any level.", "Any")
    AT.RowInput(pg, "Highest level", Level("levelMax"),
        function(v)
            local r = ctx()
            if not r then return end
            LR.SetLevelMax(r, v)
            AT.LayoutPage(pg)
        end,
        vis, "Loads only up to this level. Leave it empty for any level.", "Any")
    AT.RowDropdown(pg, owner, "Zone rule",
        function() local r = ctx() return (r and r.c.zoneMode) or "off" end,
        function(v)
            local r = ctx()
            if r then LR.SetZoneMode(r, v) end
            AT.LayoutPage(pg)
        end,
        function() return {
            { value = "off", text = "No zone rule" },
            { value = "in", text = "Only in these zones" },
            { value = "out", text = "Never in these zones" },
        } end,
        vis)
    local zoneOn = function()
        local r = ctx()
        return vis() and r.c.zoneMode ~= nil
    end
    AT.RowInput(pg, "Add a zone", function() return "" end,
        function(v)
            local r = ctx()
            if r and LR.AddZone(r, v) then AT.LayoutPage(pg) end
        end,
        zoneOn, "A zone or subzone name, or a map ID. Press Enter to add it.", "Zone name")
    AT.RowButton(pg, "Add current zone",
        function()
            local r = ctx()
            if r and LR.AddZone(r, LR.Here()) then AT.LayoutPage(pg) end
        end,
        zoneOn, 150, "Where you are")
    -- the listed zones, each with its own Remove
    for i = 1, LR.ZONES_MAX do
        local row = AT.AddRow(pg, 22, function()
            local r = ctx()
            return zoneOn() and type(r.c.zones) == "table" and r.c.zones[i] ~= nil
        end)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 11, "")
        fs:SetPoint("LEFT", 10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        local b = AT.MakeDangerButton(row, "Remove", 90)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r = ctx()
            if r then LR.RemoveZone(r, i) end
            AT.LayoutPage(pg)
        end)
        row._colCtrl = b
        row._adText = fs
        row._sync = function()
            local r = ctx()
            local e = r and type(r.c.zones) == "table" and r.c.zones[i]
            fs:SetText(e and LR.EntryName(e) or "")
        end
    end
    AT.Section(pg, nil)
end
