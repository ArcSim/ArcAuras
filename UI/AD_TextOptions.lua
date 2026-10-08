-- AD_TextOptions: a Text element's Add window tab and its Tracking rows: its type (your words, a countdown, a count or some info), what drives it (a spell, an aura, custom triggers), each one's own fields and the Format block.
-- AD_Options calls in behind nil checks (Options.TextAddRows / TextCreate / TextTrackRows / TextWhat); the runtime is Bars\AD_TextElement.lua, the rules editor UI\AD_CustomOptions.lua's.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local TO = {}
Options.TextElement = TO

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Items(values, labels)
    local out = {}
    for _, v in ipairs(values or {}) do out[#out + 1] = { value = v, text = (labels and labels[v]) or tostring(v) } end
    return out
end

function TO.Runtime() return NS.TextElements end

-- The sources this client can feed: an engine a source needs must be there.
function TO.SourceItems()
    local S = NS.Schema
    local out = {}
    for _, s in ipairs(S.TEXT_SOURCES or {}) do
        local ok = true
        if s == "auraTime" or s == "auraStacks" or s == "auraText" then
            ok = NS.DriverAura ~= nil and NS.DriverAura.IsAvailable ~= nil and NS.DriverAura.IsAvailable() == true
        elseif s == "rules" or s == "custom" then
            ok = NS.DriverCustom ~= nil
        elseif s == "range" then
            ok = NS.RangeBars ~= nil and NS.DriverRange ~= nil
        elseif s == "spellCd" then
            ok = C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil
        elseif s == "spellCharges" then
            ok = C_Spell ~= nil and C_Spell.GetSpellCharges ~= nil
        elseif s == "petMood" or s == "ammo" then
            ok = NS.IsForever == true
        end
        if ok then out[#out + 1] = { value = s, text = S.TEXT_SOURCE_LABELS[s] or s } end
    end
    return out
end

-- A text is a type first (your words, a countdown, a count or some info),
-- then what drives it. Each type and trigger is one runtime source, so a
-- saved text reads as its type and trigger from what it already stores.
TO.KINDS = { "custom", "duration", "stack", "info" }
TO.KIND_LABELS = { custom = "Custom text", duration = "Duration text", stack = "Stack text", info = "Info text" }
TO.KIND_NOTES = {
    custom = "Your own words, shown on the state you pick.",
    duration = "Counts down a spell's cooldown, an aura's time left or a custom timer.",
    stack = "Counts a spell's charges, an aura's stacks or custom stacks.",
    info = "Your power, health, a name and more.",
}
TO.TRIGGERS = {
    custom = { "spell", "aura", "rules", "none" },
    duration = { "spell", "aura", "rules", "item" },
    stack = { "spell", "aura", "rules", "item" },
}
TO.TRIGGER_LABELS = { spell = "A spell", aura = "An aura", rules = "Custom triggers",
    none = "None (always shown)", item = "A Custom Icon or Bar" }
-- [type][trigger] = the source that shows it
TO.SOURCE_OF = {
    custom = { spell = "spellText", aura = "auraText", rules = "static", none = "static" },
    duration = { spell = "spellCd", aura = "auraTime", rules = "rules", item = "custom" },
    stack = { spell = "spellCharges", aura = "auraStacks", rules = "rules", item = "custom" },
}
-- the info texts' sources, in their list's order
TO.INFO = { "power", "health", "name", "combo", "ammo", "petMood", "range", "clock" }
-- a spell's or an aura's own sources: its art on the rail, its auto name
TO.SHOWS = {
    spell = { "spellCd", "spellCharges", "spellText" },
    aura = { "auraTime", "auraStacks", "auraText" },
}
-- A text's name follows its spell or aura ("Serpent Sting duration") until the
-- player names it: a name that is still the one it was given, or an older
-- default, moves with the spell, the aura, the type and the trigger.
TO.NAME_WORDS = { spellCd = "cooldown", spellCharges = "charges", spellText = "text",
    auraTime = "duration", auraStacks = "stacks", auraText = "text" }
TO.NAMES = { spellCd = "Spell cooldown", spellCharges = "Spell charges", spellText = "Spell text",
    auraTime = "Aura duration", auraStacks = "Aura stacks", auraText = "Aura text" }
-- a custom timer's text, or another item's, by what it counts
TO.RULE_NAMES = { duration = "Timer text", stack = "Stacks text" }
TO.ITEM_NAMES = { duration = "Item time left", stack = "Item stacks" }
-- names given before these: the source labels and the first defaults
TO.OLD_NAMES = { Text = true, ["Cooldown text"] = true, ["Charges text"] = true, ["Custom text"] = true,
    ["Aura time text"] = true, ["Stacks text"] = true }
for _, n in pairs(NS.Schema and NS.Schema.TEXT_SOURCE_LABELS or {}) do TO.OLD_NAMES[n] = true end
for _, list in ipairs({ TO.NAMES, TO.RULE_NAMES, TO.ITEM_NAMES }) do
    for _, n in pairs(list) do TO.OLD_NAMES[n] = true end
end

local KNOWN = {}
for _, s in ipairs(NS.Schema and NS.Schema.TEXT_SOURCES or {}) do KNOWN[s] = true end

-- a driver's source as the runtime reads it: an unknown one is typed words
local function SourceOf(d)
    local s = d and d.source
    return KNOWN[s] and s or "static"
end

-- A driver's type: words, a countdown, a count or some info.
function TO.KindOf(d)
    local s = SourceOf(d)
    if s == "static" or s == "spellText" or s == "auraText" then return "custom" end
    if s == "spellCd" or s == "auraTime" then return "duration" end
    if s == "spellCharges" or s == "auraStacks" then return "stack" end
    if s == "rules" or s == "custom" then return ((d.show or "stacks") == "left") and "duration" or "stack" end
    return "info"
end

-- What drives it; nil for an info text. Typed words with a rule list (even an
-- empty one) are on custom triggers.
function TO.TriggerOf(d)
    local s = SourceOf(d)
    if s == "spellCd" or s == "spellCharges" or s == "spellText" then return "spell" end
    if s == "auraTime" or s == "auraStacks" or s == "auraText" then return "aura" end
    if s == "rules" then return "rules" end
    if s == "custom" then return "item" end
    if s == "static" then return (type(d.rules) == "table") and "rules" or "none" end
    return nil
end

-- nil for a text on another source: its name is its own
function TO.AutoName(rec)
    local d = rec.driver or {}
    local w = TO.NAME_WORDS[d.source]
    if not w then return nil end
    local nm = d.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(d.spellID) -- raw-id: the typed spell names the element
    if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" or nm == "" then return TO.NAMES[d.source] end
    return nm .. " " .. w
end

function TO.NameIsAuto(rec)
    local n = rec.name
    if type(n) ~= "string" or n == "" or TO.OLD_NAMES[n] then return true end
    return n == TO.AutoName(rec)
end

-- A change to the spell, the aura, the type or the trigger: the name moves
-- with it when it was never the player's own.
function TO.Follow(r, change)
    local auto = TO.NameIsAuto(r)
    change()
    if not auto then return end
    local d = r.driver or {}
    local nm = TO.AutoName(r) or TO.DefaultName(d.source, d.show)
    if nm and nm ~= r.name then NS.Store.Rename(r.id, nm) end
end

-- A text opened with an older default name catches up once, a frame later
-- (never a rename in the middle of laying out the page).
TO.catchUp = {}
function TO.CatchUpName(r)
    if not (r and r.type == "bar" and r.barKind == "text") or TO.catchUp[r.id] then return end
    if not TO.NameIsAuto(r) then return end
    local nm = TO.AutoName(r)
    if not nm or nm == r.name then return end
    local id = r.id
    TO.catchUp[id] = true
    C_Timer.After(0, function()
        TO.catchUp[id] = nil
        local cur = NS.Store.Get(id)
        if not (cur and TO.NameIsAuto(cur)) then return end
        local want = TO.AutoName(cur)
        if want and want ~= cur.name then NS.Store.Rename(id, want) end
    end)
end

function TO.Subject(source)
    for subj, list in pairs(TO.SHOWS) do
        for _, s in ipairs(list) do
            if s == source then return subj end
        end
    end
    return "other"
end

-- a kind's own first values, so its first draw means something
function TO.SourceDefaults(d, s)
    if (s == "health" or s == "name") and not d.unit then d.unit = "player" end
    if s == "rules" and type(d.rules) ~= "table" then d.rules = {} end
end

-- the sources this client feeds, keyed
local function Offered()
    local out = {}
    for _, it in ipairs(TO.SourceItems()) do out[it.value] = true end
    return out
end

-- A trigger this client can run for a type: custom triggers need the rule
-- engine, the rest their type's source. ok: Offered(), when the caller has it.
function TO.TriggerOK(kind, trig, ok)
    local s = TO.SOURCE_OF[kind] and TO.SOURCE_OF[kind][trig]
    if not s then return false end
    if trig == "rules" or trig == "item" then return NS.DriverCustom ~= nil end
    return (ok or Offered())[s] == true
end

function TO.FirstTrigger(kind)
    local ok = Offered()
    for _, t in ipairs(TO.TRIGGERS[kind] or {}) do
        if TO.TriggerOK(kind, t, ok) then return t end
    end
    return "none"
end

function TO.FirstInfo()
    local ok = Offered()
    for _, s in ipairs(TO.INFO) do
        if ok[s] then return s end
    end
    return "power"
end

-- The types this client can make; cur stays listed on a text that has it.
function TO.KindItems(cur)
    local ok = Offered()
    local out = {}
    for _, k in ipairs(TO.KINDS) do
        local any = (k == cur)
        if k == "info" then
            for _, s in ipairs(TO.INFO) do
                if ok[s] then any = true end
            end
        else
            for _, t in ipairs(TO.TRIGGERS[k]) do
                if TO.TriggerOK(k, t, ok) then any = true end
            end
        end
        if any then out[#out + 1] = { value = k, text = TO.KIND_LABELS[k] } end
    end
    return out
end

-- A type's triggers this client runs; cur stays listed on a text that has it.
function TO.TriggerItems(kind, cur)
    local ok = Offered()
    local out = {}
    for _, t in ipairs(TO.TRIGGERS[kind] or {}) do
        if t == cur or TO.TriggerOK(kind, t, ok) then out[#out + 1] = { value = t, text = TO.TRIGGER_LABELS[t] } end
    end
    return out
end

-- The info kinds this client reads, by their own labels; cur stays listed.
function TO.InfoItems(cur)
    local ok = Offered()
    local labels = NS.Schema.TEXT_SOURCE_LABELS or {}
    local out = {}
    for _, s in ipairs(TO.INFO) do
        if s == cur or ok[s] then out[#out + 1] = { value = s, text = labels[s] or s } end
    end
    return out
end

-- The one writer of a text's type and trigger (or the info it reads): the
-- source that shows them, and the fields that source reads made to fit. The
-- rules leave with the custom triggers pick, a value choice stays only where
-- it still means something, and a new trigger's states start over.
function TO.Retype(d, kind, trig, info)
    local oldTrig = TO.TriggerOf(d)
    local s
    if kind == "info" then
        s = info or ((TO.KindOf(d) == "info") and SourceOf(d)) or TO.FirstInfo()
        trig = nil
    else
        local list = TO.SOURCE_OF[kind] or TO.SOURCE_OF.custom
        if not list[trig] then trig = TO.FirstTrigger(kind) end
        s = list[trig]
    end
    if s == "rules" or s == "custom" then
        if kind == "duration" then
            d.show = "left"
        elseif d.show ~= "both" then
            d.show = nil
        end
    elseif s == "power" or s == "health" then
        if d.show ~= "max" and d.show ~= "percent" then d.show = nil end
    else
        d.show = nil
    end
    if trig == "rules" then
        if type(d.rules) ~= "table" then d.rules = {} end
    elseif oldTrig == "rules" then
        d.rules, d.duration, d.maxStacks, d.clearOnEnd, d.showWhile = nil, nil, nil, nil, nil
    end
    if trig ~= oldTrig then d.when = nil end
    d.source = s
    TO.SourceDefaults(d, s)
end

-- A new type keeps the trigger where the type has one, else takes its first.
function TO.SetKind(d, kind)
    if kind == TO.KindOf(d) then return false end
    local trig = TO.TriggerOf(d)
    if kind ~= "info" and not (trig and TO.TriggerOK(kind, trig)) then trig = TO.FirstTrigger(kind) end
    TO.Retype(d, kind, trig)
    return true
end

function TO.SetTrigger(d, trig)
    if trig == TO.TriggerOf(d) then return false end
    TO.Retype(d, TO.KindOf(d), trig)
    return true
end

function TO.SetInfo(d, s)
    if s == SourceOf(d) then return false end
    TO.Retype(d, "info", nil, s)
    return true
end

-- The states the words show on, the glows' own: what this client can draw.
function TO.WhenItems(source)
    local S = NS.Schema
    local out = {}
    if source == "spellText" then
        for _, w in ipairs(S.TEXT_SPELL_WHEN) do out[#out + 1] = { value = w, text = S.TEXT_SPELL_WHEN_LABELS[w] } end
        return out
    end
    local DA = NS.DriverAura
    for _, w in ipairs(S.TEXT_AURA_WHEN) do
        local ok = true
        if w == "missing" then ok = DA ~= nil and DA.EraserAvailable ~= nil and DA.EraserAvailable() == true end
        if w == "time" then ok = Enum ~= nil and Enum.StatusBarTimerDirection ~= nil end
        if ok then out[#out + 1] = { value = w, text = S.TEXT_AURA_WHEN_LABELS[w] } end
    end
    return out
end

-- Show when's list: a spell's or an aura's states for its words, or what the
-- custom triggers decide (Always first, a text's own default).
function TO.ShowWhenItems(w)
    if w == "spell" then return TO.WhenItems("spellText") end
    if w == "aura" then return TO.WhenItems("auraText") end
    local S = NS.Schema
    local out = { { value = "always", text = "Always" } }
    for _, k in ipairs(S.CUSTOM_SHOW_WHILE) do
        if k ~= "always" then out[#out + 1] = { value = k, text = S.CUSTOM_SHOW_WHILE_LABELS[k] or k } end
    end
    return out
end

-- Which Show when a driver has: its words on a spell's or an aura's state, its
-- custom triggers', or none.
function TO.WhenOf(d)
    local trig = TO.TriggerOf(d)
    if trig == "rules" then return "rules" end
    if TO.KindOf(d) == "custom" and (trig == "spell" or trig == "aura") then return trig end
    return nil
end

function TO.UnitItems()
    local hasFocus = not (C_EventUtils and C_EventUtils.IsEventValid)
        or C_EventUtils.IsEventValid("PLAYER_FOCUS_CHANGED")
    local out = {}
    for _, u in ipairs(NS.Schema.HEALTH_UNITS or { "player", "target", "focus", "pet" }) do
        if u ~= "focus" or hasFocus then out[#out + 1] = { value = u, text = Options.HealthUnitLabel(u) } end
    end
    return out
end

-- every range bar in the store, after the class preset
function TO.RangeItems()
    local Store = NS.Store
    local out = { { value = 0, text = "Your class preset" } }
    for _, lay in ipairs(Store.Layouts()) do
        for _, m in ipairs(Store.MembersOf(lay)) do
            if m.type == "bar" and m.barKind == "range" then
                out[#out + 1] = { value = m.id, text = tostring(m.name) .. " (" .. tostring(lay.name) .. ")" }
            end
        end
    end
    return out
end

-- show: the rule readout, so a custom timer and a custom count differ
function TO.DefaultName(source, show)
    local S = NS.Schema
    if source == "static" then return "Text" end
    if source == "rules" or source == "custom" then
        local kind = ((show or "stacks") == "left") and "duration" or "stack"
        return ((source == "rules") and TO.RULE_NAMES or TO.ITEM_NAMES)[kind]
    end
    return TO.NAMES[source] or (S.TEXT_SOURCE_LABELS and S.TEXT_SOURCE_LABELS[source]) or "Text"
end

-- The editor tabs: Triggers on custom triggers, or on a text that keeps rules
-- of its own from before.
function Options.TextTabs(rec)
    local T = TO.Runtime()
    local tabs = { "Tracking" }
    local rules = TO.TriggerOf(rec.driver or {}) == "rules" or (T and T.HasRules and T.HasRules(rec))
    if rules then tabs[#tabs + 1] = "Triggers" end
    for _, t in ipairs({ "Appearance", "Conditions", "Position", "Load Conditions" }) do tabs[#tabs + 1] = t end
    return tabs
end

-- The sidebar's and cards' one line.
function Options.TextWhat(rec)
    local T = TO.Runtime()
    return T and T.Describe(rec) or "text"
end

local function ParseSpell(text)
    local CO = Options.Custom
    if CO and CO.ParseSpell then return CO.ParseSpell(text) end
    local id = tonumber(Trim(text))
    return (id and id > 0) and math.floor(id) or nil
end

local function SpellName(id)
    local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
    if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" then return "" end
    return nm
end

local function FirstID(text)
    local n = tonumber(tostring(text or ""):match("%d+"))
    return (n and n > 0) and n or nil
end

-- The spell's name after its row's field, from get().
local function NameBeside(row, get)
    local COL = NS.AT.COL
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.AT.FONT, 11, "")
    fs:SetPoint("LEFT", row._colCtrl, "RIGHT", 8, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local sync = row._sync
    row._sync = function()
        if sync then sync() end
        fs:SetText(get() or "")
    end
end

-- The Add window's picks, each checked against what this client offers: a
-- pick the list no longer holds falls back to its first, and the window
-- keeps the pick itself for when it fits again.
local function AddKind(a)
    for _, it in ipairs(TO.KindItems(nil)) do
        if it.value == a.textKind then return it.value end
    end
    return "custom"
end

local function AddTrigger(a, kind)
    for _, it in ipairs(TO.TriggerItems(kind, nil)) do
        if it.value == a.textTrigger then return it.value end
    end
    return TO.FirstTrigger(kind)
end

local function AddInfo(a)
    for _, it in ipairs(TO.InfoItems(nil)) do
        if it.value == a.textInfo then return it.value end
    end
    return TO.FirstInfo()
end

local function AddWhen(a, w)
    local items = TO.ShowWhenItems(w)
    for _, it in ipairs(items) do
        if it.value == a.textWhen then return it.value end
    end
    return items[1] and items[1].value
end

-- The driver the Add window's picks make: what Create stores, and what the
-- name hint is read from.
function TO.AddDriver(a)
    local d = {}
    local kind = AddKind(a)
    if kind == "info" then
        TO.Retype(d, "info", nil, AddInfo(a))
    else
        TO.Retype(d, kind, AddTrigger(a, kind))
    end
    local s, trig = d.source, TO.TriggerOf(d)
    if kind == "custom" then
        local words = Trim(a.textWords)
        d.text = (words ~= "") and words:sub(1, 120) or nil
    end
    if trig == "spell" then
        d.spellID = ParseSpell(a.textSpell)
    elseif trig == "aura" then
        local ids = Options.ParseSpellIDs and Options.ParseSpellIDs(a.textAuraIDs) or {}
        if #ids > 0 and Options.SetAuraSpellIDs then Options.SetAuraSpellIDs(d, ids) end
    elseif trig == "item" and a.textSrcId and a.textSrcId ~= 0 then
        d.srcId = a.textSrcId
    end
    -- Show when: nil is a state's first, and Always for custom triggers
    local w = TO.WhenOf(d)
    if w == "rules" then
        local v = AddWhen(a, w)
        d.showWhile = (v ~= "always") and v or nil
    elseif w then
        local v = AddWhen(a, w)
        d.when = (v ~= ((w == "spell") and "ready" or "up")) and v or nil
    end
    -- an info text's own pick (the Tracking rows' values; defaults unstored)
    if s == "power" then
        local pt = tonumber(a.textPower)
        d.powerType = (pt and pt >= 0) and pt or nil
    end
    if (s == "power" or s == "health") and a.textShow and a.textShow ~= "current" then d.show = a.textShow end
    if s == "health" or s == "name" then d.unit = a.textUnit end
    if s == "range" and a.textRange and a.textRange ~= 0 then d.rangeFrom = a.textRange end
    TO.SourceDefaults(d, s)
    return d
end

local function AddName(a)
    local d = TO.AddDriver(a)
    return TO.AutoName({ driver = d }) or TO.DefaultName(d.source, d.show)
end

-- The Add window: the type, then its trigger (or the info it reads) and that
-- one's own picks, then the name.
function Options.TextAddRows(pg, owner, addState)
    local AT = NS.AT
    local S = NS.Schema
    local vis = function() return addState.cat == "Text" end
    local function Kind() return AddKind(addState) end
    local function Trig()
        local k = Kind()
        return (k ~= "info") and AddTrigger(addState, k) or nil
    end
    local driven = function() return vis() and Kind() ~= "info" end
    local function TrigIs(t) return function() return driven() and Trig() == t end end
    local function InfoIs(...)
        local want = { ... }
        return function()
            if not (vis() and Kind() == "info") then return false end
            local s = AddInfo(addState)
            for _, x in ipairs(want) do
                if s == x then return true end
            end
            return false
        end
    end
    local function When()
        local k, t = Kind(), Trig()
        if t == "rules" then return "rules" end
        if k == "custom" and (t == "spell" or t == "aura") then return t end
        return nil
    end
    local relayout = function() AT.LayoutPage(pg) end
    AT.RowDesc(pg, "Pick what the text is, then what drives it.", 20, vis)
    AT.RowDropdown(pg, owner, "Text type",
        Kind,
        function(v) addState.textKind = v end,
        function() return TO.KindItems(nil) end, vis, relayout)
    AT.RowInput(pg, "Words",
        function() return addState.textWords or "" end,
        function(v) addState.textWords = v end,
        function() return vis() and Kind() == "custom" end,
        "What it says. Tracking can change it later.", "e.g. READY", true)
    AT.RowDropdown(pg, owner, "Trigger",
        function() return Trig() end,
        function(v) addState.textTrigger = v end,
        function() return TO.TriggerItems(Kind(), nil) end, driven, relayout)
    local spellRow = AT.RowInput(pg, "Tracked spell",
        function() return addState.textSpell or "" end,
        function(v) addState.textSpell = v end,
        TrigIs("spell"), "A spell ID, a link, or the name of a spell you know.", "e.g. 19434", true)
    NameBeside(spellRow, function() return SpellName(ParseSpell(addState.textSpell)) end)
    local auraRow = AT.RowInput(pg, "Aura spell IDs",
        function() return addState.textAuraIDs or "" end,
        function(v) addState.textAuraIDs = v end,
        TrigIs("aura"), "The aura's spell IDs, separated by commas or spaces. Tracking sets its unit.",
        "e.g. 13549, 13550", true)
    NameBeside(auraRow, function() return SpellName(FirstID(addState.textAuraIDs)) end)
    AT.RowDropdown(pg, owner, "Custom item",
        function() return addState.textSrcId or 0 end,
        function(v) addState.textSrcId = v end,
        function()
            local CO = Options.Custom
            return CO and CO.ChainItems and CO.ChainItems(nil) or { { value = 0, text = "Pick an item" } }
        end,
        TrigIs("item"))
    AT.RowDesc(pg, "Its rules go on the Triggers tab once it is made.", 20, TrigIs("rules"))
    AT.RowDropdown(pg, owner, "Show when",
        function() return AddWhen(addState, When()) end,
        function(v) addState.textWhen = v end,
        function() return TO.ShowWhenItems(When()) end,
        function() return driven() and When() ~= nil end, relayout)
    AT.RowDropdown(pg, owner, "Shows",
        function() return AddInfo(addState) end,
        function(v) addState.textInfo = v end,
        function() return TO.InfoItems(nil) end,
        function() return vis() and Kind() == "info" end, relayout)
    AT.RowDropdown(pg, owner, "Power shown",
        function() return addState.textPower or -1 end,
        function(v) addState.textPower = tonumber(v) end,
        function()
            if Options.PowerItems then return Options.PowerItems(addState.textPower, true) end
            return { { value = -1, text = "Automatic (current power)" } }
        end,
        InfoIs("power"))
    AT.RowDropdown(pg, owner, "Value",
        function() return addState.textShow or "current" end,
        function(v) addState.textShow = v end,
        function() return Items(S.TEXT_SHOWS, S.TEXT_SHOW_LABELS) end,
        InfoIs("power", "health"))
    AT.RowDropdown(pg, owner, "Health of",
        function() return addState.textUnit or "player" end,
        function(v) addState.textUnit = v end,
        TO.UnitItems, InfoIs("health"))
    AT.RowDropdown(pg, owner, "Name of",
        function() return addState.textUnit or "player" end,
        function(v) addState.textUnit = v end,
        TO.UnitItems, InfoIs("name"))
    AT.RowDropdown(pg, owner, "Bands from",
        function() return addState.textRange or 0 end,
        function(v) addState.textRange = v end,
        TO.RangeItems, InfoIs("range"))
    AT.RowInput(pg, "Name",
        function() return addState.textName or "" end,
        function(v) addState.textName = v end,
        vis, "What the sidebar calls it.", function() return AddName(addState) end, true)
end

function Options.TextCreate(addState, layoutId)
    local d = TO.AddDriver(addState)
    local name = Trim(addState.textName)
    if name == "" then name = TO.AutoName({ driver = d }) or TO.DefaultName(d.source, d.show) end
    return NS.Store.NewBar(layoutId, "text", d, name)
end

-- The Tracking rows. ctx(): the open bar; vis: the Tracking tab. kit:
-- { SectionRows, triggers } from the bar pane: the Format block's schema
-- rows, and the Triggers tab's gate.
function Options.TextTrackRows(pg, ctx, trackVis, owner, kit)
    local AT, Store, S = NS.AT, NS.Store, NS.Schema
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "text" and not r._adMulti) and r or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    local function Source(r)
        local T = TO.Runtime()
        return (r and T) and T.Source(r) or "static"
    end
    local function Kind()
        local r = Rec()
        return r and TO.KindOf(r.driver) or nil
    end
    local function Trig()
        local r = Rec()
        return r and TO.TriggerOf(r.driver) or nil
    end
    local function Is(...)
        local want = { ... }
        return function()
            local r = Rec()
            if not (vis() and r) then return false end
            local s = Source(r)
            for _, w in ipairs(want) do
                if s == w then return true end
            end
            return false
        end
    end
    local function KindIs(k) return function() return vis() and Kind() == k end end
    local function TrigIs(t) return function() return vis() and Trig() == t end end
    -- a driver edit: the record in place, then the page again at once
    local function Set(field, value)
        local r = Rec()
        if not r then return end
        if r.driver[field] == value then return end
        r.driver[field] = value
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end
    -- a type, trigger or info change: the name follows it, the element rebuilds
    local function Retyped(fn)
        local r = Rec()
        if not r then return end
        TO.Follow(r, function() fn(r.driver) end)
        Store.Dirty("tree", r.id)
    end
    -- the rule engine's own fields on the text
    local function SetCustom(field, value)
        local r, CU = Rec(), NS.DriverCustom
        if r and CU and CU.SetDriver then CU.SetDriver(r, field, value) end
        AT.LayoutPage(pg)
    end
    local function HasRules()
        local r, T = Rec(), TO.Runtime()
        return r ~= nil and T ~= nil and T.HasRules(r)
    end
    -- custom triggers drive it, or it keeps rules it was given before
    local rulesVis = function() return vis() and (Trig() == "rules" or HasRules()) end
    local relayout = function() AT.LayoutPage(pg) end

    AT.Section(pg, "Text", { visibleFn = vis })
    local kindRow = AT.RowDropdown(pg, owner, "Text type",
        function() return Kind() or "custom" end,
        function(v)
            if v ~= Kind() then Retyped(function(d) TO.SetKind(d, v) end) end
        end,
        function() return TO.KindItems(Kind()) end, vis, relayout)
    -- the search finds it on every text element (its own field name)
    kindRow._adMeta = { family = "bar", section = "textel", field = "textKind",
        def = { label = "Text type" }, baseVis = vis }
    -- an older default name catches up with its spell or aura when opened
    local kindSync = kindRow._sync
    kindRow._sync = function()
        if kindSync then kindSync() end
        if vis() then TO.CatchUpName(Rec()) end
    end
    for _, k in ipairs(TO.KINDS) do AT.RowDesc(pg, TO.KIND_NOTES[k], 20, KindIs(k)) end
    AT.RowInput(pg, "Words",
        function()
            local r = Rec()
            return (r and r.driver.text) or ""
        end,
        function(v)
            v = Trim(v)
            Set("text", (v ~= "") and v:sub(1, 120) or nil)
        end,
        KindIs("custom"), "What it says. Enter applies it.", "e.g. READY")

    -- what drives it; an info text's section holds the info it reads instead
    AT.Section(pg, "Trigger", { visibleFn = vis })
    local trigSec = pg._curSection
    local driven = function() return vis() and Kind() ~= "info" end
    local trigRow = AT.RowDropdown(pg, owner, "Trigger",
        function() return Trig() or "none" end,
        function(v)
            if v ~= Trig() then Retyped(function(d) TO.SetTrigger(d, v) end) end
        end,
        function() return TO.TriggerItems(Kind(), Trig()) end, driven, relayout)
    trigRow._adMeta = { family = "bar", section = "textel", field = "textTrigger",
        def = { label = "Trigger" }, baseVis = driven }
    local trigSync = trigRow._sync
    trigRow._sync = function()
        if trigSync then trigSync() end
        if trigSec and trigSec.title and vis() then trigSec.title:SetText((Kind() == "info") and "INFO" or "TRIGGER") end
    end
    local infoVis = KindIs("info")
    local infoRow = AT.RowDropdown(pg, owner, "Shows",
        function() return Source(Rec()) end,
        function(v)
            if v ~= Source(Rec()) then Retyped(function(d) TO.SetInfo(d, v) end) end
        end,
        function() return TO.InfoItems(Source(Rec())) end, infoVis, relayout)
    infoRow._adMeta = { family = "bar", section = "textel", field = "textInfo",
        def = { label = "Shows" }, baseVis = infoVis }
    -- a spell: which one
    local spellVis = TrigIs("spell")
    local spellRow = AT.RowInput(pg, "Tracked spell",
        function()
            local r = Rec()
            return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local id = ParseSpell(v)
            if Trim(v) ~= "" and not id then return end
            local r = Rec()
            if r then TO.Follow(r, function() Set("spellID", id) end) end
        end,
        spellVis, "A spell ID, a link, or the name of a spell you know. Enter applies it.",
        "e.g. 17364")
    NameBeside(spellRow, function()
        local r = Rec()
        return r and SpellName(r.driver.spellID)
    end)
    AT.RowToggle(pg, "Follow my rank",
        function()
            local r = Rec()
            return r ~= nil and NS.Store.AutoRankOn(r.driver)
        end,
        -- on by default: only off is stored
        function(v) if v then Set("autoRank", nil) else Set("autoRank", false) end end,
        function() return spellVis() and NS.IsForever == true end,
        "On ranked realms, read whichever rank of this spell you know now.")
    AT.RowDesc(pg, "Counts down the spell's cooldown; blank while it is ready or only the global cooldown runs.", 20,
        Is("spellCd"))
    AT.RowDesc(pg, "How many charges are up; Blank at zero below hides the 0.", 20, Is("spellCharges"))
    -- an aura on a unit: the aura icons' shape
    local auraVis = TrigIs("aura")
    local auraRow = AT.RowInput(pg, "Aura spell IDs",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            local ids = (r and DA) and DA.SpellIDList(r.driver) or {}
            return table.concat(ids, ", ")
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local ids = Options.ParseSpellIDs(v)
            local old = NS.DriverAura and table.concat(NS.DriverAura.SpellIDList(r.driver), ",") or ""
            if table.concat(ids, ",") == old then return end
            TO.Follow(r, function() Options.SetAuraSpellIDs(r.driver, ids) end)
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        auraVis, "The aura's spell IDs, separated by commas or spaces; any of them counts.", "e.g. 13549, 13550")
    NameBeside(auraRow, function()
        local r = Rec()
        return r and SpellName(r.driver.spellID)
    end)
    AT.RowDropdown(pg, owner, "Buff or debuff",
        function()
            local r = Rec()
            return (r and r.driver.auraType == "debuff") and "debuff" or "buff"
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local DA = NS.DriverAura
            local unit = DA and DA.ShapeOf(r.driver) or "player"
            r.driver.auraType = v
            if not Options.AuraUnitAllowed(r.driver, unit, v) then unit = "target" end
            r.driver.unit = unit
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura on unit",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            return (r and DA) and (DA.ShapeOf(r.driver)) or "player"
        end,
        function(v) Set("unit", v) end,
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return {} end
            return Options.AuraUnitItems(r.driver, nil, (DA.ShapeOf(r.driver)))
        end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura cast by",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return "any" end
            local _, _, caster = DA.ShapeOf(r.driver)
            return caster or "any"
        end,
        function(v) Set("caster", (v ~= "any") and v or nil) end,
        function() return Options.AURA_CASTER_ITEMS end,
        auraVis)
    AT.RowDesc(pg, "Buffs work on you, your pet and friendly units; debuffs on a hostile target or focus.", 20, auraVis)
    -- another Custom Icon or Bar's timer or stacks
    AT.RowDropdown(pg, owner, "Custom item",
        function()
            local r = Rec()
            return (r and r.driver.srcId) or 0
        end,
        function(v) Set("srcId", (v ~= 0) and v or nil) end,
        function()
            local CO = Options.Custom
            return CO and CO.ChainItems and CO.ChainItems(nil) or { { value = 0, text = "Pick an item" } }
        end,
        TrigIs("item"))
    -- Show when: the words' state of a spell or an aura, or what the custom
    -- triggers decide on any type
    local function WhenKind()
        local r = Rec()
        return r and TO.WhenOf(r.driver) or nil
    end
    AT.RowDropdown(pg, owner, "Show when",
        function()
            local r, T = Rec(), TO.Runtime()
            if WhenKind() == "rules" then return (r and r.driver.showWhile) or "always" end
            return (r and T) and T.When(r) or "ready"
        end,
        function(v)
            local w = WhenKind()
            if w == "rules" then
                SetCustom("showWhile", (v ~= "always") and v or nil)
            elseif w then
                Set("when", (v ~= ((w == "spell") and "ready" or "up")) and v or nil)
            end
        end,
        function() return TO.ShowWhenItems(WhenKind()) end,
        function() return vis() and WhenKind() ~= nil end, relayout)
    -- "When little time is left": the aura glows' own rows
    local function TimeVis()
        local r, T = Rec(), TO.Runtime()
        return Is("auraText")() and T ~= nil and T.When(r) == "time"
    end
    local function Secs()
        local r = Rec()
        return r ~= nil and r.driver.timeUnit == "sec"
    end
    AT.RowDropdown(pg, owner, "Time left in",
        function() return Secs() and "sec" or "pct" end,
        function(v) Set("timeUnit", (v == "sec") and "sec" or nil) end,
        function() return { { value = "pct", text = "Percent of the aura" }, { value = "sec", text = "Seconds" } } end,
        TimeVis, relayout)
    AT.RowSlider(pg, "Show under this % left",
        function()
            local r = Rec()
            return (r and tonumber(r.driver.timePct)) or 30
        end,
        function(v)
            v = math.floor((tonumber(v) or 30) + 0.5)
            Set("timePct", (v ~= 30) and v or nil)
        end,
        1, 99, 1, false, function() return TimeVis() and not Secs() end)
    AT.RowSlider(pg, "Show under this many seconds left",
        function()
            local r = Rec()
            return (r and tonumber(r.driver.timeSec)) or 5
        end,
        function(v)
            v = tonumber(v) or 5
            Set("timeSec", (v ~= 5) and v or nil)
        end,
        0.5, 120, 0.5, false, function() return TimeVis() and Secs() end)
    AT.RowSlider(pg, "The aura lasts (seconds)",
        function()
            local r = Rec()
            return (r and tonumber(r.driver.auraLen)) or 0
        end,
        function(v)
            v = math.floor((tonumber(v) or 0) + 0.5)
            Set("auraLen", (v > 0) and v or nil)
        end,
        0, 600, 1, false, function() return TimeVis() and Secs() end)
    AT.RowDesc(pg, "The game keeps the aura's length from addons: 0 shows the words the whole time it is up.", 20,
        function() return TimeVis() and Secs() end)
    -- rules a text was given before it had a type keep their own Show while
    AT.RowDropdown(pg, owner, "Show while",
        function()
            local r = Rec()
            return (r and r.driver.showWhile) or "always"
        end,
        function(v) SetCustom("showWhile", (v ~= "always") and v or nil) end,
        function() return TO.ShowWhenItems("rules") end,
        function() return vis() and HasRules() and Trig() ~= "rules" end)
    -- the custom triggers' timer and stacks, as a Custom Icon words them
    AT.RowInput(pg, "Default seconds",
        function()
            local r = Rec()
            local n = r and tonumber(r.driver.duration)
            return n and ("%g"):format(n) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetCustom("duration", nil) return end
            if n and n > 0 then SetCustom("duration", math.min(3600, n)) end
        end,
        rulesVis, "How long the timer runs when a rule starts it with no seconds of its own. Enter applies it.",
        "Set per rule")
    AT.RowInput(pg, "Max stacks",
        function()
            local r = Rec()
            local m = r and tonumber(r.driver.maxStacks)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetCustom("maxStacks", nil) return end
            if n and n >= 1 then SetCustom("maxStacks", math.floor(math.min(999, n))) end
        end,
        rulesVis, "Stacks never pass this. Empty = no cap. Enter applies it.", "No cap")
    AT.RowToggle(pg, "Clear stacks when the timer ends",
        function()
            local r = Rec()
            return r ~= nil and r.driver.clearOnEnd == true
        end,
        function(v) SetCustom("clearOnEnd", v or nil) end,
        rulesVis, "When the timer runs out, the stacks go back to 0 with it.")
    -- a count from custom triggers or another item can carry its time left
    AT.RowToggle(pg, "Show the time left too",
        function()
            local r = Rec()
            return r ~= nil and r.driver.show == "both"
        end,
        function(v) Set("show", v and "both" or nil) end,
        function() return vis() and Kind() == "stack" and (Trig() == "rules" or Trig() == "item") end,
        "The stacks, then the timer in brackets: 3 (7.2).")
    AT.RowDesc(pg, "Its rules are on the Triggers tab: they start its timer and count its stacks.", 20, rulesVis)
    -- an info text's own pick
    AT.RowDropdown(pg, owner, "Power shown",
        function()
            local r = Rec()
            local pt = r and r.driver.powerType
            return (pt == nil or pt < 0) and -1 or pt
        end,
        function(v) Set("powerType", (tonumber(v) and tonumber(v) >= 0) and tonumber(v) or nil) end,
        function()
            local r = Rec()
            if Options.PowerItems then return Options.PowerItems(r and r.driver.powerType, true) end
            return { { value = -1, text = "Automatic (current power)" } }
        end,
        Is("power"))
    AT.RowDropdown(pg, owner, "Value",
        function()
            local r = Rec()
            return (r and r.driver.show) or "current"
        end,
        function(v) Set("show", (v ~= "current") and v or nil) end,
        function() return Items(S.TEXT_SHOWS, S.TEXT_SHOW_LABELS) end,
        Is("power", "health"))
    AT.RowDropdown(pg, owner, "Health of",
        function()
            local r = Rec()
            return (r and r.driver.unit) or "player"
        end,
        function(v) Set("unit", v) end,
        TO.UnitItems, Is("health"))
    AT.RowDropdown(pg, owner, "Name of",
        function()
            local r = Rec()
            return (r and r.driver.unit) or "player"
        end,
        function(v) Set("unit", v) end,
        TO.UnitItems, Is("name"))
    AT.RowDesc(pg, "Combo points on your target, as the combo bar counts them.", 20, Is("combo"))
    AT.RowDesc(pg, "The count of your equipped ammo; blank with the slot empty.", 20, Is("ammo"))
    AT.RowDesc(pg, "Happy, Content or Unhappy; blank with no pet out.", 20, Is("petMood"))
    AT.RowDropdown(pg, owner, "Bands from",
        function()
            local r = Rec()
            return (r and r.driver.rangeFrom) or 0
        end,
        function(v) Set("rangeFrom", (v ~= 0) and v or nil) end,
        TO.RangeItems, Is("range"))
    AT.RowDesc(pg, "The band your target is in; blank with no target or a friendly one.", 20, Is("range"))
    AT.RowDesc(pg, "The game's clock, as the minimap shows it.", 20, Is("clock"))
    -- The records the Triggers tab serves: a text element, and a texture with
    -- custom triggers (UI\AD_TextureOptions.lua). A texture's default is The
    -- timer runs, the custom engine's own.
    local function TRec()
        local r = ctx()
        if not (r and r.type == "bar" and not r._adMulti) then return nil end
        if r.barKind == "text" then return r end
        if r.barKind == "texture" and r.driver and r.driver.source == "rules" then return r end
        return nil
    end
    local function TexRec()
        local r = TRec()
        return (r and r.barKind == "texture") and r or nil
    end
    local function SetTex(field, value)
        local r, CU = TexRec(), NS.DriverCustom
        if r and CU and CU.SetDriver then CU.SetDriver(r, field, value) end
        AT.LayoutPage(pg)
    end

    -- The Triggers tab: the rules, for a text and a texture alike. A texture's
    -- timer and Show while sit here too; a text has them on Tracking.
    local trigShown = kit and kit.triggers
    local tvis = function() return trigShown ~= nil and trigShown() and TRec() ~= nil end
    local texVis = function() return tvis() and TexRec() ~= nil end
    AT.Section(pg, "When it shows", { visibleFn = texVis })
    AT.RowDropdown(pg, owner, "Show while",
        function()
            local r = TexRec()
            return (r and r.driver.showWhile) or "timer"
        end,
        function(v) SetTex("showWhile", (v ~= "timer") and v or nil) end,
        function()
            local out = { { value = "always", text = "Always" } }
            for _, k in ipairs(S.CUSTOM_SHOW_WHILE) do
                if k ~= "always" then out[#out + 1] = { value = k, text = S.CUSTOM_SHOW_WHILE_LABELS[k] or k } end
            end
            return out
        end,
        texVis)
    AT.RowDesc(pg, "Always: it shows all the time. Otherwise the rules below decide when it shows.", 20, texVis)
    AT.RowInput(pg, "Timer seconds",
        function()
            local r = TexRec()
            local n = r and tonumber(r.driver.duration)
            return n and ("%g"):format(n) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetTex("duration", nil) return end
            if n and n > 0 then SetTex("duration", math.min(3600, n)) end
        end,
        texVis, "How long the timer runs when a rule starts it with no seconds of its own. Enter applies it.",
        "Set per rule")
    AT.RowInput(pg, "Stack cap",
        function()
            local r = TexRec()
            local m = r and tonumber(r.driver.maxStacks)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetTex("maxStacks", nil) return end
            if n and n >= 1 then SetTex("maxStacks", math.floor(math.min(999, n))) end
        end,
        texVis, "Stacks never pass this. Empty = no cap. Enter applies it.", "No cap")
    AT.RowToggle(pg, "Stacks clear when the timer ends",
        function()
            local r = TexRec()
            return r ~= nil and r.driver.clearOnEnd == true
        end,
        function(v) SetTex("clearOnEnd", v or nil) end,
        texVis, "When the timer runs out, the stacks go back to 0 with it.")
    if Options.Custom and Options.Custom.RuleRows then
        Options.Custom.RuleRows(pg, TRec, tvis, owner, true)
    end

    -- The words around the value and its number or time format: the element's
    -- own, so no push bar; each row shows for the sources it reaches.
    AT.Section(pg, "Format", { visibleFn = vis })
    if kit and kit.SectionRows then
        kit.SectionRows(pg, "bar", "textel", ctx, vis, {
            "prefix", "suffix", "numFormat", "blankAtZero", "decimals", "decimalsBelow", "abbrev", "rounding",
        })
    end
    AT.Section(pg, nil)
end
