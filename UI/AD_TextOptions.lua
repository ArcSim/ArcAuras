-- AD_TextOptions: a Text element's Add window tab and its Tracking rows: the source, each source's own fields (words, power, unit, spell, aura shape, the rules) and the Format block.
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
        elseif s == "petMood" then
            ok = NS.IsForever == true
        end
        if ok then out[#out + 1] = { value = s, text = S.TEXT_SOURCE_LABELS[s] or s } end
    end
    return out
end

-- A text is for a spell or an aura (Text for), then shows its value or custom
-- words (Shows). Every other kind is picked by its own name in Text for.
TO.SHOWS = {
    spell = { "spellCd", "spellCharges", "spellText" },
    aura = { "auraTime", "auraStacks", "auraText" },
}
TO.SHOW_LABELS = { spellCd = "Cooldown time", spellCharges = "Charges", spellText = "Custom text",
    auraTime = "Time left", auraStacks = "Stacks", auraText = "Custom text" }
-- A text's name follows its spell or aura ("Serpent Sting duration") until the
-- player names it: a name that is still the one it was given, or an older
-- default, moves with the spell, the aura and what it shows.
TO.NAME_WORDS = { spellCd = "cooldown", spellCharges = "charges", spellText = "text",
    auraTime = "duration", auraStacks = "stacks", auraText = "text" }
TO.NAMES = { spellCd = "Spell cooldown", spellCharges = "Spell charges", spellText = "Spell text",
    auraTime = "Aura duration", auraStacks = "Aura stacks", auraText = "Aura text" }
-- names given before these: the source labels and the first defaults
TO.OLD_NAMES = { Text = true, ["Cooldown text"] = true, ["Charges text"] = true, ["Custom text"] = true,
    ["Aura time text"] = true, ["Stacks text"] = true }
for _, n in pairs(NS.Schema and NS.Schema.TEXT_SOURCE_LABELS or {}) do TO.OLD_NAMES[n] = true end
for _, n in pairs(TO.NAMES) do TO.OLD_NAMES[n] = true end
-- the same kind of text across a switch of Text for
TO.SWAP = { spellCd = "auraTime", spellCharges = "auraStacks", spellText = "auraText",
    auraTime = "spellCd", auraStacks = "spellCharges", auraText = "spellText" }

-- nil for a text on another source: its name is its own
function TO.AutoName(rec)
    local d = rec.driver or {}
    local w = TO.NAME_WORDS[d.source]
    if not w then return nil end
    local nm = d.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(d.spellID)
    if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" or nm == "" then return TO.NAMES[d.source] end
    return nm .. " " .. w
end

function TO.NameIsAuto(rec)
    local n = rec.name
    if type(n) ~= "string" or n == "" or TO.OLD_NAMES[n] then return true end
    return n == TO.AutoName(rec)
end

-- A change to the spell, the aura or what it shows: the name moves with it
-- when it was never the player's own.
function TO.Follow(r, change)
    local auto = TO.NameIsAuto(r)
    change()
    if not auto then return end
    local nm = TO.AutoName(r) or TO.DefaultName(r.driver and r.driver.source)
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

-- Text for's value: a spell or an aura, or any other kind by its own name.
function TO.ForOf(source)
    if TO.Subject(source) == "other" then return source or "static" end
    return TO.Subject(source)
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

-- A spell, an aura, then every other kind this client feeds. cur: a text's
-- own kind, kept in the list even where this client cannot feed it.
function TO.SubjectItems(cur)
    local ok = Offered()
    local out = {}
    if ok.spellCd or ok.spellCharges or ok.spellText then out[#out + 1] = { value = "spell", text = "A spell" } end
    if ok.auraTime or ok.auraStacks or ok.auraText then out[#out + 1] = { value = "aura", text = "An aura" } end
    local listed = false
    for _, it in ipairs(TO.SourceItems()) do
        if TO.Subject(it.value) == "other" then
            out[#out + 1] = it
            if it.value == cur then listed = true end
        end
    end
    local labels = NS.Schema and NS.Schema.TEXT_SOURCE_LABELS or {}
    if cur and not listed and TO.SHOWS[cur] == nil and labels[cur] and TO.Subject(cur) == "other" then
        out[#out + 1] = { value = cur, text = labels[cur] }
    end
    return out
end

function TO.ShowsItems(source)
    local ok = Offered()
    local subj = TO.Subject(source)
    local out = {}
    if subj == "other" then
        for _, it in ipairs(TO.SourceItems()) do
            if TO.Subject(it.value) == "other" then out[#out + 1] = it end
        end
        return out
    end
    for _, s in ipairs(TO.SHOWS[subj]) do
        if ok[s] then out[#out + 1] = { value = s, text = TO.SHOW_LABELS[s] } end
    end
    return out
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

function TO.DefaultName(source)
    local S = NS.Schema
    if source == "static" then return "Text" end
    return TO.NAMES[source] or (S.TEXT_SOURCE_LABELS and S.TEXT_SOURCE_LABELS[source]) or "Text"
end

-- The editor tabs: Triggers only on a text that already has rules of its own.
function Options.TextTabs(rec)
    local T = TO.Runtime()
    local d = rec.driver or {}
    local tabs = { "Tracking" }
    local rules = (d.source == "rules") or (T and T.HasRules and T.HasRules(rec))
    if rules then tabs[#tabs + 1] = "Triggers" end
    for _, t in ipairs({ "Appearance", "Show & Hide", "Position", "Load Conditions" }) do tabs[#tabs + 1] = t end
    return tabs
end

-- The sidebar's and cards' one line.
function Options.TextWhat(rec)
    local T = TO.Runtime()
    return T and T.Describe(rec) or "text"
end

-- The Add window's pick: a spell or an aura and what of it, or another kind
-- with its own pick (whose health or name, which power, the value, the bands,
-- the custom item). The spell and the aura are set on Tracking once it exists.
local function AddFor(addState)
    local items = TO.SubjectItems(nil)
    for _, it in ipairs(items) do
        if it.value == addState.textFor then return it.value end
    end
    return items[1] and items[1].value or "spell"
end

local function AddSource(addState)
    local subj = AddFor(addState)
    if not TO.SHOWS[subj] then return subj end
    local items = TO.ShowsItems(TO.SHOWS[subj][1])
    for _, it in ipairs(items) do
        if it.value == addState.textSource then return it.value end
    end
    return items[1] and items[1].value or "spellCd"
end

function Options.TextAddRows(pg, owner, addState)
    local AT = NS.AT
    local vis = function() return addState.cat == "Text" end
    AT.RowDesc(pg, "A spell's or an aura's value or your words on its state, or power, health and more.", 20, vis)
    AT.RowDropdown(pg, owner, "Text for",
        function() return AddFor(addState) end,
        function(v)
            if v == AddFor(addState) then return end
            addState.textSource = TO.SWAP[AddSource(addState)]
            addState.textFor = v
        end,
        function() return TO.SubjectItems(nil) end, vis, function() AT.LayoutPage(pg) end)
    AT.RowDropdown(pg, owner, "Shows",
        function() return AddSource(addState) end,
        function(v) addState.textSource = v end,
        function()
            local sh = TO.SHOWS[AddFor(addState)]
            return sh and TO.ShowsItems(sh[1]) or {}
        end,
        function() return vis() and TO.SHOWS[AddFor(addState)] ~= nil end, function() AT.LayoutPage(pg) end)
    -- a kind's own pick, as Tracking shows it, so the text starts on it
    local function AddIs(...)
        local want = { ... }
        return function()
            if not vis() then return false end
            local s = AddSource(addState)
            for _, w in ipairs(want) do
                if s == w then return true end
            end
            return false
        end
    end
    local S = NS.Schema
    AT.RowDropdown(pg, owner, "Power shown",
        function() return addState.textPower or -1 end,
        function(v) addState.textPower = tonumber(v) end,
        function()
            if Options.PowerItems then return Options.PowerItems(addState.textPower) end
            return { { value = -1, text = "Automatic (current power)" } }
        end,
        AddIs("power"))
    AT.RowDropdown(pg, owner, "Value",
        function() return addState.textShow or "current" end,
        function(v) addState.textShow = v end,
        function() return Items(S.TEXT_SHOWS, S.TEXT_SHOW_LABELS) end,
        AddIs("power", "health"))
    AT.RowDropdown(pg, owner, "Health of",
        function() return addState.textUnit or "player" end,
        function(v) addState.textUnit = v end,
        TO.UnitItems, AddIs("health"))
    AT.RowDropdown(pg, owner, "Name of",
        function() return addState.textUnit or "player" end,
        function(v) addState.textUnit = v end,
        TO.UnitItems, AddIs("name"))
    AT.RowDropdown(pg, owner, "Bands from",
        function() return addState.textRange or 0 end,
        function(v) addState.textRange = v end,
        TO.RangeItems, AddIs("range"))
    AT.RowDropdown(pg, owner, "Custom item",
        function() return addState.textSrcId or 0 end,
        function(v) addState.textSrcId = v end,
        function()
            local CO = Options.Custom
            return CO and CO.ChainItems and CO.ChainItems(nil) or { { value = 0, text = "Pick an item" } }
        end,
        AddIs("custom"))
    AT.RowDropdown(pg, owner, "Readout",
        function() return addState.textReadout or "stacks" end,
        function(v) addState.textReadout = v end,
        function() return Items(S.TEXT_READOUTS, S.TEXT_READOUT_LABELS) end,
        AddIs("rules", "custom"))
    AT.RowInput(pg, "Words",
        function() return addState.textWords or "" end,
        function(v) addState.textWords = v end,
        function()
            local s = AddSource(addState)
            return vis() and (s == "spellText" or s == "auraText" or s == "static")
        end,
        "What it says. For a spell or an aura, Tracking sets when it shows.", "e.g. READY", true)
    AT.RowInput(pg, "Name",
        function() return addState.textName or "" end,
        function(v) addState.textName = v end,
        vis, "What the sidebar calls it.", function() return TO.DefaultName(AddSource(addState)) end, true)
end

function Options.TextCreate(addState, layoutId)
    local Store = NS.Store
    local s = AddSource(addState)
    local driver = { source = s }
    if s == "spellText" or s == "auraText" or s == "static" then
        local words = Trim(addState.textWords)
        driver.text = (words ~= "") and words:sub(1, 120) or nil
    end
    -- the kind's own pick from the Add window (the Tracking rows' values)
    if s == "power" then
        local pt = tonumber(addState.textPower)
        driver.powerType = (pt and pt >= 0) and pt or nil
    end
    if (s == "power" or s == "health") and addState.textShow and addState.textShow ~= "current" then
        driver.show = addState.textShow
    end
    if s == "health" or s == "name" then driver.unit = addState.textUnit end
    if s == "range" and addState.textRange and addState.textRange ~= 0 then driver.rangeFrom = addState.textRange end
    if s == "custom" and addState.textSrcId and addState.textSrcId ~= 0 then driver.srcId = addState.textSrcId end
    if (s == "rules" or s == "custom") and addState.textReadout and addState.textReadout ~= "stacks" then
        driver.show = addState.textReadout
    end
    TO.SourceDefaults(driver, s)
    local name = Trim(addState.textName)
    if name == "" then name = TO.DefaultName(s) end
    return Store.NewBar(layoutId, "text", driver, name)
end

-- The Tracking rows. ctx(): the open bar; vis: the Tracking tab. kit:
-- { SectionRows } from the bar pane, for the Format block's schema rows.
function Options.TextTrackRows(pg, ctx, trackVis, owner, kit)
    local AT, Store, S = NS.AT, NS.Store, NS.Schema
    local COL = AT.COL
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "text" and not r._adMulti) and r or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    local function Source(r)
        local T = TO.Runtime()
        return (r and T) and T.Source(r) or "static"
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
    -- a driver edit: the record in place, then the page again at once
    local function Set(field, value)
        local r = Rec()
        if not r then return end
        if r.driver[field] == value then return end
        r.driver[field] = value
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end
    local function ParseSpell(text)
        local CO = Options.Custom
        if CO and CO.ParseSpell then return CO.ParseSpell(text) end
        local id = tonumber(Trim(text))
        return (id and id > 0) and math.floor(id) or nil
    end
    local function SpellName(id)
        local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" then return "" end
        return nm
    end
    local function NameBeside(row, get)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 11, "")
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

    AT.Section(pg, "Text", { visibleFn = vis })
    AT.RowDropdown(pg, owner, "Text for",
        function() return TO.ForOf(Source(Rec())) end,
        function(v)
            local r = Rec()
            if not r or TO.ForOf(Source(r)) == v then return end
            TO.Follow(r, function()
                if TO.SHOWS[v] then
                    -- the same kind of text on the other side; the states differ
                    r.driver.source = TO.SWAP[Source(r)] or TO.SHOWS[v][1]
                else
                    r.driver.source = v
                    TO.SourceDefaults(r.driver, v)
                end
                r.driver.when = nil
            end)
            Store.Dirty("tree", r.id)
        end,
        function() return TO.SubjectItems(TO.ForOf(Source(Rec()))) end,
        vis, function() AT.LayoutPage(pg) end)
    -- a spell: which one
    local spellVis = Is("spellCd", "spellCharges", "spellText")
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
            return r ~= nil and r.driver.autoRank == true
        end,
        function(v) Set("autoRank", v or nil) end,
        function() return spellVis() and NS.IsForever == true end,
        "On ranked realms, read whichever rank of this spell you know now.")
    -- an aura on a unit: the aura icons' shape
    local auraVis = Is("auraTime", "auraStacks", "auraText")
    AT.RowInput(pg, "Aura spell IDs",
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
    -- what of it: its value, or words of your own on its state; another kind
    -- is already whole in Text for
    local showsVis = function() return vis() and TO.Subject(Source(Rec())) ~= "other" end
    local srcRow = AT.RowDropdown(pg, owner, "Shows",
        function() return Source(Rec()) end,
        function(v)
            local r = Rec()
            if not r or Source(r) == v then return end
            TO.Follow(r, function()
                r.driver.source = v
                TO.SourceDefaults(r.driver, v)
            end)
            Store.Dirty("tree", r.id)
        end,
        function() return TO.ShowsItems(Source(Rec())) end, showsVis, function() AT.LayoutPage(pg) end)
    -- the search finds the row on every spell or aura text (its own field name)
    srcRow._adMeta = { family = "bar", section = "textel", field = "textSource",
        def = { label = "Shows" }, baseVis = showsVis }
    -- an older default name catches up with its spell or aura when opened
    local srcSync = srcRow._sync
    srcRow._sync = function()
        if srcSync then srcSync() end
        if vis() then TO.CatchUpName(Rec()) end
    end
    local wordsVis = Is("spellText", "auraText")
    AT.RowInput(pg, "Words",
        function()
            local r = Rec()
            return (r and r.driver.text) or ""
        end,
        function(v)
            v = Trim(v)
            Set("text", (v ~= "") and v:sub(1, 120) or nil)
        end,
        Is("static", "spellText", "auraText"), "What it says. Enter applies it.", "e.g. READY")
    AT.RowDropdown(pg, owner, "Show when",
        function()
            local r, T = Rec(), TO.Runtime()
            return (r and T) and T.When(r) or "ready"
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local first = (Source(r) == "spellText") and "ready" or "up"
            Set("when", (v ~= first) and v or nil)
        end,
        function() return TO.WhenItems(Source(Rec())) end,
        wordsVis, function() AT.LayoutPage(pg) end)
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
        TimeVis, function() AT.LayoutPage(pg) end)
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
    -- power: which one, and what of it
    AT.RowDropdown(pg, owner, "Power shown",
        function()
            local r = Rec()
            local pt = r and r.driver.powerType
            return (pt == nil or pt < 0) and -1 or pt
        end,
        function(v) Set("powerType", (tonumber(v) and tonumber(v) >= 0) and tonumber(v) or nil) end,
        function()
            local r = Rec()
            if Options.PowerItems then return Options.PowerItems(r and r.driver.powerType) end
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
    AT.RowDesc(pg, "Counts down the spell's cooldown; blank while it is ready or only the global cooldown runs.", 20,
        Is("spellCd"))
    AT.RowDesc(pg, "How many charges are up; Blank at zero below hides the 0.", 20, Is("spellCharges"))
    -- rules of its own, or another custom item's value
    local rulesVis = Is("rules")
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
        Is("custom"))
    AT.RowDropdown(pg, owner, "Readout",
        function()
            local r = Rec()
            return (r and r.driver.show) or "stacks"
        end,
        function(v) Set("show", (v ~= "stacks") and v or nil) end,
        function() return Items(S.TEXT_READOUTS, S.TEXT_READOUT_LABELS) end,
        Is("rules", "custom"))
    AT.RowDesc(pg, "Its rules are on the Triggers tab: they start its timer and count its stacks.", 20, rulesVis)
    -- The records the Triggers tab serves: a text element, and a texture with
    -- custom triggers (UI\AD_TextureOptions.lua). A texture's default is The
    -- timer runs, the custom engine's own; a text's is Always.
    local function TRec()
        local r = ctx()
        if not (r and r.type == "bar" and not r._adMulti) then return nil end
        if r.barKind == "text" then return r end
        if r.barKind == "texture" and r.driver and r.driver.source == "rules" then return r end
        return nil
    end
    local function Idle(r) return (r and r.barKind == "texture") and "timer" or "always" end
    local function SetCustom(field, value)
        local r, CU = TRec(), NS.DriverCustom
        if r and CU and CU.SetDriver then CU.SetDriver(r, field, value) end
        AT.LayoutPage(pg)
    end

    -- The Triggers tab (every source): its own rules, and whether they decide
    -- when it shows. Always, the default, keeps today's text on screen.
    local trigShown = kit and kit.triggers
    local tvis = function() return trigShown ~= nil and trigShown() and TRec() ~= nil end
    AT.Section(pg, "When it shows", { visibleFn = tvis })
    AT.RowDropdown(pg, owner, "Show while",
        function()
            local r = TRec()
            return (r and r.driver.showWhile) or Idle(r)
        end,
        function(v) SetCustom("showWhile", (v ~= Idle(TRec())) and v or nil) end,
        function()
            local out = { { value = "always", text = "Always" } }
            for _, k in ipairs(S.CUSTOM_SHOW_WHILE) do
                if k ~= "always" then out[#out + 1] = { value = k, text = S.CUSTOM_SHOW_WHILE_LABELS[k] or k } end
            end
            return out
        end,
        tvis)
    AT.RowDesc(pg, "Always: it shows all the time. Otherwise the rules below decide when it shows.", 20, tvis)
    AT.RowInput(pg, "Timer seconds",
        function()
            local r = TRec()
            local d = r and tonumber(r.driver.duration)
            return d and ("%g"):format(d) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetCustom("duration", nil) return end
            if n and n > 0 then SetCustom("duration", math.min(3600, n)) end
        end,
        tvis, "How long the timer runs when a rule starts it with no seconds of its own. Enter applies it.",
        "Set per rule")
    AT.RowInput(pg, "Stack cap",
        function()
            local r = TRec()
            local m = r and tonumber(r.driver.maxStacks)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetCustom("maxStacks", nil) return end
            if n and n >= 1 then SetCustom("maxStacks", math.floor(math.min(999, n))) end
        end,
        tvis, "Stacks never pass this. Empty = no cap. Enter applies it.", "No cap")
    AT.RowToggle(pg, "Stacks clear when the timer ends",
        function()
            local r = TRec()
            return r ~= nil and r.driver.clearOnEnd == true
        end,
        function(v) SetCustom("clearOnEnd", v or nil) end,
        tvis, "When the timer runs out, the stacks go back to 0 with it.")
    if Options.Custom and Options.Custom.RuleRows then
        Options.Custom.RuleRows(pg, TRec, tvis, owner, true)
    end

    -- The words around the value and its number or time format: the element's
    -- own, so no push bar; each row shows for the sources it reaches.
    AT.Section(pg, "Format", { visibleFn = vis })
    AT.RowDesc(pg, "The game draws this countdown itself: the prefix and suffix stay off it.", 20,
        Is("spellCd", "auraTime"))
    if kit and kit.SectionRows then
        kit.SectionRows(pg, "bar", "textel", ctx, vis, {
            "prefix", "suffix", "numFormat", "blankAtZero", "decimals", "decimalsBelow", "abbrev", "rounding",
        })
    end
    AT.Section(pg, nil)
end
