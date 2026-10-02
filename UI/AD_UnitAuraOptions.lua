-- AD_UnitAuraOptions: an aura group's Tracking tab, where it shows its own aura icons or every aura on one unit.
-- AD_Options calls in behind nil checks (the group's tabs, the rows); the runtime is Drivers\AD_DriverUnitAuras.lua.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local UO = { TAB = "Tracking", withTab = setmetatable({}, { __mode = "k" }) }
Options.UnitAuraOptions = UO

-- An aura group opens on what it shows, where the game has the aura engine
-- (without it the tab would hold nothing).
function Options.UnitAuraTabsFor(g, tabs)
    local G = NS.DriverAuraGroups
    if not (g and g.groupKind == "aura" and G and G.IsAvailable()) then return tabs end
    local out = UO.withTab[tabs]
    if not out then
        out = { UO.TAB }
        for _, t in ipairs(tabs) do out[#out + 1] = t end
        UO.withTab[tabs] = out
    end
    return out
end

-- The alignment the placement reads, for AD_Options' Alignment row: a group
-- showing every aura reads it on its own grid, Rows by Columns.
function Options.GroupAlignment(g)
    local UA = NS.DriverUnitAuras
    if UA and NS.Store.ShowsAll(g) then return UA.Alignment(g) end
    return NS.LayoutEngine.EffectiveAlignment(g)
end

-- The Tracking tab's rows on the group editor's page. tabFn(): the open tab.
-- kit: the page's SectionRows.
function Options.UnitAuraGroupRows(pg, ctx, tabFn, kit)
    local AT, Store, Schema = NS.AT, NS.Store, NS.Schema
    local function G()
        local g = ctx()
        return (g and g.groupKind == "aura") and g or nil
    end
    local function vis() return tabFn() == UO.TAB and G() ~= nil end
    -- a note for a group showing every aura on its unit
    local function On(test)
        return function()
            if not vis() then return false end
            local g = G()
            return g ~= nil and Store.ShowsAll(g) and test(g) == true
        end
    end
    local function Plates(g) return Store.Resolve(g, "unitAuras", "unit") == "nameplate" end
    local function SR(fields) kit.SectionRows(pg, "iconGroup", "unitAuras", ctx, vis, fields) end

    AT.Section(pg, "Auras", { visibleFn = vis })
    SR({ "shows" })
    AT.RowDesc(pg, "The aura icons in this group are kept for when you switch back.", 20,
        On(function(g) return #Store.IconsOf(g) > 0 end))
    AT.RowDesc(pg, "It starts out of combat, or after a /reload.", 20, On(function(g)
        local UA = NS.DriverUnitAuras
        return UA ~= nil and UA.Waiting(g)
    end))
    SR({ "unit" })
    AT.RowDesc(pg, "Enemy nameplates show debuffs in this version.", 20, On(Plates))
    SR({ "auraType", "caster", "rows", "fill", "debuffLine" })
    AT.RowDesc(pg, "Columns is set under Appearance, Grid. Up to 40 show.", 20, On(function() return true end))
    AT.RowDesc(pg, "Most people want one row of 3 to 6 here.", 20, On(Plates))
    SR({ "order", "hideSpells" })
    -- where the game cannot hide an aura by spell, the list is not offered;
    -- with both halves it reaches the one the game honours
    AT.RowDesc(pg, "Debuffs on you or your pet cannot be hidden by spell.", 20, On(function(g)
        local unit, harmful = Schema.UnitAuraShape(g)
        return harmful and not Schema.UnitAuraHideOK(unit, harmful)
    end))
    AT.RowDesc(pg, "Buffs on a target or focus cannot be hidden by spell.", 20, On(function(g)
        local unit, harmful, both = Schema.UnitAuraShape(g)
        return not harmful and not both and not Schema.UnitAuraHideOK(unit, harmful)
    end))
    AT.RowDesc(pg, "With both, the hide list applies to the buffs only.", 20, On(function(g)
        local unit, _, both = Schema.UnitAuraShape(g)
        return both and Schema.UnitAuraHideOK(unit, false)
    end))
    AT.RowDesc(pg, "With both, the hide list applies to the debuffs only.", 20, On(function(g)
        local unit, _, both = Schema.UnitAuraShape(g)
        return both and Schema.UnitAuraHideOK(unit, true)
    end))
    AT.RowDesc(pg, "Nothing is hidden while the target or focus is friendly.", 20, On(function(g)
        local unit, harmful, both = Schema.UnitAuraShape(g)
        return (harmful or both) and not Plates(g) and Schema.UnitAuraHideOK(unit, true)
    end))
    SR({ "plateCount" })
    AT.RowDesc(pg, "Plates past the pool get their rows out of combat, or after a /reload.", 20, On(function(g)
        local UA = NS.DriverUnitAuras
        return UA ~= nil and UA.PoolShort(g)
    end))
    SR({ "plateEdge", "plateX", "plateY" })
    -- the game's own dispel-type filter: any unit, enemies too, in combat
    local always = On(function() return true end)
    AT.Section(pg, "Dispel types", { visibleFn = always })
    AT.RowDesc(pg, "Tick any to show only those types; none ticked shows every aura.", 20, always)
    SR({ "dispelMagic", "dispelCurse", "dispelDisease", "dispelPoison" })
end
