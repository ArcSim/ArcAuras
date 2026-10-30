-- AD_EffectsTab: the icon's Effects tab: a list down the left of the triggers that do something (a state, the aura on the icon, an own look, the fade rules), + Add a trigger at its foot (a tile picker), and the open trigger's effects behind folder tabs to its right.
-- AD_Options builds the editor and calls EF.Build; the effect lines are UI\AD_EditorTabs.lua's (ET.LookLine, ET.BlockLine, ET.LayLines), so they read and write as the old table did.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store, Schema = NS.AT, NS.Store, NS.Schema
local COL = AT.COL
local Tr = AT.Tr

local EF = {}
Options.EffectsTab = EF

-- the board's sizes in UI units (its px / 1.17)
EF.TITLE_H, EF.GAP_Y = 22, 9
-- the list column, a trigger's row at its least, its preview, the panel's
-- head strip at its least, + Add a trigger
EF.SIDE_W, EF.ROW_MIN, EF.MINI, EF.HEAD_MIN, EF.ADD_H = 224, 48, 22, 38, 26
-- Three boxes on the page's ground, no edge shared: the list, the open
-- trigger's head, its effects. The ground between them: the board's 12 px.
EF.HEAD_GAP = 10
EF.SIDE_GAP = 10
EF.PANEL_X = EF.SIDE_W + EF.SIDE_GAP
EF.TAB_H, EF.TAB_ON_H, EF.HEAD_H = 23, 26, 26
EF.LABEL_W, EF.CAP_W = 91, 72
local PAD, ROW_X, GAP = 12, 12, 24

local function ET() return Options.EditorTabs end

local function Indexing()
    local S = Options.Search
    return S ~= nil and S.indexing == true
end

local function Measure(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    return math.ceil(w)
end

local function RGB(hex) return AT.RGB(hex) end
local GREEN, GREEN_EDGE = { 0.482, 0.847, 0.561 }, { 0.243, 0.478, 0.267 }
local ICON_INK = RGB("B58CF2")
local FX_ORDER = { "look", "glow", "sound", "art" }
local FX_WORD = { look = "Look", glow = "Glow", sound = "Sound", art = "Icon", when = "When" }
EF.FX_WORD = FX_WORD
-- between the idle tab's words and the open one's
local function MidInk()
    return { (COL.ink[1] + COL.dim[1]) / 2, (COL.ink[2] + COL.dim[2]) / 2, (COL.ink[3] + COL.dim[3]) / 2 }
end
-- a colour part way from a to b
local function Mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Session picks

-- Per kind for the session: the open card (false: none) and each card's
-- picked effect. Per icon: the cards listed though they do nothing (added
-- from + Add a trigger) and the effects shown on a card (a tab never goes
-- while it is in use: only its Remove takes it off).
local function Slot(name)
    local ui = Options.ui
    if not ui then return nil end
    ui[name] = ui[name] or {}
    return ui[name]
end
local function RecKey(r)
    if r._adMulti then return "multi" end
    return tostring(r.id or r.kind or "?")
end
local function PerRec(name, r)
    local s = Slot(name)
    if not (s and r) then return nil end
    local k = RecKey(r)
    s[k] = s[k] or {}
    return s[k]
end
local function Shown(r, key)
    local s = PerRec("effShown", r)
    return s ~= nil and s[key] == true
end
local function SetShown(r, key, on)
    local s = PerRec("effShown", r)
    if s then s[key] = on or nil end
end
local function Added(r, key, fx)
    local s = PerRec("effAdded", r)
    return s ~= nil and s[key .. ":" .. fx] == true
end
local function SetAdded(r, key, fx, on)
    local s = PerRec("effAdded", r)
    if s then s[key .. ":" .. fx] = on or nil end
end
EF.SetAdded = SetAdded

-- an own look's card: its state's key and its place under the state
local function SplitLook(p)
    if type(p) ~= "string" then return nil end
    local key, i = p:match("^(.-)#(%d+)$")
    if key then return key, tonumber(i) end
end
function EF.LookKey(stKey, i) return stKey .. "#" .. i end

-- Triggers

-- Usable: a state of its own, its glow and sound off Ready's, its look the
-- rule that lifts a dimmed icon to full opacity.
local USABLE = { key = "usable", label = "Usable", when = "while you can cast it",
    fx = { glow = { "states.usableGlow" }, sound = { "alerts.usableSoundEnabled" } } }
EF.USABLE = USABLE
local SPLIT = { ["states.usableGlow"] = true, ["alerts.usableSoundEnabled"] = true }

-- a rule that is a state's look: a proc or Usable shows the icon at full opacity
local RULES = {
    proc = { section = "states", fields = { "procOverride", "procOverrideWhen" }, lineName = false, rule = true,
        labels = { procOverride = "Shows it at full opacity", procOverrideWhen = "While" },
        breakBefore = { procOverrideWhen = true }, labelW = 162 },
    usable = { section = "states", fields = { "usableOverride" }, lineName = false, rule = true,
        labels = { usableOverride = "Shows it at full opacity" }, labelW = 162 },
}
EF.RULES = RULES

-- A count of the icon's as a state of its own: an aura's stacks, a charge
-- spell's charges. It holds while the count meets its rule (any = off) and
-- its effects apply only then. `start`: the rule a new one gets. Its `st` is
-- a state as the editor lines read one (its Look's cells; a glow as its
-- fields arrive). The engine reads the same fields (DriverAura.StacksState /
-- ChargesState).
local COUNTS = {
    { key = "stacks", label = "Stacks", section = "auraActive", rule = "stacksRule", a = "stacksA", b = "stacksB",
        alpha = "stacksAlpha", min = 1, start = { rule = "least" },
        tile = "Stacks at a count", line = "While its stacks are at a count" },
    { key = "charges", label = "Charges", section = "states", rule = "chargesRule", a = "chargesA", b = "chargesB",
        alpha = "chargesAlpha", min = 0, start = { rule = "most", a = 1 },
        tile = "Charges at a count", line = "While its charges are at a count" },
}
-- its state: the look's cells and the glow its fields give it (a field the
-- schema lacks leaves its cell out)
for _, C in ipairs(COUNTS) do
    local pre, sec = C.key, C.section
    local f = Schema.icon[sec] and Schema.icon[sec].fields or {}
    local st = { key = C.key, label = C.label, when = "while it is at that count", count = C,
        alpha = { sec, C.alpha } }
    if f[pre .. "Desaturate"] then st.grey = { sec, pre .. "Desaturate" } end
    if f[pre .. "TintColor"] then st.tint = { sec, pre .. "TintColor", on = f[pre .. "TintEnabled"] and pre .. "TintEnabled" or nil } end
    if f[pre .. "Glow"] then st.fx = { glow = { sec .. "." .. pre .. "Glow" } } end
    C.st = st
end
EF.COUNTS = COUNTS
-- the words for a count: the row's after its name, the head's "While it has ..."
-- (each a whole Tr literal: the key list reads only those)
local function CountRuleWords(kind)
    if kind == "least" then return Tr(" at %d or more") end
    if kind == "most" then return Tr(" at %d or fewer") end
    if kind == "exactly" then return Tr(" at exactly %d") end
    if kind == "between" then return Tr(" at %d to %d") end
end
local function CountHasWords(key, kind, one)
    if key == "stacks" then
        if kind == "least" then return Tr("%d+ stacks") end
        if kind == "most" then return one and Tr("%d stack or fewer") or Tr("%d stacks or fewer") end
        if kind == "exactly" then return one and Tr("exactly %d stack") or Tr("exactly %d stacks") end
        if kind == "between" then return Tr("%d to %d stacks") end
    elseif key == "charges" then
        if kind == "least" then return Tr("%d+ charges") end
        if kind == "most" then return one and Tr("%d charge or fewer") or Tr("%d charges or fewer") end
        if kind == "exactly" then return one and Tr("exactly %d charge") or Tr("exactly %d charges") end
        if kind == "between" then return Tr("%d to %d charges") end
    end
end

local function FieldDef(section, field)
    local sec = Schema.icon[section]
    return sec and sec.fields[field]
end
local function FieldShows(r, section, field)
    local f = FieldDef(section, field)
    return f ~= nil and Options.FieldShows ~= nil and Options.FieldShows(r, "icon", section, f) == true
end
local function RuleShows(r, key)
    local rule = RULES[key]
    return rule ~= nil and FieldShows(r, rule.section, rule.fields[1])
end

-- A count state the record can have: its rule's row shows for it (the
-- engine's own test, the schema's showIf); one icon at a time.
local function CountOffered(r, C)
    return r ~= nil and not r._adMulti and FieldShows(r, C.section, C.rule)
end
-- its rule and counts as the engine reads them (a never under min, b never under a)
local function CountRule(r, C)
    local kind = Store.Resolve(r, C.section, C.rule) or "any"
    local a = math.max(C.min, math.floor(tonumber(Store.Resolve(r, C.section, C.a)) or C.min))
    local b = math.max(a, math.floor(tonumber(Store.Resolve(r, C.section, C.b)) or a))
    return kind, a, b
end
EF.CountRule = CountRule

-- Usable has a card on one icon whose kind has its rule or its effects. It
-- follows the kind alone, so each record asks once (every effect lookup
-- asked again: a layout pass made over a hundred of these).
local usableOf = setmetatable({}, { __mode = "k" })
local function UsableOn(r)
    if not r or r._adMulti then return false end
    local m = usableOf[r]
    if m and m.kind == r.kind then return m.on end
    local E = ET()
    local on = RuleShows(r, "usable") or #E.FxFor(r, USABLE) > 0
    usableOf[r] = { kind = r.kind, on = on }
    return on
end

-- The record's states, Usable after Ready; over several icons, only those
-- every icon shares (UI\AD_MultiSelect.lua M.StateShared).
local function States(r)
    local list = ET().StatesFor(r) or {}
    local M = Options.MultiSelect
    local out = {}
    local usable = UsableOn(r)
    for _, st in ipairs(list) do
        if not (r and r._adMulti and M and M.StateShared) or M.StateShared(r, st) then
            out[#out + 1] = st
            if usable and st.key == "ready" then
                out[#out + 1] = USABLE
                usable = false
            end
        end
    end
    if usable then out[#out + 1] = USABLE end
    return out
end
EF.States = States

-- A state's effects: ET.FxFor's, with Usable's glow and sound on its own card
-- (where it has one).
function EF.FxFor(r, st)
    local E = ET()
    local list = E.FxFor(r, st)
    if not (st == USABLE or UsableOn(r)) then return list end
    local out = {}
    for _, f in ipairs(list) do
        local keys = {}
        for _, k in ipairs(f.keys) do
            if (st == USABLE) == (SPLIT[k] == true) then keys[#keys + 1] = k end
        end
        if #keys > 0 then out[#out + 1] = { kind = f.kind, keys = keys } end
    end
    return out
end

local function KeysOf(r, st, fx)
    for _, f in ipairs(EF.FxFor(r, st)) do
        if f.kind == fx then return f.keys end
    end
    return {}
end

-- The fade rules can be set on the record: one icon's (they are per item),
-- not a member its aura group packs (it fades with the group). AD_Options
-- sets EF.FadeApplies, the Fade When pane's own test.
function EF.FadeOK(r)
    if not r or r._adMulti then return false end
    return EF.FadeApplies == nil or EF.FadeApplies(r) == true
end

-- the fade rules hold something: the WHILE card shows
function EF.HasWhile(r)
    local c = EF.FadeOK(r) and r.c
    if not c then return false end
    local C = NS.Conditions
    if next(c.fadeWhen or {}) or next(c.showWhen or {}) then return true end
    if C and C.RangeRule then
        local id = C.RangeRule(r)
        if id then return true end
    end
    return false
end

-- The fade rules' name: its conditions (any or all), else "Fade rules".
function EF.WhileWords(r)
    local C = NS.Conditions
    local c = r and r.c or {}
    local words = {}
    for key in pairs(c.fadeWhen or {}) do
        local d = C and C.ByKey and C.ByKey(key)
        if d then words[#words + 1] = Tr(d.text or key) end
    end
    table.sort(words)
    if #words == 0 then return Tr("Fade rules") end
    local all = C and C.MatchAll and C.MatchAll(r, "fadeWhen")
    return table.concat(words, all and Tr(" and ") or ", ")
end

-- A state's look settings outside its cells (Show while missing), by state
-- key: the first lines of its Look. chip(r): the card's words for it when it
-- changes something, and true when the icon hides then. AD_Options files them.
EF.lookRows = {}
function EF.LookRow(stKey, section, fields, chip)
    local list = EF.lookRows[stKey] or {}
    EF.lookRows[stKey] = list
    -- a second build of the window files them again: once each
    for _, def in ipairs(list) do
        if def.section == section and def.fields[1] == fields[1] then return end
    end
    list[#list + 1] = { section = section, fields = fields, lineName = "", lookRow = true, chip = chip }
end
local function LookRows(r, st)
    local E, out = ET(), {}
    for _, def in ipairs(EF.lookRows[st.key] or {}) do
        if E.blockShows and E.blockShows(r, def) then out[#out + 1] = def end
    end
    return out
end

-- the words a state's look rows put on its card, and whether the icon hides
local function LookRowChip(r, st)
    for _, def in ipairs(LookRows(r, st)) do
        if def.chip then
            local words, hides = def.chip(r)
            if words then return words, hides end
        end
    end
end

-- the state's look does something: an opacity under full, grey, or a tint
local function LookLit(r, st)
    local function V(spec, f) return spec and Store.Resolve(r, spec[1], f or spec[2]) end
    local a = st.alpha and V(st.alpha)
    if a ~= nil and a < 1 and (not st.alpha.on or V(st.alpha, st.alpha.on) == true) then return true end
    if st.grey and V(st.grey) == true then return true end
    if st.tint and st.tint.on and V(st.tint, st.tint.on) == true then return true end
    return false
end
EF.LookLit = LookLit

-- Kept bright while a look dims: one setting, on every look with an opacity.
local KEEP = {
    states = { section = "states", fields = { "preserveDurationText", "preserveSwipe", "labelsFullOpacity", "preserveTextWhen" },
        lineName = "KEEP BRIGHT", cap = true, flat = true, capW = EF.CAP_W,
        labels = { preserveDurationText = "Texts", preserveSwipe = "Swipe", labelsFullOpacity = "Custom texts",
            preserveTextWhen = "When" } },
    auraActive = { section = "auraActive", fields = { "activePreserveText", "activePreserveSwipe", "activeLabelsBright" },
        lineName = "KEEP BRIGHT", cap = true, flat = true, capW = EF.CAP_W,
        labels = { activePreserveText = "Texts", activePreserveSwipe = "Swipe", activeLabelsBright = "Custom texts" } },
    auraMissing = { section = "auraMissing", fields = { "missingPreserveText" },
        lineName = "KEEP BRIGHT", cap = true, flat = true, capW = EF.CAP_W,
        labels = { missingPreserveText = "Texts" } },
}
EF.KEEP = KEEP
local function KeepDef(r, st)
    -- a count state's look is the whole icon's: nothing to keep bright
    if not st.alpha or st.count then return nil end
    if r.kind == "aura" then
        if st.key == "active" then return KEEP.auraActive end
        if st.key == "missing" then return KEEP.auraMissing end
        return nil
    end
    return KEEP.states
end

-- The usability rules Can't use it and Not enough resource share: a fold,
-- named for the other card while shut.
local function UseSum(r, shown)
    local n = #shown
    local open = EF.OpenCard and EF.OpenCard(r)
    local other = (open and open.key == "nomana") and "unusable" or "nomana"
    for _, st in ipairs(States(r)) do
        if st.key == other then
            return Tr("%d more, shared with %s"):format(n, Tr(ET().StateWord(r, st)))
        end
    end
    return Tr("%d more"):format(n)
end
local USE_FOLD = { section = "states", fields = { "usabilityOnCooldown", "usabilityAlphaReplaces", "usabilityReadyOnly" },
    lineName = false, foldRow = true, foldWord = "More", foldSum = UseSum, advRows = true, advIndent = 15, foldSession = true,
    labels = { usabilityOnCooldown = "Also while on cooldown", usabilityAlphaReplaces = "Its opacity replaces the state's",
        usabilityReadyOnly = "Only while ready" } }
-- the rules on a state's look, after its cells
local EXTRA = {
    ready = { { section = "states", fields = { "readyGreyUsable" }, lineName = false, flat = true,
        labels = { readyGreyUsable = "Grey out only while usable" } } },
    cooldown = { { section = "states", fields = { "skipShortLocks" }, lineName = false, flat = true } },
    recharge = { { section = "states", fields = { "ignoreHardICD", "skipShortLocks" }, lineName = false, flat = true } },
    unusable = { USE_FOLD },
    nomana = { USE_FOLD },
}
EF.EXTRA = EXTRA

-- A glow's tuning folds under Fine tune in groups; shut, it names only what
-- differs from the defaults.
local GLOW_GROUP = { Speed = "MOTION", Intensity = "MOTION", FadeOut = "MOTION", Lines = "LINES", Thickness = "LINES",
    Length = "LINES", Backing = "LINES", Particles = "PARTICLES", Scale = "SIZE", XOffset = "PLACE", YOffset = "PLACE",
    MoveX = "PLACE", MoveY = "PLACE", Strata = "LAYER", Level = "LAYER" }
local GLOW_ORDER = { "MOTION", "LINES", "PARTICLES", "SIZE", "PLACE", "LAYER" }
local function GlowPart(field) return field:match("Glow(%u%a*)%d*$") end
local function GlowGroup(field) return GLOW_GROUP[GlowPart(field) or ""] or "MOTION" end

local function ValueWords(f, v)
    if f.t == "enum" then return Tr((f.labels and f.labels[v]) or tostring(v)) end
    if f.t == "num" then
        if not f.fmt and (f.max or 1) <= 1 then return math.floor(v * 100 + 0.5) .. "%" end
        return f.fmt and f.fmt:format(v) or ("%.1f"):format(v)
    end
    return tostring(v)
end
local function TuneSum(r, shown, def)
    local t = {}
    for _, P in ipairs(shown) do
        local f = P.fdef
        local v = f and Store.Resolve(r, def.section, P.field)
        local d = f and f.d
        local differs
        if type(v) == "number" and type(d) == "number" then differs = math.abs(v - d) > 1e-6
        elseif type(v) ~= "table" and v ~= nil then differs = v ~= d end
        if differs then
            local words = Tr((def.labels and def.labels[P.field]) or f.label or P.field):lower()
            t[#t + 1] = words .. " " .. ValueWords(f, v)
        end
    end
    if #t == 0 then return Tr("all as they come") end
    return table.concat(t, ", ")
end

-- An effect block as the open card's panel draws it: a lone switch is the
-- tab itself, so it hides with the line's name; a glow's look rows break as
-- the board's do and its tuning folds under Fine tune; a sound's words go
-- under its sound.
local wraps = {}
local function Wrap(def, fx, single)
    wraps[def] = wraps[def] or {}
    local w = wraps[def][single]
    if w then return w end
    w = setmetatable({}, { __index = def })
    if single and def.isCard then
        w.noCheck = true
        w.lineName = false
    end
    w.labelW = EF.LABEL_W
    if fx == "glow" then
        local fields, brk = {}, {}
        local native
        for _, f in ipairs(def.fields) do
            local part = GlowPart(f)
            if part == "Native" then native = f
            else
                fields[#fields + 1] = f
                if part == "Color" and native then
                    fields[#fields + 1] = native
                    native = nil
                end
            end
            if part == "Type" or part == "CombatOnly" then brk[f] = true end
        end
        if native then fields[#fields + 1] = native end
        w.fields, w.breakBefore = fields, brk
        -- shut by default: open for the session only, never from a saved More
        w.foldRow, w.foldWord, w.foldSum, w.foldSession = true, "Fine tune", TuneSum, true
        w.advGroup, w.advOrder, w.capW, w.advIndent = GlowGroup, GLOW_ORDER, EF.CAP_W, 15
    elseif fx == "sound" then
        local brk = {}
        for _, f in ipairs(def.fields) do
            if f:find("Speech", 1, true) then brk[f] = true end
        end
        w.breakBefore = brk
        if def.fields[1] == "soundChannel" then w.labels = { soundChannel = "Channel" } end
    end
    wraps[def][single] = w
    return w
end

-- Cards

-- Every card the record can have, in order: each state, its own looks
-- under it, then the fade rules.
local function AllCards(r)
    local E = ET()
    local out = {}
    for _, st in ipairs(States(r)) do
        out[#out + 1] = { key = st.key, st = st, kind = st.overlay and "aura" or "state" }
        for i, e in ipairs(E.LooksOf(r, st)) do
            local _, look = E.LookAt(e)
            if look then
                out[#out + 1] = { key = EF.LookKey(st.key, i), st = st, i = i, look = look, entry = e, kind = "while" }
            end
        end
    end
    if EF.FadeOK(r) then out[#out + 1] = { key = "while", kind = "while", isWhile = true } end
    for _, C in ipairs(COUNTS) do
        if CountOffered(r, C) then out[#out + 1] = { key = C.key, st = C.st, count = C, kind = "count", isCount = true } end
    end
    return out
end
EF.AllCards = AllCards

-- the effects a card can have, in tab order
local function Allowed(r, c)
    if c.isWhile then return {} end
    if c.i then return { "look" } end
    local st, out = c.st, {}
    if RULES[st.key] then
        if RuleShows(r, st.key) then out[1] = "look" end
    elseif st.alpha or st.grey or st.tint or #LookRows(r, st) > 0 then
        out[1] = "look"
    end
    for _, f in ipairs(EF.FxFor(r, st)) do out[#out + 1] = f.kind end
    return out
end
EF.Allowed = Allowed

-- a block is on: its switch, or its own test (art)
local function KeyOn(r, key)
    local E = ET()
    local def = E.KeyDef(r, key)
    if not def then return false end
    if def.isCard then return Store.Resolve(r, def.section, def.fields[1]) == true end
    return E.FxLit(r, key)
end

-- the card has that effect: it does something, or it was added or shown
function EF.Has(r, c, fx)
    if c.isWhile then return false end
    -- a count state's rule is its first tab, always there
    if c.isCount and fx == "when" then return true end
    if Added(r, c.key, fx) then return true end
    if c.i then return fx == "look" end
    local st = c.st
    if fx == "look" then
        local rule = RULES[st.key]
        if rule then return Store.Resolve(r, rule.section, rule.fields[1]) == true end
        return LookLit(r, st) or LookRowChip(r, st) ~= nil
    end
    for _, k in ipairs(KeysOf(r, st, fx)) do
        if KeyOn(r, k) then return true end
    end
    return false
end

-- the effects a card has, in tab order
local function Have(r, c)
    local out = {}
    if c.isCount then out[1] = "when" end
    for _, fx in ipairs(Allowed(r, c)) do
        if EF.Has(r, c, fx) then out[#out + 1] = fx end
    end
    return out
end
EF.Have = Have

-- A card is listed: it does something, is an own look, the fade rules while
-- they hold something, or was added from + Add a trigger.
local function Listed(r, c)
    if c.i ~= nil or Shown(r, c.key) then return true end
    if c.isWhile then return EF.HasWhile(r) end
    if c.isCount then return (CountRule(r, c.count)) ~= "any" end
    for _, fx in ipairs(Allowed(r, c)) do
        if EF.Has(r, c, fx) then return true end
    end
    return false
end

function EF.Cards(r)
    local out = {}
    if not r then return out end
    for _, c in ipairs(AllCards(r)) do
        if Listed(r, c) then out[#out + 1] = c end
    end
    return out
end

local function OpenStore() return Slot("effOpen") end

-- + Add a trigger's tile picker open in the panel, per kind for the session:
-- no trigger is open meanwhile.
function EF.Picking(r)
    local s = Slot("effPicking")
    return r ~= nil and s ~= nil and s[r.kind or "?"] == true
end
function EF.SetPicking(r, on)
    local s = Slot("effPicking")
    if s and r then s[r.kind or "?"] = on and true or nil end
end

-- The open trigger: the one picked for the kind, else the first listed (a
-- pick the record no longer lists too); none while the picker is open.
-- Without the list at hand only the cards it needs are tested: the page's
-- gates (every fade row's) ask on every layout pass.
function EF.OpenCard(r, cards)
    if not r or EF.Picking(r) then return nil end
    local s = OpenStore()
    local p = s and s[r.kind or "?"]
    local lk = SplitLook(p)
    local all = cards or AllCards(r)
    local function On(c) return cards ~= nil or Listed(r, c) end
    for _, c in ipairs(all) do
        if c.key == p and On(c) then return c end
    end
    -- a look gone (removed, or another icon's list) falls to its state
    if lk then
        for _, c in ipairs(all) do
            if c.key == lk and not c.i and On(c) then return c end
        end
    end
    for _, c in ipairs(all) do
        if On(c) then return c end
    end
end

function EF.Picked(r)
    local c = EF.OpenCard(r)
    return c and c.key or nil
end

-- Opens a trigger, listing it, and shuts the picker (nil or false: back to
-- the first listed).
function EF.Pick(r, key)
    local s = OpenStore()
    if not (s and r) then return end
    s[r.kind or "?"] = key or nil
    EF.SetPicking(r, false)
    if key then SetShown(r, key, true) end
end

-- the open card's state and an own look's place under it; nil for the fade
-- rules or none
function EF.PickedState(r)
    local c = EF.OpenCard(r)
    if not c or c.isWhile then return nil end
    return c.st, c.i
end

function EF.PickedLook(r)
    local st, i = EF.PickedState(r)
    if st and i then return st, i end
end

-- Gates for the tab's other rows: a state card (or that one) or the fade
-- rules open. While the search indexes, every row counts as shown.
function EF.Shows(r, what)
    if Indexing() then return true end
    local key = EF.Picked(r)
    -- several icons sharing no state still push the tab
    if not key then return what == "state" and r ~= nil and r._adMulti == true end
    if what == "while" then return key == "while" end
    if what == "state" then return key ~= "while" end
    return key == what
end

-- The effect a card shows: the one picked for it, else its first.
local function TabStore() return Slot("effTab") end
function EF.TabOf(r, c, have)
    have = have or Have(r, c)
    local s = TabStore()
    local p = s and s[(r.kind or "?") .. ":" .. c.key]
    for _, fx in ipairs(have) do
        if fx == p then return fx end
    end
    return have[1]
end
function EF.PickTab(r, c, fx)
    local s = TabStore()
    if s then s[(r.kind or "?") .. ":" .. c.key] = fx end
end

-- The search's jump to a row the open card hides (the fade rules, the push
-- bar): the first card under which the row and its section show. None: the
-- pick stays as it was.
function EF.Reveal(r, row, sec)
    local s = OpenStore()
    if not (r and row and s) then return end
    local function On()
        if sec and sec.visibleFn and not sec.visibleFn() then return false end
        return row._visibleFn == nil or row._visibleFn() == true
    end
    if On() then return end
    local kind = r.kind or "?"
    local was, picking = s[kind], EF.Picking(r)
    -- the picker hides every trigger's rows
    EF.SetPicking(r, false)
    local keys = {}
    if EF.FadeOK(r) then keys[1] = "while" end
    for _, st in ipairs(States(r)) do keys[#keys + 1] = st.key end
    for _, k in ipairs(keys) do
        -- a card the list leaves out opens only once listed
        local listed = Shown(r, k)
        SetShown(r, k, true)
        s[kind] = k
        if On() then return end
        if not listed then SetShown(r, k, nil) end
    end
    s[kind] = was
    EF.SetPicking(r, picking)
end

-- Words

local function Pct(v) return math.floor(v * 100 + 0.5) .. "%" end

-- a glow block's style in words, "in combat" after it when gated so
local function GlowWords(r, def)
    local style, combat
    for _, f in ipairs(def.fields) do
        local part = GlowPart(f)
        if part == "Type" then
            local fd = FieldDef(def.section, f)
            local v = Store.Resolve(r, def.section, f)
            style = Tr((fd and fd.labels and fd.labels[v]) or tostring(v or "Glow"))
        elseif part == "CombatOnly" then
            combat = Store.Resolve(r, def.section, f) == true
        end
    end
    style = style or Tr("Glow")
    if combat then style = style .. ", " .. Tr("in combat") end
    return style
end

local function GlowColor(r, def)
    for _, f in ipairs(def.fields) do
        if GlowPart(f) == "Color" then
            local c = Store.Resolve(r, def.section, f)
            if type(c) == "table" then return c end
        end
    end
    return COL.arc
end

local function SoundWords(r, def)
    local snd = def.fields[2]
    local v = snd and Store.Resolve(r, def.section, snd)
    if type(v) == "string" and v ~= "" then
        for _, it in ipairs((NS.Sounds and NS.Sounds.Items(false)) or {}) do
            if it.value == v then return Tr(it.text) end
        end
        return v
    end
    local say = def.fields[3]
    local s = say and Store.Resolve(r, def.section, say)
    if type(s) == "string" and s ~= "" then return Tr("says it") end
    return Tr("none picked")
end

-- a proc's rule: when it lifts the icon, in words
local function RuleWhen(r)
    local f = FieldDef("states", "procOverrideWhen")
    local v = Store.Resolve(r, "states", "procOverrideWhen")
    return Tr((f and f.labels and f.labels[v]) or "Ready or on cooldown"):lower()
end

-- an own look's or a state's look as parts: opacity, grey, tint
local function LookParts(r, c)
    local E = ET()
    local st = c.st
    local p = {}
    if c.i then
        local has, look = E.LookCols(r, st), c.look
        local a = has.alpha and look.alpha
        if type(a) == "number" and a < 1 then p.alpha = a end
        p.grey = has.grey and look.grey == true
        if has.tint and look.tint == true then p.tint = look.tintColor or { 1, 1, 1 } end
        p.glow = has.glow ~= nil and look.glow == true and E.LookGlowColor(r, has.glow) or nil
        return p
    end
    local a = st.alpha and Store.Resolve(r, st.alpha[1], st.alpha[2])
    if a ~= nil and a < 1 and (not st.alpha.on or Store.Resolve(r, st.alpha[1], st.alpha.on) == true) then p.alpha = a end
    p.grey = st.grey ~= nil and Store.Resolve(r, st.grey[1], st.grey[2]) == true
    if st.tint and (not st.tint.on or Store.Resolve(r, st.tint[1], st.tint.on) == true) and st.tint.on then
        p.tint = Store.Resolve(r, st.tint[1], st.tint[2]) or { 1, 1, 1 }
    end
    return p
end

-- A card's chips: what each of its effects does, in tab order.
-- { fx, text, ink (the glyph's), swatch }
function EF.Chips(r, c)
    local E = ET()
    local out = {}
    local function Chip(fx, text, ink, swatch)
        out[#out + 1] = { fx = fx, text = text, ink = ink, swatch = swatch }
    end
    if c.isWhile then
        -- the fade rules' one look: the opacity they fade it to
        local C = NS.Conditions
        if EF.HasWhile(r) and C and C.GetFade then Chip("look", Tr("Opacity") .. " " .. Pct(C.GetFade(r, "fadeAlpha"))) end
        return out
    end
    for _, fx in ipairs(Have(r, c)) do
        if fx == "look" then
            local rule = not c.i and RULES[c.st.key]
            if rule then
                if Store.Resolve(r, rule.section, rule.fields[1]) == true then
                    Chip("look", Tr("Full opacity") .. (c.st.key == "proc" and (", " .. RuleWhen(r)) or ""))
                end
            else
                local words, hides = nil, nil
                if not c.i then words, hides = LookRowChip(r, c.st) end
                if words then Chip("look", Tr(words)) end
                if not hides then
                    local p = LookParts(r, c)
                    if p.alpha then Chip("look", Tr("Opacity") .. " " .. Pct(p.alpha)) end
                    if p.grey then Chip("look", Tr("Grey out")) end
                    if p.tint then Chip("look", Tr("Tint"), nil, p.tint) end
                    if p.glow then Chip("glow", Tr("Glow"), p.glow) end
                end
            end
        elseif fx == "glow" then
            for _, k in ipairs(KeysOf(r, c.st, "glow")) do
                local def = E.KeyDef(r, k)
                if def and KeyOn(r, k) then Chip("glow", GlowWords(r, def), GlowColor(r, def)) end
            end
        elseif fx == "sound" then
            for _, k in ipairs(KeysOf(r, c.st, "sound")) do
                if KeyOn(r, k) then
                    Chip("sound", Tr("Sound"))
                    break
                end
            end
        elseif fx == "art" then
            for _, k in ipairs(KeysOf(r, c.st, "art")) do
                if KeyOn(r, k) then
                    Chip("art", Tr("Icon"))
                    break
                end
            end
        end
    end
    return out
end

-- An effect in a few words, for its panel's head.
function EF.Summary(r, c, fx)
    local E = ET()
    if c.isCount and fx == "when" then
        local _, rule = EF.CardWords(r, c)
        -- the name as it reads (a German noun keeps its capital)
        return Tr(c.count.label) .. rule
    end
    if fx == "look" then
        local rule = not c.i and RULES[c.st.key]
        if rule then
            if Store.Resolve(r, rule.section, rule.fields[1]) ~= true then return Tr("off") end
            return c.st.key == "proc" and (Tr("full") .. ", " .. RuleWhen(r)) or Tr("full opacity")
        end
        local t = {}
        if not c.i then
            local words, hides = LookRowChip(r, c.st)
            if words then t[#t + 1] = Tr(words):lower() end
            if hides then return table.concat(t, ", ") end
        end
        local p = LookParts(r, c)
        if p.alpha then t[#t + 1] = Pct(p.alpha) end
        if p.grey then t[#t + 1] = Tr("grey") end
        if p.tint then t[#t + 1] = Tr("tint") end
        if p.glow then t[#t + 1] = Tr("glow") end
        return #t > 0 and table.concat(t, ", ") or Tr("as it comes")
    end
    local keys = KeysOf(r, c.st, fx)
    local first
    for _, k in ipairs(keys) do
        local def = E.KeyDef(r, k)
        if def then
            first = first or def
            if KeyOn(r, k) then
                first = def
                break
            end
        end
    end
    if not first then return "" end
    if fx == "glow" then return GlowWords(r, first) end
    if fx == "sound" then return SoundWords(r, first) end
    return Tr("its own art")
end

-- a card's words: its name, and the part after it in the accent
function EF.CardWords(r, c)
    local E = ET()
    if c.isWhile then return EF.WhileWords(r), "" end
    if c.isCount then
        local kind, a, b = CountRule(r, c.count)
        local f = CountRuleWords(kind)
        return Tr(c.count.label), f and f:format(a, b) or ""
    end
    local name = Tr(E.StateWord(r, c.st))
    if c.i then
        local rule = ", " .. E.LookWords(c.look)
        local tag = E.LookTag(r, c.entry)
        if tag ~= "" then rule = rule .. "  " .. tag end
        return name, rule
    end
    return name, ""
end

-- a state's when, as a line of its own ("While it is ready"); a record's own
-- words when the state names one (st.whenFn)
function EF.WhenWords(st, r)
    local w = st and st.whenFn and r and st.whenFn(r) or (st and st.when)
    if not w then return "" end
    return (Tr(w):gsub("^%l", string.upper))
end

-- a count state's: "While it has 5+ stacks", "While it has 1 charge or fewer"
function EF.CountWhen(r, c)
    local kind, a, b = CountRule(r, c.count)
    local f = CountHasWords(c.count.key, kind, a == 1)
    if not f then return "" end
    return Tr("While it has %s"):format(f:format(a, b))
end

-- How a trigger draws the icon, for its preview: { alpha, grey, tint (a
-- colour), glow (a colour), hidden }. A state that changes nothing yet shows
-- its cue as the board does: the tint it keeps, the game's own glow.
local CUE = { unusable = true, nomana = true, range = true }
function EF.MiniLook(r, c)
    local out = { alpha = 1, grey = false }
    if not (r and c) then return out end
    if c.isWhile then
        local C = NS.Conditions
        out.alpha = (C and C.GetFade) and C.GetFade(r, "fadeAlpha") or 0
        out.hidden = out.alpha <= 0
        return out
    end
    local st = c.st
    local _, hides
    if not c.i then _, hides = LookRowChip(r, st) end
    if hides then
        out.alpha, out.hidden = 0, true
    elseif c.i or not RULES[st.key] then
        local p = LookParts(r, c)
        if p.alpha then out.alpha = p.alpha end
        out.grey = p.grey == true
        out.tint = p.tint
        out.glow = p.glow
    end
    if not c.i then
        for _, k in ipairs(KeysOf(r, st, "glow")) do
            local def = ET().KeyDef(r, k)
            if def and KeyOn(r, k) then
                out.glow = GlowColor(r, def)
                break
            end
        end
        if not out.glow and (st.key == "proc" or st.key == "assist") then out.glow = EF.FxInk(r, c, "glow") end
        if CUE[st.key] and st.tint and not out.tint and not out.grey and out.alpha >= 1 then
            local t = Store.Resolve(r, st.tint[1], st.tint[2])
            if type(t) == "table" then out.tint = t end
        end
    end
    if out.alpha <= 0 then out.hidden = true end
    return out
end

-- + Add a trigger's tiles in groups: the states (the spell's, or its own
-- words), the aura on the icon, the fade rules. A trigger already on the
-- icon shows ticked. { title, tiles = { { key, name, line, added, card } } }
function EF.Offers(r)
    local groups = {}
    if not r then return groups end
    local listed = {}
    for _, c in ipairs(EF.Cards(r)) do listed[c.key] = true end
    local states, aura = {}, {}
    for _, c in ipairs(AllCards(r)) do
        if not c.i and not c.isWhile and not c.isCount then
            local t = { key = c.key, card = c, name = Tr(ET().StateWord(r, c.st)), line = EF.WhenWords(c.st, r),
                added = listed[c.key] == true }
            if c.kind == "aura" then aura[#aura + 1] = t else states[#states + 1] = t end
        end
    end
    if #states > 0 then
        groups[#groups + 1] = { title = r.kind == "spell" and "WHEN THE SPELL IS" or "WHEN IT IS", tiles = states }
    end
    if #aura > 0 then groups[#groups + 1] = { title = "AURA ON THE ICON", tiles = aura, side = true } end
    if EF.FadeOK(r) then
        groups[#groups + 1] = { title = "WHILE", side = true, tiles = { { key = "while", name = Tr("A condition holds"),
            line = Tr("Fades or shows it while a condition is true"), added = listed["while"] == true,
            card = { key = "while", kind = "while", isWhile = true } } } }
    end
    local counts = {}
    for _, c in ipairs(AllCards(r)) do
        if c.isCount then
            counts[#counts + 1] = { key = c.key, card = c, name = Tr(c.count.tile), line = Tr(c.count.line),
                added = listed[c.key] == true, count = true }
        end
    end
    if #counts > 0 then groups[#groups + 1] = { title = "AT A COUNT", side = true, tiles = counts } end
    return groups
end

-- A count state added: its rule to the start one (and its count where the
-- start names one), its Look shown, listed and open.
function EF.AddCount(r, key)
    for _, C in ipairs(COUNTS) do
        if C.key == key and r then
            if (CountRule(r, C)) == "any" then
                Store.SetOverride(r, C.section, C.rule, C.start.rule)
                if C.start.a then Store.SetOverride(r, C.section, C.a, C.start.a) end
            end
            SetAdded(r, key, "look", true)
            EF.Pick(r, key)
            return true
        end
    end
    return false
end

-- Changes

-- an effect comes on: a glow, a sound or a rule switches on, a look or an
-- icon starts as it is
function EF.AddFx(r, c, fx)
    local E = ET()
    SetAdded(r, c.key, fx, true)
    EF.PickTab(r, c, fx)
    if fx == "look" then
        local rule = RULES[c.st.key]
        if rule then Store.SetOverride(r, rule.section, rule.fields[1], true) end
        return
    end
    -- an aura's glow switched on under Missing glows while it is missing
    if E.SetOpen then E.SetOpen(r, c.st.key, fx) end
    for _, k in ipairs(KeysOf(r, c.st, fx)) do
        local def = E.KeyDef(r, k)
        if def and def.isCard then
            if not KeyOn(r, k) then E.SetSwitch(r, def, true) end
            return
        end
    end
end

-- a field back to what it was before it was set here
local function Reset(r, section, field)
    Store.SetOverride(r, section, field, nil)
    local f = FieldDef(section, field)
    local d = f and f.d
    if f and d ~= nil and type(d) ~= "table" and Store.Resolve(r, section, field) ~= d then
        Store.SetOverride(r, section, field, d)
    end
end

-- an effect taken off: a switch off, a look as it comes, the art back
function EF.RemoveFx(r, c, fx)
    local E = ET()
    SetAdded(r, c.key, fx, nil)
    if c.i then
        local idx = E.LookAt(c.entry)
        if idx then E.LookRemove(r, idx) end
        return
    end
    local st = c.st
    if fx == "look" then
        local rule = RULES[st.key]
        if rule then
            Store.SetOverride(r, rule.section, rule.fields[1], false)
            return
        end
        if st.alpha then
            if st.alpha.on then Store.SetOverride(r, st.alpha[1], st.alpha.on, false)
            else Store.SetOverride(r, st.alpha[1], st.alpha[2], 1) end
        end
        if st.grey then Store.SetOverride(r, st.grey[1], st.grey[2], false) end
        if st.tint and st.tint.on then Store.SetOverride(r, st.tint[1], st.tint.on, false) end
        if st.timed and FieldShows(r, st.timed[1], st.timed.on) then Store.SetOverride(r, st.timed[1], st.timed.on, false) end
        for _, def in ipairs(LookRows(r, st)) do
            for _, f in ipairs(def.fields) do Reset(r, def.section, f) end
        end
        return
    end
    for _, k in ipairs(KeysOf(r, st, fx)) do
        local def = E.KeyDef(r, k)
        if def and def.isCard then
            if KeyOn(r, k) then E.SetSwitch(r, def, false) end
        elseif def then
            for _, f in ipairs(def.fields) do Reset(r, def.section, f) end
        end
    end
end

-- the card's x: everything on it off, and it leaves the list
function EF.RemoveCard(r, c)
    if c.isWhile then
        local C = NS.Conditions
        if C and C.Clear then
            C.Clear(r, "fadeWhen")
            C.Clear(r, "showWhen")
        end
    elseif c.i then
        EF.RemoveFx(r, c, "look")
    else
        -- a count state: its rule back to any, the state off with its effects
        if c.isCount then Reset(r, c.count.section, c.count.rule) end
        for _, fx in ipairs(Allowed(r, c)) do
            if EF.Has(r, c, fx) then EF.RemoveFx(r, c, fx) end
            SetAdded(r, c.key, fx, nil)
        end
    end
    SetShown(r, c.key, nil)
    local s = OpenStore()
    if s and EF.Picked(r) == c.key then s[r.kind or "?"] = nil end
end

-- Drawing

local function Font(parent, size, col)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    if col then fs:SetTextColor(col[1], col[2], col[3]) end
    return fs
end

local function Tex(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(AT.WHITE)
    return t
end

-- A frame's four hairline edges; each side can be coloured or hidden.
local function Edges(f, layer)
    local e = { t = Tex(f, layer), b = Tex(f, layer), l = Tex(f, layer), r = Tex(f, layer) }
    function e:Lay()
        local px = AT.Hairline(f)
        self.t:ClearAllPoints()
        self.t:SetPoint("TOPLEFT")
        self.t:SetPoint("TOPRIGHT")
        self.t:SetHeight(px)
        self.b:ClearAllPoints()
        self.b:SetPoint("BOTTOMLEFT")
        self.b:SetPoint("BOTTOMRIGHT")
        self.b:SetHeight(px)
        self.l:ClearAllPoints()
        self.l:SetPoint("TOPLEFT")
        self.l:SetPoint("BOTTOMLEFT")
        self.l:SetWidth(px)
        self.r:ClearAllPoints()
        self.r:SetPoint("TOPRIGHT")
        self.r:SetPoint("BOTTOMRIGHT")
        self.r:SetWidth(px)
    end
    function e:Color(c, sides)
        for k, t in pairs({ t = self.t, b = self.b, l = self.l, r = self.r }) do
            t:SetVertexColor(c[1], c[2], c[3], 1)
            t:SetShown(sides == nil or sides[k] == true)
        end
    end
    e:Lay()
    return e
end

-- a small boxed button on a card's right: the x, an own look's arrows
local function BoxBtn(parent, label)
    local b = AT.MakeQuietButton(parent, label, 17)
    b:SetSize(17, 17)
    local function Rest()
        b:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        b:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
        b.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    end
    Rest()
    b:SetScript("OnLeave", Rest)
    return b
end

-- the colour an effect shows in: a glow its own, the others fixed
local function FxInk(r, c, fx)
    if fx == "glow" then
        for _, k in ipairs(KeysOf(r, c.st, "glow")) do
            local def = ET().KeyDef(r, k)
            if def and KeyOn(r, k) then return GlowColor(r, def) end
        end
        local k = KeysOf(r, c.st, "glow")[1]
        local def = k and ET().KeyDef(r, k)
        return def and GlowColor(r, def) or COL.arc
    end
    if fx == "sound" then return GREEN end
    if fx == "when" then return COL.title end
    if fx == "art" then return AT.Mute(ICON_INK) end
    return COL.arc
end
EF.FxInk = FxInk

-- a small menu of words and glyphs: + Add effect's.
-- On the window, over everything in it as the theme's pullouts sit: the
-- window is DIALOG itself, so a DIALOG menu inside it tied with the page and
-- the panel's words showed through.
local function Menu(parent, owner)
    local m = CreateFrame("Frame", nil, owner or parent, "BackdropTemplate")
    AT.Skin(m, COL.panel, COL.line2)
    if owner then m:SetFrameLevel(owner:GetFrameLevel() + 30) else m:SetFrameStrata("FULLSCREEN_DIALOG") end
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:Hide()
    m._items = {}
    function m:Item(i, h)
        local b = self._items[i]
        if not b then
            b = CreateFrame("Button", nil, self)
            b:SetHeight(h or 20)
            local hl = Tex(b, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetVertexColor(COL.btnHover[1], COL.btnHover[2], COL.btnHover[3], 1)
            hl:Hide()
            local mid = MidInk()
            b._fs = Font(b, 12, mid)
            b:SetScript("OnEnter", function()
                hl:Show()
                b._fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            end)
            b:SetScript("OnLeave", function()
                hl:Hide()
                local c = MidInk()
                b._fs:SetTextColor(c[1], c[2], c[3])
            end)
            self._items[i] = b
        end
        return b
    end
    return m
end

-- the side list

-- a text's lines at a width, wrapped at its spaces as a font string wraps
-- (a word wider than the line takes the lines it needs)
local function WrapLines(text, width, measure)
    if width <= 0 then return 1 end
    local lines, cur = 1, nil
    for word in tostring(text or ""):gmatch("%S+") do
        local cand = cur and (cur .. " " .. word) or word
        if measure(cand) <= width then
            cur = cand
        elseif not cur then
            local n = math.ceil(measure(word) / width)
            lines = lines + n - 1
            cur = nil
            if n == 1 then cur = word end
        else
            lines = lines + 1
            local n = math.ceil(measure(word) / width)
            lines = lines + n - 1
            cur = (n == 1) and word or nil
        end
    end
    return lines
end
EF.WrapLines = WrapLines

-- A row's chips flow like words: a chip's words wrap at its spaces, two
-- lines at most, the chips that would need a third folded into one "+N".
-- measure(text) gives a chip text's width. Returns the pieces ({ chip, text,
-- line, x, lead }: lead is the glyph's room on a chip's first piece, a
-- "+N" box's padding), the lines used and the chips left out.
EF.CHIP_LEAD, EF.CHIP_GAP, EF.MORE_PAD = 12, 9, 4
local function FlowChips(list, textW, measure)
    local function Lay(chips)
        local pieces, line, x = {}, 1, 0
        for _, c in ipairs(chips) do
            local lead = c.more and EF.MORE_PAD or EF.CHIP_LEAD
            local tail = c.more and EF.MORE_PAD or 0
            local words = {}
            if c.more then words[1] = c.text else for wd in c.text:gmatch("%S+") do words[#words + 1] = wd end end
            local seg
            for i, wd in ipairs(words) do
                if i == 1 then
                    local w = lead + measure(wd) + tail
                    if x > 0 and x + EF.CHIP_GAP + w > textW then line, x = line + 1, 0 end
                    local at = (x == 0) and 0 or (x + EF.CHIP_GAP)
                    seg = { chip = c, text = wd, line = line, x = at, lead = lead, tail = tail }
                    pieces[#pieces + 1] = seg
                    x = at + w
                else
                    local w = seg.lead + measure(seg.text .. " " .. wd) + tail
                    if seg.x + w <= textW then
                        seg.text = seg.text .. " " .. wd
                        x = seg.x + w
                    else
                        line = line + 1
                        seg = { chip = c, text = wd, line = line, x = 0, lead = 0, tail = tail }
                        pieces[#pieces + 1] = seg
                        x = measure(wd)
                    end
                end
            end
        end
        return pieces, (#chips > 0) and line or 0
    end
    local pieces, lines = Lay(list)
    if lines <= 2 then return pieces, lines, 0 end
    local shown = {}
    for i = 1, #list do shown[i] = list[i] end
    repeat
        shown[#shown] = nil
        local all = {}
        for i = 1, #shown do all[i] = shown[i] end
        all[#all + 1] = { more = true, text = "+" .. (#list - #shown) }
        pieces, lines = Lay(all)
    until lines <= 2 or #shown == 0
    return pieces, lines, #list - #shown
end
EF.FlowChips = FlowChips

-- the icon's art for the previews; several icons at once show a question mark
local QUESTION = 134400
local function ArtOf(r)
    local F = NS.Factory
    if not r or r._adMulti or not (F and F.GetTexture) then return QUESTION end
    return F.GetTexture(r) or QUESTION
end
EF.ArtOf = ArtOf

-- A small picture of the icon in a trigger's state: its art in a black
-- frame at that look's opacity, grey and tint, ringed in its glow's colour.
-- The frame is one black square under the art (a list makes many of these);
-- a hidden look's light edge is made the first time one shows.
local function Mini(parent, size)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(size, size)
    m._back = Tex(m, "BORDER")
    m._back:SetAllPoints()
    m._back:SetVertexColor(0, 0, 0, 1)
    m._art = m:CreateTexture(nil, "ARTWORK")
    m._art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return m
end
-- four strips `from` outside the frame, `thick` deep
local function LayRing(m, ring, from, thick, c, a)
    local o = from + thick
    local t, b, l, r = ring[1], ring[2], ring[3], ring[4]
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", m, "TOPLEFT", -o, from)
    t:SetPoint("BOTTOMRIGHT", m, "TOPRIGHT", o, from)
    t:SetHeight(thick)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", m, "BOTTOMLEFT", -o, -from)
    b:SetPoint("TOPRIGHT", m, "BOTTOMRIGHT", o, -from)
    b:SetHeight(thick)
    l:ClearAllPoints()
    l:SetPoint("TOPRIGHT", m, "TOPLEFT", -from, from)
    l:SetPoint("BOTTOMRIGHT", m, "BOTTOMLEFT", -from, -from)
    l:SetWidth(thick)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", m, "TOPRIGHT", from, from)
    r:SetPoint("BOTTOMLEFT", m, "BOTTOMRIGHT", from, -from)
    r:SetWidth(thick)
    for _, x in ipairs(ring) do
        x:SetVertexColor(c[1], c[2], c[3], a)
        x:Show()
    end
end
-- look: EF.MiniLook's; a hidden look shows faintly in a light frame
local function PaintMini(m, r, look)
    local px = AT.Hairline(m)
    m._art:ClearAllPoints()
    m._art:SetPoint("TOPLEFT", px, -px)
    m._art:SetPoint("BOTTOMRIGHT", -px, px)
    m._art:SetTexture(ArtOf(r))
    m._art:SetAlpha(look.hidden and 0.28 or math.max(0.28, look.alpha or 1))
    m._art:SetDesaturated(look.grey == true)
    local t = look.tint
    m._art:SetVertexColor(t and t[1] or 1, t and t[2] or 1, t and t[3] or 1, 1)
    m._back:SetShown(not look.hidden)
    if look.hidden and not m._edge then m._edge = Edges(m, "OVERLAY") end
    if m._edge then
        m._edge:Lay()
        m._edge:Color(COL.dim, look.hidden and { t = true, b = true, l = true, r = true } or {})
    end
    local g = look.glow
    if g and not m._ring then
        m._ring = { Tex(m, "BORDER"), Tex(m, "BORDER"), Tex(m, "BORDER"), Tex(m, "BORDER") }
        m._soft = { Tex(m, "BORDER"), Tex(m, "BORDER"), Tex(m, "BORDER"), Tex(m, "BORDER") }
    end
    if m._ring then
        if g then
            -- two pixels of the glow's colour, two more of it faint
            local s = math.max(1, math.floor(2 / px + 0.5)) * px
            LayRing(m, m._ring, 0, s, g, 1)
            LayRing(m, m._soft, s, s, g, 0.35)
        else
            for _, x in ipairs(m._ring) do x:Hide() end
            for _, x in ipairs(m._soft) do x:Hide() end
        end
    end
    m._look = look
end
EF.PaintMini = PaintMini

-- a quiet button with an x before its words: Remove <effect>, Remove trigger
local function QuietX(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    AT.Skin(b, { 0, 0, 0 }, COL.line2)
    b:SetHeight(20)
    b._x = ET().Glyph(b, "add")
    b._x:SetScale(0.7)
    b._x:SetPoint("LEFT", 8 / 0.7, 0)
    for _, t in ipairs(b._x._bars) do t:SetRotation(math.rad(45)) end
    b.fs = Font(b, 11)
    b.fs:SetPoint("LEFT", 8 + 8 + 5, 0)
    local function Paint(hot)
        b:SetBackdropColor(0, 0, 0, 0)
        if hot then b:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
        else b:SetBackdropBorderColor(0, 0, 0, 0) end
        local c = hot and COL.ink or COL.dim
        b.fs:SetTextColor(c[1], c[2], c[3])
        b._x:SetColor(c)
    end
    Paint(false)
    b:SetScript("OnEnter", function() Paint(true) end)
    b:SetScript("OnLeave", function() Paint(false) end)
    function b:SetWords(t)
        self.fs:SetText(t)
        self:SetWidth(8 + 8 + 5 + Measure(self.fs) + 9)
    end
    return b
end

-- a check in the add's green: a trigger already on the icon
local function Check(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(12, 12)
    local a = Tex(f, "OVERLAY")
    a:SetSize(4.5, 1.6)
    a:SetPoint("CENTER", -2.6, -0.4)
    a:SetRotation(math.rad(-45))
    local b = Tex(f, "OVERLAY")
    b:SetSize(8, 1.6)
    b:SetPoint("CENTER", 1.4, 0.6)
    b:SetRotation(math.rad(50))
    for _, t in ipairs({ a, b }) do t:SetVertexColor(GREEN[1], GREEN[2], GREEN[3], 1) end
    return f
end

-- the row's sizes: a name line, a chip line and the gap between them, the
-- row's top and bottom padding, the text's left edge, the scroll strip
local NAME_LH, CHIP_LH, CHIP_GAP_Y, ROW_PAD_Y = 15, 14, 2, 7
local TEXT_X, OWN_INDENT, STRIP = 10 + EF.MINI + 9, 12, 12
-- the column round the list: the first row flush under its top edge (the
-- open one's top line is the column's), + Add a trigger 9 under the last row
local COL_TOP, COL_FOOT = 0, 9 + EF.ADD_H + 9 + 1
EF.COL_CHROME = COL_TOP + COL_FOOT

-- A dashed edge of four tiled strips (the half-lit band of the glow dash
-- art), as the board's dashed buttons: four textures, not one per dash.
local DASH_H = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_GlowDashH"
local DASH_V = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_GlowDashV"
local DASH_B0, DASH_B1, DASH_CYCLE = 4 / 8 + 1 / 128, 5 / 8 - 1 / 128, 6
local function DashEdge(f)
    local e = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetTexture(i % 2 == 1 and DASH_H or DASH_V, "REPEAT", "REPEAT")
        e[i] = t
    end
    function e:Lay(w, h, c)
        local th = AT.Hairline(f)
        local top, right, bottom, left = self[1], self[2], self[3], self[4]
        for _, t in ipairs(self) do t:ClearAllPoints() end
        top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        top:SetSize(w, th)
        top:SetTexCoord(0, w / DASH_CYCLE, DASH_B0, DASH_B1)
        bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        bottom:SetSize(w, th)
        bottom:SetTexCoord(0, w / DASH_CYCLE, DASH_B0, DASH_B1)
        left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        left:SetSize(th, h)
        left:SetTexCoord(DASH_B0, DASH_B1, 0, h / DASH_CYCLE)
        right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        right:SetSize(th, h)
        right:SetTexCoord(DASH_B0, DASH_B1, 0, h / DASH_CYCLE)
        self:Color(c)
    end
    function e:Color(c)
        for _, t in ipairs(self) do t:SetVertexColor(c[1], c[2], c[3], 1) end
        self.c = c
    end
    return e
end

-- Builds the tab on page pg: the title strip, the list of triggers down the
-- left (+ Add a trigger at its foot) and the open trigger's panel to its
-- right, or the tile picker. vis: the tab's own gate. under: the editor's
-- tab row, the page's ground starts under it. Returns the row.
function EF.Build(pg, ctx, vis, owner, under)
    local E = ET()
    if not E then return end
    -- the popovers' home (the clock's, the look pick's)
    local T = { owner = owner }
    EF.T = T
    local function Relay() AT.LayoutPage(pg) end
    local function Rec() return ctx() end

    -- several icons that share no trigger have no row at all
    local row = AT.AddRow(pg, 60, function()
        if not vis() then return false end
        local r = Rec()
        return r ~= nil and #AllCards(r) > 0
    end)
    EF.cards = row
    -- The board's page under the tab row: the window's darker ground, so the
    -- panel reads as a block on it and the list sits darker still. Only
    -- while the tab shows; the editor's tab row opens its tab into it.
    local ground
    if under then
        ground = pg:CreateTexture(nil, "BACKGROUND", nil, -7)
        ground:SetTexture(AT.WHITE)
        ground:SetVertexColor(COL.bg[1], COL.bg[2], COL.bg[3], 1)
        ground:SetPoint("TOPLEFT", under, "BOTTOMLEFT", -2, 2)
        ground:SetPoint("BOTTOMRIGHT", pg, "BOTTOMRIGHT", 0, 0)
        ground:Hide()
    end
    EF.ground = ground
    -- the editor's tab row asks on every pass (it lays out first): shows the
    -- ground while the tab's row shows, and says so
    function EF.SyncGround()
        local on = ground ~= nil and row._visibleFn() == true
        if ground then ground:SetShown(on) end
        return on
    end

    -- the title strip
    local title = CreateFrame("Frame", nil, row, "BackdropTemplate")
    AT.Skin(title, COL.head, COL.line)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", 0, 0)
    title:SetHeight(EF.TITLE_H)
    local tfs = Font(title, 12, COL.title)
    tfs:SetPoint("LEFT", 9, 0)
    tfs:SetText(Tr("What it does, and when"))
    EF.title = title
    -- measuring only: a chip's words and a name, at their sizes
    local m10, m11, m13 = Font(row, 10), Font(row, 11), Font(row, 13)
    m10:Hide()
    m11:Hide()
    m13:Hide()
    local function W10(t) m10:SetText(t) return Measure(m10) end
    local function W11(t) m11:SetText(t) return Measure(m11) end
    local function W13(t) m13:SetText(t) return Measure(m13) end

    -- the list column
    local col = CreateFrame("Frame", nil, row)
    col:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(EF.TITLE_H + EF.GAP_Y))
    col:SetWidth(EF.SIDE_W)
    local colFill = Tex(col, "BACKGROUND")
    colFill:SetAllPoints()
    local colEdge = Edges(col)
    col._edge = colEdge
    EF.col = col
    -- the list scrolls inside the column when it would not fit the page
    local host, content = AT.MakeScroll(col)
    EF.listHost, EF.listContent = host, content
    local sb = host._atScroll
    sb.track:ClearAllPoints()
    sb.track:SetPoint("TOPRIGHT", host, "TOPRIGHT", -3, 0)
    sb.track:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -3, 0)

    -- + Add a trigger under the list: a dashed green edge, lit (the button
    -- fill, the bright green) while hovered or while its picker is open
    local add = CreateFrame("Button", nil, col)
    add:SetSize(EF.SIDE_W - 1 - 9 - 9 - 1, EF.ADD_H)
    add._fill = Tex(add, "BACKGROUND")
    add._fill:SetAllPoints()
    add._dash = DashEdge(add)
    add.fs = Font(add, 12, GREEN)
    add.fs:SetPoint("LEFT", 10, 0)
    add.fs:SetText(Tr("+ Add a trigger"))
    local function PaintAdd(hot)
        add._fill:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], hot and 1 or 0)
        add._dash:Lay(add:GetWidth(), EF.ADD_H, hot and GREEN or GREEN_EDGE)
        add._lit = hot == true
    end
    add._paint = PaintAdd
    PaintAdd(false)
    add:SetScript("OnEnter", function() PaintAdd(true) end)
    add:SetScript("OnLeave", function() PaintAdd(EF.Picking(Rec())) end)
    AT.Tooltip(add, "Add a trigger", "What else can change this icon's look, glow or sound.")
    add:SetScript("OnClick", function()
        local r = Rec()
        if not r then return end
        AT.CloseDropdown()
        if EF.fxMenu then EF.fxMenu:Hide() end
        EF.SetPicking(r, not EF.Picking(r))
        Relay()
    end)
    EF.add = add

    -- the list's rows
    local rows = {}
    EF.rows = rows
    local function NameInk(rw)
        local c = (rw._on or rw._hot) and COL.ink or MidInk()
        rw._name:SetTextColor(c[1], c[2], c[3])
    end
    local function ListRow(i)
        local rw = rows[i]
        if rw then return rw end
        rw = CreateFrame("Button", nil, content)
        rw._fill = Tex(rw, "BACKGROUND")
        rw._fill:SetAllPoints()
        rw._e = Edges(rw)
        rw._mini = Mini(rw, EF.MINI)
        rw._name = Font(rw, 13)
        rw._name:SetWordWrap(true)
        rw._segs, rw._gl = {}, {}
        rw:SetScript("OnClick", function(self)
            local r = Rec()
            local c = self._card
            if not (r and c) then return end
            AT.CloseDropdown()
            if EF.fxMenu then EF.fxMenu:Hide() end
            EF.Pick(r, c.key)
            local st = c.st
            if not (st and Options.PlayPreview and Options.PlayPreview(r, st.key)) then Relay() end
        end)
        rw:SetScript("OnEnter", function(self)
            self._hot = true
            NameInk(self)
        end)
        rw:SetScript("OnLeave", function(self)
            self._hot = nil
            NameInk(self)
        end)
        rows[i] = rw
        return rw
    end
    -- a piece of a row's chips: its words, its glyph on a chip's first piece
    local function Seg(rw, i)
        local fs = rw._segs[i]
        if not fs then
            fs = Font(rw, 10)
            rw._segs[i] = fs
        end
        return fs
    end
    local GLYPH_S = 9 / 14
    local function SegGlyph(rw, i, fx)
        rw._gl[i] = rw._gl[i] or {}
        local g = rw._gl[i][fx]
        if not g then
            g = E.Glyph(rw, fx)
            g:SetScale(GLYPH_S)
            rw._gl[i][fx] = g
        end
        return g
    end
    local function More(rw)
        if rw._more then return rw._more end
        local b = CreateFrame("Frame", nil, rw, "BackdropTemplate")
        AT.Skin(b, { 0, 0, 0 }, COL.line2)
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetHeight(CHIP_LH)
        b.fs = Font(b, 10, COL.dim)
        b.fs:SetPoint("CENTER", 0, 0)
        rw._more = b
        return b
    end

    -- each listed trigger's row at a text width: its chips' flow, its lines, its height
    local function MeasureRows(r, cards, textW)
        local out, total = {}, 0
        for _, c in ipairs(cards) do
            local indent = c.i and OWN_INDENT or 0
            local tw = textW - indent
            local name, rule = EF.CardWords(r, c)
            local nl = WrapLines(name .. rule, tw, W13)
            local pieces, lines, hidden = FlowChips(EF.Chips(r, c), tw, W10)
            local cl = math.max(1, lines)
            local h = math.max(EF.ROW_MIN, ROW_PAD_Y + nl * NAME_LH + 3 + cl * CHIP_LH + (cl - 1) * CHIP_GAP_Y + ROW_PAD_Y)
            out[#out + 1] = { card = c, name = name, rule = rule, nameLines = nl, pieces = pieces, lines = lines,
                hidden = hidden, h = h, textW = tw, indent = indent }
            total = total + h
        end
        return out, total
    end
    EF.MeasureRows = MeasureRows

    local function PaintRow(rw, r, L, on, y, rowW)
        local c = L.card
        rw._card, rw._lay, rw._on = c, L, on
        rw:ClearAllPoints()
        rw:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        rw:SetSize(rowW, L.h)
        local bg = on and COL.panel or COL.well
        rw._fill:SetVertexColor(bg[1], bg[2], bg[3], on and 1 or 0)
        -- the open one: an accent edge on its left, lines above and below,
        -- inside the column's own edges (the list is a box of its own)
        local px = AT.Hairline(rw)
        rw._e:Lay()
        rw._e:Color(COL.line, { t = on, b = on, l = on })
        rw._e.l:SetWidth(2 * px)
        rw._e.l:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        local x0 = TEXT_X + L.indent
        rw._mini:ClearAllPoints()
        rw._mini:SetPoint("LEFT", rw, "LEFT", 10 + L.indent, 0)
        PaintMini(rw._mini, r, EF.MiniLook(r, c))
        local cl = math.max(1, L.lines)
        local block = L.nameLines * NAME_LH + 3 + cl * CHIP_LH + (cl - 1) * CHIP_GAP_Y
        local top = math.floor((L.h - block) / 2)
        rw._name:SetText(L.name .. (L.rule ~= "" and ("|cff" .. AT.Hex(COL.arc) .. L.rule .. "|r") or ""))
        rw._name:SetWidth(L.textW)
        rw._name:ClearAllPoints()
        rw._name:SetPoint("TOPLEFT", rw, "TOPLEFT", x0, -top)
        NameInk(rw)
        -- the chips, line by line under the name
        local function LineY(k) return -(top + L.nameLines * NAME_LH + 3 + (k - 1) * (CHIP_LH + CHIP_GAP_Y) + CHIP_LH / 2) end
        local n = 0
        local glyphs = {}
        local moreShown = false
        for i, p in ipairs(L.pieces) do
            local yc = LineY(p.line)
            local fs = Seg(rw, i)
            n = i
            fs:SetText(p.text)
            fs:ClearAllPoints()
            if p.chip.more then
                local b = More(rw)
                b.fs:SetText(p.text)
                b:SetWidth(p.lead + Measure(b.fs) + p.tail)
                b:ClearAllPoints()
                b:SetPoint("LEFT", rw, "TOPLEFT", x0 + p.x, yc)
                b:Show()
                moreShown = true
                fs:Hide()
            else
                local mid = COL.dim
                fs:SetTextColor(mid[1], mid[2], mid[3])
                fs:SetPoint("LEFT", rw, "TOPLEFT", x0 + p.x + p.lead, yc)
                fs:Show()
                if p.lead > 0 then
                    local fx = p.chip.fx
                    local g = SegGlyph(rw, i, fx)
                    g:ClearAllPoints()
                    g:SetPoint("LEFT", rw, "TOPLEFT", (x0 + p.x) / GLYPH_S, yc / GLYPH_S)
                    g:SetColor(p.chip.ink or COL.title)
                    glyphs[g] = true
                end
            end
        end
        if #L.pieces == 0 then
            n = 1
            local fs = Seg(rw, 1)
            fs:SetText(Tr("No effect yet"))
            fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", rw, "TOPLEFT", x0, LineY(1))
            fs:Show()
        end
        for i = n + 1, #rw._segs do rw._segs[i]:Hide() end
        for _, set in pairs(rw._gl) do
            for _, g in pairs(set) do g:SetShown(glyphs[g] == true) end
        end
        if rw._more and not moreShown then rw._more:Hide() end
        rw:Show()
    end

    -- the page's height for the column: the list scrolls rather than the page
    -- (what sits above the row is measured once it is laid out, and kept)
    local above = 36
    local function ListMax()
        local vh = pg:GetHeight() or 0
        if vh <= 100 then return math.huge end
        local pt, rt = pg:GetTop(), row:GetTop()
        if type(pt) == "number" and type(rt) == "number" then
            local t = pt - rt + (pg._scrollOff or 0)
            if t >= 0 and t < vh then above = math.floor(t + 0.5) end
        end
        return math.max(2 * EF.ROW_MIN, vh - above - EF.TITLE_H - EF.GAP_Y - EF.COL_CHROME - 8)
    end
    EF.ListMax = ListMax

    -- the panel's head
    local head = CreateFrame("Frame", nil, row)
    local headFill = Tex(head, "BACKGROUND")
    headFill:SetAllPoints()
    local headEdge = Edges(head)
    head._mini = Mini(head, 20)
    head._mini:SetPoint("LEFT", head, "LEFT", 10, 0)
    head._name = Font(head, 13, COL.ink)
    head._name:SetWordWrap(true)
    head._when = Font(head, 11, COL.faint)
    head._when:SetWordWrap(true)
    local trm = QuietX(head)
    trm:SetWords(Tr("Remove trigger"))
    trm:SetPoint("RIGHT", head, "RIGHT", -9, 0)
    AT.Tooltip(trm, "Remove this trigger", "Turns off everything on it and takes it off the list.")
    trm:SetScript("OnClick", function()
        local r = Rec()
        local c = head._card
        if not (r and c) then return end
        AT.CloseDropdown()
        EF.RemoveCard(r, c)
        Relay()
    end)
    head._rm, head._edge = trm, headEdge
    EF.head = head
    -- an own look's arrows, made the first time one opens
    local function Arrows()
        if head._up then return end
        head._dn = BoxBtn(head, "")
        head._up = BoxBtn(head, "")
        for _, b in ipairs({ head._up, head._dn }) do
            b._chev = AT.MakeChevron(b)
            b._chev:SetPoint("CENTER", 0, 0)
            b._chev:SetColor(COL.dim)
        end
        head._up._chev:SetDir("up")
        head._dn._chev:SetDir("down")
        AT.Tooltip(head._up, "Move up", "The top look wins when several hold.")
        AT.Tooltip(head._dn, "Move down", "The top look wins when several hold.")
        local function Move(dir)
            local r = Rec()
            local c = head._card
            if not (r and c and c.i) then return end
            AT.CloseDropdown()
            local n = #E.LooksOf(r, c.st)
            if c.i + dir < 1 or c.i + dir > n then return end
            local idx = E.LookAt(c.entry)
            if idx then E.LookMove(r, idx, dir) end
            -- the look it was stays open at its new place
            if EF.Picked(r) == c.key then EF.Pick(r, EF.LookKey(c.st.key, c.i + dir)) end
            Relay()
        end
        head._up:SetScript("OnClick", function() Move(-1) end)
        head._dn:SetScript("OnClick", function() Move(1) end)
    end
    EF.headArrows = Arrows

    -- the head: the trigger's preview, its name and when (both wrap on a
    -- narrow panel), an own look's arrows, Remove trigger. Returns its height.
    local function LayHead(r, c, y, pw)
        head._card = c
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", row, "TOPLEFT", EF.PANEL_X, y)
        head:SetWidth(pw)
        headFill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
        headEdge:Lay()
        headEdge:Color(COL.line)
        PaintMini(head._mini, r, EF.MiniLook(r, c))
        local name, rule = EF.CardWords(r, c)
        local when = (c.st and not c.i) and EF.WhenWords(c.st, r) or ""
        -- a count state: its name, its rule in the when ("While it has 5+ stacks")
        if c.isCount then rule, when = "", EF.CountWhen(r, c) end
        head._name:SetText(name .. (rule ~= "" and ("|cff" .. AT.Hex(COL.arc) .. rule .. "|r") or ""))
        head._when:SetText(when)
        local right = pw - 9 - trm:GetWidth() - 8
        local arrows = c.i ~= nil
        if arrows then
            Arrows()
            head._dn:ClearAllPoints()
            head._dn:SetPoint("RIGHT", trm, "LEFT", -8, 0)
            head._up:ClearAllPoints()
            head._up:SetPoint("RIGHT", head._dn, "LEFT", -3, 0)
            local n = #E.LooksOf(r, c.st)
            head._up:SetAlpha(c.i == 1 and 0.45 or 1)
            head._dn:SetAlpha(c.i == n and 0.45 or 1)
            right = right - (17 + 3 + 17 + 8)
        end
        if head._up then
            head._up:SetShown(arrows)
            head._dn:SetShown(arrows)
        end
        -- a Custom Icon's Active state: Change opens what makes it
        local chg = c.st ~= nil and not c.i and c.st.change ~= nil and c.st.change(r) == true
        if chg and not head._chg then
            head._chg = AT.MakeSmallButton(head, "Change", 64)
            head._chg:SetScript("OnClick", function()
                AT.CloseDropdown()
                if Options.OpenActiveWhile then Options.OpenActiveWhile() end
            end)
            AT.Tooltip(head._chg, "Change", "Opens Active while on Tracking, which decides when this state holds.")
        end
        if head._chg then
            head._chg:SetShown(chg)
            if chg then
                head._chg:ClearAllPoints()
                head._chg:SetPoint("RIGHT", trm, "LEFT", -8, 0)
                right = right - ((head._chg:GetWidth() or 64) + 8)
            end
        end
        local x0 = 10 + 20 + 8
        local room = math.max(40, math.floor(right - x0))
        local nw = W13(name .. rule)
        local ww = when ~= "" and W11(when) or 0
        -- the when beside the name while both fit (the when wrapping), else under it
        local stacked = when ~= "" and nw + 8 + math.min(ww, 77) > room
        local nameW = math.max(1, math.floor(math.min(nw, room)))
        local nl = WrapLines(name .. rule, nameW, W13)
        head._name:SetWidth(nameW)
        head._when:SetShown(when ~= "")
        local wl, whenW = 0, 0
        if when ~= "" then
            whenW = stacked and room or math.max(1, room - nameW - 8)
            wl = WrapLines(when, whenW, W11)
            head._when:SetWidth(whenW)
        end
        local block = stacked and (nl * NAME_LH + 2 + wl * 13) or math.max(nl * NAME_LH, wl * 13, 20)
        local h = math.max(EF.HEAD_MIN, 5 + block + 5)
        head:SetHeight(h)
        head._name:ClearAllPoints()
        head._when:ClearAllPoints()
        if stacked then
            local top = math.floor((h - block) / 2)
            head._name:SetPoint("TOPLEFT", head, "TOPLEFT", x0, -top)
            head._when:SetPoint("TOPLEFT", head, "TOPLEFT", x0, -(top + nl * NAME_LH + 2))
        else
            head._name:SetPoint("LEFT", head, "LEFT", x0, 0)
            if when ~= "" then head._when:SetPoint("LEFT", head, "LEFT", x0 + nameW + 8, 0) end
        end
        head._nameW, head._nameLines, head._whenLines, head._right, head._stacked = nameW, nl, wl, right, stacked
        head:Show()
        return h
    end

    -- the open trigger's body
    local body = CreateFrame("Frame", nil, row)
    body:Hide()
    EF.body = body
    local bodyFill = Tex(body, "BACKGROUND")
    bodyFill:SetAllPoints()
    local bodyEdge = Edges(body)
    body._edge = bodyEdge
    local empty = Font(body, 11, COL.faint)
    empty:SetWordWrap(true)
    EF.emptyNote = empty

    -- the folder tabs: the picked one taller, its effect's colour on top,
    -- open into the panel under it
    local tabs = {}
    EF.tabs = tabs
    local function Tab(i)
        local t = tabs[i]
        if t then return t end
        t = CreateFrame("Button", nil, body)
        t._fill = Tex(t, "BACKGROUND")
        t._fill:SetAllPoints()
        t._edge = Edges(t)
        t._top = Tex(t, "ARTWORK")
        t._top:SetPoint("TOPLEFT", 1, -1)
        t._top:SetPoint("TOPRIGHT", -1, -1)
        t._top:SetHeight(2)
        t._fs = Font(t, 11)
        t._glyphs = {}
        t:SetScript("OnClick", function(self)
            local r = Rec()
            local c = EF.OpenCard(r)
            if not (r and c) then return end
            AT.CloseDropdown()
            if EF.fxMenu then EF.fxMenu:Hide() end
            EF.PickTab(r, c, self._fx)
            Relay()
        end)
        tabs[i] = t
        return t
    end

    -- + Add effect and its menu, made the first time a trigger opens
    local addFx, fxMenu
    local function AddFxButton()
        if addFx then return addFx end
        addFx = CreateFrame("Button", nil, body, "BackdropTemplate")
        AT.Skin(addFx, { 0, 0, 0 }, GREEN_EDGE)
        addFx:SetBackdropColor(0, 0, 0, 0)
        addFx:SetBackdropBorderColor(0, 0, 0, 0)
        addFx.fs = Font(addFx, 12, GREEN)
        addFx.fs:SetText(Tr("+ Add effect"))
        addFx.fs:SetPoint("CENTER", 0, 0)
        addFx:SetSize(Measure(addFx.fs) + 20, 23)
        -- the same dashed edge as + Add a trigger
        local dash = DashEdge(addFx)
        dash:Lay(addFx:GetWidth(), 23, GREEN_EDGE)
        addFx._dashes = dash
        function addFx:SetDashColor(c) dash:Color(c) end
        -- bright while hovered or while its menu is open
        addFx:SetScript("OnEnter", function() addFx:SetDashColor(GREEN) end)
        addFx:SetScript("OnLeave", function() addFx:SetDashColor(fxMenu:IsShown() and GREEN or GREEN_EDGE) end)
        EF.addFx = addFx
        fxMenu = Menu(body, owner)
        EF.fxMenu = fxMenu
        fxMenu:HookScript("OnHide", function() addFx:SetDashColor(GREEN_EDGE) end)
        -- one pullout at a time with the theme's: a click elsewhere in the window shuts it
        addFx:SetScript("OnClick", function()
            if AT.openDropdown == fxMenu then
                AT.CloseDropdown()
                return
            end
            AT.CloseDropdown()
            local r = Rec()
            local c = r and EF.OpenCard(r)
            if not c then return end
            local n = 0
            for _, fx in ipairs(Allowed(r, c)) do
                if not EF.Has(r, c, fx) then
                    n = n + 1
                    local b = fxMenu:Item(n, 22)
                    b._fx = fx
                    b._fs:SetText(Tr(FX_WORD[fx]))
                    b._g = b._g or {}
                    if not b._g[fx] then
                        b._g[fx] = E.Glyph(b, fx)
                        b._g[fx]:SetScale(0.8)
                        b._g[fx]:SetPoint("LEFT", 9 / 0.8, 0)
                    end
                    for k, g in pairs(b._g) do g:SetShown(k == fx) end
                    b._g[fx]:SetColor(COL.title)
                    b._fs:ClearAllPoints()
                    b._fs:SetPoint("LEFT", 9 + 11 + 7, 0)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 1, -3 - (n - 1) * 22)
                    b:SetPoint("TOPRIGHT", -1, -3 - (n - 1) * 22)
                    b:SetScript("OnClick", function(self)
                        local rr = Rec()
                        local cc = rr and EF.OpenCard(rr)
                        AT.CloseDropdown()
                        if not cc then return end
                        EF.AddFx(rr, cc, self._fx)
                        Relay()
                    end)
                    b:Show()
                end
            end
            for i = n + 1, #fxMenu._items do fxMenu._items[i]:Hide() end
            fxMenu:SetSize(154, n * 22 + 6)
            fxMenu:ClearAllPoints()
            fxMenu:SetPoint("TOPLEFT", addFx, "BOTTOMLEFT", 0, -4)
            fxMenu:Show()
            AT.openDropdown = fxMenu
            addFx:SetDashColor(GREEN)
        end)
        AT.Tooltip(addFx, "Add effect", "Give this trigger a look, a glow, a sound or an icon.")
        body:HookScript("OnHide", function() fxMenu:Hide() end)
        return addFx
    end

    -- the effect's panel: framed, its effect's colour down its edge, its
    -- words and a quiet Remove in its head strip
    local ed = CreateFrame("Frame", nil, body, "BackdropTemplate")
    AT.Skin(ed, COL.box, COL.line)
    EF.panel, EF.ed = ed, ed
    local accent = Tex(ed, "BORDER")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    local strip = Tex(ed, "BACKGROUND")
    local stripLine = Tex(ed, "BORDER")
    local sum = Font(ed, 11, COL.faint)
    sum:SetWordWrap(true)
    EF.summary = sum
    local rm = QuietX(ed)
    rm:SetScript("OnClick", function()
        local r = Rec()
        local c = r and EF.OpenCard(r)
        if not (c and rm._fx) then return end
        AT.CloseDropdown()
        EF.RemoveFx(r, c, rm._fx)
        Relay()
    end)
    EF.remove = rm
    local note = Font(ed, 11, COL.faint)

    -- the lines: a Look line per state entry (kinds share keys with fields of
    -- their own), an own look's lines, the add under a state's look, and the
    -- effect blocks, each built once
    local looks, built = {}, {}
    local function LookOf(st)
        local L = looks[st]
        if not L then
            local B, def = E.LookLine(ed, st, Rec, owner, Relay, T)
            -- the tab names it
            if B.name then B.name:SetText("") end
            L = { B = B, def = def }
            looks[st] = L
        end
        return L
    end
    EF.LookLineOf = LookOf
    local function Which()
        local r = Rec()
        if not r then return nil end
        local st, i = EF.PickedLook(r)
        return r, st, i
    end
    local function PickedOf()
        local r = Rec()
        if not r then return nil end
        return r, (EF.PickedState(r))
    end
    local function Place(i)
        local r = Rec()
        local st = r and EF.PickedState(r)
        if st then EF.Pick(r, i and EF.LookKey(st.key, i) or st.key) end
    end
    -- an own look's lines and the add line: made the first time a look shows
    local ownD1, addD
    local fixed = {}
    local function Fixed()
        if ownD1 then return end
        local ownB1, d1, ownB2, d2 = E.OwnLookLines(ed, Which, Relay, Place)
        ownB1.name:SetText("")
        local addB, dA = E.AddLookLine(ed, PickedOf, T, pg, Relay, Place)
        ownD1, addD = d1, dA
        fixed[d1], fixed[d2], fixed[dA] = ownB1, ownB2, addB
        EF.ownLines, EF.addLine = { ownB1, ownB2 }, addB
    end
    -- a count state's rule line (its When tab), made once each
    local countDefs = {}
    local function CountDefs(C)
        local d = countDefs[C.key]
        if not d then
            d = { section = C.section, fields = { C.rule, C.a, C.b }, lineName = false, flat = true, countRule = C }
            countDefs[C.key] = d
        end
        return d
    end
    local function LineOf(def)
        if fixed[def] then return fixed[def] end

        if def.look then
            for _, L in pairs(looks) do
                if L.def == def then return L.B end
            end
        end
        local B = built[def]
        if not B then
            B = E.BlockLine(ed, def, Rec, owner, Relay)
            built[def] = B
        end
        return B
    end
    EF.lines = built

    -- the defs an effect's panel lays, in the board's order
    local function PanelDefs(r, c, fx)
        Fixed()
        if c.i then return { ownD1 } end
        if c.isCount and fx == "when" then return { CountDefs(c.count) } end
        local st = c.st
        local out = {}
        if fx == "look" then
            local rule = RULES[st.key]
            if rule then return { rule } end
            for _, def in ipairs(LookRows(r, st)) do out[#out + 1] = def end
            if st.alpha or st.grey or st.tint then out[#out + 1] = LookOf(st).def end
            local keep = KeepDef(r, st)
            if keep and E.blockShows(r, keep) then out[#out + 1] = keep end
            for _, def in ipairs(EXTRA[st.key] or {}) do
                if E.blockShows(r, def) then out[#out + 1] = def end
            end
            if E.LookCanAdd(r, st) then out[#out + 1] = addD end
            return out
        end
        local keys = KeysOf(r, st, fx)
        for _, k in ipairs(keys) do
            local def = E.KeyDef(r, k)
            if def then out[#out + 1] = Wrap(def, fx, #keys == 1) end
        end
        for _, def in ipairs(E.FX_KIND_BLOCKS[fx] or {}) do
            if E.blockShows(r, def) then out[#out + 1] = Wrap(def, fx, false) end
        end
        return out
    end
    EF.PanelDefs = PanelDefs

    -- every line not drawn this pass hides: a shown control hidden and
    -- shown again drops a drag in hand, so only the leaving ones do
    local function HideLines(staying)
        for _, L in pairs(looks) do
            if not staying[L.B] then L.B:Hide() end
        end
        for _, B in pairs(built) do
            if not staying[B] then B:Hide() end
        end
        for _, B in pairs(fixed) do
            if not staying[B] then B:Hide() end
        end

    end

    -- a tab's width at a padding
    local function TabW(t, padX) return padX + 12 + 6 + Measure(t._fs) + padX end
    -- Lays the open trigger's body under its head, from y, pw wide: its
    -- folder tabs, + Add effect, the picked effect's panel. Returns its height.
    local function LayBody(r, c, y, pw)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", row, "TOPLEFT", EF.PANEL_X, y)
        body:SetWidth(pw)
        bodyFill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
        bodyEdge:Lay()
        bodyEdge:Color(COL.line)
        body:Show()
        local inner = pw - PAD * 2
        local have = Have(r, c)
        -- a tab in use stays until its Remove
        for _, fx in ipairs(have) do SetAdded(r, c.key, fx, true) end
        local picked = EF.TabOf(r, c, have)
        if c.st and picked and E.SetOpen then E.SetOpen(r, c.st.key, picked) end
        local mid = MidInk()
        for i, fx in ipairs(have) do
            local t = Tab(i)
            t._fx = fx
            t._fs:SetText(Tr(FX_WORD[fx]))
        end
        -- the board's padding, tighter where the tabs would not fit
        local padX = 9
        local function RowW(p)
            local s = 0
            for i = 1, #have do s = s + TabW(tabs[i], p) + (i > 1 and 3 or 0) end
            return s
        end
        if RowW(padX) > inner then padX = 5 end
        local tabsW = RowW(padX)
        -- + Add effect after the tabs, or above them where they leave it no room
        local left = #Allowed(r, c) > #have
        local addW = left and AddFxButton():GetWidth() or 0
        local above = left and #have > 0 and tabsW + 3 + 5 + addW > inner
        local by = 0
        if above then by = by - 23 - 6 end
        local tabsBottom = by - EF.TAB_ON_H
        local x = PAD
        for i, fx in ipairs(have) do
            local t = tabs[i]
            local on = fx == picked
            local h = on and EF.TAB_ON_H or EF.TAB_H
            local ink = on and COL.ink or mid
            t._fs:SetTextColor(ink[1], ink[2], ink[3])
            local g = t._glyphs[fx]
            if not g then
                g = E.Glyph(t, fx)
                g:SetScale(0.86)
                t._glyphs[fx] = g
            end
            for k, gg in pairs(t._glyphs) do gg:SetShown(k == fx) end
            g:ClearAllPoints()
            g:SetPoint("LEFT", padX / 0.86, 0)
            local fxc = FxInk(r, c, fx)
            g:SetColor(fxc)
            t._fs:ClearAllPoints()
            t._fs:SetPoint("LEFT", padX + 12 + 6, 0)
            local tw = TabW(t, padX)
            t:SetSize(tw, h + (on and 1 or 0))
            t:ClearAllPoints()
            -- the open tab reaches one line into the panel, over its top edge
            t:SetPoint("BOTTOMLEFT", body, "TOPLEFT", x, tabsBottom - (on and 1 or 0))
            local fill = on and COL.box or COL.well
            t._fill:SetVertexColor(fill[1], fill[2], fill[3], 1)
            t._edge:Lay()
            t._edge:Color(COL.line, on and { t = true, l = true, r = true } or nil)
            t._top:SetHeight(2 * AT.Hairline(t))
            t._top:SetVertexColor(fxc[1], fxc[2], fxc[3], 1)
            t._top:SetShown(on)
            t:SetFrameLevel(ed:GetFrameLevel() + (on and 2 or 0))
            t:Show()
            x = x + tw + 3
        end
        for i = #have + 1, #tabs do tabs[i]:Hide() end
        if left then
            addFx:Show()
            addFx:ClearAllPoints()
            if above then addFx:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, 0)
            else addFx:SetPoint("BOTTOMLEFT", body, "TOPLEFT", x + (#have > 0 and 5 or 0), tabsBottom + 3) end
        elseif addFx then
            addFx:Hide()
            fxMenu:Hide()
        end
        EF.addAbove = above
        local yb
        if #have == 0 then
            -- nothing on it yet: a word, and the add above it
            ed:Hide()
            HideLines({})
            local words = Tr("Nothing on this trigger yet. + Add effect gives it a look, a glow or a sound.")
            empty:SetText(words)
            empty:SetWidth(inner)
            empty:ClearAllPoints()
            empty:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, tabsBottom - 10)
            empty:Show()
            yb = tabsBottom - 10 - WrapLines(words, inner, W11) * 14 - 12
        else
            empty:Hide()
            local fxc = FxInk(r, c, picked)
            -- whole pixels: the accent 3, the open tab's top 2
            accent:SetWidth(3 * AT.Hairline(ed))
            accent:SetVertexColor(fxc[1], fxc[2], fxc[3], 1)
            rm._fx = picked
            rm:SetWords(c.i and Tr("Remove look") or (Tr("Remove") .. " " .. Tr(FX_WORD[picked]):lower()))
            -- a count state's rule tab: no Remove (the rule goes with the trigger)
            rm:SetShown(picked ~= "when")
            -- the head strip: the effect in words (wrapping where the panel is
            -- narrow, the strip growing with it) and Remove at its right
            local words = EF.Summary(r, c, picked)
            sum:SetText(words)
            local room = math.max(40, inner - 3 - 10 - (rm:IsShown() and (rm:GetWidth() + 7) or 0) - 8)
            local sl = WrapLines(words, room, W11)
            sum:SetWidth(room)
            local hh = math.max(EF.HEAD_H, sl * 13 + 10)
            strip:ClearAllPoints()
            strip:SetPoint("TOPLEFT", accent, "TOPRIGHT", 0, -1)
            strip:SetPoint("TOPRIGHT", ed, "TOPRIGHT", -1, -1)
            strip:SetHeight(hh - 1)
            strip:SetVertexColor(COL.head[1], COL.head[2], COL.head[3], 1)
            stripLine:ClearAllPoints()
            stripLine:SetPoint("TOPLEFT", accent, "TOPRIGHT", 0, -hh)
            stripLine:SetPoint("TOPRIGHT", ed, "TOPRIGHT", -1, -hh)
            stripLine:SetHeight(AT.Hairline(ed))
            stripLine:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
            sum:ClearAllPoints()
            sum:SetPoint("LEFT", ed, "TOPLEFT", 3 + 10, -hh / 2)
            rm:ClearAllPoints()
            rm:SetPoint("RIGHT", ed, "TOPRIGHT", -7, -hh / 2)
            EF.stripH, EF.sumRoom = hh, room
            ed:ClearAllPoints()
            ed:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, tabsBottom)
            ed:SetWidth(inner)
            local defs = PanelDefs(r, c, picked)
            local staying = {}
            for _, def in ipairs(defs) do staying[LineOf(def)] = true end
            HideLines(staying)
            local ly = E.LayLines(ed, r, defs, LineOf, 3 + ROW_X, inner - ROW_X, -(hh + 5), note,
                { flat = true, gap = GAP, minRoom = 320, squeeze = true })
            local eh = math.floor(-ly + 4 + 0.5)
            ed:SetHeight(eh)
            ed:Show()
            yb = tabsBottom - eh - 12
        end
        return -yb
    end

    -- a box of words
    -- under the head of the fade rules (their rows are on the page under the
    -- list), or in the panel's place while nothing is listed
    local box, boxFill, boxEdge, boxNote
    local function Box()
        if box then return box end
        box = CreateFrame("Frame", nil, row)
        boxFill = Tex(box, "BACKGROUND")
        boxFill:SetAllPoints()
        boxEdge = Edges(box)
        boxNote = Font(box, 12, COL.faint)
        boxNote:SetWordWrap(true)
        boxNote:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -14)
        EF.box, EF.boxNote = box, boxNote
        return box
    end
    local function LayBox(y, pw, words)
        Box()
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", row, "TOPLEFT", EF.PANEL_X, y)
        box:SetWidth(pw)
        boxFill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
        boxEdge:Lay()
        boxEdge:Color(COL.line)
        boxNote:SetText(words)
        boxNote:SetWidth(pw - 24)
        box:Show()
        return 14 + WrapLines(words, pw - 24, W13) * 15 + 14
    end

    -- the tile picker
    local picker, pickEdge, closeX
    local tiles, caps = {}, {}
    EF.tiles, EF.pickCaps = tiles, caps
    local function PaintTile(t, hot)
        local m = t._mini
        if t._added then
            t:SetBackdropColor(0, 0, 0, 0)
            local e = Mix(COL.box, COL.line, 0.5)
            t:SetBackdropBorderColor(e[1], e[2], e[3], 1)
            t._name:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            local l = Mix(COL.faint, COL.panel, 0.3)
            t._line:SetTextColor(l[1], l[2], l[3])
            m:SetAlpha(0.55)
        else
            local bg = hot and COL.btn or COL.well
            local e = hot and COL.arc or COL.line
            t:SetBackdropColor(bg[1], bg[2], bg[3], 1)
            t:SetBackdropBorderColor(e[1], e[2], e[3], 1)
            t._name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            t._line:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            m:SetAlpha(1)
        end
        if t._check then t._check:SetShown(t._added == true) end
    end
    local function Picker()
        if picker then return picker end
        picker = CreateFrame("Frame", nil, row)
        local fill = Tex(picker, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
        pickEdge = Edges(picker)
        picker._edge = pickEdge
        closeX = BoxBtn(picker, "x")
        closeX:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -7, -4)
        AT.Tooltip(closeX, "Close", "Back to the trigger you had open.")
        closeX:SetScript("OnClick", function()
            local r = Rec()
            if not r then return end
            AT.CloseDropdown()
            EF.SetPicking(r, false)
            Relay()
        end)
        EF.picker, EF.pickClose = picker, closeX
        return picker
    end
    local function Tile(i)
        local t = tiles[i]
        if t then return t end
        t = CreateFrame("Button", nil, picker, "BackdropTemplate")
        AT.Skin(t, COL.well, COL.line)
        t._mini = Mini(t, 24)
        t._mini:SetPoint("LEFT", t, "LEFT", 9, 0)
        t._name = Font(t, 13, COL.ink)
        t._name:SetWordWrap(true)
        t._line = Font(t, 10, COL.faint)
        t._line:SetWordWrap(true)
        t:SetScript("OnEnter", function(self) PaintTile(self, true) end)
        t:SetScript("OnLeave", function(self) PaintTile(self, false) end)
        t:SetScript("OnClick", function(self)
            if self._added then return end
            local r = Rec()
            if not r then return end
            AT.CloseDropdown()
            -- the trigger lists and opens, the picker shuts (a count state gets its start rule)
            if not EF.AddCount(r, self._key) then EF.Pick(r, self._key) end
            local played = self._key ~= "while" and Options.PlayPreview and Options.PlayPreview(r, self._key)
            if not played then Relay() end
        end)
        tiles[i] = t
        return t
    end
    -- Lays the picker from y, pw wide; returns its height. The states fill
    -- the width two or three to a row (one on a narrow panel), the other
    -- groups sit side by side under them.
    local function LayPicker(r, y, pw)
        Picker()
        picker:ClearAllPoints()
        picker:SetPoint("TOPLEFT", row, "TOPLEFT", EF.PANEL_X, y)
        picker:SetWidth(pw)
        pickEdge:Lay()
        pickEdge:Color(COL.line)
        picker:Show()
        local inner = pw - 20
        local cols = inner >= 684 and 3 or (inner >= 360 and 2 or 1)
        EF.pickCols = cols
        local nt, nc = 0, 0
        -- one group: its caption, its tiles in rows; returns its bottom
        local function Group(g, gx, gy, gw, gcols)
            nc = nc + 1
            local cap = caps[nc]
            if not cap then
                cap = Font(picker, 10, COL.faint)
                caps[nc] = cap
            end
            cap:SetText(Tr(g.title))
            cap:ClearAllPoints()
            cap:SetPoint("TOPLEFT", picker, "TOPLEFT", 10 + gx, gy - 6)
            cap:Show()
            local ty = gy - 22
            local tw = math.floor((gw - 9 * (gcols - 1)) / gcols)
            local i = 1
            while i <= #g.tiles do
                local rowH = 36
                local made = {}
                for k = i, math.min(#g.tiles, i + gcols - 1) do
                    local d = g.tiles[k]
                    nt = nt + 1
                    local t = Tile(nt)
                    t._key, t._added, t._card = d.key, d.added == true, d.card
                    if t._added and not t._check then
                        t._check = Check(t)
                        t._check:SetPoint("RIGHT", t, "RIGHT", -9, 0)
                    end
                    t._name:SetText(d.name)
                    t._line:SetText(d.line)
                    local textW = tw - 41 - 9 - (t._added and (12 + 8) or 0)
                    local nl, ll = WrapLines(d.name, textW, W13), WrapLines(d.line, textW, W10)
                    t._name:SetWidth(textW)
                    t._line:SetWidth(textW)
                    t._nl, t._ll, t._textW = nl, ll, textW
                    PaintMini(t._mini, r, EF.MiniLook(r, d.card))
                    PaintTile(t, false)
                    rowH = math.max(rowH, 4 + nl * NAME_LH + 1 + ll * 13 + 4)
                    made[#made + 1] = { t = t, k = k - i }
                end
                for _, mk in ipairs(made) do
                    local t = mk.t
                    t:SetSize(tw, rowH)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", picker, "TOPLEFT", 10 + gx + mk.k * (tw + 9), ty)
                    local block = t._nl * NAME_LH + 1 + t._ll * 13
                    local top = math.floor((rowH - block) / 2)
                    t._name:ClearAllPoints()
                    t._name:SetPoint("TOPLEFT", t, "TOPLEFT", 41, -top)
                    t._line:ClearAllPoints()
                    t._line:SetPoint("TOPLEFT", t, "TOPLEFT", 41, -(top + t._nl * NAME_LH + 1))
                    t:Show()
                end
                ty = ty - rowH - 5
                i = i + gcols
            end
            return ty + 5
        end
        local groups = EF.Offers(r)
        local y0, bottom = 0, 0
        local sideW = cols >= 2 and math.floor((inner - 9 * (cols - 1)) / cols) or inner
        local gx, rowBottom = 0, 0
        for gi, g in ipairs(groups) do
            if not g.side then
                if gx > 0 then y0, gx = rowBottom, 0 end
                bottom = Group(g, 0, y0, inner, cols)
                y0, rowBottom = bottom, bottom
            else
                if gx > 0 and gx + sideW > inner + 0.5 then y0, gx = rowBottom, 0 end
                local b = Group(g, gx, y0, sideW, 1)
                rowBottom = (gx == 0) and b or math.min(rowBottom, b)
                gx = gx + sideW + 9
                bottom = math.min(bottom, rowBottom)
            end
            if gi == #groups then bottom = math.min(bottom, rowBottom) end
        end
        for i = nt + 1, #tiles do tiles[i]:Hide() end
        for i = nc + 1, #caps do caps[i]:Hide() end
        return -bottom + 10
    end

    -- the pass
    local lastOpen, lastRec
    row._sync = function()
        local r = Rec()
        if not r then return end
        local w = row:GetWidth() or 0
        if w <= 100 then
            -- no width yet: the page's, less its edges
            w = (pg:GetWidth() or 0) - 8
            if w <= 100 then pg._sizeUnresolved = true w = 700 end
        end
        local px = AT.Hairline(row)
        local cards = EF.Cards(r)
        local picking = EF.Picking(r)
        local open = (not picking) and EF.OpenCard(r, cards) or nil
        local top = -(EF.TITLE_H + EF.GAP_Y)
        local rowW = EF.SIDE_W - 2 * px
        -- the list: at the full text width, narrower by the strip when it scrolls
        local textW = rowW - TEXT_X - 9
        local lmax = ListMax()
        local lays, total = MeasureRows(r, cards, textW)
        local scroll = total > lmax
        if scroll then lays, total = MeasureRows(r, cards, textW - STRIP) end
        local listH = scroll and lmax or total
        local colMin = COL_TOP + listH + COL_FOOT
        EF.scrolls, EF.listH = scroll, listH
        -- the panel: the picker, the open trigger, or a word
        local pw = w - EF.PANEL_X
        local ph, last, lastOwn = 0, nil, 0
        if picking then
            ph = LayPicker(r, top, pw)
            last, lastOwn = picker, ph
        elseif picker then
            picker:Hide()
        end
        if open then
            local hh = LayHead(r, open, top, pw)
            if open.isWhile then
                body:Hide()
                HideLines({})
                local bh = LayBox(top - hh - EF.HEAD_GAP, pw, Tr("Its rules are below."))
                ph, last, lastOwn = hh + EF.HEAD_GAP + bh, box, bh
            else
                if box then box:Hide() end
                local bh = LayBody(r, open, top - hh - EF.HEAD_GAP, pw)
                ph, last, lastOwn = hh + EF.HEAD_GAP + bh, body, bh
            end
        else
            head:Hide()
            body:Hide()
            HideLines({})
            if not picking then
                local bh = LayBox(top, pw, Tr("Nothing changes this icon yet. + Add a trigger picks what does."))
                ph, last, lastOwn = bh, box, bh
            elseif box then
                box:Hide()
            end
        end
        -- the column and the panel end together
        local H = math.max(colMin, ph)
        if last then last:SetHeight(lastOwn + (H - ph)) end
        col:SetHeight(H)
        colFill:SetVertexColor(COL.well[1], COL.well[2], COL.well[3], 1)
        colEdge:Lay()
        colEdge:Color(COL.line)
        -- the rows
        local y = 0
        local openAt, openH
        for i, L in ipairs(lays) do
            local on = open ~= nil and L.card.key == open.key
            if on then openAt, openH = y, L.h end
            PaintRow(ListRow(i), r, L, on, y, rowW)
            y = y + L.h
        end
        for i = #lays + 1, #rows do rows[i]:Hide() end
        content:SetSize(rowW, math.max(1, total))
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", col, "TOPLEFT", px, -COL_TOP)
        host:SetSize(rowW, math.max(1, listH))
        -- the wheel scrolls the list only while it overflows, else the page;
        -- the strip over the rows, so it takes the clicks along its edge
        host:EnableMouseWheel(scroll)
        sb.track:SetFrameLevel(content:GetFrameLevel() + 10)
        -- a newly opened trigger's row scrolled whole into view
        local key = open and open.key or (picking and "+pick") or nil
        if not scroll then
            host:SetVerticalScroll(0)
        elseif (key ~= lastOpen or r ~= lastRec) and openAt then
            local cur = host:GetVerticalScroll() or 0
            if openAt < cur then cur = openAt
            elseif openAt + openH > cur + listH then cur = openAt + openH - listH end
            host:SetVerticalScroll(math.max(0, math.min(cur, total - listH)))
        end
        lastOpen, lastRec = key, r
        host:UpdateScroll()
        -- + Add a trigger 9 under the last row, the column running on below it
        add:ClearAllPoints()
        add:SetPoint("TOPLEFT", col, "TOPLEFT", 1 + 9, -(COL_TOP + listH + 9))
        PaintAdd(picking)
        local want = math.floor(EF.TITLE_H + EF.GAP_Y + H + 2 + 0.5)
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
        end
        -- an open popover follows the record
        local pop = T.pop
        if pop and pop:IsShown() then pop:Sync() end
    end

    -- the search: every setting of every trigger, each own look by its name;
    -- a jump opens the trigger holding it, picks its effect's tab (adding it)
    -- and opens a fold for a tuning one
    local function Labels(r, c)
        local out = {}
        if c.isWhile then return out end
        -- a count state's rule, on its When tab; its effects as any state's
        if c.isCount then
            local d = CountDefs(c.count)
            local sec = Schema.icon[c.count.section]
            for _, fld in ipairs(d.fields) do
                local fdef = sec and sec.fields[fld]
                if fdef and Options.FieldShows(r, "icon", c.count.section, fdef) then
                    out[#out + 1] = { label = fdef.label or fld, def = d, fdef = fdef, fx = "when" }
                end
            end
        end
        if c.i then
            out[1] = { label = Tr(E.StateWord(r, c.st)) .. ", " .. E.LookWords(c.look), fx = "look" }
            return out
        end
        for _, fx in ipairs(Allowed(r, c)) do
            local defs
            if fx == "look" and not RULES[c.st.key] then
                defs = {}
                for _, def in ipairs(LookRows(r, c.st)) do defs[#defs + 1] = def end
                local keep = KeepDef(r, c.st)
                if keep then defs[#defs + 1] = keep end
                for _, def in ipairs(EXTRA[c.st.key] or {}) do defs[#defs + 1] = def end
                if c.st.alpha or c.st.grey or c.st.tint then
                    for _, P in ipairs(LookOf(c.st).B.pairs) do
                        out[#out + 1] = { label = (P.fdef and P.fdef.label) or P.words, fx = fx }
                    end
                end
            else
                defs = PanelDefs(r, c, fx)
            end
            for _, def in ipairs(defs) do
                local sec = def.section and Schema.icon[def.section]
                for _, fld in ipairs(def.fields or {}) do
                    local fdef = sec and sec.fields[fld]
                    if fdef and Options.FieldShows(r, "icon", def.section, fdef) then
                        out[#out + 1] = { label = fdef.label or fld, def = def, fdef = fdef, fx = fx,
                            adv = fdef.adv ~= nil and not def.flat }
                    end
                end
            end
        end
        return out
    end
    EF.Labels = Labels
    -- a setting on several triggers (Keep bright on every look): a listed one
    -- that already has its tab first, then a listed one, then any
    local function Find(r, label)
        local listed, any = nil, nil
        for _, c in ipairs(AllCards(r)) do
            for _, l in ipairs(Labels(r, c)) do
                if l.label == label then
                    local on = Listed(r, c)
                    if on and (not l.fx or EF.Has(r, c, l.fx)) then return c, l end
                    if on and not listed then listed = { c, l } end
                    if not any then any = { c, l } end
                end
            end
        end
        local hit = listed or any
        if hit then return hit[1], hit[2] end
    end
    row._adSearch = function()
        local out = {}
        local r = Rec()
        if not r then return out end
        for _, c in ipairs(AllCards(r)) do
            for _, l in ipairs(Labels(r, c)) do out[#out + 1] = l.label end
        end
        return out
    end
    row._adRevealFor = function(label)
        local r = Rec()
        if not r then return end
        local c, l = Find(r, label)
        if not c then return end
        EF.Pick(r, c.key)
        if l.fx then
            if not EF.Has(r, c, l.fx) then SetAdded(r, c.key, l.fx, true) end
            EF.PickTab(r, c, l.fx)
        end
        if l.adv and l.def then
            local folds = l.def.foldSession and E.SessionFolds() or E.FoldState()
            folds["fx." .. l.def.section .. "." .. l.def.fields[1]] = true
        end
    end
    -- a hit's note when a switch or a choice hides the setting (rec: a
    -- record the hit was found on)
    row._adDepNoteFor = function(label, rec)
        local r = rec or Rec()
        local S = Options.Search
        if not (r and S and S.DepNote) then return nil end
        local _, l = Find(r, label)
        if l and l.fdef then
            return S.DepNote({ _adMeta = { family = "icon", section = l.def.section, def = l.fdef } })
        end
    end
    -- the state a hit sits under, for the search's own words
    row._adStateFor = function(label, rec)
        local r = rec or Rec()
        if not r then return nil end
        local c = Find(r, label)
        return c and c.st and c.st.key or nil
    end
    return row
end
