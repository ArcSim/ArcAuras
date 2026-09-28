-- AD_EditorTabs: the editors' tabs by effect: the state table, the More options folds, the glow and sound cards, and the new home of a tab pick made before the regroup.
-- AD_Options builds the editors and calls in behind nil checks; every cell reads Store.Resolve and writes Store.SetOverride, as SectionRows does.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store, Schema = NS.AT, NS.Store, NS.Schema
local COL = AT.COL

local ET = {}
Options.EditorTabs = ET

-- Values

-- Colours compare by their numbers (a missing alpha reads as 1).
function ET.Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for i = 1, 3 do
        if a[i] ~= b[i] then return false end
    end
    return (a[4] or 1) == (b[4] or 1)
end

-- The record's own value, when it differs from what the record reads without
-- it. SetOverride keeps records sparse, so this is nearly always "has one".
function ET.Changed(rec, section, field)
    local o = rec and rec.o and rec.o[section]
    local own = o and o[field]
    if own == nil then return false end
    o[field] = nil
    local base = Store.Resolve(rec, section, field)
    o[field] = own
    return not ET.Same(own, base)
end

-- Settings > Panel > Show every option: every fold stays open.
function ET.ShowAll()
    return Store.GetSetting("showEveryOption") == true
end

-- Which folds are open, by key, in the panel's own saved state.
function ET.FoldState()
    local u = Store.UI()
    if not u then return {} end
    u.folds = u.folds or {}
    return u.folds
end

-- More options folds

local Fold = {}
Fold.__index = Fold

-- A fold row, "More <word> options" and a count, in the section open on pg.
-- The rows the caller adds after it show while it is open; it opens by itself
-- while one of them holds a changed value, so a value you set never hides.
function ET.NewFold(pg, key, word, ctx)
    local f = setmetatable({ key = key, ctx = ctx, items = {}, pg = pg }, Fold)
    local title = "More " .. ((type(word) == "string" and word ~= "") and (word .. " ") or "") .. "options"
    f.title = title
    local row = AT.AddRow(pg, 24, function() return f:HeadShown() end)
    f.row = row
    row._adFoldHead = f
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetTexture(AT.WHITE)
    line:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    line:SetPoint("TOPLEFT", 4, 0)
    line:SetPoint("TOPRIGHT", -4, 0)
    local chev = AT.MakeChevron(row)
    chev:SetPoint("LEFT", 8, 0)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    fs:SetPoint("LEFT", chev, "RIGHT", 4, 0)
    fs:SetWordWrap(false)
    fs:SetText(title)
    local nb = CreateFrame("Frame", nil, row, "BackdropTemplate")
    nb:SetHeight(16)
    nb:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    AT.Skin(nb, COL.panel, COL.line2)
    local nfs = nb:CreateFontString(nil, "OVERLAY")
    nfs:SetFont(STANDARD_TEXT_FONT, 10, "")
    nfs:SetPoint("CENTER", 0, 0)
    nfs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row._adFoldText, row._adFoldCount = fs, nfs
    local function Paint()
        local c = f.hot and COL.ink or COL.dim
        fs:SetTextColor(c[1], c[2], c[3])
        chev:SetColor(f.hot and COL.arc or COL.dim)
    end
    row._sync = function()
        line:SetHeight(AT.Hairline(row))
        local n = f:Count()
        nfs:SetText(tostring(n))
        local w = nfs:GetStringWidth() or 6
        nb:SetWidth(math.max(18, math.floor(w + 10.5)))
        chev:SetDown(f:IsOpen())
        Paint()
    end
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function() f:Toggle() end)
    row:SetScript("OnEnter", function() f.hot = true Paint() end)
    row:SetScript("OnLeave", function() f.hot = nil Paint() end)
    AT.Tooltip(row, title, function()
        if f:Changed() then return "Stays open while one of these differs from its default." end
        return "Fine-tuning for the rows above. Click to show or hide it."
    end)
    return f
end

-- base: every gate of the row but its dep (what the search reads); vis: the
-- row's own visibility; changed(rec): it holds a value you set. Returns the
-- row's visibility behind the fold.
function Fold:Add(base, vis, changed)
    self.items[#self.items + 1] = { base = base, vis = vis, changed = changed }
    local f = self
    return function() return vis() and f:IsOpen() end
end

-- The rows it holds that show when it is open.
function Fold:Count()
    local n = 0
    for _, it in ipairs(self.items) do
        if it.vis() then n = n + 1 end
    end
    return n
end

function Fold:Changed()
    local rec = self.ctx and self.ctx()
    if not rec then return false end
    for _, it in ipairs(self.items) do
        if it.changed(rec) then return true end
    end
    return false
end

function Fold:IsOpen()
    return ET.ShowAll() or ET.FoldState()[self.key] == true or self:Changed()
end

-- With Show every option on, the rows show inline and the fold row goes.
function Fold:HeadShown()
    return not ET.ShowAll() and self:Count() > 0
end

-- A fold held open (a changed value, Show every option) ignores the click.
function Fold:Toggle()
    AT.CloseDropdown()
    if ET.ShowAll() or self:Changed() then return end
    local st = ET.FoldState()
    local open = st[self.key] ~= true
    st[self.key] = open or nil
    PlaySound(open and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    AT.LayoutPage(self.pg)
end

-- The search opens a fold before it flashes a row inside.
function Fold:Open()
    ET.FoldState()[self.key] = true
end

-- Cards

-- A glow or sound card: the theme's card (AT.Card) on one of the record's
-- switches. Its header is that switch's row for the search, and the card shows
-- while the switch's row would. spec: vis, ctx, family, section, switch (a bool
-- field), name, when (words, or a function(rec) giving them), word (the
-- switch's own name, for its tooltip). Add the rows, then ET.CardEnd.
function ET.CardStart(pg, spec)
    local fam = Schema[spec.family]
    local def = fam and fam[spec.section] and fam[spec.section].fields[spec.switch]
    -- every gate of the switch's row but its tab
    local function shows()
        if not spec.vis() then return false end
        local r = spec.ctx()
        return r ~= nil and def ~= nil and Options.FieldShows(r, spec.family, spec.section, def) == true
    end
    local when = spec.when
    local c = AT.Card(pg, {
        title = spec.name,
        note = function()
            if type(when) ~= "function" then return when end
            local r = spec.ctx()
            return r and when(r) or ""
        end,
        isOn = function()
            local r = spec.ctx()
            return r ~= nil and Store.Resolve(r, spec.section, spec.switch) == true
        end,
        setOn = function(v)
            local r = spec.ctx()
            if not r then return end
            Store.SetOverride(r, spec.section, spec.switch, v)
            if def and def.onSet then def.onSet(r, v) end
        end,
        visibleFn = shows,
        tip = { spec.word or (def and def.label) or spec.switch,
            (def and def.desc) or "Off keeps its settings, greyed out." },
    })
    c.adSpec = spec
    -- the switch's row for the search: found by its label, flashed by a jump
    c.head._adMeta = { family = spec.family, section = spec.section, field = spec.switch, def = def or {},
        baseVis = shows }
    c.head._adCardHead = c
    return c
end

-- Marks the card's rows, which the search's jump reads, and counts a sound
-- row's Play button in the card's width.
function ET.CardEnd(c)
    for _, r in ipairs(c:Rows()) do
        r._adCard = c
        local m = r._adMeta
        if m and m.def and m.def.t == "sound" then r._colTrail = 58 end
    end
    return c
end

local function Measure(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    return math.ceil(w)
end

-- Card words

-- A glow card names its lane, so its rows take short words.
local GLOW_WORDS = { Type = "Style", Color = "Color", CombatOnly = "Only in combat", For = "Glow for",
    When = "Glow when", TimeUnit = "Time left in", TimePct = "Under this % left",
    TimeSec = "Under this many seconds left", AuraLength = "The aura lasts (seconds)",
    Speed = "Speed", Lines = "Lines", Thickness = "Thickness", Length = "Line length (0 = auto)",
    Particles = "Particles", Intensity = "Intensity", Scale = "Size", XOffset = "X offset",
    YOffset = "Y offset", MoveX = "Move X", MoveY = "Move Y", Strata = "Strata", Level = "Frame level" }
-- switch, look, gates, then the tuning (the tuning folds away)
local GLOW_ORDER = { "Type", "Color", "CombatOnly", "For", "When", "TimeUnit", "TimePct", "TimeSec",
    "AuraLength", "Speed", "Lines", "Thickness", "Length", "Particles", "Intensity", "Scale", "XOffset",
    "YOffset", "MoveX", "MoveY", "Strata", "Level" }

-- When each glow card fires, in plain words for its header.
local WARN_WORDS = { ammo = "your ammo runs low", petHealth = "your pet's health is low",
    petMood = "your pet is not happy" }
local AURA_WORDS = { always = "the aura is up", pandemic = "the last 30% of it", time = "little time is left" }
ET.GLOW_WHEN = {
    ready = "cooldown done",
    active = function(rec) return rec.kind == "totem" and "the totem is out" or "the weapon has it" end,
    proc = "the proc glow is up",
    usable = "you can cast it now",
    overlay = "its aura is up",
    warn = function(rec) return WARN_WORDS[Store.Resolve(rec, "states", "warnGlowWhen")] or "" end,
}

-- An aura glow's words follow its own Glow when.
function ET.AuraGlowWhen(suffix)
    local field = "activeGlowWhen" .. (suffix or "")
    return function(rec) return AURA_WORDS[Store.Resolve(rec, "auraActive", field)] or "" end
end

-- A glow card's fields in card order and the words its rows show. extra: a
-- lane's own gate rows after Glow when ({ field, words } pairs).
function ET.GlowCard(section, prefix, suffix, switchWord, extra)
    suffix = suffix or ""
    local defs = Schema.icon[section].fields
    local sw = prefix .. suffix
    local fields, words = { sw }, { [sw] = switchWord }
    for _, part in ipairs(GLOW_ORDER) do
        local f = prefix .. part .. suffix
        if defs[f] then
            fields[#fields + 1] = f
            words[f] = GLOW_WORDS[part]
        end
        if part == "When" and extra then
            for _, e in ipairs(extra) do
                fields[#fields + 1] = e[1]
                words[e[1]] = e[2]
            end
        end
    end
    return fields, words
end

-- The state table

local S, A, M, O = "states", "auraActive", "auraMissing", "outOfStock"
local READY = { label = "Ready", when = "while it is ready", alpha = { S, "readyAlpha" },
    tint = { S, "readyTintColor", on = "readyTintEnabled" },
    alphaTip = "0 hides it; the rules under the table can bring it back." }
local COOLDOWN = { label = "On cooldown", when = "while it is on cooldown", alpha = { S, "cooldownAlpha" },
    grey = { S, "cooldownDesaturate" }, tint = { S, "cooldownTintColor", on = "cooldownTintEnabled" } }
local OUT_OF_STOCK = { label = "Out of stock", when = "while none is left", alpha = { O, "outAlpha", on = "outAlphaEnabled" },
    grey = { O, "outDesaturate" },
    onTip = "On: this opacity while none is left. Off: it keeps its opacity." }
-- One entry per state a kind has, in order: its words, then the field each
-- column drives as { section, field }. A tint's switch is `on`, or `shared`
-- when one switch serves two rows; an opacity with `on` has a switch before
-- its slider. A missing column is a dash; `never` puts words in its place.
ET.STATES = {
    spell = {
        READY, COOLDOWN,
        { label = "Can't use it", when = "while it can't be used", alpha = { S, "unusableAlpha" },
          grey = { S, "unusableDesaturate" }, tint = { S, "unusableTintColor", shared = "usabilityTint" },
          alphaTip = "Never brighter than Ready's opacity." },
        { label = "Not enough resource", when = "while you lack the resource for it", alpha = { S, "resourceAlpha" },
          grey = { S, "resourceDesaturate" }, tint = { S, "resourceTintColor", shared = "usabilityTint" },
          alphaTip = "Never brighter than Ready's opacity." },
        { label = "Out of range", when = "while your target is out of range", never = "never dims",
          neverTip = "Out of range never dims the icon: its tint marks it instead.",
          tint = { S, "rangeTintColor", on = "rangeTint" } },
        { label = "Aura active", when = "while its aura is up", overlay = true, alpha = { A, "activeAlpha" },
          grey = { A, "activeDesaturate" }, tint = { A, "activeTintColor", on = "activeTintEnabled" } },
        { label = "Aura missing", when = "while its aura is down", overlay = true,
          grey = { A, "overlayDesatInactive" } },
    },
    aura = {
        { label = "Active", when = "while the aura is up", alpha = { A, "activeAlpha" },
          grey = { A, "activeDesaturate" }, tint = { A, "activeTintColor", on = "activeTintEnabled" } },
        { label = "Missing", when = "while the aura is missing", alpha = { M, "missingAlpha" },
          grey = { M, "missingDesaturate" } },
    },
    item = { READY, COOLDOWN, OUT_OF_STOCK },
    trinket = { READY, COOLDOWN, OUT_OF_STOCK },
    timer = { READY, COOLDOWN },
    totem = {
        { label = "Active", when = "while the totem is out", alpha = READY.alpha, tint = READY.tint },
        { label = "Missing", when = "while no totem is out", alpha = COOLDOWN.alpha, grey = COOLDOWN.grey,
          tint = COOLDOWN.tint },
    },
    enchant = {
        { label = "Active", when = "while the weapon has the enchant", alpha = READY.alpha, tint = READY.tint },
        { label = "Missing", when = "while the weapon has none", alpha = COOLDOWN.alpha, grey = COOLDOWN.grey,
          tint = COOLDOWN.tint },
    },
    ammo = {
        { label = "In stock", when = "while you have ammo", alpha = READY.alpha },
        OUT_OF_STOCK,
    },
}

local COLS = { "alpha", "grey", "tint" }
local COL_WORD = { alpha = "opacity", grey = "grey out", tint = "tint" }
local SLIDER_W, VALUE_W = 72, 38

local function Def(section, field)
    local sec = Schema.icon[section]
    return sec and sec.fields[field], sec
end

local function Applies(rec, section, field)
    local def, sec = Def(section, field)
    return def ~= nil and Schema.Applies(def, sec, Store.KindOf(rec)) == true
end

-- A field's dep, through the editor's own dep rules.
local function DepOK(rec, section, field)
    local def = Def(section, field)
    local dep = def and def.dep
    if not dep then return true end
    local check = Options.DepOK
    if not check then return true end
    if dep.field then return check(rec, "icon", section, dep) end
    for _, d in ipairs(dep) do
        if not check(rec, "icon", section, d) then return false end
    end
    return true
end

local function OverlayOn(rec)
    local DA = NS.DriverAura
    return DA ~= nil and DA.OverlayOn ~= nil and DA.OverlayOn(rec) == true
end

-- The state rows a record shows.
function ET.StatesFor(rec)
    local list = rec and ET.STATES[rec.kind]
    if not list then return nil end
    local out = {}
    for _, st in ipairs(list) do
        if not st.overlay or OverlayOn(rec) then out[#out + 1] = st end
    end
    return out
end

-- Every field the record's table drives, as push parts ({ section, fields }).
function ET.StateParts(rec)
    local bySec, out = {}, {}
    local function add(section, field)
        if not (section and field) or not Applies(rec, section, field) then return end
        local p = bySec[section]
        if not p then
            p = { section = section, fields = {} }
            bySec[section] = p
            out[#out + 1] = p
        end
        for _, f in ipairs(p.fields) do
            if f == field then return end
        end
        p.fields[#p.fields + 1] = field
    end
    for _, st in ipairs(ET.StatesFor(rec) or {}) do
        for _, c in ipairs(COLS) do
            local spec = st[c]
            if spec then
                add(spec[1], spec.on)
                add(spec[1], spec[2])
                add(spec[1], spec.shared)
            end
        end
    end
    return out
end

-- The layout's looks mirror the table as plain rows, one block per state,
-- each field once (a totem's Active is the spell's Ready).
function ET.StateLooks(tabName)
    local seen = {}
    for _, kind in ipairs(Schema.ICON_KINDS) do
        for _, st in ipairs(ET.STATES[kind] or {}) do
            local order, bySec = {}, {}
            for _, c in ipairs(COLS) do
                local spec = st[c]
                if spec then
                    for _, f in ipairs({ spec.on or false, spec[2], spec.shared or false }) do
                        local k = f and (spec[1] .. "." .. f)
                        if k and not seen[k] then
                            seen[k] = true
                            if not bySec[spec[1]] then
                                bySec[spec[1]] = {}
                                order[#order + 1] = spec[1]
                            end
                            table.insert(bySec[spec[1]], f)
                        end
                    end
                end
            end
            for _, section in ipairs(order) do
                Options.LookBlock("icon", tabName, st.label, section, bySec[section])
            end
        end
    end
end

local function Tip(region, title, body)
    AT.Tooltip(region, title, body)
end

-- A hairline strip on a row, in the table's line colour.
local function Strip(row)
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetTexture(AT.WHITE)
    t:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    return t
end

-- The box a row draws of the table: its sides and its bottom edge, and the
-- top edge on the header.
local function TableEdges(row, top)
    local e = { l = Strip(row), r = Strip(row), b = Strip(row) }
    if top then e.t = Strip(row) end
    return function(w)
        local px = AT.Hairline(row)
        e.l:ClearAllPoints()
        e.l:SetPoint("TOPLEFT", 4, 0)
        e.l:SetPoint("BOTTOMLEFT", 4, 0)
        e.l:SetWidth(px)
        e.r:ClearAllPoints()
        e.r:SetPoint("TOPLEFT", w, 0)
        e.r:SetPoint("BOTTOMLEFT", w, 0)
        e.r:SetWidth(px)
        e.b:ClearAllPoints()
        e.b:SetPoint("BOTTOMLEFT", 4, 0)
        e.b:SetWidth(w - 4 + px)
        e.b:SetHeight(px)
        if e.t then
            e.t:ClearAllPoints()
            e.t:SetPoint("TOPLEFT", 4, 0)
            e.t:SetWidth(w - 4 + px)
            e.t:SetHeight(px)
        end
    end
end

-- A compact opacity slider with its value, as AT.RowSlider but narrower.
local function OpacityCell(cell, get, set)
    local s = CreateFrame("Slider", nil, cell, "BackdropTemplate")
    local box = CreateFrame("EditBox", nil, cell, "BackdropTemplate")
    local settingUp = true
    local function fmt(v) return ("%d%%"):format(math.floor((tonumber(v) or 0) * 100 + 0.5)) end
    local function refresh()
        settingUp = true
        s:SetValue(math.max(0, math.min(1, get() or 0)))
        if not box:HasFocus() then box:SetText(fmt(get() or 0)) end
        settingUp = false
    end
    s:SetOrientation("HORIZONTAL")
    s:SetSize(SLIDER_W, 10)
    AT.Skin(s, COL.well)
    s:SetThumbTexture(AT.WHITE)
    local th = s:GetThumbTexture()
    th:SetSize(8, 10)
    th:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    s:SetMinMaxValues(0, 1)
    s:SetValueStep(0.01)
    s:SetObeyStepOnDrag(true)
    s:SetScript("OnValueChanged", function(_, v)
        if settingUp then return end
        v = math.floor(v * 100 + 0.5) / 100
        if not box:HasFocus() then box:SetText(fmt(v)) end
        set(v)
    end)
    box:SetSize(VALUE_W, 16)
    AT.Skin(box, COL.well)
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    local function commit(self)
        local n = tonumber(((self:GetText() or ""):gsub("%%", "")))
        if n then set(math.max(0, math.min(1, math.floor(n + 0.5) / 100))) end
        refresh()
    end
    box:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetPoint("LEFT", s, "RIGHT", 6, 0)
    refresh()
    return s, box, refresh
end

-- One state row: its words, then one cell per column.
local function StateRow(pg, T, ctx, vis, kind, st)
    local row = AT.AddRow(pg, 28, function()
        if not vis() then return false end
        local r = ctx()
        if not (r and r.kind == kind) then return false end
        return not st.overlay or OverlayOn(r)
    end)
    row._adStateRow = st
    row._adStateKind = kind
    local lbl = row:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(STANDARD_TEXT_FONT, 12, "")
    lbl:SetPoint("LEFT", 14, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    lbl:SetText(st.label)
    row._adLabel = lbl
    local frame = TableEdges(row, false)
    row._adCells = {}

    local function Rec() return ctx() end
    local function Get(section, field)
        local r = Rec()
        return r and Store.Resolve(r, section, field)
    end
    local function Put(section, field, v)
        local r = Rec()
        if r then Store.SetOverride(r, section, field, v) end
    end
    local function Relay() AT.LayoutPage(pg) end

    for _, c in ipairs(COLS) do
        local spec = st[c]
        local cell = CreateFrame("Frame", nil, row)
        cell:SetHeight(24)
        cell:EnableMouse(true)
        local C = { frame = cell, col = c, spec = spec, parts = {} }
        row._adCells[c] = C
        local dash = cell:CreateFontString(nil, "OVERLAY")
        dash:SetFont(STANDARD_TEXT_FONT, 12, "")
        dash:SetPoint("LEFT", 0, 0)
        dash:SetTextColor(COL.line2[1], COL.line2[2], COL.line2[3])
        dash:SetText((c == "alpha" and st.never) or "-")
        C.dash = dash
        local stateWord = st.when or ""
        -- a dash explains itself; a cell with controls leaves it to them
        Tip(cell, st.label .. ": " .. COL_WORD[c], function()
            if C.has then return nil end
            if c == "alpha" and st.never then return st.neverTip end
            return st.label .. " has no " .. COL_WORD[c] .. " look."
        end)
        if spec then
            local section, field = spec[1], spec[2]
            local def = Def(section, field)
            local lab = (def and def.label) or field
            if c == "alpha" then
                if spec.on then
                    local ondef = Def(section, spec.on)
                    local cb = AT.MakeCheckbox(cell)
                    cb:SetPoint("LEFT", 0, 0)
                    cb:SetScript("OnClick", function()
                        AT.CloseDropdown()
                        Put(section, spec.on, Get(section, spec.on) ~= true)
                        PlaySound(Get(section, spec.on) == true and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
                        Relay()
                    end)
                    cb:HookScript("OnEnter", function() cb:SetHover(true) end)
                    cb:HookScript("OnLeave", function() cb:SetHover(false) end)
                    Tip(cb, (ondef and ondef.label) or spec.on, st.onTip or (ondef and ondef.desc) or "")
                    C.on = cb
                end
                local s, box, refresh = OpacityCell(cell,
                    function() return Get(section, field) or (def and def.d) or 1 end,
                    function(v) Put(section, field, v) end)
                s:SetPoint("LEFT", spec.on and 24 or 0, 0)
                local body = (def and def.desc) or ("How visible the icon is " .. stateWord .. ". "
                    .. (st.alphaTip or "0 hides it."))
                Tip(s, lab, body)
                Tip(box, lab, body)
                C.slider, C.box, C.refresh = s, box, refresh
            elseif c == "grey" then
                local cb = AT.MakeCheckbox(cell)
                cb:SetPoint("LEFT", 0, 0)
                cb:SetScript("OnClick", function()
                    AT.CloseDropdown()
                    Put(section, field, Get(section, field) ~= true)
                    PlaySound(Get(section, field) == true and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
                    Relay()
                end)
                cb:HookScript("OnEnter", function() cb:SetHover(true) end)
                cb:HookScript("OnLeave", function() cb:SetHover(false) end)
                Tip(cb, lab, (def and def.desc) or ("Greys the icon out " .. stateWord .. "."))
                C.check = cb
            else
                local x = 0
                if spec.on then
                    local ondef = Def(section, spec.on)
                    local cb = AT.MakeCheckbox(cell)
                    cb:SetPoint("LEFT", 0, 0)
                    cb:SetScript("OnClick", function()
                        AT.CloseDropdown()
                        Put(section, spec.on, Get(section, spec.on) ~= true)
                        PlaySound(Get(section, spec.on) == true and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
                        Relay()
                    end)
                    cb:HookScript("OnEnter", function() cb:SetHover(true) end)
                    cb:HookScript("OnLeave", function() cb:SetHover(false) end)
                    Tip(cb, (ondef and ondef.label) or spec.on,
                        (ondef and ondef.desc) or ("Colors the icon " .. stateWord .. "."))
                    C.on = cb
                    x = 24
                end
                local sw = AT.MakeSwatch(cell, 24, 14)
                sw:SetPoint("LEFT", x, 0)
                -- no opacity slider: a tint's alpha belongs to the state opacity
                sw:SetScript("OnClick", function()
                    AT.CloseDropdown()
                    local picker = ColorPickerFrame
                    if not (picker and picker.SetupColorPickerAndShow) then return end
                    local r = Rec()
                    if not r then return end
                    local col = Get(section, field) or (def and def.d) or { 1, 1, 1, 1 }
                    local was = { col[1], col[2], col[3], col[4] }
                    local ready, last = false, nil
                    local function pick()
                        if not ready then return end
                        local cr, cg, cb2 = picker:GetColorRGB()
                        if last and last[1] == cr and last[2] == cg and last[3] == cb2 then return end
                        last = { cr, cg, cb2 }
                        local cur = Get(section, field)
                        local a = (type(cur) == "table" and cur[4]) or (def and type(def.d) == "table" and def.d[4]) or 1
                        Put(section, field, { cr, cg, cb2, a })
                        Relay()
                    end
                    picker:SetupColorPickerAndShow({
                        r = col[1], g = col[2], b = col[3], hasOpacity = false,
                        swatchFunc = pick,
                        cancelFunc = function()
                            Put(section, field, { was[1], was[2], was[3], was[4] })
                            Relay()
                        end,
                    })
                    ready = true
                end)
                local body = (def and def.desc) or ("The color " .. stateWord .. ".")
                if spec.shared then
                    local sdef = Def(section, spec.shared)
                    body = body .. " " .. ((sdef and sdef.label) or spec.shared)
                        .. ", under the table, switches it with the other usability color."
                end
                Tip(sw, lab, body)
                C.swatch = sw
            end
        end
    end

    -- the cells, re-read and placed on the table's columns every pass
    row._sync = function()
        local r = Rec()
        if not (r and T.c1) then return end
        frame(T.w)
        local xs = { alpha = T.c1, grey = T.c2, tint = T.c3 }
        local ws = { alpha = T.w1, grey = T.w2, tint = T.w3 }
        for _, c in ipairs(COLS) do
            local C = row._adCells[c]
            C.frame:ClearAllPoints()
            C.frame:SetPoint("LEFT", xs[c], 0)
            C.frame:SetWidth(ws[c])
            local spec = C.spec
            local has = spec ~= nil and Applies(r, spec[1], spec[2])
            C.has = has
            C.dash:SetShown(not has)
            for _, w in ipairs({ C.on or false, C.slider or false, C.box or false, C.check or false, C.swatch or false }) do
                if w then w:SetShown(has) end
            end
            if has then
                local section, field = spec[1], spec[2]
                local ok = DepOK(r, section, field)
                if C.on then C.on:SetOn(Store.Resolve(r, section, spec.on) == true) end
                if C.refresh then C.refresh() end
                if C.check then C.check:SetOn(Store.Resolve(r, section, field) == true) end
                if C.swatch then
                    local col = Store.Resolve(r, section, field) or { 1, 1, 1 }
                    C.swatch:SetColor({ col[1] or 1, col[2] or 1, col[3] or 1 })
                end
                -- a cell whose dep fails dims in place, so the table never jumps
                for _, w in ipairs({ C.slider or false, C.box or false, C.check or false, C.swatch or false }) do
                    if w then
                        w:SetAlpha(ok and 1 or 0.45)
                        w:EnableMouse(ok)
                    end
                end
                C.enabled = ok
            end
        end
    end

    -- every cell's option, for the search
    row._adSearch = function()
        local out = {}
        local r = Rec()
        if not r then return out end
        for _, c in ipairs(COLS) do
            local spec = st[c]
            if spec then
                for _, f in ipairs({ spec.on or false, spec[2] }) do
                    if f and Applies(r, spec[1], f) then
                        local def = Def(spec[1], f)
                        out[#out + 1] = (def and def.label) or f
                    end
                end
            end
        end
        return out
    end
    T.rows[#T.rows + 1] = row
    return row
end

-- The table: a header row, then one row per state of the record's kind. It
-- joins the section open on pg; vis gates the whole table.
function ET.StateTable(pg, ctx, vis)
    local T = { rows = {} }
    local head = AT.AddRow(pg, 24, function()
        return vis() and ET.StatesFor(ctx()) ~= nil
    end)
    head._adStateHead = T
    local fill = head:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture(AT.WHITE)
    fill:SetVertexColor(COL.box[1], COL.box[2], COL.box[3], 1)
    fill:SetPoint("TOPLEFT", 4, 0)
    fill:SetPoint("BOTTOMLEFT", 4, 0)
    local frame = TableEdges(head, true)
    local heads = {}
    for i, text in ipairs({ "STATE", "OPACITY", "GREY OUT", "TINT" }) do
        local fs = head:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 10, "")
        fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(text)
        heads[i] = fs
    end
    T.heads = heads
    -- The columns, measured from the rows the record shows: the header runs
    -- first in its section, so every row after it reads these.
    head._sync = function()
        local r = ctx()
        local lw = Measure(heads[1])
        local hasOn = false
        for _, row in ipairs(T.rows) do
            if row._visibleFn() then
                lw = math.max(lw, Measure(row._adLabel))
                local a = row._adStateRow.alpha
                if a and a.on then hasOn = true end
            end
        end
        if not r then return end
        local w1 = math.max((hasOn and 24 or 0) + SLIDER_W + 6 + VALUE_W, Measure(heads[2]))
        local w2 = math.max(18, Measure(heads[3]))
        local w3 = math.max(24 + 24, Measure(heads[4]))
        T.c1 = 14 + lw + 18
        T.c2 = T.c1 + w1 + 18
        T.c3 = T.c2 + w2 + 18
        T.w1, T.w2, T.w3 = w1, w2, w3
        T.w = T.c3 + w3 + 12
        heads[1]:ClearAllPoints()
        heads[1]:SetPoint("LEFT", 14, 0)
        heads[2]:ClearAllPoints()
        heads[2]:SetPoint("LEFT", T.c1, 0)
        heads[3]:ClearAllPoints()
        heads[3]:SetPoint("LEFT", T.c2, 0)
        heads[4]:ClearAllPoints()
        heads[4]:SetPoint("LEFT", T.c3, 0)
        fill:SetWidth(T.w - 4)
        frame(T.w)
    end
    T.head = head
    for _, kind in ipairs(Schema.ICON_KINDS) do
        for _, st in ipairs(ET.STATES[kind] or {}) do
            Options.BuildYield()
            StateRow(pg, T, ctx, vis, kind, st)
        end
    end
    ET.lastTable = T
    return T
end

-- Old picks

-- Tab and sub-tab names before the regroup, and where their rows went. A
-- pick that names an old place lands there, never on an empty page.
local ICON_STATE_TABS = { ["Spell State"] = true, ["Aura State"] = true, ["Item State"] = true,
    ["Timer State"] = true, ["Totem State"] = true, ["Enchant State"] = true }
local ICON_STATE_SUB = { Proc = { "Glows" }, Warning = { "Glows" }, Pulse = { "Appearance", "Icon" },
    ["Aura Swipe"] = { "Appearance", "Swipe" } }
local ICON_SUB = {
    Appearance = { Size = { "Appearance", "Icon" }, Look = { "Appearance", "Icon" },
        Visibility = { "Show & Hide", "Fade When" } },
    Position = { Mouse = { "Position", "Position" } },
    Text = { ["Duration Text"] = { "Text", "Duration" }, ["Stack & Charges"] = { "Text", "Stacks" },
        ["Ammo Stack Text"] = { "Text", "Stacks" }, Keybind = { "Text", "Labels & Keybind" },
        ["Label 1"] = { "Text", "Labels & Keybind" }, ["Label 2"] = { "Text", "Labels & Keybind" },
        ["Label 3"] = { "Text", "Labels & Keybind" } },
}
-- a bar tab that went away: its rows' new tab and sub-tab
ET.BAR_TAB_HOME = { Thresholds = { "Appearance", "Fill & Colors" }, ["Color Changes"] = { "Appearance", "Fill & Colors" },
    Behavior = { "Show & Hide", "By State" } }
local BAR_SUB = {
    Appearance = { Style = "Size & Frame", ["Bar Size"] = "Size & Frame", Scale = "Size & Frame",
        Background = "Size & Frame", Border = "Size & Frame", Fill = "Fill & Colors",
        Direction = "Fill & Colors", ["Point Colors"] = "Fill & Colors", Segments = "Fill & Colors",
        ["Cost Preview"] = "Fill & Colors", ["Off-hand"] = "Swing", ["Next Swing"] = "Swing",
        Spark = true, Visibility = { "Show & Hide", "Fade When" } },
}
-- tabs that stack their blocks: no sub-tab pick
local BAR_STACKED = { ["Heals & Shields"] = true, Castbar = true }

-- The new home of an old (tab, sub-tab) pick; an unchanged pick comes back
-- as it went in. rec: the record, for a bar's Spark.
function ET.Home(fam, tab, sub, rec)
    if fam == "icon" then
        if ICON_STATE_TABS[tab] then
            local h = ICON_STATE_SUB[sub]
            if h then return h[1], h[2] end
            return "Show & Hide", "By State"
        end
        if tab == "Swipe" then return "Appearance", "Swipe" end
        if tab == "Alerts" then return "Sounds", nil end
        local h = ICON_SUB[tab] and ICON_SUB[tab][sub]
        if h then return h[1], h[2] end
        return tab, sub
    end
    if fam == "bar" then
        local moved = ET.BAR_TAB_HOME[tab]
        if moved then return moved[1], moved[2] end
        if BAR_STACKED[tab] then return tab, nil end
        local h = BAR_SUB[tab] and BAR_SUB[tab][sub]
        if h == true then
            return tab, (rec and rec.barKind == "swing") and "Swing" or "Fill & Colors"
        end
        if type(h) == "table" then return h[1], h[2] end
        if h then return tab, h end
        return tab, sub
    end
    return tab, sub
end

-- An editor's picks (the open tab and each tab's sub-tab) moved to their
-- new homes. keys: the ui fields ("icoTab", "icoSec" / "barTab", "barSec").
function ET.FixPicks(fam, ui, rec, tabKey, secKey)
    ui[secKey] = ui[secKey] or {}
    local secs = ui[secKey]
    local t = ui[tabKey]
    if t then
        local nt, ns = ET.Home(fam, t, secs[t], rec)
        if nt ~= t then
            secs[t] = nil
            ui[tabKey] = nt
            if ns then secs[nt] = ns end
        elseif ns ~= secs[t] then
            secs[t] = ns
        end
    end
    local old = {}
    for k, v in pairs(secs) do old[#old + 1] = { k, v } end
    for _, kv in ipairs(old) do
        if kv[1] ~= ui[tabKey] then
            local nt, ns = ET.Home(fam, kv[1], kv[2], rec)
            if nt ~= kv[1] then
                secs[kv[1]] = nil
                if ns and secs[nt] == nil then secs[nt] = ns end
            elseif ns ~= kv[2] then
                secs[kv[1]] = ns
            end
        end
    end
end

-- A group's picks: Arrangement is Appearance, and Dynamic, Visibility,
-- Keybinds, Mouse and Audio live inside other tabs now.
function ET.FixGroupPicks(ui, g)
    local t = ui.grpTab
    if t == "Arrangement" then
        ui.grpTab = "Appearance"
        -- a Reminder group's Arrangement held its Container alone
        if g and g.groupKind == "reminder" then ui.grpSec = "Container" end
    elseif t == "Dynamic" then
        ui.grpTab, ui.grpSec = "Appearance", "Grid"
    elseif t == "Visibility" then
        ui.grpTab, ui.grpSec = "Appearance", "Visibility"
    elseif t == "Audio" then
        ui.grpTab = "Sounds"
    elseif t == "Mouse" then
        ui.grpTab, ui.grpPosSec = "Position", "Position"
    end
    if ui.grpSec == "Keybinds" then ui.grpSec = "Icons" end
    if ui.grpPosSec == "Mouse" then ui.grpPosSec = "Position" end
end

Options.RENAMED_BAR_TABS = {}
for k, v in pairs(ET.BAR_TAB_HOME) do Options.RENAMED_BAR_TABS[k] = v[1] end

-- New marks

-- The tabs and sub-tabs the regroup made, marked new for one version
-- (Options.NewBadge), by strip.
ET.BADGES = {
    icon = { ["Show & Hide"] = "tab:showhide", Glows = "tab:glows", Sounds = "tab:sounds" },
    iconSub = { ["Labels & Keybind"] = "sub:labelskeybind" },
    bar = { ["Show & Hide"] = "bar:showhide" },
    barSub = { ["Size & Frame"] = "sub:sizeframe", ["Fill & Colors"] = "sub:fillcolors" },
    group = { Appearance = "grp:appearance" },
    reminder = { Appearance = "rem:appearance", Sounds = "rem:sounds" },
}

-- A strip's marks for the tabs it draws, for AT.TabRow's Set. A strip off
-- screen only peeks, so a mark counts as seen once it has been drawn. active:
-- the tab open now; on screen, its mark goes for good (clicked, jumped to by
-- the search, or a pick kept from before).
function ET.Badges(which, tabs, shown, active)
    local map = ET.BADGES[which]
    if not (map and Options.NewBadges) then return nil end
    if shown and active and map[active] and Options.ClearNew then Options.ClearNew(map[active]) end
    local want
    for _, t in ipairs(tabs or {}) do
        if map[t] then
            want = want or {}
            want[t] = map[t]
        end
    end
    if not want then return nil end
    return Options.NewBadges(want, not shown)
end
