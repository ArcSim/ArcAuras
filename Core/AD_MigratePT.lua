-- AD_MigratePT: copies what a player picks from their ArcUI ProcTracker setup into
-- Arc Auras: each tracker's icon and deck bar, and the Power Infusion icon, into a
-- new "ProcTracker" layout with the same places, sizes, texts, colors and sounds.
-- ProcTracker's save is only read, never changed. Retail only; the window that
-- picks the parts is UI\AD_ImportPTOptions.lua.
local ADDON, NS = ...
if NS.IsForever == true then return end

local MP = {}
NS.MigratePT = MP

MP.ADDON = "ArcUI_ProcTracker"
MP.TRACKERS = { "dw", "tempest", "stormunleashed", "elemtempest", "dre", "restodre", "soulburst", "ng" }
-- the decks with a chance and a violation count (custom texts 2 and 3)
MP.HAS_CHANCE = { dw = true, tempest = true, stormunleashed = true, elemtempest = true, dre = true }
MP.HAS_VIOL = { dw = true, tempest = true, stormunleashed = true, dre = true }
-- counters, not decks: their texts are the tracker's own words
MP.COUNTER = { restodre = true, soulburst = true }
MP.SPEND = { dw = true, tempest = true, stormunleashed = true, dre = true }
-- the decks with ProcTracker's "only show with" switch; its other decks always
-- hide without their talent, so their talent rule always comes over
MP.LOAD_SWITCH = { restodre = true, soulburst = true }

-- ProcTracker's own defaults for every key read here: a save keeps only the
-- keys that existed when it was made.
MP.ICON_D = {
    posX = 0, posY = 180, iconW = 48, iconH = 48, iconScale = 1.0, frameStrata = "HIGH", frameLevel = 5,
    showViolations = false, desaturateEmpty = false, violOffX = 0, violOffY = -20, violSize = 12,
    violR = 1, violG = 0.2, violB = 0.2, deckOffX = 0, deckOffY = 0, deckSize = 19, procOffX = 0, procOffY = 27,
    procSize = 19, countDown = true, procCountDown = true, showDeckText = true, showProcText = true,
    showChanceText = false, deckAnchor = "0", procAnchor = "0", chanceAnchor = "0", violAnchor = "0",
    rdyAlpha = 1.0, rdyDesat = false, rdyTint = false, rdyTintR = 1, rdyTintG = 1, rdyTintB = 1,
    rdyGlow = false, rdyGlowStyle = "pixel", rdyGlowR = 0.95, rdyGlowG = 0.95, rdyGlowB = 0.32,
    rdyGlowPad = 0, rdyGlowX = 0, rdyGlowY = 0, rdyGlowSpeed = 0.25, rdyGlowLines = 8, rdyGlowLength = 0,
    rdyGlowThick = 2, rdyGlowParticles = 4, rdyGlowScale = 1,
    cdAlpha = 1.0, cdDesat = false, cdTint = false, cdTintR = 1, cdTintG = 1, cdTintB = 1,
    cdGlow = false, cdGlowStyle = "pixel", cdGlowR = 0.95, cdGlowG = 0.95, cdGlowB = 0.32,
    cdGlowPad = 0, cdGlowX = 0, cdGlowY = 0, cdGlowSpeed = 0.25, cdGlowLines = 8, cdGlowLength = 0,
    cdGlowThick = 2, cdGlowParticles = 4, cdGlowScale = 1,
    swipeShow = true, swipeR = 0, swipeG = 0, swipeB = 0, swipeA = 0.8, swipeEdge = false,
    swipeNumbers = true, swipeBling = true, swipeReverse = false,
    chanceOffX = 0, chanceOffY = -27, chanceSize = 19, chanceSpend = 10, chanceForecast = "auto",
    chanceDecimals = true, chanceColorMode = "fixed", chanceR = 1.0, chanceG = 1.0, chanceB = 1.0,
    chanceLowPct = 3, chanceHighPct = 10, chanceColdR = 0.6, chanceColdG = 0.6, chanceColdB = 0.6,
    chanceMidR = 1.0, chanceMidG = 0.82, chanceMidB = 0.0, chanceHotR = 0.0, chanceHotG = 1.0, chanceHotB = 0.0,
    procSound = "None", procSoundEnabled = false, procSoundChannel = "Master",
    showDeckSuffix = false, showProcSuffix = false,
    emptyR = 0.0, emptyG = 1.0, emptyB = 0.0, halfR = 1.0, halfG = 0.82, halfB = 0.0,
    fullR = 1.0, fullG = 0.0, fullB = 0.0, deckR = 1.0, deckG = 1.0, deckB = 1.0,
    borderEnabled = true, borderThickness = 1, borderInset = 0, borderUseClass = false,
    borderR = 0.0, borderG = 0.0, borderB = 0.0, borderA = 1.0, textOnly = false, hideOOC = false,
}
-- Nature's Guardian's own (ArcUI_PT_NaturesGuardian.lua iconDefaults)
MP.NG_D = { frameStrata = "MEDIUM", cdDesat = true, swipeEdge = true }
MP.BAR_D = {
    barEnabled = false, barX = 0, barY = 130, barW = 200, barH = 16, barVertical = false, barRotateFill = false,
    barCountDown = true, barStrata = "HIGH", barLevel = 5, barHideOOC = false, barTexture = "Blizzard",
    barFillSingle = false, barFillSingleR = 0.0, barFillSingleG = 0.8, barFillSingleB = 1.0, barFillSingleA = 1.0,
    barEmptyR = 0.0, barEmptyG = 1.0, barEmptyB = 0.0, barEmptyA = 1.0,
    barHalfR = 1.0, barHalfG = 0.82, barHalfB = 0.0, barHalfA = 1.0,
    barFullR = 1.0, barFullG = 0.0, barFullB = 0.0, barFullA = 1.0,
    barBgR = 0.08, barBgG = 0.08, barBgB = 0.08, barBgA = 0.85,
    barBorderEnabled = true, barBorderR = 0.35, barBorderG = 0.35, barBorderB = 0.35, barBorderA = 1.0,
    barBorderThickness = 1, barTickEnabled = true, barTickR = 1.0, barTickG = 1.0, barTickB = 0.0, barTickA = 1.0,
    barTickThickness = 2, barScale = 1.0,
    barDeckTextEnabled = false, barDeckTextAnchor = "CENTER", barDeckTextX = 0, barDeckTextY = 110,
    barDeckTextOffX = 0, barDeckTextOffY = 0, barDeckTextSize = 14,
    barDeckTextR = 1.0, barDeckTextG = 1.0, barDeckTextB = 1.0, barDeckTextA = 1.0, barDeckTextUseStateColor = false,
    barDeckTextEmptyR = 0.0, barDeckTextEmptyG = 1.0, barDeckTextEmptyB = 0.0, barDeckTextEmptyA = 1.0,
    barDeckTextHalfR = 1.0, barDeckTextHalfG = 0.82, barDeckTextHalfB = 0.0, barDeckTextHalfA = 1.0,
    barDeckTextFullR = 1.0, barDeckTextFullG = 0.0, barDeckTextFullB = 0.0, barDeckTextFullA = 1.0,
    barDeckCountDown = true,
    barProcTextEnabled = true, barProcTextAnchor = "TOP", barProcTextX = 0, barProcTextY = 108,
    barProcTextOffX = 0, barProcTextOffY = 2, barProcTextSize = 14,
    barProcTextR = 1.0, barProcTextG = 1.0, barProcTextB = 1.0, barProcTextA = 1.0, barProcTextUseStateColor = true,
    barProcTextEmptyR = 0.0, barProcTextEmptyG = 1.0, barProcTextEmptyB = 0.0, barProcTextEmptyA = 1.0,
    barProcTextHalfR = 1.0, barProcTextHalfG = 0.82, barProcTextHalfB = 0.0, barProcTextHalfA = 1.0,
    barProcTextFullR = 1.0, barProcTextFullG = 0.0, barProcTextFullB = 0.0, barProcTextFullA = 1.0,
    barProcCountDown = true, barProcShowSuffix = false, barDeckShowSuffix = false, barFillReverse = false,
    barTexEmptyR = 0.15, barTexEmptyG = 0.15, barTexEmptyB = 0.15, barTexEmptyA = 0.6, barTexUseEmptyColor = false,
    barIconEnabled = false, barIconAnchor = "LEFT", barIconOffX = 0, barIconOffY = 0, barIconSize = 16,
    barIconBorderEnabled = false, barIconBorderR = 1.0, barIconBorderG = 1.0, barIconBorderB = 1.0,
    barIconBorderA = 1.0, barIconBorderThickness = 1,
}
MP.PI_D = {
    iconEnabled = false, size = 44, posX = 0, posY = -120, strata = "MEDIUM", showSwipe = true,
    showCountdown = true, border = true, borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
    glowEnabled = false, glowStyle = "proc", glowR = 0.95, glowG = 0.95, glowB = 0.32, glowA = 1, glowScale = 1,
    glowLines = 8, glowThickness = 3, glowLength = 11, glowSpeed = 0.25,
    soundEnabled = false, sound = "None", soundChannel = "Master",
}
-- ProcTracker's sound picks by their labels (ArcUI_PT_Sounds.lua S.KITS)
MP.KITS = {
    ["Reveal: Legendary"] = 63971, ["Reveal: Epic Loot"] = 31578, ["Reveal: Azerite"] = 118238,
    ["Reveal: Corrupted"] = 147833, ["Reveal: Warforged"] = 51561, ["Reveal: Bonus Roll"] = 31581,
    ["Reveal: Dig Site"] = 38326, ["Alert: Raid Warning"] = 8959, ["Alert: Ready Check"] = 8960,
    ["Alert: Power Aura"] = 23287, ["Alert: Orb Impact"] = 97597, ["Alert: Invasion"] = 44292,
}
-- the strata Arc Auras offers; higher ones come down to the top it has
MP.STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
-- the bar textures: ProcTracker's built-ins by the Arc Auras one drawing the same file
MP.TEXTURES = { Blizzard = "Blizzard", Otravi = "Blizzard Raid", Aluminium = "Character Skills",
    Solid = "Flat", Minimalist = "Flat" }

function MP.DB()
    local db = rawget(_G, "ArcUI_ProcTrackerDB")
    return type(db) == "table" and db or nil
end

-- installed at all (the card shows), and loaded (its save can be read)
function MP.Installed()
    if MP.DB() then return true end
    local A = C_AddOns
    if A and A.DoesAddOnExist then return A.DoesAddOnExist(MP.ADDON) == true end
    return false
end

function MP.Loaded()
    local A = C_AddOns
    return MP.DB() ~= nil and A ~= nil and A.IsAddOnLoaded ~= nil and A.IsAddOnLoaded(MP.ADDON) == true
end

local function Filled(raw, ...)
    local o = {}
    for i = 1, select("#", ...) do
        for k, v in pairs(select(i, ...) or {}) do o[k] = v end
    end
    for k, v in pairs(raw or {}) do o[k] = v end
    return o
end

function MP.Icon(id, raw) return Filled(raw, MP.ICON_D, id == "ng" and MP.NG_D or nil) end
function MP.Bar(raw) return Filled(raw, MP.BAR_D) end
function MP.PI(raw) return Filled(raw, MP.PI_D) end

-- the bar kind exists in this build
function MP.BarsOK()
    local B = NS.Bars
    return B ~= nil and B.KINDS ~= nil and B.KINDS.special ~= nil
end

-- What can come over: a row per part ProcTracker has settings for. `off`
-- marks one with nothing switched on there: still offered, unticked, and a
-- picked one comes over shown.
function MP.Candidates()
    local db, SP, out = MP.DB(), NS.Special, {}
    if not (db and SP) then return out end
    -- ProcTracker writes some trackers' settings on every class (Nature's
    -- Guardian reads as on everywhere): another class's part is offered unticked
    local _, myClass = UnitClass("player")
    for _, id in ipairs(MP.TRACKERS) do
        local def = SP.Get(id)
        local other = (def and def.class and myClass and def.class ~= myClass) and def.class or nil
        local ic = type(db.icons) == "table" and db.icons[id] or nil
        if def and type(ic) == "table" then
            local t = MP.Icon(id, ic)
            local on = t.deckEnabled ~= false or t.procSoundEnabled == true
            out[#out + 1] = { key = id .. ":icon", tracker = id, part = "icon", name = def.name, off = (not on) or nil,
                other = other }
        end
        local bt = type(db.bars) == "table" and db.bars[id] or nil
        if def and def.bar and type(bt) == "table" and MP.BarsOK() then
            out[#out + 1] = { key = id .. ":bar", tracker = id, part = "bar", name = def.name,
                off = (bt.barEnabled ~= true) or nil, other = other }
        end
    end
    local pi = type(db.powerInfusion) == "table" and db.powerInfusion or nil
    if pi then
        out[#out + 1] = { key = "pi", tracker = "pi", part = "aura", name = "Power Infusion",
            off = (not (pi.iconEnabled == true or pi.soundEnabled == true)) or nil }
    end
    return out
end

-- Something is switched on in ProcTracker (the login offer asks then).
function MP.AnyOn()
    for _, c in ipairs(MP.Candidates()) do
        if not c.off and not c.other then return true end
    end
    return false
end

-- "None" is none; a ProcTracker sound kit label is that kit; any other name is
-- a shared sound name, as both addons register them.
function MP.Sound(name, filesOnly)
    if type(name) ~= "string" or name == "" or name == "None" then return "" end
    local kit = MP.KITS[name]
    if kit then return filesOnly and "" or ("kit:" .. kit) end
    return name
end

-- A text's ProcTracker anchor: "0" its own icon, "cdm:<id>" a Cooldown Manager
-- icon by cooldown ID, "action:<ids>" an action button by spell, a bare number
-- (an older save) a cooldown ID.
function MP.PinOf(spec)
    if spec == nil or spec == 0 or spec == "0" or spec == "" then return "own", "" end
    if type(spec) == "number" then return "cdm", "cd:" .. spec end
    local kind, rest = tostring(spec):match("^(%a+):(.+)$")
    if kind == "cdm" then
        local n = tonumber(rest:match("%d+") or "")
        if n then return "cdm", "cd:" .. n end
    elseif kind == "action" then
        local ids = {}
        for n in rest:gmatch("%d+") do ids[#ids + 1] = n end
        if #ids > 0 then return "action", table.concat(ids, ", ") end
    elseif tonumber(spec) then
        return "cdm", "cd:" .. tonumber(spec)
    end
    return "own", ""
end

-- ProcTracker scales the whole widget; Arc Auras multiplies sizes and draws
-- texts at height / 36, so a text value is value * 36 / icon height.
local function Round(v) return math.floor(v + 0.5) end
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- The icon's centre on screen from UIParent's: ProcTracker's frame is the art
-- plus 4 wide and 14 tall, the art 3 up from its centre, the frame scaled.
local DX = { LEFT = -1, TOPLEFT = -1, BOTTOMLEFT = -1, RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1 }
local DY = { TOP = 1, TOPLEFT = 1, TOPRIGHT = 1, BOTTOM = -1, BOTTOMLEFT = -1, BOTTOMRIGHT = -1 }
function MP.IconPos(t, uw, uh)
    local s = t.iconScale or 1
    local W, H = ((t.iconW or 48) + 4) * s, ((t.iconH or 48) + 14) * s
    local P, RP = t.posPoint or "CENTER", t.posRelPoint or "CENTER"
    local ax = (t.posX or 0) * s + (DX[RP] or 0) * (uw or 0) / 2
    local ay = (t.posY or 0) * s + (DY[RP] or 0) * (uh or 0) / 2
    local cx, cy = ax - (DX[P] or 0) * W / 2, ay - (DY[P] or 0) * H / 2
    return { x = Round(cx), y = Round(cy + 3 * s) }
end

local function Color(r, g, b, a) return { r or 1, g or 1, b or 1, a or 1 } end

local function ClassColor()
    local _, tag = UnitClass("player")
    local c = tag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
    return c and { c.r, c.g, c.b, 1 } or nil
end

local function Strata(s)
    if MP.STRATA[s] then return s end
    if s == "FULLSCREEN" or s == "FULLSCREEN_DIALOG" or s == "TOOLTIP" then return "DIALOG" end
    return nil
end

-- One text's look: size and offsets in the icon's units, its anchor CENTER as
-- ProcTracker's, its font, its pin.
local function TextLook(O, rec, sec, k, pre, suf, size, ox, oy, font, anchor)
    O(sec, pre .. "Size" .. suf, Clamp(Round(size * k), 6, 32))
    O(sec, pre .. "Anchor" .. suf, "CENTER")
    O(sec, pre .. "X" .. suf, Clamp(Round(ox * k), -200, 200))
    O(sec, pre .. "Y" .. suf, Clamp(Round(oy * k), -200, 200))
    if type(font) == "string" and font ~= "" then O(sec, pre .. "Font" .. suf, font) end
    local kind, target = MP.PinOf(anchor)
    if kind ~= "own" then
        O(sec, pre .. "PinTo" .. suf, kind)
        O(sec, pre .. "PinTarget" .. suf, target)
    end
end

-- A state lane's glow (ready or cooldown) from ProcTracker's rdy / cd keys.
local function Glow(O, t, pt, lane)
    if t[pt .. "Glow"] ~= true then return end
    O("states", lane .. "Glow", true)
    O("states", lane .. "GlowType", t[pt .. "GlowStyle"] or "pixel")
    O("states", lane .. "GlowColor", Color(t[pt .. "GlowR"], t[pt .. "GlowG"], t[pt .. "GlowB"], 1))
    O("states", lane .. "GlowSpeed", Clamp(t[pt .. "GlowSpeed"] or 0.25, 0.05, 1))
    O("states", lane .. "GlowLines", Clamp(t[pt .. "GlowLines"] or 8, 1, 16))
    O("states", lane .. "GlowLength", Clamp(t[pt .. "GlowLength"] or 0, 0, 40))
    O("states", lane .. "GlowThickness", Clamp(t[pt .. "GlowThick"] or 2, 1, 20))
    O("states", lane .. "GlowParticles", Clamp(t[pt .. "GlowParticles"] or 4, 1, 16))
    O("states", lane .. "GlowScale", Clamp(t[pt .. "GlowScale"] or 1, 0.5, 2))
    local pad = Clamp(t[pt .. "GlowPad"] or 0, -20, 20)
    if pad ~= 0 then
        O("states", lane .. "GlowXOffset", pad)
        O("states", lane .. "GlowYOffset", pad)
    end
    O("states", lane .. "GlowMoveX", Clamp(t[pt .. "GlowX"] or 0, -20, 20))
    O("states", lane .. "GlowMoveY", Clamp(t[pt .. "GlowY"] or 0, -20, 20))
end

-- Where and how big, the art, the border and out of combat: every icon the
-- import makes from a tracker's icon settings.
local function Place(O, rec, t, uw, uh)
    local s, h = t.iconScale or 1, t.iconH or 48
    rec.pos = MP.IconPos(t, uw, uh)
    O("position", "iconScale", Clamp(s, 0.25, 4))
    O("position", "iconWidth", Clamp(t.iconW or 48, 1, 200))
    O("position", "iconHeight", Clamp(h, 1, 200))
    O("position", "strata", Strata(t.frameStrata))
    O("position", "frameLevel", Clamp(t.frameLevel or 0, 0, 50))
    if t.textOnly == true then O("appearance", "forceHideIcon", true) end
    if t.customIcon then
        local n = tonumber(t.customIcon)
        if n then
            local fromSpell = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(n) ~= nil
            O("appearance", "customIcon", n)
            O("appearance", "customIconFrom", fromSpell and "spell" or "icon")
        end
    end
    -- the border
    O("appearance", "borderEnabled", t.borderEnabled ~= false)
    O("appearance", "borderThickness", Clamp(t.borderThickness or 1, 1, 20))
    O("appearance", "borderInset", Clamp(t.borderInset or 0, -20, 20))
    O("appearance", "borderColor", (t.borderUseClass == true and ClassColor())
        or Color(t.borderR, t.borderG, t.borderB, t.borderA))
    -- hidden out of combat
    if t.hideOOC == true then
        rec.c.fadeWhen = rec.c.fadeWhen or {}
        rec.c.fadeWhen.outOfCombat = true
    end
end

-- The special icon for tracker id, from its ProcTracker icon settings.
function MP.MakeIcon(layoutId, id, raw, uw, uh)
    local SP, Store = NS.Special, NS.Store
    local def = SP and SP.Get(id)
    if not def then return nil end
    local t = MP.Icon(id, raw)
    local drv = { tracker = id }
    if MP.SPEND[id] then drv.chanceSpend = Clamp(t.chanceSpend or 10, 1, 10) end
    if id == "elemtempest" then drv.chanceForecast = t.chanceForecast or "auto" end
    if id == "dw" and t.forceCDM == true then drv.forceCDM = true end
    local rec = Store.NewIcon("special", drv, nil, layoutId, def.name)
    if not rec then return nil end
    local SO = NS.Options and NS.Options.Special
    if SO and SO.ScopeToTracker then SO.ScopeToTracker(rec, def) end
    if MP.SwitchOff(id, t) then MP.DropGate(rec, def) end
    local function O(sec, k, v) if v ~= nil then Store.SetOverride(rec, sec, k, v) end end

    Place(O, rec, t, uw, uh)
    local h = t.iconH or 48
    -- the deck icon greys only where ProcTracker did
    if id ~= "ng" then O("states", "cooldownDesaturate", t.desaturateEmpty == true) end

    local k = 36 / math.max(1, h)
    -- the deck text rides the stack text (Nature's Guardian has no deck)
    if id == "ng" then
        O("text", "stackText", false)
    elseif t.showDeckText == false then
        O("text", "stackText", false)
    else
        if not MP.COUNTER[id] then
            O("special", "stackTemplate", ((t.countDown ~= false) and "{left}" or "{drawn}")
                .. (t.showDeckSuffix == true and "/{size}" or ""))
        end
        TextLook(O, rec, "text", k, "stack", "", t.deckSize or 19, t.deckOffX or 0, t.deckOffY or 0,
            t.deckFont, t.deckAnchor)
        O("text", "stackColor", Color(t.deckR, t.deckG, t.deckB, 1))
    end
    -- the proc count: its own text (slot 4, custom texts 1 to 3 stay free),
    -- colored by procs used
    local l1 = ""
    if t.showProcText ~= false and id ~= "ng" then
        l1 = MP.COUNTER[id] and (def.labels and def.labels[1] or "{count}")
            or (((t.procCountDown ~= false) and "{procsLeft}" or "{procs}") .. (t.showProcSuffix == true and "/{max}" or ""))
    end
    O("label", "labelText4", l1)
    if l1 ~= "" then
        TextLook(O, rec, "label", k, "label", "4", t.procSize or 19, t.procOffX or 0, t.procOffY or 27,
            t.procFont, t.procAnchor)
        O("special", "procEmptyColor", Color(t.emptyR, t.emptyG, t.emptyB, 1))
        O("special", "procHalfColor", Color(t.halfR, t.halfG, t.halfB, 1))
        O("special", "procFullColor", Color(t.fullR, t.fullG, t.fullB, 1))
    end
    -- the chance: its own text (slot 5)
    local l2 = (MP.HAS_CHANCE[id] and t.showChanceText == true) and "{chance}" or ""
    O("label", "labelText5", l2)
    if l2 ~= "" then
        TextLook(O, rec, "label", k, "label", "5", t.chanceSize or 19, t.chanceOffX or 0, t.chanceOffY or -27,
            t.chanceFont, t.chanceAnchor)
        O("label", "labelColor5", Color(t.chanceR, t.chanceG, t.chanceB, 1))
        O("special", "chanceDecimals", t.chanceDecimals ~= false)
        local mode = t.chanceColorMode
        if mode == "procs" or mode == "chance" then O("special", "chanceColorMode", mode) end
        if mode == "chance" then
            O("special", "chanceLowPct", Clamp(t.chanceLowPct or 3, 0, 100))
            O("special", "chanceHighPct", Clamp(t.chanceHighPct or 10, 0, 100))
            O("special", "chanceColdColor", Color(t.chanceColdR, t.chanceColdG, t.chanceColdB, 1))
            O("special", "chanceMidColor", Color(t.chanceMidR, t.chanceMidG, t.chanceMidB, 1))
            O("special", "chanceHotColor", Color(t.chanceHotR, t.chanceHotG, t.chanceHotB, 1))
        elseif mode == "procs" and type(t.chanceCountColors) == "table" and next(t.chanceCountColors) then
            O("special", "chanceLeftCustom", true)
            -- a count left alone there wears ProcTracker's own tint: red at
            -- none left (our default too), gold between, green at a full deck
            local full = def.procs or 1
            for n = 0, 5 do
                local c = t.chanceCountColors[n] or t.chanceCountColors[tostring(n)]
                if type(c) == "table" then
                    O("special", "chanceLeft" .. n .. "Color", Color(c.r or c[1], c.g or c[2], c.b or c[3], 1))
                elseif n >= full then
                    O("special", "chanceLeft" .. n .. "Color", { 0, 1, 0, 1 })
                end
            end
        end
    end
    -- the violation count: its own text (slot 6)
    local l3 = (MP.HAS_VIOL[id] and t.showViolations == true) and "{viol}" or ""
    O("label", "labelText6", l3)
    if l3 ~= "" then
        TextLook(O, rec, "label", k, "label", "6", t.violSize or 12, t.violOffX or 0, t.violOffY or -20,
            t.violFont, t.violAnchor)
        O("label", "labelColor6", Color(t.violR, t.violG, t.violB, 1))
    end
    -- the proc sound
    if t.procSoundEnabled == true then
        O("alerts", "procSoundEnabled", true)
        O("alerts", "procSound", MP.Sound(t.procSound))
    end
    if t.procSoundChannel and t.procSoundChannel ~= "Master" then O("alerts", "soundChannel", t.procSoundChannel) end

    -- Nature's Guardian: a timer's two states, its glows and its swipe
    if id == "ng" then
        O("states", "readyAlpha", Clamp(t.rdyAlpha or 1, 0, 1))
        O("states", "cooldownAlpha", Clamp(t.cdAlpha or 1, 0, 1))
        O("states", "cooldownDesaturate", t.cdDesat == true)
        if t.rdyTint == true then
            O("states", "readyTintEnabled", true)
            O("states", "readyTintColor", Color(t.rdyTintR, t.rdyTintG, t.rdyTintB, 1))
        end
        if t.cdTint == true then
            O("states", "cooldownTintEnabled", true)
            O("states", "cooldownTintColor", Color(t.cdTintR, t.cdTintG, t.cdTintB, 1))
        end
        Glow(O, t, "rdy", "ready")
        Glow(O, t, "cd", "cooldown")
        O("swipe", "showSwipe", t.swipeShow ~= false)
        O("swipe", "swipeColor", Color(t.swipeR, t.swipeG, t.swipeB, t.swipeA or 0.8))
        O("swipe", "showEdge", t.swipeEdge == true)
        O("swipe", "showBling", t.swipeBling ~= false)
        O("swipe", "reverse", t.swipeReverse == true)
        O("text", "durationText", t.swipeNumbers ~= false)
    end
    -- the icon switched off with its sound on: kept, faded out, so it still
    -- sounds. One with both off was picked on purpose: it comes over shown.
    if t.deckEnabled == false and t.procSoundEnabled == true then
        rec.c.fadeWhen = rec.c.fadeWhen or {}
        rec.c.fadeWhen.always = true
    end
    Store.Dirty("load", rec.id)
    return rec
end

-- Nature's Guardian comes over as a Custom Icon: the talent's internal cooldown
-- is a timer the heal's cooldown update starts. A later rule restarts it at the
-- Natural Harmony length on each spec that talent shortens it for, so with the
-- talent the shorter one wins. Enhancement never has it and keeps the base.
function MP.NGRules(def)
    local icd = def and def.icd
    if not (icd and icd.spell and icd.base) then return nil end
    local rules = { { when = "spell_update", spellID = icd.spell, act = "start", mode = "restart", secs = icd.base } }
    local h = icd.harmony
    if h and h.node and h.bySpec then
        local specs = {}
        for spec in pairs(h.bySpec) do specs[#specs + 1] = spec end
        table.sort(specs)
        for _, spec in ipairs(specs) do
            rules[#rules + 1] = { when = "spell_update", spellID = icd.spell, act = "start", mode = "restart",
                secs = icd.base - h.bySpec[spec], talent = h.node, talentEntry = h.entry, spec = spec }
        end
    end
    -- ProcTracker clears it at a raid pull and a key start
    rules[#rules + 1] = { when = "cond_on", cond = "raidEncounter", act = "stop" }
    rules[#rules + 1] = { when = "cond_on", cond = "mythicPlus", act = "stop" }
    return rules
end

function MP.MakeNG(layoutId, raw, uw, uh)
    local SP, Store = NS.Special, NS.Store
    local def = SP and SP.Get("ng")
    local rules = MP.NGRules(def)
    if not rules then return nil end
    local t = MP.Icon("ng", raw)
    local rec = Store.NewIcon("timer", { spellID = def.icd.spell, rules = rules }, nil, layoutId, def.name)
    if not rec then return nil end
    -- the class and the talent as load conditions, as ProcTracker shows it
    local SO = NS.Options and NS.Options.Special
    if SO and SO.ScopeToTracker then SO.ScopeToTracker(rec, def) end
    local function O(sec, k, v) if v ~= nil then Store.SetOverride(rec, sec, k, v) end end
    Place(O, rec, t, uw, uh)
    if not tonumber(t.customIcon) and def.icon then
        -- tried as a spell first, then as a file, as ProcTracker drew it
        local fromSpell = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(def.icon) ~= nil
        O("appearance", "customIcon", def.icon)
        O("appearance", "customIconFrom", fromSpell and "spell" or "icon")
    end
    -- Active is the timer running (the talent on cooldown): ProcTracker's
    -- cooldown look. Not active is its ready look.
    O("states", "readyAlpha", Clamp(t.cdAlpha or 1, 0, 1))
    O("states", "readyDesaturate", t.cdDesat == true)
    if t.cdTint == true then
        O("states", "readyTintEnabled", true)
        O("states", "readyTintColor", Color(t.cdTintR, t.cdTintG, t.cdTintB, 1))
    end
    O("states", "cooldownAlpha", Clamp(t.rdyAlpha or 1, 0, 1))
    O("states", "cooldownDesaturate", t.rdyDesat == true)
    if t.rdyTint == true then
        O("states", "cooldownTintEnabled", true)
        O("states", "cooldownTintColor", Color(t.rdyTintR, t.rdyTintG, t.rdyTintB, 1))
    end
    Glow(O, t, "cd", "ready")
    Glow(O, t, "rdy", "cooldown")
    O("swipe", "showSwipe", t.swipeShow ~= false)
    O("swipe", "swipeColor", Color(t.swipeR, t.swipeG, t.swipeB, t.swipeA or 0.8))
    O("swipe", "showEdge", t.swipeEdge == true)
    O("swipe", "showBling", t.swipeBling ~= false)
    O("swipe", "reverse", t.swipeReverse == true)
    O("text", "durationText", t.swipeNumbers ~= false)
    O("text", "stackText", false)
    Store.Dirty("load", rec.id)
    return rec
end

-- Power Infusion: an aura icon for the buff, shown only while it is up.
function MP.MakePI(layoutId, raw)
    local Store = NS.Store
    local t = MP.PI(raw)
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(10060)) or "Power Infusion"
    local rec = Store.NewIcon("aura", { spellID = 10060, auraType = "buff", unit = "player" }, nil, layoutId, name)
    if not rec then return nil end
    -- any class and spec can receive it, as ProcTracker showed it
    rec.c.specs, rec.c.classes = nil, nil
    local function O(sec, k, v) if v ~= nil then Store.SetOverride(rec, sec, k, v) end end
    O("auraMissing", "showWhileMissing", false)
    rec.pos = { x = Round(t.posX or 0), y = Round(t.posY or -120) }
    local sz = Clamp(t.size or 44, 1, 200)
    O("position", "iconWidth", sz)
    O("position", "iconHeight", sz)
    O("position", "strata", Strata(t.strata))
    O("auraSwipe", "swipeShow", t.showSwipe ~= false)
    O("text", "durationText", t.showCountdown ~= false)
    O("appearance", "borderEnabled", t.border ~= false)
    O("appearance", "borderThickness", Clamp(t.borderSize or 1, 1, 20))
    O("appearance", "borderColor", Color(t.borderR, t.borderG, t.borderB, t.borderA))
    if t.glowEnabled == true then
        local style = t.glowStyle
        if style == "pulse" then style = "flash" end
        O("auraActive", "activeGlow", true)
        O("auraActive", "activeGlowType", style or "proc")
        -- the glow's alpha is its intensity here (the colour carries none)
        O("auraActive", "activeGlowColor", Color(t.glowR, t.glowG, t.glowB, 1))
        O("auraActive", "activeGlowIntensity", Clamp(t.glowA or 1, 0.1, 1))
        O("auraActive", "activeGlowScale", Clamp(t.glowScale or 1, 0.5, 2))
        O("auraActive", "activeGlowLines", Clamp(t.glowLines or 8, 1, 16))
        O("auraActive", "activeGlowThickness", Clamp(t.glowThickness or 3, 1, 20))
        O("auraActive", "activeGlowLength", Clamp(t.glowLength or 11, 0, 40))
        O("auraActive", "activeGlowSpeed", Clamp(t.glowSpeed or 0.25, 0.05, 1))
    end
    -- the game plays an aura's sound from a file, never a kit
    local snd = (t.soundEnabled == true) and MP.Sound(t.sound, true) or ""
    if snd ~= "" then
        O("alerts", "auraGainSoundEnabled", true)
        O("alerts", "auraGainSound", snd)
    end
    if t.soundChannel and t.soundChannel ~= "Master" then O("alerts", "soundChannel", t.soundChannel) end
    if t.iconEnabled ~= true and t.soundEnabled == true then
        -- the sound alone was on: the icon stays out of sight
        rec.c.fadeWhen = rec.c.fadeWhen or {}
        rec.c.fadeWhen.always = true
    end
    Store.Dirty("load", rec.id)
    return rec
end

-- A ProcTracker bar text's centre from the bar's: each text sits in an unscaled
-- 80 x 24 box at its named point (or free on the screen), so its centre is 40
-- or 12 in from that point.
function MP.BarTextOffset(t, anchor, ox, oy, fx, fy)
    local bs = t.barScale or 1
    local W, H = (t.barW or 200) * bs, (t.barH or 16) * bs
    if t.barVertical then W, H = H, W end
    if anchor == "FREE" then
        return Round((fx or 0) - (t.barX or 0) * bs), Round((fy or 0) - (t.barY or 0) * bs)
    end
    local dx, dy = DX[anchor] or 0, DY[anchor] or 0
    return Round(dx * W / 2 + (ox or 0) - dx * 40), Round(dy * H / 2 + (oy or 0) - dy * 12)
end

-- The deck bar's fields from ProcTracker's bar settings (t filled with its defaults).
function MP.MapBar(bar, t, def)
    local Store = NS.Store
    local function O(sec, k, v) if v ~= nil then Store.SetOverride(bar, sec, k, v) end end
    local bs = t.barScale or 1
    bar.pos = { x = Round((t.barX or 0) * bs), y = Round((t.barY or 0) * bs) }
    -- ProcTracker stands a vertical bar by swapping its two sides
    local bw, bh = t.barW or 200, t.barH or 16
    if t.barVertical == true then bw, bh = bh, bw end
    O("size", "width", Clamp(bw, 1, 600))
    O("size", "height", Clamp(bh, 1, 600))
    O("size", "scale", Clamp(bs, 0.25, 4))
    if t.barVertical == true then O("fill", "orientation", "VERTICAL") end
    O("fill", "rotateTexture", t.barRotateFill == true)
    O("fill", "reverseFill", t.barFillReverse == true)
    O("fill", "fillMode", (t.barCountDown ~= false) and "drain" or "fill")
    O("fill", "texture", MP.TEXTURES[t.barTexture] or t.barTexture)
    O("frame", "strata", Strata(t.barStrata))
    O("frame", "level", Clamp(t.barLevel or 5, 1, 100))
    -- the fill: one color, or by procs used
    if t.barFillSingle == true then
        O("deck", "stateFill", false)
        O("fill", "color", Color(t.barFillSingleR, t.barFillSingleG, t.barFillSingleB, t.barFillSingleA))
    else
        O("deck", "emptyColor", Color(t.barEmptyR, t.barEmptyG, t.barEmptyB, t.barEmptyA))
        O("deck", "halfColor", Color(t.barHalfR, t.barHalfG, t.barHalfB, t.barHalfA))
        O("deck", "fullColor", Color(t.barFullR, t.barFullG, t.barFullB, t.barFullA))
    end
    if t.barTexUseEmptyColor == true then
        O("deck", "texEmptyEnabled", true)
        O("deck", "texEmptyColor", Color(t.barTexEmptyR, t.barTexEmptyG, t.barTexEmptyB, t.barTexEmptyA))
    end
    -- background, border, ticks
    O("look", "bgShow", true)
    O("look", "bgColor", Color(t.barBgR, t.barBgG, t.barBgB, 1))
    O("look", "bgAlpha", Clamp(t.barBgA or 0.85, 0, 1))
    O("look", "borderEnabled", t.barBorderEnabled ~= false)
    O("look", "borderColor", Color(t.barBorderR, t.barBorderG, t.barBorderB, t.barBorderA))
    O("look", "borderThickness", Clamp(t.barBorderThickness or 1, 1, 20))
    O("ticks", "ticksShow", t.barTickEnabled ~= false)
    -- a new deck bar starts with its icon and name on; ProcTracker's bar has no name text
    O("icon", "iconShow", t.barIconEnabled == true)
    O("text", "nameShow", false)
    O("ticks", "tickColor", Color(t.barTickR, t.barTickG, t.barTickB, t.barTickA))
    O("ticks", "tickThickness", Clamp(t.barTickThickness or 2, 1, 10))
    -- the two texts: sizes as ProcTracker drew them (bar texts do not scale)
    local counter = MP.COUNTER[def and def.id or ""]
    local function BarText(pre, on, tpl, size, font, anchor, ox, oy, fx, fy, state, c, e, h, f)
        O("deck", pre .. "Show", on == true)
        if on ~= true then return end
        if tpl and not counter then O("deck", pre .. "Template", tpl) end
        O("deck", pre .. "Size", Clamp(math.floor((size or 14) * bs), 6, 64))
        if type(font) == "string" and font ~= "" then O("deck", pre .. "Font", font) end
        O("deck", pre .. "Anchor", "CENTER")
        -- ProcTracker drew every bar text outlined with a black shadow
        O("deck", pre .. "Shadow", true)
        local x, y = MP.BarTextOffset(t, anchor or "CENTER", ox, oy, fx, fy)
        O("deck", pre .. "OffsetX", Clamp(x, -200, 200))
        O("deck", pre .. "OffsetY", Clamp(y, -200, 200))
        O("deck", pre .. "ColorMode", state and "state" or "fixed")
        O("deck", pre .. "Color", c)
        O("deck", pre .. "EmptyColor", e)
        O("deck", pre .. "HalfColor", h)
        O("deck", pre .. "FullColor", f)
    end
    BarText("pos", t.barDeckTextEnabled,
        ((t.barDeckCountDown ~= false) and "{left}" or "{drawn}") .. (t.barDeckShowSuffix == true and "/{size}" or ""),
        t.barDeckTextSize, t.barDeckFont, t.barDeckTextAnchor, t.barDeckTextOffX, t.barDeckTextOffY,
        t.barDeckTextX, t.barDeckTextY, t.barDeckTextUseStateColor == true,
        Color(t.barDeckTextR, t.barDeckTextG, t.barDeckTextB, t.barDeckTextA),
        Color(t.barDeckTextEmptyR, t.barDeckTextEmptyG, t.barDeckTextEmptyB, t.barDeckTextEmptyA),
        Color(t.barDeckTextHalfR, t.barDeckTextHalfG, t.barDeckTextHalfB, t.barDeckTextHalfA),
        Color(t.barDeckTextFullR, t.barDeckTextFullG, t.barDeckTextFullB, t.barDeckTextFullA))
    BarText("proc", t.barProcTextEnabled,
        ((t.barProcCountDown ~= false) and "{procsLeft}" or "{procs}") .. (t.barProcShowSuffix == true and "/{max}" or ""),
        t.barProcTextSize, t.barProcFont, t.barProcTextAnchor, t.barProcTextOffX, t.barProcTextOffY,
        t.barProcTextX, t.barProcTextY, t.barProcTextUseStateColor ~= false,
        Color(t.barProcTextR, t.barProcTextG, t.barProcTextB, t.barProcTextA),
        Color(t.barProcTextEmptyR, t.barProcTextEmptyG, t.barProcTextEmptyB, t.barProcTextEmptyA),
        Color(t.barProcTextHalfR, t.barProcTextHalfG, t.barProcTextHalfB, t.barProcTextHalfA),
        Color(t.barProcTextFullR, t.barProcTextFullG, t.barProcTextFullB, t.barProcTextFullA))
    -- the icon beside the bar: its side, gap and height from where ProcTracker drew it
    if t.barIconEnabled == true then
        local W, H = (t.barW or 200) * bs, (t.barH or 16) * bs
        if t.barVertical then W, H = H, W end
        local S = math.max(4, math.floor((t.barIconSize or 16) * bs)) * bs
        local a = t.barIconAnchor or "LEFT"
        local dx, dy = DX[a] or 0, DY[a] or 0
        local cx = dx * W / 2 + (t.barIconOffX or 0) * bs - dx * S / 2
        local cy = dy * H / 2 + (t.barIconOffY or 0) * bs - dy * S / 2
        local side, gap = "LEFT", -(cx + W / 2 + S / 2)
        if cx > 0 then side, gap = "RIGHT", cx - W / 2 - S / 2 end
        O("icon", "iconShow", true)
        O("icon", "iconSide", side)
        O("icon", "iconSize", Clamp(Round(S), 8, 128))
        -- a gap past the spacing's range (an icon drawn over the bar) moves it
        -- the rest of the way sideways
        local spacing = Clamp(Round(gap), -20, 40)
        local rest = Round(gap) - spacing
        O("icon", "iconSpacing", spacing)
        O("icon", "iconOffsetX", Clamp((side == "LEFT") and -rest or rest, -100, 100))
        O("icon", "iconOffsetY", Clamp(Round(cy), -100, 100))
        if t.barIconFileID then O("icon", "iconOverride", tonumber(t.barIconFileID)) end
        O("icon", "iconBorderEnabled", t.barIconBorderEnabled == true)
        if t.barIconBorderEnabled == true then
            O("icon", "iconBorderColor", Color(t.barIconBorderR, t.barIconBorderG, t.barIconBorderB, t.barIconBorderA))
            O("icon", "iconBorderThickness", Clamp(t.barIconBorderThickness or 1, 1, 10))
        end
    end
    if t.barHideOOC == true then
        bar.c.fadeWhen = bar.c.fadeWhen or {}
        bar.c.fadeWhen.outOfCombat = true
    end
end

-- ProcTracker's "only show with" switch turned off on a deck that has one
-- (its icon settings carry it for the deck's bar too).
function MP.SwitchOff(id, iconRaw)
    return MP.LOAD_SWITCH[id] == true and type(iconRaw) == "table" and iconRaw.requireLoad == false
end

-- that switch off: the record gets no talent or set rule
function MP.DropGate(rec, def)
    if def.talentGate and def.talentGate.node then NS.Store.SetTalentState(rec, def.talentGate.node, nil) end
    if NS.Conditions and NS.Conditions.SetSetID then NS.Conditions.SetSetID(rec, nil) end
    -- and a set rule still waiting on item info never lands
    local SO = NS.Options and NS.Options.Special
    if SO and SO.setWait then SO.setWait[rec.id] = nil end
end

-- The deck bar for tracker id (Bars\AD_SpecialBar.lua), from its ProcTracker
-- bar settings; MP.MapBar fills it. iconRaw: the deck's icon settings, for
-- the "only show with" switch.
function MP.MakeBar(layoutId, id, raw, iconRaw)
    if not MP.BarsOK() then return nil end
    local SP, Store = NS.Special, NS.Store
    local def = SP and SP.Get(id)
    if not def then return nil end
    -- ProcTracker's "Use CDM Detection Instead" is the deck's, so a bar alone keeps it
    local drv = { tracker = id }
    if id == "dw" and type(iconRaw) == "table" and iconRaw.forceCDM == true then drv.forceCDM = true end
    local bar = Store.NewBar(layoutId, "special", drv, def.name)
    if not bar then return nil end
    local SO = NS.Options and NS.Options.Special
    if SO and SO.ScopeToTracker then SO.ScopeToTracker(bar, def) end
    if MP.SwitchOff(id, iconRaw) then MP.DropGate(bar, def) end
    if MP.MapBar then MP.MapBar(bar, MP.Bar(raw), def) end
    Store.Dirty("load", bar.id)
    return bar
end

-- A free layout name: "ProcTracker", then "ProcTracker 2" and on.
function MP.LayoutName()
    local Store, used = NS.Store, {}
    for _, L in ipairs(Store.Layouts and Store.Layouts() or {}) do used[L.name or ""] = true end
    if not used.ProcTracker then return "ProcTracker" end
    local n = 2
    while used["ProcTracker " .. n] do n = n + 1 end
    return "ProcTracker " .. n
end

-- Imports the picked parts ({ [key] = true }, keys from MP.Candidates) into a
-- new layout centred on the screen. Returns { layoutId, icons, bars } or nil
-- and the reason.
function MP.Import(picks)
    if InCombatLockdown() then return nil, "Not in combat." end
    local db = MP.DB()
    if not db then return nil, "ArcUI ProcTracker's settings are not loaded: turn it on and reload first." end
    local list = {}
    for _, c in ipairs(MP.Candidates()) do
        if picks and picks[c.key] then list[#list + 1] = c end
    end
    if #list == 0 then return nil, "Tick what should come over first." end
    local Store = NS.Store
    local L = Store.NewLayout(MP.LayoutName())
    if not L then return nil, "The layout could not be made." end
    local uw = UIParent and UIParent:GetWidth() or 0
    local uh = UIParent and UIParent:GetHeight() or 0
    local res = { layoutId = L.id, icons = 0, bars = 0 }
    local made = {}
    for _, c in ipairs(list) do
        local rec
        if c.part == "icon" then
            if c.tracker == "ng" then
                rec = MP.MakeNG(L.id, db.icons.ng, uw, uh)
            else
                rec = MP.MakeIcon(L.id, c.tracker, db.icons[c.tracker], uw, uh)
            end
            if rec then res.icons = res.icons + 1 end
        elseif c.part == "bar" then
            rec = MP.MakeBar(L.id, c.tracker, db.bars[c.tracker], db.icons and db.icons[c.tracker])
            if rec then res.bars = res.bars + 1 end
        elseif c.part == "aura" then
            rec = MP.MakePI(L.id, db.powerInfusion)
            if rec then res.icons = res.icons + 1 end
        end
        if rec then made[#made + 1] = c end
    end
    -- off in ArcUI ProcTracker once every part has read its settings
    for _, c in ipairs(made) do MP.SwitchOffInPT(c) end
    -- its Safe Mythic+ Reset choice (on unless the player turned it off)
    local SP = NS.Special
    if db.safeMPlusReset ~= nil and SP and SP.SetSafeMPlusReset then SP.SetSafeMPlusReset(db.safeMPlusReset == true) end
    Store.Dirty("tree")
    return res
end

-- An imported part is switched off in ArcUI ProcTracker, so it never shows
-- twice: its own switches in its save (read back at its next load), and at
-- once through its own appliers where it has them (icons and bars).
function MP.SwitchOffInPT(c)
    local db = MP.DB()
    if not (db and c) then return end
    local t
    if c.part == "icon" then
        t = type(db.icons) == "table" and db.icons[c.tracker] or nil
        if type(t) ~= "table" then return end
        t.deckEnabled, t.procSoundEnabled = false, false
    elseif c.part == "bar" then
        t = type(db.bars) == "table" and db.bars[c.tracker] or nil
        if type(t) ~= "table" then return end
        t.barEnabled = false
    elseif c.part == "aura" then
        t = type(db.powerInfusion) == "table" and db.powerInfusion or nil
        if type(t) ~= "table" then return end
        t.iconEnabled, t.soundEnabled = false, false
        return
    end
    local PT = rawget(_G, "ArcUI_PT")
    if type(PT) ~= "table" or type(PT.ForEachDeck) ~= "function" then return end
    PT.ForEachDeck(function(entry)
        if type(entry) ~= "table" or entry.id ~= c.tracker then return end
        if c.part == "icon" and entry.widget then entry.widget:Hide() end
        if c.part == "bar" and type(PT.ApplyBarVisibility) == "function" then PT.ApplyBarVisibility(entry) end
        if type(PT.RefreshDeckDemand) == "function" then PT.RefreshDeckDemand(entry.id) end
    end)
end
