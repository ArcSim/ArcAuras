-- AD_DefaultsOptions: the Defaults page. Every item's defaults by family and
-- kind (the Add window's tabs), each kind's page drawn from its editor's look
-- blocks (Options.LOOK_BLOCKS) over a defaults proxy (Store.DefaultsProxy),
-- one sub-tab per page. A change asks whether the items you have change too.
-- AD_Options owns the pane and its header: Fill as the pane builds, Refresh
-- whenever it shows, RailRow / PaintRail for the sidebar row, and AskPopup for
-- the editors' Save as Default and Forget default.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store, Schema = NS.AT, NS.Store, NS.Schema
local COL = AT.COL

local D = { pages = {}, used = {}, epoch = 0, okCache = {}, looseCache = {} }
Options.Defaults = D

D.LIST_W, D.HEAD_H, D.ROW_H = 176, 52, 24
D.NEW_KEY = "rail:defaults"
D.STATE_TITLE = "How it looks in each state"
-- What the page leaves out on purpose. tools\t_addefaults.lua compares every
-- row each editor shows for each kind with this page and fails on any other
-- gap: a new look reaches the page through Options.LookBlock (with its sub-tab),
-- or it is named here with why.
-- Per item, never a default: an icon's nudge inside its cell.
D.PER_ITEM = { icon = { position = { offsetX = true, offsetY = true } } }
-- The editor tabs whose rows are each item's own (what it tracks, its rules,
-- where it loads, a Reminder group's reminders).
D.PER_ITEM_TABS = { Tracking = true, Triggers = true, ["Load Conditions"] = true, Reminders = true }
-- Rows an editor draws through its own control, with no plain row to offer.
D.NOT_ON_PAGE = {
    iconGroup = { arrangement = { alignment = "the editor's own pick, in the words of the group's shape" } },
}
-- Kinds with no page, and why.
D.NOT_LISTED = {
    bar = { sound = "a Sound item plays what each one is set to: nothing to default",
        stack = "the old power-stack bar, no longer made" },
}

-- Words

local function K(name, one, many, title) return { name = name, one = one, many = many, title = title } end
D.WORDS = {
    icon = {
        spell = K("Spell Cooldown", "spell icon", "spell icons", "Spell icons"),
        aura = K("Aura", "aura icon", "aura icons", "Aura icons"),
        groupbuff = K("Group Buff", "group buff icon", "group buff icons", "Group buff icons"),
        item = K("Item", "item icon", "item icons", "Item icons"),
        trinket = K("Trinket", "trinket icon", "trinket icons", "Trinket icons"),
        totem = K("Totem / Guardian", "totem icon", "totem icons", "Totem icons"),
        ammo = K("Ammo", "ammo icon", "ammo icons", "Ammo icons"),
        enchant = K("Weapon Enchant", "enchant icon", "enchant icons", "Enchant icons"),
        stance = K("Stance", "stance icon", "stance icons", "Stance icons"),
        timer = K("Custom Icon", "Custom Icon", "Custom Icons", "Custom Icons"),
        special = K("Arc Proc icon", "Arc Proc icon", "Arc Proc icons", "Arc Proc icons"),
    },
    bar = {
        cooldown = K("Cooldown Bar", "cooldown bar", "cooldown bars", "Cooldown bars"),
        aura = K("Aura Bar", "aura bar", "aura bars", "Aura bars"),
        swing = K("Swing Bar", "swing bar", "swing bars", "Swing bars"),
        resource = K("Resource Bar", "resource bar", "resource bars", "Resource bars"),
        health = K("Health Bar", "health bar", "health bars", "Health bars"),
        cast = K("Castbar", "castbar", "castbars", "Castbars"),
        enchant = K("Weapon Enchant Bar", "enchant bar", "enchant bars", "Enchant bars"),
        range = K("Range Bar", "range bar", "range bars", "Range bars"),
        timer = K("Custom Bar", "Custom Bar", "Custom Bars", "Custom Bars"),
        text = K("Text", "text", "texts", "Texts"),
        texture = K("Texture", "texture", "textures", "Textures"),
        wheel = K("Wheel", "wheel", "wheels", "Wheels"),
        special = K("Arc Proc bar", "Arc Proc bar", "Arc Proc bars", "Arc Proc bars"),
    },
    iconGroup = {
        cooldown = K("CD Group", "CD group", "CD groups", "CD groups"),
        aura = K("Aura Group", "aura group", "aura groups", "Aura groups"),
        reminder = K("Reminder Group", "reminder group", "reminder groups", "Reminder groups"),
    },
}
D.FAMILY_WORDS = { icon = { "icon", "icons", "The icon" }, bar = { "bar", "bars", "The bar" },
    iconGroup = { "group", "groups", "The group" } }

function D.Words(family, kind)
    local w = D.WORDS[family] and D.WORDS[family][kind]
    if w then return w end
    local f = D.FAMILY_WORDS[family] or { "item", "items" }
    return K(kind or "?", f[1], f[2], f[2])
end

-- The families and kinds this client lists

function D.ProcsOn()
    local SO = Options.Special
    return SO ~= nil and SO.On ~= nil and SO.On() == true
end

function D.IconKinds()
    local out = { "spell", "aura", "groupbuff", "item", "trinket", "totem" }
    if NS.IsForever == true then out[#out + 1] = "ammo" end
    out[#out + 1] = "enchant"
    if NS.DriverStance then out[#out + 1] = "stance" end
    if NS.DriverCustom then out[#out + 1] = "timer" end
    return out
end

function D.BarKinds()
    local out = { "cooldown", "aura" }
    if C_SwingTimer then out[#out + 1] = "swing" end
    for _, k in ipairs({ "resource", "health", "cast", "enchant" }) do out[#out + 1] = k end
    if C_Spell and C_Spell.IsSpellInRange then out[#out + 1] = "range" end
    if NS.DriverCustom then out[#out + 1] = "timer" end
    return out
end

-- The Add window's tabs: a list of kinds (an All row heads a list of several),
-- and the kinds each family copies between (the proc kinds included).
function D.BuildTabs()
    local tabs = {}
    local function Tab(name, family, kinds, allKinds)
        local t = { name = name, entries = {} }
        for _, k in ipairs(kinds) do t.entries[#t.entries + 1] = { family = family, kind = k } end
        if allKinds and #allKinds > 1 then t.all = { family = family, kinds = allKinds } end
        tabs[#tabs + 1] = t
        return t
    end
    local procs = D.ProcsOn()
    local icons, bars = D.IconKinds(), D.BarKinds()
    local allIcons, allBars = {}, {}
    for _, k in ipairs(icons) do allIcons[#allIcons + 1] = k end
    for _, k in ipairs(bars) do allBars[#allBars + 1] = k end
    if procs then
        allIcons[#allIcons + 1] = "special"
        allBars[#allBars + 1] = "special"
    end
    Tab("Icons", "icon", icons, allIcons)
    Tab("Bars", "bar", bars, allBars)
    Tab("Groups", "iconGroup", Schema.GROUP_KINDS, Schema.GROUP_KINDS)
    if Options.TextAddRows then Tab("Texts", "bar", { "text" }) end
    if Options.TextureAddRows then Tab("Textures", "bar", { "texture" }) end
    if Options.WheelAddRows then Tab("Wheels", "bar", { "wheel" }) end
    if procs then
        tabs[#tabs + 1] = { name = "Arc Procs", entries = {
            { family = "icon", kind = "special" }, { family = "bar", kind = "special" } } }
    end
    D.pool = { icon = allIcons, bar = allBars, iconGroup = Schema.GROUP_KINDS }
    D.tabs = tabs
    return tabs
end

-- Selection

-- The page's picks, kept with the panel's own state for the session.
function D.State()
    local ui = Options.ui
    ui.defaults = ui.defaults or { pick = {}, etab = {}, esub = {} }
    return ui.defaults
end

function D.TabByName(name)
    for _, t in ipairs(D.tabs or {}) do
        if t.name == name then return t end
    end
    return D.tabs and D.tabs[1]
end

function D.EntryKey(e) return e.family .. ":" .. e.kind end

-- The open family tab, kind (nil on an All row) and the proxy its rows edit.
function D.Resolve()
    local s = D.State()
    local tab = D.TabByName(s.tab)
    if not tab then return nil end
    local pick = s.pick[tab.name]
    if tab.all and pick == "all" then
        return { tab = tab, family = tab.all.family, kinds = tab.all.kinds,
            px = Store.DefaultsAllProxy(tab.all.family, tab.all.kinds) }
    end
    local e = tab.entries[1]
    for _, x in ipairs(tab.entries) do
        if D.EntryKey(x) == pick then e = x end
    end
    return { tab = tab, entry = e, family = e.family, px = Store.DefaultsProxy(e.family, e.kind) }
end

-- The proxy the rows of `family` read now, nil while another family shows.
function D.Ctx(family)
    local c = D.cur
    if not (c and c.family == family) then return nil end
    local px = c.px
    if c.entry then px = Store.DefaultsProxy(c.entry.family, c.entry.kind) end
    -- its batch is answered Only new when the page closes (D.Leave)
    if px and px._adBatch then D.used[px._adBatch] = true end
    return px
end

-- The kinds a proxy speaks for.
local function KindsOf(px)
    return px._adKinds or { px._adKind }
end

-- Values

local ET
local function Same(a, b)
    ET = ET or Options.EditorTabs
    if ET then return ET.Same(a, b) end
    return a == b
end

-- A saved default that differs from the shipped value, on the kind or (All)
-- on any kind.
function D.Changed(family, px, section, field)
    for _, k in ipairs(Store.DefaultKinds(family, KindsOf(px), section, field)) do
        if Store.DefaultChanged(family, k, section, field) then return true end
    end
    return false
end

-- The kinds of an All row that read different values for a field.
function D.Mixed(family, px, section, field)
    if not px._adKinds then return false end
    local first, seen = nil, false
    for _, k in ipairs(Store.DefaultKinds(family, px._adKinds, section, field)) do
        local v = Store.Resolve(Store.DefaultsProxy(family, k), section, field)
        if not seen then first, seen = v, true
        elseif not Same(v, first) then return true end
    end
    return false
end

-- The shipped value for the row, or "by kind" where an All row's kinds differ.
function D.ArcValue(family, px, section, field)
    local kinds = Store.DefaultKinds(family, KindsOf(px), section, field)
    local v = Store.ArcDefault(family, kinds[1], section, field)
    for i = 2, #kinds do
        if not Same(Store.ArcDefault(family, kinds[i], section, field), v) then return nil, true end
    end
    return v, false
end

-- A value in its row's own words (a percent, a label, the empty pick's name).
function D.Fmt(def, v, field)
    local t = def.t
    if t == "bool" then return v and "On" or "Off" end
    if t == "num" or t == "int" then
        v = tonumber(v) or 0
        if def.input then
            return def.fmt and string.format(def.fmt, v) or tostring(v)
        end
        if t == "int" then return string.format("%d", math.floor(v + 0.5)) end
        if def.fmt then return string.format(def.fmt, v) end
        if (def.max or 1) <= 1 then return string.format("%.0f%%", v * 100) end
        if (def.step or 0.01) < 1 then return string.format("%.1f", v) end
        return string.format("%d", math.floor(v + 0.5))
    end
    if t == "enum" then return (def.labels and def.labels[v]) or tostring(v) end
    if t == "id" then return (tonumber(v) or 0) ~= 0 and tostring(v) or "None" end
    if t == "sound" then return (v and v ~= "") and tostring(v) or "None" end
    if t == "text" then
        if v == nil or v == "" then
            if def.media then return (Options.MEDIA_EMPTY and Options.MEDIA_EMPTY[field]) or "Flat" end
            if def.font then return "Default" end
            return "Empty"
        end
        return tostring(v)
    end
    return tostring(v)
end

-- A row and the fields its one control writes (a pick of two switches).
local function RowFields(m)
    local def = m.def
    local list = { m.field }
    if def.showPick then list[#list + 1] = def.showPick end
    if def.statePick then list[#list + 1] = def.statePick end
    if def.rangePick then list[#list + 1] = def.rangePick end
    return list
end

-- The shipped pick for a row of two switches, in the row's own words.
local function PickArc(family, px, m)
    local def, section = m.def, m.section
    local function A(f) return (D.ArcValue(family, px, section, f)) end
    if def.showPick then
        local w = (def.pickWords and def.pickWords(px))
            or { up = "While the aura is up", missing = "While the aura is missing" }
        if A(m.field) == true then return w.up end
        if A(def.showPick) == true and w.missing then return w.missing end
        return "Always"
    end
    local one, two = Options.StateWords(px)
    local a, b = A(m.field) ~= false, A(def.statePick) ~= false
    if a and b then return "Always" end
    if a then return "While " .. one end
    if b then return "While " .. two end
    return "Never"
end

function D.RowChanged(family, px, m)
    for _, f in ipairs(RowFields(m)) do
        if D.Changed(family, px, m.section, f) then return true end
    end
    return false
end

-- Writing

-- The batch a proxy's changes ask under; the page remembers it to answer
-- Only new when it closes.
function D.Batch(px)
    local name = px and px._adBatch
    if name then D.used[name] = true end
    return name
end

-- Every open batch of the page answered Only new.
function D.Leave()
    for name in pairs(D.used) do Store.AnswerDefaults(name, false) end
    wipe(D.used)
end

-- A field back to the shipped value, on the kind or every kind of an All row.
function D.ResetField(family, px, section, field)
    local batch = D.Batch(px)
    for _, k in ipairs(Store.DefaultKinds(family, KindsOf(px), section, field)) do
        Store.SetDefaultValue(family, k, section, field, nil, batch)
    end
end

-- Popups

local function Popup(key, spec)
    StaticPopupDialogs[key] = StaticPopupDialogs[key] or {
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local d = StaticPopupDialogs[key]
    for k, v in pairs(spec) do d[k] = v end
    StaticPopup_Show(key)
end

-- Yes / No before an action that resets values.
function D.Confirm(text, onYes)
    Popup("ARCUIV2_DEFAULTS_CONFIRM", { text = text, button1 = YES, button2 = NO,
        OnAccept = function() onYes() end })
end

-- The ask in words: "N changes. M spell icons use the old values."
function D.AskText(p, w)
    local c, n = p.changes, p.items
    return c .. (c == 1 and " change. " or " changes. ") .. n .. " " .. (n == 1 and w.one or w.many)
        .. (n == 1 and " uses" or " use") .. " the old " .. (c == 1 and "value." or "values.")
end

-- The words for a batch's items: the kind's while it reached one kind.
function D.BatchWords(family, kind, p)
    if kind and p and p.kinds <= 1 then return D.Words(family, kind) end
    local f = D.FAMILY_WORDS[family] or { "item", "items" }
    return K(f[2], f[1], f[2], f[2])
end

-- The editors' Save as Default and Forget default: the same question as the
-- page, in a popup. No answer (Escape) is Only new.
function D.AskPopup(batch, rec)
    local p = Store.DefaultsPending(batch)
    if not p then return end
    local w = D.BatchWords(Store.FamilyOf(rec), Store.KindOf(rec), p)
    Popup("ARCUIV2_DEFAULTS_ASK", {
        text = D.AskText(p, w) .. "\n\nChange them too, or keep the new default for new " .. w.many .. " only?",
        button1 = "Change them too", button2 = "Only new ones",
        OnAccept = function() Store.AnswerDefaults(batch, true) Options.RefreshAll() end,
        OnCancel = function() Store.AnswerDefaults(batch, false) end,
    })
end

-- Gates

-- A block's own gate on one kind's proxy: its kinds and when(rec), widened
-- over every registration (Options.LookBlock).
local function GateOK(b, px, kind)
    if b.open or not b.gates then return true end
    for _, g in ipairs(b.gates) do
        local ko = g.kindOnly
        local okK = (not ko) or ko == kind or (type(ko) == "table" and ko[kind] == true)
        if okK and ((not g.when) or g.when(px) == true) then return true end
    end
    return false
end

-- A row the proxy would show: its gates, then its switch (dep).
local function RowCanShow(px, family, section, def)
    if not Options.FieldShows(px, family, section, def) then return false end
    local dep = def.dep
    if not dep then return true end
    if dep.field then return Options.DepOK(px, family, section, dep) end
    for _, d in ipairs(dep) do
        if not Options.DepOK(px, family, section, d) then return false end
    end
    return true
end

-- A block shows on the proxy: a push section of a kind it serves, its gate,
-- and a row that shows (loose: one that would with its switch on, for the
-- filter, which shows a changed row whatever its switch). Kept per layout
-- pass (D.epoch).
function D.BlockOK(family, b, px, loose)
    local cache = loose and D.looseCache or D.okCache
    local c = cache[b]
    if c and c.epoch == D.epoch and c.px == px then return c.ok end
    local ok = false
    local sec = Schema[family] and Schema[family][b.section]
    if sec and sec.push then
        local any = false
        for _, k in ipairs(KindsOf(px)) do
            local kp = px._adKinds and Store.DefaultsProxy(family, k) or px
            if Schema.Applies(nil, sec, k) and GateOK(b, kp, k) then any = true break end
        end
        if any then
            for _, f in ipairs(b.fields) do
                local def = sec.fields[f]
                if def and (loose and Options.FieldShows(px, family, b.section, def)
                    or (not loose and RowCanShow(px, family, b.section, def))) then
                    ok = true
                    break
                end
            end
        end
    end
    cache[b] = { epoch = D.epoch, px = px, ok = ok }
    return ok
end

-- The open editor tab and sub-tab of the family's page.
function D.On(family, tab, sub)
    local c = D.cur
    if not (c and c.family == family and c.etab == tab) then return false end
    return sub == nil or c.esub == sub
end

-- Every field a state table column or a state's base pick draws, for any
-- kind ("section.field" = true).
function D.StateTableFields()
    ET = ET or Options.EditorTabs
    local out = {}
    for _, list in pairs((ET and ET.STATES) or {}) do
        for _, st in ipairs(list) do
            for _, c in ipairs({ "alpha", "grey", "tint" }) do
                local spec = st[c]
                if spec then
                    out[spec[1] .. "." .. spec[2]] = true
                    if spec.on then out[spec[1] .. "." .. spec.on] = true end
                end
            end
            if st.base then out[st.base[1] .. "." .. st.base[2]] = true end
        end
    end
    return out
end

-- The state table and its effects' fields on a kind, as parts.
function D.StateParts(px)
    ET = ET or Options.EditorTabs
    local out, bySec = {}, {}
    local function add(section, fields)
        local p = bySec[section]
        if not p then
            p = { section = section, fields = {}, has = {} }
            bySec[section] = p
            out[#out + 1] = p
        end
        for _, f in ipairs(fields) do
            if not p.has[f] then
                p.has[f] = true
                p.fields[#p.fields + 1] = f
            end
        end
    end
    if not (ET and px and not px._adKinds and ET.StatesFor(px)) then return out end
    for _, p in ipairs(ET.StateParts(px)) do add(p.section, p.fields) end
    local shows = ET.blockShows
    if shows then
        for _, list in pairs(ET.FX_BLOCKS) do
            for _, def in ipairs(list) do
                local s = Schema.icon[def.section]
                if s and s.push and shows(px, def) then add(def.section, def.fields) end
            end
        end
        for _, list in pairs(ET.FX_KIND_BLOCKS) do
            for _, def in ipairs(list) do
                local s = Schema.icon[def.section]
                if s and s.push and shows(px, def) then add(def.section, def.fields) end
            end
        end
    end
    return out
end

-- The fields a page section shows on the proxy, as parts.
function D.SectionParts(family, s, px, out, bySec)
    out, bySec = out or {}, bySec or {}
    local function add(section, field)
        local p = bySec[section]
        if not p then
            p = { section = section, fields = {}, has = {} }
            bySec[section] = p
            out[#out + 1] = p
        end
        if not p.has[field] then
            p.has[field] = true
            p.fields[#p.fields + 1] = field
        end
    end
    if s.state then
        for _, p in ipairs(D.StateParts(px)) do
            for _, f in ipairs(p.fields) do add(p.section, f) end
        end
        return out, bySec
    end
    for _, b in ipairs(s.blocks) do
        if D.BlockOK(family, b, px, true) then
            local sec = Schema[family][b.section]
            for _, f in ipairs(b.fields) do
                local def = sec.fields[f]
                if def and Options.FieldShows(px, family, b.section, def) then add(b.section, f) end
            end
        end
    end
    return out, bySec
end

-- How many fields of these parts differ from the shipped value.
function D.CountChanged(family, px, parts)
    local n = 0
    for _, p in ipairs(parts) do
        for _, f in ipairs(p.fields) do
            if D.Changed(family, px, p.section, f) then n = n + 1 end
        end
    end
    return n
end

-- The tabs and sub-tabs a proxy shows (only those with a change while the
-- filter is on), with each one's count of changes.
function D.Avail(family, px)
    local P = D.pages[family]
    local tabs, subs, nTab, nSub = {}, {}, {}, {}
    if not (P and px) then return tabs, subs, nTab, nSub end
    for _, s in ipairs(P.order) do
        local shows
        if s.state then
            shows = not px._adKinds and ET ~= nil and ET.StatesFor(px) ~= nil
        else
            shows = false
            local loose = D.State().filter == true
            for _, b in ipairs(s.blocks) do
                if D.BlockOK(family, b, px, loose) then shows = true break end
            end
        end
        if shows then
            local n = D.CountChanged(family, px, (D.SectionParts(family, s, px)))
            if D.State().filter and n == 0 then shows = false end
            if shows then
                if not subs[s.tab] then
                    subs[s.tab] = {}
                    tabs[#tabs + 1] = s.tab
                end
                nTab[s.tab] = (nTab[s.tab] or 0) + n
                if s.sub then
                    local list = subs[s.tab]
                    local k = s.tab .. "\1" .. s.sub
                    if not nSub[k] then list[#list + 1] = s.sub end
                    nSub[k] = (nSub[k] or 0) + n
                end
            end
        end
    end
    return tabs, subs, nTab, nSub
end

-- The fields the open page shows, as parts (Reset this page, Make them
-- follow, Copy this page to).
function D.PageParts(family, px)
    local P = D.pages[family]
    local out, bySec = {}, {}
    if not (P and px) then return out end
    for _, s in ipairs(P.order) do
        if D.On(family, s.tab, s.sub) then
            if not s.state or not px._adKinds then D.SectionParts(family, s, px, out, bySec) end
        end
    end
    return out
end

-- A badges map of counts for a tab strip.
local function Counts(names, counts, keyFn)
    local out
    for _, n in ipairs(names) do
        local c = counts[keyFn and keyFn(n) or n]
        if c and c > 0 then
            out = out or {}
            out[n] = tostring(c)
        end
    end
    return out
end

-- Rows

-- A link-like button: a word in the accent, brighter on hover.
local function LinkButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    b.fs:SetFont(AT.FONT, 10, "")
    b.fs:SetPoint("LEFT", 0, 0)
    b.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    b.fs:SetText(text)
    b:SetHeight(16)
    b:SetWidth(math.ceil((b.fs:GetStringWidth() or 0) > 0 and b.fs:GetStringWidth() or (#text * 6)) + 2)
    b:SetScript("OnEnter", function() b.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3]) end)
    b:SetScript("OnLeave", function() b.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3]) end)
    return b
end

-- Hooks the page's marks onto a schema row: the dot while your default
-- differs from the shipped value, that value and Reset beside the control,
-- and on an All row "mixed" where kinds differ and how many kinds have the
-- row. The filter shows a changed row whatever its switch or fold.
function D.Decorate(row, family)
    local m = row._adMeta
    if not (m and m.def and row._colLabel and row._colCtrl) then return false end
    local dot = row:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(AT.WHITE)
    dot:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    dot:SetSize(4, 4)
    dot:SetPoint("LEFT", row, "LEFT", 3, 0)
    dot:Hide()
    local arc = row:CreateFontString(nil, "OVERLAY")
    arc:SetFont(AT.FONT, 10, "")
    arc:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    arc:SetWordWrap(false)
    arc:SetJustifyH("RIGHT")
    local sw = row:CreateTexture(nil, "OVERLAY")
    sw:SetTexture(AT.WHITE)
    sw:SetSize(12, 10)
    sw:Hide()
    local reset = LinkButton(row, "Reset")
    reset:Hide()
    local kinds = row:CreateFontString(nil, "OVERLAY")
    kinds:SetFont(AT.FONT, 10, "")
    kinds:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    kinds:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    kinds:SetWordWrap(false)
    row._adDot, row._adArc, row._adReset, row._adKinds = dot, arc, reset, kinds
    reset:SetScript("OnClick", function()
        AT.CloseDropdown()
        local px = D.Ctx(family)
        if not px then return end
        for _, f in ipairs(RowFields(m)) do D.ResetField(family, px, m.section, f) end
        D.Refresh()
    end)
    AT.Tooltip(reset, "Reset", function()
        return "Back to Arc's value for this row" .. (row._adArcWord and (": " .. row._adArcWord) or "")
            .. ". It asks whether the items you have change too."
    end)
    local inner = row._sync
    row._sync = function()
        if inner then inner() end
        local px = D.Ctx(family)
        if not px then return end
        local changed = D.RowChanged(family, px, m)
        dot:SetShown(changed)
        local mixed = D.Mixed(family, px, m.section, m.field)
        local words, swatch, word
        if changed then
            local v, byKind = D.ArcValue(family, px, m.section, m.field)
            if m.def.showPick or m.def.statePick then
                word = PickArc(family, px, m)
            elseif byKind then
                word = "by kind"
            elseif m.def.t == "color" and type(v) == "table" then
                swatch = v
            else
                word = D.Fmt(m.def, v, m.field)
            end
            words = word and ("Arc: " .. word) or "Arc:"
        end
        row._adArcWord = word
        if mixed then words = words and ("mixed   " .. words) or "mixed" end
        if px._adKinds then
            local n = #Store.DefaultKinds(family, px._adKinds, m.section, m.field)
            kinds:SetText(n == 1 and "1 kind" or (n .. " kinds"))
            kinds:Show()
        else
            kinds:Hide()
        end
        -- One column at the row's right, right to left: how many kinds, Reset,
        -- the swatch, then the words, which stop short of the control (and
        -- what trails it) and shorten there rather than run into anything.
        local edge, point, gap = row, "RIGHT", -12
        if px._adKinds then edge, point, gap = kinds, "LEFT", -10 end
        reset:ClearAllPoints()
        reset:SetPoint("RIGHT", edge, point, gap, 0)
        reset:SetShown(changed)
        if changed then edge, point, gap = reset, "LEFT", -8 end
        if swatch then
            sw:ClearAllPoints()
            sw:SetPoint("RIGHT", edge, point, gap, 0)
            sw:SetVertexColor(swatch[1] or 0, swatch[2] or 0, swatch[3] or 0, 1)
            sw:Show()
            edge, point, gap = sw, "LEFT", -4
        else
            sw:Hide()
        end
        arc:ClearAllPoints()
        arc:SetPoint("LEFT", row._colCtrl, "RIGHT", (row._colTrail or 0) + 12, 0)
        arc:SetPoint("RIGHT", edge, point, gap, 0)
        arc:SetText(words or "")
        arc:SetShown(words ~= nil)
    end
    local vis = row._visibleFn
    row._visibleFn = function()
        if D.State().filter then
            local px = D.Ctx(family)
            return px ~= nil and m.baseVis() and D.RowChanged(family, px, m)
        end
        return vis == nil or vis()
    end
    return true
end

-- The page of one family: its editor strips, then every block of every kind
-- under its tab and sub-tab (shown for the kind open), then the foot.
function D.BuildFamily(family, host)
    ET = ET or Options.EditorTabs
    local pg = AT.NewPage(host)
    AT.MakeScrollable(pg)
    pg:SetPoint("TOPLEFT", 0, -(D.HEAD_H + 6))
    pg:SetPoint("BOTTOMRIGHT", 0, 0)
    local P = { pg = pg, order = {} }
    D.pages[family] = P
    local ctx = function() return D.Ctx(family) end
    local mine = function() return D.cur ~= nil and D.cur.family == family end

    -- the editor's tabs, then its sub-tabs; a new pass of the gates starts here
    local tabRow = AT.AddRow(pg, 30, mine)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        D.epoch = D.epoch + 1
        if not mine() then return end
        D.Pick()
        local c = D.cur
        local h = tabRow._strip:Set(c.tabs, c.etab, function(name)
            D.State().etab[family] = name
            D.Refresh()
        end, 11, Counts(c.tabs, c.nTab))
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end
    local subRow = AT.AddRow(pg, 30, function()
        return mine() and #(D.cur.subs[D.cur.etab] or {}) >= 2
    end)
    subRow._strip = AT.TabRow(subRow)
    subRow._strip._openFill = COL.panel
    subRow._strip:SetPoint("TOPLEFT", 8, 0)
    subRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    subRow._sync = function()
        if not mine() then return end
        local c = D.cur
        local list = c.subs[c.etab] or {}
        if #list < 2 then return end
        local h = subRow._strip:Set(list, c.esub, function(name)
            D.State().esub[family .. "\1" .. c.etab] = name
            D.Refresh()
        end, 11, Counts(list, c.nSub, function(n) return c.etab .. "\1" .. n end))
        local want = (h or 24) + 6
        if subRow._h ~= want then subRow._h = want subRow:SetHeight(want) end
    end
    local empty = AT.AddRow(pg, 24, function() return mine() and #D.cur.tabs == 0 end)
    empty._fs = empty:CreateFontString(nil, "OVERLAY")
    empty._fs:SetFont(AT.FONT, 11, "")
    empty._fs:SetPoint("LEFT", 12, 0)
    empty._fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    empty._sync = function()
        empty._fs:SetText(D.State().filter and "Nothing changed here yet." or "Nothing to set here.")
    end
    P.empty = empty

    -- the page sections: one per tab, sub-tab and title, in the editors'
    -- order; the state table where the first state's look was filed, and a
    -- state's own rows the table leaves out (Show while missing) after it
    local byKey, stateAt = {}, false
    local tableField = D.StateTableFields()
    for _, b in ipairs(Options.LOOK_BLOCKS[family] or {}) do
        local sec = Schema[family] and Schema[family][b.section]
        if b.state and not stateAt then
            stateAt = true
            P.order[#P.order + 1] = { state = true, tab = b.tab, sub = b.sub, title = D.STATE_TITLE, blocks = {} }
        end
        if not b.fx and sec and sec.push then
            -- the block's rows, less what is per item, what the editor picks
            -- its own way, and what the state table draws
            local skip = D.PER_ITEM[family] and D.PER_ITEM[family][b.section]
            local out = D.NOT_ON_PAGE[family] and D.NOT_ON_PAGE[family][b.section]
            local fields = {}
            for _, f in ipairs(b.fields) do
                if not (skip and skip[f]) and not (out and out[f])
                    and not (b.state and tableField[b.section .. "." .. f]) then
                    fields[#fields + 1] = f
                end
            end
            if #fields > 0 then
                local key = b.tab .. "\1" .. (b.sub or "") .. "\1" .. b.title
                local s = byKey[key]
                if not s then
                    s = { tab = b.tab, sub = b.sub, title = b.title, blocks = {} }
                    byKey[key] = s
                    P.order[#P.order + 1] = s
                end
                s.blocks[#s.blocks + 1] = { section = b.section, fields = fields, gates = b.gates, open = b.open,
                    labels = b.labels }
            end
        end
    end
    local placed = {}   -- page -> section.field -> the rows built for it
    for _, s in ipairs(P.order) do
        Options.BuildYield()
        local secVis = function() return D.On(family, s.tab, s.sub) end
        if s.state then
            if ET and ET.StateTable then
                local vis = function()
                    local px = ctx()
                    return secVis() and px ~= nil and not px._adKinds
                end
                AT.Section(pg, s.title, { visibleFn = vis })
                local first = #pg._sections
                -- the editor's table stays the one ET.lastTable names
                local editorTable = ET.lastTable
                ET.StateTable(pg, ctx, vis, D.win)
                P.stateTable = ET.lastTable
                ET.lastTable = editorTable
                -- the filter shows the table while a state's look or effect changed
                for i = first, #pg._sections do
                    for _, row in ipairs(pg._sections[i].rows) do
                        local inner = row._visibleFn
                        row._visibleFn = function()
                            if D.State().filter then
                                local px = ctx()
                                if not (px and vis()) or D.CountChanged(family, px, D.StateParts(px)) == 0 then
                                    return false
                                end
                            end
                            return inner == nil or inner()
                        end
                    end
                end
            end
        else
            AT.Section(pg, s.title, { visibleFn = secVis })
            local pkey = s.tab .. "\1" .. (s.sub or "")
            placed[pkey] = placed[pkey] or {}
            for _, b in ipairs(s.blocks) do
                local vis = function()
                    local px = ctx()
                    return secVis() and px ~= nil and D.BlockOK(family, b, px)
                end
                local sec = pg._curSection
                local n0 = #sec.rows
                Options.SectionRows(pg, family, b.section, ctx, vis, b.fields, b.labels and { labels = b.labels } or nil)
                for i = n0 + 1, #sec.rows do
                    local row = sec.rows[i]
                    if not D.Decorate(row, family) then
                        -- a More options fold or a count's buttons: the
                        -- filter shows the changed rows themselves
                        local inner = row._visibleFn
                        row._visibleFn = function()
                            if D.State().filter then return false end
                            return inner == nil or inner()
                        end
                    end
                    -- one field in two blocks of a page, each for some kinds
                    -- (a pips bar's Direction, every other bar's Orientation):
                    -- the first one showing wins
                    local m = row._adMeta
                    if m then
                        local k = m.section .. "." .. m.field
                        local list = placed[pkey][k]
                        if list then
                            local earlier = {}
                            for j, r in ipairs(list) do earlier[j] = r end
                            local inner = row._visibleFn
                            row._visibleFn = function()
                                for _, r in ipairs(earlier) do
                                    if r._visibleFn() then return false end
                                end
                                return inner == nil or inner()
                            end
                            list[#list + 1] = row
                        else
                            placed[pkey][k] = { row }
                        end
                    end
                end
            end
        end
    end
    D.BuildFoot(family, pg, mine)
    return P
end

-- The foot of a kind's page: who uses these, Make them follow, Reset this
-- page, and Copy this page to another kind.
function D.BuildFoot(family, pg, mine)
    AT.Section(pg, nil, { visibleFn = function() return mine() and #D.cur.tabs > 0 end })
    local row = AT.AddRow(pg, 26)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    local resetPage = AT.MakeQuietButton(row, "Reset this page", 112)
    resetPage:SetPoint("RIGHT", -12, 0)
    local follow = AT.MakeSmallButton(row, "Make them follow", 124)
    follow:SetPoint("RIGHT", resetPage, "LEFT", -8, 0)
    row._adText, row._adFollow, row._adResetPage = fs, follow, resetPage
    local function Own()
        local c = D.cur
        if not (c and c.entry) then return 0 end
        return Store.DefaultsOwnCount(family, c.entry.kind, D.PageParts(family, D.Ctx(family)))
    end
    row._sync = function()
        local c = D.cur
        if not (mine() and c) then return end
        local px = D.Ctx(family)
        local parts = D.PageParts(family, px)
        local anyChanged = D.CountChanged(family, px, parts) > 0
        resetPage:SetShown(anyChanged)
        local text, own = "", 0
        if c.entry then
            local w = D.Words(family, c.entry.kind)
            local n = #Store.DefaultsItems(family, c.entry.kind)
            own = Own()
            if n == 0 then
                text = "No " .. w.many .. " yet. New ones start with these."
            elseif own > 0 then
                text = n .. " " .. (n == 1 and (w.one .. " uses") or (w.many .. " use")) .. " these. " .. own
                    .. (own == 1 and " keeps its own value for a row here." or " keep their own value for a row here.")
            else
                text = n .. " " .. (n == 1 and (w.one .. " uses these. It follows them.")
                    or (w.many .. " use these. Each one follows them."))
            end
        else
            local items = 0
            for _, k in ipairs(c.kinds) do items = items + #Store.DefaultsItems(family, k) end
            local f = D.FAMILY_WORDS[family]
            text = "Reaches every kind with that row: " .. #c.kinds .. " kinds, " .. items .. " "
                .. (items == 1 and f[1] or f[2]) .. "."
        end
        fs:SetText(text)
        fs:SetTextColor((own > 0 and COL.ink or COL.dim)[1], (own > 0 and COL.ink or COL.dim)[2],
            (own > 0 and COL.ink or COL.dim)[3])
        follow:SetShown(own > 0)
        local right = (own > 0 and follow) or (anyChanged and resetPage) or nil
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", 10, 0)
        if right then fs:SetPoint("RIGHT", right, "LEFT", -8, 0) else fs:SetPoint("RIGHT", -12, 0) end
    end
    follow:SetScript("OnClick", function()
        AT.CloseDropdown()
        local c = D.cur
        if not (c and c.entry) then return end
        local own = Own()
        if own == 0 then return end
        local w = D.Words(family, c.entry.kind)
        local one = own == 1
        local parts = D.PageParts(family, D.Ctx(family))
        D.Confirm(own .. " " .. (one and w.one or w.many) .. (one and " has its own value" or " have their own values")
            .. " for a row on this page. Reset " .. (one and "it so it follows" or "them so they follow")
            .. " your defaults?", function()
            Store.DefaultsFollow(family, c.entry.kind, parts)
            D.Refresh()
        end)
    end)
    resetPage:SetScript("OnClick", function()
        AT.CloseDropdown()
        local c = D.cur
        if not c then return end
        local px = D.Ctx(family)
        local parts = D.PageParts(family, px)
        local batch = D.Batch(px)
        for _, k in ipairs(KindsOf(px)) do Store.ResetDefaults(family, k, parts, batch) end
        D.Refresh()
    end)
    AT.Tooltip(follow, "Make them follow", "Drops the own values items of this kind hold for the rows on this page, so they follow your defaults. It asks first and says how many.")
    AT.Tooltip(resetPage, "Reset this page", "Every row on this page back to Arc's value. It asks whether the items you have change too.")

    -- Copy this page to [kind v] [Copy]: pick, then act
    local copyRow = AT.AddRow(pg, 26, function()
        local c = D.cur
        return mine() and c ~= nil and c.entry ~= nil and #D.CopyTargets(family, c.entry.kind) > 0
    end)
    local lbl = AT.RowLabel(copyRow, "Copy this page to")
    local sel = "others"
    local dd = AT.MakeDropdown(D.win, copyRow, nil,
        function()
            local c = D.cur
            if not (c and c.entry) then return { { value = "others", text = "Every other kind" } } end
            local list = D.CopyTargets(family, c.entry.kind)
            local f = D.FAMILY_WORDS[family]
            local items = { { value = "others", text = "Every other kind of " .. f[2] .. " (" .. #list .. ")" } }
            for _, k in ipairs(list) do items[#items + 1] = { value = k, text = D.Words(family, k).title } end
            return items
        end,
        function() return sel end,
        function(v) sel = v end)
    dd:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    local copy = AT.MakeSmallButton(copyRow, "Copy", 70)
    copy:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    copyRow._sync = dd.Refresh
    copyRow._adDropdown, copyRow._adCopy = dd, copy
    copy:SetScript("OnClick", function()
        AT.CloseDropdown()
        local c = D.cur
        if not (c and c.entry) then return end
        local list = D.CopyTargets(family, c.entry.kind)
        local targets = list
        if sel ~= "others" then targets = { sel } end
        local px = D.Ctx(family)
        Store.CopyDefaults(family, c.entry.kind, targets, D.PageParts(family, px), D.Batch(px))
        D.Refresh()
    end)
    AT.Tooltip(dd, "Copy this page to", "The kinds that take this page's rows, each where it has the row. Nothing happens until you press Copy.")
    AT.Tooltip(copy, "Copy", "Sets the rows of this page as the default of the kinds picked. It asks whether the items you have change too.")
end

-- The other kinds of a family a page copies to.
function D.CopyTargets(family, kind)
    local out, member = {}, false
    local pool = (D.pool and D.pool[family]) or {}
    for _, k in ipairs(pool) do
        if k == kind then member = true end
    end
    -- a text, a texture or a wheel copies to nothing: no bar has its rows
    if not member then return out end
    for _, k in ipairs(pool) do
        if k ~= kind then out[#out + 1] = k end
    end
    return out
end

-- The kind's head: preview, name, the order strip, then Reset all or the ask

local ORDER = { "Arc's default", "Your default", "Layout looks" }

-- One step of the order strip: its words, and a box round the one this page sets.
local function OrderStep(parent, text, on)
    local f = CreateFrame("Frame", nil, parent, on and "BackdropTemplate" or nil)
    f.fs = f:CreateFontString(nil, "OVERLAY")
    f.fs:SetFont(AT.FONT, 10, "")
    f.fs:SetPoint("LEFT", on and 6 or 0, 0)
    f.fs:SetText(text)
    local c = on and COL.ink or COL.faint
    f.fs:SetTextColor(c[1], c[2], c[3])
    if on then
        AT.Skin(f, COL.sel, COL.arcDeep)
        f:EnableMouse(true)
    end
    f:SetHeight(16)
    return f
end

function D.BuildHead(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", 0, 0)
    h:SetHeight(D.HEAD_H)
    D.head = h
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(AT.WHITE)
    bg:SetVertexColor(COL.box[1], COL.box[2], COL.box[3], 1)
    bg:SetAllPoints()
    local line = h:CreateTexture(nil, "BORDER")
    line:SetTexture(AT.WHITE)
    line:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    h.prev = D.BuildPreview(h)
    h.prev:SetPoint("TOPLEFT", 6, -6)
    h.name = h:CreateFontString(nil, "OVERLAY")
    h.name:SetFont(AT.FONT, 14, "")
    h.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    h.name:SetWordWrap(false)
    -- the order strip: shipped, yours, the layout's, the item's own (later wins)
    h.steps, h.chevs = {}, {}
    for i, t in ipairs(ORDER) do h.steps[i] = OrderStep(h, t, i == 2) end
    h.steps[4] = OrderStep(h, "The icon", false)
    for i = 1, 3 do
        local ch = AT.MakeChevron(h)
        ch:SetDir("right")
        ch:SetColor(COL.faint)
        h.chevs[i] = ch
    end
    AT.Tooltip(h.steps[2], "Your default", "What this page sets. An item's layout looks and its own values win over it; Arc's default is what it starts from.")
    -- right: Reset all N, or the ask
    h.resetAll = AT.MakeQuietButton(h, "Reset all", 96)
    h.resetAll:SetPoint("TOPRIGHT", -10, -8)
    h.ask = h:CreateFontString(nil, "OVERLAY")
    h.ask:SetFont(AT.FONT, 11, "")
    h.ask:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    h.ask:SetPoint("TOPRIGHT", -10, -7)
    h.ask:SetJustifyH("RIGHT")
    h.ask:SetWordWrap(false)
    h.only = AT.MakeQuietButton(h, "Only new", 120)
    h.only:SetPoint("BOTTOMRIGHT", -10, 6)
    h.too = AT.MakeSmallButton(h, "Change them too", 124)
    h.too:SetPoint("RIGHT", h.only, "LEFT", -8, 0)
    h.resetAll:SetScript("OnClick", function()
        AT.CloseDropdown()
        local c = D.cur
        if not c then return end
        local n, w = D.KindChanges(c), D.HeadWords(c)
        if n == 0 then return end
        D.Confirm("Put all " .. n .. " of your " .. w.one .. " defaults back to Arc's?", function()
            local px = D.Ctx(c.family)
            local batch = D.Batch(px)
            for _, k in ipairs(KindsOf(px)) do Store.ResetDefaults(c.family, k, nil, batch) end
            D.Refresh()
        end)
    end)
    h.too:SetScript("OnClick", function()
        AT.CloseDropdown()
        local px = D.cur and D.Ctx(D.cur.family)
        if px then Store.AnswerDefaults(px._adBatch, true) end
        D.Refresh()
    end)
    h.only:SetScript("OnClick", function()
        AT.CloseDropdown()
        local px = D.cur and D.Ctx(D.cur.family)
        if px then Store.AnswerDefaults(px._adBatch, false) end
        D.Refresh()
    end)
    AT.Tooltip(h.resetAll, "Reset all", "Every default of this kind back to Arc's. It asks first, then whether the items you have change too.")
    AT.Tooltip(h.too, "Change them too", "The items that used the old values take the new ones.")
    AT.Tooltip(h.only, "Only new", "The items you have keep their look; only new ones start with these. Leaving the page does the same.")
    return h
end

-- The words a head speaks of: the kind's, or the family's on an All row.
function D.HeadWords(c)
    if c.entry then return D.Words(c.family, c.entry.kind) end
    local f = D.FAMILY_WORDS[c.family]
    local tab = c.tab
    return K(tab.name, f[1], f[2], "All " .. f[2])
end

-- The order strip's last step: the item itself, in its own word (a text, a
-- texture, a wheel; else the family's).
D.OWN_WORD = { text = true, texture = true, wheel = true }
function D.ItemWord(c)
    local kind = c.entry and c.entry.kind
    if c.family == "bar" and kind and D.OWN_WORD[kind] then return "The " .. D.Words("bar", kind).one end
    return (D.FAMILY_WORDS[c.family] or { nil, nil, "The item" })[3]
end

-- How many saved defaults of the open kind (every kind on an All row) differ
-- from the shipped value.
function D.KindChanges(c)
    local n = 0
    for _, k in ipairs(c.entry and { c.entry.kind } or c.kinds) do
        n = n + #Store.DefaultsChanged(c.family, k)
    end
    return n
end

function D.SyncHead()
    local h, c = D.head, D.cur
    if not (h and c) then return end
    local px = D.Ctx(c.family)
    local w = D.HeadWords(c)
    local shown, pw = D.PaintPreview(h.prev, c.family, px)
    local nx = shown and (6 + (pw or D.PREV) + 12) or 10
    h.name:ClearAllPoints()
    h.name:SetPoint("TOPLEFT", nx, -8)
    h.name:SetText(w.title)
    -- the strip, laid in whole units left to right
    h.steps[4].fs:SetText(D.ItemWord(c))
    local x = nx
    for i = 1, 4 do
        local st = h.steps[i]
        local sw = math.ceil(st.fs:GetStringWidth() or 0) + (i == 2 and 12 or 0)
        st:SetWidth(sw)
        st:ClearAllPoints()
        st:SetPoint("TOPLEFT", x, -28)
        x = x + sw
        if i < 4 then
            h.chevs[i]:ClearAllPoints()
            h.chevs[i]:SetPoint("TOPLEFT", x + 2, -30)
            x = x + 16
        end
    end
    h._stripW = x
    -- the ask while a change waits on its answer, else Reset all N
    local p = px and Store.DefaultsPending(px._adBatch)
    if p then
        local bw = D.BatchWords(c.family, c.entry and c.entry.kind, p)
        h.ask:SetText(D.AskText(p, bw))
        h.too.fs:SetText(p.items == 1 and "Change it too" or "Change them too")
        local label = "Only new " .. bw.many
        h.only.fs:SetText(label)
        local lw = math.ceil(h.only.fs:GetStringWidth() or 0)
        h.only:SetWidth(math.max(96, (lw > 0 and lw or #label * 6) + 20))
        h.ask:Show()
        h.too:Show()
        h.only:Show()
        h.resetAll:Hide()
        -- the strip gives way to the two buttons on a narrow pane
        local hw = h:GetWidth() or 0
        local need = x + 12 + (h.only:GetWidth() or 0) + 8 + (h.too:GetWidth() or 0) + 10
        local fits = hw <= 0 or need <= hw
        for i = 1, 4 do h.steps[i]:SetShown(fits) end
        for i = 1, 3 do h.chevs[i]:SetShown(fits) end
    else
        h.ask:Hide()
        h.too:Hide()
        h.only:Hide()
        for i = 1, 4 do h.steps[i]:Show() end
        for i = 1, 3 do h.chevs[i]:Show() end
        local n = D.KindChanges(c)
        h.resetAll.fs:SetText("Reset all " .. n)
        h.resetAll:SetShown(n > 0)
    end
end

-- The preview: the kind's look drawn from the defaults, at its real size on
-- a host scaled to fit (a preview is the live thing magnified, never restyled
-- big): an icon, a bar, or a text's words.
D.ICON_ART = {
    spell = "Interface\\Icons\\Spell_Nature_Lightning", aura = "Interface\\Icons\\Spell_Holy_WordFortitude",
    groupbuff = "Interface\\Icons\\Spell_Holy_MagicalSentry", item = "Interface\\Icons\\INV_Potion_54",
    trinket = "Interface\\Icons\\INV_Jewelry_Talisman_07", totem = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
    ammo = "Interface\\Icons\\INV_Ammo_Arrow_02", enchant = "Interface\\Icons\\Spell_Fire_FlameTounge",
    stance = "Interface\\Icons\\Ability_Warrior_DefensiveStance", timer = "Interface\\Icons\\Spell_Holy_BorrowedTime",
    special = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
}
D.PREV = 40

function D.BuildPreview(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(D.PREV, D.PREV)
    local host = CreateFrame("Frame", nil, box)
    host:SetPoint("TOPLEFT", 0, 0)
    box.host = host
    local function Tex(layer)
        local t = host:CreateTexture(nil, layer)
        t:SetTexture(AT.WHITE)
        return t
    end
    box.art = host:CreateTexture(nil, "ARTWORK")
    box.edges = { Tex("OVERLAY"), Tex("OVERLAY"), Tex("OVERLAY"), Tex("OVERLAY") }
    box.bg = Tex("BACKGROUND")
    box.fill = host:CreateTexture(nil, "ARTWORK")
    box.text = host:CreateFontString(nil, "OVERLAY")
    box.text:SetFont(AT.FONT, 12, "OUTLINE")
    return box
end

-- A length on the live pixel grid (UIParent's), at least one pixel.
local function LivePx(v)
    local px = AT.Px(UIParent) or 1
    if px <= 0 then px = 1 end
    return math.max(px, math.floor((tonumber(v) or 0) / px + 0.5) * px)
end

-- Four strips round the host's inner rect, `t` thick, corner anchored.
local function Edges(box, w, h, t, c)
    local e = box.edges
    for i = 1, 4 do e[i]:ClearAllPoints() end
    e[1]:SetPoint("TOPLEFT", 0, 0); e[1]:SetSize(w, t)
    e[2]:SetPoint("TOPLEFT", 0, -(h - t)); e[2]:SetSize(w, t)
    e[3]:SetPoint("TOPLEFT", 0, -t); e[3]:SetSize(t, h - 2 * t)
    e[4]:SetPoint("TOPLEFT", w - t, -t); e[4]:SetSize(t, h - 2 * t)
    for i = 1, 4 do
        e[i]:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
        e[i]:Show()
    end
end

local function HideAll(box)
    box.art:Hide()
    box.bg:Hide()
    box.fill:Hide()
    box.text:Hide()
    for i = 1, 4 do box.edges[i]:Hide() end
end

local function TexturePath(key)
    local B = NS.Bars
    if not key or key == "" or not B then return AT.WHITE end
    if B.BUILTIN_TEXTURES and B.BUILTIN_TEXTURES[key] then return B.BUILTIN_TEXTURES[key] end
    local lsm = B.GetLSM and B.GetLSM()
    return (lsm and lsm:Fetch("statusbar", key, true)) or AT.WHITE
end

local function FontPath(key)
    local B = NS.Bars
    if B and B.BUILTIN_FONTS then
        if not key or key == "" then return B.BUILTIN_FONTS.Default or AT.FONT end
        if B.BUILTIN_FONTS[key] then return B.BUILTIN_FONTS[key] end
        local lsm = B.GetLSM and B.GetLSM()
        local p = lsm and lsm:Fetch("font", key, true)
        if p then return p end
    end
    return AT.FONT
end

-- The host at w x h units, scaled to fit maxW x the box's height, centred
-- top to bottom; returns how wide it draws.
local function Fit(box, w, h, maxW)
    local host = box.host
    local sc = math.min(D.PREV / h, maxW / w, 1)
    host:SetSize(w, h)
    host:SetScale(sc)
    local oy = math.floor((D.PREV - h * sc) / 2 + 0.5)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -oy / sc)
    local shown = math.ceil(w * sc)
    box:SetWidth(shown)
    return shown
end

-- Draws the proxy's look; false when its kind has none to show, else true
-- and how wide it drew (the name starts after it).
function D.PaintPreview(box, family, px)
    HideAll(box)
    if not px then box:Hide() return false end
    local host = box.host
    local R = function(s, f) return Store.Resolve(px, s, f) end
    local kind = KindsOf(px)[1]
    if family == "icon" then
        local size = 36
        local shown = Fit(box, size, size, D.PREV)
        box.art:ClearAllPoints()
        box.art:SetPoint("TOPLEFT", 0, 0)
        box.art:SetSize(size, size)
        box.art:SetTexture(D.ICON_ART[kind] or D.ICON_ART.spell)
        local z = tonumber(R("appearance", "zoom")) or 0.08
        box.art:SetTexCoord(z, 1 - z, z, 1 - z)
        box.art:SetAlpha(tonumber(R("appearance", "alpha")) or 1)
        box.art:Show()
        if R("appearance", "borderEnabled") ~= false then
            local c = R("appearance", "borderColor") or { 0, 0, 0, 1 }
            Edges(box, size, size, LivePx(R("appearance", "borderThickness") or 2), c)
        end
        box:Show()
        return true, shown
    end
    if family == "bar" and (kind == "text") then
        local w, h = math.max(1, tonumber(R("size", "width")) or 140), math.max(1, tonumber(R("size", "height")) or 24)
        local shown = Fit(box, w, h, 120)
        -- the text's box: its own background, else a well, so the sample
        -- reads as one thing beside the name
        local c = (R("textel", "bgShow") == true and R("textel", "bgColor")) or COL.well
        box.bg:ClearAllPoints()
        box.bg:SetPoint("TOPLEFT", 0, 0)
        box.bg:SetSize(w, h)
        box.bg:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
        box.bg:Show()
        Edges(box, w, h, LivePx(1), COL.line)
        box.text:SetFont(FontPath(R("textel", "font")), tonumber(R("textel", "size")) or 14, "OUTLINE")
        box.text:ClearAllPoints()
        box.text:SetPoint("TOPLEFT", 0, 0)
        box.text:SetSize(w, h)
        local c = R("textel", "color") or { 1, 1, 1, 1 }
        box.text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        box.text:SetText("72%")
        box.text:Show()
        box:Show()
        return true, shown
    end
    if family == "bar" and kind ~= "texture" and kind ~= "wheel" then
        local w, h = tonumber(R("size", "width")) or 193, tonumber(R("size", "height")) or 24
        w, h = math.max(1, w), math.max(1, h)
        local shown = Fit(box, w, h, 120)
        local t = (R("look", "borderEnabled") ~= false) and LivePx(R("look", "borderThickness") or 1) or 0
        if R("look", "bgShow") ~= false then
            local c = R("look", "bgColor") or { 0.4, 0.42, 0.46 }
            box.bg:ClearAllPoints()
            box.bg:SetPoint("TOPLEFT", t, -t)
            box.bg:SetSize(math.max(1, w - 2 * t), math.max(1, h - 2 * t))
            box.bg:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, tonumber(R("look", "bgAlpha")) or 0.9)
            box.bg:Show()
        end
        local fc = R("fill", "color") or { 1, 0.8, 0.2, 1 }
        box.fill:ClearAllPoints()
        box.fill:SetPoint("TOPLEFT", t, -t)
        box.fill:SetSize(math.max(1, math.floor((w - 2 * t) * 0.6 + 0.5)), math.max(1, h - 2 * t))
        box.fill:SetTexture(TexturePath(R("fill", "texture")))
        box.fill:SetVertexColor(fc[1] or 1, fc[2] or 1, fc[3] or 1, fc[4] or 1)
        box.fill:Show()
        if t > 0 then Edges(box, w, h, t, R("look", "borderColor") or { 0, 0, 0, 1 }) end
        box:Show()
        return true, shown
    end
    box:Hide()
    return false
end

-- The kind list

function D.BuildList(parent)
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(list, COL.panel, COL.line)
    list:SetWidth(D.LIST_W)
    list.rows = {}
    D.list = list
    return list
end

-- A kind's row reads as something to pick: a quiet button at rest, lifted
-- under the mouse, the open kind in the selection's colours.
local function PaintListRow(r)
    local sel, hot = r._sel, r._hot
    local fill, edge, ink = COL.btn, COL.line, COL.dim
    if sel then fill, edge, ink = COL.sel, COL.arcDeep, COL.arc
    elseif hot then fill, edge, ink = COL.btnHover, COL.line2, COL.ink end
    if r._all and not sel then ink = hot and COL.ink or COL.word end
    AT.Skin(r, fill, edge)
    r.name:SetTextColor(ink[1], ink[2], ink[3])
end

function D.ListRow(i)
    local list = D.list
    local r = list.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list, "BackdropTemplate")
    r:SetHeight(D.ROW_H - 2)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(AT.FONT, 12, "")
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.count = r:CreateFontString(nil, "OVERLAY")
    r.count:SetFont(AT.FONT, 10, "")
    r.count:SetPoint("RIGHT", -8, 0)
    r.count:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    r.name:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
    r:SetScript("OnEnter", function() r._hot = true PaintListRow(r) end)
    r:SetScript("OnLeave", function() r._hot = nil PaintListRow(r) end)
    r:SetScript("OnClick", function()
        AT.CloseDropdown()
        local c = D.cur
        if not c then return end
        D.Leave()
        D.State().pick[c.tab.name] = r._key
        D.Refresh()
    end)
    list.rows[i] = r
    return r
end

function D.SyncList()
    local list, c = D.list, D.cur
    if not (list and c) then return end
    local tab = c.tab
    local multi = #tab.entries > 1
    list:SetShown(multi)
    D.right:ClearAllPoints()
    D.right:SetPoint("TOPLEFT", D.body, "TOPLEFT", multi and (D.LIST_W + 8) or 0, 0)
    D.right:SetPoint("BOTTOMRIGHT", D.body, "BOTTOMRIGHT", 0, 0)
    if not multi then return end
    local items = {}
    if tab.all then
        local n = 0
        for _, k in ipairs(tab.all.kinds) do n = n + #Store.DefaultsChanged(tab.all.family, k) end
        items[#items + 1] = { key = "all", text = "All " .. D.FAMILY_WORDS[tab.all.family][2], n = n, all = true }
    end
    for _, e in ipairs(tab.entries) do
        items[#items + 1] = { key = D.EntryKey(e), text = D.Words(e.family, e.kind).name,
            n = #Store.DefaultsChanged(e.family, e.kind) }
    end
    local curKey = c.entry and D.EntryKey(c.entry) or "all"
    local y = -4
    for i, it in ipairs(items) do
        local r = D.ListRow(i)
        r._key, r._all, r._sel = it.key, it.all, it.key == curKey
        r.name:SetText(it.text)
        r.count:SetText(it.n > 0 and tostring(it.n) or "")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 4, y)
        r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, y)
        PaintListRow(r)
        r:Show()
        -- the All row stands apart from the kinds under it
        y = y - D.ROW_H - ((it.all and 6) or 0)
    end
    for i = #items + 1, #list.rows do list.rows[i]:Hide() end
end

-- The family strip

function D.SyncFamilies()
    local strip, c = D.famStrip, D.cur
    if not (strip and c) then return end
    local names, counts = {}, {}
    for _, t in ipairs(D.tabs) do
        names[#names + 1] = t.name
        local n = 0
        for _, e in ipairs(t.entries) do n = n + #Store.DefaultsChanged(e.family, e.kind) end
        counts[t.name] = n
    end
    local h = strip:Set(names, c.tab.name, function(name)
        D.Leave()
        D.State().tab = name
        D.Refresh()
    end, 12, Counts(names, counts))
    -- a narrow window wraps the tabs: the body starts under them
    local want = (h or 24) + 6
    if D.famH ~= want then
        D.famH = want
        D.famRow:SetHeight(want)
        D.body:SetPoint("TOPLEFT", 0, -(34 + want + 6))
    end
end

-- Picks and refresh

-- The open kind, its editor tabs and sub-tabs (a stale pick snaps to the first).
function D.Pick()
    local c = D.Resolve()
    if not c then D.cur = nil return end
    c.etab, c.esub = nil, nil
    D.cur = c
    local px = D.Ctx(c.family)
    c.tabs, c.subs, c.nTab, c.nSub = D.Avail(c.family, px)
    local s = D.State()
    local want = s.etab[c.family]
    for _, t in ipairs(c.tabs) do if t == want then c.etab = t end end
    c.etab = c.etab or c.tabs[1]
    local list = c.etab and c.subs[c.etab] or {}
    local wantSub = c.etab and s.esub[c.family .. "\1" .. c.etab]
    for _, t in ipairs(list) do if t == wantSub then c.esub = t end end
    c.esub = c.esub or list[1]
end

function D.Refresh()
    if not D.pane then return end
    D.epoch = D.epoch + 1
    D.Pick()
    local c = D.cur
    if not c then return end
    -- the page open takes the sidebar row's mark down
    if D.pane:IsVisible() then Options.ClearNew(D.NEW_KEY) end
    D.PaintRail()
    D.SyncFamilies()
    D.SyncList()
    for fam, P in pairs(D.pages) do P.pg:SetShown(fam == c.family) end
    D.SyncHead()
    local P = D.pages[c.family]
    if P then AT.LayoutPage(P.pg) end
    if D.filterBox then D.filterBox:SetOn(D.State().filter == true) end
end

-- The sidebar row

function D.RailRow(row)
    D.railRow = row
    row._newChip = AT.NewChip(row)
    row._newChip:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row._newChip:Hide()
end

-- NEW for one version, down once the page is opened; counted as seen only
-- while the sidebar shows it.
function D.PaintRail()
    local row = D.railRow
    if not (row and row._newChip) then return end
    local seen = row:IsVisible() == true
    local b = Options.NewBadge and Options.NewBadge(D.NEW_KEY, not seen)
    if b then row._newChip:SetText(b) end
    row._newChip:SetShown(b ~= nil)
end

-- The pane

function D.Fill(pane, header, win)
    D.pane, D.header, D.win = pane, header, win
    header.name:SetText("Defaults")
    header.chip1:Hide()
    header.chip2:Hide()
    D.BuildTabs()
    -- Only what I changed: a switch at the header's right
    local fb = CreateFrame("Button", nil, header)
    fb:SetHeight(20)
    local box = AT.MakeCheckbox(fb)
    box:SetPoint("RIGHT", 0, 0)
    box:EnableMouse(false)
    local word = fb:CreateFontString(nil, "OVERLAY")
    word:SetFont(AT.FONT, 11, "")
    word:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    word:SetPoint("RIGHT", box, "LEFT", -6, 0)
    word:SetText("Only what I changed")
    local ww = math.ceil(word:GetStringWidth() or 0)
    fb:SetWidth((ww > 0 and ww or 110) + 30)
    fb:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    fb:SetScript("OnClick", function()
        AT.CloseDropdown()
        local s = D.State()
        s.filter = not s.filter or nil
        D.Refresh()
    end)
    fb:SetScript("OnEnter", function() box:SetHover(true) end)
    fb:SetScript("OnLeave", function() box:SetHover(false) end)
    AT.Tooltip(fb, "Only what I changed", "Shows only the rows where your default differs from Arc's.")
    D.filterBox = box
    header._btns = header._btns or {}
    header._btns[#header._btns + 1] = fb
    -- the family tabs
    local famRow = CreateFrame("Frame", nil, pane)
    famRow:SetPoint("TOPLEFT", 0, -34)
    famRow:SetPoint("TOPRIGHT", 0, -34)
    famRow:SetHeight(30)
    D.famRow = famRow
    -- the strip sits on the page's fill, as every editor strip does, down to
    -- the body: idle tabs (set back, darker) then never match their ground
    local ground = famRow:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(AT.WHITE)
    ground:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    ground:SetPoint("TOPLEFT", famRow, "TOPLEFT", 0, 0)
    ground:SetPoint("BOTTOMRIGHT", famRow, "BOTTOMRIGHT", 0, -6)
    D.famGround = ground
    D.famStrip = AT.TabRow(famRow)
    D.famStrip._openFill = COL.panel
    D.famStrip:SetPoint("TOPLEFT", 4, 0)
    D.famStrip:SetPoint("BOTTOMRIGHT", -4, 2)
    -- the body: the kind list, then the kind's head and page
    local body = CreateFrame("Frame", nil, pane)
    body:SetPoint("TOPLEFT", 0, -70)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    D.body = body
    local list = D.BuildList(body)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", 0, 0)
    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPLEFT", D.LIST_W + 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    D.right = right
    D.BuildHead(right)
    for _, fam in ipairs({ "icon", "iconGroup", "bar" }) do D.BuildFamily(fam, right) end
    -- leaving the page answers Only new to whatever still waits
    pane:HookScript("OnHide", function() D.Leave() end)
    D.Pick()
end

