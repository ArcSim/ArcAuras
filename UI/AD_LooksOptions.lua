-- AD_LooksOptions: the rows that give a resource bar its own look per power (a
-- druid's forms), per spec, or with and without a talent (Core\AD_Looks.lua):
-- what the looks follow, which look the rows below edit, and a reset. Called
-- behind nil checks by the bar editor; editing a look shows it on the bar
-- until another is picked or the editor closes. The talent rows list what the
-- custom triggers' talent guard lists (UI\AD_CustomOptions.lua).
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local LO = {}
Options.LooksUI = LO

LO.MODE_ITEMS = {
    { value = "", text = "One look" },
    { value = "power", text = "Each power (druid forms)" },
    { value = "spec", text = "Each spec" },
    { value = "talent", text = "With or without a talent" },
}

-- pg / ctx / vis as every row builder; withMode draws the "Look for" row too
-- (the first place the rows appear), else only the editing rows.
function Options.LooksRows(pg, ctx, vis, owner, withMode)
    local AT, Store, COL = NS.AT, NS.Store, NS.AT.COL
    local function L() return NS.Looks end
    local function Rec()
        local r = ctx()
        local LK = L()
        if not (r and not r._adMulti and LK and LK.Offered(r)) then return nil end
        return r
    end
    local function Mode()
        local r = Rec()
        return r and r.looks and r.looks.by or nil
    end
    local on = function() return vis() and Rec() ~= nil end
    local looksOn = function() return on() and Mode() ~= nil end

    if withMode then
        local row = AT.RowDropdown(pg, owner, "Look for",
            function() return Mode() or "" end,
            function(v)
                local r, LK = Rec(), L()
                if r and LK then LK.SetMode(r, (v ~= "") and v or nil) end
            end,
            function()
                local r, LK = Rec(), L()
                local items = {}
                for _, it in ipairs(LO.MODE_ITEMS) do
                    if it.value == "" or (r and LK and LK.ModeOK(r, it.value)) then items[#items + 1] = it end
                end
                return items
            end, on,
            function() AT.LayoutPage(pg) end)
        AT.Tooltip(row, "Look for",
            "Colors, texts and ticks of their own for each power (a druid's forms), each spec, or with and without a talent.")

        local talentOn = function() return on() and Mode() == "talent" end
        -- picked on the Load Conditions talent tree (a choice node's option is
        -- its own button); a look has With and Without, so no Not taken
        Options.TalentPickRow(pg, "Talent", function()
            local r, LK = Rec(), L()
            if not (r and LK) then return nil end
            return {
                talentTarget = true, noExclude = true,
                State = function(node)
                    local lk = r.looks
                    if not (lk and lk.talentNode == node) then return nil end
                    return "req", lk.talentEntry
                end,
                Set = function(node, state, entry)
                    if state == nil then
                        if r.looks and r.looks.talentNode == node then LK.SetTalent(r, nil) end
                    else
                        LK.SetTalent(r, node)
                        LK.SetChoice(r, entry)
                    end
                    AT.LayoutPage(pg)
                end,
                List = function()
                    local node = r.looks and r.looks.talentNode
                    return node and { { nodeID = node } } or {}
                end,
                Clear = function()
                    LK.SetTalent(r, nil)
                    AT.LayoutPage(pg)
                end,
            }
        end, talentOn, "Opens the talent tree: the bar keeps one look while you have the talent you pick, one while you don't.")
    end

    local editRow = AT.RowDropdown(pg, owner, "Editing",
        function()
            local r, LK = Rec(), L()
            local k = r and LK and LK.editing[r.id]
            return (k == nil) and LK.BASE or k
        end,
        function(v)
            local r, LK = Rec(), L()
            if r and LK then LK.SetEditing(r, v) end
        end,
        function()
            local r, LK = Rec(), L()
            local items = { { value = LK and LK.BASE or "base", text = "The bar's own look" } }
            if r and LK and Mode() then
                for _, it in ipairs(LK.Keys(r, Mode())) do
                    local mark = LK.HasLook(r, it.value) and "  (changed)" or ""
                    items[#items + 1] = { value = it.value, text = it.text .. mark }
                end
            end
            return items
        end, looksOn,
        function() AT.LayoutPage(pg) end)
    AT.Tooltip(editRow, "Editing",
        "The look the rows below change. The bar shows it while you edit; anything a look leaves alone follows the bar's own.")
    -- the rows show what they edit: with no look picked yet that is the bar's own,
    -- not the look of the form you happen to be in
    local baseSync = editRow._sync
    editRow._sync = function()
        local r, LK = Rec(), L()
        if r and LK and looksOn() and LK.editing[r.id] == nil then LK.SetEditing(r, LK.BASE) end
        if baseSync then baseSync() end
    end

    local function Editing()
        local r, LK = Rec(), L()
        local k = r and LK and LK.editing[r.id]
        if k == nil or k == LK.BASE then return nil end
        return k
    end
    AT.RowActions(pg, {
        { label = "Reset this look", w = 130, quiet = true,
            onClick = function()
                local r, LK, k = Rec(), L(), Editing()
                if r and LK and k ~= nil then LK.Reset(r, k) AT.LayoutPage(pg) end
            end,
            visibleFn = function()
                local r, LK, k = Rec(), L(), Editing()
                return r ~= nil and LK ~= nil and k ~= nil and LK.HasLook(r, k)
            end },
    }, "left", function()
        local r, LK, k = Rec(), L(), Editing()
        return looksOn() and k ~= nil and LK.HasLook(r, k)
    end)

    -- what the rows below change, in words
    local line = AT.AddRow(pg, 30, looksOn)
    local fs = line:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -4)
    fs:SetPoint("TOPRIGHT", -10, -4)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    line._sync = function()
        local r, LK, k = Rec(), L(), Editing()
        if not (r and LK) then fs:SetText("") return end
        local mode = Mode()
        if k == nil then
            if mode == "talent" and not r.looks.talentNode then
                fs:SetText("Pick a talent, then the look to edit: with it or without it.")
            elseif mode == "talent" then
                fs:SetText("Changes below are the bar's own look. A talent look changes only what it sets.")
            else
                fs:SetText("Changes below are the bar's own look, for every power or spec without a look of its own.")
            end
            return
        end
        local name, when = tostring(k), nil
        for _, it in ipairs(LK.Keys(r, mode)) do
            if it.value == k then name, when = it.text, it.line end
        end
        if when then
            fs:SetText("Changes below apply only " .. when .. ". Place and size stay the bar's.")
        else
            fs:SetText("Changes below apply only to " .. name .. ". Place and size stay the bar's.")
        end
    end

    -- the editor's editing state ends with the editor
    pg:HookScript("OnHide", function()
        local LK = L()
        if LK then LK.StopEditing() end
    end)
end
