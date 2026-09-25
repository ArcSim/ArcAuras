-- The options window: the rail, an editor for layouts, groups, icons and bars,
-- the settings pages, import / export and the search. The main chunk sits close
-- to Lua's 200-local limit, so new helpers go on Options, not in new locals.

local ADDON, NS = ...
local AT = NS.AT
local COL = AT.COL
local Schema = NS.Schema
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory
local Engine = NS.LayoutEngine

local Options = {}
NS.Options = Options

local WHITE = AT.WHITE
local YELLOW = { 0.949, 0.757, 0.306 }   -- CD Group
local PURPLE = { 0.710, 0.549, 0.949 }   -- Aura Group
local SHR = { 0.435, 0.659, 0.769 }

local win
local ui = {
    selType = nil,      -- "layout" | "group" | "free" | "bar"
    selId = nil,        -- layout, group or bar id
    selIconId = nil,    -- selected icon inside group/free pane
    grpMode = "grp",    -- "grp" | "ico"
    layoutTab = "Position",
    grpTab = "Arrangement",
    icoTab = "Tracking",
    barTab = "Tracking",
    search = "",
    ieSel = {},         -- export picker: record id -> true (ticked)
    ieOpen = {},        -- export picker: layout id -> true (tree open)
    ieTargetId = nil,   -- import target picked on the Import / Export page
    lastLayoutId = nil, -- the layout the rail last had open
}

local function ExpandedSet()
    local u = Store.UI()
    u.expanded = u.expanded or {}
    return u.expanded
end

local function SelLayout()
    if ui.selType == "layout" then return Store.Get(ui.selId) end
    if ui.selType == "group" or ui.selType == "bar" then
        local r = Store.Get(ui.selId)
        return r and Store.Get(r.layoutId)
    end
    if ui.selType == "free" then return Store.Get(ui.selId) end
end

local function SelGroup()
    if ui.selType == "group" then return Store.Get(ui.selId) end
end

local function SelIcon() return Store.Get(ui.selIconId) end

local function SelBar()
    if ui.selType == "bar" then return Store.Get(ui.selId) end
end

-- The layout engine draws the grow arrows on this group.
function Options.SelectedGroupId()
    if ui.selType == "group" then return ui.selId end
end

-- Tab order: what it tracks, how it looks and behaves, then where it shows.
local KIND_TABS = {
    spell   = { "Tracking", "Appearance", "Position", "States", "Swipe", "Text", "Keybind", "Label", "Alerts", "Visibility", "Load Conditions" },
    aura    = { "Tracking", "Appearance", "Position", "Aura Active", "Aura Missing", "Swipe", "Text", "Label", "Visibility", "Load Conditions" },
    trinket = { "Tracking", "Appearance", "Position", "States", "Swipe", "Out of Stock", "Text", "Label", "Alerts", "Visibility", "Load Conditions" },
    item    = { "Tracking", "Appearance", "Position", "States", "Swipe", "Out of Stock", "Text", "Label", "Alerts", "Visibility", "Load Conditions" },
    timer   = { "Tracking", "Appearance", "Position", "States", "Swipe", "Text", "Keybind", "Label", "Visibility", "Load Conditions" },
    totem   = { "Tracking", "Appearance", "Position", "States", "Swipe", "Text", "Label", "Visibility", "Load Conditions" },
    -- Ammo has no cooldown and no binding, so no Swipe, Keybind or Alerts.
    ammo    = { "Tracking", "Appearance", "Position", "States", "Out of Stock", "Text", "Label", "Visibility", "Load Conditions" },
}

-- An aura-group icon is drawn by the group's engine rows, which cannot hide or
-- fade one member in combat, so its conditions and Visibility live on the group.
local function InAuraGroup(rec)
    if not (rec and rec.type == "icon" and rec.groupId) then return false end
    local g = Store.Get(rec.groupId)
    return g ~= nil and g.groupKind == "aura"
end

local function IconTabsFor(rec)
    local tabs = KIND_TABS[rec.kind] or KIND_TABS.spell
    local overlay = rec.kind == "spell" and NS.DriverAura and NS.DriverAura.OverlayOn
        and NS.DriverAura.OverlayOn(rec)
    -- A free icon can anchor; a group member's cell places it.
    local free = rec.groupId == nil
    if overlay or free then
        local out = {}
        for _, t in ipairs(tabs) do
            out[#out + 1] = t
            if overlay and t == "States" then out[#out + 1] = "Aura Active" end
            if free and t == "Position" then out[#out + 1] = "Anchor" end
        end
        tabs = out
    end
    if not InAuraGroup(rec) then return tabs end
    local out = {}
    for _, t in ipairs(tabs) do
        if t ~= "Visibility" then out[#out + 1] = t end
    end
    return out
end
Options._iconTabsFor = IconTabsFor   -- test harness handle
local TAB_SECTION = {   -- editor tab -> schema section for the push bar
    Appearance = "appearance", States = "states", Swipe = "swipe",
    ["Aura Missing"] = "auraMissing", ["Aura Active"] = "auraActive", Text = "text",
    ["Out of Stock"] = "outOfStock", Label = "label", Alerts = "alerts",
}

local GREENC = { 0.482, 0.847, 0.561 }

-- Segments live on Appearance; the schema hides them from kinds without them.
local BAR_TABS = {
    -- Behavior holds the state hides, which only cooldown bars have.
    cooldown = { "Tracking", "Appearance", "Position", "Text", "Thresholds", "Behavior", "Anchor", "Visibility", "Load Conditions" },
    aura     = { "Tracking", "Appearance", "Position", "Text", "Thresholds", "Anchor", "Visibility", "Load Conditions" },
    timer    = { "Tracking", "Appearance", "Position", "Text", "Thresholds", "Anchor", "Visibility", "Load Conditions" },
    stack    = { "Tracking", "Appearance", "Position", "Text", "Anchor", "Visibility", "Load Conditions" },
    swing    = { "Tracking", "Appearance", "Position", "Text", "Thresholds", "Anchor", "Visibility", "Load Conditions" },
    resource = { "Tracking", "Appearance", "Position", "Text", "Thresholds", "Anchor", "Visibility", "Load Conditions" },
    health   = { "Tracking", "Appearance", "Heals & Shields", "Position", "Text", "Thresholds", "Anchor", "Visibility", "Load Conditions" },
    cast     = { "Tracking", "Appearance", "Castbar", "Position", "Text", "Anchor", "Visibility", "Load Conditions" },
}

-- C_SwingTimer swing types; the API exists only on WoW Forever.
local SWING_TYPES = {
    { value = 0, text = "Main Hand" },
    { value = 1, text = "Off Hand" },
    { value = 2, text = "Ranged" },
}
local function SwingLabel(v)
    for _, it in ipairs(SWING_TYPES) do
        if it.value == v then return it.text end
    end
    return "Main Hand"
end

-- The stack colour bands in words for the editor's summary row, e.g. "Fill
-- color below 2 stacks | Color 2 from 2 stacks". DetectMaxStacks below asks
-- the client (nil = unknown); a typed max wins, as the client is wrong for
-- some spells.
function Options.StackColorSummary(rec)
    local B = NS.Bars
    if not (B and B.MaxStacksFor and B.StackBands) then return "" end
    local M = B.MaxStacksFor(rec)
    local function span(a, b) return (a == b) and tostring(a) or (a .. "-" .. b) end
    local parts = {}
    local bands = B.StackBands(rec, M)
    local segmented = Store.Resolve(rec, "stackcolors", "scPosition") == true
    if not bands then
        parts[#parts + 1] = "Fill color at every stack"
    elseif segmented then
        local lo = 1
        for k, band in ipairs(bands) do
            if band.from > lo then
                parts[#parts + 1] = "Stacks " .. span(lo, band.from - 1) .. ": "
                    .. ((k == 1) and "fill color" or ("Color " .. tostring(bands[k - 1].n)))
            end
            lo = band.from
        end
        parts[#parts + 1] = "Stacks " .. span(lo, M) .. ": Color " .. tostring(bands[#bands].n)
    else
        parts[#parts + 1] = "Fill color below " .. bands[1].from .. " stacks"
        for _, band in ipairs(bands) do
            parts[#parts + 1] = "Color " .. tostring(band.n) .. " from " .. band.from .. " stacks"
        end
    end
    if Store.Resolve(rec, "stackcolors", "maxColorEnabled") == true then
        parts[#parts + 1] = "Max stacks color at " .. M
    end
    return table.concat(parts, "  |  ")
end

function Options.DetectMaxStacks(spellID)
    local sid = tonumber(spellID)
    if not sid or sid <= 0 then return nil end
    local f = NS.Bars and NS.Bars.ClientMaxStacks
    return f and f(sid) or nil
end

-- Enum.PowerType values for the stack-bar driver
local POWER_TYPES = {
    { value = 0, text = "Mana" }, { value = 1, text = "Rage" },
    { value = 2, text = "Focus" }, { value = 3, text = "Energy" },
    { value = 4, text = "Combo Points" }, { value = 5, text = "Runes" },
    { value = 6, text = "Runic Power" }, { value = 7, text = "Soul Shards" },
    { value = 8, text = "Astral Power" }, { value = 9, text = "Holy Power" },
    { value = 11, text = "Maelstrom" }, { value = 12, text = "Chi" },
    { value = 13, text = "Insanity" }, { value = 16, text = "Arcane Charges" },
    { value = 17, text = "Fury" }, { value = 18, text = "Pain" },
    { value = 19, text = "Essence" },
}
local function PowerLabel(v)
    for _, it in ipairs(POWER_TYPES) do
        if it.value == v then return it.text end
    end
    return "Power"
end

local RefreshAll   -- forward

-- Small widgets

local function KindPill(parent)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetHeight(14)
    AT.Skin(p, COL.bg, COL.line2)
    p.fs = p:CreateFontString(nil, "OVERLAY")
    p.fs:SetFont(STANDARD_TEXT_FONT, 8, "")
    p.fs:SetPoint("CENTER", 0, 0)
    function p:Set(text, color)
        self.fs:SetText(text)
        local c = color or COL.dim
        self.fs:SetTextColor(c[1], c[2], c[3])
        self:SetBackdropBorderColor(c[1], c[2], c[3], 0.7)
        self:SetWidth((self.fs:GetStringWidth() or 20) + 12)
    end
    return p
end

local function GroupPill(pill, groupKind)
    if groupKind == "aura" then pill:Set("Aura Group", PURPLE)
    else pill:Set("CD Group", YELLOW) end
end

local function BarPillText(barKind, barMode)
    local mode = (barMode == "stack") and "Stack" or "Duration"
    if barKind == "aura" then return "Aura " .. mode, PURPLE end
    if barKind == "timer" then return "Timer Bar", COL.arc end
    if barKind == "stack" then return "Stack Bar", GREENC end
    if barKind == "swing" then return "Swing Bar", { 0.95, 0.62, 0.30 } end
    if barKind == "resource" then return "Resource", { 0.36, 0.62, 1 } end
    if barKind == "health" then return "Health", { 0.35, 0.85, 0.45 } end
    if barKind == "cast" then return "Castbar", { 0.95, 0.47, 0.72 } end
    return "CD " .. mode, YELLOW
end

-- A family keeps its colour across icons, bars and groups (CD yellow, aura
-- purple, timer cyan); the icon-only kinds take hues nothing else uses.
Options.ICON_PILL_COLORS = {
    item    = { 0.36, 0.85, 0.76 },   -- teal
    trinket = { 0.95, 0.50, 0.74 },   -- rose
    totem   = { 0.70, 0.88, 0.36 },   -- lime
    ammo    = { 0.95, 0.52, 0.45 },   -- coral
}
Options.ICON_PILL_WORDS = { spell = "CD Icon", aura = "Aura Icon", timer = "Timer Icon",
    item = "Item Icon", trinket = "Trinket Icon", totem = "Totem Icon", ammo = "Ammo Icon" }
function Options.IconPillText(kind)
    local text = Options.ICON_PILL_WORDS[kind]
    if not text then return "Icon", COL.dim end
    if kind == "spell" then return text, YELLOW end
    if kind == "aura" then return text, PURPLE end
    if kind == "timer" then return text, COL.arc end
    return text, Options.ICON_PILL_COLORS[kind]
end

-- Records keep any unit the schema allows (Schema.HEALTH_UNITS), so a bar from
-- another client is never rewritten; only the picker filters by this client.
Options.HEALTH_UNIT_LABELS = {
    player = "Player (you)", target = "Target", focus = "Focus", pet = "Pet",
    party1 = "Party member 1", party2 = "Party member 2",
    party3 = "Party member 3", party4 = "Party member 4",
}
function Options.HealthUnitLabel(u)
    return Options.HEALTH_UNIT_LABELS[u or "player"] or tostring(u)
end
function Options.HealthUnitItems()
    -- A focus unit exists only where the client has PLAYER_FOCUS_CHANGED.
    local hasFocus = not (C_EventUtils and C_EventUtils.IsEventValid)
        or C_EventUtils.IsEventValid("PLAYER_FOCUS_CHANGED")
    local items = {}
    for _, u in ipairs(Schema.HEALTH_UNITS or { "player" }) do
        if u ~= "focus" or hasFocus then
            items[#items + 1] = { value = u, text = Options.HealthUnitLabel(u) }
        end
    end
    return items
end

function Options.CastUnitItems()
    local hasFocus = not (C_EventUtils and C_EventUtils.IsEventValid)
        or C_EventUtils.IsEventValid("PLAYER_FOCUS_CHANGED")
    local items = {}
    for _, u in ipairs(Schema.CAST_UNITS or { "player" }) do
        if u ~= "focus" or hasFocus then
            items[#items + 1] = { value = u, text = Options.HealthUnitLabel(u) }
        end
    end
    return items
end

-- One aura icon is one unit, one aura type and any number of spell IDs on a
-- single engine button. Debuffs on you, your pet or a party member need every
-- tracked ID to be never secret: the spell-ID filter does not reach a friendly
-- unit's debuffs (Forever shows nothing, retail 12.1.0 the unfiltered aura).
Options.AURA_UNIT_ORDER = { "player", "target", "focus", "pet",
    "party1", "party2", "party3", "party4" }
function Options.AuraUnitAllowed(d, unit, auraType)
    local t = auraType or ((d and d.auraType == "debuff") and "debuff" or "buff")
    if unit == "focus" and C_EventUtils and C_EventUtils.IsEventValid
        and not C_EventUtils.IsEventValid("PLAYER_FOCUS_CHANGED") then
        return false
    end
    if t ~= "debuff" or unit == "target" or unit == "focus" then return true end
    return NS.DriverAura ~= nil and NS.DriverAura.IDsNeverSecret(d)
end
-- keep: the current unit, listed even when no longer allowed.
function Options.AuraUnitItems(d, auraType, keep)
    local items = {}
    for _, u in ipairs(Options.AURA_UNIT_ORDER) do
        if u == keep or Options.AuraUnitAllowed(d, u, auraType) then
            items[#items + 1] = { value = u, text = Options.HealthUnitLabel(u) }
        end
    end
    return items
end
Options.AURA_CASTER_ITEMS = {
    { value = "any", text = "Anyone" },
    { value = "mine", text = "Me (or my pet)" },
    { value = "others", text = "Anyone but me" },
}
-- "2825, 32182 80353" -> { 2825, 32182, 80353 }: every number, in order, once
function Options.ParseSpellIDs(text)
    local out, seen = {}, {}
    for n in tostring(text or ""):gmatch("%d+") do
        local v = tonumber(n)
        if v and v > 0 and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    return out
end
-- A one-ID icon keeps the plain shape: spellIDs is set only for two or more.
function Options.SetAuraSpellIDs(d, ids)
    d.spellID = ids[1]
    d.spellIDs = (#ids > 1) and ids or nil
end
-- The aura on a spell icon: an aura driver shape on rec.driver.overlay plus
-- `on`, kept while off so switching back on restores it. The first switch-on
-- guesses: the spell's own ID (a classic buff carries its spell's ID) plus the
-- rank you know, a debuff on your target if the spell is harmful, else a buff.
function Options.OverlayOf(rec)
    return rec and rec.driver and rec.driver.overlay or nil
end
function Options.SetOverlayOn(rec, on)
    if not (rec and rec.driver) then return end
    local ov = rec.driver.overlay
    if on then
        if type(ov) ~= "table" then
            local sid = tonumber(rec.driver.spellID)
            local ids = {}
            if sid then ids[1] = sid end
            local nm = sid and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
            if NS.IsForever == true and type(nm) == "string" and nm ~= ""
                and not (issecretvalue and issecretvalue(nm)) and C_Spell.GetSpellIDForSpellIdentifier then
                local cur = C_Spell.GetSpellIDForSpellIdentifier(nm)
                if type(cur) == "number" and not (issecretvalue and issecretvalue(cur)) and cur ~= sid then
                    ids[#ids + 1] = cur
                end
            end
            local harmful = sid and C_Spell.IsSpellHarmful and C_Spell.IsSpellHarmful(sid)
            if issecretvalue and issecretvalue(harmful) then harmful = false end
            ov = {
                auraType = (harmful == true) and "debuff" or "buff",
                unit = (harmful == true) and "target" or "player",
                caster = "mine",
            }
            Options.SetAuraSpellIDs(ov, ids)
            rec.driver.overlay = ov
        end
        ov.on = true
    elseif type(ov) == "table" then
        ov.on = nil
    end
    Store.Dirty("style", rec.id)
end

-- The rail's words for an aura icon's IDs: "aura 2825" or "auras 2825 +3".
function Options.AuraSummary(d)
    local ids = NS.DriverAura and NS.DriverAura.SpellIDList(d) or {}
    if #ids > 1 then return "auras " .. ids[1] .. " +" .. (#ids - 1) end
    return "aura " .. tostring(ids[1] or "?")
end
-- True when an aura group's play-mode rows carry this lane.
function Options.AuraLaneInGroupRows(d)
    local unit, harmful = NS.DriverAura.ShapeOf(d)
    if harmful then return unit == "target" end
    return unit == "player" or unit == "pet"
end

-- nil follows the player's live display power. The picker uses -1 for
-- automatic because 0 is Mana; PowerValue maps it back to nil.
local POWER_AUTO = -1
local function PowerValue(v)
    v = tonumber(v)
    if not v or v < 0 then return nil end
    return v
end
local function PowerItems()
    local items = { { value = POWER_AUTO, text = "Automatic (current power)" } }
    local info = NS.Bars and NS.Bars.POWER_INFO
    if info then
        local ids = {}
        for id in pairs(info) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            items[#items + 1] = { value = id, text = info[id].name or ("Power " .. id) }
        end
    end
    return items
end

local function BarPill(pill, barKind, barMode)
    local text, color = BarPillText(barKind, barMode)
    pill:Set(text, color)
end

local function IconButton(parent, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size, size)
    AT.Skin(b, COL.well, COL.line)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    function b:SetSelected(on)
        if on then b:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        else b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end
    end
    return b
end

local function HeaderChip(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetHeight(16)
    AT.Skin(c, COL.bg, COL.line2)
    c.fs = c:CreateFontString(nil, "OVERLAY")
    c.fs:SetFont(STANDARD_TEXT_FONT, 9, "")
    c.fs:SetPoint("CENTER")
    function c:Set(text, color)
        self.fs:SetText(text)
        local col = color or COL.dim
        self.fs:SetTextColor(col[1], col[2], col[3])
        self:SetBackdropBorderColor(col[1], col[2], col[3], 0.7)
        self:SetWidth((self.fs:GetStringWidth() or 20) + 14)
        self:Show()
    end
    return c
end

-- The Copy to list for a record's sub-panel. Keys: all = everything of this
-- type, l<id> = one layout's records of this family, g<id> = one group's icons,
-- r<id> = one record, kind = every record of this kind.
function Options.PushTargets(rec, section)
    local items = { { value = 0, text = "Choose where to copy..." } }
    if not rec then return items end
    local fam = Store.FamilyOf(rec)
    local word = ({ icon = "icons", iconGroup = "groups", bar = "bars", layout = "layouts" })[fam] or "things"
    items[#items + 1] = { value = "all", text = "All " .. word .. " everywhere" }
    for _, lay in ipairs(Store.Layouts()) do
        local groups, _, bars = Store.ChildrenOf(lay)
        if fam == "icon" then
            items[#items + 1] = { value = "l" .. lay.id, text = "All icons in " .. lay.name }
            for _, g in ipairs(groups) do
                items[#items + 1] = { value = "g" .. g.id,
                    text = "Icons in " .. lay.name .. " / " .. g.name .. (g.id == rec.groupId and " (this group)" or "") }
            end
        elseif fam == "iconGroup" then
            items[#items + 1] = { value = "l" .. lay.id, text = "All groups in " .. lay.name }
            for _, g in ipairs(groups) do
                if g.id ~= rec.id then
                    items[#items + 1] = { value = "r" .. g.id, text = lay.name .. " / " .. g.name }
                end
            end
        elseif fam == "bar" then
            items[#items + 1] = { value = "l" .. lay.id, text = "All bars in " .. lay.name }
            for _, b in ipairs(bars) do
                if b.id ~= rec.id then
                    items[#items + 1] = { value = "r" .. b.id, text = lay.name .. " / " .. b.name }
                end
            end
        elseif fam == "layout" then
            if lay.id ~= rec.id then
                items[#items + 1] = { value = "r" .. lay.id, text = lay.name }
            end
        end
    end
    if fam == "icon" then
        items[#items + 1] = { value = "kind", text = "All " .. tostring(rec.kind) .. " icons" }
    end
    return items
end

function Options.PushTargetIds(rec, key)
    local ids = {}
    if type(key) ~= "string" then return ids end
    local fam = Store.FamilyOf(rec)
    local tag, id = key:sub(1, 1), tonumber(key:sub(2))
    if key == "kind" then
        Store.EachRecord(function(rid, r)
            if r.type == rec.type and Store.KindOf(r) == Store.KindOf(rec) then ids[#ids + 1] = rid end
        end)
    elseif tag == "r" and id then
        ids[1] = id
    elseif tag == "g" and id then
        local g = Store.Get(id)
        for _, ic in ipairs(g and Store.IconsOf(g) or {}) do ids[#ids + 1] = ic.id end
    elseif tag == "l" and id then
        local lay = Store.Get(id)
        if lay then
            local groups, freeIcons, bars = Store.ChildrenOf(lay)
            if fam == "icon" then
                for _, ic in ipairs(freeIcons) do ids[#ids + 1] = ic.id end
                for _, g in ipairs(groups) do
                    for _, ic in ipairs(Store.IconsOf(g)) do ids[#ids + 1] = ic.id end
                end
            elseif fam == "iconGroup" then
                for _, g in ipairs(groups) do ids[#ids + 1] = g.id end
            elseif fam == "bar" then
                for _, b in ipairs(bars) do ids[#ids + 1] = b.id end
            end
        end
    end
    return ids
end

-- Block field lists by vis function; a PushBar given that vis scopes to them.
Options.blockFields = Options.blockFields or {}

-- A line at the end of a block, above its Copy to: "From layout X" while its
-- rows follow the layout, "Changed here" with Reset to layout once the item sets
-- its own, hidden while the layout sets none. fieldsFn(): the rows, nil = section.
function Options.LayoutStatusRow(pg, ctx, section, visibleFn, fieldsFn)
    local function Status()
        local r = ctx()
        if not r then return nil, 0, 0 end
        return Store.LayoutStatus(r, section, fieldsFn())
    end
    local row = AT.AddRow(pg, 24, function()
        if visibleFn and not visibleFn() then return false end
        local _, setN = Status()
        return setN > 0
    end)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    local btn = AT.MakeQuietButton(row, "Reset to layout", 112)
    btn:SetPoint("RIGHT", -12, 0)
    row._adText, row._adButton = fs, btn
    row._sync = function()
        local lay, setN, ownN = Status()
        if not lay or setN == 0 then return end
        local name = lay.name or "?"
        if ownN > 0 then
            fs:SetText("Changed here: " .. ownN .. (ownN == 1 and " setting differs" or " settings differ")
                .. " from the layout " .. name .. ".")
            fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            fs:SetPoint("RIGHT", btn, "LEFT", -8, 0)
            btn:Show()
        else
            fs:SetText("From layout " .. name .. ": "
                .. (setN == 1 and "1 setting here follows it." or (setN .. " settings here follow it.")))
            fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
            fs:SetPoint("RIGHT", -12, 0)
            btn:Hide()
        end
    end
    btn:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r = ctx()
        if r and Store.ResetToLayout(r, section, fieldsFn()) then AT.LayoutPage(pg) end
    end)
    AT.Tooltip(btn, "Reset to layout", "Drops this item's own values for the settings here that its layout sets, so they follow the layout again. Settings the layout leaves alone keep this item's values.")
    return row
end

-- Copy and default controls scoped to one sub-panel's rows: two blocks can
-- share a schema section, and a copy must not carry the neighbour's rows.
-- `fields`: a list or a function returning one; nil means
-- blockFields[visibleFn], else the whole section.
local function PushBar(pg, ctx, section, visibleFn, fields)
    local function FieldsNow()
        if type(fields) == "function" then return fields() end
        if fields then return fields end
        return Options.blockFields[visibleFn]
    end
    local function flash(btn, text)
        btn._label = btn._label or btn.fs:GetText()
        btn.fs:SetText(text)
        C_Timer.After(1.2, function() btn.fs:SetText(btn._label) end)
    end
    Options.LayoutStatusRow(pg, ctx, section, visibleFn, FieldsNow)
    -- The pick resets when another record is selected, so a stale target never
    -- gets a copy. w = nil: an auto-width dropdown (up to 300).
    local row = AT.AddRow(pg, 24, visibleFn)
    local lbl = AT.RowLabel(row, "Copy to")
    local sel, selRec = 0, nil
    local function Sel()
        local rec = ctx()
        local id = rec and rec.id
        if id ~= selRec then sel, selRec = 0, id end
        return sel
    end
    local dd = AT.MakeDropdown(win, row, nil,
        function() return Options.PushTargets(ctx(), section) end,
        Sel,
        function(v) Sel() sel = v end)
    dd:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    row._sync = dd.Refresh
    local copy = AT.MakeSmallButton(row, "Copy", 70)
    copy:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    copy:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        local v = Sel()
        if v == 0 then flash(copy, "Pick one") return end
        local n
        if v == "all" then
            n = Store.PushToAll(rec, section, FieldsNow())
        else
            n = Store.PushTo(rec, section, Options.PushTargetIds(rec, v), FieldsNow())
        end
        flash(copy, "Copied: " .. tostring(n or 0))
    end)
    AT.Tooltip(dd, "Copy to", "Where the rows of this sub-panel go: everything of this type, one layout, one group, one other thing, or every icon of this kind. Nothing happens until you press Copy.")
    AT.Tooltip(copy, "Copy", "Copies the rows of this sub-panel onto the chosen target. Copy semantics - no live link; the target keeps its own values from then on.")
    local row2 = AT.AddRow(pg, 24, visibleFn)
    local b2 = AT.MakeSmallButton(row2, "Save as Default", 112)
    b2:SetPoint("LEFT", 10, 0)
    local b3 = AT.MakeQuietButton(row2, "Reset", 60)
    b3:SetPoint("LEFT", b2, "RIGHT", 6, 0)
    local b4 = AT.MakeQuietButton(row2, "Forget default", 104)
    b4:SetPoint("LEFT", b3, "RIGHT", 6, 0)
    local function HasDefault()
        local rec = ctx()
        return rec ~= nil and Store.HasDefault(rec, section, FieldsNow()) == true
    end
    row2._sync = function() b4:SetShown(HasDefault()) end
    b2:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        Store.SaveAsDefault(rec, section, FieldsNow())
        flash(b2, "Saved")
        b4:Show()
    end)
    b3:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        Store.ResetSection(rec, section, FieldsNow())
        flash(b3, "Done")
        AT.LayoutPage(pg)
    end)
    b4:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        Store.ForgetDefault(rec, section, FieldsNow())
        flash(b4, "Forgotten")
        C_Timer.After(1.2, function() b4:SetShown(HasDefault()) end)
    end)
    AT.Tooltip(b2, "Save as Default", "New creations of this kind are born with the rows of this sub-panel as they are now.")
    AT.Tooltip(b3, "Reset", "Puts the rows of this sub-panel back: to the layout's values where its layout sets them, to the defaults for this thing everywhere else (a saved default still counts).")
    AT.Tooltip(b4, "Forget default", "Drops the saved default for these rows; new creations go back to the factory values.")
    return row
end

-- Stored by sound name ("" = none), never a file ID.
function Options.SoundRow(pg, owner, label, section, field, ctx, visible)
    local function get()
        local r = ctx()
        local v = r and Store.Resolve(r, section, field)
        return type(v) == "string" and v or ""
    end
    local row = AT.RowDropdown(pg, owner, label, get,
        function(v)
            local r = ctx()
            if r then Store.SetOverride(r, section, field, type(v) == "string" and v or "") end
        end,
        function()
            if NS.Sounds then return NS.Sounds.Items() end
            return { { value = "", text = "None" } }
        end,
        visible)
    local play = AT.MakeSmallButton(row, "Play", 52)
    play:SetPoint("LEFT", row._colCtrl, "RIGHT", 6, 0)
    play:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r = ctx()
        if not (r and NS.Sounds) then return end
        NS.Sounds.Preview(get(), Store.Resolve(r, section, "soundChannel"))
    end)
    AT.Tooltip(play, "Play", "Hear the chosen sound once, on this icon's sound channel.")
    return row
end

-- The game's faces, then LibSharedMedia fonts A-Z; "Default" stands for "".
function Options.FontItems()
    local items, seen = {}, {}
    local builtin = NS.Bars and NS.Bars.BUILTIN_FONT_ORDER or { "Default" }
    for _, k in ipairs(builtin) do
        items[#items + 1] = { value = k, text = k }
        seen[k] = true
    end
    local lsm = NS.Bars and NS.Bars.GetLSM and NS.Bars.GetLSM()
    if lsm then
        local extra = {}
        for _, name in ipairs(lsm:List("font") or {}) do
            if not seen[name] then extra[#extra + 1] = name end
        end
        table.sort(extra)
        for _, name in ipairs(extra) do
            items[#items + 1] = { value = name, text = name }
        end
    end
    return items
end

-- Textures or borders for the layout editor's bar looks: `empty` (what "" means
-- for the field; MEDIA_EMPTY, else "Flat") first, then built-ins, then LSM A-Z.
Options.MEDIA_EMPTY = { bgTexture = "Same as fill" }
function Options.MediaItems(kind, empty)
    local items, seen = {}, {}
    local function add(k)
        if k and not seen[k] then
            seen[k] = true
            items[#items + 1] = { value = k, text = k }
        end
    end
    add(empty)
    add("Flat")
    if kind == "border" then
        for _, k in ipairs((NS.Bars and NS.Bars.BUILTIN_BORDER_ORDER) or {}) do add(k) end
    else
        for _, k in ipairs({ "Blizzard", "Blizzard Raid", "Character Skills" }) do add(k) end
    end
    local lsm = NS.Bars and NS.Bars.GetLSM and NS.Bars.GetLSM()
    if lsm then
        local extra = {}
        for _, name in ipairs(lsm:List(kind) or {}) do
            if not seen[name] and name ~= "None" then extra[#extra + 1] = name end
        end
        table.sort(extra)
        for _, name in ipairs(extra) do add(name) end
    end
    return items
end

-- Look registry: each item-editor block registers its tab, title, section and
-- rows as it is built; BuildLayoutLooks mirrors them into the layout editor.
-- The same family, tab, title and section again merges the rows. Fields are
-- copied, so later changes to the caller's list do not leak in.
Options.LOOK_BLOCKS = Options.LOOK_BLOCKS or {}
Options.blockTab = Options.blockTab or {}   -- a BarBlock's vis -> its tab (BarSub)
function Options.LookBlock(family, tab, title, section, fields)
    if not (family and tab and title and section and fields) then return end
    local list = Options.LOOK_BLOCKS[family] or {}
    Options.LOOK_BLOCKS[family] = list
    local b
    for _, x in ipairs(list) do
        if x.tab == tab and x.title == title and x.section == section then b = x break end
    end
    if not b then
        b = { tab = tab, title = title, section = section, fields = {} }
        list[#list + 1] = b
    end
    for _, fld in ipairs(fields) do b.fields[#b.fields + 1] = fld end
    return b
end

-- Schema rows for one section, bound to ctx(). `only`: the fields to render, in
-- that order (nil = every non-hidden field by label). opts.layoutTier: the rows
-- edit a layout (Store.LayoutProxy): every inheriting field shows, deps on
-- non-inheriting fields never hide a row, and the group-member gates are off.
local function SectionRows(pg, family, section, ctx, tabVisible, only, opts)
    local tier = opts and opts.layoutTier == true
    local fam = Schema[family]
    local sec = fam[section]
    local keys = {}
    if only then
        for _, k in ipairs(only) do
            if sec.fields[k] then keys[#keys + 1] = k end
        end
    else
        -- Hidden fields get bespoke rows (the bar anchor's group dropdown).
        for k, d in pairs(sec.fields) do
            if not d.hidden then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            return (sec.fields[a].label or a) < (sec.fields[b].label or b)
        end)
    end
    -- def.dep hides a field until the named fields hold the wanted values.
    local function DepOK(rec, d)
        -- Layout tier: an item-only switch never hides the layout's rows.
        if tier then
            local dsec = fam[d.section or section]
            local ddef = dsec and dsec.fields[d.field]
            if not (ddef and Schema.Inherits(ddef, dsec)) then return true end
        end
        -- unlessFree: a free icon has no group scale, so its size rows show.
        if d.unlessFree and not rec.groupId then return true end
        local v = Store.Resolve(rec, d.section or section, d.field)
        if d.nonempty then return v ~= nil and v ~= "" end
        if d.notValue ~= nil then return v ~= d.notValue end
        if d.min ~= nil then return type(v) == "number" and v >= d.min end
        if d.anyOf ~= nil then return v ~= nil and d.anyOf[v] == true end
        local want = d.value
        if want == nil then want = true end
        if type(want) == "boolean" then return (v == true) == want end
        return v == want
    end
    for _, field in ipairs(keys) do
        local def = sec.fields[field]
        -- Every gate but the dep: the settings search reads this, so it still
        -- finds a row a dep hides.
        local baseVis = function()
            if not tabVisible() then return false end
            local rec = ctx()
            if not rec then return false end
            if tier then
                -- a layout shows exactly the rows it can set, for any kind
                if not Schema.Inherits(def, sec) then return false end
            elseif not Schema.Applies(def, sec, Store.KindOf(rec), rec.barMode) then
                return false
            end
            if def.classOnly and def.classOnly ~= Store.ClassTag() then return false end
            if def.foreverOnly and NS.IsForever ~= true then return false end
            if def.groupOnly and not rec.groupId and not tier then return false end
            return true
        end
        local visible = function()
            if not baseVis() then return false end
            local rec = ctx()
            local dep = def.dep
            if dep then
                if dep.field then
                    if not DepOK(rec, dep) then return false end
                else
                    for _, d in ipairs(dep) do
                        if not DepOK(rec, d) then return false end
                    end
                end
            end
            return true
        end
        local label = def.label or field
        local row
        if def.t == "bool" then
            row = AT.RowToggle(pg, label,
                function() local r = ctx() return r and Store.Resolve(r, section, field) == true end,
                function(v)
                    local r = ctx()
                    if r then
                        Store.SetOverride(r, section, field, v)
                        if def.onSet then def.onSet(r, v) end
                    end
                end,
                visible)
        elseif def.t == "num" or def.t == "int" then
            -- def.minFn / maxFn (record -> number) give live slider bounds.
            local isInt = def.t == "int"
            local lo = def.minFn and function()
                local r = ctx()
                return (r and def.minFn(r)) or def.min or 0
            end or (def.min or 0)
            local hi = def.maxFn and function()
                local r = ctx()
                return (r and def.maxFn(r)) or def.max or (isInt and 100 or 1)
            end or (def.max or (isInt and 100 or 1))
            row = AT.RowSlider(pg, label,
                function() local r = ctx() return r and Store.Resolve(r, section, field) or def.d or 0 end,
                function(v) local r = ctx() if r then Store.SetOverride(r, section, field, v) end end,
                -- def.fmt: a display format for units a 0..1 range would
                -- otherwise show as a percent (seconds: "0.18", not "18")
                lo, hi, isInt and 1 or (def.step or 0.01),
                (not isInt) and (def.fmt or ((def.max or 1) <= 1)) or false, visible)
        elseif def.t == "enum" then
            row = AT.RowDropdown(pg, win, label,
                function() local r = ctx() return r and Store.Resolve(r, section, field) end,
                function(v)
                    local r = ctx()
                    if r then
                        Store.SetOverride(r, section, field, v)
                        if def.onSet then def.onSet(r, v) end
                    end
                end,
                function()
                    local items = {}
                    local L = def.labels
                    local rv = ctx()
                    for _, v in ipairs(def.values or {}) do
                        local cond = def.valueIf and def.valueIf[v]
                        if not cond or (rv ~= nil and cond(rv)) then
                            items[#items + 1] = { value = v, text = (L and L[v]) or v }
                        end
                    end
                    return items
                end,
                visible)
        elseif def.t == "id" then
            row = AT.RowInput(pg, label,
                function()
                    local r = ctx()
                    local val = r and Store.Resolve(r, section, field)
                    return (val and val ~= 0) and tostring(val) or ""
                end,
                function(v)
                    local r = ctx()
                    if r then Store.SetOverride(r, section, field, tonumber(v) or 0) end
                end,
                visible, "Numeric ID. Empty = default art.")
        elseif def.t == "text" and def.media then
            local empty = Options.MEDIA_EMPTY[field] or "Flat"
            row = AT.RowDropdown(pg, win, label,
                function()
                    local r = ctx()
                    local v = r and Store.Resolve(r, section, field)
                    return (v == nil or v == "") and empty or v
                end,
                function(v)
                    local r = ctx()
                    if r then Store.SetOverride(r, section, field, (v == empty) and "" or v) end
                end,
                function() return Options.MediaItems(def.media, empty) end, visible)
        elseif def.t == "text" and def.font then
            row = AT.RowDropdown(pg, win, label,
                function()
                    local r = ctx()
                    local v = r and Store.Resolve(r, section, field)
                    return (v == nil or v == "") and "Default" or v
                end,
                function(v)
                    local r = ctx()
                    if r then Store.SetOverride(r, section, field, (v == "Default") and "" or v) end
                end,
                Options.FontItems, visible)
        elseif def.t == "text" then
            row = AT.RowInput(pg, label,
                function()
                    local r = ctx()
                    local val = r and Store.Resolve(r, section, field)
                    return val and tostring(val) or ""
                end,
                function(v)
                    local r = ctx()
                    if r then Store.SetOverride(r, section, field, tostring(v or "")) end
                end,
                -- def.desc: the tooltip. def.hintFn(rec): what an empty field
                -- stands for, shown inside it.
                visible, def.desc or "Free text. Empty = none.",
                def.hintFn and function()
                    local r = ctx()
                    return (r and def.hintFn(r)) or ""
                end or def.hint)
        elseif def.t == "sound" then
            row = Options.SoundRow(pg, win, label, section, field, ctx, visible)
        elseif def.t == "color" then
            row = AT.RowColor(pg, label,
                function()
                    local r = ctx()
                    local c = r and Store.Resolve(r, section, field) or def.d
                    return { c[1] or 0, c[2] or 0, c[3] or 0 }
                end,
                function(c)
                    local r = ctx()
                    if not r then return end
                    -- The picker has no opacity: keep the field's alpha, or a
                    -- translucent default (the 80% swipe) goes opaque.
                    local cur = Store.Resolve(r, section, field)
                    local a = (type(cur) == "table" and cur[4])
                        or (type(def.d) == "table" and def.d[4]) or 1
                    Store.SetOverride(r, section, field, { c[1], c[2], c[3], a })
                end,
                visible)
        end
        -- Search metadata: the search indexes by baseVis, so a dep-hidden row
        -- (Gradient colors) is still found and the jump flashes its switch.
        if row then
            row._adMeta = { family = family, section = section, field = field,
                def = def, baseVis = baseVis, layoutTier = tier or nil }
        end
    end
end

-- Talent tree picker: the real tree, drawn as Blizzard draws it (each node at
-- posX/10, posY/10, the whole tree scaled once to fit). The catalog drops the
-- nodes whose 10x coordinates would stretch the bounds tenfold. A click adds or
-- drops a node as a load condition on the record being edited.

local tpWin, tpCanvas, tpCtx, tpSearch, tpCount, tpEmpty, tpLineHost
local tpQuery = ""
local tpNodes, tpLines, tpPanels = {}, {}, {}
local TP_PAD, TP_HDR, TP_ICON = 12, 24, 42
local TPPaint, TPLayout

local function TPRecord() return tpCtx and tpCtx() end

TPPaint = function()
    if not (tpWin and tpWin:IsShown()) then return end
    local rec = TPRecord()
    local chosen = (rec and rec.c.talents) or {}
    local q = tpQuery:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local n = 0
    for _ in pairs(chosen) do n = n + 1 end
    tpCount:SetText(n == 0 and "Nothing required yet - click a talent to add it."
        or (n == 1 and "1 talent required" or (n .. " talents required")))
    for _, node in ipairs(tpNodes) do
        local e = node.entry
        if e and node.btn:IsShown() then
            local sel = chosen[e.nodeID] == true
            local taken = (e.rank or 0) > 0
            local hit = (q == "") or (e.nameLower:find(q, 1, true) ~= nil)
            local bc = sel and COL.arc or (taken and COL.line2 or COL.line)
            node.ring:SetShown(sel)
            node.ic:SetDesaturated(not taken)
            node.btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
            node.btn:SetAlpha(hit and (taken and 1 or 0.55) or 0.15)
            node.ring:SetAlpha(hit and 1 or 0.15)
        end
    end
end

local function TPPanel(i)
    local p = tpPanels[i]
    if p then return p end
    local box = CreateFrame("Frame", nil, tpCanvas, "BackdropTemplate")
    AT.Skin(box, COL.box or COL.well, COL.line)
    box:SetFrameLevel(tpCanvas:GetFrameLevel() + 1)
    local bar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TP_HDR)
    AT.Skin(bar, COL.panel, COL.panel)
    local rule = bar:CreateTexture(nil, "OVERLAY")
    rule:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.9)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
    local name = bar:CreateFontString(nil, "OVERLAY")
    name:SetFont(STANDARD_TEXT_FONT, 12, "")
    name:SetPoint("LEFT", 8, 0)
    name:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    local pts = bar:CreateFontString(nil, "OVERLAY")
    pts:SetFont(STANDARD_TEXT_FONT, 11, "")
    pts:SetPoint("RIGHT", -8, 0)
    pts:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])

    -- Blizzard's four-quadrant talent art, anchored to refit at any panel size.
    local body = CreateFrame("Frame", nil, box)
    body:SetPoint("TOPLEFT", 1, -(TP_HDR + 1))
    body:SetPoint("BOTTOMRIGHT", -1, 1)
    body:SetClipsChildren(true)
    local bg = {}
    for qi = 1, 4 do
        local t = body:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetVertexColor(0.82, 0.88, 1, 0.34)
        bg[qi] = t
    end
    bg[1]:SetPoint("TOPLEFT", body, "TOPLEFT")
    bg[1]:SetPoint("BOTTOMRIGHT", body, "CENTER")
    bg[2]:SetPoint("TOPRIGHT", body, "TOPRIGHT")
    bg[2]:SetPoint("BOTTOMLEFT", body, "CENTER")
    bg[3]:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT")
    bg[3]:SetPoint("TOPRIGHT", body, "CENTER")
    bg[4]:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT")
    bg[4]:SetPoint("TOPLEFT", body, "CENTER")

    p = { box = box, name = name, pts = pts, body = body, bg = bg }
    tpPanels[i] = p
    return p
end

local TP_QUADS = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" }

local function TPNode(i)
    local node = tpNodes[i]
    if node then return node end
    local ring = CreateFrame("Frame", nil, tpCanvas, "BackdropTemplate")
    AT.Skin(ring, COL.arc, COL.arc)
    ring:SetFrameLevel(tpCanvas:GetFrameLevel() + 6)
    ring:Hide()
    local btn = CreateFrame("Button", nil, tpCanvas, "BackdropTemplate")
    AT.Skin(btn, COL.well, COL.line)
    btn:SetFrameLevel(ring:GetFrameLevel() + 1)
    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
    ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
    local ic = btn:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 2, -2)
    ic:SetPoint("BOTTOMRIGHT", -2, 2)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local rank = btn:CreateFontString(nil, "OVERLAY")
    rank:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    rank:SetPoint("BOTTOMRIGHT", -1, 1)
    rank:SetTextColor(0.95, 0.97, 1)
    node = { btn = btn, ring = ring, ic = ic, rank = rank }
    btn:SetScript("OnEnter", function()
        local e = node.entry
        if not e then return end
        btn:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name, 1, 1, 1)
        if e.maxRanks and e.maxRanks > 1 then
            GameTooltip:AddLine(("Rank %d of %d"):format(e.rank or 0, e.maxRanks),
                0.7, 0.78, 0.88)
        elseif (e.rank or 0) > 0 then
            GameTooltip:AddLine("Taken", 0.48, 0.85, 0.56)
        else
            GameTooltip:AddLine("Not taken", 0.95, 0.62, 0.30)
        end
        local rec = TPRecord()
        local on = rec and rec.c.talents and rec.c.talents[e.nodeID]
        GameTooltip:AddLine(on and "Click to stop requiring this talent."
            or "Click to require this talent.", 0.247, 0.788, 0.949)
        GameTooltip:AddLine("Node " .. e.nodeID, 0.4, 0.47, 0.57)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        TPPaint()      -- puts the state border back
    end)
    btn:SetScript("OnClick", function()
        local rec, e = TPRecord(), node.entry
        if not (rec and e) then return end
        Store.ToggleTalent(rec, e.nodeID)
        TPPaint()
        RefreshAll()
    end)
    tpNodes[i] = node
    return node
end

TPLayout = function()
    if not tpWin then return end
    local cat = NS.TalentCatalog
    local list, groups, bounds
    if cat then list, groups, bounds = cat.Layout() end
    list, groups = list or {}, groups or {}
    local have = #list > 0 and bounds ~= nil and bounds.minX ~= nil
    tpEmpty:SetShown(not have)
    if not have then
        for _, node in ipairs(tpNodes) do node.btn:Hide(); node.ring:Hide() end
        for _, ln in ipairs(tpLines) do ln:Hide() end
        for _, p in ipairs(tpPanels) do p.box:Hide() end
        tpCount:SetText("")
        return
    end
    local cw, ch = tpCanvas:GetWidth() or 0, tpCanvas:GetHeight() or 0
    if cw < 60 or ch < 60 then return end

    -- One scale for the whole tree: scaling each tree on its own would put
    -- the three out of step, and the data already separates them in X.
    local spanX = (bounds.maxX - bounds.minX) / 10
    local spanY = (bounds.maxY - bounds.minY) / 10
    local availW = cw - TP_PAD * 2
    local availH = ch - TP_PAD * 2 - TP_HDR
    local s = math.min(availW / (spanX + TP_ICON), availH / (spanY + TP_ICON))
    if s > 1.6 then s = 1.6 elseif s < 0.3 then s = 0.3 end
    local size = math.max(14, math.floor(TP_ICON * s + 0.5))
    local offX = TP_PAD + math.max(0, (availW - (spanX * s + size)) / 2)
    -- Centre the nodes vertically so leftover height is not a dead strip below.
    local bodyTop = TP_PAD + TP_HDR
    local bodyH = math.max(0, ch - TP_PAD - bodyTop)
    local offY = bodyTop + math.max(0, (bodyH - (spanY * s + size)) / 2)

    local gap = size * 0.45
    for i, g in ipairs(groups) do
        local p = TPPanel(i)
        if g.minX and g.maxX then
            local l = offX + (g.minX - bounds.minX) / 10 * s - gap
            local r = offX + size + (g.maxX - bounds.minX) / 10 * s + gap
            p.box:ClearAllPoints()
            p.box:SetPoint("TOPLEFT", tpCanvas, "TOPLEFT", l, -TP_PAD)
            p.box:SetPoint("BOTTOMRIGHT", tpCanvas, "TOPLEFT", r, -(ch - TP_PAD))
            p.name:SetText(string.upper(g.name or ""))
            p.pts:SetText((g.spent or 0) > 0 and ((g.spent) .. " points") or "")
            local base = g.background and ("Interface\\TalentFrame\\" .. g.background .. "-")
            for qi, quad in ipairs(TP_QUADS) do
                if base then
                    p.bg[qi]:SetTexture(base .. quad)
                    p.bg[qi]:Show()
                else
                    p.bg[qi]:Hide()
                end
            end
            p.box:Show()
        else
            p.box:Hide()
        end
    end
    for i = #groups + 1, #tpPanels do tpPanels[i].box:Hide() end

    local byID = {}
    for i, e in ipairs(list) do
        local node = TPNode(i)
        node.entry = e
        node.btn:SetSize(size, size)
        node.btn:ClearAllPoints()
        node.btn:SetPoint("CENTER", tpCanvas, "TOPLEFT",
            offX + size / 2 + (e.posX - bounds.minX) / 10 * s,
            -(offY + size / 2 + (e.posY - bounds.minY) / 10 * s))
        node.ic:SetTexture(e.icon)
        node.rank:SetText((e.maxRanks and e.maxRanks > 1 and (e.rank or 0) > 0)
            and (e.rank .. "/" .. e.maxRanks) or "")
        node.rank:SetShown(size >= 26)
        node.btn:Show()
        byID[e.nodeID] = node
    end
    for i = #list + 1, #tpNodes do
        tpNodes[i].entry = nil
        tpNodes[i].btn:Hide()
        tpNodes[i].ring:Hide()
    end

    -- Connector lines, lit where both ends are taken. WoW Forever ships no edge
    -- data (visibleEdges is empty), so nothing draws there.
    local li = 0
    if tpLineHost.CreateLine then
        for _, e in ipairs(list) do
            local from = byID[e.nodeID]
            for _, target in ipairs(e.edges or {}) do
                local to = byID[target]
                if from and to then
                    li = li + 1
                    local ln = tpLines[li]
                    if not ln then
                        ln = tpLineHost:CreateLine(nil, "OVERLAY")
                        tpLines[li] = ln
                    end
                    ln:SetThickness(math.max(1, math.floor(s * 2)))
                    if (e.rank or 0) > 0 and (to.entry.rank or 0) > 0 then
                        ln:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.55)
                    else
                        ln:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 0.8)
                    end
                    ln:SetStartPoint("CENTER", from.btn)
                    ln:SetEndPoint("CENTER", to.btn)
                    ln:Show()
                end
            end
        end
    end
    for i = li + 1, #tpLines do tpLines[i]:Hide() end
    TPPaint()
end

local function TPBuild()
    if tpWin then return end
    -- The default size matches the tree's aspect, so the panels fill the window.
    tpWin = AT.CreateWindow("ArcUIv2TalentPicker", {
        w = 1020, h = 580, minW = 620, minH = 420, maxW = 1600, maxH = 1200,
        title = "|cff3fc9f2Arc|r|cffd5e2f2 Talents|r",
        onResize = function() TPLayout() end,
    })

    local body = CreateFrame("Frame", nil, tpWin)
    body:SetPoint("TOPLEFT", 8, -38)
    body:SetPoint("BOTTOMRIGHT", -8, 8)

    tpSearch = CreateFrame("EditBox", nil, body, "BackdropTemplate")
    tpSearch:SetSize(220, 20)
    tpSearch:SetPoint("TOPLEFT", 0, 0)
    AT.Skin(tpSearch, COL.well)
    tpSearch:SetFont(STANDARD_TEXT_FONT, 11, "")
    tpSearch:SetTextInsets(6, 6, 0, 0)
    tpSearch:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    tpSearch:SetAutoFocus(false)
    local hint = tpSearch:CreateFontString(nil, "OVERLAY")
    hint:SetFont(STANDARD_TEXT_FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("Search talents")
    tpSearch:SetScript("OnTextChanged", function(self)
        tpQuery = self:GetText() or ""
        hint:SetShown(tpQuery == "")
        TPPaint()
    end)
    tpSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    tpSearch:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    tpCount = body:CreateFontString(nil, "OVERLAY")
    tpCount:SetFont(STANDARD_TEXT_FONT, 11, "")
    tpCount:SetPoint("LEFT", tpSearch, "RIGHT", 12, 0)
    tpCount:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])

    local clear = AT.MakeSmallButton(body, "Clear all", 80)
    clear:SetPoint("TOPRIGHT", 0, 0)
    clear:SetHeight(20)
    clear:SetScript("OnClick", function()
        local rec = TPRecord()
        if not rec then return end
        Store.ClearTalents(rec)
        TPPaint()
        RefreshAll()
    end)
    AT.Tooltip(clear, "Clear all", "Drops every talent requirement from this one.")

    local done = AT.MakeSmallButton(body, "Done", 70)
    done:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    done:SetHeight(20)
    done.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    done:SetScript("OnClick", function() tpWin:Hide() end)

    tpCanvas = CreateFrame("Frame", nil, body, "BackdropTemplate")
    tpCanvas:SetPoint("TOPLEFT", 0, -28)
    tpCanvas:SetPoint("BOTTOMRIGHT", 0, 0)
    AT.Skin(tpCanvas, COL.panel, COL.line)
    tpCanvas:SetClipsChildren(true)

    -- connector lines live between the tree panels and the nodes
    tpLineHost = CreateFrame("Frame", nil, tpCanvas)
    tpLineHost:SetAllPoints()
    tpLineHost:SetFrameLevel(tpCanvas:GetFrameLevel() + 4)

    tpEmpty = tpCanvas:CreateFontString(nil, "OVERLAY")
    tpEmpty:SetFont(STANDARD_TEXT_FONT, 12, "")
    tpEmpty:SetPoint("CENTER", 0, 0)
    tpEmpty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    tpEmpty:SetText("No talent tree on this character yet.")
    tpEmpty:Hide()

    tpWin:HookScript("OnShow", function() TPLayout() end)
end

local function OpenTalentPicker(ctxFn)
    TPBuild()
    tpCtx = ctxFn
    tpQuery = ""
    tpSearch:SetText("")
    if NS.TalentCatalog then NS.TalentCatalog.Rescan() end
    tpWin:Show()
    TPLayout()
end

-- The picker edits one record, so it closes with the panel that chose it.
local function CloseTalentPicker()
    if tpWin and tpWin:IsShown() then tpWin:Hide() end
end

-- Condition rows (Core\AD_Conditions.lua), shared by the Load Conditions and
-- Visibility tabs: a checkbox grid per list, a summary line with Clear, and the
-- Match row. Three columns when every label fits, else two, so none truncates.

local COND_CELL_H, COND_HDR_H = 22, 16
local COND_COL_MIN = 170   -- box + the longest label (18 chars) + gutter

-- Shown in place of the condition sections while the conditions module is
-- not loaded; a new Lua file loads on /reload.
local COND_RESTART = "Type /reload once to turn these on."

local function CondGrid(pg, ctx, visible, list)
    local C = NS.Conditions
    for _, cat in ipairs(C.CATEGORIES) do
        local defs = {}
        for _, d in ipairs(C.VOCAB) do
            if d.cat == cat.id then defs[#defs + 1] = d end
        end
        local function offeredAny(r)
            for _, d in ipairs(defs) do
                if C.Offered(d, r, list) then return true end
            end
            return false
        end
        local row = AT.AddRow(pg, COND_HDR_H + COND_CELL_H, function()
            if not visible() then return false end
            local r = ctx()
            return r ~= nil and offeredAny(r)
        end)
        -- the settings search lists every condition this row offers the
        -- record (the checkboxes carry no row label of their own)
        row._adSearch = function()
            local r = ctx()
            local out = {}
            if not r then return out end
            for _, d in ipairs(defs) do
                if C.Offered(d, r, list) then out[#out + 1] = d.text end
            end
            return out
        end
        local hdr = row:CreateFontString(nil, "OVERLAY")
        hdr:SetFont(STANDARD_TEXT_FONT, 10, "")
        hdr:SetPoint("TOPLEFT", 6, -2)
        hdr:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        hdr:SetText(cat.text)
        local cells = {}
        for _, d in ipairs(defs) do
            local cell = CreateFrame("Frame", nil, row)
            cell:SetHeight(COND_CELL_H)
            local cb = AT.MakeCheckbox(cell)
            cb:SetPoint("LEFT", 0, 0)
            local fs = cell:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_TEXT_FONT, 11, "")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetText(d.text)
            fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            cb:SetScript("OnClick", function()
                local r = ctx()
                if r then C.Toggle(r, list, d.key) end
                AT.LayoutPage(pg)
                RefreshAll()
            end)
            cb:HookScript("OnEnter", function() cb:SetHover(true) end)
            cb:HookScript("OnLeave", function() cb:SetHover(false) end)
            cells[#cells + 1] = { f = cell, cb = cb, d = d }
        end
        -- measured placement; returns true when the row's height changed
        local function place()
            local r = ctx()
            if not r then return false end
            local w = row:GetWidth() or 0
            if w < 90 then w = (pg:GetWidth() or 0) - 24 end
            if w < 90 then return false end
            local ncol = math.max(2, math.min(3, math.floor(w / COND_COL_MIN)))
            local cw = math.floor(w / ncol)
            local i = 0
            for _, cell in ipairs(cells) do
                if C.Offered(cell.d, r, list) then
                    cell.f:ClearAllPoints()
                    cell.f:SetPoint("TOPLEFT", row, "TOPLEFT", (i % ncol) * cw + 6,
                        -(COND_HDR_H + math.floor(i / ncol) * COND_CELL_H))
                    cell.f:SetWidth(cw - 10)
                    cell.cb:SetOn(C.Has(r, list, cell.d.key))
                    cell.f:Show()
                    i = i + 1
                else
                    cell.f:Hide()
                end
            end
            local want = COND_HDR_H + math.max(1, math.ceil(i / ncol)) * COND_CELL_H + 2
            if row._h ~= want then
                row._h = want
                row:SetHeight(want)
                return true
            end
            return false
        end
        row._sync = function() place() end
        -- a pane resize can change the column count, and with it the height
        row:SetScript("OnSizeChanged", function()
            if row._adPlacing then return end
            row._adPlacing = true
            if place() then AT.LayoutPage(pg) end
            row._adPlacing = nil
        end)
    end
end

local function CondMatchRow(pg, ctx, visible, list)
    local C = NS.Conditions
    AT.RowDropdown(pg, win, "Match",
        function()
            local r = ctx()
            return (r and C.MatchAll(r, list)) and "all" or "any"
        end,
        function(v)
            local r = ctx()
            if r then C.SetMatchAll(r, list, v == "all") end
            RefreshAll()
        end,
        function() return {
            { value = "any", text = "Any one of them" },
            { value = "all", text = "All of them" },
        } end,
        function()
            if not visible() then return false end
            local r = ctx()
            return r ~= nil and C.Count(r, list) > 1
        end)
end

-- What the list does right now in words, with Clear once anything is checked.
local function CondStatusRow(pg, ctx, visible, list, textFn)
    local C = NS.Conditions
    local row = AT.AddRow(pg, 24, visible)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -4)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local clear = AT.MakeSmallButton(row, "Clear", 56)
    clear:SetPoint("TOPRIGHT", -8, -2)
    clear:SetHeight(18)
    clear.fs:SetFont(STANDARD_TEXT_FONT, 10, "")
    AT.Tooltip(clear, "Clear", "Unchecks every condition in this list.")
    clear:SetScript("OnClick", function()
        local r = ctx()
        if r then C.Clear(r, list) end
        AT.LayoutPage(pg)
        RefreshAll()
    end)
    row._sync = function()
        local r = ctx()
        if not r then return end
        local n = C.Count(r, list)
        clear:SetShown(n > 0)
        fs:SetText(textFn(r, n))
        local w = row:GetWidth() or 0
        if w < 90 then w = (pg:GetWidth() or 0) - 24 end
        if w > 90 then fs:SetWidth(w - 84) end
        local want = math.max(24, math.floor((fs:GetStringHeight() or 12) + 10))
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
        end
    end
    return row
end

-- Load-condition rows for every record editor, never pushable, each group in a
-- collapsible section. Boxes show the effective state: no conditions shows every
-- box checked (loads everywhere), and unchecking one writes the allow-set.
local function ConditionRows(pg, ctx, tabVisible)
    local uiStore = Store.UI()
    local matrix = Store.ClassSpecMatrix()
    local anySpecs = false
    for _, cls in ipairs(matrix) do
        if #cls.specs > 0 then anySpecs = true break end
    end

    AT.Section(pg, "Classes",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    AT.RowDesc(pg, "Every box checked = shows everywhere.", 18, tabVisible)
    -- Shortcuts: check all (loads everywhere) or clear all to pick a few.
    local btnRow = AT.AddRow(pg, 24, tabVisible)
    local allB = AT.MakeSmallButton(btnRow, "Check all", 76)
    allB:SetPoint("LEFT", 4, 0)
    allB:SetHeight(18)
    allB.fs:SetFont(STANDARD_TEXT_FONT, 10, "")
    local noneB = AT.MakeSmallButton(btnRow, "Uncheck all", 86)
    noneB:SetPoint("LEFT", allB, "RIGHT", 6, 0)
    noneB:SetHeight(18)
    noneB.fs:SetFont(STANDARD_TEXT_FONT, 10, "")
    AT.Tooltip(allB, "Check all", "Show everywhere - clears every class and spec restriction.")
    AT.Tooltip(noneB, "Uncheck all", "Clears the whole matrix so you can check just the classes or specs you want.")
    allB:SetScript("OnClick", function()
        local r = ctx()
        if r then Store.SetAllSpecs(r, true) end
        AT.LayoutPage(pg)
        RefreshAll()
    end)
    noneB:SetScript("OnClick", function()
        local r = ctx()
        if r then Store.SetAllSpecs(r, false) end
        AT.LayoutPage(pg)
        RefreshAll()
    end)
    if anySpecs then
        for _, cls in ipairs(matrix) do
            local row = AT.AddRow(pg, 22, tabVisible)
            local cb = AT.MakeCheckbox(row)
            cb:SetPoint("LEFT", 4, 0)
            local fs = row:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_TEXT_FONT, 10, "")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetText(cls.name)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls.tag]
            if cc then fs:SetTextColor(cc.r, cc.g, cc.b)
            else fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3]) end
            cb:SetScript("OnClick", function()
                local r = ctx()
                if r then
                    local any = Store.ClassConditionState(r, cls.tag)
                    Store.SetClassSpecs(r, cls.tag, not any)
                end
                AT.LayoutPage(pg)
                RefreshAll()
            end)
            cb:HookScript("OnEnter", function() cb:SetHover(true) end)
            cb:HookScript("OnLeave", function() cb:SetHover(false) end)
            row._spec = {}
            local x = 128
            for si, sp in ipairs(cls.specs) do
                local cell = { cb = AT.MakeCheckbox(row) }
                cell.cb:SetPoint("LEFT", row, "LEFT", x, 0)
                cell.fs = row:CreateFontString(nil, "OVERLAY")
                cell.fs:SetFont(STANDARD_TEXT_FONT, 10, "")
                cell.fs:SetPoint("LEFT", cell.cb, "RIGHT", 4, 0)
                cell.fs:SetText(sp.name)
                cell.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
                cell.cb:SetScript("OnClick", function()
                    local r = ctx()
                    if r then
                        Store.SetSpecCondition(r, sp.id,
                            not Store.SpecConditionState(r, cls.tag, sp.id))
                    end
                    AT.LayoutPage(pg)
                    RefreshAll()
                end)
                cell.cb:HookScript("OnEnter", function() cell.cb:SetHover(true) end)
                cell.cb:HookScript("OnLeave", function() cell.cb:SetHover(false) end)
                x = x + 104
                row._spec[si] = cell
            end
            row._sync = function()
                local r = ctx()
                if not r then return end
                local any = Store.ClassConditionState(r, cls.tag)
                cb:SetOn(any)
                for si, sp in ipairs(cls.specs) do
                    row._spec[si].cb:SetOn(Store.SpecConditionState(r, cls.tag, sp.id))
                end
            end
        end
    else
        -- No specs (WoW Forever): one row per class would be a tall, mostly empty
        -- stack, so the class toggles go in a grid that follows the panel width.
        local PERROW = 3
        for r = 1, math.ceil(#matrix / PERROW) do
            local row = AT.AddRow(pg, 22, tabVisible)
            local cells = {}
            for c = 1, PERROW do
                local cls = matrix[(r - 1) * PERROW + c]
                if cls then
                    local cell = CreateFrame("Frame", nil, row)
                    cell:SetHeight(22)
                    local cb = AT.MakeCheckbox(cell)
                    cb:SetPoint("LEFT", 0, 0)
                    local fs = cell:CreateFontString(nil, "OVERLAY")
                    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
                    fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
                    fs:SetPoint("RIGHT", -4, 0)
                    fs:SetJustifyH("LEFT")
                    fs:SetWordWrap(false)
                    fs:SetText(cls.name)
                    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls.tag]
                    if cc then fs:SetTextColor(cc.r, cc.g, cc.b)
                    else fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]) end
                    cb:SetScript("OnClick", function()
                        local rr = ctx()
                        if rr then
                            Store.SetClassSpecs(rr, cls.tag,
                                not Store.ClassConditionState(rr, cls.tag))
                        end
                        AT.LayoutPage(pg)
                        RefreshAll()
                    end)
                    cb:HookScript("OnEnter", function() cb:SetHover(true) end)
                    cb:HookScript("OnLeave", function() cb:SetHover(false) end)
                    cells[#cells + 1] = { f = cell, cb = cb, tag = cls.tag }
                end
            end
            -- OnSizeChanged catches the first real width; placing only from _sync
            -- would leave the cells at the left edge until the next layout pass.
            local function place()
                local w = row:GetWidth() or 0
                if w < 90 then return end
                local cw = math.floor(w / PERROW)
                for i, cell in ipairs(cells) do
                    cell.f:ClearAllPoints()
                    cell.f:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * cw + 4, 0)
                    cell.f:SetWidth(cw - 8)
                end
            end
            row:SetScript("OnSizeChanged", place)
            row._sync = function()
                place()
                local rr = ctx()
                if not rr then return end
                for _, cell in ipairs(cells) do
                    cell.cb:SetOn(Store.ClassConditionState(rr, cell.tag))
                end
            end
        end
    end

    -- Faction: like the classes, a record kept to one faction is released on the
    -- other. Both boxes checked (no restriction) is the default.
    local C = NS.Conditions
    if C then
        AT.Section(pg, "Faction",
            { collapsible = true, store = uiStore, visibleFn = tabVisible })
        local facRow = AT.AddRow(pg, 24, tabVisible)
        local facCells = {}
        for i, fac in ipairs(C.FACTIONS) do
            local cb = AT.MakeCheckbox(facRow)
            cb:SetPoint("LEFT", 4 + (i - 1) * 150, 0)
            local fs = facRow:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_TEXT_FONT, 11, "")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetText((fac == "Alliance" and FACTION_ALLIANCE)
                or (fac == "Horde" and FACTION_HORDE) or fac)
            local fc = PLAYER_FACTION_COLORS
                and PLAYER_FACTION_COLORS[(fac == "Horde") and 0 or 1]
            if fc and fc.r then fs:SetTextColor(fc.r, fc.g, fc.b)
            else fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]) end
            cb:SetScript("OnClick", function()
                local r = ctx()
                if r then C.ToggleFaction(r, fac) end
                AT.LayoutPage(pg)
                RefreshAll()
            end)
            cb:HookScript("OnEnter", function() cb:SetHover(true) end)
            cb:HookScript("OnLeave", function() cb:SetHover(false) end)
            facCells[i] = { cb = cb, fac = fac }
        end
        facRow._sync = function()
            local r = ctx()
            if not r then return end
            for _, cell in ipairs(facCells) do
                cell.cb:SetOn(C.FactionOn(r, cell.fac))
            end
        end
    end

    AT.Section(pg, "Character",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    AT.RowToggle(pg, "Only this character",
        function()
            local r = ctx()
            return r ~= nil and r.c.chars ~= nil and r.c.chars[Store.CharKey()] == true
        end,
        function()
            local r = ctx()
            if r then Store.ToggleCharCondition(r) end
            RefreshAll()
        end,
        tabVisible,
        "Restricts this to the current character. Off = every character on the account sees it.")
    -- Stale character locks: a server rename or transfer orphans the saved
    -- name-realm key, so the toggle above reads unchecked while the lock still
    -- hides the record everywhere. This row shows the lock and offers Unlock.
    local lockRow = AT.AddRow(pg, 24, function()
        local r = ctx()
        return tabVisible() and r ~= nil and r.c.chars ~= nil
            and r.c.chars[Store.CharKey()] ~= true
    end)
    local lockFs = lockRow:CreateFontString(nil, "OVERLAY")
    lockFs:SetFont(STANDARD_TEXT_FONT, 10, "")
    lockFs:SetPoint("LEFT", 10, 0)
    lockFs:SetPoint("RIGHT", -76, 0)
    lockFs:SetJustifyH("LEFT")
    lockFs:SetWordWrap(false)
    lockFs:SetTextColor(0.95, 0.62, 0.30)
    local lockBtn = AT.MakeSmallButton(lockRow, "Unlock", 60)
    lockBtn:SetPoint("RIGHT", -8, 0)
    lockBtn:SetScript("OnClick", function()
        local r = ctx()
        if r then Store.ClearCharCondition(r) end
        RefreshAll()
    end)
    AT.Tooltip(lockBtn, "Unlock", "Clears the character lock so this loads for every character again (class boxes above still apply).")
    lockRow._sync = function()
        local r = ctx()
        if not (r and r.c.chars) then return end
        local names = {}
        for k in pairs(r.c.chars) do names[#names + 1] = k end
        table.sort(names)
        lockFs:SetText("Locked to another character: " .. table.concat(names, ", "))
    end

    -- Talents: the build-level gate. WoW Forever has no specs, so this does what
    -- "only on Enhancement" does on retail.
    AT.Section(pg, "Talents",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })

    local haveTree = function()
        local cat = NS.TalentCatalog
        return cat ~= nil and #cat.All() > 0
    end
    AT.RowDesc(pg, "Shows only with these talents. None listed = no restriction.",
        18, function() return tabVisible() and haveTree() end)
    AT.RowDesc(pg, "No talent tree on this character: talent conditions do not apply.",
        20, function() return tabVisible() and not haveTree() end)

    local pickRow = AT.AddRow(pg, 26, function() return tabVisible() and haveTree() end)
    local pick = AT.MakeSmallButton(pickRow, "Choose talents", 130)
    pick:SetPoint("LEFT", 10, 0)
    pick:SetHeight(20)
    pick.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    pick:SetScript("OnClick", function() OpenTalentPicker(ctx) end)
    AT.Tooltip(pick, "Choose talents",
        "Opens the talent tree. Click a node to require it, click it again to drop it.")
    local pickFs = pickRow:CreateFontString(nil, "OVERLAY")
    pickFs:SetFont(STANDARD_TEXT_FONT, 10, "")
    pickFs:SetPoint("LEFT", pick, "RIGHT", 10, 0)
    pickFs:SetPoint("RIGHT", -8, 0)
    pickFs:SetJustifyH("LEFT")
    pickFs:SetWordWrap(false)
    pickFs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    pickRow._sync = function()
        local r = ctx()
        local n = r and #Store.TalentList(r) or 0
        pickFs:SetText(n == 0 and "nothing required - shows on any build"
            or (n == 1 and "1 talent required" or (n .. " talents required")))
    end

    local haveMulti = function()
        local r = ctx()
        if not (r and r.c.talents) then return false end
        local n = 0
        for _ in pairs(r.c.talents) do n = n + 1 if n > 1 then return true end end
        return false
    end
    AT.RowDropdown(pg, win, "Match",
        function()
            local r = ctx()
            return (r and r.c.talentMode == "any") and "any" or "all"
        end,
        function(v)
            local r = ctx()
            if r then Store.SetTalentMode(r, v) end
            RefreshAll()
        end,
        function() return {
            { value = "all", text = "Need all of them" },
            { value = "any", text = "Need any one" },
        } end,
        function() return tabVisible() and haveMulti() end)

    local chosenRows = {}
    for i = 1, 10 do
        local row = AT.AddRow(pg, 22, function()
            if not tabVisible() then return false end
            local r = ctx()
            if not r then return false end
            return #Store.TalentList(r) >= i
        end)
        local tex = row:CreateTexture(nil, "ARTWORK")
        tex:SetSize(16, 16)
        tex:SetPoint("LEFT", 10, 0)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local nameFs = row:CreateFontString(nil, "OVERLAY")
        nameFs:SetFont(STANDARD_TEXT_FONT, 11, "")
        nameFs:SetPoint("LEFT", 32, 0)
        nameFs:SetPoint("RIGHT", -150, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        local stateFs = row:CreateFontString(nil, "OVERLAY")
        stateFs:SetFont(STANDARD_TEXT_FONT, 10, "")
        stateFs:SetPoint("RIGHT", -74, 0)
        stateFs:SetJustifyH("RIGHT")
        local del = AT.MakeSmallButton(row, "Remove", 62)
        del:SetPoint("RIGHT", -8, 0)
        del:SetHeight(18)
        del.fs:SetFont(STANDARD_TEXT_FONT, 10, "")
        row._sync = function()
            local r = ctx()
            if not r then return end
            local list = Store.TalentList(r)
            local e = list[i]
            if not e then return end
            tex:SetTexture(e.icon)
            nameFs:SetText(e.name)
            if not e.known then
                -- stored from another class or a changed tree: say so rather
                -- than quietly reading as "not taken"
                nameFs:SetTextColor(0.55, 0.65, 0.78)
                stateFs:SetText("not in this tree")
                stateFs:SetTextColor(0.55, 0.65, 0.78)
            elseif e.taken then
                nameFs:SetTextColor(0.95, 0.97, 1)
                stateFs:SetText("taken")
                stateFs:SetTextColor(0.48, 0.85, 0.56)
            else
                nameFs:SetTextColor(0.7, 0.78, 0.88)
                stateFs:SetText("not taken")
                stateFs:SetTextColor(0.95, 0.62, 0.30)
            end
            del:SetScript("OnClick", function()
                local rr = ctx()
                if rr then Store.ToggleTalent(rr, e.nodeID) end
                AT.LayoutPage(pg)
                RefreshAll()
            end)
        end
        chosenRows[i] = row
    end

    -- Load When / Never Load When: a failing record is not released but goes
    -- inert (invisible, no mouse or sounds, out of its dynamic cell) with its
    -- frames kept, so it returns the moment the answer flips, in combat too.
    if C then
        local whenVis = function()
            return tabVisible() and not InAuraGroup(ctx())
        end
        AT.Section(pg, "Load When",
            { collapsible = true, store = uiStore, visibleFn = whenVis })
        CondStatusRow(pg, ctx, whenVis, "loadWhen", function(r, n)
            if n == 0 then
                return "Nothing checked: no condition, so the sections above decide alone."
            end
            local head = C.MatchAll(r, "loadWhen")
                and "Loads only while EVERY checked condition is true."
                or "Loads only while at least one checked condition is true."
            return head .. " Unloaded, it is gone completely - no mouse, no sounds, no cell in a dynamic group - and it is back the moment that changes, in combat too."
        end)
        CondMatchRow(pg, ctx, whenVis, "loadWhen")
        CondGrid(pg, ctx, whenVis, "loadWhen")
        AT.Section(pg, "Never Load When",
            { collapsible = true, store = uiStore, visibleFn = whenVis })
        CondStatusRow(pg, ctx, whenVis, "loadNever", function(_, n)
            if n == 0 then return "Nothing checked." end
            return "Stays unloaded while any checked condition is true. This wins over Load When."
        end)
        CondGrid(pg, ctx, whenVis, "loadNever")
        AT.Section(pg, nil)
        AT.RowDesc(pg, "Set these on the icon's Aura Group: it cannot hide one member in combat.", 20,
            function() return tabVisible() and InAuraGroup(ctx()) end)
    else
        AT.Section(pg, nil)
        AT.RowDesc(pg, COND_RESTART, 20, tabVisible)
    end

    -- Close the section, so rows a caller adds next are not put inside it.
    AT.Section(pg, nil)
end

-- The Visibility tab: a fade layer, never pushable. Fade When
-- wins over Full Opacity When; fading in is instant, fading out waits the
-- delay, then takes the fade time.
local function VisibilityRows(pg, ctx, tabVisible)
    local C = NS.Conditions
    if not C then
        AT.Section(pg, nil)
        AT.RowDesc(pg, COND_RESTART, 20, tabVisible)
        return
    end
    local uiStore = Store.UI()
    AT.Section(pg, "Full Opacity When",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    CondStatusRow(pg, ctx, tabVisible, "showWhen", function(r, n)
        if n == 0 then
            return "Nothing checked: full opacity, unless Fade When says otherwise."
        end
        if C.MatchAll(r, "showWhen") then
            return "Full opacity only while EVERY checked condition is true; faded the rest of the time."
        end
        return "Full opacity while at least one checked condition is true; faded the rest of the time."
    end)
    CondMatchRow(pg, ctx, tabVisible, "showWhen")
    CondGrid(pg, ctx, tabVisible, "showWhen")
    AT.Section(pg, "Fade When",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    CondStatusRow(pg, ctx, tabVisible, "fadeWhen", function(_, n)
        if n == 0 then return "Nothing checked." end
        return "Fades while any checked condition is true. This wins over Full Opacity When."
    end)
    CondGrid(pg, ctx, tabVisible, "fadeWhen")
    AT.Section(pg, "Fade Settings",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    AT.RowSlider(pg, "Faded opacity",
        function() local r = ctx() return r and C.GetFade(r, "fadeAlpha") or 0 end,
        function(v) local r = ctx() if r then C.SetFade(r, "fadeAlpha", v) end end,
        0, 1, 0.01, true, tabVisible)
    AT.RowSlider(pg, "Fade time (seconds)",
        function() local r = ctx() return r and C.GetFade(r, "fadeTime") or 0 end,
        function(v) local r = ctx() if r then C.SetFade(r, "fadeTime", v) end end,
        0, C.FADE_MAX.fadeTime, 0.05, "%.2f", tabVisible)
    AT.RowSlider(pg, "Delay before fading (seconds)",
        function() local r = ctx() return r and C.GetFade(r, "fadeDelay") or 0 end,
        function(v) local r = ctx() if r then C.SetFade(r, "fadeDelay", v) end end,
        0, C.FADE_MAX.fadeDelay, 0.1, "%.1f", tabVisible)
    AT.RowDesc(pg, "Everything shows fully while this window is open. Close it to see the fade.", 20, tabVisible)
    AT.Section(pg, nil)
end

-- The window

local rail, content
local railRows = {}          -- row frame pool
local panes = {}             -- name -> frame
local layoutRowPool = {}     -- layout-page member rows
local layoutAddRow           -- the "+ Add to this layout" row
local stripPool = {}         -- group strip icon buttons
local freeStripPool = {}
local addWin

local function ShowPane(name)
    for n, f in pairs(panes) do f:SetShown(n == name) end
end

-- Rail

-- Element thumbnails: the art left of a name says what the element is, so
-- there are no type symbols. A group is a 2x2 glyph (three filled squares, one
-- hollow) in its kind color; a bar a miniature of itself; an icon its spell
-- art. `size` drives the icon and bar modes, `groupSize` the glyph.
local THUMB_EDGES = { "top", "bottom", "left", "right" }

local function BarTexPath(key)
    local B = NS.Bars
    if not key or key == "" or not B then return WHITE end
    if B.BUILTIN_TEXTURES and B.BUILTIN_TEXTURES[key] then return B.BUILTIN_TEXTURES[key] end
    local lsm = B.GetLSM and B.GetLSM()
    local path = lsm and lsm:Fetch("statusbar", key, true)
    return path or WHITE
end

local function MakeThumb(parent, size, groupSize)
    groupSize = groupSize or size
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(size, size)
    t.single = t:CreateTexture(nil, "ARTWORK")
    t.single:SetPoint("TOPLEFT", 0, 0)
    t.single:SetSize(size, size)
    t.single:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local gap = 2
    local cell = (groupSize - gap) / 2
    t.cells = {}
    for i = 1, 4 do
        local c = t:CreateTexture(nil, "ARTWORK")
        c:SetSize(cell, cell)
        c:SetPoint("TOPLEFT", ((i - 1) % 2) * (cell + gap),
            -math.floor((i - 1) / 2) * (cell + gap))
        t.cells[i] = c
    end
    t.frame = {}
    for _, k in ipairs(THUMB_EDGES) do
        t.frame[k] = t:CreateTexture(nil, "OVERLAY")
    end
    local fr, c4 = t.frame, t.cells[4]
    fr.top:SetPoint("TOPLEFT", c4); fr.top:SetPoint("TOPRIGHT", c4); fr.top:SetHeight(1)
    fr.bottom:SetPoint("BOTTOMLEFT", c4); fr.bottom:SetPoint("BOTTOMRIGHT", c4); fr.bottom:SetHeight(1)
    fr.left:SetPoint("TOPLEFT", c4); fr.left:SetPoint("BOTTOMLEFT", c4); fr.left:SetWidth(1)
    fr.right:SetPoint("TOPRIGHT", c4); fr.right:SetPoint("BOTTOMRIGHT", c4); fr.right:SetWidth(1)
    t.bar = CreateFrame("Frame", nil, t)
    t.bar.bg = t.bar:CreateTexture(nil, "BACKGROUND")
    t.bar.bg:SetAllPoints()
    t.bar.fill = t.bar:CreateTexture(nil, "ARTWORK")
    t.bar.fill:SetPoint("TOPLEFT", 1, -1)
    t.bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    t.bar.edges = {}
    for _, k in ipairs(THUMB_EDGES) do
        t.bar.edges[k] = t.bar:CreateTexture(nil, "OVERLAY")
    end
    local e = t.bar.edges
    e.top:SetPoint("TOPLEFT"); e.top:SetPoint("TOPRIGHT"); e.top:SetHeight(1)
    e.bottom:SetPoint("BOTTOMLEFT"); e.bottom:SetPoint("BOTTOMRIGHT"); e.bottom:SetHeight(1)
    e.left:SetPoint("TOPLEFT"); e.left:SetPoint("BOTTOMLEFT"); e.left:SetWidth(1)
    e.right:SetPoint("TOPRIGHT"); e.right:SetPoint("BOTTOMRIGHT"); e.right:SetWidth(1)

    local function Mode(single, cells, bar)
        t.single:SetShown(single)
        for i = 1, 4 do t.cells[i]:SetShown(cells) end
        for _, k in ipairs(THUMB_EDGES) do t.frame[k]:SetShown(cells) end
        t.bar:SetShown(bar)
    end

    -- px = an optional bigger square (the layout cards' 30px free icons)
    function t:SetIcon(tex, px)
        px = px or size
        self:SetSize(px, px)
        self.single:SetSize(px, px)
        Mode(true, false, false)
        self.single:SetTexture(tex or 134400)
    end

    function t:SetGroup(color)
        self:SetSize(groupSize, groupSize)
        Mode(false, true, false)
        color = color or YELLOW
        for i = 1, 3 do
            self.cells[i]:SetColorTexture(color[1], color[2], color[3], 1)
        end
        -- The fourth square is hollow: its fill goes clear and the 1px frame,
        -- anchored to this cell, outlines it.
        self.cells[4]:SetColorTexture(0, 0, 0, 0)
        for _, k in ipairs(THUMB_EDGES) do
            self.frame[k]:SetColorTexture(color[1], color[2], color[3], 0.6)
        end
    end

    -- width = the thumb's width; at 40+ the spell art leads the mini bar
    function t:SetBar(rec, width, spellTex)
        width = width or size
        self:SetSize(width, size)
        local lead = (width >= 40) and spellTex
        Mode(lead and true or false, false, true)
        local x = 0
        if lead then
            self.single:SetSize(size, size)
            self.single:SetTexture(spellTex)
            x = size + 3
        end
        local h = math.max(6, math.floor(size * 0.5 + 0.5))
        local w = width - x
        self.bar:ClearAllPoints()
        self.bar:SetPoint("LEFT", x, 0)
        self.bar:SetSize(w, h)
        local path = BarTexPath(Store.Resolve(rec, "fill", "texture"))
        local fc = Store.Resolve(rec, "fill", "color") or COL.arc
        local bgc = Store.Resolve(rec, "look", "bgColor") or COL.well
        local bc = Store.Resolve(rec, "look", "borderColor") or COL.line
        local border = Store.Resolve(rec, "look", "borderEnabled") ~= false
        -- A resource bar in power colour previews in it (a Mana bar reads blue).
        local usePower = rec.barKind == "resource"
            and Store.Resolve(rec, "resource", "usePowerColor") ~= false
        if usePower then
            local B = NS.Bars
            local pt = rec.driver and rec.driver.powerType
            local info = B and B.POWER_INFO and pt ~= nil and B.POWER_INFO[pt]
            local pc = info and info.color
            if type(pc) == "table" then
                fc = { pc[1] or pc.r or fc[1], pc[2] or pc.g or fc[2], pc[3] or pc.b or fc[3] }
            end
        end
        -- Pips: a row of cells in the point colour, the first two thirds lit, the
        -- rest empty; diamonds are rotated squares. A row that would not fit (the
        -- rail's 22px thumb) keeps the plain mini bar.
        local pips = rec.barKind == "resource"
            and Store.Resolve(rec, "resource", "style") == "pips"
        local n = 0
        if pips and NS.Bars and NS.Bars.MaxStacksFor then
            n = tonumber(NS.Bars.MaxStacksFor(rec)) or 0
        end
        if n < 2 then n = 5 elseif n > 10 then n = 10 end
        local gap = 2
        local cell = pips and math.min(h, math.floor((w - (n - 1) * gap) / n)) or 0
        if pips and cell >= 3 then
            self.bar.bg:SetVertexColor(0, 0, 0, 0)
            self.bar.fill:SetVertexColor(0, 0, 0, 0)
            for _, k in ipairs(THUMB_EDGES) do self.bar.edges[k]:SetColorTexture(0, 0, 0, 0) end
            local pcol = fc
            if not usePower then
                pcol = Store.Resolve(rec, "resource", "pointColor") or fc
            end
            local diamond = Store.Resolve(rec, "resource", "pipShape") == "diamond"
            local lit = math.max(1, math.floor(n * 0.66 + 0.5))
            local rowW = n * cell + (n - 1) * gap
            local startX = math.floor((w - rowW) / 2 + 0.5)
            self.pips = self.pips or {}
            for i = 1, 10 do
                local p = self.pips[i]
                if i <= n then
                    if not p then
                        p = self.bar:CreateTexture(nil, "OVERLAY")
                        self.pips[i] = p
                    end
                    local px = diamond and math.max(2, math.floor(cell * 0.72 + 0.5)) or cell
                    p:ClearAllPoints()
                    p:SetSize(px, px)
                    p:SetPoint("CENTER", self.bar, "LEFT", startX + (i - 1) * (cell + gap) + cell / 2, 0)
                    p:SetRotation(diamond and math.rad(45) or 0)
                    p:SetColorTexture(pcol[1], pcol[2], pcol[3], (i <= lit) and 1 or 0.28)
                    p:Show()
                elseif p then
                    p:Hide()
                end
            end
            return
        end
        if self.pips then for _, p in ipairs(self.pips) do p:Hide() end end
        self.bar.bg:SetTexture(path)
        self.bar.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], 1)
        -- a bar caught two-thirds full, cropped (not squeezed) like a statusbar
        self.bar.fill:SetTexture(path)
        self.bar.fill:SetTexCoord(0, 0.66, 0, 1)
        self.bar.fill:SetVertexColor(fc[1], fc[2], fc[3], 1)
        self.bar.fill:SetWidth(math.max(2, math.floor((w - 2) * 0.66 + 0.5)))
        -- A borderless bar still gets a faint outline, so the thumbnail reads as
        -- a bar even when its trough matches the row.
        if not border then bc = COL.line2 end
        for _, k in ipairs(THUMB_EDGES) do
            self.bar.edges[k]:SetColorTexture(bc[1], bc[2], bc[3], border and 1 or 0.6)
        end
    end
    return t
end

local RAIL_W = 232
local RAIL_SEL = { 0.055, 0.165, 0.227 }
local ADDLINE = { 0.18, 0.34, 0.24 }

-- The side-icon override, then the driver spell, as the bar's own side icon
-- resolves. nil: no art, and the layout cards draw the mini bar alone.
local function BarTexture(rec)
    local ov = Store.Resolve(rec, "icon", "iconOverride") or 0
    if type(ov) == "number" and ov > 0 then
        return C_Spell.GetSpellTexture(ov) or ov
    end
    local d = rec.driver or {}
    if rec.barKind == "swing" then
        local slot = (d.swingType == 1 and 17) or (d.swingType == 2 and 18) or 16
        return GetInventoryItemTexture("player", slot)
    end
    if rec.barKind == "cooldown" or rec.barKind == "aura" then
        return d.spellID and C_Spell.GetSpellTexture(d.spellID) or nil
    end
    return nil
end

-- One painter for every rail row. style: "layout" = raised header card,
-- "child" = tree item, "add" / "addbtn" = green actions, "label" = inert caption.
local function PaintRailRow(row, selected, style)
    row._sel, row._style = selected, style
    local fill, edge, ink = COL.well, COL.well, COL.dim
    if selected then
        fill, edge, ink = RAIL_SEL, COL.arcDeep, COL.arc
    elseif style == "layout" then
        fill, edge, ink = COL.panel, COL.line, COL.ink
    elseif style == "add" then
        ink = GREENC
    elseif style == "addbtn" then
        edge, ink = ADDLINE, GREENC
    elseif style == "label" then
        ink = COL.faint
    end
    if row._dim and not selected then ink = COL.faint end
    if row._hot and not selected and style ~= "label" then
        fill = COL.btn
        if style == "add" or style == "addbtn" then
            edge = GREENC
        else
            edge, ink = COL.arcDeep, COL.ink
        end
    end
    AT.Skin(row, fill, edge)
    row.name:SetTextColor(ink[1], ink[2], ink[3])
    if row.accent then row.accent:SetShown(selected and true or false) end
end

-- Hover and selected accent, shared by the tree rows and the ADDON rows.
local function RailChrome(row)
    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    row.accent:SetPoint("TOPLEFT", 1, -1)
    row.accent:SetPoint("BOTTOMLEFT", 1, 1)
    row.accent:SetWidth(2)
    row.accent:Hide()
    row:SetScript("OnEnter", function(s)
        s._hot = true
        PaintRailRow(s, s._sel, s._style)
    end)
    row:SetScript("OnLeave", function(s)
        s._hot = nil
        PaintRailRow(s, s._sel, s._style)
    end)
end

-- Opens the editor on a record (a copy, a moved element, an import).
local function SelectRecord(rec)
    if not rec then return end
    if rec.type == "layout" then
        ExpandedSet()[rec.id] = true
        Options.Select("layout", rec.id)
    elseif rec.type == "group" then
        Options.Select("group", rec.id)
    elseif rec.type == "bar" then
        Options.Select("bar", rec.id)
    elseif rec.type == "icon" then
        Options.SelectIconHome(rec)
    end
end

-- Rail drag and drop: a layout row, or any row inside it, takes groups, bars and
-- icons (icons land as free icons); a group row takes icons, an aura group only
-- auras. OnDragStart fires only after the cursor travels, so clicks still work.
-- Helpers live on RailDD: this file's main chunk is at Lua's 200-local limit.
local RailDD = {}   -- .ghost = the cursor label; .drag = { id } mid-drag; .line = the drop line

-- The element row under the cursor, "+ Add New" included. Checked against the
-- scroll window first: a row scrolled out of view still answers IsMouseOver.
function RailDD.HoverRow()
    local host = Options.railHost
    if host and not host:IsMouseOver() then return nil end
    for _, row in ipairs(railRows) do
        if row:IsShown() and row._item and row:IsMouseOver() then
            local k = row._item.kind
            if k == "layout" or k == "group" or k == "bar" or k == "freeicon"
                or k == "addchild" then
                return row
            end
        end
    end
end

function RailDD.RowLayoutId(row)
    local item = row._item
    if item.kind == "layout" or item.kind == "addchild" then return item.rec.id end
    if item.kind == "freeicon" then return item.layout.id end
    return item.rec.layoutId
end

-- nil when id is the last member.
function RailDD.NextMemberId(layoutId, id)
    local lay = Store.Get(layoutId)
    if not lay then return nil end
    for i, mid in ipairs(lay.members or {}) do
        if mid == id then return lay.members[i + 1] end
    end
end

function RailDD.AlreadyThere(rec, layoutId, beforeId)
    if rec.layoutId ~= layoutId or (rec.type == "icon" and rec.groupId) then return false end
    return RailDD.NextMemberId(layoutId, rec.id) == beforeId
end

-- What releasing now would do: "into" = a layout header row (append), "join" =
-- an icon over the middle of a group row, "before" = the top or bottom half of a
-- child row (beforeId nil = the end; "+ Add New" = the end). nil = nothing: its
-- own row, a spot it already holds, or off the tree.
function RailDD.Target()
    local drag = RailDD.drag
    local row = RailDD.HoverRow()
    if not (drag and row) then return nil end
    local item = row._item
    local rec = Store.Get(drag.id)
    if not rec then return nil end
    if item.kind == "layout" then
        if item.rec.id == rec.id then return nil end
        return { row = row, mode = "into", layoutId = item.rec.id, label = "into " .. item.rec.name }
    end
    if item.kind == "addchild" then
        if RailDD.AlreadyThere(rec, item.rec.id, nil) then return nil end
        return { row = row, mode = "before", layoutId = item.rec.id, beforeId = nil,
            line = "top", label = "at the end of " .. item.rec.name }
    end
    if item.rec.id == rec.id then return nil end
    local _, cy = GetCursorPosition()
    local es = row:GetEffectiveScale()
    local top, bottom = row:GetTop(), row:GetBottom()
    if not (es and es > 0 and top and bottom and top > bottom) then return nil end
    local f = (top - cy / es) / (top - bottom)   -- 0 at the top edge, 1 at the bottom
    if rec.type == "icon" and item.kind == "group" and f >= 0.3 and f <= 0.7 then
        if item.rec.id == rec.groupId then return nil end
        if item.rec.groupKind == "aura" and rec.kind ~= "aura" then return nil end
        return { row = row, mode = "join", groupId = item.rec.id, label = "into " .. item.rec.name }
    end
    local lid = RailDD.RowLayoutId(row)
    if not lid then return nil end
    local beforeId, line, label
    if f < 0.5 then
        beforeId, line, label = item.rec.id, "top", "above " .. item.rec.name
    else
        beforeId, line, label = RailDD.NextMemberId(lid, item.rec.id), "bottom", "below " .. item.rec.name
    end
    if RailDD.AlreadyThere(rec, lid, beforeId) then return nil end
    return { row = row, mode = "before", layoutId = lid, beforeId = beforeId, line = line, label = label }
end

-- A lit row for into / join, the seam line for before, and the ghost's second
-- line.
function RailDD.Paint(t)
    local hot = t and (t.mode == "into" or t.mode == "join") and t.row or nil
    for _, row in ipairs(railRows) do
        if row._dropHot and row ~= hot then
            row._dropHot, row._hot = nil, nil
            PaintRailRow(row, row._sel, row._style)
        end
    end
    if hot and not hot._dropHot then
        hot._dropHot, hot._hot = true, true
        PaintRailRow(hot, hot._sel, hot._style)
    end
    local line = RailDD.line
    if t and t.line then
        if not line then
            -- in the scrolling list, so the scroll clips it with the rows
            local lf = Options.railList or rail
            line = CreateFrame("Frame", nil, lf)
            line:SetHeight(2)
            line:SetFrameLevel(lf:GetFrameLevel() + 18)   -- over the rows
            line.bar = line:CreateTexture(nil, "OVERLAY")
            line.bar:SetAllPoints()
            line.bar:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            line.dot = line:CreateTexture(nil, "OVERLAY")
            line.dot:SetSize(6, 6)
            line.dot:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            line.dot:SetPoint("CENTER", line, "LEFT", 0, 0)
            RailDD.line = line
        end
        line:ClearAllPoints()
        if t.line == "top" then
            line:SetPoint("TOPLEFT", t.row, "TOPLEFT", 3, 1)
            line:SetPoint("TOPRIGHT", t.row, "TOPRIGHT", -3, 1)
        else
            line:SetPoint("BOTTOMLEFT", t.row, "BOTTOMLEFT", 3, -1)
            line:SetPoint("BOTTOMRIGHT", t.row, "BOTTOMRIGHT", -3, -1)
        end
        line:Show()
    elseif line then
        line:Hide()
    end
    local ghost = RailDD.ghost
    if ghost then
        ghost.sub:SetText(t and t.label or "")
        ghost:SetHeight(t and 34 or 22)
    end
end

function RailDD.Start(row)
    local item = row._item
    if not (item and item.rec) then return end
    RailDD.drag = { id = item.rec.id }
    local ghost = RailDD.ghost
    if not ghost then
        ghost = CreateFrame("Frame", nil, win, "BackdropTemplate")
        ghost:SetSize(190, 22)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:EnableMouse(false)
        AT.Skin(ghost, COL.panel, COL.arcDeep)
        ghost.fs = ghost:CreateFontString(nil, "OVERLAY")
        ghost.fs:SetFont(STANDARD_TEXT_FONT, 11, "")
        ghost.fs:SetPoint("TOPLEFT", 8, -5)
        ghost.fs:SetPoint("TOPRIGHT", -8, -5)
        ghost.fs:SetJustifyH("LEFT")
        ghost.fs:SetWordWrap(false)
        ghost.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        ghost.sub = ghost:CreateFontString(nil, "OVERLAY")
        ghost.sub:SetFont(STANDARD_TEXT_FONT, 10, "")
        ghost.sub:SetPoint("TOPLEFT", ghost.fs, "BOTTOMLEFT", 0, -2)
        ghost.sub:SetPoint("TOPRIGHT", ghost.fs, "BOTTOMRIGHT", 0, -2)
        ghost.sub:SetJustifyH("LEFT")
        ghost.sub:SetWordWrap(false)
        ghost.sub:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        RailDD.ghost = ghost
    end
    ghost.fs:SetText(item.rec.name)
    ghost.sub:SetText("")
    ghost:SetHeight(22)
    ghost:Show()
    ghost:SetScript("OnUpdate", function(g, elapsed)
        local cx, cy = GetCursorPosition()
        local es = g:GetEffectiveScale()
        if not es or es <= 0 then return end
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / es + 14, cy / es - 6)
        RailDD.EdgeScroll(cx, cy, elapsed)
        RailDD.Paint(RailDD.Target())
    end)
end

-- Scrolls the list while a row is dragged near or past its top or bottom edge,
-- faster closer to the edge. Called only from the drag's own OnUpdate.
function RailDD.EdgeScroll(cx, cy, elapsed)
    local host, lf = Options.railHost, Options.railList
    if not (host and lf and host:IsVisible()) then return end
    local s = host:GetEffectiveScale()
    local l, r, t, b = host:GetLeft(), host:GetRight(), host:GetTop(), host:GetBottom()
    if not (s and s > 0 and l and r and t and b) then return end
    local x, y = cx / s, cy / s
    if x < l or x > r then return end
    local over = (lf:GetHeight() or 0) - (host:GetHeight() or 0)
    if over <= 0 then return end
    local zone = 24
    local dir, depth
    if y > t - zone then
        dir, depth = -1, (y - (t - zone)) / zone
    elseif y < b + zone then
        dir, depth = 1, ((b + zone) - y) / zone
    else
        return
    end
    local cur = (host:GetVerticalScroll() or 0)
        + dir * (120 + 480 * math.min(1, depth)) * (elapsed or 0)
    host:SetVerticalScroll(math.max(0, math.min(cur, over)))
    host:UpdateScroll()
end

function RailDD.Stop()
    local t = RailDD.Target()
    local drag = RailDD.drag
    RailDD.drag = nil
    if RailDD.ghost then
        RailDD.ghost:SetScript("OnUpdate", nil)
        RailDD.ghost:Hide()
    end
    RailDD.Paint(nil)
    if not (drag and t) then return end
    local rec = Store.Get(drag.id)
    if not rec then return end
    local wasGroup = rec.groupId
    local wasLayout = (not wasGroup) and rec.layoutId or nil
    if t.mode == "join" then
        if not Store.MoveIcon(rec.id, t.groupId) then return end
    elseif t.mode == "into" then
        if not Store.MoveToLayout(rec.id, t.layoutId) then return end
    else
        if not Store.PlaceInLayout(rec.id, t.layoutId, t.beforeId) then return end
    end
    -- A reorder in the same layout keeps the view; a move elsewhere follows the
    -- record.
    local moved = t.mode == "join" or wasGroup ~= nil or t.layoutId ~= wasLayout
    if not moved then return end
    if t.layoutId then ExpandedSet()[t.layoutId] = true end
    SelectRecord(rec)
end

function RailDD.Make(row)
    row:SetScript("OnDragStart", RailDD.Start)
    row:SetScript("OnDragStop", RailDD.Stop)
end
Options._railDD = RailDD   -- used by the offline tests

-- Eye on records that fail their load conditions here: slashed grey = not drawn,
-- open cyan = drawn while this window is open. Per element (Store.UnloadedShown);
-- the Settings "Show unloaded items while editing" switch is the default.
-- New texture files need a full client restart.
Options.EYE_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_Eye"
Options.EYE_OFF_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_EyeOff"

function Options.MakeEye(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 18)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetSize(18, 18)
    b.tex:SetPoint("CENTER", 0, 0)
    b.tex:SetTexture(Options.EYE_OFF_TEX)
    b:SetScript("OnEnter", function(s)
        s._hot = true
        Options.PaintEye(s, s._rec)
    end)
    b:SetScript("OnLeave", function(s)
        s._hot = nil
        Options.PaintEye(s, s._rec)
    end)
    b:SetScript("OnClick", function(s)
        AT.CloseDropdown()
        local rec = s._rec
        if not rec then return end
        local on = not Store.UnloadedShown(rec)
        Store.SetUnloadedShown(rec, on)
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                     or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        RefreshAll()
    end)
    -- Hooked after the SetScript calls above, or they would replace it.
    AT.Tooltip(b, function()
        local r = b._rec
        return (r and Store.UnloadedShown(r)) and "Shown while editing" or "Not loaded here"
    end, function()
        local r = b._rec
        if not r then return nil end
        local why = (Store.BadgeText(r))
        if Store.UnloadedShown(r) then
            return "Drawn on screen while this window is open, with an \"unloaded\" tag. It loads on: "
                .. why .. ". Click to hide it again."
        end
        return "Not loaded on this character. It loads on: " .. why
            .. ". Click to draw it on screen while this window is open. Its load conditions stay as they are."
    end)
    b:Hide()
    return b
end

-- Hidden when the record loads here.
function Options.PaintEye(b, rec)
    b._rec = rec
    local unloaded = rec ~= nil and not Store.IsLoaded(rec)
    b:SetShown(unloaded)
    if not unloaded then return end
    local on = Store.UnloadedShown(rec)
    local c = (b._hot and COL.ink) or (on and COL.arc) or COL.faint
    b.tex:SetTexture(on and Options.EYE_TEX or Options.EYE_OFF_TEX)
    b.tex:SetVertexColor(c[1], c[2], c[3], 1)
end

local function RailRow(i)
    local row = railRows[i]
    if row then return row end
    -- rows live in the scrolling list (the rail build makes it first)
    row = CreateFrame("Button", nil, Options.railList or rail, "BackdropTemplate")
    row:SetHeight(24)
    row:RegisterForDrag("LeftButton")
    AT.Skin(row, COL.well, COL.well)
    row.chev = AT.MakeChevron(row)
    -- Tree guide: one hairline under the layout.
    row.guide = row:CreateTexture(nil, "ARTWORK")
    row.guide:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    row.guide:SetWidth(1)
    row.guide:SetPoint("TOPLEFT", 11, 1)
    row.guide:SetPoint("BOTTOMLEFT", 11, 0)
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(STANDARD_TEXT_FONT, 12, "")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.pill = KindPill(row)
    -- Anchored per row kind in RefreshRail.
    row.eye = Options.MakeEye(row)
    row.badge = row:CreateFontString(nil, "OVERLAY")
    row.badge:SetFont(STANDARD_TEXT_FONT, 8, "")
    row.badge:SetPoint("RIGHT", -6, 0)
    row.badge:SetJustifyH("RIGHT")
    row.badge:SetWordWrap(false)
    if row.badge.SetMaxLines then row.badge:SetMaxLines(1) end
    row.thumb = MakeThumb(row, 18, 20)
    row.edit = AT.MakeSmallButton(row, "Edit", 38)
    row.edit:SetPoint("RIGHT", -4, 0)
    row.edit:SetHeight(16)
    row.edit.fs:SetFont(STANDARD_TEXT_FONT, 9, "")
    row.export = AT.MakeSmallButton(row, "Exp", 32)
    row.export:SetPoint("RIGHT", row.edit, "LEFT", -3, 0)
    row.export:SetHeight(16)
    row.export.fs:SetFont(STANDARD_TEXT_FONT, 9, "")
    AT.Tooltip(row.export, "Export", "Copy a share string for this layout.")
    RailChrome(row)
    -- Hooked after RailChrome's SetScript, or it would be replaced.
    AT.Tooltip(row, "Not loaded here", function()
        local item = row._item
        local rec = item and item.rec
        if not (rec and rec.type ~= "layout" and not Store.IsLoaded(rec)) then return nil end
        local why = Store.BadgeText(rec)
        return "This " .. (rec.type == "group" and "group" or rec.type)
            .. " fails its load conditions on this character (" .. why
            .. "). It exists and can be edited; it just does not show here. Click its eye to draw it on screen while you edit."
    end)
    railRows[i] = row
    return row
end

local function BuildRailList()
    local list = {}
    local expanded = ExpandedSet()
    -- While searching, every layout is matched, open or shut. A layout lists when
    -- its name or a member matches (a group when one of its icons does), opened to
    -- the matching members, without the add rows.
    local S = Options.Search
    local q = S.Norm(ui.search)
    local filter = q ~= "" and { q = q, words = S.Words(q),
        num = q:match("^%d+$") and tonumber(q) or nil } or nil
    local function Hit(rec)
        return S.RecScore(rec, filter.q, filter.words, filter.num) ~= nil
    end
    local function MemberHit(m)
        if Hit(m) then return true end
        if m.type == "group" then
            for _, ic in ipairs(Store.IconsOf(m)) do
                if Hit(ic) then return true end
            end
        end
        return false
    end
    local function AddLayout(layout, notLoaded)
        local members = Store.MembersOf(layout)
        local open = expanded[layout.id] and true or false
        if filter then
            local hits = {}
            for _, m in ipairs(members) do
                if MemberHit(m) then hits[#hits + 1] = m end
            end
            if #hits == 0 and not Hit(layout) then return end
            -- Matched by its own name only: listed as it is.
            if #hits > 0 then
                members, open = hits, true
            end
        end
        list[#list + 1] = { kind = "layout", rec = layout, notLoaded = notLoaded, open = open }
        if open then
            -- The layout's own member order, kinds mixed; free icons are plain children.
            for _, m in ipairs(members) do
                if m.type == "group" then
                    list[#list + 1] = { kind = "group", rec = m }
                elseif m.type == "icon" then
                    list[#list + 1] = { kind = "freeicon", rec = m, layout = layout }
                else
                    list[#list + 1] = { kind = "bar", rec = m }
                end
            end
            if not filter then list[#list + 1] = { kind = "addchild", rec = layout } end
        end
    end
    -- Layouts that fail their load conditions here still list, dimmed, under their
    -- own header.
    local loadedL, notLoadedL = {}, {}
    for _, layout in ipairs(Store.Layouts()) do
        if Store.IsLoaded(layout) then
            loadedL[#loadedL + 1] = layout
        else
            notLoadedL[#notLoadedL + 1] = layout
        end
    end
    for _, l in ipairs(loadedL) do AddLayout(l, false) end
    if #notLoadedL > 0 then
        -- The header counts the unloaded layouts a search kept; none kept = no header.
        local at, before = #list + 1, #list
        for _, l in ipairs(notLoadedL) do AddLayout(l, true) end
        local n = 0
        for i = before + 1, #list do
            if list[i].kind == "layout" then n = n + 1 end
        end
        if n > 0 then table.insert(list, at, { kind = "nlhdr", count = n }) end
    end
    if not filter then list[#list + 1] = { kind = "newlayout" } end
    return list
end

local function RefreshRail()
    local list = BuildRailList()
    -- inside the scrolling list, which starts under the LAYOUTS caption
    local y = -6
    -- Every thumbnail mode is centered in one 22px slot so the names line up. Call
    -- after the thumb's mode is set: the centering reads its width.
    local function Child(row, rec, indent)
        row._dim = (not Store.IsLoaded(rec)) or nil
        -- the eye sits just left of the kind pill (PillRight places the pill)
        row.eye:ClearAllPoints()
        row.eye:SetPoint("RIGHT", row.pill, "LEFT", -2, 0)
        Options.PaintEye(row.eye, rec)
        row.guide:Show()
        row.thumb:Show()
        row.thumb:ClearAllPoints()
        row.thumb:SetPoint("LEFT", indent + (22 - row.thumb:GetWidth()) / 2, 0)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", indent + 28, 0)
        row.name:SetPoint("RIGHT", -8, 0)
        row.name:SetText(rec.name)
    end
    local function PillRight(row)
        row.pill:Show()
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -5, 0)
        row.name:SetPoint("RIGHT", row.eye:IsShown() and row.eye or row.pill, "LEFT", -3, 0)
    end
    for i, item in ipairs(list) do
        local row = RailRow(i)
        -- Air above every header but the first.
        if i > 1 and (item.kind == "layout" or item.kind == "nlhdr"
            or item.kind == "newlayout") then
            y = y - 5
        end
        local h = (item.kind == "layout") and 26 or 24
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, y)
        -- -5: clear of the scroll bar's lane at the list's right edge
        row:SetPoint("TOPRIGHT", -5, y)
        row._railTop = -y
        y = y - h - 1
        row:Show()
        row._dim = nil
        row.chev:Hide()
        row.guide:Hide()
        row.pill:Hide()
        row.eye:Hide()
        row.badge:Hide()
        row.thumb:Hide()
        row.edit:Hide()
        row.export:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetPoint("RIGHT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row:SetScript("OnClick", nil)
        -- Read by the drag-and-drop hit test.
        row._item = item
        row:SetScript("OnDragStart", nil)
        row:SetScript("OnDragStop", nil)

        if item.kind == "layout" then
            local rec = item.rec
            row.chev:Show()
            row.chev:ClearAllPoints()
            row.chev:SetPoint("LEFT", 6, 0)
            -- A search opens a layout to its matches.
            row.chev:SetDown(item.open and true or false)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 22, 0)
            row.name:SetText(rec.name)
            local selected = ui.selType == "layout" and ui.selId == rec.id
            -- The conditions badge says why a dimmed layout is not loaded here.
            row._dim = item.notLoaded or nil
            PaintRailRow(row, selected, "layout")
            if selected then
                row.name:SetPoint("RIGHT", -84, 0)
                row.edit:Show()
                row.export:Show()
            else
                -- The badge truncates in its own span so a long condition list never runs
                -- under the name.
                row.name:SetPoint("RIGHT", -104, 0)
                local text = Store.BadgeText(rec)
                row.badge:SetWidth(92)
                row.badge:SetText(text)
                row.badge:SetTextColor(SHR[1], SHR[2], SHR[3])
                row.badge:Show()
            end
            -- An unloaded layout's eye sits left of its buttons (selected) or its badge.
            if item.notLoaded then
                row.eye:ClearAllPoints()
                row.eye:SetPoint("RIGHT", selected and row.export or row.badge, "LEFT", -4, 0)
                Options.PaintEye(row.eye, rec)
                row.name:SetPoint("RIGHT", row.eye, "LEFT", -4, 0)
            end
            row.edit:SetScript("OnClick", function() Options.Select("layout", rec.id) end)
            row.export:SetScript("OnClick", function() Options.OpenExport(rec.id) end)
            row:SetScript("OnClick", function()
                ExpandedSet()[rec.id] = not ExpandedSet()[rec.id] or nil
                Options.Select("layout", rec.id)
            end)
        elseif item.kind == "nlhdr" then
            -- Everything below this divider fails its load conditions on this character.
            row.name:SetText("NOT LOADED  (" .. (item.count or 0) .. ")")
            PaintRailRow(row, false, "label")
        elseif item.kind == "group" then
            local rec = item.rec
            row.thumb:SetGroup(rec.groupKind == "aura" and PURPLE or YELLOW)
            Child(row, rec, 20)
            GroupPill(row.pill, rec.groupKind)
            PillRight(row)
            PaintRailRow(row, ui.selType == "group" and ui.selId == rec.id, "child")
            row:SetScript("OnClick", function() Options.Select("group", rec.id) end)
            RailDD.Make(row)
        elseif item.kind == "bar" then
            local rec = item.rec
            row.thumb:SetBar(rec, 22)
            Child(row, rec, 20)
            BarPill(row.pill, rec.barKind, rec.barMode)
            PillRight(row)
            PaintRailRow(row, ui.selType == "bar" and ui.selId == rec.id, "child")
            row:SetScript("OnClick", function() Options.Select("bar", rec.id) end)
            RailDD.Make(row)
        elseif item.kind == "freeicon" then
            local rec = item.rec
            row.thumb:SetIcon(Factory.GetTexture(rec))
            Child(row, rec, 20)
            row.pill:Set(Options.IconPillText(rec.kind))
            PillRight(row)
            local selected = ui.selType == "free" and ui.selId == item.layout.id
                and ui.selIconId == rec.id
            PaintRailRow(row, selected, "child")
            row:SetScript("OnClick", function()
                ui.selIconId = rec.id
                Options.Select("free", item.layout.id)
            end)
            RailDD.Make(row)
        elseif item.kind == "addchild" then
            row.guide:Show()
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 20, 0)
            row.name:SetPoint("RIGHT", -8, 0)
            -- Short on purpose: a layout name would push this narrow row into an ellipsis.
            row.name:SetText("+ Add New")
            PaintRailRow(row, false, "add")
            local rec = item.rec
            row:SetScript("OnClick", function() Options.OpenAdd(rec.id) end)
        elseif item.kind == "newlayout" then
            row.name:SetJustifyH("CENTER")
            row.name:SetText("+ New Layout")
            PaintRailRow(row, false, "addbtn")
            row:SetScript("OnClick", function()
                local rec = Store.NewLayout()
                ExpandedSet()[rec.id] = true
                Options.Select("layout", rec.id)
            end)
        end
    end
    for i = #list + 1, #railRows do railRows[i]:Hide() end
    Options.RailFit(-y + 6, #list)
end

-- Sizes the scrolling list to its rows. Only when the selection changed does it
-- scroll, just enough to show the selected row, so a hand scroll is kept.
function Options.RailFit(h, n)
    local host, lf = Options.railHost, Options.railList
    if not (host and lf) then return end
    local w = host:GetWidth() or 0
    if w > 0 then lf:SetWidth(w) end
    lf:SetHeight(math.max(1, h))
    host:UpdateScroll()
    local key = tostring(ui.selType) .. ":" .. tostring(ui.selId) .. ":" .. tostring(ui.selIconId)
    if key == Options.railSelKey then return end
    local sel
    for i = 1, n do
        if railRows[i]._sel then
            sel = railRows[i]
            break
        end
    end
    if not sel then
        Options.railSelKey = key
        return
    end
    -- not laid out yet (the first pass): the next pass tries again
    local viewH = host:GetHeight() or 0
    if viewH <= 0 then return end
    Options.railSelKey = key
    local top = sel._railTop or 0
    local bottom = top + (sel:GetHeight() or 24)
    local cur = host:GetVerticalScroll() or 0
    if top < cur then
        cur = top - 6
    elseif bottom > cur + viewH then
        cur = bottom - viewH + 6
    else
        return
    end
    host:SetVerticalScroll(math.max(0, math.min(cur, math.max(0, h - viewH))))
    host:UpdateScroll()
end

-- Panes

local layoutPane, layoutHeader, layoutRowsAnchor, layoutEditorPage
local groupPane, groupHeader, groupStrip, switchStrip, groupEditorPage, iconEditorPage
local freePane, freeHeader, freeStrip
local barPane, barHeader, barEditorPage
-- The live icon preview is its own pane, pinned above the icon editor (BuildPreviewPane).

local function MakeHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", 0, 0)
    h:SetHeight(30)
    h.name = h:CreateFontString(nil, "OVERLAY")
    h.name:SetFont(STANDARD_TEXT_FONT, 15, "")
    h.name:SetPoint("LEFT", 4, 0)
    h.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    h.sub = h:CreateFontString(nil, "OVERLAY")
    h.sub:SetFont(STANDARD_TEXT_FONT, 10, "")
    h.sub:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    h.chip1 = HeaderChip(h)
    h.chip2 = HeaderChip(h)
    h.chip1:SetPoint("LEFT", h.name, "RIGHT", 8, 0)
    h.chip2:SetPoint("LEFT", h.chip1, "RIGHT", 5, 0)
    h.sub:SetPoint("LEFT", h.chip2, "RIGHT", 8, 0)
    return h
end

-- Layout page cards, one per element: a strip card (icon groups) puts a header
-- over a full-width well of member art; an art card (free icons, bars) leads
-- with the art. Both carry a 2px kind-colour stripe down the left edge.
local CARD_STRIP_H, CARD_ART_H, CARD_GAP = 74, 46, 6
local TILE, TILE_STEP = 26, 30
local CARD_BAR_THUMB_W = 72   -- spell art + mini bar

local function LayoutMemberRow(i)
    local row = layoutRowPool[i]
    if row then return row end
    row = CreateFrame("Frame", nil, layoutPane.cardsContent or layoutPane, "BackdropTemplate")
    AT.Skin(row, COL.well, COL.line)
    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT", 1, -1)
    row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    row.stripe:SetWidth(2)
    row.thumb = MakeThumb(row, 20, 24)
    row.thumbHit = CreateFrame("Button", nil, row)
    row.thumbHit:SetAllPoints(row.thumb)
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(STANDARD_TEXT_FONT, 12, "")
    row.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    row.pill = KindPill(row)
    row.pill:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.sub = row:CreateFontString(nil, "OVERLAY")
    row.sub:SetFont(STANDARD_TEXT_FONT, 10, "")
    row.sub:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row.edit = AT.MakeSmallButton(row, "Edit", 46)
    row.edit:SetHeight(20)
    row.del = AT.MakeQuietButton(row, "Delete", 56)
    row.del:SetHeight(20)
    row.del:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
    row.badge = row:CreateFontString(nil, "OVERLAY")
    row.badge:SetFont(STANDARD_TEXT_FONT, 9, "")
    row.badge:SetPoint("RIGHT", row.del, "LEFT", -8, 0)
    row.badge:SetTextColor(SHR[1], SHR[2], SHR[3])
    row.capsule = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.capsule:SetPoint("TOPLEFT", 10, -32)
    row.capsule:SetPoint("BOTTOMRIGHT", -8, 8)
    row.more = row.capsule:CreateFontString(nil, "OVERLAY")
    row.more:SetFont(STANDARD_TEXT_FONT, 10, "")
    row.more:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row.empty = row.capsule:CreateFontString(nil, "OVERLAY")
    row.empty:SetFont(STANDARD_TEXT_FONT, 10, "")
    row.empty:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row.empty:SetText("Nothing here yet - add the first icon")
    row.caps = {}
    layoutRowPool[i] = row
    return row
end

-- shape a pooled card: strip = true (header over the member well) or false
-- (leading art tile). Returns the card height.
local function ShapeCard(row, strip, color, thumbed, thumbW)
    row.stripe:SetColorTexture(color[1], color[2], color[3], 0.85)
    row.name:ClearAllPoints()
    row.sub:ClearAllPoints()
    row.edit:ClearAllPoints()
    row.thumb:ClearAllPoints()
    row.thumb:SetShown(thumbed and true or false)
    row.thumbHit:SetShown(not strip)
    if strip then
        row.thumb:SetPoint("TOPLEFT", 11, -5)
        row.name:SetPoint("TOPLEFT", thumbed and 44 or 12, -10)
        row.sub:SetPoint("LEFT", row.pill, "RIGHT", 8, 0)
        row.edit:SetPoint("TOPRIGHT", -8, -6)
        row:SetHeight(CARD_STRIP_H)
        return CARD_STRIP_H
    end
    row.capsule:Hide()
    row.thumb:SetPoint("LEFT", 10, 0)
    -- the name sits right beside the thumb (bars 72 wide, free icons 30)
    local nameX = 10 + (thumbW or CARD_BAR_THUMB_W) + 10
    row.name:SetPoint("TOPLEFT", nameX, -9)
    row.sub:SetPoint("TOPLEFT", nameX, -27)
    row.edit:SetPoint("RIGHT", -8, 0)
    row:SetHeight(CARD_ART_H)
    return CARD_ART_H
end

-- the member well: as many tiles as the card's width holds, then "+N more";
-- the "+" add tile always keeps its slot at the end
local function FillCapsule(row, icons, borderColor, addFn, cardW)
    row.capsule:Show()   -- pooled rows: a bar card may have hidden it
    AT.Skin(row.capsule, COL.bg, borderColor or COL.arcDeep)
    local slots = math.max(2, math.floor((cardW - 18 - 8) / TILE_STEP))
    local room = slots - (addFn and 1 or 0)
    local shown = #icons
    if shown > room then shown = math.max(room - 2, 1) end   -- leave the "+N more" span
    for i = 1, shown do
        local t = row.caps[i]
        if not t then
            t = IconButton(row.capsule, TILE)
            t:SetScript("OnClick", function(s)
                if s._rec then Options.SelectIconHome(s._rec) end
            end)
            t:SetScript("OnEnter", function(s)
                s:SetSelected(true)
                if s._rec then
                    GameTooltip:SetOwner(s, "ANCHOR_TOP")
                    GameTooltip:AddLine(s._rec.name or "", 1, 1, 1)
                    GameTooltip:AddLine("Click to edit this icon", 0.75, 0.82, 0.92)
                    GameTooltip:Show()
                end
            end)
            t:SetScript("OnLeave", function(s)
                s:SetSelected(false)
                GameTooltip:Hide()
            end)
            row.caps[i] = t
        end
        t._rec = icons[i]
        t:ClearAllPoints()
        t:SetPoint("LEFT", 4 + (i - 1) * TILE_STEP, 0)
        t.tex:SetTexture(Factory.GetTexture(icons[i]))
        t:SetSelected(false)
        t:Show()
    end
    for i = shown + 1, #row.caps do row.caps[i]:Hide() end
    if not row.addTile then
        local b = CreateFrame("Button", nil, row.capsule, "BackdropTemplate")
        b:SetSize(TILE, TILE)
        AT.Skin(b, COL.box, COL.arcDeep)
        b.fs = b:CreateFontString(nil, "OVERLAY")
        b.fs:SetFont(STANDARD_TEXT_FONT, 15, "")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText("+")
        b.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        b:SetScript("OnEnter", function(s)
            s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        end)
        b:SetScript("OnLeave", function(s)
            s:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
        end)
        AT.Tooltip(b, "Add an icon", "Opens the Add window aimed at this element.")
        row.addTile = b
    end
    row.addTile:ClearAllPoints()
    row.addTile:SetPoint("LEFT", 4 + shown * TILE_STEP, 0)
    row.addTile:SetScript("OnClick", addFn)
    row.addTile:SetShown(addFn ~= nil)
    local x = 4 + (shown + (addFn and 1 or 0)) * TILE_STEP
    row.more:ClearAllPoints()
    row.more:SetPoint("LEFT", x + 4, 0)
    row.more:SetText("+" .. (#icons - shown) .. " more")
    row.more:SetShown(#icons > shown)
    row.empty:ClearAllPoints()
    row.empty:SetPoint("LEFT", x + 4, 0)
    row.empty:SetShown(#icons == 0)
end

-- Tiles view of the contents list (setting layoutView: nil = tiles, "cards" =
-- cards): one square per element with its kind stripe, art and name. Hover
-- shows a delete X; an element that does not load here wears the eye.
Options.LAYOUT_TILE = { w = 84, h = 80, gap = 6 }

function Options.LayoutTileCols(width)
    local T = Options.LAYOUT_TILE
    return math.max(1, math.floor(((width or 0) + T.gap) / (T.w + T.gap)))
end

function Options.LayoutTile(i)
    local pool = layoutPane.tilePool
    if not pool then
        pool = {}
        layoutPane.tilePool = pool
    end
    local t = pool[i]
    if t then return t end
    local T = Options.LAYOUT_TILE
    t = CreateFrame("Button", nil, layoutPane.cardsContent, "BackdropTemplate")
    t:SetSize(T.w, T.h)
    AT.Skin(t, COL.well, COL.line)
    t.stripe = t:CreateTexture(nil, "ARTWORK")
    t.stripe:SetPoint("TOPLEFT", 1, -1)
    t.stripe:SetPoint("TOPRIGHT", -1, -1)
    t.stripe:SetHeight(2)
    t.thumb = MakeThumb(t, 18, 30)
    t.cells = {}
    for c = 1, 6 do
        local x = t:CreateTexture(nil, "ARTWORK")
        x:SetSize(14, 14)
        x:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        x:SetPoint("TOPLEFT", t, "TOP", -23 + ((c - 1) % 3) * 16, -13 - math.floor((c - 1) / 3) * 16)
        x:Hide()
        t.cells[c] = x
    end
    t.name = t:CreateFontString(nil, "OVERLAY")
    t.name:SetFont(STANDARD_TEXT_FONT, 11, "")
    t.name:SetPoint("BOTTOMLEFT", 5, 10)
    t.name:SetPoint("BOTTOMRIGHT", -5, 10)
    t.name:SetJustifyH("CENTER")
    t.name:SetWordWrap(false)
    t.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    t.x = CreateFrame("Button", nil, t)
    t.x:SetSize(16, 18)
    t.x:SetPoint("TOPRIGHT", -2, -5)
    t.x.fs = t.x:CreateFontString(nil, "OVERLAY")
    t.x.fs:SetFont(STANDARD_TEXT_FONT, 13, "")
    t.x.fs:SetPoint("CENTER", 0, 1)
    t.x.fs:SetText("x")
    t.x.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    t.x:SetScript("OnEnter", function(self)
        self.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    end)
    t.x:SetScript("OnLeave", function(self)
        self.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    end)
    t.x:SetScript("OnClick", function()
        AT.CloseDropdown()
        if t._rec then Options.ConfirmDelete(t._rec) end
    end)
    AT.Tooltip(t.x, "Delete", function()
        return "Delete " .. ((t._rec and t._rec.name) or "this") .. " from the layout. You are asked to confirm first."
    end)
    t.eye = Options.MakeEye(t)
    t.eye:SetPoint("TOPRIGHT", -18, -5)
    -- hover: the border lights and the X shows while the cursor is anywhere
    -- on the tile, its buttons included (IsMouseOver covers the children,
    -- so moving onto the X or the eye never flickers it away)
    function t.Hot(on)
        if on then
            t:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            t:SetAlpha(1)
        else
            t:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
            t:SetAlpha(t._alpha or 1)
        end
        t.x:SetShown(on)
    end
    t.Hot(false)
    t:SetScript("OnEnter", function() t.Hot(true) end)
    t:SetScript("OnLeave", function()
        if not t:IsMouseOver() then t.Hot(false) end
    end)
    t:SetScript("OnHide", function() t.Hot(false) end)
    t:SetScript("OnClick", function()
        AT.CloseDropdown()
        if t._open then t._open() end
    end)
    for _, b in ipairs({ t.x, t.eye }) do
        b:HookScript("OnLeave", function()
            if not t:IsMouseOver() then t.Hot(false) end
        end)
    end
    -- Hooked after the SetScript calls above, which would otherwise replace it.
    AT.Tooltip(t, function() return t._rec and t._rec.name or "" end,
        function() return t._tip end)
    pool[i] = t
    return t
end

function Options.FillLayoutTile(t, rec)
    t._rec = rec
    local th = t.thumb
    th:ClearAllPoints()
    for _, c in ipairs(t.cells) do c:Hide() end
    local color, kindLine
    if rec.type == "group" then
        local aura = rec.groupKind == "aura"
        color = aura and PURPLE or YELLOW
        local icons = Store.IconsOf(rec)
        if #icons == 0 then
            th:SetGroup(color)
            th:SetPoint("TOP", 0, -14)
            th:Show()
        else
            th:Hide()
            for c = 1, math.min(6, #icons) do
                t.cells[c]:SetTexture(Factory.GetTexture(icons[c]))
                t.cells[c]:Show()
            end
        end
        kindLine = (aura and "Aura group" or "CD group") .. "  -  "
            .. (#icons == 1 and "1 icon" or (#icons .. " icons"))
        t._open = function() Options.Select("group", rec.id) end
    elseif rec.type == "icon" then
        local text
        text, color = Options.IconPillText(rec.kind)
        th:SetIcon(Factory.GetTexture(rec), 34)
        th:SetPoint("TOP", 0, -12)
        th:Show()
        -- "Aura icon", like the group tiles' "Aura group"
        kindLine = (text == "Icon") and "Free icon" or text:gsub(" Icon$", " icon")
        t._open = function() Options.SelectIconHome(rec) end
    else
        local text
        text, color = BarPillText(rec.barKind, rec.barMode)
        th:SetBar(rec, 64, BarTexture(rec))
        th:SetPoint("TOP", 0, -20)
        th:Show()
        kindLine = text:find("Bar") and text or (text .. " bar")
        t._open = function() Options.Select("bar", rec.id) end
    end
    t.stripe:SetColorTexture(color[1], color[2], color[3], 0.85)
    t.name:SetText(rec.name or "?")
    -- Not loaded here: the eye says so, so the tile keeps full alpha.
    local loaded = Store.IsLoaded(rec)
    t._alpha = 1
    Options.PaintEye(t.eye, rec)
    t._tip = kindLine .. "\nLoad conditions: " .. (Store.BadgeText(rec))
        .. (loaded and "" or "  -  not loaded on this character. Its eye shows it while you edit")
        .. "\nClick to edit it. The x in the corner deletes it."
    t.Hot(false)
end

-- Lays the members out as tiles; returns the y under the grid and the count.
function Options.FlowLayoutTiles(layout, width)
    local T = Options.LAYOUT_TILE
    local cols = Options.LayoutTileCols(width)
    local n = 0
    for _, m in ipairs(Store.MembersOf(layout)) do
        n = n + 1
        local t = Options.LayoutTile(n)
        Options.FillLayoutTile(t, m)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", ((n - 1) % cols) * (T.w + T.gap),
            -math.floor((n - 1) / cols) * (T.h + T.gap))
        t:Show()
    end
    local pool = layoutPane.tilePool or {}
    for i = n + 1, #pool do pool[i]:Hide() end
    -- the width these columns were flowed for: the pane's resize handler
    -- re-flows only when a new width changes the column count
    layoutPane._tileW = width
    return -math.ceil(n / cols) * (T.h + T.gap), n
end

local function RefreshLayoutPane()
    local layout = SelLayout()
    if not layout then return end
    layoutHeader.name:SetText(layout.name)
    local btext, restricted = Store.BadgeText(layout)
    layoutHeader.chip1:Set(btext, restricted and PURPLE or SHR)
    layoutHeader.chip2:Set("layout", COL.dim)
    layoutHeader.sub:SetText("")

    -- the pane's own width is unresolved on the first pass after a build:
    -- fall back to the window (explicit size, always real)
    local host, cardsContent = layoutPane.cardsHost, layoutPane.cardsContent
    local cardW = host:GetWidth() or 0
    if cardW < 100 then
        cardW = (win:GetWidth() or 1020) - ((rail and rail:IsShown()) and rail:GetWidth() or 18) - 37
    end
    cardsContent:SetWidth(cardW)
    local tiles = Store.GetSetting("layoutView") ~= "cards"
    if layoutPane.PaintViewChips then layoutPane.PaintViewChips() end

    -- One card per member, in the layout's own order (the rail drag sets it).
    local y = 0
    local n = 0
    local function Card(strip, color, thumbed, thumbW)
        n = n + 1
        local row = LayoutMemberRow(n)
        local h = ShapeCard(row, strip, color, thumbed, thumbW)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", -4, y)
        y = y - h - CARD_GAP
        row:Show()
        return row
    end
    local function GroupCard(g)
        local aura = g.groupKind == "aura"
        local row = Card(true, aura and PURPLE or YELLOW, true)
        row.name:SetText(g.name)
        local icons = Store.IconsOf(g)
        row.thumb:SetGroup(aura and PURPLE or YELLOW)
        row.sub:SetText("Icon group  -  " .. (#icons == 1 and "1 icon" or (#icons .. " icons")))
        GroupPill(row.pill, g.groupKind)
        FillCapsule(row, icons, aura and { 0.29, 0.23, 0.42 } or { 0.35, 0.29, 0.16 },
            function() Options.OpenAdd(layout.id, g.id) end, cardW)
        row.badge:SetText((Store.BadgeText(g)))
        -- only Edit and the tiles navigate; the card body stays inert so a
        -- stray click never yanks the view away from the layout
        row.edit:SetScript("OnClick", function() Options.Select("group", g.id) end)
        row.del:SetScript("OnClick", function() Options.ConfirmDelete(g) end)
    end
    local function IconCard(ic)
        local ptext, pcolor = Options.IconPillText(ic.kind)
        local row = Card(false, pcolor, true, 30)
        row.name:SetText(ic.name)
        local d = ic.driver or {}
        local what = (ic.kind == "item" and d.itemID and ("item " .. d.itemID))
            or (ic.kind == "trinket" and d.slotID and ("trinket slot " .. d.slotID))
            or (ic.kind == "totem" and ("totem slot " .. (d.slot or 1)))
            or (ic.kind == "ammo" and "equipped ammo")
            or (ic.kind == "aura" and d.spellID and Options.AuraSummary(d))
            or (d.spellID and ("spell " .. d.spellID))
            or ic.kind or ""
        row.sub:SetText("Free icon  -  " .. what .. ", keeps its own position")
        row.pill:Set(ptext, pcolor)
        row.thumb:SetIcon(Factory.GetTexture(ic), 30)
        row.thumbHit:SetScript("OnClick", function() Options.SelectIconHome(ic) end)
        row.badge:SetText((Store.BadgeText(ic)))
        row.edit:SetScript("OnClick", function() Options.SelectIconHome(ic) end)
        row.del:SetScript("OnClick", function() Options.ConfirmDelete(ic) end)
    end
    local function BarCard(b)
        local _, color = BarPillText(b.barKind, b.barMode)
        local row = Card(false, color, true)
        row.name:SetText(b.name)
        local d = b.driver or {}
        if b.barKind == "stack" then
            row.sub:SetText("Stack bar  -  " .. PowerLabel(d.powerType or 0) .. " stacks")
        elseif b.barKind == "timer" then
            row.sub:SetText("Timer bar  -  " .. tostring(d.duration or "?") .. "s")
        elseif b.barKind == "swing" then
            row.sub:SetText("Swing bar  -  " .. SwingLabel(d.swingType or 0))
        elseif b.barKind == "aura" then
            row.sub:SetText("Aura bar  -  " .. (b.barMode == "stack" and "stacks" or "duration")
                .. " of aura " .. tostring(d.spellID or "?"))
        elseif b.barKind == "resource" then
            -- A resource bar shows its power (Auto = the current one).
            local pt = d.powerType
            row.sub:SetText("Resource bar  -  "
                .. ((pt == nil or pt == POWER_AUTO) and "current power" or PowerLabel(pt)))
        elseif b.barKind == "health" then
            row.sub:SetText("Health bar  -  " .. Options.HealthUnitLabel(d.unit))
        elseif b.barKind == "cast" then
            row.sub:SetText("Castbar  -  " .. Options.HealthUnitLabel(d.unit))
        else
            row.sub:SetText("Cooldown bar  -  " .. (b.barMode == "stack" and "charges" or "duration")
                .. " of spell " .. tostring(d.spellID or "?"))
        end
        BarPill(row.pill, b.barKind, b.barMode)
        row.thumb:SetBar(b, CARD_BAR_THUMB_W, BarTexture(b))
        row.thumbHit:SetScript("OnClick", function() Options.Select("bar", b.id) end)
        row.badge:SetText((Store.BadgeText(b)))
        row.edit:SetScript("OnClick", function() Options.Select("bar", b.id) end)
        row.del:SetScript("OnClick", function() Options.ConfirmDelete(b) end)
    end
    if tiles then
        y, n = Options.FlowLayoutTiles(layout, cardW)
    else
        for _, m in ipairs(Store.MembersOf(layout)) do
            if m.type == "group" then
                GroupCard(m)
            elseif m.type == "icon" then
                IconCard(m)
            else
                BarCard(m)
            end
        end
        for _, t in ipairs(layoutPane.tilePool or {}) do t:Hide() end
    end
    -- the Tiles view hides every card; the Cards view only the spare ones
    for i = (tiles and 1 or n + 1), #layoutRowPool do layoutRowPool[i]:Hide() end

    layoutAddRow:ClearAllPoints()
    layoutAddRow:SetPoint("TOPLEFT", 0, y)
    layoutAddRow:SetPoint("TOPRIGHT", -4, y)
    layoutAddRow:Show()
    y = y - 34

    -- Natural height; PlaceList applies the cap, the saved height and the fold.
    cardsContent:SetHeight(math.max(1, -y))
    layoutPane.listNatural = -y
    layoutPane.contentsLabel:SetText("CONTENTS  -  " .. n .. (n == 1 and " element" or " elements")
        .. ((Store.GetSetting("layoutListFolded") == true) and "  (folded)" or ""))
    layoutPane.PlaceList(nil)
end

-- Editor band actions on the "Editing: <name>" band of every editor: Rename
-- (an edit box in place; Enter or clicking away saves, Escape cancels),
-- Duplicate, Export and Move to; the editor follows a moved record.

-- host: the band frame. nameFS: the "Editing: name" text the rename box covers.
-- getRec(): the record. opts.rightOf: a control to sit left of; opts.hide:
-- regions hidden while renaming; opts.noMove: no Move to. The Move helpers
-- are inner locals because of the 200-local limit.
local function BandActions(host, nameFS, getRec, opts)
    opts = opts or {}
    local function MoveTargets(rec)
        local items = { { value = 0, text = "Move to..." } }
        if not rec or rec.type == "layout" then return items end
        local isIcon = rec.type == "icon"
        for _, lay in ipairs(Store.Layouts()) do
            local here
            if isIcon then
                here = not rec.groupId and rec.layoutId == lay.id
            else
                here = rec.layoutId == lay.id
            end
            if not here then
                items[#items + 1] = { value = "L" .. lay.id,
                    text = (isIcon and "Free in " or "") .. lay.name }
            end
            if isIcon then
                local groups = Store.ChildrenOf(lay)
                for _, g in ipairs(groups) do
                    if g.id ~= rec.groupId and (g.groupKind ~= "aura" or rec.kind == "aura") then
                        items[#items + 1] = { value = "G" .. g.id, text = lay.name .. " / " .. g.name }
                    end
                end
            end
        end
        return items
    end
    local function MoveTo(rec, value)
        if not (rec and type(value) == "string") then return end
        local kind, id = value:sub(1, 1), tonumber(value:sub(2))
        if not id then return end
        if kind == "G" then
            if not Store.MoveIcon(rec.id, id) then return end
            SelectRecord(rec)
        elseif kind == "L" then
            if not Store.MoveToLayout(rec.id, id) then return end
            ExpandedSet()[id] = true
            SelectRecord(rec)
        end
    end
    local edge = opts.rightOf
    local function Place(b)
        if edge then
            b:SetPoint("RIGHT", edge, "LEFT", -5, 0)
        else
            b:SetPoint("RIGHT", host, "RIGHT", -6, 0)
        end
        edge = b
    end
    local function Btn(label, w, tip)
        local b = AT.MakeSmallButton(host, label, w)
        b:SetHeight(18)
        b.fs:SetFont(STANDARD_TEXT_FONT, 9, "")
        AT.Tooltip(b, label, tip)
        Place(b)
        return b
    end
    if not opts.noMove then
        local move = AT.MakeDropdown(win, host, 92,
            function() return MoveTargets(getRec()) end,
            function() return 0 end,
            function(v) MoveTo(getRec(), v) end)
        move:SetHeight(18)
        AT.Tooltip(move, "Move to", "Moves this into another layout - or, for an icon, into a group. Position and settings travel with it.")
        Place(move)
    end
    local exp = Btn("Export", 50, "Opens Import / Export with just this ticked and its share string ready to copy.")
    exp:SetScript("OnClick", function()
        local rec = getRec()
        if rec then Options.OpenExport(rec.id) end
    end)
    local dup = Btn("Duplicate", 62, "Makes a copy right beside this one - a layout or group with everything inside it.")
    dup:SetScript("OnClick", function()
        local rec = getRec()
        if rec then SelectRecord(Store.Duplicate(rec.id)) end
    end)
    local ren = Btn("Rename", 54, "Edits the name in place. Enter saves, Escape cancels.")

    local box = CreateFrame("EditBox", nil, host, "BackdropTemplate")
    box:SetHeight(20)
    box:SetPoint("LEFT", nameFS, "LEFT", -6, 0)
    box:SetPoint("RIGHT", ren, "LEFT", -10, 0)
    AT.Skin(box, COL.well)
    box:SetFont(STANDARD_TEXT_FONT, 12, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    box:Hide()
    local function SetEditing(on)
        nameFS:SetShown(not on)
        for _, r in ipairs(opts.hide or {}) do r:SetShown(not on) end
        box:SetShown(on)
    end
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function()
        box._cancel = true
        box:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function()
        if not box:IsShown() then return end
        local rec = getRec()
        if rec and not box._cancel then Store.Rename(rec.id, box:GetText()) end
        box._cancel = nil
        SetEditing(false)
    end)
    ren:SetScript("OnClick", function()
        local rec = getRec()
        if not rec then return end
        box:SetText(rec.name or "")
        SetEditing(true)
        box:SetFocus()
        box:HighlightText()
    end)
    return ren
end

-- Position rows: X / Y sliders for layouts (from the screen centre) and for
-- groups, bars and free icons (from their layout's centre). They edit rec.pos,
-- the numbers a drag on screen writes, unless anchoredFn(rec) is true.
function Options.PosRows(pg, ctx, vis, anchoredFn)
    -- An anchored thing is placed by its anchor offsets, so the sliders edit
    -- those (the numbers its Anchor tab shows) and X / Y always move it.
    local function anchored(r)
        return r ~= nil and anchoredFn ~= nil and anchoredFn(r) == true
    end
    local OFF = { x = "anchorOffsetX", y = "anchorOffsetY" }
    local function get(k)
        return function()
            local r = ctx()
            if not r then return 0 end
            if anchored(r) then return tonumber(Store.Resolve(r, "anchor", OFF[k])) or 0 end
            return (r.pos and tonumber(r.pos[k])) or 0
        end
    end
    local function set(k)
        return function(v)
            local r = ctx()
            if not r then return end
            local n = math.floor((tonumber(v) or 0) + 0.5)
            if anchored(r) then
                -- SetOverride marks the style dirty; the anchor post-pass
                -- re-places it and its dependents follow.
                Store.SetOverride(r, "anchor", OFF[k], n)
                return
            end
            r.pos = r.pos or {}
            r.pos[k] = n
            Store.Dirty("style", r.id)
        end
    end
    AT.RowSlider(pg, "Position X", get("x"), set("x"), -2000, 2000, 1, "%.0f", vis)
    AT.RowSlider(pg, "Position Y", get("y"), set("y"), -2000, 2000, 1, "%.0f", vis)
end

-- Every record anchored to ctx(), each with an Edit button. Page rows are
-- built once, so a pool of 12 shows the first twelve.
function Options.AnchoredHereRows(pg, ctx, vis)
    local function Deps()
        local r = ctx()
        if not (r and NS.Anchor and NS.Anchor.DependentsOf) then return {} end
        return NS.Anchor.DependentsOf(r)
    end
    local function KindWord(d)
        if d.type == "bar" then return (d.barKind or "bar") .. " bar" end
        if d.type == "group" then return "group" end
        return d.type or "?"
    end
    AT.Section(pg, "Anchored to this", { visibleFn = vis })
    AT.RowDesc(pg, "Nothing is anchored to this yet.", 20,
        function() return vis() and #Deps() == 0 end)
    for i = 1, 12 do
        local row = AT.AddRow(pg, 24, function() return vis() and Deps()[i] ~= nil end)
        local lbl = AT.RowLabel(row, "")
        local b = AT.MakeQuietButton(row, "Edit", 60)
        row._colLabel, row._colCtrl = lbl, b
        row._sync = function()
            local d = Deps()[i]
            if d then lbl:SetText((d.name or "?") .. "   (" .. KindWord(d) .. ")") end
        end
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            local d = Deps()[i]
            if d then SelectRecord(d) end
        end)
        AT.Tooltip(b, "Edit", "Opens it. Its own Anchor tab holds the link back to this one.")
    end
end

-- The Anchor tab's rows, shared by bars and free icons: one dropdown picks the
-- target and writes enabled, kind and target together, so a pick is never half
-- applied; a Frame name for frame picks; what it is pinned to now; then the
-- schema's point and offset rows. It opens its own section: after a block these
-- rows would land in that block's section, which the Anchor tab hides.
function Options.AnchorPickRows(pg, family, ctx, vis, fields, note)
    AT.Section(pg, "Anchor to", { visibleFn = vis })
    if note then AT.RowDesc(pg, note, 20, vis) end
    AT.RowDropdown(pg, win, "Anchor to",
        function() return NS.Anchor and NS.Anchor.PickGet(ctx()) or "none" end,
        function(v) if NS.Anchor then NS.Anchor.PickSet(ctx(), v) end end,
        function()
            local r = ctx()
            if not (r and NS.Anchor) then return { { value = "none", text = "None (free position)" } } end
            return NS.Anchor.PickList(r)
        end,
        vis)
    AT.RowInput(pg, "Frame name",
        function()
            local r = ctx()
            return r and (Store.Resolve(r, "anchor", "anchorTargetFrame") or "") or ""
        end,
        function(v)
            local r = ctx()
            if r then Store.SetOverride(r, "anchor", "anchorTargetFrame", v or "") end
        end,
        function()
            return vis() and NS.Anchor ~= nil and NS.Anchor.IsFramePick(ctx())
        end,
        "The global name of any frame, e.g. PlayerFrame. Left empty, or naming a frame that does not exist, falls back to the free position.",
        "PlayerFrame")
    local status = AT.AddRow(pg, 22, vis)
    local fs = status:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetPoint("RIGHT", -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    status._sync = function()
        local r = ctx()
        if not (r and NS.Anchor) then fs:SetText("") return end
        local on = NS.Anchor.IsEnabled(r) and NS.Anchor.ResolveTarget(r) ~= nil
        fs:SetText(NS.Anchor.DescribePick(r))
        if on then fs:SetTextColor(0.48, 0.85, 0.56)
        else fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3]) end
    end
    SectionRows(pg, family, "anchor", ctx, vis, fields)
end

-- After a delete the editor lands on the record's layout (or the empty pane).
function Options.ConfirmDelete(rec)
    if not rec then return end
    local what, extra = rec.type, ""
    if rec.type == "layout" then
        local n = #(rec.members or {})
        extra = " and everything inside it"
            .. ((n > 0) and (" (" .. n .. (n == 1 and " element)" or " elements)")) or "")
    elseif rec.type == "group" then
        local n = #(rec.members or {})
        extra = (n > 0) and (" and its " .. n .. (n == 1 and " icon" or " icons")) or ""
    elseif rec.type == "bar" then
        what = (rec.barKind or "") .. " bar"
    end
    StaticPopupDialogs["ARCUIV2_DELETE"] = StaticPopupDialogs["ARCUIV2_DELETE"] or {
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        preferredIndex = 3,
    }
    local d = StaticPopupDialogs["ARCUIV2_DELETE"]
    d.text = "Delete the " .. what .. " '" .. (rec.name or "?") .. "'" .. extra .. "?"
    d.OnAccept = function()
        local id, layoutId = rec.id, rec.layoutId
        if rec.type == "icon" and rec.groupId then
            local g = Store.Get(rec.groupId)
            layoutId = (g and g.layoutId) or layoutId
        end
        Store.Delete(id)
        if ui.selIconId == id then
            ui.selIconId = nil
            ui.grpMode = "grp"
        end
        if rec.type == "layout" then
            if ui.selId == id or not Store.Get(ui.selId or 0) then
                ui.selType, ui.selId = nil, nil
                ShowPane("empty")
            end
        elseif ui.selId == id or not Store.Get(ui.selId or 0) then
            if layoutId and Store.Get(layoutId) then
                Options.Select("layout", layoutId)
            else
                ui.selType, ui.selId = nil, nil
                ShowPane("empty")
            end
        end
        RefreshAll()
    end
    StaticPopup_Show("ARCUIV2_DELETE")
end

local function BuildLayoutPane()
    layoutPane = CreateFrame("Frame", nil, content)
    layoutPane:SetAllPoints()
    panes.layout = layoutPane
    layoutHeader = MakeHeader(layoutPane)

    local move = AT.MakeSmallButton(layoutPane, "Move on screen", 110)
    move:SetPoint("TOPRIGHT", -4, -2)
    move:SetScript("OnClick", function()
        Engine.SetMoveMode(not Engine.IsMoveMode())
        move.fs:SetText(Engine.IsMoveMode() and "Lock position" or "Move on screen")
    end)
    AT.Tooltip(move, "Move on screen", "Shows a drag handle on every layout. Drag it where you want, then lock.")
    local del = AT.MakeSmallButton(layoutPane, "Delete", 56)
    del:SetPoint("RIGHT", move, "LEFT", -5, 0)
    del:SetScript("OnClick", function() Options.ConfirmDelete(SelLayout()) end)
    local addBtn = AT.MakeSmallButton(layoutPane, "+ Add", 52)
    addBtn:SetPoint("RIGHT", del, "LEFT", -5, 0)
    addBtn.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    addBtn:SetScript("OnClick", function()
        local layout = SelLayout()
        if layout then Options.OpenAdd(layout.id) end
    end)

    -- The CONTENTS bar folds the list (cyan underline while folded). The list
    -- is capped and scrolls; the grip under it sets and saves its height.
    local bar = CreateFrame("Button", nil, layoutPane, "BackdropTemplate")
    bar:SetHeight(22)
    bar:SetPoint("TOPLEFT", 0, -36)
    bar:SetPoint("TOPRIGHT", -4, -36)
    AT.Skin(bar, COL.panel, COL.line)
    local chev = AT.MakeChevron(bar)
    chev:SetPoint("LEFT", 7, 0)
    chev:SetDown(true)
    local title = bar:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 11, "")
    title:SetPoint("LEFT", chev, "RIGHT", 6, 0)
    title:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    title:SetText("CONTENTS")
    local rule = bar:CreateTexture(nil, "OVERLAY")
    rule:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    rule:SetPoint("BOTTOMLEFT", 1, 1)
    rule:SetPoint("BOTTOMRIGHT", -1, 1)
    rule:SetHeight(1)
    rule:Hide()
    local function paintBar(hot)
        local c = hot and COL.ink or COL.arc
        title:SetTextColor(c[1], c[2], c[3])
        chev:SetColor(c)
        local f = hot and COL.btnHover or COL.panel
        bar:SetBackdropColor(f[1], f[2], f[3], 1)
    end
    bar:SetScript("OnEnter", function() paintBar(true) end)
    bar:SetScript("OnLeave", function() paintBar(false) end)
    bar:SetScript("OnClick", function()
        AT.CloseDropdown()
        local folded = Store.GetSetting("layoutListFolded") ~= true
        Store.SetSetting("layoutListFolded", folded)
        PlaySound(folded and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
                         or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
        RefreshLayoutPane()
    end)
    AT.Tooltip(bar, "Contents", "Click to fold the element list away so the layout's own settings get the whole page, or to bring it back. Drag the grip under the list to set how tall it is.")
    layoutPane.foldChevron, layoutPane.contentsLabel, layoutPane.foldRule = chev, title, rule
    -- Tiles | Cards switch. The chips are Buttons, so a click never reaches the
    -- bar's fold; built right to left so Tiles, the default, reads first.
    layoutPane.viewChips = {}
    local prevChip
    for _, v in ipairs({
        { key = "cards", text = "Cards",
          tip = "One card per element with its preview, kind, load conditions, Edit and Delete." },
        { key = "tiles", text = "Tiles",
          tip = "A grid of small tiles showing the art and the name. Click a tile to edit it. Hover it for its details, Edit and Delete." },
    }) do
        local c = CreateFrame("Button", nil, bar, "BackdropTemplate")
        c:SetHeight(16)
        AT.Skin(c, COL.well, COL.line)
        c.fs = c:CreateFontString(nil, "OVERLAY")
        c.fs:SetFont(STANDARD_TEXT_FONT, 10, "")
        c.fs:SetPoint("CENTER", 0, 0)
        c.fs:SetText(v.text)
        local tw = (c.fs.GetUnboundedStringWidth and c.fs:GetUnboundedStringWidth())
            or c.fs:GetStringWidth() or 28
        c:SetWidth(math.ceil(tw) + 18)
        c.under = c:CreateTexture(nil, "OVERLAY")
        c.under:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        c.under:SetPoint("BOTTOMLEFT", 1, 1)
        c.under:SetPoint("BOTTOMRIGHT", -1, 1)
        c.under:SetHeight(2)
        c.key = v.key
        if prevChip then
            c:SetPoint("RIGHT", prevChip, "LEFT", -3, 0)
        else
            c:SetPoint("RIGHT", -4, 0)
        end
        prevChip = c
        c:SetScript("OnClick", function(s)
            AT.CloseDropdown()
            local want = (s.key == "cards") and "cards" or nil
            if Store.GetSetting("layoutView") == want then return end
            Store.SetSetting("layoutView", want)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
            RefreshLayoutPane()
        end)
        c:SetScript("OnEnter", function(s)
            s:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
            s.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        end)
        c:SetScript("OnLeave", function() layoutPane.PaintViewChips() end)
        -- Hooked after SetScript, or the hover paint would replace it.
        AT.Tooltip(c, v.text, v.tip)
        layoutPane.viewChips[#layoutPane.viewChips + 1] = c
    end
    function layoutPane.PaintViewChips()
        local cur = (Store.GetSetting("layoutView") == "cards") and "cards" or "tiles"
        for _, c in ipairs(layoutPane.viewChips) do
            local on = c.key == cur
            local f, e, tc = COL.well, COL.line, COL.dim
            if on then f, e, tc = COL.box, COL.arcDeep, COL.arc end
            c:SetBackdropColor(f[1], f[2], f[3], 1)
            c:SetBackdropBorderColor(e[1], e[2], e[3], 1)
            c.fs:SetTextColor(tc[1], tc[2], tc[3])
            c.under:SetShown(on)
        end
    end
    layoutPane.PaintViewChips()
    local host, cardsContent = AT.MakeScroll(layoutPane)
    host:SetPoint("TOPLEFT", 0, -62)
    host:SetPoint("TOPRIGHT", -8, -62)
    host:SetHeight(1)
    host:HookScript("OnSizeChanged", function(_, w)
        if w and w > 0 then cardsContent:SetWidth(w) end
    end)
    layoutPane.cardsHost, layoutPane.cardsContent = host, cardsContent
    local grip = AT.MakeSplitter(layoutPane, "y", {
        onStart = function() layoutPane._listH0 = layoutPane.cardsHost:GetHeight() or 0 end,
        -- Dragging up is a positive delta and a shorter list.
        onDrag = function(d)
            layoutPane.PlaceList(math.floor((layoutPane._listH0 or 0) - d + 0.5), true)
        end,
        onStop = function()
            if layoutPane.listWant then Store.SetSetting("layoutListH", layoutPane.listWant) end
            RefreshLayoutPane()
        end,
    })
    AT.Tooltip(grip, "Resize", "Drag up or down to set how much of the page the element list takes.")
    layoutPane.listGrip = grip
    -- One placer for the list, grip and editor. h: the wanted list height
    -- (nil = the saved height, else ~45% of the pane); the editor keeps 180px.
    -- Before its first layout the pane has no height: use the window's.
    function layoutPane.PlaceList(h, fromDrag)
        local naturalH = layoutPane.listNatural or 0
        local paneH = layoutPane:GetHeight() or 0
        if paneH < 100 then paneH = (win:GetHeight() or 760) - 110 end
        local maxH = math.max(60, paneH - 62 - 12 - 180)
        local want = h or Store.GetSetting("layoutListH") or math.floor((paneH - 70) * 0.45)
        want = math.max(60, math.min(want, maxH))
        if fromDrag then
            if layoutPane.listWant == want then return end
            layoutPane.listWant = want
        end
        local folded = Store.GetSetting("layoutListFolded") == true
        local listH = folded and 0 or math.min(naturalH, want)
        host:SetHeight(math.max(1, listH))
        host:SetShown(not folded)
        host:UpdateScroll()
        grip:ClearAllPoints()
        grip:SetPoint("TOPLEFT", 0, -62 - listH)
        grip:SetPoint("TOPRIGHT", -4, -62 - listH)
        grip:SetShown(not folded)
        chev:SetDown(not folded)
        rule:SetShown(folded)
        layoutEditorPage:ClearAllPoints()
        layoutEditorPage:SetPoint("TOPLEFT", 0, -62 - listH - (folded and 4 or 12))
        layoutEditorPage:SetPoint("BOTTOMRIGHT", 0, 0)
        AT.LayoutPage(layoutEditorPage)
    end
    -- Re-place at most once per frame. A width that changes the tile column
    -- count re-flows the tiles (a full refresh); the refresh records that width,
    -- so this cannot loop.
    layoutPane:SetScript("OnSizeChanged", function(s)
        if s._placeQueued then return end
        s._placeQueued = true
        C_Timer.After(0, function()
            s._placeQueued = nil
            if not (s:IsShown() and SelLayout()) then return end
            if Store.GetSetting("layoutView") ~= "cards" then
                local w = layoutPane.cardsHost:GetWidth() or 0
                if w >= 100 and Options.LayoutTileCols(w) ~= Options.LayoutTileCols(layoutPane._tileW) then
                    RefreshLayoutPane()
                    return
                end
            end
            layoutPane.PlaceList(nil)
        end)
    end)

    layoutAddRow = CreateFrame("Button", nil, cardsContent, "BackdropTemplate")
    layoutAddRow:SetHeight(28)
    AT.Skin(layoutAddRow, COL.well, { 0.18, 0.34, 0.24 })
    layoutAddRow.fs = layoutAddRow:CreateFontString(nil, "OVERLAY")
    layoutAddRow.fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    layoutAddRow.fs:SetPoint("CENTER", 0, 0)
    layoutAddRow.fs:SetTextColor(0.482, 0.847, 0.561)
    layoutAddRow.fs:SetText("+ Add to this layout")
    layoutAddRow:SetScript("OnEnter", function(s)
        s:SetBackdropBorderColor(0.482, 0.847, 0.561, 1)
    end)
    layoutAddRow:SetScript("OnLeave", function(s)
        s:SetBackdropBorderColor(0.18, 0.34, 0.24, 1)
    end)
    layoutAddRow:SetScript("OnClick", function()
        local layout = SelLayout()
        if layout then Options.OpenAdd(layout.id) end
    end)
    layoutAddRow:Hide()

    layoutEditorPage = AT.NewPage(layoutPane)
    AT.MakeScrollable(layoutEditorPage)
    layoutEditorPage:Show()
    local pg = layoutEditorPage

    local hd = AT.AddRow(pg, 30)
    local hbg = CreateFrame("Frame", nil, hd, "BackdropTemplate")
    hbg:SetPoint("TOPLEFT", 0, 0)
    hbg:SetPoint("BOTTOMRIGHT", 0, 4)
    AT.Skin(hbg, COL.panel, COL.arcDeep)
    hd._fs = hbg:CreateFontString(nil, "OVERLAY")
    hd._fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    hd._fs:SetPoint("LEFT", 10, 0)
    hd._fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    hd._chip = KindPill(hbg)
    hd._chip:SetPoint("LEFT", hd._fs, "RIGHT", 8, 0)
    BandActions(hbg, hd._fs, SelLayout, { hide = { hd._chip }, noMove = true })
    hd._sync = function()
        local l = SelLayout()
        hd._fs:SetText("Editing:  " .. ((l and l.name) or ""))
        hd._chip:Set("layout", COL.dim)
    end

    -- The last three are the look tabs, filled by Options.BuildLayoutLooks
    -- once every item editor exists.
    local tabs = { "Position", "Mouse", "Anchoring", "Visibility", "Load Conditions",
        "Icon Looks", "Group Looks", "Bar Looks" }
    -- The settings search walks this page's tabs but not the look tabs, whose
    -- rows repeat the item editors' own.
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.layout = { page = pg,
        tabs = { "Position", "Mouse", "Anchoring", "Visibility", "Load Conditions" } }
    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel   -- strips inside panel-bodied pages
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local h = tabRow._strip:Set(tabs, ui.layoutTab, function(name)
            ui.layoutTab = name
            AT.LayoutPage(pg)
        end)
        -- wrapped chips grow the row (never overlap the content below)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Position tab: the layout's X / Y from the screen centre.
    local layPosVis = function() return ui.layoutTab == "Position" end
    AT.Section(pg, "Position", { visibleFn = layPosVis })
    Options.PosRows(pg, SelLayout, layPosVis, nil)
    AT.Section(pg, nil)
    ConditionRows(pg, SelLayout, function() return ui.layoutTab == "Load Conditions" end)
    -- A layout is what the others pin to; it cannot be anchored itself.
    local layAnchVis = function() return ui.layoutTab == "Anchoring" end
    AT.Section(pg, "Anchor to", { visibleFn = layAnchVis })
    AT.RowDesc(pg, "Layouts cannot be anchored yet; place them from the Position tab.", 20, layAnchVis)
    Options.AnchoredHereRows(pg, SelLayout, layAnchVis)
    AT.Section(pg, nil)
    VisibilityRows(pg, SelLayout, function() return ui.layoutTab == "Visibility" end)
    AT.RowDesc(pg, "Applies to every icon in this layout; groups and icons can override it.", 20,
        function() return ui.layoutTab == "Mouse" end)
    SectionRows(pg, "layout", "mouse", SelLayout,
        function() return ui.layoutTab == "Mouse" end,
        { "clickThrough", "showTooltip" })
end

-- Layout looks: the Icon / Group / Bar Looks tabs mirror the item editors'
-- blocks (Options.LookBlock), each with just the rows a layout can set
-- (Schema.Inherits), editing the layout through Store.LayoutProxy. A new look
-- needs only an `inherit` flag in the schema and a place in an item block.
Options.LOOK_TABS = {
    { family = "icon", tab = "Icon Looks", one = "icon", many = "icons" },
    { family = "iconGroup", tab = "Group Looks", one = "group", many = "groups" },
    { family = "bar", tab = "Bar Looks", one = "bar", many = "bars" },
}

-- The end of a mirrored block: what the layout sets here, how many items keep
-- their own value, Make them follow (asks first, with the count) and Clear.
function Options.LayoutLookStatus(pg, family, section, vis, fields, lt)
    local function Counts()
        local l = SelLayout()
        if not l then return 0, 0 end
        return Store.LayoutSetCount(l, family, section, fields),
            Store.LayoutOwnCount(l, family, section, fields)
    end
    local row = AT.AddRow(pg, 26, function()
        if not vis() then return false end
        return (Counts()) > 0
    end)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    local clear = AT.MakeQuietButton(row, "Clear", 60)
    clear:SetPoint("RIGHT", -12, 0)
    local follow = AT.MakeSmallButton(row, "Make them follow", 124)
    follow:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    row._adText, row._adClear, row._adFollow = fs, clear, follow
    row._sync = function()
        local setN, ownN = Counts()
        if setN == 0 then return end
        local head = "Set by this layout: " .. setN .. "."
        if ownN > 0 then
            fs:SetText(head .. "  " .. ownN .. " "
                .. (ownN == 1 and (lt.one .. " keeps its own value.") or (lt.many .. " keep their own values.")))
            fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            fs:SetPoint("RIGHT", follow, "LEFT", -8, 0)
            follow:Show()
        else
            fs:SetText(head .. "  Every " .. lt.one .. " here follows it.")
            fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
            fs:SetPoint("RIGHT", clear, "LEFT", -8, 0)
            follow:Hide()
        end
    end
    clear:SetScript("OnClick", function()
        AT.CloseDropdown()
        local l = SelLayout()
        if l and Store.ClearLayoutValues(l, family, section, fields) then AT.LayoutPage(pg) end
    end)
    follow:SetScript("OnClick", function()
        AT.CloseDropdown()
        local l = SelLayout()
        if not l then return end
        local _, ownN = Counts()
        if ownN == 0 then return end
        StaticPopupDialogs["ARCUIV2_FOLLOW"] = StaticPopupDialogs["ARCUIV2_FOLLOW"] or {
            button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
            preferredIndex = 3,
        }
        local d = StaticPopupDialogs["ARCUIV2_FOLLOW"]
        local one = ownN == 1
        d.text = ownN .. " " .. (one and lt.one or lt.many) .. " in '" .. (l.name or "?") .. "' "
            .. (one and "has its own value" or "have their own values")
            .. " for these settings. Reset " .. (one and "it so it follows" or "them so they follow")
            .. " the layout?"
        d.OnAccept = function()
            Store.FollowLayout(l, family, section, fields)
            RefreshAll()
        end
        StaticPopup_Show("ARCUIV2_FOLLOW")
    end)
    AT.Tooltip(clear, "Clear", "This layout stops setting these. Everything that followed it goes back to its own defaults.")
    AT.Tooltip(follow, "Make them follow", "Resets the items in this layout that set their own value here, so they follow the layout again. It asks first and says how many.")
    return row
end

function Options.BuildLayoutLooks()
    local pg = layoutEditorPage
    if not pg or pg._adLooksBuilt then return end
    pg._adLooksBuilt = true
    for _, lt in ipairs(Options.LOOK_TABS) do
        local family, fam = lt.family, Schema[lt.family]
        -- the blocks holding a row a layout can set, and their tabs (chips)
        local blocks, chips, seen = {}, {}, {}
        for _, b in ipairs(Options.LOOK_BLOCKS[family] or {}) do
            local sec = fam and fam[b.section]
            local keep = {}
            for _, fld in ipairs(sec and b.fields or {}) do
                local def = sec.fields[fld]
                if def and Schema.Inherits(def, sec) then keep[#keep + 1] = fld end
            end
            if #keep > 0 then
                blocks[#blocks + 1] = { tab = b.tab, title = b.title, section = b.section, fields = keep }
                if not seen[b.tab] then
                    seen[b.tab] = true
                    chips[#chips + 1] = b.tab
                end
            end
        end
        local function ctx()
            local l = SelLayout()
            return l and Store.LayoutProxy(l, family)
        end
        local function Chip()
            local cur = ui.layLook and ui.layLook[family]
            for _, c in ipairs(chips) do
                if c == cur then return cur end
            end
            return chips[1]
        end
        local tabVis = function() return ui.layoutTab == lt.tab and SelLayout() ~= nil end
        AT.Section(pg, nil, { visibleFn = tabVis })
        AT.RowDesc(pg, "Every " .. lt.one .. " in this layout uses these looks unless it sets its own.", 20, tabVis)
        local chipRow = AT.AddRow(pg, 30, function() return tabVis() and #chips >= 2 end)
        chipRow._strip = AT.TabRow(chipRow)
        chipRow._strip._openFill = COL.panel
        chipRow._strip:SetPoint("TOPLEFT", 8, 0)
        chipRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
        chipRow._sync = function()
            if #chips == 0 then return end
            local h = chipRow._strip:Set(chips, Chip(), function(name)
                ui.layLook = ui.layLook or {}
                ui.layLook[family] = name
                AT.LayoutPage(pg)
            end, 11)
            local want = (h or 24) + 6
            if chipRow._h ~= want then chipRow._h = want chipRow:SetHeight(want) end
        end
        for _, b in ipairs(blocks) do
            local vis = function() return tabVis() and Chip() == b.tab end
            AT.Section(pg, b.title, { visibleFn = vis })
            SectionRows(pg, family, b.section, ctx, vis, b.fields, { layoutTier = true })
            Options.LayoutLookStatus(pg, family, b.section, vis, b.fields, lt)
        end
    end
end

-- Icon editor (shared by the group pane and the free pane)

local function IconTabVisible(tabName)
    return function()
        local rec = SelIcon()
        if not rec then return false end
        local tabs = IconTabsFor(rec)
        local listed = false
        for _, t in ipairs(tabs) do
            if t == tabName then listed = true end
        end
        return listed and ui.icoTab == tabName
    end
end

-- Live icon preview: a real factory frame restyled on every refresh (the row's
-- _sync), so drags and colour picks show at once. Aura icons get a stand-in
-- engine button over the holder's missing look, as live. The OnUpdate runs only
-- in a loop mode. Text drops write X / Y in units of a 36px icon.
local PREV_SIZE, PREV_CD, PREV_READY = 96, 6, 2.6
local prevIcon, prevBand, prevChips, prevHandles
local prevPhase, prevT, prevStyleT = "ready", 0, 0
local PREV_MODES = {
    { key = "off",   set = "cd", text = "Static",        w = 64,
      tip = "The ready look with no animation. Drag any text on the icon to place it." },
    { key = "loop",  set = "cd", text = "Cooldown loop", w = 112,
      tip = "Ready, then a fake cooldown, then ready again: swipe, edge, duration text, dims and glows loop." },
    -- Offered only on a spell icon with "Aura on this icon" on.
    { key = "ovup",  set = "ov", text = "Aura up",       w = 72,
      tip = "The look while the aura on this icon is up: the aura's button over the cooldown, in the Aura Active look, with its stacks. Drag its texts to place them." },
    { key = "proc",  set = "cd", text = "Proc glow",     w = 86,
      tip = "Holds the proc glow lit on a ready icon." },
    { key = "ready", set = "cd", text = "Ready glow",    w = 90,
      tip = "Holds the ready glow lit." },
    { key = "aup",   set = "aura", text = "Aura up",      w = 72,
      tip = "The look while the aura is up: its Aura Active art, alpha, tint, border and glow, on the same kind of button the game shows. Drag any text to place it." },
    { key = "aloop", set = "aura", text = "Aura loop",    w = 84,
      tip = "The aura comes up with a fake duration (swipe and duration text), drops to its missing look, and comes back." },
    { key = "amiss", set = "aura", text = "Aura missing", w = 100,
      tip = "The look while the aura is missing: the ghost with its Missing icon, alpha and desaturation." },
}
-- which text drags which fields; the countdown text is the swipe widget's
-- own fontstring, fetched when the handles sync
local PREV_DRAGS = {
    { fs = "stackText",   name = "Stack text",    sec = "text",    a = "stackAnchor",    x = "stackX",    y = "stackY" },
    { fs = "ammoText",    name = "Ammo text",     sec = "text",    a = "ammoAnchor",     x = "ammoX",     y = "ammoY" },
    { fs = "keybindText", name = "Keybind",       sec = "keybind", a = "keybindAnchor",  x = "keybindX",  y = "keybindY" },
    { fs = "labelText",   name = "Label 1",       sec = "label",   a = "labelAnchor",    x = "labelX",    y = "labelY" },
    { fs = "labelText2",  name = "Label 2",       sec = "label",   a = "labelAnchor2",   x = "labelX2",   y = "labelY2" },
    { fs = "labelText3",  name = "Label 3",       sec = "label",   a = "labelAnchor3",   x = "labelX3",   y = "labelY3" },
    { fs = "countdown",   name = "Duration text", sec = "text",    a = "durationAnchor", x = "durationX", y = "durationY" },
}

-- One glow at a time: the lane being edited (the States tab's chip), else the
-- first lane the icon has on, in a fixed order.
local function PreviewGlowLane(rec)
    if ui.icoTab == "States" then
        local sec = ui.icoSec and ui.icoSec["States"]
        if sec == "Proc" then return "proc" end
        if sec == "Usability" then return "usable" end
        if sec == "Ready State" then return "ready" end
    end
    local R = function(k) return Store.Resolve(rec, "states", k) end
    if R("readyGlow") == true then return "ready" end
    if R("procGlow") == true then return "proc" end
    if R("usableGlow") == true then return "usable" end
    return "ready"
end

-- the chip set follows the record: an aura icon uses the aura chips, every
-- other kind the cooldown ones (one ui.prevMode, normalized per kind)
function Options.PreviewMode(rec)
    local m = ui.prevMode or "off"
    local auraKey = (m == "aup" or m == "aloop" or m == "amiss")
    local aura = rec ~= nil and rec.kind == "aura"
    if aura and not auraKey then return "aup" end
    if (not aura) and auraKey then return "off" end
    if m == "ovup" and not (NS.DriverAura and NS.DriverAura.OverlayOn(rec)) then return "off" end
    return m
end

-- The stand-in engine button for aura previews, built and styled by the live
-- recipe (DriverAura.WireButton and AnchorButton, Factory.StyleAuraButton; the
-- two widget setters are no-ops). Parented to the pane, as live, so the missing
-- look's alpha never dims it.
function Options.PreviewAuraButton()
    local b = prevIcon._adAuraBtn
    if b then return b end
    b = CreateFrame("Frame", nil, prevBand)
    b.SetIcon = function() end
    b.SetDurationCooldown = function() end
    NS.DriverAura.WireButton(b)
    b:Hide()
    prevIcon._adAuraBtn = b
    return b
end

local function PreviewFS(d)
    -- an aura preview's count and duration are the stand-in button's own
    local ab = prevIcon._adAuraBtn
    if ab and ab:IsShown() then
        if d.fs == "countdown" then
            local sw = ab._adSwipe
            return sw and sw.GetCountdownFontString and sw:GetCountdownFontString()
        end
        if d.fs == "stackText" then return ab._adStacks end
    end
    if d.fs == "countdown" then
        return prevIcon.cooldown.GetCountdownFontString and prevIcon.cooldown:GetCountdownFontString()
    end
    return prevIcon[d.fs]
end

-- re-anchor every handle to its text; a hidden or empty text has no handle
local function PreviewSyncHandles()
    if not prevHandles then return end
    for _, h in ipairs(prevHandles) do
        local fs = PreviewFS(h._d)
        h._fs = fs
        local txt = fs and fs:GetText()
        if fs and fs:IsShown() and txt and txt ~= "" then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 4)
            h:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -4)
            h:Show()
        else
            h:Hide()
        end
    end
end

local function PreviewRestyle(rec)
    -- an aura icon's holder has no cooldown glow lanes (its glow is the
    -- live button's)
    prevIcon._adGlowLaneOnly = (rec.kind == "aura") and "none" or PreviewGlowLane(rec)
    Factory.ApplyStyle(prevIcon, rec)
    if prevIcon.stackText:IsShown() then prevIcon.stackText:SetText("2") end
    -- the preview shows a real ammo count so the styling reads true
    if prevIcon.ammoText and prevIcon.ammoText:IsShown() then
        prevIcon.ammoText:SetText(GetInventoryItemCount("player", NS.AMMO_SLOT or 0) or 0)
    end
    -- The key on your bars, else a stand-in so the text can still be placed.
    local kb = NS.DriverCooldown and NS.DriverCooldown.KeybindTextFor
        and NS.DriverCooldown.KeybindTextFor(rec)
    if not kb and Factory.KeybindEnabled(rec) then kb = "s-1" end
    Factory.SetKeybindText(prevIcon, kb)
    -- Aura icon: the count belongs to the engine button, and the stand-in takes
    -- the whole live look (the kind's art, any Active / Custom icon over it).
    local ab = prevIcon._adAuraBtn
    if rec.kind == "aura" then
        prevIcon.stackText:SetText("")
        ab = Options.PreviewAuraButton()
        NS.DriverAura.AnchorButton(ab, prevIcon)
        ab._adIcon:SetTexture(Factory.KindTexture(rec))
        Factory.StyleAuraButton(ab, rec, PREV_SIZE,
            { w = PREV_SIZE, h = PREV_SIZE, ghost = NS.DriverAura.GhostShown(rec) })
        if ab._adStacks:IsShown() then ab._adStacks:SetText("2") end
    elseif Options.PreviewMode(rec) == "ovup" then
        -- a spell icon's aura overlay: the same stand-in, one level up the
        -- ladder like the live overlay, "the engine wrote" the aura's own
        -- art (its first ID); the cooldown plane under it is the holder
        ab = Options.PreviewAuraButton()
        NS.DriverAura.AnchorButton(ab, prevIcon, 1)
        local ov = rec.driver and rec.driver.overlay
        local aid = ov and ov.spellID
        ab._adIcon:SetTexture((aid and C_Spell.GetSpellTexture(aid)) or Factory.KindTexture(rec))
        Factory.StyleAuraButton(ab, rec, PREV_SIZE, { w = PREV_SIZE, h = PREV_SIZE, ghost = true })
        if ab._adStacks:IsShown() then ab._adStacks:SetText("2") end
    elseif ab then
        ab:Hide()
    end
end

local function PreviewApplyMode(rec)
    local mode = Options.PreviewMode(rec)
    if rec.kind == "aura" then
        -- The holder always shows the missing look, as live; the stand-in
        -- covers it while the aura is up (phase "ready" in the loop).
        prevIcon.cooldown:Clear()
        Factory.StopGlow(prevIcon)
        Factory.SetState(prevIcon, rec, true, true)
        local ab = Options.PreviewAuraButton()
        local up = (mode == "aup") or (mode == "aloop" and prevPhase == "ready")
        ab:SetShown(up)
        -- a spell icon's Aura up froze the shared stand-in's swipe: free it
        if ab._adSwipe.IsPaused and ab._adSwipe:IsPaused() then ab._adSwipe:Resume() end
        if mode == "aloop" and up then
            -- the fake duration runs from the phase's start; a refresh in
            -- the middle of the phase leaves it running (plain numbers on our
            -- own Cooldown widget - nothing secret)
            if GetTime() >= (ab._adLoopUntil or 0) then
                ab._adSwipe:SetCooldown(GetTime(), PREV_CD)
                ab._adLoopUntil = GetTime() + PREV_CD
            end
        else
            ab._adSwipe:Clear()
            ab._adLoopUntil = nil
        end
        PreviewSyncHandles()
        return
    end
    if mode == "ovup" then
        -- A spell icon's aura while up: the cooldown underneath with the stand-in
        -- aura button over it, as live.
        prevIcon._adGlowLaneOnly = "none"
        Factory.SetProcGlow(prevIcon, rec, false)
        Factory.StopGlow(prevIcon)
        Factory.SetState(prevIcon, rec, true, true)
        local ab = Options.PreviewAuraButton()
        -- A frozen moment of the aura (60% left), so its swipe colour, direction,
        -- edge and time text show while nothing ticks. Plain numbers on our own
        -- Cooldown; every other use of the stand-in resumes it first.
        local sw = ab._adSwipe
        if sw.Resume then sw:Resume() end
        sw:SetCooldown(GetTime() - PREV_CD * 0.4, PREV_CD)
        if sw.Pause then sw:Pause() end
        ab:Show()
        PreviewSyncHandles()
        return
    end
    if mode == "loop" then
        if prevPhase == "cd" then
            Factory.SetProcGlow(prevIcon, rec, false)
            Factory.UpdateGlow(prevIcon, rec, false)
            Factory.SetState(prevIcon, rec, true, true)
        else
            Factory.SetState(prevIcon, rec, false, false)
            Factory.UpdateGlow(prevIcon, rec, true)
            Factory.SetProcGlow(prevIcon, rec, true)
        end
    elseif mode == "proc" then
        prevIcon._adGlowLaneOnly = "proc"
        prevIcon.cooldown:Clear()
        Factory.SetState(prevIcon, rec, false, false)
        Factory.SetProcGlow(prevIcon, rec, true)
    elseif mode == "ready" then
        prevIcon._adGlowLaneOnly = "ready"
        prevIcon.cooldown:Clear()
        Factory.SetProcGlow(prevIcon, rec, false)
        Factory.SetState(prevIcon, rec, false, false)
        Factory.UpdateGlow(prevIcon, rec, true)
    else
        prevIcon._adGlowLaneOnly = "none"
        prevIcon.cooldown:Clear()
        Factory.SetProcGlow(prevIcon, rec, false)
        Factory.SetState(prevIcon, rec, false, false)
        Factory.StopGlow(prevIcon)
    end
    PreviewSyncHandles()
end

-- The loop: ready for PREV_READY, a fake cooldown for PREV_CD, repeat. An
-- aura's loop is the reverse: up for its fake duration (PREV_CD), then missing
-- for PREV_READY.
local function PreviewTick(_, dt)
    local rec = SelIcon()
    if not rec or prevIcon._adDragging then return end
    local aura = rec.kind == "aura"
    prevT = prevT + dt
    prevStyleT = prevStyleT + dt
    if prevStyleT >= 0.25 then
        prevStyleT = 0
        PreviewRestyle(rec)
        -- ApplyStyle re-runs the ready and usable lanes on its own; the proc
        -- lane is event-driven, so it is re-asserted here (idempotent). An
        -- aura icon's holder has no proc lane.
        if not aura then Factory.SetProcGlow(prevIcon, rec, prevPhase == "ready") end
        PreviewSyncHandles()
    end
    local firstT = aura and PREV_CD or PREV_READY
    local secondT = aura and PREV_READY or (PREV_CD + 0.2)
    if prevPhase == "ready" then
        if prevT >= firstT then
            prevPhase, prevT = "cd", 0
            -- plain numbers are legal on a preview push (nothing secret)
            if not aura then prevIcon.cooldown:SetCooldown(GetTime(), PREV_CD) end
            PreviewApplyMode(rec)
        end
    elseif prevT >= secondT then
        prevPhase, prevT = "ready", 0
        prevIcon.cooldown:Clear()
        PreviewApplyMode(rec)
    end
end

-- one invisible button per text: hover names it, drag moves it live (same
-- anchor, new offsets), drop writes the fields and refreshes
local function PreviewWireHandles()
    prevHandles = {}
    for _, d in ipairs(PREV_DRAGS) do
        local h = CreateFrame("Button", nil, prevIcon)
        h:SetFrameLevel(prevIcon:GetFrameLevel() + 40)
        h:RegisterForDrag("LeftButton")
        h._d = d
        h:Hide()
        h:SetScript("OnEnter", function(s)
            local rec = SelIcon()
            if not rec then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(d.name, 1, 1, 1)
            local tab = (d.sec == "keybind" and "Keybind") or (d.sec == "label" and "Label") or "Text"
            GameTooltip:AddLine(("X %d, Y %d. Drag to move; the %s tab holds the sliders."):format(
                Store.Resolve(rec, d.sec, d.x) or 0, Store.Resolve(rec, d.sec, d.y) or 0, tab),
                0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        h:SetScript("OnDragStart", function(s)
            local rec = SelIcon()
            local fs = s._fs
            if not (rec and fs) then return end
            local cx, cy = GetCursorPosition()
            s._start = { cx = cx, cy = cy,
                x = Store.Resolve(rec, d.sec, d.x) or 0, y = Store.Resolve(rec, d.sec, d.y) or 0,
                anchor = Store.Resolve(rec, d.sec, d.a) or "CENTER" }
            s._live = nil
            prevIcon._adDragging = true
            GameTooltip:Hide()
            s:SetScript("OnUpdate", function(s2)
                local st = s2._start
                if not st then return end
                local nx, ny = GetCursorPosition()
                local es = prevIcon:GetEffectiveScale()
                if not es or es <= 0 then return end
                local kS = PREV_SIZE / 36
                local X = math.floor(st.x + (nx - st.cx) / es / kS + 0.5)
                local Y = math.floor(st.y + (ny - st.cy) / es / kS + 0.5)
                X = math.max(-50, math.min(50, X))
                Y = math.max(-50, math.min(50, Y))
                s2._live = { X, Y }
                fs:ClearAllPoints()
                fs:SetPoint(st.anchor, prevIcon, st.anchor, X * kS, Y * kS)
            end)
        end)
        h:SetScript("OnDragStop", function(s)
            s:SetScript("OnUpdate", nil)
            prevIcon._adDragging = nil
            local live, rec = s._live, SelIcon()
            s._live, s._start = nil, nil
            if rec and live then
                Store.SetOverride(rec, d.sec, d.x, live[1])
                Store.SetOverride(rec, d.sec, d.y, live[2])
            end
            if RefreshAll then RefreshAll() end
        end)
        prevHandles[#prevHandles + 1] = h
    end
end

-- The preview pane sits above the scrolling editor page so it stays in view.
-- AttachPreview returns its height, which the page's top anchor moves down by.
local PREV_PANE_H = PREV_SIZE + 4 + 8 + 22 + 8
local function BuildPreviewPane()
    prevBand = CreateFrame("Frame", nil, UIParent)
    prevBand:SetHeight(PREV_PANE_H)
    prevBand:Hide()
    prevIcon = Factory.CreatePreview(prevBand)
    prevIcon:SetSize(PREV_SIZE, PREV_SIZE)
    prevIcon:SetPoint("TOP", 0, -4)
    PreviewWireHandles()
    -- The mode chips: a cooldown set, an aura set, and the overlay's Aura up,
    -- which joins the cooldown set; AttachPreview centres the chips shown.
    prevChips = {}
    for _, m in ipairs(PREV_MODES) do
        local b = AT.MakeSmallButton(prevBand, m.text, m.w)
        b._adSet = m.set
        b._adW = m.w
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            ui.prevMode = m.key
            prevPhase, prevT, prevStyleT = "ready", 0, 0
            if prevIcon then
                prevIcon.cooldown:Clear()
                -- an aura loop starts its fake duration afresh (and a frozen
                -- Aura up swipe thaws)
                local ab = prevIcon._adAuraBtn
                if ab then
                    if ab._adSwipe.Resume then ab._adSwipe:Resume() end
                    ab._adSwipe:Clear()
                    ab._adLoopUntil = nil
                end
            end
            if RefreshAll then RefreshAll() end
        end)
        AT.Tooltip(b, m.text, m.tip)
        prevChips[m.key] = b
    end
end

-- host the pane at (parent, y), bring it up to date, hide it with the
-- editor; returns the height the editor page must leave for it
local function AttachPreview(parent, y, shown)
    if not prevBand then return 0 end
    local rec = SelIcon()
    shown = shown and rec ~= nil
    prevBand:SetParent(parent)
    prevBand:ClearAllPoints()
    prevBand:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    prevBand:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    prevBand:SetShown(shown)
    if not shown then
        prevBand:SetScript("OnUpdate", nil)
        return 0
    end
    local mode = Options.PreviewMode(rec)
    prevBand:SetScript("OnUpdate", (mode == "loop" or mode == "aloop") and PreviewTick or nil)
    local set = (rec.kind == "aura") and "aura" or "cd"
    local ov = set == "cd" and NS.DriverAura ~= nil and NS.DriverAura.OverlayOn(rec) == true
    local shownChips, total = {}, -6
    for _, m in ipairs(PREV_MODES) do
        local b = prevChips[m.key]
        local on = (m.set == set) or (ov and m.set == "ov")
        b:SetShown(on)
        if on then
            shownChips[#shownChips + 1] = b
            total = total + b._adW + 6
        end
        local c = (m.key == mode) and COL.arc or COL.dim
        b.fs:SetTextColor(c[1], c[2], c[3])
    end
    local x = -total / 2
    for _, b in ipairs(shownChips) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", prevBand, "TOP", x, -(PREV_SIZE + 4 + 8 + 11))
        x = x + b._adW + 6
    end
    if not prevIcon._adDragging then
        PreviewRestyle(rec)
        PreviewApplyMode(rec)
    end
    return PREV_PANE_H
end

local function BuildIconEditor(parent)
    local pg = AT.NewPage(parent)
    AT.MakeScrollable(pg)
    pg:Show()

    local head = AT.AddRow(pg, 34)
    head._icon = IconButton(head, 26)
    head._icon:SetPoint("LEFT", 8, 0)
    head._icon:EnableMouse(false)
    head._name = head:CreateFontString(nil, "OVERLAY")
    head._name:SetFont(STANDARD_TEXT_FONT, 13, "")
    head._name:SetPoint("LEFT", 42, 0)
    head._name:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    head._pill = KindPill(head)
    head._badge = head:CreateFontString(nil, "OVERLAY")
    head._badge:SetFont(STANDARD_TEXT_FONT, 9, "")
    head._badge:SetTextColor(SHR[1], SHR[2], SHR[3])
    head._del = AT.MakeSmallButton(head, "Delete", 56)
    head._del:SetPoint("RIGHT", -8, 0)
    head._del:SetScript("OnClick", function() Options.ConfirmDelete(SelIcon()) end)
    BandActions(head, head._name, SelIcon, { rightOf = head._del, hide = { head._pill, head._badge } })
    head._sync = function()
        local rec = SelIcon()
        if not rec then return end
        head._icon.tex:SetTexture(Factory.GetTexture(rec))
        head._name:SetText("Editing:  " .. rec.name)
        head._pill:Set(Options.IconPillText(rec.kind))
        head._pill:ClearAllPoints()
        head._pill:SetPoint("LEFT", head._name, "RIGHT", 8, 0)
        head._badge:ClearAllPoints()
        head._badge:SetPoint("LEFT", head._pill, "RIGHT", 8, 0)
        head._badge:SetText((Store.BadgeText(rec)))
    end

    -- Built once; the host panes pin it above this page, outside the scroll.
    BuildPreviewPane()

    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel   -- strips inside panel-bodied pages
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local rec = SelIcon()
        if not rec then return end
        local tabs = IconTabsFor(rec)
        -- selection changed to a kind without the current tab: snap to its
        -- first tab so the editor never shows an empty body
        local listed = false
        for _, t in ipairs(tabs) do
            if t == ui.icoTab then listed = true end
        end
        if not listed then ui.icoTab = tabs[1] end
        local h = tabRow._strip:Set(tabs, ui.icoTab, function(name)
            ui.icoTab = name
            AT.LayoutPage(pg)
        end)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Section tabs: a main tab with two or more applicable sub-panels shows them
    -- as a second chip row; a single sub-panel renders plain.
    local SEC_LISTS = {}   -- [tabName] = ordered { {title, section, fields} }
    local function BlockApplies(rec, def)
        local sec = Schema.icon[def.section]
        if not Schema.Applies(nil, sec, Store.KindOf(rec)) then return false end
        -- a block meant for one kind only (the aura swipe: its own chip on an
        -- aura icon's Swipe tab, a Swipe chip in a spell icon's Aura Active)
        if def.kindOnly and rec.kind ~= def.kindOnly then return false end
        -- A spell icon has the aura's look only while its aura overlay is on.
        if (def.section == "auraActive" or def.section == "auraSwipe") and rec.kind ~= "aura"
            and not (NS.DriverAura and NS.DriverAura.OverlayOn and NS.DriverAura.OverlayOn(rec)) then
            return false
        end
        for _, fname in ipairs(def.fields) do
            local fdef = sec.fields[fname]
            if fdef and Schema.Applies(fdef, sec, Store.KindOf(rec)) then return true end
        end
        return false
    end
    local function AvailSecs(tabName)
        local rec = SelIcon()
        local out = {}
        if not rec then return out end
        for _, def in ipairs(SEC_LISTS[tabName] or {}) do
            if BlockApplies(rec, def) then out[#out + 1] = def.title end
        end
        return out
    end
    -- The settings search walks every tab and applicable sub-panel.
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.icon = { page = pg, subs = AvailSecs }
    ui.icoSec = ui.icoSec or {}
    local secRow = AT.AddRow(pg, 30, function()
        return SelIcon() ~= nil and #AvailSecs(ui.icoTab) >= 2
    end)
    secRow._strip = AT.TabRow(secRow)
    secRow._strip._openFill = COL.panel
    secRow._strip:SetPoint("TOPLEFT", 8, 0)
    secRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    secRow._sync = function()
        local avail = AvailSecs(ui.icoTab)
        if #avail == 0 then return end
        local cur = ui.icoSec[ui.icoTab]
        local ok = false
        for _, t in ipairs(avail) do if t == cur then ok = true end end
        if not ok then cur = avail[1]; ui.icoSec[ui.icoTab] = cur end
        local h = secRow._strip:Set(avail, cur, function(name)
            ui.icoSec[ui.icoTab] = name
            AT.LayoutPage(pg)
        end, 11)
        local want = (h or 24) + 6
        if secRow._h ~= want then secRow._h = want secRow:SetHeight(want) end
    end

    -- Tracking (driver block; per kind; retarget re-keys the driver only)
    local trackVis = IconTabVisible("Tracking")
    AT.Section(pg, "Tracking", { visibleFn = trackVis })
    AT.RowInput(pg, "Spell ID",
        function()
            local r = SelIcon()
            return r and r.driver.spellID and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            local sid = tonumber(v)
            if sid then
                r.driver.spellID = sid
                local info = C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                if info then r.name = info end
                Store.Dirty("tree")
                RefreshAll()
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and (r.kind == "spell" or r.kind == "timer")
        end,
        "The tracked spell. Retargeting re-keys the driver and keeps every setting and position.")
    -- Aura tracking: every ID rides the icon's one engine button and the game
    -- shows whichever is up. ShapeOf reads older shapes (petbuff, ownOnly) as
    -- the driver does; unit and type edits rewire the slot, the rest is data.
    local auraVis = function()
        local r = SelIcon()
        return trackVis() and r ~= nil and r.kind == "aura"
    end
    AT.RowInput(pg, "Spell IDs",
        function()
            local r = SelIcon()
            if not r then return "" end
            return table.concat(NS.DriverAura.SpellIDList(r.driver), ", ")
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            local ids = Options.ParseSpellIDs(v)
            if #ids == 0 then return end
            local old = r.driver.spellID
            Options.SetAuraSpellIDs(r.driver, ids)
            -- the icon takes the first id's name only when the first id
            -- moves: a name typed by hand survives adding more ids
            if ids[1] ~= old then
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])
                if nm then r.name = nm end
            end
            Store.Dirty("tree")
            RefreshAll()
        end,
        auraVis,
        "Every spell ID this icon lights for, separated by commas or spaces - one icon for all of them, and the game shows whichever is up. The first ID gives the icon its art and name.",
        "e.g. 2825, 32182, 80353")
    AT.RowDropdown(pg, win, "Aura type",
        function()
            local r = SelIcon()
            return r and ((r.driver.auraType == "debuff") and "debuff" or "buff")
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            local d = r.driver
            -- Pin the unit the icon watches (a petbuff record keeps its pet),
            -- then move it off a unit this type cannot match on.
            local unit = NS.DriverAura.ShapeOf(d)
            d.auraType = v
            if not Options.AuraUnitAllowed(d, unit, v) then unit = "target" end
            d.unit = unit
            Store.Dirty("style", r.id)
        end,
        function() return {
            { value = "buff", text = "Buff" },
            { value = "debuff", text = "Debuff" },
        } end,
        auraVis)
    local unitRow = AT.RowDropdown(pg, win, "On unit",
        function()
            local r = SelIcon()
            return r and (NS.DriverAura.ShapeOf(r.driver))
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            -- A petbuff record becomes a plain buff with unit = pet.
            if r.driver.auraType == "petbuff" then r.driver.auraType = "buff" end
            r.driver.unit = v
            Store.Dirty("style", r.id)
        end,
        function()
            local r = SelIcon()
            if not r then return {} end
            return Options.AuraUnitItems(r.driver, nil, (NS.DriverAura.ShapeOf(r.driver)))
        end,
        auraVis)
    AT.Tooltip(unitRow, "On unit",
        "Who carries the aura. Buffs match on you, your pet, party members, players and friendly targets; debuffs on enemies. The game does not let addons match a buff on an enemy creature or a debuff on a friend by spell ID, so those stay dark (spells the game marks never-secret are the exception).")
    local casterRow = AT.RowDropdown(pg, win, "Cast by",
        function()
            local r = SelIcon()
            if not r then return "any" end
            local _, _, caster = NS.DriverAura.ShapeOf(r.driver)
            return caster or "any"
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            r.driver.caster = (v ~= "any") and v or nil
            -- ownOnly reads as Cast by = mine; drop it once Cast by is set.
            r.driver.ownOnly = nil
            Store.Dirty("style", r.id)
        end,
        function() return Options.AURA_CASTER_ITEMS end,
        auraVis)
    AT.Tooltip(casterRow, "Cast by",
        "Anyone: any copy of the aura lights the icon. Me: only yours (or your pet's), so another player's copy never does. Anyone but me: only copies other players put up.")
    AT.RowToggle(pg, "Auto rank (follow my known rank)",
        function() local r = SelIcon() return r ~= nil and r.driver.autoRank == true end,
        function(v)
            local r = SelIcon()
            if r then
                r.driver.autoRank = v and true or nil
                Store.Dirty("style", r.id)
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "spell" and NS.IsForever == true
        end,
        "Ranked realms (WoW Forever): the icon resolves by NAME to the rank you currently know, so learning a new rank never needs a new spell ID. Off = it tracks the exact ID above; you can also pin a rank there.")
    AT.RowToggle(pg, "Ignore spell overrides",
        function() local r = SelIcon() return r ~= nil and r.driver.ignoreSpellOverride == true end,
        function(v)
            local r = SelIcon()
            if r then
                r.driver.ignoreSpellOverride = v and true or nil
                Store.Dirty("style", r.id)
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "spell"
        end,
        "Replacement forms (Windstrike, proc spells) normally drive this icon's cooldown and art. On = pin the BASE spell instead.")
    AT.RowDropdown(pg, win, "Trinket slot",
        function() local r = SelIcon() return r and (r.driver.slotID or 13) end,
        function(v)
            local r = SelIcon()
            if r then r.driver.slotID = v Store.Dirty("style", r.id) end
        end,
        function() return { { value = 13, text = "Trinket 1 (top)" }, { value = 14, text = "Trinket 2 (bottom)" } } end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "trinket"
        end)
    AT.RowInput(pg, "Item ID",
        function()
            local r = SelIcon()
            return r and r.driver.itemID and tostring(r.driver.itemID) or ""
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            local iid = tonumber(v)
            if iid then
                r.driver.itemID = iid
                local nm = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(iid)
                if nm then r.name = nm end
                Store.Dirty("tree")
                RefreshAll()
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "item"
        end,
        "The tracked item. Retargeting keeps every setting and position.")
    AT.RowDropdown(pg, win, "Totem slot",
        function() local r = SelIcon() return r and (r.driver.slot or 1) end,
        function(v)
            local r = SelIcon()
            if r then r.driver.slot = v Store.Dirty("style", r.id) end
        end,
        function()
            return {
                { value = 1, text = "Slot 1" }, { value = 2, text = "Slot 2" },
                { value = 3, text = "Slot 3" }, { value = 4, text = "Slot 4" },
            }
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "totem"
        end)
    AT.RowDesc(pg, "Any spell ID above lights this one icon.", 20,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "aura"
        end)
    -- A Dynamic aura group's live rows carry only buffs on you or your pet and
    -- debuffs on your target; a static group gives every member its own slot.
    AT.RowDesc(pg, "A Dynamic group only tracks you, your pet and your target: turn its Dynamic off.", 20,
        function()
            local r = SelIcon()
            if not (trackVis() and r ~= nil and r.kind == "aura" and r.groupId) then return false end
            local g = Store.Get(r.groupId)
            return g ~= nil and g.groupKind == "aura"
                and Store.Resolve(g, "arrangement", "dynamicLayout") == true
                and not Options.AuraLaneInGroupRows(r.driver)
        end)
    AT.RowDesc(pg, "Follows your equipped ammo. Nothing to set here.", 20,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "ammo"
        end)

    -- Aura on this icon: the switch, then the aura's tracking rows; its look is
    -- on the Aura Active tab. Offered only with the game's aura container,
    -- without which the overlay could not work in combat.
    local ovSecVis = function()
        local r = SelIcon()
        return trackVis() and r ~= nil and r.kind == "spell"
            and NS.DriverAura ~= nil and NS.DriverAura.IsAvailable() == true
    end
    local ovVis = function()
        return ovSecVis() and NS.DriverAura.OverlayOn(SelIcon()) == true
    end
    AT.Section(pg, "Aura on this icon", { visibleFn = ovSecVis })
    AT.RowToggle(pg, "Show an aura on this icon",
        function()
            local r = SelIcon()
            return r ~= nil and NS.DriverAura ~= nil and NS.DriverAura.OverlayOn(r) == true
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            Options.SetOverlayOn(r, v)
            -- the Aura Active tab comes and goes with it
            RefreshAll()
        end,
        ovSecVis,
        "While the aura is up, the game shows it on this icon: its time and stacks over the cooldown, in the look set on the Aura Active tab. When it ends, the cooldown shows again. It works in combat.")
    AT.RowInput(pg, "Aura spell IDs",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return ov and table.concat(NS.DriverAura.SpellIDList(ov), ", ") or ""
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            local ids = Options.ParseSpellIDs(v)
            if #ids == 0 then return end
            Options.SetAuraSpellIDs(ov, ids)
            Store.Dirty("style", r.id)
        end,
        ovVis,
        "The aura's spell IDs, separated by commas or spaces. A buff or debuff usually has the ID of the spell that puts it up; add every rank's ID if they differ. The game shows whichever is up.",
        "e.g. 5118")
    AT.RowDropdown(pg, win, "Aura type",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return (ov and ov.auraType == "debuff") and "debuff" or "buff"
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            local unit = NS.DriverAura.ShapeOf(ov)
            ov.auraType = v
            if not Options.AuraUnitAllowed(ov, unit, v) then unit = "target" end
            ov.unit = unit
            Store.Dirty("style", r.id)
        end,
        function() return {
            { value = "buff", text = "Buff" },
            { value = "debuff", text = "Debuff" },
        } end,
        ovVis)
    local ovUnitRow = AT.RowDropdown(pg, win, "On unit",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return ov and (NS.DriverAura.ShapeOf(ov)) or "player"
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            ov.unit = v
            Store.Dirty("style", r.id)
        end,
        function()
            local ov = Options.OverlayOf(SelIcon())
            if not ov then return {} end
            return Options.AuraUnitItems(ov, nil, (NS.DriverAura.ShapeOf(ov)))
        end,
        ovVis)
    AT.Tooltip(ovUnitRow, "On unit",
        "Who carries the aura: you for a buff you put up, your target for a debuff you put on it. The game does not let addons match a buff on an enemy creature or a debuff on a friend by spell ID, so those stay dark.")
    local ovCasterRow = AT.RowDropdown(pg, win, "Cast by",
        function()
            local ov = Options.OverlayOf(SelIcon())
            if not ov then return "any" end
            local _, _, caster = NS.DriverAura.ShapeOf(ov)
            return caster or "any"
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            ov.caster = (v ~= "any") and v or nil
            Store.Dirty("style", r.id)
        end,
        function() return Options.AURA_CASTER_ITEMS end,
        ovVis)
    AT.Tooltip(ovCasterRow, "Cast by",
        "Me: only your own copy of the aura shows on this icon (the usual choice - another player's copy is not your cooldown). Anyone: any copy. Anyone but me: only copies other players put up.")

    ConditionRows(pg, SelIcon, IconTabVisible("Load Conditions"))
    VisibilityRows(pg, SelIcon, IconTabVisible("Visibility"))

    -- Icon blocks: titled sub-panels with fields in a set order, each hidden
    -- when none of its fields apply to the icon's kind. Each has its own push
    -- bar, shown only while the block is the active chip and applies (Swipe
    -- hosts `swipe` or `auraSwipe` by kind); it copies only that block's rows.
    local function IconBlockDef(tabName, title)
        for _, def in ipairs(SEC_LISTS[tabName] or {}) do
            if def.title == title then return def end
        end
    end
    local function IconPushSec(tabName, section, title)
        local tabVis = IconTabVisible(tabName)
        local vis = function()
            if not tabVis() then return false end
            local r = SelIcon()
            local def = IconBlockDef(tabName, title)
            if not (r and def and BlockApplies(r, def)) then return false end
            local avail = AvailSecs(tabName)
            if #avail >= 2 and ui.icoSec[tabName] ~= title then return false end
            return true
        end
        AT.Section(pg, nil, { visibleFn = vis })
        PushBar(pg, SelIcon, section, vis, function()
            local def = IconBlockDef(tabName, title)
            return def and def.fields or nil
        end)
    end
    local function IconBlock(title, section, tabName, fields, kindOnly)
        local def = { title = title, section = section, fields = fields, kindOnly = kindOnly }
        SEC_LISTS[tabName] = SEC_LISTS[tabName] or {}
        table.insert(SEC_LISTS[tabName], def)
        Options.LookBlock("icon", tabName, title, section, fields)
        local tabVis = IconTabVisible(tabName)
        local vis = function()
            if not tabVis() then return false end
            local r = SelIcon()
            if not r then return false end
            if not BlockApplies(r, def) then return false end
            -- 2+ sub-panels = section tabs: only the picked one renders
            local avail = AvailSecs(tabName)
            if #avail >= 2 and ui.icoSec[tabName] ~= title then return false end
            return true
        end
        AT.Section(pg, title, { visibleFn = vis })
        SectionRows(pg, "icon", section, SelIcon, vis, fields)
        return vis
    end
    -- A titled sub-group inside an icon block: it shares the block's
    -- visibility and joins its push list. Call it after any bespoke rows of the
    -- block's first run.
    local function IconSub(vis, tabName, blockTitle, title, section, fields)
        AT.Section(pg, title, { visibleFn = vis })
        SectionRows(pg, "icon", section, SelIcon, vis, fields)
        Options.LookBlock("icon", tabName, title, section, fields)
        local def = IconBlockDef(tabName, blockTitle)
        if def then for _, f in ipairs(fields) do def.fields[#def.fields + 1] = f end end
    end

    -- Push bars sit at the bottom of each tab. Size (the position section's size
    -- fields and Use group scale) lives on Appearance, not the Position tab.
    IconBlock("Size", "position", "Appearance", {
        "useGroupScale", "iconScale", "iconWidth", "iconHeight",
    })
    AT.RowDesc(pg, "In a group the group's size applies until Use group scale is off.", 20,
        function()
            if not IconTabVisible("Appearance")() then return false end
            return ui.icoSec["Appearance"] == "Size"
        end)
    local lookVis = IconBlock("Look", "appearance", "Appearance", {
        "zoom", "aspectRatio", "alpha", "padding", "keepBright",
        "keepBrightAllowDesat",
    })
    IconSub(lookVis, "Appearance", "Look", "Art", "appearance", {
        "forceHideIcon", "customIconFrom", "customIcon", "activeArt",
    })
    AT.RowDesc(pg, "Aura Active and Aura Missing can each set their own art.", 20,
        function()
            local r = SelIcon()
            return lookVis() and r ~= nil and r.kind == "aura"
        end)
    local borderVis = IconBlock("Border", "appearance", "Appearance", {
        "borderEnabled", "borderColor", "borderThickness", "borderInset",
        -- aura icons: the border takes the aura's dispel-type colour
        "dispelBorder",
    })
    -- The Cooldown Manager's soft shadow frame.
    IconSub(borderVis, "Appearance", "Border", "Shadow", "appearance", {
        "shadowEnabled", "shadowSize",
    })
    IconPushSec("Appearance", "position", "Size")
    IconPushSec("Appearance", "appearance", "Look")
    IconPushSec("Appearance", "appearance", "Border")

    -- Aura icons in an aura group: the engine lays the row out in play mode,
    -- so only the size fields reach it.
    AT.RowDesc(pg, "The game places aura group rows: these apply only while this window is open.", 20,
        function()
            if not IconTabVisible("Position")() then return false end
            if ui.icoSec["Position"] ~= "Position" and #AvailSecs("Position") >= 2 then return false end
            local r = SelIcon()
            local g = r and r.groupId and Store.Get(r.groupId)
            return r ~= nil and r.kind == "aura" and g ~= nil and g.groupKind == "aura"
        end)
    -- A free icon's screen position; a group member's cell places it.
    local freePosVis = function()
        if not IconTabVisible("Position")() then return false end
        local r = SelIcon()
        if not (r and r.groupId == nil) then return false end
        return #AvailSecs("Position") < 2 or ui.icoSec["Position"] == "Position"
    end
    AT.Section(pg, "Screen position", { visibleFn = freePosVis })
    Options.PosRows(pg, SelIcon, freePosVis, function(r)
        -- pinned right now: a gone or hidden target places it free
        return NS.Anchor ~= nil and NS.Anchor.ResolveTarget(r) ~= nil
    end)
    IconBlock("Position", "position", "Position", {
        "offsetX", "offsetY", "strata", "frameLevel",
    })
    IconBlock("Mouse", "mouse", "Position", {
        "clickThrough", "showTooltip",
    })
    AT.RowDesc(pg, "Inherit follows the group, then the layout, then Settings.", 20,
        function()
            if not IconTabVisible("Position")() then return false end
            return ui.icoSec["Position"] == "Mouse"
        end)
    IconPushSec("Position", "position", "Position")
    IconPushSec("Position", "mouse", "Mouse")

    -- Anchor: free icons only, as IconTabsFor offers the tab.
    Options.AnchorPickRows(pg, "icon", SelIcon, IconTabVisible("Anchor"), {
        "anchorSrcPoint", "anchorDstPoint", "anchorOffsetX", "anchorOffsetY",
    })

    local readyVis = IconBlock("Ready State", "states", "States", {
        "readyAlpha", "procOverride", "usableOverride", "readyTintEnabled", "readyTintColor",
    })
    AT.RowDesc(pg, "Ready alpha 0 hides a ready icon; the overrides below can bring it back.", 20,
        function()
            if not IconTabVisible("States")() then return false end
            return ui.icoSec["States"] == "Ready State"
        end)
    IconSub(readyVis, "States", "Ready State", "Ready glow", "states", {
        "readyGlow", "readyGlowType", "readyGlowColor", "readyGlowSpeed",
        "readyGlowLines", "readyGlowThickness", "readyGlowLength", "readyGlowParticles",
        "readyGlowIntensity", "readyGlowScale",
        "readyGlowXOffset", "readyGlowYOffset", "readyGlowMoveX", "readyGlowMoveY",
        "readyGlowCombatOnly", "readyGlowStrata", "readyGlowLevel",
    })
    IconBlock("Cooldown State", "states", "States", {
        "cooldownAlpha", "cooldownDesaturate", "preserveDurationText",
        "waitForNoCharges", "cooldownTintEnabled", "cooldownTintColor",
    })
    IconBlock("Proc", "states", "States", {
        "procGlow", "procGlowType", "procGlowColor", "procGlowSpeed",
        "procGlowLines", "procGlowThickness", "procGlowLength", "procGlowParticles",
        "procGlowIntensity", "procGlowScale",
        "procGlowXOffset", "procGlowYOffset", "procGlowMoveX", "procGlowMoveY",
        "procGlowStrata", "procGlowLevel",
    })
    -- Usability and Range are separate: "can I afford this" and "am I close
    -- enough" differ, and usability carries a whole glow family.
    local usabVis = IconBlock("Usability", "states", "States", {
        "unusableAlpha", "resourceAlpha",
        "usabilityTint", "resourceTintColor", "resourceDesaturate",
        "unusableTintColor", "unusableDesaturate",
    })
    AT.RowDesc(pg, "Dims while it cannot be pressed, never brighter than Ready alpha.", 20,
        function()
            if not IconTabVisible("States")() then return false end
            return ui.icoSec["States"] == "Usability"
        end)
    IconSub(usabVis, "States", "Usability", "Usable glow", "states", {
        "usableGlow", "usableGlowType", "usableGlowColor", "usableGlowSpeed",
        "usableGlowLines", "usableGlowThickness", "usableGlowLength", "usableGlowParticles",
        "usableGlowScale", "usableGlowIntensity",
        "usableGlowXOffset", "usableGlowYOffset", "usableGlowMoveX", "usableGlowMoveY",
        "usableGlowCombatOnly", "usableGlowStrata", "usableGlowLevel",
    })
    IconBlock("Range", "states", "States", {
        "rangeTint", "rangeTintColor",
    })
    IconPushSec("States", "states", "Ready State")
    IconPushSec("States", "states", "Cooldown State")
    IconPushSec("States", "states", "Proc")
    IconPushSec("States", "states", "Usability")
    IconPushSec("States", "states", "Range")

    local swipeVis = IconBlock("Swipe", "swipe", "Swipe", {
        "showSwipe", "swipeColor", "reverse", "noGCDSwipe", "swipeWaitForNoCharges",
    })
    IconSub(swipeVis, "Swipe", "Swipe", "Inset", "swipe", {
        "swipeInset", "separateInsets", "swipeInsetX", "swipeInsetY",
    })
    IconBlock("Edge & Finish", "swipe", "Swipe", {
        "showEdge", "edgeColor", "edgeScale", "edgeWaitForNoCharges", "showBling",
    })
    IconPushSec("Swipe", "swipe", "Swipe")
    IconPushSec("Swipe", "swipe", "Edge & Finish")

    IconBlock("Out of Stock", "outOfStock", "Out of Stock", {
        "outDesaturate", "outAlphaEnabled", "outAlpha", "hideWhenMissing",
    })
    IconPushSec("Out of Stock", "outOfStock", "Out of Stock")

    -- Aura Active: drawn on the aura's own engine button, so every row works in
    -- combat and in aura groups. There is no "only in combat" option: the button
    -- cannot be restyled in combat or in instances.
    IconBlock("Look", "auraActive", "Aura Active", {
        "overlayArt",
        "activeIconFrom", "activeIcon", "activeAlpha", "activeDesaturate", "activeTintEnabled", "activeTintColor",
        "overlayDesatInactive",
    })
    -- A spell icon's aura-phase swipe sits with its aura look (the Cooldown
    -- Manager's gold by default); an aura icon's is on the Swipe tab.
    IconBlock("Swipe", "auraSwipe", "Aura Active", {
        "swipeShow", "overlaySwipeColor", "overlaySwipeReverse",
        "swipeEdge", "edgeColor", "edgeScale", "swipeBling",
    }, "spell")
    IconBlock("Glow", "auraActive", "Aura Active", {
        "activeGlow", "activeGlowWhen", "activeGlowTimeUnit", "activeGlowTimePct",
        "activeGlowTimeSec", "activeGlowAuraLength",
        "activeGlowType", "activeGlowColor", "activeGlowSpeed",
        "activeGlowLines", "activeGlowThickness", "activeGlowLength", "activeGlowParticles",
        "activeGlowIntensity", "activeGlowScale",
        "activeGlowXOffset", "activeGlowYOffset", "activeGlowMoveX", "activeGlowMoveY",
        "activeGlowStrata", "activeGlowLevel",
    })
    IconPushSec("Aura Active", "auraActive", "Look")
    IconPushSec("Aura Active", "auraSwipe", "Swipe")
    IconPushSec("Aura Active", "auraActive", "Glow")

    local missVis = IconBlock("Aura Missing", "auraMissing", "Aura Missing", {
        "showWhileMissing", "missingIconFrom", "missingIcon", "missingDesaturate", "missingAlpha",
        "missingPreserveText",
    })
    -- A Dynamic aura group drops missing auras from its live rows, so this
    -- look shows only while the panel is open.
    AT.RowDesc(pg, "In a Dynamic group a missing aura leaves the row: this shows only while editing.", 20,
        function()
            if not missVis() then return false end
            local r = SelIcon()
            local g = r and r.groupId and Store.Get(r.groupId)
            return g ~= nil and g.groupKind == "aura"
                and Store.Resolve(g, "arrangement", "dynamicLayout") == true
        end)
    IconPushSec("Aura Missing", "auraMissing", "Aura Missing")

    -- the engine button's swipe is our own Cooldown widget (aura icons; a
    -- spell icon's aura phase has its own Swipe chip under Aura Active)
    IconBlock("Aura Swipe", "auraSwipe", "Swipe", {
        "swipeShow", "swipeColor", "swipeReverse", "swipeEdge", "edgeColor", "edgeScale", "swipeBling",
    }, "aura")
    IconPushSec("Swipe", "auraSwipe", "Aura Swipe")

    local durTextVis = IconBlock("Duration Text", "text", "Text", {
        "durationText", "durationRounding", "durationFont", "durationSize", "durationColor", "durationOutline",
        "durationShadow", "durationAnchor", "durationX", "durationY",
    })
    IconSub(durTextVis, "Text", "Duration Text", "Format", "text", {
        "durationAbbrev", "durationDecimals", "durationDecimalThreshold",
        "hideDurWithCharges",
    })
    IconSub(durTextVis, "Text", "Duration Text", "Color by time left", "text", {
        "durationColorBands",
        "durBand1Sec", "durBand1Color",
        "durBand2Sec", "durBand2Color",
        "durBand3Sec", "durBand3Color",
    })
    local stackTextVis = IconBlock("Stack & Charges", "text", "Text", {
        "stackText", "stackFont", "stackSize", "stackColor", "stackOutline", "stackShadow",
        "stackAnchor", "stackX", "stackY", "hideChargeAtZero",
        "stackShowSingle",
    })
    IconSub(stackTextVis, "Text", "Stack & Charges", "Color by count", "text", {
        "stackColorBands",
        "stkBand1Min", "stkBand1Color", "stkBand2Min", "stkBand2Color",
        "stkBand3Min", "stkBand3Color",
    })
    IconBlock("Ammo Stack Text", "text", "Text", {
        "ammoText", "ammoFont", "ammoSize", "ammoColor", "ammoOutline", "ammoShadow",
        "ammoAnchor", "ammoX", "ammoY",
    })
    IconPushSec("Text", "text", "Duration Text")
    IconPushSec("Text", "text", "Stack & Charges")
    IconPushSec("Text", "text", "Ammo Stack Text")

    IconBlock("Label 1", "label", "Label", {
        "labelText", "labelFont", "labelSize", "labelColor", "labelAnchor",
        "labelX", "labelY", "labelShowReady", "labelShowCooldown",
    })
    IconBlock("Label 2", "label", "Label", {
        "labelText2", "labelSize2", "labelColor2", "labelAnchor2",
        "labelX2", "labelY2", "labelShowReady2", "labelShowCooldown2",
    })
    IconBlock("Label 3", "label", "Label", {
        "labelText3", "labelSize3", "labelColor3", "labelAnchor3",
        "labelX3", "labelY3", "labelShowReady3", "labelShowCooldown3",
    })
    IconPushSec("Label", "label", "Label 1")
    IconPushSec("Label", "label", "Label 2")
    IconPushSec("Label", "label", "Label 3")

    IconBlock("Keybind", "keybind", "Keybind", {
        "keybindEnabled", "keybindByName", "keybindFont", "keybindSize", "keybindColor",
        "keybindAnchor", "keybindX", "keybindY",
    })
    AT.RowDesc(pg, "Match by spell name finds this spell's key at any rank on your bars.", 20,
        function()
            if not IconTabVisible("Keybind")() then return false end
            return NS.IsForever == true
        end)
    IconPushSec("Keybind", "keybind", "Keybind")

    IconBlock("Alerts", "alerts", "Alerts", {
        "soundChannel",
        "readySoundEnabled", "readySound",
        "cooldownSoundEnabled", "cooldownSound",
        "rechargeSoundEnabled", "rechargeSound",
        "chargeGainedSoundEnabled", "chargeGainedSound",
    })
    IconPushSec("Alerts", "alerts", "Alerts")

    return pg
end

-- Group pane

local function RefreshGroupStrip()
    local group = SelGroup()
    if not group then return end
    local icons = Store.IconsOf(group)
    for i, rec in ipairs(icons) do
        local b = stripPool[i]
        if not b then
            b = IconButton(groupStrip, 32)
            stripPool[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("LEFT", 8 + (i - 1) * 37, 0)
        b.tex:SetTexture(Factory.GetTexture(rec))
        b:SetSelected(ui.selIconId == rec.id and ui.grpMode == "ico")
        b:SetScript("OnClick", function()
            ui.selIconId = rec.id
            ui.grpMode = "ico"
            RefreshAll()
        end)
        b:Show()
    end
    for i = #icons + 1, #stripPool do stripPool[i]:Hide() end
    groupStrip.add:ClearAllPoints()
    groupStrip.add:SetPoint("LEFT", 8 + #icons * 37, 0)
end

local function RefreshGroupPane()
    local group = SelGroup()
    if not group then return end
    local layout = Store.Get(group.layoutId)
    groupHeader.name:SetText(group.name)
    local btext, restricted = Store.BadgeText(group)
    groupHeader.chip1:Set(btext, restricted and PURPLE or SHR)
    if group.groupKind == "aura" then
        groupHeader.chip2:Set("Aura Group", PURPLE)
    else
        groupHeader.chip2:Set("CD Group", YELLOW)
    end
    groupHeader.sub:SetText(layout and ("in " .. layout.name) or "")
    RefreshGroupStrip()
    if ui.grpMode == "ico" then
        local rec = SelIcon()
        if not rec or rec.groupId ~= group.id then
            local icons = Store.IconsOf(group)
            ui.selIconId = icons[1] and icons[1].id or nil
            if not ui.selIconId then ui.grpMode = "grp" end
        end
    end
    local iconRec = SelIcon()
    local icoTabName = iconRec and ("Icon: " .. iconRec.name) or "Icon: none"
    switchStrip:Set({ "Group Settings", icoTabName },
        ui.grpMode == "ico" and icoTabName or "Group Settings",
        function(name)
            if name == "Group Settings" then
                ui.grpMode = "grp"
                RefreshAll()
            elseif ui.selIconId then
                ui.grpMode = "ico"
                RefreshAll()
            end
        end, 11)
    groupEditorPage:SetShown(ui.grpMode == "grp")
    iconEditorPage:SetParent(groupPane)
    iconEditorPage:ClearAllPoints()
    local prevH = AttachPreview(groupPane, -116, ui.grpMode == "ico")
    iconEditorPage:SetPoint("TOPLEFT", 0, -116 - prevH)
    iconEditorPage:SetPoint("BOTTOMRIGHT", 0, 0)
    iconEditorPage:SetShown(ui.grpMode == "ico")
    if ui.grpMode == "grp" then
        AT.LayoutPage(groupEditorPage)
    else
        AT.LayoutPage(iconEditorPage)
    end
end

local function BuildGroupPane()
    groupPane = CreateFrame("Frame", nil, content)
    groupPane:SetAllPoints()
    panes.group = groupPane
    groupHeader = MakeHeader(groupPane)

    local addIcon = AT.MakeSmallButton(groupPane, "+ Add Icon", 82)
    addIcon:SetPoint("TOPRIGHT", -4, -2)
    addIcon.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    addIcon:SetScript("OnClick", function()
        local group = SelGroup()
        if group then Options.OpenAdd(group.layoutId, group.id) end
    end)
    local del = AT.MakeSmallButton(groupPane, "Delete", 56)
    del:SetPoint("RIGHT", addIcon, "LEFT", -5, 0)
    del:SetScript("OnClick", function() Options.ConfirmDelete(SelGroup()) end)

    groupStrip = CreateFrame("Frame", nil, groupPane, "BackdropTemplate")
    groupStrip:SetPoint("TOPLEFT", 0, -36)
    groupStrip:SetPoint("TOPRIGHT", -4, -36)
    groupStrip:SetHeight(44)
    AT.Skin(groupStrip, COL.well, COL.line)
    groupStrip.add = AT.MakeSmallButton(groupStrip, "+", 32)
    groupStrip.add:SetHeight(32)
    groupStrip.add:SetScript("OnClick", function()
        local group = SelGroup()
        if group then Options.OpenAdd(group.layoutId, group.id) end
    end)

    -- The Group Settings | Icon switcher, a nested tab strip.
    switchStrip = AT.TabRow(groupPane)
    switchStrip:SetPoint("TOPLEFT", 0, -84)
    switchStrip:SetPoint("TOPRIGHT", -4, -84)
    switchStrip:SetHeight(28)

    groupEditorPage = AT.NewPage(groupPane)
    AT.MakeScrollable(groupEditorPage)
    groupEditorPage:SetPoint("TOPLEFT", 0, -116)
    groupEditorPage:SetPoint("BOTTOMRIGHT", 0, 0)
    groupEditorPage:Show()
    local pg = groupEditorPage

    local ghd = AT.AddRow(pg, 30)
    local gbg = CreateFrame("Frame", nil, ghd, "BackdropTemplate")
    gbg:SetPoint("TOPLEFT", 0, 0)
    gbg:SetPoint("BOTTOMRIGHT", 0, 4)
    AT.Skin(gbg, COL.panel, COL.arcDeep)
    ghd._fs = gbg:CreateFontString(nil, "OVERLAY")
    ghd._fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    ghd._fs:SetPoint("LEFT", 10, 0)
    ghd._fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    ghd._chip = KindPill(gbg)
    ghd._chip:SetPoint("LEFT", ghd._fs, "RIGHT", 8, 0)
    BandActions(gbg, ghd._fs, SelGroup, { hide = { ghd._chip } })
    ghd._sync = function()
        local g = SelGroup()
        ghd._fs:SetText("Editing:  " .. ((g and g.name) or ""))
        if g then GroupPill(ghd._chip, g.groupKind) end
    end

    -- Both kinds have Dynamic: on an aura group it is the live-view switch,
    -- with the Alignment that pins the row.
    local tabs = { "Arrangement", "Dynamic", "Position", "Anchoring", "Mouse", "Visibility", "Load Conditions" }
    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel   -- strips inside panel-bodied pages
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local h = tabRow._strip:Set(tabs, ui.grpTab, function(name)
            ui.grpTab = name
            AT.LayoutPage(pg)
        end)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Arrangement sub-tabs: a second strip under the tab row, one titled box and
    -- one push bar per sub-panel. Aura groups have no Keybinds.
    ui.grpSec = ui.grpSec or "Grid"
    local GRP_SECS = { "Grid", "Icons", "Container", "Keybinds" }
    local GRP_SECS_AURA = { "Grid", "Icons", "Container" }
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.group = { page = pg, tabs = tabs, subs = function(tab)
        if tab ~= "Arrangement" then return {} end
        local g = SelGroup()
        return (g and g.groupKind == "aura") and GRP_SECS_AURA or GRP_SECS
    end }
    local secRow = AT.AddRow(pg, 30, function()
        return ui.grpTab == "Arrangement" and SelGroup() ~= nil
    end)
    secRow._strip = AT.TabRow(secRow)
    secRow._strip._openFill = COL.panel
    secRow._strip:SetPoint("TOPLEFT", 8, 0)
    secRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    secRow._sync = function()
        local g = SelGroup()
        local list = (g and g.groupKind == "aura") and GRP_SECS_AURA or GRP_SECS
        local ok = false
        for _, t in ipairs(list) do if t == ui.grpSec then ok = true end end
        if not ok then ui.grpSec = list[1] end
        local h = secRow._strip:Set(list, ui.grpSec, function(name)
            ui.grpSec = name
            AT.LayoutPage(pg)
        end, 11)
        local want = (h or 24) + 6
        if secRow._h ~= want then secRow._h = want secRow:SetHeight(want) end
    end
    local function GrpSec(name)
        return function() return ui.grpTab == "Arrangement" and ui.grpSec == name end
    end

    -- Alignment: the choices follow the grid's shape and the value is read
    -- through the engine, so the panel shows what the placement really uses; a
    -- value saved on another shape reads as its remapped equivalent.
    local ALIGN_TEXT = { left = "Left", center = "Center", right = "Right",
        top = "Top", bottom = "Bottom",
        center_h = "Center horizontal", center_v = "Center vertical" }
    local ALIGN_ORDER = {
        horizontal = { "left", "center", "right" },
        vertical = { "top", "center", "bottom" },
        multi = { "top", "bottom", "left", "right", "center_h", "center_v" },
    }
    local function AlignmentRow(visible)
        return AT.RowDropdown(pg, win, "Alignment",
            function()
                local g = SelGroup()
                return g and Engine.EffectiveAlignment(g) or "center"
            end,
            function(v)
                local g = SelGroup()
                if g then Store.SetOverride(g, "arrangement", "alignment", v) end
            end,
            function()
                local g = SelGroup()
                local shape = "horizontal"
                if g then shape = select(2, Engine.EffectiveAlignment(g)) end
                local items = {}
                for _, v in ipairs(ALIGN_ORDER[shape]) do
                    items[#items + 1] = { value = v, text = ALIGN_TEXT[v] }
                end
                return items
            end,
            visible)
    end
    local function GroupShape()
        local g = SelGroup()
        return g and select(2, Engine.EffectiveAlignment(g)) or "horizontal"
    end

    -- Grid: the cells; Icons: what fills them (both live in the one
    -- `arrangement` section, so each push bar carries its own field list)
    local GRID_FIELDS = { "rows", "cols", "growthH", "growthV", "lockGridSize", "containerPadding" }
    local ICON_FIELDS = { "iconSize", "iconWidth", "iconHeight", "spacing", "separateSpacing", "spacingX", "spacingY" }
    AT.Section(pg, "Grid", { visibleFn = GrpSec("Grid") })
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, GrpSec("Grid"), GRID_FIELDS)
    Options.LookBlock("iconGroup", "Arrangement", "Grid", "arrangement", GRID_FIELDS)
    -- Alignment is on the Dynamic tab, not here: it pins the live row, which
    -- exists only while Dynamic is on.
    PushBar(pg, SelGroup, "arrangement", GrpSec("Grid"), GRID_FIELDS)
    AT.Section(pg, "Icons", { visibleFn = GrpSec("Icons") })
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, GrpSec("Icons"), ICON_FIELDS)
    Options.LookBlock("iconGroup", "Arrangement", "Icons", "arrangement", ICON_FIELDS)
    PushBar(pg, SelGroup, "arrangement", GrpSec("Icons"), ICON_FIELDS)
    AT.Section(pg, "Dynamic", { visibleFn = function() return ui.grpTab == "Dynamic" end })
    local dynVis = function() return ui.grpTab == "Dynamic" end
    local dynOn = function()
        local g = SelGroup()
        return dynVis() and g ~= nil
            and Store.Resolve(g, "arrangement", "dynamicLayout") == true
    end
    -- The texts differ by kind: a CD group drops icons out by state; an aura
    -- group's toggle is the live-view switch.
    local dynAura = function()
        local g = SelGroup()
        return dynVis() and g ~= nil and g.groupKind == "aura"
    end
    local dynCD = function()
        local g = SelGroup()
        return dynVis() and g ~= nil and g.groupKind ~= "aura"
    end
    AT.RowDesc(pg, "Icons pack while you play; with this window open each keeps its own cell.", 20, dynCD)
    AT.RowDesc(pg, "On: only the auras that are up show, packed. Off: every aura keeps its cell.", 20, dynAura)
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, dynVis, { "dynamicLayout" })
    do
        -- The search walks one sample group per kind, mostly static ones: hand
        -- it the gate without the Dynamic check plus that switch, so "alignment"
        -- is found on any group and the jump flashes the toggle.
        local row = AlignmentRow(dynOn)
        row._adMeta = { family = "iconGroup", section = "arrangement", field = "alignment",
            def = { label = "Alignment",
                dep = { field = "dynamicLayout", value = true } },
            baseVis = dynVis }
    end
    AT.RowDesc(pg, "Icon order only applies to a single row or column.", 20,
        function() return dynOn() and dynCD() and GroupShape() == "multi" end)
    AT.RowDesc(pg, "Live rows show buffs on you or your pet and debuffs on your target.", 20,
        function() return dynOn() and dynAura() end)
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, dynVis, { "dynamicCollapse" })
    AT.RowDesc(pg, "Aura icons always keep their cell; for auras that come and go, use an Aura Group.", 20,
        function() return dynOn() and dynCD() end)
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, dynVis, {
        "dynamicOrder", "dynamicShrink", "smoothMovement", "smoothDuration",
    })
    Options.LookBlock("iconGroup", "Dynamic", "Dynamic", "arrangement", {
        "dynamicLayout", "dynamicCollapse", "dynamicOrder", "dynamicShrink",
        "smoothMovement", "smoothDuration",
    })
    PushBar(pg, SelGroup, "arrangement", dynVis, {
        "dynamicLayout", "alignment", "dynamicCollapse", "dynamicOrder",
        "dynamicShrink", "smoothMovement", "smoothDuration",
    })
    VisibilityRows(pg, SelGroup, function() return ui.grpTab == "Visibility" end)
    -- Anchoring tab: the one-pick surface bars use. NS.Anchor.PickSet writes
    -- enabled, kind and target together, so a half-applied pick cannot exist.
    local anchVis = function() return ui.grpTab == "Anchoring" end
    -- Its own section: without one these rows land in the Dynamic tab's box,
    -- whose visibleFn hides them on every other tab.
    AT.Section(pg, "Anchor to", { visibleFn = anchVis })
    AT.RowDropdown(pg, win, "Anchor to",
        function() return NS.Anchor and NS.Anchor.PickGet(SelGroup()) or "none" end,
        function(v) if NS.Anchor then NS.Anchor.PickSet(SelGroup(), v) end end,
        function()
            local g = SelGroup()
            if not (g and NS.Anchor) then return { { value = "none", text = "None (free position)" } } end
            return NS.Anchor.PickList(g)
        end,
        anchVis)
    AT.RowInput(pg, "Frame name",
        function()
            local g = SelGroup()
            return g and (Store.Resolve(g, "anchor", "anchorTargetFrame") or "") or ""
        end,
        function(v)
            local g = SelGroup()
            if g then Store.SetOverride(g, "anchor", "anchorTargetFrame", v or "") end
        end,
        function()
            return anchVis() and NS.Anchor ~= nil and NS.Anchor.IsFramePick(SelGroup())
        end,
        "Any frame's global name, e.g. PlayerFrame.",
        "PlayerFrame")
    local gAnchorStatus = AT.AddRow(pg, 22, anchVis)
    local gAnchorFS = gAnchorStatus:CreateFontString(nil, "OVERLAY")
    gAnchorFS:SetFont(STANDARD_TEXT_FONT, 11, "")
    gAnchorFS:SetPoint("LEFT", 10, 0)
    gAnchorFS:SetPoint("RIGHT", -10, 0)
    gAnchorFS:SetJustifyH("LEFT")
    gAnchorFS:SetWordWrap(false)
    gAnchorStatus._sync = function()
        local g = SelGroup()
        if not (g and NS.Anchor) then gAnchorFS:SetText("") return end
        local on = NS.Anchor.IsEnabled(g) and NS.Anchor.ResolveTarget(g) ~= nil
        gAnchorFS:SetText(NS.Anchor.DescribePick(g))
        if on then gAnchorFS:SetTextColor(0.48, 0.85, 0.56)
        else gAnchorFS:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3]) end
    end
    SectionRows(pg, "iconGroup", "anchor", SelGroup, anchVis,
        { "anchorSrcPoint", "anchorDstPoint", "anchorOffsetX", "anchorOffsetY",
          "anchorMatchWidth", "anchorMatchWidthAdjust" })
    Options.AnchoredHereRows(pg, SelGroup, anchVis)
    -- Mouse tab: the group tier of the click-through and tooltip chain.
    AT.Section(pg, "Mouse", { visibleFn = function() return ui.grpTab == "Mouse" end })
    AT.RowDesc(pg, "Applies to every icon in this group; an icon can override it.", 20,
        function() return ui.grpTab == "Mouse" end)
    SectionRows(pg, "iconGroup", "mouse", SelGroup,
        function() return ui.grpTab == "Mouse" end,
        { "clickThrough", "showTooltip" })
    PushBar(pg, SelGroup, "mouse", function() return ui.grpTab == "Mouse" end,
        { "clickThrough", "showTooltip" })
    AT.Section(pg, "Container", { visibleFn = GrpSec("Container") })
    SectionRows(pg, "iconGroup", "look", SelGroup, GrpSec("Container"))
    Options.LookBlock("iconGroup", "Arrangement", "Container", "look", {
        "showBackground", "bgColor", "showBorder", "borderColor",
    })
    PushBar(pg, SelGroup, "look", GrpSec("Container"))
    -- Keybinds sub-panel: cooldown groups only. The section's kinds keep the
    -- row off aura groups; the chip, description and push bar follow suit.
    local kbGrpVis = function()
        local g = SelGroup()
        return GrpSec("Keybinds")() and g ~= nil and g.groupKind ~= "aura"
    end
    AT.Section(pg, "Keybinds", { visibleFn = kbGrpVis })
    SectionRows(pg, "iconGroup", "keybind", SelGroup, kbGrpVis)
    Options.LookBlock("iconGroup", "Arrangement", "Keybinds", "keybind", { "showKeybinds" })
    AT.RowDesc(pg, "Each icon's own Keybind tab sets the text's size, color and position.", 20, kbGrpVis)
    PushBar(pg, SelGroup, "keybind", kbGrpVis)
    local grpPosVis = function() return ui.grpTab == "Position" end
    AT.Section(pg, "Position", { visibleFn = grpPosVis })
    Options.PosRows(pg, SelGroup, grpPosVis, function(r)
        -- "anchored" = actually pinned right now: an anchor whose target
        -- is gone or hidden places free, so the sliders drive rec.pos there
        return NS.Anchor ~= nil and NS.Anchor.ResolveTarget(r) ~= nil
    end)
    AT.Section(pg, "Frame", { visibleFn = grpPosVis })
    SectionRows(pg, "iconGroup", "frame", SelGroup, grpPosVis)
    AT.Section(pg, nil)
    ConditionRows(pg, SelGroup, function() return ui.grpTab == "Load Conditions" end)

    iconEditorPage = BuildIconEditor(groupPane)
end

-- Free pane

local function RefreshFreePane()
    local layout = SelLayout()
    if not layout then return end
    local _, freeIcons = Store.ChildrenOf(layout)
    -- The pane edits one free icon: pick one of this layout before titling.
    local sel = SelIcon()
    if not sel or sel.layoutId ~= layout.id or sel.groupId then
        ui.selIconId = freeIcons[1] and freeIcons[1].id or nil
        sel = SelIcon()
    end
    freeHeader.name:SetText(sel and sel.name or "Free Icon")
    freeHeader.chip1:Hide()
    freeHeader.chip2:Set(Options.IconPillText(sel and sel.kind))
    freeHeader.sub:SetText("in " .. layout.name .. " - keeps its own position and conditions")
    freeStrip:Hide()
    for i, rec in ipairs(freeIcons) do
        local b = freeStripPool[i]
        if not b then
            b = IconButton(freeStrip, 32)
            freeStripPool[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("LEFT", 8 + (i - 1) * 37, 0)
        b.tex:SetTexture(Factory.GetTexture(rec))
        b:SetSelected(ui.selIconId == rec.id)
        b:SetScript("OnClick", function()
            ui.selIconId = rec.id
            RefreshAll()
        end)
        b:Show()
    end
    for i = #freeIcons + 1, #freeStripPool do freeStripPool[i]:Hide() end
    freeStrip.add:ClearAllPoints()
    freeStrip.add:SetPoint("LEFT", 8 + #freeIcons * 37, 0)
    iconEditorPage:SetParent(freePane)
    iconEditorPage:ClearAllPoints()
    local prevH = AttachPreview(freePane, -38, ui.selIconId ~= nil)
    iconEditorPage:SetPoint("TOPLEFT", 0, -38 - prevH)
    iconEditorPage:SetPoint("BOTTOMRIGHT", 0, 0)
    iconEditorPage:SetShown(ui.selIconId ~= nil)
    if ui.selIconId then AT.LayoutPage(iconEditorPage) end
end

local function BuildFreePane()
    freePane = CreateFrame("Frame", nil, content)
    freePane:SetAllPoints()
    panes.free = freePane
    freeHeader = MakeHeader(freePane)
    local addIcon = AT.MakeSmallButton(freePane, "+ Add Icon", 82)
    addIcon:SetPoint("TOPRIGHT", -4, -2)
    addIcon.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    addIcon:SetScript("OnClick", function()
        local layout = SelLayout()
        if layout then Options.OpenAdd(layout.id, nil, true) end
    end)
    freeStrip = CreateFrame("Frame", nil, freePane, "BackdropTemplate")
    freeStrip:SetPoint("TOPLEFT", 0, -36)
    freeStrip:SetPoint("TOPRIGHT", -4, -36)
    freeStrip:SetHeight(44)
    AT.Skin(freeStrip, COL.well, COL.line)
    freeStrip.add = AT.MakeSmallButton(freeStrip, "+", 32)
    freeStrip.add:SetHeight(32)
    freeStrip.add:SetScript("OnClick", addIcon:GetScript("OnClick"))
end

-- Bar pane: a schema-driven editor

-- Live bar preview, pinned above the bar editor like the icon preview. The
-- real bar runtime draws the selected bar on its own preview entry
-- (Bars.PreviewBuild: never the live bar, never an aura container) from
-- simulated plain values. A large bar is fitted with SetScale, then rebuilt
-- once at that scale so its pixel math matches.
local barPrev = { H = 116, STAGE_H = 78, MIN = 78, TALL = 220, scale = 1,
    panX = 0, panY = 0, ZOOMS = { 0.5, 0.75, 1, 1.5, 2, 3, 4 } }

function barPrev.Build(parent)
    local band = CreateFrame("Frame", nil, parent)
    band:SetHeight(barPrev.H)
    band:Hide()
    local stage = CreateFrame("Frame", nil, band, "BackdropTemplate")
    stage:SetPoint("TOPLEFT", 8, -4)
    stage:SetPoint("TOPRIGHT", -12, -4)
    stage:SetHeight(barPrev.STAGE_H)
    AT.Skin(stage, COL.well, COL.line)
    stage:SetClipsChildren(true)
    local holder = CreateFrame("Frame", nil, stage)
    holder:SetPoint("CENTER")
    holder:SetSize(8, 8)
    -- above the nameplate stand-in (stage + 1), set before any preview
    -- shell is built on it
    holder:SetFrameLevel(stage:GetFrameLevel() + 5)
    barPrev.band, barPrev.stage, barPrev.holder = band, stage, holder
    -- the wheel zooms; a held left button pans a bar bigger than the stage
    -- (the OnUpdate lives only while the button is down)
    stage:EnableMouseWheel(true)
    stage:SetScript("OnMouseWheel", function(_, delta) barPrev.Zoom(delta > 0 and 1 or -1) end)
    stage:EnableMouse(true)
    stage:SetScript("OnMouseDown", function(self, btn)
        -- the stage takes the click now, so it closes a pullout like the
        -- window around it does
        AT.CloseDropdown()
        if btn ~= "LeftButton" or not barPrev.canPan then return end
        local x, y = GetCursorPosition()
        local es = self:GetEffectiveScale()
        barPrev.drag = { x = x / es, y = y / es, px = barPrev.panX, py = barPrev.panY }
        self:SetScript("OnUpdate", function(me)
            local d, rec = barPrev.drag, SelBar()
            if not (d and rec) then
                me:SetScript("OnUpdate", nil)
                return
            end
            local cx, cy = GetCursorPosition()
            local e = me:GetEffectiveScale()
            barPrev.panX = d.px + (cx / e - d.x)
            barPrev.panY = d.py + (cy / e - d.y)
            barPrev.Place(rec)
        end)
    end)
    local function EndPan(self)
        barPrev.drag = nil
        self:SetScript("OnUpdate", nil)
    end
    stage:SetScript("OnMouseUp", EndPan)
    stage:SetScript("OnHide", EndPan)
    barPrev.chips = {}
    for i = 1, 2 do
        local b = AT.MakeSmallButton(band, "", 90)
        b:SetScript("OnClick", function(self)
            AT.CloseDropdown()
            ui.barPrevMode = self._key
            if NS.Bars and NS.Bars.PreviewSetMode then NS.Bars.PreviewSetMode(self._key) end
            barPrev.Paint()
        end)
        AT.Tooltip(b, function() return b._title end, function() return b._tip end)
        barPrev.chips[i] = b
    end
    local zOut = AT.MakeSmallButton(band, "-", 24)
    local zPct = AT.MakeSmallButton(band, "100%", 52)
    local zIn = AT.MakeSmallButton(band, "+", 24)
    zOut:SetScript("OnClick", function() barPrev.Zoom(-1) end)
    zIn:SetScript("OnClick", function() barPrev.Zoom(1) end)
    zPct:SetScript("OnClick", function() barPrev.Zoom(0) end)
    AT.Tooltip(zOut, "Zoom out", "Show the bar smaller. The mouse wheel over the preview zooms too.")
    AT.Tooltip(zIn, "Zoom in", "Show the bar bigger. When it no longer fits, drag the preview to look around.")
    AT.Tooltip(zPct, function() return "Zoom: " .. zPct.fs:GetText() end,
        "How big the preview is against the bar's real size. Click to fit the whole bar in view again.")
    barPrev.zOut, barPrev.zPct, barPrev.zIn = zOut, zPct, zIn
    local scr = AT.MakeSmallButton(band, "Play on screen", 118)
    scr:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec, B = SelBar(), NS.Bars
        if not (rec and B and B.PreviewScreenStart) then return end
        if B.PreviewScreenOn(rec.id) then
            B.PreviewScreenStop()
        else
            B.PreviewScreenStart(rec)
        end
        barPrev.Paint()
    end)
    AT.Tooltip(scr, function() return scr.fs:GetText() end,
        "Plays this preview on the bar itself, in its real place and size. Press again, pick something else, or close this window to stop.")
    barPrev.screen = scr
end

-- Play on screen needs the bar's real frame in sight; a bar on a nameplate
-- hides while this window is open.
function barPrev.ScreenOK(rec)
    if barPrev.onPlate then return false end
    local f = Engine and Engine.GetBarFrame and Engine.GetBarFrame(rec.id)
    return f ~= nil and f:IsVisible() == true
end

-- Step the zoom: dir 1 in, -1 out, 0 back to the fit. ui.barPrevZoom
-- multiplies the fit (1 = the whole bar in view). The zoom never changes the
-- stage height, so the editor never moves.
function barPrev.Zoom(dir)
    local Z, z = barPrev.ZOOMS, ui.barPrevZoom or 1
    local nz = 1
    if dir > 0 then
        nz = Z[#Z]
        for _, v in ipairs(Z) do
            if v > z + 0.001 then nz = v break end
        end
    elseif dir < 0 then
        nz = Z[1]
        for i = #Z, 1, -1 do
            if Z[i] < z - 0.001 then nz = Z[i] break end
        end
    end
    -- the spot in the middle of the stage stays in the middle
    barPrev.panX, barPrev.panY = barPrev.panX * nz / z, barPrev.panY * nz / z
    ui.barPrevZoom = nz
    local rec = SelBar()
    if rec and barPrev.band and barPrev.band:IsShown() then
        barPrev.Fit(rec)
        barPrev.Paint()
    end
end

-- the chips for this kind, the active one in the accent, centred under the
-- stage; the loop's OnUpdate on or off with them
function barPrev.Paint()
    local rec, B = SelBar(), NS.Bars
    if not (rec and B and B.PreviewModes and barPrev.band) then return end
    local modes = B.PreviewModes(rec)
    local active = B.PreviewMode and B.PreviewMode() or "loop"
    local widths, total = {}, -6
    for i, m in ipairs(modes) do
        local b = barPrev.chips[i]
        if b then
            b.fs:SetText(m.text)
            widths[i] = math.max(64, math.ceil((b.fs:GetStringWidth() or 40) + 24))
            total = total + widths[i] + 6
        end
    end
    local x = -total / 2
    for i, b in ipairs(barPrev.chips) do
        local m = modes[i]
        if m then
            b._key, b._title, b._tip = m.key, m.text, m.tip
            b:SetWidth(widths[i])
            b:ClearAllPoints()
            b:SetPoint("LEFT", barPrev.band, "TOP", x, -(barPrev.STAGE_H + 4 + 8 + 11))
            x = x + widths[i] + 6
            local c = (m.key == active) and COL.arc or COL.dim
            b.fs:SetTextColor(c[1], c[2], c[3])
            b:Show()
        else
            b:Hide()
        end
    end
    -- the zoom group on the same line, the stage's right edge; the % in the
    -- accent while zoomed away from the fit
    local zy = -(barPrev.STAGE_H + 4 + 8 + 11)
    barPrev.zIn:ClearAllPoints()
    barPrev.zIn:SetPoint("RIGHT", barPrev.band, "TOPRIGHT", -12, zy)
    barPrev.zPct:ClearAllPoints()
    barPrev.zPct:SetPoint("RIGHT", barPrev.zIn, "LEFT", -4, 0)
    barPrev.zOut:ClearAllPoints()
    barPrev.zOut:SetPoint("RIGHT", barPrev.zPct, "LEFT", -4, 0)
    barPrev.zPct.fs:SetText(math.floor(barPrev.scale * 100 + 0.5) .. "%")
    local zc = ((ui.barPrevZoom or 1) ~= 1) and COL.arc or COL.dim
    barPrev.zPct.fs:SetTextColor(zc[1], zc[2], zc[3])
    -- Play on screen on the same line, at the stage's left edge
    local scr = barPrev.screen
    if scr then
        local on = B.PreviewScreenOn and B.PreviewScreenOn(rec.id)
        scr:ClearAllPoints()
        scr:SetPoint("LEFT", barPrev.band, "TOPLEFT", 8, zy)
        scr.fs:SetText(on and "Stop on screen" or "Play on screen")
        local sc = on and COL.arc or COL.dim
        scr.fs:SetTextColor(sc[1], sc[2], sc[3])
        scr:SetShown(barPrev.ScreenOK(rec))
    end
    barPrev.band:SetScript("OnUpdate", (B.PreviewTicking and B.PreviewTicking())
        and function(_, dt) B.PreviewTick(dt) end or nil)
end

-- how far a side icon hangs off a w x h bar: across the stage, down it,
-- and which side it hangs on
function barPrev.IconReach(rec, w, h)
    if Store.Resolve(rec, "icon", "iconShow") ~= true then return 0, 0, nil end
    local isz = Store.Resolve(rec, "icon", "iconSize") or 24
    if Store.Resolve(rec, "icon", "iconFollowBar") == true or isz <= 0 then isz = math.min(w, h) end
    local reach = isz + (Store.Resolve(rec, "icon", "iconSpacing") or 2)
    local side = Store.Resolve(rec, "icon", "iconSide") or "LEFT"
    if side == "TOP" or side == "BOTTOM" then return 0, reach, side end
    return reach, 0, side
end

-- The stand-in nameplate, built once on the stage: the box the bar's points
-- measure against, the health bar where the game lays it, and a name. The
-- live plate bar hides while this window is open.
function barPrev.Plate()
    if barPrev.plate then return barPrev.plate end
    local stage = barPrev.stage
    local f = CreateFrame("Frame", nil, stage)
    f:SetFrameLevel(stage:GetFrameLevel() + 1)
    f.box = f:CreateTexture(nil, "BACKGROUND")
    f.box:SetAllPoints()
    f.box:SetColorTexture(0.03, 0.05, 0.09, 0.55)
    f.edges = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.55)
        f.edges[i] = t
    end
    f.hp = CreateFrame("Frame", nil, f)
    local hpBg = f.hp:CreateTexture(nil, "BACKGROUND")
    hpBg:SetAllPoints()
    hpBg:SetColorTexture(0, 0, 0, 0.9)
    f.hpFill = f.hp:CreateTexture(nil, "ARTWORK")
    f.hpFill:SetColorTexture(0.78, 0.18, 0.16, 0.95)
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    f.name:SetPoint("BOTTOM", f.hp, "TOP", 0, 2)
    f.name:SetTextColor(1, 0.82, 0.1)
    f.name:SetText("Target")
    f.tag = f:CreateFontString(nil, "OVERLAY")
    f.tag:SetFont(STANDARD_TEXT_FONT, 8, "")
    f.tag:SetPoint("TOPLEFT", 3, -3)
    f.tag:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    f.tag:SetText("Nameplate stand-in")
    f:Hide()
    barPrev.plate = f
    return f
end

-- Size the plate from the game's shape and lay its health bar out. The edges
-- are hairlines at the plate's current scale, so call this after SetScale.
function barPrev.PlateLayout()
    local f, shape = barPrev.Plate(), barPrev.shape
    if not shape then return end
    f:SetSize(shape.w, shape.h)
    local t = AT.Hairline(f)
    local e = f.edges
    for i = 1, 4 do e[i]:ClearAllPoints() end
    e[1]:SetPoint("TOPLEFT") e[1]:SetPoint("TOPRIGHT") e[1]:SetHeight(t)
    e[2]:SetPoint("BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT") e[2]:SetHeight(t)
    e[3]:SetPoint("TOPLEFT") e[3]:SetPoint("BOTTOMLEFT") e[3]:SetWidth(t)
    e[4]:SetPoint("TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT") e[4]:SetWidth(t)
    f.hp:ClearAllPoints()
    f.hp:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", shape.hpInset, shape.hpBottom)
    f.hp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -shape.hpInset, shape.hpBottom)
    f.hp:SetHeight(shape.hpHeight)
    f.hpFill:ClearAllPoints()
    f.hpFill:SetPoint("TOPLEFT", f.hp, "TOPLEFT", t, -t)
    f.hpFill:SetPoint("BOTTOMRIGHT", f.hp, "BOTTOMRIGHT", -t, t)
end

-- The plate and a w x h bar (with its side icon) as one box, in the bar's
-- units: its size and the plate centre's offset from the box centre. The bar
-- sits where its points put it, as the live pin does; no rect reads.
function barPrev.PlateContent(rec, w, h)
    local iw, ih, side = barPrev.IconReach(rec, w, h)
    local shape = barPrev.shape
    local pw, ph = shape.w, shape.h
    local src, dst, ox, oy = NS.Anchor.PlatePoints(rec)
    local function AX(p, len) return (p:find("LEFT") and 0) or (p:find("RIGHT") and len) or len / 2 end
    local function AY(p, len) return (p:find("BOTTOM") and 0) or (p:find("TOP") and len) or len / 2 end
    -- the bar's bottom-left corner, from the plate's bottom-left
    local bl = AX(dst, pw) + ox - AX(src, w)
    local bb = AY(dst, ph) + oy - AY(src, h)
    local minX = math.min(0, bl - ((side == "LEFT") and iw or 0))
    local maxX = math.max(pw, bl + w + ((side == "RIGHT") and iw or 0))
    local minY = math.min(0, bb - ((side == "BOTTOM") and ih or 0))
    local maxY = math.max(ph, bb + h + ((side == "TOP") and ih or 0))
    return maxX - minX, maxY - minY, pw / 2 - (minX + maxX) / 2, ph / 2 - (minY + maxY) / 2
end

-- The stage height this bar gets: MIN when it fits at full size, else TALL
-- (from the settings, before the build). Two fixed steps, not the bar's own
-- height: a band that tracked the Height slider would slide the editor, and
-- the slider, out from under the cursor during a drag.
function barPrev.StageFor(rec)
    local sc = Store.Resolve(rec, "size", "scale") or 1
    local w = math.max(8, (Store.Resolve(rec, "size", "width") or 220) * sc)
    local h = math.max(4, (Store.Resolve(rec, "size", "height") or 16) * sc)
    local _, ih = barPrev.IconReach(rec, w, h)
    return (h + ih + 20 <= barPrev.MIN) and barPrev.MIN or barPrev.TALL
end

-- The scale that fits the built bar and its side icon inside the stage,
-- never above 1. The icon's reach is reserved on its own side only (Place
-- shifts the bar away from it), not on both.
function barPrev.FitScale(rec)
    local holder, stage = barPrev.holder, barPrev.stage
    local w, h = holder:GetWidth() or 0, holder:GetHeight() or 0
    if w <= 0 or h <= 0 then return 1 end
    local iw, ih = barPrev.IconReach(rec, w, h)
    local sw = stage:GetWidth() or 0
    if sw > 0 then barPrev.refitTries = 0 end
    if sw <= 0 then
        -- The first pass after the band is placed has no width yet: fit again
        -- next frame, capped at 3 tries so a band that never gets a width cannot
        -- spin a timer.
        sw = ((barPane and barPane:GetWidth()) or 0) - 20
        if sw <= 0 then sw = 700 end
        barPrev.refitTries = (barPrev.refitTries or 0) + 1
        if not barPrev.refitQueued and barPrev.refitTries <= 3 then
            barPrev.refitQueued = true
            C_Timer.After(0, function()
                barPrev.refitQueued = nil
                if barPrev.band and barPrev.band:IsShown() and Options.RefreshPane then
                    Options.RefreshPane()
                end
            end)
        end
    end
    local s
    if barPrev.onPlate then
        local cw, ch = barPrev.PlateContent(rec, w, h)
        s = math.min(1, (sw - 32) / cw, (barPrev.STAGE_H - 20) / ch)
    else
        local availW = sw - 32 - iw
        local availH = barPrev.STAGE_H - 20 - ih
        s = math.min(1, availW / w, availH / h)
    end
    if s < 0.15 then s = 0.15 end
    return s
end

-- The scale the bar shows at (the fit times the zoom). A new scale rebuilds
-- the bar once so its pixel math matches; then it is placed.
function barPrev.Fit(rec)
    local holder = barPrev.holder
    local s = barPrev.FitScale(rec) * (ui.barPrevZoom or 1)
    s = math.max(0.15, math.min(8, s))
    if math.abs(s - barPrev.scale) > 0.001 then
        barPrev.scale = s
        holder:SetScale(s)
        if barPrev.plate then barPrev.plate:SetScale(s) end
        NS.Bars.PreviewBuild(rec, holder)
    end
    -- the plate's hairlines are measured at its final scale
    if barPrev.onPlate then barPrev.PlateLayout() end
    barPrev.Place(rec)
end

-- centre the bar with its side icon, moved by the pan; the pan is held
-- inside the overflow, and only a bar bigger than the stage can pan
function barPrev.Place(rec)
    local holder, stage, s = barPrev.holder, barPrev.stage, barPrev.scale
    local w, h = holder:GetWidth() or 0, holder:GetHeight() or 0
    local iw, ih, side = barPrev.IconReach(rec, w, h)
    local cw, ch = w + iw, h + ih
    local sx = (side == "LEFT" and iw / 2) or (side == "RIGHT" and -iw / 2) or 0
    local sy = (side == "BOTTOM" and ih / 2) or (side == "TOP" and -ih / 2) or 0
    -- on a nameplate the plate and the bar are one box, placed by the plate
    if barPrev.onPlate then cw, ch, sx, sy = barPrev.PlateContent(rec, w, h) end
    local sw = stage:GetWidth() or 0
    if sw <= 0 then sw = 700 end
    local mx = math.max(0, (cw * s - (sw - 16)) / 2)
    local my = math.max(0, (ch * s - (barPrev.STAGE_H - 16)) / 2)
    barPrev.panX = math.max(-mx, math.min(mx, barPrev.panX))
    barPrev.panY = math.max(-my, math.min(my, barPrev.panY))
    barPrev.canPan = mx > 0 or my > 0
    if barPrev.onPlate then
        local plate = barPrev.Plate()
        plate:ClearAllPoints()
        -- SetPoint offsets are in the plate's own (scaled) units
        plate:SetPoint("CENTER", stage, "CENTER", sx + barPrev.panX / s, sy + barPrev.panY / s)
        -- the bar on the plate, as the live pin places it
        local src, dst, ox, oy = NS.Anchor.PlatePoints(rec)
        holder:ClearAllPoints()
        holder:SetPoint(src, plate, dst, ox, oy)
        return
    end
    holder:ClearAllPoints()
    -- SetPoint offsets are in the holder's own (scaled) units
    holder:SetPoint("CENTER", stage, "CENTER", sx + barPrev.panX / s, sy + barPrev.panY / s)
end

-- host the band at (parent, y), draw the selected bar in it; returns the
-- height the editor page must leave for it
function barPrev.Attach(parent, y)
    local rec, B, band = SelBar(), NS.Bars, barPrev.band
    if not (band and rec and B and B.PreviewBuild) then
        if band then
            band:Hide()
            band:SetScript("OnUpdate", nil)
        end
        if B and B.PreviewScreenStop then B.PreviewScreenStop() end
        return 0
    end
    band:SetParent(parent)
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    band:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    -- a bar on the target's nameplate previews on the stand-in plate
    local A = NS.Anchor
    barPrev.onPlate = A ~= nil and A.IsPlatePick ~= nil and A.IsPlatePick(rec) == true
    barPrev.shape = barPrev.onPlate and A.PlateShape() or nil
    if barPrev.onPlate then
        barPrev.Plate():Show()
    elseif barPrev.plate then
        barPrev.plate:Hide()
    end
    band:Show()
    -- the kind's chips; the stored choice normalised to them
    local modes = B.PreviewModes(rec)
    local want = ui.barPrevMode or "loop"
    local ok = false
    for _, m in ipairs(modes) do if m.key == want then ok = true end end
    if not ok then want = modes[1].key end
    if B.PreviewMode() ~= want then B.PreviewSetMode(want) end
    local holder = barPrev.holder
    holder:SetScale(barPrev.scale)
    if barPrev.plate then barPrev.plate:SetScale(barPrev.scale) end
    B.PreviewBuild(rec, holder)
    -- the Play on screen copy takes every settings change too
    if B.PreviewScreenOn and B.PreviewScreenOn(rec.id) then
        if barPrev.ScreenOK(rec) then B.PreviewScreenStart(rec) else B.PreviewScreenStop() end
    end
    -- The stage height for this bar; on a nameplate it fits the plate and the
    -- bar together, measured from the built holder (pips size themselves).
    local sh = barPrev.StageFor(rec)
    if barPrev.onPlate then
        local _, ch = barPrev.PlateContent(rec, holder:GetWidth() or 0, holder:GetHeight() or 0)
        sh = (ch + 20 <= barPrev.MIN) and barPrev.MIN or barPrev.TALL
    end
    if sh ~= barPrev.STAGE_H then
        barPrev.STAGE_H = sh
        barPrev.H = sh + 38
        barPrev.stage:SetHeight(sh)
        band:SetHeight(barPrev.H)
    end
    -- another bar starts centred (the zoom carries over: it is the viewer's)
    if barPrev.recId ~= rec.id then
        barPrev.recId, barPrev.panX, barPrev.panY = rec.id, 0, 0
    end
    -- fit x zoom (the holder's own size is scale-free, so the fit is
    -- absolute), rebuilt once at a new scale, then placed
    barPrev.Fit(rec)
    barPrev.Paint()
    return barPrev.H
end
Options._barPrev = barPrev   -- offline harness access
-- the editor tabs a bar kind gets (offline harness access)
function Options._barTabsFor(rec) return BAR_TABS[rec.barKind] or BAR_TABS.cooldown end

local function BarTabVisible(tabName)
    return function()
        local rec = SelBar()
        if not rec then return false end
        local tabs = BAR_TABS[rec.barKind] or BAR_TABS.cooldown
        local listed = false
        for _, t in ipairs(tabs) do
            if t == tabName then listed = true end
        end
        return listed and ui.barTab == tabName
    end
end

local function RefreshBarPane()
    local rec = SelBar()
    if not rec then return end
    local layout = Store.Get(rec.layoutId)
    barHeader.name:SetText(rec.name)
    local btext, restricted = Store.BadgeText(rec)
    barHeader.chip1:Set(btext, restricted and PURPLE or SHR)
    local ptext, pcolor = BarPillText(rec.barKind, rec.barMode)
    barHeader.chip2:Set(ptext, pcolor)
    local sub = layout and ("in " .. layout.name) or ""
    if rec.barMode then
        sub = sub .. "  -  " .. (rec.barMode == "stack" and "stack" or "duration") .. " mode"
    end
    barHeader.sub:SetText(sub)
    local prevH = barPrev.Attach(barPane, -36)
    barEditorPage:ClearAllPoints()
    barEditorPage:SetPoint("TOPLEFT", 0, -36 - prevH)
    barEditorPage:SetPoint("BOTTOMRIGHT", 0, 0)
    AT.LayoutPage(barEditorPage)
end

local function BuildBarPane()
    barPane = CreateFrame("Frame", nil, content)
    barPane:SetAllPoints()
    panes.bar = barPane
    barHeader = MakeHeader(barPane)

    local del = AT.MakeSmallButton(barPane, "Delete", 56)
    del:SetPoint("TOPRIGHT", -4, -2)
    del:SetScript("OnClick", function() Options.ConfirmDelete(SelBar()) end)

    -- the live preview band (RefreshBarPane pins it under the header)
    barPrev.Build(barPane)

    barEditorPage = AT.NewPage(barPane)
    AT.MakeScrollable(barEditorPage)
    barEditorPage:SetPoint("TOPLEFT", 0, -36)
    barEditorPage:SetPoint("BOTTOMRIGHT", 0, 0)
    barEditorPage:Show()
    local pg = barEditorPage

    local hd = AT.AddRow(pg, 30)
    local hbg = CreateFrame("Frame", nil, hd, "BackdropTemplate")
    hbg:SetPoint("TOPLEFT", 0, 0)
    hbg:SetPoint("BOTTOMRIGHT", 0, 4)
    AT.Skin(hbg, COL.panel, COL.arcDeep)
    hd._fs = hbg:CreateFontString(nil, "OVERLAY")
    hd._fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    hd._fs:SetPoint("LEFT", 10, 0)
    hd._fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    hd._chip = KindPill(hbg)
    hd._chip:SetPoint("LEFT", hd._fs, "RIGHT", 8, 0)
    BandActions(hbg, hd._fs, SelBar, { hide = { hd._chip } })
    hd._sync = function()
        local rec = SelBar()
        hd._fs:SetText("Editing:  " .. ((rec and rec.name) or ""))
        if rec then BarPill(hd._chip, rec.barKind, rec.barMode) end
    end

    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel   -- strips inside panel-bodied pages
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local rec = SelBar()
        if not rec then return end
        local tabs = BAR_TABS[rec.barKind] or BAR_TABS.cooldown
        local listed = false
        for _, t in ipairs(tabs) do
            if t == ui.barTab then listed = true end
        end
        if not listed then ui.barTab = tabs[1] end
        local h = tabRow._strip:Set(tabs, ui.barTab, function(name)
            ui.barTab = name
            AT.LayoutPage(pg)
        end)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Tracking: the driver block per kind (retarget re-keys, never re-ids)
    local trackVis = BarTabVisible("Tracking")
    AT.Section(pg, "Tracking", { visibleFn = trackVis })
    AT.RowInput(pg, "Spell ID",
        function()
            local r = SelBar()
            return r and r.driver.spellID and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local r = SelBar()
            if not r then return end
            local sid = tonumber(v)
            if sid then
                r.driver.spellID = sid
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                if nm then r.name = nm end
                Store.Dirty("tree")
                RefreshAll()
            end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and (r.barKind == "cooldown" or r.barKind == "timer")
        end,
        "The tracked spell. Retargeting re-keys the driver and keeps every setting and position.")
    -- ranked realms (WoW Forever): resolve by name each feed so the bar
    -- follows the player's known rank; probe-gated, mirrors the icon driver
    AT.RowToggle(pg, "Auto rank",
        function() local r = SelBar() return r ~= nil and r.driver.autoRank == true end,
        function(v)
            local r = SelBar()
            if r then r.driver.autoRank = v or nil Store.Dirty("style", r.id) end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cooldown"
                and NS.IsForever == true
        end,
        "On ranked realms, track whichever rank of this spell you currently know. Re-resolves on spell changes.")
    AT.RowToggle(pg, "Ignore spell overrides",
        function() local r = SelBar() return r ~= nil and r.driver.ignoreSpellOverride == true end,
        function(v)
            local r = SelBar()
            if r then
                r.driver.ignoreSpellOverride = v and true or nil
                Store.Dirty("style", r.id)
            end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cooldown"
        end,
        "Replacement forms (Windstrike, proc spells) normally drive this bar's cooldown. On = pin the BASE spell instead.")
    AT.RowInput(pg, "Timer duration (s)",
        function()
            local r = SelBar()
            return r and r.driver.duration and tostring(r.driver.duration) or ""
        end,
        function(v)
            local r = SelBar()
            local dur = tonumber(v)
            if r and dur and dur > 0 then
                r.driver.duration = dur
                Store.Dirty("style", r.id)
            end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "timer"
        end,
        "How long the timer runs once triggered.")
    AT.RowDropdown(pg, win, "Trigger",
        function() local r = SelBar() return r and (r.driver.triggerType or "cast") end,
        function(v)
            local r = SelBar()
            if r then r.driver.triggerType = v Store.Dirty("style", r.id) end
        end,
        function()
            return {
                { value = "cast", text = "On spell cast" },
                { value = "auraGained", text = "On aura gained" },
                { value = "auraLost", text = "On aura lost" },
            }
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "timer"
        end)
    AT.RowDropdown(pg, win, "Power type",
        function() local r = SelBar() return r and (r.driver.powerType or 0) end,
        function(v)
            local r = SelBar()
            if r then r.driver.powerType = v Store.Dirty("style", r.id) end
        end,
        function() return POWER_TYPES end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "stack"
        end)
    -- Aura bars: a typed ID commits on Enter; letters search spell names in the
    -- panel under the field, and a pick commits its ID the same way.
    local barAuraVis = function()
        local r = SelBar()
        return trackVis() and r ~= nil and r.barKind == "aura"
    end
    local function CommitBarAura(v)
        local r = SelBar()
        if not r then return end
        local sid = tonumber(v)
        if sid then
            r.driver.spellID = sid
            local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
            if nm then r.name = nm end
            Store.Dirty("tree")
            RefreshAll()
        end
    end
    local rowBarAuraID = AT.RowInput(pg, "Aura name or spell ID",
        function()
            local r = SelBar()
            return r and r.driver.spellID and tostring(r.driver.spellID) or ""
        end,
        CommitBarAura,
        barAuraVis,
        "Type the aura's NAME to see its spell IDs and click one (a bar takes one ID: the rank you cast when you know the spell), or type the numeric ID and press Enter. Retargeting keeps every setting and position.")
    local RefreshBarEdSug = Options.AuraSuggestPanel(pg, barAuraVis,
        function()
            local eb = rowBarAuraID._colCtrl
            return eb and eb:GetText() or ""
        end,
        function(v)
            if rowBarAuraID._colCtrl then rowBarAuraID._colCtrl:SetText(v) end
            CommitBarAura(v)
        end, false)
    -- the field commits on Enter only; the panel follows every keystroke
    if rowBarAuraID._colCtrl then
        rowBarAuraID._colCtrl:HookScript("OnTextChanged", function(_, userInput)
            if userInput then RefreshBarEdSug(false) end
        end)
    end
    AT.RowDropdown(pg, win, "Aura type",
        function() local r = SelBar() return r and (r.driver.auraType or "buff") end,
        function(v)
            local r = SelBar()
            if not r then return end
            local d = r.driver
            -- pin the unit the bar watches now, then move it off a unit this
            -- type cannot match on (the icons' rule)
            local unit = NS.DriverAura.ShapeOf(d)
            d.auraType = v
            if not Options.AuraUnitAllowed(d, unit, v) then unit = "target" end
            d.unit = unit
            Store.Dirty("style", r.id)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        barAuraVis)
    -- On unit and Cast by, read through NS.DriverAura.ShapeOf, so an older bar
    -- record (no unit, an ownOnly flag) shows what it actually does.
    local barUnitRow = AT.RowDropdown(pg, win, "On unit",
        function()
            local r = SelBar()
            return r and (NS.DriverAura.ShapeOf(r.driver))
        end,
        function(v)
            local r = SelBar()
            if not r then return end
            r.driver.unit = v
            Store.Dirty("style", r.id)
        end,
        function()
            local r = SelBar()
            if not r then return {} end
            return Options.AuraUnitItems(r.driver, nil, (NS.DriverAura.ShapeOf(r.driver)))
        end,
        barAuraVis)
    AT.Tooltip(barUnitRow, "On unit", "Who carries the aura. Buffs match on you, your pet, party members, players and friendly targets; debuffs on enemies. The game does not let addons match a buff on an enemy creature or a debuff on a friend by spell ID, so those stay dark (spells the game marks never-secret are the exception).")
    local barCasterRow = AT.RowDropdown(pg, win, "Cast by",
        function()
            local r = SelBar()
            if not r then return "any" end
            local _, _, caster = NS.DriverAura.ShapeOf(r.driver)
            return caster or "any"
        end,
        function(v)
            local r = SelBar()
            if not r then return end
            r.driver.caster = (v ~= "any") and v or nil
            -- ownOnly reads as Cast by = mine; drop it once Cast by is set.
            r.driver.ownOnly = nil
            Store.Dirty("style", r.id)
        end,
        function() return Options.AURA_CASTER_ITEMS end,
        barAuraVis)
    AT.Tooltip(barCasterRow, "Cast by",
        "Anyone: any copy of the aura fills the bar. Me: only yours (or your pet's), so a Blessing from another Paladin is ignored. Anyone but me: only copies other players put up. New debuff bars start on Me, buff bars on Anyone.")
    -- Stack bars need the aura's maximum stacks: the bar and its segments and
    -- stack colors count against it. Empty = the client's own maximum; a typed
    -- number overrides it, and clearing the field hands it back.
    AT.RowInput(pg, "Max stacks",
        function()
            local r = SelBar()
            return r and r.driver.maxStacks and tostring(r.driver.maxStacks) or ""
        end,
        function(v)
            local r = SelBar()
            if not r then return end
            local n = tonumber(v)
            if (v or "") == "" then
                r.driver.maxStacks = nil
                Store.Dirty("style", r.id)
            elseif n and n >= 1 then
                r.driver.maxStacks = math.floor(n)
                Store.Dirty("style", r.id)
            end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "aura" and r.barMode == "stack"
        end,
        "The bar is full at this many stacks. Empty = the maximum the game itself reports for this aura (shown in the field); type a number only when that is wrong.",
        function()
            local r = SelBar()
            local n = r and Options.DetectMaxStacks(r.driver and r.driver.spellID)
            return n and ("game says " .. n) or "unknown - type it (5 until then)"
        end)
    AT.RowDropdown(pg, win, "Swing type",
        function() local r = SelBar() return r and (r.driver.swingType or 0) end,
        function(v)
            local r = SelBar()
            if r then r.driver.swingType = v Store.Dirty("style", r.id) end
        end,
        function() return SWING_TYPES end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "swing"
        end)
    AT.RowDesc(pg, "Swing timers need WoW Forever: this bar stays hidden here.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "swing" and not C_SwingTimer
        end)
    AT.RowDropdown(pg, win, "Power",
        function()
            local r = SelBar()
            return r and (r.driver.powerType or POWER_AUTO)
        end,
        function(v)
            local r = SelBar()
            if r then
                r.driver.powerType = PowerValue(v)
                Store.Dirty("style", r.id)
            end
        end,
        PowerItems,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "resource"
        end)
    AT.RowDesc(pg, "Automatic follows the power you are using right now.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "resource"
        end)
    -- Health bars: whose health.
    AT.RowDropdown(pg, win, "Unit",
        function()
            local r = SelBar()
            return r and (r.driver.unit or "player")
        end,
        function(v)
            local r = SelBar()
            if r then
                r.driver.unit = v
                Store.Dirty("style", r.id)
            end
        end,
        Options.HealthUnitItems,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "health"
        end)
    AT.RowDesc(pg, "Hides while the unit is not there; always shows while this window is open.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "health"
        end)
    -- Castbars: whose casts.
    AT.RowDropdown(pg, win, "Unit",
        function()
            local r = SelBar()
            return r and (r.driver.unit or "player")
        end,
        function(v)
            local r = SelBar()
            if r then
                r.driver.unit = v
                Store.Dirty("style", r.id)
            end
        end,
        Options.CastUnitItems,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cast"
        end)
    AT.RowDesc(pg, "Hides between casts; shows a sample cast while this window is open.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cast"
        end)

    ConditionRows(pg, SelBar, BarTabVisible("Load Conditions"))
    VisibilityRows(pg, SelBar, BarTabVisible("Visibility"))

    -- Section tabs, as in the icon editor. A sub-panel and its push bar both hide
    -- when no field applies to the bar's kind and mode.
    local SEC_LISTS = {}
    local function BlockApplies(rec, def)
        local sec = Schema.bar[def.section]
        if not Schema.Applies(nil, sec, Store.KindOf(rec), rec.barMode) then return false end
        if def.when and not def.when(rec) then return false end
        for _, fname in ipairs(def.fields) do
            local fdef = sec.fields[fname]
            if fdef and Schema.Applies(fdef, sec, Store.KindOf(rec), rec.barMode) then
                return true
            end
        end
        return false
    end
    local function AvailSecs(tabName)
        local rec = SelBar()
        local out = {}
        if not rec then return out end
        for _, def in ipairs(SEC_LISTS[tabName] or {}) do
            if BlockApplies(rec, def) then out[#out + 1] = def.title end
        end
        return out
    end
    -- The settings search walks every tab and applicable sub-panel.
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.bar = { page = pg, subs = AvailSecs }
    ui.barSec = ui.barSec or {}
    local secRow = AT.AddRow(pg, 30, function()
        return SelBar() ~= nil and #AvailSecs(ui.barTab) >= 2
    end)
    secRow._strip = AT.TabRow(secRow)
    secRow._strip._openFill = COL.panel
    secRow._strip:SetPoint("TOPLEFT", 8, 0)
    secRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    secRow._sync = function()
        local avail = AvailSecs(ui.barTab)
        if #avail == 0 then return end
        local cur = ui.barSec[ui.barTab]
        local ok = false
        for _, t in ipairs(avail) do if t == cur then ok = true end end
        if not ok then cur = avail[1] ui.barSec[ui.barTab] = cur end
        local h = secRow._strip:Set(avail, cur, function(name)
            ui.barSec[ui.barTab] = name
            AT.LayoutPage(pg)
        end, 11)
        local want = (h or 24) + 6
        if secRow._h ~= want then secRow._h = want secRow:SetHeight(want) end
    end

    -- when(rec): a per-record gate on top of the schema's kind and mode gates
    -- (a cooldown bar's Stack text exists only for a charge spell).
    local function BarBlock(title, section, tabName, fields, when)
        local def = { title = title, section = section, fields = fields, when = when }
        SEC_LISTS[tabName] = SEC_LISTS[tabName] or {}
        table.insert(SEC_LISTS[tabName], def)
        local tabVis = BarTabVisible(tabName)
        local vis = function()
            if not tabVis() then return false end
            local r = SelBar()
            if not r then return false end
            if not BlockApplies(r, def) then return false end
            local avail = AvailSecs(tabName)
            if #avail >= 2 and ui.barSec[tabName] ~= def.title then return false end
            return true
        end
        -- the block's rows, keyed by its vis: a PushBar handed this `vis`
        -- scopes itself to exactly these fields
        Options.blockFields[vis] = fields
        -- the layout looks mirror it (the tab, for its BarSubs)
        Options.blockTab[vis] = tabName
        Options.LookBlock("bar", tabName, title, section, fields)
        AT.Section(pg, title, { visibleFn = vis })
        SectionRows(pg, "bar", section, SelBar, vis, fields)
        return vis
    end
    -- A titled sub-group inside a block: its rows share the block's visibility
    -- and join its push list; call it after the block's bespoke rows. A block
    -- with subs opens an untitled section before its PushBar, or the push bar
    -- lands in the last sub's section and keeps an all-hidden sub's title up.
    local function BarSub(vis, title, section, fields)
        AT.Section(pg, title, { visibleFn = vis })
        SectionRows(pg, "bar", section, SelBar, vis, fields)
        Options.LookBlock("bar", Options.blockTab[vis], title, section, fields)
        local list = Options.blockFields[vis]
        if list then for _, f in ipairs(fields) do list[#list + 1] = f end end
    end

    -- A resource bar in pips style draws cells: no bar size, fill, marks or
    -- cost preview; the Style block sizes and colours the cells.
    local function IsPips(r)
        return r.barKind == "resource" and Store.Resolve(r, "resource", "style") == "pips"
    end
    local function NotPips(r) return not IsPips(r) end
    -- A block's push list plus the hidden fields its bespoke dropdowns own
    -- (texture, background texture, border style): hidden fields are never in a
    -- block's row list, so a scoped push would miss them.
    local function WithHidden(vis, ...)
        local extra = { ... }
        return function()
            local list = {}
            for _, f in ipairs(Options.blockFields[vis] or {}) do list[#list + 1] = f end
            for _, f in ipairs(extra) do list[#list + 1] = f end
            return list
        end
    end

    local styleVis = BarBlock("Style", "resource", "Appearance", {
        "style", "usePowerColor",
    })
    BarSub(styleVis, "Pips", "resource", {
        "pipShape", "pipWidth", "pipHeight", "pipSpacing", "pointColor", "pipEmptyTint",
    })
    AT.Section(pg, nil, { visibleFn = styleVis })   -- push bar below the subs (BarSub)
    PushBar(pg, SelBar, "resource", styleVis)
    -- Heals & Shields (health bars): one sub-panel per overlay. A health bar's
    -- colour is in the Fill block and its texts on the Text tab.
    local healVis = BarBlock("Incoming Heals", "healpred", "Heals & Shields", {
        "healShow", "healMyColor", "healOtherColor", "healAlpha",
    })
    PushBar(pg, SelBar, "healpred", healVis)
    local absorbVis = BarBlock("Absorb Shields", "healpred", "Heals & Shields", {
        "absorbShow", "absorbStyle", "absorbColor", "absorbAlpha", "absorbOverflow",
    })
    PushBar(pg, SelBar, "healpred", absorbVis)
    local healAbsorbVis = BarBlock("Heal Absorbs", "healpred", "Heals & Shields", {
        "healAbsorbShow", "healAbsorbColor", "healAbsorbAlpha",
    })
    AT.RowDesc(pg, "Effects that eat healing before it lands.", 20, healAbsorbVis)
    PushBar(pg, SelBar, "healpred", healAbsorbVis)
    -- The Castbar tab: one sub-panel per job. Its colours live in the Fill block,
    -- the spell's name and time on the Text tab, its icon in Icon.
    local sparkVis = BarBlock("Spark", "cast", "Castbar", {
        "sparkOn", "sparkColor", "sparkWidth",
    })
    PushBar(pg, SelBar, "cast", sparkVis)
    local holdVis = BarBlock("When a Cast Ends", "cast", "Castbar", {
        "holdOn", "holdTime", "holdFailColor", "holdIntColor", "fadeOut",
    })
    PushBar(pg, SelBar, "cast", holdVis)
    local whichVis = BarBlock("Which Casts", "cast", "Castbar", {
        "hideChannels", "lockHide",
    })
    AT.RowDesc(pg, "The shield is in Appearance > Icon, the color in Appearance > Fill.", 20, whichVis)
    PushBar(pg, SelBar, "cast", whichVis)
    -- Hidden opacity (the behavior section, not pushable): the empty bar
    -- between casts
    local idleVis = BarBlock("Between Casts", "behavior", "Castbar", { "hiddenAlpha" })
    AT.RowDesc(pg, "0 hides the bar between casts.", 20, idleVis)
    -- your own casts only: a player castbar
    local yourVis = BarBlock("Your Casts", "cast", "Castbar", {
        "latencyOn", "latencyColor", "hideBlizzard",
    }, function(r) return (r.driver and r.driver.unit or "player") == "player" end)
    PushBar(pg, SelBar, "cast", yourVis)
    -- bar style only: the bar's own size
    local sizeVis = BarBlock("Bar Size", "size", "Appearance", {
        "width", "height", "scale", "opacity",
    }, NotPips)
    PushBar(pg, SelBar, "size", sizeVis)
    -- pips style: the bar frame is the row of cells, so only scale and
    -- opacity remain meaningful
    local scaleVis = BarBlock("Scale", "size", "Appearance", {
        "scale", "opacity",
    }, IsPips)
    PushBar(pg, SelBar, "size", scaleVis)
    -- Pips style: the cells' banding by position lives here (the Thresholds
    -- tab has it for aura stack bars).
    local pointVis = BarBlock("Point Colors", "stackcolors", "Appearance", {
        "scEnabled", "scCount", "sc2Value", "sc2Color", "sc3Value", "sc3Color",
        "sc4Value", "sc4Color", "maxColorEnabled", "maxColor",
    }, IsPips)
    AT.RowDesc(pg, "Each band colors its point and every point after it.", 20, pointVis)
    PushBar(pg, SelBar, "stackcolors", pointVis)
    -- Statusbar textures for the fill, pip and background dropdowns: the
    -- built-ins plus every LibSharedMedia texture when LSM is loaded.
    local function BarTextureItems()
        local items, seen = {}, {}
        for _, k in ipairs({ "Flat", "Blizzard", "Blizzard Raid", "Character Skills" }) do
            items[#items + 1] = { value = k, text = k }
            seen[k] = true
        end
        local lsm = NS.Bars and NS.Bars.GetLSM and NS.Bars.GetLSM()
        if lsm then
            local extra = {}
            for _, name in ipairs(lsm:List("statusbar") or {}) do
                if not seen[name] then extra[#extra + 1] = name end
            end
            table.sort(extra)
            for _, name in ipairs(extra) do
                items[#items + 1] = { value = name, text = name }
            end
        end
        return items
    end
    local function FillTextureGet()
        local r = SelBar()
        local v = r and Store.Resolve(r, "fill", "texture")
        return (v == nil or v == "") and "Flat" or v
    end
    local function FillTextureSet(v)
        local r = SelBar()
        if r then Store.SetOverride(r, "fill", "texture", v == "Flat" and "" or v) end
    end
    -- Pips style: the row's direction (the fill's orientation fields; the Fill
    -- block hides in this style) and the pip texture. These rows must follow this
    -- block: after the Fill block they would land in its hidden section.
    local dirVis = BarBlock("Direction", "fill", "Appearance", {
        "orientation", "reverseFill",
    }, IsPips)
    AT.RowDropdown(pg, win, "Pip texture", FillTextureGet, FillTextureSet, BarTextureItems, dirVis)
    PushBar(pg, SelBar, "fill", dirVis, WithHidden(dirVis, "texture"))
    -- a health bar's "Color by" leads (its rows hide on every other kind)
    local fillVis = BarBlock("Fill", "fill", "Appearance", {
        "colorMode", "color", "gradLowColor", "gradMidColor", "gradHighColor",
        -- A castbar's channel and can't-be-interrupted colours.
        "castChannelOn", "castChannelColor", "castLockOn", "castLockColor",
        "rotateTexture", "fillMode", "idleEmpty",
        "smoothing", "fillInset",
    }, NotPips)
    AT.RowDropdown(pg, win, "Bar texture", FillTextureGet, FillTextureSet, BarTextureItems, fillVis)
    Options.LookBlock("bar", "Appearance", "Fill", "fill", { "texture" })
    -- Orientation, then, on a vertical bar only, the quarter turn that stands
    -- the bar up (Store.SetBarStanding). It has its own visibility: charge-slot
    -- bars have no orientation. The rows join the Fill block's push list.
    do
        local orientVis = function()
            if not fillVis() then return false end
            local r = SelBar()
            return r ~= nil and not (r.barKind == "cooldown" and r.barMode == "stack")
        end
        AT.Section(pg, "Orientation", { visibleFn = orientVis })
        SectionRows(pg, "bar", "fill", SelBar, orientVis, { "orientation", "reverseFill" })
        local list = Options.blockFields[fillVis]
        if list then
            list[#list + 1] = "orientation"
            list[#list + 1] = "reverseFill"
        end
        local stand = AT.RowToggle(pg, "Stand the bar up",
            function() local r = SelBar() return r ~= nil and Store.BarStanding(r) end,
            function(v) local r = SelBar() if r then Store.SetBarStanding(r, v) end end,
            function()
                local r = SelBar()
                return orientVis() and r ~= nil and Store.Resolve(r, "fill", "orientation") == "VERTICAL"
            end,
            "A quarter turn: width and height swap so the bar is tall and thin, a side icon moves to the bar's end, and the texture and gradient turn with it. Switching the orientation back to Horizontal lays the bar down again.")
        -- The search walks one sample bar per kind, mostly flat ones: hand it
        -- this gate without the Vertical check plus that switch, so "stand" is
        -- found on any bar and the jump flashes Orientation.
        stand._adMeta = { family = "bar", section = "fill", field = "standBar",
            def = { label = "Stand the bar up",
                dep = { field = "orientation", value = "VERTICAL" } },
            baseVis = orientVis }
    end
    BarSub(fillVis, "Gradient", "fill", { "useGradient", "gradientDir", "gradientColor" })
    AT.Section(pg, nil, { visibleFn = fillVis })   -- push bar below the subs (BarSub)
    PushBar(pg, SelBar, "fill", fillVis, WithHidden(fillVis, "texture"))
    -- Background and Border: two blocks over the one `look` section.
    local bgVis = BarBlock("Background", "look", "Appearance", {
        "bgShow", "bgColor", "bgAlpha",
    })
    -- the background texture dropdown (hidden schema field): the fill's own
    -- texture by default, else a built-in or any LibSharedMedia texture
    AT.RowDropdown(pg, win, "Background texture",
        function()
            local r = SelBar()
            local v = r and Store.Resolve(r, "look", "bgTexture")
            return (v == nil or v == "") and "Same as fill" or v
        end,
        function(v)
            local r = SelBar()
            if r then Store.SetOverride(r, "look", "bgTexture", v == "Same as fill" and "" or v) end
        end,
        function()
            local items = { { value = "Same as fill", text = "Same as fill" } }
            for _, it in ipairs(BarTextureItems()) do items[#items + 1] = it end
            return items
        end,
        bgVis)
    Options.LookBlock("bar", "Appearance", "Background", "look", { "bgTexture" })
    PushBar(pg, SelBar, "look", bgVis, WithHidden(bgVis, "bgTexture"))
    local borderVis = BarBlock("Border", "look", "Appearance", {
        "borderEnabled", "borderColor", "borderThickness", "useClassColorBorder",
    })
    -- the border style dropdown (hidden schema field): Flat strips, the
    -- Blizzard edges, and every LibSharedMedia border when one is present
    AT.RowDropdown(pg, win, "Border style",
        function()
            local r = SelBar()
            local v = r and Store.Resolve(r, "look", "borderStyle")
            return (v == nil or v == "") and "Flat" or v
        end,
        function(v)
            local r = SelBar()
            if r then Store.SetOverride(r, "look", "borderStyle", v == "Flat" and "" or v) end
        end,
        function()
            local items, seen = { { value = "Flat", text = "Flat" } }, { Flat = true }
            for _, k in ipairs((NS.Bars and NS.Bars.BUILTIN_BORDER_ORDER) or {}) do
                items[#items + 1] = { value = k, text = k }
                seen[k] = true
            end
            local lsm = NS.Bars and NS.Bars.GetLSM and NS.Bars.GetLSM()
            if lsm then
                local extra = {}
                for _, name in ipairs(lsm:List("border") or {}) do
                    if not seen[name] and name ~= "None" then extra[#extra + 1] = name end
                end
                table.sort(extra)
                for _, name in ipairs(extra) do
                    items[#items + 1] = { value = name, text = name }
                end
            end
            return items
        end,
        borderVis)
    Options.LookBlock("bar", "Appearance", "Border", "look", { "borderStyle" })
    PushBar(pg, SelBar, "look", borderVis, WithHidden(borderVis, "borderStyle"))
    local segsVis = BarBlock("Segments", "segments", "Appearance", {
        "segmentsShow", "segmentCount", "segmentSpacing", "dividerColor",
    })
    BarSub(segsVis, "Segment colors", "segments", {
        "fullColorEnabled", "fullColor", "rechargeColorEnabled", "rechargeColor",
    })
    AT.Section(pg, nil, { visibleFn = segsVis })   -- push bar below the subs (BarSub)
    PushBar(pg, SelBar, "segments", segsVis)
    -- Tick marks for every counted bar ("Every point" draws one per unit from
    -- the live maximum), laid out once per size or setting change.
    local tickVis = BarBlock("Ticks", "ticks", "Appearance", {
        "ticksShow", "tickMode", "tickPercent", "tickValues", "tickAsPercent",
        "tickScale",
    }, NotPips)
    BarSub(tickVis, "Spell costs", "ticks", {
        "tickSpells", "tickSpellIcons", "tickIconSize", "tickIconSide", "tickIconDim",
    })
    BarSub(tickVis, "Marks", "ticks", {
        "tickChannelOnly", "tickColor", "tickThickness", "tickHeight", "tickHeightAnchor",
    })
    AT.Section(pg, nil, { visibleFn = tickVis })   -- push bar below the subs (BarSub)
    PushBar(pg, SelBar, "ticks", tickVis)
    local icoVis = BarBlock("Icon", "icon", "Appearance", {
        "iconShow", "iconFollowBar", "iconSize", "iconSide", "iconSpacing",
        "iconOffsetX", "iconOffsetY", "iconOverride",
    })
    BarSub(icoVis, "Icon border", "icon", {
        "iconBorderEnabled", "iconBorderColor", "iconBorderThickness",
    })
    -- The can't-be-interrupted shield sits on the icon, so its rows live here;
    -- they are castbar-only, so the group hides on other bars.
    BarSub(icoVis, "Can't Be Interrupted", "icon", {
        "iconShield", "iconShieldSize",
    })
    AT.Section(pg, nil, { visibleFn = icoVis })   -- push bar below the subs (BarSub)
    PushBar(pg, SelBar, "icon", icoVis)
    -- Resource bars: the cost of the spell being cast, against the fill edge.
    local predVis = BarBlock("Cost Preview", "predict", "Appearance", {
        "predictEnabled", "predictColor", "predictAlpha",
    }, NotPips)
    PushBar(pg, SelBar, "predict", predVis)

    -- Text: the bar's one font first, then one chip per text run.
    local textTabVis = BarTabVisible("Text")
    AT.Section(pg, "Font", { visibleFn = textTabVis })
    AT.RowDropdown(pg, win, "Font",
        function()
            local r = SelBar()
            local v = r and Store.Resolve(r, "text", "font")
            return (v == nil or v == "") and "Default" or v
        end,
        function(v)
            local r = SelBar()
            if r then Store.SetOverride(r, "text", "font", v == "Default" and "" or v) end
        end,
        function()
            local items, seen = {}, {}
            local builtin = NS.Bars and NS.Bars.BUILTIN_FONT_ORDER or { "Default" }
            for _, k in ipairs(builtin) do
                items[#items + 1] = { value = k, text = k }
                seen[k] = true
            end
            local lsm = NS.Bars and NS.Bars.GetLSM and NS.Bars.GetLSM()
            if lsm then
                local extra = {}
                for _, name in ipairs(lsm:List("font") or {}) do
                    if not seen[name] then extra[#extra + 1] = name end
                end
                table.sort(extra)
                for _, name in ipairs(extra) do
                    items[#items + 1] = { value = name, text = name }
                end
            end
            return items
        end,
        textTabVis)
    Options.LookBlock("bar", "Text", "Font", "text", { "font" })
    -- the font is tab-wide (every run shares it): its own push bar
    PushBar(pg, SelBar, "text", textTabVis, { "font" })
    -- one push bar per text run (each scoped to its own rows through
    -- Options.blockFields - the runs share the one `text` section)
    local durVis = BarBlock("Duration", "text", "Text", {
        "durShow", "durRounding", "durSize", "durOutline", "durShadow", "durColor", "durAnchor",
        "durOffsetX", "durOffsetY",
    })
    BarSub(durVis, "Decimals", "text", { "durDecimalsEnabled", "durDecimalThreshold" })
    AT.Section(pg, nil, { visibleFn = durVis })   -- push bar below the subs (BarSub)
    PushBar(pg, SelBar, "text", durVis)
    -- A cooldown bar writes its stack text only for a charge spell
    -- (maxCharges > 1); every other kind always has one.
    local function StackTextExists(r)
        if r.barKind ~= "cooldown" then return true end
        local sid = r.driver and r.driver.spellID
        local info = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
        return ((info and info.maxCharges) or 0) > 1
    end
    PushBar(pg, SelBar, "text", BarBlock("Stack", "text", "Text", {
        "stkShow", "stkShowMax", "stkSize", "stkOutline", "stkShadow", "stkColor",
        "stkAnchor", "stkOffsetX", "stkOffsetY", "stkHideAtZero",
    }, StackTextExists))
    -- Resource and health texts: text 1 plus a count, texts 2 and 3 in their
    -- own boxes. Their rows gate on their schema deps (show and count) and the
    -- theme hides a box whose rows are all hidden. Keep the count out of a box
    -- visibleFn: the settings search skips hidden boxes.
    do
        local resTextVis = BarBlock("Resource", "text", "Text", {
            "resShow", "resFormat", "resCount", "resSize", "resOutline", "resShadow", "resColor",
            "resAnchor", "resOffsetX", "resOffsetY",
        })
        BarSub(resTextVis, "Resource text 2", "text",
            { "res2Format", "res2Size", "res2Color", "res2Anchor", "res2OffsetX", "res2OffsetY" })
        BarSub(resTextVis, "Resource text 3", "text",
            { "res3Format", "res3Size", "res3Color", "res3Anchor", "res3OffsetX", "res3OffsetY" })
        AT.Section(pg, nil, { visibleFn = resTextVis })   -- push bar below the subs (BarSub)
        PushBar(pg, SelBar, "text", resTextVis)
        local hpTextVis = BarBlock("Health", "text", "Text", {
            "hpShow", "hpFormat", "hpCount", "hpSize", "hpOutline", "hpShadow", "hpColor",
            "hpAnchor", "hpOffsetX", "hpOffsetY",
        })
        BarSub(hpTextVis, "Health text 2", "text",
            { "hp2Format", "hp2Size", "hp2Color", "hp2Anchor", "hp2OffsetX", "hp2OffsetY" })
        BarSub(hpTextVis, "Health text 3", "text",
            { "hp3Format", "hp3Size", "hp3Color", "hp3Anchor", "hp3OffsetX", "hp3OffsetY" })
        AT.Section(pg, nil, { visibleFn = hpTextVis })   -- push bar below the subs (BarSub)
        PushBar(pg, SelBar, "text", hpTextVis)
    end
    -- nameSource: a health bar's name text shows its unit's name or a custom
    -- name. nameText renders under the Name switch but stays out of the block's
    -- copy and save list, so one bar's name is never copied onto the others.
    do
        local nameVis = BarBlock("Name", "text", "Text", { "nameShow", "nameSource" })
        SectionRows(pg, "bar", "text", SelBar, nameVis, { "nameText" })
        local rest = { "nameSize", "nameOutline", "nameShadow", "nameColor", "nameAnchor",
            "nameOffsetX", "nameOffsetY" }
        SectionRows(pg, "bar", "text", SelBar, nameVis, rest)
        local list = Options.blockFields[nameVis]
        if list then
            for _, f in ipairs(rest) do list[#list + 1] = f end
        end
        PushBar(pg, SelBar, "text", nameVis)
    end
    PushBar(pg, SelBar, "text", BarBlock("Ready", "text", "Text", {
        "readyShow", "readyText", "readyColor",
    }))

    -- Thresholds: time bands, stack colors and power bands, each block gated on
    -- kind and mode by the schema.
    local thVis = BarBlock("Thresholds", "thresholds", "Thresholds", {
        "threshEnabled", "threshCount", "threshAsSeconds", "threshCdSeconds", "threshRef",
        "thresh2Value", "thresh2Color", "thresh3Value", "thresh3Color",
        "thresh4Value", "thresh4Color", "threshText",
    })
    PushBar(pg, SelBar, "thresholds", thVis)
    -- aura stack bars only here: a resource bar's banding is the Point
    -- Colors block on Appearance (pips style), and a continuous fill has no
    -- per-point cells to colour
    local scVis = BarBlock("Stack Colors", "stackcolors", "Thresholds", {
        "scEnabled", "scCount", "sc2Value", "sc2Color", "sc3Value", "sc3Color",
        "sc4Value", "sc4Color", "maxColorEnabled", "maxColor",
    }, function(r)
        return r.barKind ~= "resource"
    end)
    -- The bands in words, re-read on every sync.
    local scSum = AT.AddRow(pg, 22, scVis)
    local scFS = scSum:CreateFontString(nil, "OVERLAY")
    scFS:SetFont(STANDARD_TEXT_FONT, 10, "")
    scFS:SetPoint("LEFT", 10, 0)
    scFS:SetPoint("RIGHT", -10, 0)
    scFS:SetJustifyH("LEFT")
    scFS:SetWordWrap(false)
    scFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    scSum._sync = function()
        local r = SelBar()
        scFS:SetText(r and Options.StackColorSummary(r) or "")
    end
    PushBar(pg, SelBar, "stackcolors", scVis)
    local pthVis = BarBlock("Power Colors", "powerthresholds", "Thresholds", {
        "pthEnabled", "pthCount", "pthAbsolute", "pthDirection", "pth2Value", "pth2Color",
        "pth3Value", "pth3Color", "pth4Value", "pth4Color",
        "pthFullEnabled", "pthFullColor", "pthText",
    })
    PushBar(pg, SelBar, "powerthresholds", pthVis)
    -- health bars: colour by health percent (a low-health warning, the
    -- execute range); wins over the Bar color while a band applies
    local hpthVis = BarBlock("Health Colors", "healththresholds", "Thresholds", {
        "hpthEnabled", "hpthCount", "hpthDirection", "hpth2Value", "hpth2Color",
        "hpth3Value", "hpth3Color", "hpth4Value", "hpth4Color", "hpthText",
    })
    PushBar(pg, SelBar, "healththresholds", hpthVis)

    -- Behavior tab: the cooldown bar's state hides and their opacity (the combat
    -- hides are on Visibility).
    BarBlock("Behavior", "behavior", "Behavior", {
        "hideWhenReady", "hideWhenFullCharges", "hiddenAlpha", "gcdMode",
    }, function(r) return r.barKind == "cooldown" end)
    local barPosVis = BarTabVisible("Position")
    AT.Section(pg, "Position", { visibleFn = barPosVis })
    Options.PosRows(pg, SelBar, barPosVis, function(r)
        -- "anchored" = actually pinned right now: an anchor whose target
        -- is gone or hidden places free, so the sliders drive rec.pos there
        return NS.Anchor ~= nil and NS.Anchor.ResolveTarget(r) ~= nil
    end)
    BarBlock("Frame", "frame", "Position", {
        "strata", "level",
    })
    BarBlock("Hide when inactive", "behavior", "Tracking", {
        "hideWhenInactive", "hiddenAlpha",
    }, function(r) return r.barKind == "aura" or r.barKind == "timer" or r.barKind == "swing" end)

    -- Anchor: a group, another bar, a layout, a named frame, the cursor or the
    -- target's nameplate.
    local anchorTabVis = BarTabVisible("Anchor")
    Options.AnchorPickRows(pg, "bar", SelBar, anchorTabVis, {
        "anchorSrcPoint", "anchorDstPoint", "anchorOffsetX", "anchorOffsetY",
        "anchorMatchWidth", "anchorMatchWidthAdjust",
    }, "On a nameplate the bar hides while this window is open; the preview shows it.")
    -- What is pinned to this bar (a combo bar shows on its mana bar's tab).
    Options.AnchoredHereRows(pg, SelBar, anchorTabVis)
    -- No push bar: an anchor target is per record, like the driver.
end

-- Empty pane

local function BuildEmptyPane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.empty = pane
    local fs = pane:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 13, "")
    fs:SetPoint("CENTER", 0, 40)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    fs:SetText("Create a layout to begin - it is one movable block on your screen.")
    local b = AT.MakeSmallButton(pane, "+ New Layout", 110)
    b:SetPoint("CENTER", 0, 8)
    b.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    b:SetScript("OnClick", function()
        local rec = Store.NewLayout()
        ExpandedSet()[rec.id] = true
        Options.Select("layout", rec.id)
    end)
end

-- Aura name search for the Add window and the aura bar editor. A target's
-- debuffs are only seen in combat, where their IDs read secret, and the
-- spellbook holds castables, not aura IDs, so names come from the game's whole
-- spell list (NS.SpellNames, read once in budgeted steps). multi: a pick fills
-- every ID of the name (icons), else the one it carries (bars). The buttons are
-- plain frames, so the settings search skips them.
function Options.AuraSuggestPanel(pg, visibleFn, getText, setText, multi, onPicked)
    local row = AT.AddRow(pg, 134, visibleFn)
    local status = row:CreateFontString(nil, "OVERLAY")
    status:SetFont(STANDARD_TEXT_FONT, 9, "")
    status:SetPoint("TOPLEFT", 10, -2)
    status:SetPoint("TOPRIGHT", -12, -2)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    status:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    local btns, lastText = {}, nil
    local Refresh
    local function Btn(i)
        local b = btns[i]
        if b then return b end
        b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", 8, -14 - (i - 1) * 23)
        b:SetPoint("TOPRIGHT", -12, -14 - (i - 1) * 23)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetSize(18, 18)
        b.tex:SetPoint("LEFT", 3, 0)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.name = b:CreateFontString(nil, "OVERLAY")
        b.name:SetFont(STANDARD_TEXT_FONT, 11, "")
        b.name:SetPoint("LEFT", 27, 0)
        b.name:SetPoint("RIGHT", -110, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        b.id = b:CreateFontString(nil, "OVERLAY")
        b.id:SetFont(STANDARD_TEXT_FONT, 9, "")
        b.id:SetPoint("RIGHT", -6, 0)
        b.id:SetJustifyH("RIGHT")
        b.id:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        b:SetScript("OnEnter", function()
            b:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
            local g = b._g
            if not g then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(g.pick)
            local n = #g.ids
            GameTooltip:AddLine((n > 1 and "Spell IDs: " or "Spell ID: ")
                .. table.concat(g.ids, ", ", 1, math.min(n, 12)) .. ((n > 12) and ", ..." or ""),
                COL.arc[1], COL.arc[2], COL.arc[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            local g = b._g
            if not g then return end
            setText(multi and table.concat(g.ids, ", ") or tostring(g.pick))
            Refresh(true)
            if onPicked then onPicked() end
        end)
        btns[i] = b
        return b
    end
    local function Show(results, head)
        status:SetText(head)
        for i = 1, 5 do
            local b = Btn(i)
            local g = results and results[i]
            b._g = g
            if g then
                local n = #g.ids
                b.tex:SetTexture(g.icon or 134400)
                b.name:SetText(g.knownID and (g.name .. "  |cff3fc9f2(yours)|r") or g.name)
                if multi then
                    b.id:SetText((n > 1) and (n .. " IDs: " .. g.ids[1] .. " +" .. (n - 1)) or tostring(g.ids[1]))
                else
                    b.id:SetText(tostring(g.pick))
                end
                b:Show()
            else
                b:Hide()
            end
        end
    end
    Refresh = function(force)
        -- "reset" (the window closed): forget the text, so the next
        -- open searches again instead of showing a cancelled search
        if force == "reset" then lastText = nil return end
        if not row:IsShown() then return end
        local text = getText() or ""
        if text == lastText and not force then return end
        lastText = text
        if not text:find("%a") then
            NS.SpellNames.Cancel()
            local ids = Options.ParseSpellIDs(text)
            if ids[1] then
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])
                Show(nil, nm and (ids[1] .. " is " .. nm) or (ids[1] .. " is no spell this game knows"))
            else
                Show(nil, "TYPE THE AURA'S NAME to see its spell IDs, or type the IDs")
            end
            return
        end
        NS.SpellNames.Search(text, function(state, results, pct)
            if state == "short" then
                Show(nil, "Keep typing: at least 3 letters of the name")
            elseif state == "loading" then
                Show(nil, ("Reading the game's spell list (once): %d%%"):format(pct or 0))
            elseif #results == 0 then
                Show(nil, "No spell has that name")
            else
                Show(results, ("%d SPELL NAME%s MATCH - click one to fill the field"):format(
                    #results, (#results == 1) and "" or "S"))
            end
        end)
    end
    -- Every re-layout re-judges, but only a changed field searches again.
    row._sync = function() Refresh(false) end
    return Refresh
end

-- The Add window

-- Pick what first (Icon, Bar or Icon Group), then its options; the icon kinds
-- are a dropdown, not tabs.
local addState = { cat = "Icon", iconKind = "spell",
    layoutId = nil, destGroupId = nil, forceFree = false }

local function AddDestItems()
    local items = {}
    local layout = Store.Get(addState.layoutId)
    if not layout then return items end
    local groups = Store.ChildrenOf(layout)
    for _, g in ipairs(groups) do
        -- kind filter: aura groups only accept aura icons
        if addState.iconKind == "aura" or g.groupKind ~= "aura" then
            items[#items + 1] = { value = g.id, text = g.name }
        end
    end
    items[#items + 1] = { value = 0, text = "Free position" }
    return items
end

local function BuildAddWindow()
    addWin = AT.CreateWindow("ArcUIv2Add", {
        w = 500, h = 560, minW = 500, minH = 560, resizable = false,
        title = "|cff3fc9f2Add|r|cffd5e2f2 New|r",
    })
    addWin:SetFrameLevel(win:GetFrameLevel() + 40)
    -- Inset from the window: the page's panel body is a child frame, and child
    -- frames render above the parent's textures, so a flush page would paint over
    -- the window's 1px border.
    local pg = AT.NewPage(addWin)
    pg:SetPoint("TOPLEFT", 10, -40)
    pg:SetPoint("BOTTOMRIGHT", -10, 12)
    pg:Show()
    addWin._pg = pg

    local TABS = { "Icon", "Bar", "Icon Group" }
    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local h = tabRow._strip:Set(TABS, addState.cat, function(name)
            addState.cat = name
            AT.LayoutPage(pg)
        end)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    AT.Section(pg, nil)
    local isCat = function(c) return function() return addState.cat == c end end
    local isIcon = function(kind)
        return function()
            return addState.cat == "Icon" and (addState.iconKind or "spell") == kind
        end
    end

    local UpdateSuggestions   -- forward: the autocomplete panel below
    local UpdateCreate        -- forward: the Create button's enabled state (below)
    local rowBarMax           -- forward: the Max stacks field (its hint follows the ID)

    AT.RowDropdown(pg, addWin, "Icon kind",
        function() return addState.iconKind or "spell" end,
        function(v)
            addState.iconKind = v
            AT.LayoutPage(pg)
        end,
        function()
            return {
                { value = "spell", text = "Spell Cooldown" },
                { value = "aura", text = "Aura (buff / debuff)" },
                { value = "item", text = "Item" },
                { value = "trinket", text = "Trinket" },
                { value = "totem", text = "Totem" },
                { value = "ammo", text = "Ammo" },
            }
        end,
        isCat("Icon"))
    AT.RowDesc(pg, "Your equipped ammo and its count.", 20, isIcon("ammo"))
    AT.RowDesc(pg, "A spell's cooldown as an icon.", 20, isIcon("spell"))
    local rowSpell = AT.RowInput(pg, "Spell or name",
        function() return addState.spellID or "" end,
        function(v)
            addState.spellID = v
            if UpdateSuggestions then UpdateSuggestions() end
            if UpdateCreate then UpdateCreate() end
        end,
        isIcon("spell"), "Type a spell name or ID; click a suggestion to fill it.", "e.g. Stormstrike or 17364", true)
    -- the aura name search panel (Options.AuraSuggestPanel, above the Add
    -- window section); a pick re-judges Create
    local function AuraSuggest(visibleFn, getText, setText, multi)
        return Options.AuraSuggestPanel(pg, visibleFn, getText, setText, multi,
            function() if UpdateCreate then UpdateCreate() end end)
    end
    local RefreshIconAuraSug, RefreshBarAuraSug
    AT.RowDesc(pg, "A buff or debuff as an icon; several IDs can light one icon.", 20, isIcon("aura"))
    local rowAuraIDs = AT.RowInput(pg, "Aura name or spell IDs",
        function() return addState.auraID or "" end,
        function(v)
            addState.auraID = v
            if RefreshIconAuraSug then RefreshIconAuraSug(false) end
            if UpdateCreate then UpdateCreate() end
        end,
        isIcon("aura"), "Type the aura's NAME to see the spell IDs that carry it, then click one (every rank comes along). Or type one or more numeric IDs, separated by commas or spaces. The first gives the icon its art and name.", "e.g. Serpent Sting or 13549, 13550", true)
    RefreshIconAuraSug = AuraSuggest(isIcon("aura"),
        function() return addState.auraID end,
        function(v)
            addState.auraID = v
            if rowAuraIDs._colCtrl then rowAuraIDs._colCtrl:SetText(v) end
        end, true)
    -- the tracking shape the editor's Tracking tab offers (Options.Aura*):
    -- type first, then a unit that type can match on, then who cast it
    AT.RowDropdown(pg, addWin, "Aura type",
        function() return (addState.auraType == "debuff") and "debuff" or "buff" end,
        function(v)
            addState.auraType = v
            local ids = Options.ParseSpellIDs(addState.auraID)
            local probe = { spellID = ids[1], spellIDs = ids }
            local u = addState.auraUnit or ((v == "debuff") and "target" or "player")
            if not Options.AuraUnitAllowed(probe, u, v) then u = "target" end
            addState.auraUnit = u
            AT.LayoutPage(pg)
        end,
        function() return {
            { value = "buff", text = "Buff" },
            { value = "debuff", text = "Debuff" },
        } end,
        isIcon("aura"))
    AT.RowDropdown(pg, addWin, "On unit",
        function()
            return addState.auraUnit or ((addState.auraType == "debuff") and "target" or "player")
        end,
        function(v) addState.auraUnit = v AT.LayoutPage(pg) end,
        function()
            local ids = Options.ParseSpellIDs(addState.auraID)
            local t = (addState.auraType == "debuff") and "debuff" or "buff"
            return Options.AuraUnitItems({ spellID = ids[1], spellIDs = ids }, t,
                addState.auraUnit or ((t == "debuff") and "target" or "player"))
        end,
        isIcon("aura"))
    AT.RowDropdown(pg, addWin, "Cast by",
        function() return addState.auraCaster or "any" end,
        function(v) addState.auraCaster = v end,
        function() return Options.AURA_CASTER_ITEMS end,
        isIcon("aura"))
    AT.RowDesc(pg, "An item's cooldown and count, by item ID.", 20, isIcon("item"))
    AT.RowInput(pg, "Item ID",
        function() return addState.itemID or "" end,
        function(v) addState.itemID = v if UpdateCreate then UpdateCreate() end end,
        isIcon("item"), "The numeric item ID.", "e.g. 5512", true)

    -- Bar: category, then mode (Duration / Stack) for cooldown and aura bars.
    -- Timer and power-stack bars cannot be created here; existing ones still
    -- edit and render dormant.
    AT.RowDropdown(pg, addWin, "Bar category",
        function() return addState.barKind or "cooldown" end,
        function(v)
            addState.barKind = v
            AT.LayoutPage(pg)
        end,
        function()
            local items = {
                { value = "cooldown", text = "Cooldown Bar" },
                { value = "aura", text = "Aura Bar" },
            }
            -- capability probe, never a build gate: swing bars exist only
            -- where the client ships C_SwingTimer (WoW Forever)
            if C_SwingTimer then
                items[#items + 1] = { value = "swing", text = "Swing Bar" }
            end
            items[#items + 1] = { value = "resource", text = "Resource Bar" }
            items[#items + 1] = { value = "health", text = "Health Bar" }
            items[#items + 1] = { value = "cast", text = "Castbar" }
            return items
        end,
        isCat("Bar"))
    AT.RowDesc(pg, "Casts of you, your target or your focus; hidden between casts.", 20,
        function()
            return addState.cat == "Bar" and addState.barKind == "cast"
        end)
    AT.RowDropdown(pg, addWin, "Whose casts",
        function() return addState.castUnit or "player" end,
        function(v) addState.castUnit = v end,
        Options.CastUnitItems,
        function()
            return addState.cat == "Bar" and addState.barKind == "cast"
        end)
    AT.RowDesc(pg, "A unit's health, with incoming heals and shields.", 20,
        function()
            return addState.cat == "Bar" and addState.barKind == "health"
        end)
    AT.RowDropdown(pg, addWin, "Unit",
        function() return addState.barUnit or "player" end,
        function(v) addState.barUnit = v end,
        Options.HealthUnitItems,
        function()
            return addState.cat == "Bar" and addState.barKind == "health"
        end)
    AT.RowDesc(pg, "A power bar; Automatic follows the power you are using.", 20,
        function()
            return addState.cat == "Bar" and addState.barKind == "resource"
        end)
    AT.RowDropdown(pg, addWin, "Power",
        function() return addState.barPower or POWER_AUTO end,
        function(v) addState.barPower = v end,
        PowerItems,
        function()
            return addState.cat == "Bar" and addState.barKind == "resource"
        end)
    -- onSelect re-lays the form: a dropdown pick does not by itself, and the Max
    -- stacks row must appear on the Stack pick.
    AT.RowDropdown(pg, addWin, "Bar mode",
        function() return addState.barMode or "duration" end,
        function(v) addState.barMode = v end,
        function()
            return {
                { value = "duration", text = "Duration Bar" },
                { value = "stack", text = "Stack Bar" },
            }
        end,
        function()
            local bk = addState.barKind or "cooldown"
            return addState.cat == "Bar" and (bk == "cooldown" or bk == "aura")
        end,
        function() AT.LayoutPage(pg) end)
    -- The spellbook autocomplete is for cooldowns only: the catalog holds
    -- castables, so aura fields use the name search instead.
    local barUsesSpell = function()
        return addState.cat == "Bar" and (addState.barKind or "cooldown") == "cooldown"
    end
    local rowBarSpell = AT.RowInput(pg, "Spell or name",
        function() return addState.barSpell or "" end,
        function(v)
            addState.barSpell = v
            if UpdateSuggestions then UpdateSuggestions() end
            if UpdateCreate then UpdateCreate() end
        end,
        barUsesSpell, "The tracked cooldown spell.", "e.g. Stormstrike or 17364", true)
    local barIsAura = function() return addState.cat == "Bar" and addState.barKind == "aura" end
    local rowBarAura = AT.RowInput(pg, "Aura name or spell ID",
        function() return addState.barAuraID or "" end,
        function(v)
            addState.barAuraID = v
            if RefreshBarAuraSug then RefreshBarAuraSug(false) end
            if rowBarMax and rowBarMax._sync then rowBarMax._sync() end
            if UpdateCreate then UpdateCreate() end
        end,
        barIsAura,
        "Type the aura's NAME to see its spell IDs, then click one (a bar takes one ID: the rank you cast when you know the spell). Or type the numeric ID.", "e.g. Serpent Sting or 13549", true)
    RefreshBarAuraSug = AuraSuggest(barIsAura,
        function() return addState.barAuraID end,
        function(v)
            addState.barAuraID = v
            if rowBarAura._colCtrl then rowBarAura._colCtrl:SetText(v) end
            if rowBarMax and rowBarMax._sync then rowBarMax._sync() end
        end, false)
    -- a closed window stops the scan (nothing runs unless someone types)
    addWin:HookScript("OnHide", function()
        NS.SpellNames.Cancel()
        RefreshIconAuraSug("reset")
        RefreshBarAuraSug("reset")
    end)
    -- The aura icons' tracking shape: type, then a unit that type can match on,
    -- then who cast it. A debuff bar starts on "Me", so another Warrior's Sunder
    -- never lights it.
    local function BarAuraT() return ((addState.barAuraType or "buff") == "debuff") and "debuff" or "buff" end
    local function BarAuraUnit()
        return addState.barAuraUnit or ((BarAuraT() == "debuff") and "target" or "player")
    end
    AT.RowDropdown(pg, addWin, "Aura type",
        function() return addState.barAuraType or "buff" end,
        function(v)
            addState.barAuraType = v
            local u = BarAuraUnit()
            if not Options.AuraUnitAllowed({ spellID = tonumber(addState.barAuraID) }, u, BarAuraT()) then
                u = "target"
            end
            addState.barAuraUnit = u
            AT.LayoutPage(pg)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        barIsAura)
    AT.RowDropdown(pg, addWin, "On unit",
        BarAuraUnit,
        function(v) addState.barAuraUnit = v end,
        function()
            return Options.AuraUnitItems({ spellID = tonumber(addState.barAuraID) }, BarAuraT(), BarAuraUnit())
        end,
        barIsAura)
    AT.RowDropdown(pg, addWin, "Cast by",
        function()
            return addState.barAuraCaster or ((BarAuraT() == "debuff") and "mine" or "any")
        end,
        function(v) addState.barAuraCaster = v end,
        function() return Options.AURA_CASTER_ITEMS end,
        barIsAura)
    -- The maximum is the game's by default (Options.DetectMaxStacks): the field
    -- shows it as the hint and stays empty so the record follows the game; a
    -- typed number overrides it. Create waits only while neither is known.
    rowBarMax = AT.RowInput(pg, "Max stacks",
        function() return addState.barMaxStacks or "" end,
        function(v)
            addState.barMaxStacks = v
            if UpdateCreate then UpdateCreate() end
        end,
        function()
            return addState.cat == "Bar" and addState.barKind == "aura"
                and addState.barMode == "stack"
        end,
        "The bar is full at this many stacks. Empty = the maximum the game itself reports for this aura (shown in the field); type a number only when that is wrong.",
        function()
            local n = Options.DetectMaxStacks(addState.barAuraID)
            return n and ("game says " .. n) or "unknown - type the maximum"
        end, true)
    AT.RowDropdown(pg, addWin, "Swing type",
        function() return addState.swingType or 0 end,
        function(v) addState.swingType = v end,
        function() return SWING_TYPES end,
        function() return addState.cat == "Bar" and addState.barKind == "swing" end)

    -- Spellbook autocomplete: cooldown spells only (spell icons, cooldown bars)
    local sugRow = AT.AddRow(pg, 158, function()
        if addState.cat == "Icon" then
            return (addState.iconKind or "spell") == "spell"
        end
        return barUsesSpell()
    end)
    local sugLabel = sugRow:CreateFontString(nil, "OVERLAY")
    sugLabel:SetFont(STANDARD_TEXT_FONT, 9, "")
    sugLabel:SetPoint("TOPLEFT", 10, -2)
    sugLabel:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    sugLabel:SetText("FROM YOUR SPELLBOOK - click to fill")
    local sugBtns = {}
    local function SugBtn(i)
        local b = sugBtns[i]
        if b then return b end
        b = CreateFrame("Button", nil, sugRow, "BackdropTemplate")
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", 8, -14 - (i - 1) * 23)
        b:SetPoint("TOPRIGHT", -12, -14 - (i - 1) * 23)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetSize(18, 18)
        b.tex:SetPoint("LEFT", 3, 0)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.name = b:CreateFontString(nil, "OVERLAY")
        b.name:SetFont(STANDARD_TEXT_FONT, 11, "")
        b.name:SetPoint("LEFT", 27, 0)
        b.name:SetPoint("RIGHT", -70, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        b.id = b:CreateFontString(nil, "OVERLAY")
        b.id:SetFont(STANDARD_TEXT_FONT, 9, "")
        b.id:SetPoint("RIGHT", -6, 0)
        b.id:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        b:SetScript("OnEnter", function()
            b:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
        end)
        b:SetScript("OnLeave", function()
            b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        end)
        sugBtns[i] = b
        return b
    end
    UpdateSuggestions = function()
        if not sugRow:IsShown() then return end
        local query, targetRow
        if addState.cat == "Icon" and (addState.iconKind or "spell") == "spell" then
            query, targetRow = addState.spellID, rowSpell
        elseif barUsesSpell() then
            query, targetRow = addState.barSpell, rowBarSpell
        else
            return
        end
        local results = NS.SpellCatalog.Search(query, 6)
        for i = 1, 6 do
            local b = SugBtn(i)
            local e = results[i]
            if e then
                b.tex:SetTexture(e.texture)
                b.name:SetText(e.name)
                b.id:SetText(e.spellID)
                b:SetScript("OnClick", function()
                    local v = tostring(e.spellID)
                    if addState.cat == "Bar" then addState.barSpell = v
                    else addState.spellID = v end
                    if targetRow and targetRow._colCtrl then
                        targetRow._colCtrl:SetText(v)
                    end
                    UpdateSuggestions()
                    -- The pick is the commit: Create comes on at once.
                    if UpdateCreate then UpdateCreate() end
                end)
                b:Show()
            else
                b:Hide()
            end
        end
    end
    sugRow._sync = UpdateSuggestions
    AT.RowDropdown(pg, addWin, "Trinket slot",
        function() return addState.slotID or 13 end,
        function(v) addState.slotID = v end,
        function() return { { value = 13, text = "Trinket 1 (top)" }, { value = 14, text = "Trinket 2 (bottom)" } } end,
        isIcon("trinket"))
    AT.RowDesc(pg, "A totem slot, lit while its totem is down.", 20, isIcon("totem"))
    AT.RowDropdown(pg, addWin, "Totem slot",
        function() return addState.totemSlot or 1 end,
        function(v) addState.totemSlot = v end,
        function()
            return {
                { value = 1, text = "Slot 1" }, { value = 2, text = "Slot 2" },
                { value = 3, text = "Slot 3" }, { value = 4, text = "Slot 4" },
            }
        end,
        isIcon("totem"))
    AT.RowInput(pg, "Group name",
        function() return addState.groupName or "" end,
        function(v) addState.groupName = v end,
        isCat("Icon Group"), nil, "e.g. Core Rotation", true)
    AT.RowDropdown(pg, addWin, "Group kind",
        function() return addState.groupKind or "cooldown" end,
        function(v) addState.groupKind = v end,
        function() return { { value = "cooldown", text = "CD Group" }, { value = "aura", text = "Aura Group" } } end,
        isCat("Icon Group"))

    -- only icons pick a destination: bars are always free, groups have none
    AT.RowDropdown(pg, addWin, "Add to",
        function() return addState.destGroupId or 0 end,
        function(v) addState.destGroupId = v ~= 0 and v or nil AT.LayoutPage(pg) end,
        AddDestItems,
        isCat("Icon"))
    -- The Dynamic aura-group play-mode limit, said before the icon is made.
    AT.RowDesc(pg, "A Dynamic aura group only tracks you, your pet and your target.", 20,
        function()
            if not (addState.cat == "Icon" and addState.iconKind == "aura") then return false end
            local g = (not addState.forceFree) and addState.destGroupId and Store.Get(addState.destGroupId)
            if not (g and g.groupKind == "aura") then return false end
            if Store.Resolve(g, "arrangement", "dynamicLayout") ~= true then return false end
            local t = (addState.auraType == "debuff") and "debuff" or "buff"
            return not Options.AuraLaneInGroupRows({ auraType = t,
                unit = addState.auraUnit or ((t == "debuff") and "target" or "player") })
        end)

    local btnRow = AT.AddRow(pg, 30)
    local create = AT.MakeSmallButton(btnRow, "Create", 84)
    create:SetPoint("LEFT", 10, 0)
    create.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    local cancel = AT.MakeSmallButton(btnRow, "Cancel", 64)
    cancel:SetPoint("LEFT", create, "RIGHT", 6, 0)
    cancel:SetScript("OnClick", function() addWin:Hide() end)

    -- What the click needs, mirrored so Create only lights when it will work: an
    -- aura stack bar needs the game's maximum or a typed one. A disabled Button
    -- takes no click or hover, so the dim look holds.
    local function CanCreate()
        if not Store.Get(addState.layoutId) then return false end
        if addState.cat == "Icon" then
            local ik = addState.iconKind or "spell"
            if ik == "spell" then return (addState.spellID or "") ~= "" end
            if ik == "aura" then return #Options.ParseSpellIDs(addState.auraID) > 0 end
            if ik == "item" then return tonumber(addState.itemID) ~= nil end
            return true
        elseif addState.cat == "Bar" then
            local bk = addState.barKind or "cooldown"
            if bk == "aura" then
                if not tonumber(addState.barAuraID) then return false end
                if addState.barMode == "stack" then
                    local typed = addState.barMaxStacks or ""
                    if typed ~= "" then
                        local ms = tonumber(typed)
                        return ms ~= nil and ms >= 1
                    end
                    return Options.DetectMaxStacks(addState.barAuraID) ~= nil
                end
                return true
            elseif bk == "cooldown" then
                return (addState.barSpell or "") ~= ""
            end
            return true
        end
        return true
    end
    UpdateCreate = function()
        local on = CanCreate()
        create:SetEnabled(on)
        create:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        if on then
            create.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
            create:SetBackdropBorderColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
        else
            create.fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            create:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        end
    end
    btnRow._sync = UpdateCreate   -- every re-layout (kind / mode picks) re-judges
    create:SetScript("OnClick", function()
        AT.CloseDropdown()
        if not CanCreate() then return end
        local layoutId = addState.layoutId
        if not Store.Get(layoutId) then return end
        local dest = (not addState.forceFree) and addState.destGroupId or nil
        local iconKind = (addState.cat == "Icon") and (addState.iconKind or "spell") or nil
        -- stale destination guard: a dest picked for another kind can point
        -- at an aura group while creating a non-aura icon - fall back to free
        if dest and iconKind ~= "aura" then
            local g = Store.Get(dest)
            if g and g.groupKind == "aura" then dest = nil end
        end
        -- Accept an ID or a typed name (the first autocomplete match wins).
        local function ResolveSpellInput(text)
            local sid = tonumber(text)
            if sid then return sid end
            if not text or text == "" then return nil end
            local results = NS.SpellCatalog.Search(text, 1)
            return results[1] and results[1].spellID or nil
        end
        if iconKind == "spell" then
            local sid = ResolveSpellInput(addState.spellID)
            if not sid then return end
            local name = (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Spell " .. sid)
            local rec = Store.NewIcon("spell", { spellID = sid }, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "aura" then
            -- the field holds IDs by now (a picked name fills them in); a
            -- typed name alone never resolves here. Every listed id rides
            -- the icon's one button
            local ids = Options.ParseSpellIDs(addState.auraID)
            if #ids == 0 then return end
            local t = (addState.auraType == "debuff") and "debuff" or "buff"
            local caster = addState.auraCaster
            local driver = {
                auraType = t,
                unit = addState.auraUnit or ((t == "debuff") and "target" or "player"),
                caster = (caster == "mine" or caster == "others") and caster or nil,
            }
            Options.SetAuraSpellIDs(driver, ids)
            local name = (C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])) or ("Aura " .. ids[1])
            local rec = Store.NewIcon("aura", driver, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "item" then
            local iid = tonumber(addState.itemID)
            if not iid then return end
            local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(iid))
                or ("Item " .. iid)
            local rec = Store.NewIcon("item", { itemID = iid }, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "trinket" then
            local slot = addState.slotID or 13
            local rec = Store.NewIcon("trinket", { slotID = slot }, dest, layoutId,
                slot == 13 and "Trinket 1" or "Trinket 2")
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "totem" then
            local slot = addState.totemSlot or 1
            local rec = Store.NewIcon("totem", { slot = slot }, dest, layoutId,
                "Totem " .. slot)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "ammo" then
            -- Nothing to configure: the icon is the ammo slot.
            local rec = Store.NewIcon("ammo", {}, dest, layoutId, "Ammo")
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif addState.cat == "Bar" then
            -- Creatable: cooldown and aura (duration or stack), swing where
            -- probed, resource, health and cast. Not timer or power-stack bars.
            local bk = addState.barKind or "cooldown"
            local mode = addState.barMode == "stack" and "stack" or "duration"
            local driver, name
            if bk == "swing" then
                local st = addState.swingType or 0
                driver = { swingType = st }
                name = SwingLabel(st) .. " Swing"
            elseif bk == "resource" then
                -- nil powerType = follow the live display power
                local pt = PowerValue(addState.barPower)
                driver = { powerType = pt }
                local info = pt and NS.Bars and NS.Bars.POWER_INFO
                    and NS.Bars.POWER_INFO[pt]
                name = (info and info.name) or "Resource"
                mode = nil   -- a resource bar is neither a duration nor a stack
            elseif bk == "health" then
                local u = addState.barUnit or "player"
                driver = { unit = u }
                name = (u == "player" and "Health") or (Options.HealthUnitLabel(u) .. " Health")
                mode = nil   -- neither a duration nor a stack
            elseif bk == "cast" then
                local u = addState.castUnit or "player"
                driver = { unit = u }
                name = (u == "player" and "Castbar") or (Options.HealthUnitLabel(u) .. " Castbar")
                mode = nil
            elseif bk == "aura" then
                -- the field holds the ID by now (a picked name fills it in)
                local sid = tonumber(addState.barAuraID)
                if not sid then return end
                local t = (addState.barAuraType == "debuff") and "debuff" or "buff"
                -- A debuff bar starts as "cast by me", so another Warrior's
                -- Sunder never lights it; a buff bar counts any caster.
                local caster = addState.barAuraCaster or ((t == "debuff") and "mine" or "any")
                driver = { spellID = sid, auraType = t,
                    unit = addState.barAuraUnit or ((t == "debuff") and "target" or "player"),
                    caster = (caster == "mine" or caster == "others") and caster or nil }
                if mode == "stack" then
                    -- the typed maximum; an empty or bad entry gets the
                    -- runtime's fallback (5) and the Tracking tab to fix it
                    local ms = tonumber(addState.barMaxStacks)
                    if ms and ms >= 1 then driver.maxStacks = math.floor(ms) end
                end
                name = (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Aura " .. sid)
            else
                bk = "cooldown"
                local sid = ResolveSpellInput(addState.barSpell)
                if not sid then return end
                driver = { spellID = sid }
                name = (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Spell " .. sid)
            end
            local rec = Store.NewBar(layoutId, bk, driver, name, mode)
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("bar", rec.id)
            end
        elseif addState.cat == "Icon Group" then
            local rec = Store.NewGroup(layoutId, addState.groupName ~= "" and addState.groupName or nil,
                addState.groupKind or "cooldown")
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("group", rec.id)
            end
        end
    end)
end

function Options.OpenAdd(layoutId, destGroupId, forceFree)
    if not addWin then BuildAddWindow() end
    addState.layoutId = layoutId
    addState.destGroupId = destGroupId
    addState.forceFree = forceFree and true or false
    if destGroupId then
        -- adding into a group = adding an icon; aura groups preselect aura
        addState.cat = "Icon"
        local g = Store.Get(destGroupId)
        if g and g.groupKind == "aura" then addState.iconKind = "aura" end
    end
    addWin:ClearAllPoints()
    addWin:SetPoint("CENTER", win, "CENTER", 0, 20)
    addWin:Show()
    AT.LayoutPage(addWin._pg)
end

-- after creating an icon, land where it lives
function Options.SelectIconHome(rec)
    ui.selIconId = rec.id
    if rec.groupId then
        ui.grpMode = "ico"
        Options.Select("group", rec.groupId)
    else
        Options.Select("free", rec.layoutId)
    end
end

-- Addon panes: Settings, QOL and Import / Export

local settingsPane, settingsPage
local iePane, ieBox, ieScroll, ieStatus, ieListHost
-- The Import / Export page's helpers and widgets share one table because of
-- the 200-local limit.
local IE = {
    rowPool = {},   -- picker rows
    PICK_H = 176,   -- the export picker's window; a longer tree scrolls
    ROW_H = 22,
}
local railAddonRows = {}

local function PaintAddonRows()
    for pane, r in pairs(railAddonRows) do
        PaintRailRow(r, ui.selType == pane, "child")
    end
end

local function BuildSettingsPane()
    settingsPane = CreateFrame("Frame", nil, content)
    settingsPane:SetAllPoints()
    panes.settings = settingsPane
    local h = MakeHeader(settingsPane)
    h.name:SetText("Settings")
    settingsPage = AT.NewPage(settingsPane)
    AT.MakeScrollable(settingsPage)
    settingsPage:SetPoint("TOPLEFT", 0, -36)
    settingsPage:SetPoint("BOTTOMRIGHT", 0, 0)
    settingsPage:Show()   -- NewPage creates pages hidden; each pane shows its own
    local pg = settingsPage
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.settings = { page = pg }
    AT.Section(pg, "Panel")
    -- Scale applies on release, not mid-drag: the slider lives inside the window
    -- it resizes, so rescaling on every OnValueChanged moves it under a held
    -- cursor and the value oscillates. The value is stored live; steppers and
    -- typed values apply at once.
    local scaleDragging, scalePending = false, nil
    local function ApplyScale()
        if scalePending then
            AT.SetUIScale(scalePending)
            scalePending = nil
        end
    end
    local scaleRow = AT.RowSlider(pg, "Panel scale",
        function() return Store.GetSetting("uiScale") or 1 end,
        function(v)
            Store.SetSetting("uiScale", v)
            scalePending = v
            -- IsMouseButtonDown covers a mouse-down the hooks
            -- never saw, so a missed hook cannot strand the apply mid-drag.
            if not scaleDragging and not IsMouseButtonDown() then ApplyScale() end
        end,
        0.8, 1.6, 0.05, true, nil)
    local scaleSlider = scaleRow and scaleRow._colCtrl
    if scaleSlider then
        scaleSlider:HookScript("OnMouseDown", function() scaleDragging = true end)
        scaleSlider:HookScript("OnMouseUp", function()
            scaleDragging = false
            ApplyScale()
        end)
    end
    AT.RowDesc(pg, "The resize lands when you let go of the slider.", 20)
    -- Editing preview: the minimum alpha Factory's state writer uses while this
    -- window is open (default 0.35).
    AT.RowSlider(pg, "Editing preview opacity",
        function()
            local v = Store.GetSetting("previewAlpha")
            if v == nil then v = 0.35 end
            return v
        end,
        function(v) Store.SetSetting("previewAlpha", v) end,
        0, 1, 0.05, true, nil)
    AT.RowDesc(pg, "Hidden or dimmed icons show at least this much while this window is open.", 20)
    AT.RowToggle(pg, "Show unloaded items while editing",
        function() return Store.GetSetting("showUnloaded") == true end,
        function(v)
            Store.SetSetting("showUnloaded", v and true or false)
            -- Every element's own eye goes back to following this switch.
            Store.ResetUnloadedShown()
            RefreshAll()
        end,
        nil, "While this window is open, every layout, group, icon and bar whose load conditions fail on this character is drawn anyway, each with a small \"unloaded\" tag, so you can place and style it. Each one's eye, in the sidebar and on the layout tiles, shows or hides it on its own, and flipping this switch sets them all again. Load conditions stay exactly as they are, and closing the window hides everything unloaded.")
    AT.Section(pg, "Group Editing")
    AT.RowToggle(pg, "Show layout arrows",
        function() return Store.GetSetting("showLayoutArrows") ~= false end,   -- on by default
        function(v)
            Store.SetSetting("showLayoutArrows", v and true or false)
            if Engine and Engine.RefreshArrows then Engine.RefreshArrows() end
        end,
        nil, "While this window is open, the group you are editing shows arrows on its bottom, left and right edges: green adds a row or a column on that side, red removes one. The icons stay where they are.")
    AT.Section(pg, "Icon Mouse")
    AT.RowToggle(pg, "Show tooltips",
        function() return Store.GetSetting("showTooltips") ~= false end,
        function(v)
            Store.SetSetting("showTooltips", v and true or false)
            -- the row below follows this switch
            RefreshAll()
        end,
        nil, "Hovering an icon shows its spell, item or totem tooltip.")
    -- Tooltips while editing only. Off: tooltips while you play, none while this
    -- window is open.
    AT.RowToggle(pg, "Only while this window is open",
        function() return Store.GetSetting("tooltipsEditOnly") == true end,
        function(v) Store.SetSetting("tooltipsEditOnly", v and true or nil) end,
        function() return Store.GetSetting("showTooltips") ~= false end,
        "Icon tooltips show only while this options window is open, so you can tell your icons apart while you edit, and never while you play. Normally it is the other way round: tooltips while you play, none while this window is open.")
    AT.RowToggle(pg, "Click-through icons",
        function() return Store.GetSetting("clickThrough") ~= false end,
        function(v) Store.SetSetting("clickThrough", v and true or false) end,
        nil, "Clicks pass through icons to the game world underneath. Tooltips still show while the toggle above is on. While this options window is open every icon takes the mouse regardless, for dragging.")
    -- Button Press Highlight (Core\AD_PressHighlight.lua reads these at every
    -- press). Off by default.
    AT.Section(pg, "Button Press Highlight")
    local PH = NS.PressHighlight
    local phOn = function() return Store.GetSetting("pressHighlight") == true end
    AT.RowToggle(pg, "Highlight icons when you press their button",
        function() return Store.GetSetting("pressHighlight") == true end,
        function(v)
            Store.SetSetting("pressHighlight", v and true or nil)
            if not v and PH then PH.ReleaseAll() end
            RefreshAll()
        end,
        nil, "When you press an action button, cast a spell through a macro or use a trinket, every icon of that ability on screen lights up for a moment: feedback on the icon you are watching, not the bar. Spells, items and trinkets; every rank of a spell counts as the same ability.")
    AT.RowDropdown(pg, win, "Highlight lasts",
        function() return Store.GetSetting("pressMode") or "flash" end,
        function(v) Store.SetSetting("pressMode", (v == "hold") and "hold" or nil) end,
        function()
            return {
                { value = "flash", text = "A short flash" },
                { value = "hold", text = "While the button is held" },
            }
        end,
        phOn)
    local lenRow = AT.RowSlider(pg, "Flash length (s)",
        function() return Store.GetSetting("pressDuration") or (PH and PH.DEFAULT_DURATION) or 0.1 end,
        function(v) Store.SetSetting("pressDuration", v) end,
        0.05, 0.5, 0.05, "%g", phOn)
    AT.Tooltip(lenRow, "Flash length (s)",
        "How long a flash shows. While the button is held, the highlight also stays at least this long, so a click (which casts when you let go) still shows.")
    AT.RowDropdown(pg, win, "Look",
        function() return Store.GetSetting("pressLook") or "fill" end,
        function(v)
            Store.SetSetting("pressLook", (v ~= "fill") and v or nil)
            RefreshAll()
        end,
        function() return PH and PH.LOOKS or {} end,
        phOn)
    AT.RowColor(pg, "Highlight color",
        function()
            local c = Store.GetSetting("pressColor") or (PH and PH.DEFAULT_COLOR) or { 1, 1, 0 }
            return { c[1], c[2], c[3] }
        end,
        function(c) Store.SetSetting("pressColor", { c[1], c[2], c[3] }) end,
        phOn)
    AT.RowSlider(pg, "Highlight opacity",
        function() return Store.GetSetting("pressAlpha") or (PH and PH.DEFAULT_ALPHA) or 0.45 end,
        function(v) Store.SetSetting("pressAlpha", v) end,
        0.05, 1, 0.05, true, phOn)
    AT.RowToggle(pg, "Tint the look with the color",
        function() return Store.GetSetting("pressTint") == true end,
        function(v) Store.SetSetting("pressTint", v and true or nil) end,
        function() return phOn() and (Store.GetSetting("pressLook") or "fill") ~= "fill" end,
        "Colors the button-frame looks with the highlight color instead of their own gold and white.")
    -- Timer rounding: one choice for every countdown, read through
    -- Factory.TimerRounding (nil = up).
    AT.Section(pg, "Timers")
    local roundRow = AT.RowDropdown(pg, win, "Round timer numbers",
        function() return NS.Factory and NS.Factory.TimerRounding() or "up" end,
        function(v) Store.SetSetting("timerRounding", (v == "down") and "down" or nil) end,
        function()
            return {
                { value = "up", text = "Up, like action bar cooldowns" },
                { value = "down", text = "Down, like buff timers" },
            }
        end)
    AT.Tooltip(roundRow, "Round timer numbers",
        "How every Arc UI Forever countdown shows part of a second: icons, aura bars, timer bars and swing bars. Up: 13.2 seconds reads 14, the way action bar cooldowns count, so a running timer never reads 0. Down: 13.2 seconds reads 13, the way buff timers and most nameplates count. Decimals, where you turned them on, show the tenths either way.")
    AT.Section(pg, "Tooltips")
    AT.RowToggle(pg, "IDs in tooltips",
        function() return Store.GetSetting("tooltipIDs") ~= false end,   -- on by default
        function(v)
            Store.SetSetting("tooltipIDs", v and true or false)
            if v and NS.TooltipIDs then NS.TooltipIDs.Install() end
        end,
        nil, "Appends an Arc ID block to game tooltips everywhere - spell, aura, item, toy, mount, currency, achievement and quest IDs, each with its icon ID (and the icon the button actually shows when that differs), the Cooldown Manager's cooldown ID for spells, auras and equipped trinkets, plus talent node / entry IDs on the talent tree. Works on action bars, buffs, bags and the spellbook, not just Arc UI Forever icons.")
    AT.Section(pg, "Minimap")
    AT.RowToggle(pg, "Hide minimap button",
        function() return Store.GetSetting("minimapHide") == true end,
        function(v)
            Store.SetSetting("minimapHide", v and true or false)
            if NS.MinimapButtonRefresh then NS.MinimapButtonRefresh() end
        end,
        nil, "Hides the Arc UI Forever minimap button. "
            .. (NS.IsForever and "/arcui" or "/arcui2")
            .. " always opens this window. Drag the button around the minimap rim to move it; right-click it to toggle move mode.")
    -- What's New (UI\AD_Changelog.lua): the auto-open switch writes the same UI
    -- flag as the window's own checkbox.
    AT.Section(pg, "What's New")
    AT.RowToggle(pg, "Show What's New after an update",
        function()
            local u = Store.UI()
            return not (u and u.changelogOff)
        end,
        function(v)
            local u = Store.UI()
            if u then u.changelogOff = (not v) or nil end
        end,
        nil, "The first time you log in after Arc UI Forever updates, a window opens once with what changed in the new version.")
    AT.RowButton(pg, "Open", function()
        if NS.Changelog then NS.Changelog.Show() end
    end, nil, 110, "What changed in each version")
    pg:Refresh()
end

-- QOL: game-side conveniences that are not displays. Lives in the rail's
-- ADDON block above Settings; each feature is its own module under QOL\.
local qolPage
local function BuildQOLPane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.qol = pane
    local h = MakeHeader(pane)
    h.name:SetText("Quality of Life")
    qolPage = AT.NewPage(pane)
    AT.MakeScrollable(qolPage)
    qolPage:SetPoint("TOPLEFT", 0, -36)
    qolPage:SetPoint("BOTTOMRIGHT", 0, 0)
    qolPage:Show()
    local pg = qolPage
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.qol = { page = pg }
    local AR = NS.AutoRank
    local ranked = function() return AR ~= nil and AR.Supported() end
    AT.Section(pg, "Action Bars")
    AT.RowToggle(pg, "Auto-rank action bar spells",
        function() return Store.GetSetting("autoRankBars") == true end,   -- off by default
        function(v) Store.SetSetting("autoRankBars", v and true or false) end,
        ranked, "When you learn a new rank, every action bar button that held the previous top rank moves up to the new one. Lower ranks you placed on purpose are left alone. Macros are never touched. Bars only change out of combat.")
    local upRow = AT.RowButton(pg, "Upgrade all bars now", function()
        if not AR then return end
        local n, why = AR.UpgradeAll()
        local b = pg._upBtn
        if not b then return end
        if n then b.fs:SetText(n == 1 and "Upgraded 1 button" or ("Upgraded " .. n .. " buttons"))
        elseif why == "combat" then b.fs:SetText("Not in combat")
        elseif why == "cursor" then b.fs:SetText("Empty your cursor first")
        else return end
        C_Timer.After(1.6, function() b.fs:SetText("Upgrade all bars now") end)
    end, ranked, 170)
    pg._upBtn = upRow.button
    if pg._upBtn then
        AT.Tooltip(pg._upBtn, "Upgrade all bars now", "One-time catch-up: moves EVERY action bar spell to the top rank you know, including lower ranks you placed on purpose.")
    end
    AT.RowDesc(pg, "Spell ranks only exist on WoW Forever.", 20,
        function() return not ranked() end)
    pg:Refresh()
end

function IE.SetStatus(text, ok)
    ieStatus:SetText(text or "")
    if ok then ieStatus:SetTextColor(0.35, 0.85, 0.45)
    else ieStatus:SetTextColor(0.95, 0.42, 0.42) end
end

-- Export picker: a tree of tick boxes. A layout's box ticks it with everything
-- under it, an item's box ticks that item alone, and a layout's mark reads all,
-- some or none. Everything ticked goes into one share string; items without
-- their layout land in the "items import into" layout on the other side.

-- a layout's pickable children in the layout's own order, the rail's order
-- (a group's icons travel with the group, never listed on their own)
function IE.Children(layout)
    return Store.MembersOf(layout)
end

-- the ticked ids, parents first. A group's icon ticked from its own editor
-- (Export on a group member) counts too - it has no picker row, and lands
-- as a free icon on import. A stale tick (record deleted since) drops here.
function IE.SelectedIds()
    local sel, ids, live = ui.ieSel, {}, {}
    local function take(rec)
        if sel[rec.id] then
            ids[#ids + 1] = rec.id
            live[rec.id] = true
        end
    end
    for _, lay in ipairs(Store.Layouts()) do
        take(lay)
        for _, c in ipairs(IE.Children(lay)) do
            take(c)
            if c.type == "group" then
                for _, ic in ipairs(Store.IconsOf(c)) do take(ic) end
            end
        end
    end
    for id in pairs(sel) do
        if not live[id] then sel[id] = nil end
    end
    return ids
end

function IE.PickSummary()
    local nl, ni = 0, 0
    for _, id in ipairs(IE.SelectedIds()) do
        local r = Store.Get(id)
        if r and r.type == "layout" then nl = nl + 1 else ni = ni + 1 end
    end
    if nl == 0 and ni == 0 then return "nothing ticked", 0 end
    local parts = {}
    if nl > 0 then parts[#parts + 1] = nl .. (nl == 1 and " layout" or " layouts") end
    if ni > 0 then parts[#parts + 1] = ni .. (ni == 1 and " item" or " items") end
    return table.concat(parts, ", "), nl + ni
end

-- where loose items (a string without their layout) land on import: the
-- layout picked here, else the one the rail last had open, else the first
function IE.TargetId()
    local t = Store.Get(ui.ieTargetId)
    if t and t.type == "layout" then return t.id end
    t = Store.Get(ui.lastLayoutId)
    if t and t.type == "layout" then return t.id end
    local first = Store.Layouts()[1]
    return first and first.id or 0
end

function IE.Row(i)
    local r = IE.rowPool[i]
    if r then return r end
    r = CreateFrame("Button", nil, ieListHost)
    r:SetHeight(IE.ROW_H)
    r:SetHighlightTexture(WHITE)
    r:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.35)
    r.check = AT.MakeCheckbox(r)
    r.check:EnableMouse(false)   -- the whole row is the click target
    r.chevBtn = CreateFrame("Button", nil, r)
    r.chevBtn:SetSize(18, 18)
    r.chev = AT.MakeChevron(r.chevBtn)
    r.chev:SetPoint("CENTER")
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(STANDARD_TEXT_FONT, 11, "")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.pill = KindPill(r)
    r.pill:SetPoint("RIGHT", -8, 0)
    IE.rowPool[i] = r
    return r
end

local function BuildIEPane()
    iePane = CreateFrame("Frame", nil, content)
    iePane:SetAllPoints()
    panes.ie = iePane
    local h = MakeHeader(iePane)
    h.name:SetText("Import / Export")

    local exLbl = iePane:CreateFontString(nil, "OVERLAY")
    exLbl:SetFont(STANDARD_TEXT_FONT, 9, "")
    exLbl:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    exLbl:SetPoint("TOPLEFT", 4, -40)
    exLbl:SetText("EXPORT - tick whole layouts, or open one and tick just the items to share")

    local pickHost = CreateFrame("Frame", nil, iePane, "BackdropTemplate")
    pickHost:SetPoint("TOPLEFT", 0, -54)
    pickHost:SetPoint("TOPRIGHT", -4, -54)
    pickHost:SetHeight(IE.PICK_H)
    AT.Skin(pickHost, COL.well, COL.line)
    IE.listScroll, ieListHost = AT.MakeScroll(pickHost)
    IE.listScroll:SetPoint("TOPLEFT", 3, -3)
    IE.listScroll:SetPoint("BOTTOMRIGHT", -9, 3)
    IE.listScroll:HookScript("OnSizeChanged", function(s, w)
        ieListHost:SetWidth(math.max(50, w or 300))
        s:UpdateScroll()
    end)

    local expBtn = AT.MakeSmallButton(iePane, "Export selected", 108)
    expBtn:SetPoint("TOPLEFT", pickHost, "BOTTOMLEFT", 0, -6)
    expBtn.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    expBtn:SetScript("OnClick", function() Options.ExportSelected() end)
    AT.Tooltip(expBtn, "Export selected", "Builds one share string from everything ticked above.")
    local allBtn = AT.MakeQuietButton(iePane, "Tick all", 60)
    allBtn:SetPoint("LEFT", expBtn, "RIGHT", 6, 0)
    allBtn:SetScript("OnClick", function()
        for _, lay in ipairs(Store.Layouts()) do
            ui.ieSel[lay.id] = true
            for _, c in ipairs(IE.Children(lay)) do ui.ieSel[c.id] = true end
        end
        IE.Refresh()
    end)
    local noneBtn = AT.MakeQuietButton(iePane, "Untick all", 66)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
    noneBtn:SetScript("OnClick", function()
        ui.ieSel = {}
        IE.Refresh()
    end)
    IE.expStatus = iePane:CreateFontString(nil, "OVERLAY")
    IE.expStatus:SetFont(STANDARD_TEXT_FONT, 10, "")
    IE.expStatus:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    IE.expStatus:SetPoint("LEFT", noneBtn, "RIGHT", 10, 0)
    IE.expStatus:SetPoint("RIGHT", iePane, "RIGHT", -4, 0)
    IE.expStatus:SetJustifyH("LEFT")
    IE.expStatus:SetWordWrap(false)

    -- the string band: label left, the import target right on the same line
    local yStr = -(54 + IE.PICK_H + 6 + 22 + 14)
    local strLbl = iePane:CreateFontString(nil, "OVERLAY")
    strLbl:SetFont(STANDARD_TEXT_FONT, 9, "")
    strLbl:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    strLbl:SetPoint("TOPLEFT", 4, yStr)
    strLbl:SetText("SHARE STRING - Ctrl+C to copy, or paste one here and press Import")

    IE.target = AT.MakeDropdown(win, iePane, 150, function()
        local items = {}
        for _, lay in ipairs(Store.Layouts()) do
            items[#items + 1] = { value = lay.id, text = lay.name }
        end
        if #items == 0 then items[1] = { value = 0, text = "(a new layout)" } end
        return items
    end, IE.TargetId, function(v) ui.ieTargetId = v end)
    IE.target:SetPoint("TOPRIGHT", iePane, "TOPRIGHT", -4, yStr + 6)
    AT.Tooltip(IE.target, "Items import into", "A string holding a group, icon or bar without its layout lands it in this layout. A string holding whole layouts makes new layouts.")
    local tgtLbl = iePane:CreateFontString(nil, "OVERLAY")
    tgtLbl:SetFont(STANDARD_TEXT_FONT, 9, "")
    tgtLbl:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    tgtLbl:SetPoint("RIGHT", IE.target, "LEFT", -6, 0)
    tgtLbl:SetText("ITEMS IMPORT INTO")

    local boxHost = CreateFrame("Frame", nil, iePane, "BackdropTemplate")
    boxHost:SetPoint("TOPLEFT", 0, yStr - 18)
    boxHost:SetPoint("TOPRIGHT", -4, yStr - 18)
    boxHost:SetPoint("BOTTOM", iePane, "BOTTOM", 0, 36)
    AT.Skin(boxHost, COL.well, COL.line)

    ieBox = CreateFrame("EditBox", nil, boxHost)
    ieBox:SetMultiLine(true)
    ieBox:SetAutoFocus(false)
    ieBox:SetFontObject(ChatFontNormal)
    ieBox:SetTextColor(0.85, 0.9, 0.95, 1)
    ieBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    ieScroll = AT.MakeScroll(boxHost, ieBox)
    ieScroll:SetPoint("TOPLEFT", 8, -8)
    ieScroll:SetPoint("BOTTOMRIGHT", -10, 8)
    ieScroll:HookScript("OnSizeChanged", function(s, w)
        ieBox:SetWidth(math.max(60, (w or s:GetWidth() or 300) - 6))
        s:UpdateScroll()
    end)
    ieBox:SetScript("OnTextChanged", function() ieScroll:UpdateScroll() end)
    -- clicking the empty well focuses the box (the editbox only spans its text)
    boxHost:EnableMouse(true)
    boxHost:SetScript("OnMouseUp", function() ieBox:SetFocus() end)

    local impBtn = AT.MakeSmallButton(iePane, "Import", 92)
    impBtn:SetPoint("BOTTOMLEFT", 0, 4)
    impBtn.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    impBtn:SetScript("OnClick", function()
        local res, err = Store.Import(ieBox and ieBox:GetText() or "", IE.TargetId())
        if not res then
            IE.SetStatus(err or "Import failed.", false)
            return
        end
        local nl, ni = #res.layouts, #res.items
        local parts = {}
        if nl > 0 then
            parts[#parts + 1] = (nl == 1)
                and ("layout \"" .. tostring(res.layouts[1].name) .. "\"")
                or (nl .. " layouts")
        end
        if ni > 0 and res.target then
            parts[#parts + 1] = ni .. (ni == 1 and " item" or " items")
                .. " into \"" .. tostring(res.target.name) .. "\""
        end
        -- Say how many will not show on this character (a Rogue layout on a
        -- Hunter), so a class-locked import never looks failed. A record under a
        -- parent that does not load counts too.
        local off = 0
        local function Tally(r, parentOff)
            if not r then return end
            local isOff = parentOff or not Store.IsLoaded(r)
            if isOff then off = off + 1 end
            if r.type == "layout" then
                for _, m in ipairs(Store.MembersOf(r)) do Tally(m, isOff) end
            elseif r.type == "group" then
                for _, ic in ipairs(Store.IconsOf(r)) do Tally(ic, isOff) end
            end
        end
        for _, l in ipairs(res.layouts) do Tally(l, false) end
        for _, it in ipairs(res.items) do Tally(it, false) end
        local msg = "Imported " .. table.concat(parts, " and ") .. "."
        if off > 0 then
            msg = msg .. " " .. off .. " of them "
                .. (off == 1 and "does" or "do")
                .. " not load here: the eye in the sidebar shows them."
        end
        IE.SetStatus(msg, true)
        if nl > 0 then
            SelectRecord(res.layouts[1])
        elseif res.items[1] then
            SelectRecord(res.items[1])
        end
    end)

    local clrBtn = AT.MakeSmallButton(iePane, "Clear", 60)
    clrBtn:SetPoint("LEFT", impBtn, "RIGHT", 6, 0)
    clrBtn:SetScript("OnClick", function()
        ieBox:SetText("")
        IE.SetStatus("", true)
    end)

    ieStatus = iePane:CreateFontString(nil, "OVERLAY")
    ieStatus:SetFont(STANDARD_TEXT_FONT, 11, "")
    ieStatus:SetPoint("LEFT", clrBtn, "RIGHT", 10, 0)
    ieStatus:SetPoint("RIGHT", iePane, "RIGHT", -4, 0)
    ieStatus:SetJustifyH("LEFT")
    -- two lines at most: an import report that also counts what does not
    -- load here must never lose its second half off the edge
    ieStatus:SetWordWrap(true)
    if ieStatus.SetMaxLines then ieStatus:SetMaxLines(2) end
    ieStatus:SetText("")
end

function IE.Refresh()
    local sel, open = ui.ieSel, ui.ieOpen
    local w = IE.listScroll:GetWidth()
    if not w or w < 50 then w = 300 end
    ieListHost:SetWidth(w)
    local y, n = 0, 0
    local function Row(rec, indent, isLayout, state, onClick, chevDown, onChev)
        n = n + 1
        local r = IE.Row(n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        r:SetPoint("TOPRIGHT", 0, y)
        y = y - IE.ROW_H
        r.check:ClearAllPoints()
        r.check:SetPoint("LEFT", indent, 0)
        r.check:SetOn(state ~= nil)
        r.check.check:SetAlpha(state == "some" and 0.45 or 1)
        r.chevBtn:SetShown(isLayout == true)
        r.chevBtn:ClearAllPoints()
        r.chevBtn:SetPoint("LEFT", indent + 22, 0)
        r.chev:SetDown(chevDown == true)
        r.chevBtn:SetScript("OnClick", onChev)
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", indent + (isLayout and 44 or 24), 0)
        r.name:SetPoint("RIGHT", r.pill, "LEFT", -6, 0)
        r.name:SetText(rec.name)
        local c = state and COL.ink or COL.dim
        r.name:SetTextColor(c[1], c[2], c[3])
        r:SetScript("OnClick", onClick)
        r:Show()
        return r
    end
    for _, lay in ipairs(Store.Layouts()) do
        local kids = IE.Children(lay)
        local total, picked = 1 + #kids, sel[lay.id] and 1 or 0
        for _, c in ipairs(kids) do
            if sel[c.id] then picked = picked + 1 end
        end
        local state
        if picked > 0 then state = (picked == total) and "all" or "some" end
        local r = Row(lay, 6, true, state, function()
            local on = state ~= "all"
            sel[lay.id] = on or nil
            for _, c in ipairs(kids) do sel[c.id] = on or nil end
            IE.Refresh()
        end, open[lay.id] == true, function()
            open[lay.id] = not open[lay.id] or nil
            IE.Refresh()
        end)
        r.pill:Set(#kids == 1 and "1 item" or (#kids .. " items"), COL.dim)
        if open[lay.id] then
            for _, c in ipairs(kids) do
                local cr = Row(c, 28, false, sel[c.id] and "all" or nil, function()
                    sel[c.id] = not sel[c.id] or nil
                    IE.Refresh()
                end)
                if c.type == "group" then
                    GroupPill(cr.pill, c.groupKind)
                elseif c.type == "bar" then
                    BarPill(cr.pill, c.barKind, c.barMode)
                else
                    cr.pill:Set(Options.IconPillText(c.kind))
                end
            end
        end
    end
    for i = n + 1, #IE.rowPool do IE.rowPool[i]:Hide() end
    ieListHost:SetHeight(math.max(1, -y))
    IE.listScroll:UpdateScroll()
    local what, count = IE.PickSummary()
    IE.expStatus:SetText(count > 0 and (what .. " ticked") or "nothing ticked yet")
    IE.target.Refresh()
end

-- build the string from everything ticked and fill the box pre-highlighted
-- so Ctrl+C is the only step left
function Options.ExportSelected()
    local s, n = Store.Export(IE.SelectedIds())
    if s then
        ieBox:SetText(s)
        ieBox:SetFocus()
        ieBox:HighlightText()
        local what = IE.PickSummary()
        IE.SetStatus(string.format("%s exported (%d records, %d characters). Ctrl+C copies it.",
            what, n, #s), true)
    else
        ieBox:SetText("")
        IE.SetStatus(n or "Export failed.", false)
    end
end

-- the rail Exp button and the editors' Export buttons land here: tick that
-- one record (a layout with everything under it) and export it
function Options.OpenExport(id)
    Options.Open()
    Options.Select("ie")
    local rec = Store.Get(id)
    if rec then
        ui.ieSel = { [id] = true }
        if rec.type == "layout" then
            for _, c in ipairs(IE.Children(rec)) do ui.ieSel[c.id] = true end
            ui.ieOpen[id] = true
        else
            local lid = rec.layoutId
            if not lid and rec.groupId then
                local g = Store.Get(rec.groupId)
                lid = g and g.layoutId
            end
            if lid then ui.ieOpen[lid] = true end
        end
        IE.Refresh()
    end
    Options.ExportSelected()
end

function Options.Select(selType, id)
    -- Play on screen belongs to the bar being edited
    local B = NS.Bars
    if B and B.PreviewScreenOn and B.PreviewScreenOn()
        and not (selType == "bar" and B.PreviewScreenOn(id)) then
        B.PreviewScreenStop()
    end
    ui.selType, ui.selId = selType, id
    -- the import target follows the rail: the layout last opened here
    if selType == "layout" or selType == "free" then
        ui.lastLayoutId = id
    elseif selType == "group" or selType == "bar" then
        local r = Store.Get(id)
        if r then ui.lastLayoutId = r.layoutId end
    end
    -- the grow arrows follow the editor's open group (no rebuild needed)
    if Engine and Engine.RefreshArrows then Engine.RefreshArrows() end
    if selType == "ie" or selType == "settings" or selType == "qol" then
        ShowPane(selType)
        RefreshAll()
        return
    end
    if selType == "group" then
        if ui.grpMode ~= "ico" then ui.grpMode = "grp" end
        local g = Store.Get(id)
        if g then ExpandedSet()[g.layoutId] = true end
    elseif selType == "bar" then
        local b = Store.Get(id)
        if b then ExpandedSet()[b.layoutId] = true end
    elseif selType == "free" then
        ExpandedSet()[id] = true
    end
    ShowPane(selType == "layout" and "layout" or selType == "group" and "group"
        or selType == "free" and "free" or selType == "bar" and "bar" or "empty")
    RefreshAll()
end

-- After creating a bar, or from its on-screen Edit chip, land on its editor.
function Options.SelectBarHome(rec)
    Options.Select("bar", rec.id)
end

local function RefreshPane()
    if not win or not win:IsShown() then return end
    if ui.selType == "layout" then RefreshLayoutPane()
    elseif ui.selType == "group" then RefreshGroupPane()
    elseif ui.selType == "free" then RefreshFreePane()
    elseif ui.selType == "bar" then RefreshBarPane()
    elseif ui.selType == "settings" then settingsPage:Refresh()
    elseif ui.selType == "qol" then qolPage:Refresh()
    elseif ui.selType == "ie" then IE.Refresh() end
end

RefreshAll = function()
    if not win or not win:IsShown() then return end
    RefreshRail()
    PaintAddonRows()
    RefreshPane()
    -- the search results follow a resize like every other pane
    local S = Options.Search
    if S and S.showing and S.page then AT.LayoutPage(S.page) end
end
Options.RefreshAll = function() RefreshAll() end
Options.RefreshPane = RefreshPane

-- Search: the rail's box finds your layouts, groups, icons and bars (by name,
-- tracked spell or item ID, or an icon's art file ID) and every labelled option
-- row. The index walks each editor page under every tab and sub-panel for one
-- sample record per kind, through the panel's own visibility functions, so an
-- option is found exactly where the panel draws it. The walk only reads (the ui
-- state is saved and restored, no _sync runs); AD_DIRTY drops the index.
Options.Search = {
    MAX_EL = 30, MAX_OPT = 60,
    FAMS = { "layout", "group", "icon", "bar" },
    FAM_WORD = { layout = "Layout", group = "Group", icon = "Icon", bar = "Bar",
        settings = "Settings", qol = "QOL" },
    -- result order among equal matches: the open editor's family first
    FAM_RANK = { icon = 1, group = 2, bar = 3, layout = 4, settings = 5, qol = 6 },
    KIND_WORD = {
        icon = { spell = "spell icons", aura = "aura icons", trinket = "trinket icons",
            item = "item icons", timer = "timer icons", totem = "totem icons",
            ammo = "ammo icons" },
        bar = { cooldown = "cooldown bars", aura = "aura bars", timer = "timer bars",
            stack = "stack bars", swing = "swing bars", resource = "resource bars",
            health = "health bars" },
        group = { aura = "aura groups", cooldown = "CD groups" },
    },
    -- the ui fields a sample walk moves (put back by RestoreUI)
    UI_KEYS = { "selType", "selId", "selIconId", "grpMode", "layoutTab",
        "grpTab", "grpSec", "icoTab", "barTab" },
}

function Options.Search.Norm(s)
    s = tostring(s or ""):lower()
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Options.Search.Words(q)
    local out = {}
    for w in q:gmatch("%S+") do out[#out + 1] = w end
    return out
end

-- how well `text` answers the query: 0 exact, 1 starts with it, 2 a word
-- in it starts with it, 3 contains it, 4 holds every word somewhere;
-- nil = no match
function Options.Search.Score(text, q, words)
    if type(text) ~= "string" or text == "" then return nil end
    local t = text:lower()
    if t == q then return 0 end
    local a = t:find(q, 1, true)
    if a == 1 then return 1 end
    if a then
        if t:sub(a - 1, a - 1):find("%w") then return 3 end
        return 2
    end
    if #words < 2 then return nil end
    for _, w in ipairs(words) do
        if not t:find(w, 1, true) then return nil end
    end
    return 4
end

function Options.Search.RecIDs(rec)
    local out, d = {}, rec.driver
    if type(d) ~= "table" then return out end
    local function add(v)
        v = tonumber(v)
        if v and v > 0 then out[#out + 1] = v end
    end
    add(d.spellID)
    add(d.itemID)
    if type(d.spellIDs) == "table" then
        for _, v in ipairs(d.spellIDs) do add(v) end
    end
    return out
end

-- score a record: a plain number is one of its tracked ids or (icons) the
-- art file ID it draws, anything else its name. The second return says
-- what matched when it was not the name.
function Options.Search.RecScore(rec, q, words, num)
    if num then
        for _, id in ipairs(Options.Search.RecIDs(rec)) do
            if id == num then return 0, "ID " .. num end
        end
        if rec.type == "icon" then
            local tex = Factory.GetTexture(rec)
            if not (issecretvalue and issecretvalue(tex)) and type(tex) == "number"
                and tex == num then
                return 0, "icon ID " .. num
            end
        end
    end
    return Options.Search.Score(rec.name, q, words)
end

-- your layouts, groups, icons (group members too) and bars that match,
-- best first, tree order among equals
function Options.Search.Elements(q, words, num)
    local S = Options.Search
    local out = {}
    local function take(rec, where)
        local sc, why = S.RecScore(rec, q, words, num)
        if sc then
            out[#out + 1] = { rec = rec, score = sc, where = where, why = why, n = #out + 1 }
        end
    end
    for _, layout in ipairs(Store.Layouts()) do
        take(layout, nil)
        for _, m in ipairs(Store.MembersOf(layout)) do
            take(m, layout.name)
            if m.type == "group" then
                for _, ic in ipairs(Store.IconsOf(m)) do
                    take(ic, layout.name .. "  >  " .. m.name)
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.n < b.n
    end)
    return out
end

function Options.Search.FamOf(r)
    local t = r and r.type
    if t == "layout" or t == "group" or t == "icon" or t == "bar" then return t end
end

function Options.Search.KindOf(r)
    if r.type == "group" then return r.groupKind == "aura" and "aura" or "cooldown" end
    if r.type == "icon" then return r.kind or "spell" end
    if r.type == "bar" then return r.barKind or "cooldown" end
    return "layout"
end

-- Records sharing a key draw the same rows: an icon's kind and its home (free,
-- group member, aura-group member), a bar's kind and mode.
function Options.Search.KeyOf(r)
    if r.type == "icon" then
        local home = r.groupId and (InAuraGroup(r) and ":ag" or ":g") or ":f"
        return (r.kind or "spell") .. home
    end
    if r.type == "bar" then return (r.barKind or "cooldown") .. ":" .. (r.barMode or "") end
    return Options.Search.KindOf(r)
end

-- the record the editor has open, per family: an option result jumps to it
-- when it draws the row (same key), else to the sample it was found on
function Options.Search.OpenFor(fam)
    if fam == "layout" then return SelLayout() end
    if fam == "group" then return SelGroup() end
    if fam == "icon" then
        if ui.selType == "group" or ui.selType == "free" then return SelIcon() end
        return nil
    end
    if fam == "bar" then return SelBar() end
end

-- the open editor's family (ranks its options first)
function Options.Search.CurFam()
    local t = ui.selType
    if t == "group" then return ui.grpMode == "ico" and "icon" or "group" end
    if t == "free" then return "icon" end
    return t
end

-- One sample record per key, the open records first.
function Options.Search.Samples()
    local S = Options.Search
    local out = { layout = {}, group = {}, icon = {}, bar = {} }
    local seen = {}
    local function add(r)
        local fam = S.FamOf(r)
        if not fam then return end
        local key = S.KeyOf(r)
        if seen[fam .. "|" .. key] then return end
        seen[fam .. "|" .. key] = true
        local list = out[fam]
        list[#list + 1] = { rec = r, key = key, kind = S.KindOf(r) }
    end
    for _, fam in ipairs(S.FAMS) do add(S.OpenFor(fam)) end
    for _, layout in ipairs(Store.Layouts()) do
        add(layout)
        for _, m in ipairs(Store.MembersOf(layout)) do
            add(m)
            if m.type == "group" then
                for _, ic in ipairs(Store.IconsOf(m)) do add(ic) end
            end
        end
    end
    return out
end

-- The selection and tab state a walk moves, saved by key list: a nil value
-- must come back as nil too, which pairs() would skip.
function Options.Search.SaveUI()
    local s = { vals = {}, icoSec = {}, barSec = {} }
    for i, k in ipairs(Options.Search.UI_KEYS) do s.vals[i] = ui[k] end
    for k, v in pairs(ui.icoSec or {}) do s.icoSec[k] = v end
    for k, v in pairs(ui.barSec or {}) do s.barSec[k] = v end
    return s
end

function Options.Search.RestoreUI(s)
    for i, k in ipairs(Options.Search.UI_KEYS) do ui[k] = s.vals[i] end
    for _, key in ipairs({ "icoSec", "barSec" }) do
        local t = ui[key]
        if t then
            for k in pairs(t) do t[k] = nil end
            for k, v in pairs(s[key]) do t[k] = v end
        end
    end
end

-- the label a result shows: the schema label, the row's column label, or
-- a bare button's own text. Rows with none (push bars, lists) never index.
function Options.Search.RowLabel(row)
    local m = row._adMeta
    if m then return m.def.label or m.field end
    local fs = row._colLabel
    local t = fs and fs:GetText()
    if (t == nil or t == "") and row.button and row.button.fs then
        t = row.button.fs:GetText()
    end
    if type(t) == "string" and t ~= "" then return t end
end

-- The theme stores a plain section title in upper case: read it back in
-- sentence case ("HEALTH COLORS" -> "Health colors"). A collapsible one keeps
-- its own words.
function Options.Search.SecTitle(sec)
    local t = sec.title and sec.title:GetText()
    if type(t) ~= "string" or t == "" then return nil end
    if sec.hit then return t end
    return t:sub(1, 1) .. t:sub(2):lower()
end

-- Every row the page draws in the current ui state, dep gates ignored.
function Options.Search.WalkPage(pg, sink)
    for _, sec in ipairs(pg._sections or {}) do
        if (not sec.visibleFn) or sec.visibleFn() then
            for _, row in ipairs(sec.rows) do
                local m = row._adMeta
                local on
                if m then
                    on = m.baseVis()
                else
                    on = (not row._visibleFn) or row._visibleFn()
                end
                if on then sink(row, sec) end
            end
        end
    end
end

-- One sample: select it the way its pane would (nothing refreshes), then walk
-- every tab and every applicable sub-panel of its editor page.
function Options.Search.WalkSample(fam, rec, add)
    local S = Options.Search
    local src = Options.SEARCH_SRC and Options.SEARCH_SRC[fam]
    if not (src and src.page) then return end
    local tabs, setTab, setSub
    if fam == "layout" then
        ui.selType, ui.selId = "layout", rec.id
        tabs = src.tabs
        setTab = function(t) ui.layoutTab = t end
    elseif fam == "group" then
        ui.selType, ui.selId, ui.grpMode = "group", rec.id, "grp"
        tabs = src.tabs
        setTab = function(t) ui.grpTab = t end
        setSub = function(_, s) ui.grpSec = s end
    elseif fam == "icon" then
        -- the icon editor's host: its group in icon mode, or its layout
        if rec.groupId then
            ui.selType, ui.selId, ui.grpMode = "group", rec.groupId, "ico"
        else
            ui.selType, ui.selId = "free", rec.layoutId
        end
        ui.selIconId = rec.id
        tabs = IconTabsFor(rec)
        setTab = function(t) ui.icoTab = t end
        setSub = function(t, s) ui.icoSec[t] = s end
    elseif fam == "bar" then
        ui.selType, ui.selId = "bar", rec.id
        tabs = BAR_TABS[rec.barKind] or BAR_TABS.cooldown
        setTab = function(t) ui.barTab = t end
        setSub = function(t, s) ui.barSec[t] = s end
    end
    for _, tab in ipairs(tabs or {}) do
        setTab(tab)
        local subs = (src.subs and src.subs(tab)) or {}
        -- a single applicable sub-panel renders plain: no chip to name
        local chips = #subs >= 2
        if #subs == 0 then subs = { false } end
        for _, sub in ipairs(subs) do
            if sub and setSub then setSub(tab, sub) end
            S.WalkPage(src.page, function(row, sec)
                add(row, sec, tab, chips and sub or nil)
            end)
        end
    end
end

-- "Appearance  >  Fill": tab, sub-panel, section - each once
function Options.Search.PathOf(e)
    local parts = {}
    local function push(t)
        if type(t) ~= "string" or t == "" then return end
        local lt = t:lower()
        for _, p in ipairs(parts) do
            if p:lower() == lt then return end
        end
        parts[#parts + 1] = t
    end
    push(e.tab)
    push(e.sub)
    push(e.secTitle)
    return table.concat(parts, "  >  ")
end

-- "health bars only" / "not on ammo icons": a row some kinds of its
-- family draw and others do not (among the kinds you have)
function Options.Search.NoteOf(e, famKinds)
    local words = Options.Search.KIND_WORD[e.fam]
    if not (words and famKinds) then return nil end
    local mine, missing = {}, {}
    for k in pairs(famKinds) do
        if e.kinds[k] then mine[#mine + 1] = words[k] or k
        else missing[#missing + 1] = words[k] or k end
    end
    if #mine == 0 or #missing == 0 then return nil end
    local function list(t, conj)
        table.sort(t)
        if #t <= 2 then return table.concat(t, conj) end
        return t[1] .. ", " .. t[2] .. conj .. (#t - 2) .. " more"
    end
    if #mine <= #missing then return list(mine, " and ") .. " only" end
    return "not on " .. list(missing, " or ")
end

-- "shows when Color by is Gradient": the switch a dep-gated row waits on
function Options.Search.DepNote(row)
    local m = row._adMeta
    local dep = m and m.def.dep
    if not dep then return nil end
    local d = dep.field and dep or dep[1]
    if not d then return nil end
    local famDef = Schema[m.family]
    local secDef = famDef and famDef[d.section or m.section]
    local fdef = secDef and secDef.fields and secDef.fields[d.field]
    local name = (fdef and fdef.label) or d.field
    local function word(v)
        local L = fdef and fdef.labels
        return tostring((L and L[v]) or v)
    end
    if d.nonempty then return "shows when " .. name .. " is set" end
    if d.notValue ~= nil then return "shows when " .. name .. " is not " .. word(d.notValue) end
    if d.min ~= nil then return "shows when " .. name .. " is " .. d.min .. " or more" end
    if d.anyOf ~= nil then
        -- the set in the field's own value order (stable), words joined
        local ws = {}
        if fdef and fdef.values then
            for _, v in ipairs(fdef.values) do
                if d.anyOf[v] == true then ws[#ws + 1] = word(v) end
            end
        else
            for v in pairs(d.anyOf) do ws[#ws + 1] = word(v) end
            table.sort(ws)
        end
        if #ws == 0 then return nil end
        local tail = table.remove(ws)
        if #ws == 0 then return "shows when " .. name .. " is " .. tail end
        return "shows when " .. name .. " is " .. table.concat(ws, ", ") .. " or " .. tail
    end
    local want = d.value
    if want == nil then want = true end
    if want == true then return "shows when " .. name .. " is on" end
    if want == false then return "shows when " .. name .. " is off" end
    return "shows when " .. name .. " is " .. word(want)
end

function Options.Search.Same(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- Three kinds of entry, each found once: a labelled row; a condition cell
-- (row._adSearch lists the checkboxes a grid row offers); and a titled section
-- whose name is not already its tab's or sub-panel's, so a block of custom rows
-- (Faction, Classes, Talents) is found by its name.
function Options.Search.BuildIndex()
    local S = Options.Search
    local idx = { list = {}, byRow = {}, byCell = {}, bySec = {}, famKinds = {} }
    local function new(fam, row, sec, tab, sub, label, secTitle)
        local e = { fam = fam, row = row, sec = sec, label = label, tab = tab, sub = sub,
            secTitle = secTitle, kinds = {}, keys = {}, recs = {},
            order = #idx.list + 1 }
        idx.list[#idx.list + 1] = e
        return e
    end
    local function seen(e, smp)
        if not smp then return end
        e.kinds[smp.kind] = true
        if not e.keys[smp.key] then
            e.keys[smp.key] = true
            e.recs[#e.recs + 1] = smp.rec
        end
    end
    local function visit(fam, smp, row, sec, tab, sub)
        local st = S.SecTitle(sec)
        if st and not S.Same(st, tab) and not S.Same(st, sub) then
            local e = idx.bySec[sec]
            if not e then
                e = new(fam, row, sec, tab, sub, st, nil)
                e.isSection = true
                idx.bySec[sec] = e
            end
            seen(e, smp)
        end
        if row._adSearch then
            local cells = idx.byCell[row]
            if not cells then
                cells = {}
                idx.byCell[row] = cells
            end
            for _, text in ipairs(row._adSearch()) do
                local e = cells[text]
                if not e then
                    e = new(fam, row, sec, tab, sub, text, st)
                    cells[text] = e
                end
                seen(e, smp)
            end
            return
        end
        local e = idx.byRow[row]
        if not e then
            local label = S.RowLabel(row)
            if not label then return end
            e = new(fam, row, sec, tab, sub, label, st)
            idx.byRow[row] = e
        end
        seen(e, smp)
    end
    local saved = S.SaveUI()
    local samples = S.Samples()
    for _, fam in ipairs(S.FAMS) do
        local kinds = {}
        idx.famKinds[fam] = kinds
        for _, smp in ipairs(samples[fam]) do
            kinds[smp.kind] = true
            S.WalkSample(fam, smp.rec, function(row, sec, tab, sub)
                visit(fam, smp, row, sec, tab, sub)
            end)
        end
    end
    S.RestoreUI(saved)
    -- the addon pages: no record, no tabs, drawn as they are
    for _, fam in ipairs({ "settings", "qol" }) do
        local src = Options.SEARCH_SRC and Options.SEARCH_SRC[fam]
        if src and src.page then
            S.WalkPage(src.page, function(row, sec) visit(fam, nil, row, sec, nil, nil) end)
        end
    end
    for _, e in ipairs(idx.list) do
        e.path = S.PathOf(e)
        e.note = S.NoteOf(e, idx.famKinds[e.fam])
        -- a section entry flashes its first row; that row's dep is not the
        -- section's
        e.dep = (not e.isSection) and S.DepNote(e.row) or nil
        e.hay = (e.label .. " " .. e.path):lower()
    end
    S.idx = idx
    return idx
end

-- options that match, best first: the label itself, then every word found
-- across the label and where it lives ("absorb color", "heals opacity")
function Options.Search.OptionHits(q, words)
    local S = Options.Search
    local idx = S.idx or S.BuildIndex()
    local cur = S.CurFam()
    local out = {}
    for _, e in ipairs(idx.list) do
        local sc = S.Score(e.label, q, words)
        if not sc then
            local ok = true
            for _, w in ipairs(words) do
                if not e.hay:find(w, 1, true) then
                    ok = false
                    break
                end
            end
            if ok then sc = 5 end
        end
        if sc then out[#out + 1] = { e = e, score = sc } end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        local ra = (a.e.fam == cur) and 0 or (S.FAM_RANK[a.e.fam] or 9)
        local rb = (b.e.fam == cur) and 0 or (S.FAM_RANK[b.e.fam] or 9)
        if ra ~= rb then return ra < rb end
        return a.e.order < b.e.order
    end)
    return out
end

function Options.Search.Run()
    local S = Options.Search
    local q = S.Norm(ui.search)
    local words = S.Words(q)
    local num = q:match("^%d+$") and tonumber(q) or nil
    S.res = { q = q, el = S.Elements(q, words, num), opt = S.OptionHits(q, words) }
    local n = #S.res.el + #S.res.opt
    if S.header then
        local shown = q:gsub("|", "||")
        S.header.sub:SetText(n == 0 and ("nothing matches \"" .. shown .. "\"")
            or (n .. (n == 1 and " match" or " matches") .. " for \"" .. shown .. "\""))
    end
    if S.page then
        S.page._scrollOff = 0
        AT.LayoutPage(S.page)
    end
end

-- the pane the selection owns (the search box was cleared)
function Options.Search.ShowSelPane()
    local t = ui.selType
    if t == "layout" or t == "group" or t == "free" or t == "bar"
        or t == "ie" or t == "settings" or t == "qol" then
        ShowPane(t)
    else
        ShowPane("empty")
    end
    RefreshAll()
end

-- the box's OnTextChanged: results while there is a query, the editor back
-- the moment it is empty. The rail filters on the same words.
function Options.Search.Changed()
    local S = Options.Search
    if S.quiet then return end
    RefreshRail()
    if S.Norm(ui.search) ~= "" then
        if not S.page then Options.BuildSearchPane() end
        S.showing = true
        ShowPane("search")
        S.Run()
    elseif S.showing then
        S.showing, S.res = nil, nil
        S.ShowSelPane()
    end
end

-- Empty the box without its handler re-showing the old pane (a jump is about
-- to show the new one).
function Options.Search.ClearBox()
    local S = Options.Search
    S.showing, S.res = nil, nil
    ui.search = ""
    if S.box then
        S.quiet = true
        S.box:SetText("")
        S.box:ClearFocus()
        S.quiet = nil
    end
end

function Options.Search.GoElement(rec)
    if not (rec and Store.Get(rec.id)) then return end
    Options.Search.ClearBox()
    -- A group result opens the group's settings, not its last icon.
    if rec.type == "group" then ui.grpMode = "grp" end
    SelectRecord(rec)
end

function Options.Search.GoOption(e)
    local S = Options.Search
    local rec
    if e.fam ~= "settings" and e.fam ~= "qol" then
        local open = S.OpenFor(e.fam)
        if open and e.keys[S.KeyOf(open)] then rec = open end
        if not rec then
            for _, r in ipairs(e.recs) do
                if Store.Get(r.id) then
                    rec = r
                    break
                end
            end
        end
        if not rec then return end
    end
    S.ClearBox()
    if e.fam == "settings" or e.fam == "qol" then
        Options.Select(e.fam)
    elseif e.fam == "layout" then
        ui.layoutTab = e.tab
        ExpandedSet()[rec.id] = true
        Options.Select("layout", rec.id)
    elseif e.fam == "group" then
        ui.grpMode, ui.grpTab = "grp", e.tab
        if e.sub then ui.grpSec = e.sub end
        Options.Select("group", rec.id)
    elseif e.fam == "icon" then
        ui.icoTab = e.tab
        if e.sub then ui.icoSec[e.tab] = e.sub end
        Options.SelectIconHome(rec)
    elseif e.fam == "bar" then
        ui.barTab = e.tab
        if e.sub then ui.barSec[e.tab] = e.sub end
        Options.Select("bar", rec.id)
    end
    -- next frame, once the pane has laid out: scroll the row in, flash it
    C_Timer.After(0, function() S.Reveal(e) end)
end

-- Enter in the box: the top result
function Options.Search.GoFirst()
    local S = Options.Search
    local r = S.res
    if not (S.showing and r) then return end
    if r.el[1] then S.GoElement(r.el[1].rec)
    elseif r.opt[1] then S.GoOption(r.opt[1].e) end
end

-- the switch a dep-hidden row waits on, when the page shows it
function Options.Search.DepSwitch(pg, row)
    local m = row._adMeta
    local dep = m and m.def.dep
    if not dep then return nil end
    local list = dep.field and { dep } or dep
    for _, d in ipairs(list) do
        local secName = d.section or m.section
        for _, sec in ipairs(pg._sections) do
            for _, r in ipairs(sec.rows) do
                local rm = r._adMeta
                if rm and rm.field == d.field and rm.section == secName and r:IsVisible() then
                    return r
                end
            end
        end
    end
end

function Options.Search.Reveal(e)
    local S = Options.Search
    local src = Options.SEARCH_SRC and Options.SEARCH_SRC[e.fam]
    local pg = src and src.page
    if not (pg and pg:IsVisible()) then return end
    -- a shut collapsible holding the row opens first (and stays open)
    local sec = e.sec
    if sec and sec.collapsed then
        sec.collapsed, sec.f = false, 1
        if sec.store and sec.store.secCollapsed and sec.title then
            sec.store.secCollapsed[sec.title:GetText()] = nil
        end
    end
    AT.LayoutPage(pg)
    local target = e.row
    if not target:IsVisible() then target = S.DepSwitch(pg, e.row) end
    if not (target and target:IsVisible()) then return end
    S.ScrollTo(pg, target)
    S.Flash(target)
end

-- scroll a page (the theme's in-place offset) so `row` sits near the top,
-- only when it is not already fully in view
function Options.Search.ScrollTo(pg, row)
    if not pg._scroll then return end
    local top, bottom = pg:GetTop(), pg:GetBottom()
    local rt, rb = row:GetTop(), row:GetBottom()
    if not (top and bottom and rt and rb) then return end
    if rt <= top and rb >= bottom then return end
    local off = (pg._scrollOff or 0) + (top - rt) - 48
    local over = pg._scroll.overflow()
    if off > over then off = over end
    if off < 0 then off = 0 end
    pg._scrollOff = off
    AT.LayoutPage(pg)
end

-- one cyan box that fades in over the row, holds, and fades out: an
-- animation group, so nothing runs once it is done
function Options.Search.Flash(row)
    local S = Options.Search
    local f = S.flash
    if not f then
        f = CreateFrame("Frame", nil, row, "BackdropTemplate")
        AT.Skin(f, COL.arc, COL.arc)
        f:SetBackdropColor(COL.arc[1], COL.arc[2], COL.arc[3], 0.18)
        f:EnableMouse(false)
        local ag = f:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.15)
        a:SetOrder(1)
        local b = ag:CreateAnimation("Alpha")
        b:SetFromAlpha(1)
        b:SetToAlpha(0)
        b:SetDuration(0.8)
        b:SetStartDelay(1.0)
        b:SetOrder(2)
        ag:SetScript("OnFinished", function() f:Hide() end)
        f.ag = ag
        S.flash = f
    end
    f.ag:Stop()
    f:SetParent(row)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", row, "TOPLEFT", -3, 1)
    f:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 3, -1)
    f:SetFrameLevel(row:GetFrameLevel() + 15)
    f:Show()
    f.ag:Play()
end

-- one result: a flat button with the name on top (kind pill at its right)
-- and where it lives under it. `which` = "el" (a record) or "opt".
function Options.Search.ResultRow(pg, which, i)
    local S = Options.Search
    local row = AT.AddRow(pg, 34, function()
        return S.res ~= nil and S.res[which][i] ~= nil
    end)
    local b = CreateFrame("Button", nil, row)
    b:SetAllPoints()
    b:SetHighlightTexture(WHITE)
    b:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.35)
    if which == "el" then b.thumb = MakeThumb(b, 18, 20) end
    b.pill = KindPill(b)
    b.pill:SetPoint("RIGHT", b, "TOPRIGHT", -8, -11)
    b.name = b:CreateFontString(nil, "OVERLAY")
    b.name:SetFont(STANDARD_TEXT_FONT, 12, "")
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    b.where = b:CreateFontString(nil, "OVERLAY")
    b.where:SetFont(STANDARD_TEXT_FONT, 10, "")
    b.where:SetJustifyH("LEFT")
    b.where:SetWordWrap(false)
    b.where:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    b:SetScript("OnClick", function()
        local r = S.res and S.res[which][i]
        if not r then return end
        if which == "el" then S.GoElement(r.rec) else S.GoOption(r.e) end
    end)
    row._sync = function()
        local r = S.res and S.res[which][i]
        if not r then return end
        local x = 10
        if which == "el" then
            local rec = r.rec
            b.thumb:Show()
            if rec.type == "group" then
                b.thumb:SetGroup(rec.groupKind == "aura" and PURPLE or YELLOW)
                GroupPill(b.pill, rec.groupKind)
            elseif rec.type == "bar" then
                b.thumb:SetBar(rec, 22)
                BarPill(b.pill, rec.barKind, rec.barMode)
            elseif rec.type == "icon" then
                b.thumb:SetIcon(Factory.GetTexture(rec))
                b.pill:Set(Options.IconPillText(rec.kind))
            else
                b.thumb:Hide()
                b.pill:Set("Layout", COL.dim)
            end
            if b.thumb:IsShown() then
                b.thumb:ClearAllPoints()
                b.thumb:SetPoint("LEFT", 8 + (22 - b.thumb:GetWidth()) / 2, 0)
                x = 38
            end
            b.name:SetText(rec.name)
            local where = r.where and ("in " .. r.where) or "a layout"
            if r.why then where = where .. "  -  " .. r.why end
            b.where:SetText(where)
        else
            local e = r.e
            b.pill:Set(S.FAM_WORD[e.fam] or e.fam, COL.dim)
            b.name:SetText(e.label)
            local parts = {}
            if e.path ~= "" then parts[#parts + 1] = e.path end
            if e.note then parts[#parts + 1] = e.note end
            if e.dep then parts[#parts + 1] = e.dep end
            b.where:SetText(table.concat(parts, "  -  "))
        end
        b.name:ClearAllPoints()
        b.name:SetPoint("LEFT", b, "TOPLEFT", x, -11)
        b.name:SetPoint("RIGHT", b.pill, "LEFT", -8, 0)
        b.where:ClearAllPoints()
        b.where:SetPoint("LEFT", b, "BOTTOMLEFT", x, 10)
        b.where:SetPoint("RIGHT", b, "BOTTOMRIGHT", -8, 10)
    end
    return row
end

-- "12 more - add a word to narrow it down." under a capped list
function Options.Search.MoreRow(pg, which, max)
    local S = Options.Search
    local row = AT.AddRow(pg, 22, function()
        return S.res ~= nil and #S.res[which] > max
    end)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 10, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row._sync = function()
        local n = S.res and #S.res[which] or 0
        fs:SetText((n - max) .. " more - add a word to narrow it down.")
    end
    return row
end

-- the results pane: built on the first search, not with the window
function Options.BuildSearchPane()
    local S = Options.Search
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.search = pane
    local h = MakeHeader(pane)
    h.name:SetText("Search")
    h.chip1:Hide()
    h.chip2:Hide()
    S.header = h
    local pg = AT.NewPage(pane)
    AT.MakeScrollable(pg)
    pg:SetPoint("TOPLEFT", 0, -36)
    pg:SetPoint("BOTTOMRIGHT", 0, 0)
    pg:Show()
    S.page = pg
    local function none()
        return S.res ~= nil and #S.res.el == 0 and #S.res.opt == 0
    end
    local function has(which)
        return function() return S.res ~= nil and #S.res[which] > 0 end
    end
    AT.Section(pg, "Nothing found", { visibleFn = none })
    AT.RowDesc(pg, "Try part of a name, an ID, or an option's name.", 20, none)
    AT.Section(pg, "Your layouts, groups, icons and bars", { visibleFn = has("el") })
    for i = 1, S.MAX_EL do S.ResultRow(pg, "el", i) end
    S.MoreRow(pg, "el", S.MAX_EL)
    AT.Section(pg, "Options", { visibleFn = has("opt") })
    for i = 1, S.MAX_OPT do S.ResultRow(pg, "opt", i) end
    S.MoreRow(pg, "opt", S.MAX_OPT)
    AT.Section(pg, nil)
end

-- Build and toggle

local built
local function Build()
    if built then return end
    built = true
    -- Set before the first window is created so it opens at the saved scale, and
    -- only when one is saved: a fallback here would override AT.uiScale's default.
    local savedScale = Store.GetSetting("uiScale")
    if savedScale then AT.SetUIScale(savedScale) end
    win = AT.CreateWindow("ArcUIv2Options", {
        w = 1020, h = 760, minW = 820, minH = 620, maxW = 1500, maxH = 1200,
        title = "|cff3fc9f2Arc|r|cffd5e2f2 UI Forever|r",
        -- The toc's Version, so the title matches the release.
        version = C_AddOns and C_AddOns.GetAddOnMetadata
            and C_AddOns.GetAddOnMetadata(ADDON, "Version") or nil,
        onResize = function() RefreshAll() end,
    })
    -- Window open = edit mode (drag and Edit chips); closed = click-through again.
    win:HookScript("OnShow", function() Engine.SetEditMode(true) end)
    win:HookScript("OnHide", function()
        -- before edit mode ends: its rebuild must show the real bar again
        if NS.Bars and NS.Bars.PreviewScreenStop then NS.Bars.PreviewScreenStop() end
        Engine.SetEditMode(false)
        CloseTalentPicker()
    end)

    rail = CreateFrame("Frame", nil, win, "BackdropTemplate")
    rail:SetPoint("TOPLEFT", 1, -31)
    rail:SetPoint("BOTTOMLEFT", 1, 34)
    -- the width the rail splitter saved, else the design width
    rail:SetWidth(math.max(200, math.min(tonumber(Store.GetSetting("railW")) or RAIL_W, 600)))
    AT.Skin(rail, COL.well, COL.line)
    rail:SetClipsChildren(true)

    local search = CreateFrame("EditBox", nil, rail, "BackdropTemplate")
    search:SetPoint("TOPLEFT", 8, -8)
    search:SetPoint("TOPRIGHT", -30, -8)   -- room for the collapse button
    search:SetHeight(20)
    AT.Skin(search, COL.box)
    search:SetFont(STANDARD_TEXT_FONT, 11, "")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY")
    hint:SetFont(STANDARD_TEXT_FONT, 10, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("Search everything...")
    -- Results fill the content area while there is a query; the rail filters on
    -- the same words.
    search:SetScript("OnTextChanged", function(self)
        ui.search = self:GetText() or ""
        hint:SetShown(ui.search == "")
        Options.Search.Changed()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Options.Search.GoFirst()
    end)
    Options.Search.box = search
    AT.Tooltip(search, "Search", "Finds your layouts, groups, icons and bars by name or by spell, item or icon ID, and every option by its name. Click a result to jump straight to it. Enter opens the top result, Esc clears.")

    local cat = rail:CreateFontString(nil, "OVERLAY")
    cat:SetFont(STANDARD_TEXT_FONT, 9, "")
    cat:SetPoint("TOPLEFT", 10, -40)
    cat:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cat:SetText("LAYOUTS")

    -- The layouts tree scrolls from under the caption down to the ADDON foot's
    -- hairline (the foot is 104 tall); RefreshRail fills it, Options.RailFit sizes it.
    local railHost, railList = AT.MakeScroll(rail)
    railHost:SetPoint("TOPLEFT", 0, -58)
    railHost:SetPoint("BOTTOMRIGHT", -6, 105)
    railHost:HookScript("OnSizeChanged", function(_, w)
        if w and w > 0 then railList:SetWidth(w) end
    end)
    Options.railHost, Options.railList = railHost, railList

    content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 12, -4)
    content:SetPoint("BOTTOMRIGHT", -12, 40)
    content:SetClipsChildren(true)   -- long editors clip, never overdraw the footer

    -- Drag to set the rail's width, saved account-wide. It fills the 12px gap with
    -- a hairline and a three-dot grip.
    local railGrip
    railGrip = AT.MakeSplitter(win, "x", {
        onStart = function() railGrip._w0 = rail:GetWidth() or RAIL_W end,
        onDrag = function(d)
            local w = math.floor((railGrip._w0 or RAIL_W) + d + 0.5)
            w = math.max(200, math.min(w, math.floor((win:GetWidth() or 1020) * 0.5)))
            if w ~= railGrip._w then
                railGrip._w = w
                rail:SetWidth(w)
            end
        end,
        onStop = function()
            if railGrip._w then Store.SetSetting("railW", railGrip._w) end
            RefreshAll()
        end,
    })
    railGrip:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    railGrip:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 0, 0)
    AT.Tooltip(railGrip, "Resize", "Drag to make the layouts list wider or narrower.")

    -- The rail folds to a slim strip, saved account-wide. SetPoint with the same
    -- point name moves the content's TOPLEFT and keeps its BOTTOMRIGHT.
    local railStrip = CreateFrame("Button", nil, win, "BackdropTemplate")
    railStrip:SetPoint("TOPLEFT", 1, -31)
    railStrip:SetPoint("BOTTOMLEFT", 1, 34)
    railStrip:SetWidth(18)
    AT.Skin(railStrip, COL.well, COL.line)
    local stripChev = AT.MakeChevron(railStrip)
    stripChev:SetPoint("TOP", 0, -8)
    stripChev:SetDown(false)
    railStrip:SetScript("OnEnter", function(s)
        s:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
    end)
    railStrip:SetScript("OnLeave", function(s)
        s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
    end)
    railStrip:Hide()
    AT.Tooltip(railStrip, "Show sidebar", "Brings the layouts list back.")

    local function ApplyRailCollapsed(on)
        if on then
            rail:Hide()
            railStrip:Show()
            content:SetPoint("TOPLEFT", railStrip, "TOPRIGHT", 12, -4)
        else
            railStrip:Hide()
            rail:Show()
            content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 12, -4)
        end
        -- the splitter belongs to the open rail
        railGrip:SetShown(not on)
    end
    local collapseBtn = AT.MakeSmallButton(rail, "<<", 22)
    collapseBtn:SetHeight(20)
    collapseBtn:SetPoint("TOPRIGHT", -6, -8)
    AT.Tooltip(collapseBtn, "Hide sidebar", "Folds the layouts list away - the editor gets the full window width.")
    collapseBtn:SetScript("OnClick", function()
        Store.SetSetting("railCollapsed", true)
        ApplyRailCollapsed(true)
        RefreshAll()
    end)
    railStrip:SetScript("OnClick", function()
        Store.SetSetting("railCollapsed", false)
        ApplyRailCollapsed(false)
        RefreshAll()
    end)
    ApplyRailCollapsed(Store.GetSetting("railCollapsed") == true)

    -- The ADDON foot: opaque, pinned to the rail's bottom under a hairline; the list
    -- scroll ends at its top edge.
    local foot = CreateFrame("Frame", nil, rail)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(104)
    foot:SetFrameLevel(rail:GetFrameLevel() + 19)
    foot:EnableMouse(true)   -- blocks clicks to anything under it
    local footBg = foot:CreateTexture(nil, "BACKGROUND")
    footBg:SetAllPoints()
    footBg:SetColorTexture(COL.well[1], COL.well[2], COL.well[3], 1)
    local footLine = foot:CreateTexture(nil, "BORDER")
    footLine:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    footLine:SetPoint("TOPLEFT", 0, 0)
    footLine:SetPoint("TOPRIGHT", 0, 0)
    footLine:SetHeight(1)
    local acat = foot:CreateFontString(nil, "OVERLAY")
    acat:SetFont(STANDARD_TEXT_FONT, 9, "")
    acat:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    acat:SetPoint("BOTTOMLEFT", 9, 85)
    acat:SetText("ADDON")
    local function AddonRow(label, paneName, yOff)
        local r = CreateFrame("Button", nil, rail, "BackdropTemplate")
        r:SetHeight(24)
        r:SetPoint("BOTTOMLEFT", 6, yOff)
        r:SetPoint("BOTTOMRIGHT", -6, yOff)
        r:SetFrameLevel(rail:GetFrameLevel() + 20)
        AT.Skin(r, COL.well, COL.well)
        r.name = r:CreateFontString(nil, "OVERLAY")
        r.name:SetFont(STANDARD_TEXT_FONT, 12, "")
        r.name:SetPoint("LEFT", 8, 0)
        r.name:SetText(label)
        RailChrome(r)
        PaintRailRow(r, false, "child")
        r:SetScript("OnClick", function() Options.Select(paneName) end)
        railAddonRows[paneName] = r
        return r
    end
    AddonRow("Import / Export", "ie", 58)
    AddonRow("QOL", "qol", 32)
    AddonRow("Settings", "settings", 6)

    BuildEmptyPane()
    BuildLayoutPane()
    BuildGroupPane()
    BuildFreePane()
    BuildBarPane()
    -- Built last: the layout's look tabs mirror the item editors' blocks.
    Options.BuildLayoutLooks()
    BuildSettingsPane()
    BuildQOLPane()
    BuildIEPane()
    AT.AddDiscordFooter(win, "ArcUIv2DiscordCopy")

    Events.OnMessage("AD_DIRTY", "options", function(_, what)
        -- The search index rebuilds on the next search, never here, so an edit does no
        -- index work.
        Options.Search.idx = nil
        -- Style edits (slider drags) refresh the pane only; other edits rebuild the rail
        -- too.
        if what == "style" then
            Events.Coalesce("ad_opt_refresh", RefreshPane)
        else
            Events.Coalesce("ad_opt_refresh", RefreshAll)
        end
    end)

    local layouts = Store.Layouts()
    if layouts[1] then
        Options.Select("layout", layouts[1].id)
    else
        ShowPane("empty")
    end
end

function Options.Toggle()
    Build()
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
        RefreshAll()
    end
end

function Options.Open()
    Build()
    if not win:IsShown() then win:Show() end
    RefreshAll()
end
