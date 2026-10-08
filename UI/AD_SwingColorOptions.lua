-- AD_SwingColorOptions: a swing bar's ability colour rules, in the Ability Colors block of the bar editor's Appearance > Fill & Colors.
-- AD_Options calls Options.SwingColorRows while it builds the bar pane; every edit goes through NS.Bars.SwingColor.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local WHEN = {
    { value = "queued", text = "When queued" },
    { value = "cast", text = "After cast" },
}

-- vis: the Ability Colors block's own gate. owner: the window the dropdown
-- lists open on.
function Options.SwingColorRows(pg, ctx, vis, owner)
    local AT = NS.AT
    local COL = AT.COL
    local function SW() return NS.Bars and NS.Bars.SwingColor end
    local function Rec()
        local r = ctx()
        return (r and r.barKind == "swing" and SW()) and r or nil
    end
    local function Rules()
        local r = Rec()
        return r and SW().List(r) or {}
    end
    local function Rule(i) return Rules()[i] end
    -- the rules show while the switch is on
    local function onVis()
        local r = Rec()
        return vis() and r ~= nil and NS.Store.Resolve(r, "abilcolors", "abilColorsOn") == true
    end
    -- an edit, then the page again at once (the store's refresh comes a frame later)
    local function Edit(fn)
        local r = Rec()
        if r then fn(SW(), r) end
        AT.LayoutPage(pg)
    end
    -- found by the search while the switch is off; the jump flashes the switch
    local function Stamp(row, field, label)
        row._adMeta = { family = "bar", section = "abilcolors", field = field,
            def = { label = label, dep = { field = "abilColorsOn" } }, baseVis = vis }
    end
    local maxR = (SW() and SW().MaxRules()) or 8

    AT.RowDesc(pg, "When two apply at once, the one higher in the list wins.", 20, onVis)
    for i = 1, maxR do
        if Options.BuildYield then Options.BuildYield() end
        local ruleVis = function() return onVis() and Rule(i) ~= nil end
        -- Gated on the block alone: the rows carry the rule's gate, and a box
        -- whose rows are all hidden paints nothing.
        AT.Section(pg, "Ability " .. i, { visibleFn = vis })
        local idRow = AT.RowInput(pg, "Ability (spell ID)",
            function()
                local r = Rule(i)
                return (r and r.id) and tostring(r.id) or ""
            end,
            function(v)
                local DR = NS.DriverRange
                local id = (DR and DR.ParseSpell and DR.ParseSpell(v)) or tonumber(v)
                Edit(function(S, r) S.SetRule(r, i, "id", id) end)
            end,
            ruleVis,
            "A spell ID, or the name of a spell you know. Any rank works: the bar follows the rank you know.",
            "e.g. 78")
        -- the spell the ID stands for, beside the box
        local nameFS = idRow:CreateFontString(nil, "OVERLAY")
        nameFS:SetFont(NS.AT.FONT, 11, "")
        nameFS:SetPoint("LEFT", idRow._colCtrl, "RIGHT", 8, 0)
        nameFS:SetPoint("RIGHT", idRow, "RIGHT", -10, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        nameFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        local boxSync = idRow._sync
        idRow._sync = function()
            boxSync()
            local r = Rule(i)
            local nm = (r and r.id and C_Spell and C_Spell.GetSpellName) and C_Spell.GetSpellName(r.id) -- raw-id: the typed spell, for the editor's words
            if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" then nm = "" end
            nameFS:SetText(nm)
        end
        idRow._adName = nameFS
        local whenRow = AT.RowDropdown(pg, owner, "When",
            function()
                local r = Rule(i)
                return (r and r.when == "cast") and "cast" or "queued"
            end,
            function(v) Edit(function(S, r) S.SetRule(r, i, "when", v) end) end,
            function() return WHEN end,
            ruleVis)
        local whenTip = "When queued: while it waits to go off with your next swing. After cast: from the cast until the swing it went off in lands."
        AT.Tooltip(whenRow, "When", whenTip)
        AT.Tooltip(whenRow._colCtrl, "When", whenTip)
        local colRow = AT.RowColor(pg, "Color",
            function()
                local r = Rule(i)
                local c = r and r.color
                if type(c) ~= "table" then
                    c = (NS.Schema and NS.Schema.SWING_COLOR_DEFAULT) or { 1, 0.55, 0.15, 1 }
                end
                return c
            end,
            function(c) Edit(function(S, r) S.SetRule(r, i, "color", c) end) end,
            ruleVis, { alpha = true })
        AT.RowActions(pg, {
            { label = "Move up", w = 80, quiet = true,
              onClick = function() Edit(function(S, r) S.MoveRule(r, i, -1) end) end,
              visibleFn = function() return i > 1 end },
            { label = "Move down", w = 90, quiet = true,
              onClick = function() Edit(function(S, r) S.MoveRule(r, i, 1) end) end,
              visibleFn = function() return i < #Rules() end },
            { label = "Remove", w = 80, quiet = true,
              onClick = function() Edit(function(S, r) S.RemoveRule(r, i) end) end },
        }, "left", ruleVis)
        if i == 1 then
            Stamp(idRow, "swingColorSpell", "Ability (spell ID)")
            Stamp(whenRow, "swingColorWhen", "When")
            Stamp(colRow, "swingColorColor", "Color")
        end
    end
    AT.Section(pg, nil, { visibleFn = vis })
    local add = AT.RowActions(pg, {
        { label = "Add ability color", w = 130,
          onClick = function() Edit(function(S, r) S.AddRule(r) end) end },
    }, "left", function() return onVis() and #Rules() < maxR end)
    Stamp(add, "swingColorAdd", "Add ability color")
end
