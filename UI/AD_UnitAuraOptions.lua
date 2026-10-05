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
    SR({ "auraType", "caster", "fill", "debuffLine" })
    AT.RowDesc(pg, "Rows and Columns are set under Appearance, Grid. Up to 40 show.", 20, On(function() return true end))
    AT.RowDesc(pg, "Most people want one row of 3 to 6 there.", 20, On(Plates))
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

-- Debuff type looks (Drivers\AD_TypeLooks.lua): the type picked in the strip
-- is a panel pick only. "All" holds the shared sizes, a type its own parts.
UO.chip, UO.chipGroup = "All", nil

function UO.TypeOn(g)
    return g ~= nil and NS.Store.ShowsAll(g) == true and NS.Store.Resolve(g, "typeLook", "looks") ~= "off"
end

-- Whether the group can show a type at all: with any Dispel types box ticked
-- the game shows only those, so the others (and auras with no type) never
-- appear; with none ticked every type shows.
function UO.TypeShown(g, key)
    if key == "All" then return true end
    local Store, any = NS.Store, false
    for _, d in ipairs({ "Magic", "Curse", "Disease", "Poison" }) do
        if Store.Resolve(g, "unitAuras", "dispel" .. d) == true then any = true end
    end
    if not any then return true end
    return key ~= "None" and Store.Resolve(g, "unitAuras", "dispel" .. key) == true
end

-- the open group's pick; another group, or a type it cannot show, is All
function UO.Chip(g)
    if g == nil or g.id ~= UO.chipGroup then return "All" end
    if not UO.TypeShown(g, UO.chip) then return "All" end
    return UO.chip
end

-- some type is filtered out by the Dispel types boxes
function UO.SomeHidden(g)
    return g ~= nil and not UO.TypeShown(g, "None")
end

function UO.Pick(g, key)
    UO.chip, UO.chipGroup = key, g and g.id
    if UO.openIcons then UO.openIcons() end
    -- the block sits under the icon sizes: bring the pick's rows into view
    C_Timer.After(0, function() UO.ScrollTo(key) end)
end

-- the first row of a pick, scrolled in when not in view
function UO.ScrollTo(key)
    local pg, S = UO.pg, Options.Search
    if not (pg and S and S.ScrollTo and pg:IsVisible()) then return end
    local want = key == "All" and "looks" or ("border" .. key)
    for _, sec in ipairs(pg._sections or {}) do
        for _, r in ipairs(sec.rows) do
            local m = r._adMeta
            if m and m.section == "typeLook" and m.field == want and r:IsVisible() then
                S.ScrollTo(pg, r)
                return
            end
        end
    end
end

function UO.TypeFields(key)
    return { "border" .. key, "color" .. key, "wash" .. key, "label" .. key, "glow" .. key }
end

-- a type with any part set away from its default
function UO.TypeChanged(g, key)
    local o = g and g.o and g.o.typeLook
    if not o then return false end
    for _, f in ipairs(UO.TypeFields(key)) do
        if o[f] ~= nil then return true end
    end
    return false
end

-- The strip's icons, as a group's own icons are picked: All, then each type
-- with a default icon (its dispel spell's), wearing that type's look.
UO.STRIP = {
    { key = "All", label = "All types", art = "Interface\\Icons\\INV_Misc_QuestionMark" },
    { key = "Magic", art = "Interface\\Icons\\Spell_Holy_DispelMagic" },
    { key = "Curse", art = "Interface\\Icons\\Spell_Holy_RemoveCurse" },
    { key = "Disease", art = "Interface\\Icons\\Spell_Holy_NullifyDisease" },
    { key = "Poison", art = "Interface\\Icons\\Spell_Nature_NullifyPoison" },
    { key = "None", art = "Interface\\Icons\\Ability_Gouge" },
}
UO.STRIP_SIZE, UO.STRIP_STEP = 32, 37

-- A strip icon's preview of one type's parts (drawn plainly: the window is
-- not the game's button). "All" shows none.
function UO.Preview(b, g, key)
    local TL = NS.TypeLooks
    if not TL then return end
    local pv = b._adPrev
    if not pv then
        pv = { edges = {} }
        for _, e in ipairs({ "top", "bottom", "left", "right" }) do
            local t = b:CreateTexture(nil, "OVERLAY", nil, 1)
            t:SetColorTexture(1, 1, 1, 1)
            pv.edges[e] = t
        end
        pv.edges.top:SetPoint("TOPLEFT", 1, -1) pv.edges.top:SetPoint("TOPRIGHT", -1, -1) pv.edges.top:SetHeight(2)
        pv.edges.bottom:SetPoint("BOTTOMLEFT", 1, 1) pv.edges.bottom:SetPoint("BOTTOMRIGHT", -1, 1) pv.edges.bottom:SetHeight(2)
        pv.edges.left:SetPoint("TOPLEFT", 1, -1) pv.edges.left:SetPoint("BOTTOMLEFT", 1, 1) pv.edges.left:SetWidth(2)
        pv.edges.right:SetPoint("TOPRIGHT", -1, -1) pv.edges.right:SetPoint("BOTTOMRIGHT", -1, 1) pv.edges.right:SetWidth(2)
        pv.art = b:CreateTexture(nil, "OVERLAY", nil, 2)
        pv.art:SetPoint("CENTER")
        pv.badge = b:CreateTexture(nil, "OVERLAY", nil, 3)
        pv.badge:SetPoint("TOPRIGHT", -1, -1)
        pv.wash = b:CreateTexture(nil, "ARTWORK", nil, 1)
        pv.wash:SetPoint("TOPLEFT", 1, -1)
        pv.wash:SetPoint("BOTTOMRIGHT", -1, 1)
        pv.glow = b:CreateTexture(nil, "OVERLAY", nil, 4)
        pv.glow:SetPoint("CENTER")
        pv.glow:SetTexture(TL.GLOW)
        pv.glow:SetTexCoord(TL.GLOW_TC.left, TL.GLOW_TC.right, TL.GLOW_TC.top, TL.GLOW_TC.bottom)
        pv.glow:SetBlendMode("ADD")
        pv.glow:SetDesaturated(true)
        pv.label = b:CreateFontString(nil, "OVERLAY")
        b._adPrev = pv
    end
    local p = key ~= "All" and TL and TL.Plan(g) or nil
    local c = p and p.colors[key]
    local border = p and ((p.color[key] and "color") or (p.blizzard[key] and "blizzard")
        or (p.blizzardBadge[key] and "blizzardBadge") or (p.badge[key] and "badge")) or nil
    for _, t in pairs(pv.edges) do
        if border == "color" then t:SetVertexColor(c[1], c[2], c[3], 1) end
        t:SetShown(border == "color")
    end
    local a = p and TL.Art(key)
    local atlas = a and ((border == "blizzard" and a.basicAtlas)
        or (border == "blizzardBadge" and (a.dispelAtlas or a.basicAtlas)))
    if atlas then
        pv.art:SetAtlas(atlas)
        pv.art:SetSize(b:GetWidth() * 1.15, b:GetHeight() * 1.15)
    end
    atlas = atlas or nil
    pv.art:SetShown(atlas ~= nil)
    pv.artAtlas = atlas
    local badge = border == "badge" and a and a.dispelIconAtlas
    if badge then
        pv.badge:SetAtlas(badge)
        pv.badge:SetSize(b:GetWidth() * 0.45, b:GetHeight() * 0.45)
    end
    pv.badge:SetShown(badge and true or false)
    local wash = p and p.wash[key]
    if wash then pv.wash:SetColorTexture(c[1], c[2], c[3], p.washAlpha) end
    pv.wash:SetShown(wash == true)
    local glow = p and p.glow[key]
    if glow then
        local s = math.min(p.glowSize, 1.3)
        pv.glow:SetVertexColor(c[1], c[2], c[3], 1)
        pv.glow:SetSize(b:GetWidth() * s, b:GetHeight() * s)
    end
    pv.glow:SetShown(glow == true)
    local text = p and p.labels[key]
    if text then
        pv.label:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        pv.label:ClearAllPoints()
        pv.label:SetPoint(p.labelAnchor, b, p.labelAnchor, 0, 0)
        pv.label:SetText(TL.LabelText(text, c))
    end
    pv.label:SetShown(text ~= nil)
end

-- The type picks in the group's strip, which holds no icons on a group showing
-- every aura: one icon per type, picked as a group's icon is.
function Options.TypeLookStrip(g, strip)
    local K, AT = Options.GroupPaneKit, NS.AT
    local btns = strip._adTypeBtns
    local on = UO.TypeOn(g)
    if not on then
        for _, b in ipairs(btns or {}) do b:Hide() end
        return
    end
    if not btns then
        btns = {}
        strip._adTypeBtns = btns
    end
    local names = {}
    for _, t in ipairs(NS.Schema.TYPE_LOOKS) do names[t.key] = t.label end
    -- a type the Dispel types boxes filter out never shows: no icon for it
    local cur, slot = UO.Chip(g), 0
    for i, s in ipairs(UO.STRIP) do
        local b = btns[i]
        if not b then
            b = K.IconButton(strip, UO.STRIP_SIZE)
            b.tex:SetTexture(s.art)
            b._adTypeKey = s.key
            local name = s.label or names[s.key] or s.key
            AT.Tooltip(b, name, s.key == "All" and "What every type shares: wash strength, label size and spot, glow size."
                or ("Click to give " .. name .. " its own look."))
            btns[i] = b
        end
        if UO.TypeShown(g, s.key) then
            slot = slot + 1
            b:ClearAllPoints()
            b:SetPoint("LEFT", 8 + (slot - 1) * UO.STRIP_STEP, 0)
            b:SetScript("OnClick", function() UO.Pick(g, s.key) end)
            b._adSelected = s.key == cur
            b:SetSelected(b._adSelected)
            UO.Preview(b, g, s.key)
            b:Show()
        else
            b:Hide()
        end
    end
end

-- The Debuff types block on Appearance > Icons of a group showing every aura.
-- kit: the page's SectionRows; openIcons() shows Appearance > Icons.
function Options.TypeLookRows(pg, ctx, tabVis, kit)
    local AT, Store = NS.AT, NS.Store
    UO.openIcons, UO.pg = kit.openIcons, pg
    local function G()
        local g = ctx()
        return (g and Store.ShowsAll(g)) and g or nil
    end
    local vis = function() return tabVis() and G() ~= nil end
    local function At(key) return function() return UO.Chip(ctx()) == key end end
    local function SR(fields, opts) kit.SectionRows(pg, "iconGroup", "typeLook", ctx, vis, fields, opts) end
    AT.Section(pg, "Debuff types", { visibleFn = vis })
    SR({ "looks" })
    AT.RowDesc(pg, "Click a type's icon at the top to give it its own look.", 20, function()
        return vis() and UO.TypeOn(G()) and UO.Chip(G()) == "All"
    end)
    AT.RowDesc(pg, "Only the types ticked under Tracking, Dispel types, show, so only they have an icon.", 20, function()
        return vis() and UO.TypeOn(G()) and UO.Chip(G()) == "All" and UO.SomeHidden(G())
    end)
    SR({ "washAlpha", "labelSize", "labelAnchor", "glowSize" },
        { showWhen = At("All"), reveal = function() UO.Pick(ctx(), "All") end })
    for _, t in ipairs(NS.Schema.TYPE_LOOKS) do
        local key = t.key
        SR(UO.TypeFields(key), { showWhen = At(key), reveal = function() UO.Pick(ctx(), key) end })
        AT.RowActions(pg, { { label = "Reset " .. t.label, w = 130, quiet = true, onClick = function()
            local g = G()
            if not g then return end
            for _, f in ipairs(UO.TypeFields(key)) do Store.SetOverride(g, "typeLook", f, nil) end
        end } }, "left", function()
            local g = G()
            return vis() and UO.TypeOn(g) and UO.Chip(g) == key and UO.TypeChanged(g, key)
        end)
    end
end
