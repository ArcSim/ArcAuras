-- AD_RetailWho: the retail-only Load Conditions rows: a Role row under the class and spec matrix and a Hero Talents section.
-- AD_Options' ConditionRows calls Options.RetailWhoRows behind a nil check; every write goes through the Store's role and hero setters.
-- Nothing here shows on WoW Forever: the flavor flag hides the rows there, and that client ignores the keys they write.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local RW = {}
Options.RetailWho = RW

-- hero rows built ahead of time; no class has more trees than this
RW.HERO_SLOTS = 6
RW.ROLE_WORDS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

-- the names of the specs a hero tree serves, from the class matrix
function RW.SpecWords(tree)
    local Store = NS.Store
    local names = {}
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        if cls.tag == Store.ClassTag() then
            for _, sp in ipairs(cls.specs) do
                if tree.specs and tree.specs[sp.id] then names[#names + 1] = sp.name end
            end
        end
    end
    table.sort(names)
    return table.concat(names, ", ")
end

function Options.RetailWhoRows(pg, ctx, tabVisible, uiStore)
    if NS.IsForever == true then return end
    local AT, Store = NS.AT, NS.Store
    local COL = AT.COL

    -- Role: the spec's role, boxes under the spec columns. Every box checked
    -- is any role; the set collapses back to nothing when all three are back.
    local roleRow = AT.AddRow(pg, 22, tabVisible)
    local lbl = roleRow:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(STANDARD_TEXT_FONT, 10, "")
    lbl:SetPoint("LEFT", 4, 0)
    lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    lbl:SetText("Role")
    local cells = {}
    for i, role in ipairs(Store.ROLES) do
        local cb = AT.MakeCheckbox(roleRow)
        cb:SetPoint("LEFT", roleRow, "LEFT", 128 + (i - 1) * 104, 0)
        local fs = roleRow:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 10, "")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(RW.ROLE_WORDS[role] or role)
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        cb:SetScript("OnClick", function()
            local r = ctx()
            if r then Store.ToggleRole(r, role) end
            AT.LayoutPage(pg)
            Options.RefreshAll()
        end)
        cb:HookScript("OnEnter", function() cb:SetHover(true) end)
        cb:HookScript("OnLeave", function() cb:SetHover(false) end)
        cells[i] = { cb = cb, role = role }
    end
    roleRow._adSearch = function()
        return { "Role", "Tank role", "Healer role", "Damage role" }
    end
    roleRow._sync = function()
        local r = ctx()
        if not r then return end
        for _, cell in ipairs(cells) do cell.cb:SetOn(Store.RoleOn(r, cell.role)) end
    end

    -- Hero Talents: one box per hero tree of the player's class, its specs in
    -- dim text. Same rule as the roles: every box checked is no restriction.
    AT.Section(pg, "Hero Talents",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    local function Trees() return Store.HeroTrees() end
    AT.RowDesc(pg, "Every box checked = any hero talent tree.", 18,
        function() return tabVisible() and #Trees() > 0 end)
    AT.RowDesc(pg, "No hero talent trees on this character yet.", 20,
        function() return tabVisible() and #Trees() == 0 end)
    for i = 1, RW.HERO_SLOTS do
        local row = AT.AddRow(pg, 22, function() return tabVisible() and Trees()[i] ~= nil end)
        local cb = AT.MakeCheckbox(row)
        cb:SetPoint("LEFT", 4, 0)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 11, "")
        fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        local specFs = row:CreateFontString(nil, "OVERLAY")
        specFs:SetFont(STANDARD_TEXT_FONT, 10, "")
        specFs:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        specFs:SetPoint("RIGHT", -8, 0)
        specFs:SetJustifyH("LEFT")
        specFs:SetWordWrap(false)
        specFs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        cb:SetScript("OnClick", function()
            local r, t = ctx(), Trees()[i]
            if r and t then Store.ToggleHero(r, t.id) end
            AT.LayoutPage(pg)
            Options.RefreshAll()
        end)
        cb:HookScript("OnEnter", function() cb:SetHover(true) end)
        cb:HookScript("OnLeave", function() cb:SetHover(false) end)
        row._adSearch = function()
            local t = Trees()[i]
            return t and { t.name } or {}
        end
        row._sync = function()
            local r, t = ctx(), Trees()[i]
            if not (r and t) then return end
            fs:SetText(t.name)
            specFs:SetText(RW.SpecWords(t))
            cb:SetOn(Store.HeroOn(r, t.id))
        end
    end
end
