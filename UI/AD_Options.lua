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
-- the New Layout cards draw template groups in the sidebar's kind colours;
-- reminder groups take a magenta nothing else uses
Options.GROUP_COLORS = { cooldown = YELLOW, aura = PURPLE, reminder = { 0.98, 0.40, 0.98 } }
-- The main window's design height: it sets the panel scale, and the talent
-- pickers fit their own scale to it so they draw at the same size.
Options.MAIN_H = 760
local SHR ={ 0.435, 0.659, 0.769 }

local win
local ui = {
    selType = nil,      -- "layout" | "group" | "free" | "bar"
    selId = nil,        -- layout, group or bar id
    selIconId = nil,    -- selected icon inside group/free pane
    selRemId = nil,     -- selected reminder inside a Reminder group's pane
    grpMode = "grp",    -- "grp" | "ico" | "rem"
    layoutTab = "Position",
    grpTab = "Appearance",
    icoTab = "Tracking",
    barTab = "Tracking",
    search = "",
    ieSel = {},         -- export picker: record id -> true (ticked)
    ieOpen = {},        -- export picker: layout id -> true (tree open)
    ieTargetId = nil,   -- import target picked on the Import / Export page
    ieTab = "export",   -- the Import / Export page's open tab
    lastLayoutId = nil, -- the layout the rail last had open
}
-- the panel state, for the files that draw panes of their own
Options.ui = ui

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

-- The record the icon rows read: the multi proxy while Edit together is open
-- on icons (UI\AD_MultiSelect.lua), else the selected icon. SelBar the same.
local function SelIcon()
    local M = Options.MultiSelect
    local px = M and M.Proxy("icon")
    if px then return px end
    return Store.Get(ui.selIconId)
end

local function SelBar()
    if ui.selType == "bar" then return Store.Get(ui.selId) end
    local M = Options.MultiSelect
    return M and M.Proxy("bar") or nil
end

-- The layout engine draws the grow arrows on this group.
function Options.SelectedGroupId()
    if ui.selType == "group" then return ui.selId end
end

-- The item whose editor is open, for the engine's Editing chip: the icon when
-- an icon pane shows, else the group or bar. The selected icon is checked
-- against the pane, since it can linger from another group or layout.
function Options.EditingId()
    if not (win and win:IsShown()) then return nil end
    if ui.selType == "bar" then return ui.selId end
    local ic = SelIcon()
    if ui.selType == "group" then
        if ui.grpMode == "ico" and ic and ic.groupId == ui.selId then return ic.id end
        return ui.selId
    end
    if ui.selType == "free" and ic and not ic.groupId and ic.layoutId == ui.selId then
        return ic.id
    end
end

-- Tabs by what you want to happen: what it tracks, the look that never
-- changes, how it looks and what it does in each state (Conditions: the state
-- table, then each state's glows, sounds and art), then its texts and where
-- it sits. A tab with nothing for the icon drops out (IconTabsFor).
local KIND_TABS = {
    spell   = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    aura    = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    trinket = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    item    = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    -- a Custom Icon: its rules on Triggers (UI\AD_CustomOptions.lua)
    timer   = { "Tracking", "Triggers", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    totem   = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    ammo    = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    enchant = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    special = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    -- a Group Buff: its count and its two states, no glows or sounds
    groupbuff = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    -- a Stance icon: in the stance or not, no swipe, count or sounds
    stance = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
}

-- An aura-group icon, and whether its group packs it (Close gaps on). Packed
-- rows are the game's, which cannot hide or fade one member in combat, so a
-- packed member's Load When and Fade When live on the group.
local function InAuraGroup(rec)
    if not (rec and rec.type == "icon" and rec.groupId) then return false, false end
    local g = Store.Get(rec.groupId)
    if not (g ~= nil and g.groupKind == "aura") then return false, false end
    return true, Store.Resolve(g, "arrangement", "dynamicLayout") == true
end

-- Options.iconTabEmpty(rec, tab), set by the icon editor, drops a tab none of
-- whose blocks apply (none today: every kind has its state table).
local function IconTabsFor(rec)
    -- several icons at once: the tabs every one of them has
    if rec._adMulti and Options.MultiSelect then return Options.MultiSelect.IconTabs(rec) end
    local tabs = KIND_TABS[rec.kind] or KIND_TABS.spell
    local empty = Options.iconTabEmpty
    if not empty then return tabs end
    local out = {}
    for _, t in ipairs(tabs) do
        if not empty(rec, t) then out[#out + 1] = t end
    end
    return out
end
Options._iconTabsFor = IconTabsFor   -- test harness handle

local GREENC = { 0.482, 0.847, 0.561 }

-- The icons' order: Appearance holds every fill colour (the old Color Changes),
-- Conditions the state hides, the glows and the fade rules, and a kind's own tab
-- (Heals & Shields, Castbar) sits right after it. An old pick lands
-- on its new home (Options.EditorTabs.Home, UI\AD_EditorTabs.lua).
local BAR_TABS = {
    cooldown = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    aura     = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    timer    = { "Tracking", "Triggers", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    stack    = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    swing    = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    resource = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    health   = { "Tracking", "Appearance", "Conditions", "Heals & Shields", "Text", "Position", "Load Conditions" },
    cast     = { "Tracking", "Appearance", "Conditions", "Castbar", "Text", "Position", "Load Conditions" },
    enchant  = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    range    = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    -- a Text element: one string, no text runs of its own (Bars\AD_TextElement.lua);
    -- Triggers only with rules of its own (Options.TextTabs); this is every tab it can have
    text     = { "Tracking", "Triggers", "Appearance", "Conditions", "Position", "Load Conditions" },
    -- Triggers only with custom triggers (Options.TextureTabs); this is every tab it can have
    texture  = { "Tracking", "Triggers", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    -- a wheel opens at the cursor: no place, chrome or show rules (Bars\AD_Wheel.lua)
    wheel    = { "Wheel", "Appearance", "Load Conditions" },
    -- an Arc Proc's deck (Bars\AD_SpecialBar.lua, rows in UI\AD_SpecialOptions.lua)
    special  = { "Tracking", "Appearance", "Conditions", "Text", "Position", "Load Conditions" },
    -- a Sound item draws nothing: its rules, and when it loads (Bars\AD_SoundItem.lua)
    sound    = { "Tracking", "Load Conditions" },
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
    local segmented = B.StackSegmented and B.StackSegmented(rec)
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
    if Store.Resolve(rec, "stackcolors", "maxColorEnabled") == true
        and NS.Schema.NewEngineFill(rec) then
        parts[#parts + 1] = "Max stacks color at " .. M
    end
    return table.concat(parts, "  |  ")
end

function Options.DetectMaxStacks(spellID)
    local sid = tonumber(spellID)
    if not sid or sid <= 0 then return nil end
    if not (NS.Bars and NS.Bars.ClientMaxStacks) then return nil end
    return NS.Bars.ClientMaxStacks(sid) -- raw-id: the aura ID typed in the box
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
    p.fs:SetFont(AT.FONT, 8, "")
    p.fs:SetPoint("CENTER", 0, 0)
    function p:Set(text, color)
        self.fs:SetText(text)
        -- the palette's pill style, in the kind colour as the palette shows it
        AT.PaintPill(self, self.fs, AT.Mute(color or COL.dim), 0.7)
        self:SetWidth((self.fs:GetStringWidth() or 20) + 12)
    end
    return p
end

local function GroupPill(pill, groupKind)
    if groupKind == "aura" then pill:Set("Aura Group", PURPLE)
    elseif groupKind == "reminder" then pill:Set("Reminder Group", Options.GROUP_COLORS.reminder)
    else pill:Set("CD Group", YELLOW) end
end

local function BarPillText(barKind, barMode)
    local mode = (barMode == "stack") and "Stack" or "Duration"
    if barKind == "aura" then return "Aura " .. mode, PURPLE end
    if barKind == "timer" then return "Custom Bar", COL.arc end
    if barKind == "stack" then return "Stack Bar", GREENC end
    if barKind == "swing" then return "Swing Bar", { 0.95, 0.62, 0.30 } end
    if barKind == "resource" then return "Resource", { 0.36, 0.62, 1 } end
    if barKind == "health" then return "Health", { 0.35, 0.85, 0.45 } end
    if barKind == "cast" then return "Castbar", { 0.95, 0.47, 0.72 } end
    -- the weapon enchant family's steel, as on its icon pill
    if barKind == "enchant" then return "Enchant Bar", Options.ICON_PILL_COLORS.enchant end
    if barKind == "range" then return "Range Bar", { 0.92, 0.34, 0.34 } end
    if barKind == "text" then return "Text", { 0.93, 0.84, 0.58 } end
    if barKind == "texture" then return "Texture", { 0.66, 0.55, 0.98 } end
    if barKind == "wheel" then return "Wheel", { 0.98, 0.78, 0.2 } end
    if barKind == "sound" then return "Sound", { 0.56, 0.82, 1 } end
    -- the Arc Proc family's amber, as on its icon pill
    if barKind == "special" then return "Arc Proc Bar", Options.ICON_PILL_COLORS.special end
    return "CD " .. mode, YELLOW
end

-- A family keeps its colour across icons, bars and groups (CD yellow, aura
-- purple, timer cyan); the icon-only kinds take hues nothing else uses.
Options.ICON_PILL_COLORS = {
    item    = { 0.36, 0.85, 0.76 },   -- teal
    trinket = { 0.95, 0.50, 0.74 },   -- rose
    totem   = { 0.70, 0.88, 0.36 },   -- lime
    ammo    = { 0.95, 0.52, 0.45 },   -- coral
    enchant = { 0.72, 0.80, 0.92 },   -- steel
    special = { 0.98, 0.72, 0.22 },   -- amber
    groupbuff = { 0.55, 0.80, 1.00 }, -- sky
    stance = { 0.85, 0.60, 0.40 },    -- bronze
}
Options.ICON_PILL_WORDS = { spell = "CD Icon", aura = "Aura Icon", timer = "Custom Icon",
    item = "Item Icon", trinket = "Trinket Icon", totem = "Totem Icon", ammo = "Ammo Icon",
    enchant = "Enchant Icon", special = "Arc Proc Icon", groupbuff = "Group Buff Icon", stance = "Stance Icon" }
function Options.IconPillText(kind)
    local text = Options.ICON_PILL_WORDS[kind]
    if not text then return "Icon", COL.dim end
    if kind == "spell" then return text, YELLOW end
    if kind == "aura" then return text, PURPLE end
    if kind == "timer" then return text, COL.arc end
    return text, Options.ICON_PILL_COLORS[kind]
end

-- Totem slots by element on Forever (NS.DriverTotem.SlotName).
function Options.TotemSlotItems()
    local out = {}
    for i = 1, 4 do
        out[i] = { value = i, text = NS.DriverTotem and NS.DriverTotem.SlotName(i) or ("Slot " .. i) }
    end
    return out
end

function Options.EnchantHandItems()
    return { { value = "main", text = "Main Hand" }, { value = "off", text = "Off Hand" } }
end

-- The slot picker's tooltip: a slot holds whatever the game puts there.
function Options.TotemSlotTip()
    local hint = NS.DriverTotem and NS.DriverTotem.ElementHint and NS.DriverTotem.ElementHint()
    local s = "The totem or guardian slot to watch. The icon lights while anything is in it."
    if hint then s = s .. " A shaman's slots hold: " .. hint .. "." end
    return s
end

-- What is on a weapon enchant icon's (or bar's) weapon now, for its Tracking
-- tab: every enchant, since a weapon can carry two (an imbue and a stone).
function Options.EnchantNowText(r)
    local E = NS.DriverEnchant
    local list = E and E.ReadHand(r.driver and r.driver.hand)
    if list == nil then return "" end
    if #list == 0 then return "Nothing on this weapon now." end
    local parts = {}
    for _, e in ipairs(list) do parts[#parts + 1] = "enchant " .. E.Describe(e) end
    return "On it now: " .. table.concat(parts, ", ") .. "."
end

-- The "Add one on it now" pick: the enchants on the record's weapon now, ID
-- and time left; picking one adds it to the record's enchant IDs.
function Options.EnchantPickItems(r)
    local E = NS.DriverEnchant
    local list = r and E and E.ReadHand(r.driver and r.driver.hand) or {}
    local items = { { value = 0, text = (#list > 0) and "Pick one..." or "Nothing on it now" } }
    for _, e in ipairs(list) do
        if e.id then items[#items + 1] = { value = e.id, text = E.Describe(e) } end
    end
    return items
end

-- A weapon enchant keeps its IDs as an aura icon keeps its spell IDs: the
-- first in enchantID, the list only for two or more. None = any enchant.
function Options.SetEnchantIDs(d, ids)
    d.enchantID = ids[1]
    d.enchantIDs = (#ids > 1) and ids or nil
end

-- A pick joins the IDs already typed instead of replacing them.
function Options.AddEnchantID(d, id)
    local E = NS.DriverEnchant
    if not E then return end
    local ids = E.IDs(d)
    for _, v in ipairs(ids) do
        if v == id then return end
    end
    ids[#ids + 1] = id
    Options.SetEnchantIDs(d, ids)
end

function Options.EnchantIDsText(d)
    local E = NS.DriverEnchant
    return E and table.concat(E.IDs(d), ", ") or ""
end

-- Weapon enchant templates (Forever: NS.DriverEnchant.Templates); the picker
-- is Options.EnchantTemplateGrid.
function Options.HasEnchantTemplates()
    local E = NS.DriverEnchant
    return E ~= nil and E.Templates ~= nil and #E.Templates() > 0
end

-- A template's IDs into a driver, a copy of them; returns the template.
function Options.UseEnchantTemplate(d, key)
    local E = NS.DriverEnchant
    local t = E and E.Template and E.Template(key)
    if not t then return nil end
    local ids = {}
    for i, id in ipairs(t.ids) do ids[i] = id end
    Options.SetEnchantIDs(d, ids)
    return t
end

-- What a template calls an icon or a bar, the off hand said.
function Options.EnchantTemplateName(t, hand)
    return t.name .. ((hand == "off") and " (Off Hand)" or "")
end

-- An enchant record's name still one it was given (a hand's default or a
-- template's): a template may rename it; a name of the player's own stays.
function Options.EnchantNameIsAuto(r)
    local n = r and r.name
    if type(n) ~= "string" or n == "" or n == "Main Hand Enchant" or n == "Off Hand Enchant" then return true end
    for _, t in ipairs(NS.DriverEnchant and NS.DriverEnchant.Templates() or {}) do
        if n == t.name or n == t.name .. " (Off Hand)" then return true end
    end
    return false
end

-- The Tracking tab's template: picked, then Use (pick then act). The pick
-- belongs to one record and resets on another.
function Options.EnchantTemplatePick(r)
    local p = Options.ui.enchTpl
    return (p and r and p.id == r.id and p.key) or ""
end
function Options.SetEnchantTemplatePick(r, key)
    Options.ui.enchTpl = r and { id = r.id, key = key } or nil
end
function Options.ApplyEnchantTemplate(r)
    local key = Options.EnchantTemplatePick(r)
    if not (r and key ~= "") then return false end
    local auto = Options.EnchantNameIsAuto(r)
    local t = Options.UseEnchantTemplate(r.driver, key)
    if not t then return false end
    if auto then Store.Rename(r.id, Options.EnchantTemplateName(t, r.driver.hand)) end
    Options.ui.enchTpl = nil
    Store.Dirty("style", r.id)
    return true
end

-- A template's art: its spell's icon, the class crest for any imbue, the
-- weapon itself for none. Returns the texture and its coords, or nil.
function Options.EnchantTemplateArt(t, hand)
    if t and t.spell then
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(t.spell)
        return tex, { 0.08, 0.92, 0.08, 0.92 }
    end
    if t and t.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[t.class] then
        return "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes", CLASS_ICON_TCOORDS[t.class]
    end
    local E = NS.DriverEnchant
    local inv = E and E.HANDS[hand or "main"] and E.HANDS[hand or "main"].inv or 16
    local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", inv)
    if issecretvalue and issecretvalue(tex) then tex = nil end
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark", { 0.08, 0.92, 0.08, 0.92 }
end

-- The template picker, the Add window's spell grid in small: a cell per
-- template (withNone: "any enchant" first), the pick lit cyan, a tooltip each;
-- a click picks (set), nothing else happens. get() / set(key) hold the pick;
-- hand() the weapon whose art the "any enchant" cell shows.
Options.TPL_CELL, Options.TPL_GAP, Options.TPL_TOP = 32, 4, 14
function Options.EnchantTemplateGrid(pg, vis, get, set, withNone, hand)
    local cell, gap, top = Options.TPL_CELL, Options.TPL_GAP, Options.TPL_TOP
    local row = AT.AddRow(pg, top + cell + gap, vis)
    row._tplGrid = true
    local cap = row:CreateFontString(nil, "OVERLAY")
    cap:SetFont(AT.FONT, 9, "")
    cap:SetPoint("TOPLEFT", 10, -2)
    cap:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cap:SetText("TEMPLATE - click one to fill in every rank's enchant ID")
    row._cells = {}
    local function Cell(i)
        local b = row._cells[i]
        if b then return b end
        b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(cell, cell)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        function b.Edge(hot)
            local c = (b._picked and COL.arc) or (hot and COL.focus) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:AddLine(b._title or "", 1, 1, 1)
            GameTooltip:AddLine(b._body or "", COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            set(b._key)
            if row._sync then row._sync() end
        end)
        row._cells[i] = b
        return b
    end
    row._sync = function()
        local E = NS.DriverEnchant
        local list = {}
        if withNone then list[1] = { key = "", label = "Any enchant", none = true } end
        for _, t in ipairs(E and E.Templates() or {}) do list[#list + 1] = t end
        local cur = get() or ""
        for i, t in ipairs(list) do
            local b = Cell(i)
            local tex, coords = Options.EnchantTemplateArt(t, hand and hand())
            b.tex:SetTexture(tex)
            if coords then b.tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
            b._key, b._picked = t.key, t.key == cur
            b._title = t.label
            b._body = t.none and "Lights for any enchant on the weapon: an imbue, a poison, an oil or a stone."
                or (#t.ids .. " enchant IDs. You can still edit them after.")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8 + (i - 1) * (cell + gap), -top)
            b.Edge(b:IsMouseOver())
            b:Show()
        end
        for i = #list + 1, #row._cells do row._cells[i]:Hide() end
    end
    return row
end

-- What a totem icon tracks, in a few words: its totem, else its slot.
function Options.TotemWhat(d)
    local nm = d.spellID and C_Spell.GetSpellName and C_Spell.GetSpellName(d.spellID) -- raw-id: the typed totem, for the editor's words
    if nm then return nm end
    return "totem slot " .. (d.slot or 1)
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
-- "You, then your target", the Cooldown Manager's rule, as one pick on a unit
-- row: stored as unit = player + unit2 = target. The icon's own buttons run it
-- (a spell's aura, an aura icon outside a Dynamic aura group).
Options.TWO_UNITS = "playertarget"
function Options.TwoUnitsOK(rec)
    local D = NS.DriverAura
    if not (rec and D and D.IsAvailable()) then return false end
    if rec.kind == "spell" then return true end
    if rec.kind ~= "aura" then return false end
    local g = rec.groupId and Store.Get(rec.groupId)
    return not (g and g.groupKind == "aura" and Store.Resolve(g, "arrangement", "dynamicLayout") == true)
end
function Options.UnitPick(d)
    if NS.DriverAura.TwoUnits(d) then return Options.TWO_UNITS end
    return (NS.DriverAura.ShapeOf(d))
end
function Options.SetUnitPick(d, v)
    if v == Options.TWO_UNITS then
        d.unit, d.unit2 = "player", "target"
    else
        d.unit, d.unit2 = v, nil
    end
end
function Options.UnitPickItems(rec, d)
    local items = Options.AuraUnitItems(d, nil, (NS.DriverAura.ShapeOf(d)))
    if Options.TwoUnitsOK(rec) or NS.DriverAura.TwoUnits(d) then
        local at = #items + 1
        for i, it in ipairs(items) do
            if it.value == "player" then at = i + 1 break end
        end
        table.insert(items, at, { value = Options.TWO_UNITS, text = "You, then your target" })
    end
    return items
end
-- The row SectionRows just made for a field: the current section's last match.
function Options.RowFor(pg, section, field)
    local sec = pg and pg._curSection
    local rows = (sec and sec.rows) or (pg and pg._rows) or {}
    for i = #rows, 1, -1 do
        local m = rows[i]._adMeta
        if m and m.section == section and m.field == field then return rows[i] end
    end
    return nil
end
-- A drawn yellow "!" in a ring after a row's control: a limit worth knowing,
-- its why on hover, in place of a note line. Shown while vis() holds.
Options.MARK_YELLOW = { 1, 0.82, 0 }
function Options.InfoMark(row, title, body, vis)
    local ctrl = row and row._colCtrl
    if not ctrl then return nil end
    local Y = Options.MARK_YELLOW
    local m = CreateFrame("Frame", nil, row)
    m:SetSize(16, 16)
    m:SetPoint("LEFT", ctrl, "RIGHT", 8, 0)
    m:EnableMouse(true)
    -- The ring: a yellow disc under one in the page's colour.
    local function Disc(sub, c)
        local t = m:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetColorTexture(c[1], c[2], c[3], 1)
        local mask = m:CreateMaskTexture()
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(t)
        t:AddMaskTexture(mask)
        return t
    end
    local ring = Disc(0, Y)
    ring:SetAllPoints()
    local hole = Disc(1, COL.panel)
    -- never thinner than two device pixels, or it breaks up at some scales
    local function Thick()
        local t = math.max(1.5, 2 * AT.Px(m))
        hole:ClearAllPoints()
        hole:SetPoint("TOPLEFT", t, -t)
        hole:SetPoint("BOTTOMRIGHT", -t, t)
    end
    Thick()
    -- The "!": a stem and a dot, whole units on the 16 grid.
    for _, b in ipairs({ { 3, 6 }, { 11, 2 } }) do
        local t = m:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(Y[1], Y[2], Y[3], 1)
        t:SetPoint("TOPLEFT", 7, -b[1])
        t:SetSize(2, b[2])
    end
    AT.Tooltip(m, title, body)
    local sync = row._sync
    row._sync = function(...)
        if sync then sync(...) end
        Thick()
        m:SetShown(vis == nil or vis() == true)
    end
    row._adInfoMark = m
    return m
end
-- Follow my rank: aura icons, the aura on a spell icon and aura bars (Forever).
Options.FOLLOW_RANK_DESC = "Also watches the rank you know of each spell, so this keeps working when you train "
    .. "a new rank. The IDs you typed still count."
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
-- A name search's pick joins the IDs already there instead of replacing them.
-- True when the list changed.
function Options.AddAuraSpellID(d, id)
    id = tonumber(id)
    if not (type(d) == "table" and id and id > 0) then return false end
    id = math.floor(id)
    local ids = Store.AuraIDList(d)
    for _, v in ipairs(ids) do
        if v == id then return false end
    end
    ids[#ids + 1] = id
    Options.SetAuraSpellIDs(d, ids)
    return true
end
-- An item icon's items, the same shape: itemID first, itemIDs the full list
-- when there are several (it shows the first you carry and can use). Typed
-- items replace a Cooldown Manager category the icon followed.
function Options.SetItemIDs(d, ids)
    d.itemID = ids[1]
    d.itemIDs = (#ids > 1) and ids or nil
    d.category = nil
end
function Options.ItemIDsText(d)
    local t = {}
    if d and d.itemID then t[1] = tostring(d.itemID) end
    for _, v in ipairs(d and type(d.itemIDs) == "table" and d.itemIDs or {}) do
        if v ~= d.itemID then t[#t + 1] = tostring(v) end
    end
    return table.concat(t, ", ")
end
-- A spell icon's other spells (driver.spellAlts): never its own spell, none = no list
function Options.SetSpellAlts(d, ids)
    local out = {}
    for _, v in ipairs(ids) do
        if v ~= d.spellID then out[#out + 1] = v end -- raw-id: stored IDs deduped, not a spell match
    end
    d.spellAlts = (#out > 0) and out or nil
end
function Options.SpellAltsText(d)
    local t = {}
    for _, v in ipairs(d and type(d.spellAlts) == "table" and d.spellAlts or {}) do
        t[#t + 1] = tostring(v)
    end
    return table.concat(t, ", ")
end
-- the rail's words for an item icon: "item 5512" or "items 19013 +14"
function Options.ItemWords(d)
    local n = type(d.itemIDs) == "table" and #d.itemIDs or 1
    if n > 1 then return "items " .. tostring(d.itemID) .. " +" .. (n - 1) end
    return "item " .. tostring(d.itemID)
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
            -- an item's or a trinket's use spell stands in for the spell
            local sid = (NS.DriverPhase and NS.DriverPhase.OwnSpell(rec)) or tonumber(rec.driver.spellID)
            -- the spell's aura and, on ranked realms, your rank of it (the
            -- aura entry's rule); its type from the spell the icon reads
            local ids = sid and Store.TrackedAuraIDs({ spellID = sid }) or {}
            local eff = Store.RecordSpellID(rec.driver)
            local harmful = eff and C_Spell.IsSpellHarmful and C_Spell.IsSpellHarmful(eff)
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

-- What shows over a spell icon's cooldown: nothing, the aura (the engine's),
-- its totem, its totem while down else the aura (overlay.totem, the Cooldown
-- Manager's order) or a set duration on cast (Drivers\AD_DriverPhase.lua). The
-- aura shape stays on the overlay whatever the pick, so switching back keeps it.
Options.OVERLAY_PICKS = {
    { value = "none", text = "Nothing" },
    { value = "aura", text = "An aura" },
    { value = "totem", text = "Its totem" },
    { value = "both", text = "Its totem or an aura" },
    { value = "cast", text = "A set duration" },
}
function Options.OverlayPick(rec)
    local ov = Options.OverlayOf(rec)
    if not (type(ov) == "table" and ov.on == true) then return "none" end
    local src = NS.DriverAura.OverlaySource(ov)
    if src == "aura" and ov.totem == true then return "both" end
    return src
end
function Options.SetOverlayPick(rec, v)
    if not rec then return end
    if v == "none" then
        Options.SetOverlayOn(rec, false)
        return
    end
    Options.SetOverlayOn(rec, true)
    local ov = Options.OverlayOf(rec)
    if ov then
        ov.source = (v == "totem" or v == "cast") and v or nil
        ov.totem = (v == "both") or nil
    end
    Store.Dirty("style", rec.id)
end
-- The spells a totem or a set duration follows (overlay.spells), empty for
-- the icon's own; one for a totem.
function Options.OverlaySpellsText(rec)
    local ov = Options.OverlayOf(rec)
    return (ov and type(ov.spells) == "table") and table.concat(ov.spells, ", ") or ""
end
function Options.SetOverlaySpells(rec, text, one)
    local ov = Options.OverlayOf(rec)
    if not ov then return end
    local ids = Options.ParseSpellIDs(text)
    if one and #ids > 1 then ids = { ids[1] } end
    ov.spells = (#ids > 0) and ids or nil
    Store.Dirty("style", rec.id)
end
function Options.OverlaySpellHint(rec)
    if rec and rec.kind ~= "spell" then
        local sid = NS.DriverPhase and NS.DriverPhase.OwnSpell(rec)
        return sid and ("its use spell, " .. sid) or "its use spell"
    end
    local sid = rec and rec.driver and tonumber(rec.driver.spellID)
    return sid and ("this spell, " .. sid) or "this spell"
end

-- The rail's words for an aura icon's IDs: "aura 2825" or "auras 2825 +3".
function Options.AuraSummary(d)
    local ids = NS.DriverAura and NS.DriverAura.SpellIDList(d) or {}
    if #ids > 1 then return "auras " .. ids[1] .. " +" .. (#ids - 1) end
    return "aura " .. tostring(ids[1] or "?")
end

-- "Glow for" on an aura icon: any of its spells, or one of them with its
-- ranks (DriverAura.GlowSpellGroups, each keyed by its first id).
function Options.AuraGlowForItems(rec)
    local items = { { value = 0, text = "Any of its spells" } }
    local DA = NS.DriverAura
    if not (rec and DA and DA.GlowSpellGroups) then return items end
    for _, g in ipairs(DA.GlowSpellGroups(rec.driver)) do
        items[#items + 1] = { value = g.id,
            text = (g.n > 1) and (g.name .. " (" .. g.n .. " ranks)") or g.name }
    end
    return items
end

-- The stored pick as its choice: another rank of a listed spell shows as that
-- spell, and a spell the icon no longer tracks as Any (the driver agrees).
function Options.AuraGlowForValue(rec, section, field)
    local v = rec and tonumber(Store.Resolve(rec, section, field)) or 0
    local DA = NS.DriverAura
    if v <= 0 or not (DA and DA.GlowSpellGroups) then return 0 end
    for _, g in ipairs(DA.GlowSpellGroups(rec.driver)) do
        if Store.SameAura(g.id, v) then return g.id end
    end
    return 0
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
-- textOnly: the Text element's list, which reads enum powers only (stagger and
-- the aura-held resources have no power events to repaint it)
local function PowerItems(keep, textOnly)
    local items = { { value = POWER_AUTO, text = "Automatic (current power)" } }
    local B = NS.Bars
    local info = B and B.POWER_INFO
    if info then
        -- retail: the powers this character has (Bars\AD_ResourcePowers.lua);
        -- Forever keeps its client-filtered list
        local ids = B.ResPowers and B.ResPowers.Offered and B.ResPowers.Offered()
        if ids and textOnly then
            local enum = {}
            for _, id in ipairs(ids) do
                if not B.ResPowers.Pseudo(id) then enum[#enum + 1] = id end
            end
            ids = enum
        end
        if not ids then
            ids = {}
            for id in pairs(info) do ids[#ids + 1] = id end
            table.sort(ids)
        end
        -- a record's power this character lacks stays listed, so its name shows
        if keep ~= nil and keep >= 0 and NS.IsForever ~= true then
            local listed = false
            for _, id in ipairs(ids) do if id == keep then listed = true end end
            if not listed then ids[#ids + 1] = keep end
        end
        local all = B.POWER_ALL or info
        for _, id in ipairs(ids) do
            local pi = all[id] or info[id]
            items[#items + 1] = { value = id, text = (pi and pi.name) or ("Power " .. id) }
        end
    end
    return items
end

-- the Text element's power picker reads the same list (UI\AD_TextOptions.lua)
Options.PowerItems = PowerItems

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
    c.fs:SetFont(AT.FONT, 9, "")
    c.fs:SetPoint("CENTER")
    function c:Set(text, color)
        self.fs:SetText(text)
        AT.PaintPill(self, self.fs, AT.Mute(color or COL.dim), 0.7)
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
-- section may be a function returning parts ({ section, fields } each) for a
-- sub-panel whose blocks span sections; the counts add up.
function Options.LayoutStatusRow(pg, ctx, section, visibleFn, fieldsFn)
    local function Parts()
        if type(section) == "function" then return section() end
        return { { section = section, fields = fieldsFn() } }
    end
    local function Status()
        local r = ctx()
        if not r then return nil, 0, 0 end
        local lay, setN, ownN = nil, 0, 0
        for _, p in ipairs(Parts()) do
            local l, s, o = Store.LayoutStatus(r, p.section, p.fields)
            lay = lay or l
            setN, ownN = setN + s, ownN + o
        end
        return lay, setN, ownN
    end
    local row = AT.AddRow(pg, 24, function()
        if visibleFn and not visibleFn() then return false end
        local _, setN = Status()
        return setN > 0
    end)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
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
        if not r then return end
        local changed = false
        for _, p in ipairs(Parts()) do
            if Store.ResetToLayout(r, p.section, p.fields) then changed = true end
        end
        if changed then AT.LayoutPage(pg) end
    end)
    AT.Tooltip(btn, "Reset to layout", "Drops this item's own values for the settings here that its layout sets, so they follow the layout again. Settings the layout leaves alone keep this item's values.")
    row._adPush = true
    return row
end

-- Copy and default controls scoped to one sub-panel's rows: two blocks can
-- share a schema section, and a copy must not carry the neighbour's rows.
-- `fields`: a list or a function returning one; nil means
-- blockFields[visibleFn], else the whole section. `section` may be a function
-- returning parts ({ section, fields } each) when a sub-panel's blocks span
-- sections; every action then runs once per part.
local function PushBar(pg, ctx, section, visibleFn, fields)
    local function FieldsNow()
        if type(fields) == "function" then return fields() end
        if fields then return fields end
        return Options.blockFields[visibleFn]
    end
    local function Parts()
        if type(section) == "function" then return section() end
        return { { section = section, fields = FieldsNow() } }
    end
    local function flash(btn, text)
        btn._label = btn._label or btn.fs:GetText()
        btn.fs:SetText(text)
        C_Timer.After(1.2, function() btn.fs:SetText(btn._label) end)
    end
    -- no push bar over several records at once (the multi proxy): a copy or a
    -- default of the first one would not say what the others hold. The bar's
    -- own vis stays the blockFields key.
    local function vis()
        local r = ctx()
        if r and r._adMulti then return false end
        return (not visibleFn) or visibleFn()
    end
    Options.LayoutStatusRow(pg, ctx, Parts, vis)
    -- The pick resets when another record is selected, so a stale target never
    -- gets a copy. w = nil: an auto-width dropdown (up to 300).
    local row = AT.AddRow(pg, 24, vis)
    local lbl = AT.RowLabel(row, "Copy to")
    local sel, selRec = 0, nil
    local function Sel()
        local rec = ctx()
        local id = rec and rec.id
        if id ~= selRec then sel, selRec = 0, id end
        return sel
    end
    local dd = AT.MakeDropdown(win, row, nil,
        function() return Options.PushTargets(ctx()) end,
        Sel,
        function(v) Sel() sel = v end)
    dd:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    row._sync = dd.Refresh
    row._adPush = true
    local copy = AT.MakeSmallButton(row, "Copy", 70)
    copy:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    copy:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        local v = Sel()
        if v == 0 then flash(copy, "Pick one") return end
        -- the most targets any one part reached (they reach the same ones)
        local n = 0
        local ids = (v ~= "all") and Options.PushTargetIds(rec, v) or nil
        for _, p in ipairs(Parts()) do
            local k
            if ids then k = Store.PushTo(rec, p.section, ids, p.fields)
            else k = Store.PushToAll(rec, p.section, p.fields) end
            if (k or 0) > n then n = k end
        end
        flash(copy, "Copied: " .. tostring(n))
    end)
    AT.Tooltip(dd, "Copy to", "Where the rows of this sub-panel go: everything of this type, one layout, one group, one other thing, or every icon of this kind. Nothing happens until you press Copy.")
    AT.Tooltip(copy, "Copy", "Copies the rows of this sub-panel onto the chosen target. Copy semantics - no live link; the target keeps its own values from then on.")
    local row2 = AT.AddRow(pg, 24, vis)
    row2._adPush = true
    local b2 = AT.MakeSmallButton(row2, "Save as Default", 112)
    b2:SetPoint("LEFT", 10, 0)
    local b3 = AT.MakeQuietButton(row2, "Reset", 60)
    b3:SetPoint("LEFT", b2, "RIGHT", 6, 0)
    local b4 = AT.MakeQuietButton(row2, "Forget default", 104)
    b4:SetPoint("LEFT", b3, "RIGHT", 6, 0)
    local function HasDefault()
        local rec = ctx()
        if not rec then return false end
        for _, p in ipairs(Parts()) do
            if Store.HasDefault(rec, p.section, p.fields) == true then return true end
        end
        return false
    end
    row2._sync = function() b4:SetShown(HasDefault()) end
    -- A default change asks whether the items that follow it change too: they
    -- keep their look under the "editor" batch until answered (no answer: Only new).
    local function Ask(rec)
        if Options.Defaults and Options.Defaults.AskPopup then Options.Defaults.AskPopup("editor", rec)
        else Store.AnswerDefaults("editor", false) end
    end
    b2:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        for _, p in ipairs(Parts()) do Store.SaveAsDefault(rec, p.section, p.fields, "editor") end
        flash(b2, "Saved")
        b4:SetShown(HasDefault())
        Ask(rec)
    end)
    b3:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        for _, p in ipairs(Parts()) do Store.ResetSection(rec, p.section, p.fields) end
        flash(b3, "Done")
        AT.LayoutPage(pg)
    end)
    b4:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec = ctx()
        if not rec then return end
        for _, p in ipairs(Parts()) do Store.ForgetDefault(rec, p.section, p.fields, "editor") end
        flash(b4, "Forgotten")
        C_Timer.After(1.2, function() b4:SetShown(HasDefault()) end)
        Ask(rec)
    end)
    AT.Tooltip(b2, "Save as Default", "Makes these rows, as they are now, the default for this kind. It asks whether the items you have change too.")
    AT.Tooltip(b3, "Reset", "Puts the rows of this sub-panel back: to the layout's values where its layout sets them, to the defaults for this thing everywhere else (a saved default still counts).")
    AT.Tooltip(b4, "Forget default", "Drops your saved default for these rows, so they read Arc's again. It asks whether the items you have change too.")
    return row
end

-- Stored by sound name ("" = none), never a file ID.
function Options.SoundRow(pg, owner, label, section, field, ctx, visible, filesOnly)
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
            if NS.Sounds then return NS.Sounds.Items(filesOnly) end
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
        for _, k in ipairs((NS.Bars and NS.Bars.BUILTIN_TEXTURE_ORDER)
            or { "Blizzard", "Blizzard Raid", "Character Skills" }) do add(k) end
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
-- rows as it is built; BuildLayoutLooks mirrors them into the layout editor
-- and the Defaults page (UI\AD_DefaultsOptions.lua) into its kind pages.
-- The same family, tab, title and section again merges the rows. Fields are
-- copied, so later changes to the caller's list do not leak in.
-- sub: the editor's sub-tab (b.sub; nil: a stacked or tab-wide block).
-- extra: fx (an effect the state table draws), state (a state's look the
-- table draws), labels (the block's own words for its rows), its own gates
-- kindOnly / when(rec), and defaultsOnly (a kind's own words for rows another
-- block already gives the layout looks). A merge widens the gates: one
-- registration without any opens the block to every kind (b.open), else any
-- gate passes. Two registrations on different sub-tabs never merge.
Options.LOOK_BLOCKS = Options.LOOK_BLOCKS or {}
Options.blockTab = Options.blockTab or {}   -- a BarBlock's vis -> its tab (BarSub)
function Options.LookBlock(family, tab, title, section, fields, sub, extra)
    if not (family and tab and title and section and fields) then return end
    local list = Options.LOOK_BLOCKS[family] or {}
    Options.LOOK_BLOCKS[family] = list
    local b
    for _, x in ipairs(list) do
        if x.tab == tab and x.title == title and x.section == section
            and (x.sub == nil or sub == nil or x.sub == sub) then
            b = x
            break
        end
    end
    if not b then
        b = { tab = tab, title = title, section = section, fields = {}, sub = sub or nil }
        list[#list + 1] = b
    end
    if b.sub == nil then b.sub = sub or nil end
    for _, fld in ipairs(fields) do b.fields[#b.fields + 1] = fld end
    extra = extra or {}
    if extra.fx then b.fx = true end
    if extra.state then b.state = true end
    if extra.defaultsOnly then b.defaultsOnly = true end
    if extra.labels then
        b.labels = b.labels or {}
        for k, v in pairs(extra.labels) do b.labels[k] = v end
    end
    if extra.kindOnly or extra.when then
        b.gates = b.gates or {}
        b.gates[#b.gates + 1] = { kindOnly = extra.kindOnly, when = extra.when }
    else
        b.open = true
    end
    return b
end

-- def.dep hides a field until the named fields hold the wanted values: one
-- entry `d` of a field's dep, read on `rec`. tier: the layout editor's rows.
function Options.DepOK(rec, family, section, d, tier)
    local fam = Schema[family]
    -- Layout tier: an item-only switch never hides the layout's rows.
    if tier then
        local dsec = fam[d.section or section]
        local ddef = dsec and dsec.fields[d.field]
        if not (ddef and Schema.Inherits(ddef, dsec)) then return true end
    end
    -- The Defaults page: a switch that is part of what an item is (its custom
    -- text's words) lives on each item, so it never hides a default's row.
    if rec._adDefaults then
        local dsec = fam[d.section or section]
        local ddef = dsec and dsec.fields[d.field]
        if ddef and ddef.noDefault then return true end
    end
    -- unlessFree: a free icon has no group scale, so its size rows show.
    if d.unlessFree and not rec.groupId then return true end
    local v = Store.Resolve(rec, d.section or section, d.field)
    if d.nonempty then return v ~= nil and v ~= "" end
    if d.notValue ~= nil then return v ~= d.notValue end
    if d.min ~= nil then return type(v) == "number" and v >= d.min end
    if d.anyOf ~= nil then return v ~= nil and d.anyOf[v] == true end
    -- listMin: a typed tick list holds that many numbers (a colour row per number)
    if d.listMin ~= nil then return #Schema.TickValues(v) >= d.listMin end
    local want = d.value
    if want == nil then want = true end
    if type(want) == "boolean" then return (v == true) == want end
    return v == want
end

-- A schema row's gates on the record, its tab and dep aside: the kind, the
-- class, Forever only, group only and def.showIf. tier: the layout editor's
-- rows, which show exactly what a layout can set, for any kind.
function Options.FieldShows(rec, family, section, def, tier)
    -- several records at once: the row shows only when it shows for every one
    if rec._adMulti and Options.MultiSelect then
        return Options.MultiSelect.FieldShows(rec, family, section, def, tier)
    end
    local sec = Schema[family][section]
    -- The Defaults page (Store.DefaultsProxy): the kind's rows, or on an All
    -- row the rows two kinds or more share; never one a record shapes (group
    -- only, showIf); never what makes an item itself, unless an old saved
    -- default holds one to reset.
    if rec._adDefaults then
        local kinds = rec._adKinds or { rec._adKind }
        local name
        if def.noDefault then
            for f, d in pairs(sec.fields) do if d == def then name = f end end
        end
        local held, n = false, 0
        for _, k in ipairs(kinds) do
            if Schema.Applies(def, sec, k) then
                n = n + 1
                if name and Store.DefaultValue(family, k, section, name) ~= nil then held = true end
            end
        end
        if n < (rec._adKinds and 2 or 1) or (def.noDefault and not held) then return false end
        local co = def.classOnly
        if co and co ~= Store.ClassTag()
            and not (type(co) == "table" and co[Store.ClassTag() or ""]) then return false end
        if def.foreverOnly and NS.IsForever ~= true then return false end
        if def.newAuraEngine and NS.OldAuraEngine then return false end
        if def.appWindow and NS.AuraAppWindow ~= true then return false end
        return true
    end
    if tier then
        if not Schema.Inherits(def, sec) then return false end
    elseif not Schema.Applies(def, sec, Store.KindOf(rec), rec.barMode) then
        return false
    end
    -- classOnly: one class tag, or a set of them
    local co = def.classOnly
    if co and co ~= Store.ClassTag()
        and not (type(co) == "table" and co[Store.ClassTag() or ""]) then return false end
    if def.foreverOnly and NS.IsForever ~= true then return false end
    if def.newAuraEngine and NS.OldAuraEngine then return false end
    if def.appWindow and NS.AuraAppWindow ~= true then return false end
    if def.groupOnly and not rec.groupId and not tier then return false end
    -- a Masque skin draws it on this record (Core\AD_Skins.lua); a look tier
    -- keeps its row, as its icons may wear no skin
    if def.skin and not tier and NS.Skins and NS.Skins.Skinned(rec) then return false end
    -- def.showIf(rec): a record-shaped gate (a layout sets it for all)
    if def.showIf and not tier and not def.showIf(rec) then return false end
    return true
end

-- A kind's first two states in its own words, as its Conditions table names
-- them (ready / on cooldown, active / missing, in stock / out of stock ...).
function Options.StateWords(rec)
    local ET = Options.EditorTabs
    local st = rec and ET and ET.STATES and ET.STATES[rec.kind]
    local function W(e) return e and ((e.labelFn and e.labelFn(rec)) or e.label) end
    -- the ready and cooldown states by key where a kind has them (a charge
    -- spell lists Recharging between them), else its first two
    local a, b
    for _, e in ipairs(st or {}) do
        if e.key == "ready" then a = e elseif e.key == "cooldown" then b = e end
    end
    local one, two = W(a or (st and st[1])), W(b or (st and st[2]))
    return one and one:lower() or "ready", two and two:lower() or "on cooldown"
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
    -- def.pickedBy: its partner's dropdown writes it (def.showPick), no row
    if only then
        for _, k in ipairs(only) do
            if sec.fields[k] and not sec.fields[k].pickedBy then keys[#keys + 1] = k end
        end
    else
        -- Hidden fields get bespoke rows (the bar anchor's group dropdown).
        for k, d in pairs(sec.fields) do
            if not (d.hidden or d.pickedBy) then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            return (sec.fields[a].label or a) < (sec.fields[b].label or b)
        end)
    end
    -- Fine-tuning fields (def.adv) go last, behind a More options fold
    -- (UI\AD_EditorTabs.lua). A call of fine-tuning alone draws them plainly
    -- unless opts.foldAll: its section has other rows.
    local ET, fold, isAdv = Options.EditorTabs, nil, {}
    if ET then
        local plain, adv = {}, {}
        for _, k in ipairs(keys) do
            if sec.fields[k].adv then adv[#adv + 1] = k else plain[#plain + 1] = k end
        end
        if #adv > 0 and (#plain > 0 or (opts and opts.foldAll)) then
            for _, k in ipairs(adv) do
                plain[#plain + 1] = k
                isAdv[k] = true
            end
            keys = plain
        end
    end
    local function DepOK(rec, d) return Options.DepOK(rec, family, section, d, tier) end
    -- opts.dimDep: a card's switch. Its rows stay while it is off; the card
    -- dims them (UI\AD_EditorTabs.lua), so that dep never hides one.
    local dim = opts and opts.dimDep
    local function Gate(rec, d)
        if dim and d.field == dim and (d.section == nil or d.section == section) then return true end
        return DepOK(rec, d)
    end
    for _, field in ipairs(keys) do
        -- a slice boundary while the loader runs the first build
        Options.BuildYield()
        local def = sec.fields[field]
        -- Every gate but the dep: the settings search reads this, so it still
        -- finds a row a dep hides.
        local baseVis = function()
            if not tabVisible() then return false end
            local rec = ctx()
            if not rec then return false end
            return Options.FieldShows(rec, family, section, def, tier)
        end
        local visible = function()
            if not baseVis() then return false end
            local rec = ctx()
            local dep = def.dep
            if dep then
                if dep.field then
                    if not Gate(rec, dep) then return false end
                else
                    for _, d in ipairs(dep) do
                        if not Gate(rec, d) then return false end
                    end
                end
            end
            return true
        end
        -- the first fine-tuning field opens the fold row; each one then shows
        -- only while it is open
        if isAdv[field] then
            if not fold then
                fold = ET.NewFold(pg, family .. "." .. section .. "." .. field, def.adv, ctx)
            end
            visible = fold:Add(baseVis, visible, function(r) return ET.Changed(r, section, field) end)
        end
        -- opts.showWhen: a panel pick the row also waits on (the type picked in
        -- a show-all group's strip). It is not a record gate, so the search
        -- still finds the row; opts.reveal makes that pick before the jump.
        if opts and opts.showWhen then
            local inner = visible
            visible = function() return opts.showWhen() and inner() end
        end
        -- opts.labels: a block's own words for a shared field (a totem's
        -- "Active alpha" is the states section's ready alpha)
        local label = (opts and opts.labels and opts.labels[field]) or def.label or field
        local row
        if def.t == "bool" and def.showPick then
            -- Two exclusive switches as one pick: Always (both off), While the
            -- aura is up (this one), While the aura is missing (its partner).
            -- def.pickWords(rec) words them for a kind and may leave the second out.
            local other = def.showPick
            local function Words(r)
                return (def.pickWords and def.pickWords(r))
                    or { up = "While the aura is up", missing = "While the aura is missing" }
            end
            row = AT.RowDropdown(pg, win, label,
                function()
                    local r = ctx()
                    if not r then return "always" end
                    if Store.Resolve(r, section, field) == true then return "up" end
                    if Store.Resolve(r, section, other) == true then return "missing" end
                    return "always"
                end,
                function(v)
                    local r = ctx()
                    if not r then return end
                    Store.SetOverride(r, section, field, v == "up")
                    Store.SetOverride(r, section, other, v == "missing")
                end,
                function()
                    local w = Words(ctx())
                    local items = { { value = "always", text = "Always" }, { value = "up", text = w.up } }
                    if w.missing then items[#items + 1] = { value = "missing", text = w.missing } end
                    return items
                end,
                visible)
        elseif def.t == "bool" and def.statePick then
            -- Two state switches as one pick, in the kind's own words (its
            -- first two Conditions states): Always (both on), while the
            -- first (this one), while the second (its partner), Never. A
            -- totem set to one totem adds While out of range (def.rangePick),
            -- drawn by its Out of range look, so both switches go off.
            local other, range = def.statePick, def.rangePick
            local function RangeOK(r)
                local rdef = range and sec.fields[range]
                return rdef ~= nil and r ~= nil and not r._adMulti
                    and Schema.Applies(rdef, sec, Store.KindOf(r)) == true
                    and (not rdef.showIf or rdef.showIf(r) == true)
            end
            row = AT.RowDropdown(pg, win, label,
                function()
                    local r = ctx()
                    if not r then return "always" end
                    if RangeOK(r) and Store.Resolve(r, section, range) == true then return "range" end
                    local one = Store.Resolve(r, section, field) ~= false
                    local two = Store.Resolve(r, section, other) ~= false
                    if one and two then return "always" end
                    if one then return "first" end
                    if two then return "second" end
                    return "never"
                end,
                function(v)
                    local r = ctx()
                    if not r then return end
                    Store.SetOverride(r, section, field, v == "always" or v == "first")
                    Store.SetOverride(r, section, other, v == "always" or v == "second")
                    if RangeOK(r) then Store.SetOverride(r, section, range, v == "range") end
                end,
                function()
                    local one, two = Options.StateWords(ctx())
                    local items = { { value = "always", text = "Always" },
                        { value = "first", text = "While " .. one },
                        { value = "second", text = "While " .. two },
                        { value = "never", text = "Never" } }
                    if RangeOK(ctx()) then
                        table.insert(items, 4, { value = "range", text = "While out of range" })
                    end
                    return items
                end,
                visible)
        elseif def.t == "bool" then
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
        elseif def.input and (def.t == "num" or def.t == "int") then
            -- Typed, not slid: a long range (a pulse held for minutes), clamped
            -- to def.min..def.max on the way in.
            row = AT.RowInput(pg, label,
                function()
                    local r = ctx()
                    local v = r and Store.Resolve(r, section, field)
                    if type(v) ~= "number" then v = def.d or 0 end
                    return def.fmt and string.format(def.fmt, v) or tostring(v)
                end,
                function(v)
                    local r, n = ctx(), tonumber(v)
                    if not (r and n) then return end
                    n = math.max(def.min or n, math.min(def.max or n, n))
                    if def.t == "int" then n = math.floor(n + 0.5) end
                    Store.SetOverride(r, section, field, n)
                end,
                visible, def.desc or "Type a number.")
        elseif def.adds then
            -- A count grown with a button, not a slider: the rows each step
            -- reveals sit above this row and read the count in their deps.
            local lo, hi = def.min or 1, def.max or 3
            local function Cur()
                local r = ctx()
                local v = r and Store.Resolve(r, section, field)
                return math.floor((type(v) == "number" and v) or def.d or lo)
            end
            local function Put(n)
                local r = ctx()
                if r then Store.SetOverride(r, section, field, math.max(lo, math.min(hi, n))) end
            end
            local steps = {
                { label = "+ Add " .. def.adds, w = 140,
                    visibleFn = function() return Cur() < hi end,
                    onClick = function() Put(Cur() + 1) end },
                { label = "Remove last " .. def.adds, w = 170, quiet = true,
                    visibleFn = function() return Cur() > lo end,
                    onClick = function() Put(Cur() - 1) end },
            }
            row = AT.RowActions(pg, steps, "left", visible)
            row._adSteps = steps
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
                function(v)
                    local r = ctx()
                    if r then
                        Store.SetOverride(r, section, field, v)
                        if def.onSet then def.onSet(r, v) end
                    end
                end,
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
                    local rv = ctx()
                    -- def.labelsFn: words that follow the record (a crop's Top or Left)
                    local L = (def.labelsFn and rv ~= nil and def.labelsFn(rv)) or def.labels
                    for _, v in ipairs(def.values or {}) do
                        local cond = def.valueIf and def.valueIf[v]
                        if not cond or (rv ~= nil and cond(rv)) then
                            items[#items + 1] = { value = v, text = (L and L[v]) or v }
                        end
                    end
                    return items
                end,
                visible)
        elseif def.t == "id" and def.auraSpellPick then
            -- one of the aura icon's own spells (Options.AuraGlowFor*)
            row = AT.RowDropdown(pg, win, label,
                function() return Options.AuraGlowForValue(ctx(), section, field) end,
                function(v)
                    local r = ctx()
                    if r then Store.SetOverride(r, section, field, tonumber(v) or 0) end
                end,
                function() return Options.AuraGlowForItems(ctx()) end,
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
        elseif def.t == "text" and def.picture and Options.PictureRow then
            -- a texture's picture: the library, or an ID or path of your own
            row = Options.PictureRow(pg, win, label, section, field, ctx, visible)
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
            row = Options.SoundRow(pg, win, label, section, field, ctx, visible, def.files == true)
        elseif def.t == "color" then
            -- def.alpha: the picker offers opacity only where the drawn thing
            -- honours the colour's alpha
            local aOpts = def.alpha == true
                and { alpha = true, alphaDefault = type(def.d) == "table" and def.d[4] or 1 } or nil
            row = AT.RowColor(pg, label,
                function()
                    local r = ctx()
                    local c = r and Store.Resolve(r, section, field) or def.d
                    -- a number always, so a cancel puts the alpha back too
                    if aOpts then return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or aOpts.alphaDefault } end
                    return { c[1] or 0, c[2] or 0, c[3] or 0 }
                end,
                function(c)
                    local r = ctx()
                    if not r then return end
                    -- Without the slider the field keeps its alpha, or a
                    -- translucent default (the 80% swipe) goes opaque.
                    local cur = Store.Resolve(r, section, field)
                    local a = (type(cur) == "table" and cur[4])
                        or (type(def.d) == "table" and def.d[4]) or 1
                    if aOpts and c[4] ~= nil then a = c[4] end
                    Store.SetOverride(r, section, field, { c[1], c[2], c[3], a })
                end,
                visible, aOpts)
        end
        -- Search metadata: the search indexes by baseVis, so a dep-hidden row
        -- (Gradient colors) is still found and the jump flashes its switch.
        if row then
            row._adMeta = { family = family, section = section, field = field,
                def = def, baseVis = baseVis, layoutTier = tier or nil,
                label = opts and opts.searchLabels and opts.labels and opts.labels[field] or nil,
                reveal = opts and opts.reveal or nil }
            -- the search opens the fold before it flashes the row
            if isAdv[field] then row._adFold = fold end
            -- def.labelFn(rec): the row's words for the record shown (nil: the
            -- label), set before the "(mixed)" mark reads them; the search
            -- keeps the schema label
            if def.labelFn and row._colLabel then
                local inner = row._sync
                row._sync = function()
                    if inner then inner() end
                    local r = ctx()
                    local want = (r and def.labelFn(r)) or label
                    if row._adLabelNow ~= want then
                        row._adLabelNow = want
                        row._colLabel:SetText(want)
                        if row._adPlainLabel ~= nil then row._adPlainLabel = want end
                    end
                end
            end
            -- "(mixed)" after the label while several records disagree
            if Options.MultiSelect then
                Options.MultiSelect.MarkRow(row, ctx, section, field, def.showPick or def.statePick)
            end
            -- def.desc: the row's tooltip; a text box shows its own
            local box = (def.t == "text" and not def.media and not def.font)
                or (def.t == "id" and not def.auraSpellPick)
            if def.desc and not box then
                AT.Tooltip(row, label, def.desc)
                if row._colCtrl then AT.Tooltip(row._colCtrl, label, def.desc) end
            end
        end
    end
end
-- for the pages that draw schema rows outside this file (the Defaults page)
Options.SectionRows = SectionRows

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

-- A node's state on what the picker edits, "req", "not" or nil: a record's
-- load talents, or a talent target's one pick (Options.TalentPickRow).
-- With a state, it writes one instead (nil drops the node); a record's pick
-- is tagged with the class the picker shows.
local function TPState(rec, nodeID, write, state)
    if not rec then return nil end
    if write then
        if rec.talentTarget then rec.Set(nodeID, state)
        else Store.SetTalentState(rec, nodeID, state, nil, tpWin and tpWin._adClass) end
        return state
    end
    if rec.talentTarget then return (rec.State(nodeID)) end
    return (Store.TalentState(rec, nodeID))
end

TPPaint = function()
    if not (tpWin and tpWin:IsShown()) then return end
    local rec = TPRecord()
    local red = { 0.95, 0.38, 0.38 }
    local q = tpQuery:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local req, exc = 0, 0
    -- the count is this tree's: the class shown
    local list = rec and (rec.talentTarget and rec.List() or Store.TalentPicksOf(rec, tpWin._adClass)) or {}
    for _, p in ipairs(list) do
        if p.excluded then exc = exc + 1 else req = req + 1 end
    end
    if rec and rec.talentTarget then
        local pick = list[1]
        tpCount:SetText(pick and ((pick.excluded and "Not taken: " or "Picked: ")
                .. (Options.TalentPickName(pick.nodeID) or ""))
            or ("Nothing picked yet - click a talent to pick it"
                .. (rec.noExclude and "." or ", again for Not taken.")))
    elseif req + exc == 0 then
        tpCount:SetText("Nothing required yet - click a talent to require it, again to exclude it.")
    else
        local parts = {}
        if req > 0 then parts[#parts + 1] = req .. " required" end
        if exc > 0 then parts[#parts + 1] = exc .. " excluded" end
        tpCount:SetText(table.concat(parts, ", "))
    end
    for _, node in ipairs(tpNodes) do
        local e = node.entry
        if e and node.btn:IsShown() then
            local state = TPState(rec, e.nodeID)
            local taken = (e.rank or 0) > 0
            local hit = (q == "") or (e.nameLower:find(q, 1, true) ~= nil)
            local rc = (state == "not") and red or COL.arc
            node.ring:SetShown(state ~= nil)
            node.ring:SetBackdropColor(rc[1], rc[2], rc[3], 1)
            node.ring:SetBackdropBorderColor(rc[1], rc[2], rc[3], 1)
            local bc = (state == "req" and COL.arc) or (state == "not" and red)
                or (taken and COL.line2 or COL.line)
            node.ic:SetDesaturated(not taken)
            node.btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
            -- Always opaque, so the tree art never shows through an icon: an
            -- untaken talent is grey, a search miss darkened.
            local v = hit and 1 or 0.3
            node.ic:SetVertexColor(v, v, v)
            node.btn:SetAlpha(1)
            node.ring:SetAlpha(1)
            if node.x1 then
                node.x1:SetShown(state == "not")
                node.x2:SetShown(state == "not")
            end
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
    rule:SetColorTexture(COL.rule[1], COL.rule[2], COL.rule[3], 0.9)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
    local name = bar:CreateFontString(nil, "OVERLAY")
    name:SetFont(AT.FONT, 12, "")
    name:SetPoint("LEFT", 8, 0)
    name:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
    local pts = bar:CreateFontString(nil, "OVERLAY")
    pts:SetFont(AT.FONT, 11, "")
    pts:SetPoint("RIGHT", -8, 0)
    pts:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])

    -- Blizzard's talent art in its true shape: the right and bottom pieces are
    -- partly padding (44 of 64 wide, 75 of 128 tall), so equal quarters left
    -- empty strips. TPLayout sizes the whole to cover the body; the body clips.
    local body = CreateFrame("Frame", nil, box)
    body:SetPoint("TOPLEFT", 1, -(TP_HDR + 1))
    body:SetPoint("BOTTOMRIGHT", -1, 1)
    body:SetClipsChildren(true)
    local art = CreateFrame("Frame", nil, body)
    local bg = {}
    for qi = 1, 4 do
        local t = art:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetVertexColor(0.82, 0.88, 1, 0.34)
        bg[qi] = t
    end
    bg[2]:SetTexCoord(0, 0.6875, 0, 1)
    bg[3]:SetTexCoord(0, 1, 0, 0.5859375)
    bg[4]:SetTexCoord(0, 0.6875, 0, 0.5859375)

    p = { box = box, name = name, pts = pts, body = body, art = art, bg = bg }
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
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
    ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
    local ic = btn:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 2, -2)
    ic:SetPoint("BOTTOMRIGHT", -2, 2)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local rank = btn:CreateFontString(nil, "OVERLAY")
    rank:SetFont(AT.FONT, 10, "OUTLINE")
    rank:SetPoint("BOTTOMRIGHT", -1, 1)
    rank:SetTextColor(0.95, 0.97, 1)
    node = { btn = btn, ring = ring, ic = ic, rank = rank }
    -- the cross of an excluded node, as the retail picker draws it
    if btn.CreateLine then
        local red = { 0.95, 0.38, 0.38 }
        for k, corners in ipairs({ { "TOPLEFT", "BOTTOMRIGHT" }, { "TOPRIGHT", "BOTTOMLEFT" } }) do
            local ln = btn:CreateLine(nil, "OVERLAY")
            ln:SetColorTexture(red[1], red[2], red[3], 0.9)
            ln:SetThickness(2)
            ln:SetStartPoint(corners[1], k == 1 and 4 or -4, -4)
            ln:SetEndPoint(corners[2], k == 1 and -4 or 4, 4)
            ln:Hide()
            node["x" .. k] = ln
        end
    end
    btn:SetScript("OnEnter", function()
        local e = node.entry
        if not e then return end
        btn:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name, 1, 1, 1)
        local rk = e.rank or 0
        if e.maxRanks and e.maxRanks > 1 then
            GameTooltip:AddLine(("Rank %d of %d"):format(rk, e.maxRanks),
                0.7, 0.78, 0.88)
        elseif rk > 0 then
            GameTooltip:AddLine("Taken", 0.48, 0.85, 0.56)
        else
            GameTooltip:AddLine("Not taken", 0.95, 0.62, 0.30)
        end
        -- the game's own talent text, as its talent frame shows it: the rank
        -- you have (the first while untaken), then the next one
        if e.entryID and GameTooltip.AppendInfo then
            GameTooltip:AddLine(" ")
            GameTooltip:AppendInfo("GetTraitEntry", e.entryID, rk > 0 and rk or 1)
            if rk > 0 and e.maxRanks and rk < e.maxRanks then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Next rank:", 1, 1, 1)
                GameTooltip:AppendInfo("GetTraitEntry", e.entryID, rk + 1)
            end
        elseif e.spellID and C_Spell.GetSpellDescription then
            local d = C_Spell.GetSpellDescription(e.spellID) -- raw-id: a talent entry
            if d ~= nil and not (issecretvalue and issecretvalue(d)) and d ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(d, 1, 0.82, 0, true)
            end
        end
        GameTooltip:AddLine(" ")
        local rec = TPRecord()
        local state = TPState(rec, e.nodeID)
        local one = rec ~= nil and rec.talentTarget == true
        local red = { 0.95, 0.38, 0.38 }
        if state == "req" then
            GameTooltip:AddLine(not one and "Required: click to exclude it instead."
                or (rec.noExclude and "Picked: click to drop it." or "Taken: click for Not taken instead."),
                COL.arc[1], COL.arc[2], COL.arc[3])
        elseif state == "not" then
            GameTooltip:AddLine(one and "Not taken: click to drop it."
                or "Excluded: this never loads while you have it. Click to drop the condition.",
                red[1], red[2], red[3], true)
        else
            GameTooltip:AddLine(one and "Click to pick this talent." or "Click to require this talent.",
                COL.arc[1], COL.arc[2], COL.arc[3])
        end
        GameTooltip:AddLine("Right-click clears it.", 0.55, 0.65, 0.78)
        GameTooltip:AddLine("Node " .. e.nodeID, 0.4, 0.47, 0.57)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        TPPaint()      -- puts the state border back
    end)
    -- left click cycles required, excluded, off; a right click clears
    btn:SetScript("OnClick", function(_, button)
        local rec, e = TPRecord(), node.entry
        if not (rec and e) then return end
        local cur = TPState(rec, e.nodeID)
        local nxt
        if button ~= "RightButton" then
            if cur == nil then nxt = "req" elseif cur == "req" and not rec.noExclude then nxt = "not" end
        end
        TPState(rec, e.nodeID, true, nxt)
        TPPaint()
        RefreshAll()
    end)
    tpNodes[i] = node
    return node
end

TPLayout = function()
    if not tpWin then return end
    local cat = NS.TalentCatalog
    -- the class the picker was opened on: your own live tree or the game's
    -- view of another; the note names it on a line of its own under the
    -- search row, and the canvas moves down for it
    local src = Options.TalentPickSource(TPRecord(), tpWin._adClass)
    local note = tpWin._adNote
    note:SetText(src.note or "")
    note:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    note:SetShown(src.note ~= nil)
    tpCanvas:SetPoint("TOPLEFT", 0, src.note and -44 or -28)
    tpEmpty:SetText(src.empty or "No talent tree on this character yet.")
    local list, groups, bounds
    if src.view then
        list, groups, bounds = src.view.entries, src.view.groups, src.view.bounds
    elseif cat and not src.empty then
        list, groups, bounds = cat.Layout()
    end
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

    -- Each tree gets an equal column, and one scale serves all three so the
    -- rows line up. The data spaces the trees further apart than they are
    -- wide, so placing the panels by the data's X left wide empty gaps.
    local shown = {}
    for _, g in ipairs(groups) do
        if g.minX and g.maxX then shown[#shown + 1] = g end
    end
    -- no tree groups: the whole tree in one column
    if #shown == 0 then shown[1] = { minX = bounds.minX, maxX = bounds.maxX, name = "", spent = 0 } end
    local n = #shown
    local panelW = math.floor((cw - TP_PAD * (n - 1)) / n)
    local bodyW, bodyH = panelW - 2, ch - TP_HDR - 2
    local spanY = (bounds.maxY - bounds.minY) / 10
    local s = (bodyH - TP_PAD * 2) / (spanY + TP_ICON)
    for _, g in ipairs(shown) do
        s = math.min(s, (bodyW - TP_PAD * 2) / ((g.maxX - g.minX) / 10 + TP_ICON))
    end
    if s > 1.6 then s = 1.6 elseif s < 0.3 then s = 0.3 end
    local size = math.max(14, math.floor(TP_ICON * s + 0.5))
    -- one Y origin for every tree, the tallest centred in the body
    local offY = TP_HDR + 1 + math.max(0, math.floor((bodyH - (spanY * s + size)) / 2))
    -- the art covers the body at its own shape, top aligned; the body clips
    local k = math.max(bodyW / 300, bodyH / 331)
    local aw, ah = math.floor(300 * k + 0.5), math.floor(331 * k + 0.5)
    local cutX, cutY = math.floor(256 * k + 0.5), math.floor(256 * k + 0.5)

    local cols = {}
    for i, g in ipairs(shown) do
        local p = TPPanel(i)
        local l = (i - 1) * (panelW + TP_PAD)
        p.box:ClearAllPoints()
        p.box:SetPoint("TOPLEFT", tpCanvas, "TOPLEFT", l, 0)
        p.box:SetSize(panelW, ch)
        p.name:SetText(string.upper(g.name or ""))
        p.pts:SetText((g.spent or 0) > 0 and ((g.spent) .. " points") or "")
        p.art:ClearAllPoints()
        p.art:SetPoint("TOP", p.body, "TOP", 0, 0)
        p.art:SetSize(aw, ah)
        local sizes = { { cutX, cutY, 0, 0 }, { aw - cutX, cutY, cutX, 0 },
            { cutX, ah - cutY, 0, cutY }, { aw - cutX, ah - cutY, cutX, cutY } }
        local base = g.background and ("Interface\\TalentFrame\\" .. g.background .. "-")
        for qi, quad in ipairs(TP_QUADS) do
            local t, d = p.bg[qi], sizes[qi]
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", p.art, "TOPLEFT", d[3], -d[4])
            t:SetSize(d[1], d[2])
            if base then
                t:SetTexture(base .. quad)
                t:Show()
            else
                t:Hide()
            end
        end
        p.box:Show()
        local spanX = (g.maxX - g.minX) / 10
        cols[#cols + 1] = { g = g, x = l + math.floor((panelW - (spanX * s + size)) / 2) }
    end
    for i = #shown + 1, #tpPanels do tpPanels[i].box:Hide() end

    local byID = {}
    for i, e in ipairs(list) do
        local node = TPNode(i)
        node.entry = e
        -- its tree's column; a node without one joins the nearest tree
        local col, best
        for _, c in ipairs(cols) do
            if c.g.groupID == e.groupID then col = c break end
            local d = math.max(c.g.minX - e.posX, e.posX - c.g.maxX, 0)
            if not best or d < best then best, col = d, c end
        end
        node.btn:SetSize(size, size)
        node.btn:ClearAllPoints()
        if col then
            node.btn:SetPoint("CENTER", tpCanvas, "TOPLEFT",
                math.floor(col.x + size / 2 + (e.posX - col.g.minX) / 10 * s + 0.5),
                -math.floor(offY + size / 2 + (e.posY - bounds.minY) / 10 * s + 0.5))
        end
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
        scaleH = Options.MAIN_H,
        title = AT.Brand("Arc", " Talents"),
        onResize = function() TPLayout() end,
    })

    local body = CreateFrame("Frame", nil, tpWin)
    body:SetPoint("TOPLEFT", 8, -38)
    body:SetPoint("BOTTOMRIGHT", -8, 8)

    tpSearch = CreateFrame("EditBox", nil, body, "BackdropTemplate")
    tpSearch:SetSize(220, 20)
    tpSearch:SetPoint("TOPLEFT", 0, 0)
    AT.Skin(tpSearch, COL.well)
    tpSearch:SetFont(AT.FONT, 11, "")
    tpSearch:SetTextInsets(6, 6, 0, 0)
    tpSearch:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    tpSearch:SetAutoFocus(false)
    local hint = tpSearch:CreateFontString(nil, "OVERLAY")
    hint:SetFont(AT.FONT, 11, "")
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
    tpCount:SetFont(AT.FONT, 11, "")
    tpCount:SetPoint("LEFT", tpSearch, "RIGHT", 12, 0)
    tpCount:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])

    -- whose talents show, on a line of its own so it never meets the row above
    local note = body:CreateFontString(nil, "OVERLAY")
    note:SetFont(AT.FONT, 11, "")
    note:SetPoint("TOPLEFT", 2, -26)
    note:SetPoint("TOPRIGHT", -2, -26)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(false)
    note:Hide()
    tpWin._adNote = note

    local clear = AT.MakeSmallButton(body, "Clear all", 80)
    clear:SetPoint("TOPRIGHT", 0, 0)
    clear:SetHeight(20)
    clear:SetScript("OnClick", function()
        local rec = TPRecord()
        if not rec then return end
        if rec.talentTarget then rec.Clear() else Store.ClearTalentsOf(rec, tpWin._adClass) end
        TPPaint()
        RefreshAll()
    end)
    AT.Tooltip(clear, "Clear all", "Drops every talent picked in this tree. Other classes' picks stay.")

    local done = AT.MakeSmallButton(body, "Done", 70)
    done:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    done:SetHeight(20)
    done.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    done:SetScript("OnClick", function() tpWin:Hide() end)

    -- no box of its own: the three tree panels are the boxes, edge to edge
    tpCanvas = CreateFrame("Frame", nil, body)
    tpCanvas:SetPoint("TOPLEFT", 0, -28)
    tpCanvas:SetPoint("BOTTOMRIGHT", 0, 0)
    tpCanvas:SetClipsChildren(true)

    -- connector lines live between the tree panels and the nodes
    tpLineHost = CreateFrame("Frame", nil, tpCanvas)
    tpLineHost:SetAllPoints()
    tpLineHost:SetFrameLevel(tpCanvas:GetFrameLevel() + 4)

    tpEmpty = tpCanvas:CreateFontString(nil, "OVERLAY")
    tpEmpty:SetFont(AT.FONT, 12, "")
    tpEmpty:SetPoint("CENTER", 0, 0)
    tpEmpty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    tpEmpty:SetText("No talent tree on this character yet.")
    tpEmpty:Hide()

    tpWin:HookScript("OnShow", function() TPLayout() end)
end

-- classTag: the class whose talents to pick (a class row's button); nil is
-- your own. A talent target always picks on your own live tree, untagged.
local function OpenTalentPicker(ctxFn, classTag, specID)
    -- retail's picker (class, hero and spec panels) lives in its own file
    if NS.IsForever ~= true and Options.OpenRetailTalentPicker then
        Options.OpenRetailTalentPicker(ctxFn, classTag, specID)
        return
    end
    TPBuild()
    tpCtx = ctxFn
    local rec = ctxFn and ctxFn()
    tpWin._adClass = (rec and not rec.talentTarget) and (classTag or Store.ClassTag()) or nil
    tpQuery = ""
    tpSearch:SetText("")
    if NS.TalentCatalog then NS.TalentCatalog.Rescan() end
    tpWin:Show()
    TPLayout()
end

-- The picker edits one record, so it closes with the panel that chose it.
local function CloseTalentPicker()
    if tpWin and tpWin:IsShown() then tpWin:Hide() end
    if Options.CloseRetailTalentPicker then Options.CloseRetailTalentPicker() end
end

-- A picked talent in words: the option's name on a choice node, else the
-- node's (its options together), or its number when this tree lacks it.
function Options.TalentPickName(nodeID, entryID)
    if not nodeID then return nil end
    local T = NS.TalentCatalog
    local e = T and T.Known and T.Known(nodeID)
    if type(e) ~= "table" then return "Talent " .. nodeID end
    if type(e.entries) == "table" then
        local names = {}
        for _, opt in ipairs(e.entries) do
            if entryID and opt.entryID == entryID then return tostring(opt.name) end
            names[#names + 1] = tostring(opt.name)
        end
        return table.concat(names, " / ")
    end
    return e.name and tostring(e.name) or ("Talent " .. nodeID)
end

-- The class matrix row of a class tag, or nil.
function Options.TalentClassRow(tag)
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        if cls.tag == tag then return cls end
    end
    return nil
end

-- Retail: the spec a class's talents open on, the record's one checked spec
-- of that class, else your current spec when it is your class, else the
-- class's first. nil where the class has no specs (Forever).
function Options.TalentDefaultSpec(rec, tag)
    local cls = Options.TalentClassRow(tag)
    if not (cls and #cls.specs > 0) then return nil end
    local one, n = nil, 0
    if rec and rec.c then
        for _, s in ipairs(cls.specs) do
            if Store.SpecConditionState(rec, tag, s.id) then one, n = s.id, n + 1 end
        end
    end
    if n == 1 then return one end
    if tag == Store.ClassTag() then
        local cur = Store.CurSpecID()
        for _, s in ipairs(cls.specs) do
            if s.id == cur then return cur end
        end
    end
    return cls.specs[1].id
end

-- Which tree a talent picker opened on a class shows: your own class (on
-- retail, your current spec) is the live tree; any other class or spec is
-- the game's view of it, where nothing is taken. A talent target always
-- uses your live tree. Returns { view, other (a class not yours), classTag,
-- specID, note (the header's one line naming the tree), empty (the text when
-- the view yields nothing) }; view nil = the live tree.
function Options.TalentPickSource(rec, classTag, specID)
    local out = {}
    local T = NS.TalentCatalog
    if not (rec and rec.c) or rec.talentTarget then return out end
    local own = Store.ClassTag()
    local tag = classTag or own
    if not tag then return out end
    local cls = Options.TalentClassRow(tag)
    local name = (cls and cls.name) or tag
    local sp
    if cls and #cls.specs > 0 then
        local want = specID or Options.TalentDefaultSpec(rec, tag)
        for _, s in ipairs(cls.specs) do
            if s.id == want then sp = s end
        end
        sp = sp or cls.specs[1]
    end
    out.classTag, out.specID = tag, sp and sp.id
    out.note = (sp and (sp.name .. " ") or "") .. name .. " talents"
    if tag ~= own then out.other = tag end
    if tag == own and (not sp or sp.id == Store.CurSpecID()) then return out end
    out.view = T and T.View and T.View(tag, sp and sp.id) or nil
    if not out.view then
        if tag == own then
            out.empty = "Can't show " .. sp.name .. " talents here. Switch to " .. sp.name .. " to pick its talents."
        else
            local a = name:find("^[AEIOU]") and "an " or "a "
            out.empty = "Can't show " .. name .. " talents here. Log in on " .. a .. name .. " to pick its talents."
        end
    end
    return out
end

-- "Fury Warrior" / "Warrior" for a pick's tags.
function Options.TalentClassLabel(tag, specID)
    local cls = Options.TalentClassRow(tag)
    local name = (cls and cls.name) or tostring(tag)
    if not specID then return name end
    for _, s in ipairs((cls and cls.specs) or {}) do
        if s.id == specID then return s.name .. " " .. name end
    end
    local sn = GetSpecializationInfoForSpecID and select(2, GetSpecializationInfoForSpecID(specID))
    return (type(sn) == "string" and sn ~= "") and (sn .. " " .. name) or name
end

-- The picks in one line, per class: "Warrior 2 required, Mage 1 excluded".
-- Picks made before tags lead as "Every class" (they count on every class),
-- or alone with no class at all. "" when nothing is picked.
function Options.TalentSummary(rec)
    local by, tagged = {}, false
    for _, e in ipairs(rec and Store.TalentList(rec) or {}) do
        local k = e.class or ""
        if k ~= "" then tagged = true end
        local g = by[k]
        if not g then
            g = { req = 0, exc = 0 }
            by[k] = g
        end
        if e.excluded then g.exc = g.exc + 1 else g.req = g.req + 1 end
    end
    local parts = {}
    local function add(k, label)
        local g = by[k]
        if not g then return end
        local p = {}
        if g.req > 0 then p[#p + 1] = g.req .. " required" end
        if g.exc > 0 then p[#p + 1] = g.exc .. " excluded" end
        parts[#parts + 1] = (label and (label .. " ") or "") .. table.concat(p, " + ")
        by[k] = nil
    end
    add("", tagged and "Every class" or nil)
    for _, cls in ipairs(Store.ClassSpecMatrix()) do add(cls.tag, cls.name) end
    local rest = {}
    for k in pairs(by) do rest[#rest + 1] = k end
    table.sort(rest)
    for _, k in ipairs(rest) do add(k, k) end
    return table.concat(parts, ", ")
end

-- A class's Talents button on Load Conditions: it opens that class's talents
-- and reads "Talents (n)" in the accent colour once the class has picks.
-- Its width holds the longest label, so a row can lay out around it.
-- SetCount(n) from the row's _sync.
function Options.TalentClassButton(parent, ctx, tag, name)
    local b = AT.MakeSmallButton(parent, "Talents (99)", 60)
    b:SetHeight(18)
    b.fs:SetFont(AT.FONT, 10, "")
    b.fs:SetText("Talents (99)")
    b:SetWidth(math.max(60, math.ceil(b.fs:GetStringWidth() or 0) + 10))
    b._adTalentClass = tag
    function b.SetCount(n)
        n = n or 0
        b.fs:SetText(n > 0 and ("Talents (" .. n .. ")") or "Talents")
        local c = n > 0 and COL.arc or COL.ink
        b.fs:SetTextColor(c[1], c[2], c[3])
    end
    b.SetCount(0)
    b:SetScript("OnClick", function() OpenTalentPicker(ctx, tag) end)
    local a = name:find("^[AEIOU]") and "an " or "a "
    AT.Tooltip(b, "Choose " .. name .. " talents",
        "Click a talent to require it, again to exclude it, again to drop it. Picks count only on "
        .. a .. name .. (NS.IsForever == true and "." or "; spec and hero ones in their spec."))
    return b
end

-- How many picks each class's button shows: a pick's tag, else the class
-- whose tree holds it.
function Options.TalentClassCounts(rec)
    local out = {}
    for _, e in ipairs(rec and Store.TalentList(rec) or {}) do
        if e.owner then out[e.owner] = (out[e.owner] or 0) + 1 end
    end
    return out
end

-- One talent picked on the Load Conditions talent tree for a setting of its
-- own (a rule's guard, a look's talent). target() builds, for the record
-- being edited, { talentTarget = true, State(node) -> state, entry;
-- Set(node, state, entry); List() -> { { nodeID, excluded } }; Clear();
-- noExclude = true when it has no Not taken }. A press pins that record.
function Options.TalentPickRow(pg, label, target, visibleFn, tip)
    local row = AT.RowButton(pg, "Choose talent", function()
        local t = target()
        if t then OpenTalentPicker(function() return t end) end
    end, visibleFn, 120, label)
    row._adTalentTarget = target
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("LEFT", row.button, "RIGHT", 10, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    row._adPickText = fs
    row._sync = function()
        local t = target()
        local pick = t and t.List()[1]
        if not pick then
            fs:SetText("Nothing picked")
            fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            return
        end
        local _, entry = t.State(pick.nodeID)
        local name = Options.TalentPickName(pick.nodeID, entry) or ""
        fs:SetText(pick.excluded and ("Not taken: " .. name) or name)
        local c = pick.excluded and { 0.95, 0.38, 0.38 } or COL.ink
        fs:SetTextColor(c[1], c[2], c[3])
    end
    if tip then AT.Tooltip(row.button, "Choose talent", tip) end
    return row
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
        Options.BuildYield()
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
        row._adCondGrid = cat.id
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
        hdr:SetFont(AT.FONT, 10, "")
        hdr:SetPoint("TOPLEFT", 6, -2)
        hdr:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        hdr:SetText(cat.text)
        -- the checkboxes come with the row's first showing, not with the
        -- window: sixteen grids of them sit on tabs most opens never visit
        local cells
        local function BuildCells()
            cells = {}
            for _, d in ipairs(defs) do
                local cell = CreateFrame("Frame", nil, row)
                cell:SetHeight(COND_CELL_H)
                local cb = AT.MakeCheckbox(cell)
                cb:SetPoint("LEFT", 0, 0)
                local fs = cell:CreateFontString(nil, "OVERLAY")
                fs:SetFont(AT.FONT, 11, "")
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
        end
        -- measured placement; returns true when the row's height changed
        local function place()
            local r = ctx()
            if not r then return false end
            if not cells then
                if not row._visibleFn() then return false end
                BuildCells()
            end
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
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -4)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local clear = AT.MakeSmallButton(row, "Clear", 56)
    clear:SetPoint("TOPRIGHT", -8, -2)
    clear:SetHeight(18)
    clear.fs:SetFont(AT.FONT, 10, "")
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

    AT.Section(pg, anySpecs and "Class and Spec" or "Classes",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    AT.RowDesc(pg, "Every box checked = shows everywhere.", 18, tabVisible)
    -- Shortcuts: check all (loads everywhere) or clear all to pick a few.
    local btnRow = AT.AddRow(pg, 24, tabVisible)
    local allB = AT.MakeSmallButton(btnRow, "Check all", 76)
    allB:SetPoint("LEFT", 4, 0)
    allB:SetHeight(18)
    allB.fs:SetFont(AT.FONT, 10, "")
    local noneB = AT.MakeSmallButton(btnRow, "Uncheck all", 86)
    noneB:SetPoint("LEFT", allB, "RIGHT", 6, 0)
    noneB:SetHeight(18)
    noneB.fs:SetFont(AT.FONT, 10, "")
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
        -- Each row reads box, name, Talents button, then the spec columns, laid
        -- out from measured widths so nothing clips or overlaps and the columns
        -- line up across rows. Too narrow for that on one line (Druid's four
        -- specs at the window's minimum width), every class row takes two:
        -- name and button above, the specs below.
        local lines, lastKey = {}, nil
        local function At(f, row, x, line)
            f:ClearAllPoints()
            f:SetPoint("LEFT", row, "TOPLEFT", x, -11 - (line - 1) * 22)
        end
        local function PlaceClassRows()
            if #lines == 0 then return false end
            local w = lines[1].row:GetWidth() or 0
            if w < 90 then w = (pg:GetWidth() or 0) - 24 end
            if w < 90 then w = 10000 end
            local key = math.floor(w) .. "|" .. #lines .. "|" .. tostring(AT.FONT)
            if key == lastKey then return false end
            local nameW, specW = 0, 0
            for _, l in ipairs(lines) do
                nameW = math.max(nameW, math.ceil(l.fs:GetStringWidth() or 0))
                for _, c in ipairs(l.cells) do
                    specW = math.max(specW, math.ceil(c.fs:GetStringWidth() or 0))
                end
            end
            -- a font that has not measured yet places now and measures again
            lastKey = (nameW > 0 and specW > 0) and key or nil
            local btnX = 28 + nameW + 6
            local x0 = btnX + lines[1].tb:GetWidth() + 8
            local step = math.max(104, 30 + specW)
            local need = 0
            for _, l in ipairs(lines) do
                local n = #l.cells
                if n > 0 then
                    local last = math.ceil(l.cells[n].fs:GetStringWidth() or 0)
                    need = math.max(need, x0 + (n - 1) * step + 22 + last)
                end
            end
            local narrow = need > w - 4
            local h = narrow and 44 or 22
            local changed = false
            for _, l in ipairs(lines) do
                At(l.tb, l.row, btnX, 1)
                for i, c in ipairs(l.cells) do
                    if narrow then At(c.cb, l.row, 28 + (i - 1) * step, 2)
                    else At(c.cb, l.row, x0 + (i - 1) * step, 1) end
                end
                if l.row._h ~= h then
                    l.row._h = h
                    l.row:SetHeight(h)
                    changed = true
                end
            end
            return changed
        end
        for _, cls in ipairs(matrix) do
            Options.BuildYield()
            local row = AT.AddRow(pg, 22, tabVisible)
            local cb = AT.MakeCheckbox(row)
            cb:SetPoint("LEFT", row, "TOPLEFT", 4, -11)
            local fs = row:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, 10, "")
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
            local tb = Options.TalentClassButton(row, ctx, cls.tag, cls.name)
            row._spec = {}
            lines[#lines + 1] = { row = row, fs = fs, tb = tb, cells = row._spec }
            for si, sp in ipairs(cls.specs) do
                local cell = { cb = AT.MakeCheckbox(row) }
                cell.fs = row:CreateFontString(nil, "OVERLAY")
                cell.fs:SetFont(AT.FONT, 10, "")
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
                row._spec[si] = cell
            end
            row._sync = function()
                PlaceClassRows()
                local r = ctx()
                if not r then return end
                local any = Store.ClassConditionState(r, cls.tag)
                cb:SetOn(any)
                for si, sp in ipairs(cls.specs) do
                    row._spec[si].cb:SetOn(Store.SpecConditionState(r, cls.tag, sp.id))
                end
                tb.SetCount(Options.TalentClassCounts(r)[cls.tag])
            end
            -- a pane resize can change one line into two, and with it the height
            row:SetScript("OnSizeChanged", function()
                if row._adPlacing then return end
                row._adPlacing = true
                if PlaceClassRows() then AT.LayoutPage(pg) end
                row._adPlacing = nil
            end)
        end
    else
        -- No specs (WoW Forever): one row per class would be a tall, mostly empty
        -- stack, so the class toggles go in one grid that follows the panel
        -- width: three columns while a cell holds the box, the longest name and
        -- the Talents button whole, else two.
        local row = AT.AddRow(pg, 22, tabVisible)
        local cells = {}
        for _, cls in ipairs(matrix) do
            local cell = CreateFrame("Frame", nil, row)
            cell:SetHeight(22)
            local cb = AT.MakeCheckbox(cell)
            cb:SetPoint("LEFT", 0, 0)
            local fs = cell:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, 11, "")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetText(cls.name)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls.tag]
            if cc then fs:SetTextColor(cc.r, cc.g, cc.b)
            else fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]) end
            -- placed by place(): after the longest name, so the buttons line up
            local tb = Options.TalentClassButton(cell, ctx, cls.tag, cls.name)
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
            cells[#cells + 1] = { f = cell, cb = cb, tag = cls.tag, tb = tb, fs = fs }
        end
        -- OnSizeChanged catches the first real width; placing only from _sync
        -- would leave the cells at the left edge until the next layout pass.
        local lastKey
        local function place()
            if #cells == 0 then return false end
            local w = row:GetWidth() or 0
            if w < 90 then w = (pg:GetWidth() or 0) - 24 end
            if w < 90 then w = 10000 end
            local nameW = 0
            for _, c in ipairs(cells) do
                nameW = math.max(nameW, math.ceil(c.fs:GetStringWidth() or 0))
            end
            local btnX = 18 + 6 + nameW + 6
            local ncol = (math.floor(w / 3) - 8 >= btnX + cells[1].tb:GetWidth()) and 3 or 2
            local key = math.floor(w) .. "|" .. ncol .. "|" .. btnX
            if key == lastKey then return false end
            -- a font that has not measured yet places now and measures again
            lastKey = nameW > 0 and key or nil
            local cw = math.floor(w / ncol)
            for i, c in ipairs(cells) do
                c.f:ClearAllPoints()
                c.f:SetPoint("TOPLEFT", row, "TOPLEFT", ((i - 1) % ncol) * cw + 4,
                    -math.floor((i - 1) / ncol) * 22)
                c.f:SetWidth(cw - 8)
                c.tb:ClearAllPoints()
                c.tb:SetPoint("LEFT", c.f, "LEFT", btnX, 0)
            end
            local want = math.ceil(#cells / ncol) * 22
            if row._h == want then return false end
            row._h = want
            row:SetHeight(want)
            return true
        end
        row:SetScript("OnSizeChanged", function()
            if row._adPlacing then return end
            row._adPlacing = true
            if place() then AT.LayoutPage(pg) end
            row._adPlacing = nil
        end)
        row._sync = function()
            place()
            local rr = ctx()
            if not rr then return end
            local counts = Options.TalentClassCounts(rr)
            for _, cell in ipairs(cells) do
                cell.cb:SetOn(Store.ClassConditionState(rr, cell.tag))
                cell.tb.SetCount(counts[cell.tag])
            end
        end
    end
    -- A group's own icons can carry class boxes of their own (an import made
    -- on another class): they load only where both allow. Say so, and offer
    -- the group's boxes, one copy on demand.
    do
        local what = anySpecs and "class and spec checks" or "class checks"
        local function Strays()
            local r = ctx()
            return (r and r.type == "group") and Store.ClassSpecStrays(r) or {}
        end
        local strayVis = function() return tabVisible() and #Strays() > 0 end
        local note = AT.RowDesc(pg, "", 20, strayVis)
        local fs = note:GetRegions()
        local sync = note._sync
        note._sync = function()
            local list = Strays()
            local icons = true
            for _, rec in ipairs(list) do
                if rec.type ~= "icon" then icons = false end
            end
            local n = #list
            local noun = (icons and "icon" or "item") .. (n == 1 and "" or "s")
            if fs then
                fs:SetText(("%d %s in this group %s %s that leave out some of the group's %s.")
                    :format(n, noun, n == 1 and "has" or "have", what, anySpecs and "specs" or "classes"))
            end
            if sync then sync() end
        end
        local row = AT.RowButton(pg, "Match the group", function()
            local r = ctx()
            if not (r and r.type == "group") then return end
            Store.MatchClassSpecs(r, Store.ClassSpecStrays(r))
            AT.LayoutPage(pg)
            RefreshAll()
        end, strayVis, 150, "Their own " .. what)
        AT.Tooltip(row.button, "Match the group", "Copies this group's " .. what
            .. " onto those icons, so they load wherever the group does.")
    end
    -- the layout's twin, Match the layout (UI\AD_LayoutFollow.lua)
    if ctx == SelLayout and Options.LayoutFollow then
        Options.LayoutFollow.Rows(pg, ctx, tabVisible, anySpecs)
    end
    -- Talents, in the class section under a hairline: the build-level gate
    -- (on WoW Forever, with no specs, what "only on Enhancement" is on retail).
    AT.RowDivider(pg, tabVisible)
    local haveTree = function()
        local cat = NS.TalentCatalog
        return cat ~= nil and #cat.All() > 0
    end
    AT.RowDesc(pg, "No talent tree on this character: talent conditions do not apply.",
        20, function() return tabVisible() and not haveTree() end)

    -- The picks per class in one line that wraps, never cut. The Talents
    -- button by each class above picks them.
    local pickRow = AT.AddRow(pg, 24, tabVisible)
    local pickFs = pickRow:CreateFontString(nil, "OVERLAY")
    pickFs:SetFont(AT.FONT, 11, "")
    pickFs:SetPoint("TOPLEFT", 10, -5)
    pickFs:SetJustifyH("LEFT")
    pickFs:SetJustifyV("TOP")
    pickFs:SetWordWrap(true)
    pickFs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    pickRow._adPickText = pickFs
    pickRow._adSearch = function() return { "Talents" } end
    pickRow._sync = function()
        local r = ctx()
        -- another class's (or retail spec's) picks are named from its tree,
        -- read once a session while this list shows, never in combat
        local T = NS.TalentCatalog
        if r and T and T.LoadNames then
            for _, e in ipairs(Store.TalentList(r)) do
                if e.class and not e.named then T.LoadNames(e.class, e.spec) end
            end
        end
        local sum = Options.TalentSummary(r)
        pickFs:SetText(sum ~= "" and ("Talents: " .. sum)
            or "Talents: none, shows on any build. The Talents button by a class picks its talents.")
        local w = pickRow:GetWidth() or 0
        if w < 90 then w = (pg:GetWidth() or 0) - 24 end
        if w > 90 then pickFs:SetWidth(w - 20) end
        local want = math.max(24, math.floor((pickFs:GetStringHeight() or 12) + 10))
        if pickRow._h ~= want then
            pickRow._h = want
            pickRow:SetHeight(want)
        end
    end

    local haveMulti = function()
        local r = ctx()
        return r ~= nil and #Store.TalentList(r) > 1
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
        Options.BuildYield()
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
        nameFs:SetFont(AT.FONT, 11, "")
        nameFs:SetPoint("LEFT", 32, 0)
        nameFs:SetPoint("RIGHT", -150, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        local stateFs = row:CreateFontString(nil, "OVERLAY")
        stateFs:SetFont(AT.FONT, 10, "")
        stateFs:SetPoint("RIGHT", -74, 0)
        stateFs:SetJustifyH("RIGHT")
        local del = AT.MakeSmallButton(row, "Remove", 62)
        del:SetPoint("RIGHT", -8, 0)
        del:SetHeight(18)
        del.fs:SetFont(AT.FONT, 10, "")
        row._sync = function()
            local r = ctx()
            if not r then return end
            local list = Store.TalentList(r)
            local e = list[i]
            if not e then return end
            tex:SetTexture(e.icon)
            -- a pick made for a class says so, in that class's colour
            local label = ""
            if e.class then
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
                local hex = cc and (cc.colorStr or string.format("ff%02x%02x%02x",
                    math.floor((cc.r or 1) * 255 + 0.5), math.floor((cc.g or 1) * 255 + 0.5),
                    math.floor((cc.b or 1) * 255 + 0.5)))
                label = Options.TalentClassLabel(e.class, e.spec) .. ": "
                if hex then label = "|c" .. hex .. label .. "|r" end
            end
            nameFs:SetText(label .. e.name)
            if e.class and not e.here then
                -- made for another class or spec: not tested on this character
                nameFs:SetTextColor(0.7, 0.78, 0.88)
                stateFs:SetText(e.excluded and "excluded" or "required")
                stateFs:SetTextColor(0.55, 0.65, 0.78)
            elseif not e.known then
                -- stored from another class or a changed tree: say so rather
                -- than quietly reading as "not taken"
                nameFs:SetTextColor(0.55, 0.65, 0.78)
                stateFs:SetText("not in this tree")
                stateFs:SetTextColor(0.55, 0.65, 0.78)
            elseif e.excluded then
                -- a must-not-have: met while the node is not taken
                if e.taken then
                    nameFs:SetTextColor(0.7, 0.78, 0.88)
                    stateFs:SetText("excluded, taken")
                    stateFs:SetTextColor(0.95, 0.62, 0.30)
                else
                    nameFs:SetTextColor(0.95, 0.97, 1)
                    stateFs:SetText("excluded")
                    stateFs:SetTextColor(0.48, 0.85, 0.56)
                end
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
                if rr then Store.RemoveTalent(rr, e.nodeID) end
                AT.LayoutPage(pg)
                RefreshAll()
            end)
        end
        chosenRows[i] = row
    end
    -- retail only: the Role row and the Hero Talents section (UI\AD_RetailWho.lua)
    if Options.RetailWhoRows then Options.RetailWhoRows(pg, ctx, tabVisible, uiStore) end

    -- Faction: like the classes, a record kept to one faction is released on the
    -- other. Both boxes checked (no restriction) is the default.
    local C = NS.Conditions
    if C then
        Options.BuildYield()
        AT.Section(pg, "Faction",
            { collapsible = true, store = uiStore, visibleFn = tabVisible })
        local facRow = AT.AddRow(pg, 24, tabVisible)
        local facCells = {}
        for i, fac in ipairs(C.FACTIONS) do
            local cb = AT.MakeCheckbox(facRow)
            cb:SetPoint("LEFT", 4 + (i - 1) * 150, 0)
            local fs = facRow:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, 11, "")
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

    Options.BuildYield()
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
    lockFs:SetFont(AT.FONT, 10, "")
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

    -- Load When / Never Load When: a failing record is not released but goes
    -- inert (invisible, no mouse or sounds, out of its dynamic cell) with its
    -- frames kept, so it returns the moment the answer flips, in combat too.
    if C then
        local whenVis = function()
            local r = ctx()
            local _, packed = InAuraGroup(r)
            -- a wheel's key cannot change in combat, so it takes no Load When rules
            return tabVisible() and not packed and not (r and r.type == "bar" and r.barKind == "wheel")
        end
        Options.BuildYield()
        AT.Section(pg, "Load When",
            { collapsible = true, store = uiStore, visibleFn = whenVis })
        CondStatusRow(pg, ctx, whenVis, "loadWhen", function(r, n)
            if n == 0 then
                return "Nothing checked: no condition, so the sections above decide alone."
            end
            local head = C.MatchAll(r, "loadWhen")
                and "Loads only while EVERY checked condition is true."
                or "Loads only while at least one checked condition is true."
            -- the game plays an aura icon's sounds itself, so unloading cannot stop them
            if r and r.kind == "aura" then
                return head .. " Unloaded, it is hidden with no mouse and back the moment that changes, in combat too; the game still plays its aura sounds."
            end
            return head .. " Unloaded, it is gone completely - no mouse, no sounds, no spot in a dynamic group - and it is back the moment that changes, in combat too."
        end)
        CondMatchRow(pg, ctx, whenVis, "loadWhen")
        CondGrid(pg, ctx, whenVis, "loadWhen")
        -- a checked row of the other game version is kept but decides nothing
        AT.RowDesc(pg, "Some conditions here are for the other game version and are ignored.", 18,
            function() return whenVis() and C.Foreign ~= nil and C.Foreign(ctx(), "loadWhen") > 0 end)
        Options.BuildYield()
        AT.Section(pg, "Never Load When",
            { collapsible = true, store = uiStore, visibleFn = whenVis })
        CondStatusRow(pg, ctx, whenVis, "loadNever", function(_, n)
            if n == 0 then return "Nothing checked." end
            return "Stays unloaded while any checked condition is true. This wins over Load When."
        end)
        CondGrid(pg, ctx, whenVis, "loadNever")
        AT.RowDesc(pg, "Some conditions here are for the other game version and are ignored.", 18,
            function() return whenVis() and C.Foreign ~= nil and C.Foreign(ctx(), "loadNever") > 0 end)
        -- the set-pieces load rule (retail; UI\AD_SpecialOptions.lua)
        if Options.SetPiecesRows then Options.SetPiecesRows(pg, ctx, whenVis, uiStore, win) end
        AT.Section(pg, nil)
        -- A packed member keeps its own rules: they apply again once its group's
        -- Close gaps is off. saved: the note for a member that has some.
        local packedNote = function(saved)
            local r = ctx()
            local _, packed = InAuraGroup(r)
            if not (tabVisible() and packed) then return false end
            local own = (C.RangeRule ~= nil and C.RangeRule(r) ~= nil) or (C.SetRule ~= nil and C.SetRule(r) ~= nil)
            for _, list in ipairs(C.LISTS or {}) do
                if C.Count(r, list) > 0 then own = true end
            end
            return own == saved
        end
        AT.RowDesc(pg, "With Close gaps on, set these on the Aura Group.", 20,
            function() return packedNote(false) end)
        AT.RowDesc(pg, "This icon's own rules wait until Close gaps is off: set these on the Aura Group.", 20,
            function() return packedNote(true) end)
        AT.RowDesc(pg, "A wheel loads by class, spec, talents and spells: its key cannot change during combat.", 20,
            function()
                local r = ctx()
                return tabVisible() and r ~= nil and r.type == "bar" and r.barKind == "wheel"
            end)
    else
        AT.Section(pg, nil)
        AT.RowDesc(pg, COND_RESTART, 20, tabVisible)
    end

    -- The Known Spell rule on every kind of item: a "who" gate like the
    -- talents (Store.IsLoaded), so a record failing it is released, and
    -- SPELLS_CHANGED brings it back.
    Options.BuildYield()
    AT.Section(pg, "Known Spell", { collapsible = true, store = uiStore, visibleFn = tabVisible })
    do
        local row = AT.AddRow(pg, 24, tabVisible)
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
            fs:SetText(Options.KnownRuleText(r))
            local w = row:GetWidth() or 0
            if w < 90 then w = (pg:GetWidth() or 0) - 24 end
            if w > 90 then fs:SetWidth(w - 20) end
            local want = math.max(24, math.floor((fs:GetStringHeight() or 12) + 10))
            if row._h ~= want then
                row._h = want
                row:SetHeight(want)
            end
        end
    end
    AT.RowDropdown(pg, win, "Load only while",
        function() local r = ctx() return (r and r.c.knownMode) or "off" end,
        function(v)
            local r = ctx()
            if r then Store.SetKnownMode(r, v) end
            RefreshAll()
        end,
        function() return {
            { value = "off", text = "No spell rule" },
            { value = "known", text = "I know this spell" },
            { value = "unknown", text = "I don't know this spell" },
        } end,
        tabVisible)
    local knownOn = function()
        local r = ctx()
        return tabVisible() and r ~= nil and r.c.knownMode ~= nil
    end
    AT.RowInput(pg, "Spell",
        function()
            local r = ctx()
            return (r and r.c.knownSpell) and tostring(r.c.knownSpell) or ""
        end,
        function(v)
            local r = ctx()
            if not r then return end
            local DR = NS.DriverRange
            Store.SetKnownSpell(r, (DR and DR.ParseSpell(v)) or tonumber(v))
            RefreshAll()
        end,
        knownOn, "A spell ID, a link, or the name of a spell you know. Any rank of it counts unless Only this rank is on.",
        "e.g. 1495")
    AT.RowToggle(pg, "Only this rank",
        function() local r = ctx() return r ~= nil and r.c.knownRank == true end,
        function(v)
            local r = ctx()
            if r then Store.SetKnownRank(r, v) end
        end,
        function() return knownOn() and NS.IsForever == true end,
        "Counts only this exact rank (this spell ID), not any rank of the spell.")

    -- Close the section, so rows a caller adds next are not put inside it.
    AT.Section(pg, nil)
end

-- The Known Spell rule in words, for its status line.
function Options.KnownRuleText(r)
    local c = r and r.c
    local mode = c and c.knownMode
    if mode ~= "known" and mode ~= "unknown" then return "No spell rule." end
    local id = c.knownSpell
    if not id then return "Type the spell to check." end
    local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
    if issecretvalue and issecretvalue(nm) then nm = nil end
    local what = (type(nm) == "string" and nm ~= "") and nm or ("spell " .. id)
    if NS.IsForever == true then
        what = what .. ((c.knownRank == true) and (", this rank (" .. id .. ")") or ", any rank")
    end
    local has = Store.KnowsSpell(id, c.knownRank == true)
    local now = (has == true) and " Known now." or (has == false) and " Not known now." or ""
    if mode == "known" then return "Loads only once you know " .. what .. "." .. now end
    return "Loads only while you don't know " .. what .. "." .. now
end

-- The target range rule in words, for its status line.
function Options.RangeRuleText(r)
    local C = NS.Conditions
    local mode = r and r.c and r.c.rangeMode
    if mode ~= "in" and mode ~= "out" then return "No range rule." end
    local id = C and C.RangeRule and C.RangeRule(r)
    if not id then return "Type the spell to check." end
    local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
    if issecretvalue and issecretvalue(nm) then nm = nil end
    local what = (type(nm) == "string" and nm ~= "") and nm or ("spell " .. id)
    local where = (mode == "in") and "in range of " or "out of range of "
    return "Full opacity only while your target is " .. where .. what .. ". With no target it stays faded."
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
    Options.BuildYield()
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
    Options.BuildYield()
    AT.Section(pg, "Fade When",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    CondStatusRow(pg, ctx, tabVisible, "fadeWhen", function(r, n)
        if n == 0 then return "Nothing checked." end
        if n > 1 and C.MatchAll(r, "fadeWhen") then
            return "Fades only while EVERY checked condition is true. This wins over Full Opacity When."
        end
        return "Fades while any checked condition is true. This wins over Full Opacity When."
    end)
    CondMatchRow(pg, ctx, tabVisible, "fadeWhen")
    CondGrid(pg, ctx, tabVisible, "fadeWhen")
    -- A range rule for this element: a gate of its own besides the lists above,
    -- answered by the range engine's spell events. A range bar's bands are on its
    -- Tracking tab, never here.
    Options.BuildYield()
    AT.Section(pg, "Target Range Rule",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    do
        local row = AT.AddRow(pg, 24, tabVisible)
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
            fs:SetText(Options.RangeRuleText(r))
            local w = row:GetWidth() or 0
            if w < 90 then w = (pg:GetWidth() or 0) - 24 end
            if w > 90 then fs:SetWidth(w - 20) end
            local want = math.max(24, math.floor((fs:GetStringHeight() or 12) + 10))
            if row._h ~= want then
                row._h = want
                row:SetHeight(want)
            end
        end
    end
    AT.RowDropdown(pg, win, "Show only while",
        function() local r = ctx() return (r and r.c.rangeMode) or "off" end,
        function(v)
            local r = ctx()
            if r and C.SetRangeMode then C.SetRangeMode(r, v) end
            RefreshAll()
        end,
        function() return {
            { value = "off", text = "No range rule" },
            { value = "in", text = "Target in range" },
            { value = "out", text = "Target out of range" },
        } end,
        tabVisible)
    AT.RowInput(pg, "Check range with",
        function()
            local r = ctx()
            return (r and r.c.rangeSpell) and tostring(r.c.rangeSpell) or ""
        end,
        function(v)
            local r = ctx()
            if not (r and C.SetRangeSpell) then return end
            local DR = NS.DriverRange
            C.SetRangeSpell(r, (DR and DR.ParseSpell(v)) or tonumber(v))
            RefreshAll()
        end,
        tabVisible, "The spell whose range to your target decides the rule: a spell ID, or the name of a spell you know. Any rank works: the rank you know is checked.",
        "e.g. 75")
    Options.BuildYield()
    AT.Section(pg, "Fade Settings",
        { collapsible = true, store = uiStore, visibleFn = tabVisible })
    AT.RowSlider(pg, "Faded opacity",
        function() local r = ctx() return r and C.GetFade(r, "fadeAlpha") or 0 end,
        function(v) local r = ctx() if r then C.SetFade(r, "fadeAlpha", v) end end,
        0, 1, 0.01, true, tabVisible)
    AT.RowDesc(pg, "Everything shows fully while this window is open. Close it to see the fade.", 20, tabVisible)
    -- the fade's timing is fine-tuning, behind a fold (its tooltip says when
    -- either is set: C.SetFade stores nothing for the default 0)
    local ET = Options.EditorTabs
    local fadeFold = ET and ET.NewFold(pg, "cond.fade", "fade", ctx)
    for _, t in ipairs({
        { "Fade time (seconds)", "fadeTime", 0.05, "%.2f" },
        { "Delay before fading (seconds)", "fadeDelay", 0.1, "%.1f" },
    }) do
Options.BuildYield()
        local key = t[2]
        local vis = tabVisible
        if fadeFold then
            vis = fadeFold:Add(tabVisible, tabVisible, function(r) return r.c ~= nil and r.c[key] ~= nil end)
        end
        local row = AT.RowSlider(pg, t[1],
            function() local r = ctx() return r and C.GetFade(r, key) or 0 end,
            function(v) local r = ctx() if r then C.SetFade(r, key, v) end end,
            0, C.FADE_MAX[key], t[3], t[4], vis)
        row._adFold = fadeFold
        -- found by the search while the fold is shut
        row._adMeta = { family = "cond", section = "fade", field = key,
            def = { label = t[1], t = "num" }, baseVis = tabVisible }
    end
    AT.Section(pg, nil)
end

-- The window

local rail, content
local railRows = {}          -- row frame pool
-- name -> frame. A pane stored while the window shows starts hidden, so the
-- page on screen stays until ShowPane swaps the new one in whole.
local panes = setmetatable({}, { __newindex = function(t, k, v)
    rawset(t, k, v)
    if type(v) == "table" and v.Hide and win and win:IsShown() then v:Hide() end
end })
local layoutRowPool = {}     -- layout-page member rows
local layoutAddRow           -- the "+ Add to this layout" row
local stripPool = {}         -- group strip icon buttons
local freeStripPool = {}
local addWin

local function ShowPane(name)
    -- a pane no pick built yet (the picks build theirs behind the loader)
    Options.EnsurePane(name)
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

    local function Mode(single, cells, bar, letters)
        t.single:SetShown(single)
        for i = 1, 4 do t.cells[i]:SetShown(cells) end
        for _, k in ipairs(THUMB_EDGES) do t.frame[k]:SetShown(cells) end
        t.bar:SetShown(bar)
        if t.letters then t.letters:SetShown(letters == true) end
    end
    -- a bar thumb may have laid the art under its bar, a text thumb dimmed it;
    -- pooled rows reuse it
    local function PlainSingle()
        t.single:ClearAllPoints()
        t.single:SetPoint("TOPLEFT", 0, 0)
        t.single:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.single:SetVertexColor(1, 1, 1)
        -- a texture thumb may have left its blend and grey
        t.single:SetBlendMode("BLEND")
        t.single:SetDesaturated(false)
    end

    -- A texture is its own picture: the art it shows, whole (an atlas through
    -- its part of the file, an animated sheet its first frame), in its colour,
    -- blend and grey. The spell's icon keeps the icons' trim.
    function t:SetPicture(rec, px)
        px = px or size
        self:SetSize(px, px)
        PlainSingle()
        self.single:SetSize(px, px)
        Mode(true, false, false)
        local TP = NS.TextureElements
        if not TP then
            self.single:SetTexture(134400)
            return
        end
        local art = TP.Art(TP.PictureOf(rec))
        local l, r, tp, b = art.l, art.r, art.t, art.b
        local own = Store.Resolve(rec, "texlook", "image")
        if own == nil or own == "" then
            l, r, tp, b = 0.08, 0.92, 0.08, 0.92
        elseif TP.Flip(rec) then
            local cols = math.max(1, tonumber(Store.Resolve(rec, "texlook", "flipCols")) or 1)
            local rows = math.max(1, tonumber(Store.Resolve(rec, "texlook", "flipRows")) or 1)
            r, b = l + (r - l) / cols, tp + (b - tp) / rows
        end
        self.single:SetTexture(art.file)
        self.single:SetTexCoord(l, r, tp, b)
        local c = Store.Resolve(rec, "texlook", "color") or { 1, 1, 1, 1 }
        self.single:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1)
        self.single:SetBlendMode(Store.Resolve(rec, "texlook", "blend") == "ADD" and "ADD" or "BLEND")
        self.single:SetDesaturated(Store.Resolve(rec, "texlook", "desat") == true)
    end

    -- A text is a miniature of itself: "Aa" in its own colour, over its
    -- spell's or aura's art when it has one (dimmed so the letters read), else
    -- on a small plate.
    function t:SetText(rec, width, spellTex)
        width = width or size
        self:SetSize(width, size)
        PlainSingle()
        Mode(true, false, false, true)
        self.single:SetSize(size, size)
        if spellTex then
            self.single:SetTexture(spellTex)
            self.single:SetVertexColor(0.45, 0.45, 0.45)
        else
            self.single:SetColorTexture(COL.box[1], COL.box[2], COL.box[3], 1)
        end
        local fs = self.letters
        if not fs then
            fs = self:CreateFontString(nil, "OVERLAY")
            self.letters = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", self, "LEFT", size / 2, 0)
        -- the text element on screen, so the game's font, not the panel's
        fs:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(size * 0.5 + 0.5)), "OUTLINE")
        local c = Store.Resolve(rec, "textel", "color") or { 1, 1, 1, 1 }
        fs:SetTextColor(c[1], c[2], c[3], 1)
        fs:SetText("Aa")
        fs:Show()
    end

    -- px = an optional bigger square (the layout cards' 30px free icons)
    function t:SetIcon(tex, px)
        px = px or size
        self:SetSize(px, px)
        PlainSingle()
        self.single:SetSize(px, px)
        Mode(true, false, false)
        self.single:SetTexture(tex or 134400)
    end

    function t:SetGroup(color)
        self:SetSize(groupSize, groupSize)
        Mode(false, true, false)
        -- the kind colour as the palette's pills show it
        color = AT.Mute(color or YELLOW)
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

    -- width = the thumb's width; at 40+ the spell art leads the mini bar,
    -- below that (the sidebar) it fills the thumb behind the same mini bar
    function t:SetBar(rec, width, spellTex)
        if rec.barKind == "text" then return self:SetText(rec, width, spellTex) end
        if rec.barKind == "wheel" then return self:SetIcon(Options.WheelThumb and Options.WheelThumb(rec) or 134400) end
        if rec.barKind == "sound" then return self:SetIcon(Options.SoundThumb and Options.SoundThumb(rec) or 134400) end
        if rec.barKind == "texture" then return self:SetPicture(rec) end
        width = width or size
        self:SetSize(width, size)
        local lead = (width >= 40) and spellTex
        local behind = (not lead) and spellTex
        Mode((lead or behind) and true or false, false, true)
        PlainSingle()
        local x = 0
        if lead then
            self.single:SetSize(size, size)
            self.single:SetTexture(spellTex)
            x = size + 3
        elseif behind then
            -- cropped to the thumb's shape rather than squeezed
            local v = 0.42 * size / width
            self.single:ClearAllPoints()
            self.single:SetAllPoints(self)
            self.single:SetTexCoord(0.08, 0.92, 0.5 - v, 0.5 + v)
            self.single:SetTexture(spellTex)
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

Options._makeThumb = MakeThumb   -- offline harness access

local RAIL_W = 232
local ADDLINE = { 0.18, 0.34, 0.24 }

-- The side-icon override, then the driver spell, as the bar's own side icon
-- resolves. nil: no art, and the layout cards draw the mini bar alone.
local function BarTexture(rec)
    local ov = Store.Resolve(rec, "icon", "iconOverride") or 0
    if type(ov) == "number" and ov > 0 then
        return C_Spell.GetSpellTexture(ov) or ov -- raw-id: an art pick, not a tracked spell
    end
    local d = rec.driver or {}
    if rec.barKind == "swing" then
        local slot = (d.swingType == 1 and 17) or (d.swingType == 2 and 18) or 16
        return GetInventoryItemTexture("player", slot)
    end
    -- the spell the bar reads, or its aura (each question's own entry)
    if rec.barKind == "cooldown" then
        local sid = Store.RecordSpellID(d)
        return sid and C_Spell.GetSpellTexture(sid) or nil
    end
    if rec.barKind == "aura" then
        local aid = Store.TrackedAuraIDs(d)[1]
        return aid and C_Spell.GetSpellTexture(aid) or nil
    end
    -- a deck bar wears its tracker's art
    if rec.barKind == "special" and NS.SpecialIcon then return NS.SpecialIcon.Texture(rec) end
    -- a text for a spell or an aura wears its art under its letters
    local TO = Options.TextElement
    if rec.barKind == "text" and TO and TO.Subject(d.source) ~= "other" then
        local sid = (TO.Subject(d.source) == "spell") and Store.RecordSpellID(d) or Store.TrackedAuraIDs(d)[1]
        return sid and C_Spell.GetSpellTexture(sid) or nil
    end
    return nil
end

-- One painter for every rail row. style: "layout" = raised header card,
-- "child" = tree item, "add" / "addbtn" = green actions, "label" = inert caption.
local function PaintRailRow(row, selected, style)
    row._sel, row._style = selected, style
    local fill, edge, ink = COL.well, COL.well, COL.dim
    if selected and AT.LOOK.selBar then
        -- the fill and the left bar alone: no accent edge or words
        fill, edge, ink = COL.sel, COL.sel, COL.ink
    elseif selected then
        fill, edge, ink = COL.sel, COL.arcDeep, COL.arc
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
            edge, ink = COL.focus, COL.ink
        end
    end
    -- part of a multi-selection (UI\AD_MultiSelect.lua): outlined and worded
    -- in the accent, the current row alone keeps the filled look
    if row._multi and not selected then edge, ink = COL.arc, COL.arc end
    AT.Skin(row, fill, edge)
    row.name:SetTextColor(ink[1], ink[2], ink[3])
    if row.glyph then row.glyph:SetColor(ink) end
    if row.accent then row.accent:SetShown((selected or row._multi) and true or false) end
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
    elseif rec.type == "icon" or rec.type == "reminder" then
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
                or k == "addchild" or k == "groupicon" then
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
    -- over an icon inside a group: an icon from elsewhere joins that group
    if item.kind == "groupicon" then
        local g = item.group
        if rec.type ~= "icon" or rec.groupId == g.id then return nil end
        if not Store.GroupTakes(g, rec.kind) then return nil end
        return { row = row, mode = "join", groupId = g.id, label = "into " .. g.name }
    end
    if item.rec.id == rec.id then return nil end
    local _, cy = GetCursorPosition()
    local es = row:GetEffectiveScale()
    local top, bottom = row:GetTop(), row:GetBottom()
    if not (es and es > 0 and top and bottom and top > bottom) then return nil end
    local f = (top - cy / es) / (top - bottom)   -- 0 at the top edge, 1 at the bottom
    if rec.type == "icon" and item.kind == "group" and f >= 0.3 and f <= 0.7 then
        if item.rec.id == rec.groupId then return nil end
        if not Store.GroupTakes(item.rec, rec.kind) then return nil end
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
        ghost.fs:SetFont(AT.FONT, 11, "")
        ghost.fs:SetPoint("TOPLEFT", 8, -5)
        ghost.fs:SetPoint("TOPRIGHT", -8, -5)
        ghost.fs:SetJustifyH("LEFT")
        ghost.fs:SetWordWrap(false)
        ghost.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        ghost.sub = ghost:CreateFontString(nil, "OVERLAY")
        ghost.sub:SetFont(AT.FONT, 10, "")
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
-- On loaded records, open grey = drawn, slashed cyan = hidden on screen while
-- the window is open (Store.EditHidden, cleared on close). New texture files
-- need a full client restart.
Options.EYE_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_Eye"
Options.EYE_OFF_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_EyeOff"

function Options.MakeEye(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 18)
    -- One texture per state, each given its file once here; PaintEye shows one
    -- and hides the other. Handing a visible texture a new file drew nothing
    -- until the window was reopened.
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetSize(18, 18)
    b.tex:SetPoint("CENTER", 0, 0)
    b.tex:SetTexture(Options.EYE_OFF_TEX)
    b.texOn = b:CreateTexture(nil, "OVERLAY")
    b.texOn:SetSize(18, 18)
    b.texOn:SetPoint("CENTER", 0, 0)
    b.texOn:SetTexture(Options.EYE_TEX)
    b.texOn:Hide()
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
        -- on: drawn on screen after this click
        local on
        if Store.IsLoaded(rec) then
            on = Store.EditHidden(rec)
            Store.SetEditHidden(rec, not on)
        else
            on = not Store.UnloadedShown(rec)
            Store.SetUnloadedShown(rec, on)
        end
        -- a layout's or group's click reaches everything under it
        if rec.type == "layout" or rec.type == "group" then Store.SetEyeTree(rec, on) end
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                     or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        RefreshAll()
    end)
    -- Hooked after the SetScript calls above, or they would replace it.
    AT.Tooltip(b, function()
        local r = b._rec
        if r and Store.IsLoaded(r) then
            return Store.EditHidden(r) and "Hidden while editing" or "Hide while editing"
        end
        return (r and Store.UnloadedDrawn(r)) and "Shown while editing" or "Not loaded here"
    end, function()
        local r = b._rec
        if not r then return nil end
        if Store.IsLoaded(r) then
            if Store.EditHidden(r) then
                return "Not drawn on screen for now. Click to show it again. Closing this window shows everything again."
            end
            return "Hides it on screen while this window is open, so you can get at what sits under it. Closing the window shows it again."
        end
        local why = (Store.BadgeText(r))
        if Store.UnloadedDrawn(r) then
            return "Drawn on screen while this window is open, with an \"unloaded\" tag. It loads on: "
                .. why .. ". Click to hide it again."
        end
        if Store.UnloadedShown(r) then
            return "Not loaded on this character. It loads on: " .. why
                .. ". The sidebar View keeps it off screen; Everything shows it."
        end
        return "Not loaded on this character. It loads on: " .. why
            .. ". Click to draw it on screen while this window is open. Its load conditions stay as they are."
    end)
    b:Hide()
    return b
end

-- Shown for every record. Cyan marks an eye in its working state: an unloaded
-- record drawn, a loaded one hidden.
function Options.PaintEye(b, rec)
    b._rec = rec
    b:SetShown(rec ~= nil)
    if not rec then return end
    local worked, open
    if Store.IsLoaded(rec) then
        worked = Store.EditHidden(rec)
        open = not worked
    else
        -- the screen's answer: the View "This character" draws none
        worked = Store.UnloadedDrawn(rec)
        open = worked
    end
    local c = (b._hot and COL.ink) or (worked and COL.arc) or COL.faint
    local show, hide = b.tex, b.texOn
    if open then show, hide = b.texOn, b.tex end
    hide:Hide()
    show:SetVertexColor(c[1], c[2], c[3], 1)
    show:Show()
end

-- The lock beside a layout's or group's eye: locked, nothing in it moves or
-- reshapes from the screen while this window is open, and the panel still
-- edits it (Store.Locked). It shows while its row is under the mouse or while
-- it locks itself, so the rail stays clean; Position's "Lock in place" is the
-- same switch. Drawn like the eye: one tinted texture per state.
Options.LOCK_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_Lock"
Options.LOCK_OPEN_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_LockOpen"

function Options.MakeLock(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 18)
    -- the row or tile whose hover shows it
    b._host = parent
    -- each texture gets its file once, as on the eye
    b.shut = b:CreateTexture(nil, "OVERLAY")
    b.shut:SetSize(18, 18)
    b.shut:SetPoint("CENTER", 0, 0)
    b.shut:SetTexture(Options.LOCK_TEX)
    b.open = b:CreateTexture(nil, "OVERLAY")
    b.open:SetSize(18, 18)
    b.open:SetPoint("CENTER", 0, 0)
    b.open:SetTexture(Options.LOCK_OPEN_TEX)
    b.open:Hide()
    b:SetScript("OnEnter", function(s)
        s._hot = true
        Options.PaintLock(s, s._rec)
    end)
    b:SetScript("OnLeave", function(s)
        s._hot = nil
        Options.PaintLock(s, s._rec)
    end)
    b:SetScript("OnClick", function(s)
        AT.CloseDropdown()
        local rec = s._rec
        if not rec then return end
        local on = not Store.LockedSelf(rec)
        Store.SetLocked(rec, on)
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                     or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        RefreshAll()
    end)
    -- Hooked after the SetScript calls above, or they would replace it.
    AT.Tooltip(b, function()
        local r = b._rec
        if r and Store.LockedSelf(r) then return "Locked" end
        if r and Store.Locked(r) then return "Locked by its layout" end
        return "Lock in place"
    end, function()
        local r = b._rec
        if not r then return nil end
        if Store.Locked(r) then return "It can't be dragged on screen." end
        return "Stops it being dragged on screen."
    end)
    b:Hide()
    return b
end

-- Shown while its row or tile is under the mouse (IsMouseOver counts the lock
-- itself, so moving onto it keeps it) or while it locks itself. Shut while
-- locked, cyan when locked here (its working state, like the eye's), grey
-- when its layout locks it.
function Options.PaintLock(b, rec)
    b._rec = rec
    if not rec then
        b:Hide()
        return
    end
    local own, any = Store.LockedSelf(rec), Store.Locked(rec)
    local host = b._host
    local over = b._hot == true or (host ~= nil and host:IsMouseOver() == true)
    b:SetShown(own or over)
    local c = (b._hot and COL.ink) or (own and COL.arc) or COL.faint
    local show, hide = b.shut, b.open
    if not any then show, hide = b.open, b.shut end
    hide:Hide()
    show:SetVertexColor(c[1], c[2], c[3], 1)
    show:Show()
end

-- Position's "Lock in place" on a layout or a group: the same lock the
-- sidebar's padlock sets.
function Options.LockRow(pg, ctx, vis)
    AT.RowToggle(pg, "Lock in place",
        function() return Store.LockedSelf(ctx()) end,
        function(v)
            local r = ctx()
            if not r then return end
            Store.SetLocked(r, v)
            RefreshAll()
        end, vis)
    AT.RowDesc(pg, "Its layout is locked, so it stays put anyway.", 20, function()
        local r = ctx()
        return vis() and r ~= nil and r.type == "group" and Store.Locked(r) and not Store.LockedSelf(r)
    end)
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
    row.name:SetFont(AT.FONT, 12, "")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.pill = KindPill(row)
    -- Anchored per row kind in RefreshRail; the lock only on layouts and groups.
    row.eye = Options.MakeEye(row)
    row.lock = Options.MakeLock(row)
    row.badge = row:CreateFontString(nil, "OVERLAY")
    row.badge:SetFont(AT.FONT, 8, "")
    row.badge:SetPoint("RIGHT", -6, 0)
    row.badge:SetJustifyH("RIGHT")
    row.badge:SetWordWrap(false)
    if row.badge.SetMaxLines then row.badge:SetMaxLines(1) end
    row.thumb = MakeThumb(row, 18, 20)
    -- the class mark on the picture's corner (the View, RefreshRail)
    row.cmark = row.thumb:CreateTexture(nil, "OVERLAY", nil, 7)
    row.cmark:SetSize(11, 11)
    row.cmark:SetPoint("CENTER", row.thumb, "BOTTOMRIGHT", 0, 1)
    row.cmark:Hide()
    row.edit = AT.MakeSmallButton(row, "Edit", 38)
    row.edit:SetPoint("RIGHT", -4, 0)
    row.edit:SetHeight(16)
    row.edit.fs:SetFont(AT.FONT, 9, "")
    row.export = AT.MakeSmallButton(row, "Exp", 32)
    row.export:SetPoint("RIGHT", row.edit, "LEFT", -3, 0)
    row.export:SetHeight(16)
    row.export.fs:SetFont(AT.FONT, 9, "")
    AT.Tooltip(row.export, "Export", "Copy a share string for this layout.")
    row.add = AT.MakeSmallButton(row, "+", 20)
    row.add:SetPoint("RIGHT", row.export, "LEFT", -3, 0)
    row.add:SetHeight(16)
    row.add.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    AT.Tooltip(row.add, "Add", "Add an icon, bar or group to this layout.")
    RailChrome(row)
    -- a row's item may carry a tooltip (rows are pooled: read it on hover)
    AT.Tooltip(row, function() return row._item and row._item.tipTitle end,
        function() return row._item and row._item.tip end)
    -- Hooked after RailChrome's SetScript, or it would be replaced.
    AT.Tooltip(row, "Not loaded here", function()
        local item = row._item
        local rec = item and item.rec
        if not (rec and not Store.IsLoaded(rec)) then return nil end
        -- a layout row says it in its badge, when the badge had room
        if rec.type == "layout" and (item.kind ~= "layout" or row.badge:IsShown()) then return nil end
        local why = Store.BadgeText(rec)
        return "This " .. (rec.type == "group" and "group" or rec.type)
            .. " fails its load conditions on this character (" .. why
            .. "). It exists and can be edited; it just does not show here. Click its eye to draw it on screen while you edit."
    end)
    -- the lock shows while the row is under the mouse
    row:HookScript("OnEnter", function() Options.PaintLock(row.lock, row.lock._rec) end)
    row:HookScript("OnLeave", function() Options.PaintLock(row.lock, row.lock._rec) end)
    railRows[i] = row
    return row
end

-- The sidebar's View, for the account (setting railView): nil lists everything
-- as each layout orders it; "char" only what loads on this character;
-- "byclass" the items that do not load here in a section per class;
-- "only:<TAG>" one class's HUD, what holds to no class plus that class's own.
-- A class no saved load condition names any more reads as nil.
local function RailClassName(tag)
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        if cls.tag == tag then return cls.name end
    end
    return tag
end

local function RailClassHex(tag)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
    if not c then return "ffffffff" end
    return string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

-- every class a saved load condition names
function Options.RailClasses()
    local set = {}
    Store.EachRecord(function(_, rec)
        for _, tag in ipairs((Store.ClassesOf(rec))) do set[tag] = true end
    end)
    return set
end

local function RailView()
    local v = Store.GetSetting("railView")
    if v == "char" or v == "byclass" then return v end
    local tag = type(v) == "string" and v:match("^only:(.+)$")
    if tag and Options.RailClasses()[tag] then return v end
    return nil
end
Options.RailView = RailView

-- the View's choices: the three ways, then each class your layouts name
function Options.RailViewItems()
    local items = {
        { value = "all", text = "Everything" },
        { value = "char", text = "This character" },
        { value = "byclass", text = "By class" },
    }
    local tags = {}
    for tag in pairs(Options.RailClasses()) do tags[#tags + 1] = tag end
    table.sort(tags, function(a, b) return RailClassName(a) < RailClassName(b) end)
    for _, tag in ipairs(tags) do
        items[#items + 1] = { value = "only:" .. tag,
            text = "|c" .. RailClassHex(tag) .. RailClassName(tag) .. "|r" }
    end
    return items
end

-- the one class a record's own conditions name, or nil
local function OneClass(rec)
    local cls = Store.ClassesOf(rec)
    if #cls == 1 then return cls[1] end
    return nil
end

-- A class mark: the class's own icon (its atlas on both clients, the
-- character-create sheet where the atlas is missing), or none.
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local function PaintClassMark(t, tag)
    local atlas = tag and GetClassAtlas and GetClassAtlas(tag:lower())
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        t:SetAtlas(atlas)
        t:Show()
        return
    end
    local tc = tag and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tag]
    if not tc then
        t:Hide()
        return
    end
    t:SetTexture(CLASS_SHEET)
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    t:Show()
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
    -- the View holds while nothing is searched; a search lists every match
    local view = (not filter) and RailView() or nil
    local only = view and view:match("^only:(.+)$")
    -- what holds to no class, or holds to `want` among its classes
    local function HoldsTo(rec, want)
        local cls, limited = Store.ClassesOf(rec)
        if not limited then return true end
        for _, tag in ipairs(cls) do
            if tag == want then return true end
        end
        return false
    end
    -- in a one-class view: what holds to no class, or holds to that one
    local function ForOnly(rec) return HoldsTo(rec, only) end
    -- what a filtering view keeps; a count stands where the rest were
    local function Keeps(rec)
        if view == "char" then return Store.IsLoaded(rec) end
        if only then return ForOnly(rec) end
        return true
    end
    -- every one of them held to a single class that is not this character's
    local me = Store.ClassTag and Store.ClassTag()
    local function OthersOnly(recs)
        for _, r in ipairs(recs) do
            local tag = OneClass(r)
            if not tag or tag == me then return false end
        end
        return true
    end
    -- classes in name order
    local function ByName(map)
        local tags = {}
        for tag in pairs(map) do tags[#tags + 1] = tag end
        table.sort(tags, function(a, b) return RailClassName(a) < RailClassName(b) end)
        return tags
    end
    local function Hit(rec)
        return S.RecScore(rec, filter.q, filter.words, filter.num) ~= nil
    end
    local function MemberHit(m)
        if Hit(m) then return true end
        if m.type == "group" then
            local kids = (m.groupKind == "reminder") and Store.GroupMembers(m) or Store.IconsOf(m)
            for _, ic in ipairs(kids) do
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
            -- The layout's own member order, kinds mixed; free icons are plain
            -- children. In a layout that loads here, members that do not load
            -- here follow the add row under their own sub-header.
            local later = {}
            local function Add(m)
                if m.type == "group" then
                    -- An icon group opens like a layout, to its icons; a search
                    -- opens it to the ones that match. A Reminder group opens
                    -- to its reminders (aura reminders among them, as icon
                    -- rows) and an add row, even while empty.
                    local rem = m.groupKind == "reminder"
                    local icons = rem and Store.GroupMembers(m) or Store.IconsOf(m)
                    local count = #icons
                    local gopen = expanded[m.id] and true or false
                    if filter then
                        local hits = {}
                        for _, ic in ipairs(icons) do
                            if Hit(ic) then hits[#hits + 1] = ic end
                        end
                        if #hits > 0 then icons, gopen = hits, true end
                    end
                    list[#list + 1] = { kind = "group", rec = m, open = gopen and (count > 0 or rem),
                        count = count, rem = rem }
                    if gopen then
                        local function Row(ic)
                            list[#list + 1] = { kind = (ic.type == "reminder") and "reminder" or "groupicon",
                                rec = ic, group = m }
                        end
                        -- In a group that loads here, its members that do not
                        -- follow the add row in a fold of their own. A one-class
                        -- view keeps that class's own in place (they fail here by
                        -- their class), so only a member whose class check passes
                        -- on this character folds there.
                        local ctx = not notLoaded and Store.IsLoaded(m)
                        local rest, gone = {}, 0
                        for _, ic in ipairs(icons) do
                            if not Keeps(ic) then
                                gone = gone + 1
                            elseif ctx and not Store.IsLoaded(ic) and (not only or HoldsTo(ic, me)) then
                                rest[#rest + 1] = ic
                            else
                                Row(ic)
                            end
                        end
                        if gone > 0 then list[#list + 1] = { kind = "hidden", count = gone, depth = 2 } end
                        if rem and not filter then list[#list + 1] = { kind = "addrem", rec = m } end
                        if #rest > 0 then
                            -- shut until opened (per group, Store.UI().nlOpen); nil
                            -- also opens it while it holds the member being edited,
                            -- false keeps it shut even then; a search shows its matches
                            local st = Store.UI().nlOpen
                            local o = st and st[m.id]
                            local shut = false
                            if not filter and o ~= true then
                                local sid = ui.selType == "group" and ui.selId == m.id
                                    and ((ui.grpMode == "ico" and ui.selIconId)
                                    or (ui.grpMode == "rem" and ui.selRemId)) or nil
                                local holds = false
                                for _, ic in ipairs(rest) do
                                    if ic.id == sid then holds = true break end
                                end
                                shut = o == false or not holds
                            end
                            list[#list + 1] = { kind = "gsub", count = #rest, rec = m, shut = shut,
                                others = (view == "byclass" and OthersOnly(rest)) or nil }
                            if not shut then
                                for _, ic in ipairs(rest) do Row(ic) end
                            end
                        end
                    end
                elseif m.type == "icon" then
                    list[#list + 1] = { kind = "freeicon", rec = m, layout = layout }
                else
                    list[#list + 1] = { kind = "bar", rec = m }
                end
            end
            local gone, byClass = 0, {}
            for _, m in ipairs(members) do
                if view == "char" or only then
                    -- a one-class view keeps that class's items in place, loaded here or not
                    if Keeps(m) then Add(m) else gone = gone + 1 end
                elseif notLoaded or Store.IsLoaded(m) then
                    Add(m)
                else
                    local tag = (view == "byclass") and OneClass(m) or nil
                    if tag then
                        byClass[tag] = byClass[tag] or {}
                        byClass[tag][#byClass[tag] + 1] = m
                    else
                        later[#later + 1] = m
                    end
                end
            end
            if not filter then list[#list + 1] = { kind = "addchild", rec = layout } end
            if gone > 0 then list[#list + 1] = { kind = "hidden", count = gone, depth = 1 } end
            local shutSet = Store.UI().nlShut
            -- by class: a section per class, each folding on its own
            for _, tag in ipairs(ByName(byClass)) do
                local key = layout.id .. ":" .. tag
                local shut = shutSet ~= nil and shutSet[key] == true
                list[#list + 1] = { kind = "clsub", tag = tag, count = #byClass[tag], rec = layout,
                    key = key, shut = shut }
                if not shut then
                    for _, m in ipairs(byClass[tag]) do Add(m) end
                end
            end
            if #later > 0 then
                -- the section folds per layout (a panel preference); a search
                -- always shows its matches
                local shut = (not filter) and shutSet ~= nil and shutSet[layout.id] == true
                list[#list + 1] = { kind = "nlsub", count = #later, rec = layout, shut = shut }
                if not shut then
                    for _, m in ipairs(later) do Add(m) end
                end
            end
        end
    end
    -- Layouts that fail their load conditions here still list, dimmed, under their
    -- own header.
    local loadedL, notLoadedL = {}, {}
    local goneL = 0
    for _, layout in ipairs(Store.Layouts()) do
        if only and not ForOnly(layout) then
            goneL = goneL + 1
        elseif Store.IsLoaded(layout) then
            loadedL[#loadedL + 1] = layout
        elseif view == "char" then
            goneL = goneL + 1
        else
            notLoadedL[#notLoadedL + 1] = layout
        end
    end
    for _, l in ipairs(loadedL) do AddLayout(l, false) end
    -- by class: the layouts that do not load here, under a header per class
    if view == "byclass" then
        local byClass, rest = {}, {}
        for _, l in ipairs(notLoadedL) do
            local tag = OneClass(l)
            if tag then
                byClass[tag] = byClass[tag] or {}
                byClass[tag][#byClass[tag] + 1] = l
            else
                rest[#rest + 1] = l
            end
        end
        for _, tag in ipairs(ByName(byClass)) do
            list[#list + 1] = { kind = "clhdr", tag = tag, count = #byClass[tag] }
            for _, l in ipairs(byClass[tag]) do AddLayout(l, true) end
        end
        notLoadedL = rest
    end
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
    if goneL > 0 then list[#list + 1] = { kind = "hidden", count = goneL, depth = 0, layouts = true } end
    if not filter then
        list[#list + 1] = { kind = "newlayout" }
    end
    return list
end
Options._buildRailList = BuildRailList   -- used by the offline tests

local function RefreshRail()
    local list = BuildRailList()
    -- class marks on the pictures in every View but Everything, never in a search
    local marks = RailView() ~= nil and (ui.search or "") == ""
    if Options.railView then Options.railView.Refresh() end
    -- layout id -> the layout pack whose newer version its copy lacks
    local packUpd = Options.Home and Options.Home.UpdateByLayout() or nil
    -- inside the scrolling list, which starts under the LAYOUTS caption
    local y = -6
    -- Every thumbnail mode is centered in one 22px slot so the names line up. Call
    -- after the thumb's mode is set: the centering reads its width.
    local function Child(row, rec, indent)
        -- dimmed: not drawn here, by its load conditions or by its eye
        row._dim = (not Store.IsLoaded(rec) or Store.EditHidden(rec)) or nil
        -- the eye sits just left of the kind pill (PillRight places the pill)
        row.eye:ClearAllPoints()
        row.eye:SetPoint("RIGHT", row.pill, "LEFT", -2, 0)
        Options.PaintEye(row.eye, rec)
        row.guide:Show()
        row.thumb:Show()
        row.thumb:ClearAllPoints()
        row.thumb:SetPoint("LEFT", indent + (22 - row.thumb:GetWidth()) / 2, 0)
        if marks then PaintClassMark(row.cmark, OneClass(rec)) end
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", indent + 28, 0)
        row.name:SetPoint("RIGHT", -8, 0)
        row.name:SetText(rec.name)
    end
    local function PillRight(row)
        row.pill:Show()
        row.pill:ClearAllPoints()
        row.pill:SetPoint("RIGHT", -5, 0)
        row.name:SetPoint("RIGHT", row.eye, "LEFT", -3, 0)
    end
    for i, item in ipairs(list) do
        local row = RailRow(i)
        -- Air above every header but the first.
        if i > 1 and (item.kind == "layout" or item.kind == "nlhdr" or item.kind == "clhdr"
            or item.kind == "nlsub" or item.kind == "clsub" or item.kind == "gsub"
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
        -- a pooled row forgets its lock, so hovering an icon row shows none
        Options.PaintLock(row.lock, nil)
        row.cmark:Hide()
        row.badge:Hide()
        if row.upd then row.upd:Hide() end
        row.thumb:Hide()
        row.edit:Hide()
        row.export:Hide()
        row.add:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetPoint("RIGHT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row:SetScript("OnClick", nil)
        -- Read by the drag-and-drop hit test.
        row._item = item
        row:SetScript("OnDragStart", nil)
        row:SetScript("OnDragStop", nil)
        local MS = Options.MultiSelect
        row._multi = (MS and item.rec and MS.Has(item.rec.id)) or nil

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
            row._dim = (item.notLoaded or Store.EditHidden(rec)) or nil
            PaintRailRow(row, selected, "layout")
            -- Every layout row carries its buttons and its eye; the conditions
            -- badge sits left of the eye only when the name leaves it room
            -- (for an unloaded layout the row's tooltip says it otherwise).
            row.edit:Show()
            row.export:Show()
            row.add:Show()
            row.eye:ClearAllPoints()
            row.eye:SetPoint("RIGHT", row.add, "LEFT", -4, 0)
            Options.PaintEye(row.eye, rec)
            row.lock:ClearAllPoints()
            row.lock:SetPoint("RIGHT", row.eye, "LEFT", -2, 0)
            Options.PaintLock(row.lock, rec)
            row.badge:SetText(Store.BadgeText(rec))
            row.badge:SetTextColor(SHR[1], SHR[2], SHR[3])
            local nw = (row.name.GetUnboundedStringWidth and row.name:GetUnboundedStringWidth()) or 0
            local bw = (row.badge.GetUnboundedStringWidth and row.badge:GetUnboundedStringWidth()) or 0
            -- 17: the list's and the row's insets; 150: the buttons, the eye, the lock, their gaps
            local want = math.min(92, bw + 2)
            local fit = math.min(want, (rail:GetWidth() or 0) - 17 - 22 - nw - 8 - 150)
            -- a newer version of the layout pack it came from takes the badge's
            -- place: a "v2" tag whose click offers it (UI\AD_Home.lua)
            local pe = packUpd and packUpd[rec.id]
            if pe then
                if not row.upd then row.upd = Options.Home.MakeRailTag(row) end
                Options.Home.PaintRailTag(row.upd, pe)
                row.upd:ClearAllPoints()
                row.upd:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
                row.upd:Show()
                row.name:SetPoint("RIGHT", row.upd, "LEFT", -4, 0)
            elseif bw > 0 and (fit == want or fit >= 30) then
                row.badge:ClearAllPoints()
                row.badge:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
                row.badge:SetWidth(fit)
                row.badge:Show()
                row.name:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
            else
                row.name:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
            end
            row.edit:SetScript("OnClick", function() Options.Select("layout", rec.id) end)
            row.export:SetScript("OnClick", function() Options.OpenExport(rec.id) end)
            row.add:SetScript("OnClick", function() Options.OpenAdd(rec.id) end)
            row:SetScript("OnClick", function()
                ExpandedSet()[rec.id] = not ExpandedSet()[rec.id] or nil
                Options.Select("layout", rec.id)
            end)
        elseif item.kind == "nlhdr" then
            -- Everything below this divider fails its load conditions on this character.
            row.name:SetText("NOT LOADED  (" .. (item.count or 0) .. ")")
            PaintRailRow(row, false, "label")
        elseif item.kind == "clhdr" then
            -- By class: the layouts below hold to this class, which is not this character's
            row.name:SetText("|c" .. RailClassHex(item.tag) .. RailClassName(item.tag):upper()
                .. "  (" .. (item.count or 0) .. ")|r")
            PaintRailRow(row, false, "label")
        elseif item.kind == "clsub" then
            -- By class, inside a layout: one class's items, folding like NOT LOADED
            row.guide:Show()
            row.chev:Show()
            row.chev:ClearAllPoints()
            row.chev:SetPoint("LEFT", 20, 0)
            row.chev:SetDown(not item.shut)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 36, 0)
            row.name:SetPoint("RIGHT", -8, 0)
            row.name:SetText("|c" .. RailClassHex(item.tag) .. RailClassName(item.tag):upper()
                .. "  (" .. (item.count or 0) .. ")|r")
            PaintRailRow(row, false, "label")
            local key = item.key
            row:SetScript("OnClick", function()
                local u = Store.UI()
                u.nlShut = u.nlShut or {}
                u.nlShut[key] = (not item.shut) or nil
                RefreshAll()
            end)
        elseif item.kind == "gsub" then
            -- NOT LOADED inside a group, one step in from the layout's; a click
            -- folds or opens it. By class says OTHER CLASSES when every member
            -- in it holds to another single class.
            row.guide:Show()
            row.chev:Show()
            row.chev:ClearAllPoints()
            row.chev:SetPoint("LEFT", 36, 0)
            row.chev:SetDown(not item.shut)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 52, 0)
            row.name:SetPoint("RIGHT", -8, 0)
            row.name:SetText((item.others and "OTHER CLASSES  (" or "NOT LOADED  (") .. (item.count or 0) .. ")")
            PaintRailRow(row, false, "label")
            local gid = item.rec.id
            row:SetScript("OnClick", function()
                local u = Store.UI()
                u.nlOpen = u.nlOpen or {}
                u.nlOpen[gid] = item.shut and true or false
                RefreshAll()
            end)
        elseif item.kind == "hidden" then
            -- where a View left rows out, how many
            local depth = item.depth or 0
            if depth > 0 then row.guide:Show() end
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", (depth == 2 and 36) or (depth == 1 and 20) or 8, 0)
            row.name:SetPoint("RIGHT", -8, 0)
            local what = ""
            if item.layouts then what = (item.count == 1) and " layout" or " layouts" end
            row.name:SetText("+" .. (item.count or 0) .. what
                .. ((RailView() == "char") and " not loaded here" or " for other classes"))
            PaintRailRow(row, false, "label")
        elseif item.kind == "nlsub" then
            -- the same divider inside a layout, at the children's indent; a
            -- click folds or opens it
            row.guide:Show()
            row.chev:Show()
            row.chev:ClearAllPoints()
            row.chev:SetPoint("LEFT", 20, 0)
            row.chev:SetDown(not item.shut)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 36, 0)
            row.name:SetPoint("RIGHT", -8, 0)
            row.name:SetText("NOT LOADED  (" .. (item.count or 0) .. ")")
            PaintRailRow(row, false, "label")
            local lid = item.rec.id
            row:SetScript("OnClick", function()
                local u = Store.UI()
                u.nlShut = u.nlShut or {}
                u.nlShut[lid] = (not item.shut) or nil
                RefreshAll()
            end)
        elseif item.kind == "group" then
            local rec = item.rec
            row.thumb:SetGroup(Options.GROUP_COLORS[rec.groupKind] or YELLOW)
            Child(row, rec, 20)
            GroupPill(row.pill, rec.groupKind)
            PillRight(row)
            row.lock:ClearAllPoints()
            row.lock:SetPoint("RIGHT", row.eye, "LEFT", -2, 0)
            Options.PaintLock(row.lock, rec)
            row.name:SetPoint("RIGHT", row.lock, "LEFT", -3, 0)
            -- an open group with one of its icons (or reminders) in the editor
            -- lights that row instead
            local si = (ui.grpMode == "ico" and ui.selIconId and Store.Get(ui.selIconId))
                or (ui.grpMode == "rem" and ui.selRemId and Store.Get(ui.selRemId))
            local iconSel = si and si.groupId == rec.id
            PaintRailRow(row, ui.selType == "group" and ui.selId == rec.id and not (item.open and iconSel), "child")
            -- the chevron sits on the tree line, in the guide's place
            if (item.count or 0) > 0 or item.rem then
                row.guide:Hide()
                row.chev:Show()
                row.chev:ClearAllPoints()
                row.chev:SetPoint("CENTER", row, "LEFT", 11, 0)
                row.chev:SetDown(item.open == true)
            end
            -- a click opens or closes it, like a layout, and edits the group itself
            row:SetScript("OnClick", function()
                ExpandedSet()[rec.id] = not ExpandedSet()[rec.id] or nil
                ui.grpMode = "grp"
                Options.Select("group", rec.id)
            end)
            RailDD.Make(row)
        elseif item.kind == "groupicon" then
            local rec, g = item.rec, item.group
            row.thumb:SetIcon(Factory.GetTexture(rec))
            Child(row, rec, 36)
            row.pill:Set(Options.IconPillText(rec.kind))
            PillRight(row)
            PaintRailRow(row, ui.selType == "group" and ui.selId == g.id and ui.grpMode == "ico"
                and ui.selIconId == rec.id, "child")
            row:SetScript("OnClick", function() Options.SelectIconHome(rec) end)
            RailDD.Make(row)
        elseif item.kind == "reminder" then
            -- a Reminder group's member: no eye (nothing of its own is drawn)
            -- and no drag (a reminder never leaves its group)
            local rec, g = item.rec, item.group
            row.thumb:SetIcon(Factory.GetTexture(rec))
            Child(row, rec, 36)
            row.eye:Hide()
            row.pill:Set("Reminder", Options.GROUP_COLORS.reminder)
            PillRight(row)
            PaintRailRow(row, ui.selType == "group" and ui.selId == g.id and ui.grpMode == "rem"
                and ui.selRemId == rec.id, "child")
            row:SetScript("OnClick", function() Options.SelectIconHome(rec) end)
        elseif item.kind == "addrem" then
            row.guide:Show()
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 36, 0)
            row.name:SetPoint("RIGHT", -8, 0)
            row.name:SetText("+ Add Reminder")
            PaintRailRow(row, false, "add")
            local g = item.rec
            row:SetScript("OnClick", function() Options.OpenAdd(g.layoutId, g.id) end)
        elseif item.kind == "bar" then
            local rec = item.rec
            row.thumb:SetBar(rec, 22, BarTexture(rec))
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
            -- lit while its chooser shows
            PaintRailRow(row, ui.selType == "newlayout", "addbtn")
            row:SetScript("OnClick", function() Options.Select("newlayout") end)
        end
        -- Ctrl and Shift clicks select several rows (UI\AD_MultiSelect.lua)
        if MS then MS.RailRow(row, item, i) end
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
    if w > 0 then lf:SetWidth(w - AT.ScrollExtra()) end
    lf:SetHeight(math.max(1, h))
    host:UpdateScroll()
    local key = tostring(ui.selType) .. ":" .. tostring(ui.selId) .. ":" .. tostring(ui.selIconId)
        .. ":" .. tostring(ui.selRemId)
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
    h.name:SetFont(AT.FONT, 15, "")
    h.name:SetPoint("LEFT", 4, 0)
    h.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    h.sub = h:CreateFontString(nil, "OVERLAY")
    h.sub:SetFont(AT.FONT, 10, "")
    h.sub:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    h.chip1 = HeaderChip(h)
    h.chip2 = HeaderChip(h)
    h.chip1:SetPoint("LEFT", h.name, "RIGHT", 8, 0)
    h.chip2:SetPoint("LEFT", h.chip1, "RIGHT", 5, 0)
    h.sub:SetPoint("LEFT", h.chip2, "RIGHT", 8, 0)
    h.name:SetWordWrap(false)
    h.sub:SetWordWrap(false)
    -- h._btns: the pane's buttons at the header's right, for Options.FitHeader
    h._fitHid = {}
    h:SetScript("OnSizeChanged", function(s) Options.FitHeader(s) end)
    return h
end

-- A pane header gives way before its buttons when the pane is narrow: the sub
-- line goes first, then the chips, then the name shortens. Pane refreshes call
-- it after setting the texts; a resize calls it too.
function Options.FitHeader(h)
    local w = h:GetWidth() or 0
    if w <= 0 then return end
    local room = w - 4 - 10
    for _, b in ipairs(h._btns or {}) do room = room - b:GetWidth() - 5 end
    -- what the last fit hid comes back first
    for r in pairs(h._fitHid) do r:Show() end
    wipe(h._fitHid)
    local parts = { { h.chip1, 8 }, { h.chip2, 5 }, { h.sub, 8 } }
    local nw = (h.name.GetUnboundedStringWidth and h.name:GetUnboundedStringWidth())
        or h.name:GetStringWidth() or 0
    local used = nw
    for _, p in ipairs(parts) do
        local r = p[1]
        p[3] = (r:GetObjectType() == "FontString" and r.GetUnboundedStringWidth
            and r:GetUnboundedStringWidth()) or r:GetWidth() or 0
        if r:IsShown() then used = used + p[2] + p[3] end
    end
    for i = #parts, 1, -1 do
        if used <= room then break end
        local r = parts[i][1]
        if r:IsShown() then
            used = used - parts[i][2] - parts[i][3]
            r:Hide()
            h._fitHid[r] = true
        end
    end
    h.name:SetWidth(used > room and math.max(40, nw - (used - room)) or 0)
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
    row.name:SetFont(AT.FONT, 12, "")
    row.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    row.pill = KindPill(row)
    row.pill:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.sub = row:CreateFontString(nil, "OVERLAY")
    row.sub:SetFont(AT.FONT, 10, "")
    row.sub:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row.edit = AT.MakeSmallButton(row, "Edit", 46)
    row.edit:SetHeight(20)
    row.del = AT.MakeQuietButton(row, "Delete", 56)
    row.del:SetHeight(20)
    row.del:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
    row.badge = row:CreateFontString(nil, "OVERLAY")
    row.badge:SetFont(AT.FONT, 9, "")
    row.badge:SetPoint("RIGHT", row.del, "LEFT", -8, 0)
    row.badge:SetTextColor(SHR[1], SHR[2], SHR[3])
    row.capsule = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.capsule:SetPoint("TOPLEFT", 10, -32)
    row.capsule:SetPoint("BOTTOMRIGHT", -8, 8)
    row.more = row.capsule:CreateFontString(nil, "OVERLAY")
    row.more:SetFont(AT.FONT, 10, "")
    row.more:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row.empty = row.capsule:CreateFontString(nil, "OVERLAY")
    row.empty:SetFont(AT.FONT, 10, "")
    row.empty:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row.empty:SetText("Nothing here yet - add the first icon")
    row.caps = {}
    layoutRowPool[i] = row
    return row
end

-- shape a pooled card: strip = true (header over the member well) or false
-- (leading art tile). Returns the card height.
local function ShapeCard(row, strip, color, thumbed, thumbW)
    color = AT.Mute(color)
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
                    GameTooltip:AddLine(s._rec.type == "reminder" and "Click to edit this reminder"
                        or "Click to edit this icon", 0.75, 0.82, 0.92)
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
        b.fs:SetFont(AT.FONT, 15, "")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText("+")
        b.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
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
    t.name:SetFont(AT.FONT, 11, "")
    t.name:SetPoint("BOTTOMLEFT", 5, 10)
    t.name:SetPoint("BOTTOMRIGHT", -5, 10)
    t.name:SetJustifyH("CENTER")
    t.name:SetWordWrap(false)
    t.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    t.x = CreateFrame("Button", nil, t)
    t.x:SetSize(16, 18)
    t.x:SetPoint("TOPRIGHT", -2, -5)
    t.x.fs = t.x:CreateFontString(nil, "OVERLAY")
    t.x.fs:SetFont(AT.FONT, 13, "")
    t.x.fs:SetPoint("CENTER", 0, 1)
    t.x.fs:SetText("x")
    -- always shown, top right, red; brighter under the cursor
    local red, hot = { 0.86, 0.33, 0.33 }, { 1, 0.5, 0.5 }
    t.x.fs:SetTextColor(red[1], red[2], red[3])
    t.x:SetScript("OnEnter", function(self)
        self.fs:SetTextColor(hot[1], hot[2], hot[3])
    end)
    t.x:SetScript("OnLeave", function(self)
        self.fs:SetTextColor(red[1], red[2], red[3])
    end)
    t.x:SetScript("OnClick", function()
        AT.CloseDropdown()
        if t._rec then Options.ConfirmDelete(t._rec) end
    end)
    AT.Tooltip(t.x, "Delete", function()
        return "Delete " .. ((t._rec and t._rec.name) or "this") .. " from the layout. You are asked to confirm first."
    end)
    t.eye = Options.MakeEye(t)
    t.eye:SetPoint("TOPLEFT", 2, -5)
    -- a group's tile only (FillLayoutTile)
    t.lock = Options.MakeLock(t)
    t.lock:SetPoint("LEFT", t.eye, "RIGHT", 0, 0)
    -- hover: the border lights while the cursor is anywhere on the tile, its
    -- buttons included (IsMouseOver covers the children, so moving onto the X
    -- or the eye never flickers it away)
    function t.Hot(on)
        if on then
            t:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            t:SetAlpha(1)
        else
            t:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
            t:SetAlpha(t._alpha or 1)
        end
        -- a group's lock shows while the tile is hovered
        Options.PaintLock(t.lock, t.lock._rec)
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
    for _, b in ipairs({ t.x, t.eye, t.lock }) do
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
        local rem = rec.groupKind == "reminder"
        color = Options.GROUP_COLORS[rec.groupKind] or YELLOW
        local icons = rem and Store.GroupMembers(rec) or Store.IconsOf(rec)
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
        local word = rem and "reminder" or "icon"
        kindLine = (aura and "Aura group" or (rem and "Reminder group") or "CD group") .. "  -  "
            .. (#icons == 1 and ("1 " .. word) or (#icons .. " " .. word .. "s"))
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
        kindLine = (rec.barKind == "text") and "Text element" or (rec.barKind == "texture") and "Texture"
            or (rec.barKind == "wheel") and "Wheel" or (rec.barKind == "sound") and "Sound"
            or (text:find("Bar") and text or (text .. " bar"))
        t._open = function() Options.Select("bar", rec.id) end
    end
    color = AT.Mute(color)
    t.stripe:SetColorTexture(color[1], color[2], color[3], 0.85)
    t.name:SetText(rec.name or "?")
    -- Not loaded here: the eye says so, so the tile keeps full alpha.
    local loaded = Store.IsLoaded(rec)
    t._alpha = 1
    Options.PaintEye(t.eye, rec)
    local group = rec.type == "group"
    Options.PaintLock(t.lock, group and rec or nil)
    local how = {}
    if loaded then how[#how + 1] = "the eye hides it on screen while you edit" end
    if group then how[#how + 1] = "the lock keeps it from moving" end
    how[#how + 1] = "the red x deletes it"
    local tail = table.concat(how, ", ") .. "."
    t._tip = kindLine .. "\nLoad conditions: " .. (Store.BadgeText(rec))
        .. (loaded and "" or "  -  not loaded on this character. Its eye shows it while you edit")
        .. "\nClick to edit it. " .. tail:sub(1, 1):upper() .. tail:sub(2)
    t.Hot(false)
end

-- Lays members out as tiles (default: all the layout's) from tile number
-- `first` of the shared pool and from y0 down; returns the y under the grid
-- and the last tile number used. Tiles past it hide; a later call re-shows
-- the ones it takes.
function Options.FlowLayoutTiles(layout, width, members, first, y0)
    local T = Options.LAYOUT_TILE
    local cols = Options.LayoutTileCols(width)
    first, y0 = first or 1, y0 or 0
    local n, k = first - 1, 0
    for _, m in ipairs(members or Store.MembersOf(layout)) do
        n, k = n + 1, k + 1
        local t = Options.LayoutTile(n)
        Options.FillLayoutTile(t, m)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", ((k - 1) % cols) * (T.w + T.gap),
            y0 - math.floor((k - 1) / cols) * (T.h + T.gap))
        t:Show()
    end
    local pool = layoutPane.tilePool or {}
    for i = n + 1, #pool do pool[i]:Hide() end
    -- the width these columns were flowed for: the pane's resize handler
    -- re-flows only when a new width changes the column count
    layoutPane._tileW = width
    return y0 - math.ceil(k / cols) * (T.h + T.gap), n
end

-- The Tiles view's add tile, built once: it takes the cell after the loaded
-- members, where the Cards view keeps the full-width add row.
function Options.LayoutAddTile()
    local t = layoutPane.addTile
    if t then return t end
    local T = Options.LAYOUT_TILE
    local green, dark = { 0.482, 0.847, 0.561 }, { 0.18, 0.34, 0.24 }
    t = CreateFrame("Button", nil, layoutPane.cardsContent, "BackdropTemplate")
    t:SetSize(T.w, T.h)
    AT.Skin(t, COL.well, dark)
    t._adAddTile = true
    t.plus = t:CreateFontString(nil, "OVERLAY")
    t.plus:SetFont(AT.FONT, 26, "")
    t.plus:SetPoint("CENTER", 0, 8)
    t.plus:SetTextColor(green[1], green[2], green[3])
    t.plus:SetText("+")
    t.name = t:CreateFontString(nil, "OVERLAY")
    t.name:SetFont(AT.FONT, 11, "")
    t.name:SetPoint("BOTTOMLEFT", 5, 10)
    t.name:SetPoint("BOTTOMRIGHT", -5, 10)
    t.name:SetJustifyH("CENTER")
    t.name:SetTextColor(green[1], green[2], green[3])
    t.name:SetText("Add")
    t:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(green[1], green[2], green[3], 1) end)
    t:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(dark[1], dark[2], dark[3], 1) end)
    t:SetScript("OnClick", function()
        AT.CloseDropdown()
        local layout = SelLayout()
        if layout then Options.OpenAdd(layout.id) end
    end)
    -- hooked after the SetScript calls above, or they would replace it
    AT.Tooltip(t, "Add to this layout", "Add an icon, bar or group to this layout.")
    layoutPane.addTile = t
    return t
end

-- The NOT LOADED header of the layout pane's list, built once. A click folds
-- the section here and in the sidebar alike (Store.UI().nlShut, per layout).
function Options.LayoutNLHeader()
    local h = layoutPane.nlHead
    if h then return h end
    h = CreateFrame("Button", nil, layoutPane.cardsContent)
    h:SetHeight(22)
    h.chev = AT.MakeChevron(h)
    h.chev:SetPoint("LEFT", 7, 0)
    h.fs = h:CreateFontString(nil, "OVERLAY")
    h.fs:SetFont(AT.FONT, 11, "")
    h.fs:SetPoint("LEFT", h.chev, "RIGHT", 6, 0)
    local function paint(c)
        h.fs:SetTextColor(c[1], c[2], c[3])
        h.chev:SetColor(c)
    end
    paint(COL.dim)
    h:SetScript("OnEnter", function() paint(COL.ink) end)
    h:SetScript("OnLeave", function() paint(COL.dim) end)
    h:SetScript("OnClick", function()
        AT.CloseDropdown()
        local lid = h._lid
        if not lid then return end
        local u = Store.UI()
        u.nlShut = u.nlShut or {}
        u.nlShut[lid] = (not u.nlShut[lid]) or nil
        if RefreshAll then RefreshAll() end
    end)
    layoutPane.nlHead = h
    return h
end

local function RefreshLayoutPane()
    local layout = SelLayout()
    if not layout then return end
    layoutHeader.name:SetText(layout.name)
    local btext, restricted = Store.BadgeText(layout)
    layoutHeader.chip1:Set(btext, restricted and PURPLE or SHR)
    layoutHeader.chip2:Set("layout", COL.dim)
    layoutHeader.sub:SetText("")
    Options.FitHeader(layoutHeader)

    -- the pane's own width is unresolved on the first pass after a build:
    -- fall back to the window (explicit size, always real)
    local host, cardsContent = layoutPane.cardsHost, layoutPane.cardsContent
    local cardW = host:GetWidth() or 0
    if cardW < 100 then
        cardW = (win:GetWidth() or 1020) - ((rail and rail:IsShown()) and rail:GetWidth() or 18) - 37
    end
    cardW = cardW - AT.ScrollExtra()
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
        local rem = g.groupKind == "reminder"
        local col = Options.GROUP_COLORS[g.groupKind] or YELLOW
        local row = Card(true, col, true)
        row.name:SetText(g.name)
        local icons = rem and Store.GroupMembers(g) or Store.IconsOf(g)
        row.thumb:SetGroup(col)
        if rem then
            row.sub:SetText("Reminder group  -  " .. (#icons == 1 and "1 reminder" or (#icons .. " reminders")))
        else
            row.sub:SetText("Group  -  " .. (#icons == 1 and "1 icon" or (#icons .. " icons")))
        end
        GroupPill(row.pill, g.groupKind)
        FillCapsule(row, icons, (aura and { 0.29, 0.23, 0.42 })
            or (g.groupKind == "reminder" and { 0.40, 0.17, 0.40 }) or { 0.35, 0.29, 0.16 },
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
        local what = (ic.kind == "item" and d.itemID and Options.ItemWords(d))
            or (ic.kind == "trinket" and d.slotID and ("trinket slot " .. d.slotID))
            or (ic.kind == "totem" and Options.TotemWhat(d))
            or (ic.kind == "enchant" and ((d.hand == "off") and "off-hand enchant" or "main-hand enchant"))
            or (ic.kind == "ammo" and "equipped ammo")
            or (ic.kind == "aura" and d.spellID and Options.AuraSummary(d))
            or (ic.kind == "timer" and Options.CustomWhat and Options.CustomWhat(ic))
            or (ic.kind == "special" and Options.SpecialWhat and Options.SpecialWhat(ic))
            or (ic.kind == "groupbuff" and d.spellID and ("who has buff " .. d.spellID))
            or (ic.kind == "stance" and Options.StanceWhat and Options.StanceWhat(ic))
            or (ic.kind == "spell" and d.spellID and Store.HasSpellAlts(d)
                and ("spells " .. d.spellID .. " +" .. #d.spellAlts))
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
            row.sub:SetText(Options.CustomWhat and Options.CustomWhat(b)
                or ("Timer bar  -  " .. tostring(d.duration or "?") .. "s"))
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
        elseif b.barKind == "range" then
            local RBm = NS.RangeBars
            row.sub:SetText("Range bar  -  " .. (RBm and RBm.Describe(b) or "target range"))
        elseif b.barKind == "text" then
            row.sub:SetText("Text  -  " .. (Options.TextWhat and Options.TextWhat(b) or "text"))
        elseif b.barKind == "texture" then
            row.sub:SetText("Texture  -  " .. (Options.TextureWhat and Options.TextureWhat(b) or "texture"))
        elseif b.barKind == "wheel" then
            row.sub:SetText("Wheel  -  " .. (Options.WheelWhat and Options.WheelWhat(b) or "wheel"))
        elseif b.barKind == "sound" then
            row.sub:SetText("Sound  -  " .. (Options.SoundWhat and Options.SoundWhat(b) or "sound"))
        elseif b.barKind == "special" then
            row.sub:SetText("Deck bar  -  " .. (Options.SpecialBarWhat and Options.SpecialBarWhat(b) or "Arc Proc"))
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
    -- In a layout that loads here, members that do not load here follow the
    -- add row under their own NOT LOADED header, as in the sidebar.
    local members = Store.MembersOf(layout)
    local layoutLoaded = Store.IsLoaded(layout)
    local loadedM, laterM = {}, {}
    for _, m in ipairs(members) do
        if (not layoutLoaded) or Store.IsLoaded(m) then
            loadedM[#loadedM + 1] = m
        else
            laterM[#laterM + 1] = m
        end
    end
    local shutSet = Store.UI().nlShut
    local shut = shutSet ~= nil and shutSet[layout.id] == true
    local function CardFor(m)
        if m.type == "group" then
            GroupCard(m)
        elseif m.type == "icon" then
            IconCard(m)
        else
            BarCard(m)
        end
    end
    local lastTile = 0
    local addTile = Options.LayoutAddTile()
    if tiles then
        y, lastTile = Options.FlowLayoutTiles(layout, cardW, loadedM)
        -- the add tile takes the next cell of the same grid
        local T, cols, k = Options.LAYOUT_TILE, Options.LayoutTileCols(cardW), #loadedM
        addTile:ClearAllPoints()
        addTile:SetPoint("TOPLEFT", (k % cols) * (T.w + T.gap), -math.floor(k / cols) * (T.h + T.gap))
        addTile:Show()
        y = -math.ceil((k + 1) / cols) * (T.h + T.gap)
        layoutAddRow:Hide()
    else
        addTile:Hide()
        for _, m in ipairs(loadedM) do CardFor(m) end
        layoutAddRow:ClearAllPoints()
        layoutAddRow:SetPoint("TOPLEFT", 0, y)
        layoutAddRow:SetPoint("TOPRIGHT", -4, y)
        layoutAddRow:Show()
        y = y - 34
    end

    local head = Options.LayoutNLHeader()
    if #laterM > 0 then
        head._lid = layout.id
        head.fs:SetText("NOT LOADED  (" .. #laterM .. ")")
        head.chev:SetDown(not shut)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", 0, y)
        head:SetPoint("TOPRIGHT", -4, y)
        head:Show()
        y = y - 28
        if not shut then
            if tiles then
                y, lastTile = Options.FlowLayoutTiles(layout, cardW, laterM, lastTile + 1, y)
            else
                for _, m in ipairs(laterM) do CardFor(m) end
            end
        end
    else
        head:Hide()
    end
    if not tiles then
        for _, t in ipairs(layoutPane.tilePool or {}) do t:Hide() end
    end
    -- the Tiles view hides every card; the Cards view only the spare ones
    for i = (tiles and 1 or n + 1), #layoutRowPool do layoutRowPool[i]:Hide() end
    n = #members

    -- Natural height; PlaceList applies the cap, the saved height and the fold.
    cardsContent:SetHeight(math.max(1, -y))
    layoutPane.listNatural = -y
    layoutPane.contentsLabel:SetText("CONTENTS  -  " .. n .. (n == 1 and " element" or " elements")
        .. (Options.ListFolded() and "  (folded)" or ""))
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
                    if g.id ~= rec.groupId and Store.GroupTakes(g, rec.kind) then
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
    local edge, placed = opts.rightOf, {}
    local function Place(b)
        if edge then
            b:SetPoint("RIGHT", edge, "LEFT", -5, 0)
        else
            b:SetPoint("RIGHT", host, "RIGHT", -6, 0)
        end
        edge = b
        placed[#placed + 1] = b
    end
    local function Btn(label, w, tip)
Options.BuildYield()
        local b = AT.MakeSmallButton(host, label, w)
        b:SetHeight(18)
        b.fs:SetFont(AT.FONT, 9, "")
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
    box:SetFont(AT.FONT, 12, "")
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
    -- Options.FitBand lays these out for the band's width; btns in reading order.
    local btns = {}
    for i = #placed, 1, -1 do btns[#btns + 1] = placed[i] end
    btns[#btns + 1] = opts.rightOf
    nameFS:SetWordWrap(false)
    local row = opts.row or host
    host._adBand = { row = row, host = host, name = nameFS, box = box, btns = btns,
        extra = opts.hide or {}, lead = opts.lead or 10, top = opts.top or 26, h = row._h }
    return ren
end

-- The band's actions sit right of the name while both fit; past that they drop
-- to lines under it, right-aligned, and the name shortens to fit. Runs from the
-- band row's _sync, before the page reads the row's height.
function Options.FitBand(band)
    local row, host, name, top = band.row, band.host, band.name, band.top
    local pg = row._pg
    local w = ((pg and pg:GetWidth()) or 0) - 4
    if w < 60 then
        -- not laid out yet: the page passes again next frame
        if pg then pg._sizeUnresolved = true end
        return
    end
    local GAP, EDGE, LINE = 5, 6, 22
    local acts = -GAP
    for _, b in ipairs(band.btns) do acts = acts + b:GetWidth() + GAP end
    local tail = 0
    for _, r in ipairs(band.extra) do
        local rw = (r:GetObjectType() == "FontString" and r.GetUnboundedStringWidth
            and r:GetUnboundedStringWidth()) or r:GetWidth() or 0
        if rw > 0 then tail = tail + rw + 8 end
    end
    local nw = (name.GetUnboundedStringWidth and name:GetUnboundedStringWidth())
        or name:GetStringWidth() or 0
    local room = w - band.lead - EDGE
    local one = nw + tail + 16 + acts <= room
    local lines = { band.btns }
    if not one then
        -- filled in reading order, a new line when the next would not fit
        lines = {}
        local cur, cw, span = {}, 0, w - 2 * EDGE
        for _, b in ipairs(band.btns) do
            local bw = b:GetWidth()
            if #cur > 0 and cw + GAP + bw > span then
                lines[#lines + 1] = cur
                cur, cw = {}, 0
            end
            cw = (#cur > 0) and (cw + GAP + bw) or bw
            cur[#cur + 1] = b
        end
        lines[#lines + 1] = cur
    end
    for j, line in ipairs(lines) do
        local y = one and -top / 2 or -(top - 2 + (j - 1) * LINE + LINE / 2)
        local x = -EDGE
        for k = #line, 1, -1 do
            local b = line[k]
            b:ClearAllPoints()
            b:SetPoint("RIGHT", host, "TOPRIGHT", x, y)
            x = x - b:GetWidth() - GAP
        end
    end
    local fit = math.max(40, (one and (room - acts - 16) or room) - tail)
    name:SetWidth(nw > fit and fit or 0)
    -- the rename box keeps to the name's line
    local box = band.box
    box:ClearAllPoints()
    box:SetPoint("LEFT", name, "LEFT", -6, 0)
    if one then
        box:SetPoint("RIGHT", band.btns[1], "LEFT", -10, 0)
    else
        box:SetPoint("RIGHT", host, "TOPRIGHT", -EDGE, -top / 2)
    end
    local h = band.h + (one and 0 or #lines * LINE)
    if row._h ~= h then
        row._h = h
        row:SetHeight(h)
    end
end

-- Position rows: X / Y sliders for layouts (from the screen centre) and for
-- groups, bars and free icons (from their layout's centre). They edit rec.pos,
-- the numbers a drag on screen writes, unless anchoredFn(rec) is true.
function Options.PosRows(pg, ctx, vis, anchoredFn)
    -- An anchored thing is placed by its anchor offsets, so the sliders edit
    -- those (the numbers its Anchor panel shows) and X / Y always move it.
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
Options.depsGen = 0
if NS.Events and NS.Events.OnMessage then
    NS.Events.OnMessage("AD_DIRTY", "adanchoredhere", function() Options.depsGen = Options.depsGen + 1 end)
end
function Options.AnchoredHereRows(pg, ctx, vis)
    -- Every row asks, for its place and its words: one walk of the records per
    -- frame and record serves them all; a store change starts a new one.
    local cache, cacheRec, cacheAt, cacheGen
    local function Deps()
        local r = ctx()
        if not (r and NS.Anchor and NS.Anchor.DependentsOf) then return {} end
        local t = GetTime()
        if cacheRec ~= r or cacheAt ~= t or cacheGen ~= Options.depsGen then
            cache, cacheRec, cacheAt, cacheGen = NS.Anchor.DependentsOf(r), r, t, Options.depsGen
        end
        return cache
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
        Options.BuildYield()
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
        AT.Tooltip(b, "Edit", "Opens it. The Anchor panel on its Position tab holds the link back to this one.")
    end
end

-- The point, offset and match rows every anchor panel draws, in this order. A
-- family draws the ones its anchor section declares and does not hide.
Options.ANCHOR_ROW_FIELDS = {
    "anchorSrcPoint", "anchorDstPoint", "anchorOffsetX", "anchorOffsetY",
    "anchorMatchWidth", "anchorMatchWidthAdjust", "anchorMatchHeight", "anchorMatchHeightAdjust",
}

-- The anchor list (Core\AD_Anchor.lua slots): one row per anchor, tried top
-- to bottom. A row holds its pick, a Named frame's name box, the crosshair
-- (pick it on screen), a word for whether it holds the record now, and, while
-- the first pick can have a list, move up / move down / remove. A spell pin's
-- rows sit under the first anchor.
Options.ANCHOR_SLOT_STATES = {
    use = { text = "In use", col = { 0.48, 0.85, 0.56 } },
    there = { text = "On screen", col = COL.dim },
    away = { text = "Not there", col = COL.faint },
}
Options.ANCHOR_SLOT_BUSY = { text = "Not in combat", col = COL.faint }
Options.ANCHOR_LIST_NOTE = "It sits on the first one that is on screen, top to bottom."
local SLOT_DD_W, SLOT_NAME_W, SLOT_BTN, SLOT_CHIP_W = 200, 140, 20, 76

-- a square raised button for a glyph; a disabled one dims and takes no hover
local function SlotButton(row, tip, body)
    local b = AT.MakeSmallButton(row, "", SLOT_BTN)
    b:SetSize(SLOT_BTN, SLOT_BTN)
    local enter = b:GetScript("OnEnter")
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then enter(self) end end)
    AT.Tooltip(b, tip, body)
    return b
end
local function SlotEnable(b, on)
    b:SetEnabled(on)
    b:SetAlpha(on and 1 or 0.35)
end
-- the crosshair: four ticks round a dot
local function Crosshair(b)
    local c = COL.dim
    for _, d in ipairs({ { 0, 5, 2, 4 }, { 0, -5, 2, 4 }, { 5, 0, 4, 2 }, { -5, 0, 4, 2 }, { 0, 0, 2, 2 } }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:SetSize(d[3], d[4])
        t:SetPoint("CENTER", d[1], d[2])
    end
end

-- the pinned frames' rows draw with the same glyph buttons (UI\AD_PinOptions.lua)
Options.SlotButton, Options.SlotEnable, Options.Crosshair = SlotButton, SlotEnable, Crosshair

local function SlotRow(pg, family, sec, ctx, vis, s)
    local function An() return NS.Anchor end
    local shows = function()
        local r, A = ctx(), An()
        return vis() and r ~= nil and A ~= nil and s <= A.SlotCount(r)
    end
    local row = AT.AddRow(pg, AT.LAY.rowH, shows)
    local lbl = AT.RowLabel(row, "Anchor " .. s)
    local dd = AT.MakeDropdown(win, row, SLOT_DD_W,
        function()
            local r, A = ctx(), An()
            if not (r and A) then return { { value = "none", text = "None (free position)" } } end
            return A.SlotChoices(r, s)
        end,
        function()
            local r, A = ctx(), An()
            if not (r and A) then return "none" end
            return (A.SlotGet(r, s))
        end,
        function(v)
            local r, A = ctx(), An()
            if r and A then A.SlotSet(r, s, v) end
        end,
        function() AT.LayoutPage(pg) end)
    row._colLabel, row._colCtrl = lbl, dd
    AT.Tooltip(dd, "Anchor " .. s, (s == 1)
        and "What it anchors to. Anchors added after it are tried in order while it is not on screen."
        or "Used while the anchors above it are not on screen, with the same points and offsets.")

    -- a Named frame's name, on the row
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetSize(SLOT_NAME_W, 18)
    box:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    AT.Skin(box, COL.well, COL.line)
    box:SetFont(AT.FONT, 11, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetAutoFocus(false)
    local hint = box:CreateFontString(nil, "OVERLAY")
    hint:SetFont(AT.FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetPoint("RIGHT", -6, 0)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("e.g. PlayerFrame")
    local function syncHint() hint:SetShown((box:GetText() or "") == "") end
    local function saved()
        local r, A = ctx(), An()
        return (r and A) and select(2, A.SlotGet(r, s)) or ""
    end
    box:SetScript("OnTextChanged", syncHint)
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function() AT.BoxText(box, saved()); box:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function()
        box:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    box:SetScript("OnEditFocusLost", function()
        box:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        local r, A = ctx(), An()
        if r and A then Store.SetOverride(r, "anchor", A.SlotNameKey(s), box:GetText() or "") end
        AT.LayoutPage(pg)
    end)
    AT.Tooltip(box, "Frame name", "The global name of a frame, e.g. ElvUF_Player. A frame that does not exist counts as not there.")

    local pick = SlotButton(row, "Pick Frame",
        "Hover a frame on screen, a game frame or one of your Arc Auras items, and click it. Right-click or Esc cancels.")
    Crosshair(pick)
    pick:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r, FP = ctx(), NS.FramePicker
        if not (r and FP) then return end
        if not FP.PickSlot(r, s, function() AT.LayoutPage(pg) end) then
            row._adNoCombat = true
            row._sync()
            C_Timer.After(2, function()
                row._adNoCombat = nil
                row._sync()
            end)
        end
    end)

    local chip = CreateFrame("Frame", nil, row, "BackdropTemplate")
    chip:SetSize(SLOT_CHIP_W, 16)
    chip:SetPoint("LEFT", pick, "RIGHT", 6, 0)
    AT.Skin(chip, { 0, 0, 0, 0 }, COL.line)
    chip.fs = chip:CreateFontString(nil, "OVERLAY")
    chip.fs:SetFont(AT.FONT, 10, "")
    chip.fs:SetPoint("CENTER", 0, 0)

    local del = AT.MakeQuietButton(row, "x", SLOT_BTN)
    del:SetSize(SLOT_BTN, SLOT_BTN)
    del:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    AT.Tooltip(del, "Remove", "Takes this anchor off the list.")
    local down = SlotButton(row, "Move down", "Tries it later.")
    down:SetPoint("RIGHT", del, "LEFT", -3, 0)
    local dch = AT.MakeChevron(down)
    dch:SetDir("down")
    dch:SetPoint("CENTER", 0, 0)
    local up = SlotButton(row, "Move up", "Tries it sooner.")
    up:SetPoint("RIGHT", down, "LEFT", -3, 0)
    local uch = AT.MakeChevron(up)
    uch:SetDir("up")
    uch:SetPoint("CENTER", 0, 0)
    local function Act(fn)
        return function()
            AT.CloseDropdown()
            local r, A = ctx(), An()
            if r and A then fn(r, A) end
            AT.LayoutPage(pg)
        end
    end
    up:SetScript("OnClick", Act(function(r, A) A.SlotSwap(r, s - 1, s) end))
    down:SetScript("OnClick", Act(function(r, A) A.SlotSwap(r, s, s + 1) end))
    del:SetScript("OnClick", Act(function(r, A) A.SlotRemove(r, s) end))
    row._adSlot = { dd = dd, box = box, pick = pick, chip = chip, up = up, down = down, del = del }

    row._sync = function()
        dd.Refresh()
        local r, A = ctx(), An()
        if not (r and A) then return end
        local v, nm = A.SlotGet(r, s)
        local isFrame = v == "frame"
        box:SetShown(isFrame)
        if isFrame and not box:HasFocus() then AT.BoxText(box, nm) end
        syncHint()
        pick:ClearAllPoints()
        pick:SetPoint("LEFT", isFrame and box or dd, "RIGHT", 6, 0)
        local word = Options.ANCHOR_SLOT_STATES[A.SlotState(r, s) or ""]
        if row._adNoCombat then word = Options.ANCHOR_SLOT_BUSY end
        chip:SetShown(word ~= nil)
        if word then
            chip.fs:SetText(word.text)
            AT.PaintPill(chip, chip.fs, word.col)
        end
        local list = A.BackupsOK(r)
        up:SetShown(list)
        down:SetShown(list)
        del:SetShown(list)
        if list then
            local n = A.SlotCount(r)
            local above = (s > 1) and (A.SlotGet(r, s - 1)) or nil
            local below = (s < n) and (A.SlotGet(r, s + 1)) or nil
            SlotEnable(up, above ~= nil and A.SlotTakes(r, s - 1, v) and A.SlotTakes(r, s, above))
            SlotEnable(down, below ~= nil and A.SlotTakes(r, s + 1, v) and A.SlotTakes(r, s, below))
        end
    end
    -- the search reads a later slot like a schema row
    local key = "anchorBackup" .. (s - 1)
    if s > 1 and sec and sec.fields[key] then
        row._adMeta = { family = family, section = "anchor", field = key, def = sec.fields[key], baseVis = shows }
    end
    return row
end

-- The note, the slots (a spell pin's rows under the first) and Add.
function Options.AnchorListRows(pg, family, ctx, vis)
    local sec = Schema[family] and Schema[family].anchor
    local listVis = function()
        local r = ctx()
        return vis() and r ~= nil and NS.Anchor ~= nil and NS.Anchor.BackupsOK(r)
    end
    AT.RowDesc(pg, Options.ANCHOR_LIST_NOTE, nil, listVis)
    local n = (NS.Anchor and NS.Anchor.SLOTS) or 4
    for s = 1, n do
Options.BuildYield()
        SlotRow(pg, family, sec, ctx, vis, s)
        if s == 1 and Options.AnchorSpellRows then Options.AnchorSpellRows(pg, ctx, vis) end
    end
    AT.RowButton(pg, "+ Add", function()
        local r = ctx()
        if r and NS.Anchor then NS.Anchor.SlotAdd(r) end
        AT.LayoutPage(pg)
    end, function()
        return listVis() and NS.Anchor.SlotCount(ctx()) < NS.Anchor.SLOTS
    end, 80, "Another anchor")
    -- pick mode ends with the page that started it
    pg:HookScript("OnHide", function()
        if NS.FramePicker then NS.FramePicker.Stop() end
    end)
end

-- Position > Anchor for bars, groups and free icons. One dropdown writes
-- enabled, kind and target together, so a pick is never half applied. fields
-- nil = ANCHOR_ROW_FIELDS as the family's schema declares them. It opens its
-- own section: after a block these rows would land in that block's section.
function Options.AnchorPickRows(pg, family, ctx, vis, fields, note)
    AT.Section(pg, "Anchor to", { visibleFn = vis })
    if note then AT.RowDesc(pg, note, 20, vis) end
    -- the list, then the line saying which anchor holds it now
    Options.AnchorListRows(pg, family, ctx, vis)
    local status = AT.AddRow(pg, 22, vis)
    local fs = status:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
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
    if not fields then
        fields = {}
        local sec = Schema[family] and Schema[family].anchor
        for _, k in ipairs(Options.ANCHOR_ROW_FIELDS) do
            local d = sec and sec.fields[k]
            if d and not d.hidden then fields[#fields + 1] = k end
        end
    end
    SectionRows(pg, family, "anchor", ctx, vis, fields)
    Options.AnchoredHereRows(pg, ctx, vis)
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
        local word = (rec.groupKind == "reminder") and " reminder" or " icon"
        extra = (n > 0) and (" and its " .. n .. word .. (n == 1 and "" or "s")) or ""
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
    addBtn.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    addBtn:SetScript("OnClick", function()
        local layout = SelLayout()
        if layout then Options.OpenAdd(layout.id) end
    end)
    layoutHeader._btns = { addBtn, del, move }

    -- The CONTENTS bar folds the list (cyan underline while folded). The list
    -- is capped and scrolls; the grip under it sets and saves its height.
    local bar = CreateFrame("Button", nil, layoutPane, "BackdropTemplate")
    bar:SetHeight(22)
    bar:SetPoint("TOPLEFT", 0, -36)
    bar:SetPoint("TOPRIGHT", -4, -36)
    AT.Skin(bar, COL.head, COL.line)
    local chev = AT.MakeChevron(bar)
    chev:SetPoint("LEFT", 7, 0)
    chev:SetDown(true)
    local title = bar:CreateFontString(nil, "OVERLAY")
    title:SetFont(AT.FONT, 11, "")
    title:SetPoint("LEFT", chev, "RIGHT", 6, 0)
    title:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
    title:SetText("CONTENTS")
    local rule = bar:CreateTexture(nil, "OVERLAY")
    rule:SetColorTexture(COL.rule[1], COL.rule[2], COL.rule[3], 1)
    rule:SetPoint("BOTTOMLEFT", 1, 1)
    rule:SetPoint("BOTTOMRIGHT", -1, 1)
    rule:SetHeight(1)
    rule:Hide()
    local function paintBar(hot)
        local c = hot and COL.ink or COL.title
        title:SetTextColor(c[1], c[2], c[3])
        chev:SetColor(hot and COL.ink or COL.chev)
        local f = hot and COL.btnHover or COL.head
        bar:SetBackdropColor(f[1], f[2], f[3], 1)
    end
    bar:SetScript("OnEnter", function() paintBar(true) end)
    bar:SetScript("OnLeave", function() paintBar(false) end)
    bar:SetScript("OnClick", function()
        AT.CloseDropdown()
        local folded
        if Store.GetSetting("layoutListFolded") ~= true and Options.OnLookTab() then
            -- folded by the look tab: open (or shut) it for this visit only
            ui.listOnLooks = not ui.listOnLooks or nil
            folded = not ui.listOnLooks
        else
            folded = Store.GetSetting("layoutListFolded") ~= true
            Store.SetSetting("layoutListFolded", folded)
        end
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
        c.fs:SetFont(AT.FONT, 10, "")
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
            s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
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
        if w and w > 0 then cardsContent:SetWidth(w - AT.ScrollExtra()) end
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
        local folded = Options.ListFolded()
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
    layoutAddRow.fs:SetFont(AT.FONT, 11, "")
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
    hd._fs:SetFont(AT.FONT, 12, "")
    -- on the first line: a narrow pane puts the actions on lines under it
    hd._fs:SetPoint("LEFT", hbg, "TOPLEFT", 10, -13)
    hd._fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    hd._chip = KindPill(hbg)
    hd._chip:SetPoint("LEFT", hd._fs, "RIGHT", 8, 0)
    BandActions(hbg, hd._fs, SelLayout, { hide = { hd._chip }, noMove = true, row = hd })
    hd._sync = function()
        local l = SelLayout()
        hd._fs:SetText("Editing:  " .. ((l and l.name) or ""))
        hd._chip:Set("layout", COL.dim)
        Options.FitBand(hbg._adBand)
    end
    -- the layout's last pack update, while it can be undone: what it was,
    -- and the undo, quiet at the end of the line
    local und = AT.AddRow(pg, 26, function()
        local l = SelLayout()
        return l ~= nil and Store.UndoInfo(l.id) ~= nil
    end)
    und._fs = und:CreateFontString(nil, "OVERLAY")
    und._fs:SetFont(AT.FONT, 11, "")
    und._fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    und._fs:SetJustifyH("LEFT")
    und._fs:SetWordWrap(false)
    und._btn = AT.MakeQuietButton(und, "Undo the last update", 140)
    und._btn:SetPoint("RIGHT", -12, 0)
    und._fs:SetPoint("LEFT", 10, 0)
    und._fs:SetPoint("RIGHT", und._btn, "LEFT", -8, 0)
    und._btn:SetScript("OnClick", function()
        AT.CloseDropdown()
        local l = SelLayout()
        if l then Options.ConfirmUndo(l.id) end
    end)
    AT.Tooltip(und._btn, "Undo the last update",
        "Puts back what the update changed, added or removed. Your changes since to the items it changed go too.")
    und._sync = function()
        local l = SelLayout()
        und._fs:SetText((l and Options.UndoNote(l.id)) or "")
    end
    Options._layoutUndoRow = und

    -- The last three are the look tabs, filled by Options.BuildLayoutLooks
    -- once every item editor exists.
    local tabs = { "Position", "Visibility", "Load Conditions",
        "Icon Looks", "Group Looks", "Bar Looks" }
    -- The settings search walks this page's tabs but not the look tabs, whose
    -- rows repeat the item editors' own.
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.layout = { page = pg,
        tabs = { "Position", "Visibility", "Load Conditions" } }
    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel   -- strips inside panel-bodied pages
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local h = tabRow._strip:Set(tabs, ui.layoutTab, function(name)
            local function pick()
                local wasFolded = Options.ListFolded()
                ui.layoutTab = name
                -- leaving Load Conditions offers its changes to the items inside
                if Options.LayoutFollow then Options.LayoutFollow.Sync(Options.LCLayoutId()) end
                -- a look tab folds the element list away: re-place the page under it
                if Options.ListFolded() ~= wasFolded and layoutPane and layoutPane.PlaceList then
                    RefreshLayoutPane()
                else
                    AT.LayoutPage(pg)
                end
            end
            -- a look tab builds with the editors it mirrors, on its first pick
            if name == "Icon Looks" or name == "Group Looks" or name == "Bar Looks" then
                Options.WhenPane("looks", pick)
            else
                pick()
            end
        end)
        -- wrapped chips grow the row (never overlap the content below)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Position tab: the layout's X / Y from the screen centre, the mouse
    -- defaults its icons follow, then what is pinned to it (a layout cannot
    -- be anchored itself). Short enough to stack, so no sub-tabs.
    local layPosVis = function() return ui.layoutTab == "Position" end
    Options.BuildYield()
    AT.Section(pg, "Position", { visibleFn = layPosVis })
    Options.LockRow(pg, SelLayout, layPosVis)
    Options.BuildYield()
    Options.PosRows(pg, SelLayout, layPosVis, nil)
    Options.BuildYield()
    AT.Section(pg, "Mouse", { visibleFn = layPosVis })
    Options.BuildYield()
    AT.RowDesc(pg, "Applies to every icon in this layout; groups and icons can override it.", 20,
        layPosVis)
    Options.BuildYield()
    SectionRows(pg, "layout", "mouse", SelLayout, layPosVis, { "clickThrough", "showTooltip" })
    Options.BuildYield()
    Options.AnchoredHereRows(pg, SelLayout, layPosVis)
    Options.BuildYield()
    AT.Section(pg, nil)
    Options.BuildYield()
    ConditionRows(pg, SelLayout, function() return ui.layoutTab == "Load Conditions" end)
    Options.BuildYield()
    VisibilityRows(pg, SelLayout, function() return ui.layoutTab == "Visibility" end)
    -- the contents tiles, as many as the fullest layout needs, one a slice
    -- here: made by the pane's first refresh, they were one long frame
    local most = 0
    for _, l in ipairs(Store.Layouts()) do most = math.max(most, #Store.MembersOf(l)) end
    for i = 1, most do
        Options.BuildYield()
        Options.LayoutTile(i)
    end
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
    fs:SetFont(AT.FONT, 11, "")
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

-- Bar Looks shows one bar type's blocks at a time; these are the picker's
-- words, in Schema.BAR_KINDS order.
Options.LOOK_BAR_WORDS = { cooldown = "Cooldown bars", aura = "Aura bars", swing = "Swing bars",
    resource = "Resource bars", health = "Health bars", cast = "Castbars", enchant = "Weapon enchant bars",
    range = "Range bars", text = "Texts", texture = "Textures", wheel = "Wheels", special = "Arc Proc bars",
    sound = "Sounds" }

-- The element list folds by itself while a look tab is open, so those pages
-- get the height; the CONTENTS bar still opens it for the visit.
function Options.OnLookTab()
    return ui.layoutTab == "Icon Looks" or ui.layoutTab == "Group Looks" or ui.layoutTab == "Bar Looks"
end
function Options.ListFolded()
    if Store.GetSetting("layoutListFolded") == true then return true end
    return Options.OnLookTab() and not ui.listOnLooks
end

-- A look tab is short: its blocks split by the editor's sub-tabs (b.sub, the
-- same row the item editors show), and Bar Looks by bar type, so one page
-- holds one sub-tab of one type.
function Options.BuildLayoutLooks()
    local pg = layoutEditorPage
    if not pg or pg._adLooksBuilt then return end
    pg._adLooksBuilt = true
    ui.layLook = ui.layLook or {}
    ui.layLookSub = ui.layLookSub or {}
    ui.layLookState = ui.layLookState or {}
    for _, lt in ipairs(Options.LOOK_TABS) do
        local family, fam = lt.family, Schema[lt.family]
        -- the blocks holding a row a layout can set, and their tabs (chips)
        local blocks, chips, seen = {}, {}, {}
        for _, b in ipairs(Options.LOOK_BLOCKS[family] or {}) do
            -- defaultsOnly: a kind's own words for rows another block carries
            local sec = (not b.defaultsOnly) and fam and fam[b.section]
            local keep, defs = {}, {}
            for _, fld in ipairs(sec and b.fields or {}) do
                local def = sec.fields[fld]
                if def and Schema.Inherits(def, sec) then
                    keep[#keep + 1] = fld
                    defs[#defs + 1] = def
                end
            end
            if #keep > 0 then
                blocks[#blocks + 1] = { tab = b.tab, sub = b.sub, state = b.state, title = b.title,
                    section = b.section, fields = keep, defs = defs, sec = sec }
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
        -- a block serves a bar type when one of its rows does
        local function KindOK(b, kind)
            if kind == nil or kind == "all" then return true end
            for _, def in ipairs(b.defs) do
                if Schema.Applies(def, b.sec, kind, nil) then return true end
            end
            return false
        end
        local kinds = {}
        if family == "bar" then
            for _, k in ipairs(Schema.BAR_KINDS) do
                for _, b in ipairs(blocks) do
                    if Options.LOOK_BAR_WORDS[k] and KindOK(b, k) then kinds[#kinds + 1] = k break end
                end
            end
        end
        -- the picked type, else the one this layout has most of
        local function Kind()
            if #kinds == 0 then return "all" end
            local cur = ui.layLookKind
            if cur == "all" then return cur end
            for _, k in ipairs(kinds) do if k == cur then return cur end end
            local counts, best, bestN = {}, "all", 0
            for _, b in ipairs(Store.LayoutItems(SelLayout(), "bar")) do
                local k = Store.KindOf(b)
                if k then
                    counts[k] = (counts[k] or 0) + 1
                    if counts[k] > bestN and Options.LOOK_BAR_WORDS[k] then best, bestN = k, counts[k] end
                end
            end
            return best
        end
        local function ChipsNow()
            local out, kind = {}, Kind()
            for _, c in ipairs(chips) do
                for _, b in ipairs(blocks) do
                    if b.tab == c and KindOK(b, kind) then out[#out + 1] = c break end
                end
            end
            return out
        end
        local function Chip()
            local now = ChipsNow()
            local cur = ui.layLook[family]
            for _, c in ipairs(now) do
                if c == cur then return cur end
            end
            return now[1]
        end
        -- the sub-tabs of the open chip, in block order
        local function Subs()
            local out, had, chip, kind = {}, {}, Chip(), Kind()
            for _, b in ipairs(blocks) do
                if b.sub and not had[b.sub] and b.tab == chip and KindOK(b, kind) then
                    had[b.sub] = true
                    out[#out + 1] = b.sub
                end
            end
            return out
        end
        local function Sub()
            local subs, chip = Subs(), Chip()
            local cur = ui.layLookSub[family] and ui.layLookSub[family][chip or ""]
            for _, s in ipairs(subs) do
                if s == cur then return cur end
            end
            return subs[1]
        end
        -- the open block is on the open sub-tab (or the chip has fewer than two)
        local function OnSub(b)
            if not b.sub then return true end
            local subs = Subs()
            return #subs < 2 or Sub() == b.sub
        end
        -- A sub-tab holding the Conditions table's state blocks (b.state)
        -- splits once more, a state at a time as the editor's table shows one
        -- state's row; its effect blocks (b.fx) share one page, the rest
        -- keep their own.
        local GLOWS = "Glows and art"
        local function PageOf(b) return (b.state or not b.fx) and b.title or GLOWS end
        local function States()
            local out, had, chip, kind, stateful = {}, {}, Chip(), Kind(), false
            for _, b in ipairs(blocks) do
                if b.tab == chip and KindOK(b, kind) and OnSub(b) then
                    if b.state then stateful = true end
                    local key = PageOf(b)
                    if not had[key] then
                        had[key] = true
                        out[#out + 1] = key
                    end
                end
            end
            return stateful and out or {}
        end
        local function State()
            local states, chip = States(), Chip()
            local cur = ui.layLookState[family] and ui.layLookState[family][chip or ""]
            for _, s in ipairs(states) do
                if s == cur then return cur end
            end
            return states[1]
        end
        local tabVis = function() return ui.layoutTab == lt.tab and SelLayout() ~= nil end
        AT.Section(pg, nil, { visibleFn = tabVis })
        AT.RowDesc(pg, "Every " .. lt.one .. " in this layout uses these looks unless it sets its own.", 20, tabVis)
        if family == "bar" then
            AT.RowDropdown(pg, win, "Bars of type",
                function() return Kind() end,
                function(v)
                    ui.layLookKind = v
                    AT.LayoutPage(pg)
                end,
                function()
                    local items = { { value = "all", text = "All bars" } }
                    for _, k in ipairs(kinds) do
                        items[#items + 1] = { value = k, text = Options.LOOK_BAR_WORDS[k] }
                    end
                    return items
                end,
                function() return tabVis() and #kinds >= 2 end)
        end
        local chipRow = AT.AddRow(pg, 30, function() return tabVis() and #ChipsNow() >= 2 end)
        chipRow._strip = AT.TabRow(chipRow)
        chipRow._strip._openFill = COL.panel
        chipRow._strip:SetPoint("TOPLEFT", 8, 0)
        chipRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
        chipRow._sync = function()
            local now = ChipsNow()
            if #now == 0 then return end
            local h = chipRow._strip:Set(now, Chip(), function(name)
                ui.layLook[family] = name
                AT.LayoutPage(pg)
            end, 11)
            local want = (h or 24) + 6
            if chipRow._h ~= want then chipRow._h = want chipRow:SetHeight(want) end
        end
        local subRow = AT.AddRow(pg, 30, function() return tabVis() and #Subs() >= 2 end)
        subRow._strip = AT.TabRow(subRow)
        subRow._strip._openFill = COL.panel
        subRow._strip:SetPoint("TOPLEFT", 8, 0)
        subRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
        subRow._sync = function()
            local subs = Subs()
            if #subs == 0 then return end
            local h = subRow._strip:Set(subs, Sub(), function(name)
                local chip = Chip()
                if not chip then return end
                ui.layLookSub[family] = ui.layLookSub[family] or {}
                ui.layLookSub[family][chip] = name
                AT.LayoutPage(pg)
            end, 11)
            local want = (h or 24) + 6
            if subRow._h ~= want then subRow._h = want subRow:SetHeight(want) end
        end
        local stateRow = AT.AddRow(pg, 30, function() return tabVis() and #States() >= 2 end)
        stateRow._strip = AT.TabRow(stateRow)
        stateRow._strip._openFill = COL.panel
        stateRow._strip:SetPoint("TOPLEFT", 8, 0)
        stateRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
        stateRow._sync = function()
            local states = States()
            if #states == 0 then return end
            local h = stateRow._strip:Set(states, State(), function(name)
                local chip = Chip()
                if not chip then return end
                ui.layLookState[family] = ui.layLookState[family] or {}
                ui.layLookState[family][chip] = name
                AT.LayoutPage(pg)
            end, 11)
            local want = (h or 24) + 6
            if stateRow._h ~= want then stateRow._h = want stateRow:SetHeight(want) end
        end
        for _, b in ipairs(blocks) do
            local vis = function()
                if not (tabVis() and Chip() == b.tab and KindOK(b, Kind())) then return false end
                -- a block without a sub-tab shows on every one, as in the editors
                if not OnSub(b) then return false end
                local pages = States()
                if #pages >= 2 and State() ~= PageOf(b) then return false end
                return true
            end
            AT.Section(pg, b.title, { visibleFn = vis })
            SectionRows(pg, family, b.section, ctx, vis, b.fields, { layoutTier = true })
            Options.LayoutLookStatus(pg, family, b.section, vis, b.fields, lt)
        end
    end
end

-- Icon editor (shared by the group pane and the free pane)

local function IconTabVisible(tabName)
    return function()
        -- the open tab first: every row of every other tab stops here
        if ui.icoTab ~= tabName then return false end
        local rec = SelIcon()
        if not rec then return false end
        for _, t in ipairs(IconTabsFor(rec)) do
            if t == tabName then return true end
        end
        return false
    end
end

-- Live icon preview: a real factory frame restyled on every refresh (the row's
-- _sync), so drags and colour picks show at once. It is the icon at its real
-- size on a scaled host (PreviewFit), so borders keep the live proportions.
-- Aura icons get a stand-in engine button over the holder's missing look, as
-- live. The OnUpdate runs only in a loop mode. Text drops write X / Y in units
-- of a 36px icon. Play on screen paints a copy over the live icon too.
local PREV_SIZE, PREV_CD, PREV_READY, PREV_CHG = 96, 6, 2.6, 4

-- A fake cooldown on a preview icon, with the duration object a timed On
-- cooldown opacity reads (plain numbers on our own frames, nothing secret).
function Options.PreviewCooldown(f, len)
    local now = GetTime()
    f.cooldown:SetCooldown(now, len)
    local d = f._adPrevDur or (C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration())
    if d then
        d:SetTimeFromStart(now, len)
        f._adPrevDur = d
        f._adTimedDur = d
    end
end
local prevIcon, prevBand, prevChips, prevHandles
local prevPhase, prevT, prevStyleT = "ready", 0, 0
local PREV_MODES = {
    { key = "off",   set = "cd", text = "Static",        w = 64,
      tip = "The ready look with no animation. Drag any text on the icon to place it." },
    { key = "loop",  set = "cd", text = "Cooldown loop", w = 112,
      tip = "Ready, a fake cooldown, then ready again (a charge spell: Ready, Recharging, Depleted and back). Swipe, texts, dims and glows loop." },
    -- offered only on a charge spell (charge = true)
    { key = "recharge", set = "cd", charge = true, text = "Recharging", w = 90,
      tip = "A charge left and another coming back, over and over: the Recharging look, with its opacity, grey out, tint and glow." },
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
    -- a Custom Icon's own two states
    { key = "tact",  set = "timer", text = "Active",     w = 64,
      tip = "The Active look, its timer running with its swipe and duration text. Drag any text on the icon to place it." },
    { key = "tina",  set = "timer", text = "Not active", w = 86,
      tip = "The Not active look, with no timer running." },
    { key = "tloop", set = "timer", text = "Timer loop", w = 90,
      tip = "Not active, then a timer starts and runs out, then Not active again." },
    -- a Stance icon's own two states
    { key = "sin",   set = "stance", text = "In it",     w = 56,
      tip = "The look while you are in the stance (any stance, for your current one). Drag any text on the icon to place it." },
    { key = "sout",  set = "stance", text = "Not in it", w = 76,
      tip = "The look while you are not in it (no stance, for your current one)." },
    { key = "sloop", set = "stance", text = "Stance loop", w = 96,
      tip = "In it, then not in it, then in it again." },
}
-- which text drags which fields; the countdown text is the swipe widget's
-- own fontstring, fetched when the handles sync
local PREV_DRAGS = {
    { fs = "stackText",   name = "Stack text",    sec = "text",    a = "stackAnchor",    x = "stackX",    y = "stackY" },
    { fs = "ammoText",    name = "Ammo text",     sec = "text",    a = "ammoAnchor",     x = "ammoX",     y = "ammoY" },
    { fs = "keybindText", name = "Keybind",       sec = "keybind", a = "keybindAnchor",  x = "keybindX",  y = "keybindY" },
    { fs = "labelText",   name = "Custom text 1", sec = "label",   a = "labelAnchor",    x = "labelX",    y = "labelY" },
    { fs = "labelText2",  name = "Custom text 2", sec = "label",   a = "labelAnchor2",   x = "labelX2",   y = "labelY2" },
    { fs = "labelText3",  name = "Custom text 3", sec = "label",   a = "labelAnchor3",   x = "labelX3",   y = "labelY3" },
    { fs = "countdown",   name = "Duration text", sec = "text",    a = "durationAnchor", x = "durationX", y = "durationY" },
}

-- One glow at a time. On Conditions with a state's glows open: the first of
-- them switched on, else its first. Otherwise the first lane the icon has on,
-- in a fixed order.
Options.GLOW_LANE_OF = { ["states.readyGlow"] = "ready", ["states.procGlow"] = "proc",
    ["states.usableGlow"] = "usable", ["states.cooldownGlow"] = "cooldown", ["states.rangeGlow"] = "range",
    ["states.rechargeGlow"] = "recharge", ["states.warnGlow"] = "warn", ["states.toggleGlow"] = "toggle",
    ["states.assistGlow"] = "assist" }
local function PreviewGlowLane(rec)
    local ET = Options.EditorTabs
    if ET and ui.icoTab == "Conditions" then
        local _, kind, keys = ET.Open(rec)
        if kind == "glow" then
            local first
            for _, key in ipairs(keys or {}) do
                local lane = Options.GLOW_LANE_OF[key]
                if lane then
                    first = first or lane
                    if ET.FxLit(rec, key) then return lane end
                end
            end
            if first then return first end
        end
        -- the Queued row's checkmark rides the toggle lane
        if kind == "art" then
            for _, key in ipairs(keys or {}) do
                if key == "states.queueCheck" then return "toggle" end
            end
        end
    end
    local R = function(k) return Store.Resolve(rec, "states", k) end
    if R("readyGlow") == true then return "ready" end
    if R("procGlow") == true then return "proc" end
    if R("usableGlow") == true then return "usable" end
    if R("cooldownGlow") == true then return "cooldown" end
    if R("rangeGlow") == true then return "range" end
    if R("rechargeGlow") == true then return "recharge" end
    if R("warnGlow") == true then return "warn" end
    -- the toggle lane also shows a queued ability's checkmark
    if R("toggleGlow") == true or R("queueCheck") == true then return "toggle" end
    if R("assistGlow") == true then return "assist" end
    return "ready"
end

-- the chip set follows the record: an aura icon uses the aura chips, every
-- other kind the cooldown ones (one ui.prevMode, normalized per kind)
function Options.PreviewMode(rec)
    local m = ui.prevMode or "off"
    local auraKey = (m == "aup" or m == "aloop" or m == "amiss")
    local timerKey = (m == "tact" or m == "tina" or m == "tloop")
    local stanceKey = (m == "sin" or m == "sout" or m == "sloop")
    local aura = rec ~= nil and rec.kind == "aura"
    local timer = rec ~= nil and rec.kind == "timer"
    local stance = rec ~= nil and rec.kind == "stance"
    if aura and not auraKey then return "aup" end
    if timer and not timerKey then return "tact" end
    if stance and not stanceKey then return "sin" end
    if (not aura) and auraKey then return "off" end
    if (not timer) and timerKey then return "off" end
    if (not stance) and stanceKey then return "off" end
    if m == "ovup" and not (NS.DriverAura and NS.DriverAura.OverlayOn(rec)) then return "off" end
    if m == "recharge" and not Options.PreviewCharge(rec) then return "off" end
    return m
end

-- A charge spell: the preview offers its Recharging look.
function Options.PreviewCharge(rec)
    local ET = Options.EditorTabs
    return rec ~= nil and rec.kind == "spell" and ET ~= nil and ET.IsCharge(rec) == true
end

-- A charge spell's count follows the preview: 2 ready, 1 recharging, 0 spent.
function Options.PreviewChargeSample(rec)
    local mode = Options.PreviewMode(rec)
    if mode == "recharge" then return "1" end
    if mode ~= "loop" then return "2" end
    if prevPhase == "cd" then
        return Store.Resolve(rec, "text", "hideChargeAtZero") == true and "" or "0"
    end
    return (prevPhase == "rc" or prevPhase == "rc2") and "1" or "2"
end

-- The stand-in engine button for aura previews, built and styled by the live
-- recipe (DriverAura.WireButton and AnchorButton, Factory.StyleAuraButton; the
-- two widget setters are no-ops). One per preview frame (the pane's, or the
-- on-screen copy's), parented beside it as live, so the missing look's alpha
-- never dims it; it snaps on the same pixel grid as its holder.
function Options.PreviewAuraButton(f)
    f = f or prevIcon
    local b = f._adAuraBtn
    if not b then
        b = CreateFrame("Frame", nil, f:GetParent())
        b.SetIcon = function() end
        b.SetDurationCooldown = function() end
        NS.DriverAura.WireButton(b)
        b:Hide()
        f._adAuraBtn = b
    end
    if b:GetParent() ~= f:GetParent() then b:SetParent(f:GetParent()) end
    b._adPxRef = f._adPxRef
    return b
end

-- The Play on screen copy while it plays this icon, else nil.
function Options.PreviewCopy(rec)
    local S = NS.IconScreen
    if S and rec and S.On(rec.id) then return S.copy end
    return nil
end

-- A new mode starts clean: no cooldown, and an aura loop's fake duration
-- afresh (a frozen Aura up swipe thaws).
function Options.PreviewReset(f)
    if not f then return end
    if f.cooldown.Resume then f.cooldown:Resume() end
    f.cooldown:Clear()
    f._adLoopUntil = nil
    local ab = f._adAuraBtn
    if ab then
        if ab._adSwipe.Resume then ab._adSwipe:Resume() end
        ab._adSwipe:Clear()
        ab._adLoopUntil = nil
    end
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

-- f: the pane's preview (default) or the on-screen copy; both take the same
-- look, at their own size.
local function PreviewRestyle(rec, f)
    f = f or prevIcon
    -- an aura icon's holder has no cooldown glow lanes (its glow is the
    -- live button's)
    f._adGlowLaneOnly = (rec.kind == "aura") and "none" or PreviewGlowLane(rec)
    Factory.ApplyStyle(f, rec)
    -- Hide icon art (texts pinned onto another icon, an Arc Proc on a Cooldown
    -- Manager icon): a faint stand-in shows where the art sits, so the texts
    -- have something to place against. The preview's alone.
    local hidden = Store.Resolve(rec, "appearance", "forceHideIcon") == true and rec.kind ~= "aura"
        and f._adOnStage == true
    if hidden and not f._adPrevGhost then
        f._adPrevGhost = f:CreateTexture(nil, "BACKGROUND")
    end
    if f._adPrevGhost then
        local g = f._adPrevGhost
        g:SetShown(hidden)
        if hidden then
            g:ClearAllPoints()
            g:SetAllPoints(f.icon)
            g:SetTexture(Factory.GetTexture(rec))
            g:SetDesaturated(true)
            g:SetAlpha(0.3)
        end
    end
    -- a count that reads like the kind's own: a group buff's words, your ammo
    -- (an Arc Proc's texts are its tracker's, painted by ApplyStyle)
    if f.stackText:IsShown() and rec.kind ~= "special" then
        local sample = "2"
        if Options.PreviewCharge(rec) then
            sample = Options.PreviewChargeSample(rec)
        elseif rec.kind == "groupbuff" and NS.DriverGroupBuff then
            sample = NS.DriverGroupBuff.SampleText(rec)
        elseif rec.kind == "ammo" then
            sample = GetInventoryItemCount("player", NS.AMMO_SLOT or 0) or 0
        end
        f.stackText:SetText(sample)
    end
    -- the preview shows a real ammo count so the styling reads true
    if f.ammoText and f.ammoText:IsShown() then
        f.ammoText:SetText(GetInventoryItemCount("player", NS.AMMO_SLOT or 0) or 0)
    end
    -- The key on your bars, else a stand-in so the text can still be placed.
    local kb = NS.DriverCooldown and NS.DriverCooldown.KeybindTextFor
        and NS.DriverCooldown.KeybindTextFor(rec)
    if not kb and Factory.KeybindEnabled(rec) then kb = "s-1" end
    Factory.SetKeybindText(f, kb)
    -- Aura icon: the count belongs to the engine button, and the stand-in takes
    -- the whole live look (the kind's art, any Active / Custom icon over it).
    local ab = f._adAuraBtn
    local w, h = f:GetSize()
    if rec.kind == "aura" then
        f.stackText:SetText("")
        ab = Options.PreviewAuraButton(f)
        NS.DriverAura.AnchorButton(ab, f)
        ab._adIcon:SetTexture(Factory.KindTexture(rec))
        -- PreviewApplyMode hides the missing look itself there, so no plate.
        Factory.StyleAuraButton(ab, rec, h,
            { w = w, h = h, ghost = NS.DriverAura.GhostShown(rec) and not NS.DriverAura.NeedsEraser(rec),
              previewGlows = true })
        if ab._adStacks:IsShown() then ab._adStacks:SetText("2") end
    elseif Options.PreviewMode(rec) == "ovup" then
        -- a spell icon's aura overlay: the same stand-in, one level up the
        -- ladder like the live overlay, "the engine wrote" the aura's own
        -- art (its first ID); the cooldown plane under it is the holder
        ab = Options.PreviewAuraButton(f)
        NS.DriverAura.AnchorButton(ab, f, 1)
        local ov = rec.driver and rec.driver.overlay
        local aid = ov and Store.TrackedAuraIDs(ov)[1]
        -- a totem or a set duration wears the spell it follows (an item or trinket its own art)
        local PH = NS.DriverPhase
        if ov and PH and PH.Source(rec) then
            aid = rec.kind == "spell" and (Store.RecordSpellID(rec.driver, PH.SpellOf(rec, ov)) or aid) or nil
        end
        ab._adIcon:SetTexture((aid and C_Spell.GetSpellTexture(aid)) or Factory.KindTexture(rec))
        Factory.StyleAuraButton(ab, rec, h, { w = w, h = h, ghost = true })
        if ab._adStacks:IsShown() then ab._adStacks:SetText("2") end
    elseif ab then
        ab:Hide()
    end
end

local function PreviewApplyMode(rec, f)
    f = f or prevIcon
    local mode = Options.PreviewMode(rec)
    -- only a charge spell's preview recharges; another kind never inherits it
    if rec.kind ~= "spell" and f._adRecharging then
        Factory.SetGCDPresentation(f, rec, false, false, false)
        f._adChargesAvail = nil
    end
    if rec.kind == "aura" then
        -- The holder always shows the missing look, as live; the stand-in
        -- covers it while the aura is up (phase "ready" in the loop).
        f.cooldown:Clear()
        Factory.StopGlow(f)
        Factory.SetState(f, rec, true, true)
        local ab = Options.PreviewAuraButton(f)
        local up = (mode == "aup") or (mode == "aloop" and prevPhase == "ready")
        ab:SetShown(up)
        -- where live hides the missing look while the aura is up, the preview does too
        if up and NS.DriverAura.NeedsEraser(rec) then Factory.HideMissingLook(f) end
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
        if f == prevIcon then PreviewSyncHandles() end
        return
    end
    if rec.kind == "timer" then
        -- A Custom Icon: Active runs a timer, frozen at 60% left so its swipe
        -- and time text show; Not active has none. The loop's second phase is
        -- the timer the tick started.
        f._adGlowLaneOnly = nil
        Factory.SetProcGlow(f, rec, false)
        if f.cooldown.Resume then f.cooldown:Resume() end
        local active = (mode == "tact") or (mode == "tloop" and prevPhase == "cd")
        if mode == "tact" then
            f.cooldown:SetCooldown(GetTime() - PREV_CD * 0.4, PREV_CD)
            if f.cooldown.Pause then f.cooldown:Pause() end
        elseif not active then
            f.cooldown:Clear()
        end
        Factory.SetState(f, rec, not active, not active)
        Factory.UpdateGlow(f, rec, active)
        if f == prevIcon then PreviewSyncHandles() end
        return
    end
    if rec.kind == "stance" then
        -- A Stance icon: In it is the ready look (its While active glow), Not
        -- in it the cooldown look; the art is the live one, and no swipe runs.
        Factory.SetProcGlow(f, rec, false)
        if f.cooldown.Resume then f.cooldown:Resume() end
        f.cooldown:Clear()
        local active = (mode == "sin") or (mode == "sloop" and prevPhase == "ready")
        Factory.SetState(f, rec, not active, not active)
        if f == prevIcon then PreviewSyncHandles() end
        return
    end
    if mode == "ovup" then
        -- A spell icon's aura while up: the cooldown underneath with the stand-in
        -- aura button over it, as live.
        f._adGlowLaneOnly = "none"
        Factory.SetProcGlow(f, rec, false)
        Factory.StopGlow(f)
        Factory.SetState(f, rec, true, true)
        local ab = Options.PreviewAuraButton(f)
        -- A frozen moment of the aura (60% left), so its swipe colour, direction,
        -- edge and time text show while nothing ticks. Plain numbers on our own
        -- Cooldown; every other use of the stand-in resumes it first.
        local sw = ab._adSwipe
        if sw.Resume then sw:Resume() end
        sw:SetCooldown(GetTime() - PREV_CD * 0.4, PREV_CD)
        if sw.Pause then sw:Pause() end
        ab:Show()
        if f == prevIcon then PreviewSyncHandles() end
        return
    end
    -- a frozen swipe (Aura up's stand-in aside) never carries into another mode
    if f.cooldown.Resume then f.cooldown:Resume() end
    -- Recharging through the driver's own setter, so the swipe settings for a
    -- charge left (fill, edge, the duration text) show as live
    local charge = Options.PreviewCharge(rec)
    local rc = charge and (mode == "recharge"
        or (mode == "loop" and (prevPhase == "rc" or prevPhase == "rc2"))) or false
    Factory.SetGCDPresentation(f, rec, false, rc, false)
    f._adChargesAvail = rc or nil
    Factory.ApplyDurationVis(f, rec)
    if mode ~= "recharge" then f._adLoopUntil = nil end
    if mode == "loop" then
        if prevPhase ~= "ready" then
            -- Depleted, or a charge spell's Recharging
            Factory.SetProcGlow(f, rec, false)
            Factory.UpdateGlow(f, rec, false)
            Factory.SetState(f, rec, true, not rc)
        else
            Factory.SetState(f, rec, false, false)
            Factory.UpdateGlow(f, rec, true)
            Factory.SetProcGlow(f, rec, true)
        end
    elseif mode == "recharge" then
        -- A charge left and another coming back, over and over: Recharging's
        -- own look and glow while the charge's swipe runs; a refresh in the
        -- middle leaves it running, the tick starts the next (plain numbers
        -- on our own Cooldown, nothing secret).
        f._adGlowLaneOnly = "recharge"
        Factory.SetProcGlow(f, rec, false)
        if GetTime() >= (f._adLoopUntil or 0) then
            f.cooldown:SetCooldown(GetTime(), PREV_CHG)
            f._adLoopUntil = GetTime() + PREV_CHG
        end
        Factory.SetState(f, rec, true, false)
    elseif mode == "proc" then
        f._adGlowLaneOnly = "proc"
        f.cooldown:Clear()
        Factory.SetState(f, rec, false, false)
        Factory.SetProcGlow(f, rec, true)
    elseif mode == "ready" then
        f._adGlowLaneOnly = "ready"
        f.cooldown:Clear()
        Factory.SetProcGlow(f, rec, false)
        Factory.SetState(f, rec, false, false)
        Factory.UpdateGlow(f, rec, true)
    else
        f._adGlowLaneOnly = "none"
        f.cooldown:Clear()
        Factory.SetProcGlow(f, rec, false)
        Factory.SetState(f, rec, false, false)
        Factory.StopGlow(f)
    end
    if charge and f.stackText:IsShown() then f.stackText:SetText(Options.PreviewChargeSample(rec)) end
    if f == prevIcon then PreviewSyncHandles() end
end

-- The loop: ready for PREV_READY, a fake cooldown for PREV_CD, repeat. A
-- charge spell's loop walks Ready, Recharging, Depleted, Recharging. An aura's
-- loop is the reverse: up for its fake duration (PREV_CD), then missing for
-- PREV_READY. Recharging alone restarts its charge as it comes back. The Play
-- on screen copy runs on the same clock.
-- An Aura loop with Active starting near the end: the stand-in wears Before
-- that's look until then, as live (seconds count on the fake aura's own
-- length). rem: the fake aura's time left, nil while it is down.
function Options.PreviewEarly(rec, rem, copy)
    local early = false
    if rem and Factory.TimeGateFrac(rec) ~= nil then
        if (Store.Resolve(rec, "auraActive", "activeTimeUnit") or "pct") == "sec" then
            early = rem > (Store.Resolve(rec, "auraActive", "activeTimeSec") or 3)
        else
            early = rem > PREV_CD * (Store.Resolve(rec, "auraActive", "activeTimePct") or 30) / 100
        end
    end
    local f = prevIcon
    while f do
        if early then
            Factory.PaintBeforeLook(Options.PreviewAuraButton(f), rec)
        elseif f._adPrevEarly then
            -- the live look again: the stand-in restyles
            PreviewRestyle(rec, f)
        end
        f._adPrevEarly = early
        f = (f == prevIcon) and copy or nil
    end
end

local function PreviewTick(_, dt)
    local rec = SelIcon()
    if not rec or prevIcon._adDragging then return end
    local aura = rec.kind == "aura"
    local copy = Options.PreviewCopy(rec)
    local mode = Options.PreviewMode(rec)
    if mode == "recharge" then
        -- no restyle here: it would put back the lane Recharging holds
        if GetTime() >= (prevIcon._adLoopUntil or 0) then PreviewApplyMode(rec) end
        if copy and GetTime() >= (copy._adLoopUntil or 0) then PreviewApplyMode(rec, copy) end
        return
    end
    prevT = prevT + dt
    prevStyleT = prevStyleT + dt
    if prevStyleT >= 0.25 then
        prevStyleT = 0
        PreviewRestyle(rec)
        if copy then PreviewRestyle(rec, copy) end
        -- ApplyStyle re-runs the ready and usable lanes on its own; the proc
        -- lane is event-driven, so it is re-asserted here (idempotent). An
        -- aura icon's holder has no proc lane, nor has a timer or a stance.
        if not aura and rec.kind ~= "timer" and rec.kind ~= "stance" then
            Factory.SetProcGlow(prevIcon, rec, prevPhase == "ready")
            if copy then Factory.SetProcGlow(copy, rec, prevPhase == "ready") end
        end
        PreviewSyncHandles()
    end
    if aura and mode == "aloop" then
        Options.PreviewEarly(rec, prevPhase == "ready" and (PREV_CD - prevT) or nil, copy)
    end
    if mode == "loop" and Options.PreviewCharge(rec) then
        -- one charge spent (Recharging), the last spent (Depleted) while that
        -- charge comes back, then the next one back to Ready
        local len = (prevPhase == "ready" and PREV_READY) or (prevPhase == "rc" and PREV_CHG * 0.4)
            or (prevPhase == "cd" and PREV_CHG * 0.6) or (PREV_CHG + 0.2)
        if prevT < len then return end
        prevPhase = (prevPhase == "ready" and "rc") or (prevPhase == "rc" and "cd")
            or (prevPhase == "cd" and "rc2") or "ready"
        prevT = 0
        local f = prevIcon
        while f do
            if prevPhase == "rc" or prevPhase == "rc2" then
                Options.PreviewCooldown(f, PREV_CHG)
            elseif prevPhase == "ready" then
                f.cooldown:Clear()
            end
            PreviewApplyMode(rec, f)
            f = (f == prevIcon) and copy or nil
        end
        return
    end
    local firstT = aura and PREV_CD or PREV_READY
    local secondT = aura and PREV_READY or (PREV_CD + 0.2)
    if prevPhase == "ready" then
        if prevT >= firstT then
            prevPhase, prevT = "cd", 0
            -- plain numbers are legal on a preview push (nothing secret)
            if not aura then
                Options.PreviewCooldown(prevIcon, PREV_CD)
                if copy then Options.PreviewCooldown(copy, PREV_CD) end
            end
            PreviewApplyMode(rec)
            if copy then PreviewApplyMode(rec, copy) end
        end
    elseif prevT >= secondT then
        prevPhase, prevT = "ready", 0
        prevIcon.cooldown:Clear()
        PreviewApplyMode(rec)
        if copy then
            copy.cooldown:Clear()
            PreviewApplyMode(rec, copy)
        end
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
            GameTooltip:AddLine(("X %d, Y %d. Drag to move; the Text tab holds the sliders."):format(
                Store.Resolve(rec, d.sec, d.x) or 0, Store.Resolve(rec, d.sec, d.y) or 0),
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
                -- es carries the host's scale; kS is the live icon's own
                local es = prevIcon:GetEffectiveScale()
                if not es or es <= 0 then return end
                local kS = (prevIcon:GetHeight() or 36) / 36
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

-- The icon and bar previews sit on a stage in one shared colour (saved with the
-- panel's own state): dark borders vanish on the window's navy, so the stage
-- is slate (#6F9797) unless dark, light or any colour is picked.
Options.PREVIEW_BG = {
    { key = "dark", name = "Dark", col = COL.well },
    { key = "slate", name = "Slate", col = { 111 / 255, 151 / 255, 151 / 255 } },
    { key = "light", name = "Light", col = { 0.80, 0.81, 0.83 } },
}
Options.previewStages = {}

-- The picked swatch: nothing picked, or a preset no longer offered, is slate.
function Options.PreviewBgKey()
    local key = Store.UI().previewBg
    if key == "custom" then return key end
    for _, p in ipairs(Options.PREVIEW_BG) do
        if p.key == key then return key end
    end
    return "slate"
end

function Options.PreviewBgColor()
    local u = Store.UI()
    local key = Options.PreviewBgKey()
    if key == "custom" and type(u.previewBgColor) == "table" then return u.previewBgColor end
    for _, p in ipairs(Options.PREVIEW_BG) do
        if p.key == key then return p.col end
    end
    return Options.PREVIEW_BG[2].col
end

function Options.PaintPreviewBg()
    local u = Store.UI()
    local key = Options.PreviewBgKey()
    local c = Options.PreviewBgColor()
    for _, stage in ipairs(Options.previewStages) do
        stage:SetBackdropColor(c[1], c[2], c[3], 1)
        for _, sw in ipairs(stage._adBgSwatches) do
            if sw._adKey == "custom" then sw:SetColor(u.previewBgColor or Options.PREVIEW_BG[2].col) end
            sw._adOn = (sw._adKey == key)
            local b = sw._adOn and COL.arc or COL.line
            sw:SetBackdropBorderColor(b[1], b[2], b[3], 1)
        end
    end
end

-- The swatches in a stage's top-right corner: the presets, then a custom colour
-- that opens the colour picker.
function Options.PreviewBgSwatches(stage)
    local items = {}
    for _, p in ipairs(Options.PREVIEW_BG) do items[#items + 1] = p end
    items[#items + 1] = { key = "custom", name = "custom color" }
    stage._adBgSwatches = {}
    local x = -6
    for i = #items, 1, -1 do
        local p = items[i]
        local sw = AT.MakeSwatch(stage, 12, 12)
        sw:SetPoint("TOPRIGHT", x, -6)
        sw:SetFrameLevel(stage:GetFrameLevel() + 20)
        x = x - 16
        sw._adKey = p.key
        sw:SetColor(p.col or Options.PREVIEW_BG[2].col)
        if p.key == "custom" then
            local plus = sw:CreateFontString(nil, "OVERLAY")
            plus:SetFont(AT.FONT, 10, "OUTLINE")
            plus:SetPoint("CENTER", 0, 0)
            plus:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            plus:SetText("+")
        end
        -- the picked swatch keeps its cyan border through hover
        sw:SetScript("OnEnter", function(s)
            if not s._adOn then s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end
        end)
        sw:SetScript("OnLeave", function(s)
            local b = s._adOn and COL.arc or COL.line
            s:SetBackdropBorderColor(b[1], b[2], b[3], 1)
        end)
        sw:SetScript("OnClick", function()
            AT.CloseDropdown()
            local u = Store.UI()
            if p.key ~= "custom" then
                u.previewBg = p.key
                Options.PaintPreviewBg()
                return
            end
            local was, wasCol = u.previewBg, u.previewBgColor
            local c = Options.PreviewBgColor()
            if not ColorPickerFrame.SetupColorPickerAndShow then return end
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c[1], g = c[2], b = c[3], hasOpacity = false,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    u.previewBg, u.previewBgColor = "custom", { r, g, b }
                    Options.PaintPreviewBg()
                end,
                cancelFunc = function()
                    u.previewBg, u.previewBgColor = was, wasCol
                    Options.PaintPreviewBg()
                end,
            })
        end)
        AT.Tooltip(sw, "Preview background: " .. p.name, p.key == "custom"
            and "Pick any color for the icon and bar previews to sit on."
            or "The icon and bar previews sit on this color.")
        stage._adBgSwatches[#stage._adBgSwatches + 1] = sw
    end
    Options.previewStages[#Options.previewStages + 1] = stage
    Options.PaintPreviewBg()
end

-- The icon at the size the engine gives it, on a host scaled so its longer
-- side fills the stage (PREV_SIZE): a magnified live icon, never a 96px
-- restyle. The host's offsets are in its own, scaled units.
function Options.PreviewFit(rec)
    local w, h = 36, 36
    if rec and Engine and Engine.IconSize then w, h = Engine.IconSize(rec) end
    if not (w and h and w > 0 and h > 0) then w, h = 36, 36 end
    local host, s = prevBand.host, PREV_SIZE / math.max(w, h)
    prevIcon:SetSize(w, h)
    host:SetSize(w, h)
    host:SetScale(s)
    host:ClearAllPoints()
    host:SetPoint("CENTER", prevBand, "TOP", 0, -(10 + PREV_SIZE / 2) / s)
end

-- Play on screen is offered while the icon shows on screen, and reads Stop in
-- the accent while it plays.
function Options.PaintScreenButton()
    local b = prevBand and prevBand.screen
    if not b then return end
    local rec, S = SelIcon(), NS.IconScreen
    local on = S ~= nil and rec ~= nil and S.On(rec.id)
    b.fs:SetText(on and "Stop on screen" or "Play on screen")
    local c = on and COL.arc or COL.dim
    b.fs:SetTextColor(c[1], c[2], c[3])
    b:SetShown(S ~= nil and rec ~= nil and S.OK(rec))
end

-- The preview pane sits above the scrolling editor page so it stays in view.
-- AttachPreview returns its height, which the page's top anchor moves down by.
-- Stage: the icon plus 10 px all round; then the mode chips.
local PREV_PANE_H = PREV_SIZE + 20 + 6 + 22 + 8
local function BuildPreviewPane()
    prevBand = CreateFrame("Frame", nil, UIParent)
    prevBand:SetHeight(PREV_PANE_H)
    prevBand:Hide()
    -- made first and kept at the band's own level, so the icon draws above it
    local stage = CreateFrame("Frame", nil, prevBand, "BackdropTemplate")
    stage:SetPoint("TOPLEFT", 8, 0)
    stage:SetPoint("TOPRIGHT", -12, 0)
    stage:SetHeight(PREV_SIZE + 20)
    stage:SetFrameLevel(prevBand:GetFrameLevel())
    AT.Skin(stage, COL.well, COL.line)
Options.BuildYield()
    Options.PreviewBgSwatches(stage)
    -- The icon's host, scaled by PreviewFit; the aura stand-in shares it.
    -- Borders snap on the live icons' pixel grid, then scale with the rest.
Options.BuildYield()
    prevBand.host = CreateFrame("Frame", nil, prevBand)
    prevIcon = Factory.CreatePreview(prevBand.host)
    prevIcon:SetPoint("CENTER")
    prevIcon._adPxRef = UIParent
    -- the stage keeps pinned texts on the icon (TA.Place)
    prevIcon._adOnStage = true
    Options.PreviewFit(nil)
Options.BuildYield()
    PreviewWireHandles()
    -- The mode chips: a cooldown set, an aura set, and the overlay's Aura up,
    -- which joins the cooldown set; AttachPreview centres the chips shown.
    prevChips = {}
    for _, m in ipairs(PREV_MODES) do
        Options.BuildYield()
        local b = AT.MakeSmallButton(prevBand, m.text, m.w)
        b._adSet = m.set
        b._adW = m.w
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            ui.prevMode = m.key
            prevPhase, prevT, prevStyleT = "ready", 0, 0
            Options.PreviewReset(prevIcon)
            Options.PreviewReset(Options.PreviewCopy(SelIcon()))
            if RefreshAll then RefreshAll() end
        end)
        AT.Tooltip(b, m.text, m.tip)
        prevChips[m.key] = b
    end
    -- Play on screen, in the stage's top-left corner: this preview drawn over
    -- the icon itself (UI\AD_IconScreen), painted by the same two steps.
    local scr = AT.MakeSmallButton(stage, "Play on screen", 118)
    scr:SetPoint("TOPLEFT", 6, -6)
    scr:SetFrameLevel(stage:GetFrameLevel() + 20)
    scr:SetScript("OnClick", function()
        AT.CloseDropdown()
        local rec, S = SelIcon(), NS.IconScreen
        if not (rec and S) then return end
        if S.On(rec.id) then
            S.Stop()
        elseif S.OK(rec) then
            -- the pane and the copy start the loop together
            prevPhase, prevT, prevStyleT = "ready", 0, 0
            Options.PreviewReset(prevIcon)
            S.Start(rec)
        end
        if RefreshAll then RefreshAll() end
    end)
    AT.Tooltip(scr, function() return scr.fs:GetText() end,
        "Plays this preview on the icon itself, in its real place and size. Press again, pick something else, or close this window to stop.")
    prevBand.screen = scr
    local S = NS.IconScreen
    if S then
        S.painter = function(rec, f)
            PreviewRestyle(rec, f)
            PreviewApplyMode(rec, f)
        end
        S.onStop = Options.PaintScreenButton
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
    -- Play on screen belongs to the icon on show here
    local S = NS.IconScreen
    if S and S.On() and not (shown and S.On(rec.id)) then S.Stop() end
    if not shown then
        prevBand:SetScript("OnUpdate", nil)
        return 0
    end
    local mode = Options.PreviewMode(rec)
    prevBand:SetScript("OnUpdate", (mode == "loop" or mode == "aloop" or mode == "tloop" or mode == "sloop"
        or mode == "recharge") and PreviewTick or nil)
    local set = (rec.kind == "aura") and "aura" or (rec.kind == "timer") and "timer"
        or (rec.kind == "stance") and "stance" or "cd"
    local ov = set == "cd" and NS.DriverAura ~= nil and NS.DriverAura.OverlayOn(rec) == true
    local shownChips, total = {}, -6
    for _, m in ipairs(PREV_MODES) do
        local b = prevChips[m.key]
        local on = ((m.set == set) and (not m.charge or Options.PreviewCharge(rec)))
            or (ov and m.set == "ov")
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
        b:SetPoint("LEFT", prevBand, "TOP", x, -(PREV_SIZE + 20 + 6 + 11))
        x = x + b._adW + 6
    end
    if not prevIcon._adDragging then
        Options.PreviewFit(rec)
        PreviewRestyle(rec)
        PreviewApplyMode(rec)
    end
    -- the copy on screen takes every settings change too
    if S and S.On(rec.id) then
        if S.OK(rec) then S.Start(rec) else S.Stop() end
    end
    Options.PaintScreenButton()
    return PREV_PANE_H
end
-- offline harness access
function Options._iconPrev() return prevIcon, prevBand end

local function BuildIconEditor(parent)
    local pg = AT.NewPage(parent)
    AT.MakeScrollable(pg)
    pg:Show()

    local head = AT.AddRow(pg, 34)
    head._icon = IconButton(head, 26)
    -- on the first line: a narrow pane puts the actions on lines under it
    head._icon:SetPoint("LEFT", head, "TOPLEFT", 8, -17)
    head._icon:EnableMouse(false)
    head._name = head:CreateFontString(nil, "OVERLAY")
    head._name:SetFont(AT.FONT, 13, "")
    head._name:SetPoint("LEFT", head, "TOPLEFT", 42, -17)
    head._name:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    head._pill = KindPill(head)
    head._badge = head:CreateFontString(nil, "OVERLAY")
    head._badge:SetFont(AT.FONT, 9, "")
    head._badge:SetTextColor(SHR[1], SHR[2], SHR[3])
    head._del = AT.MakeSmallButton(head, "Delete", 56)
    head._del:SetPoint("RIGHT", -8, 0)
    head._del:SetScript("OnClick", function() Options.ConfirmDelete(SelIcon()) end)
    BandActions(head, head._name, SelIcon, { rightOf = head._del,
        hide = { head._pill, head._badge }, lead = 42, top = 34 })
    head._sync = function()
        local rec = SelIcon()
        if not rec then return end
        -- several icons at once: their count and kinds, no actions
        local MS = Options.MultiSelect
        if MS and MS.Band(head, rec, "icon") then return end
        head._icon.tex:SetTexture(Factory.GetTexture(rec))
        head._name:SetText("Editing:  " .. rec.name)
        head._pill:Set(Options.IconPillText(rec.kind))
        head._pill:ClearAllPoints()
        head._pill:SetPoint("LEFT", head._name, "RIGHT", 8, 0)
        head._badge:ClearAllPoints()
        head._badge:SetPoint("LEFT", head._pill, "RIGHT", 8, 0)
        head._badge:SetText((Store.BadgeText(rec)))
        Options.FitBand(head._adBand)
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
        -- a pick made before the regroup moves to where its rows went
        local ET = Options.EditorTabs
        if ET then ET.FixPicks("icon", ui, rec, "icoTab", "icoSec") end
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
        end, nil, ET and ET.Badges("icon", tabs, pg:IsVisible(), ui.icoTab))
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Sub-tabs: every block names the sub-tab it sits on (def.sub), and a tab
    -- with two or more applicable sub-tabs shows them as a second chip row; one
    -- renders plain. A tab whose blocks name none would stack them.
    local SEC_LISTS = {}   -- [tabName] = ordered block defs
    local function BlockApplies(rec, def)
        -- several icons at once: a block they all have, never a per-item pane
        if rec._adMulti then return Options.MultiSelect.BlockApplies(rec, def, BlockApplies) end
        -- a pane of bespoke rows (Fade When, Anchor) answers for itself; the
        -- Defaults page's kind (rec._adDefaults) has no record to ask, so its
        -- effects follow the kind alone
        local dp = rec._adDefaults
        if def.applies and not dp then return def.applies(rec) == true end
        local sec = Schema.icon[def.section]
        if not sec or not Schema.Applies(nil, sec, Store.KindOf(rec)) then return false end
        -- a block meant for some kinds only (the two aura swipes, the looks
        -- ammo has not): a kind or a set
        local ko = def.kindOnly
        if ko and not (ko == rec.kind or (type(ko) == "table" and ko[rec.kind])) then return false end
        -- A spell icon has the aura's look only while its aura overlay is on.
        if not dp and (def.section == "auraActive" or def.section == "auraSwipe") and rec.kind ~= "aura"
            and not (NS.DriverAura and NS.DriverAura.OverlayOn and NS.DriverAura.OverlayOn(rec)) then
            return false
        end
        -- any row of any of its parts (a block can join rows of two sections)
        for _, p in ipairs(def.parts or { def }) do
            local psec = Schema.icon[p.section]
            for _, fname in ipairs(p.fields) do
                local fdef = psec and psec.fields[fname]
                if fdef and Schema.Applies(fdef, psec, Store.KindOf(rec)) then return true end
            end
        end
        return false
    end
    local function AvailSecs(tabName, rec)
        rec = rec or SelIcon()
        local out, seen = {}, {}
        if not rec then return out end
        for _, def in ipairs(SEC_LISTS[tabName] or {}) do
            local s = def.sub
            if s and not seen[s] and BlockApplies(rec, def) then
                seen[s] = true
                out[#out + 1] = s
            end
        end
        return out
    end
    -- the tab lists leave out a tab none of whose blocks apply (no tab is on
    -- this list today: Conditions always has the state table)
    local HIDE_EMPTY = {}
    Options.iconTabEmpty = function(rec, tabName)
        if not HIDE_EMPTY[tabName] then return false end
        for _, def in ipairs(SEC_LISTS[tabName] or {}) do
            if def.parts and BlockApplies(rec, def) then return false end
        end
        return true
    end
    -- a block's sub-tab shows: no sub-tab, fewer than two, or the picked one
    local function SubOpen(tabName, sub)
        if not sub then return true end
        local avail = AvailSecs(tabName)
        return #avail < 2 or ui.icoSec[tabName] == sub
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
        local ET = Options.EditorTabs
        local h = secRow._strip:Set(avail, cur, function(name)
            ui.icoSec[ui.icoTab] = name
            AT.LayoutPage(pg)
        end, 11, ET and ET.Badges("iconSub", avail, pg:IsVisible() and secRow._visibleFn(), cur))
        local want = (h or 24) + 6
        if secRow._h ~= want then secRow._h = want secRow:SetHeight(want) end
    end

    -- Tracking (driver block; per kind; retarget re-keys the driver only)
    local trackVis = IconTabVisible("Tracking")
    Options.BuildYield()
    AT.Section(pg, "Tracking", { visibleFn = trackVis })
    Options.BuildYield()
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
                local info = C_Spell.GetSpellName and C_Spell.GetSpellName(sid) -- raw-id: the typed ID names the record
                if info then r.name = info end
                Store.Dirty("tree")
                RefreshAll()
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "spell"
        end,
        "The tracked spell. Retargeting re-keys the driver and keeps every setting and position.")
    -- More spells on the same icon (driver.spellAlts): the cooldown driver
    -- turns it to the last of them cast, else it shows the first one known.
    Options.BuildYield()
    AT.RowInput(pg, "Also these spells",
        function()
            local r = SelIcon()
            return r and Options.SpellAltsText(r.driver) or ""
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            Options.SetSpellAlts(r.driver, Options.ParseSpellIDs(v))
            Store.Dirty("tree")
            RefreshAll()
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "spell"
        end,
        "Other spells this icon can show, separated by commas. It turns to the last of them you cast, else shows the first one you know.",
        "e.g. 12294, 23922")
    -- Aura tracking: every ID rides the icon's one engine button and the game
    -- shows whichever is up. ShapeOf reads older shapes (petbuff, ownOnly) as
    -- the driver does; unit and type edits rewire the slot, the rest is data.
    local auraVis = function()
        local r = SelIcon()
        return trackVis() and r ~= nil and r.kind == "aura"
    end
    Options.BuildYield()
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
    -- Forever's ranks share only a name: the icon can follow the one you know
    Options.BuildYield()
    AT.RowToggle(pg, "Follow my rank",
        function()
            local r = SelIcon()
            return r ~= nil and r.driver.followRank ~= false
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            -- on by default: only off is stored
            if v then r.driver.followRank = nil else r.driver.followRank = false end
            Store.Dirty("style", r.id)
        end,
        function() return auraVis() and NS.IsForever == true end,
        Options.FOLLOW_RANK_DESC)
    Options.BuildYield()
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
            -- then move it off a unit this type cannot match on. You, then
            -- your target fits either type (your buff, then the target's).
            local unit = NS.DriverAura.ShapeOf(d)
            d.auraType = v
            if not NS.DriverAura.TwoUnits(d) and not Options.AuraUnitAllowed(d, unit, v) then unit = "target" end
            d.unit = unit
            Store.Dirty("style", r.id)
        end,
        function() return {
            { value = "buff", text = "Buff" },
            { value = "debuff", text = "Debuff" },
        } end,
        auraVis)
    Options.BuildYield()
    local unitRow = AT.RowDropdown(pg, win, "On unit",
        function()
            local r = SelIcon()
            return r and Options.UnitPick(r.driver)
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            -- A petbuff record becomes a plain buff with unit = pet.
            if r.driver.auraType == "petbuff" then r.driver.auraType = "buff" end
            Options.SetUnitPick(r.driver, v)
            Store.Dirty("style", r.id)
        end,
        function()
            local r = SelIcon()
            if not r then return {} end
            return Options.UnitPickItems(r, r.driver)
        end,
        auraVis)
    AT.Tooltip(unitRow, "On unit",
        "Who carries the aura. Buffs match on you, your pet, party members, players and friendly targets; debuffs on enemies. The game does not let addons match a buff on an enemy creature or a debuff on a friend by spell ID, so those stay dark (spells the game marks never-secret are the exception).")
    Options.BuildYield()
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
    -- a totem from the icon's first spell shows ahead of the aura, as the
    -- Cooldown Manager's do (Drivers\AD_DriverPhase.lua)
    Options.BuildYield()
    AT.RowToggle(pg, "Show its totem first",
        function()
            local r = SelIcon()
            return r ~= nil and r.driver.totem == true
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            r.driver.totem = v and true or nil
            Store.Dirty("style", r.id)
        end,
        auraVis,
        "While a totem or guardian from the first spell is out, the icon shows its time instead of the aura.")
    -- A group buff: every rank and the group version on one icon; a member
    -- counts as having it with any of them on (Drivers\AD_DriverGroupBuff.lua).
    local gbVis = function()
        local r = SelIcon()
        return trackVis() and r ~= nil and r.kind == "groupbuff"
    end
    Options.BuildYield()
    AT.RowInput(pg, "Buff spell IDs",
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
            if ids[1] ~= old then
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])
                if nm then r.name = nm end
            end
            Store.Dirty("tree")
            RefreshAll()
        end,
        gbVis,
        "Every rank of the buff, and its group version, separated by commas or spaces. A member counts as having it with any of them on.",
        "e.g. 10938, 21564")
    Options.BuildYield()
    local gbCaster = AT.RowDropdown(pg, win, "Cast by",
        function()
            local r = SelIcon()
            return (r and NS.DriverGroupBuff and NS.DriverGroupBuff.Caster(r)) or "any"
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            r.driver.caster = (v ~= "any") and v or nil
            Store.Dirty("style", r.id)
        end,
        function() return Options.AURA_CASTER_ITEMS end,
        gbVis)
    AT.Tooltip(gbCaster, "Cast by",
        "Anyone: any copy counts. Me: only yours, so your Beacon or Earth Shield, not another player's.")
    Options.BuildYield()
    SectionRows(pg, "icon", "groupBuff", SelIcon, gbVis, { "remind", "combatShow" })
    Options.BuildYield()
    AT.RowToggle(pg, "Auto rank (follow my known rank)",
        function() local r = SelIcon() return r ~= nil and Store.AutoRankOn(r.driver) end,
        function(v)
            local r = SelIcon()
            if r then
                -- on by default: only off is stored
                if v then r.driver.autoRank = nil else r.driver.autoRank = false end
                Store.Dirty("style", r.id)
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "spell" and NS.IsForever == true
        end,
        "Ranked realms (WoW Forever): the icon resolves by NAME to the rank you currently know, so learning a new rank never needs a new spell ID. Off = it tracks the exact ID above; you can also pin a rank there.")
    Options.BuildYield()
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
    -- a "who" gate (Store.IsLoaded), so a change is a load pass
    Options.BuildYield()
    AT.RowToggle(pg, "Only load once learned",
        function() local r = SelIcon() return r ~= nil and r.driver.onlyKnown == true end,
        function(v)
            local r = SelIcon()
            if r then
                r.driver.onlyKnown = v and true or nil
                Store.Dirty("load")
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "spell"
        end,
        "Doesn't load until your character knows this spell (any rank), and loads by itself the moment you learn it.")
    Options.BuildYield()
    AT.RowToggle(pg, "Only this rank",
        function() local r = SelIcon() return r ~= nil and r.driver.knownExact == true end,
        function(v)
            local r = SelIcon()
            if r then
                r.driver.knownExact = v and true or nil
                Store.Dirty("load")
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "spell" and r.driver.onlyKnown == true
                and NS.IsForever == true
        end,
        "Waits for this exact rank (the spell ID above), not just any rank of the spell.")
    Options.BuildYield()
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
    -- The slot shows whatever is equipped; this keeps it to trinkets with a
    -- use effect (they hide, and close a dynamic group's gap, while passive).
    Options.BuildYield()
    SectionRows(pg, "icon", "trinket", SelIcon, function()
        local r = SelIcon()
        return trackVis() and r ~= nil and r.kind == "trinket"
    end, { "onlyOnUse" })
    Options.BuildYield()
    AT.RowInput(pg, "Item IDs",
        function()
            local r = SelIcon()
            return r and Options.ItemIDsText(r.driver) or ""
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            local ids = Options.ParseSpellIDs(v)
            if #ids > 0 then
                Options.SetItemIDs(r.driver, ids)
                -- one item names the icon after itself; a list keeps its name
                local nm = #ids == 1 and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(ids[1])
                if nm then r.name = nm end
                Store.Dirty("tree")
                RefreshAll()
            end
        end,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "item"
        end,
        "The tracked item, or several: the icon shows the first one you carry and can use. Retargeting keeps every setting and position.")
    -- A totem icon: what it follows (one totem, a slot, or the totem bar's
    -- pick), the bar's click and key, and its Out of range buff
    -- (UI\AD_TotemOptions.lua).
    Options.BuildYield()
    if Options.TotemTrackRows then
        Options.TotemTrackRows(pg, SelIcon, trackVis, win, function() RefreshAll() end)
    end
    -- A weapon enchant: a hand, and optionally the enchant IDs that count (a
    -- rogue's poison per hand, or every rank of one imbue).
    local enchVis = function()
        local r = SelIcon()
        return trackVis() and r ~= nil and r.kind == "enchant"
    end
    Options.BuildYield()
    AT.RowDropdown(pg, win, "Weapon",
        function() local r = SelIcon() return r and (r.driver.hand or "main") end,
        function(v)
            local r = SelIcon()
            if r then r.driver.hand = v Store.Dirty("style", r.id) end
        end,
        function() return Options.EnchantHandItems() end,
        enchVis)
    -- a "who" gate (Store.IsLoaded), so a change is a load pass
    Options.BuildYield()
    AT.RowToggle(pg, "Only load while this hand holds a weapon",
        function() local r = SelIcon() return r ~= nil and r.driver.onlyArmed == true end,
        function(v)
            local r = SelIcon()
            if r then
                r.driver.onlyArmed = v and true or nil
                Store.Dirty("load")
            end
        end,
        enchVis,
        "With a two-hander, a shield or nothing in this hand, the icon doesn't load. It comes back when you equip a weapon there.")
    Options.BuildYield()
    AT.RowInput(pg, "Enchant IDs",
        function()
            local r = SelIcon()
            return r and Options.EnchantIDsText(r.driver) or ""
        end,
        function(v)
            local r = SelIcon()
            if not r then return end
            Options.SetEnchantIDs(r.driver, Options.ParseSpellIDs(v))
            Store.Dirty("style", r.id)
        end,
        enchVis, "Every enchant ID this icon lights for, separated by commas or spaces. Empty: anything on the weapon. With two of them on the weapon at once, the first listed shows.",
        "Any enchant")
    local nowRow = AT.AddRow(pg, 22, enchVis)
    local nowFS = nowRow:CreateFontString(nil, "OVERLAY")
    nowFS:SetFont(AT.FONT, 11, "")
    nowFS:SetPoint("LEFT", 10, 0)
    nowFS:SetPoint("RIGHT", -10, 0)
    nowFS:SetJustifyH("LEFT")
    nowFS:SetWordWrap(false)
    nowFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    nowRow._sync = function()
        local r = SelIcon()
        nowFS:SetText(r and r.kind == "enchant" and Options.EnchantNowText(r) or "")
    end
    Options.BuildYield()
    AT.RowDropdown(pg, win, "Add one on it now",
        function() return 0 end,
        function(v)
            local r = SelIcon()
            if not (r and type(v) == "number" and v > 0) then return end
            Options.AddEnchantID(r.driver, v)
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        function() return Options.EnchantPickItems(SelIcon()) end,
        enchVis)
    -- every rank of an imbue (Forever): pick a template, then Use
    local tplVis = function() return enchVis() and Options.HasEnchantTemplates() end
    Options.EnchantTemplateGrid(pg, tplVis,
        function() return Options.EnchantTemplatePick(SelIcon()) end,
        function(v) Options.SetEnchantTemplatePick(SelIcon(), v) end,
        false, function() local r = SelIcon() return r and r.driver.hand end)
    Options.BuildYield()
    AT.RowButton(pg, "Use template", function()
        if Options.ApplyEnchantTemplate(SelIcon()) then
            AT.LayoutPage(pg)
            RefreshAll()
        end
    end, tplVis, 120)
    Options.BuildYield()
    AT.RowDesc(pg, "Any spell ID above lights this one icon.", 20,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "aura"
        end)
    -- A Dynamic aura group's live rows carry only buffs on you or your pet and
    -- debuffs on your target; a static group gives every member its own slot.
    Options.BuildYield()
    AT.RowDesc(pg, "A Dynamic group only tracks you, your pet and your target: turn its Dynamic off.", 20,
        function()
            local r = SelIcon()
            if not (trackVis() and r ~= nil and r.kind == "aura" and r.groupId) then return false end
            local g = Store.Get(r.groupId)
            return g ~= nil and g.groupKind == "aura"
                and Store.Resolve(g, "arrangement", "dynamicLayout") == true
                and not Options.AuraLaneInGroupRows(r.driver)
        end)
    Options.BuildYield()
    AT.RowDesc(pg, "Follows your equipped ammo. Nothing to set here.", 20,
        function()
            local r = SelIcon()
            return trackVis() and r ~= nil and r.kind == "ammo"
        end)
    -- A Stance icon: what it shows, then the stance it lights for
    -- (UI\AD_StanceOptions.lua)
    Options.BuildYield()
    SectionRows(pg, "icon", "stance", SelIcon, function()
        local r = SelIcon()
        return trackVis() and r ~= nil and r.kind == "stance"
    end, { "shows" })
    Options.BuildYield()
    if Options.StanceTrackRows then
        Options.StanceTrackRows(pg, SelIcon, trackVis, win, function() RefreshAll() end)
    end

    -- On this icon: what shows over the cooldown (an aura, its totem or a set
    -- duration on cast), then that source's rows; the look is on the
    -- Conditions and Swipe tabs. Offered only with the game's aura container,
    -- without which the aura could not work in combat.
    local ovSecVis = function()
        local r = SelIcon()
        return trackVis() and r ~= nil and NS.DriverAura ~= nil
            and NS.DriverAura.OVERLAY_KINDS[r.kind] == true and NS.DriverAura.IsAvailable() == true
    end
    local function OvPick() return Options.OverlayPick(SelIcon()) end
    local ovVis = function() local p = OvPick() return ovSecVis() and (p == "aura" or p == "both") end
    local ovTotemVis = function() local p = OvPick() return ovSecVis() and (p == "totem" or p == "both") end
    local ovCastVis = function() return ovSecVis() and OvPick() == "cast" end
    Options.BuildYield()
    AT.Section(pg, "On this icon", { visibleFn = ovSecVis })
    Options.BuildYield()
    local ovPickRow = AT.RowDropdown(pg, win, "Show on this icon",
        function() return OvPick() end,
        function(v)
            local r = SelIcon()
            if not r then return end
            Options.SetOverlayPick(r, v)
            -- the phase's rows on Conditions and Swipe come and go with it
            RefreshAll()
        end,
        function() return Options.OVERLAY_PICKS end,
        ovSecVis)
    AT.Tooltip(ovPickRow, "Show on this icon",
        "Over the cooldown, in the look set on Conditions: an aura while it's up, its totem while down (or both, totem first), or a set time after a cast.")
    Options.BuildYield()
    AT.RowInput(pg, "Totem from spell ID",
        function() return Options.OverlaySpellsText(SelIcon()) end,
        function(v) Options.SetOverlaySpells(SelIcon(), v, true) end,
        ovTotemVis,
        "The spell that puts the totem down, any rank. Empty: this icon's spell.",
        function() return Options.OverlaySpellHint(SelIcon()) end)
    Options.BuildYield()
    AT.RowInput(pg, "Starts when you cast",
        function() return Options.OverlaySpellsText(SelIcon()) end,
        function(v) Options.SetOverlaySpells(SelIcon(), v) end,
        ovCastVis,
        "Spell IDs whose cast starts the time, any rank, separated by commas. Empty: this icon's spell.",
        function() return Options.OverlaySpellHint(SelIcon()) end)
    Options.BuildYield()
    AT.RowInput(pg, "Lasts (seconds)",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return (ov and tonumber(ov.seconds)) and tostring(ov.seconds) or ""
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            local n = tonumber(v)
            ov.seconds = (n and n > 0) and math.min(n, 3600) or nil
            Store.Dirty("style", r.id)
        end,
        ovCastVis,
        "How long it shows after each cast.",
        "e.g. 10")
    Options.BuildYield()
    local ovRecastRow = AT.RowDropdown(pg, win, "When cast again",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return (ov and ov.recast) or "restart"
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            ov.recast = (v ~= "restart") and v or nil
            Store.Dirty("style", r.id)
        end,
        function()
            local out = {}
            for _, k in ipairs(Schema.CUSTOM_START_MODES) do
                out[#out + 1] = { value = k, text = Schema.CUSTOM_START_MODE_LABELS[k] }
            end
            return out
        end,
        ovCastVis)
    AT.Tooltip(ovRecastRow, "When cast again",
        "A cast while it runs: start it over, add the seconds to what is left, or leave it running as it is.")
    Options.BuildYield()
    AT.RowInput(pg, "Ends early when you cast",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return (ov and type(ov.endSpells) == "table") and table.concat(ov.endSpells, ", ") or ""
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            local ids = Options.ParseSpellIDs(v)
            ov.endSpells = (#ids > 0) and ids or nil
            Store.Dirty("style", r.id)
        end,
        ovCastVis,
        "Spell IDs whose cast ends it before its time, such as a spender. Optional.",
        "optional")
    Options.BuildYield()
    AT.RowToggle(pg, "Ends when you die",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return ov ~= nil and ov.endOnDeath == true
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            ov.endOnDeath = v and true or nil
            Store.Dirty("style", r.id)
        end,
        ovCastVis)
    Options.BuildYield()
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
    Options.BuildYield()
    AT.RowToggle(pg, "Follow my rank",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return ov ~= nil and ov.followRank ~= false
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            if v then ov.followRank = nil else ov.followRank = false end
            Store.Dirty("style", r.id)
        end,
        function() return ovVis() and NS.IsForever == true end,
        Options.FOLLOW_RANK_DESC)
    Options.BuildYield()
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
            if not NS.DriverAura.TwoUnits(ov) and not Options.AuraUnitAllowed(ov, unit, v) then unit = "target" end
            ov.unit = unit
            Store.Dirty("style", r.id)
        end,
        function() return {
            { value = "buff", text = "Buff" },
            { value = "debuff", text = "Debuff" },
        } end,
        ovVis)
    Options.BuildYield()
    local ovUnitRow = AT.RowDropdown(pg, win, "On unit",
        function()
            local ov = Options.OverlayOf(SelIcon())
            return ov and Options.UnitPick(ov) or "player"
        end,
        function(v)
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return end
            Options.SetUnitPick(ov, v)
            Store.Dirty("style", r.id)
        end,
        function()
            local r = SelIcon()
            local ov = Options.OverlayOf(r)
            if not ov then return {} end
            return Options.UnitPickItems(r, ov)
        end,
        ovVis)
    AT.Tooltip(ovUnitRow, "On unit",
        "Who carries the aura: you for a buff you put up, your target for a debuff you put on it. You, then your target shows yours on you first, as the Cooldown Manager does. Buffs on enemy creatures and debuffs on friends stay dark: the game hides them from addons.")
    Options.BuildYield()
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

    -- a Custom Icon's tracking rows and its Triggers tab (UI\AD_CustomOptions.lua)
    Options.BuildYield()
    if Options.CustomIconRows then
        Options.CustomIconRows(pg, SelIcon, IconTabVisible("Tracking"), IconTabVisible("Triggers"), win)
    end
    -- a Special Aura's tracking rows (UI\AD_SpecialOptions.lua)
    Options.BuildYield()
    if Options.SpecialIconRows then Options.SpecialIconRows(pg, SelIcon, IconTabVisible("Tracking"), win) end

    Options.BuildYield()
    ConditionRows(pg, SelIcon, IconTabVisible("Load Conditions"))

    -- Icon blocks: titled sections of schema rows, each on a tab and a sub-tab
    -- (sub nil: the tab stacks its blocks). A block hides when none of its
    -- rows apply to the icon's kind; each sub-tab ends with one push bar over
    -- every block it shows (SubPush).
    local ET = Options.EditorTabs
    local function Block(tabName, sub, title, section, fields, o)
        o = o or {}
        local def = { tab = tabName, title = title, section = section, fields = fields, sub = sub,
            kindOnly = o.kindOnly, applies = o.applies, parts = { { section = section, fields = fields } } }
        SEC_LISTS[tabName] = SEC_LISTS[tabName] or {}
        table.insert(SEC_LISTS[tabName], def)
        -- the block's own gate, read when asked (a block may set it later)
        def.lookWhen = function(r) return def.applies == nil or def.applies(r) == true end
        if not o.noLook then
            Options.LookBlock("icon", tabName, title, section, fields, sub, { fx = (o.fx or o.fxKind) and true or nil,
                labels = o.labels, kindOnly = o.kindOnly, when = def.lookWhen })
        end
        local tabVis = IconTabVisible(tabName)
        def.vis = function()
            if not tabVis() then return false end
            local r = SelIcon()
            if not (r and BlockApplies(r, def)) then return false end
            return SubOpen(tabName, sub)
        end
        -- An effect block of the Conditions tab: o.fx, its key in the states'
        -- effect lists; o.fxKind, rows every state's effect shares (the sound
        -- channel). Nothing is drawn here: the editor under a table row draws
        -- it (UI\AD_EditorTabs.lua), from these: a card's switch (o.card), its
        -- words (o.labels), its line's name (o.lineName, false for none), its
        -- own lit test (o.lit), its note (o.note) and onOn.
        if ET and (o.fx or o.fxKind) then
            def.isCard = o.card ~= nil
            def.labels, def.lit, def.onOn, def.note = o.labels, o.lit, o.onOn, o.note
            def.lineName = o.lineName
            if o.card then def.cardWhen, def.word = o.card.when, o.card.word end
            if o.fx then ET.FxBlock(o.fx, def) else ET.FxKindBlock(o.fxKind, def) end
            return def
        end
        if o.card and ET then
            -- a card (o.card: its when words and the switch's name): the
            -- first field is the switch in its header, the rest dim while off
            def.isCard = true
            local card = ET.CardStart(pg, { vis = def.vis, ctx = SelIcon, family = "icon",
                section = section, switch = fields[1], name = title, when = o.card.when, word = o.card.word })
            local rest = {}
            for i = 2, #fields do rest[#rest + 1] = fields[i] end
            SectionRows(pg, "icon", section, SelIcon, def.vis, rest, { labels = o.labels, dimDep = fields[1] })
            ET.CardEnd(card)
            def.card = card
            return def
        end
        -- o.side: "L" / "R", two blocks on one line (the R one titled " ",
        -- named for the search by o.searchTitle)
        AT.Section(pg, title, { visibleFn = def.vis, side = o.side })
        if o.searchTitle then pg._curSection.searchTitle = o.searchTitle end
        SectionRows(pg, "icon", section, SelIcon, def.vis, fields,
            o.labels and { labels = o.labels, searchLabels = o.searchLabels } or nil)
        return def
    end
    -- a block's rows of one more section join its push list
    local function AddPart(def, section, fields)
        for _, p in ipairs(def.parts) do
            if p.section == section then
                for _, f in ipairs(fields) do p.fields[#p.fields + 1] = f end
                return
            end
        end
        def.parts[#def.parts + 1] = { section = section, fields = fields }
    end
    -- A titled group inside a block: it shows with the block (o.vis narrows
    -- it) and joins its push list.
    local function Sub(def, title, section, fields, o)
        o = o or {}
        local vis = o.vis or def.vis
        AT.Section(pg, title, { visibleFn = vis })
        SectionRows(pg, "icon", section, SelIcon, vis, fields, o.labels and { labels = o.labels } or nil)
        if not o.noLook then
            Options.LookBlock("icon", def.tab, title, section, fields, def.sub,
                { labels = o.labels, kindOnly = def.kindOnly, when = def.lookWhen })
        end
        AddPart(def, section, fields)
    end
    -- More rows in the block's own section, from another schema section.
    local function More(def, section, fields, o)
        o = o or {}
        SectionRows(pg, "icon", section, SelIcon, o.vis or def.vis, fields,
            o.labels and { labels = o.labels, searchLabels = o.searchLabels } or nil)
        if not o.noLook then
            Options.LookBlock("icon", def.tab, def.title, section, fields, def.sub,
                { labels = o.labels, kindOnly = def.kindOnly, when = def.lookWhen })
        end
        AddPart(def, section, fields)
    end
    -- A sub-tab of bespoke rows (Fade When, Anchor): shown while applies(rec)
    -- holds, no push bar. Returns the rows' vis.
    local function Pane(tabName, sub, applies)
        local def = { title = sub, sub = sub, fields = {}, applies = applies, pane = true }
        SEC_LISTS[tabName] = SEC_LISTS[tabName] or {}
        table.insert(SEC_LISTS[tabName], def)
        local tabVis = IconTabVisible(tabName)
        return function()
            if not tabVis() then return false end
            local r = SelIcon()
            if not (r and BlockApplies(r, def)) then return false end
            return SubOpen(tabName, sub)
        end
    end
    -- The push bar at the end of a sub-tab (or of a stacked tab): the rows of
    -- every block it shows, one part per pushable section.
    local function SubPush(tabName, sub)
        local tabVis = IconTabVisible(tabName)
        local function Parts()
            local r = SelIcon()
            local out, bySec = {}, {}
            if not r then return out end
            local function take(p)
                local s = Schema.icon[p.section]
                if not (s and s.push) then return end
                local e = bySec[p.section]
                if not e then
                    e = { section = p.section, fields = {}, has = {} }
                    bySec[p.section] = e
                    out[#out + 1] = e
                end
                for _, f in ipairs(p.fields) do
                    if not e.has[f] then
                        e.has[f] = true
                        e.fields[#e.fields + 1] = f
                    end
                end
            end
            for _, def in ipairs(SEC_LISTS[tabName] or {}) do
                if def.sub == sub and not def.pane and BlockApplies(r, def) then
                    if def.partsFn then
                        for _, p in ipairs(def.partsFn(r)) do take(p) end
                    end
                    for _, p in ipairs(def.parts or {}) do take(p) end
                end
            end
            return out
        end
        local vis = function()
            if not (tabVis() and SubOpen(tabName, sub)) then return false end
            return #Parts() > 0
        end
        AT.Section(pg, nil, { visibleFn = vis })
        PushBar(pg, SelIcon, Parts, vis)
    end
    local NOT_AURA = { spell = true, item = true, trinket = true, timer = true, totem = true, ammo = true,
        enchant = true }

    -- Appearance > Icon: the size, the look and the art (a totem's pulse timer
    -- too: it is drawn on the icon).
    local sizeDef = Block("Appearance", "Icon", "Size", "position", {
        "useGroupScale", "iconScale", "iconShape", "iconWidth", "iconHeight",
    })
    Options.BuildYield()
    AT.RowDesc(pg, "In a group the group's size applies until Use group scale is off.", 20,
        function()
            local r = SelIcon()
            return sizeDef.vis() and r ~= nil and r.groupId ~= nil
        end)
    -- a Time left group draws one sorted row per unit, so a member's own look
    -- never reaches play
    Options.BuildYield()
    AT.RowDesc(pg, "Its group orders by Time left, so in play it wears a new aura icon's look.", 20,
        function()
            local r = SelIcon()
            local _, packed = InAuraGroup(r)
            return sizeDef.vis() and packed
                and Store.Resolve(Store.Get(r.groupId), "arrangement", "dynamicSort") == "time"
        end)
    local lookDef = Block("Appearance", "Icon", "Look", "appearance", {
        "cdmLook", "iconMask", "cropToShape", "zoom", "aspectRatio", "cropFocus", "alpha", "padding", "keepBright", "keepBrightAllowDesat",
    })
    -- a skin's rows step aside (Options.FieldShows): one line says why, naming
    -- the Cooldown Manager look or the Masque skin
    local function SkinNote(def, text, cdm)
        AT.RowDesc(pg, text, 20, function()
            local r = SelIcon()
            if not (def.vis() and r ~= nil and NS.Skins ~= nil and NS.Skins.Skinned(r)) then return false end
            local look = NS.Skins.CdmLook ~= nil and NS.Skins.CdmLook(r) == true
            return look == (cdm == true)
        end)
    end
    SkinNote(lookDef, "Its Masque skin sets the picture's size, crop and shape.")
    SkinNote(lookDef, "The Cooldown Manager look sets the picture's size, crop and shape.", true)
    -- the switch reads the icon's own; its group's switch can turn the look on too
    Options.BuildYield()
    AT.RowDesc(pg, "Its group turns this look on: the group's Appearance > Icons.", 20, function()
        local r = SelIcon()
        if not (lookDef.vis() and r ~= nil and r.groupId and NS.Skins and NS.Skins.CdmLook) then return false end
        return Store.Resolve(r, "appearance", "cdmLook") ~= true and NS.Skins.CdmLook(Store.Get(r.groupId)) == true
    end)
    Sub(lookDef, "Art", "appearance", { "forceHideIcon", "customIconFrom", "customIcon", "activeArt" })
    Options.BuildYield()
    AT.RowDesc(pg, "Conditions > By State sets the art while the aura is up or missing.", 20,
        function()
            local r = SelIcon()
            return lookDef.vis() and r ~= nil and r.kind == "aura"
        end)
    local pulseDef = Block("Appearance", "Icon", "Pulse timer", "pulse", {
        "pulseShow", "pulseInterval", "pulseColor", "pulseHeight",
    })
    Options.BuildYield()
    AT.RowDesc(pg, "Refills at every pulse, counted from when the totem went down.", 20, pulseDef.vis)
    SubPush("Appearance", "Icon")

    -- Appearance > Border
    local borderDef = Block("Appearance", "Border", "Border", "appearance", {
        "borderEnabled", "borderColor", "borderClassColor", "borderThickness", "borderInset", "borderFollowsGrey",
        -- aura icons: the border takes the aura's dispel-type colour
        "dispelBorder", "dispelBorderStyle",
    })
    SkinNote(borderDef, "Its Masque skin draws the border and the shadow.")
    SkinNote(borderDef, "The Cooldown Manager look draws the border and the shadow.", true)
    -- The Cooldown Manager's soft shadow frame.
    Sub(borderDef, "Shadow", "appearance", { "shadowEnabled", "shadowSize" })
    -- the Cooldown Manager's dark overlay on a spell out of range
    Sub(borderDef, "Out-of-range shadow", "states", { "rangeShadow", "rangeShadowSize" })
    SubPush("Appearance", "Border")

    -- Appearance > Swipe: the cooldown's swipe, or the aura's (ammo has none).
    local swipeDef = Block("Appearance", "Swipe", "Swipe", "swipe", {
        "showSwipe", "swipeColor", "reverse", "swipeWaitForNoCharges",
    })
    Sub(swipeDef, "Inset", "swipe", { "swipeInset", "separateInsets", "swipeInsetX", "swipeInsetY" })
    -- a diamond or hexagon icon's swipe draws no edge line (Factory.SHAPE_EDGE)
    local function NoEdgeNote(def)
        AT.RowDesc(pg, "Diamond and hexagon icons draw no edge line.", 20, function()
            local r = SelIcon()
            local F = NS.Factory
            local k = r and F and F.MaskOf(r)
            return def.vis() and k ~= nil and not F.SHAPE_EDGE[k]
        end)
    end
    NoEdgeNote(Block("Appearance", "Swipe", "Edge & finish", "swipe", {
        "showEdge", "edgeColor", "edgeScale", "edgeWaitForNoCharges", "showBling",
    }))
    -- The wand rows follow the schema's class and Forever gates, and so does
    -- the name: elsewhere it is plain "GCD".
    local wandGate = Schema.icon.swipe.fields.wandSwipe.classOnly
    local gcdTitle = (NS.IsForever == true and wandGate and wandGate[Store.ClassTag() or ""])
        and "GCD & Wand" or "GCD"
    Block("Appearance", "Swipe", gcdTitle, "swipe", {
        "gcdSwipe", "gcdSwipeColor", "wandSwipe", "wandSwipeColor",
    })
    -- the aura's own swipe (our Cooldown widget on its button): a spell, item or
    -- trinket icon's aura phase (the Cooldown Manager's gold by default), an aura icon's
    local OV_KINDS = { spell = true, item = true, trinket = true }
    NoEdgeNote(Block("Appearance", "Swipe", "Aura swipe", "auraSwipe", {
        "swipeShow", "overlaySwipeColor", "overlaySwipeReverse", "swipeEdge", "edgeColor", "edgeScale", "swipeBling",
        "swipeInset", "separateInsets", "swipeInsetX", "swipeInsetY",
    }, { kindOnly = OV_KINDS }))
    NoEdgeNote(Block("Appearance", "Swipe", "Aura swipe", "auraSwipe", {
        "swipeShow", "swipeColor", "swipeReverse", "swipeEdge", "edgeColor", "edgeScale", "swipeBling",
        "swipeInset", "separateInsets", "swipeInsetX", "swipeInsetY",
    }, { kindOnly = "aura", noLook = true }))
    -- one look block carries both kinds' rows
    Options.BuildYield()
    Options.LookBlock("icon", "Appearance", "Aura swipe", "auraSwipe", { "swipeColor", "swipeReverse" }, "Swipe")
    SubPush("Appearance", "Swipe")

    -- Conditions > By State: every state the kind has in one table (opacity,
    -- grey out, tint, its effects), the switches it needs, then the rules for
    -- when states overlap. UI\AD_EditorTabs.lua draws the table and the editor
    -- under a row; the effect blocks below are filed under the states' keys.
    local stateTab = IconTabVisible("Conditions")
    local stateDef = { tab = "Conditions", title = "How it looks in each state", sub = "By State",
        fields = {}, parts = {},
        applies = function(r) return ET ~= nil and ET.StatesFor(r) ~= nil end,
        partsFn = function(r) return ET.StateParts(r) end }
    SEC_LISTS["Conditions"] = SEC_LISTS["Conditions"] or {}
    table.insert(SEC_LISTS["Conditions"], stateDef)
    stateDef.vis = function()
        if not stateTab() then return false end
        local r = SelIcon()
        if not (r and BlockApplies(r, stateDef)) then return false end
        return SubOpen("Conditions", "By State")
    end
    Options.BuildYield()
    AT.Section(pg, stateDef.title, { visibleFn = stateDef.vis })
    if ET then
        ET.StateTable(pg, SelIcon, stateDef.vis, win)
        ET.StateLooks("Conditions")
    end
    More(stateDef, "auraMissing", { "showWhileMissing" }, { noLook = true })
    -- When Active starts is the clock on its opacity (ET.TimePop): no rows
    -- under the table, only the push parts.
    AddPart(stateDef, "auraActive", { "activeTimeOnly", "activeTimeUnit", "activeTimePct", "activeTimeSec",
        "activeTimeLen", "activeTimeBefore" })
    -- they join the aura's Active state in the looks (as Show while missing
    -- joins Missing): the layout's per-state page and the Defaults page
    Options.BuildYield()
    Options.LookBlock("icon", "Conditions", "Active", "auraActive", { "activeTimeOnly", "activeTimeUnit",
        "activeTimePct", "activeTimeSec", "activeTimeLen", "activeTimeBefore" }, "By State",
        { state = true, kindOnly = "aura" })
    More(stateDef, "outOfStock", { "hideWhenMissing" }, { noLook = true })
    -- an item's switch for its Can't use it row
    More(stateDef, "states", { "itemUsability" }, { noLook = true })
    Options.BuildYield()
    Options.LookBlock("icon", "Conditions", "Missing", "auraMissing", { "showWhileMissing" }, "By State",
        { kindOnly = "aura" })
    Options.BuildYield()
    Options.LookBlock("icon", "Conditions", "Out of stock", "outOfStock", { "hideWhenMissing" }, "By State")
    Options.BuildYield()
    Options.LookBlock("icon", "Conditions", "Can't use it", "states", { "itemUsability" }, "By State",
        { kindOnly = "item" })
    -- An effect block shows for a record when its kind has it and, with a
    -- switch, the switch's row would show; with none, a setting of it can
    -- show (the missing art waits on Show while missing).
    if ET then
        ET.blockShows = function(r, def)
            if not BlockApplies(r, def) then return false end
            local sec = Schema.icon[def.section]
            if def.isCard then
                local sdef = sec and sec.fields[def.fields[1]]
                return sdef ~= nil and Options.FieldShows(r, "icon", def.section, sdef) == true
            end
            for _, f in ipairs(def.fields) do
                local fdef = sec and sec.fields[f]
                if fdef and ET.PairShows(r, def, fdef) then return true end
            end
            return false
        end
    end

    -- Glows: one block per trigger, filed under its state (ET.STATES fx) for
    -- the editor under the table row: the switch and when it fires, then
    -- style, colour and gates, the tuning behind More.
    if ET then
        local W = ET.GLOW_WHEN
        local function Card(title, section, prefix, suffix, switch, when, o, extra)
            local fields, words = ET.GlowCard(section, prefix, suffix, switch, extra)
            o.labels = words
            o.card = { when = when, word = switch }
            o.fx = section .. "." .. prefix .. (suffix or "")
            return Block("Conditions", "By State", title, section, fields, o)
        end
        -- a special icon's glows in its states' words: a deck's procs, or
        -- Nature's Guardian's timer (it keeps When ready). An applies stands
        -- in for the kind check, so each names its kinds.
        local function SpecialTimer(r)
            local SI = NS.SpecialIcon
            local d = SI and SI.Def and SI.Def(r)
            return d ~= nil and d.isTimer == true
        end
        local function Deck(r) return r.kind == "special" and not SpecialTimer(r) end
        local function Timer(r) return r.kind == "special" and SpecialTimer(r) end
        Card("When ready", "states", "readyGlow", nil, "Glow when ready", W.ready,
            { kindOnly = { spell = true, item = true, trinket = true, special = true },
                applies = function(r)
                    local k = r.kind
                    return k == "spell" or k == "item" or k == "trinket" or Timer(r)
                end })
        Card("While procs are left", "states", "readyGlow", nil, "Glow while procs are left",
            "a proc is still in the deck", { kindOnly = { special = true }, noLook = true, applies = Deck })
        -- a totem or an enchant is up or gone, a Custom Icon active or not,
        -- you in a stance or not: the same glows, worded so
        Card("While active", "states", "readyGlow", nil, "Glow while active", W.active,
            { kindOnly = { totem = true, enchant = true, timer = true, stance = true }, noLook = true })
        -- a totem set to one totem: out, but its buff not on you
        Card("While out of range", "states", "totemRangeGlow", nil, "Glow while out of range", W.range,
            { kindOnly = { totem = true }, noLook = true })
        Card("On proc", "states", "procGlow", nil, "Proc glow", W.proc, {})
        Card("When usable", "states", "usableGlow", nil, "Glow when usable", W.usable, {})
        -- a spell's target out of range: the state the table styles too
        Card("When out of range", "states", "rangeGlow", nil, "Glow while out of range", W.outrange,
            { kindOnly = { spell = true }, noLook = true })
        -- a charge spell with a charge left and another on its way
        Card("While recharging", "states", "rechargeGlow", nil, "Glow while recharging", W.recharge,
            { kindOnly = { spell = true }, noLook = true, applies = function(r)
                local D = NS.DriverCooldown
                return D ~= nil and D.IsCharge ~= nil and D.IsCharge(r)
            end })
        -- a charge spell's cooldown is every charge spent: Depleted
        Card("While on cooldown", "states", "cooldownGlow", nil, "Glow while on cooldown", W.cooldown,
            { kindOnly = { spell = true, item = true, trinket = true }, applies = function(r)
                local k = r.kind
                return (k == "spell" and not ET.IsCharge(r)) or k == "item" or k == "trinket"
            end })
        Card("While depleted", "states", "cooldownGlow", nil, "Glow while depleted", "every charge is spent",
            { kindOnly = { spell = true }, noLook = true, applies = function(r)
                return r.kind == "spell" and ET.IsCharge(r)
            end })
        Card("While all procs are used", "states", "cooldownGlow", nil, "Glow while all procs are used",
            "every proc in the deck is used", { kindOnly = { special = true }, noLook = true, applies = Deck })
        Card("While the timer runs", "states", "cooldownGlow", nil, "Glow while the timer runs",
            "its internal cooldown runs", { kindOnly = { special = true }, noLook = true, applies = Timer })
        Card("While not active", "states", "cooldownGlow", nil, "Glow while not active", W.inactive,
            { kindOnly = { timer = true }, noLook = true })
        -- ammo and pet warnings (Drivers\AD_DriverWarn.lua), for the classes
        -- with ammo or a pet
        Card("Warning", "states", "warnGlow", nil, "Warning glow", W.warn, { noLook = true,
            applies = function(r)
                return r.kind ~= "aura" and Schema.WARN_CLASSES[Store.ClassTag() or ""] == true
            end }, {
            { "warnAmmoBelow", "Ammo at or below" },
            { "warnPetHealth", "Pet health under (%)" },
            { "warnPetMood", "Glow while the pet is" },
        })
        -- Shoot or Auto Shot repeating, melee Attack swinging, a pet spell on
        -- autocast (Drivers\AD_DriverToggle.lua): on the spell icons that toggle
        Card("While toggled on", "states", "toggleGlow", nil, "Glow while toggled on", W.toggle, { noLook = true,
            applies = function(r)
                return NS.DriverToggle ~= nil and NS.DriverToggle.IsToggle(r) and not Schema.QueueShows(r)
            end })
        -- the game's Assisted Highlight suggests it next (retail)
        Card("While suggested", "states", "assistGlow", nil, "Glow while suggested", W.assist, { kindOnly = "spell",
            applies = function() return NS.DriverAssist ~= nil and NS.DriverAssist.Available() end })
        -- a next-swing ability's toggle is its queue (Heroic Strike, Cleave,
        -- Maul, Raptor Strike): the same glow, worded for it
        Card("While queued", "states", "toggleGlow", nil, "Glow while queued", "it waits for your next swing",
            { noLook = true, applies = Schema.QueueShows })
        Block("Conditions", "By State", "Checkmark while queued", "states", { "queueCheck" }, {
            fx = "states.queueCheck", card = {}, lineName = "Checkmark",
            applies = Schema.QueueShows,
            lit = function(r) return Store.Resolve(r, "states", "queueCheck") == true end })
        Block("Conditions", "By State", "Short of rage or mana", "states", { "queueShort", "queueShortColor" }, {
            fx = "states.queueShort", card = {}, labels = { queueShortColor = "Tint" }, applies = Schema.QueueShows,
            lit = function(r) return Store.Resolve(r, "states", "queueShort") == true end })
        -- The aura's glows ride its engine button, so they work in combat and
        -- in aura groups: glow 1 (a layout's looks carry it) and glows 2-4 on
        -- an aura icon, the aura phase's glow on a spell icon. An aura icon's
        -- glow sits under Active or Missing by its Glow when; one switched on
        -- under Missing glows while the aura is missing.
        Card("Aura active", "auraActive", "activeGlow", nil, "Glow while the aura is up", W.overlay,
            { kindOnly = { spell = true, item = true, trinket = true }, noLook = true })
        Card("Glow 1", "auraActive", "activeGlow", nil, "Glow while active", ET.AuraGlowWhen(nil),
            { kindOnly = "aura", onOn = function(r) ET.AuraGlowAdded(r, nil) end })
        for k = 2, Schema.AURA_GLOW_SLOTS do
            local sfx = tostring(k)
            Card("Glow " .. k, "auraActive", "activeGlow", sfx, "Glow while active",
                ET.AuraGlowWhen(sfx), { kindOnly = "aura", noLook = true,
                    onOn = function(r) ET.AuraGlowAdded(r, sfx) end })
        end
    end

    -- Sounds: one block per moment a sound can play, under its state, then the
    -- channel under any state's Sound. A weapon enchant's two mark it going on
    -- and falling off (NS.DriverEnchant plays them on a real change only).
    if ET then
        local CD_SOUNDS = { spell = true, item = true, trinket = true, timer = true }
        -- a charge spell's cooldown starts with its last charge spent
        local function NotCharge(r) return CD_SOUNDS[r.kind] == true and not (r.kind == "spell" and ET.IsCharge(r)) end
        local function Charge(r) return r.kind == "spell" and ET.IsCharge(r) end
        for _, s in ipairs({
            { "When ready", "readySound", CD_SOUNDS },
            { "When the cooldown starts", "cooldownSound", CD_SOUNDS, NotCharge },
            { "When the last charge is spent", "cooldownSound", CD_SOUNDS, Charge },
            { "When recharging starts", "rechargeSound", CD_SOUNDS },
            { "When a charge returns", "chargeGainedSound", CD_SOUNDS },
            { "When usable", "usableSound", CD_SOUNDS },
            { "When it goes on", "readySound", "enchant" },
            { "When it falls off", "cooldownSound", "enchant" },
            { "On proc", "procSound", "special" },
            { "When the next draw is guaranteed", "sureSound", "special" },
            { "When the aura appears", "auraGainSound", "aura", nil, true },
            { "When it gains a stack", "auraStackSound", "aura", nil, true },
            { "When the aura drops", "auraLostSound", "aura", nil, true },
        }) do
            local en, snd = s[2] .. "Enabled", s[2]
            -- an aura's moment is the game's to play: a sound, never words
            local say = (not s[5]) and (s[2]:gsub("Sound$", "Speech")) or nil
            -- lit once it plays something: switched on with a sound or words
            Block("Conditions", "By State", s[1], "alerts", say and { en, snd, say } or { en, snd }, {
                kindOnly = s[3], applies = s[4], noLook = true,
                labels = { [snd] = "Sound", [say or snd] = say and "Say" or "Sound" }, card = {}, fx = "alerts." .. en,
                lit = function(r)
                    if Store.Resolve(r, "alerts", en) ~= true then return false end
                    return (Store.Resolve(r, "alerts", snd) or "") ~= ""
                        or (say ~= nil and (Store.Resolve(r, "alerts", say) or "") ~= "")
                end })
        end
    end
    Block("Conditions", "By State", "Sound channel", "alerts", { "soundChannel" }, { fxKind = "sound",
        lineName = false, note = function(r)
            return r.kind == "aura" and "The game plays aura sounds itself, so they work in combat, for anyone's copy of the aura."
                or nil
        end })

    -- Art: the picture while the aura is up (a spell icon's aura phase too)
    -- or missing, lit while it is not the default.
    Block("Conditions", "By State", "Art while active", "auraActive", {
        "overlayArt", "activeIconFrom", "activeIcon",
    }, { fx = "art.active", lineName = false,
        labels = { overlayArt = "Show", activeIconFrom = "Icon from", activeIcon = "ID" }, lit = function(r)
        return (tonumber(Store.Resolve(r, "auraActive", "activeIcon")) or 0) ~= 0
            or (r.kind ~= "aura" and Store.Resolve(r, "auraActive", "overlayArt") == "aura")
    end })
    Block("Conditions", "By State", "Art while missing", "auraMissing", { "missingIconFrom", "missingIcon" },
        { fx = "art.missing", lineName = false, labels = { missingIconFrom = "Icon from", missingIcon = "ID" },
            lit = function(r)
            return (tonumber(Store.Resolve(r, "auraMissing", "missingIcon")) or 0) ~= 0
        end })

    -- the rules that decide which look wins, two to a line (an aura icon has
    -- its own pair). Wait for no charges is Recharging's look pick now.
    -- the usability rules fold under the left half, the text ones under the right
    Block("Conditions", "By State", "When states overlap", "states", { "procOverride", "procOverrideWhen", "usableOverride",
        "usabilityOnCooldown", "usabilityReadyOnly", "usabilityAlphaReplaces", "readyGreyUsable" },
        { kindOnly = NOT_AURA, side = "L", labels = { procOverride = "A proc shows it at full opacity",
            usableOverride = "Usable shows it at full opacity" } })
    Block("Conditions", "By State", " ", "states",
        { "preserveDurationText", "preserveTextWhen", "labelsFullOpacity", "ignoreHardICD" },
        { kindOnly = NOT_AURA, side = "R", noLook = true, searchTitle = "When states overlap" })
    Options.BuildYield()
    Options.LookBlock("icon", "Conditions", "When states overlap", "states",
        { "preserveDurationText", "preserveTextWhen", "labelsFullOpacity", "ignoreHardICD" },
        "By State", { kindOnly = NOT_AURA })
    Block("Conditions", "By State", "When states overlap", "auraMissing", { "missingPreserveText" },
        { kindOnly = "aura", side = "L" })
    Block("Conditions", "By State", " ", "auraActive", { "activePreserveText", "activeLabelsBright" },
        { kindOnly = "aura", side = "R", noLook = true, searchTitle = "When states overlap" })
    Options.BuildYield()
    Options.LookBlock("icon", "Conditions", "When states overlap", "auraActive", { "activePreserveText", "activeLabelsBright" },
        "By State", { kindOnly = "aura" })
    SubPush("Conditions", "By State")

    -- Conditions > Fade When: the fade rules. A member its aura group packs
    -- (Close gaps on) fades with the group, so it has none.
    Options.BuildYield()
    VisibilityRows(pg, SelIcon, Pane("Conditions", "Fade When",
        function(r)
            local _, packed = InAuraGroup(r)
            return not packed
        end))

    -- Text > Duration
    local durDef = Block("Text", "Duration", "Duration text", "text", {
        "durationText", "durationRounding", "durationFont", "durationSize", "durationColor", "durationOutline",
        "durationShadow", "durationShadowColor", "durationShadowX", "durationShadowY", "durationAnchor", "durationX", "durationY",
    })
    Sub(durDef, "Format", "text", {
        "durationAbbrev", "durationDecimals", "durationDecimalThreshold", "durationShowBelow", "hideDurWithCharges",
    })
    -- One band when switched on; "+ Add band" (durBandCount) under the bands
    Sub(durDef, "Color by time left", "text", {
        "durationColorBands", "durationBandsPercent",
        "durBand1Sec", "durBand1Pct", "durBand1Color",
        "durBand2Sec", "durBand2Pct", "durBand2Color",
        "durBand3Sec", "durBand3Pct", "durBand3Color",
        "durBand4Sec", "durBand4Pct", "durBand4Color",
        "durBand5Sec", "durBand5Pct", "durBand5Color",
        "durBandCount",
    })
    -- a special icon's deck or counter has no time left: only Nature's
    -- Guardian (a timer) keeps Duration. The block's own test, kept.
    do
        local plain = { section = durDef.section, fields = durDef.fields, parts = durDef.parts }
        durDef.applies = function(r)
            if r.kind == "special" and not (Options.SpecialIsTimer and Options.SpecialIsTimer(r)) then
                return false
            end
            return BlockApplies(r, plain)
        end
    end
    SubPush("Text", "Duration")

    -- Text > Stacks: the count, its colours, and a spell's ammo text. An ammo
    -- icon's and a group buff's number have Text > Count, in their own words.
    local stackDef = Block("Text", "Stacks", "Stack & charges", "text", {
        "stackText", "stackFont", "stackSize", "stackColor", "stackOutline", "stackShadow",
        "stackShadowColor", "stackShadowX", "stackShadowY", "stackAnchor", "stackX", "stackY", "hideChargeAtZero",
        "stackShowZero", "stackShowSingle",
    }, { kindOnly = { spell = true, item = true, timer = true, aura = true, enchant = true } })
    -- an aura's count is the game button's, which cannot move in combat
    Options.BuildYield()
    if Options.TextPinRows then
        Options.TextPinRows(pg, SelIcon, function()
            local r = SelIcon()
            return stackDef.vis() and r ~= nil and r.kind ~= "aura" and Store.Resolve(r, "text", "stackText") ~= false
        end, "icon", "text", "stackPinTo", "stackPinTarget", win, "Stack text")
    end
    Sub(stackDef, "Color by count", "text", {
        "stackColorBands",
        "stkBand1Min", "stkBand1Color", "stkBand2Min", "stkBand2Color",
        "stkBand3Min", "stkBand3Color",
        "stkBand4Min", "stkBand4Color", "stkBand5Min", "stkBand5Color",
        "stkBand6Min", "stkBand6Color",
        "stkBandCount",
    })
    -- The ammo count's thresholds sit with the text that shows it: the ammo
    -- icon's stack text, a spell icon's ammo text.
    local AMMO_COLORS = {
        "ammoCountColors", "ammoCount1", "ammoCount1Color",
        "ammoCount2", "ammoCount2Color", "ammoCount3", "ammoCount3Color", "ammoCountSteps",
    }
    -- spell only: the ammo thresholds above also name the ammo kind
    local ammoDef = Block("Text", "Stacks", "Ammo stack text", "text", {
        "ammoText", "ammoFont", "ammoSize", "ammoColor", "ammoOutline", "ammoShadow",
        "ammoAnchor", "ammoX", "ammoY",
    }, { kindOnly = "spell" })
    Sub(ammoDef, "Color by ammo count", "text", AMMO_COLORS, { noLook = true, vis = function()
        local r = SelIcon()
        return ammoDef.vis() and r ~= nil and Schema.AmmoCountShown(r)
    end })
    Options.BuildYield()
    Options.LookBlock("icon", "Text", "Color by ammo count", "text", AMMO_COLORS, "Stacks", { kindOnly = "spell" })
    SubPush("Text", "Stacks")

    -- Text > Count: an ammo icon's and a group buff's number, in their words.
    -- Their look rows stay the generic block's (noLook).
    local function CountLabels(word)
        return { stackText = word, stackFont = word .. " font", stackSize = word .. " size",
            stackColor = word .. " color", stackOutline = word .. " outline", stackShadow = word .. " shadow",
            stackAnchor = word .. " anchor", stackX = word .. " X", stackY = word .. " Y" }
    end
    local ammoCountDef = Block("Text", "Count", "Ammo count", "text", {
        "stackText", "stackFont", "stackSize", "stackColor", "stackOutline", "stackShadow",
        "stackAnchor", "stackX", "stackY",
    }, { kindOnly = "ammo", noLook = true, labels = CountLabels("Ammo count text"), searchLabels = true })
    Sub(ammoCountDef, "Color by ammo count", "text", AMMO_COLORS, { noLook = true, vis = function()
        local r = SelIcon()
        return ammoCountDef.vis() and r ~= nil and Schema.AmmoCountShown(r)
    end })
    -- the Defaults page shows Count in each kind's own words; the layout looks
    -- keep the generic Stack & charges block for these rows (defaultsOnly)
    local STACK_LOOK = { "stackText", "stackFont", "stackSize", "stackColor", "stackOutline", "stackShadow",
        "stackAnchor", "stackX", "stackY" }
    Options.BuildYield()
    Options.LookBlock("icon", "Text", "Ammo count", "text", STACK_LOOK, "Count",
        { kindOnly = "ammo", labels = CountLabels("Ammo count text"), defaultsOnly = true })
    Options.BuildYield()
    Options.LookBlock("icon", "Text", "Color by ammo count", "text", AMMO_COLORS, "Count",
        { kindOnly = "ammo", defaultsOnly = true })
    local gbCountDef = Block("Text", "Count", "Group count", "text", { "stackText" },
        { kindOnly = "groupbuff", noLook = true, labels = CountLabels("Count text"), searchLabels = true })
    More(gbCountDef, "groupBuff", { "countShows" }, { noLook = true })
    More(gbCountDef, "text", {
        "stackFont", "stackSize", "stackColor", "stackOutline", "stackShadow",
        "stackAnchor", "stackX", "stackY",
    }, { noLook = true, labels = CountLabels("Count text"), searchLabels = true })
    Options.BuildYield()
    Options.LookBlock("icon", "Text", "Group count", "text", STACK_LOOK, "Count",
        { kindOnly = "groupbuff", labels = CountLabels("Count text"), defaultsOnly = true })
    Options.BuildYield()
    Options.LookBlock("icon", "Text", "Group count", "groupBuff", { "countShows" }, "Count", { kindOnly = "groupbuff" })
    SubPush("Text", "Count")

    -- Text > a special icon's own texts: Deck Position, Proc Count, Counter,
    -- Proc Chance (UI\AD_SpecialOptions.lua)
    if Options.SpecialTextTabs then
        Options.SpecialTextTabs({ Block = Block, More = More, SubPush = SubPush, pg = pg, ctx = SelIcon, win = win })
    end

    -- Text > Custom Text & Keybind: texts on the icon, each short until used.
    -- each custom text and the keybind may ride another frame (TextPinRows)
    local function LabelPins(def, suf, word)
        if not Options.TextPinRows then return end
        Options.TextPinRows(pg, SelIcon, function()
            local r = SelIcon()
            local t = r and Store.Resolve(r, "label", "labelText" .. suf)
            return def.vis() and t ~= nil and t ~= ""
        end, "icon", "label", "labelPinTo" .. suf, "labelPinTarget" .. suf, win, word)
    end
    LabelPins(Block("Text", "Custom Text & Keybind", "Custom text 1", "label", {
        "labelText", "labelFont", "labelOutline", "labelSize", "labelColor", "labelAnchor",
        "labelX", "labelY", "labelShowReady", "labelShowCooldown", "labelActiveOnly", "labelMissingOnly",
    }), "", "Custom text")
    LabelPins(Block("Text", "Custom Text & Keybind", "Custom text 2", "label", {
        "labelText2", "labelFont2", "labelSize2", "labelColor2", "labelAnchor2",
        "labelX2", "labelY2", "labelShowReady2", "labelShowCooldown2", "labelActiveOnly2", "labelMissingOnly2",
    }), "2", "Custom text 2")
    LabelPins(Block("Text", "Custom Text & Keybind", "Custom text 3", "label", {
        "labelText3", "labelFont3", "labelSize3", "labelColor3", "labelAnchor3",
        "labelX3", "labelY3", "labelShowReady3", "labelShowCooldown3", "labelActiveOnly3", "labelMissingOnly3",
    }), "3", "Custom text 3")
    local kbDef = Block("Text", "Custom Text & Keybind", "Keybind", "keybind", {
        "keybindEnabled", "keybindByName", "keybindStyle", "keybindFont", "keybindOutline", "keybindSize",
        "keybindColor", "keybindAnchor", "keybindX", "keybindY", "keybindReplace",
    })
    Options.BuildYield()
    if Options.TextPinRows then
        Options.TextPinRows(pg, SelIcon, function()
            local r = SelIcon()
            return kbDef.vis() and r ~= nil and Factory.KeybindEnabled(r)
        end, "icon", "keybind", "keybindPinTo", "keybindPinTarget", win, "Keybind")
    end
    Options.BuildYield()
    AT.RowDesc(pg, "Match by spell name finds this spell's key at any rank on your bars.", 20,
        function() return kbDef.vis() and NS.IsForever == true end)
    SubPush("Text", "Custom Text & Keybind")

    -- Position > Position: a free icon's screen spot (a group member's cell
    -- places it), the nudge, and how it takes the mouse.
    local freePosVis = function()
        if not IconTabVisible("Position")() then return false end
        local r = SelIcon()
        if not (r and r.groupId == nil) then return false end
        return SubOpen("Position", "Position")
    end
    Options.BuildYield()
    AT.Section(pg, "Screen position", { visibleFn = freePosVis })
    Options.BuildYield()
    Options.PosRows(pg, SelIcon, freePosVis, function(r)
        -- pinned right now: a gone or hidden target places it free
        return NS.Anchor ~= nil and NS.Anchor.ResolveTarget(r) ~= nil
    end)
    local posDef = Block("Position", "Position", "Position", "position", {
        "offsetX", "offsetY", "strata", "frameLevel",
    })
    -- Aura icons in a packed aura group: the engine lays the row out in play
    -- mode, so only the size fields reach it. A static group's member keeps
    -- its own frame, whose offsets apply in play.
    Options.BuildYield()
    AT.RowDesc(pg, "With Close gaps on, the game places the row: these apply only while this window is open.", 20,
        function()
            if not posDef.vis() then return false end
            local r = SelIcon()
            local _, packed = InAuraGroup(r)
            return r ~= nil and r.kind == "aura" and packed
        end)
    local mouseDef = Block("Position", "Position", "Mouse", "mouse", {
        "clickThrough", "showTooltip",
    })
    Options.BuildYield()
    AT.RowDesc(pg, "Inherit follows the group, then the layout, then Settings.", 20, mouseDef.vis)
    SubPush("Position", "Position")
    -- Position > Anchor: free icons only; a group member's cell places it.
    Options.BuildYield()
    Options.AnchorPickRows(pg, "icon", SelIcon, Pane("Position", "Anchor",
        function(r) return r.groupId == nil end))

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
    -- a group showing every aura on a unit takes no icons; its strip holds
    -- the debuff type picks instead (UI\AD_UnitAuraOptions.lua)
    groupStrip.add:SetShown(not Store.ShowsAll(group))
    if Options.TypeLookStrip then Options.TypeLookStrip(group, groupStrip) end
end

local function RefreshGroupPane()
    local group = SelGroup()
    if not group then return end
    local layout = Store.Get(group.layoutId)
    groupHeader.name:SetText(group.name)
    local btext, restricted = Store.BadgeText(group)
    groupHeader.chip1:Set(btext, restricted and PURPLE or SHR)
    GroupPill(groupHeader.chip2, group.groupKind)
    groupHeader.sub:SetText(layout and ("in " .. layout.name) or "")
    -- a Reminder group's members are reminders (UI\AD_ReminderOptions.lua)
    local rem = group.groupKind == "reminder" and Options.RefreshReminderPane ~= nil
    local addB = groupHeader._btns[2]
    addB.fs:SetText(rem and "+ Add Reminder" or "+ Add Icon")
    addB:SetWidth(rem and 108 or 82)
    addB:SetShown(not Store.ShowsAll(group))
    -- an aura or reminder group never takes a spell/item icon either way
    groupHeader.fillBtn:SetShown(Store.GroupTakes(group, "spell") == true)
    Options.FitHeader(groupHeader)
    if rem then
        Options.RefreshReminderPane(group)
        return
    end
    if Options.HideReminderPane then Options.HideReminderPane() end
    if ui.grpMode == "rem" then ui.grpMode = "grp" end
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
    addIcon.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    addIcon:SetScript("OnClick", function()
        local group = SelGroup()
        if group then Options.OpenAdd(group.layoutId, group.id) end
    end)
    local del = AT.MakeSmallButton(groupPane, "Delete", 56)
    del:SetPoint("RIGHT", addIcon, "LEFT", -5, 0)
    del:SetScript("OnClick", function() Options.ConfirmDelete(SelGroup()) end)
    -- cooldown groups only (Store.GroupTakes): RefreshGroupPane shows/hides it
    local fillBtn = AT.MakeSmallButton(groupPane, "+ From Action Bars", 150)
    fillBtn:SetPoint("RIGHT", del, "LEFT", -5, 0)
    fillBtn:SetScript("OnClick", function()
        local group = SelGroup()
        if group and Options.BarImport then Options.BarImport.OpenForGroup(group) end
    end)
    AT.Tooltip(fillBtn, "From your action bars",
        "Finds the spells and items on your action bars and lets you pick which become icons in this group. Out of combat only.")
    groupHeader.fillBtn = fillBtn
    groupHeader._btns = { del, addIcon, fillBtn }

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
    ghd._fs:SetFont(AT.FONT, 12, "")
    ghd._fs:SetPoint("LEFT", gbg, "TOPLEFT", 10, -13)
    ghd._fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    ghd._chip = KindPill(gbg)
    ghd._chip:SetPoint("LEFT", ghd._fs, "RIGHT", 8, 0)
    BandActions(gbg, ghd._fs, SelGroup, { hide = { ghd._chip }, row = ghd })
    ghd._sync = function()
        local g = SelGroup()
        ghd._fs:SetText("Editing:  " .. ((g and g.name) or ""))
        if g then GroupPill(ghd._chip, g.groupKind) end
        Options.FitBand(gbg._adBand)
    end

    -- Tabs: how the group looks (its grid, icons, container and fade rules),
    -- where it sits, when it loads.
    local tabs = { "Appearance", "Position", "Load Conditions" }
    -- a Reminder group has tabs of its own (UI\AD_ReminderOptions.lua)
    local function GroupTabs(g)
        local list = tabs
        if Options.GroupTabsFor then list = Options.GroupTabsFor(g, list) end
        -- an aura group opens on what it shows (UI\AD_UnitAuraOptions.lua)
        if Options.UnitAuraTabsFor then list = Options.UnitAuraTabsFor(g, list) end
        return list
    end
    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel   -- strips inside panel-bodied pages
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local g = SelGroup()
        -- a pick made before the regroup moves to where its rows went
        if Options.EditorTabs then Options.EditorTabs.FixGroupPicks(ui, g) end
        local list = GroupTabs(g)
        -- a tab this group lacks snaps to the first, so the body is never empty
        local listed = false
        for _, t in ipairs(list) do
            if t == ui.grpTab then listed = true end
        end
        if not listed then ui.grpTab = list[1] end
        local ET = Options.EditorTabs
        local h = tabRow._strip:Set(list, ui.grpTab, function(name)
            ui.grpTab = name
            AT.LayoutPage(pg)
        end, nil, ET and ET.Badges((g and g.groupKind == "reminder") and "reminder" or "group", list,
            pg:IsVisible(), ui.grpTab))
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Appearance sub-tabs, a second strip under the tab row: Grid (with
    -- Dynamic), Icons (with Keybinds on cooldown groups), Container and the
    -- fade rules. One titled box or more and one push bar per sub-tab.
    ui.grpSec = ui.grpSec or "Grid"
    local GRP_SECS = { "Grid", "Icons", "Container", "Visibility" }
    -- Position sub-tabs: where the group sits (its frame and mouse defaults as
    -- sections) and what it is pinned to. The pick is kept apart from
    -- Appearance's, so each tab remembers its own.
    local GRP_POS_SECS = { "Position", "Anchor" }
    local function PosSecs() return GRP_POS_SECS end
    local function GrpPosPick()
        if ui.grpPosSec == "Anchor" then return "Anchor" end
        return "Position"
    end
    -- Appearance's sub-tabs by kind (a Reminder group: Pulse, Container and
    -- Visibility, Options.GroupSecsFor in UI\AD_ReminderOptions.lua)
    local function ArrSecs()
        local g = SelGroup()
        local list = GRP_SECS
        if Options.GroupSecsFor then list = Options.GroupSecsFor(g, list) end
        return list
    end
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.group = { page = pg, tabs = tabs, tabsFor = GroupTabs, subs = function(tab)
        if tab == "Position" then return PosSecs() end
        if tab ~= "Appearance" then return {} end
        return ArrSecs()
    end }
    local secRow = AT.AddRow(pg, 30, function()
        return (ui.grpTab == "Appearance" or ui.grpTab == "Position") and SelGroup() ~= nil
    end)
    secRow._strip = AT.TabRow(secRow)
    secRow._strip._openFill = COL.panel
    secRow._strip:SetPoint("TOPLEFT", 8, 0)
    secRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    secRow._sync = function()
        local h
        if ui.grpTab == "Position" then
            h = secRow._strip:Set(PosSecs(), GrpPosPick(), function(name)
                ui.grpPosSec = name
                AT.LayoutPage(pg)
            end, 11)
        else
            local list = ArrSecs()
            local ok = false
            for _, t in ipairs(list) do if t == ui.grpSec then ok = true end end
            if not ok then ui.grpSec = list[1] end
            h = secRow._strip:Set(list, ui.grpSec, function(name)
                ui.grpSec = name
                AT.LayoutPage(pg)
            end, 11)
        end
        local want = (h or 24) + 6
        if secRow._h ~= want then secRow._h = want secRow:SetHeight(want) end
    end
    local function GrpSec(name)
        return function() return ui.grpTab == "Appearance" and ui.grpSec == name end
    end
    local function GrpPos(name)
        return function() return ui.grpTab == "Position" and GrpPosPick() == name end
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
                return g and (Options.GroupAlignment or Engine.EffectiveAlignment)(g) or "center"
            end,
            function(v)
                local g = SelGroup()
                if g then Store.SetOverride(g, "arrangement", "alignment", v) end
            end,
            function()
                local g = SelGroup()
                local shape = "horizontal"
                if g then shape = select(2, (Options.GroupAlignment or Engine.EffectiveAlignment)(g)) end
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

    -- Tracking: what an aura group shows (UI\AD_UnitAuraOptions.lua)
    Options.BuildYield()
    if Options.UnitAuraGroupRows then
        Options.UnitAuraGroupRows(pg, SelGroup, function() return ui.grpTab end,
            { SectionRows = SectionRows })
    end

    -- Appearance > Grid: the cells, then Dynamic (both live in the one
    -- `arrangement` section, so the push bar carries its own field list).
    local GRID_FIELDS = { "rows", "cols", "growthH", "growthV", "lockGridSize", "containerPadding" }
    local ICON_FIELDS = { "iconSize", "iconShape", "iconWidth", "iconHeight", "cropIcons", "cropFocus", "iconMask", "cdmLook", "spacing", "separateSpacing",
        "spacingX", "spacingY" }
    local DYN_FIELDS = { "dynamicLayout", "dynamicCollapse", "dynamicOrder", "dynamicShrink",
        "smoothMovement", "smoothDuration" }
    local gridVis = GrpSec("Grid")
    Options.BuildYield()
    AT.Section(pg, "Grid", { visibleFn = gridVis })
    -- a group showing every aura on a unit: its own Rows, beside Columns
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "unitAuras", SelGroup, gridVis, { "rows" })
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, gridVis, GRID_FIELDS)
    -- A group showing every aura on a unit is always live, so its pin sits
    -- with the grid; a plate row stays on its plate's edge.
    AlignmentRow(function()
        local g = SelGroup()
        return gridVis() and Store.ShowsAll(g) and Store.Resolve(g, "unitAuras", "unit") ~= "nameplate"
    end)
    Options.BuildYield()
    Options.LookBlock("iconGroup", "Appearance", "Grid", "arrangement", GRID_FIELDS, "Grid")
    -- Dynamic: its switch first; its rows fold away while it is off. Alignment
    -- sits here, not with the grid: it pins the live row, which exists only
    -- while Dynamic is on. A group showing every aura on a unit is always live.
    local dynVis = function() return gridVis() and not Store.ShowsAll(SelGroup()) end
    Options.BuildYield()
    AT.Section(pg, "Dynamic", { visibleFn = dynVis })
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
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, dynVis, { "dynamicLayout" })
    Options.BuildYield()
    AT.RowDesc(pg, "With this window open, every icon keeps its spot.", 20, dynCD)
    Options.BuildYield()
    AT.RowDesc(pg, "On: icons pack (Show while missing ones too). Off: every aura keeps its spot.", 20, dynAura)
    -- An aura group packs each grid row or column on its own
    -- (Drivers\AD_DriverAuraRows.lua): its direction, then Alignment in that
    -- direction's words, a row Left / Center / Right, a column Up / Center / Down.
    local auraDyn = function() return dynOn() and dynAura() end
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, auraDyn, { "dynamicAxis" })
    Options.BuildYield()
    AT.RowDropdown(pg, win, "Alignment",
        function()
            local g, AR = SelGroup(), NS.DriverAuraRows
            if not (g and AR) then return "center" end
            local axis, mode = AR.Pack(g)
            if axis == "vertical" and mode == "center" then return "center_v" end
            return mode
        end,
        function(v)
            local g = SelGroup()
            if g then Store.SetOverride(g, "arrangement", "alignment", v) end
        end,
        function()
            local g, AR = SelGroup(), NS.DriverAuraRows
            if g and AR and AR.Pack(g) == "vertical" then
                return { { value = "top", text = "Up" }, { value = "center_v", text = "Center" },
                    { value = "bottom", text = "Down" } }
            end
            return { { value = "left", text = "Left" }, { value = "center", text = "Center" },
                { value = "right", text = "Right" } }
        end,
        auraDyn)
    -- Order: Time left gives each unit one flow the game sorts
    -- (Drivers\AD_DriverAuraRows.lua AR.PlaceFlows), so no icon keeps its own
    -- look and a missing aura has nowhere to show.
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, dynVis, { "dynamicSort" })
    Options.BuildYield()
    AT.RowDesc(pg, "Time left shows only auras that are up, all in a new aura icon's look.", 20, function()
        return auraDyn() and Store.Resolve(SelGroup(), "arrangement", "dynamicSort") == "time"
    end)
    do
        -- The search walks one sample group per kind, mostly static ones: hand
        -- it the gate without the Dynamic check plus that switch, so "alignment"
        -- is found on any group and the jump flashes the toggle.
        local row = AlignmentRow(function() return dynOn() and dynCD() end)
        row._adMeta = { family = "iconGroup", section = "arrangement", field = "alignment",
            def = { label = "Alignment",
                dep = { field = "dynamicLayout", value = true } },
            baseVis = dynVis }
    end
    Options.BuildYield()
    AT.RowDesc(pg, "With more than one row and column, a returning icon always takes its spot back.", 20,
        function() return dynOn() and dynCD() and GroupShape() == "multi" end)
    Options.BuildYield()
    AT.RowDesc(pg, "Live rows show buffs on you or your pet and debuffs on your target.", 20,
        function() return dynOn() and dynAura() end)
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, dynVis, { "dynamicCollapse" })
    -- an opacity that changes near the end can't move a spot in combat: with
    -- Icons at opacity 0 and such an icon here, the note says so instead
    local function timedNote()
        local ETb = Options.EditorTabs
        return Store.Resolve(SelGroup(), "arrangement", "dynamicCollapse") == "hidden"
            and ETb ~= nil and ETb.GroupHasTimed ~= nil and ETb.GroupHasTimed(SelGroup())
    end
    Options.BuildYield()
    AT.RowDesc(pg, "Aura icons always keep their spot; for auras that come and go, use an Aura Group.", 20,
        function() return dynOn() and dynCD() and not timedNote() end)
    Options.BuildYield()
    AT.RowDesc(pg, "Aura icons and opacities that change near the end keep their spot: neither can be read in combat.", 20,
        function() return dynOn() and dynCD() and timedNote() end)
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, dynVis, {
        "dynamicOrder", "dynamicShrink", "smoothMovement", "smoothDuration",
    })
    Options.BuildYield()
    Options.LookBlock("iconGroup", "Appearance", "Dynamic", "arrangement", DYN_FIELDS, "Grid")
    Options.BuildYield()
    Options.LookBlock("iconGroup", "Appearance", "Dynamic", "arrangement", { "dynamicAxis", "dynamicSort" }, "Grid",
        { kindOnly = "aura" })
    do
        local list = {}
        for _, f in ipairs(GRID_FIELDS) do list[#list + 1] = f end
        for _, f in ipairs(DYN_FIELDS) do list[#list + 1] = f end
        list[#list + 1] = "alignment"
        list[#list + 1] = "dynamicAxis"
        list[#list + 1] = "dynamicSort"
        AT.Section(pg, nil, { visibleFn = gridVis })
        PushBar(pg, SelGroup, "arrangement", gridVis, list)
    end

    -- Appearance > Icons: what fills the cells, then (cooldown groups) the
    -- keybind switch every member follows.
    local iconsVis = GrpSec("Icons")
    Options.BuildYield()
    AT.Section(pg, "Icons", { visibleFn = iconsVis })
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "arrangement", SelGroup, iconsVis, ICON_FIELDS)
    Options.BuildYield()
    Options.LookBlock("iconGroup", "Appearance", "Icons", "arrangement", ICON_FIELDS, "Icons")
    -- The section's kinds keep the row off aura groups; the box and its note
    -- follow suit.
    local kbGrpVis = function()
        local g = SelGroup()
        return iconsVis() and g ~= nil and g.groupKind ~= "aura"
    end
    Options.BuildYield()
    AT.Section(pg, "Keybinds", { visibleFn = kbGrpVis })
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "keybind", SelGroup, kbGrpVis)
    Options.BuildYield()
    Options.LookBlock("iconGroup", "Appearance", "Keybinds", "keybind", { "showKeybinds" }, "Icons")
    Options.BuildYield()
    AT.RowDesc(pg, "Each icon's Text > Custom Text & Keybind sets the text's size, color and position.", 20, kbGrpVis)
    Options.BuildYield()
    AT.Section(pg, nil, { visibleFn = iconsVis })
    PushBar(pg, SelGroup, function()
        local parts = { { section = "arrangement", fields = ICON_FIELDS } }
        local g = SelGroup()
        if g and g.groupKind ~= "aura" then
            parts[2] = { section = "keybind", fields = { "showKeybinds" } }
        end
        return parts
    end, iconsVis)
    -- a group showing every aura on a unit: its debuff type looks
    Options.BuildYield()
    if Options.TypeLookRows then
        Options.TypeLookRows(pg, SelGroup, iconsVis, { SectionRows = SectionRows, openIcons = function()
            ui.grpMode, ui.grpTab, ui.grpSec = "grp", "Appearance", "Icons"
            RefreshAll()
        end })
    end

    -- Appearance > Container
    Options.BuildYield()
    AT.Section(pg, "Container", { visibleFn = GrpSec("Container") })
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "look", SelGroup, GrpSec("Container"))
    Options.BuildYield()
    Options.LookBlock("iconGroup", "Appearance", "Container", "look", {
        "showBackground", "bgColor", "showBorder", "borderColor", "borderSize", "editFill",
    }, "Container")
    PushBar(pg, SelGroup, "look", GrpSec("Container"))
    -- Appearance > Visibility: the fade rules.
    Options.BuildYield()
    VisibilityRows(pg, SelGroup, GrpSec("Visibility"))
    -- a Reminder group's own tabs and its Pulse sub-tab (UI\AD_ReminderOptions.lua)
    Options.BuildYield()
    if Options.ReminderGroupRows then
        Options.ReminderGroupRows(pg, SelGroup, function() return ui.grpTab end,
            { SectionRows = SectionRows, PushBar = PushBar, win = win,
                subFn = function() return ui.grpSec end })
    end

    -- Position > Position: where it sits, its frame, and (not on a Reminder
    -- group, whose pulses never take the mouse, nor on one the game draws
    -- every aura for, whose buttons never do) the group tier of the
    -- click-through and tooltip chain.
    local grpPosVis = GrpPos("Position")
    Options.BuildYield()
    AT.Section(pg, "Position", { visibleFn = grpPosVis })
    Options.LockRow(pg, SelGroup, grpPosVis)
    Options.BuildYield()
    Options.PosRows(pg, SelGroup, grpPosVis, function(r)
        -- "anchored" = actually pinned right now: an anchor whose target
        -- is gone or hidden places free, so the sliders drive rec.pos there
        return NS.Anchor ~= nil and NS.Anchor.ResolveTarget(r) ~= nil
    end)
    Options.BuildYield()
    AT.Section(pg, "Frame", { visibleFn = grpPosVis })
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "frame", SelGroup, grpPosVis)
    local grpMouseVis = function()
        local g = SelGroup()
        return grpPosVis() and g ~= nil and g.groupKind ~= "reminder" and not Store.ShowsAll(g)
    end
    Options.BuildYield()
    AT.Section(pg, "Mouse", { visibleFn = grpMouseVis })
    Options.BuildYield()
    AT.RowDesc(pg, "Applies to every icon in this group; an icon can override it.", 20, grpMouseVis)
    Options.BuildYield()
    SectionRows(pg, "iconGroup", "mouse", SelGroup, grpMouseVis, { "clickThrough", "showTooltip" })
    Options.BuildYield()
    Options.LookBlock("iconGroup", "Position", "Mouse", "mouse", { "clickThrough", "showTooltip" }, "Position",
        { kindOnly = { cooldown = true, aura = true } })
    PushBar(pg, SelGroup, "mouse", grpMouseVis, { "clickThrough", "showTooltip" })
    -- Position > Anchor: the rows bars and free icons use too. They open their
    -- own section; without one they would land in the Mouse box.
    Options.BuildYield()
    Options.AnchorPickRows(pg, "iconGroup", SelGroup, GrpPos("Anchor"))
    -- game frames it carries along (UI\AD_PinOptions.lua)
    Options.BuildYield()
    if Options.PinRows then Options.PinRows(pg, SelGroup, GrpPos("Anchor"), win) end
    Options.BuildYield()
    AT.Section(pg, nil)
    Options.BuildYield()
    ConditionRows(pg, SelGroup, function() return ui.grpTab == "Load Conditions" end)

    iconEditorPage = BuildIconEditor(groupPane)
    -- what a Reminder group's pane draws with (UI\AD_ReminderOptions.lua)
    Options.GroupPaneKit = { pane = groupPane, strip = groupStrip, stripPool = stripPool,
        switch = switchStrip, groupPage = groupEditorPage, iconPage = iconEditorPage,
        IconButton = IconButton, AttachPreview = AttachPreview, ConditionRows = ConditionRows,
        SelGroup = SelGroup, win = win }
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
    Options.FitHeader(freeHeader)
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
    freeHeader._btns = { addIcon }
    addIcon.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
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
    Options.PreviewBgSwatches(stage)
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
    -- a nameplate's name, so the game's font, not the panel's
    f.name:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    f.name:SetPoint("BOTTOM", f.hp, "TOP", 0, 2)
    f.name:SetTextColor(1, 0.82, 0.1)
    f.name:SetText("Target")
    f.tag = f:CreateFontString(nil, "OVERLAY")
    f.tag:SetFont(AT.FONT, 8, "")
    f.tag:SetPoint("TOPLEFT", 3, -3)
    f.tag:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
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
    local w = math.max(1, (Store.Resolve(rec, "size", "width") or 220) * sc)
    local h = math.max(1, (Store.Resolve(rec, "size", "height") or 16) * sc)
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
    -- a wheel has no bar to preview: its editor draws the wheel itself
    if not (band and rec and B and B.PreviewBuild) or rec.barKind == "wheel" or rec.barKind == "sound" then
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
function Options._barTabsFor(rec)
    -- several bars at once: the tabs every one of them has
    if rec._adMulti and Options.MultiSelect then return Options.MultiSelect.BarTabs(rec) end
    if rec.barKind == "texture" and Options.TextureTabs then return Options.TextureTabs(rec) end
    if rec.barKind == "text" and Options.TextTabs then return Options.TextTabs(rec) end
    return BAR_TABS[rec.barKind] or BAR_TABS.cooldown
end

local function BarTabVisible(tabName)
    return function()
        -- the open tab first: every row of every other tab stops here
        if ui.barTab ~= tabName then return false end
        local rec = SelBar()
        if not rec then return false end
        for _, t in ipairs(Options._barTabsFor(rec)) do
            if t == tabName then return true end
        end
        return false
    end
end

local function RefreshBarPane()
    local rec = SelBar()
    if not rec then return end
    local layout = Store.Get(rec.layoutId)
    -- back from the multi-selection pane, which hosts the page for its bars
    barEditorPage:SetParent(barPane)
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
    Options.FitHeader(barHeader)
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
    barHeader._btns = { del }

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
    hd._fs:SetFont(AT.FONT, 12, "")
    hd._fs:SetPoint("LEFT", hbg, "TOPLEFT", 10, -13)
    hd._fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    hd._chip = KindPill(hbg)
    hd._chip:SetPoint("LEFT", hd._fs, "RIGHT", 8, 0)
    BandActions(hbg, hd._fs, SelBar, { hide = { hd._chip }, row = hd })
    hd._sync = function()
        local rec = SelBar()
        -- several bars at once: their count and kinds, no actions
        local MS = Options.MultiSelect
        if MS and MS.Band(hbg, rec, "bar") then return end
        hd._fs:SetText("Editing:  " .. ((rec and rec.name) or ""))
        if rec then BarPill(hd._chip, rec.barKind, rec.barMode) end
        Options.FitBand(hbg._adBand)
    end

    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel   -- strips inside panel-bodied pages
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local rec = SelBar()
        if not rec then return end
        local tabs = Options._barTabsFor(rec)
        -- an old tab or sub-tab pick moves to where its rows went
        local ET = Options.EditorTabs
        if ET then ET.FixPicks("bar", ui, rec, "barTab", "barSec") end
        local listed = false
        for _, t in ipairs(tabs) do
            if t == ui.barTab then listed = true end
        end
        if not listed then ui.barTab = tabs[1] end
        local h = tabRow._strip:Set(tabs, ui.barTab, function(name)
            ui.barTab = name
            AT.LayoutPage(pg)
        end, nil, ET and ET.Badges("bar", tabs, pg:IsVisible(), ui.barTab))
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end

    -- Tracking: the driver block per kind (retarget re-keys, never re-ids)
    local trackVis = BarTabVisible("Tracking")
    Options.BuildYield()
    AT.Section(pg, "Tracking", { visibleFn = trackVis })
    Options.BuildYield()
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
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(sid) -- raw-id: the typed ID names the record
                if nm then r.name = nm end
                Store.Dirty("tree")
                RefreshAll()
            end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cooldown"
        end,
        "The tracked spell. Retargeting re-keys the driver and keeps every setting and position.")
    -- ranked realms (WoW Forever): resolve by name each feed so the bar
    -- follows the player's known rank; probe-gated, mirrors the icon driver
    Options.BuildYield()
    AT.RowToggle(pg, "Auto rank",
        function() local r = SelBar() return r ~= nil and Store.AutoRankOn(r.driver) end,
        function(v)
            local r = SelBar()
            if not r then return end
            if v then r.driver.autoRank = nil else r.driver.autoRank = false end
            Store.Dirty("style", r.id)
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cooldown"
                and NS.IsForever == true
        end,
        "On ranked realms, track whichever rank of this spell you currently know. Re-resolves on spell changes.")
    Options.BuildYield()
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
    Options.BuildYield()
    AT.RowToggle(pg, "Only load once learned",
        function() local r = SelBar() return r ~= nil and r.driver.onlyKnown == true end,
        function(v)
            local r = SelBar()
            if r then
                r.driver.onlyKnown = v and true or nil
                Store.Dirty("load")
            end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cooldown"
        end,
        "Doesn't load until your character knows this spell (any rank), and loads by itself the moment you learn it.")
    Options.BuildYield()
    AT.RowToggle(pg, "Only this rank",
        function() local r = SelBar() return r ~= nil and r.driver.knownExact == true end,
        function(v)
            local r = SelBar()
            if r then
                r.driver.knownExact = v and true or nil
                Store.Dirty("load")
            end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cooldown" and r.driver.onlyKnown == true
                and NS.IsForever == true
        end,
        "Waits for this exact rank (the spell ID above), not just any rank of the spell.")
    -- what the bar follows: the spell's own cooldown, or the GCD it starts
    Options.BuildYield()
    SectionRows(pg, "bar", "behavior", SelBar, function()
        local r = SelBar()
        return trackVis() and r ~= nil and r.barKind == "cooldown"
    end, { "gcdMode" })
    Options.BuildYield()
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
            local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(sid) -- raw-id: the typed ID names the record
            if nm then r.name = nm end
            Store.Dirty("tree")
            RefreshAll()
        end
    end
    Options.BuildYield()
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
    Options.BuildYield()
    AT.RowToggle(pg, "Follow my rank",
        function()
            local r = SelBar()
            return r ~= nil and r.driver.followRank ~= false
        end,
        function(v)
            local r = SelBar()
            if not r then return end
            if v then r.driver.followRank = nil else r.driver.followRank = false end
            Store.Dirty("style", r.id)
        end,
        function() return barAuraVis() and NS.IsForever == true end,
        Options.FOLLOW_RANK_DESC)
    Options.BuildYield()
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
    Options.BuildYield()
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
    Options.BuildYield()
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
    Options.BuildYield()
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
    Options.BuildYield()
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
    Options.BuildYield()
    AT.RowToggle(pg, "Show the off-hand on this bar",
        function()
            local r = SelBar()
            return r ~= nil and Store.Resolve(r, "fill", "swingOffhand") == true
        end,
        function(v)
            local r = SelBar()
            if r then Store.SetOverride(r, "fill", "swingOffhand", v and true or false) end
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "swing"
                and ((r.driver and r.driver.swingType) or 0) == 0
        end,
        "Adds your off-hand's swing to this main-hand bar. Pick its look on the Appearance tab.")
    Options.BuildYield()
    AT.RowDesc(pg, "Swing timers need WoW Forever: this bar stays hidden here.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "swing" and not C_SwingTimer
        end)
    Options.BuildYield()
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
        function()
            local r = SelBar()
            return PowerItems(r and r.driver and r.driver.powerType)
        end,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "resource"
        end)
    Options.BuildYield()
    AT.RowDesc(pg, "Automatic follows the power you are using right now.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "resource"
        end)
    -- Health bars: whose health.
    Options.BuildYield()
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
    Options.BuildYield()
    AT.RowDesc(pg, "Hides while the unit is not there; always shows while this window is open.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "health"
        end)
    -- A health bar's click area (Bars\AD_ClickUnit.lua): the switch, then one
    -- line on which of the bar's conditions the game can follow in combat.
    Options.BuildYield()
    SectionRows(pg, "bar", "behavior", SelBar, function()
        local r = SelBar()
        return trackVis() and r ~= nil and r.barKind == "health"
    end, { "clickable" })
    do
        local row = AT.AddRow(pg, 24, function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "health" and not r._adMulti
                and NS.Bars ~= nil and NS.Bars.ClickUnit ~= nil
                and Store.Resolve(r, "behavior", "clickable") == true
        end)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 11, "")
        fs:SetPoint("TOPLEFT", 10, -4)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        row._sync = function()
            local r = SelBar()
            local CU = NS.Bars and NS.Bars.ClickUnit
            if not (r and CU) then return end
            fs:SetText(CU.Note(r))
            local w = row:GetWidth() or 0
            if w < 90 then w = (pg:GetWidth() or 0) - 24 end
            if w > 90 then fs:SetWidth(w - 20) end
            local want = math.max(24, math.floor((fs:GetStringHeight() or 12) + 10))
            if row._h ~= want then
                row._h = want
                row:SetHeight(want)
            end
        end
    end
    -- Castbars: whose casts.
    Options.BuildYield()
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
    Options.BuildYield()
    AT.RowDesc(pg, "Hides between casts; shows a sample cast while this window is open.", 20,
        function()
            local r = SelBar()
            return trackVis() and r ~= nil and r.barKind == "cast"
        end)
    -- A weapon enchant bar: a hand, and optionally the enchant IDs that count.
    local enchBarVis = function()
        local r = SelBar()
        return trackVis() and r ~= nil and r.barKind == "enchant"
    end
    Options.BuildYield()
    AT.RowDropdown(pg, win, "Weapon",
        function() local r = SelBar() return r and (r.driver.hand or "main") end,
        function(v)
            local r = SelBar()
            if r then r.driver.hand = v Store.Dirty("style", r.id) end
        end,
        function() return Options.EnchantHandItems() end,
        enchBarVis)
    Options.BuildYield()
    AT.RowInput(pg, "Enchant IDs",
        function()
            local r = SelBar()
            return r and Options.EnchantIDsText(r.driver) or ""
        end,
        function(v)
            local r = SelBar()
            if not r then return end
            Options.SetEnchantIDs(r.driver, Options.ParseSpellIDs(v))
            Store.Dirty("style", r.id)
        end,
        enchBarVis, "Every enchant ID this bar fills for, separated by commas or spaces. Empty: anything on the weapon. With two of them on the weapon at once, the first listed shows.",
        "Any enchant")
    local ebNow = AT.AddRow(pg, 22, enchBarVis)
    local ebNowFS = ebNow:CreateFontString(nil, "OVERLAY")
    ebNowFS:SetFont(AT.FONT, 11, "")
    ebNowFS:SetPoint("LEFT", 10, 0)
    ebNowFS:SetPoint("RIGHT", -10, 0)
    ebNowFS:SetJustifyH("LEFT")
    ebNowFS:SetWordWrap(false)
    ebNowFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    ebNow._sync = function()
        local r = SelBar()
        ebNowFS:SetText(r and r.barKind == "enchant" and Options.EnchantNowText(r) or "")
    end
    Options.BuildYield()
    AT.RowDropdown(pg, win, "Add one on it now",
        function() return 0 end,
        function(v)
            local r = SelBar()
            if not (r and type(v) == "number" and v > 0) then return end
            Options.AddEnchantID(r.driver, v)
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        function() return Options.EnchantPickItems(SelBar()) end,
        enchBarVis)
    local tplBarVis = function() return enchBarVis() and Options.HasEnchantTemplates() end
    Options.EnchantTemplateGrid(pg, tplBarVis,
        function() return Options.EnchantTemplatePick(SelBar()) end,
        function(v) Options.SetEnchantTemplatePick(SelBar(), v) end,
        false, function() local r = SelBar() return r and r.driver.hand end)
    Options.BuildYield()
    AT.RowButton(pg, "Use template", function()
        if Options.ApplyEnchantTemplate(SelBar()) then
            AT.LayoutPage(pg)
            RefreshAll()
        end
    end, tplBarVis, 120)
    -- A range bar: its preset of bands (or its own, edited on the Range tab), and
    -- the spell a Melee or Caster preset checks (Bars\AD_RangeBar.lua).
    do
        local function RangeRec()
            local r = SelBar()
            return (r and r.barKind == "range") and r or nil
        end
        local function Preset(r)
            local RBm = NS.RangeBars
            return (r and RBm) and RBm.Preset(r) or "melee"
        end
        local rangeVis = function() return trackVis() and RangeRec() ~= nil end
        -- Own bands go back to a preset only through Reset below, so no pick in
        -- this list can throw them away.
        AT.RowDropdown(pg, win, "Preset",
            function() return Preset(RangeRec()) end,
            function(v)
                local r, RBm = RangeRec(), NS.RangeBars
                if not (r and RBm) or Preset(r) == "custom" then return end
                if v == "custom" then
                    RBm.MakeCustom(r)
                    return
                end
                -- a new preset starts from its own class default spell
                if Preset(r) ~= v then r.driver.spellID = nil end
                r.driver.preset = v
                Store.Dirty("style", r.id)
            end,
            function()
                local RBm = NS.RangeBars
                local items = {}
                if not RBm then return items end
                if Preset(RangeRec()) ~= "custom" then
                    for _, p in ipairs(RBm.PRESETS) do items[#items + 1] = { value = p, text = RBm.PRESET_TEXT[p] } end
                end
                items[#items + 1] = { value = "custom", text = RBm.PRESET_TEXT.custom }
                return items
            end,
            rangeVis, function() AT.LayoutPage(pg) end)
        -- Reset to preset: the dropdown picks, the button acts.
        do
            local pick, pickFor
            local function Pick()
                local r = RangeRec()
                if not r then return nil end
                if pickFor ~= r.id then
                    local RBm = NS.RangeBars
                    pick, pickFor = RBm and RBm.DefaultPreset() or "melee", r.id
                end
                return pick
            end
            local row = AT.AddRow(pg, 24, function() return rangeVis() and Preset(RangeRec()) == "custom" end)
            local lbl = AT.RowLabel(row, "Reset to preset")
            local dd = AT.MakeDropdown(win, row, nil,
                function()
                    local RBm, items = NS.RangeBars, {}
                    for _, p in ipairs(RBm and RBm.PRESETS or {}) do
                        items[#items + 1] = { value = p, text = RBm.PRESET_TEXT[p] }
                    end
                    return items
                end,
                Pick,
                function(v) Pick() pick = v end)
            local reset = AT.MakeQuietButton(row, "Reset", 60)
            reset:SetPoint("LEFT", dd, "RIGHT", 6, 0)
            reset:SetScript("OnClick", function()
                AT.CloseDropdown()
                local r, RBm = RangeRec(), NS.RangeBars
                if r and RBm then RBm.ResetTo(r, Pick()) end
                AT.LayoutPage(pg)
            end)
            AT.Tooltip(reset, "Reset", "Replaces this bar's own bands with the picked preset: the texts, colors and checks you changed are lost.")
            row._colLabel, row._colCtrl = lbl, dd
            row._sync = dd.Refresh
        end
        AT.RowInput(pg, "Spell",
            function()
                local r = RangeRec()
                return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
            end,
            function(v)
                local r = RangeRec()
                if not r then return end
                local DR = NS.DriverRange
                local id = (DR and DR.ParseSpell(v)) or tonumber(v)
                if id and id <= 0 then id = nil end
                if r.driver.spellID == id then return end -- raw-id: an unchanged entry, not a match
                r.driver.spellID = id
                Store.Dirty("style", r.id)
            end,
            function()
                local p = Preset(RangeRec())
                return rangeVis() and (p == "melee" or p == "caster")
            end,
            "The spell whose range picks the band: a melee ability for Melee, a ranged spell for Caster. A spell ID or the name of a spell you know; the rank you know is checked. Empty: your class's usual one.",
            function()
                local r, RBm = RangeRec(), NS.RangeBars
                return (r and RBm) and RBm.SpellHint(r) or ""
            end)
        local st = AT.AddRow(pg, 22, rangeVis)
        local stFS = st:CreateFontString(nil, "OVERLAY")
        stFS:SetFont(AT.FONT, 11, "")
        stFS:SetPoint("LEFT", 10, 0)
        stFS:SetPoint("RIGHT", -10, 0)
        stFS:SetJustifyH("LEFT")
        stFS:SetWordWrap(false)
        stFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        st._sync = function()
            local r, RBm = RangeRec(), NS.RangeBars
            stFS:SetText((r and RBm) and RBm.CheckText(r) or "")
        end
        -- the band editor under the preset (UI\AD_RangeOptions.lua): the bar's
        -- own data, so no push bar
        if Options.RangeBandRows then Options.RangeBandRows(pg, SelBar, rangeVis, win) end
    end
    -- a Custom Bar's tracking rows and its Triggers tab (UI\AD_CustomOptions.lua)
    Options.BuildYield()
    if Options.CustomBarRows then
        Options.CustomBarRows(pg, SelBar, BarTabVisible("Tracking"), BarTabVisible("Triggers"), win)
    end
    -- a Text element's source rows and Format block (UI\AD_TextOptions.lua)
    Options.BuildYield()
    if Options.TextTrackRows then
        Options.TextTrackRows(pg, SelBar, BarTabVisible("Tracking"), win,
            { SectionRows = SectionRows, triggers = BarTabVisible("Triggers") })
    end
    -- a texture's source rows (UI\AD_TextureOptions.lua); its triggers are the
    -- text's Triggers block above
    Options.BuildYield()
    if Options.TextureTrackRows then Options.TextureTrackRows(pg, SelBar, BarTabVisible("Tracking"), win) end
    -- a wheel's key, spots and editor (UI\AD_WheelOptions.lua)
    Options.BuildYield()
    if Options.WheelRows then Options.WheelRows(pg, SelBar, BarTabVisible("Wheel"), win) end
    -- a Sound item's play-in switches and rules (UI\AD_SoundOptions.lua)
    Options.BuildYield()
    if Options.SoundRows then Options.SoundRows(pg, SelBar, BarTabVisible("Tracking"), win) end
    -- a deck bar's tracker, status and Reset (UI\AD_SpecialOptions.lua)
    Options.BuildYield()
    if Options.SpecialBarRows then Options.SpecialBarRows(pg, SelBar, trackVis) end

    Options.BuildYield()
    ConditionRows(pg, SelBar, BarTabVisible("Load Conditions"))

    -- Sub-tabs, as in the icon editor: every block names its sub-tab (def.sub;
    -- by default its own title, as the Text runs; none on Heals & Shields and
    -- Castbar, which stack their blocks). A block and its push bar hide when
    -- no field applies to the bar's kind and mode.
    local SEC_LISTS = {}
    local DEF_OF = {}   -- a block's vis -> its def
    local function BlockApplies(rec, def)
        -- several bars at once: a block they all have, never a per-item pane
        if rec._adMulti then return Options.MultiSelect.BlockApplies(rec, def, BlockApplies) end
        -- a pane of bespoke rows (Position, Anchor, Fade When) always applies
        if def.pane then return true end
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
        local out, seen = {}, {}
        if not rec then return out end
        for _, def in ipairs(SEC_LISTS[tabName] or {}) do
            local s = def.sub
            if s and not seen[s] and BlockApplies(rec, def) then
                seen[s] = true
                out[#out + 1] = s
            end
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
        local ET = Options.EditorTabs
        local h = secRow._strip:Set(avail, cur, function(name)
            ui.barSec[ui.barTab] = name
            AT.LayoutPage(pg)
        end, 11, ET and ET.Badges("barSub", avail, pg:IsVisible() and secRow._visibleFn(), cur))
        local want = (h or 24) + 6
        if secRow._h ~= want then secRow._h = want secRow:SetHeight(want) end
    end
    -- a block's sub-tab shows: no sub-tab, fewer than two, or the picked one
    local function SubOpen(tabName, sub)
        if not sub then return true end
        local avail = AvailSecs(tabName)
        return #avail < 2 or ui.barSec[tabName] == sub
    end

    -- when(rec): a per-record gate on top of the schema's kind and mode gates
    -- (a cooldown bar's Stack text exists only for a charge spell). sub: the
    -- sub-tab (nil: the block's own title; false: the tab stacks its blocks).
    -- noLook: another block already mirrors these rows in the layout looks.
    -- rowOpts: SectionRows' options (labels: a block's own words for shared fields)
    local function BarBlock(title, section, tabName, fields, when, sub, noLook, rowOpts)
        if sub == nil then sub = title end
        local def = { title = title, section = section, fields = fields, when = when, sub = sub or nil }
        SEC_LISTS[tabName] = SEC_LISTS[tabName] or {}
        table.insert(SEC_LISTS[tabName], def)
        local tabVis = BarTabVisible(tabName)
        local vis = function()
            if not tabVis() then return false end
            local r = SelBar()
            if not r then return false end
            if not BlockApplies(r, def) then return false end
            return SubOpen(tabName, def.sub)
        end
        DEF_OF[vis] = def
        -- the block's rows, keyed by its vis: a PushBar handed this `vis`
        -- scopes itself to exactly these fields
        Options.blockFields[vis] = fields
        -- the layout looks mirror it (the tab, for its BarSubs)
        Options.blockTab[vis] = tabName
        if not noLook then
            Options.LookBlock("bar", tabName, title, section, fields, def.sub,
                { when = when, labels = rowOpts and rowOpts.labels })
        end
        local ET = Options.EditorTabs
        if rowOpts and rowOpts.card and ET then
            -- a card: the first field is the switch in its header; the rest
            -- follow their deps, so an off card is its header line alone
            local card = ET.CardStart(pg, { vis = vis, ctx = SelBar, family = "bar", section = section,
                switch = fields[1], name = title, when = rowOpts.card.when, word = rowOpts.card.word })
            if rowOpts.card.rows then
                -- a card that draws its own rows (a bar glow's aura rows sit mid-card)
                rowOpts.card.rows(vis)
            else
                local rest = {}
                for i = 2, #fields do rest[#rest + 1] = fields[i] end
                SectionRows(pg, "bar", section, SelBar, vis, rest)
            end
            ET.CardEnd(card)
            def.card = card
            return vis
        end
        AT.Section(pg, title, { visibleFn = vis })
        if rowOpts and rowOpts.rows then
            -- a block that draws its own rows (a resource bar's States table)
            rowOpts.rows(vis)
            return vis
        end
        SectionRows(pg, "bar", section, SelBar, vis, fields, rowOpts)
        return vis
    end
    -- A titled sub-group inside a block: its rows share the block's visibility
    -- and join its push list; call it after the block's bespoke rows.
    local function BarSub(vis, title, section, fields)
        AT.Section(pg, title, { visibleFn = vis })
        SectionRows(pg, "bar", section, SelBar, vis, fields)
        local def = DEF_OF[vis]
        Options.LookBlock("bar", Options.blockTab[vis], title, section, fields, def and def.sub,
            { when = def and def.when })
        local list = Options.blockFields[vis]
        if list then for _, f in ipairs(fields) do list[#list + 1] = f end end
    end
    -- A sub-tab of bespoke rows (Position, Anchor, Fade When), with no push
    -- bar. Returns the rows' vis.
    local function BarPane(title, tabName)
        local def = { title = title, fields = {}, pane = true, sub = title }
        SEC_LISTS[tabName] = SEC_LISTS[tabName] or {}
        table.insert(SEC_LISTS[tabName], def)
        local tabVis = BarTabVisible(tabName)
        return function()
            if not (tabVis() and SelBar()) then return false end
            return SubOpen(tabName, title)
        end
    end
    -- The push bar at the end of a sub-tab (or of a stacked tab): the rows of
    -- every block it shows, one part per pushable section, with the hidden
    -- fields its bespoke dropdowns own (def.extra: texture, background
    -- texture, border style).
    local function SubPush(tabName, sub)
        local tabVis = BarTabVisible(tabName)
        local function Parts()
            local r = SelBar()
            local out, bySec = {}, {}
            if not r then return out end
            for _, def in ipairs(SEC_LISTS[tabName] or {}) do
                local s = def.section and Schema.bar[def.section]
                if def.sub == sub and not def.pane and s and s.push and BlockApplies(r, def) then
                    local e = bySec[def.section]
                    if not e then
                        e = { section = def.section, fields = {}, has = {} }
                        bySec[def.section] = e
                        out[#out + 1] = e
                    end
                    for _, list in ipairs({ def.fields, def.extra or {} }) do
                        for _, f in ipairs(list) do
                            if not e.has[f] then
                                e.has[f] = true
                                e.fields[#e.fields + 1] = f
                            end
                        end
                    end
                end
            end
            return out
        end
        local vis = function()
            if not (tabVis() and SubOpen(tabName, sub)) then return false end
            return #Parts() > 0
        end
        AT.Section(pg, nil, { visibleFn = vis })
        PushBar(pg, SelBar, Parts, vis)
    end

    -- A resource bar in pips style draws cells: no bar size, fill, marks or
    -- cost preview; the Style block sizes and colours the cells.
    local function IsPips(r)
        if r.barKind == "timer" and r.barMode == "stack" then
            local s = Store.Resolve(r, "stacklook", "style")
            return s == "pips" or s == "icons"
        end
        return r.barKind == "resource" and Store.Resolve(r, "resource", "style") == "pips"
    end
    local function NotPips(r) return not IsPips(r) end
    -- a text element is words in a box, never a bar: its size lives with its text
    local function IsText(r) return r.barKind == "text" end
    -- a texture is a picture: its size has a sub-tab of its own, after Picture
    local function IsTexture(r) return r.barKind == "texture" end
    local SF, FC = "Size & Frame", "Fill & Colors"

    -- Appearance > Size & Frame. A resource bar's style (a bar or a row of
    -- cells) and a range bar's (how its bands draw) lead: they decide the frame.
    local styleVis = BarBlock("Style", "resource", "Appearance", {
        "style", "usePowerColor", "runeOrder",
    }, nil, SF)
    BarSub(styleVis, "Pips", "resource", {
        "pipShape", "pipWidth", "pipHeight", "pipSpacing", "pointColor", "pipEmptyTint",
    })
    BarBlock("Style", "range", "Appearance", {
        "style", "plateShow", "textBandColor", "cellGap", "cellDim",
    }, nil, SF)
    -- a custom bar showing its stacks: one bar, or a row of cells
    local cellVis = BarBlock("Style", "stacklook", "Appearance", { "style" }, nil, SF)
    BarSub(cellVis, "Cells", "stacklook", {
        "cellShape", "cellWidth", "cellHeight", "cellSpacing", "cellEmptyTint",
    })
    BarSub(cellVis, "Icons", "stacklook", { "iconArt", "iconDim", "iconColorUnlit" })
    BarSub(cellVis, "Segments", "stacklook", { "segGap" })
    -- bar style only: the bar's own size
    local sizeVis = BarBlock("Bar Size", "size", "Appearance", {
        "width", "height", "scale", "opacity",
    }, function(r) return NotPips(r) and not IsText(r) and not IsTexture(r) and r.barKind ~= "wheel" end, SF)
    -- An anchored bar can take its size from its target: the Anchor block's
    -- match rows again, where the size is set. Not a BarSub: these are anchor
    -- fields, outside the size section's copy and reset.
    do
        local function Anchored()
            local r = SelBar()
            -- an anchor is per bar: not over several at once
            if not (r and not r._adMulti and sizeVis() and NS.Anchor and NS.Anchor.IsEnabled(r)) then return false end
            local k = Store.Resolve(r, "anchor", "anchorTargetKind") or "group"
            return k ~= "nameplate" and k ~= "mouse"
        end
        AT.Section(pg, "Match the anchor target", { visibleFn = Anchored })
        SectionRows(pg, "bar", "anchor", SelBar, Anchored, {
            "anchorMatchWidth", "anchorMatchWidthAdjust", "anchorMatchHeight", "anchorMatchHeightAdjust",
        })
    end
    -- pips style: the bar frame is the row of cells, so only scale and
    -- opacity remain meaningful
    BarBlock("Scale", "size", "Appearance", {
        "scale", "opacity",
    }, IsPips, SF)
    -- Statusbar textures for the fill, pip and background dropdowns: the
    -- built-ins plus every LibSharedMedia texture when LSM is loaded.
    local function BarTextureItems()
        local items, seen = {}, {}
        for _, k in ipairs((NS.Bars and NS.Bars.BUILTIN_TEXTURE_ORDER)
            or { "Flat", "Blizzard", "Blizzard Raid", "Character Skills" }) do
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
    -- Background and Border: two blocks over the one `look` section.
    local bgVis = BarBlock("Background", "look", "Appearance", {
        "bgShow", "bgColor", "bgAlpha",
    }, nil, SF)
    -- the background texture dropdown (hidden schema field): the fill's own
    -- texture by default, else a built-in or any LibSharedMedia texture
    Options.BuildYield()
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
    DEF_OF[bgVis].extra = { "bgTexture" }
    Options.BuildYield()
    Options.LookBlock("bar", "Appearance", "Background", "look", { "bgTexture" }, SF)
    local borderVis = BarBlock("Border", "look", "Appearance", {
        "borderEnabled", "borderColor", "borderThickness", "useClassColorBorder",
    }, nil, SF)
    -- the border style dropdown (hidden schema field): Flat strips, the
    -- Blizzard edges, and every LibSharedMedia border when one is present
    Options.BuildYield()
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
    DEF_OF[borderVis].extra = { "borderStyle" }
    Options.BuildYield()
    Options.LookBlock("bar", "Appearance", "Border", "look", { "borderStyle" }, SF)
    SubPush("Appearance", SF)

    -- Appearance > Fill & Colors: the fill, its orientation and gradient, then
    -- every rule that recolours it, each its own section.
    -- Pips style: the row's direction (the fill's orientation fields; the Fill
    -- block hides in this style) and the pip texture.
    -- A resource bar's look per power or spec leads the colours it changes
    -- (UI\AD_LooksOptions.lua); the Text tab repeats its Editing row.
    local appTabVis = BarTabVisible("Appearance")
    local function LookVis()
        local r = SelBar()
        return appTabVis() and SubOpen("Appearance", FC) and r ~= nil and not r._adMulti and r.barKind == "resource"
    end
    Options.BuildYield()
    if Options.LooksRows then
        AT.Section(pg, "Look per form or spec", { visibleFn = LookVis })
        Options.LooksRows(pg, SelBar, LookVis, win, true)
    end
    local dirVis = BarBlock("Direction", "fill", "Appearance", {
        "orientation", "reverseFill",
    }, IsPips, FC)
    Options.BuildYield()
    AT.RowDropdown(pg, win, "Pip texture", FillTextureGet, FillTextureSet, BarTextureItems, dirVis)
    DEF_OF[dirVis].extra = { "texture" }
    -- a health bar's "Color by" leads (its rows hide on every other kind)
    local fillVis = BarBlock("Fill", "fill", "Appearance", {
        "colorMode", "color", "gradLowColor", "gradMidColor", "gradHighColor",
        -- A castbar's channel and can't-be-interrupted colours.
        "castChannelOn", "castChannelColor", "castLockOn", "castLockColor",
        "rotateTexture", "fillMode", "idleEmpty",
        "smoothing", "fillInset",
    }, NotPips, FC)
    Options.BuildYield()
    AT.RowDropdown(pg, win, "Bar texture", FillTextureGet, FillTextureSet, BarTextureItems, fillVis)
    -- a resource bar's colours by state live in its States table
    Options.BuildYield()
    AT.RowDesc(pg, "Colors by spell, aura or power: Conditions > By State.", 20, function()
        local r = SelBar()
        return fillVis() and r ~= nil and r.barKind == "resource"
    end)
    DEF_OF[fillVis].extra = { "texture" }
    Options.BuildYield()
    Options.LookBlock("bar", "Appearance", "Fill", "fill", { "texture" }, FC)
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
        -- in the Fill block's look (one box less on the Defaults page; these
        -- never inherit, so the layout looks are unchanged)
        Options.LookBlock("bar", "Appearance", "Fill", "fill", { "orientation", "reverseFill" }, FC)
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
                -- a swap of one bar's own width and height: not over several
                return orientVis() and r ~= nil and not r._adMulti
                    and Store.Resolve(r, "fill", "orientation") == "VERTICAL"
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
    -- Runes and essence, either style: how a point that is coming back fills
    -- and its shade. Charged combo points and the fold each have their own.
    BarBlock("Recharge", "resource", "Appearance", {
        "rechargeFill", "rechargeDir", "rechargeColorEnabled", "rechargeColor",
    }, function(r) return Schema.Recharges(r) end, FC)
    BarBlock("Charged Points", "resource", "Appearance", {
        "chargedShow", "chargedColor",
    }, function(r) return Schema.ResPower(r) == 4 and NS.IsForever ~= true end, FC)
    BarBlock("Fold", "resource", "Appearance", {
        "foldOn", "foldColor",
    }, function(r) return Schema.Foldable(r) end, FC)
    -- Pips style: the cells' banding by position (an aura stack bar's is
    -- Stack Colors below).
    local pointVis = BarBlock("Point Colors", "stackcolors", "Appearance", {
        "scEnabled", "sc2Value", "sc2Color", "sc3Value", "sc3Color",
        "sc4Value", "sc4Color", "scCount", "maxColorEnabled", "maxColor",
    }, IsPips, FC)
    Options.BuildYield()
    AT.RowDesc(pg, "Each band colors its point and every point after it.", 20, pointVis)
    local segsVis = BarBlock("Segments", "segments", "Appearance", {
        "segmentsShow", "segmentCount", "segmentSpacing", "dividerColor",
    }, nil, FC)
    BarSub(segsVis, "Segment colors", "segments", {
        "fullColorEnabled", "fullColor", "rechargeColorEnabled", "rechargeColor",
    })
    -- Time bands, stack colors, power and health bands and a swing bar's
    -- ability colours, each block gated on kind and mode by the schema.
    BarBlock("Thresholds", "thresholds", "Appearance", {
        "threshEnabled", "threshAsSeconds", "threshCdSeconds", "threshRef",
        "thresh2Value", "thresh2Color", "thresh3Value", "thresh3Color",
        "thresh4Value", "thresh4Color", "threshCount", "threshText",
    }, nil, FC)
    -- aura stack bars only here: a resource bar's banding is Point Colors
    -- above (pips style), and a continuous fill has no per-point cells
    local scVis = BarBlock("Stack Colors", "stackcolors", "Appearance", {
        "scEnabled", "sc2Value", "sc2Color", "sc3Value", "sc3Color",
        "sc4Value", "sc4Color", "scCount", "maxColorEnabled", "maxColor", "scPosition",
    }, function(r)
        return r.barKind ~= "resource"
    end, FC)
    -- The bands in words, re-read on every sync.
    local scSum = AT.AddRow(pg, 22, scVis)
    local scFS = scSum:CreateFontString(nil, "OVERLAY")
    scFS:SetFont(AT.FONT, 10, "")
    scFS:SetPoint("LEFT", 10, 0)
    scFS:SetPoint("RIGHT", -10, 0)
    scFS:SetJustifyH("LEFT")
    scFS:SetWordWrap(false)
    scFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    scSum._sync = function()
        local r = SelBar()
        scFS:SetText(r and Options.StackColorSummary(r) or "")
    end
    -- health bars: colour by health percent (a low-health warning, the
    -- execute range); wins over the Bar color while a band applies
    BarBlock("Health Colors", "healththresholds", "Appearance", {
        "hpthEnabled", "hpthDirection", "hpth2Value", "hpth2Color",
        "hpth3Value", "hpth3Color", "hpth4Value", "hpth4Color", "hpthCount", "hpthText", "hpthPulse",
    }, nil, FC)
    -- Swing bars: the fill wears an ability's colour while it is queued or
    -- after its cast. The rules are the bar's own (rec.driver.swingColors),
    -- drawn by UI\AD_SwingColorOptions.lua; not pushable.
    local abcVis = BarBlock("Ability Colors", "abilcolors", "Appearance", { "abilColorsOn" }, nil, FC)
    DEF_OF[abcVis].perItem = true   -- the rules are one bar's own: never over several
    Options.BuildYield()
    if Options.SwingColorRows then Options.SwingColorRows(pg, SelBar, abcVis, win) end
    -- a timer bar's spark on the fill's moving edge (a swing bar's is on Swing)
    BarBlock("Spark", "fill", "Appearance", {
        "edgeSpark", "edgeSparkColor", "edgeSparkWidth",
    }, function(r) return r.barKind ~= "swing" end, FC)
    -- a deck bar's colours by procs used (UI\AD_SpecialOptions.lua)
    if Options.SpecialBarBlocks then Options.SpecialBarBlocks(FC, BarBlock, PushBar, pg, SelBar) end
    SubPush("Appearance", FC)

    -- Appearance > Cost & Regen, resource bars: what a cast will take and when
    -- mana comes back, as cards (Bars\AD_ManaRegen.lua draws the regen ones)
    local CR = "Cost & Regen"
    BarBlock("Cost Preview", "predict", "Appearance", {
        "predictEnabled", "predictQueued", "predictColor", "predictAlpha",
    }, NotPips, CR, nil, { card = { when = "While casting" } })
    -- the regen cards: a bar that tracks mana or follows the display power
    Options.ManaBarWhen = function(r)
        local pt = r.driver and tonumber(r.driver.powerType)
        return NotPips(r) and (pt == nil or pt < 0 or pt == 0)
    end
    BarBlock("Five-Second Rule", "regen", "Appearance", {
        "fsrOn", "fsrShow", "fsrColor", "fsrWidth", "fsrDir", "fsrSound", "fsrText", "fsrTextPos", "fsrTextSize",
    }, Options.ManaBarWhen, CR, nil, { card = { when = "After a mana spell" } })
    BarBlock("Tick Spark", "regen", "Appearance", {
        "tickSpark", "tickSparkColor", "tickSparkWidth",
    }, Options.ManaBarWhen, CR, nil, { card = { when = "Every 2 s" } })
    BarBlock("Incoming Mana", "regen", "Appearance", {
        "incoming", "incomingColor", "incomingFlash",
    }, Options.ManaBarWhen, CR, nil, { card = { when = "The next tick" } })
    SubPush("Appearance", CR)

    -- Appearance > Icon
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
    SubPush("Appearance", "Icon")

    -- Appearance > Swing (swing bars): the off-hand track, the closing fill and
    -- the spark, as one sub-tab; the next-swing abilities have their own
    -- (Next Swing, below), the ticks before the swing lands are on Ticks.
    local SW = "Swing"
    local offVis = BarBlock("Off-hand", "fill", "Appearance", {
        "swingOffhandStyle", "swingOffhandColor",
    }, function(r)
        return r.barKind == "swing" and ((r.driver and r.driver.swingType) or 0) == 0
            and Store.Resolve(r, "fill", "swingOffhand") == true
    end, SW)
    -- a label that rides the off-hand's moving edge while it swings
    BarSub(offVis, "Off-hand label", "fill", {
        "swingOffhandLabel", "swingOffhandLabelText", "swingOffhandLabelPos",
        "swingOffhandLabelSize", "swingOffhandLabelColor",
    })
    -- Halves that close in (its switch hides beside the off-hand track); the
    -- ticks before the swing lands sit on Ticks with the custom ticks. The
    -- field's kinds gate it.
    BarBlock("Swing", "fill", "Appearance", { "swingClosing" }, nil, SW)
    BarBlock("Spark", "fill", "Appearance", {
        "edgeSpark", "edgeSparkColor", "edgeSparkWidth",
    }, function(r) return r.barKind == "swing" end, SW, true)
    -- the Defaults page shows it on Swing too; the layout looks keep the one
    -- Spark block on Fill & Colors (defaultsOnly)
    Options.BuildYield()
    Options.LookBlock("bar", "Appearance", "Spark", "fill", { "edgeSpark", "edgeSparkColor", "edgeSparkWidth" }, SW,
        { when = function(r) return r.barKind == "swing" end, defaultsOnly = true })
    SubPush("Appearance", SW)
    -- Appearance > Next Swing (main-hand swing bars, a sub-tab of its own):
    -- next-swing abilities marked where each comes off cooldown.
    -- The abilities and their rank picks are the bar's own (rec.driver), drawn
    -- as a list by UI\AD_SwingAbilOptions.lua; not pushable.
    do
        local abilVis = BarBlock("Next Swing", "fill", "Appearance", { "swingAbilities" }, function(r)
            return ((r.driver and r.driver.swingType) or 0) == 0
        end)
        if Options.SwingAbilRows then Options.SwingAbilRows(pg, SelBar, abilVis, win) end
        -- which markers show and where, then how they look
        BarSub(abilVis, "Markers", "fill", { "swingAbilCD", "swingAbilAhead", "swingAbilBadge", "swingAbilFar",
            "swingAbilReady", "swingAbilQueued", "swingAbilPlace", "swingAbilFollow" })
        BarSub(abilVis, "Icons and colors", "fill", { "swingAbilIconSize", "swingAbilTint", "swingAbilColorNow",
            "swingAbilColorLater", "swingAbilColorFar", "swingAbilColorReady", "swingAbilColorQueued" })
    end
    SubPush("Appearance", "Next Swing")

    -- Appearance > Ticks: tick marks for every counted bar ("Every point" draws
    -- one per unit from the live maximum), laid out once per size or setting
    -- change.
    local tickVis = BarBlock("Ticks", "ticks", "Appearance", {
        "ticksShow", "tickMode", "tickPercent", "tickValues", "tickAsPercent",
        "tickScale",
    }, NotPips)
    -- A swing bar's ticks before the swing lands, in the same box right after
    -- the custom ticks, so both kinds of tick are found in one place. They
    -- are fill fields: a def of their own puts them in the push bar's fill
    -- part and the layout looks, never in the ticks block's list.
    do
        local swingTicks = { "swingTicks", "swingTickCount", "swingTickTime", "swingTickColor",
            "swingTick2Time", "swingTick2Color", "swingTick3Time", "swingTick3Color" }
        table.insert(SEC_LISTS.Appearance, { title = "Ticks", section = "fill", fields = swingTicks, sub = "Ticks" })
        SectionRows(pg, "bar", "fill", SelBar, tickVis, swingTicks)
        Options.LookBlock("bar", "Appearance", "Ticks", "fill", swingTicks, "Ticks", { kindOnly = "swing" })
    end
    -- a resource bar's cost marks are its States rows' (Conditions > By State)
    Options.BuildYield()
    AT.RowDesc(pg, "Spell cost marks: COST MARK on a row in Conditions > By State.", 20, function()
        local r = SelBar()
        return tickVis() and r ~= nil and r.barKind == "resource"
    end)
    BarSub(tickVis, "Spell costs", "ticks", {
        "tickSpellIcons", "tickIconSize", "tickIconSide", "tickIconDim",
    })
    -- Color each tick: the custom list's colours, one row per number typed
    BarSub(tickVis, "Marks", "ticks", {
        "tickChannelOnly", "tickColor", "tickColorEach", "tickColor2", "tickColor3", "tickColor4",
        "tickColor5", "tickColor6", "tickThickness", "tickThicknessAnchor", "tickHeight", "tickHeightAnchor",
    })
    -- a deck bar marks its procs (UI\AD_SpecialOptions.lua)
    if Options.SpecialBarBlocks then Options.SpecialBarBlocks("Ticks", BarBlock, PushBar, pg, SelBar) end
    SubPush("Appearance", "Ticks")

    -- Appearance (text elements): one page, the one string's font, size and
    -- colour, then the box it sits in, in a box's words (the size section),
    -- then the box's background (Bars\AD_TextElement.lua).
    local txVis = BarBlock("Text", "textel", "Appearance", {
        "font", "size", "outline", "shadow", "color", "justifyH", "justifyV",
    }, nil, "Text")
    local boxVis = BarBlock("Box", "size", "Appearance", { "width", "height", "opacity" }, IsText, "Text", nil,
        { labels = { width = "Box width", height = "Box height", opacity = "Opacity" }, searchLabels = true })
    do
        -- an anchored text can take its box's size from its target, as a bar does
        local function Anchored()
            local r = SelBar()
            if not (r and not r._adMulti and boxVis() and NS.Anchor and NS.Anchor.IsEnabled(r)) then return false end
            local k = Store.Resolve(r, "anchor", "anchorTargetKind") or "group"
            return k ~= "nameplate" and k ~= "mouse"
        end
        AT.Section(pg, "Match the anchor target", { visibleFn = Anchored })
        SectionRows(pg, "bar", "anchor", SelBar, Anchored, {
            "anchorMatchWidth", "anchorMatchWidthAdjust", "anchorMatchHeight", "anchorMatchHeightAdjust",
        })
    end
    BarSub(txVis, "Background", "textel", { "bgShow", "bgColor" })
    SubPush("Appearance", "Text")

    -- a texture's picture (Bars\AD_TextureElement.lua): the picker first, then
    -- its look; each sub shows for the mode it reaches. Short pages: Picture,
    -- Shape (the whole picture only), Motion, Size.
    -- (whole picture, fill or ring, and what a fill follows: Tracking, How it shows)
    local tpVis = BarBlock("Picture", "texlook", "Appearance", {
        "image", "color", "blend", "desat",
    }, nil, "Picture")
    BarSub(tpVis, "Fill", "texlook", { "fillDir", "ringStart", "ringDir", "fillMode" })
    BarSub(tpVis, "Dim Copy", "texlook", { "bgShow", "bgInactive", "bgAlpha", "bgTint", "bgColor", "bgDesat", "bgDesatAmount" })
    SubPush("Appearance", "Picture")
    local function WholePicture(r) return Schema.TexMode(r) == "show" end
    local tpShapeVis = BarBlock("Turn and Zoom", "texlook", "Appearance", { "rotation", "flipH", "flipV", "zoom" },
        WholePicture, "Shape")
    BarSub(tpShapeVis, "Crop", "texlook", { "cropL", "cropR", "cropT", "cropB" })
    BarSub(tpShapeVis, "Repeat", "texlook", { "tileX", "tileY" })
    SubPush("Appearance", "Shape")
    local tpMoveVis = BarBlock("Pulse", "texlook", "Appearance", { "pulse", "pulseSize", "pulseTime" }, nil, "Motion")
    BarSub(tpMoveVis, "Motion", "texlook", { "motion", "motionTime", "motionSize" })
    BarSub(tpMoveVis, "Animated Picture", "texlook", { "flipOn", "flipRows", "flipCols", "flipFrames", "flipTime" })
    SubPush("Appearance", "Motion")
    -- its size, in a picture's words
    local tpSizeVis = BarBlock("Size", "size", "Appearance", { "width", "height", "scale", "opacity" }, IsTexture, "Size", nil,
        { labels = { width = "Width", height = "Height", scale = "Scale", opacity = "Opacity" }, searchLabels = true })
    do
        local function Anchored()
            local r = SelBar()
            if not (r and not r._adMulti and tpSizeVis() and NS.Anchor and NS.Anchor.IsEnabled(r)) then return false end
            local k = Store.Resolve(r, "anchor", "anchorTargetKind") or "group"
            return k ~= "nameplate" and k ~= "mouse"
        end
        AT.Section(pg, "Match the anchor target", { visibleFn = Anchored })
        SectionRows(pg, "bar", "anchor", SelBar, Anchored, {
            "anchorMatchWidth", "anchorMatchWidthAdjust", "anchorMatchHeight", "anchorMatchHeightAdjust",
        })
    end
    SubPush("Appearance", "Size")

    -- a wheel's look (Bars\AD_Wheel.lua): one block; it never inherits, so
    -- only the Defaults page shows it outside the editor
    BarBlock("Wheel", "wheel", "Appearance", { "size", "names", "cooldowns", "counts" }, nil, "Wheel")

    -- Text: the bar's one font first, then one chip per text run.
    local textTabVis = BarTabVisible("Text")
    Options.BuildYield()
    if Options.LooksRows then
        local function TextLookVis()
            local r = SelBar()
            return textTabVis() and r ~= nil and not r._adMulti and r.barKind == "resource"
                and r.looks ~= nil and r.looks.by ~= nil
        end
        AT.Section(pg, "Look per form or spec", { visibleFn = TextLookVis })
        Options.LooksRows(pg, SelBar, TextLookVis, win, false)
    end
    -- a texture's texts carry their own font (Text tab, the picture's rows)
    local barTextTabVis = textTabVis
    textTabVis = function()
        local r = SelBar()
        return barTextTabVis() and not (r and r.barKind == "texture")
    end
    Options.BuildYield()
    AT.Section(pg, "Font", { visibleFn = textTabVis })
    Options.BuildYield()
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
    Options.BuildYield()
    Options.LookBlock("bar", "Text", "Font", "text", { "font" })
    -- the font is tab-wide (every run shares it): its own push bar
    PushBar(pg, SelBar, "text", textTabVis, { "font" })
    -- a deck bar's two texts, each with its own font (UI\AD_SpecialOptions.lua)
    if Options.SpecialBarBlocks then Options.SpecialBarBlocks("Text", BarBlock, PushBar, pg, SelBar, win) end
    -- one push bar per text run (each scoped to its own rows through
    -- Options.blockFields - the runs share the one `text` section)
    local durVis = BarBlock("Duration", "text", "Text", {
        "durShow", "durRounding", "durSize", "durOutline", "durShadow", "durColor", "durAnchor",
        "durOffsetX", "durOffsetY",
    })
    -- A run may ride another frame (TextPinRows). Not an aura bar's duration
    -- or stack (the game's button draws them) nor a cooldown bar's countdown.
    local function BarPins(blockVis, pin, show, word, allow)
        if not Options.TextPinRows then return end
        Options.TextPinRows(pg, SelBar, function()
            local r = SelBar()
            return blockVis() and r ~= nil and Store.Resolve(r, "text", show) ~= false and (not allow or allow(r))
        end, "bar", "text", pin .. "PinTo", pin .. "PinTarget", win, word)
    end
    BarPins(durVis, "dur", "durShow", "Duration text",
        function(r) return r.barKind ~= "aura" and r.barKind ~= "cooldown" end)
    BarSub(durVis, "Format", "text", { "durAbbrev", "durDecimalsEnabled", "durDecimalThreshold" })
    Options.BuildYield()
    AT.Section(pg, nil, { visibleFn = durVis })   -- push bar below the subs (BarSub)
    PushBar(pg, SelBar, "text", durVis)
    -- A cooldown bar writes its stack text only for a charge spell
    -- (maxCharges > 1); every other kind always has one.
    local function StackTextExists(r)
        if r.barKind ~= "cooldown" then return true end
        -- the spell the bar reads (its rank, its override)
        local sid = Store.RecordSpellID(r.driver)
        local info = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
        return ((info and info.maxCharges) or 0) > 1
    end
    local stkVis = BarBlock("Stack", "text", "Text", {
        "stkShow", "stkShowMax", "stkSize", "stkOutline", "stkShadow", "stkColor",
        "stkAnchor", "stkOffsetX", "stkOffsetY", "stkHideAtZero",
    }, StackTextExists)
    BarPins(stkVis, "stk", "stkShow", "Stack text", function(r) return r.barKind ~= "aura" end)
    PushBar(pg, SelBar, "text", stkVis)
    -- Resource and health texts: text 1, texts 2 and 3 in their own boxes,
    -- then the count as "+ Add" / "Remove last" buttons (the schema's adds)
    -- under the last box, in the untitled section that keeps the push bar out
    -- of that box; the count joins the block's push list by hand, since it is
    -- drawn outside the block. Their rows gate on their schema deps (show and
    -- count) and the theme hides a box whose rows are all hidden. Keep the
    -- count out of a box visibleFn: the settings search skips hidden boxes.
    do
        local resTextVis = BarBlock("Resource", "text", "Text", {
            "resShow", "resFormat", "resWholeShards", "resSize", "resOutline", "resShadow", "resColor",
            "resAnchor", "resOffsetX", "resOffsetY",
        })
        BarPins(resTextVis, "res", "resShow", "Resource text")
        BarSub(resTextVis, "Resource text 2", "text",
            { "res2Format", "res2Size", "res2Color", "res2Anchor", "res2OffsetX", "res2OffsetY" })
        BarSub(resTextVis, "Resource text 3", "text",
            { "res3Format", "res3Size", "res3Color", "res3Anchor", "res3OffsetX", "res3OffsetY" })
        AT.Section(pg, nil, { visibleFn = resTextVis })   -- push bar below the subs (BarSub)
        SectionRows(pg, "bar", "text", SelBar, resTextVis, { "resCount" })
        Options.LookBlock("bar", "Text", "Resource", "text", { "resCount" }, "Resource")
        local resList = Options.blockFields[resTextVis]
        if resList then resList[#resList + 1] = "resCount" end
        PushBar(pg, SelBar, "text", resTextVis)
        -- runes and essence: each recharging point's own countdown
        local rcVis = BarBlock("Recharge", "text", "Text", {
            "rcShow", "rcSize", "rcOutline", "rcShadow", "rcColor", "rcAnchor", "rcOffsetX", "rcOffsetY",
        }, function(r) return Schema.Recharges(r) end)
        BarSub(rcVis, "Recharge format", "text", { "rcDecimalsEnabled", "rcDecimalThreshold" })
        AT.Section(pg, nil, { visibleFn = rcVis })   -- push bar below the sub (BarSub)
        PushBar(pg, SelBar, "text", rcVis)
        local hpTextVis = BarBlock("Health", "text", "Text", {
            "hpShow", "hpFormat", "hpSize", "hpOutline", "hpShadow", "hpColor",
            "hpAnchor", "hpOffsetX", "hpOffsetY",
        })
        BarPins(hpTextVis, "hp", "hpShow", "Health text")
        BarSub(hpTextVis, "Health text 2", "text",
            { "hp2Format", "hp2Size", "hp2Color", "hp2Anchor", "hp2OffsetX", "hp2OffsetY" })
        BarSub(hpTextVis, "Health text 3", "text",
            { "hp3Format", "hp3Size", "hp3Color", "hp3Anchor", "hp3OffsetX", "hp3OffsetY" })
        AT.Section(pg, nil, { visibleFn = hpTextVis })   -- push bar below the subs (BarSub)
        SectionRows(pg, "bar", "text", SelBar, hpTextVis, { "hpCount" })
        Options.LookBlock("bar", "Text", "Health", "text", { "hpCount" }, "Health")
        local hpList = Options.blockFields[hpTextVis]
        if hpList then hpList[#hpList + 1] = "hpCount" end
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
        Options.LookBlock("bar", "Text", "Name", "text", rest, "Name")
        local list = Options.blockFields[nameVis]
        if list then
            for _, f in ipairs(rest) do list[#list + 1] = f end
        end
        BarPins(nameVis, "name", "nameShow", "Name text")
        PushBar(pg, SelBar, "text", nameVis)
    end
    PushBar(pg, SelBar, "text", BarBlock("Ready", "text", "Text", {
        "readyShow", "readyText", "readyColor",
    }))


    -- Text (textures): the aura's stack count and the time left on the
    -- picture, then their font; one page (Bars\AD_TextureElement.lua).
    BarBlock("Stack count", "pictext", "Text", {
        "ptStkShow", "ptStkSize", "ptStkColor", "ptStkAnchor", "ptStkX", "ptStkY",
    }, function(r) return Schema.TexAura(r) end, false)
    BarBlock("Time left", "pictext", "Text", {
        "ptTimeShow", "ptTimeSize", "ptTimeColor", "ptTimeAnchor", "ptTimeX", "ptTimeY",
        "ptTimeDecimals", "ptTimeDecTo",
    }, nil, false)
    BarBlock("Font", "pictext", "Text", { "ptFont", "ptOutline", "ptShadow" }, nil, false)
    SubPush("Text", nil)

    -- Conditions > By State: the state hides and their opacity (a cooldown
    -- bar's ready and full charges; an aura, timer, swing or enchant bar's
    -- inactive). Per bar, like the driver: no push bar.
    BarBlock("Hide by state", "behavior", "Conditions", {
        "hideWhenReady", "hideWhenFullCharges", "hiddenAlpha",
    }, function(r) return r.barKind == "cooldown" end, "By State")
    do
        local inactiveVis = BarBlock("Hide when inactive", "behavior", "Conditions", {
            "hideWhenInactive", "hiddenAlpha",
        }, function(r)
            return r.barKind == "aura" or r.barKind == "timer" or r.barKind == "swing" or r.barKind == "enchant"
        end, "By State")
        -- Swing bars: dim while the target is out of range of a spell, the
        -- bar's own or its hand's usual one (the field's kinds hide the sub on
        -- other bars). The spell is the bar's own (rec.driver), so its row is
        -- bespoke.
        BarSub(inactiveVis, "Out of range", "behavior", { "rangeDim" })
        local label = "Range check spell"
        local spellRow = AT.RowInput(pg, label,
            function()
                local r = SelBar()
                local id = r and r.driver and r.driver.rangeSpell
                return id and tostring(id) or ""
            end,
            function(v)
                local r = SelBar()
                if not (r and r.driver) then return end
                local DR = NS.DriverRange
                local id = (DR and DR.ParseSpell(v)) or tonumber(v)
                if id and id <= 0 then id = nil end
                if r.driver.rangeSpell == id then return end
                r.driver.rangeSpell = id
                Store.Dirty("style", r.id)
            end,
            function()
                local r = SelBar()
                -- the spell is one bar's own: not over several at once
                return inactiveVis() and r ~= nil and r.barKind == "swing" and not r._adMulti
                    and Store.Resolve(r, "behavior", "rangeDim") == true
            end,
            "The spell whose range to your target decides the dim: a spell ID, or the name of a spell you know; the rank you know is checked. Empty: your class's usual one for this hand (a melee ability, Auto Shot or the wand's Shoot). No target, or a target the spell cannot check, never dims.",
            function()
                local r = SelBar()
                local SR = NS.Bars and NS.Bars.SwingRange
                return (r and SR) and SR.SpellHint(r) or ""
            end)
        -- found by the search while the switch is off; the jump flashes the switch
        spellRow._adMeta = { family = "bar", section = "behavior", field = "rangeSpell",
            def = { label = label, dep = { field = "rangeDim" } }, baseVis = function()
                local r = SelBar()
                return inactiveVis() and r ~= nil and r.barKind == "swing"
            end }
    end
    -- Conditions > By State (resource bars): the States table, one row per
    -- state with what it changes: fill, texts, cost mark, glow
    -- (UI\AD_ResColorOptions.lua). The rows are the bar's own: no push bar,
    -- never over several.
    local statesVis = BarBlock("How the bar looks in each state", "rescolors", "Conditions", { "resTextFill" },
        nil, "By State", true, { rows = function(vis)
            if Options.ResStateRows then Options.ResStateRows(pg, SelBar, vis, win) end
        end })
    DEF_OF[statesVis].perItem = true
    -- Conditions (textures): a picture per stack count, then a look of its
    -- own under a time left. When it shows at all is Tracking's (UI\AD_TextureOptions.lua).
    -- Per picture, like its source: no push bar.
    BarBlock("Pictures by stack count", "texstate", "Conditions", {
        "stackBands", "sb1From", "sb1Image", "sb1Color", "sb2From", "sb2Image", "sb2Color",
        "sb3From", "sb3Image", "sb3Color", "sb4From", "sb4Image", "sb4Color",
    }, function(r) return Schema.TexStackBands(r) end, "Stack Pictures")
    BarBlock("A look under a time left", "texstate", "Conditions", {
        "timeOn", "timeUnit", "timePct", "timeSec", "timeLen", "timeColor",
    }, function(r) return Schema.TexTimeLook(r) end, "Time Left")
    -- a power or health picture: shown at or above a value, or below it
    BarBlock("Show by value", "texstate", "Conditions", { "valShow", "valUnit", "valPct", "valPts" },
        function(r) return Schema.TexValue(r) end, "By Value")
    -- Conditions > Glows: up to three glows around any bar, on every kind in
    -- Schema.BAR_GLOW_KINDS but a resource bar's (its glows are its States rows)
    -- (UI\AD_BarGlowOptions.lua).
    Options.BuildYield()
    if Options.BarGlowRows then
        Options.BarGlowRows(pg, SelBar, win, { BarBlock = BarBlock, SubPush = SubPush,
            SectionRows = SectionRows, BarTabVisible = BarTabVisible })
    end
    -- Conditions > Fade When: the fade rules.
    Options.BuildYield()
    VisibilityRows(pg, SelBar, BarPane("Fade When", "Conditions"))
    -- Conditions > Blizzard's Bar (resource bars): the game's own class bar,
    -- faded while this bar is loaded. Per bar: no push bar.
    BarBlock("Blizzard's Bar", "resource", "Conditions", { "hideBlizzard" },
        function(r) return Schema.HasBlizzardBar(r) end)

    -- Heals & Shields (health bars): one page of titled sections, one per
    -- overlay, and one push bar. A health bar's colour is on Fill & Colors and
    -- its texts on the Text tab.
    BarBlock("Incoming Heals", "healpred", "Heals & Shields", {
        "healShow", "healMyColor", "healOtherColor", "healAlpha",
    }, nil, false)
    BarBlock("Absorb Shields", "healpred", "Heals & Shields", {
        "absorbShow", "absorbStyle", "absorbColor", "absorbAlpha", "absorbOverflow", "absorbOver",
    }, nil, false)
    local healAbsorbVis = BarBlock("Heal Absorbs", "healpred", "Heals & Shields", {
        "healAbsorbShow", "healAbsorbColor", "healAbsorbAlpha",
    }, nil, false)
    Options.BuildYield()
    AT.RowDesc(pg, "Effects that eat healing before it lands.", 20, healAbsorbVis)
    SubPush("Heals & Shields", nil)

    -- The Castbar tab: one page of titled sections, one per job, and one push
    -- bar. Its colours live in Fill & Colors, the spell's name and time on the
    -- Text tab, its icon in Icon.
    BarBlock("Spark", "cast", "Castbar", {
        "sparkOn", "sparkColor", "sparkWidth",
    }, nil, false)
    BarBlock("When a Cast Ends", "cast", "Castbar", {
        "holdOn", "holdTime", "holdFailColor", "holdIntColor", "fadeOut",
    }, nil, false)
    local whichVis = BarBlock("Which Casts", "cast", "Castbar", {
        "hideChannels", "lockHide",
    }, nil, false)
    Options.BuildYield()
    AT.RowDesc(pg, "The shield is in Appearance > Icon, the color in Appearance > Fill & Colors.", 20, whichVis)
    -- Hidden opacity (the behavior section, not pushable): the empty bar
    -- between casts
    local idleVis = BarBlock("Between Casts", "behavior", "Castbar", { "hiddenAlpha" }, nil, false)
    Options.BuildYield()
    AT.RowDesc(pg, "0 hides the bar between casts.", 20, idleVis)
    -- your own casts only: a player castbar
    BarBlock("Your Casts", "cast", "Castbar", {
        "latencyOn", "latencyColor", "queueTickOn", "queueTickColor", "queueTickWidth", "hideBlizzard",
    }, function(r) return (r.driver and r.driver.unit or "player") == "player" end, false)
    SubPush("Castbar", nil)

    -- Position > Position: the place, then its strata and level, fine-tuning
    -- behind a fold (per bar: no push bar).
    local barPosVis = BarPane("Position", "Position")
    Options.BuildYield()
    AT.Section(pg, "Position", { visibleFn = barPosVis })
    Options.BuildYield()
    Options.PosRows(pg, SelBar, barPosVis, function(r)
        -- "anchored" = actually pinned right now: an anchor whose target
        -- is gone or hidden places free, so the sliders drive rec.pos there
        return NS.Anchor ~= nil and NS.Anchor.ResolveTarget(r) ~= nil
    end)
    Options.BuildYield()
    SectionRows(pg, "bar", "frame", SelBar, barPosVis, { "strata", "level" }, { foldAll = true })
    Options.BuildYield()
    Options.LookBlock("bar", "Position", "Position", "frame", { "strata", "level" }, "Position")
    -- Position > Anchor: a group, another bar, a free icon, a layout, a named
    -- frame, the cursor or the target's nameplate. No push bar: an anchor
    -- target is per record, like the driver.
    local anchorVis = BarPane("Anchor", "Position")
    Options.BuildYield()
    Options.AnchorPickRows(pg, "bar", SelBar, anchorVis, nil,
        "On a nameplate the bar hides while this window is open; the preview shows it.")
end

-- Empty pane

local function BuildEmptyPane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.empty = pane
    local fs = pane:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 13, "")
    fs:SetPoint("CENTER", 0, 40)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    fs:SetText("Create a layout to begin - it is one movable block on your screen.")
    local b = AT.MakeSmallButton(pane, "+ New Layout", 110)
    b:SetPoint("CENTER", 0, 8)
    b.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    b:SetScript("OnClick", function() Options.Select("newlayout") end)
end

-- What kind of layout to make. The pane and its header are the host's; the
-- cards and templates are UI\AD_NewLayout.lua's.
function Options.BuildNewLayoutPane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.newlayout = pane
    local h = MakeHeader(pane)
    h.name:SetText("New Layout")
    if NS.NewLayout then NS.NewLayout.Fill(pane) end
end

-- Home, the window's front page. The pane and its header are the host's; the
-- page is UI\AD_Home.lua's.
function Options.BuildHomePane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.home = pane
    local h = MakeHeader(pane)
    h.name:SetText("Home")
    if Options.Home then Options.Home.Fill(pane, h) end
end

-- The "N selected" pane of a multi-selection: the pane and its header are the
-- host's; UI\AD_MultiSelect.lua fills it and hosts the icon or bar editor
-- page under its actions.
function Options.BuildMultiPane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.multi = pane
    local h = MakeHeader(pane)
    local MS = Options.MultiSelect
    if MS then MS.Fill(pane, h, win, { icon = iconEditorPage, bar = barEditorPage }) end
end

-- A layout just made from the New Layout page: unfold it and open it.
function Options.OpenLayout(rec)
    ExpandedSet()[rec.id] = true
    Options.Select("layout", rec.id)
end

-- A suggestion panel's height: its status lines, or one line and the buttons
-- it shows, plus pad. An empty list leaves no gap under the field; five
-- buttons keep the height the panel always had. True when it changed.
Options.SUG_LINE = 12
Options.SUG_IDS = 5
function Options.SuggestFit(row, buttons, lines, pad)
    local h = 14 + pad
    if buttons > 0 then
        h = h + buttons * 23
    elseif lines > 1 then
        h = h + (lines - 1) * Options.SUG_LINE
    end
    if row._h == h then return false end
    row._h = h
    row:SetHeight(h)
    return true
end
-- A panel's status line i (made on first use), one under the other.
function Options.SuggestLine(row, lines, i)
    local fs = lines[i]
    if fs then return fs end
    local y = -2 - (i - 1) * Options.SUG_LINE
    fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 9, "")
    fs:SetPoint("TOPLEFT", 10, y)
    fs:SetPoint("TOPRIGHT", -12, y)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    lines[i] = fs
    return fs
end
-- The lines, shown in order; the rest emptied and hidden.
function Options.SuggestLines(row, lines, list)
    for i, t in ipairs(list) do
        local fs = Options.SuggestLine(row, lines, i)
        fs:SetText(t)
        fs:Show()
    end
    for i = #list + 1, #lines do
        lines[i]:SetText("")
        lines[i]:Hide()
    end
end
-- Aura name search for the Add window, the aura bar editor and bar glows. A
-- target's debuffs are only seen in combat, where their IDs read secret, and
-- the spellbook holds castables, not aura IDs, so names come from the game's
-- whole spell list (NS.SpellNames, read once in budgeted steps). multi: a pick
-- fills every ID of the name (icons), else the one it carries (bars). adds: a
-- pick joins the IDs already in the field (its words say so). Typed IDs get a
-- line each. The buttons are plain frames, so the settings search skips them.
function Options.AuraSuggestPanel(pg, visibleFn, getText, setText, multi, onPicked, adds)
    local row = AT.AddRow(pg, 19, visibleFn)
    local lines = {}
    Options.SuggestLine(row, lines, 1)
    local btns, lastText = {}, nil
    -- set while a layout pass runs it: that pass places the new height itself
    local syncing = false
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
        b.name:SetFont(AT.FONT, 11, "")
        b.name:SetPoint("LEFT", 27, 0)
        b.name:SetPoint("RIGHT", -110, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        b.id = b:CreateFontString(nil, "OVERLAY")
        b.id:SetFont(AT.FONT, 9, "")
        b.id:SetPoint("RIGHT", -6, 0)
        b.id:SetJustifyH("RIGHT")
        b.id:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        b:SetScript("OnEnter", function()
            b:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
            local g = b._g
            if not g then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(g.pick) -- raw-id: a name search's result
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
    -- head: the status line, or a list of lines (a readout per typed ID)
    local function Show(results, head)
        local list = (type(head) == "table") and head or { head }
        Options.SuggestLines(row, lines, list)
        local shown = 0
        for i = 1, 5 do
            local b = Btn(i)
            local g = results and results[i]
            b._g = g
            if g then
                local n = #g.ids
                shown = shown + 1
                b.tex:SetTexture(g.icon or 134400)
                b.name:SetText(g.knownID and (g.name .. "  |cff" .. AT.Hex(COL.arc) .. "(yours)|r") or g.name)
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
        if Options.SuggestFit(row, shown, #list, 5) and not syncing and row:IsShown() then
            AT.LayoutPage(pg)
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
                -- one line per ID; past the room for them, a count
                local out, cap = {}, Options.SUG_IDS
                for i, id in ipairs(ids) do
                    if i == cap and #ids > cap then
                        out[i] = ("and %d more IDs"):format(#ids - cap + 1)
                        break
                    end
                    local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: an ID typed in the box
                    out[i] = nm and (id .. " is " .. nm) or (id .. " is no spell this game knows")
                end
                Show(nil, out)
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
                Show(results, ("%d SPELL NAME%s MATCH - click one to %s"):format(
                    #results, (#results == 1) and "" or "S", adds and "add its ID" or "fill the field"))
            end
        end)
    end
    -- Every re-layout re-judges, but only a changed field searches again.
    row._sync = function()
        syncing = true
        Refresh(false)
        syncing = false
    end
    -- test handles: the status lines and the buttons
    row._adLines, row._adBtns = lines, btns
    return Refresh
end

-- The Add window

-- Pick what first (Icon, Bar or Group), then its options; the icon kinds
-- are a dropdown, not tabs.
local addState = { cat = "Icon", iconKind = "spell",
    layoutId = nil, destGroupId = nil, forceFree = false }

local function AddDestItems()
    local items = {}
    local layout = Store.Get(addState.layoutId)
    if not layout then return items end
    local groups = Store.ChildrenOf(layout)
    for _, g in ipairs(groups) do
        -- kind filter: aura groups take aura icons, reminder groups none
        if Store.GroupTakes(g, (addState.cat == "Arc Procs") and "special" or (addState.iconKind or "spell")) then
            items[#items + 1] = { value = g.id, text = g.name }
        end
    end
    items[#items + 1] = { value = 0, text = "Free position" }
    return items
end

local function BuildAddWindow()
    addWin = AT.CreateWindow("ArcUIv2Add", {
        w = 500, h = 560, minW = 500, minH = 560, resizable = false,
        title = AT.Brand("Add", " New"),
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

    local TABS = { "Icon", "Bar", "Group" }
    -- a Text element's tab (UI\AD_TextOptions.lua)
    if Options.TextAddRows then TABS[#TABS + 1] = "Text" end
    -- a texture's tab (UI\AD_TextureOptions.lua)
    if Options.TextureAddRows then TABS[#TABS + 1] = "Texture" end
    -- a wheel's tab (UI\AD_WheelOptions.lua)
    if Options.WheelAddRows then TABS[#TABS + 1] = "Wheel" end
    -- a Sound item's tab (UI\AD_SoundOptions.lua)
    if Options.SoundAddRows then TABS[#TABS + 1] = "Sound" end
    if Options.SpecialAddTab then Options.SpecialAddTab(TABS) end
    -- Opened for a Reminder group it makes a reminder: one tab, and the icon
    -- form's spell and item rows (addState.remGroupId).
    local REM_TABS = { "Reminder" }
    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local rem = addState.remGroupId ~= nil
        -- opened from a group's "+": icons into that group, nothing else
        local tabs = rem and REM_TABS or TABS
        if addState.groupOnly and not rem then
            tabs = { "Icon" }
            for _, t in ipairs(TABS) do if t == "Arc Procs" then tabs[#tabs + 1] = t end end
        end
        local h = tabRow._strip:Set(tabs, rem and "Reminder" or addState.cat, function(name)
            if rem then return end
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
            local items = {
                { value = "spell", text = "Spell Cooldown" },
                { value = "aura", text = "Aura (buff / debuff)" },
                { value = "groupbuff", text = "Group Buff (party / raid)" },
                { value = "item", text = "Item" },
                { value = "trinket", text = "Trinket" },
                { value = "totem", text = "Totem / Guardian Duration" },
            }
            -- retail has no ammo slot
            if NS.IsForever == true then items[#items + 1] = { value = "ammo", text = "Ammo" } end
            items[#items + 1] = { value = "enchant", text = "Weapon Enchant" }
            -- a Stance icon: the stance bar drives it (its driver loads first)
            if NS.DriverStance then items[#items + 1] = { value = "stance", text = "Stance" } end
            -- a Custom Icon: rules on plain events drive it (its engine loads first)
            if NS.DriverCustom then items[#items + 1] = { value = "timer", text = "Custom Icon" } end
            -- an Arc Proc (retail), the Arc Procs tab's grid under it
            local SO = Options.Special
            if SO and SO.On and SO.On() then items[#items + 1] = { value = "special", text = "Arc Proc" } end
            -- opened from a group's "+": only the kinds that group takes
            local g = addState.groupOnly and addState.destGroupId and Store.Get(addState.destGroupId)
            if g then
                local kept = {}
                for _, it in ipairs(items) do
                    if Store.GroupTakes(g, it.value) then kept[#kept + 1] = it end
                end
                items = kept
            end
            return items
        end,
        function() return addState.cat == "Icon" and not addState.remGroupId end)
    -- a cooldown group's "+" also fills it from the action bars
    AT.RowButton(pg, "From my action bars", function()
        local g = addState.destGroupId and Store.Get(addState.destGroupId)
        local BI = Options.BarImport
        if not (g and BI and BI.OpenForGroup) then return end
        addWin:Hide()
        BI.OpenForGroup(g)
    end, function()
        local g = addState.groupOnly and addState.destGroupId and Store.Get(addState.destGroupId)
        return addState.cat == "Icon" and g ~= nil and Options.BarImport ~= nil
            and Store.GroupTakes(g, "spell") == true
    end, 170)
    local remVis = function() return addState.remGroupId ~= nil end
    AT.RowDropdown(pg, addWin, "Remind me of",
        function()
            local k = addState.iconKind
            return (k == "item" or k == "enchant" or k == "aura") and k or "spell"
        end,
        function(v)
            addState.iconKind = v
            AT.LayoutPage(pg)
        end,
        function()
            return { { value = "spell", text = "A spell" }, { value = "item", text = "An item" },
                { value = "enchant", text = "A weapon enchant" }, { value = "aura", text = "A missing aura" } }
        end,
        remVis)
    AT.RowDesc(pg, "It pulses when its cooldown is back; add more triggers after.", 20,
        function() return remVis() and addState.iconKind ~= "enchant" and addState.iconKind ~= "aura" end)
    AT.RowDesc(pg, "It pulses when the enchant is missing; add more triggers after.", 20,
        function() return remVis() and addState.iconKind == "enchant" end)
    AT.RowDesc(pg, "It shows beside the pulse while the aura is missing, in combat too.", 20,
        function() return remVis() and addState.iconKind == "aura" end)
    AT.RowDesc(pg, "Your equipped ammo and its count.", 20, isIcon("ammo"))
    AT.RowDesc(pg, "A spell's cooldown as an icon.", 20,
        function() return isIcon("spell")() and not addState.remGroupId end)
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
    AT.RowDesc(pg, "A buff or debuff as an icon; several IDs can light one icon.", 20,
        function() return isIcon("aura")() and not addState.remGroupId end)
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
    -- a group buff: its ranks by name through the aura search, then counted on
    -- every member of your party or raid
    local RefreshGbSug
    AT.RowDesc(pg, "How many in your party or raid have a buff.", 20, isIcon("groupbuff"))
    local rowGbIDs = AT.RowInput(pg, "Buff name or spell IDs",
        function() return addState.gbID or "" end,
        function(v)
            addState.gbID = v
            if RefreshGbSug then RefreshGbSug(false) end
            if UpdateCreate then UpdateCreate() end
        end,
        isIcon("groupbuff"), "Type the buff's NAME to see the spell IDs that carry it, then click one (every rank comes along). Add the group version's too.", "e.g. Power Word: Fortitude", true)
    RefreshGbSug = AuraSuggest(isIcon("groupbuff"),
        function() return addState.gbID end,
        function(v)
            addState.gbID = v
            if rowGbIDs._colCtrl then rowGbIDs._colCtrl:SetText(v) end
        end, true)
    AT.RowDesc(pg, "An item's cooldown and count, by item ID.", 20,
        function() return isIcon("item")() and not addState.remGroupId end)
    -- the ready-made item lists (UI\AD_ItemSets.lua)
    if Options.ItemSetAddRows then
        Options.ItemSetAddRows(pg, addWin, addState,
            function() return isIcon("item")() and not addState.remGroupId end,
            function() if UpdateCreate then UpdateCreate() end end)
    end
    -- a reminder follows one item; an icon can take several
    AT.RowInput(pg, "Item ID",
        function() return addState.itemID or "" end,
        function(v) addState.itemID = v if UpdateCreate then UpdateCreate() end end,
        function() return isIcon("item")() and addState.remGroupId ~= nil end,
        "The numeric item ID.", "e.g. 5512", true)
    AT.RowInput(pg, "Item IDs",
        function() return addState.itemID or "" end,
        function(v)
            addState.itemID, addState.itemName, addState.itemSet = v, nil, nil
            if UpdateCreate then UpdateCreate() end
        end,
        function() return isIcon("item")() and not addState.remGroupId end,
        "The item, or several: the icon shows the first one you carry and can use.", "e.g. 5512", true)
    -- a Custom Icon's name and art (UI\AD_CustomOptions.lua)
    if Options.CustomAddRows then Options.CustomAddRows(pg, addWin, addState, "Icon") end
    -- a Stance icon: what it shows, and the stance (UI\AD_StanceOptions.lua)
    if Options.StanceAddRows then
        Options.StanceAddRows(pg, addWin, addState,
            function() return isIcon("stance")() and not addState.remGroupId end,
            function() if UpdateCreate then UpdateCreate() end end)
    end
    -- the Arc Procs tab's list (UI\AD_SpecialOptions.lua)
    if Options.SpecialAddRows then Options.SpecialAddRows(pg, addWin, addState) end

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
            items[#items + 1] = { value = "enchant", text = "Weapon Enchant Bar" }
            if C_Spell and C_Spell.IsSpellInRange then
                items[#items + 1] = { value = "range", text = "Range Bar" }
            end
            -- a Custom Bar: rules on plain events drive it (its engine loads first)
            if NS.DriverCustom then items[#items + 1] = { value = "timer", text = "Custom Bar" } end
            -- an Arc Proc's deck bar (retail), the Arc Procs tab's grid under it
            local SO = Options.Special
            if SO and SO.On and SO.On() then items[#items + 1] = { value = "special", text = "Arc Proc (deck bar)" } end
            return items
        end,
        isCat("Bar"))
    AT.RowDesc(pg, "The time left on a weapon's enchant, with its charges.", 20,
        function()
            return addState.cat == "Bar" and addState.barKind == "enchant"
        end)
    AT.RowDesc(pg, "How far your target is, in colored range bands you can edit.", 20,
        function()
            return addState.cat == "Bar" and addState.barKind == "range"
        end)
    AT.RowDropdown(pg, addWin, "Weapon",
        function() return addState.enchantHand or "main" end,
        function(v) addState.enchantHand = v end,
        function() return Options.EnchantHandItems() end,
        function()
            return addState.cat == "Bar" and addState.barKind == "enchant"
        end)
    Options.EnchantTemplateGrid(pg,
        function()
            return addState.cat == "Bar" and addState.barKind == "enchant" and Options.HasEnchantTemplates()
        end,
        function() return addState.enchantTemplate or "" end,
        function(v) addState.enchantTemplate = v end,
        true, function() return addState.enchantHand end)
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
            return addState.cat == "Bar" and (bk == "cooldown" or bk == "aura" or bk == "timer")
        end,
        function() AT.LayoutPage(pg) end)
    -- a Custom Bar's name and art (UI\AD_CustomOptions.lua)
    if Options.CustomAddRows then Options.CustomAddRows(pg, addWin, addState, "Bar") end
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

    -- Spellbook picker, cooldown spells only (spell icons, cooldown bars):
    -- every catalog spell as a square. Typing filters it, a click fills the
    -- field. The height follows the whole catalog, not the matches, so typing
    -- never moves the rows below; past SUG.rows rows it scrolls.
    local SUG = { cell = 32, gap = 4, rows = 8, top = 14 }
    SUG.pitch = SUG.cell + SUG.gap
    -- The window is fixed-width: less the page, box and row insets (10, 6
    -- and 6 a side) and the grid's own 8 left and 12 right.
    SUG.cols = math.max(1, math.floor((addWin:GetWidth() - 64 + SUG.gap) / SUG.pitch))
    local function sugVis()
        if addState.cat == "Icon" then
            return (addState.iconKind or "spell") == "spell"
        end
        return barUsesSpell()
    end
    local sugRow = AT.AddRow(pg, SUG.top + SUG.pitch, sugVis)
    addWin._sugRow = sugRow
    local sugLabel = sugRow:CreateFontString(nil, "OVERLAY")
    sugLabel:SetFont(AT.FONT, 9, "")
    sugLabel:SetPoint("TOPLEFT", 10, -2)
    sugLabel:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    sugLabel:SetText("FROM YOUR SPELLBOOK - click to fill")
    sugRow._scroll, sugRow._grid = AT.MakeScroll(sugRow)
    sugRow._scroll:SetPoint("TOPLEFT", 8, -SUG.top)
    sugRow._scroll:SetPoint("BOTTOMRIGHT", -12, SUG.gap)
    sugRow._empty = sugRow:CreateFontString(nil, "OVERLAY")
    sugRow._empty:SetFont(AT.FONT, 11, "")
    sugRow._empty:SetPoint("LEFT", sugRow._scroll, "TOPLEFT", 2, -SUG.cell / 2)
    sugRow._empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local sugBtns = {}
    sugRow._cells = sugBtns
    local function SugBtn(i)
        local b = sugBtns[i]
        if b then return b end
        b = CreateFrame("Button", nil, sugRow._grid, "BackdropTemplate")
        b:SetSize(SUG.cell, SUG.cell)
        AT.Skin(b, COL.well, COL.line)
        -- inset past the edge (a hairline, 2 px at a fractional scale) so
        -- the art never covers the border
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- the pick stays cyan under the cursor too
        function b.Edge(hot)
            local c = (b._picked and COL.arc) or (hot and COL.focus) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            local e = b._e
            if not e then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(e.spellID) -- raw-id: a catalog entry
            GameTooltip:AddLine("Spell ID: " .. e.spellID, COL.arc[1], COL.arc[2], COL.arc[3])
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            local e = b._e
            if not e then return end
            local v = tostring(e.spellID)
            local target = rowSpell
            if addState.cat == "Bar" then addState.barSpell, target = v, rowBarSpell
            else addState.spellID = v end
            if target._colCtrl then target._colCtrl:SetText(v) end
            UpdateSuggestions()
            -- The pick is the commit: Create comes on at once.
            if UpdateCreate then UpdateCreate() end
        end)
        sugBtns[i] = b
        return b
    end
    UpdateSuggestions = function(inLayout)
        if not sugVis() then return end
        local query = (addState.cat == "Bar") and addState.barSpell or addState.spellID
        local all = NS.SpellCatalog.All()
        local want = SUG.top + SUG.pitch * math.min(SUG.rows, math.max(1, math.ceil(#all / SUG.cols)))
        if sugRow._h ~= want then
            sugRow._h = want
            sugRow:SetHeight(want)
            -- the rows below move with it; that pass syncs back here
            if not inLayout then AT.LayoutPage(pg) return end
        end
        -- A picked or typed ID shows every spell with that one lit, so
        -- picking another needs no clearing first.
        local pickID = tonumber(query or "")
        local results
        if pickID then
            for _, e in ipairs(all) do
                if e.spellID == pickID then results = all break end -- raw-id: a catalog pick, not a match
            end
        end
        results = results or NS.SpellCatalog.Search(query, #all)
        for i, e in ipairs(results) do
            local b = SugBtn(i)
            b._e, b._picked = e, e.spellID == pickID -- raw-id: a catalog pick, not a match
            b.tex:SetTexture(e.texture)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ((i - 1) % SUG.cols) * SUG.pitch,
                -math.floor((i - 1) / SUG.cols) * SUG.pitch)
            b.Edge(b:IsMouseOver())
            b:Show()
        end
        for i = #results + 1, #sugBtns do
            sugBtns[i]._e = nil
            sugBtns[i]:Hide()
        end
        local rows = math.ceil(#results / SUG.cols)
        sugRow._grid:SetSize(SUG.cols * SUG.pitch - SUG.gap, math.max(1, rows * SUG.pitch - SUG.gap))
        sugRow._scroll:UpdateScroll()
        sugRow._empty:SetShown(#results == 0)
        sugRow._empty:SetText((#all == 0) and "No spells listed yet: type a spell ID."
            or "Nothing in your spellbook matches: a spell ID still works.")
    end
    sugRow._sync = function() UpdateSuggestions(true) end
    AT.RowDropdown(pg, addWin, "Trinket slot",
        function() return addState.slotID or 13 end,
        function(v) addState.slotID = v end,
        function() return { { value = 13, text = "Trinket 1 (top)" }, { value = 14, text = "Trinket 2 (bottom)" } } end,
        isIcon("trinket"))
    AT.RowDesc(pg, "Lit while an enchant is on the weapon: an imbue, a poison, an oil or a stone.", 20,
        function() return isIcon("enchant")() and not addState.remGroupId end)
    AT.RowDropdown(pg, addWin, "Weapon",
        function() return addState.enchantHand or "main" end,
        function(v) addState.enchantHand = v end,
        function() return Options.EnchantHandItems() end,
        isIcon("enchant"))
    Options.EnchantTemplateGrid(pg,
        function() return isIcon("enchant")() and not addState.remGroupId and Options.HasEnchantTemplates() end,
        function() return addState.enchantTemplate or "" end,
        function(v) addState.enchantTemplate = v end,
        true, function() return addState.enchantHand end)
    local totemVis = isIcon("totem")
    AT.RowDesc(pg, "A totem or guardian in its slot, or one of them by the spell that puts it down.", 20,
        totemVis)
    AT.RowInput(pg, "Spell ID",
        function() return addState.totemSpell or "" end,
        function(v) addState.totemSpell = v end,
        totemVis, "The spell that puts it down: the icon follows that totem or guardian, any rank, into whatever slot it lands. Empty: whatever is in the slot.",
        "Optional", true)
    local addSlotRow = AT.RowDropdown(pg, addWin, "Totem slot",
        function() return addState.totemSlot or 1 end,
        function(v) addState.totemSlot = v end,
        function() return Options.TotemSlotItems() end,
        function()
            local sid = tonumber(addState.totemSpell)
            return totemVis() and not (sid and sid > 0)
        end)
    AT.Tooltip(addSlotRow, "Totem slot", Options.TotemSlotTip)
    AT.RowInput(pg, "Group name",
        function() return addState.groupName or "" end,
        function(v) addState.groupName = v end,
        isCat("Group"), nil, "e.g. Core Rotation", true)
    AT.RowDropdown(pg, addWin, "Group kind",
        function() return addState.groupKind or "cooldown" end,
        function(v) addState.groupKind = v AT.LayoutPage(pg) end,
        function()
            local items = { { value = "cooldown", text = "CD Group" }, { value = "aura", text = "Aura Group" } }
            if NS.Reminders then items[#items + 1] = { value = "reminder", text = "Reminder Group" } end
            -- an aura group made from a template (UI\AD_MissingBuffs.lua)
            if Options.MissingBuffsAddRows then items[#items + 1] = { value = "missing", text = "Missing Buffs" } end
            return items
        end,
        isCat("Group"))
    AT.RowDesc(pg, "A spot mid-screen where your cooldowns pulse as they come back.", 20,
        function() return addState.cat == "Group" and addState.groupKind == "reminder" end)
    AT.RowToggle(pg, "Fill it from my action bars",
        function() return addState.fillFromBars == true end,
        function(v) addState.fillFromBars = v end,
        function() return addState.cat == "Group" and (addState.groupKind or "cooldown") == "cooldown" end,
        "Opens a picker for this group's spells and items right after Create. Out of combat only.")
    if Options.MissingBuffsAddRows then Options.MissingBuffsAddRows(pg, addWin, addState) end
    if Options.TextAddRows then Options.TextAddRows(pg, addWin, addState) end
    if Options.TextureAddRows then Options.TextureAddRows(pg, addWin, addState) end
    if Options.WheelAddRows then Options.WheelAddRows(pg, addWin, addState) end
    if Options.SoundAddRows then Options.SoundAddRows(pg, addWin, addState) end

    -- only icons pick a destination: bars are always free, groups have none
    AT.RowDropdown(pg, addWin, "Add to",
        function() return addState.destGroupId or 0 end,
        function(v) addState.destGroupId = v ~= 0 and v or nil AT.LayoutPage(pg) end,
        AddDestItems,
        function()
            -- an Arc Procs tab pick made as a deck bar is a bar: always free
            if addState.cat == "Arc Procs" and Options.SpecialMakesBar and Options.SpecialMakesBar(addState) then return false end
            return (addState.cat == "Icon" or addState.cat == "Arc Procs") and not addState.remGroupId
        end)
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
    create.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    local cancel = AT.MakeSmallButton(btnRow, "Cancel", 64)
    cancel:SetPoint("LEFT", create, "RIGHT", 6, 0)
    cancel:SetScript("OnClick", function() addWin:Hide() end)

    -- What the click needs, mirrored so Create only lights when it will work: an
    -- aura stack bar needs the game's maximum or a typed one. A disabled Button
    -- takes no click or hover, so the dim look holds.
    local function CanCreate()
        if not Store.Get(addState.layoutId) then return false end
        if addState.cat == "Group" and addState.groupKind == "missing" then
            return Options.MissingBuffsCanCreate ~= nil and Options.MissingBuffsCanCreate(addState)
        end
        -- an Arc Proc, from its tab or as an icon or bar kind
        if addState.cat == "Arc Procs" or (addState.cat == "Icon" and addState.iconKind == "special")
            or (addState.cat == "Bar" and addState.barKind == "special") then
            return Options.SpecialCanCreate ~= nil and Options.SpecialCanCreate(addState)
        end
        if addState.cat == "Icon" then
            local ik = addState.iconKind or "spell"
            if ik == "spell" then return (addState.spellID or "") ~= "" end
            if ik == "aura" then return #Options.ParseSpellIDs(addState.auraID) > 0 end
            if ik == "groupbuff" then return #Options.ParseSpellIDs(addState.gbID) > 0 end
            if ik == "item" then return #Options.ParseSpellIDs(addState.itemID) > 0 end
            if ik == "timer" then return Options.CustomCreate ~= nil end
            if ik == "stance" then return Options.StanceCanCreate ~= nil and Options.StanceCanCreate(addState) end
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
            elseif bk == "timer" then
                return Options.CustomBarDriver ~= nil
            end
            return true
        elseif addState.cat == "Text" then
            return Options.TextCreate ~= nil
        elseif addState.cat == "Texture" then
            return Options.TextureCanCreate ~= nil and Options.TextureCanCreate(addState)
        elseif addState.cat == "Wheel" then
            return Options.WheelCreate ~= nil
        elseif addState.cat == "Sound" then
            return Options.SoundCreate ~= nil
        end
        return true
    end
    UpdateCreate = function()
        local on = CanCreate()
        create:SetEnabled(on)
        create:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        if on then
            create.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
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
        -- at a group that does not take this one - fall back to free
        if dest and iconKind then
            local g = Store.Get(dest)
            if g and not Store.GroupTakes(g, iconKind) then dest = nil end
        end
        -- Accept an ID or a typed name (the first autocomplete match wins).
        local function ResolveSpellInput(text)
            local sid = tonumber(text)
            if sid then return sid end
            if not text or text == "" then return nil end
            local results = NS.SpellCatalog.Search(text, 1)
            return results[1] and results[1].spellID or nil
        end
        -- the aura form's driver and name: an aura icon's, or an aura reminder's.
        -- The field holds IDs by now (a picked name fills them in); a typed
        -- name alone never resolves here. Every listed id rides the icon's
        -- one button.
        local function AuraFromForm()
            local ids = Options.ParseSpellIDs(addState.auraID)
            if #ids == 0 then return nil end
            local t = (addState.auraType == "debuff") and "debuff" or "buff"
            local caster = addState.auraCaster
            local driver = {
                auraType = t,
                unit = addState.auraUnit or ((t == "debuff") and "target" or "player"),
                caster = (caster == "mine" or caster == "others") and caster or nil,
            }
            Options.SetAuraSpellIDs(driver, ids)
            return driver, (C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])) or ("Aura " .. ids[1])
        end
        -- a Reminder group's add makes a reminder for it; an aura makes an
        -- aura reminder, an aura icon in its row
        local remG = addState.remGroupId and Store.Get(addState.remGroupId)
        if remG and iconKind == "aura" then
            local driver, name = AuraFromForm()
            if not driver then return end
            local rec = Store.NewAuraReminder(remG.id, driver, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
            return
        end
        if remG then
            local kind = (iconKind == "item" or iconKind == "enchant") and iconKind or "spell"
            local id
            if kind == "enchant" then
                id = (addState.enchantHand == "off") and "off" or "main"
            elseif kind == "item" then
                id = Options.ParseSpellIDs(addState.itemID)[1]
            else
                id = ResolveSpellInput(addState.spellID)
            end
            local RP = Options.ReminderPane
            if not (id and RP) then return end
            -- one reminder per spell, item or hand in a group: one it has opens
            if RP.Create(remG, kind, id) then addWin:Hide() end
            return
        end
        if iconKind == "spell" then
            local sid = ResolveSpellInput(addState.spellID)
            if not sid then return end
            local name = (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Spell " .. sid) -- raw-id: the Add window's typed spell
            local rec = Store.NewIcon("spell", { spellID = sid }, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "aura" then
            local driver, name = AuraFromForm()
            if not driver then return end
            local rec = Store.NewIcon("aura", driver, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "groupbuff" then
            local ids = Options.ParseSpellIDs(addState.gbID)
            if #ids == 0 then return end
            local driver = {}
            Options.SetAuraSpellIDs(driver, ids)
            local name = (C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])) or ("Buff " .. ids[1])
            local rec = Store.NewIcon("groupbuff", driver, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "item" then
            local ids = Options.ParseSpellIDs(addState.itemID)
            if #ids == 0 then return end
            local d = {}
            Options.SetItemIDs(d, ids)
            -- a ready-made list names the icon after itself
            local name = addState.itemName
                or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(ids[1]))
                or ("Item " .. ids[1])
            local rec = Store.NewIcon("item", d, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "trinket" then
            local slot = addState.slotID or 13
            local rec = Store.NewIcon("trinket", { slotID = slot }, dest, layoutId,
                slot == 13 and "Trinket 1" or "Trinket 2")
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "totem" then
            local slot = addState.totemSlot or 1
            local sid = tonumber(addState.totemSpell)
            if sid and sid <= 0 then sid = nil end
            local name = (sid and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) -- raw-id: the Add window's typed spell
                or ("Totem Slot " .. slot)
            local rec = Store.NewIcon("totem", { slot = slot, spellID = sid }, dest, layoutId, name)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "ammo" then
            -- Nothing to configure: the icon is the ammo slot.
            local rec = Store.NewIcon("ammo", {}, dest, layoutId, "Ammo")
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "enchant" then
            local hand = (addState.enchantHand == "off") and "off" or "main"
            local driver = { hand = hand }
            local t = (addState.enchantTemplate or "") ~= "" and Options.UseEnchantTemplate(driver, addState.enchantTemplate)
            local rec = Store.NewIcon("enchant", driver, dest, layoutId,
                t and Options.EnchantTemplateName(t, hand) or ((hand == "off" and "Off Hand" or "Main Hand") .. " Enchant"))
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "timer" then
            local rec = Options.CustomCreate and Options.CustomCreate(addState, dest, layoutId)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif iconKind == "stance" then
            local rec = Options.StanceCreate and Options.StanceCreate(addState, dest, layoutId)
            if rec then addWin:Hide() Options.SelectIconHome(rec) end
        elseif addState.cat == "Arc Procs" or iconKind == "special"
            or (addState.cat == "Bar" and addState.barKind == "special") then
            local rec = Options.SpecialCreate and Options.SpecialCreate(addState, dest, layoutId)
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
            elseif bk == "enchant" then
                local hand = (addState.enchantHand == "off") and "off" or "main"
                driver = { hand = hand }
                local t = (addState.enchantTemplate or "") ~= "" and Options.UseEnchantTemplate(driver, addState.enchantTemplate)
                name = t and Options.EnchantTemplateName(t, hand) or ((hand == "off" and "Off Hand" or "Main Hand") .. " Enchant")
                mode = nil
            elseif bk == "range" then
                -- the class's preset; its spell stays empty to follow the class default
                local RBm = NS.RangeBars
                driver = { preset = RBm and RBm.DefaultPreset() or "melee" }
                name = "Target Range"
                mode = nil
            elseif bk == "timer" then
                if not Options.CustomBarDriver then return end
                driver, name = Options.CustomBarDriver(addState)
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
                name = (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Aura " .. sid) -- raw-id: the Add window's typed aura
            else
                bk = "cooldown"
                local sid = ResolveSpellInput(addState.barSpell)
                if not sid then return end
                driver = { spellID = sid }
                name = (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Spell " .. sid) -- raw-id: the Add window's typed spell
            end
            local rec = Store.NewBar(layoutId, bk, driver, name, mode)
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("bar", rec.id)
            end
        elseif addState.cat == "Text" then
            local rec = Options.TextCreate and Options.TextCreate(addState, layoutId)
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("bar", rec.id)
            end
        elseif addState.cat == "Texture" then
            local rec = Options.TextureCreate and Options.TextureCreate(addState, layoutId)
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("bar", rec.id)
            end
        elseif addState.cat == "Wheel" then
            local rec = Options.WheelCreate and Options.WheelCreate(addState, layoutId)
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("bar", rec.id)
            end
        elseif addState.cat == "Sound" then
            local rec = Options.SoundCreate and Options.SoundCreate(addState, layoutId)
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("bar", rec.id)
            end
        elseif addState.cat == "Group" and addState.groupKind == "missing" then
            Options.MissingBuffsCreate(addState, layoutId, function() AT.LayoutPage(pg) end, function(rec)
                AT.LayoutPage(pg)
                if rec then
                    addWin:Hide()
                    ExpandedSet()[layoutId] = true
                    Options.Select("group", rec.id)
                end
            end)
            AT.LayoutPage(pg)
        elseif addState.cat == "Group" then
            local rec = Store.NewGroup(layoutId, addState.groupName ~= "" and addState.groupName or nil,
                addState.groupKind or "cooldown")
            if rec then
                addWin:Hide()
                ExpandedSet()[layoutId] = true
                Options.Select("group", rec.id)
                if addState.fillFromBars and Options.BarImport then
                    Options.BarImport.OpenForGroup(rec)
                end
            end
        end
    end)
end

function Options.OpenAdd(layoutId, destGroupId, forceFree)
    if not addWin then BuildAddWindow() end
    addState.layoutId = layoutId
    addState.destGroupId = destGroupId
    addState.forceFree = forceFree and true or false
    addState.remGroupId = nil
    addState.groupOnly = destGroupId ~= nil
    if destGroupId then
        -- adding into a group = adding an icon; aura groups preselect aura
        addState.cat = "Icon"
        local g = Store.Get(destGroupId)
        if g and g.groupKind == "aura" then addState.iconKind = "aura" end
        -- a kind this group does not take falls back to the first it does (a
        -- Reminder group takes no icons: its own branch below picks)
        if g and g.groupKind ~= "reminder" and not Store.GroupTakes(g, addState.iconKind or "spell") then
            addState.iconKind = Store.GroupTakes(g, "aura") and "aura" or "spell"
        end
        -- a Reminder group's add makes a reminder, of a spell, an item or an enchant
        if g and g.groupKind == "reminder" then
            addState.remGroupId = g.id
            local k = addState.iconKind
            if k ~= "item" and k ~= "enchant" then addState.iconKind = "spell" end
        end
    end
    addWin:ClearAllPoints()
    addWin:SetPoint("CENTER", win, "CENTER", 0, 20)
    addWin:Show()
    AT.LayoutPage(addWin._pg)
end

-- A Custom Bar template found in the search: the Add window opens on it,
-- picked, for the layout open now, else the first.
function Options.OpenAddTemplate(key)
    local CO = Options.Custom
    local lay = SelLayout() or Store.Layouts()[1]
    if not (CO and CO.Pick and lay) then return end
    Options.OpenAdd(lay.id)
    addState.cat, addState.barKind = "Bar", "timer"
    CO.Pick(addState, key)
    AT.LayoutPage(addWin._pg)
end

-- after creating an icon, land where it lives
function Options.SelectIconHome(rec)
    local L = Options.Loader
    if L and L.Busy() and not L.InBuild() then
        L.Then(function() Options.SelectIconHome(rec) end)
        return
    end
    -- a reminder opens in its group's pane, in its own editor
    if rec.type == "reminder" then
        ui.selRemId, ui.grpMode = rec.id, "rem"
        ExpandedSet()[rec.groupId] = true
        Options.Select("group", rec.groupId)
        return
    end
    -- a deck bar made on the Arc Procs tab opens in the bar editor
    if rec.type == "bar" then
        ExpandedSet()[rec.layoutId] = true
        Options.Select("bar", rec.id)
        return
    end
    ui.selIconId = rec.id
    if rec.groupId then
        ui.grpMode = "ico"
        -- the sidebar opens the group to show the icon being edited
        ExpandedSet()[rec.groupId] = true
        Options.Select("group", rec.groupId)
    else
        Options.Select("free", rec.layoutId)
    end
end

-- Addon panes: Settings, Modules and Import / Export

local settingsPane, settingsPage
local iePane, ieBox, ieScroll, ieStatus, ieListHost
-- The Import / Export page's helpers and widgets share one table because of
-- the 200-local limit.
local IE = {
    rowPool = {},   -- picker rows
    PICK_H = 176,   -- the export picker's window; a longer tree scrolls
    ROW_H = 22,
    TOP = 64,       -- the Export and Import panes start under the tab strip
    NOTE_H = 26,    -- a pane's one-line note, then its first box
    HEAD_H = 26,    -- a box's header strip
    GAP = 10,       -- between boxes
    FOOT_H = 34,    -- WHAT TO SHARE's bar
    LIST_H = 252,   -- the tree at most; a short window takes from it first
    STR_MIN = 150,  -- YOUR STRING at least
    PACK_OPEN_H = 92, -- PACK INFO's fields, two lines of a label over its box
    PASTE_H = 96,   -- the paste box at most
    PASTE_ROW_H = 36, -- the row under it, Clear at its end
    WHAT_H = 100,   -- WHAT'S IN IT's body (76 on a short window)
    WHAT_H_SHORT = 76,
    WHERE_MIN = 190, -- WHERE IT GOES at least: four rows and its bar
    IMP_FOOT_H = 40, -- WHERE IT GOES's bar, Import on it
    WHERE_H = 28,   -- a WHERE IT GOES row
    WHERE_X = 200,  -- where a row's text starts
    keep = {},      -- the update panel's Keep mine ticks, by uid
}
local railAddonRows = {}

local function PaintAddonRows()
    for pane, r in pairs(railAddonRows) do
        PaintRailRow(r, ui.selType == pane, pane == "home" and "layout" or "child")
    end
    -- the Modules row's dot, while a module card still says NEW
    if Options.Modules then Options.Modules.PaintRailDot(railAddonRows.modules) end
    -- the Home row's dot, while a layout pack update waits there
    if Options.Home then Options.Home.PaintRailDot(railAddonRows.home) end
    -- the Defaults row's NEW mark, for one version
    if Options.Defaults then Options.Defaults.PaintRail() end
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
    -- palettes, finish and scroll bar width (UI\AD_ThemeOptions.lua)
    if Options.Theme then Options.Theme.Build(pg, win) end
    Options.BuildYield()
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
    Options.BuildYield()
    local scaleRow = AT.RowSlider(pg, "Panel scale",
        -- unsaved = the scale the window really runs at (AT.uiScale, 0.85),
        -- so the first nudge steps from what is on screen
        function() return Store.GetSetting("uiScale") or AT.uiScale or 1 end,
        function(v)
            Store.SetSetting("uiScale", v)
            scalePending = v
            -- IsMouseButtonDown covers a mouse-down the hooks
            -- never saw, so a missed hook cannot strand the apply mid-drag.
            if not scaleDragging and not IsMouseButtonDown() then ApplyScale() end
        end,
        AT.UI_SCALE_MIN or 0.2, 1.6, 0.05, true, nil)
    local scaleSlider = scaleRow and scaleRow._colCtrl
    if scaleSlider then
        scaleSlider:HookScript("OnMouseDown", function() scaleDragging = true end)
        scaleSlider:HookScript("OnMouseUp", function()
            scaleDragging = false
            ApplyScale()
        end)
    end
    Options.BuildYield()
    AT.RowDesc(pg, "The resize lands when you let go of the slider.", 20)
    -- Editing preview: the minimum alpha Factory's state writer uses while this
    -- window is open (default 0.35).
    Options.BuildYield()
    AT.RowSlider(pg, "Editing preview opacity",
        function()
            local v = Store.GetSetting("previewAlpha")
            if v == nil then v = 0.35 end
            return v
        end,
        function(v) Store.SetSetting("previewAlpha", v) end,
        0, 1, 0.05, true, nil)
    Options.BuildYield()
    AT.RowDesc(pg, "Hidden or dimmed icons show at least this much while this window is open.", 20)
    Options.BuildYield()
    AT.RowToggle(pg, "Show unloaded items while editing",
        function() return Store.GetSetting("showUnloaded") == true end,
        function(v)
            Store.SetSetting("showUnloaded", v and true or false)
            -- Every element's own eye goes back to following this switch.
            Store.ResetUnloadedShown()
            RefreshAll()
        end,
        nil, "While this window is open, every layout, group, icon and bar whose load conditions fail on this character is drawn anyway, each with a small slashed eye in its corner, so you can place and style it. Each one's eye, in the sidebar and on the layout tiles, shows or hides it on its own, and flipping this switch sets them all again. Load conditions stay exactly as they are, and closing the window hides everything unloaded.")
    Options.BuildYield()
    AT.RowToggle(pg, "Mark unloaded items",
        function() return Store.GetSetting("hideGhostMark") ~= true end,
        function(v) Store.SetSetting("hideGhostMark", (not v) and true or nil) end,
        nil, "Unloaded items drawn while this window is open carry a small slashed eye in their corner. Turn this off to draw them without it.")
    -- Every More options fold stays open (UI\AD_EditorTabs.lua).
    Options.BuildYield()
    AT.RowToggle(pg, "Show every option",
        function() return Store.GetSetting("showEveryOption") == true end,
        function(v)
            Store.SetSetting("showEveryOption", v and true or nil)
            RefreshAll()
        end,
        nil, "Opens every More options fold in the editors, so the fine-tuning rows show without a click. Off: they wait behind their fold.")
    Options.BuildYield()
    AT.Section(pg, "Group Editing")
    Options.BuildYield()
    AT.RowToggle(pg, "Show layout arrows",
        function() return Store.GetSetting("showLayoutArrows") ~= false end,   -- on by default
        function(v)
            Store.SetSetting("showLayoutArrows", v and true or false)
            if Engine and Engine.RefreshArrows then Engine.RefreshArrows() end
        end,
        nil, "While this window is open, the group you are editing shows arrows on its bottom, left and right edges: green adds a row or a column on that side, red removes one. The icons stay where they are.")
    Options.BuildYield()
    AT.RowToggle(pg, "Show group names",
        function() return Store.GetSetting("groupNames") ~= false end,   -- on by default
        function(v) Store.SetSetting("groupNames", v and true or false) end,
        nil, "While this window is open, each group shows its name on its top edge, which is what you drag the group by. Off: a small green handle stays there instead; hover it to see the name.")
    -- Which kinds keep their Edit chips: read through Factory.EditChipsOn
    -- (nil = all). The rebuild the setting's dirty queues re-places every chip.
    Options.BuildYield()
    local chipRow = AT.RowDropdown(pg, win, "Edit buttons on screen",
        function() return Store.GetSetting("editButtons") or "all" end,
        function(v) Store.SetSetting("editButtons", (v ~= "all") and v or nil) end,
        function()
            return {
                { value = "all", text = "All" },
                { value = "icons", text = "Icons only" },
                { value = "bars", text = "Bars only" },
                { value = "none", text = "None" },
            }
        end)
    AT.Tooltip(chipRow, "Edit buttons on screen",
        "While this window is open, icons and bars carry a small Edit button that opens them here. Icons only or Bars only hides the other kind's buttons, None hides them all; the sidebar and the search still open every item. The buttons come back when you pick All.")
    Options.BuildYield()
    AT.Section(pg, "Icon Mouse")
    Options.BuildYield()
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
    Options.BuildYield()
    AT.RowToggle(pg, "Only while this window is open",
        function() return Store.GetSetting("tooltipsEditOnly") == true end,
        function(v) Store.SetSetting("tooltipsEditOnly", v and true or nil) end,
        function() return Store.GetSetting("showTooltips") ~= false end,
        "Icon tooltips show only while this options window is open, so you can tell your icons apart while you edit, and never while you play. Normally it is the other way round: tooltips while you play, none while this window is open.")
    Options.BuildYield()
    AT.RowToggle(pg, "Click-through icons",
        function() return Store.GetSetting("clickThrough") ~= false end,
        function(v) Store.SetSetting("clickThrough", v and true or false) end,
        nil, "Clicks pass through icons to the game world underneath. Tooltips still show while the toggle above is on. While this options window is open every icon takes the mouse regardless, for dragging.")
    -- Button Press Highlight and Tooltip IDs are modules now (UI\AD_Modules.lua).
    -- Timer rounding: one choice for every countdown, read through
    -- Factory.TimerRounding (nil = up).
    Options.BuildYield()
    AT.Section(pg, "Timers")
    Options.BuildYield()
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
        "How every Arc Auras countdown shows part of a second: icons, aura bars, timer bars and swing bars. Up: 13.2 seconds reads 14, the way action bar cooldowns count, so a running timer never reads 0. Down: 13.2 seconds reads 13, the way buff timers and most nameplates count. Decimals, where you turned them on, show the tenths either way.")
    -- The game's Cooldown Manager, switched off here as in the game's own
    -- options: Arc Auras reads its lists, which work either way.
    local cdmVis = function()
        return C_CVar ~= nil and C_CVar.GetCVar ~= nil and C_CVar.GetCVar("cooldownViewerEnabled") ~= nil
    end
    Options.BuildYield()
    AT.Section(pg, "Cooldown Manager", { visibleFn = cdmVis })
    Options.BuildYield()
    AT.RowToggle(pg, "Turn off the game's Cooldown Manager",
        function() return C_CVar.GetCVar("cooldownViewerEnabled") == "0" end,
        function(v)
            C_CVar.SetCVar("cooldownViewerEnabled", v and "0" or "1")
            if NS.LayoutEngine and NS.LayoutEngine.QueueRebuild then NS.LayoutEngine.QueueRebuild() end
        end,
        cdmVis, "The game's own cooldown and buff icons and bars, as in its options. Items pinned to its icons stand free until it is back on.")
    -- One pass from it: its bars become a new layout (NS.CDMMirror.Build), then
    -- it turns off. A copy that fails leaves it on, its reason on a line below.
    local cdmWhy
    local cdmOnVis = function()
        return cdmVis() and C_CVar.GetCVar("cooldownViewerEnabled") ~= "0"
            and NS.CDMMirror ~= nil and NS.CDMMirror.Available() == true
    end
    Options.BuildYield()
    local cdmCopy = AT.RowButton(pg, "Copy and turn off", function()
        local function Failed(why)
            cdmWhy = (why == "empty") and "empty" or "read"
            RefreshAll()
        end
        local why = NS.CDMMirror.Check()
        if why then return Failed(why) end
        -- the look question first, as the New Layout card asks it
        local function Go(look)
            local lay, why2 = NS.CDMMirror.Build(look)
            if not lay then return Failed(why2) end
            cdmWhy = nil
            C_CVar.SetCVar("cooldownViewerEnabled", "0")
            if NS.LayoutEngine and NS.LayoutEngine.QueueRebuild then NS.LayoutEngine.QueueRebuild() end
            Options.OpenLayout(lay)
        end
        local MO = NS.CDMMirrorOptions
        if MO and MO.AskLook then MO.AskLook(Go) else Go(false) end
    end, cdmOnVis, nil, "Copy its bars into a new layout")
    AT.Tooltip(cdmCopy.button, "Copy and turn off",
        "Its bars become a new layout of groups: same spells, sizes and places. Then it turns off.")
    for _, k in ipairs({ "empty", "read" }) do
        AT.RowDesc(pg, NS.CDMMirrorOptions and NS.CDMMirrorOptions.SAY[k] or "", 20,
            function() return cdmWhy == k and cdmOnVis() end)
    end
    -- The "Ammo is low" condition's line; icons keep their own thresholds.
    local hunterVis = function() return NS.IsForever == true and Store.ClassTag() == "HUNTER" end
    Options.BuildYield()
    AT.Section(pg, "Ammo", { visibleFn = hunterVis })
    Options.BuildYield()
    local ammoRow = AT.RowSlider(pg, "Ammo is low at or below",
        function() return Store.GetSetting("ammoLowAt") or NS.Conditions.AMMO_LOW_AT end,
        function(v)
            Store.SetSetting("ammoLowAt", v ~= NS.Conditions.AMMO_LOW_AT and v or nil)
            NS.Conditions.Queue()
        end, 50, 2000, 1, false, hunterVis)
    AT.Tooltip(ammoRow, "Ammo is low at or below",
        "The count the \"Ammo is low\" load and visibility condition uses. An icon's warning glow and ammo count colors have their own thresholds.")
    Options.BuildYield()
    AT.Section(pg, "Minimap")
    Options.BuildYield()
    AT.RowToggle(pg, "Hide minimap button",
        function() return Store.GetSetting("minimapHide") == true end,
        function(v)
            Store.SetSetting("minimapHide", v and true or false)
            if NS.MinimapButtonRefresh then NS.MinimapButtonRefresh() end
        end,
        nil, "Hides the Arc Auras minimap button. "
            .. (NS.IsForever and "/arcui" or "/arcui2")
            .. " always opens this window. Drag the button around the minimap rim to move it; right-click it to toggle move mode.")
    -- What's New (UI\AD_Changelog.lua): the auto-open switch writes the same UI
    -- flag as the window's own checkbox.
    Options.BuildYield()
    AT.Section(pg, "What's New")
    Options.BuildYield()
    AT.RowToggle(pg, "Show What's New after an update",
        function()
            local u = Store.UI()
            return not (u and u.changelogOff)
        end,
        function(v)
            local u = Store.UI()
            if u then u.changelogOff = (not v) or nil end
        end,
        nil, "The first time you log in after Arc Auras updates, a window opens once with what changed in the new version.")
    Options.BuildYield()
    AT.RowButton(pg, "Open", function()
        if NS.Changelog then NS.Changelog.Show() end
    end, nil, 110, "What changed in each version")
    pg:Refresh()
end

-- Modules: features for the whole addon, a card each (the QOL page folded in
-- here). The pane and its header are the host's; the cards, each module's page
-- and the back link are UI\AD_Modules.lua's.
function Options.BuildModulesPane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.modules = pane
    local h = MakeHeader(pane)
    h.name:SetText("Modules")
    if Options.Modules then Options.Modules.Fill(pane, h, win) end
end

-- The Defaults page (UI\AD_DefaultsOptions.lua): every item's defaults by
-- family and kind. It builds after the item editors, whose blocks it mirrors.
function Options.BuildDefaultsPane()
    local pane = CreateFrame("Frame", nil, content)
    pane:SetAllPoints()
    panes.defaults = pane
    local h = MakeHeader(pane)
    h.name:SetText("Defaults")
    if Options.Defaults then Options.Defaults.Fill(pane, h, win) end
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

-- "Only what loads here" (a saved panel preference, off by default)
function IE.LoadedOnly()
    return Store.UI().ieLoadedOnly == true
end

-- "Import groups empty" (a saved panel preference, off by default)
function IE.EmptyGroups()
    return Store.UI().ieEmptyGroups == true
end

-- Loads on this character, its group and layout included: the engine hides
-- what sits in something that does not load.
function IE.LoadsHere(rec)
    if not (rec and Store.IsLoaded(rec)) then return false end
    local g = rec.groupId and Store.Get(rec.groupId)
    if g and not Store.IsLoaded(g) then return false end
    local lay = Store.LayoutOf(rec)
    return not (lay and lay ~= rec and not Store.IsLoaded(lay))
end

-- the ticked ids, parents first. A group's icon ticked from its own editor
-- (Export on a group member) counts too - it has no picker row, and lands
-- as a free icon on import. A stale tick (record deleted since) drops here;
-- with "Only what loads here" a tick on something that does not load is
-- kept but left out.
function IE.SelectedIds()
    local sel, ids, live = ui.ieSel, {}, {}
    local only = IE.LoadedOnly()
    local function take(rec)
        if sel[rec.id] then
            live[rec.id] = true
            if not only or IE.LoadsHere(rec) then ids[#ids + 1] = rec.id end
        end
    end
    for _, lay in ipairs(Store.Layouts()) do
        take(lay)
        for _, c in ipairs(IE.Children(lay)) do
            take(c)
            if c.type == "group" then
                for _, ic in ipairs(Store.IconsOf(c)) do take(ic) end
                -- a reminder, from Export on its own band (no picker row either)
                for _, rr in ipairs(Store.RemindersOf(c)) do take(rr) end
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
-- player's pick this session while it exists (0 = a new layout), else a
-- layout that loads on this character, the rail's last one first; with none
-- loading here, 0 (Store.Import then makes a new layout)
function IE.TargetId()
    local pick = ui.ieTargetId
    if pick == 0 then return 0 end
    local t = Store.Get(pick)
    if t and t.type == "layout" then return t.id end
    t = Store.Get(ui.lastLayoutId)
    if t and t.type == "layout" and Store.IsLoaded(t) then return t.id end
    for _, lay in ipairs(Store.Layouts()) do
        if Store.IsLoaded(lay) then return lay.id end
    end
    return 0
end

-- What a string brings, counted by Store.Import's rule: its layouts; the
-- groups, icons and bars whose group or layout is not in it (loose, they land
-- in the target); the reminders whose group is not in it.
function IE.Brings(payload)
    local here, c = {}, { layout = 0, group = 0, icon = 0, bar = 0, reminder = 0, layNames = {} }
    for _, r in ipairs(payload.records or {}) do
        if type(r) == "table" and r.id ~= nil and c[r.type] then here[r.id] = r.type end
    end
    for _, r in ipairs(payload.records or {}) do
        if type(r) == "table" and r.id ~= nil and c[r.type] then
            if r.type == "layout" then
                c.layout = c.layout + 1
                c.layNames[#c.layNames + 1] = r.name
            elseif r.type == "reminder" then
                if r.groupId == nil or here[r.groupId] ~= "group" then c.reminder = c.reminder + 1 end
            elseif not ((r.groupId ~= nil and here[r.groupId]) or (r.layoutId ~= nil and here[r.layoutId])) then
                c[r.type] = c[r.type] + 1
            end
        end
    end
    return c
end

-- "1 group", "2 icons and 1 bar": loose groups, icons and bars in plain
-- words, and their total
function IE.KindsText(c)
    local parts, n = {}, 0
    for _, k in ipairs({ "group", "icon", "bar" }) do
        local v = c[k] or 0
        if v > 0 then
            parts[#parts + 1] = v .. " " .. k .. (v == 1 and "" or "s")
            n = n + v
        end
    end
    if n == 0 then return nil, 0 end
    local last = table.remove(parts)
    return (#parts > 0) and (table.concat(parts, ", ") .. " and " .. last) or last, n
end

-- "1 layout, 4 groups, 31 icons and 2 bars": everything a string holds
function IE.HoldsText(payload)
    local c = {}
    for _, r in ipairs(payload.records or {}) do
        if type(r) == "table" and r.type then c[r.type] = (c[r.type] or 0) + 1 end
    end
    local parts = {}
    for _, k in ipairs({ "layout", "group", "icon", "bar", "reminder" }) do
        local v = c[k] or 0
        if v > 0 then parts[#parts + 1] = v .. " " .. k .. (v == 1 and "" or "s") end
    end
    if #parts == 0 then return "nothing this version can use" end
    local last = table.remove(parts)
    return (#parts > 0) and (table.concat(parts, ", ") .. " and " .. last) or last
end

-- the Reminder groups, in layout order
function IE.ReminderGroups()
    local out = {}
    for _, lay in ipairs(Store.Layouts()) do
        for _, g in ipairs((Store.ChildrenOf(lay))) do
            if g.groupKind == "reminder" then out[#out + 1] = g end
        end
    end
    return out
end

-- where a reminder exported alone lands on import: the Reminder group picked
-- here, else the first one; 0 = a new one (picked, or none yet)
function IE.RemTargetId()
    local g = Store.Get(ui.ieRemId)
    if g and g.type == "group" and g.groupKind == "reminder" then return g.id end
    if ui.ieRemId == 0 then return 0 end
    local first = IE.ReminderGroups()[1]
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
    r.name:SetFont(AT.FONT, 12, "")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.pill = KindPill(r)
    r.pill:SetPoint("RIGHT", -8, 0)
    IE.rowPool[i] = r
    return r
end

-- one of the page's labels in front of a row ("Layouts", "Reminders")
function IE.RowLabel(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 12, "")
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- a line of the page's own text, one line, never wrapped
function IE.Line(parent, size, col)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetTextColor(col[1], col[2], col[3])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A boxed block of the page: a bordered body under a header strip that
-- carries its title, and a line at the strip's right end.
function IE.Box(parent, title)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(b, COL.box, COL.line2)
    local hd = CreateFrame("Frame", nil, b)
    hd:SetPoint("TOPLEFT", 1, -1)
    hd:SetPoint("TOPRIGHT", -1, -1)
    hd:SetHeight(IE.HEAD_H - 1)
    hd.bg = hd:CreateTexture(nil, "BACKGROUND")
    hd.bg:SetAllPoints()
    hd.bg:SetTexture(WHITE)
    hd.bg:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
    b.head = hd
    b.title = hd:CreateFontString(nil, "OVERLAY")
    b.title:SetFont(AT.FONT, 10, "")
    b.title:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    b.title:SetPoint("LEFT", 10, 0)
    b.title:SetText(title or "")
    b.right = IE.Line(hd, 11, COL.ink)
    b.right:SetPoint("RIGHT", -10, 0)
    b.right:SetJustifyH("RIGHT")
    return b
end

-- a bar along a box's foot, a hairline on its top
function IE.FootBar(box, h)
    local f = CreateFrame("Frame", nil, box)
    f:SetPoint("BOTTOMLEFT", 1, 1)
    f:SetPoint("BOTTOMRIGHT", -1, 1)
    f:SetHeight(h)
    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetTexture(WHITE)
    f.line:SetVertexColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    f.line:SetPoint("TOPLEFT", 0, 0)
    f.line:SetPoint("TOPRIGHT", 0, 0)
    f.line:SetHeight(AT.Hairline(f))
    return f
end

-- a tick box whose whole label clicks, on the page's own sound
function IE.Tick(parent, text, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    b.check = AT.MakeCheckbox(b)
    b.check:SetPoint("LEFT", 0, 0)
    b.check:EnableMouse(false)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    b.fs:SetFont(AT.FONT, 12, "")
    b.fs:SetPoint("LEFT", b.check, "RIGHT", 6, 0)
    b.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    b.fs:SetWordWrap(false)
    b.Label = function(t)
        b.fs:SetText(t)
        b:SetWidth(20 + 6 + math.ceil(b.fs:GetUnboundedStringWidth() or 120) + 4)
    end
    b.Label(text)
    b:SetScript("OnClick", function()
        local v = not get()
        set(v)
        PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        b.check:SetOn(get() == true)
    end)
    b.Sync = function() b.check:SetOn(get() == true) end
    return b
end

-- the Import button's green, and its edge
IE.GREEN = GREENC
IE.GREEN_EDGE = { GREENC[1] * 0.5, GREENC[2] * 0.5, GREENC[3] * 0.5 }

-- a page button that keeps its own edge and word colour at rest (the theme's
-- hover still lights it cyan)
function IE.EdgeButton(parent, label, w, edge, ink)
    local b = AT.MakeSmallButton(parent, label, w)
    b:SetHeight(26)
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    b.fs:SetTextColor(ink[1], ink[2], ink[3])
    b:SetScript("OnLeave", function()
        b:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end)
    return b
end

-- Export and Import are two tabs, one job each: a string made on Export
-- never sits where one is pasted, and nothing about importing is on Export.
function IE.SetTab(name)
    -- the strip hands over its tab's label ("Import"), the code its key
    ui.ieTab = (tostring(name):lower() == "import") and "import" or "export"
    if not IE.tabStrip then return end
    IE.expPane:SetShown(ui.ieTab == "export")
    IE.impPane:SetShown(ui.ieTab == "import")
    IE.tabStrip:Set({ "Export", "Import" }, (ui.ieTab == "import") and "Import" or "Export", function(n)
        AT.CloseDropdown()
        IE.SetTab(n)
        IE.LayPane()
    end)
end

local function BuildIEPane()
    iePane = CreateFrame("Frame", nil, content)
    iePane:SetAllPoints()
    panes.ie = iePane
    local h = MakeHeader(iePane)
    h.name:SetText("Import / Export")

    local strip = AT.TabRow(iePane)
    strip:SetPoint("TOPLEFT", iePane, "TOPLEFT", 0, -34)
    strip:SetPoint("TOPRIGHT", iePane, "TOPRIGHT", -4, -34)
    strip:SetHeight(26)
    IE.tabStrip = strip
    local ex = CreateFrame("Frame", nil, iePane)
    ex:SetPoint("TOPLEFT", iePane, "TOPLEFT", 0, -IE.TOP)
    ex:SetPoint("BOTTOMRIGHT", iePane, "BOTTOMRIGHT", 0, 0)
    local im = CreateFrame("Frame", nil, iePane)
    im:SetPoint("TOPLEFT", iePane, "TOPLEFT", 0, -IE.TOP)
    im:SetPoint("BOTTOMRIGHT", iePane, "BOTTOMRIGHT", 0, 0)
    IE.expPane, IE.impPane = ex, im

    -- Export: tick, make the string, copy it
    local exNote = IE.Line(ex, 12, COL.ink)
    exNote:SetPoint("TOPLEFT", 4, -2)
    exNote:SetText("Share your setup: tick what goes in, then make its string.")

    -- WHAT TO SHARE: the tree, then a bar with the ticks' tools and the act
    Options.BuildYield()
    local share = IE.Box(ex, "WHAT TO SHARE")
    IE.shareBox = share
    IE.expStatus = share.right
    local pickHost = CreateFrame("Frame", nil, share, "BackdropTemplate")
    pickHost:SetPoint("TOPLEFT", 1, -IE.HEAD_H)
    pickHost:SetPoint("TOPRIGHT", -1, -IE.HEAD_H)
    pickHost:SetHeight(IE.LIST_H)
    AT.Skin(pickHost, COL.well)
    IE.pickHost = pickHost
    IE.listScroll, ieListHost = AT.MakeScroll(pickHost)
    IE.listScroll:SetPoint("TOPLEFT", 3, -3)
    IE.listScroll:SetPoint("BOTTOMRIGHT", -9, 3)
    IE.listScroll:HookScript("OnSizeChanged", function(s, w)
        ieListHost:SetWidth(math.max(50, (w or 300) - AT.ScrollExtra()))
        s:UpdateScroll()
    end)
    local bar = IE.FootBar(share, IE.FOOT_H)
    local allBtn = AT.MakeSmallButton(bar, "Tick all", 70)
    allBtn:SetPoint("LEFT", 10, 0)
    allBtn:SetScript("OnClick", function()
        -- with "Only what loads here" on, what stays out stays unticked
        local only = IE.LoadedOnly()
        for _, lay in ipairs(Store.Layouts()) do
            if not only or IE.LoadsHere(lay) then ui.ieSel[lay.id] = true end
            for _, c in ipairs(IE.Children(lay)) do
                if not only or IE.LoadsHere(c) then ui.ieSel[c.id] = true end
            end
        end
        IE.Refresh()
    end)
    local noneBtn = AT.MakeSmallButton(bar, "Untick all", 80)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)
    noneBtn:SetScript("OnClick", function()
        ui.ieSel = {}
        IE.Refresh()
    end)
    local lo = IE.Tick(bar, "Only what loads on this character", IE.LoadedOnly, function(v)
        Store.UI().ieLoadedOnly = v or nil
        IE.Refresh()
    end)
    lo:SetPoint("LEFT", noneBtn, "RIGHT", 14, 0)
    AT.Tooltip(lo, "Only what loads here", "Leaves out everything that does not load on this character, so the string holds only what you use here. What stays out is still listed, greyed, under each layout's NOT LOADED.")
    IE.loadedOnly = lo
    local expBtn = IE.EdgeButton(bar, "Export selected", 130, COL.leadEdge, COL.ink)
    expBtn:SetPoint("RIGHT", -10, 0)
    expBtn:SetScript("OnClick", function() Options.ExportSelected() end)
    AT.Tooltip(expBtn, "Export selected", "Makes one share string from everything ticked above.")
    IE.expBtn = expBtn

    -- PACK INFO: a box whose header is its fold (IE.BuildPackInfo)
    Options.BuildYield()
    IE.packBox = IE.Box(ex, "")
    IE.BuildPackInfo()

    -- YOUR STRING: named after what it holds, the box to copy from, its foot
    Options.BuildYield()
    local str = IE.Box(ex, "YOUR STRING")
    IE.strBox = str
    IE.expName = IE.Line(str, 15, COL.ink)
    IE.expName:SetPoint("TOPLEFT", str, "TOPLEFT", 10, -(IE.HEAD_H + 9))
    IE.expMeta = IE.Line(str, 12, COL.dim)
    IE.expMeta:SetPoint("BOTTOMLEFT", IE.expName, "BOTTOMRIGHT", 10, 1)
    IE.expMeta:SetPoint("RIGHT", str, "RIGHT", -10, 0)
    local expHost = CreateFrame("Frame", nil, str, "BackdropTemplate")
    expHost:SetPoint("TOPLEFT", str, "TOPLEFT", 10, -(IE.HEAD_H + 34))
    expHost:SetPoint("BOTTOMRIGHT", str, "BOTTOMRIGHT", -10, 28)
    AT.Skin(expHost, COL.well, COL.line2)
    IE.expHost = expHost
    local eb = CreateFrame("EditBox", nil, expHost)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(0.85, 0.9, 0.95, 1)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    IE.expScroll = AT.MakeScroll(expHost, eb)
    IE.expScroll:SetPoint("TOPLEFT", 8, -6)
    IE.expScroll:SetPoint("BOTTOMRIGHT", -10, 6)
    IE.expScroll:HookScript("OnSizeChanged", function(s, w)
        eb:SetWidth(math.max(60, (w or s:GetWidth() or 300) - 6))
        s:UpdateScroll()
    end)
    -- read only: typing puts the string back, selected, ready to copy
    eb:SetScript("OnTextChanged", function(s, user)
        if user then
            s:SetText(IE.expText or "")
            s:HighlightText()
        end
        IE.expScroll:UpdateScroll()
    end)
    eb:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
    expHost:EnableMouse(true)
    expHost:SetScript("OnMouseUp", function() eb:SetFocus() end)
    IE.expBox = eb
    -- with no string yet, one quiet line where it will show
    IE.expEmpty = str:CreateFontString(nil, "OVERLAY")
    IE.expEmpty:SetFont(AT.FONT, 13, "")
    IE.expEmpty:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    IE.expEmpty:SetPoint("CENTER", str, "CENTER", 0, -IE.HEAD_H / 2)
    IE.expEmpty:SetText("Tick what to share above, then press Export selected. The string shows here.")
    IE.expFoot = IE.Line(str, 12, COL.dim)
    IE.expFoot:SetPoint("BOTTOMLEFT", str, "BOTTOMLEFT", 10, 8)
    IE.expFoot:SetPoint("BOTTOMRIGHT", str, "BOTTOMRIGHT", -10, 8)

    -- Import: paste, see what it holds and where it goes, bring it in
    local imNote = IE.Line(im, 12, COL.ink)
    imNote:SetPoint("TOPLEFT", 4, -2)
    imNote:SetText("Bring in a string someone shared: paste it, check what it holds and where it goes, then import.")

    -- PASTE A STRING: the box, then a row with Clear at its end
    Options.BuildYield()
    local paste = IE.Box(im, "PASTE A STRING")
    IE.pasteBox = paste
    local boxHost = CreateFrame("Frame", nil, paste, "BackdropTemplate")
    boxHost:SetPoint("TOPLEFT", paste, "TOPLEFT", 10, -(IE.HEAD_H + 8))
    boxHost:SetPoint("TOPRIGHT", paste, "TOPRIGHT", -10, -(IE.HEAD_H + 8))
    boxHost:SetHeight(IE.PASTE_H)
    AT.Skin(boxHost, COL.well, COL.steel)
    ieBox = CreateFrame("EditBox", nil, boxHost)
    ieBox:SetMultiLine(true)
    ieBox:SetAutoFocus(false)
    ieBox:SetFontObject(ChatFontNormal)
    ieBox:SetTextColor(0.85, 0.9, 0.95, 1)
    ieBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    ieScroll = AT.MakeScroll(boxHost, ieBox)
    ieScroll:SetPoint("TOPLEFT", 8, -6)
    ieScroll:SetPoint("BOTTOMRIGHT", -10, 6)
    ieScroll:HookScript("OnSizeChanged", function(s, w)
        ieBox:SetWidth(math.max(60, (w or s:GetWidth() or 300) - 6))
        s:UpdateScroll()
    end)
    ieBox:SetScript("OnTextChanged", function()
        ieScroll:UpdateScroll()
        IE.boxHint:SetShown((ieBox:GetText() or "") == "")
        IE.QueuePeek()
    end)
    -- clicking the empty well focuses the box (the editbox only spans its text)
    boxHost:EnableMouse(true)
    boxHost:SetScript("OnMouseUp", function() ieBox:SetFocus() end)
    IE.boxHost, IE.box = boxHost, ieBox
    IE.boxHint = boxHost:CreateFontString(nil, "OVERLAY")
    IE.boxHint:SetFont(AT.FONT, 13, "")
    IE.boxHint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    IE.boxHint:SetPoint("TOPLEFT", 9, -8)
    IE.boxHint:SetText("Paste a string here (Ctrl+V).")
    local clrBtn = AT.MakeSmallButton(paste, "Clear", 64)
    clrBtn:SetPoint("BOTTOMRIGHT", paste, "BOTTOMRIGHT", -10, 7)
    clrBtn:SetScript("OnClick", function()
        ieBox:SetText("")
        IE.SetStatus("", true)
        IE.gameAck = nil
        IE.ShowUndo(nil)
        if IE.upd then IE.upd:Hide() end
    end)
    IE.clrBtn = clrBtn

    -- WHAT'S IN IT: one height whether or not anything is pasted
    Options.BuildYield()
    local what = IE.Box(im, "WHAT'S IN IT")
    IE.whatBox = what
    IE.peek = IE.PeekLines(what)
    IE.peekEmpty = what:CreateFontString(nil, "OVERLAY")
    IE.peekEmpty:SetFont(AT.FONT, 13, "")
    IE.peekEmpty:SetPoint("TOP", what, "TOP", 0, -(IE.HEAD_H + 38))

    -- WHERE IT GOES: a row per kind with its choice beside it; a string you
    -- have already shows what to take from it; Import on the foot bar
    Options.BuildYield()
    local where = IE.Box(im, "WHERE IT GOES")
    IE.whereBox = where
    IE.whereRows = {}
    for i, lbl in ipairs({ "Layouts", "Groups, icons, bars", "Reminders", "Empty groups" }) do
        local r = CreateFrame("Frame", nil, where)
        r:SetHeight(IE.WHERE_H)
        r:SetPoint("TOPLEFT", where, "TOPLEFT", 1, -(IE.HEAD_H + 6 + (i - 1) * IE.WHERE_H))
        r:SetPoint("TOPRIGHT", where, "TOPRIGHT", -1, -(IE.HEAD_H + 6 + (i - 1) * IE.WHERE_H))
        r.lbl = IE.RowLabel(r, lbl)
        r.lbl:SetPoint("LEFT", 9, 0)
        r.val = IE.Line(r, 12, COL.ink)
        r.val:SetPoint("LEFT", IE.WHERE_X, 0)
        IE.whereRows[i] = r
    end
    IE.whereLay, IE.whereItems, IE.whereRem = IE.whereRows[1].val, IE.whereRows[2].val, IE.whereRows[3].val
    IE.whereEmpty = where:CreateFontString(nil, "OVERLAY")
    IE.whereEmpty:SetFont(AT.FONT, 13, "")
    IE.whereEmpty:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    IE.whereEmpty:SetPoint("TOP", where, "TOP", 0, -(IE.HEAD_H + 40))
    IE.whereEmpty:SetText("Paste a string to see where each part goes.")

    IE.target = AT.MakeDropdown(win, IE.whereRows[2], 170, function()
        local items = {}
        for _, lay in ipairs(Store.Layouts()) do
            items[#items + 1] = { value = lay.id, text = lay.name }
        end
        -- with no layout picked, items go where the import itself puts them:
        -- the string's own layout when it has one, else a new one
        local c = IE.peekData and IE.peekData.brings
        local nl = c and c.layout or 0
        items[#items + 1] = { value = 0, text = (nl == 1) and "(the layout in the string)"
            or (nl > 1) and "(the first layout in the string)" or "(a new layout)" }
        return items
    end, IE.TargetId, function(v) ui.ieTargetId = v end, function() IE.LayPane() end)
    IE.target:SetPoint("LEFT", IE.whereItems, "RIGHT", 8, 0)
    AT.Tooltip(IE.target, "Groups, icons and bars go into", "Where a group, icon or bar shared without its layout lands. It starts on a layout that loads on this character.")
    IE.remTarget = AT.MakeDropdown(win, IE.whereRows[3], 190, function()
        local items = {}
        for _, g in ipairs(IE.ReminderGroups()) do items[#items + 1] = { value = g.id, text = g.name } end
        items[#items + 1] = { value = 0, text = "(a new Reminder group)" }
        return items
    end, IE.RemTargetId, function(v) ui.ieRemId = v end, function() IE.LayPane() end)
    IE.remTarget:SetPoint("LEFT", IE.whereRem, "RIGHT", 8, 0)
    AT.Tooltip(IE.remTarget, "Reminders join", "A reminder exported on its own joins this Reminder group. A group keeps one reminder per spell, item or weapon hand, so one it already has stays out.")
Options.BuildYield()
    local eg = IE.Tick(IE.whereRows[4], "Bring groups in without their icons", IE.EmptyGroups, function(v)
        Store.UI().ieEmptyGroups = v or nil
    end)
    eg:SetPoint("LEFT", IE.WHERE_X, 0)
    AT.Tooltip(eg, "Empty groups", "Each group in the string comes in without its icons: you get its place and look, and fill it yourself. Bars, and icons outside a group, still come in.")
    IE.emptyGroups = eg
Options.BuildYield()
    IE.BuildUpdInline(where)

    Options.BuildYield()
    local foot = IE.FootBar(where, IE.IMP_FOOT_H)
    IE.impFoot = foot
    local impBtn = IE.EdgeButton(foot, "Import", 100, IE.GREEN_EDGE, IE.GREEN)
    impBtn:SetPoint("LEFT", 10, 0)
    -- a string whose items are here already (an earlier version of it) asks
    -- first: update them, or import a copy; anything else imports at once.
    -- One made for the other game warns on the first press (the update
    -- panel says it instead).
    impBtn:SetScript("OnClick", function()
        IE.ShowUndo(nil)
        local text = ieBox and ieBox:GetText() or ""
        if text == "" then
            IE.SetStatus("Paste a string first.", false)
            return
        end
        local plan, err = Store.PlanUpdate(text)
        if not plan then
            IE.SetStatus(err or "Import failed.", false)
            return
        end
        if plan.relation == "new" and plan.otherGame and IE.gameAck ~= text then
            IE.gameAck = text
            IE.SetStatus(IE.GameNote(plan) .. " Press Import again to bring it in.", false)
            return
        end
        IE.gameAck = nil
        if plan.relation == "new" then
            IE.DoImport(text, false, plan)
        else
            IE.ShowUpdate(plan, text)
        end
    end)
    IE.impBtn = impBtn
    -- a string you have an earlier copy of: its two ways in Import's place,
    -- and the item by item panel
    local updBtn = IE.EdgeButton(foot, "Update my copy", 130, IE.GREEN_EDGE, IE.GREEN)
    updBtn:SetPoint("LEFT", 10, 0)
    updBtn:SetScript("OnClick", function()
        IE.updMode = "update"
        IE.RunUpdate()
    end)
    local cpyBtn = IE.EdgeButton(foot, "Import as a new copy", 160, COL.steel, COL.ink)
    cpyBtn:SetPoint("LEFT", updBtn, "RIGHT", 8, 0)
    cpyBtn:SetScript("OnClick", function()
        IE.updMode = "copy"
        IE.RunUpdate()
    end)
    AT.Tooltip(cpyBtn, "Import as a new copy", "Leaves the items you have alone and brings a second copy in.")
    local eachBtn = AT.MakeQuietButton(foot, "Each change", 100)
    eachBtn:SetHeight(26)
    eachBtn:SetPoint("LEFT", cpyBtn, "RIGHT", 8, 0)
    eachBtn:SetScript("OnClick", function()
        if IE.plan then IE.ShowUpdate(IE.plan, IE.planText) end
    end)
    AT.Tooltip(eachBtn, "Each change", "Lists every item the update changes, adds or drops, with a Keep mine tick on each changed one.")
    IE.updBtn, IE.cpyBtn, IE.eachBtn = updBtn, cpyBtn, eachBtn

    -- right after an update, its undo at the end of the bar, quiet
    IE.undoBtn = AT.MakeQuietButton(foot, "Undo the update", 112)
    IE.undoBtn:SetPoint("RIGHT", -10, 0)
    IE.undoBtn:SetScript("OnClick", function() IE.RunUndo() end)
    AT.Tooltip(IE.undoBtn, "Undo the update",
        "Puts back what the update changed, added or removed. The layout's page offers it too, until its next update.")
    IE.undoBtn:Hide()

    ieStatus = foot:CreateFontString(nil, "OVERLAY")
    ieStatus:SetFont(AT.FONT, 12, "")
    ieStatus:SetPoint("LEFT", impBtn, "RIGHT", 10, 0)
    ieStatus:SetPoint("RIGHT", foot, "RIGHT", -10, 0)
    ieStatus:SetJustifyH("LEFT")
    -- two lines at most: an import report that also counts what does not
    -- load here must never lose its second half off the edge
    ieStatus:SetWordWrap(true)
    if ieStatus.SetMaxLines then ieStatus:SetMaxLines(2) end
    ieStatus:SetText("")
    IE.SetTab(ui.ieTab)
    IE.LayPane()
    -- the pane's height shares out its boxes, its width wraps the lines
    iePane:HookScript("OnSizeChanged", function() IE.LayPane() end)
end

-- WHAT'S IN IT's lines: the pack's name and version with its link to copy on
-- the same line, its notes, what the string holds, the media it needs. One
-- line each; a long one shows whole in the box's tooltip.
function IE.PeekLines(box)
    local blk = CreateFrame("Frame", nil, box)
    blk:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -(IE.HEAD_H + 8))
    blk:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 6)
    blk.head = IE.Line(blk, 15, COL.ink)
    blk.head:SetPoint("TOPLEFT", 0, 0)
    local link = CreateFrame("EditBox", nil, blk, "BackdropTemplate")
    link:SetHeight(18)
    AT.Skin(link, COL.well)
    link:SetFont(AT.FONT, 12, "")
    link:SetTextInsets(6, 6, 0, 0)
    link:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    link:SetAutoFocus(false)
    -- read only: the text is there to copy
    link:SetScript("OnTextChanged", function(s, user)
        if user then
            s:SetText(s._v or "")
            s:HighlightText()
        end
    end)
    link:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
    link:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    link:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    AT.Tooltip(link, "Link", "Click it and press Ctrl+C to copy it, then paste it into your browser.")
    blk.link = link
    blk.notes = IE.Line(blk, 12, COL.dim)
    blk.holds = IE.Line(blk, 12, COL.ink)
    blk.media = IE.Line(blk, 12, COL.ink)
    for i, fs in ipairs({ blk.notes, blk.holds, blk.media }) do
        fs:SetPoint("TOPLEFT", 0, -(22 + (i - 1) * 18))
        fs:SetPoint("RIGHT", blk, "RIGHT", 0, 0)
    end
    blk:EnableMouse(true)
    AT.Tooltip(blk, function() return blk._tipTitle end, function() return blk._tip end)
    blk:Hide()
    return blk
end

-- The update, in WHERE IT GOES (a string you have an earlier copy of): what
-- you have and what it is, the parts to take as chips, the items, and on the
-- foot bar Update my copy / Import as a new copy. "Each change" opens the
-- item by item panel (its Keep mine ticks).
function IE.BuildUpdInline(where)
    local u = CreateFrame("Frame", nil, where)
    u:SetPoint("TOPLEFT", where, "TOPLEFT", 10, -(IE.HEAD_H + 10))
    u:SetPoint("BOTTOMRIGHT", where, "BOTTOMRIGHT", -10, IE.IMP_FOOT_H + 4)
    u.line = u:CreateFontString(nil, "OVERLAY")
    u.line:SetFont(AT.FONT, 12, "")
    u.line:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    u.line:SetJustifyH("LEFT")
    u.line:SetWordWrap(true)
    u.line:SetPoint("TOPLEFT", 0, 0)
    u.line:SetPoint("RIGHT", u, "RIGHT", 0, 0)
    u.chips = {}
    for _, p in ipairs(Store.UPDATE_PARTS) do
Options.BuildYield()
        local c = CreateFrame("Button", nil, u, "BackdropTemplate")
        c:SetHeight(22)
        AT.Skin(c, COL.well, COL.line)
        c.fs = c:CreateFontString(nil, "OVERLAY")
        c.fs:SetFont(AT.FONT, 11, "")
        c.fs:SetPoint("CENTER", 0, 0)
        c.part = p
        c:SetScript("OnClick", function()
            local s = Store.UI()
            if type(s.ieParts) ~= "table" then s.ieParts = {} end
            local v = not IE.UpdateParts()[p]
            s.ieParts[p] = v
            PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            IE.PaintWhere()
        end)
        if p == "position" then
            AT.Tooltip(c, "Size & Position", "Where each item sits (its group, or free and where), its anchor, sizes, strata and mouse. Off keeps your own placement.")
        end
        u.chips[#u.chips + 1] = c
    end
    u.add = IE.Tick(u, "Add new items", function() return IE.UpdFlag("ieAdd") end,
        function(v) Store.UI().ieAdd = v and nil or false end)
    AT.Tooltip(u.add, "Add new items", "Items in the string that you do not have yet come in, where it puts them.")
    u.remove = IE.Tick(u, "Remove items the pack dropped", function() return IE.UpdFlag("ieRemove") end,
        function(v) Store.UI().ieRemove = v and nil or false end)
    AT.Tooltip(u.remove, "Remove items the pack dropped", "Items that came from this pack but are no longer in the string go. Anything you added yourself always stays.")
    u.revive = IE.Tick(u, "Bring back the items you deleted", function() return IE.revive == true end,
        function(v) IE.revive = v or nil end)
    AT.Tooltip(u.revive, "Items you deleted", "The pack items you deleted come back with this update. Unticked, they stay deleted.")
    u:Hide()
    IE.updInline = u
end

-- The plain import, or (asCopy) a copy linked to no pack: every item gets a
-- fresh ID, so a later update of the string reaches the first copy only.
function IE.DoImport(text, asCopy, plan)
    do
        local tid = IE.TargetId()
        local res, err = Store.Import(text, tid,
            { emptyGroups = IE.EmptyGroups(), reminderGroupId = IE.RemTargetId(), asCopy = asCopy or nil })
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
            local c = {}
            for _, it in ipairs(res.items) do c[it.type] = (c[it.type] or 0) + 1 end
            -- a layout the import had to make says so
            local made = tid == 0
            for _, l in ipairs(res.layouts) do
                if l == res.target then made = false end
            end
            parts[#parts + 1] = (IE.KindsText(c) or (ni .. (ni == 1 and " item" or " items")))
                .. " into " .. (made and "a new layout " or "") .. "\"" .. tostring(res.target.name) .. "\""
        end
        -- reminders exported alone: the group they joined becomes the pick
        local nr = #(res.reminders or {})
        if nr > 0 and res.reminderGroup then
            ui.ieRemId = res.reminderGroup.id
            parts[#parts + 1] = nr .. (nr == 1 and " reminder" or " reminders")
                .. " into \"" .. tostring(res.reminderGroup.name) .. "\""
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
        for _, it in ipairs(res.reminders or {}) do Tally(it, false) end
        local msg = "Imported " .. table.concat(parts, " and ") .. "."
        if #(res.refused or {}) > 0 then
            msg = msg .. " Left out, the group has one already: " .. table.concat(res.refused, ", ") .. "."
        end
        local dropped = res.dropped or 0
        if dropped > 0 then
            msg = msg .. " Groups came in empty: " .. dropped
                .. (dropped == 1 and " icon" or " icons") .. " left out."
        end
        if off > 0 then
            msg = msg .. " " .. off .. " of them "
                .. (off == 1 and "does" or "do")
                .. " not load here: the eye in the sidebar shows them."
        end
        if plan and plan.newer then msg = msg .. " " .. IE.NewerNote(plan) end
        IE.SetStatus(msg, true)
        -- the string is here now: read it again, so the line stops saying
        -- where it would land
        IE.peekText = nil
        IE.ShowPeek()
        if nl > 0 then
            SelectRecord(res.layouts[1])
        elseif res.items[1] then
            SelectRecord(res.items[1])
        elseif res.reminders and res.reminders[1] then
            SelectRecord(res.reminders[1])
        end
    end
end

function IE.NewerNote(plan)
    return "Made with Arc Auras " .. tostring(plan.newer)
        .. ", newer than yours: update Arc Auras to get every setting in it."
end

function IE.GameNote(plan)
    return "Made for " .. Store.GameName(plan.otherGame) .. ": some spells and items may not work here."
end

-- The update panel: over the pane while the player decides. Parts start as
-- they were last left (Size & Position off the first time).
function IE.UpdateParts()
    local u = Store.UI()
    if type(u.ieParts) ~= "table" then u.ieParts = {} end
    local out = {}
    for _, p in ipairs(Store.UPDATE_PARTS) do
        local v = u.ieParts[p]
        if v == nil then v = not Store.UPDATE_PART_OFF[p] end
        out[p] = v
    end
    return out
end

function IE.UpdFlag(key)
    return Store.UI()[key] ~= false
end

-- a tick box with its whole label clickable (the pane's own pattern)
function IE.CheckRow(parent, get, set, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    b.check = AT.MakeCheckbox(b)
    b.check:SetPoint("LEFT", 0, 0)
    b.check:EnableMouse(false)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    b.fs:SetFont(AT.FONT, 11, "")
    b.fs:SetPoint("LEFT", b.check, "RIGHT", 6, 0)
    b.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    b.fs:SetJustifyH("LEFT")
    b.fs:SetWordWrap(false)
    b:SetScript("OnClick", function()
        local v = not get()
        set(v)
        PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        IE.PaintUpdate()
    end)
    b.Sync = function() b.check:SetOn(get() == true) end
    if tip then AT.Tooltip(b, tip[1], tip[2]) end
    return b
end

-- one of the pane's small capital labels, faint
function IE.Caps(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 9, "")
    fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- text from a string shows as itself: no colour, picture or link codes
function IE.Safe(s)
    return (tostring(s or ""):gsub("|", "||"))
end

function IE.Dim(s)
    return ("|cff%02x%02x%02x"):format(math.floor(COL.dim[1] * 255 + 0.5), math.floor(COL.dim[2] * 255 + 0.5),
        math.floor(COL.dim[3] * 255 + 0.5)) .. s .. "|r"
end

-- "Missing here: A, B, C, D and 2 more; they use the default until you add them."
function IE.MediaNote(missing)
    local names = {}
    for i = 1, math.min(#missing, 4) do names[i] = IE.Safe(missing[i]) end
    local more = #missing - #names
    return "Missing here: " .. table.concat(names, ", ") .. ((more > 0) and (" and " .. more .. " more") or "")
        .. "; they use the default until you add them."
end

-- A string's pack info and missing media as lines (IE.FillInfo lays them):
-- the name and version, the notes (three lines at most), the link in a box to
-- copy (never one that opens), then the media this client lacks.
function IE.InfoBlock(parent)
    local blk = CreateFrame("Frame", nil, parent)
    blk:SetSize(10, 1)
    local function Text(size, col, lines)
        local fs = blk:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, size, "")
        fs:SetTextColor(col[1], col[2], col[3])
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(lines > 1)
        if fs.SetMaxLines then fs:SetMaxLines(lines) end
        return fs
    end
    blk.head = Text(12, COL.ink, 1)
    blk.notes = Text(11, COL.dim, 3)
    blk.media = Text(11, COL.ink, 2)
    blk.notes._lines, blk.media._lines = 3, 2
    blk.linkLbl = IE.Caps(blk, "LINK")
    local box = CreateFrame("EditBox", nil, blk, "BackdropTemplate")
    box:SetHeight(20)
    AT.Skin(box, COL.well)
    box:SetFont(AT.FONT, 11, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetAutoFocus(false)
    -- read only: the text is there to copy
    box:SetScript("OnTextChanged", function(s, user)
        if user then
            s:SetText(s._v or "")
            s:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    AT.Tooltip(box, "Link", "Click it and press Ctrl+C to copy it, then paste it into your browser.")
    blk.link = box
    blk:Hide()
    return blk
end

-- Fills an info block and lays its lines top down at width w: the height it
-- takes, 0 when there is nothing to say (it hides then). compact: the notes
-- and the media take one line each.
function IE.FillInfo(blk, info, missing, w, compact)
    w = math.max(120, math.floor(w or 0))
    blk:SetWidth(w)
    local y = 0
    local function Line(fs, text)
        fs:SetShown(text ~= nil)
        if text == nil then return end
        if fs._lines and fs.SetMaxLines then fs:SetMaxLines(compact and 1 or fs._lines) end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, -y)
        fs:SetWidth(w)
        fs:SetText(text)
        y = y + math.ceil(fs:GetStringHeight() or 12) + 4
    end
    local head
    if info and (info.name or info.version) then
        local ver = info.version and ("version " .. IE.Safe(info.version)) or nil
        if info.name then
            head = IE.Safe(info.name) .. (ver and ("   " .. IE.Dim(ver)) or "")
        else
            head = "Version " .. IE.Safe(info.version)
        end
    end
    Line(blk.head, head)
    Line(blk.notes, (info and info.notes) and IE.Safe(info.notes) or nil)
    local link = info and info.link
    blk.linkLbl:SetShown(link ~= nil)
    blk.link:SetShown(link ~= nil)
    if link then
        local lw = math.ceil(blk.linkLbl:GetUnboundedStringWidth() or 24) + 8
        blk.linkLbl:ClearAllPoints()
        blk.linkLbl:SetPoint("LEFT", blk, "TOPLEFT", 0, -(y + 10))
        blk.link:ClearAllPoints()
        blk.link:SetPoint("TOPLEFT", blk, "TOPLEFT", lw, -y)
        blk.link:SetWidth(math.max(60, w - lw))
        blk.link._v = IE.Safe(link)
        blk.link:SetText(blk.link._v)
        blk.link:SetCursorPosition(0)
        y = y + 20 + 4
    end
    Line(blk.media, (missing and #missing > 0) and IE.MediaNote(missing) or nil)
    blk:SetHeight(math.max(1, y))
    blk:SetShown(y > 0)
    return y
end

-- The maker's pack info under the export row: a plain fold, shut until
-- clicked, with a name, a version, a link and notes. They save as they are
-- typed, on the layout the ticks point at (Store.PackInfoLayout), and every
-- string made from it carries them.
IE.PACK_FIELDS = {
    { key = "name", label = "NAME", title = "Name", w = 180,
      tip = "The pack's name. Whoever imports the string sees it first." },
    { key = "version", label = "VERSION", title = "Version", w = 70,
      tip = "Your version of the pack, for example 1.2. An update and its undo name it." },
    { key = "link", label = "LINK", title = "Link",
      tip = "Where to find the pack or you, a page or a Discord. It shows as text to copy." },
    { key = "notes", label = "NOTES", title = "Notes",
      tip = "What the pack is for, or what changed in this version." },
}

function IE.BuildPackInfo()
    local box = IE.packBox
    local fold = CreateFrame("Button", nil, box.head)
    fold:SetAllPoints(box.head)
    fold.chev = AT.MakeChevron(fold)
    fold.chev:SetPoint("LEFT", 10, 0)
    fold.lbl = fold:CreateFontString(nil, "OVERLAY")
    fold.lbl:SetFont(AT.FONT, 10, "")
    fold.lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    fold.lbl:SetPoint("LEFT", fold.chev, "RIGHT", 8, 0)
    fold.lbl:SetText("PACK INFO")
    fold.note = IE.Line(fold, 12, COL.faint)
    fold.note:SetPoint("LEFT", fold.lbl, "RIGHT", 10, 0)
    fold.note:SetPoint("RIGHT", fold, "RIGHT", -10, 0)
    fold:SetScript("OnClick", function()
        local u = Store.UI()
        u.iePackOpen = (u.iePackOpen ~= true) or nil
        PlaySound(u.iePackOpen and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        IE.LayPane()
    end)
    -- the header lifts under the mouse, as a fold does
    fold:SetScript("OnEnter", function()
        box.head.bg:SetVertexColor(COL.btnHover[1], COL.btnHover[2], COL.btnHover[3], 1)
    end)
    fold:SetScript("OnLeave", function()
        box.head.bg:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
    end)
    AT.Tooltip(fold, "Pack info", "A name, version, link and notes for your pack. Whoever imports the string sees them first.")
    IE.packFold = fold
    IE.packFields = {}
    for _, d in ipairs(IE.PACK_FIELDS) do
        local lbl = box:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 10, "")
        lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        lbl:SetJustifyH("LEFT")
        lbl:SetText(d.label)
        local b = CreateFrame("EditBox", nil, box, "BackdropTemplate")
        b:SetHeight(20)
        AT.Skin(b, COL.well, COL.line2)
        b:SetFont(AT.FONT, 12, "")
        b:SetTextInsets(6, 6, 0, 0)
        b:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        b:SetAutoFocus(false)
        b:SetMaxLetters(Store.PACK_INFO_CAPS[d.key] or 60)
        b:SetScript("OnTextChanged", function(s, user)
            if not user then return end
            local lay = IE.PackLayout()
            if lay then
                Store.SetPackInfo(lay.id, d.key, s:GetText() or "")
                IE.SyncPackNote()
            end
        end)
        b:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        b:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        b:SetScript("OnEditFocusGained", function(s)
            s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
        end)
        b:SetScript("OnEditFocusLost", function(s)
            s:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
            IE.SyncPackInfo()
        end)
        AT.Tooltip(b, d.title, d.tip)
        IE.packFields[#IE.packFields + 1] = { key = d.key, lbl = lbl, box = b, w = d.w }
    end
end

-- the layout whose pack info the fields edit: the ticked one, else the
-- layout of the first ticked item
function IE.PackLayout()
    return Store.PackInfoLayout(IE.SelectedIds())
end

function IE.SyncPackNote()
    local fold = IE.packFold
    if not fold then return end
    local lay = IE.PackLayout()
    local info = lay and Store.PackInfo(lay.id)
    local t
    if not lay then
        t = "tick a layout to give its pack a name"
    elseif info and info.name then
        t = IE.Safe(info.name) .. (info.version and (" " .. IE.Safe(info.version)) or "")
            .. ", saved with \"" .. IE.Safe(lay.name) .. "\""
    else
        t = "optional: a name, version, link and notes whoever imports it sees first"
    end
    fold.note:SetText(t)
end

function IE.SyncPackInfo()
    if not IE.packFields then return end
    local lay = IE.PackLayout()
    local info = lay and Store.PackInfo(lay.id) or nil
    for _, f in ipairs(IE.packFields) do
        if not f.box:HasFocus() then AT.BoxText(f.box, info and info[f.key] or "") end
        f.box:EnableMouse(lay ~= nil)
        f.box:SetAlpha(lay and 1 or 0.45)
        f.lbl:SetAlpha(lay and 1 or 0.45)
    end
    IE.SyncPackNote()
end

-- The panes' height in use: their own once laid out, else the window's less
-- its frame (the first pass, before the client has laid the panes out).
function IE.PaneH()
    local h = IE.expPane and IE.expPane:GetHeight() or 0
    if h < 100 then h = (iePane and iePane:GetHeight() or 0) - IE.TOP end
    if h < 100 then h = ((win and win:GetHeight()) or 580) - 68 - IE.TOP end
    return h
end

function IE.PaneW()
    local w = iePane and iePane:GetWidth() or 0
    if w < 100 then w = ((win and win:GetWidth()) or 1020) - 240 end
    return w
end

-- a box placed from y down, h tall (nil: to the pane's foot)
function IE.PlaceBox(b, pane, y, h)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
    if h then
        b:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -4, y)
        b:SetHeight(h)
    else
        b:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 6)
    end
end

-- Export, top down as the board draws it: the note, WHAT TO SHARE (header,
-- the tree up to 252 px, the bar), PACK INFO (its header, the fields while
-- open), YOUR STRING to the foot. The tree gives way first on a short window.
function IE.LayExport()
    if not (IE.packFold and IE.strBox) then return end
    local ex, w, paneH = IE.expPane, IE.PaneW(), IE.PaneH()
    local open = Store.UI().iePackOpen == true
    local packH = IE.HEAD_H + (open and IE.PACK_OPEN_H or 0)
    local listH = math.max(110, math.min(IE.LIST_H,
        paneH - (IE.NOTE_H + IE.HEAD_H + IE.FOOT_H + IE.GAP + packH + IE.GAP + IE.STR_MIN + 6)))
    IE.pickHost:SetHeight(listH)
    local y = -IE.NOTE_H
    local shareH = IE.HEAD_H + listH + IE.FOOT_H
    IE.PlaceBox(IE.shareBox, ex, y, shareH)
    y = y - shareH - IE.GAP
    IE.PlaceBox(IE.packBox, ex, y, packH)
    y = y - packH - IE.GAP
    IE.PlaceBox(IE.strBox, ex, y, nil)
    IE.packFold.chev:SetDown(open)
    -- the fields, name, version and link on one line and notes on the next, each
    -- label over its box
    local box = IE.packBox
    local inner = (w - 4) - 20
    local by = {}
    for _, f in ipairs(IE.packFields) do
        f.lbl:SetShown(open)
        f.box:SetShown(open)
        by[f.key] = f
    end
    if open then
        local function Put(f, x, yy, width)
            f.lbl:ClearAllPoints()
            f.lbl:SetPoint("TOPLEFT", box, "TOPLEFT", x, yy)
            f.box:ClearAllPoints()
            f.box:SetPoint("TOPLEFT", box, "TOPLEFT", x, yy - 14)
            f.box:SetWidth(math.max(40, width))
        end
        local y1 = -(IE.HEAD_H + 8)
        Put(by.name, 10, y1, by.name.w)
        Put(by.version, 10 + by.name.w + 10, y1, by.version.w)
        local lx = 10 + by.name.w + 10 + by.version.w + 10
        Put(by.link, lx, y1, inner - (lx - 10))
        Put(by.notes, 10, y1 - 42, inner)
    end
    IE.SyncPackInfo()
end

-- Import, top down as the board draws it: the note, PASTE A STRING (header,
-- the box up to 96 px, the row with Clear), WHAT'S IN IT (one height, pasted
-- or not), WHERE IT GOES to the foot, its bar at the bottom.
function IE.LayImport()
    if not IE.whereRows then return end
    local im, paneH = IE.impPane, IE.PaneH()
    local whatH = (paneH < 480) and IE.WHAT_H_SHORT or IE.WHAT_H
    local pasteH = math.max(50, math.min(IE.PASTE_H,
        paneH - (IE.NOTE_H + IE.HEAD_H + 8 + IE.PASTE_ROW_H + IE.GAP + IE.HEAD_H + whatH + IE.GAP + IE.WHERE_MIN + 6)))
    IE.boxHost:SetHeight(pasteH)
    local y = -IE.NOTE_H
    local pasteBoxH = IE.HEAD_H + 8 + pasteH + IE.PASTE_ROW_H
    IE.PlaceBox(IE.pasteBox, im, y, pasteBoxH)
    y = y - pasteBoxH - IE.GAP
    IE.PlaceBox(IE.whatBox, im, y, IE.HEAD_H + whatH)
    y = y - IE.HEAD_H - whatH - IE.GAP
    IE.PlaceBox(IE.whereBox, im, y, nil)
    IE.PaintWhat()
    IE.PaintWhere()
end

-- WHAT'S IN IT: the pack's lines, "Nothing pasted yet." or the read error
function IE.PaintWhat()
    local pv = IE.peek
    if not pv then return end
    local d, err = IE.peekData, IE.peekErr
    pv:SetShown(d ~= nil)
    IE.peekEmpty:SetShown(d == nil)
    IE.peekEmpty:SetText(err and IE.Safe(err) or "Nothing pasted yet.")
    local c = err and { 0.95, 0.42, 0.42 } or COL.faint
    IE.peekEmpty:SetTextColor(c[1], c[2], c[3])
    if not d then return end
    local info = d.info or {}
    local head
    if info.name then
        head = IE.Safe(info.name) .. (info.version and ("   " .. IE.Dim("version " .. IE.Safe(info.version))) or "")
    elseif info.version then
        head = "Version " .. IE.Safe(info.version)
    else
        head = IE.Dim("No pack name")
    end
    pv.head:SetText(head)
    local link = info.link
    pv.link:SetShown(link ~= nil)
    if link then
        pv.link:ClearAllPoints()
        pv.link:SetPoint("LEFT", pv.head, "RIGHT", 12, 0)
        pv.link:SetPoint("RIGHT", pv, "RIGHT", 0, 0)
        pv.link._v = IE.Safe(link)
        pv.link:SetText(pv.link._v)
        pv.link:SetCursorPosition(0)
    end
    pv.notes:SetText(info.notes and IE.Safe(info.notes) or IE.Dim("No notes."))
    pv.holds:SetText(IE.Dim("Holds: ") .. d.holds)
    local missing = d.missing or {}
    if #missing > 0 then
        pv.media:SetText(IE.MediaNote(missing))
        pv.media:SetTextColor(0.95, 0.75, 0.35)
    else
        pv.media:SetText("Every texture and font it uses is on this PC.")
        pv.media:SetTextColor(IE.GREEN[1], IE.GREEN[2], IE.GREEN[3])
    end
    -- a long note or media list reads whole in the tooltip
    pv._tipTitle = info.name and IE.Safe(info.name) or "This string"
    local tip = {}
    if info.notes then tip[#tip + 1] = IE.Safe(info.notes) end
    tip[#tip + 1] = "Holds " .. d.holds .. "."
    if #missing > 0 then tip[#tip + 1] = IE.MediaNote(missing) end
    pv._tip = table.concat(tip, "\n\n")
end

-- WHERE IT GOES. Nothing pasted: one quiet line. A plain import: a row per
-- kind (its choice beside it only when the string has that kind) and the
-- empty-groups tick. A string you have an earlier copy of: what you have and
-- what it is, the parts to take, the items; its two ways on the foot bar.
function IE.PaintWhere()
    local rows = IE.whereRows
    if not rows then return end
    local d = IE.peekData
    local c = d and d.brings
    local upd = d ~= nil and c == nil and IE.plan ~= nil
    local function Ink(fs, on)
        local col = on and COL.ink or COL.faint
        fs:SetTextColor(col[1], col[2], col[3])
    end
    IE.whereEmpty:SetShown(d == nil)
    for _, r in ipairs(rows) do r:SetShown(c ~= nil) end
    IE.updInline:SetShown(upd)
    IE.whereBox.title:SetText(upd and "YOU ALREADY HAVE THIS PACK" or "WHERE IT GOES")
    -- the foot bar: Import, or the update's two ways
    local empty = (ieBox and ieBox:GetText() or "") == ""
    IE.impBtn:SetShown(not upd)
    IE.impBtn:SetAlpha(empty and 0.45 or 1)
    IE.updBtn:SetShown(upd)
    IE.cpyBtn:SetShown(upd)
    IE.eachBtn:SetShown(upd)
    ieStatus:SetPoint("LEFT", upd and IE.eachBtn or IE.impBtn, "RIGHT", 10, 0)
    if c then
        local nl = c.layout
        if nl == 1 then
            IE.whereLay:SetText("\"" .. IE.Safe(c.layNames[1] or "?") .. "\" comes in as a new layout.")
        elseif nl > 1 then
            IE.whereLay:SetText(nl .. " layouts come in as new layouts.")
        else
            IE.whereLay:SetText("None in this string")
        end
        Ink(IE.whereLay, nl > 0)
        local kinds, n = IE.KindsText(c)
        IE.whereItems:SetText(kinds and (kinds .. (n == 1 and " goes into" or " go into")) or "None in this string")
        Ink(IE.whereItems, kinds ~= nil)
        IE.target:SetShown(kinds ~= nil)
        if kinds then IE.target.Refresh() end
        local nr = c.reminder
        IE.whereRem:SetText((nr > 0) and (nr .. (nr == 1 and " reminder joins" or " reminders join")) or "None in this string")
        Ink(IE.whereRem, nr > 0)
        IE.remTarget:SetShown(nr > 0)
        if nr > 0 then IE.remTarget.Refresh() end
        IE.emptyGroups.Sync()
    end
    if upd then IE.PaintUpdInline() end
end

-- the update's own lines: what you have and what this is, the part chips
-- (each with how many items it touches), the item ticks
function IE.PaintUpdInline()
    local u, plan = IE.updInline, IE.plan
    if not (u and plan) then return end
    local theirs = plan.info and plan.info.version
    local name = (plan.info and plan.info.name) and IE.Safe(plan.info.name) or "this pack"
    local mine = IE.LocalVersion(plan)
    local line
    if plan.relation == "same" then
        line = "You have this exact version of " .. name .. ". Importing it again brings in a second copy."
    elseif plan.relation == "older" then
        line = "This string is older than your copy of " .. name .. ": updating would bring back its older settings."
    else
        line = "You have " .. name .. (mine and (" " .. IE.Safe(mine)) or "") .. ". This string is "
            .. (theirs and IE.Safe(theirs) or "newer") .. ". Pick what to take from it:"
    end
    u.line:SetText(line)
    local h = math.ceil(u.line:GetStringHeight() or 14)
    -- the parts, as chips that wrap to the box's width
    local per = {}
    for _, it in ipairs(plan.items or {}) do
        if it.status == "changed" and not (IE.keep and IE.keep[it.inc.uid]) then
            for p in pairs(it.parts) do per[p] = (per[p] or 0) + 1 end
        end
    end
    local parts = IE.UpdateParts()
    local width = (u:GetWidth() or 0)
    if width < 100 then width = IE.PaneW() - 24 end
    local x, y = 0, -(h + 8)
    for _, c in ipairs(u.chips) do
        local n = per[c.part] or 0
        c.fs:SetText(Store.UPDATE_PART_LABELS[c.part] .. ((n > 0) and (" (" .. n .. ")") or ""))
        local cw = math.ceil(c.fs:GetUnboundedStringWidth() or 60) + 18
        if x > 0 and x + cw > width then
            x, y = 0, y - 26
        end
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", u, "TOPLEFT", x, y)
        c:SetWidth(cw)
        local on = parts[c.part] == true
        local bg = on and COL.sel or COL.well
        local edge = on and COL.arcDeep or COL.line
        local ink = on and COL.ink or COL.faint
        c:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        c:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        c.fs:SetTextColor(ink[1], ink[2], ink[3])
        x = x + cw + 6
    end
    y = y - 22 - 10
    local nNew, newName = 0, nil
    for _, it in ipairs(plan.items or {}) do
        if it.status == "new" then
            nNew = nNew + 1
            newName = it.name
        end
    end
    local nGone = #(plan.gone or {})
    u.add.Label("Add new items (" .. ((nNew == 0) and "none" or (nNew == 1 and newName)
        and ("1: " .. IE.Safe(newName)) or tostring(nNew)) .. ")")
    u.add:ClearAllPoints()
    u.add:SetPoint("TOPLEFT", u, "TOPLEFT", 0, y)
    u.add.Sync()
    u.remove.Label("Remove items the pack dropped (" .. ((nGone == 0) and "none" or tostring(nGone)) .. ")")
    u.remove:ClearAllPoints()
    u.remove:SetPoint("LEFT", u.add, "RIGHT", 18, 0)
    u.remove.Sync()
    local dn = plan.deleted or 0
    u.revive:SetShown(dn > 0)
    if dn > 0 then
        u.revive.Label("Bring back the " .. dn .. (dn == 1 and " item" or " items") .. " you deleted")
        u.revive:ClearAllPoints()
        u.revive:SetPoint("TOPLEFT", u, "TOPLEFT", 0, y - 26)
        u.revive.Sync()
    end
end

-- the pack version this player has: the one saved with the layout here that
-- the string updates
function IE.LocalVersion(plan)
    for _, r in ipairs(plan.payload and plan.payload.records or {}) do
        local id = r.type == "layout" and plan.map and plan.map[r.id]
        if type(id) == "number" then
            local info = Store.PackInfo(id)
            if info and info.version then return info.version end
        end
    end
    return nil
end

function IE.LayPane()
    IE.LayExport()
    IE.LayImport()
end

-- The pasted string's pack info and missing media, read a moment after the
-- text stops changing.
function IE.QueuePeek()
    if IE.peekQueued then return end
    IE.peekQueued = true
    C_Timer.After(0.2, function()
        IE.peekQueued = nil
        IE.ShowPeek()
    end)
end

function IE.ShowPeek()
    local text = ieBox and ieBox:GetText() or ""
    if text == IE.peekText then return end
    IE.peekText = text
    -- one read of the string: its payload for the lines, and what a plain
    -- import would bring (an update says what it does on its own panel)
    local plan, err
    if text ~= "" then plan, err = Store.PlanUpdate(text) end
    local payload = plan and plan.payload
    IE.peekData = payload and { info = Store.CleanPackInfo(payload.info), missing = Store.MissingMedia(payload),
        brings = (plan.relation == "new") and IE.Brings(payload) or nil, holds = IE.HoldsText(payload) } or nil
    IE.peekErr = (text ~= "" and not payload) and (err or "This string can't be read.") or nil
    if plan and plan.relation ~= "new" then
        -- per string: nothing kept, nothing deleted brought back
        if IE.planText ~= text then IE.keep, IE.revive = {}, nil end
        IE.plan, IE.planText = plan, text
        IE.updMode = (plan.relation == "update") and "update" or "copy"
    elseif not (IE.upd and IE.upd:IsShown()) then
        IE.plan, IE.planText = nil, nil
    end
    IE.LayImport()
end

-- Right after an update its undo waits at the end of the Import line (nil
-- hides it); the layout's own page offers it until the next update.
function IE.ShowUndo(key)
    IE.undoKey = key
    if not (IE.undoBtn and ieStatus) then return end
    IE.undoBtn:SetShown(key ~= nil)
    ieStatus:SetPoint("RIGHT", IE.impFoot, "RIGHT", key and -(10 + 112 + 8) or -10, 0)
end

function IE.UndoReport(res)
    local n = res.restored
    local parts = { "Update undone: " .. n .. (n == 1 and " item" or " items") .. " back as before" }
    if res.removed > 0 then parts[#parts + 1] = res.removed .. (res.removed == 1 and " new item" or " new items") .. " removed" end
    if res.kept > 0 then
        parts[#parts + 1] = res.kept .. (res.kept == 1 and " new group kept, it holds" or " new groups kept, they hold")
            .. " your own items"
    end
    return table.concat(parts, ", ") .. "."
end

function IE.RunUndo()
    local key = IE.undoKey
    IE.ShowUndo(nil)
    local res, err = Options.RunUndo(key)
    if not res then
        IE.SetStatus(err == "nothing to undo" and "Nothing to undo." or (err or "Nothing to undo."), false)
        return
    end
    IE.SetStatus(IE.UndoReport(res), true)
end

-- A layout's undo: the line its page shows, the ask, the act.
function Options.UndoNote(layoutId)
    local u = Store.UndoInfo(layoutId)
    if not u then return nil end
    local when = IE.DateOf(u.when)
    local s = u.version and ("Updated to version " .. IE.Safe(u.version)) or "Updated from a pack string"
    return s .. (when and (" on " .. when) or "") .. "."
end

function Options.RunUndo(layoutId)
    local res, err = Store.UndoUpdate(layoutId)
    if res then RefreshAll() end
    return res, err
end

function Options.ConfirmUndo(layoutId)
    local lay = Store.Get(layoutId)
    if not (lay and Store.UndoInfo(layoutId)) then return end
    StaticPopupDialogs["ARCUIV2_UNDO_UPDATE"] = StaticPopupDialogs["ARCUIV2_UNDO_UPDATE"] or {
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        preferredIndex = 3,
    }
    local d = StaticPopupDialogs["ARCUIV2_UNDO_UPDATE"]
    d.text = "Undo the last update of '" .. (lay.name or "?") .. "'? What it changed, added or removed goes back as it was."
    d.OnAccept = function() Options.RunUndo(layoutId) end
    StaticPopup_Show("ARCUIV2_UNDO_UPDATE")
end

function IE.BuildUpdate()
    if IE.upd then return IE.upd end
    local im = IE.impPane
    local f = CreateFrame("Frame", nil, im, "BackdropTemplate")
    f:SetPoint("TOPLEFT", im, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", im, "BOTTOMRIGHT", -4, 0)
    f:SetFrameLevel(im:GetFrameLevel() + 30)
    AT.Skin(f, COL.bg, COL.arcDeep)
    f:EnableMouse(true)
    f:Hide()
    IE.upd = f
    local function Label(text, size, col)
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, size, "")
        fs:SetTextColor(col[1], col[2], col[3])
        fs:SetJustifyH("LEFT")
        if text then fs:SetText(text) end
        return fs
    end
    f.title = Label(nil, 14, COL.lead)
    f.title:SetPoint("TOPLEFT", 12, -10)
    -- the string's pack info and the media missing here, under the title
    f.info = IE.InfoBlock(f)
    f.info:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.sum = Label(nil, 11, COL.ink)
    f.sum:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.sum:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.sum:SetWordWrap(true)
    -- what to do: the two ways are one choice
    f.modeLbl = Label("WHAT TO DO", 9, COL.faint)
    f.modeLbl:SetPoint("TOPLEFT", f.sum, "BOTTOMLEFT", 0, -12)
    f.mode = AT.MakeDropdown(win, f, 200, function()
        return { { value = "update", text = "Update my copy" }, { value = "copy", text = "Import as a new copy" } }
    end, function() return IE.updMode or "update" end, function(v)
        IE.updMode = v
        IE.PaintUpdate()
    end)
    f.mode:SetPoint("TOPLEFT", f.modeLbl, "BOTTOMLEFT", 0, -4)
    AT.Tooltip(f.mode, "What to do", "Update my copy changes the items you have, part by part. Import as a new copy leaves them alone and brings a second copy in.")
    -- the parts, four to a line
    f.partsLbl = Label("UPDATE THESE PARTS", 9, COL.faint)
    f.partsLbl:SetPoint("TOPLEFT", f.mode, "BOTTOMLEFT", 0, -12)
    f.parts = {}
    local COLW, ROWH = 140, 22
    for i, p in ipairs(Store.UPDATE_PARTS) do
        local b = IE.CheckRow(f, function() return IE.UpdateParts()[p] end, function(v)
            local u = Store.UI()
            if type(u.ieParts) ~= "table" then u.ieParts = {} end
            u.ieParts[p] = v
        end, p == "position" and { "Size & Position",
            "Where each item sits (its group, or free and where), its anchor, sizes, strata and mouse. Off keeps your own placement." } or nil)
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        b:SetPoint("TOPLEFT", f.partsLbl, "BOTTOMLEFT", col * COLW, -4 - row * ROWH)
        b:SetWidth(COLW - 8)
        b.part = p
        f.parts[#f.parts + 1] = b
    end
    local rows = math.ceil(#Store.UPDATE_PARTS / 4)
    f.itemsLbl = Label("ITEMS", 9, COL.faint)
    f.itemsLbl:SetPoint("TOPLEFT", f.partsLbl, "BOTTOMLEFT", 0, -8 - rows * ROWH)
    f.add = IE.CheckRow(f, function() return IE.UpdFlag("ieAdd") end, function(v) Store.UI().ieAdd = v and nil or false end,
        { "Add new items", "Items in the string that you do not have yet come in, where it puts them." })
    f.add:SetPoint("TOPLEFT", f.itemsLbl, "BOTTOMLEFT", 0, -4)
    f.add:SetWidth(COLW * 2 - 8)
    f.remove = IE.CheckRow(f, function() return IE.UpdFlag("ieRemove") end, function(v) Store.UI().ieRemove = v and nil or false end,
        { "Remove items the pack dropped", "Items that came from this pack but are no longer in the string go. Anything you added yourself always stays." })
    f.remove:SetPoint("TOPLEFT", f.add, "TOPLEFT", COLW * 2, 0)
    f.remove:SetWidth(COLW * 2 - 8)
    -- the pack items the player deleted: one line, and a tick for this time
    f.dead = CreateFrame("Frame", nil, f)
    f.dead:SetSize(COLW * 4, 20)
    f.dead:SetPoint("TOPLEFT", f.add, "BOTTOMLEFT", 0, -4)
    f.dead.fs = f.dead:CreateFontString(nil, "OVERLAY")
    f.dead.fs:SetFont(AT.FONT, 11, "")
    f.dead.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    f.dead.fs:SetPoint("LEFT", f.dead, "LEFT", 0, 0)
    f.dead.fs:SetJustifyH("LEFT")
    f.dead.fs:SetWordWrap(false)
    f.revive = IE.CheckRow(f.dead, function() return IE.revive == true end, function(v) IE.revive = v or nil end,
        { "Bring them back this time", "The pack items you deleted come back with this update. Unticked, they stay deleted." })
    f.revive:SetPoint("LEFT", f.dead.fs, "RIGHT", 12, 0)
    f.dead:Hide()
    -- the changes, item by item; a changed one can keep the player's version
    local well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    well:SetPoint("TOPLEFT", f.add, "BOTTOMLEFT", 0, -10)
    well:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    well:SetPoint("BOTTOM", f, "BOTTOM", 0, 40)
    AT.Skin(well, COL.well, COL.line)
    f.well = well
    f.listScroll, f.listHost = AT.MakeScroll(well)
    f.listScroll:SetPoint("TOPLEFT", 6, -6)
    f.listScroll:SetPoint("BOTTOMRIGHT", -10, 6)
    f.rows = {}
    f.listScroll:HookScript("OnSizeChanged", function(s, w)
        f.listHost:SetWidth(math.max(60, (w or 300) - AT.ScrollExtra()))
        s:UpdateScroll()
    end)
    -- the info lines wrap to the panel's width
    f:HookScript("OnSizeChanged", function() IE.FillUpdInfo() end)
    f.go = AT.MakeSmallButton(f, "Update", 150)
    f.go:SetPoint("BOTTOMLEFT", 12, 10)
    f.go.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    f.go:SetScript("OnClick", function() IE.RunUpdate() end)
    f.cancel = AT.MakeQuietButton(f, "Cancel", 70)
    f.cancel:SetPoint("LEFT", f.go, "RIGHT", 8, 0)
    f.cancel:SetScript("OnClick", function()
        f:Hide()
        IE.SetStatus("", true)
    end)
    return f
end

function IE.DateOf(t)
    t = tonumber(t)
    if not (t and t > 0 and date) then return nil end
    return date("%b %d, %Y", t)
end

-- one line of the change list: a heading, or an item; a changed item's line
-- carries its Keep mine tick
IE.LIST_H = 20
function IE.ListRow(i)
    local f = IE.upd
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f.listHost)
    r:SetHeight(IE.LIST_H)
    r.fs = r:CreateFontString(nil, "OVERLAY")
    r.fs:SetFont(AT.FONT, 11, "")
    r.fs:SetJustifyH("LEFT")
    r.fs:SetWordWrap(false)
    r.keep = IE.CheckRow(r, function() return r.uid ~= nil and IE.keep[r.uid] == true end, function(v)
        if r.uid then IE.keep[r.uid] = v or nil end
    end, { "Keep mine", "Leaves this item as you have it. The rest of the update still comes in." })
    r.keep.fs:SetText("Keep mine")
    r.keep:SetWidth(20 + 6 + math.ceil(r.keep.fs:GetUnboundedStringWidth() or 60) + 4)
    r.keep:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    f.rows[i] = r
    return r
end

-- the list of changes, item by item
function IE.FillList(plan)
    local f = IE.upd
    local n = 0
    local function Row(text, kind, uid)
        n = n + 1
        local r = IE.ListRow(n)
        local y = -(n - 1) * IE.LIST_H
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f.listHost, "TOPLEFT", 0, y)
        r:SetPoint("TOPRIGHT", f.listHost, "TOPRIGHT", 0, y)
        r.kind, r.uid = kind, uid
        r.keep:SetShown(kind == "changed")
        r.fs:SetFont(AT.FONT, (kind == "head") and 9 or 11, "")
        r.fs:ClearAllPoints()
        r.fs:SetPoint("LEFT", r, "LEFT", (kind == "head") and 2 or 12, 0)
        if kind == "changed" then
            r.fs:SetPoint("RIGHT", r.keep, "LEFT", -8, 0)
        else
            r.fs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        end
        r.fs:SetText(text)
        r:Show()
    end
    local function Name(it) return IE.Safe(it.name or it.type or "?") end
    local changed, new, dead = {}, {}, {}
    for _, it in ipairs(plan.items) do
        if it.status == "changed" then
            changed[#changed + 1] = it
        elseif it.status == "new" then
            new[#new + 1] = it
        elseif it.status == "deleted" then
            dead[#dead + 1] = it
        end
    end
    if #changed > 0 then
        Row("CHANGED", "head")
        for _, it in ipairs(changed) do
            local ps = {}
            for _, p in ipairs(Store.UPDATE_PARTS) do
                if it.parts[p] then ps[#ps + 1] = Store.UPDATE_PART_LABELS[p] end
            end
            Row(Name(it) .. ": " .. table.concat(ps, ", "), "changed", it.inc.uid)
        end
    end
    if #new > 0 then
        Row("NEW", "head")
        for _, it in ipairs(new) do Row(Name(it), "item") end
    end
    if #plan.gone > 0 then
        Row("NO LONGER IN THE PACK", "head")
        for _, m in ipairs(plan.gone) do Row(IE.Safe(m.name or m.type or "?"), "item") end
    end
    if #dead > 0 then
        Row("YOU DELETED", "head")
        for _, it in ipairs(dead) do Row(Name(it), "item") end
    end
    if n == 0 then Row("Nothing differs from what you have.", "item") end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    f.listHost:SetHeight(math.max(10, n * IE.LIST_H + 4))
    f.listScroll:UpdateScroll()
end

-- the summary line: dates, what the string does, counts, notes
function IE.Summary(plan, kept)
    local mine, theirs = IE.DateOf(plan.localAt), IE.DateOf(plan.at)
    local s = {}
    if theirs then s[#s + 1] = "Made " .. theirs .. (mine and (", yours is from " .. mine) or "") .. "." end
    if plan.relation == "older" then
        s[#s + 1] = "Updating would bring back its older settings."
    elseif plan.relation == "same" then
        s[#s + 1] = "Nothing would change; importing again brings in a second copy."
    end
    local goneN = #plan.gone
    local counts = {}
    if plan.changed > 0 then
        counts[#counts + 1] = plan.changed .. " changed" .. ((kept > 0) and (" (" .. kept .. " kept as yours)") or "")
    end
    if plan.new > 0 then counts[#counts + 1] = plan.new .. " new" end
    if plan.same > 0 then counts[#counts + 1] = plan.same .. " unchanged" end
    if goneN > 0 then counts[#counts + 1] = goneN .. (goneN == 1 and " pack item is" or " pack items are") .. " no longer in it" end
    if #counts > 0 then s[#s + 1] = table.concat(counts, ", ") .. "." end
    if plan.otherGame then s[#s + 1] = IE.GameNote(plan) end
    if plan.newer then s[#s + 1] = IE.NewerNote(plan) end
    return table.concat(s, " ")
end

-- the info lines at the panel's width, the summary under them
function IE.FillUpdInfo()
    local f = IE.upd
    if not (f and IE.plan) then return end
    local w = (f:GetWidth() or 0) - 24
    if w < 100 then w = (iePane:GetWidth() or 0) - 28 end
    if w < 100 then w = 560 end
    local h = IE.FillInfo(f.info, IE.plan.info, IE.updMissing, w)
    f.sum:SetPoint("TOPLEFT", (h > 0) and f.info or f.title, "BOTTOMLEFT", 0, -6)
end

function IE.ShowUpdate(plan, text)
    local f = IE.BuildUpdate()
    IE.plan, IE.planText = plan, text
    -- per string: nothing kept, nothing deleted brought back
    IE.keep, IE.revive = {}, nil
    IE.ShowUndo(nil)
    -- nothing to change, or older than the copy here: a copy is the safer pick
    IE.updMode = (plan.relation == "update") and "update" or "copy"
    if plan.relation == "same" then
        f.title:SetText("You already have this")
    elseif plan.relation == "older" then
        f.title:SetText("This string is older than your copy")
    else
        f.title:SetText("This string updates items you have")
    end
    IE.updMissing = Store.MissingMedia(plan.payload)
    IE.FillUpdInfo()
    IE.FillList(plan)
    IE.PaintUpdate()
    f:Show()
    IE.SetStatus("", true)
end

function IE.PaintUpdate()
    local f = IE.upd
    if not f then return end
    local plan = IE.plan
    local update = (IE.updMode or "update") == "update"
    -- how many items each part touches; a kept one counts for none
    local per, kept = {}, 0
    for _, it in ipairs(plan and plan.items or {}) do
        if it.status == "changed" then
            if IE.keep and IE.keep[it.inc.uid] then
                kept = kept + 1
            else
                for p in pairs(it.parts) do per[p] = (per[p] or 0) + 1 end
            end
        end
    end
    IE.partCount = per
    if plan then f.sum:SetText(IE.Summary(plan, kept)) end
    for _, b in ipairs(f.parts) do
        local n = per[b.part] or 0
        b.fs:SetText(Store.UPDATE_PART_LABELS[b.part] .. ((n > 0) and (" (" .. n .. ")") or ""))
        -- a part nothing changed in reads quieter
        local c = (n > 0) and COL.ink or COL.faint
        b.fs:SetTextColor(c[1], c[2], c[3])
        b:SetWidth(20 + 6 + math.ceil(b.fs:GetUnboundedStringWidth() or 100) + 4)
        b.Sync()
        b:SetShown(update)
    end
    f.add.fs:SetText("Add new items")
    f.remove.fs:SetText("Remove items the pack dropped")
    f.add.Sync()
    f.remove.Sync()
    f.add:SetShown(update)
    f.remove:SetShown(update)
    f.partsLbl:SetShown(update)
    f.itemsLbl:SetShown(update)
    -- the items the player deleted stay out unless ticked back this time
    local dn = plan and plan.deleted or 0
    local dead = update and dn > 0
    f.dead:SetShown(dead)
    if dead then
        f.dead.fs:SetText((dn == 1) and "1 item you deleted stays deleted." or (dn .. " items you deleted stay deleted."))
        f.dead.fs:SetWidth(math.ceil(f.dead.fs:GetUnboundedStringWidth() or 200) + 2)
        f.revive.fs:SetText((dn == 1) and "Bring it back this time" or "Bring them back this time")
        f.revive:SetWidth(20 + 6 + math.ceil(f.revive.fs:GetUnboundedStringWidth() or 140) + 4)
        f.revive.Sync()
    end
    f.well:SetPoint("TOPLEFT", dead and f.dead or f.add, "BOTTOMLEFT", 0, -10)
    -- the list's ticks; a kept item reads quieter
    for _, r in ipairs(f.rows) do
        if r:IsShown() then
            local c = COL.dim
            if r.kind == "head" then
                c = COL.faint
            elseif r.kind == "changed" then
                r.keep:SetShown(update)
                r.keep.Sync()
                c = (update and IE.keep and IE.keep[r.uid]) and COL.faint or COL.ink
            end
            r.fs:SetTextColor(c[1], c[2], c[3])
        end
    end
    f.go.fs:SetText(update and "Update" or "Import as a copy")
end

function IE.RunUpdate()
    local plan, text = IE.plan, IE.planText
    if not plan then return end
    local f = IE.upd
    if (IE.updMode or "update") ~= "update" then
        if f then f:Hide() end
        IE.DoImport(text, true, plan)
        return
    end
    local kept = 0
    for _, it in ipairs(plan.items) do
        if it.status == "changed" and IE.keep and IE.keep[it.inc.uid] then kept = kept + 1 end
    end
    local res = Store.ApplyUpdate(plan, {
        parts = IE.UpdateParts(), add = IE.UpdFlag("ieAdd"), remove = IE.UpdFlag("ieRemove"),
        skip = IE.keep, revive = IE.revive == true, targetLayoutId = IE.TargetId(),
    })
    if f then f:Hide() end
    local parts = {}
    parts[#parts + 1] = "Updated " .. res.updated .. (res.updated == 1 and " item" or " items")
    if res.added > 0 then parts[#parts + 1] = "added " .. res.added end
    if res.removed > 0 then parts[#parts + 1] = "removed " .. res.removed end
    if kept > 0 then parts[#parts + 1] = "kept " .. kept .. " as yours" end
    local msg = table.concat(parts, ", ") .. "."
    if plan.newer then msg = msg .. " " .. IE.NewerNote(plan) end
    IE.SetStatus(msg, true)
    IE.plan, IE.planText = nil, nil
    IE.ShowUndo(res.undo)
    IE.peekText = nil
    IE.ShowPeek()
end

function IE.Refresh()
    IE.SetTab(ui.ieTab)
    local sel, open = ui.ieSel, ui.ieOpen
    local only = IE.LoadedOnly()
    IE.loadedOnly.check:SetOn(only)
    IE.emptyGroups.check:SetOn(IE.EmptyGroups())
    local w = IE.listScroll:GetWidth()
    if not w or w < 50 then w = 300 end
    ieListHost:SetWidth(w - AT.ScrollExtra())
    local y, n = 0, 0
    local function Row(rec, indent, isLayout, state, onClick, chevDown, onChev)
        n = n + 1
        local r = IE.Row(n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        r:SetPoint("TOPRIGHT", 0, y)
        y = y - IE.ROW_H
        -- pooled: a NOT LOADED header hid the pill, a left-out row dimmed itself
        r.pill:Show()
        r:SetAlpha(1)
        local tx = indent + (isLayout and 18 or 0)
        r.check:ClearAllPoints()
        r.check:SetPoint("LEFT", tx, 0)
        r.check:SetOn(state ~= nil)
        r.check.check:SetAlpha(state == "some" and 0.45 or 1)
        r.chevBtn:SetShown(isLayout == true)
        r.chevBtn:ClearAllPoints()
        r.chevBtn:SetPoint("LEFT", indent - 2, 0)
        r.chev:SetDown(chevDown == true)
        r.chevBtn:SetScript("OnClick", onChev)
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", tx + 24, 0)
        r.name:SetPoint("RIGHT", r.pill, "LEFT", -6, 0)
        r.name:SetText(rec.name)
        local c = state and COL.ink or COL.dim
        r.name:SetTextColor(c[1], c[2], c[3])
        r:SetScript("OnClick", onClick)
        r:Show()
        return r
    end
    -- a row "Only what loads here" leaves out: greyed, its tick box inert
    local function Out(r)
        r:SetAlpha(0.45)
        r:SetScript("OnClick", nil)
    end
    local function State(recs)
        local picked = 0
        for _, x in ipairs(recs) do if sel[x.id] then picked = picked + 1 end end
        if picked == 0 then return nil end
        return (picked == #recs) and "all" or "some"
    end
    local function Kid(c, indent, out)
        local cr = Row(c, indent, false, (sel[c.id] and not out) and "all" or nil, function()
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
        if out then Out(cr) end
    end
    for _, lay in ipairs(Store.Layouts()) do
        local kids = IE.Children(lay)
        local layLoads = Store.IsLoaded(lay)
        local layOut = only and not layLoads
        -- A layout that loads lists what does not load here after the rest,
        -- under its own NOT LOADED, as the sidebar does.
        local here, later = {}, {}
        for _, c in ipairs(kids) do
            if not layLoads or Store.IsLoaded(c) then here[#here + 1] = c else later[#later + 1] = c end
        end
        -- the layout's box covers what can go in the string
        local counted = { lay }
        for _, c in ipairs(here) do counted[#counted + 1] = c end
        if not only then
            for _, c in ipairs(later) do counted[#counted + 1] = c end
        end
        local state = (not layOut) and State(counted) or nil
        local r = Row(lay, 6, true, state, function()
            local on = state ~= "all"
            for _, x in ipairs(counted) do sel[x.id] = on or nil end
            IE.Refresh()
        end, open[lay.id] == true, function()
            open[lay.id] = not open[lay.id] or nil
            IE.Refresh()
        end)
        if layLoads then
            r.pill:Set(#kids == 1 and "1 item" or (#kids .. " items"), COL.dim)
        else
            r.pill:Set("not loaded", COL.faint)
        end
        if layOut then Out(r) end
        if open[lay.id] then
            for _, c in ipairs(here) do Kid(c, 28, layOut) end
            if #later > 0 then
                -- folds with the sidebar's own NOT LOADED (one preference)
                local shutSet = Store.UI().nlShut
                local shut = shutSet ~= nil and shutSet[lay.id] == true
                local hs = (not only) and State(later) or nil
                local hr = Row({ name = "NOT LOADED  (" .. #later .. ")" .. (only and "  -  left out" or "") },
                    28, true, hs, function()
                        local on = hs ~= "all"
                        for _, c in ipairs(later) do sel[c.id] = on or nil end
                        IE.Refresh()
                    end, not shut, function()
                        local u = Store.UI()
                        u.nlShut = u.nlShut or {}
                        u.nlShut[lay.id] = (not shut) or nil
                        IE.Refresh()
                    end)
                hr.pill:Hide()
                hr.name:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
                if only then Out(hr) end
                if not shut then
                    for _, c in ipairs(later) do Kid(c, 50, only) end
                end
            end
        end
    end
    for i = n + 1, #IE.rowPool do IE.rowPool[i]:Hide() end
    ieListHost:SetHeight(math.max(1, -y))
    IE.listScroll:UpdateScroll()
    local what, count = IE.PickSummary()
    local text = count > 0 and (what .. " ticked") or "nothing ticked yet"
    local left = IE.LeftOut()
    if left > 0 then text = text .. "  (" .. left .. " not loaded, left out)" end
    IE.expStatus:SetText(text)
    IE.target.Refresh()
    IE.remTarget.Refresh()
    -- the pack info fields follow the ticks, and the rows saying where a
    -- pasted string lands follow the layouts (LayPane does both)
    IE.LayPane()
    IE.PaintExport()
end

-- ticks that "Only what loads here" leaves out of the string
function IE.LeftOut()
    if not IE.LoadedOnly() then return 0 end
    local n = 0
    for id in pairs(ui.ieSel) do
        local r = Store.Get(id)
        if r and not IE.LoadsHere(r) then n = n + 1 end
    end
    return n
end
Options._ie = IE   -- offline harness access

-- 44181 -> "44,181"
function IE.Thousands(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- the ticks a string was made from, to tell when they changed since
function IE.SelSig()
    return table.concat(IE.SelectedIds(), ",") .. (IE.LoadedOnly() and "|o" or "")
end

-- What a string is named after: the one layout it holds, else the item, or
-- the count of items from one layout, else the counts.
function IE.ExportName(ids)
    local lays, items, from = {}, {}, {}
    for _, id in ipairs(ids) do
        local r = Store.Get(id)
        if r and r.type == "layout" then
            lays[#lays + 1] = r
        elseif r then
            items[#items + 1] = r
            local l = Store.LayoutOf(r)
            if l then from[l.id] = l end
        end
    end
    local function One()
        local only
        for _, l in pairs(from) do
            if only and only ~= l then return nil end
            only = l
        end
        return only
    end
    local l = One()
    if #lays == 1 and (l == nil or l == lays[1]) then return tostring(lays[1].name) end
    if #lays == 0 and #items == 1 then return tostring(items[1].name) end
    if #lays == 0 and l then return #items .. " items from " .. tostring(l.name) end
    return (IE.PickSummary())
end

-- The string's name, its counts and the line under the box: how to copy it,
-- or that the ticks changed since it was made, or why it failed.
function IE.PaintExport()
    if not IE.expBox then return end
    local has = IE.expText ~= nil
    IE.expName:SetShown(has)
    IE.expMeta:SetShown(has)
    IE.expScroll:SetShown(has)
    IE.expEmpty:SetShown(not has)
    local foot, c = "", COL.dim
    if IE.expErr then
        foot, c = IE.expErr, { 0.95, 0.42, 0.42 }
    elseif has and IE.expSig ~= IE.SelSig() then
        foot, c = "Your ticks changed since. Press Export selected again for a new string.", { 0.95, 0.75, 0.35 }
    elseif has then
        foot, c = "Selected: press Ctrl+C to copy it, then paste it anywhere.", { 0.35, 0.85, 0.45 }
    end
    IE.expFoot:SetText(foot)
    IE.expFoot:SetTextColor(c[1], c[2], c[3])
end

-- build the string from everything ticked into the Export tab's own box,
-- pre-highlighted, so Ctrl+C is the only step left
function Options.ExportSelected()
    -- the icons of a group that goes in are tested too
    local ids = IE.SelectedIds()
    local s, n = Store.Export(ids, IE.LoadedOnly() and IE.LoadsHere or nil)
    if s then
        IE.expText, IE.expSig, IE.expErr = s, IE.SelSig(), nil
        local what = IE.PickSummary()
        local left = IE.LeftOut()
        IE.expName:SetText(IE.Safe(IE.ExportName(ids)))
        IE.expMeta:SetText(string.format("%s, %s characters%s", what, IE.Thousands(#s),
            left > 0 and (", " .. left .. " not loaded left out") or ""))
        IE.expBox:SetText(s)
        IE.expBox:SetFocus()
        IE.expBox:HighlightText()
    else
        IE.expText, IE.expSig, IE.expErr = nil, nil, n or "Export failed."
        IE.expBox:SetText("")
    end
    IE.PaintExport()
end

-- the rail Exp button and the editors' Export buttons land here: tick that
-- one record (a layout with everything under it) and export it
function Options.OpenExport(id)
    ui.ieTab = "export"
    Options.Open()
    Options.Select("ie")
    IE.SetTab("export")
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

-- A pack's string offered from elsewhere (a Spotlight card's Update my copy):
-- the Import page opens holding it, on its update plan when the player has an
-- earlier version, else ready to import.
function Options.ImportOffer(text)
    ui.ieTab = "import"
    Options.Open()
    Options.Select("ie")
    if not ieBox then return end
    IE.SetTab("import")
    ieBox:SetText(text)
    local plan, err = Store.PlanUpdate(text)
    if not plan then
        IE.SetStatus(err or "Import failed.", false)
    elseif plan.relation == "new" then
        IE.SetStatus("Press Import to bring it in.", true)
    else
        IE.ShowUpdate(plan, text)
    end
end

function Options.Select(selType, id)
    -- The QOL page folded into Modules: a pick of it lands there.
    if selType == "qol" then selType, id = "modules", nil end
    -- An open-then-select from outside waits for the first build to finish.
    local L = Options.Loader
    if L and L.Busy() and not L.InBuild() then
        L.Then(function() Options.Select(selType, id) end)
        return
    end
    -- A pick before the window exists (a popup outside the panel) builds the
    -- window first: a pane built without it has no parent and covers the screen.
    if not win then
        Options.WhenBuilt(function() if win then Options.Select(selType, id) end end)
        return
    end
    -- an editor not built yet builds first, and the pick lands after it
    local need = (selType == "layout" or selType == "group" or selType == "free" or selType == "bar"
        or selType == "multi" or selType == "defaults") and selType or nil
    if need and not Options.PaneBuilt(need) then
        Options.WhenPane(need, function() Options.Select(selType, id) end)
        return
    end
    -- a single pick ends a multi-selection (UI\AD_MultiSelect.lua)
    if Options.MultiSelect then Options.MultiSelect.OnSelect(selType) end
    -- Play on screen belongs to the bar being edited
    local B = NS.Bars
    if B and B.PreviewScreenOn and B.PreviewScreenOn()
        and not (selType == "bar" and B.PreviewScreenOn(id)) then
        B.PreviewScreenStop()
    end
    -- an icon's copy too: only an icon pane can keep it (its preview decides)
    if NS.IconScreen and selType ~= "group" and selType ~= "free" then NS.IconScreen.Stop() end
    ui.selType, ui.selId = selType, id
    if Options.LayoutFollow then Options.LayoutFollow.Sync(Options.LCLayoutId()) end
    -- the import target follows the rail: the layout last opened here
    if selType == "layout" or selType == "free" then
        ui.lastLayoutId = id
    elseif selType == "group" or selType == "bar" then
        local r = Store.Get(id)
        if r then ui.lastLayoutId = r.layoutId end
    end
    -- the grow arrows follow the editor's open group (no rebuild needed)
    if Engine and Engine.RefreshArrows then Engine.RefreshArrows() end
    -- id on "modules": the module whose page opens, nil for the cards
    if selType == "ie" or selType == "settings" or selType == "modules" or selType == "newlayout"
        or selType == "home" or selType == "defaults" then
        ShowPane(selType)
        RefreshAll()
        return
    end
    if selType == "group" then
        if ui.grpMode ~= "ico" and ui.grpMode ~= "rem" then ui.grpMode = "grp" end
        local g = Store.Get(id)
        if g then ExpandedSet()[g.layoutId] = true end
    elseif selType == "bar" then
        local b = Store.Get(id)
        if b then ExpandedSet()[b.layoutId] = true end
    elseif selType == "free" then
        ExpandedSet()[id] = true
    end
    ShowPane(selType == "layout" and "layout" or selType == "group" and "group"
        or selType == "free" and "free" or selType == "bar" and "bar"
        or selType == "multi" and "multi" or "empty")
    RefreshAll()
end

-- After creating a bar, or from its on-screen Edit chip, land on its editor.
function Options.SelectBarHome(rec)
    Options.Select("bar", rec.id)
end

local function RefreshPane()
    if not win or not win:IsShown() then return end
    -- a look tab open before its rows exist (they build on the tab's pick)
    local lt = ui.layoutTab
    if ui.selType == "layout" and (lt == "Icon Looks" or lt == "Group Looks" or lt == "Bar Looks")
        and not Options.PaneBuilt("looks") then
        Options.WhenPane("looks", RefreshPane)
        return
    end
    if ui.selType == "layout" then RefreshLayoutPane()
    elseif ui.selType == "group" then RefreshGroupPane()
    elseif ui.selType == "free" then RefreshFreePane()
    elseif ui.selType == "bar" then RefreshBarPane()
    elseif ui.selType == "multi" then
        if Options.MultiSelect then Options.MultiSelect.Refresh() end
    elseif ui.selType == "settings" then settingsPage:Refresh()
    elseif ui.selType == "modules" then
        if Options.Modules then Options.Modules.Refresh() end
    elseif ui.selType == "defaults" then
        if Options.Defaults then Options.Defaults.Refresh() end
    elseif ui.selType == "ie" then IE.Refresh()
    elseif ui.selType == "newlayout" and NS.NewLayout then NS.NewLayout.Refresh()
    elseif ui.selType == "home" and Options.Home then Options.Home.Refresh() end
    -- after the pane: it can re-pick the icon it shows
    if Engine and Engine.RefreshEditing then Engine.RefreshEditing() end
end

RefreshAll = function()
    if not win or not win:IsShown() then return end
    -- the open probe times every refresh (Core\AD_Perf.lua)
    local P = NS.Perf
    local t0 = P and P.openRec and debugprofilestop()
    RefreshRail()
    PaintAddonRows()
    RefreshPane()
    -- the search results follow a resize like every other pane
    local S = Options.Search
    if S and S.showing and S.page then AT.LayoutPage(S.page) end
    -- a pick made while folded names itself on the title bar
    if Options.Fold then Options.Fold.Sync() end
    if t0 then P.OpenNote("rf", debugprofilestop() - t0) end
end
Options.RefreshAll = function() RefreshAll() end
-- the layout whose Load Conditions page is open, or nil (UI\AD_LayoutFollow.lua)
function Options.LCLayoutId()
    return (ui.selType == "layout" and ui.layoutTab == "Load Conditions") and ui.selId or nil
end
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
        settings = "Settings", modules = "Modules", template = "Template" },
    -- result order among equal matches: the open editor's family first
    FAM_RANK = { icon = 1, group = 2, bar = 3, layout = 4, settings = 5, modules = 6, template = 7 },
    KIND_WORD = {
        icon = { spell = "spell icons", aura = "aura icons", trinket = "trinket icons",
            item = "item icons", timer = "custom icons", totem = "totem icons",
            ammo = "ammo icons", enchant = "enchant icons", stance = "stance icons",
            special = "Arc Proc icons" },
        bar = { cooldown = "cooldown bars", aura = "aura bars", timer = "custom bars",
            stack = "stack bars", swing = "swing bars", resource = "resource bars", cast = "castbars",
            health = "health bars", enchant = "enchant bars", range = "range bars",
            text = "text elements", texture = "textures", wheel = "wheels", special = "Arc Proc bars", sound = "sounds" },
        group = { aura = "aura groups", cooldown = "CD groups", reminder = "reminder groups" },
    },
    -- the ui fields a sample walk moves (put back by RestoreUI)
    UI_KEYS = { "selType", "selId", "selIconId", "grpMode", "layoutTab",
        "grpTab", "grpSec", "grpPosSec", "icoTab", "barTab" },
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
    if type(d.itemIDs) == "table" then
        for _, v in ipairs(d.itemIDs) do add(v) end
    end
    if type(d.spellAlts) == "table" then
        for _, v in ipairs(d.spellAlts) do add(v) end
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
                -- a Reminder group's members are its reminders and aura reminders
                local kids = (m.groupKind == "reminder") and Store.GroupMembers(m) or Store.IconsOf(m)
                for _, ic in ipairs(kids) do
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
    if r.type == "group" then
        if r.groupKind == "aura" or r.groupKind == "reminder" then return r.groupKind end
        return "cooldown"
    end
    if r.type == "icon" then return r.kind or "spell" end
    if r.type == "bar" then return r.barKind or "cooldown" end
    return "layout"
end

-- Records sharing a key draw the same rows: an icon's kind and its home (free,
-- group member, aura-group member, or one its aura group packs), a bar's kind
-- and mode.
function Options.Search.KeyOf(r)
    if r.type == "icon" then
        local ag, packed = InAuraGroup(r)
        local home = r.groupId and (ag and (packed and ":agp" or ":ag") or ":g") or ":f"
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
    if fam == "bar" then
        -- never the multi proxy: a jump lands on one bar
        local b = SelBar()
        return (b and not b._adMulti) and b or nil
    end
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
    -- a block that asks for it is found by its own words (a text's "Box
    -- width"); a card's short words keep the full name as search text
    if m then return m.label or m.def.label or m.field end
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
    -- a card (AT.Card) names itself in its header, in its own words
    if sec.card then return sec.card.title:GetText() end
    -- a section titled " " (the right half of a pair) is named for the search
    if sec.searchTitle then return sec.searchTitle end
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
        -- the tabs this group's kind shows (a Reminder group has its own)
        tabs = (src.tabsFor and src.tabsFor(rec)) or src.tabs
        setTab = function(t) ui.grpTab = t end
        setSub = function(t, s)
            if t == "Position" then ui.grpPosSec = s else ui.grpSec = s end
        end
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
    -- a panel pick (the Conditions tab's state and effect) stands aside, so
    -- every block a sample has is walked
    local was = S.indexing
    S.indexing = true
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
    S.indexing = was
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
    -- a switch outside the schema (a module's) names itself on the dep
    local name = (fdef and fdef.label) or d.label or d.field
    local function word(v)
        local L = fdef and fdef.labels
        return tostring((L and L[v]) or v)
    end
    if d.nonempty then return "shows when " .. name .. " is set" end
    if d.notValue ~= nil then return "shows when " .. name .. " is not " .. word(d.notValue) end
    if d.min ~= nil then return "shows when " .. name .. " is " .. d.min .. " or more" end
    if d.listMin ~= nil then return "shows when " .. name .. " holds " .. d.listMin .. " numbers or more" end
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
    local set = Options.SEARCH_SRC and Options.SEARCH_SRC.settings
    if set and set.page then
        S.WalkPage(set.page, function(row, sec) visit("settings", nil, row, sec, nil, nil) end)
    end
    -- the Modules page (UI\AD_Modules.lua): its cards, found by name and by the
    -- words of their line, then each module's rows under "Modules > <module>";
    -- e.mod names the module page the jump opens
    if Options.Modules then
        Options.Modules.SearchWalk(function(row, sec, sub, words, key)
            visit("modules", nil, row, sec, "Modules", sub)
            local se, re = idx.bySec[sec], idx.byRow[row]
            if se then se.mod = key end
            if re then re.mod, re.words = key, words end
        end)
    end
    -- the Add window's ready-made Custom Bars (UI\AD_CustomOptions.lua): no
    -- row of an editor, found by name, class and line; the jump opens the Add
    -- window with the template picked
    local CO = Options.Custom
    for _, t in ipairs(CO and CO.Templates and CO.Templates() or {}) do
        local e = new("template", nil, nil, "Add", "Custom Bar", t.name, nil)
        e.tpl, e.words = t.key, ((t.class or "") .. " template " .. (t.tip or ""))
    end
    for _, e in ipairs(idx.list) do
        e.path = S.PathOf(e)
        e.note = S.NoteOf(e, idx.famKinds[e.fam])
        -- a section entry flashes its first row; that row's dep is not the
        -- section's
        e.dep = (e.row and not e.isSection) and S.DepNote(e.row) or nil
        -- a setting on a row of several (an effect editor's) has its own
        if e.dep == nil and e.row and not e.isSection and e.row._adDepNoteFor then
            e.dep = e.row._adDepNoteFor(e.label, e.recs[1])
        end
        e.hay = (e.label .. " " .. e.path .. (e.words and (" " .. e.words) or "")):lower()
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
    -- an old QOL pick is the Modules page now
    if ui.selType == "qol" then ui.selType, ui.selId = "modules", nil end
    local t = ui.selType
    if t == "layout" or t == "group" or t == "free" or t == "bar" or t == "multi"
        or t == "ie" or t == "settings" or t == "modules" or t == "home" then
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
        -- the settings search walks every editor: the first one builds them
        if not Options.PaneBuilt("all") then
            Options.WhenPane("all", function() S.Changed() end)
            return
        end
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
    if e.tpl then
        S.ClearBox()
        Options.OpenAddTemplate(e.tpl)
        return
    end
    local rec
    -- the addon pages have no record: Settings, and Modules (a card, or a
    -- module's page when e.mod names one)
    local addonPage = e.fam == "settings" or e.fam == "modules"
    if not addonPage then
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
    if addonPage then
        Options.Select(e.fam, e.mod)
    elseif e.fam == "layout" then
        ui.layoutTab = e.tab
        ExpandedSet()[rec.id] = true
        Options.Select("layout", rec.id)
    elseif e.fam == "group" then
        ui.grpMode, ui.grpTab = "grp", e.tab
        if e.sub and e.tab == "Position" then ui.grpPosSec = e.sub
        elseif e.sub then ui.grpSec = e.sub end
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
    -- so does a More options fold holding it
    if e.row._adFold then e.row._adFold:Open() end
    -- and the panel pick the row waits on (SectionRows' opts.reveal)
    local m = e.row._adMeta
    if m and m.reveal then m.reveal() end
    -- a row holding several settings opens the one the hit names (the
    -- Conditions table's editor under a state row)
    if e.row._adRevealFor then e.row._adRevealFor(e.label) end
    AT.LayoutPage(pg)
    local target = e.row
    -- a row in a switched-off card shows dimmed: its switch flashes instead
    local card = target._adCard
    if card and not card:On() then target = card.head end
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
    b.name:SetFont(AT.FONT, 12, "")
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    b.where = b:CreateFontString(nil, "OVERLAY")
    b.where:SetFont(AT.FONT, 10, "")
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
                b.thumb:SetGroup(Options.GROUP_COLORS[rec.groupKind] or YELLOW)
                GroupPill(b.pill, rec.groupKind)
            elseif rec.type == "bar" then
                b.thumb:SetBar(rec, 22, BarTexture(rec))
                BarPill(b.pill, rec.barKind, rec.barMode)
            elseif rec.type == "icon" then
                b.thumb:SetIcon(Factory.GetTexture(rec))
                b.pill:Set(Options.IconPillText(rec.kind))
            elseif rec.type == "reminder" then
                b.thumb:SetIcon(Factory.GetTexture(rec))
                b.pill:Set("Reminder", Options.GROUP_COLORS.reminder)
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
    fs:SetFont(AT.FONT, 10, "")
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

-- Set before the first window is created so it opens at the saved scale, and
-- only when one is saved: a fallback here would override AT.uiScale's default.
function Options.ApplySavedScale()
    local savedScale = Store.GetSetting("uiScale")
    if savedScale then AT.SetUIScale(savedScale) end
end

-- The loader (UI\AD_OptionsLoader.lua) replaces these to run the first build in
-- slices; without it the build runs straight through.
function Options.BuildYield() end
function Options.BuildStep() end

-- The light panes build with the window; the heavy ones (`lazy`: the layout
-- pane, the editors, the layout's look tabs) on their first pick, each after
-- what it needs: the free pane shows the group pane's icon editor, the multi
-- pane hosts both editors' pages, the look tabs mirror the editors' blocks,
-- and `all` (the settings search walks every editor) is them all. Without the
-- loader (the harnesses) every pane builds with the window, as before.
local PANE_BUILD = {
    empty = { BuildEmptyPane },
    home = { function() Options.BuildHomePane() end },
    newlayout = { function() Options.BuildNewLayoutPane() end },
    layout = { BuildLayoutPane, lazy = true },
    group = { BuildGroupPane, lazy = true },
    free = { BuildFreePane, lazy = true, needs = { "group" } },
    bar = { BuildBarPane, lazy = true },
    multi = { function() Options.BuildMultiPane() end, lazy = true, needs = { "group", "bar" } },
    looks = { function() Options.BuildLayoutLooks() end, lazy = true, needs = { "layout", "group", "bar" } },
    settings = { BuildSettingsPane },
    modules = { function() Options.BuildModulesPane() end },
    -- every item's defaults: its kind pages mirror the item editors' blocks
    defaults = { function() Options.BuildDefaultsPane() end, lazy = true, needs = { "group", "bar" } },
    ie = { BuildIEPane },
    all = { lazy = true, needs = { "layout", "group", "free", "bar", "multi", "looks" } },
}
-- the build order of old, kept for the panes that build together
local PANE_ORDER = { "empty", "home", "newlayout", "layout", "group", "free", "bar", "multi", "looks",
    "settings", "modules", "defaults", "ie" }
local paneBuilt = {}    -- name -> "building" | true

-- Builds a pane, and what it needs, once. The page on screen stays while it
-- builds: the new pane's root hides the moment it is stored (`panes`), so
-- nothing half-built shows and the area is never empty.
function Options.EnsurePane(name)
    local p = PANE_BUILD[name]
    if not p or paneBuilt[name] then return end
    paneBuilt[name] = "building"
    for _, dep in ipairs(p.needs or {}) do Options.EnsurePane(dep) end
    if p[1] then
        -- the pane under way, for the open probe (Core\AD_Perf.lua)
        local was = Options.buildingPane
        Options.buildingPane = name
        p[1]()
        Options.buildingPane = was
        if panes[name] then panes[name]:Hide() end
    end
    paneBuilt[name] = true
end

function Options.PaneBuilt(name) return paneBuilt[name] == true end

-- the panes still to build for `name`, what they need first
local function PanePlan(name, out, seen)
    out, seen = out or {}, seen or {}
    if seen[name] or paneBuilt[name] then return out end
    seen[name] = true
    local p = PANE_BUILD[name]
    for _, dep in ipairs(p and p.needs or {}) do PanePlan(dep, out, seen) end
    out[#out + 1] = name
    return out
end

-- the background build: picks waiting on a pane ({ name, fn }, in order),
-- the build order, the loading line
local PB = { want = {} }

-- Runs fn once pane `name` exists. Inside a build, or with no loader, it
-- builds now. Otherwise the pick waits in `PB.want` while the background
-- build (Options.Prebuild) does that pane first in full slices; the page on
-- screen stays meanwhile, under a thin loading line.
function Options.WhenPane(name, fn)
    local L = Options.Loader
    if L and L.Busy() and not L.InBuild() and not L.Background() then
        L.Then(function() Options.WhenPane(name, fn) end)
        return
    end
    -- never a pane before its window (see Options.Select)
    if not win then
        Options.WhenBuilt(function() if win then Options.WhenPane(name, fn) end end)
        return
    end
    if paneBuilt[name] == true then
        fn()
    elseif not L or L.InBuild() then
        Options.EnsurePane(name)
        fn()
    else
        PB.want[#PB.want + 1] = { name = name, fn = fn }
        Options.LoadLine(true)
        Options.Prebuild(true)
    end
end

-- The editors' panes the window builds in the background once it shows, in
-- the order a player usually opens them.
PB.ORDER = { "layout", "group", "bar", "free", "multi", "looks" }

function PB.Next()
    for _, w in ipairs(PB.want) do
        if paneBuilt[w.name] ~= true and PANE_BUILD[w.name] then return w.name end
    end
    for _, n in ipairs(PB.ORDER) do
        if paneBuilt[n] ~= true then return n end
    end
end

-- After each slice, outside the build: the picks whose pane now exists open.
function PB.RunWanted()
    if #PB.want == 0 then return end
    local run, still = {}, {}
    for _, w in ipairs(PB.want) do
        if paneBuilt[w.name] == true then run[#run + 1] = w.fn else still[#still + 1] = w end
    end
    if #run == 0 then return end
    PB.want = still
    if #still == 0 then
        Options.LoadLine(false)
        if Options.Loader then Options.Loader.Calm() end
    end
    for _, f in ipairs(run) do f() end
end

-- The window shut: a pick still waiting on its pane is dropped, the build goes on.
function PB.Drop()
    PB.want = {}
    Options.LoadLine(false)
    if Options.Loader then Options.Loader.Calm() end
end

-- Builds every pane still missing, a small slice a frame (none in combat);
-- hurry: a pick waits, so full slices until it opens.
function Options.Prebuild(hurry)
    local L = Options.Loader
    if not (L and win) then return end
    L.OnSlice, L.OnCancel = PB.RunWanted, PB.Drop
    if L.Busy() then
        if hurry and L.Background() then L.Hurry() end
        return
    end
    if not PB.Next() then return end
    L.Start(function()
        while true do
            local n = PB.Next()
            if not n then break end
            for _, p in ipairs(PanePlan(n)) do Options.EnsurePane(p) end
            Options.BuildYield(true)
        end
    end, true, true)
    if hurry then L.Hurry() end
end

-- While a pick waits on its pane, the page on screen is dimmed under a
-- "Loading" box with a sweeping bar, so the window never looks frozen. A thin
-- line at the content's top edge was missed (the header drew over it). The
-- veil waits a beat before it shows, so a pane built at once never flashes it;
-- it takes the clicks meant for the stale page, sits above every pane's
-- frames, and goes with the window (it is the window's child, and PB.Drop
-- clears it on a cancel).
PB.VEIL_DELAY, PB.VEIL_W, PB.VEIL_H = 0.12, 240, 64
function Options.LoadLine(on)
    if not (win and content) then return end
    if on and not PB.veil then
        local v = CreateFrame("Frame", nil, win)
        v:SetAllPoints(content)
        v:SetFrameLevel(math.min(9000, win:GetFrameLevel() + 500))
        v:EnableMouse(true)
        v:EnableMouseWheel(true)
        v:SetScript("OnMouseWheel", function() end)
        local dim = v:CreateTexture(nil, "BACKGROUND")
        dim:SetAllPoints(v)
        dim:SetColorTexture(COL.bg[1], COL.bg[2], COL.bg[3], 0.6)
        local box = CreateFrame("Frame", nil, v, "BackdropTemplate")
        box:SetSize(PB.VEIL_W, PB.VEIL_H)
        box:SetPoint("CENTER", v, "CENTER", 0, 0)
        AT.Skin(box, COL.bg, COL.line2)
        local fs = box:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 12, "")
        fs:SetPoint("TOPLEFT", 12, -12)
        fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        fs:SetText("Loading this page")
        local track = CreateFrame("Frame", nil, box, "BackdropTemplate")
        track:SetPoint("BOTTOMLEFT", 12, 12)
        track:SetPoint("BOTTOMRIGHT", -12, 12)
        track:SetHeight(8)
        AT.Skin(track, COL.well, COL.line)
        local seg = track:CreateTexture(nil, "ARTWORK")
        seg:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        -- the track's inner width, from the box's own numbers (law 3: no rect read)
        local inner = PB.VEIL_W - 24 - 2
        local t = 0
        v:SetScript("OnShow", function(self)
            t = 0
            self:SetAlpha(0)
        end)
        -- runs only while shown, which is only while a pick waits
        v:SetScript("OnUpdate", function(self, el)
            t = t + el
            if t < PB.VEIL_DELAY then return end
            self:SetAlpha(1)
            local p = ((t - PB.VEIL_DELAY) % 1.1) / 1.1
            local sw = math.floor(inner * 0.3)
            local x = math.floor((inner + sw) * p) - sw
            local left, right = math.max(0, x), math.min(inner, x + sw)
            seg:ClearAllPoints()
            seg:SetPoint("TOPLEFT", track, "TOPLEFT", 1 + left, -1)
            seg:SetSize(math.max(1, right - left), 6)
            seg:SetShown(right > left)
        end)
        v:Hide()
        PB.veil = v
    end
    if PB.veil then PB.veil:SetShown(on == true) end
end

local built
local function Build()
    if built then return end
    built = true
    Options.ApplySavedScale()
    win = AT.CreateWindow("ArcUIv2Options", {
        w = 1020, h = Options.MAIN_H, minW = 820, minH = 620, maxW = 1500, maxH = 1200,
        title = AT.Brand("Arc", " Auras"),
        -- The toc's Version, so the title matches the release.
        version = C_AddOns and C_AddOns.GetAddOnMetadata
            and C_AddOns.GetAddOnMetadata(ADDON, "Version") or nil,
        onResize = function() RefreshAll() end,
    })
    -- the fold to the title bar (UI\AD_WindowFold.lua); the bounds above, restored on unfold
    if Options.Fold then Options.Fold.Attach(win, { 820, 620, 1500, 1200 }) end
    -- Window open = edit mode (drag and Edit chips); closed = click-through again.
    win:HookScript("OnShow", function()
        -- the open probe's step list (Core\AD_Perf.lua)
        local PF = NS.Perf
        if PF and PF.marking then PF.Mark("window shows, edit mode turns on") end
        Engine.SetEditMode(true)
        if PF and PF.marking then PF.Mark("edit mode on") end
        if Options.LayoutFollow then Options.LayoutFollow.Sync(Options.LCLayoutId()) end
        -- a layout pack version the player has not been shown: open on Home
        -- (UI\AD_Home.lua)
        if Options.Home then Options.Home.OnOpen() end
        if PF and PF.marking then PF.Mark("window show hook done") end
        -- the editors' panes build in the background, so a first pick finds
        -- its page ready (a beat later: the open itself stays light)
        C_Timer.After(0.5, function()
            if win and win:IsShown() then Options.Prebuild() end
        end)
    end)
    win:HookScript("OnHide", function()
        PB.Drop()
        -- closing the window leaves an open Load Conditions page too
        if Options.LayoutFollow then Options.LayoutFollow.Sync(nil) end
        -- before edit mode ends: its rebuild must show the real bar and icon again
        if NS.Bars and NS.Bars.PreviewScreenStop then NS.Bars.PreviewScreenStop() end
        if NS.IconScreen then NS.IconScreen.Stop() end
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
    search:SetFont(AT.FONT, 11, "")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY")
    hint:SetFont(AT.FONT, 10, "")
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

    -- Home, the front page (UI\AD_Home.lua), under the search box
    -- a raised button like a layout's header card, with a house, so it reads
    -- as a place to go even when it is not the open page
    local home = CreateFrame("Button", nil, rail, "BackdropTemplate")
    home:SetHeight(28)
    home:SetPoint("TOPLEFT", 6, -34)
    home:SetPoint("TOPRIGHT", -6, -34)
    AT.Skin(home, COL.panel, COL.line)
    home.name = home:CreateFontString(nil, "OVERLAY")
    home.name:SetFont(AT.FONT, 13, "")
    home.name:SetPoint("LEFT", 29, 0)
    home.name:SetText("Home")
    if Options.Home then
        home.glyph = Options.Home.MakeHouse(home)
        home.glyph:SetPoint("LEFT", 9, 0)
    end
    RailChrome(home)
    PaintRailRow(home, false, "layout")
    home:SetScript("OnClick", function() Options.Select("home") end)
    railAddonRows.home = home

Options.BuildYield()
    local cat = rail:CreateFontString(nil, "OVERLAY")
    cat:SetFont(AT.FONT, 9, "")
    cat:SetPoint("TOPLEFT", 10, -70)
    cat:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cat:SetText("LAYOUTS")
    -- the View, on the caption's line: how the list below shows (RailView)
    local viewDD = AT.MakeDropdown(win, rail, nil, Options.RailViewItems,
        function() return RailView() or "all" end,
        function(v) Store.SetSetting("railView", (v ~= "all") and v or nil) end,
        function() RefreshAll() end)
    viewDD:SetPoint("TOPRIGHT", -6, -65)
    AT.Tooltip(viewDD, "View", "Everything, only what loads on this character, a section per class, or one class's items with what every class shares.")
    local viewWord = rail:CreateFontString(nil, "OVERLAY")
    viewWord:SetFont(AT.FONT, 9, "")
    viewWord:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    viewWord:SetPoint("RIGHT", viewDD, "LEFT", -5, 0)
    viewWord:SetText("View")
    Options.railView = viewDD

    -- The layouts tree scrolls from under the caption down to the ADDON foot's
    -- hairline (the foot is 130 tall); RefreshRail fills it, Options.RailFit sizes it.
    local railHost, railList = AT.MakeScroll(rail)
    railHost:SetPoint("TOPLEFT", 0, -88)
    railHost:SetPoint("BOTTOMRIGHT", -6, 131)
    railHost:HookScript("OnSizeChanged", function(_, w)
        if w and w > 0 then railList:SetWidth(w - AT.ScrollExtra()) end
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
        s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
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
    foot:SetHeight(130)
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
Options.BuildYield()
    local acat = foot:CreateFontString(nil, "OVERLAY")
    acat:SetFont(AT.FONT, 9, "")
    acat:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    acat:SetPoint("BOTTOMLEFT", 9, 111)
    acat:SetText("ADDON")
    local function AddonRow(label, paneName, yOff)
        local r = CreateFrame("Button", nil, rail, "BackdropTemplate")
        r:SetHeight(24)
        r:SetPoint("BOTTOMLEFT", 6, yOff)
        r:SetPoint("BOTTOMRIGHT", -6, yOff)
        r:SetFrameLevel(rail:GetFrameLevel() + 20)
        AT.Skin(r, COL.well, COL.well)
        r.name = r:CreateFontString(nil, "OVERLAY")
        r.name:SetFont(AT.FONT, 12, "")
        r.name:SetPoint("LEFT", 8, 0)
        r.name:SetText(label)
        RailChrome(r)
        PaintRailRow(r, false, "child")
        r:SetScript("OnClick", function() Options.Select(paneName) end)
        railAddonRows[paneName] = r
        return r
    end
    AddonRow("Modules", "modules", 84)
    AddonRow("Import / Export", "ie", 58)
    -- every item's defaults on one page (UI\AD_DefaultsOptions.lua), NEW for a version
    local defRow = AddonRow("Defaults", "defaults", 32)
    if Options.Defaults then Options.Defaults.RailRow(defRow) end
    AddonRow("Settings", "settings", 6)

    -- The panes that build with the window, in the old order; each is one step
    -- of the loading bar. With the loader the heavy ones wait for their pick.
    local L = Options.Loader
    local first = {}
    for _, name in ipairs(PANE_ORDER) do
        if not (L and PANE_BUILD[name].lazy) then first[#first + 1] = name end
    end
    Options.BuildStep(0, #first)
    for i, name in ipairs(first) do
        Options.EnsurePane(name)
        Options.BuildStep(i, #first)
    end
    AT.AddDiscordFooter(win, "ArcUIv2DiscordCopy")
    -- the sidebar's rows, one a slice here: made all at once by the window's
    -- first refresh, they were its one long frame
    for i = 1, #BuildRailList() do
        RailRow(i)
        Options.BuildYield()
    end

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

    -- The first open after a login or /reload lands on Home; later opens stay
    -- where you were.
    local layouts = Store.Layouts()
    if Options.Home then
        Options.Select("home")
    elseif layouts[1] then
        Options.Select("layout", layouts[1].id)
    else
        ShowPane("empty")
    end
end

-- Runs fn once the window exists. With the loader the first build runs in
-- slices and fn waits for its end; without it the build runs now.
function Options.WhenBuilt(fn)
    local L = Options.Loader
    -- the background build runs only once the window is built: it waits on nothing
    if L and L.Busy() and not L.Background() then
        L.Then(fn)
    elseif L and not built then
        L.Start(Build)
        L.Then(fn)
    else
        Build()
        fn()
    end
end

-- The window never opens in combat: a press then waits and opens it as combat
-- ends, and a window open when combat starts closes. The game's error line
-- says so; never chat.
function Options.CombatBlocked()
    if not InCombatLockdown() then return false end
    Options._openAfterCombat = true
    if UIErrorsFrame then UIErrorsFrame:AddMessage("Arc Auras opens when combat ends.", 1, 0.82, 0) end
    return true
end

function Options.Toggle()
    local L = Options.Loader
    -- A second press while the first open loads closes it; the build
    -- finishes quietly. The background build is no reason to wait: a press
    -- opens or closes the window as usual (closing drops a waiting pick).
    if L and L.Busy() and not L.Background() then
        L.Cancel()
        if win and win:IsShown() then win:Hide() end
        return
    end
    if not (win and win:IsShown()) and Options.CombatBlocked() then return end
    Options.WhenBuilt(function()
        if win:IsShown() then
            win:Hide()
        elseif not Options.CombatBlocked() then
            -- a build that spans frames can end in combat
            win:Show()
            RefreshAll()
        end
    end)
end

function Options.Open()
    if Options.CombatBlocked() then return end
    Options.WhenBuilt(function()
        if Options.CombatBlocked() then return end
        if not win:IsShown() then win:Show() end
        RefreshAll()
    end)
end

if Events then
    Events.On("PLAYER_REGEN_DISABLED", "adoptcombat", function()
        if not (win and win:IsShown()) then return end
        win:Hide()
        if addWin and addWin:IsShown() then addWin:Hide() end
        if UIErrorsFrame then UIErrorsFrame:AddMessage("Arc Auras closed for combat.", 1, 0.82, 0) end
    end)
    Events.On("PLAYER_REGEN_ENABLED", "adoptcombat", function()
        if not Options._openAfterCombat then return end
        Options._openAfterCombat = nil
        -- a beat after the edge, so the combat flags have settled
        C_Timer.After(0.1, function()
            if not InCombatLockdown() then Options.Open() end
        end)
    end)
end
