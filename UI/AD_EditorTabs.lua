-- AD_EditorTabs: the editors' tabs by effect: the state table and its Effects box, the More options folds, the glow and sound cards, and the new home of a tab pick made before the regroup.
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
-- The rows the caller adds after it show while it is open. A plain fold: it
-- opens and shuts on a click (the search opens it for a hit), and a changed
-- value inside only shows in its tooltip.
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
        if f:Changed() then return "Fine-tuning for the rows above; some differ from their default. Click to show or hide it." end
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
    return ET.ShowAll() or ET.FoldState()[self.key] == true
end

-- With Show every option on, the rows show inline and the fold row goes.
function Fold:HeadShown()
    return not ET.ShowAll() and self:Count() > 0
end

-- Show every option holds every fold open, so the click does nothing then.
function Fold:Toggle()
    AT.CloseDropdown()
    if ET.ShowAll() then return end
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

-- A card: the theme's card (AT.Card) on one of the record's switches. Its
-- header is that switch's row for the search, and the card shows while the
-- switch's row would. spec: vis, ctx, family, section, switch (a bool field),
-- name, when (words, or a function(rec) giving them), word (the switch's own
-- name, for its tooltip). Add the rows, then ET.CardEnd.
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
-- switch, when it fires, look, gates, then the tuning (the tuning folds away)
local GLOW_ORDER = { "When", "TimeUnit", "TimePct", "TimeSec", "AuraLength", "Type", "Color",
    "CombatOnly", "For", "Speed", "Lines", "Thickness", "Length", "Particles", "Intensity", "Scale",
    "XOffset", "YOffset", "MoveX", "MoveY", "Strata", "Level" }

-- When each glow card fires, in plain words for its header.
local WARN_WORDS = { ammo = "your ammo runs low", petHealth = "your pet's health is low",
    petMood = "your pet is not happy" }
local AURA_WORDS = { always = "the aura is up", pandemic = "the last 30% of it", time = "little time is left",
    missing = "the aura is missing", both = "always" }
ET.GLOW_WHEN = {
    -- a deck's glows have cards of their own; Nature's Guardian, a timer, keeps When ready
    ready = function(rec) return rec.kind == "special" and "its internal cooldown is ready" or "cooldown done" end,
    cooldown = "the cooldown runs",
    active = function(rec)
        if rec.kind == "timer" then return "it is active" end
        if rec.kind == "stance" then return ET.StanceOne(rec) and "you are in it" or "you are in a stance" end
        return rec.kind == "totem" and "the totem is out" or "the weapon has it"
    end,
    inactive = "it is not active",
    proc = "the proc glow is up",
    usable = "you can cast it now",
    overlay = function(rec)
        return ET.OverlayWords(rec, "its aura is up", "its totem is down", "the set duration runs")
    end,
    range = "the totem is out and its buff is not on you",
    outrange = "your target is out of range",
    recharge = "a charge is coming back",
    toggle = function(rec)
        local id = rec.driver and tonumber(rec.driver.spellID)
        local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        return (name or "it") .. " is on"
    end,
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
-- A spell icon's overlay rows in its source's words: an aura, its totem or a
-- set duration (Drivers\AD_DriverPhase.lua).
function ET.OverlayWords(rec, aura, totem, cast)
    local ov = rec and rec.driver and rec.driver.overlay
    local src = NS.DriverAura and NS.DriverAura.OverlaySource and NS.DriverAura.OverlaySource(ov)
    if src == "totem" then return totem end
    if src == "cast" then return cast end
    return aura
end
-- One field's every gate (its kind, class and game), as the editor reads it.
local function FieldOn(r, section, field)
    local sec = Schema.icon[section]
    local def = sec and sec.fields[field]
    return def ~= nil and Options.FieldShows ~= nil and Options.FieldShows(r, "icon", section, def) == true
end

-- An aura icon's numbered glows under Active or Missing: the ones on whose
-- Glow when names that state ("Always" names both), then the first one off,
-- which is how a glow is added there (ET.AuraGlowAdded).
local function AuraGlowKeys(missing)
    return function(r)
        local out, spare = {}, nil
        for k = 1, Schema.AURA_GLOW_SLOTS do
            local sfx = (k > 1) and tostring(k) or ""
            local key = A .. ".activeGlow" .. sfx
            if Store.Resolve(r, A, "activeGlow" .. sfx) == true then
                local when = Store.Resolve(r, A, "activeGlowWhen" .. sfx)
                if when == "both" or (when == "missing") == missing then out[#out + 1] = key end
            elseif not spare then
                spare = key
            end
        end
        if spare then out[#out + 1] = spare end
        return out
    end
end

local READY = { key = "ready", label = "Ready", when = "while it is ready", alpha = { S, "readyAlpha" },
    grey = { S, "readyDesaturate" }, tint = { S, "readyTintColor", on = "readyTintEnabled" },
    alphaTip = "0 hides it; the rules under the table can bring it back.",
    fx = { glow = { "states.readyGlow", "states.usableGlow" },
        sound = { "alerts.readySoundEnabled", "alerts.usableSoundEnabled" } } }
local COOLDOWN = { key = "cooldown", label = "On cooldown", when = "while it is on cooldown", alpha = { S, "cooldownAlpha" },
    grey = { S, "cooldownDesaturate" }, tint = { S, "cooldownTintColor", on = "cooldownTintEnabled" },
    fx = { glow = { "states.cooldownGlow" }, sound = { "alerts.cooldownSoundEnabled" } } }
local OUT_OF_STOCK = { key = "out", label = "Out of stock", when = "while none is left", alpha = { O, "outAlpha", on = "outAlphaEnabled" },
    grey = { O, "outDesaturate" },
    onTip = "On: this opacity while none is left. Off: it keeps its opacity." }
-- ammo running low or the pet in trouble (Drivers\AD_DriverWarn.lua), for
-- the classes with ammo or a pet: a glow, named for what it warns of
local WARN_LABEL = { ammo = "Ammo low", petHealth = "Pet health low", petMood = "Pet not happy" }
local WARNING = { key = "warn", label = "Warning", when = "while the warning is on",
    labelFn = function(r) return WARN_LABEL[Store.Resolve(r, S, "warnGlowWhen")] or "Warning" end,
    showIf = function(r) return FieldOn(r, S, "warnGlow") end,
    fx = { glow = { "states.warnGlow" } } }
local function GBNobody(r) return r ~= nil and Store.Resolve(r, "groupBuff", "remind") == "nobody" end
-- A charge spell's cooldown state is every charge spent: Depleted, listed
-- after Recharging (Ready, Recharging, Depleted).
function ET.IsCharge(r)
    local D = NS.DriverCooldown
    return r ~= nil and D ~= nil and D.IsCharge ~= nil and D.IsCharge(r) == true
end
-- A Special Aura that is a timer (Nature's Guardian) is ready or on cooldown.
function ET.SpecialTimer(r)
    local O = NS.Options
    return r ~= nil and O ~= nil and O.SpecialIsTimer ~= nil and O.SpecialIsTimer(r) == true
end
-- A stance icon set to one stance (else it shows your current stance).
function ET.StanceOne(r)
    return r ~= nil and Store.Resolve(r, "stance", "shows") == "one"
end
local SPELL_COOLDOWN = {}
for k, v in pairs(COOLDOWN) do SPELL_COOLDOWN[k] = v end
SPELL_COOLDOWN.labelFn = function(r) return ET.IsCharge(r) and "Depleted" or "On cooldown" end
-- One entry per state a kind has, in order: its key (the Effects box's pick),
-- its words, then the field each column drives as { section, field }. A tint's
-- switch is `on`; an opacity with `on` has a switch before its slider. A
-- missing column is a dash (`never`: words). `fx`: its effect blocks by effect, keys or a function(rec) giving
-- them. `base`: the switch picking whose look it copies, under its words.
ET.STATES = {
    spell = {
        READY,
        -- a charge spell with a charge left and another on its way; it copies
        -- Depleted or, with Wait for no charges, Ready
        { key = "recharge", label = "Recharging", when = "while a charge comes back",
          alpha = { S, "rechargeAlpha", on = "rechargeAlphaEnabled" },
          onTip = "On: this opacity while a charge comes back. Off: the opacity of the look picked under Recharging.",
          grey = { S, "rechargeDesaturate" }, tint = { S, "rechargeTintColor", on = "rechargeTintEnabled" },
          base = { S, "waitForNoCharges" },
          showIf = ET.IsCharge,
          fx = { glow = { "states.rechargeGlow" },
              sound = { "alerts.rechargeSoundEnabled", "alerts.chargeGainedSoundEnabled" } } },
        SPELL_COOLDOWN,
        { key = "unusable", label = "Can't use it", when = "while it can't be used", alpha = { S, "unusableAlpha" },
          grey = { S, "unusableDesaturate" }, tint = { S, "unusableTintColor", on = "unusableTintEnabled" },
          alphaTip = "Never brighter than Ready's opacity." },
        { key = "nomana", label = "Not enough resource", when = "while you lack the resource for it",
          alpha = { S, "resourceAlpha" },
          grey = { S, "resourceDesaturate" }, tint = { S, "resourceTintColor", on = "resourceTintEnabled" },
          alphaTip = "Never brighter than Ready's opacity." },
        { key = "range", label = "Out of range", when = "while your target is out of range", alpha = { S, "rangeAlpha" },
          grey = { S, "rangeDesaturate" }, tint = { S, "rangeTintColor", on = "rangeTint" },
          alphaTip = "Never brighter than Ready's opacity.",
          fx = { glow = { "states.rangeGlow" } } },
        -- Shoot, Auto Shot or Attack on (Drivers\AD_DriverToggle.lua)
        { key = "toggle", label = "Toggled on", when = "while it is toggled on",
          alpha = { S, "toggleAlpha", on = "toggleAlphaEnabled" },
          onTip = "On: this opacity while toggled on. Off: it keeps its opacity.",
          grey = { S, "toggleDesaturate" }, tint = { S, "toggleTintColor", on = "toggleTintEnabled" },
          showIf = function(r) return NS.DriverToggle ~= nil and NS.DriverToggle.IsToggle(r) end,
          fx = { glow = { "states.toggleGlow" } } },
        -- the game lights it up: its glow here, its opacity rule under the table
        { key = "proc", label = "Proc lit", when = "while the game lights it up",
          fx = { glow = { "states.procGlow" } } },
        WARNING,
        { key = "overlay", label = "Aura active", when = "while its aura is up", overlay = true,
          alpha = { A, "activeAlpha" },
          grey = { A, "activeDesaturate" }, tint = { A, "activeTintColor", on = "activeTintEnabled" },
          labelFn = function(r) return ET.OverlayWords(r, "Aura active", "Totem down", "Duration running") end,
          fx = { glow = { "auraActive.activeGlow" }, art = { "art.active" } } },
        { key = "overlayMissing", label = "Aura missing", when = "while its aura is down", overlay = true,
          grey = { A, "overlayDesatInactive" },
          labelFn = function(r) return ET.OverlayWords(r, "Aura missing", "Totem gone", "Duration over") end },
    },
    aura = {
        { key = "active", label = "Active", when = "while the aura is up", alpha = { A, "activeAlpha" },
          grey = { A, "activeDesaturate" }, tint = { A, "activeTintColor", on = "activeTintEnabled" },
          fx = { glow = AuraGlowKeys(false), sound = { "alerts.auraGainSoundEnabled", "alerts.auraStackSoundEnabled" },
              art = { "art.active" } } },
        { key = "missing", label = "Missing", when = "while the aura is missing", alpha = { M, "missingAlpha" },
          grey = { M, "missingDesaturate" },
          fx = { glow = AuraGlowKeys(true), sound = { "alerts.auraLostSoundEnabled" }, art = { "art.missing" } } },
    },
    item = { READY, COOLDOWN, OUT_OF_STOCK, WARNING },
    trinket = { READY, COOLDOWN, OUT_OF_STOCK, WARNING },
    -- a Custom Icon: active per its Show as active while (the ready bucket),
    -- else not active (the cooldown bucket); both can grey out
    timer = {
        { key = "active", label = "Active", when = "while it is active", alpha = READY.alpha,
          grey = READY.grey, tint = READY.tint, alphaTip = READY.alphaTip,
          fx = { glow = { "states.readyGlow" } } },
        { key = "inactive", label = "Not active", when = "while it is not active", alpha = COOLDOWN.alpha,
          grey = COOLDOWN.grey, tint = COOLDOWN.tint,
          fx = { glow = { "states.cooldownGlow" } } },
        WARNING,
    },
    totem = {
        { key = "active", label = "Active", when = "while the totem is out", alpha = READY.alpha,
          grey = READY.grey, tint = READY.tint,
          fx = { glow = { "states.readyGlow" } } },
        { key = "missing", label = "Missing", when = "while no totem is out", alpha = COOLDOWN.alpha,
          grey = COOLDOWN.grey, tint = COOLDOWN.tint },
        -- a totem set to one totem: out, but its buff not on you
        -- (Drivers\AD_TotemRange.lua); its look covers the art, so no opacity
        { key = "range", label = "Out of range", lookTitle = "Out of totem range", showIf = Schema.TotemBySpell,
          when = "while the totem is out and its buff is not on you",
          grey = { S, "totemRangeDesaturate" }, tint = { S, "totemRangeTintColor", on = "totemRangeTint" },
          fx = { glow = { "states.totemRangeGlow" } } },
        WARNING,
    },
    enchant = {
        { key = "active", label = "Active", when = "while the weapon has the enchant", alpha = READY.alpha,
          grey = READY.grey, tint = READY.tint,
          fx = { glow = { "states.readyGlow" }, sound = { "alerts.readySoundEnabled" } } },
        { key = "missing", label = "Missing", when = "while the weapon has none", alpha = COOLDOWN.alpha,
          grey = COOLDOWN.grey, tint = COOLDOWN.tint,
          fx = { sound = { "alerts.cooldownSoundEnabled" } } },
        WARNING,
    },
    ammo = {
        { key = "ready", label = "In stock", when = "while you have ammo", alpha = READY.alpha },
        OUT_OF_STOCK,
        WARNING,
    },
    -- a Special Aura: procs left in the deck, or every proc used; a timer
    -- (Nature's Guardian) ready, or its internal cooldown running
    special = {
        { key = "ready", label = "Procs left", when = "while it can still proc", alpha = READY.alpha,
          grey = READY.grey, tint = READY.tint, alphaTip = "0 hides it; the rules under the table can bring it back.",
          labelFn = function(r) return ET.SpecialTimer(r) and "Ready" or "Procs left" end,
          fx = { glow = { "states.readyGlow" }, sound = { "alerts.procSoundEnabled", "alerts.sureSoundEnabled" } } },
        { key = "cooldown", label = "All procs used", when = "while every proc is used, or its timer runs",
          alpha = COOLDOWN.alpha, grey = COOLDOWN.grey, tint = COOLDOWN.tint,
          labelFn = function(r) return ET.SpecialTimer(r) and "On cooldown" or "All procs used" end,
          fx = { glow = { "states.cooldownGlow" } } },
        WARNING,
    },
    -- a Group Buff: its count read between pulls (in combat it steps aside);
    -- labelFn words a state for an icon set to remind while nobody has it
    groupbuff = {
        { key = "lacking", label = "Someone lacks it", when = "while the buff is missing", alpha = READY.alpha,
          labelFn = function(r) return GBNobody(r) and "Nobody has it" or "Someone lacks it" end },
        { key = "covered", label = "Everyone has it", when = "while the buff is covered", alpha = COOLDOWN.alpha,
          grey = COOLDOWN.grey, alphaTip = "0 hides it (the default): it shows only while the buff is missing.",
          labelFn = function(r) return GBNobody(r) and "Someone has it" or "Everyone has it" end },
    },
    -- a Stance icon (Drivers\AD_DriverStance.lua): in it is the ready
    -- bucket, not in it the cooldown bucket; worded for what it shows
    stance = {
        { key = "active", label = "In the stance", when = "while you are in it", alpha = READY.alpha,
          grey = READY.grey, tint = READY.tint, alphaTip = READY.alphaTip,
          labelFn = function(r) return ET.StanceOne(r) and "In this stance" or "In a stance" end,
          fx = { glow = { "states.readyGlow" } } },
        { key = "inactive", label = "Not in the stance", when = "while you are not in it", alpha = COOLDOWN.alpha,
          grey = COOLDOWN.grey, tint = COOLDOWN.tint,
          labelFn = function(r) return ET.StanceOne(r) and "Not in it" or "No stance" end },
        WARNING,
    },
}

local COLS = { "alpha", "grey", "tint" }
local COL_WORD = { alpha = "opacity", grey = "grey out", tint = "tint" }
local SLIDER_W, VALUE_W = 96, 40

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

-- A row that waits on something: the aura overlay, or its own gate.
local function RowShows(st, rec)
    if st.overlay and not OverlayOn(rec) then return false end
    return not st.showIf or st.showIf(rec) == true
end

-- The state rows a record shows.
function ET.StatesFor(rec)
    local list = rec and ET.STATES[rec.kind]
    if not list then return nil end
    local out = {}
    for _, st in ipairs(list) do
        if RowShows(st, rec) then out[#out + 1] = st end
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
            end
        end
        if st.base then add(st.base[1], st.base[2]) end
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
            -- the columns' fields, then the look it copies (Recharging's)
            local specs = {}
            for _, c in ipairs(COLS) do
                if st[c] then specs[#specs + 1] = st[c] end
            end
            if st.base then specs[#specs + 1] = st.base end
            for _, spec in ipairs(specs) do
                for _, f in ipairs({ spec.on or false, spec[2] }) do
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
            for _, section in ipairs(order) do
                Options.LookBlock("icon", tabName, st.lookTitle or st.label, section, bySec[section])
            end
        end
    end
end

-- Effects

-- What a state can do beyond its look, by effect, in column order. Options
-- files each effect block (a glow or sound moment, an art block) under its key
-- (ET.FxBlock) and the rows every state's effect shares (the sound channel)
-- under the effect (ET.FxKindBlock); the editor under a table row draws them.
ET.FX_ORDER = { "glow", "sound", "art" }
ET.FX_WORD = { glow = "Glow", sound = "Sound", art = "Icon" }
-- a sound field's width in an editor line (it narrows on a short line)
ET.SOUND_W = 220
ET.FX_BLOCKS = {}
ET.FX_KIND_BLOCKS = {}
-- Options' gate for a block on a record: its kind, a switch's own row, and
-- for a block with no switch a row that can show.
ET.blockShows = nil

function ET.FxBlock(key, def)
    local list = ET.FX_BLOCKS[key]
    if not list then
        list = {}
        ET.FX_BLOCKS[key] = list
    end
    list[#list + 1] = def
end

function ET.FxKindBlock(kind, def)
    local list = ET.FX_KIND_BLOCKS[kind]
    if not list then
        list = {}
        ET.FX_KIND_BLOCKS[kind] = list
    end
    list[#list + 1] = def
end

-- The block a key names that the record shows (two kinds can share a key:
-- a spell's "When ready" and a totem's "While active" are one switch).
local function KeyDef(rec, key)
    local shows = ET.blockShows
    if not (shows and rec) then return nil end
    for _, def in ipairs(ET.FX_BLOCKS[key] or {}) do
        if shows(rec, def) then return def end
    end
end

-- A state's effects on a record: { kind, keys } in column order, the keys
-- whose blocks it shows.
function ET.FxFor(rec, st)
    local out = {}
    if not (rec and st and st.fx) then return out end
    for _, kind in ipairs(ET.FX_ORDER) do
        local list = st.fx[kind]
        if type(list) == "function" then list = list(rec) end
        local keys = {}
        for _, key in ipairs(list or {}) do
            if KeyDef(rec, key) then keys[#keys + 1] = key end
        end
        if #keys > 0 then out[#out + 1] = { kind = kind, keys = keys } end
    end
    return out
end

-- Any state the record shows has an effect (a group buff's have none).
function ET.AnyFx(rec)
    for _, st in ipairs(ET.StatesFor(rec) or {}) do
        if #ET.FxFor(rec, st) > 0 then return true end
    end
    return false
end

-- An effect block is on: its switch, or its own test (art).
function ET.FxLit(rec, key)
    local def = KeyDef(rec, key)
    if not def then return false end
    if def.lit then return def.lit(rec) == true end
    return Store.Resolve(rec, def.section, def.fields[1]) == true
end

-- A state's words on a record.
function ET.StateWord(rec, st)
    return (st.labelFn and rec and st.labelFn(rec)) or st.label
end

-- The editor open under the table, per kind, for the session: a state and an
-- effect, or none.
local function OpenStore(rec)
    local ui = Options.ui
    if not (ui and rec) then return nil end
    ui.condOpen = ui.condOpen or {}
    return ui.condOpen, rec.kind or "?"
end

-- The open state and effect, and the effect's keys, while the record still
-- shows that state with that effect.
function ET.Open(rec)
    local store, k = OpenStore(rec)
    local o = store and store[k]
    if not o then return nil end
    for _, st in ipairs(ET.StatesFor(rec) or {}) do
        if st.key == o.state then
            for _, f in ipairs(ET.FxFor(rec, st)) do
                if f.kind == o.fx then return st, f.kind, f.keys end
            end
            return nil
        end
    end
    return nil
end

-- Opens a state's effect under its row; no kind closes the editor.
function ET.SetOpen(rec, key, kind)
    local store, k = OpenStore(rec)
    if not store then return end
    store[k] = (key and kind) and { state = key, fx = kind } or nil
end

-- The search walks every editor, so the open pick stands aside while it indexes.
local function Indexing()
    local S = Options.Search
    return S ~= nil and S.indexing == true
end

-- The first state the record shows that holds a block (by key) or an effect
-- (by kind, key nil), and that effect: where a search jump lands.
local function FxFind(rec, key, kind)
    for _, st in ipairs(ET.StatesFor(rec) or {}) do
        for _, f in ipairs(ET.FxFor(rec, st)) do
            if key == nil and f.kind == kind then return st, f.kind end
            for _, k in ipairs(f.keys) do
                if k == key then return st, f.kind end
            end
        end
    end
end

-- A search jump onto an effect's setting opens it under its state's row.
function ET.RevealFx(rec, key, kind)
    local st, k = FxFind(rec, key, kind)
    if st then ET.SetOpen(rec, st.key, k) end
end

-- A numbered aura glow switched on under Missing glows while the aura is
-- missing; under Active, one left on "missing" goes back to "while up".
function ET.AuraGlowAdded(rec, sfx)
    if not (rec and rec.kind == "aura") then return end
    local st = ET.Open(rec)
    if not st then return end
    local field = "activeGlowWhen" .. (sfx or "")
    local when = Store.Resolve(rec, A, field)
    if st.key == "missing" and when ~= "missing" and when ~= "both" then
        Store.SetOverride(rec, A, field, "missing")
    elseif st.key == "active" and when == "missing" then
        Store.SetOverride(rec, A, field, "always")
    end
end

-- A block's switch on or off, as its card's header did.
local function SetSwitch(rec, def, v)
    local field = def.fields[1]
    Store.SetOverride(rec, def.section, field, v)
    local sec = Schema.icon[def.section]
    local sdef = sec and sec.fields[field]
    if sdef and sdef.onSet then sdef.onSet(rec, v) end
    if v and def.onOn then def.onOn(rec) end
end

-- The colour an effect's cell lights in: a glow's own (the first one on),
-- the accent for the others.
local function FxColor(rec, kind, keys)
    if kind == "glow" then
        for _, key in ipairs(keys) do
            local def = KeyDef(rec, key)
            if def and ET.FxLit(rec, key) then
                for _, f in ipairs(def.fields) do
                    if f:find("Color", 1, true) then
                        local c = Store.Resolve(rec, def.section, f)
                        if type(c) == "table" then return c end
                    end
                end
            end
        end
    end
    return COL.arc
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

-- The box a row draws of the table: its fill, its sides and its bottom edge,
-- and the top edge on the header. noBottom: a row whose editor is open below
-- it leaves its bottom edge to the editor.
local function TableEdges(row, top)
    local e = { l = Strip(row), r = Strip(row), b = Strip(row) }
    if top then e.t = Strip(row) end
    local fill = row:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture(AT.WHITE)
    fill:SetVertexColor(COL.box[1], COL.box[2], COL.box[3], 1)
    fill:SetPoint("TOPLEFT", 4, 0)
    fill:SetPoint("BOTTOMLEFT", 4, 0)
    return function(w, noBottom)
        local px = AT.Hairline(row)
        fill:SetWidth(math.max(1, w - 4))
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
        e.b:SetShown(not noBottom)
        if e.t then
            e.t:ClearAllPoints()
            e.t:SetPoint("TOPLEFT", 4, 0)
            e.t:SetWidth(w - 4 + px)
            e.t:SetHeight(px)
        end
    end, fill
end

-- A compact slider with its value box. lo and hi may be functions, re-read on
-- every refresh; pct shows a 0..1 value as a percent, fmtStr a raw format.
local function CompactSlider(parent, w, lo, hi, step, pct, fmtStr, get, set)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    local settingUp = true
    local function Lo() return type(lo) == "function" and lo() or lo end
    local function Hi() return type(hi) == "function" and hi() or hi end
    local function fmt(v)
        v = tonumber(v) or 0
        if pct then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
        if fmtStr then return fmtStr:format(v) end
        if step >= 1 then return tostring(math.floor(v + 0.5)) end
        return (("%.2f"):format(v):gsub("%.?0+$", ""))
    end
    local function refresh()
        settingUp = true
        local a, b = Lo(), Hi()
        s:SetMinMaxValues(a, b)
        local v = tonumber(get()) or a
        s:SetValue(math.max(a, math.min(b, v)))
        if not box:HasFocus() then box:SetText(fmt(v)) end
        settingUp = false
    end
    s:SetOrientation("HORIZONTAL")
    s:SetSize(w, 10)
    AT.Skin(s, COL.well)
    s:SetThumbTexture(AT.WHITE)
    local th = s:GetThumbTexture()
    th:SetSize(8, 10)
    th:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    s:SetMinMaxValues(Lo(), Hi())
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetScript("OnValueChanged", function(_, v)
        if settingUp then return end
        v = math.floor(v / step + 0.5) * step
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
        if n then
            if pct then n = n / 100 end
            n = math.floor(n / step + 0.5) * step
            set(math.max(Lo(), math.min(Hi(), n)))
        end
        refresh()
    end
    box:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetPoint("LEFT", s, "RIGHT", 6, 0)
    refresh()
    return s, box, refresh
end

-- The state table's opacity cell: the compact slider over 0..1, as percents.
local function OpacityCell(cell, get, set)
    return CompactSlider(cell, SLIDER_W, 0, 1, 0.01, true, nil, get, set)
end

-- A typed number (an id: empty reads 0). lo / hi clamp it, int rounds it.
local function NumberBox(parent, w, get, set, lo, hi, int, isId)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(w, 18)
    AT.Skin(box, COL.well)
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    local function refresh()
        if box:HasFocus() then return end
        local v = tonumber(get())
        if isId then box:SetText((v and v ~= 0) and tostring(v) or "")
        else box:SetText(v and tostring(v) or "") end
    end
    local function commit(self)
        local n = tonumber(self:GetText() or "")
        if isId then
            set(n or 0)
        elseif n then
            if int then n = math.floor(n + 0.5) end
            if lo then n = math.max(lo, n) end
            if hi then n = math.min(hi, n) end
            set(n)
        end
        refresh()
    end
    box:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    refresh()
    return box, refresh
end

-- The colour picker on a swatch; withAlpha offers opacity (the field's
-- alpha honoured), else the stored alpha stays.
local function PickColor(sw, get, set, withAlpha, alphaDefault, relay)
    local function A(c) return c[4] or alphaDefault or 1 end
    sw:SetScript("OnClick", function()
        AT.CloseDropdown()
        local picker = ColorPickerFrame
        if not (picker and picker.SetupColorPickerAndShow) then return end
        local c = get()
        local was = { c[1], c[2], c[3], c[4] }
        local ready, last = false, nil
        local function pick()
            if not ready then return end
            local r, g, b = picker:GetColorRGB()
            local a = withAlpha and (picker:GetColorAlpha() or A(was)) or A(get())
            if last and last[1] == r and last[2] == g and last[3] == b and last[4] == a then return end
            last = { r, g, b, a }
            set({ r, g, b, a })
            relay()
        end
        picker:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], hasOpacity = withAlpha, opacity = withAlpha and A(c) or nil,
            swatchFunc = pick, opacityFunc = withAlpha and pick or nil,
            cancelFunc = function()
                set({ was[1], was[2], was[3], was[4] })
                relay()
            end,
        })
        ready = true
    end)
end

-- Effect glyphs, drawn from bars like the theme's chevrons: a burst for a
-- glow, a speaker for a sound, a picture for the icon, a plus for none yet.
local GLYPH = {
    glow = { { 1.5, 3, 0, 4.5 }, { 1.5, 3, 0, -4.5 }, { 3, 1.5, 4.5, 0 }, { 3, 1.5, -4.5, 0 },
        { 1.5, 3, 3.2, 3.2, -45 }, { 1.5, 3, -3.2, 3.2, 45 }, { 1.5, 3, 3.2, -3.2, 45 }, { 1.5, 3, -3.2, -3.2, -45 } },
    sound = { { 2.5, 4, -4.25, 0 }, { 4, 1.5, -1.4, 2.5, 47 }, { 4, 1.5, -1.4, -2.5, -47 }, { 1.5, 8, 0.3, 0 },
        { 1.5, 3, 3, 1.9, 21 }, { 1.5, 3, 3, -1.9, -21 } },
    art = { { 12, 1.5, 0, 4 }, { 12, 1.5, 0, -4 }, { 1.5, 8, -5.25, 0 }, { 1.5, 8, 5.25, 0 },
        { 4.6, 1.5, -2.4, -1.3, 49 }, { 5.3, 1.5, 1.1, -1.3, -41 } },
    add = { { 8, 1.5, 0, 0 }, { 1.5, 8, 0, 0 } },
}

function ET.Glyph(parent, kind)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(14, 14)
    f._bars = {}
    for _, b in ipairs(GLYPH[kind] or GLYPH.add) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(AT.WHITE)
        t:SetSize(b[1], b[2])
        t:SetPoint("CENTER", b[3], b[4])
        if b[5] then t:SetRotation(math.rad(b[5])) end
        f._bars[#f._bars + 1] = t
    end
    function f:SetColor(c, a)
        for _, t in ipairs(self._bars) do t:SetVertexColor(c[1], c[2], c[3], a or 1) end
    end
    f:SetColor(COL.ink)
    return f
end

-- One setting as a label and its control side by side, for the editor's
-- lines. blk: the block def (its section, its card words), field: the schema
-- field. Returns the pair: label, ctrl, extra (a sound's Play), sync().
local function MakePair(ed, blk, field, ctx, owner, relay)
    local section = blk.section
    local fdef = Schema.icon[section].fields[field]
    local P = { field = field, fdef = fdef, adv = fdef.adv ~= nil }
    local words = (blk.labels and blk.labels[field]) or fdef.label or field
    local lbl = ed:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(STANDARD_TEXT_FONT, 12, "")
    lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    lbl:SetWordWrap(false)
    lbl:SetText(words)
    P.label, P.words = lbl, words
    local function Get()
        local r = ctx()
        return r and Store.Resolve(r, section, field)
    end
    local function Put(v)
        local r = ctx()
        if not r then return end
        Store.SetOverride(r, section, field, v)
        if fdef.onSet then fdef.onSet(r, v) end
    end
    local t = fdef.t
    if t == "bool" then
        local cb = AT.MakeCheckbox(ed)
        cb:SetScript("OnClick", function()
            AT.CloseDropdown()
            Put(Get() ~= true)
            PlaySound(Get() == true and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            relay()
        end)
        cb:HookScript("OnEnter", function() cb:SetHover(true) end)
        cb:HookScript("OnLeave", function() cb:SetHover(false) end)
        P.ctrl = cb
        P.sync = function() cb:SetOn(Get() == true) end
    elseif t == "enum" or t == "sound" or (t == "id" and fdef.auraSpellPick) then
        local items, get, set
        if t == "enum" then
            items = function()
                local out, rv = {}, ctx()
                for _, v in ipairs(fdef.values or {}) do
                    local cond = fdef.valueIf and fdef.valueIf[v]
                    if not cond or (rv ~= nil and cond(rv)) then
                        out[#out + 1] = { value = v, text = (fdef.labels and fdef.labels[v]) or v }
                    end
                end
                return out
            end
            get, set = Get, Put
        elseif t == "sound" then
            items = function()
                if NS.Sounds then return NS.Sounds.Items(fdef.files == true) end
                return { { value = "", text = "None" } }
            end
            get = function()
                local v = Get()
                return type(v) == "string" and v or ""
            end
            set = function(v) Put(type(v) == "string" and v or "") end
        else
            items = function() return Options.AuraGlowForItems(ctx()) end
            get = function() return Options.AuraGlowForValue(ctx(), section, field) end
            set = function(v) Put(tonumber(v) or 0) end
        end
        -- a sound field keeps a set width: sized to the longest sound name it
        -- ran past the editor's edge, and its pullout with it
        local fixed = t == "sound"
        local dd = AT.MakeDropdown(owner, ed, fixed and ET.SOUND_W or nil, items, get, set, function() relay() end)
        P.ctrl = dd
        P.sync = function()
            if fixed then dd:SetWidth(ET.SOUND_W) end
            dd.Refresh()
        end
        if t == "sound" then
            local play = AT.MakeSmallButton(ed, "Play", 44)
            play:SetScript("OnClick", function()
                AT.CloseDropdown()
                local r = ctx()
                if not (r and NS.Sounds) then return end
                NS.Sounds.Preview(get(), Store.Resolve(r, section, "soundChannel"))
            end)
            Tip(play, "Play", "Hear the chosen sound once, on this icon's sound channel.")
            P.extra = play
            -- on a line too short for it the field narrows, long names cut short
            P.fit = function(room)
                local other = Measure(lbl) + 8 + 4 + play:GetWidth()
                dd:SetWidth(math.max(80, math.floor(room - other)))
                return P.width()
            end
        end
    elseif t == "color" then
        local sw = AT.MakeSwatch(ed, 28, 14)
        local withAlpha = fdef.alpha == true
        local aDef = type(fdef.d) == "table" and fdef.d[4] or 1
        local function Cur()
            local c = Get() or fdef.d or { 1, 1, 1, 1 }
            return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] }
        end
        PickColor(sw, Cur, Put, withAlpha, aDef, relay)
        P.ctrl = sw
        P.sync = function()
            local c = Cur()
            sw:SetColor(c, withAlpha and (c[4] or aDef) or nil)
        end
    elseif t == "id" or ((t == "num" or t == "int") and fdef.input) then
        local box, refresh = NumberBox(ed, 56, Get, Put, fdef.min, fdef.max, t ~= "num", t == "id")
        P.ctrl = box
        P.sync = refresh
    elseif t == "num" or t == "int" then
        local int = t == "int"
        local lo = fdef.minFn and function() local r = ctx() return (r and fdef.minFn(r)) or fdef.min or 0 end
            or (fdef.min or 0)
        local hi = fdef.maxFn and function() local r = ctx() return (r and fdef.maxFn(r)) or fdef.max or (int and 100 or 1) end
            or (fdef.max or (int and 100 or 1))
        local pct = (not int) and not fdef.fmt and (fdef.max or 1) <= 1
        local s, box, refresh = CompactSlider(ed, 80, lo, hi, int and 1 or (fdef.step or 0.01), pct, fdef.fmt,
            function() return Get() or fdef.d or 0 end, Put)
        P.ctrl, P.extra = s, box
        P.extraGap = 6
        P.sync = refresh
    end
    if not P.ctrl then return nil end
    if fdef.desc then Tip(P.ctrl, fdef.label or words, fdef.desc) end
    P.width = function()
        local w = Measure(lbl) + 8 + (P.ctrl:GetWidth() or 0)
        if P.extra then w = w + (P.extraGap or 4) + (P.extra:GetWidth() or 0) end
        return w
    end
    P.place = function(x, y)
        lbl:ClearAllPoints()
        lbl:SetPoint("LEFT", ed, "TOPLEFT", x, y)
        P.ctrl:ClearAllPoints()
        P.ctrl:SetPoint("LEFT", ed, "TOPLEFT", x + Measure(lbl) + 8, y)
        if P.extra then
            P.extra:ClearAllPoints()
            P.extra:SetPoint("LEFT", P.ctrl, "RIGHT", P.extraGap or 4, 0)
        end
    end
    P.show = function(on)
        lbl:SetShown(on)
        P.ctrl:SetShown(on)
        if P.extra then P.extra:SetShown(on) end
    end
    -- an off block's settings dim in place and take no clicks
    P.dim = function(off)
        local a = off and AT.CARD_DIM or 1
        lbl:SetAlpha(a)
        P.ctrl:SetAlpha(a)
        P.ctrl:EnableMouse(not off)
        if P.extra then
            P.extra:SetAlpha(a)
            P.extra:EnableMouse(not off)
        end
    end
    return P
end

-- A setting shows on the record: its kind, class and game, and its deps but
-- the block's own switch (an off block dims instead).
local function PairShows(r, blk, fdef)
    if not (Options.FieldShows and Options.FieldShows(r, "icon", blk.section, fdef)) then return false end
    local dep = fdef.dep
    if not dep then return true end
    local list = dep.field and { dep } or dep
    for _, d in ipairs(list) do
        local own = blk.isCard and d.field == blk.fields[1] and (d.section == nil or d.section == blk.section)
        if not own and Options.DepOK and not Options.DepOK(r, "icon", blk.section, d) then return false end
    end
    return true
end
ET.PairShows = PairShows

local LINE_H, PAIR_GAP, BLOCK_GAP = 26, 18, 6

-- One block's line in an editor: its switch and name (a card's), its
-- settings side by side, and More with its finer settings. Built once.
local function BlockLine(ed, blk, ctx, owner, relay)
    local B = { blk = blk, pairs = {}, adv = {} }
    if blk.isCard then
        local cb = AT.MakeCheckbox(ed)
        cb:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r = ctx()
            if not r then return end
            local v = Store.Resolve(r, blk.section, blk.fields[1]) ~= true
            SetSwitch(r, blk, v)
            PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            relay()
        end)
        cb:HookScript("OnEnter", function() cb:SetHover(true) end)
        cb:HookScript("OnLeave", function() cb:SetHover(false) end)
        local sdef = Schema.icon[blk.section].fields[blk.fields[1]]
        Tip(cb, blk.word or (sdef and sdef.label) or blk.title, function()
            local r = ctx()
            local when = blk.cardWhen
            if type(when) == "function" then when = r and when(r) end
            local w = (type(when) == "string" and when ~= "") and ("When " .. when .. ". ") or ""
            return w .. ((sdef and sdef.desc) or "Off keeps its settings, greyed out.")
        end)
        B.check = cb
    end
    if blk.lineName ~= false then
        local nm = ed:CreateFontString(nil, "OVERLAY")
        nm:SetFont(STANDARD_TEXT_FONT, 12, "")
        nm:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        nm:SetWordWrap(false)
        nm:SetText(blk.lineName or blk.title or "")
        B.name = nm
    end
    for i = blk.isCard and 2 or 1, #blk.fields do
        local P = MakePair(ed, blk, blk.fields[i], ctx, owner, relay)
        if P then
            if P.adv then B.adv[#B.adv + 1] = P else B.pairs[#B.pairs + 1] = P end
        end
    end
    -- the finer settings fold away behind More (Settings > Panel > Show every
    -- option keeps them out)
    if #B.adv > 0 then
        local mb = CreateFrame("Button", nil, ed)
        mb:SetHeight(18)
        local chev = AT.MakeChevron(mb)
        chev:SetPoint("LEFT", 0, 0)
        local fs = mb:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 12, "")
        fs:SetPoint("LEFT", chev, "RIGHT", 4, 0)
        fs:SetText("More")
        mb:SetWidth(16 + Measure(fs) + 2)
        B.foldKey = "fx." .. blk.section .. "." .. blk.fields[1]
        local function Paint()
            local c = mb._hot and COL.ink or COL.dim
            fs:SetTextColor(c[1], c[2], c[3])
            chev:SetColor(mb._hot and COL.arc or COL.dim)
            chev:SetDown(ET.FoldState()[B.foldKey] == true)
        end
        mb:SetScript("OnClick", function()
            AT.CloseDropdown()
            local stt = ET.FoldState()
            local open = stt[B.foldKey] ~= true
            stt[B.foldKey] = open or nil
            PlaySound(open and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            relay()
        end)
        mb:SetScript("OnEnter", function() mb._hot = true Paint() end)
        mb:SetScript("OnLeave", function() mb._hot = nil Paint() end)
        Tip(mb, "More", "Fine-tuning for this one. Click to show or hide it.")
        B.more, B.paintMore = mb, Paint
        B.moreText = fs
    end
    function B:Hide()
        if self.check then self.check:Hide() end
        if self.name then self.name:Hide() end
        for _, P in ipairs(self.pairs) do P.show(false) end
        for _, P in ipairs(self.adv) do P.show(false) end
        if self.more then self.more:Hide() end
    end
    return B
end

-- A click on the page outside the open editor shuts it, as Done does. The
-- table's effect cells open, move or shut it themselves; an open pullout and
-- the color picker belong to it. It listens only while an editor shows.
local editorRows = {}
local outside = CreateFrame("Frame")

local function OverFxCell(T)
    for _, sr in ipairs(T.rows) do
        for _, b in pairs(sr._adFxCells or {}) do
            if b:IsVisible() and b:IsMouseOver() then return true end
        end
    end
    return false
end

function ET.ClickOutside(button)
    if button ~= "LeftButton" and button ~= "RightButton" then return end
    local dd = AT.openDropdown
    if dd and dd:IsShown() and dd:IsMouseOver() then return end
    if ColorPickerFrame and ColorPickerFrame:IsShown() then return end
    for _, er in ipairs(editorRows) do
        if er:IsVisible() and er._adIsOpen() then
            if er._adPage:IsMouseOver() and not er:IsMouseOver() and not OverFxCell(er._adTable) then
                er._adClose()
            end
            return
        end
    end
end
outside:SetScript("OnEvent", function(_, _, button) ET.ClickOutside(button) end)

local function WatchOutside()
    for _, er in ipairs(editorRows) do
        if er:IsVisible() then
            outside:RegisterEvent("GLOBAL_MOUSE_DOWN")
            return
        end
    end
    outside:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end

-- The editor under a state row: the open effect's blocks as compact lines
-- (a switch, the moment's name, its settings side by side; More for the
-- finer ones), its glyph and name with Done at the left, a notch up at the
-- cell. One is open at a time (ET.Open); the search reads every one.
local function EditorRow(pg, T, ctx, vis, kind, st, owner, stateRow)
    local row = AT.AddRow(pg, 60, function()
        if not vis() then return false end
        local r = ctx()
        if not (r and r.kind == kind) then return false end
        if not stateRow._visibleFn() then return false end
        if Indexing() then return #ET.FxFor(r, st) > 0 end
        return ET.Open(r) == st
    end)
    row._adFxEditor = st
    row._adStateKind = kind
    local frame, fill = TableEdges(row, false)
    local openFill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    openFill:SetTexture(AT.WHITE)
    openFill:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], 0.5)
    openFill:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    openFill:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    local ed = CreateFrame("Frame", nil, row, "BackdropTemplate")
    AT.Skin(ed, COL.well, COL.arcDeep)
    ed:SetPoint("TOPLEFT", 14, -6)
    ed:SetPoint("BOTTOMRIGHT", -12, 8)
    row._adEditor = ed
    -- the notch: an outlined diamond on the top edge, its lower half lost
    -- in the well
    local notchO = ed:CreateTexture(nil, "OVERLAY")
    notchO:SetTexture(AT.WHITE)
    notchO:SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1)
    notchO:SetSize(10, 10)
    notchO:SetRotation(math.rad(45))
    local notchI = ed:CreateTexture(nil, "OVERLAY", nil, 2)
    notchI:SetTexture(AT.WHITE)
    notchI:SetVertexColor(COL.well[1], COL.well[2], COL.well[3], 1)
    notchI:SetSize(10, 10)
    notchI:SetRotation(math.rad(45))
    row._adNotch = notchO
    -- the head: the effect's glyph and name, Done under them, a rule after
    local glyphs = {}
    for _, k in ipairs(ET.FX_ORDER) do
        local g = ET.Glyph(ed, k)
        g:SetPoint("TOPLEFT", 12, -9)
        g:Hide()
        glyphs[k] = g
    end
    local word = ed:CreateFontString(nil, "OVERLAY")
    word:SetFont(STANDARD_TEXT_FONT, 11, "")
    word:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    word:SetPoint("TOPLEFT", 32, -11)
    local function Close()
        AT.CloseDropdown()
        local r = ctx()
        if r then ET.SetOpen(r, nil) end
        AT.LayoutPage(pg)
    end
    local done = AT.MakeSmallButton(ed, "Done", 56)
    done:SetPoint("TOPLEFT", 12, -32)
    done:SetScript("OnClick", Close)
    Tip(done, "Done", "Closes this, back to the table.")
    row._adPage, row._adTable, row._adClose = pg, T, Close
    row._adIsOpen = function()
        local r = ctx()
        return r ~= nil and r.kind == kind and ET.Open(r) == st
    end
    editorRows[#editorRows + 1] = row
    row:HookScript("OnShow", WatchOutside)
    row:HookScript("OnHide", WatchOutside)
    local rule = ed:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(AT.WHITE)
    rule:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    local note = ed:CreateFontString(nil, "OVERLAY")
    note:SetFont(STANDARD_TEXT_FONT, 11, "")
    note:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    note:SetWordWrap(false)
    row._adNote = note
    local relay = function() AT.LayoutPage(pg) end
    local built = {}
    local function Line(def)
        local B = built[def]
        if not B then
            B = BlockLine(ed, def, ctx, owner, relay)
            built[def] = B
        end
        return B
    end
    row._adFxLines = built

    -- the open effect's blocks, then its shared rows (the sound channel)
    local function Blocks(r, fxKind, keys)
        local out = {}
        for _, key in ipairs(keys or {}) do
            local def = KeyDef(r, key)
            if def then out[#out + 1] = def end
        end
        for _, def in ipairs(ET.FX_KIND_BLOCKS[fxKind] or {}) do
            if ET.blockShows and ET.blockShows(r, def) then out[#out + 1] = def end
        end
        return out
    end
    row._adFxBlocks = Blocks

    row._sync = function()
        local r = ctx()
        if not (r and T.c1) then return end
        local open = ET.Open(r) == st
        frame(T.full or T.w)
        fill:SetWidth(math.max(1, (T.full or T.w) - 4))
        openFill:SetShown(open)
        if not open then return end
        local _, fxKind, keys = ET.Open(r)
        local defs = Blocks(r, fxKind, keys)
        for _, B in pairs(built) do B:Hide() end
        for k, g in pairs(glyphs) do g:SetShown(k == fxKind) end
        local g = glyphs[fxKind]
        if g then g:SetColor(COL.arc) end
        word:SetText(string.upper(ET.FX_WORD[fxKind] or ""))
        -- the notch over the open cell
        local cx = (T.fxX and T.fxX[fxKind] or T.c1) + 22 - 14
        notchO:ClearAllPoints()
        notchO:SetPoint("CENTER", ed, "TOPLEFT", cx, 0)
        notchI:ClearAllPoints()
        notchI:SetPoint("CENTER", ed, "TOPLEFT", cx, -1.4)
        -- the blocks start under the Opacity column; the rule before them
        local edW = math.max(200, (T.full or T.w) - 26)
        local x0 = math.max(T.c1 - 14, 140)
        local right = edW - 12
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", ed, "TOPLEFT", x0 - 12, -6)
        rule:SetPoint("BOTTOMLEFT", ed, "BOTTOMLEFT", x0 - 12, 6)
        rule:SetWidth(AT.Hairline(ed))
        -- the names' column: as wide as the widest name shown
        local nameW, anyCheck = 0, false
        for _, def in ipairs(defs) do
            local B = Line(def)
            if B.name then nameW = math.max(nameW, Measure(B.name)) end
            if B.check then anyCheck = true end
        end
        local y = -8
        local MS = Options.MultiSelect
        for _, def in ipairs(defs) do
            local B = Line(def)
            local on = (not B.check) or Store.Resolve(r, def.section, def.fields[1]) == true
            local yc = y - LINE_H / 2
            local x = x0
            if B.check then
                B.check:ClearAllPoints()
                B.check:SetPoint("LEFT", ed, "TOPLEFT", x, yc)
                B.check:SetOn(on)
                B.check:Show()
            end
            if anyCheck then x = x + 24 end
            if B.name then
                B.name:ClearAllPoints()
                B.name:SetPoint("LEFT", ed, "TOPLEFT", x, yc)
                B.name:Show()
                x = x + nameW + 16
            end
            local px0 = x
            local function Flow(P)
                local w = P.width()
                if x + w > right and x > px0 then
                    y = y - LINE_H
                    yc = y - LINE_H / 2
                    x = px0
                end
                -- still too wide on a line of its own: never past the edge
                if x + w > right and P.fit then w = P.fit(right - x) end
                P.place(x, yc)
                x = x + w + PAIR_GAP
            end
            -- "(mixed)" after a label while several records disagree
            local editing = MS ~= nil and MS.editing and r._adMulti == true
            local function Mark(P)
                if editing then MS.SetMark(P, P.label, MS.Mixed(r, def.section, P.field) == true)
                elseif MS and P._adPlainLabel then MS.SetMark(P, P.label, false) end
            end
            if B.name and B.check then
                if editing then MS.SetMark(B, B.name, MS.Mixed(r, def.section, def.fields[1]) == true)
                elseif MS and B._adPlainLabel then MS.SetMark(B, B.name, false) end
            end
            for _, P in ipairs(B.pairs) do
                local shows = PairShows(r, def, P.fdef)
                P.show(shows)
                if shows then
                    P.sync()
                    P.dim(not on)
                    Mark(P)
                    Flow(P)
                end
            end
            -- More, then its settings while it is open
            local advShown = {}
            for _, P in ipairs(B.adv) do
                if PairShows(r, def, P.fdef) then advShown[#advShown + 1] = P else P.show(false) end
            end
            local showAll = ET.ShowAll()
            local foldOpen = showAll or (B.foldKey and ET.FoldState()[B.foldKey] == true)
            if B.more then
                B.more:SetShown(#advShown > 0 and not showAll)
                if #advShown > 0 and not showAll then
                    B.paintMore()
                    local w = B.more:GetWidth()
                    if x + w > right and x > px0 then
                        y = y - LINE_H
                        yc = y - LINE_H / 2
                        x = px0
                    end
                    B.more:ClearAllPoints()
                    B.more:SetPoint("LEFT", ed, "TOPLEFT", x, yc)
                    x = x + w + PAIR_GAP
                end
            end
            for _, P in ipairs(advShown) do
                P.show(foldOpen)
                if foldOpen then
                    P.sync()
                    P.dim(not on)
                    Mark(P)
                    Flow(P)
                end
            end
            y = y - LINE_H - BLOCK_GAP
        end
        -- a line under the blocks (the game plays an aura's sounds itself)
        local text
        for _, def in ipairs(defs) do
            if def.note then text = text or def.note(r) end
        end
        note:SetShown(text ~= nil)
        if text then
            note:ClearAllPoints()
            note:SetPoint("TOPLEFT", ed, "TOPLEFT", x0, y + BLOCK_GAP - 2)
            note:SetText(text)
            y = y - 16
        end
        -- the lines, or the head (its glyph, name and Done) when taller
        local h = math.max(-y - BLOCK_GAP + 10, 62)
        local want = math.floor(h + 14 + 0.5)
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
        end
    end

    -- the search: every setting the state's effects hold on the sample, and
    -- the jump opens the editor (and its More) before the flash
    row._adSearch = function()
        local out = {}
        local r = ctx()
        if not r then return out end
        for _, f in ipairs(ET.FxFor(r, st)) do
            for _, def in ipairs(Blocks(r, f.kind, f.keys)) do
                for _, field in ipairs(def.fields) do
                    local fdef = Schema.icon[def.section].fields[field]
                    if fdef and Options.FieldShows(r, "icon", def.section, fdef) then
                        out[#out + 1] = fdef.label or field
                    end
                end
            end
        end
        return out
    end
    -- a hit's note when a switch or a choice hides the setting (rec: a
    -- record the hit was found on)
    row._adDepNoteFor = function(label, rec)
        local r = rec or ctx()
        local S = Options.Search
        if not (r and S and S.DepNote) then return nil end
        for _, f in ipairs(ET.FxFor(r, st)) do
            for _, def in ipairs(Blocks(r, f.kind, f.keys)) do
                for _, field in ipairs(def.fields) do
                    local fdef = Schema.icon[def.section].fields[field]
                    if fdef and (fdef.label or field) == label then
                        return S.DepNote({ _adMeta = { family = "icon", section = def.section, def = fdef } })
                    end
                end
            end
        end
    end
    row._adRevealFor = function(label)
        local r = ctx()
        if not r then return end
        for _, f in ipairs(ET.FxFor(r, st)) do
            for _, def in ipairs(Blocks(r, f.kind, f.keys)) do
                for _, field in ipairs(def.fields) do
                    local fdef = Schema.icon[def.section].fields[field]
                    if fdef and (fdef.label or field) == label then
                        ET.SetOpen(r, st.key, f.kind)
                        if fdef.adv then ET.FoldState()["fx." .. def.section .. "." .. def.fields[1]] = true end
                        return
                    end
                end
            end
        end
    end
    return row
end

-- One state row: its words (and the look it copies, on Recharging), one cell
-- per column, then a cell per effect it has: lit in the effect's colour while
-- one is on, a plus while none is. A click on an effect cell opens it under
-- the row; another click closes it.
local function StateRow(pg, T, ctx, vis, kind, st, owner)
    local lbl
    -- a row with a base pick carries it on a second line under its words
    local tall = st.base ~= nil
    local row = AT.AddRow(pg, tall and 52 or 34, function()
        if not vis() then return false end
        local r = ctx()
        if not (r and r.kind == kind) then return false end
        -- an icon's own words for the state (st.labelFn)
        if st.labelFn and lbl then lbl:SetText(st.labelFn(r) or st.label) end
        return RowShows(st, r)
    end)
    row._adStateRow = st
    row._adStateKind = kind
    local frame, fill = TableEdges(row, false)
    -- the open row: a raised fill, and its words in the accent
    local openFill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    openFill:SetTexture(AT.WHITE)
    openFill:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], 0.5)
    openFill:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    openFill:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    openFill:Hide()
    row._adPickFill = openFill
    lbl = row:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(STANDARD_TEXT_FONT, 13, "")
    if tall then lbl:SetPoint("TOPLEFT", 14, -11) else lbl:SetPoint("LEFT", 14, 0) end
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    lbl:SetText(st.label)
    row._adLabel = lbl
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

    -- the look it copies until it has its own (Recharging: Depleted, or
    -- Ready with Wait for no charges), one pick for the two
    if tall then
        local section, field = st.base[1], st.base[2]
        local bdef = Def(section, field)
        local dd = AT.MakeDropdown(owner or pg, row, nil,
            function()
                return { { value = false, text = "Like Depleted" }, { value = true, text = "Like Ready" } }
            end,
            function() return Get(section, field) == true end,
            function(v) Put(section, field, v == true) end,
            function() Relay() end)
        dd:SetPoint("TOPLEFT", 12, -27)
        Tip(dd, (bdef and bdef.label) or field,
            "Until it has looks of its own: like Depleted (dim from the first charge spent) or like Ready (until the last one).")
        row._adBase = dd
    end

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
                local sw = AT.MakeSwatch(cell, 30, 14)
                sw:SetPoint("LEFT", x, 0)
                -- no opacity slider: a tint's alpha belongs to the state opacity
                PickColor(sw, function() return Get(section, field) or (def and def.d) or { 1, 1, 1, 1 } end,
                    function(v) Put(section, field, v) end, false, nil, Relay)
                Tip(sw, lab, (def and def.desc) or ("The color " .. stateWord .. "."))
                C.swatch = sw
            end
        end
    end

    -- the effect cells, one per effect column
    local fxCells = {}
    for _, fk in ipairs(ET.FX_ORDER) do
        local b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(32, 24)
        AT.Skin(b, COL.box, COL.line)
        local lit = ET.Glyph(b, fk)
        lit:SetPoint("CENTER", 0, 0)
        local add = ET.Glyph(b, "add")
        add:SetPoint("CENTER", 0, 0)
        b._adLit, b._adAdd = lit, add
        -- lit, open or under the mouse: the fill and the edge
        function b:_adPaint()
            local on, isOpen = self._adOn, self._adIsOpen
            local fillC = isOpen and COL.btn or (on and COL.panel or COL.box)
            local edge = (isOpen or self._hot) and COL.arc or (on and COL.line2 or COL.line)
            self:SetBackdropColor(fillC[1], fillC[2], fillC[3], 1)
            self:SetBackdropBorderColor(edge[1], edge[2], edge[3], (on or isOpen or self._hot) and 1 or 0.6)
        end
        b:SetScript("OnClick", function()
            local r = Rec()
            if not r then return end
            AT.CloseDropdown()
            -- it only opens or shuts: nothing switches on until its switch does
            local ost, okind = ET.Open(r)
            if ost == st and okind == fk then
                ET.SetOpen(r, nil)
            else
                ET.SetOpen(r, st.key, fk)
            end
            Relay()
        end)
        b:HookScript("OnEnter", function() b._hot = true b:_adPaint() end)
        b:HookScript("OnLeave", function() b._hot = nil b:_adPaint() end)
        Tip(b, function() return ET.StateWord(Rec(), st) .. ": " .. ET.FX_WORD[fk] end, function()
            local r = Rec()
            if not r then return nil end
            local parts = {}
            for _, f in ipairs(ET.FxFor(r, st)) do
                if f.kind == fk then
                    for _, key in ipairs(f.keys) do
                        local def = KeyDef(r, key)
                        if def then parts[#parts + 1] = (def.title or key) .. (ET.FxLit(r, key) and ": on" or ": off") end
                    end
                end
            end
            if #parts == 0 then return nil end
            return table.concat(parts, ". ") .. ". Click to set it up here."
        end)
        b:Hide()
        fxCells[fk] = b
    end
    row._adFxCells = fxCells

    -- the cells, re-read and placed on the table's columns every pass
    row._sync = function()
        local r = Rec()
        if not (r and T.c1) then return end
        local ost, okind = ET.Open(r)
        local open = ost == st
        frame(T.full or T.w, open)
        openFill:SetShown(open)
        local ink = open and COL.arc or COL.ink
        lbl:SetTextColor(ink[1], ink[2], ink[3])
        local xs = { alpha = T.c1, grey = T.c2, tint = T.c3 }
        local ws = { alpha = T.w1, grey = T.w2, tint = T.w3 }
        -- effects
        for _, fk in ipairs(ET.FX_ORDER) do fxCells[fk]:Hide() end
        for _, f in ipairs(ET.FxFor(r, st)) do
            local b = fxCells[f.kind]
            local x = T.fxX and T.fxX[f.kind]
            if x then
                local on = false
                for _, key in ipairs(f.keys) do
                    if ET.FxLit(r, key) then on = true end
                end
                b._adOn, b._adIsOpen = on, open and okind == f.kind
                b:_adPaint()
                b._adLit:SetShown(on)
                b._adAdd:SetShown(not on)
                if on then b._adLit:SetColor(FxColor(r, f.kind, f.keys)) end
                b._adAdd:SetColor(COL.line2)
                b:ClearAllPoints()
                if tall then b:SetPoint("TOPLEFT", x + 6, -5) else b:SetPoint("LEFT", x + 6, 0) end
                b:Show()
            end
        end
        for _, c in ipairs(COLS) do
            local C = row._adCells[c]
            C.frame:ClearAllPoints()
            if tall then C.frame:SetPoint("TOPLEFT", xs[c], -5) else C.frame:SetPoint("LEFT", xs[c], 0) end
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
        if row._adBase then
            row._adBase:SetShown(Applies(r, st.base[1], st.base[2]))
            row._adBase.Refresh()
        end
    end

    -- every cell's option, for the search (the base pick's too)
    row._adSearch = function()
        local out = {}
        local r = Rec()
        if not r then return out end
        local specs = {}
        for _, c in ipairs(COLS) do
            if st[c] then specs[#specs + 1] = st[c] end
        end
        if st.base then specs[#specs + 1] = st.base end
        for _, spec in ipairs(specs) do
            for _, f in ipairs({ spec.on or false, spec[2] }) do
                if f and Applies(r, spec[1], f) then
                    local def = Def(spec[1], f)
                    out[#out + 1] = (def and def.label) or f
                end
            end
        end
        return out
    end
    T.rows[#T.rows + 1] = row
    return row
end

-- The table: a header row, then one row per state of the record's kind, each
-- with its editor row under it. It joins the section open on pg and spans
-- its width; vis gates the whole table. owner: the window a dropdown opens over.
function ET.StateTable(pg, ctx, vis, owner)
    local T = { rows = {}, editors = {} }
    local head = AT.AddRow(pg, 36, function()
        return vis() and ET.StatesFor(ctx()) ~= nil
    end)
    head._adStateHead = T
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
    -- an effect column's head: its glyph over its word
    local fxHeads = {}
    for _, fk in ipairs(ET.FX_ORDER) do
        local g = ET.Glyph(head, fk)
        g:SetColor(COL.faint)
        local fs = head:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 10, "")
        fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        fs:SetWordWrap(false)
        fs:SetText(string.upper(ET.FX_WORD[fk]))
        fxHeads[fk] = { glyph = g, fs = fs }
    end
    T.heads, T.fxHeads = heads, fxHeads
    -- The columns, measured from the rows the record shows: the header runs
    -- first in its section, so every row after it reads these. An effect
    -- column shows while a row has that effect.
    head._sync = function()
        local r = ctx()
        local lw = Measure(heads[1])
        local hasOn = false
        local has = {}
        for _, row in ipairs(T.rows) do
            if row._visibleFn() then
                lw = math.max(lw, Measure(row._adLabel))
                -- a base pick sits under the words, two to the left of them
                if row._adBase then lw = math.max(lw, (row._adBase:GetWidth() or 0) - 2) end
                local a = row._adStateRow.alpha
                if a and a.on then hasOn = true end
                if r then
                    for _, f in ipairs(ET.FxFor(r, row._adStateRow)) do has[f.kind] = true end
                end
            end
        end
        if not r then return end
        local w1 = math.max((hasOn and 24 or 0) + SLIDER_W + 6 + VALUE_W, Measure(heads[2]))
        local w2 = math.max(18, Measure(heads[3]))
        local w3 = math.max(24 + 30, Measure(heads[4]))
        T.c1 = 14 + lw + 18
        T.c2 = T.c1 + w1 + 18
        T.c3 = T.c2 + w2 + 18
        T.w1, T.w2, T.w3 = w1, w2, w3
        local x = T.c3 + w3 + 12
        T.fxX, T.hasFx = {}, false
        for _, fk in ipairs(ET.FX_ORDER) do
            local H = fxHeads[fk]
            if has[fk] then
                T.fxX[fk] = x
                T.hasFx = true
                H.glyph:ClearAllPoints()
                H.glyph:SetPoint("CENTER", head, "TOPLEFT", x + 22, -11)
                H.fs:ClearAllPoints()
                H.fs:SetPoint("BOTTOM", head, "BOTTOMLEFT", x + 22, 6)
                H.glyph:Show()
                H.fs:Show()
                x = x + 44
            else
                H.glyph:Hide()
                H.fs:Hide()
            end
        end
        T.w = x + 12
        -- the box spans the section (the next pass, once the width is known)
        local rw = head:GetWidth() or 0
        if rw <= 60 then pg._sizeUnresolved = true end
        T.full = math.max(T.w, rw - 2)
        local hx = { 14, T.c1, T.c2, T.c3 }
        for i = 1, 4 do
            heads[i]:ClearAllPoints()
            heads[i]:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", hx[i], 6)
        end
        frame(T.full)
    end
    T.head = head
    for _, kind in ipairs(Schema.ICON_KINDS) do
        for _, st in ipairs(ET.STATES[kind] or {}) do
            Options.BuildYield()
            local srow = StateRow(pg, T, ctx, vis, kind, st, owner)
            T.editors[#T.editors + 1] = EditorRow(pg, T, ctx, vis, kind, st, owner, srow)
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
local ICON_STATE_SUB = { Proc = { "Conditions", "By State" }, Warning = { "Conditions", "By State" },
    Pulse = { "Appearance", "Icon" }, ["Aura Swipe"] = { "Appearance", "Swipe" } }
-- the tabs Conditions took in: Show & Hide keeps its sub-tab, the glows and
-- sounds are under the states
local ICON_TO_CONDITIONS = { ["Show & Hide"] = true, Glows = "By State", Sounds = "By State", Alerts = "By State" }
local ICON_SUB = {
    Appearance = { Size = { "Appearance", "Icon" }, Look = { "Appearance", "Icon" },
        Visibility = { "Conditions", "Fade When" } },
    Position = { Mouse = { "Position", "Position" } },
    Text = { ["Duration Text"] = { "Text", "Duration" }, ["Stack & Charges"] = { "Text", "Stacks" },
        ["Ammo Stack Text"] = { "Text", "Stacks" }, Keybind = { "Text", "Custom Text & Keybind" },
        ["Label 1"] = { "Text", "Custom Text & Keybind" }, ["Label 2"] = { "Text", "Custom Text & Keybind" },
        ["Label 3"] = { "Text", "Custom Text & Keybind" },
        ["Labels & Keybind"] = { "Text", "Custom Text & Keybind" } },
}
-- a bar tab that went away: its rows' new tab and sub-tab
ET.BAR_TAB_HOME = { Thresholds = { "Appearance", "Fill & Colors" }, ["Color Changes"] = { "Appearance", "Fill & Colors" },
    Behavior = { "Show & Hide", "By State" } }
local BAR_SUB = {
    Appearance = { Style = "Size & Frame", ["Bar Size"] = "Size & Frame", Scale = "Size & Frame",
        Background = "Size & Frame", Border = "Size & Frame", Fill = "Fill & Colors",
        Direction = "Fill & Colors", ["Point Colors"] = "Fill & Colors", Segments = "Fill & Colors",
        ["Cost Preview"] = "Fill & Colors", ["Off-hand"] = "Swing",
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
            return "Conditions", "By State"
        end
        if tab == "Swipe" then return "Appearance", "Swipe" end
        local c = ICON_TO_CONDITIONS[tab]
        if c then return "Conditions", (c == true) and sub or c end
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

-- New tabs and sub-tabs (the regroup's, an aura group's Tracking), marked new
-- for one version (Options.NewBadge), by strip.
ET.BADGES = {
    icon = { Conditions = "tab:conditions" },
    iconSub = { ["Custom Text & Keybind"] = "sub:labelskeybind" },
    bar = { ["Show & Hide"] = "bar:showhide" },
    barSub = { ["Size & Frame"] = "sub:sizeframe", ["Fill & Colors"] = "sub:fillcolors" },
    group = { Appearance = "grp:appearance", Tracking = "grp:tracking" },
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
