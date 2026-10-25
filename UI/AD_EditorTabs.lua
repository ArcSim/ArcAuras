-- AD_EditorTabs: the editors' tabs by effect: the state table and its Effects box, the More options folds, the glow and sound cards, and the new home of a tab pick made before the regroup.
-- AD_Options builds the editors and calls in behind nil checks; every cell reads Store.Resolve and writes Store.SetOverride, as SectionRows does.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store, Schema = NS.AT, NS.Store, NS.Schema
local COL = AT.COL
local Tr = AT.Tr

local ET = {}
Options.EditorTabs = ET

-- Capitals only for plain Latin words: string.upper would split a multibyte
-- letter, and other scripts have no capitals.
local function Upper(s)
    if type(s) ~= "string" or s:find("[\128-\255]") then return s end
    return s:upper()
end
ET.Upper = Upper

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

-- The Effects tab's folds (Fine tune, More) open for this session only: they
-- start shut after every /reload, whatever an older More left saved open.
local sessionFolds = {}
function ET.SessionFolds() return sessionFolds end

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

-- Each fold's whole title, so a translation never fits a loose word into a
-- sentence; a word not listed here reads "More <word> options".
ET.FOLD_TITLES = { fade = "More fade options", frame = "More frame options", glow = "More glow options",
    inset = "More inset options", text = "More text options", usability = "More usability options" }

-- A fold row, "More <word> options" and a count, in the section open on pg.
-- The rows the caller adds after it show while it is open. A plain fold: it
-- opens and shuts on a click (the search opens it for a hit), and a changed
-- value inside only shows in its tooltip.
function ET.NewFold(pg, key, word, ctx)
    local f = setmetatable({ key = key, ctx = ctx, items = {}, pg = pg }, Fold)
    local title, shown = "More options", nil
    if type(word) == "string" and word ~= "" then
        title = ET.FOLD_TITLES[word] or ("More %s options"):format(word)
        -- a word with no title of its own: the sentence and the word translate apart
        if not ET.FOLD_TITLES[word] then shown = Tr("More %s options"):format(Tr(word)) end
    end
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
    fs:SetFont(AT.FONT, 12, "")
    fs:SetPoint("LEFT", chev, "RIGHT", 4, 0)
    fs:SetWordWrap(false)
    fs:SetText(shown or Tr(title))
    local nb = CreateFrame("Frame", nil, row, "BackdropTemplate")
    nb:SetHeight(16)
    nb:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    AT.Skin(nb, COL.panel, COL.line2)
    local nfs = nb:CreateFontString(nil, "OVERLAY")
    nfs:SetFont(AT.FONT, 10, "")
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
local GLOW_WORDS = { Type = "Style", Native = "Game's own color", Color = "Color", CombatOnly = "Only in combat",
    For = "Glow for", When = "Glow when", TimeUnit = "Time left in", TimePct = "Under this % left",
    TimeSec = "Under this many seconds left", AuraLength = "The aura lasts (seconds)",
    Speed = "Speed", Lines = "Lines", Thickness = "Thickness", Length = "Line length (0 = auto)",
    Backing = "Dark backing line", Particles = "Particles", Intensity = "Intensity", Scale = "Size",
    FadeOut = "Fade out (seconds)", XOffset = "X offset", YOffset = "Y offset", MoveX = "Move X", MoveY = "Move Y", Strata = "Strata",
    Level = "Frame level" }
-- switch, when it fires, look, gates, then the tuning (the tuning folds away)
local GLOW_ORDER = { "When", "TimeUnit", "TimePct", "TimeSec", "AuraLength", "Type", "Native", "Color",
    "CombatOnly", "For", "Speed", "Lines", "Thickness", "Length", "Backing", "Particles", "Intensity", "Scale",
    "FadeOut", "XOffset", "YOffset", "MoveX", "MoveY", "Strata", "Level" }

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
        return ET.OverlayWords(rec, "its aura is up", "its totem is down", "the set duration runs",
            "its totem is down or its aura is up")
    end,
    range = "the totem is out and its buff is not on you",
    outrange = "your target is out of range",
    recharge = "a charge is coming back",
    toggle = function(rec)
        local id = rec.driver and tonumber(rec.driver.spellID)
        local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
        if name then return Tr("%s is on"):format(name) end
        return "it is on"
    end,
    warn = function(rec) return WARN_WORDS[Store.Resolve(rec, "states", "warnGlowWhen")] or "" end,
    assist = "the game's Assisted Highlight suggests it next",
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
-- A spell icon's overlay rows in its source's words: an aura, its totem, its
-- totem else the aura (both) or a set duration (Drivers\AD_DriverPhase.lua).
function ET.OverlayWords(rec, aura, totem, cast, both)
    local ov = rec and rec.driver and rec.driver.overlay
    local src = NS.DriverAura and NS.DriverAura.OverlaySource and NS.DriverAura.OverlaySource(ov)
    if src == "totem" then return totem end
    if src == "cast" then return cast end
    if both and type(ov) == "table" and ov.totem == true then return both end
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
local UNUSABLE = { key = "unusable", label = "Can't use it", when = "while it can't be used", alpha = { S, "unusableAlpha" },
    grey = { S, "unusableDesaturate" }, tint = { S, "unusableTintColor", on = "unusableTintEnabled" },
    alphaTip = "Never brighter than Ready's opacity." }
-- What shows over the cooldown ("On this icon": an aura, a totem, a set
-- duration), on a spell, item or trinket icon: its two rows while it is on.
local OVERLAY = { key = "overlay", label = "Aura active", when = "while its aura is up", overlay = true,
    alpha = { A, "activeAlpha" },
    grey = { A, "activeDesaturate" }, tint = { A, "activeTintColor", on = "activeTintEnabled" },
    labelFn = function(r) return ET.OverlayWords(r, "Aura active", "Totem down", "Duration running", "Totem or aura up") end,
    fx = { glow = { "auraActive.activeGlow" }, art = { "art.active" } } }
local OVERLAY_MISSING = { key = "overlayMissing", label = "Aura missing", when = "while its aura is down", overlay = true,
    grey = { A, "overlayDesatInactive" },
    labelFn = function(r) return ET.OverlayWords(r, "Aura missing", "Totem gone", "Duration over", "Totem and aura gone") end }
-- A Custom Icon showing an aura (Tracking's "Aura on this icon"): the same
-- look as a spell's, named Aura up, with the sound the game plays as it appears.
local TIMER_AURA = {}
for k, v in pairs(OVERLAY) do TIMER_AURA[k] = v end
TIMER_AURA.labelFn = nil
TIMER_AURA.label = "Aura up"
TIMER_AURA.fx = { glow = { "auraActive.activeGlow" }, sound = { "alerts.auraGainSoundEnabled" }, art = { "art.active" } }
-- A Custom Icon with an aura or a cooldown on it, and one with a cooldown.
function ET.CustomPhased(r)
    return Options.CustomPhased ~= nil and Options.CustomPhased(r) == true
end
function ET.CustomCd(r)
    return r ~= nil and r.kind == "timer" and type(r.driver) == "table" and r.driver.cdOn == true
end
local OUT_OF_STOCK = { key = "out", label = "Out of stock", when = "while none is left", alpha = { O, "outAlpha", on = "outAlphaEnabled" },
    grey = { O, "outDesaturate" }, tint = { O, "outTintColor", on = "outTintEnabled" },
    onTip = "On: this opacity while none is left. Off: it keeps its opacity." }
-- ammo running low or the pet in trouble (Drivers\AD_DriverWarn.lua), for
-- the classes with ammo or a pet: a glow, named for what it warns of
local WARN_LABEL = { ammo = "Ammo low", petHealth = "Pet health low", petMood = "Pet not happy" }
local WARNING = { key = "warn", label = "Warning", when = "while the warning is on",
    labelFn = function(r) return WARN_LABEL[Store.Resolve(r, S, "warnGlowWhen")] or "Warning" end,
    showIf = function(r) return FieldOn(r, S, "warnGlow") end,
    fx = { glow = { "states.warnGlow" } } }
local function GBNobody(r) return r ~= nil and Store.Resolve(r, "groupBuff", "remind") == "nobody" end
-- A charge spell's cooldown state is every charge spent: No charges, listed
-- after Recharging (Ready, Recharging, No charges).
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
SPELL_COOLDOWN.labelFn = function(r) return ET.IsCharge(r) and "No charges" or "On cooldown" end
-- `timed`: the clock after a state's opacity, when that opacity starts
-- (ET.TimePop). `on` switches it, `sec` the seconds, `before` the opacity
-- until then; an aura also takes a share (`unit`, `pct`) and its length
-- (`len`), as its gate runs on a share of the time. `ownLook`: Options files
-- its look block itself.
SPELL_COOLDOWN.timed = { S, fields = { "cooldownAlphaTimed", "cooldownAlphaSec", "cooldownAlphaBefore" },
    on = "cooldownAlphaTimed", sec = "cooldownAlphaSec", before = "cooldownAlphaBefore",
    whole = "the whole cooldown", left = "seconds left on the cooldown",
    ok = function() return C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil end }
-- One entry per state a kind has, in order: its key (the Effects box's pick),
-- its words, then the field each column drives as { section, field }. A tint's
-- switch is `on`; an opacity with `on` has a switch before its slider. A
-- missing column is a dash (`never`: words). `fx`: its effect blocks by effect, keys or a function(rec) giving
-- them. `base`: the switch picking whose look it copies, under its words.
ET.STATES = {
    spell = {
        READY,
        -- a charge spell with a charge left and another on its way: a state
        -- with its own look, as Ready and No charges have
        { key = "recharge", label = "Recharging", when = "while a charge comes back",
          alpha = { S, "rechargeAlpha" },
          grey = { S, "rechargeDesaturate" }, tint = { S, "rechargeTintColor", on = "rechargeTintEnabled" },
          showIf = ET.IsCharge,
          fx = { glow = { "states.rechargeGlow" },
              sound = { "alerts.rechargeSoundEnabled", "alerts.chargeGainedSoundEnabled" } } },
        SPELL_COOLDOWN,
        UNUSABLE,
        { key = "nomana", label = "Not enough resource", when = "while you lack the resource for it",
          alpha = { S, "resourceAlpha" },
          grey = { S, "resourceDesaturate" }, tint = { S, "resourceTintColor", on = "resourceTintEnabled" },
          alphaTip = "Never brighter than Ready's opacity." },
        { key = "range", label = "Out of range", when = "while your target is out of range", alpha = { S, "rangeAlpha" },
          grey = { S, "rangeDesaturate" }, tint = { S, "rangeTintColor", on = "rangeTint" },
          alphaTip = "Never brighter than Ready's opacity.",
          fx = { glow = { "states.rangeGlow" } } },
        -- Shoot, Auto Shot or Attack on, a pet spell on autocast (Drivers\AD_DriverToggle.lua)
        -- a next-swing ability's toggle is its queue: the row reads Queued
        -- and its icon effect is the action bar's checkmark
        { key = "toggle", label = "Toggled on", when = "while it is toggled on",
          alpha = { S, "toggleAlpha", on = "toggleAlphaEnabled" },
          onTip = "On: this opacity while toggled on. Off: it keeps its opacity.",
          grey = { S, "toggleDesaturate" }, tint = { S, "toggleTintColor", on = "toggleTintEnabled" },
          showIf = function(r) return NS.DriverToggle ~= nil and NS.DriverToggle.IsToggle(r) end,
          labelFn = function(r)
              local DT = NS.DriverToggle
              return (DT ~= nil and DT.Kind(r) == "queue") and "Queued" or "Toggled on"
          end,
          fx = { glow = { "states.toggleGlow" }, art = { "states.queueCheck", "states.queueShort" } } },
        -- the game lights it up: its glow here, its opacity rule under the table
        { key = "proc", label = "Proc lit", when = "while the game lights it up",
          fx = { glow = { "states.procGlow" } } },
        -- the game's Assisted Highlight picks it next (retail, Drivers\AD_DriverAssist.lua)
        { key = "assist", label = "Suggested", when = "while the game suggests it next",
          showIf = function() return NS.DriverAssist ~= nil and NS.DriverAssist.Available() end,
          fx = { glow = { "states.assistGlow" } } },
        WARNING,
        OVERLAY,
        OVERLAY_MISSING,
    },
    aura = {
        { key = "active", label = "Active", when = "while the aura is up", alpha = { A, "activeAlpha" },
          grey = { A, "activeDesaturate" }, tint = { A, "activeTintColor", on = "activeTintEnabled" },
          timed = { A, fields = { "activeTimeOnly", "activeTimeUnit", "activeTimeSec", "activeTimePct",
              "activeTimeLen", "activeTimeBefore" },
              on = "activeTimeOnly", sec = "activeTimeSec", before = "activeTimeBefore", unit = "activeTimeUnit",
              pct = "activeTimePct", len = "activeTimeLen", whole = "the whole time it is up",
              left = "seconds left on the aura", ownLook = true,
              ok = function(r)
                  if r == nil then return false end
                  if r._adDefaults then return true end
                  local DA = NS.DriverAura
                  return DA ~= nil and DA.TimeGateOK ~= nil and DA.TimeGateOK(r) == true
              end },
          fx = { glow = AuraGlowKeys(false), sound = { "alerts.auraGainSoundEnabled", "alerts.auraStackSoundEnabled" },
              art = { "art.active" } } },
        { key = "missing", label = "Missing", when = "while the aura is missing", alpha = { M, "missingAlpha" },
          grey = { M, "missingDesaturate" }, tint = { M, "missingTintColor", on = "missingTintEnabled" },
          fx = { glow = AuraGlowKeys(true), sound = { "alerts.auraLostSoundEnabled" }, art = { "art.missing" } } },
    },
    item = { READY, COOLDOWN, UNUSABLE, OUT_OF_STOCK, WARNING, OVERLAY, OVERLAY_MISSING },
    trinket = { READY, COOLDOWN, OUT_OF_STOCK, WARNING, OVERLAY, OVERLAY_MISSING },
    -- a Custom Icon: active per its Show as active while (the ready bucket),
    -- else not active (the cooldown bucket); both can grey out. With an aura
    -- or a cooldown on it the rows follow what it shows: Aura up, Timer
    -- running, On cooldown (the same cooldown bucket) and Ready (its own).
    timer = {
        TIMER_AURA,
        { key = "active", label = "Active", when = "while it is active", alpha = READY.alpha,
          grey = READY.grey, tint = READY.tint, alphaTip = READY.alphaTip,
          labelFn = function(r) return ET.CustomPhased(r) and "Timer running" or "Active" end,
          fx = { glow = { "states.readyGlow" }, sound = { "alerts.readySoundEnabled" } } },
        { key = "inactive", label = "Not active", when = "while it is not active", alpha = COOLDOWN.alpha,
          grey = COOLDOWN.grey, tint = COOLDOWN.tint,
          labelFn = function(r) return ET.CustomCd(r) and "On cooldown" or "Not active" end,
          fx = { glow = { "states.cooldownGlow" }, sound = { "alerts.cooldownSoundEnabled" } } },
        { key = "idle", label = "Ready", when = "while it is ready", showIf = function(r) return ET.CustomCd(r) end,
          alpha = { S, "idleAlpha" }, grey = { S, "idleDesaturate" }, tint = { S, "idleTintColor", on = "idleTintEnabled" },
          fx = { glow = { "states.idleGlow" }, sound = { "alerts.idleSoundEnabled" } } },
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
        -- a two-hander's off hand, a shield, bare hands
        { key = "noweapon", label = "No weapon", when = "while this hand holds no weapon",
          alpha = { S, "noWeaponAlpha" }, alphaTip = "0 hides it while the hand has no weapon to enchant." },
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
-- a cell's tooltip, one whole line per column around the state's words
local COL_TIP = { alpha = "%s: opacity", grey = "%s: grey out", tint = "%s: tint" }
local COL_NONE = { alpha = "%s has no opacity look.", grey = "%s has no grey out look.", tint = "%s has no tint look." }
local SLIDER_W = 96

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

-- A row that waits on something: the aura overlay, or its own gate. The
-- Defaults page (rec._adDefaults) sets every state's look a kind can have.
local function RowShows(st, rec)
    if rec and rec._adDefaults then return true end
    if st.overlay and not OverlayOn(rec) then return false end
    return not st.showIf or st.showIf(rec) == true
end
ET.RowShows = RowShows

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
        if st.timed then
            for _, f in ipairs(st.timed.fields) do add(st.timed[1], f) end
        end
    end
    return out
end

-- The layout's looks mirror the table as plain rows, one block per state,
-- each field once (a totem's Active is the spell's Ready), on the table's own
-- sub-tab; the Defaults page draws the table itself instead (b.state).
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
            -- when its opacity starts goes with the opacity
            if st.timed and not st.timed.ownLook then
                for _, f in ipairs(st.timed.fields) do specs[#specs + 1] = { st.timed[1], f } end
            end
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
                Options.LookBlock("icon", tabName, st.lookTitle or st.label, section, bySec[section], "By State",
                    { state = true })
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
-- a slider's Default button (fdef.resetTo): the quiet button grows to its words
ET.RESET_W = 56
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

ET.SetSwitch = SetSwitch

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

-- A slider of the theme's one build (AT.MakeSlider: track, [-][value][+]).
-- lo and hi may be functions, re-read on every refresh; pct shows a 0..1
-- value as a percent, fmtStr a raw format. Its width with the stepper is
-- w + AT.SLIDER_TRAIL.
local function CompactSlider(parent, w, lo, hi, step, pct, fmtStr, get, set)
    local s, refresh = AT.MakeSlider(parent, w, {
        lo = lo, hi = hi, step = step, get = get, set = set,
        fmt = function(v)
            if pct then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
            if fmtStr then return fmtStr:format(v) end
            if step >= 1 then return tostring(math.floor(v + 0.5)) end
            return (("%.2f"):format(v):gsub("%.?0+$", ""))
        end,
        parse = function(text)
            local n = tonumber((text:gsub("%%", "")))
            if not n then return nil end
            if pct then n = n / 100 end
            return math.floor(n / step + 0.5) * step
        end,
    })
    return s, s.box, refresh
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
    box:SetFont(AT.FONT, 11, "")
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    local function refresh()
        if box:HasFocus() then return end
        local v = tonumber(get())
        if isId then AT.BoxText(box, (v and v ~= 0) and tostring(v) or "")
        else AT.BoxText(box, v and tostring(v) or "") end
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

-- A few words, set on Enter or on leaving the box; an empty box clears them.
local function TextBox(parent, w, get, set, maxLen)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(w, 18)
    AT.Skin(box, COL.well)
    box:SetFont(AT.FONT, 11, "")
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetJustifyH("LEFT")
    box:SetTextInsets(4, 4, 0, 0)
    box:SetAutoFocus(false)
    if maxLen then box:SetMaxLetters(maxLen) end
    local function refresh()
        if box:HasFocus() then return end
        local v = get()
        AT.BoxText(box, type(v) == "string" and v or "")
    end
    local function commit(self)
        local v = tostring(self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        set(v)
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
    -- a funnel: a count state's rule (the Effects tab's When)
    when = { { 10.5, 1.4, 0, 4.4 }, { 6.1, 1.4, -3.1, 2, -51.6 }, { 6.1, 1.4, 3.1, 2, 51.6 }, { 2.2, 4.6, 0, -2.6 } },
    -- a dial split down the middle: the look (opacity, grey out, tint)
    look = { { 3.8, 1.2, 4.6, 0, 90 }, { 3.8, 1.2, 3.25, 3.25, 135 }, { 3.8, 1.2, 0, 4.6 },
        { 3.8, 1.2, -3.25, 3.25, 45 }, { 3.8, 1.2, -4.6, 0, 90 }, { 3.8, 1.2, -3.25, -3.25, 135 },
        { 3.8, 1.2, 0, -4.6 }, { 3.8, 1.2, 3.25, -3.25, 45 }, { 1.3, 8.6, 0, 0 } },
    -- a dial of eight chords and its two hands
    clock = { { 3.8, 1.2, 4.6, 0, 90 }, { 3.8, 1.2, 3.25, 3.25, 135 }, { 3.8, 1.2, 0, 4.6 },
        { 3.8, 1.2, -3.25, 3.25, 45 }, { 3.8, 1.2, -4.6, 0, 90 }, { 3.8, 1.2, -3.25, -3.25, 135 },
        { 3.8, 1.2, 0, -4.6 }, { 3.8, 1.2, 3.25, -3.25, 45 }, { 1.3, 3, 0, 1.4 }, { 2.4, 1.3, 0.95, -0.6, -32 } },
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
    lbl:SetFont(AT.FONT, 12, "")
    lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    lbl:SetWordWrap(false)
    lbl:SetText(Tr(words))
    P.label, P.words = lbl, words
    -- P.lw: a row's first label column, so its controls line up down the rows
    local function LW() return math.max(Measure(lbl) + 8, P.lw or 0) end
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
                local L = (fdef.labelsFn and rv ~= nil and fdef.labelsFn(rv)) or fdef.labels
                for _, v in ipairs(fdef.values or {}) do
                    local cond = fdef.valueIf and fdef.valueIf[v]
                    if not cond or (rv ~= nil and cond(rv)) then
                        out[#out + 1] = { value = v, text = (L and L[v]) or v }
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
                local other = LW() + 4 + play:GetWidth()
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
    elseif t == "text" then
        -- words to speak, with Speak to hear them once in the voice they use
        local box, refresh = TextBox(ed, ET.SOUND_W, Get, function(v) Put(v ~= "" and v or nil) end, 200)
        P.ctrl = box
        P.sync = refresh
        local say = AT.MakeSmallButton(ed, "Speak", 52)
        say:SetScript("OnClick", function()
            AT.CloseDropdown()
            local v, CU = Get(), NS.DriverCustom
            if type(v) == "string" and v ~= "" and CU and CU.Speak then CU.Speak(v) end
        end)
        Tip(say, "Speak", "Hear the words once.")
        P.extra = say
        P.fit = function(room)
            local other = LW() + 4 + say:GetWidth()
            box:SetWidth(math.max(80, math.floor(room - other)))
            return P.width()
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
        -- fdef.resetTo: a Default button after the box puts the value back
        -- (a glow's Speed: the game's own pace), shown while it differs
        local rb
        local function Differs()
            local v = tonumber(Get())
            return fdef.resetTo ~= nil and v ~= nil and math.abs(v - fdef.resetTo) > 1e-6
        end
        local function SyncReset()
            if rb then rb:SetShown(P.shownNow ~= false and Differs()) end
        end
        local s, _, refresh = CompactSlider(ed, 80, lo, hi, int and 1 or (fdef.step or 0.01), pct, fdef.fmt,
            function() return Get() or fdef.d or 0 end, function(v) Put(v) SyncReset() end)
        -- the stepper and box ride the slider: one control, AT.SLIDER_TRAIL wider
        P.ctrl, P.trail, P.after = s, AT.SLIDER_TRAIL, s.plus
        P.sync = function() refresh() SyncReset() end
        if fdef.resetTo ~= nil then
            rb = AT.MakeQuietButton(ed, "Default", ET.RESET_W)
            rb:SetScript("OnClick", function()
                AT.CloseDropdown()
                local r = ctx()
                if not r then return end
                -- its own value goes; where a layout or saved default holds
                -- another, the default itself is set
                Store.SetOverride(r, section, field, nil)
                if Differs() then Store.SetOverride(r, section, field, fdef.resetTo) end
                if fdef.onSet then fdef.onSet(r, Get()) end
                P.sync()
            end)
            Tip(rb, "Default", Tr("Back to the default speed: the game's own pace."))
            P.extra2 = rb
        end
    end
    if not P.ctrl then return nil end
    if fdef.desc then Tip(P.ctrl, fdef.label or words, fdef.desc) end
    P.labelSpan = LW
    P.width = function()
        local w = LW() + (P.ctrl:GetWidth() or 0) + (P.trail or 0)
        if P.extra then w = w + (P.extraGap or 4) + (P.extra:GetWidth() or 0) end
        -- the Default button's place is kept while it hides: the row never shifts
        if P.extra2 then w = w + 6 + (P.extra2:GetWidth() or 0) end
        return w
    end
    -- cx, cy: the control on a line of its own under the label (a narrow panel)
    P.place = function(x, y, cx, cy)
        lbl:ClearAllPoints()
        lbl:SetPoint("LEFT", ed, "TOPLEFT", x, y)
        P.ctrl:ClearAllPoints()
        P.ctrl:SetPoint("LEFT", ed, "TOPLEFT", cx or (x + LW()), cy or y)
        if P.extra then
            P.extra:ClearAllPoints()
            P.extra:SetPoint("LEFT", P.ctrl, "RIGHT", P.extraGap or 4, 0)
        end
        if P.extra2 then
            P.extra2:ClearAllPoints()
            P.extra2:SetPoint("LEFT", P.extra or P.after or P.ctrl, "RIGHT", 6, 0)
        end
    end
    P.show = function(on)
        lbl:SetShown(on)
        P.ctrl:SetShown(on)
        if P.extra then P.extra:SetShown(on) end
        P.shownNow = on
        if P.extra2 then P.sync() end
    end
    -- an off block's settings dim in place and take no clicks
    P.dim = function(off)
        local a = off and AT.CARD_DIM or 1
        lbl:SetAlpha(a)
        P.ctrl:SetAlpha(a)
        if P.trail then AT.SliderMouse(P.ctrl, not off) else P.ctrl:EnableMouse(not off) end
        if P.extra then
            P.extra:SetAlpha(a)
            P.extra:EnableMouse(not off)
        end
        if P.extra2 then
            P.extra2:SetAlpha(a)
            P.extra2:EnableMouse(not off)
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
            local w = (type(when) == "string" and when ~= "") and (Tr("When %s."):format(Tr(when)) .. " ") or ""
            return w .. Tr((sdef and sdef.desc) or "Off keeps its settings, greyed out.")
        end)
        B.check = cb
    end
    if blk.lineName ~= false then
        local nm = ed:CreateFontString(nil, "OVERLAY")
        -- blk.cap: a caption before the line's settings, not a name
        local c = blk.cap and COL.faint or COL.ink
        nm:SetFont(AT.FONT, blk.cap and 10 or 12, "")
        nm:SetTextColor(c[1], c[2], c[3])
        nm:SetWordWrap(false)
        nm:SetText(Tr(blk.lineName or blk.title or ""))
        B.name = nm
    end
    -- blk.flat: every setting on the line, none behind More
    for i = blk.isCard and 2 or 1, #blk.fields do
        local P = MakePair(ed, blk, blk.fields[i], ctx, owner, relay)
        if P then
            if P.adv and not blk.flat then B.adv[#B.adv + 1] = P else B.pairs[#B.pairs + 1] = P end
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
        fs:SetFont(AT.FONT, 12, "")
        fs:SetPoint("LEFT", chev, "RIGHT", 4, 0)
        fs:SetText(Tr(blk.foldWord or "More"))
        mb:SetWidth(16 + Measure(fs) + 2)
        -- blk.foldRow: the fold on a line of its own, what it holds in a few words while shut
        if blk.foldRow then
            local sum = ed:CreateFontString(nil, "OVERLAY")
            sum:SetFont(AT.FONT, 11, "")
            sum:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            sum:SetWordWrap(false)
            B.sum = sum
        end
        B.foldKey = "fx." .. blk.section .. "." .. blk.fields[1]
        -- blk.foldSession: open for this session only
        local function Folds() return blk.foldSession and sessionFolds or ET.FoldState() end
        B.folds = Folds
        local function Paint()
            local c = mb._hot and COL.ink or COL.dim
            fs:SetTextColor(c[1], c[2], c[3])
            chev:SetColor(mb._hot and COL.arc or COL.dim)
            chev:SetDown(Folds()[B.foldKey] == true)
        end
        mb:SetScript("OnClick", function()
            AT.CloseDropdown()
            local stt = Folds()
            local open = stt[B.foldKey] ~= true
            stt[B.foldKey] = open or nil
            PlaySound(open and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            relay()
        end)
        mb:SetScript("OnEnter", function() mb._hot = true Paint() end)
        mb:SetScript("OnLeave", function() mb._hot = nil Paint() end)
        Tip(mb, blk.foldWord or "More", "Fine-tuning for this one. Click to show or hide it.")
        B.more, B.paintMore = mb, Paint
        B.moreText = fs
    end
    B.caps = {}
    function B:Hide()
        if self.check then self.check:Hide() end
        if self.name then self.name:Hide() end
        for _, P in ipairs(self.pairs) do P.show(false) end
        for _, P in ipairs(self.adv) do P.show(false) end
        if self.more then self.more:Hide() end
        if self.sum then self.sum:Hide() end
        for _, c in pairs(self.caps) do c:Hide() end
    end
    return B
end
ET.BlockLine, ET.MakePair = BlockLine, MakePair

-- Lays effect lines in `ed` from x0, the first line's top at y (negative, from
-- ed's top), wrapping at `right`: each line's switch, name, settings, More and
-- its tuning, then the blocks' note when `note` is given. Line(def) finds or
-- builds a def's line. Returns the y under the last line.
-- opts.flat: a nameless line starts at x0 and a caption (def.cap) takes its own
-- width; opts.gap: the space between settings; opts.minRoom: the room a named
-- line needs after its name, else its settings start under it; opts.squeeze: a
-- setting too wide for a narrow panel drops the label column, then starts
-- under its line's name, then puts its control under its label, and a fold's
-- caption that leaves too little room sits on a line of its own. A def may also carry noCheck
-- (its switch hidden, the line on), breakBefore[field] (that setting starts a
-- line), labelW (each line's first label column), foldRow / foldSum (More on a
-- line of its own, its words while shut), advGroup(field) and advOrder (the
-- open fold's settings grouped under captions) or advRows (each on its own line).
function ET.LayLines(ed, r, defs, Line, x0, right, y, note, opts)
    local flat = opts ~= nil and opts.flat == true
    local squeeze = opts ~= nil and opts.squeeze == true
    local gap = (opts and opts.gap) or PAIR_GAP
    -- the names' column: as wide as the widest name shown
    local nameW, anyCheck = 0, false
    for _, def in ipairs(defs) do
        local B = Line(def)
        if B.name and not (flat and def.cap) then nameW = math.max(nameW, Measure(B.name)) end
        if B.check and not def.noCheck then anyCheck = true end
    end
    local MS = Options.MultiSelect
    for _, def in ipairs(defs) do
        local B = Line(def)
        local on = (not B.check) or def.noCheck == true or Store.Resolve(r, def.section, def.fields[1]) == true
        local yc = y - LINE_H / 2
        local x = x0
        local function NewLine(to)
            y = y - LINE_H
            yc = y - LINE_H / 2
            x = to
        end
        if B.check then
            if def.noCheck then
                B.check:Hide()
            else
                B.check:ClearAllPoints()
                B.check:SetPoint("LEFT", ed, "TOPLEFT", x, yc)
                B.check:SetOn(on)
                B.check:Show()
            end
        end
        if anyCheck then x = x + 24 end
        if B.name then
            B.name:ClearAllPoints()
            B.name:SetPoint("LEFT", ed, "TOPLEFT", x, yc)
            B.name:Show()
            if not flat then
                x = x + nameW + 16
            elseif def.cap then
                x = x + math.max(Measure(B.name) + 12, def.capW or 0)
            elseif Measure(B.name) > 0 then
                x = x + nameW + 16
            end
        end
        local px0 = x
        -- opts.minRoom: a name that leaves the panel too little room puts its
        -- settings on the line under it, never past the edge
        if flat and opts.minRoom and B.name and not def.cap and Measure(B.name) > 0 and right - x < opts.minRoom then
            NewLine(x0 + (anyCheck and 24 or 0))
            px0 = x
        end
        local home = x0 + (anyCheck and 24 or 0)
        local function Flow(P, lineX)
            -- a fold's settings keep to the fold's edge; the others may go under the name
            local floor = lineX or home
            lineX = lineX or px0
            if def.breakBefore and def.breakBefore[P.field] and x > lineX then NewLine(lineX) end
            P.lw = (x == lineX) and def.labelW or nil
            local w = P.width()
            if x + w > right and x > lineX then
                NewLine(lineX)
                P.lw = def.labelW
                w = P.width()
            end
            if squeeze and x + w > right and P.labelSpan then
                P.lw = nil
                w = P.width()
                if x + w > right and x > floor then
                    NewLine(floor)
                    w = P.width()
                end
                if x + w > right then
                    -- the control on the line under its label
                    local lx, ly, span = x, yc, P.labelSpan()
                    NewLine(x)
                    w = P.width() - span
                    -- under the switches' column too when it needs that
                    if x + w > right and x > x0 then x = x0 end
                    if x + w > right and P.fit then w = P.fit(right - x + span) - span end
                    P.place(lx, ly, x, yc)
                    P.stacked = true
                    x = x + w + gap
                    return
                end
            end
            P.stacked = nil
            -- still too wide on a line of its own: never past the edge
            if x + w > right and P.fit then w = P.fit(right - x) end
            P.place(x, yc)
            x = x + w + gap
        end
        -- "(mixed)" after a label while several records disagree
        local editing = MS ~= nil and MS.editing and r._adMulti == true
        local function Mark(P)
            if P.noMark then return end
            if editing then MS.SetMark(P, P.label, MS.Mixed(r, P.section or def.section, P.field) == true)
            elseif MS and P._adPlainLabel then MS.SetMark(P, P.label, false) end
        end
        -- a pair with its own show test (an own look's cells)
        local function Shows(P)
            if P.shows then return P.shows() == true end
            return PairShows(r, def, P.fdef)
        end
        if B.name and B.check and not def.noCheck then
            if editing then MS.SetMark(B, B.name, MS.Mixed(r, def.section, def.fields[1]) == true)
            elseif MS and B._adPlainLabel then MS.SetMark(B, B.name, false) end
        end
        for _, P in ipairs(B.pairs) do
            local shows = Shows(P)
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
            if Shows(P) then advShown[#advShown + 1] = P else P.show(false) end
        end
        local showAll = ET.ShowAll()
        local foldOpen = showAll or (B.foldKey and (B.folds and B.folds() or ET.FoldState())[B.foldKey] == true)
        if B.sum then B.sum:Hide() end
        if B.more then
            B.more:SetShown(#advShown > 0 and not showAll)
            if #advShown > 0 and not showAll then
                B.paintMore()
                local w = B.more:GetWidth()
                if def.foldRow then
                    if x > px0 then NewLine(px0) end
                elseif x + w > right and x > px0 then
                    NewLine(px0)
                end
                B.more:ClearAllPoints()
                B.more:SetPoint("LEFT", ed, "TOPLEFT", x, yc)
                x = x + w + gap
                if B.sum and not foldOpen then
                    B.sum:SetText(def.foldSum and (def.foldSum(r, advShown, def) or "") or "")
                    B.sum:ClearAllPoints()
                    B.sum:SetPoint("LEFT", B.more, "RIGHT", 6, 0)
                    B.sum:Show()
                end
            end
        end
        for _, c in pairs(B.caps or {}) do c:Hide() end
        -- flat: the open fold's rows hang under the line's switch, not after its name
        local indent = (flat and (x0 + (anyCheck and 24 or 0)) or px0) + (def.advIndent or 0)
        if foldOpen and (def.advGroup or def.advRows) and #advShown > 0 then
            -- grouped: a line per caption, its settings after it; rows: a line each
            local groups, order = {}, {}
            for _, P in ipairs(advShown) do
                local g = def.advGroup and def.advGroup(P.field) or P.field
                if not groups[g] then
                    groups[g] = {}
                    order[#order + 1] = g
                end
                table.insert(groups[g], P)
            end
            if def.advOrder then
                local rank = {}
                for i, g in ipairs(def.advOrder) do rank[g] = i end
                table.sort(order, function(a, b) return (rank[a] or 99) < (rank[b] or 99) end)
            end
            for _, g in ipairs(order) do
                NewLine(indent)
                local lineX = indent
                if def.advGroup then
                    local c = B.caps[g]
                    if not c then
                        c = ed:CreateFontString(nil, "OVERLAY")
                        c:SetFont(AT.FONT, 10, "")
                        c:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
                        c:SetWordWrap(false)
                        c:SetText(Tr(g))
                        B.caps[g] = c
                    end
                    c:ClearAllPoints()
                    c:SetPoint("LEFT", ed, "TOPLEFT", indent, yc)
                    c:Show()
                    lineX = indent + math.max(Measure(c) + 12, def.capW or 0)
                    x = lineX
                    -- a narrow panel: the caption on a line of its own, its
                    -- settings from the fold's edge under it
                    if squeeze then
                        local widest = 0
                        for _, P in ipairs(groups[g]) do
                            P.lw = def.labelW
                            widest = math.max(widest, P.width())
                        end
                        if lineX + widest > right then
                            NewLine(indent)
                            lineX = indent
                        end
                    end
                end
                for _, P in ipairs(groups[g]) do
                    P.show(true)
                    P.sync()
                    P.dim(not on)
                    Mark(P)
                    Flow(P, lineX)
                end
            end
        else
            for _, P in ipairs(advShown) do
                P.show(foldOpen)
                if foldOpen then
                    P.sync()
                    P.dim(not on)
                    Mark(P)
                    Flow(P)
                end
            end
        end
        y = y - LINE_H - BLOCK_GAP
    end
    -- a line under the blocks (the game plays an aura's sounds itself)
    if note then
        local text
        for _, def in ipairs(defs) do
            if def.note then text = text or def.note(r) end
        end
        note:SetShown(text ~= nil)
        if text then
            note:ClearAllPoints()
            note:SetPoint("TOPLEFT", ed, "TOPLEFT", x0, y + BLOCK_GAP - 2)
            note:SetText(Tr(text))
            y = y - 16
        end
    end
    return y
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
    word:SetFont(AT.FONT, 11, "")
    word:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
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
    note:SetFont(AT.FONT, 11, "")
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
        -- only the blocks leaving hide: a shown control hidden and shown again
        -- drops a drag in hand (a slider let go mid-drag on every write); the
        -- staying blocks show or hide each control below
        local staying = {}
        for _, def in ipairs(defs) do staying[def] = true end
        for def, B in pairs(built) do
            if not staying[def] then B:Hide() end
        end
        for k, g in pairs(glyphs) do g:SetShown(k == fxKind) end
        local g = glyphs[fxKind]
        if g then g:SetColor(COL.arc) end
        word:SetText(Upper(Tr(ET.FX_WORD[fxKind] or "")))
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
        local y = ET.LayLines(ed, r, defs, Line, x0, right, -8, note)
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
-- When a state's opacity starts: the clock after its opacity cell, and one
-- popover per table that sets it.

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- A round piece on `parent`'s own textures (a mask clips only its frame's).
local function Round(parent, size, sub)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, sub or 0)
    t:SetTexture(AT.WHITE)
    t:SetSize(size, size)
    t:SetPoint("CENTER", 0, 0)
    local m = parent:CreateMaskTexture()
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return t
end

-- A radio: a steel ring, lit under the mouse, the accent dot when picked.
local function Radio(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 14)
    local ring = Round(b, 14, 0)
    local hole = Round(b, 12, 1)
    hole:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    local dot = Round(b, 6, 2)
    dot:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    local function paint()
        local c = b._hot and COL.arc or COL.steel
        ring:SetVertexColor(c[1], c[2], c[3], 1)
    end
    function b:SetOn(on) dot:SetShown(on == true) end
    b:SetScript("OnEnter", function() b._hot = true paint() end)
    b:SetScript("OnLeave", function() b._hot = nil paint() end)
    b:SetScript("OnClick", onClick)
    paint()
    b:SetOn(false)
    return b
end

local function TimedGet(r, t, k) return r and k and Store.Resolve(r, t[1], k) end

-- What a timed opacity waits for, as its clock says it ("3s", "30%"), or nil.
function ET.TimedWord(r, st)
    local t = st and st.timed
    if not (t and r) or TimedGet(r, t, t.on) ~= true then return nil end
    if t.unit and TimedGet(r, t, t.unit) ~= "sec" then
        return ("%d%%"):format(math.floor((tonumber(TimedGet(r, t, t.pct)) or 30) + 0.5))
    end
    return ("%gs"):format(tonumber(TimedGet(r, t, t.sec)) or 3)
end

-- Set and working: an aura's seconds also need its length.
function ET.TimedLive(r, st)
    local t = st and st.timed
    if not ET.TimedWord(r, st) then return false end
    if t.unit and TimedGet(r, t, t.unit) == "sec" then
        return (tonumber(TimedGet(r, t, t.len)) or 0) > 0
    end
    return true
end

-- A Dynamic group can't move icons at that moment (it can't be read in
-- combat), so a spell there keeps its spot, or is gone the whole cooldown.
function ET.TimedGroupNote(r)
    if not (r and r.kind == "spell" and r.groupId) then return nil end
    local g = Store.Get(r.groupId)
    if not (g and Store.Resolve(g, "arrangement", "dynamicLayout") == true) then return nil end
    local c = Store.Resolve(g, "arrangement", "dynamicCollapse")
    if c == "hidden" then return "It keeps its spot in its Dynamic group." end
    if c == "cooldown" then return "Its Dynamic group hides it on cooldown." end
    return nil
end

-- True when an icon of the group has a timed opacity on.
function ET.GroupHasTimed(g)
    for _, r in ipairs(g and Store.IconsOf(g) or {}) do
        if r.kind == "spell" and Store.Resolve(r, "states", "cooldownAlphaTimed") == true then return true end
    end
    return false
end

-- The clock: a dial, and what it waits for once set; cyan while it works.
local function PaintClock(ck, r, st)
    local word = ET.TimedWord(r, st)
    local lit = ET.TimedLive(r, st)
    local fill = lit and COL.sel or COL.well
    local edge = lit and COL.arc or COL.line2
    local ink = lit and COL.arc or (word and COL.dim or COL.faint)
    ck:SetBackdropColor(fill[1], fill[2], fill[3], 1)
    ck:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    ck._adGlyph:SetColor(ink)
    local w = ck._adWord
    w:SetTextColor(ink[1], ink[2], ink[3])
    w:SetText(word or "")
    w:SetShown(word ~= nil)
    local ww = word and Measure(w) or 0
    local total = 11 + (word and (3 + ww) or 0)
    local x0 = math.floor((40 - total) / 2 + 0.5)
    ck._adGlyph:ClearAllPoints()
    ck._adGlyph:SetPoint("CENTER", ck, "LEFT", x0 + 5.5, 0)
    w:ClearAllPoints()
    w:SetPoint("LEFT", ck, "LEFT", x0 + 14, 0)
end

local POP_W, POP_PAD, POP_GAP = 286, 12, 8

-- The popover under a clock: Right away, or With [N] seconds left (an aura
-- also With [N] % of it left, and its length for seconds), then Before that.
function ET.TimePop(T)
    if T.pop then return T.pop end
    -- on the window, as a dropdown's list: a section box clips its children
    local p = CreateFrame("Frame", nil, T.owner or T.head:GetParent(), "BackdropTemplate")
    AT.Skin(p, COL.panel, COL.arc)
    p:EnableMouse(true)
    p:Hide()
    T.pop = p
    local function Rec() return p._ctx and p._ctx() end
    local function Tm() return p._st and p._st.timed end
    -- a field of the open row's spec (nil while closed: the widgets refresh at birth)
    local function TK(k) local t = Tm() return t and t[k] end
    local function Get(k) local t = Tm() return t and TimedGet(Rec(), t, k) end
    local function Put(k, v)
        local r, t = Rec(), Tm()
        if r and t and k then Store.SetOverride(r, t[1], k, v) end
    end
    local function Changed()
        if p._relay then p._relay() end
        p:Sync()
    end
    local function Words(parent, size, col)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, size, "")
        fs:SetTextColor(col[1], col[2], col[3])
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    local function Line(h)
        local l = CreateFrame("Frame", nil, p)
        l:SetHeight(h)
        return l
    end
    local function Bounds(field, lo, hi)
        local t = Tm()
        local def = t and Def(t[1], field)
        return (def and def.min) or lo, (def and def.max) or hi
    end

    local title = Words(p, 11, COL.arc)
    title:SetPoint("TOPLEFT", POP_PAD, -POP_PAD)
    local close = CreateFrame("Button", nil, p, "BackdropTemplate")
    close:SetSize(16, 16)
    AT.Skin(close, COL.well, COL.line2)
    close:SetPoint("TOPRIGHT", -POP_PAD, -10)
    local cx = Words(close, 11, COL.dim)
    cx:SetPoint("CENTER", 0, 1)
    cx:SetText("x")
    close:SetScript("OnClick", function() p:Close() end)

    -- Right away
    local l1 = Line(18)
    local r1 = Radio(l1, function()
        Put(TK("on"), false)
        Changed()
    end)
    r1:SetPoint("LEFT", 0, 0)
    local w1 = Words(l1, 13, COL.ink)
    w1:SetPoint("LEFT", r1, "RIGHT", 8, 0)

    -- With [N] seconds left
    local function PickSec()
        local t = Tm()
        Put(t.on, true)
        if t.unit then Put(t.unit, "sec") end
    end
    local l2 = Line(18)
    local r2 = Radio(l2, function()
        PickSec()
        Changed()
    end)
    r2:SetPoint("LEFT", 0, 0)
    local w2a = Words(l2, 13, COL.ink)
    w2a:SetPoint("LEFT", r2, "RIGHT", 8, 0)
    w2a:SetText(Tr("With"))
    local b2, b2sync = NumberBox(l2, 30, function() return Get(TK("sec")) or 3 end, function(v)
        local lo, hi = Bounds(TK("sec"), 0.5, 600)
        Put(TK("sec"), math.max(lo, math.min(hi, v)))
        PickSec()
        Changed()
    end)
    b2:SetPoint("LEFT", w2a, "RIGHT", 6, 0)
    local w2b = Words(l2, 13, COL.ink)
    w2b:SetPoint("LEFT", b2, "RIGHT", 6, 0)
    Tip(b2, "Seconds left", "The opacity starts with this many seconds left.")

    -- An aura's length, which seconds need
    local l2l = Line(18)
    local wl = Words(l2l, 12, COL.dim)
    wl:SetPoint("LEFT", 22, 0)
    wl:SetText(Tr("The aura lasts"))
    local bl, blsync = NumberBox(l2l, 30, function()
        local v = tonumber(Get(TK("len"))) or 0
        return v > 0 and v or nil
    end, function(v)
        local lo, hi = Bounds(TK("len"), 0, 600)
        Put(TK("len"), math.max(lo, math.min(hi, math.floor(v + 0.5))))
        Changed()
    end)
    bl:SetPoint("LEFT", wl, "RIGHT", 6, 0)
    local wl2 = Words(l2l, 12, COL.dim)
    wl2:SetPoint("LEFT", bl, "RIGHT", 6, 0)
    wl2:SetText(Tr("seconds"))
    Tip(bl, "The aura lasts", "The game keeps an aura's length from addons, so seconds need it. A share needs none.")

    -- With [N] % of the aura left (30 % is a debuff's pandemic window)
    local function PickPct()
        local t = Tm()
        Put(t.on, true)
        Put(t.unit, "pct")
    end
    local l3 = Line(18)
    local r3 = Radio(l3, function()
        PickPct()
        Changed()
    end)
    r3:SetPoint("LEFT", 0, 0)
    local w3a = Words(l3, 13, COL.ink)
    w3a:SetPoint("LEFT", r3, "RIGHT", 8, 0)
    w3a:SetText(Tr("With"))
    local b3, b3sync = NumberBox(l3, 30, function() return Get(TK("pct")) or 30 end, function(v)
        local lo, hi = Bounds(TK("pct"), 1, 99)
        Put(TK("pct"), math.max(lo, math.min(hi, math.floor(v + 0.5))))
        PickPct()
        Changed()
    end)
    b3:SetPoint("LEFT", w3a, "RIGHT", 6, 0)
    local w3b = Words(l3, 13, COL.ink)
    w3b:SetPoint("LEFT", b3, "RIGHT", 6, 0)
    w3b:SetText(Tr("% of the aura left"))
    Tip(b3, "Share of the aura left", "30 is a debuff's pandemic window. Needs no length.")

    -- Before that
    local div = p:CreateTexture(nil, "ARTWORK")
    div:SetTexture(AT.WHITE)
    div:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    local l4 = Line(18)
    local w4 = Words(l4, 12, COL.dim)
    w4:SetPoint("LEFT", 0, 0)
    w4:SetWidth(74)
    w4:SetText(Tr("Before that"))
    local s4, box4, s4sync = CompactSlider(l4, SLIDER_W, 0, 1, 0.01, true, nil,
        function() return Get(TK("before")) or 0 end,
        function(v)
            Put(TK("before"), v)
            if p._relay then p._relay() end
        end)
    s4:SetPoint("LEFT", w4, "RIGHT", 6, 0)
    Tip(s4, "Before that", "How visible the icon is until this opacity starts. 0 hides it.")
    Tip(box4, "Before that", "How visible the icon is until this opacity starts. 0 hides it.")

    -- what its Dynamic group does with it
    local l5 = Line(16)
    local w5 = Words(l5, 12, COL.dim)
    w5:SetPoint("LEFT", 0, 0)
    -- its parts by name, as a row keeps its cells
    p._adParts = { title = title, close = close, right = r1, sec = r2, pct = r3, secBox = b2, lenBox = bl,
        pctBox = b3, before = s4, beforeBox = box4, lenLine = l2l, pctLine = l3, beforeLine = l4,
        rightWords = w1, secWords = w2b, noteLine = l5, note = w5 }

    -- Lays the lines out for the record and sizes the box to them.
    function p:Sync()
        local r, t, st = Rec(), Tm(), self._st
        if not (r and t and self._row and self._row:IsVisible()) or r ~= self._rec then
            self:Close()
            return
        end
        local on = Get(t.on) == true
        local unit = t.unit and Get(t.unit) or "sec"
        title:SetText(Upper(Tr("%s: When it starts"):format(Tr(ET.StateWord(r, st) or st.label))))
        w1:SetText(Tr("Right away (%s)"):format(Tr(t.whole)))
        w2b:SetText(Tr(t.left))
        -- a longer word than the column's 74 widens it, so it never cuts off
        w4:SetWidth(math.max(74, Measure(w4)))
        r1:SetOn(not on)
        r2:SetOn(on and unit == "sec")
        r3:SetOn(on and unit == "pct")
        b2sync()
        blsync()
        b3sync()
        s4sync()
        local note = on and ET.TimedGroupNote(r) or nil
        w5:SetText(Tr(note or ""))
        local inner = math.max(Measure(title) + 8 + 16, 22 + Measure(w1),
            22 + Measure(w2a) + 6 + 30 + 6 + Measure(w2b), note and Measure(w5) or 0)
        local lines = { l1, l2 }
        local showLen = t.len ~= nil and on and unit == "sec"
        if showLen then lines[#lines + 1] = l2l end
        l2l:SetShown(showLen)
        if t.unit then
            lines[#lines + 1] = l3
            inner = math.max(inner, 22 + Measure(w3a) + 6 + 30 + 6 + Measure(w3b))
        end
        l3:SetShown(t.unit ~= nil)
        -- Before that: its word, then the slider with its stepper
        if on then inner = math.max(inner, w4:GetWidth() + 6 + SLIDER_W + AT.SLIDER_TRAIL) end
        local w = math.max(POP_W, inner + 2 * POP_PAD)
        local y = POP_PAD + 16 + POP_GAP
        for _, l in ipairs(lines) do
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", POP_PAD, -y)
            l:SetWidth(w - 2 * POP_PAD)
            y = y + 18 + POP_GAP
        end
        div:SetShown(on)
        l4:SetShown(on)
        if on then
            local px = AT.Hairline(p)
            div:ClearAllPoints()
            div:SetPoint("TOPLEFT", POP_PAD, -y)
            div:SetSize(w - 2 * POP_PAD, px)
            y = y + 6
            l4:ClearAllPoints()
            l4:SetPoint("TOPLEFT", POP_PAD, -y)
            l4:SetWidth(w - 2 * POP_PAD)
            y = y + 18 + POP_GAP
        end
        l5:SetShown(note ~= nil)
        if note then
            l5:ClearAllPoints()
            l5:SetPoint("TOPLEFT", POP_PAD, -y)
            l5:SetWidth(w - 2 * POP_PAD)
            y = y + 16 + POP_GAP
        end
        self:SetSize(w, y - POP_GAP + POP_PAD)
    end

    function p:Open(row, st, clock, ctx, relay)
        self._row, self._st, self._clock, self._ctx, self._relay = row, st, clock, ctx, relay
        self._rec = ctx()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", clock, "BOTTOMLEFT", 0, -10)
        self:SetFrameLevel(row:GetFrameLevel() + 50)
        self:Show()
        self:Sync()
    end

    function p:Close()
        self._row, self._st, self._clock, self._rec = nil, nil, nil, nil
        self:Hide()
    end

    -- a click anywhere else shuts it (its clock toggles it itself)
    p:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    p:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    p:SetScript("OnEvent", function(self, _, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        if self:IsMouseOver() or (self._clock and self._clock:IsMouseOver()) then return end
        local dd = AT.openDropdown
        if dd and dd:IsShown() and dd:IsMouseOver() then return end
        self:Close()
    end)
    return p
end

-- The Effects tab's Look line for state st: its opacity (the clock after it
-- on a timed state), grey out and tint as labelled pairs for ET.LayLines. A
-- setting whose dep fails dims in place, as the table's cell does. T: the
-- popover's home ({ owner = window }). Returns the line and its block def.
function ET.LookLine(ed, st, ctx, owner, relay, T)
    local B = { pairs = {}, adv = {}, st = st }
    local nm = ed:CreateFontString(nil, "OVERLAY")
    nm:SetFont(AT.FONT, 12, "")
    nm:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    nm:SetWordWrap(false)
    nm:SetText(Tr("Look"))
    B.name = nm
    local function Rec() return ctx() end
    local function Get(section, field)
        local r = Rec()
        return r and Store.Resolve(r, section, field)
    end
    local function Put(section, field, v)
        local r = Rec()
        if r then Store.SetOverride(r, section, field, v) end
    end
    local function Pair(section, field, words, ctrl, sync)
        local fdef = Def(section, field)
        local lbl = ed:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 12, "")
        lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        lbl:SetWordWrap(false)
        lbl:SetText(Tr(words))
        -- the line dims a failed dep itself, so the layout never drops the pair
        local P = { field = field, section = section, label = lbl, words = words, ctrl = ctrl, adv = false,
            fdef = fdef and setmetatable({ dep = false }, { __index = fdef }) }
        P.sync = function()
            local r = Rec()
            P._off = r ~= nil and not DepOK(r, section, field)
            sync()
        end
        P.labelSpan = function() return Measure(lbl) + 8 end
        P.width = function()
            local w = Measure(lbl) + 8 + (ctrl:GetWidth() or 0) + (P.trail or 0)
            if P.extra and P.extra:IsShown() then w = w + 6 + (P.extra:GetWidth() or 0) end
            return w
        end
        -- cx, cy: the control on a line of its own under the label (a narrow panel)
        P.place = function(x, y, cx, cy)
            lbl:ClearAllPoints()
            lbl:SetPoint("LEFT", ed, "TOPLEFT", x, y)
            ctrl:ClearAllPoints()
            ctrl:SetPoint("LEFT", ed, "TOPLEFT", cx or (x + Measure(lbl) + 8), cy or y)
            if P.extra then
                P.extra:ClearAllPoints()
                P.extra:SetPoint("LEFT", P.after or ctrl, "RIGHT", 6, 0)
            end
        end
        P.show = function(on)
            lbl:SetShown(on)
            ctrl:SetShown(on)
            P.shownNow = on
        end
        P.dim = function(off)
            local dim = off or P._off
            local a = dim and 0.45 or 1
            lbl:SetAlpha(a)
            ctrl:SetAlpha(a)
            if P.trail then AT.SliderMouse(ctrl, not dim) else ctrl:EnableMouse(not dim) end
        end
        if fdef and fdef.desc then Tip(ctrl, fdef.label or words, fdef.desc) end
        B.pairs[#B.pairs + 1] = P
        return P
    end
    local function Check(section, field, words)
        local cb = AT.MakeCheckbox(ed)
        cb:SetScript("OnClick", function()
            AT.CloseDropdown()
            Put(section, field, Get(section, field) ~= true)
            PlaySound(Get(section, field) == true and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            relay()
        end)
        cb:HookScript("OnEnter", function() cb:SetHover(true) end)
        cb:HookScript("OnLeave", function() cb:SetHover(false) end)
        return Pair(section, field, words, cb, function() cb:SetOn(Get(section, field) == true) end)
    end
    local stateWord = st.when or ""
    local sec
    local a, g, t = st.alpha, st.grey, st.tint
    if a then
        sec = a[1]
        if a.on then
            local ondef = Def(a[1], a.on)
            local P = Check(a[1], a.on, (ondef and ondef.label) or a.on)
            Tip(P.ctrl, (ondef and ondef.label) or a.on, st.onTip or (ondef and ondef.desc) or "")
        end
        local def = Def(a[1], a[2])
        local s, _, refresh = OpacityCell(ed, function() return Get(a[1], a[2]) or (def and def.d) or 1 end,
            function(v) Put(a[1], a[2], v) end)
        local P = Pair(a[1], a[2], "Opacity", s, refresh)
        P.trail, P.after = AT.SLIDER_TRAIL, s.plus
        local body = (def and def.desc) or function()
            return Tr("How visible the icon is %s."):format(Tr(stateWord)) .. " " .. Tr(st.alphaTip or "0 hides it.")
        end
        Tip(s, (def and def.label) or a[2], body)
        if st.timed then
            -- the clock: when this opacity starts (ET.TimePop)
            local ck = CreateFrame("Button", nil, ed, "BackdropTemplate")
            ck:SetSize(40, 18)
            AT.Skin(ck, COL.well, COL.line2)
            ck._adGlyph = ET.Glyph(ck, "clock")
            ck._adWord = ck:CreateFontString(nil, "OVERLAY")
            ck._adWord:SetFont(AT.FONT, 11, "")
            ck:SetScript("OnClick", function()
                AT.CloseDropdown()
                local pop = ET.TimePop(T)
                if pop:IsShown() and pop._row == ed then pop:Close() else pop:Open(ed, st, ck, Rec, relay) end
            end)
            Tip(ck, "When it starts", function()
                local word = ET.TimedWord(Rec(), st)
                if not word then return "Right away. Click to make it wait for the last seconds." end
                if not ET.TimedLive(Rec(), st) then return "Seconds need the aura's length: click to set it." end
                return Tr("With %s left. Click to change it."):format(word)
            end)
            P.extra = ck
            local base = P.sync
            P.sync = function()
                base()
                local r = Rec()
                local tm = st.timed
                local on = r ~= nil and tm.ok(r) == true and Applies(r, tm[1], tm.on)
                ck:SetShown(on and P.shownNow ~= false)
                if on then PaintClock(ck, r, st) end
                local pop = T and T.pop
                if pop and pop._row == ed and pop:IsShown() then pop:Sync() end
            end
            local show = P.show
            P.show = function(on)
                show(on)
                if not on then ck:Hide() end
            end
        end
    end
    if g then
        sec = sec or g[1]
        local P = Check(g[1], g[2], "Grey out")
        local gdef = Def(g[1], g[2])
        Tip(P.ctrl, (gdef and gdef.label) or g[2], (gdef and gdef.desc) or function()
            return Tr("Greys the icon out %s."):format(Tr(stateWord))
        end)
    end
    if t then
        sec = sec or t[1]
        if t.on then
            local ondef = Def(t[1], t.on)
            local P = Check(t[1], t.on, "Tint")
            Tip(P.ctrl, (ondef and ondef.label) or t.on, (ondef and ondef.desc) or function()
                return Tr("Colors the icon %s."):format(Tr(stateWord))
            end)
        end
        local tdef = Def(t[1], t[2])
        local sw = AT.MakeSwatch(ed, 28, 14)
        -- no opacity in the picker: a tint's alpha belongs to the state's opacity
        PickColor(sw, function() return Get(t[1], t[2]) or (tdef and tdef.d) or { 1, 1, 1, 1 } end,
            function(v) Put(t[1], t[2], v) end, false, nil, relay)
        Pair(t[1], t[2], t.on and "Tint color" or "Tint", sw, function()
            local c = Get(t[1], t[2]) or (tdef and tdef.d) or { 1, 1, 1 }
            sw:SetColor({ c[1] or 1, c[2] or 1, c[3] or 1 })
        end)
        Tip(sw, (tdef and tdef.label) or t[2], (tdef and tdef.desc) or function()
            return Tr("The color %s."):format(Tr(stateWord))
        end)
    end
    function B:Hide()
        nm:Hide()
        for _, P in ipairs(self.pairs) do
            P.show(false)
            if P.extra then P.extra:Hide() end
        end
    end
    local def = { section = sec, fields = {}, look = true }
    for _, P in ipairs(B.pairs) do def.fields[#def.fields + 1] = P.field end
    return B, def
end
ET.KeyDef, ET.FxColor = KeyDef, FxColor

local function StateRow(pg, T, ctx, vis, kind, st, owner)
    local lbl
    -- a row with a base pick carries it on a second line under its words
    local tall = st.base ~= nil
    local row = AT.AddRow(pg, tall and 52 or 34, function()
        if not vis() then return false end
        local r = ctx()
        if not (r and r.kind == kind) then return false end
        -- an icon's own words for the state (st.labelFn)
        if st.labelFn and lbl then lbl:SetText(Tr(st.labelFn(r) or st.label)) end
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
    lbl:SetFont(AT.FONT, 13, "")
    if tall then lbl:SetPoint("TOPLEFT", 14, -11) else lbl:SetPoint("LEFT", 14, 0) end
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    lbl:SetText(Tr(st.label))
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

    for _, c in ipairs(COLS) do
        local spec = st[c]
        local cell = CreateFrame("Frame", nil, row)
        cell:SetHeight(24)
        cell:EnableMouse(true)
        local C = { frame = cell, col = c, spec = spec, parts = {} }
        row._adCells[c] = C
        local dash = cell:CreateFontString(nil, "OVERLAY")
        dash:SetFont(AT.FONT, 12, "")
        dash:SetPoint("LEFT", 0, 0)
        dash:SetTextColor(COL.line2[1], COL.line2[2], COL.line2[3])
        local never = c == "alpha" and st.never
        dash:SetText(never and Tr(never) or "-")
        C.dash = dash
        local stateWord = st.when or ""
        -- a dash explains itself; a cell with controls leaves it to them
        Tip(cell, function() return Tr(COL_TIP[c]):format(Tr(st.label)) end, function()
            if C.has then return nil end
            if c == "alpha" and st.never then return st.neverTip end
            return Tr(COL_NONE[c]):format(Tr(st.label))
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
                local body = (def and def.desc) or function()
                    return Tr("How visible the icon is %s."):format(Tr(stateWord)) .. " "
                        .. Tr(st.alphaTip or "0 hides it.")
                end
                Tip(s, lab, body)
                Tip(box, lab, body)
                C.slider, C.box, C.refresh = s, box, refresh
                if st.timed then
                    -- the clock: when this opacity starts (ET.TimePop)
                    local ck = CreateFrame("Button", nil, cell, "BackdropTemplate")
                    ck:SetSize(40, 18)
                    ck:SetPoint("LEFT", s.plus, "RIGHT", 6, 0)
                    AT.Skin(ck, COL.well, COL.line2)
                    ck._adGlyph = ET.Glyph(ck, "clock")
                    ck._adWord = ck:CreateFontString(nil, "OVERLAY")
                    ck._adWord:SetFont(AT.FONT, 11, "")
                    ck:SetScript("OnClick", function()
                        AT.CloseDropdown()
                        local pop = ET.TimePop(T)
                        if pop:IsShown() and pop._row == row then
                            pop:Close()
                        else
                            pop:Open(row, st, ck, Rec, Relay)
                        end
                    end)
                    Tip(ck, "When it starts", function()
                        local word = ET.TimedWord(Rec(), st)
                        if not word then return "Right away. Click to make it wait for the last seconds." end
                        if not ET.TimedLive(Rec(), st) then return "Seconds need the aura's length: click to set it." end
                        return Tr("With %s left. Click to change it."):format(word)
                    end)
                    C.clock = ck
                end
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
                Tip(cb, lab, (def and def.desc) or function()
                    return Tr("Greys the icon out %s."):format(Tr(stateWord))
                end)
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
                        (ondef and ondef.desc) or function()
                            return Tr("Colors the icon %s."):format(Tr(stateWord))
                        end)
                    C.on = cb
                    x = 24
                end
                local sw = AT.MakeSwatch(cell, 30, 14)
                sw:SetPoint("LEFT", x, 0)
                -- no opacity slider: a tint's alpha belongs to the state opacity
                PickColor(sw, function() return Get(section, field) or (def and def.d) or { 1, 1, 1, 1 } end,
                    function(v) Put(section, field, v) end, false, nil, Relay)
                Tip(sw, lab, (def and def.desc) or function()
                    return Tr("The color %s."):format(Tr(stateWord))
                end)
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
        Tip(b, function() return Tr(ET.StateWord(Rec(), st)) .. ": " .. Tr(ET.FX_WORD[fk]) end, function()
            local r = Rec()
            if not r then return nil end
            local parts = {}
            for _, f in ipairs(ET.FxFor(r, st)) do
                if f.kind == fk then
                    for _, key in ipairs(f.keys) do
                        local def = KeyDef(r, key)
                        if def then
                            parts[#parts + 1] = Tr(ET.FxLit(r, key) and "%s: on" or "%s: off"):format(Tr(def.title or key))
                        end
                    end
                end
            end
            if #parts == 0 then return nil end
            return Tr("%s. Click to set it up here."):format(table.concat(parts, ". "))
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
                -- the slider's box and stepper are its children: they fade with it
                for _, w in ipairs({ C.slider or false, C.check or false, C.swatch or false }) do
                    if w then
                        w:SetAlpha(ok and 1 or 0.45)
                        if w == C.slider then AT.SliderMouse(w, ok) else w:EnableMouse(ok) end
                    end
                end
                C.enabled = ok
            end
            if C.clock then
                local t = st.timed
                local on = has and t.ok(r) == true and Applies(r, t[1], t.on)
                C.clock:SetShown(on)
                if on then PaintClock(C.clock, r, st) end
            end
        end
        -- an open popover follows the record, or shuts with its row
        local pop = T.pop
        if pop and pop._row == row and pop:IsShown() then pop:Sync() end
    end
    row:HookScript("OnHide", function()
        local pop = T.pop
        if pop and pop._row == row then pop:Close() end
    end)

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
        if st.timed and st.timed.ok(r) == true then
            for _, f in ipairs(st.timed.fields) do specs[#specs + 1] = { st.timed[1], f } end
        end
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

-- Own looks

-- A state's own looks while a condition holds (Core\AD_OwnLooks.lua, reached
-- at call time): a row each under the state, drawn as the state's row is,
-- added from a green + after the state's name. Look rows are made when a
-- record first needs them, so a table without looks draws as it always did.
local LOOK_H = 34
-- the + after a state's name, and its gap from the name
local PLUS_W, PLUS_GAP = 17, 5
-- a look's words sit further in than its state's, after the joint line
local LOOK_X, JOINT_X = 26, 17
-- up, down and x after the effect columns
local CTL_BTN, CTL_GAP = 17, 3
local CTL_W = 3 * CTL_BTN + 2 * CTL_GAP
-- the rail's "+ Add New" green, and its edge at rest
local GREEN, GREEN_EDGE = { 0.482, 0.847, 0.561 }, { 0.243, 0.478, 0.267 }

-- One icon's table, the Defaults page's kind (the looks its icons take) and
-- several icons at once (the lead's rows, each edit made on all of them):
-- the last two need the engine's inheritance and its writes over many.
local function LooksOn(r)
    local OL = NS.OwnLooks
    if not (r and OL and OL.List) then return false end
    if r._adMulti then return r.type == "icon" and OL.AddMany ~= nil end
    if r._adDefaults then return not r._adKinds and OL.Effective ~= nil end
    return true
end
ET.LooksOn = LooksOn

-- The record whose looks the rows list: the first of several icons.
local function Owner(r)
    if r and r._adMulti then return Store.Get(r._adIds[1]) end
    return r
end
ET.LookOwner = Owner

-- The icons of several, in the order they were picked.
local function Picked(r)
    local out = {}
    for _, id in ipairs(r._adIds or {}) do
        local x = Store.Get(id)
        if x then out[#out + 1] = x end
    end
    return out
end

-- The record's looks under a state, top first.
local function LooksOf(r, st)
    if not LooksOn(r) then return {} end
    local o = Owner(r)
    return (o and NS.OwnLooks.List(o, st.key)) or {}
end

-- A listed look's place in the record's list, and the look.
local function LookAt(e)
    if type(e) ~= "table" then return nil, nil end
    return e.index or e[1], e.look or e[2]
end

-- Two looks for the same state while the same conditions hold, in any order.
local function SameLook(a, b)
    if not (a and b) or a.state ~= b.state then return false end
    local wa, wb = a.when or {}, b.when or {}
    if #wa ~= #wb then return false end
    local set = {}
    for _, k in ipairs(wa) do set[k] = true end
    for _, k in ipairs(wb) do
        if not set[k] then return false end
    end
    return true
end
ET.SameLook = SameLook

-- How many of several icons have this look, of how many.
local function LookOnMany(r, look)
    local recs, n = Picked(r), 0
    for _, x in ipairs(recs) do
        for _, e in ipairs(NS.OwnLooks.List(x, look.state) or {}) do
            local _, l = LookAt(e)
            if SameLook(l, look) then
                n = n + 1
                break
            end
        end
    end
    return n, #recs
end

-- The quiet words after a look's name: on how many of several icons it is,
-- or where an icon's inherited look comes from (the layout's name raw).
local function LookTag(r, e)
    local _, look = LookAt(e)
    if not look then return "" end
    if r._adMulti then
        local n, m = LookOnMany(r, look)
        return n < m and Tr("on %d of %d"):format(n, m) or ""
    end
    local from = type(e) == "table" and e.source
    if from == "defaults" then return Tr("from Defaults") end
    if from == "layout" then
        local lay = Store.LayoutOf(r)
        return Tr("from %s"):format(lay and lay.name or "?")
    end
    return ""
end

-- The kind's own row for a state another kind's table names (several icons).
local function StateOf(rec, st)
    for _, s in ipairs(ET.STATES[rec.kind] or {}) do
        if s.key == st.key then return s end
    end
    return st
end

-- A look's writes: on the record (the engine copies an inherited list into
-- it first), or on the matching look of every icon picked.
local function LookSet(r, idx, field, v)
    local OL = NS.OwnLooks
    if r._adMulti then
        if OL.SetMatching then OL.SetMatching(Picked(r), Owner(r), idx, field, v) end
    elseif OL.Set then
        OL.Set(r, idx, field, v)
    end
end
local function LookRemove(r, idx)
    local OL = NS.OwnLooks
    if r._adMulti then
        if OL.RemoveMatching then OL.RemoveMatching(Picked(r), Owner(r), idx) end
    elseif OL.Remove then
        OL.Remove(r, idx)
    end
end
local function LookMove(r, idx, dir)
    local OL = NS.OwnLooks
    if r._adMulti then
        if OL.MoveMatching then OL.MoveMatching(Picked(r), Owner(r), idx, dir) end
    elseif OL.Move then
        OL.Move(r, idx, dir)
    end
end
ET.LookMove, ET.LookRemove = LookMove, LookRemove
-- a new look starts as each icon's own look of the state
local function LookAdd(r, st, condKey)
    local OL = NS.OwnLooks
    if r._adMulti then
        OL.AddMany(Picked(r), st.key, condKey, function(rec) return ET.LookCopy(rec, StateOf(rec, st)) end)
    elseif OL.Add then
        OL.Add(r, st.key, condKey, ET.LookCopy(r, st))
    end
end

-- The columns a look of the state can set on the record: the cells the state
-- row draws that the engine lets a look take over (OL.Spec: an aura's Active
-- is the game's button, so it has none), and the glow (its keys). An aura's
-- Missing glows can only be turned off, so that cell waits for one that is on.
local OFFER_KEY = { alpha = "a", grey = "g", tint = "t" }
local function LookCols(r, st)
    local has = { any = false }
    local OL = NS.OwnLooks
    r = Owner(r)
    if not r then return has end
    local offer = OL and OL.Offered and OL.Offered(r, st.key) and OL.Spec(r, st.key)
    if not offer then return has end
    for _, c in ipairs(COLS) do
        local spec = st[c]
        if spec and offer[OFFER_KEY[c]] and Applies(r, spec[1], spec[2]) then
            has[c] = true
            has.any = true
        end
    end
    if offer.glow then
        local offOnly = offer.glow[1] == "missing"
        for _, f in ipairs(ET.FxFor(r, st)) do
            if f.kind == "glow" then
                local lit = false
                for _, key in ipairs(f.keys) do
                    if ET.FxLit(r, key) then lit = true end
                end
                if lit or not offOnly then
                    has.glow = f.keys
                    has.any = true
                end
            end
        end
    end
    return has
end

-- The state's look as its row's cells show it: where a new look starts, so
-- nothing changes until it is edited. An opacity whose switch is off is the
-- state keeping its opacity, so a copy leaves it out; shown: the slider's
-- value anyway, for a look row that leaves it to the state.
function ET.LookCopy(r, st, shown)
    r = Owner(r)
    local has = LookCols(r, st)
    local out = {}
    if not r then return out end
    if has.alpha then
        local s = st.alpha
        local def = Def(s[1], s[2])
        if shown or not s.on or Store.Resolve(r, s[1], s.on) == true then
            out.alpha = Store.Resolve(r, s[1], s[2]) or (def and def.d) or 1
        end
        -- a hidden Missing look draws at 0 whatever its opacity says, so a
        -- new look must not show the icon
        if s[1] == "auraMissing" and s[2] == "missingAlpha"
            and Store.Resolve(r, "auraMissing", "showWhileMissing") == false then
            out.alpha = 0
        end
    end
    if has.grey then out.grey = Store.Resolve(r, st.grey[1], st.grey[2]) == true end
    if has.tint then
        local s = st.tint
        out.tint = (s.on == nil) or Store.Resolve(r, s[1], s.on) == true
        local c = Store.Resolve(r, s[1], s[2]) or { 1, 1, 1 }
        out.tintColor = { c[1] or 1, c[2] or 1, c[3] or 1 }
    end
    if has.glow then
        local on = false
        for _, key in ipairs(has.glow) do
            if ET.FxLit(r, key) then on = true end
        end
        out.glow = on
    end
    return out
end

-- A look's conditions in the engine's words ("no target"), translated there.
function ET.LookWords(look)
    local OL = NS.OwnLooks
    return (OL and OL.Label and look and OL.Label(look)) or ""
end

-- "+ Add a Missing look while...", "an" before a vowel.
local VOWEL = { A = true, E = true, I = true, O = true, U = true }
function ET.AddLookWords(r, st)
    local w = ET.StateWord(r, st) or st.label
    if VOWEL[w:sub(1, 1):upper()] then return Tr("+ Add an %s look while..."):format(Tr(w)) end
    return Tr("+ Add a %s look while..."):format(Tr(w))
end

-- A look's glow lights in its state's glow colour: the first one on, else
-- the first one's, else the accent.
local function LookGlowColor(r, keys)
    local first
    for _, key in ipairs(keys or {}) do
        local def = KeyDef(r, key)
        for _, f in ipairs(def and def.fields or {}) do
            if f:find("Color", 1, true) then
                local c = Store.Resolve(r, def.section, f)
                if type(c) == "table" then
                    if ET.FxLit(r, key) then return c end
                    first = first or c
                end
                break
            end
        end
    end
    return first or COL.arc
end
ET.LooksOf, ET.LookAt, ET.LookCols, ET.LookTag, ET.LookGlowColor = LooksOf, LookAt, LookCols, LookTag, LookGlowColor

-- A tooltip of one line (the theme's wants a body too).
local function TipLine(region, text)
    region:HookScript("OnEnter", function(self)
        local t = text
        if type(t) == "function" then t = t() end
        if type(t) ~= "string" or t == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Tr(t), 1, 1, 1)
        GameTooltip:Show()
    end)
    region:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A quiet square button for a look row's arrows and x.
local function LookButton(row)
    local b = CreateFrame("Button", nil, row, "BackdropTemplate")
    b:SetSize(CTL_BTN, CTL_BTN)
    AT.Skin(b, COL.btn, COL.line2)
    b:HookScript("OnEnter", function() b:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    b:HookScript("OnLeave", function() b:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1) end)
    return b
end

-- A look cell's switch, lit under the mouse as the state rows' are.
local function Checkbox(parent, onClick)
    local cb = AT.MakeCheckbox(parent)
    cb:SetPoint("LEFT", 0, 0)
    cb:SetScript("OnClick", onClick)
    cb:HookScript("OnEnter", function() cb:SetHover(true) end)
    cb:HookScript("OnLeave", function() cb:SetHover(false) end)
    return cb
end

-- One own look's row under its state: its name joined to the state by a
-- line, the state's cells (a dash where the state has none), its glow,
-- then up and down (on hover, with two or more) and x. i: its place under
-- the state. Made on demand, under the state's editor row and its looks.
local function LookRow(T, slot, i)
    local pg, sec, st, kind, ctx = T.pg, T.sec, slot.st, slot.kind, T.ctx
    local function Entry()
        local r = ctx()
        if not (r and r.kind == kind) then return nil, nil end
        return r, LooksOf(r, st)[i]
    end
    local was = pg._curSection
    pg._curSection = sec
    local row = AT.AddRow(pg, LOOK_H, function()
        if not T.vis() then return false end
        local r = ctx()
        if not (r and r.kind == kind) or not slot.srow._visibleFn() then return false end
        return LooksOf(r, st)[i] ~= nil
    end)
    pg._curSection = was
    -- AddRow put it last: it belongs right after the state's last row so far
    local list = (sec and sec.rows) or pg._rows
    table.remove(list)
    local at = #list + 1
    for k, r in ipairs(list) do
        if r == slot.last then
            at = k + 1
            break
        end
    end
    table.insert(list, at, row)
    slot.last = row
    row._adOwnLook, row._adLookIndex = slot, i
    local frame = TableEdges(row, false)
    local jv, jh = Strip(row), Strip(row)
    jv:SetVertexColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
    jh:SetVertexColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
    local nameA = row:CreateFontString(nil, "OVERLAY")
    nameA:SetFont(AT.FONT, 12, "")
    nameA:SetPoint("LEFT", LOOK_X, 0)
    nameA:SetJustifyH("LEFT")
    nameA:SetWordWrap(false)
    local nameB = row:CreateFontString(nil, "OVERLAY")
    nameB:SetFont(AT.FONT, 12, "")
    nameB:SetPoint("LEFT", nameA, "RIGHT", 0, 0)
    nameB:SetJustifyH("LEFT")
    nameB:SetWordWrap(false)
    -- where an inherited look comes from, or on how many of several icons
    local tag = row:CreateFontString(nil, "OVERLAY")
    tag:SetFont(AT.FONT, 10, "")
    tag:SetPoint("LEFT", nameB, "RIGHT", 8, 0)
    tag:SetJustifyH("LEFT")
    tag:SetWordWrap(false)
    tag:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row._adLabel, row._adWords, row._adTag = nameA, nameB, tag

    local function Look()
        local _, e = Entry()
        local _, look = LookAt(e)
        return look
    end
    -- a field as the row shows it: the look's own, else its state's
    local function Val(field)
        local r, e = Entry()
        local _, look = LookAt(e)
        if not look then return nil end
        if look[field] ~= nil then return look[field] end
        return ET.LookCopy(r, st, true)[field]
    end
    local function Put(field, v)
        local r, e = Entry()
        local idx = LookAt(e)
        if idx and NS.OwnLooks then LookSet(r, idx, field, v) end
    end
    local function Relay() AT.LayoutPage(pg) end
    local function Name()
        local r = ctx()
        local look = Look()
        if not (r and look) then return "" end
        return Tr(ET.StateWord(r, st)) .. ", " .. ET.LookWords(look)
    end
    -- the name's parts set, and their width, for the table's first column
    row._adNameW = function()
        local r, e = Entry()
        local _, look = LookAt(e)
        if not (r and look) then return 0 end
        nameA:SetText(Tr(ET.StateWord(r, st)) .. ", ")
        nameB:SetText(ET.LookWords(look))
        local words = LookTag(r, e)
        tag:SetText(words)
        tag:SetShown(words ~= "")
        return Measure(nameA) + Measure(nameB) + (words ~= "" and (8 + Measure(tag)) or 0)
    end
    local function Click(field)
        return function()
            AT.CloseDropdown()
            local v = Val(field) ~= true
            Put(field, v)
            PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            Relay()
        end
    end

    local hoverables = {}
    local cells = {}
    row._adCells = cells
    for _, c in ipairs(COLS) do
        local spec = st[c]
        local cell = CreateFrame("Frame", nil, row)
        cell:SetHeight(24)
        cell:EnableMouse(true)
        hoverables[#hoverables + 1] = cell
        local C = { frame = cell, col = c, spec = spec }
        cells[c] = C
        local dash = cell:CreateFontString(nil, "OVERLAY")
        dash:SetFont(AT.FONT, 12, "")
        dash:SetPoint("LEFT", 0, 0)
        dash:SetTextColor(COL.line2[1], COL.line2[2], COL.line2[3])
        local never = c == "alpha" and st.never
        dash:SetText(never and Tr(never) or "-")
        C.dash = dash
        local function Title() return Tr(COL_TIP[c]):format(Name()) end
        Tip(cell, Title, function()
            if C.has then return nil end
            if c == "alpha" and st.never then return st.neverTip end
            return Tr(COL_NONE[c]):format(Tr(st.label))
        end)
        if spec and c == "alpha" then
            local s, box, refresh = OpacityCell(cell, function() return Val("alpha") or 1 end,
                function(v) Put("alpha", v) end)
            -- where the state's slider sits, after its switch when it has one
            s:SetPoint("LEFT", spec.on and 24 or 0, 0)
            local body = function() return Tr("How visible the icon is while this look shows. 0 hides it.") end
            Tip(s, Title, body)
            Tip(box, Title, body)
            C.slider, C.box, C.refresh = s, box, refresh
            for _, f in ipairs({ s, s.minus, box, s.plus }) do hoverables[#hoverables + 1] = f end
        elseif spec and c == "grey" then
            local cb = Checkbox(cell, Click("grey"))
            Tip(cb, Title, function() return Tr("Greys the icon out while this look shows.") end)
            C.check = cb
            hoverables[#hoverables + 1] = cb
        elseif spec then
            local x = 0
            local body = function() return Tr("Colors the icon while this look shows.") end
            if spec.on then
                local cb = Checkbox(cell, Click("tint"))
                Tip(cb, Title, body)
                C.on = cb
                hoverables[#hoverables + 1] = cb
                x = 24
            end
            local sw = AT.MakeSwatch(cell, 30, 14)
            sw:SetPoint("LEFT", x, 0)
            PickColor(sw, function()
                local v = Val("tintColor") or { 1, 1, 1 }
                return { v[1] or 1, v[2] or 1, v[3] or 1, v[4] }
            end, function(v) Put("tintColor", { v[1], v[2], v[3] }) end, false, nil, Relay)
            Tip(sw, Title, body)
            C.swatch = sw
            hoverables[#hoverables + 1] = sw
        end
    end

    -- its glow: lit in the state's glow colour while on, a plus while off
    local gb = CreateFrame("Button", nil, row, "BackdropTemplate")
    gb:SetSize(32, 24)
    AT.Skin(gb, COL.box, COL.line)
    local lit = ET.Glyph(gb, "glow")
    lit:SetPoint("CENTER", 0, 0)
    local plus = ET.Glyph(gb, "add")
    plus:SetPoint("CENTER", 0, 0)
    gb._adLit, gb._adAdd = lit, plus
    function gb:_adPaint()
        local on = self._adOn
        local fillC = on and COL.panel or COL.box
        local edge = self._hot and COL.arc or (on and COL.line2 or COL.line)
        self:SetBackdropColor(fillC[1], fillC[2], fillC[3], 1)
        self:SetBackdropBorderColor(edge[1], edge[2], edge[3], (on or self._hot) and 1 or 0.6)
    end
    gb:SetScript("OnClick", Click("glow"))
    gb:HookScript("OnEnter", function() gb._hot = true gb:_adPaint() end)
    gb:HookScript("OnLeave", function() gb._hot = nil gb:_adPaint() end)
    Tip(gb, function() return Name() .. ": " .. Tr(ET.FX_WORD.glow) end,
        function() return Tr("On: it glows while this look shows. Click to switch it.") end)
    gb:Hide()
    row._adGlow = gb
    hoverables[#hoverables + 1] = gb

    -- up and down swap it with its neighbour under the state; x removes it
    local up, down, x = LookButton(row), LookButton(row), LookButton(row)
    local cu, cd = AT.MakeChevron(up), AT.MakeChevron(down)
    cu:SetPoint("CENTER", 0, 0)
    cu:SetDir("up")
    cu:SetColor(COL.chev)
    cd:SetPoint("CENTER", 0, 0)
    cd:SetDir("down")
    cd:SetColor(COL.chev)
    local xf = x:CreateFontString(nil, "OVERLAY")
    xf:SetFont(AT.FONT, 10, "")
    xf:SetPoint("CENTER", 0, 1)
    xf:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    xf:SetText("x")
    local function Move(dir)
        AT.CloseDropdown()
        local r, e = Entry()
        local idx = LookAt(e)
        local to = i + dir
        if not (idx and NS.OwnLooks) or to < 1 or to > #LooksOf(r, st) then return end
        LookMove(r, idx, dir)
        Relay()
    end
    up:SetScript("OnClick", function() Move(-1) end)
    down:SetScript("OnClick", function() Move(1) end)
    x:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r, e = Entry()
        local idx = LookAt(e)
        if idx and NS.OwnLooks then LookRemove(r, idx) end
        Relay()
    end)
    local order = function() return Tr("The top look wins when several hold.") end
    Tip(up, function() return Tr("Move up") end, order)
    Tip(down, function() return Tr("Move down") end, order)
    TipLine(x, function() return Tr("Remove this look") end)
    up:Hide()
    down:Hide()
    row._adUp, row._adDown, row._adX = up, down, x
    for _, b in ipairs({ up, down, x }) do hoverables[#hoverables + 1] = b end

    -- the arrows show while the mouse is anywhere on the row
    local function Hover()
        local on = row._adMany == true and row:IsMouseOver() and true or false
        up:SetShown(on)
        down:SetShown(on)
    end
    row._adHover = Hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", Hover)
    row:SetScript("OnLeave", Hover)
    for _, f in ipairs(hoverables) do
        f:HookScript("OnEnter", Hover)
        f:HookScript("OnLeave", Hover)
    end

    row._sync = function()
        local r = ctx()
        local look = Look()
        if not (look and T.c1) then return end
        local n = #LooksOf(r, st)
        frame(T.full or T.w)
        -- the joint: down from the row above, to the middle on the last look
        local px = AT.Hairline(row)
        jv:ClearAllPoints()
        jv:SetPoint("TOPLEFT", JOINT_X, 1)
        jv:SetSize(px, (i == n) and (LOOK_H / 2 + 1) or (LOOK_H + 2))
        jh:ClearAllPoints()
        jh:SetPoint("TOPLEFT", JOINT_X, -LOOK_H / 2)
        jh:SetSize(LOOK_X - 3 - JOINT_X, px)
        -- the state's words a step under its own, the condition's in the accent
        nameA:SetTextColor((COL.ink[1] + COL.dim[1]) / 2, (COL.ink[2] + COL.dim[2]) / 2,
            (COL.ink[3] + COL.dim[3]) / 2)
        nameB:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        row._adNameW()
        local has = LookCols(r, st)
        local xs = { alpha = T.c1, grey = T.c2, tint = T.c3 }
        local ws = { alpha = T.w1, grey = T.w2, tint = T.w3 }
        for _, c in ipairs(COLS) do
            local C = cells[c]
            C.frame:ClearAllPoints()
            C.frame:SetPoint("LEFT", xs[c], 0)
            C.frame:SetWidth(ws[c])
            C.has = has[c] == true and C.spec ~= nil
            C.dash:SetShown(not C.has)
            for _, w in ipairs({ C.on or false, C.slider or false, C.box or false, C.check or false, C.swatch or false }) do
                if w then w:SetShown(C.has) end
            end
            if C.has then
                if C.refresh then C.refresh() end
                if C.check then C.check:SetOn(Val("grey") == true) end
                if C.on then C.on:SetOn(Val("tint") == true) end
                if C.swatch then
                    local v = Val("tintColor") or { 1, 1, 1 }
                    C.swatch:SetColor({ v[1] or 1, v[2] or 1, v[3] or 1 })
                end
            end
        end
        local gx = T.fxX and T.fxX.glow
        if has.glow and gx then
            local on = Val("glow") == true
            gb._adOn = on
            gb:_adPaint()
            lit:SetShown(on)
            plus:SetShown(not on)
            if on then lit:SetColor(LookGlowColor(r, has.glow)) end
            plus:SetColor(COL.line2)
            gb:ClearAllPoints()
            gb:SetPoint("LEFT", gx + 6, 0)
            gb:Show()
        else
            gb:Hide()
        end
        local cx = T.ctlX or (T.w - 10)
        row._adMany = n >= 2
        up:ClearAllPoints()
        up:SetPoint("LEFT", cx, 0)
        down:ClearAllPoints()
        down:SetPoint("LEFT", cx + CTL_BTN + CTL_GAP, 0)
        x:ClearAllPoints()
        x:SetPoint("LEFT", cx + (row._adMany and 2 * (CTL_BTN + CTL_GAP) or 0), 0)
        up:SetAlpha(i == 1 and 0.35 or 1)
        down:SetAlpha(i == n and 0.35 or 1)
        Hover()
    end

    -- found by its name, as the state rows are by their cells
    row._adSearch = function()
        if not Look() then return {} end
        return { Name() }
    end
    return row
end

-- The conditions a look can wait on, grouped as the condition list groups
-- them, in the engine's order.
local function LookGroups()
    local OL, C = NS.OwnLooks, NS.Conditions
    local cats = {}
    for _, c in ipairs(C and C.CATEGORIES or {}) do cats[c.id] = c.text end
    local out, by = {}, {}
    for _, c in ipairs(OL and OL.CONDITIONS or {}) do
        local d = C and C.ByKey and C.ByKey(c.key)
        local cat = c.cat or (d and d.cat) or "other"
        local g = by[cat]
        if not g then
            g = { title = cats[cat] or "Other", items = {} }
            by[cat] = g
            out[#out + 1] = g
        end
        g.items[#g.items + 1] = c
    end
    return out
end

local PICK_W, PICK_PAD, PICK_HEAD_H, PICK_ITEM_H = 128, 3, 17, 19

-- The condition pick under an add row: two columns of groups, on the window
-- as a dropdown's list is (a section box clips its children). One per table.
function ET.LookPick(T)
    if T.lookPick then return T.lookPick end
    local p = CreateFrame("Frame", nil, T.owner or T.head:GetParent(), "BackdropTemplate")
    AT.Skin(p, COL.panel, COL.line2)
    p:EnableMouse(true)
    p:Hide()
    T.lookPick = p
    p._heads, p._items = {}, {}
    local function Head(n)
        local fs = p._heads[n]
        if not fs then
            fs = p:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, 9, "")
            fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            p._heads[n] = fs
        end
        return fs
    end
    local function Item(n)
        local b = p._items[n]
        if not b then
            b = CreateFrame("Button", nil, p)
            b:SetHeight(PICK_ITEM_H)
            b:SetHighlightTexture(AT.WHITE)
            b:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.5)
            b.t = b:CreateFontString(nil, "OVERLAY")
            b.t:SetFont(AT.FONT, 11, "")
            b.t:SetPoint("LEFT", 14, 0)
            b.t:SetJustifyH("LEFT")
            b.t:SetWordWrap(false)
            b:SetScript("OnClick", function(self)
                local pick, key = p._onPick, self._adKey
                AT.CloseDropdown()
                if pick and key then pick(key) end
            end)
            p._items[n] = b
        end
        return b
    end
    -- The groups in two columns, the first taking groups until it holds
    -- half the conditions; each column as wide as its words need.
    function p:Fill()
        local groups = LookGroups()
        local total = 0
        for _, g in ipairs(groups) do total = total + #g.items end
        local cols, n1, second = { {}, {} }, 0, false
        for _, g in ipairs(groups) do
            if not second and n1 >= total / 2 and #cols[1] > 0 then second = true end
            local c = second and cols[2] or cols[1]
            c[#c + 1] = g
            if not second then n1 = n1 + #g.items end
        end
        for _, fs in ipairs(self._heads) do fs:Hide() end
        for _, b in ipairs(self._items) do b:Hide() end
        local ink = { (COL.ink[1] + COL.dim[1]) / 2, (COL.ink[2] + COL.dim[2]) / 2, (COL.ink[3] + COL.dim[3]) / 2 }
        local nh, ni, x, h = 0, 0, 0, 0
        for _, col in ipairs(cols) do
            if #col > 0 then
                local w, y, made = PICK_W, PICK_PAD, {}
                for _, g in ipairs(col) do
                    nh = nh + 1
                    local fs = Head(nh)
                    fs:SetText(Upper(Tr(g.title)))
                    w = math.max(w, Measure(fs) + 8 + 9)
                    made[#made + 1] = { fs = fs, y = y }
                    y = y + PICK_HEAD_H
                    for _, c in ipairs(g.items) do
                        ni = ni + 1
                        local b = Item(ni)
                        b._adKey = c.key
                        b.t:SetText(Tr(c.text))
                        b.t:SetTextColor(ink[1], ink[2], ink[3])
                        w = math.max(w, Measure(b.t) + 14 + 9)
                        made[#made + 1] = { b = b, y = y }
                        y = y + PICK_ITEM_H
                    end
                end
                for _, m in ipairs(made) do
                    if m.fs then
                        m.fs:ClearAllPoints()
                        m.fs:SetPoint("LEFT", self, "TOPLEFT", x + 8, -(m.y + PICK_HEAD_H / 2))
                        m.fs:Show()
                    else
                        m.b:ClearAllPoints()
                        m.b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -m.y)
                        m.b:SetWidth(w)
                        m.b:Show()
                    end
                end
                x = x + w
                h = math.max(h, y)
            end
        end
        self:SetSize(math.max(PICK_W, x), h + PICK_PAD)
    end
    -- Opens under the add row, or over it when the page has no room below.
    function p:Open(btn, onPick, pg)
        self._owner, self._onPick = btn, onPick
        self:Fill()
        self:ClearAllPoints()
        self:SetFrameLevel(btn:GetFrameLevel() + 50)
        local bb, pb = btn:GetBottom(), pg and pg:GetBottom()
        local bs, ps = btn:GetEffectiveScale() or 1, pg and pg:GetEffectiveScale() or 1
        local room = (bb and pb) and (bb * bs - pb * ps) / bs or nil
        if room and room < self:GetHeight() + 4 then
            self:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 3)
        else
            self:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -3)
        end
        self:Show()
        AT.openDropdown = self
    end
    -- a click anywhere else shuts it (its add row toggles it itself)
    p:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    p:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        local b = self._owner
        self._owner, self._onPick = nil, nil
        if AT.openDropdown == self then AT.openDropdown = nil end
        if b and b._adPaint then b._adPaint() end
    end)
    p:SetScript("OnEvent", function(self, _, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        if self:IsMouseOver() or (self._owner and self._owner:IsMouseOver()) then return end
        AT.CloseDropdown()
    end)
    return p
end

-- A look can be added under the state on the record: looks are on, the
-- state has a column a look can set, and the engine's cap is not reached.
function ET.LookCanAdd(r, st)
    if not (r and LooksOn(r)) then return false end
    -- the Defaults page draws every state; a state only some icons have
    -- (Recharging, Toggled on) gets its looks on those icons, which keeps
    -- the page within its height
    if r._adDefaults and st.showIf and st.showIf(r) ~= true then return false end
    -- at the engine's cap a pick could add nothing (an inherited list
    -- counts: the add copies it first)
    local max, OL, o = Schema.OWN_LOOK_MAX, NS.OwnLooks, Owner(r)
    local list = (OL.Effective and o and OL.Effective(o)) or (o and o.ownLooks)
    if max and type(list) == "table" and #list >= max then return false end
    return LookCols(r, st).any
end

-- The Effects tab's lines for one own look (UI\AD_EffectsTab.lua): the cells
-- a look of its state can set, then its order and removal. which(): the
-- record, the state and the look's place under it; place(i): the look moved
-- to i, or was removed (nil). One pair of lines serves every look.
function ET.OwnLookLines(ed, which, relay, place)
    local function Entry()
        local r, st, i = which()
        if not (r and st and i) then return nil end
        return r, st, i, LooksOf(r, st)[i]
    end
    local function Val(field)
        local r, st, _, e = Entry()
        local _, look = LookAt(e)
        if not look then return nil end
        if look[field] ~= nil then return look[field] end
        return ET.LookCopy(r, st, true)[field]
    end
    local function Put(field, v)
        local r, _, _, e = Entry()
        local idx = LookAt(e)
        if idx and NS.OwnLooks then LookSet(r, idx, field, v) end
    end
    local function Has(c)
        local r, st, _, e = Entry()
        if not e then return false end
        local has = LookCols(r, st)
        if c == "tintOn" then return has.tint == true and st.tint.on ~= nil end
        if c == "glow" then return has.glow ~= nil end
        return has[c] == true
    end
    local function Name(text)
        local fs = ed:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 12, "")
        fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        fs:SetWordWrap(false)
        fs:SetText(Tr(text))
        return fs
    end
    local function Line(name)
        local B = { pairs = {}, adv = {}, name = Name(name) }
        function B:Hide()
            self.name:Hide()
            for _, P in ipairs(self.pairs) do P.show(false) end
        end
        return B, { section = "states", fields = {}, ownLook = true }
    end
    -- a pair with its own show test (P.shows) and no mixed mark: a look's
    -- cells are not fields of the record
    local function Pair(B, words, ctrl, shows, sync)
        local lbl = ed:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 12, "")
        lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        lbl:SetWordWrap(false)
        lbl:SetText(Tr(words))
        local P = { label = lbl, words = words, ctrl = ctrl, adv = false, noMark = true, shows = shows }
        local function LabelW() return words ~= "" and (Measure(lbl) + 8) or 0 end
        P.sync = sync or function() end
        P.width = function() return LabelW() + (ctrl:GetWidth() or 0) + (P.trail or 0) end
        P.place = function(x, y)
            lbl:ClearAllPoints()
            lbl:SetPoint("LEFT", ed, "TOPLEFT", x, y)
            ctrl:ClearAllPoints()
            ctrl:SetPoint("LEFT", ed, "TOPLEFT", x + LabelW(), y)
        end
        P.show = function(on)
            lbl:SetShown(on and words ~= "")
            ctrl:SetShown(on)
        end
        P.dim = function() end
        B.pairs[#B.pairs + 1] = P
        return P
    end
    local function Check(B, words, field, shows, body)
        local cb = AT.MakeCheckbox(ed)
        cb:SetScript("OnClick", function()
            AT.CloseDropdown()
            local v = Val(field) ~= true
            Put(field, v)
            PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
            relay()
        end)
        cb:HookScript("OnEnter", function() cb:SetHover(true) end)
        cb:HookScript("OnLeave", function() cb:SetHover(false) end)
        Tip(cb, words, function() return Tr(body) end)
        return Pair(B, words, cb, shows, function() cb:SetOn(Val(field) == true) end)
    end

    local B1, def1 = Line("Look")
    local s, _, refresh = OpacityCell(ed, function() return Val("alpha") or 1 end, function(v) Put("alpha", v) end)
    local P = Pair(B1, "Opacity", s, function() return Has("alpha") end, refresh)
    P.trail = AT.SLIDER_TRAIL
    Tip(s, "Opacity", function() return Tr("How visible the icon is while this look shows. 0 hides it.") end)
    Check(B1, "Grey out", "grey", function() return Has("grey") end, "Greys the icon out while this look shows.")
    Check(B1, "Tint", "tint", function() return Has("tintOn") end, "Colors the icon while this look shows.")
    local sw = AT.MakeSwatch(ed, 28, 14)
    PickColor(sw, function()
        local v = Val("tintColor") or { 1, 1, 1 }
        return { v[1] or 1, v[2] or 1, v[3] or 1, v[4] }
    end, function(v) Put("tintColor", { v[1], v[2], v[3] }) end, false, nil, relay)
    local tc = Pair(B1, "Tint color", sw, function() return Has("tint") end)
    tc.sync = function()
        tc.label:SetText(Tr(Has("tintOn") and "Tint color" or "Tint"))
        local v = Val("tintColor") or { 1, 1, 1 }
        sw:SetColor({ v[1] or 1, v[2] or 1, v[3] or 1 })
    end
    Tip(sw, "Tint color", function() return Tr("Colors the icon while this look shows.") end)
    Check(B1, "Glow", "glow", function() return Has("glow") end,
        "It glows while this look shows, in its state's glow colour.")

    -- up and down swap it with its neighbour under the state; the top wins
    local B2, def2 = Line("")
    local function Move(dir)
        AT.CloseDropdown()
        local r, st, i, e = Entry()
        local idx = LookAt(e)
        if not (idx and NS.OwnLooks) or i + dir < 1 or i + dir > #LooksOf(r, st) then return end
        LookMove(r, idx, dir)
        place(i + dir)
        relay()
    end
    local function Many()
        local r, st = Entry()
        return r ~= nil and #LooksOf(r, st) >= 2
    end
    local up = AT.MakeSmallButton(ed, "Move up", 84)
    up:SetScript("OnClick", function() Move(-1) end)
    local dn = AT.MakeSmallButton(ed, "Move down", 94)
    dn:SetScript("OnClick", function() Move(1) end)
    local order = function() return Tr("The top look wins when several hold.") end
    Tip(up, "Move up", order)
    Tip(dn, "Move down", order)
    Pair(B2, "", up, Many, function()
        local _, _, i = Entry()
        up:SetAlpha(i == 1 and 0.45 or 1)
    end)
    Pair(B2, "", dn, Many, function()
        local r, st, i = Entry()
        dn:SetAlpha((r and i == #LooksOf(r, st)) and 0.45 or 1)
    end)
    local rm = AT.MakeQuietButton(ed, "Remove look", 104)
    rm:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r, _, _, e = Entry()
        local idx = LookAt(e)
        if not (idx and NS.OwnLooks) then return end
        LookRemove(r, idx)
        place(nil)
        relay()
    end)
    Tip(rm, "Remove look", function() return Tr("Takes this look off the icon.") end)
    Pair(B2, "", rm, function() return Entry() ~= nil end)
    return B1, def1, B2, def2
end

-- The line under a state's look on the Effects tab: "+ Add a Ready look
-- while...", opening the condition pick; added(i): the new look's place.
function ET.AddLookLine(ed, which, T, pg, relay, added)
    local B = { pairs = {}, adv = {} }
    local nm = ed:CreateFontString(nil, "OVERLAY")
    nm:SetFont(AT.FONT, 12, "")
    nm:SetText("")
    B.name = nm
    local btn = AT.MakeQuietButton(ed, "+", 120)
    local function Paint()
        local p = T.lookPick
        local hot = btn._hot or (p ~= nil and p:IsShown() and p._owner == btn)
        if hot then btn:SetBackdropColor(COL.btnHover[1], COL.btnHover[2], COL.btnHover[3], 1)
        else btn:SetBackdropColor(0, 0, 0, 0) end
        local e = hot and GREEN or GREEN_EDGE
        btn:SetBackdropBorderColor(e[1], e[2], e[3], 1)
        btn.fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    end
    btn._adPaint = Paint
    btn:SetScript("OnEnter", function() btn._hot = true Paint() end)
    btn:SetScript("OnLeave", function() btn._hot = nil Paint() end)
    btn:SetScript("OnClick", function()
        local p = ET.LookPick(T)
        if p:IsShown() and p._owner == btn then
            AT.CloseDropdown()
            return
        end
        AT.CloseDropdown()
        p:Open(btn, function(key)
            local r, st = which()
            if r and st and ET.LookCanAdd(r, st) then
                LookAdd(r, st, key)
                added(#LooksOf(r, st))
            end
            relay()
        end, pg)
        Paint()
    end)
    Tip(btn, function()
            local r, st = which()
            if not (r and st) then return Tr("Own look") end
            return (ET.AddLookWords(r, st):gsub("^%+%s*", ""))
        end,
        function() return Tr("It starts as this state's look. When several hold, the top one wins.") end)
    local P = { label = nm, words = "", ctrl = btn, adv = false, noMark = true }
    P.shows = function()
        local r, st = which()
        return r ~= nil and st ~= nil and ET.LookCanAdd(r, st)
    end
    P.sync = function()
        local r, st = which()
        if not (r and st) then return end
        btn.fs:SetText(ET.AddLookWords(r, st))
        btn:SetWidth(Measure(btn.fs) + 20)
        Paint()
    end
    P.width = function() return btn:GetWidth() or 0 end
    -- a panel too narrow for it: the words without the state (the panel names it)
    P.fit = function()
        btn.fs:SetText(Tr("+ Add a look while..."))
        btn:SetWidth(Measure(btn.fs) + 20)
        return P.width()
    end
    P.place = function(x, y)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", ed, "TOPLEFT", x, y)
    end
    P.show = function(on) btn:SetShown(on) end
    P.dim = function() end
    B.pairs[1] = P
    function B:Hide()
        nm:Hide()
        btn:Hide()
        local p = T.lookPick
        if p and p:IsShown() and p._owner == btn then AT.CloseDropdown() end
    end
    return B, { section = "states", fields = {}, addLook = true }
end

-- The green + right after a state's name and the pick it opens; a pick adds
-- a look that starts as the state's look. Only a state with a column a look
-- can set shows one; made on first show. erow: the state's editor row, the
-- first look's row goes after it.
local function LookSlot(pg, T, ctx, vis, kind, st, srow, erow)
    local slot = { kind = kind, st = st, srow = srow, last = erow, rows = {} }
    T.slots[#T.slots + 1] = slot
    srow._adLookSlot = slot
    local function CanAdd(r)
        return r ~= nil and r.kind == kind and ET.LookCanAdd(r, st)
    end
    -- the room the + takes after the name, for the table's first column
    srow._adPlusW = function()
        return CanAdd(ctx()) and (PLUS_GAP + PLUS_W) or 0
    end
    local row = srow
    local btn
    local function Build()
        btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetSize(PLUS_W, PLUS_W)
        btn:SetPoint("LEFT", row._adLabel, "RIGHT", PLUS_GAP, 0)
        AT.Skin(btn, COL.btn, GREEN)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 15, "")
        fs:SetPoint("CENTER", 0, 1)
        fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        fs:SetText("+")
        btn.fs = fs
        -- a bare + at rest; boxed under the mouse or while its pick is open
        function btn._adPaint()
            local p = T.lookPick
            local hot = btn._hot or (p ~= nil and p:IsShown() and p._owner == btn)
            btn:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], hot and 1 or 0)
            btn:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], hot and 1 or 0)
        end
        btn:SetScript("OnEnter", function() btn._hot = true btn._adPaint() end)
        btn:SetScript("OnLeave", function() btn._hot = nil btn._adPaint() end)
        btn:SetScript("OnClick", function()
            local p = ET.LookPick(T)
            if p:IsShown() and p._owner == btn then
                AT.CloseDropdown()
                return
            end
            AT.CloseDropdown()
            p:Open(btn, function(key)
                local r = ctx()
                if r and r.kind == kind and LooksOn(r) then LookAdd(r, st, key) end
                AT.LayoutPage(pg)
            end, pg)
            btn._adPaint()
        end)
        -- its title: the add words without their +, as the + is the button
        Tip(btn, function()
                local r = ctx()
                if not r then return Tr("Own look") end
                return (ET.AddLookWords(r, st):gsub("^%+%s*", ""))
            end,
            function() return Tr("It starts as this state's look. When several hold, the top one wins.") end)
        btn._adPaint()
        row._adLookPlus = btn
        row:HookScript("OnHide", function()
            local p = T.lookPick
            if p and p:IsShown() and p._owner == btn then AT.CloseDropdown() end
        end)
    end
    local base = row._sync
    row._sync = function()
        if base then base() end
        local on = T.c1 ~= nil and CanAdd(ctx())
        if on and not btn then Build() end
        if btn then
            btn:SetShown(on)
            if not on and T.lookPick and T.lookPick:IsShown() and T.lookPick._owner == btn then
                AT.CloseDropdown()
            end
        end
    end
    return slot
end

-- Where one icon with its own looks takes them from once it follows again:
-- "layout" or "defaults" while that holds looks, else nil.
function ET.LookFollowFrom(r)
    local OL = NS.OwnLooks
    if not (r and not r._adMulti and not r._adDefaults and LooksOn(r) and OL.Effective and OL.Follow) then
        return nil
    end
    local _, src = OL.Effective(r)
    if src ~= "own" or not Store.InheritedOwnLooks then return nil end
    local list, from = Store.InheritedOwnLooks(r)
    return (type(list) == "table" and #list > 0) and from or nil
end

-- The table: a header row, then one row per state of the record's kind, each
-- with its editor row under it. It joins the section open on pg and spans
-- its width; vis gates the whole table. owner: the window a dropdown opens over.
function ET.StateTable(pg, ctx, vis, owner)
    local T = { rows = {}, editors = {}, owner = owner, slots = {} }
    -- what an own look's row needs to join the table later
    T.pg, T.sec, T.ctx, T.vis = pg, pg._curSection, ctx, vis
    -- Rows for the record's own looks, made before they show: the head runs
    -- first in its section, so a layout pass sees them.
    function T.GrowLooks(r)
        if not LooksOn(r) then return end
        for _, slot in ipairs(T.slots) do
            if slot.kind == r.kind then
                local n = #LooksOf(r, slot.st)
                while #slot.rows < n do
                    slot.rows[#slot.rows + 1] = LookRow(T, slot, #slot.rows + 1)
                end
            end
        end
    end
    local head = AT.AddRow(pg, 36, function()
        local on = vis() and ET.StatesFor(ctx()) ~= nil
        -- the search walks rows without a layout pass
        if on and Indexing() then T.GrowLooks(ctx()) end
        return on
    end)
    head._adStateHead = T
    local frame = TableEdges(head, true)
    local heads = {}
    for i, text in ipairs({ "State", "Opacity", "Grey out", "Tint" }) do
        local fs = head:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 10, "")
        fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(Upper(Tr(text)))
        heads[i] = fs
    end
    -- an effect column's head: its glyph over its word
    local fxHeads = {}
    for _, fk in ipairs(ET.FX_ORDER) do
        local g = ET.Glyph(head, fk)
        g:SetColor(COL.faint)
        local fs = head:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 10, "")
        fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        fs:SetWordWrap(false)
        fs:SetText(Upper(Tr(ET.FX_WORD[fk])))
        fxHeads[fk] = { glyph = g, fs = fs }
    end
    T.heads, T.fxHeads = heads, fxHeads
    -- The columns, measured from the rows the record shows: the header runs
    -- first in its section, so every row after it reads these. An effect
    -- column shows while a row has that effect.
    head._sync = function()
        local r = ctx()
        if r then T.GrowLooks(r) end
        local lw = Measure(heads[1])
        local hasOn, hasClock = false, false
        local has = {}
        for _, row in ipairs(T.rows) do
            if row._visibleFn() then
                -- a name with its + after it
                lw = math.max(lw, Measure(row._adLabel) + (row._adPlusW and row._adPlusW() or 0))
                local a = row._adStateRow.alpha
                if a and a.on then hasOn = true end
                -- a clock after the opacity widens the column by itself and a gap
                local tm = row._adStateRow.timed
                if tm and r and tm.ok(r) == true and Applies(r, tm[1], tm.on) then hasClock = true end
                if r then
                    for _, f in ipairs(ET.FxFor(r, row._adStateRow)) do has[f.kind] = true end
                end
            end
        end
        -- an own look's name starts further in than its state's
        local anyLook = false
        for _, slot in ipairs(r and T.slots or {}) do
            if slot.kind == r.kind then
                for _, lr in ipairs(slot.rows) do
                    if lr._visibleFn() then
                        anyLook = true
                        lw = math.max(lw, LOOK_X - 14 + lr._adNameW())
                    end
                end
            end
        end
        if not r then return end
        local w1 = math.max((hasOn and 24 or 0) + SLIDER_W + AT.SLIDER_TRAIL + (hasClock and (6 + 40) or 0),
            Measure(heads[2]))
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
        -- a look's arrows and x after the effect columns
        T.ctlX = T.w - 10
        if anyLook then T.w = math.max(T.w, T.ctlX + CTL_W + 12) end
        -- Follow defaults at the head's right end, clear of the effect heads
        local from = ET.LookFollowFrom(r)
        if from then
            local b = T.Follow()
            b._adFrom = from
            b.fs:SetText(from == "layout" and Tr("Follow layout") or Tr("Follow defaults"))
            b:SetWidth(math.max(104, Measure(b.fs) + 16))
            T.w = math.max(T.w, x + 12 + b:GetWidth() + 10)
        end
        -- the box spans the section (the next pass, once the width is known)
        local rw = head:GetWidth() or 0
        if rw <= 60 then pg._sizeUnresolved = true end
        T.full = math.max(T.w, rw - 2)
        local hx = { 14, T.c1, T.c2, T.c3 }
        for i = 1, 4 do
            heads[i]:ClearAllPoints()
            heads[i]:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", hx[i], 6)
        end
        if T.follow then
            T.follow:ClearAllPoints()
            T.follow:SetPoint("RIGHT", head, "LEFT", T.full - 10, 0)
            T.follow:SetShown(from ~= nil)
        end
        frame(T.full)
    end
    T.head = head
    -- made on first need, so a table without own looks draws as it did
    function T.Follow()
        if T.follow then return T.follow end
        local b = AT.MakeQuietButton(head, "Follow defaults", 104)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r, OL = ctx(), NS.OwnLooks
            if r and OL and OL.Follow and ET.LookFollowFrom(r) then OL.Follow(r) end
            AT.LayoutPage(pg)
        end)
        Tip(b, function() return b._adFrom == "layout" and Tr("Follow layout") or Tr("Follow defaults") end,
            function()
                return b._adFrom == "layout" and Tr("Drops this icon's own looks, so it takes the ones its layout sets.")
                    or Tr("Drops this icon's own looks, so it takes the ones its defaults set.")
            end)
        T.follow = b
        return b
    end
    for _, kind in ipairs(Schema.ICON_KINDS) do
        for _, st in ipairs(ET.STATES[kind] or {}) do
            Options.BuildYield()
            local srow = StateRow(pg, T, ctx, vis, kind, st, owner)
            Options.BuildYield()
            local erow = EditorRow(pg, T, ctx, vis, kind, st, owner, srow)
            T.editors[#T.editors + 1] = erow
            LookSlot(pg, T, ctx, vis, kind, st, srow, erow)
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
local ICON_STATE_SUB = { Proc = { "Effects" }, Warning = { "Effects" },
    Pulse = { "Appearance", "Icon" }, ["Aura Swipe"] = { "Appearance", "Swipe" } }
-- the tabs Effects took in (Conditions, and the ones Conditions had taken
-- in): no sub-tabs, everything sits under its trigger; the fade rules' old
-- places open on the WHILE trigger (a third value: the Effects pick)
local ICON_TO_EFFECTS = { Conditions = true, ["Show & Hide"] = true, Glows = true, Sounds = true, Alerts = true }
local ICON_SUB = {
    Appearance = { Size = { "Appearance", "Icon" }, Look = { "Appearance", "Icon" },
        Visibility = { "Effects", nil, "while" } },
    Position = { Mouse = { "Position", "Position" } },
    Text = { ["Duration Text"] = { "Text", "Duration" }, ["Stack & Charges"] = { "Text", "Stacks" },
        ["Ammo Stack Text"] = { "Text", "Stacks" }, Keybind = { "Text", "Custom Text & Keybind" },
        ["Label 1"] = { "Text", "Custom Text & Keybind" }, ["Label 2"] = { "Text", "Custom Text & Keybind" },
        ["Label 3"] = { "Text", "Custom Text & Keybind" },
        ["Labels & Keybind"] = { "Text", "Custom Text & Keybind" } },
}
-- a bar tab that went away: its rows' new tab and sub-tab (true: the same sub-tab)
ET.BAR_TAB_HOME = { Thresholds = { "Appearance", "Fill & Colors" }, ["Color Changes"] = { "Appearance", "Fill & Colors" },
    Behavior = { "Conditions", "By State" }, ["Show & Hide"] = { "Conditions", true } }
local BAR_SUB = {
    Appearance = { Style = "Size & Frame", ["Bar Size"] = "Size & Frame", Scale = "Size & Frame",
        Background = "Size & Frame", Border = "Size & Frame", Fill = "Fill & Colors",
        Direction = "Fill & Colors", ["Point Colors"] = "Fill & Colors", Segments = "Fill & Colors",
        ["Cost Preview"] = "Fill & Colors", ["Off-hand"] = "Swing",
        Spark = true, Visibility = { "Conditions", "Fade When" } },
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
            return "Effects", nil
        end
        if tab == "Swipe" then return "Appearance", "Swipe" end
        if ICON_TO_EFFECTS[tab] then return "Effects", nil, sub == "Fade When" and "while" or nil end
        local h = ICON_SUB[tab] and ICON_SUB[tab][sub]
        if h then return h[1], h[2], h[3] end
        return tab, sub
    end
    if fam == "bar" then
        local moved = ET.BAR_TAB_HOME[tab]
        if moved then
            if moved[2] == true then return moved[1], sub end
            return moved[1], moved[2]
        end
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
        local nt, ns, pick = ET.Home(fam, t, secs[t], rec)
        if nt ~= t then
            secs[t] = nil
            ui[tabKey] = nt
            if ns then secs[nt] = ns end
            -- the open tab's old Fade When opens on the fade rules
            local EF = Options.EffectsTab
            if pick and rec and EF then EF.Pick(rec, pick) end
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
    icon = { Effects = "tab:effects" },
    iconSub = { ["Custom Text & Keybind"] = "sub:labelskeybind" },
    -- the bars' Conditions tab was Show & Hide: a rename keeps its mark's id
    bar = { Conditions = "bar:showhide" },
    barSub = { ["Size & Frame"] = "sub:sizeframe", ["Fill & Colors"] = "sub:fillcolors", Glows = "sub:barglows" },
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
