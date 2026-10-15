-- AD_ImportArcUI: reads an installed Arc UI v1 setup and copies it into Arc Auras records.
-- It owns the v1 field matrix, Plan (v1 data in, record plans out, no game reads) and
-- Apply (writes through the Store); the New Layout page's card calls both.
-- Retail only, and read-only on v1: the v1 saved data is never written, and a stamp on
-- the store keeps a second run from duplicating anything.
local ADDON, NS = ...

local IA = NS.ImportArcUI or {}
NS.ImportArcUI = IA

-- the picker's words in the player's language; English where the theme is not loaded
local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end

IA.STAMP = "ArcUI v1"

-- Class file tags by class id, as GetClassInfo answers them; the game's answer wins
-- in play (opts.classTag), this table serves the offline dry run.
IA.CLASS_TAGS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
-- Spec ids in the game's index order per class, the dry run's stand-in for
-- GetSpecializationInfoForClassID; in play the game's answer wins (opts.specID).
IA.SPEC_IDS = {
    [1] = { 71, 72, 73 }, [2] = { 65, 66, 70 }, [3] = { 253, 254, 255 }, [4] = { 259, 260, 261 },
    [5] = { 256, 257, 258 }, [6] = { 250, 251, 252 }, [7] = { 262, 263, 264 }, [8] = { 62, 63, 64 },
    [9] = { 265, 266, 267 }, [10] = { 268, 270, 269 }, [11] = { 102, 103, 104, 105 },
    [12] = { 577, 581, 1480 }, [13] = { 1467, 1468, 1473 },
}

-- v1 hide keys (groups' visibility tables, bars' hideWhen) -> Arc Auras fade conditions.
IA.HIDE_WHEN = {
    hideOOC = "outOfCombat", hideInCombat = "inCombat", hideMounted = "mounted",
    hideInVehicle = "vehicle", hideDead = "dead", hideResting = "resting", hideSolo = "solo",
    hideInGroup = "party", hideInRaid = "raid", hideInInstance = "instance",
    hideInEncounter = "encounter", hideInPetBattle = "petBattle", hidePvP = "pvp",
    hideDragonriding = "skyriding", hideNoTarget = "noTarget", hideHasTarget = "hasTarget",
    hideNotCasting = "notCasting", hideCasting = "casting", hideStealthed = "stealthed",
    hideFlying = "flying", hideSwimming = "swimming", hideAlways = "always",
    hideInCasterForm = "formCaster", hideInCatForm = "formCat", hideInBearForm = "formBear",
    hideInMoonkinForm = "formMoonkin", hideInTravelForm = "formTravel", hideInTreeForm = "formTree",
    hideInBattleStance = "stanceBattle", hideInDefensiveStance = "stanceDefensive",
    hideInBerserkerStance = "stanceBerserker", hideInNoStance = "stanceNone",
    hideInShadowform = "shadowform", hideInNoShadowform = "noShadowform",
    hideOutOfCombat = "outOfCombat",
}
-- v1's oldest visibility strings
IA.LEGACY_VIS = { combat = "outOfCombat", ooc = "inCombat", never = "always" }

IA.PROC_TYPES = { default = "proc", proc = "proc", pixel = "pixel", autocast = "autocast",
    button = "button", ants = "ants", ach_proc = "procloop", cdm_flash = "flash" }
IA.ABBREV = { 0, 120, 300, 600, 3600 }
IA.GLOW_STRATA = { LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
IA.AURA_UNITS = { "player", "target", "focus", "pet", "party1", "party2", "party3", "party4" }
-- v1 secondary resource names -> retail power ids Arc Auras draws
IA.POWERS = { comboPoints = 4, holyPower = 9, chi = 12, runes = 5, soulShards = 7, essence = 19, maelstromWeapon = 101,
    soulFragments = 102, soulFragmentsDevourer = 103,
    arcaneCharges = 16, stagger = 100 }
-- v1's secondary resources by the names its panel gave them (a bar saved without one)
IA.SECONDARY_NAMES = { comboPoints = "Combo Points", holyPower = "Holy Power", chi = "Chi", runes = "Runes",
    soulShards = "Soul Shards", essence = "Essence", arcaneCharges = "Arcane Charges", stagger = "Stagger",
    soulFragments = "Soul Fragments", soulFragmentsDevourer = "Soul Fragments (Devourer)", maelstromWeapon = "Maelstrom Weapon" }
-- an Automatic bar's excluded powers -> the conditions' "Using ..." rows
IA.POWER_ROWS = { [0] = "powerMana", [1] = "powerRage", [3] = "powerEnergy", [8] = "powerAstral" }

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end
IA.Copy = Copy

-- A pause in a long read of Arc UI's save: the options window runs the plan in
-- its sliced loader, which ends the frame here; anywhere else it does nothing.
function IA.Yield()
    local O = NS.Options
    if O and O.BuildYield then O.BuildYield() end
end

-- a v1 colour ({r, g, b, a} named or listed) as the {r, g, b, a} list the schema keeps
-- A v1 colour table ({ r, g, b, a } or a list); a channel an old record left out is 1.
local function Color(c)
    if type(c) ~= "table" then return nil end
    local r, g, b, a = c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4]
    if type(r) ~= "number" and type(g) ~= "number" and type(b) ~= "number" then return nil end
    return { type(r) == "number" and r or 1, type(g) == "number" and g or 1, type(b) == "number" and b or 1,
        type(a) == "number" and a or 1 }
end
IA.Color = Color

-- one value of a nested table by its dot path
local function Leaf(t, path)
    local cur = t
    for part in path:gmatch("[^.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
    end
    return cur
end
IA.Leaf = Leaf

-- v1's deep merge: a later layer's values win, tables merge field by field
function IA.Merge(...)
    local out = {}
    for i = 1, select("#", ...) do
        local src = select(i, ...)
        if type(src) == "table" then
            for k, v in pairs(src) do
                if type(v) == "table" and not Color(v) and type(out[k]) == "table" then
                    out[k] = IA.Merge(out[k], v)
                else
                    out[k] = Copy(v)
                end
            end
        end
    end
    return out
end

-- The converters a matrix row names. Each returns the Arc Auras value, or nil and
-- a reason when the v1 value has no home.
IA.CONV = {
    color = function(v) return Color(v) end,
    proc = function(v) return IA.PROC_TYPES[v] or "proc" end,
    outline = function(v)
        if v == "" or v == "NONE" then return "NONE" end
        if v == "THICKOUTLINE" then return "THICKOUTLINE" end
        return "OUTLINE"
    end,
    abbrev = function(v)
        v = tonumber(v) or 0
        local best, gap = 0, nil
        for _, c in ipairs(IA.ABBREV) do
            local d = math.abs(c - v)
            if not gap or d < gap then best, gap = c, d end
        end
        return best
    end,
    ["not"] = function(v) return not v end,
    -- a bar text's anchor; FREE (a dragged text) is placed by the freeText special instead
    barAnchor = function(v) if v == "FREE" then return nil end return v end,
    dec = function(v) return (tonumber(v) or 0) > 0 end,
    strata = function(v) return IA.GLOW_STRATA[v] and v or "inherit" end,
    -- the game's own face needs no media name
    font = function(v)
        if type(v) ~= "string" or v == "Friz Quadrata TT" then return "" end
        return v
    end,
    num = function(v) return tonumber(v) end,
    bool = function(v) return v == true end,
    int = function(v)
        v = tonumber(v)
        return v and math.floor(v + 0.5) or nil
    end,
}

-- v1 group record fields -> the iconGroup schema.
IA.GROUP_MAP = {
    gridRows = { "arrangement", "rows", "int" },
    gridCols = { "arrangement", "cols", "int" },
    iconSize = { "arrangement", "iconSize", "int" },
    iconWidth = { "arrangement", "iconWidth", "int" },
    iconHeight = { "arrangement", "iconHeight", "int" },
    spacing = { "arrangement", "spacing", "int" },
    spacingX = { special = "spacing" },
    spacingY = { special = "spacing" },
    separateSpacing = { special = "spacing" },
    alignment = { special = "alignment" },
    horizontalGrowth = { "arrangement", "growthH" },
    verticalGrowth = { "arrangement", "growthV" },
    lockGridSize = { "arrangement", "lockGridSize", "bool" },
    containerPadding = { special = "padding" },
    dynamicLayout = { special = "dynamicAuras" },
    dynamicCooldowns = { special = "collapse" },
    dynamicOrderMode = { "arrangement", "dynamicOrder" },
    dynamicContainerSize = { "arrangement", "dynamicShrink", "bool" },
    smoothMovement = { "arrangement", "smoothMovement", "bool" },
    smoothMoveDuration = { "arrangement", "smoothDuration", "num" },
    autoReflow = { special = "reflow" },
    showBorder = { "look", "showBorder", "bool" },
    showBackground = { "look", "showBackground", "bool" },
    borderColor = { "look", "borderColor", "color" },
    bgColor = { "look", "bgColor", "color" },
    frameStrata = { "frame", "strata" },
    frameLevel = { "frame", "level", "int" },
    visibility = { special = "visibility" },
    visibilityLogic = { special = "visibility" },
    hiddenAlpha = { special = "visibility" },
    anchor = { special = "anchor" },
    position = { special = "position" },
    groupType = { special = "kind" },
    auraLayout = { gap = "aura groups always continue the row; no debuff row option" },
    id = { special = "identity" },
    enabled = { special = "identity" },
    layout = { special = "identity" },
    members = { special = "identity" },
    grid = { special = "identity" },
    ["layout.gridRows"] = { "arrangement", "rows", "int" },
    ["layout.gridCols"] = { "arrangement", "cols", "int" },
    ["layout.iconSize"] = { "arrangement", "iconSize", "int" },
    ["layout.iconWidth"] = { "arrangement", "iconWidth", "int" },
    ["layout.iconHeight"] = { "arrangement", "iconHeight", "int" },
    ["layout.spacing"] = { "arrangement", "spacing", "int" },
    ["layout.direction"] = { gap = "the oldest group records' direction; the grid growth fields replaced it" },
    ["layout.perRow"] = { gap = "the oldest group records' perRow; gridCols replaced it" },
}

-- The bar matrix (shared by aura, cooldown, charge, resource and cast bars); a row
-- whose section the bar's kind lacks is dropped by the schema at Apply.
IA.BAR_MAP = {
    ["display.width"] = { "size", "width", "int" },
    ["display.height"] = { "size", "height", "int" },
    ["display.barScale"] = { "size", "scale", "num" },
    ["display.opacity"] = { "size", "opacity", "num" },
    ["display.barColor"] = { "fill", "color", "color" },
    ["display.texture"] = { "fill", "texture" },
    ["display.barOrientation"] = { special = "orientation" },
    ["display.barReverseFill"] = { "fill", "reverseFill", "bool" },
    ["display.durationBarFillMode"] = { "fill", "fillMode" },
    ["display.enableSmoothing"] = { "fill", "smoothing", "bool" },
    ["display.useGradient"] = { "fill", "useGradient", "bool" },
    ["display.gradientDirection"] = { "fill", "gradientDir" },
    ["display.gradientSecondColor"] = { special = "gradient" },
    ["display.rotateTexture"] = { "fill", "rotateTexture", "bool" },
    ["display.showBackground"] = { "look", "bgShow", "bool" },
    ["display.backgroundColor"] = { special = "bgColor" },
    ["display.backgroundTexture"] = { "look", "bgTexture" },
    ["display.showBorder"] = { "look", "borderEnabled", "bool" },
    ["display.borderColor"] = { "look", "borderColor", "color" },
    ["display.drawnBorderThickness"] = { "look", "borderThickness", "int" },
    ["display.useClassColorBorder"] = { "look", "useClassColorBorder", "bool" },
    ["display.showTickMarks"] = { "ticks", "ticksShow", "bool" },
    ["display.tickMode"] = { special = "tickMode" },
    ["display.tickPercent"] = { "ticks", "tickPercent", "int" },
    ["display.tickColor"] = { "ticks", "tickColor", "color" },
    ["display.tickThickness"] = { "ticks", "tickThickness", "int" },
    ["display.tickHeightPercent"] = { "ticks", "tickHeight", "int" },
    ["display.tickHeightAnchor"] = { "ticks", "tickHeightAnchor" },
    ["display.showText"] = { "text", "stkShow", "bool" },
    ["display.font"] = { "text", "font", "font" },
    ["display.fontSize"] = { "text", "stkSize", "int" },
    ["display.textColor"] = { "text", "stkColor", "color" },
    ["display.textOutline"] = { "text", "stkOutline", "outline" },
    ["display.textShadow"] = { "text", "stkShadow", "bool" },
    ["display.textAnchor"] = { "text", "stkAnchor", "barAnchor" },
    ["display.textAnchorOffsetX"] = { "text", "stkOffsetX", "int" },
    ["display.textAnchorOffsetY"] = { "text", "stkOffsetY", "int" },
    ["display.textFormat"] = { "text", "resFormat" },
    ["display.showDuration"] = { "text", "durShow", "bool" },
    ["display.durationFontSize"] = { "text", "durSize", "int" },
    ["display.durationColor"] = { "text", "durColor", "color" },
    ["display.durationOutline"] = { "text", "durOutline", "outline" },
    ["display.durationShadow"] = { "text", "durShadow", "bool" },
    ["display.durationAnchor"] = { "text", "durAnchor", "barAnchor" },
    ["display.durationAnchorOffsetX"] = { "text", "durOffsetX", "int" },
    ["display.durationAnchorOffsetY"] = { "text", "durOffsetY", "int" },
    ["display.durationDecimals"] = { "text", "durDecimalsEnabled", "dec" },
    ["display.showName"] = { "text", "nameShow", "bool" },
    ["display.nameFontSize"] = { "text", "nameSize", "int" },
    ["display.nameColor"] = { "text", "nameColor", "color" },
    ["display.nameOutline"] = { "text", "nameOutline", "outline" },
    ["display.nameShadow"] = { "text", "nameShadow", "bool" },
    ["display.nameAnchor"] = { "text", "nameAnchor", "barAnchor" },
    ["display.nameOffsetX"] = { "text", "nameOffsetX", "int" },
    ["display.nameOffsetY"] = { "text", "nameOffsetY", "int" },
    ["display.showBarIcon"] = { "icon", "iconShow", "bool" },
    ["display.barIconSize"] = { "icon", "iconSize", "int" },
    ["display.barIconAnchor"] = { "icon", "iconSide" },
    ["display.barIconShowBorder"] = { "icon", "iconBorderEnabled", "bool" },
    ["display.barIconBorderColor"] = { "icon", "iconBorderColor", "color" },
    ["display.iconOverride"] = { "icon", "iconOverride", "int" },
    ["display.iconOffsetX"] = { "icon", "iconOffsetX", "int" },
    ["display.iconOffsetY"] = { "icon", "iconOffsetY", "int" },
    ["display.barFrameStrata"] = { "frame", "strata" },
    ["display.barFrameLevel"] = { "frame", "level", "int" },
    ["display.barPosition"] = { special = "position" },
    ["display.anchorToGroup"] = { special = "anchor" },
    ["display.anchorGroupName"] = { special = "anchor" },
    ["display.anchorPoint"] = { special = "anchor" },
    ["display.anchorOffsetX"] = { special = "anchor" },
    ["display.anchorOffsetY"] = { special = "anchor" },
    ["display.matchGroupWidth"] = { special = "anchor" },
    ["display.matchWidthAdjust"] = { special = "anchor" },
    ["display.slotSpacing"] = { "segments", "segmentSpacing", "int" },
    ["display.iconSize"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconShowTexture"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconShowStacks"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconShowDuration"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconShowBorder"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconShowCooldownSwipe"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconZoom"] = { gap = "the retired icon display mode", nv = true },
    ["display.durationThreshold2Enabled"] = { special = "thresholds" },
    ["display.durationThreshold2Value"] = { special = "thresholds" },
    ["display.durationThreshold2Color"] = { special = "thresholds" },
    ["display.durationThreshold3Enabled"] = { special = "thresholds" },
    ["display.durationThreshold3Value"] = { special = "thresholds" },
    ["display.durationThreshold3Color"] = { special = "thresholds" },
    ["display.durationThreshold4Enabled"] = { special = "thresholds" },
    ["display.durationThreshold4Value"] = { special = "thresholds" },
    ["display.durationThreshold4Color"] = { special = "thresholds" },
    ["display.durationThresholdAsSeconds"] = { special = "thresholds" },
    ["display.durationThresholdMaxDuration"] = { special = "thresholds" },
    ["display.thresholdMode"] = { special = "style" },
    ["display.enabled"] = { special = "identity" },
    ["behavior.hideWhen"] = { special = "hideWhen" },
    ["behavior.hideLogic"] = { special = "hideWhen" },
    ["behavior.hideWhenAlpha"] = { special = "hideWhen" },
    ["behavior.hideOutOfCombat"] = { special = "hideWhen" },
    ["behavior.hideWhenReady"] = { "behavior", "hideWhenReady", "bool" },
    ["behavior.hideWhenFull"] = { "behavior", "hideWhenFullCharges", "bool" },
    ["behavior.hideWhenFullCharges"] = { "behavior", "hideWhenFullCharges", "bool" },
    ["behavior.hideWhenInactive"] = { "behavior", "hideWhenInactive", "bool" },
    ["behavior.showOnSpecs"] = { special = "specs" },
    ["behavior.showOnSpec"] = { special = "specs" },
    ["behavior.talentConditions"] = { special = "talents" },
    ["behavior.talentMatchMode"] = { special = "talents" },
    ["behavior.hideBuffIcon"] = { special = "hideIcon" },
    ["behavior.hideBlizzardFrame"] = { gap = "the game's own resource frame stays; Arc Auras hides only the cast bar's", nv = true },
    ["behavior.forceShow"] = { gap = "a preview switch, not a setting", nv = true },
    ["tracking"] = { special = "identity" },
    thresholds = { special = "layers" },
    colorRanges = { special = "layers" },
    stackColors = { special = "layers" },
    abilityThresholds = { special = "costTicks" },
    presets = { special = "skins" },
    prediction = { special = "predict" },
    autoPowerProfiles = { special = "looks" },
    _configVersion = { special = "identity" },
    _migrated = { special = "identity" },
    -- the texts' second homes: a free-dragged text, the charge text's own keys, the
    -- duration's and the name's fonts (one font per bar here), the curve colours
    ["display.textPosition"] = { special = "freeText" },
    ["display.durationPosition"] = { special = "freeText" },
    ["display.textLocked"] = { special = "freeText" },
    ["display.textMovable"] = { special = "identity" },
    ["display.barMovable"] = { special = "identity" },
    ["display.chargeTextAnchor"] = { special = "chargeText" },
    ["display.chargeTextOffsetX"] = { special = "chargeText" },
    ["display.chargeTextOffsetY"] = { special = "chargeText" },
    ["display.durationFont"] = { special = "font" },
    ["display.nameFont"] = { special = "font" },
    ["display.durationColorCurveEnabled"] = { special = "thresholds" },
    ["display.durationColorCurveMode"] = { gap = "Arc UI no longer reads it", nv = true },
    ["display.durationColorCurveThreshold"] = { gap = "Arc UI no longer reads it", nv = true },
    ["display.durationColorCurveLowColor"] = { gap = "Arc UI no longer reads it", nv = true },
    ["display.durationColorCurveHighColor"] = { gap = "Arc UI no longer reads it", nv = true },
    ["display.durationColorCurveMidColor"] = { gap = "the curve's middle colour: Arc Auras colours in steps, not a gradient" },
    -- a resource bar's colour bands (IA.ResourceBands)
    ["display.colorCurveEnabled"] = { special = "layers" },
    ["display.colorCurveDirection"] = { special = "layers" },
    ["display.colorCurveDirectionFilling"] = { special = "layers" },
    ["display.colorCurveThreshold2Enabled"] = { special = "layers" },
    ["display.colorCurveThreshold2Value"] = { special = "layers" },
    ["display.colorCurveThreshold2Color"] = { special = "layers" },
    ["display.colorCurveThreshold3Enabled"] = { special = "layers" },
    ["display.colorCurveThreshold3Value"] = { special = "layers" },
    ["display.colorCurveThreshold3Color"] = { special = "layers" },
    ["display.colorCurveThreshold4Enabled"] = { special = "layers" },
    ["display.colorCurveThreshold4Value"] = { special = "layers" },
    ["display.colorCurveThreshold4Color"] = { special = "layers" },
    ["display.colorCurveThreshold5Enabled"] = { special = "layers" },
    ["display.colorCurveThreshold5Value"] = { special = "layers" },
    ["display.colorCurveThreshold5Color"] = { special = "layers" },
    ["display.colorCurveThresholdAsPercent"] = { special = "layers" },
    ["display.colorCurveMaxValue"] = { special = "layers" },
    ["display.thresholdAsPercent"] = { special = "layers" },
    ["display.enableMaxColor"] = { special = "maxColor" },
    ["display.maxColor"] = { special = "maxColor" },
    ["display.fragmentedSpacing"] = { "resource", "pipSpacing", "int" },
    ["display.fragmentedColors"] = { special = "pipColors" },
    ["display.fragmentedChargingColor"] = { special = "recharge" },
    ["display.smartChargingColor"] = { special = "recharge" },
    ["display.fragmentedLayoutDirection"] = { special = "pipLayout" },
    ["display.fragmentedFillOrientation"] = { special = "pipLayout" },
    -- the rune / essence recharge countdown and its older names
    ["display.cdTextShow"] = { special = "rcText" },
    ["display.cdTextSize"] = { special = "rcText" },
    ["display.cdTextOffsetX"] = { special = "rcText" },
    ["display.cdTextOffsetY"] = { special = "rcText" },
    ["display.cdTextOutline"] = { special = "rcText" },
    ["display.cdTextColor"] = { special = "rcText" },
    ["display.cdTextDecimalPrecision"] = { special = "rcText" },
    ["display.cdTextFont"] = { special = "font" },
    ["display.fragmentedShowSegmentText"] = { special = "rcText" },
    ["display.fragmentedTextSize"] = { special = "rcText" },
    ["display.fragmentedTextOffsetX"] = { special = "rcText" },
    ["display.fragmentedTextOffsetY"] = { special = "rcText" },
    ["display.iconsShowCooldownText"] = { special = "rcText" },
    ["display.iconsCooldownTextSize"] = { special = "rcText" },
    ["display.iconsCDTextOffsetX"] = { special = "rcText" },
    ["display.iconsCDTextOffsetY"] = { special = "rcText" },
    ["display.segmentedSpacing"] = { "segments", "segmentSpacing", "int" },
    ["display.iconBarSpacing"] = { "icon", "iconSpacing", "int" },
    ["display.stackShowAtZero"] = { "text", "stkHideAtZero", "not" },
    -- the Ready word, or v1's "0" in its place
    ["display.showReadyText"] = { special = "readyText" },
    ["display.readyText"] = { special = "readyText" },
    ["display.readyColor"] = { special = "readyText" },
    ["display.showZeroWhenReady"] = { special = "readyText" },
    ["display.showMaxText"] = { "text", "stkShowMax", "bool" },
    ["display.customTicksAsPercent"] = { "ticks", "tickAsPercent", "bool" },
    ["display.customTicks"] = { "ticks", "tickValues" },
    ["display.barPadding"] = { "fill", "fillInset", "int" },
    ["display.barPaddingL"] = { special = "padding" },
    ["display.barPaddingR"] = { special = "padding" },
    ["display.barPaddingT"] = { special = "padding" },
    ["display.barPaddingB"] = { special = "padding" },
    ["display.textColorThresholdEnabled"] = { special = "textThresh" },
    ["display.textColorThresholdFill"] = { special = "textThresh" },
    ["display.textColorThresholdBaseColor"] = { special = "textThresh" },
    ["display.textColorThresholdT1Enabled"] = { special = "textThresh" },
    ["display.textColorThresholdT1Value"] = { special = "textThresh" },
    ["display.textColorThresholdT1Color"] = { special = "textThresh" },
    ["display.textColorThresholdT2Enabled"] = { special = "textThresh" },
    ["display.textColorThresholdT2Value"] = { special = "textThresh" },
    ["display.textColorThresholdT2Color"] = { special = "textThresh" },
    ["display.textColorThresholdT3Enabled"] = { special = "textThresh" },
    ["display.textColorThresholdT3Value"] = { special = "textThresh" },
    ["display.textColorThresholdT3Color"] = { special = "textThresh" },
    ["display.textColorThresholdT4Enabled"] = { special = "textThresh" },
    ["display.textColorThresholdT4Value"] = { special = "textThresh" },
    ["display.textColorThresholdT4Color"] = { special = "textThresh" },
    ["display.textShowPercentSymbol"] = { special = "resFormat" },
    ["display.chargedComboColor"] = { special = "charged" },
    ["display.showPrediction"] = { special = "predict" },
    ["display.predCostColor"] = { special = "predict" },
    ["display.useTextureColor"] = { special = "textureColor" },
    ["display.gradientIntensity"] = { special = "gradient" },
    -- a charge bar: its strip, its backgrounds, its own text keys, a full charge's colour
    ["display.slotHeight"] = { special = "chargeSize" },
    ["display.slotOffsetX"] = { special = "chargeBox" },
    ["display.slotOffsetY"] = { special = "chargeBox" },
    ["display.showBarBackground"] = { special = "chargeLook" },
    ["display.barBackgroundColor"] = { special = "chargeLook" },
    ["display.showSlotBackground"] = { special = "chargeLook" },
    ["display.slotBackgroundColor"] = { special = "chargeLook" },
    ["display.slotBackgroundTexture"] = { special = "chargeLook" },
    ["display.useDifferentFullColor"] = { special = "fullCharge" },
    ["display.fullChargeColor"] = { special = "fullCharge" },
    ["display.timerTextAnchor"] = { special = "chargeText" },
    ["display.timerTextOffsetX"] = { special = "chargeText" },
    ["display.timerTextOffsetY"] = { special = "chargeText" },
    ["display.timerTextPosition"] = { special = "freeText" },
    ["display.durationTextPosition"] = { special = "freeText" },
    ["display.nameTextPosition"] = { special = "freeText" },
    ["display.namePosition"] = { special = "freeText" },
    ["display.barIconPosition"] = { special = "iconFree" },
    ["display.textUsableColor"] = { special = "usableText" },
    -- options Arc Auras does not offer yet
    ["display.frameWidth"] = { special = "chargeBox" },
    ["display.frameHeight"] = { special = "chargeBox" },
    ["display.durationThreshold5Enabled"] = { special = "thresholds" },
    ["display.durationThreshold5Value"] = { special = "thresholds" },
    ["display.durationThreshold5Color"] = { special = "thresholds" },
    ["display.dynamicTextOnSlot"] = { gap = "the charge text sits on the bar, not on the recharging charge" },
    ["display.dynamicTextOffsetX"] = { gap = "the charge text sits on the bar, not on the recharging charge" },
    ["display.dynamicTextOffsetY"] = { gap = "the charge text sits on the bar, not on the recharging charge" },
    ["display.showSlotBorder"] = { gap = "charges share the bar's border" },
    ["display.slotBorderColor"] = { gap = "charges share the bar's border" },
    ["display.slotBorderThickness"] = { gap = "charges share the bar's border" },
    ["display.usePerSlotColors"] = { gap = "charges share one colour" },
    ["display.chargeSlot1Color"] = { gap = "charges share one colour" },
    ["display.chargeSlot2Color"] = { gap = "charges share one colour" },
    ["display.chargeSlot3Color"] = { gap = "charges share one colour" },
    ["display.chargeSlot4Color"] = { gap = "charges share one colour" },
    ["display.chargeSlot5Color"] = { gap = "charges share one colour" },
    ["display.textColorByState"] = { gap = "the stack text keeps one colour while the spell is unusable" },
    ["display.textUnusableColor"] = { gap = "the stack text keeps one colour while the spell is unusable" },
    ["display.readyTextAnchor"] = { gap = "the Ready text takes the duration text's place" },
    ["display.readyTextOffsetX"] = { gap = "the Ready text takes the duration text's place" },
    ["display.readyTextOffsetY"] = { gap = "the Ready text takes the duration text's place" },
    ["display.readyTextPosition"] = { gap = "the Ready text takes the duration text's place" },
    ["display.durationTextColorEnabled"] = { gap = "the time text takes the bar's threshold colours, not bands of its own" },
    ["display.matchSlotsOnly"] = { gap = "a matched width spans the group's frame, not only its slots (it comes in centred, as v1 drew it)" },
    ["display.matchIconEdges"] = { gap = "a matched width spans the group's frame" },
    ["display.mirrorStaticTexture"] = { gap = "a Cooldown Manager bar drains only" },
    ["display.predGainColor"] = { gap = "the cast preview shows a cost, not a gain" },
    ["display.predTextFormat"] = { gap = "the text shows the value while casting" },
    ["display.predTextCostColor"] = { gap = "the text shows the value while casting" },
    ["display.predTextGainColor"] = { gap = "the text shows the value while casting" },
    ["display.activeCountColors"] = { special = "litColors" },
    ["display.enableActiveCountColors"] = { special = "litColors" },
    ["display.fragmentedSpecColors"] = { special = "looks" },
    ["display.iconsPositions"] = { gap = "freely placed rune / essence icons come in as a row of pips" },
    -- rune / essence icons in a row are pips
    ["display.iconsMode"] = { special = "pipIcons" },
    ["display.iconsSpacing"] = { special = "pipIcons" },
    ["display.iconsSize"] = { special = "pipIcons" },
    ["display.iconsShape"] = { special = "pipIcons" },
    ["display.foldedColor1"] = { special = "fold" },
    ["display.foldedColor2"] = { special = "fold" },
    -- nothing v1 draws: dead keys, editor state, the retired icon display mode
    ["display.nameTextStrata"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.stackTextStrata"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.durationTextStrata"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.durationTextLevel"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.nameTextLevel"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.stackTextLevel"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.readyTextStrata"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.readyTextLevel"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.tickTrackSegments"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.tickThicknessAnchor"] = { "ticks", "tickThicknessAnchor" },
    ["display.fillTextureScale"] = { gap = "Arc UI reads it and never uses it", nv = true },
    ["display.borderStyle"] = { gap = "Arc UI never draws it", nv = true },
    ["display.durationShowWhenReady"] = { gap = "no Arc UI panel row; always off", nv = true },
    ["display.showDurationWhenReady"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.chargeDisplayMode"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.showBarBorder"] = { gap = "a hidden Arc UI row; the border is the bar's own", nv = true },
    ["display.barBorderColor"] = { gap = "a hidden Arc UI row; the border is the bar's own", nv = true },
    ["display.barBorderThickness"] = { gap = "a hidden Arc UI row; the border is the bar's own", nv = true },
    ["display.durationTextLocked"] = { gap = "editor state", nv = true },
    ["display.durationTextLockedOffset"] = { gap = "editor state", nv = true },
    ["display.nameTextLocked"] = { gap = "editor state", nv = true },
    ["display.nameTextLockedOffset"] = { gap = "editor state", nv = true },
    ["display.stackTextLocked"] = { gap = "editor state", nv = true },
    ["display.readyTextLocked"] = { gap = "editor state", nv = true },
    ["display.durationTextFrameWidth"] = { gap = "a drag box's width; the text sits centred in it", nv = true },
    ["display.nameTextFrameWidth"] = { gap = "a drag box's width; the text sits centred in it", nv = true },
    ["display.stackTextFrameWidth"] = { gap = "a drag box's width; the text sits centred in it", nv = true },
    ["display.chargeTextPosition"] = { gap = "Arc UI offers no free charge text", nv = true },
    ["display.stackHideAtZero"] = { gap = "an aura's stack text shows nothing while the aura is missing", nv = true },
    ["display.stackColors"] = { gap = "nothing in Arc UI reads it here", nv = true },
    ["display.barIconAnchorOffsetX"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.barIconAnchorOffsetY"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.nameAnchorOffsetX"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.nameAnchorOffsetY"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.durationColorCurveMidColor"] = { gap = "Arc UI never draws a middle colour", nv = true },
    ["display.iconsBorderStyle"] = { gap = "Arc UI never reads it", nv = true },
    ["display.iconsCDTextSize"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.iconsLayout"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.iconShape"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.iconSpacing"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.autoPowerColors"] = { special = "looks" },
    ["display.showInForms"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.tickMarkInterval"] = { special = "timerTicks" },
    ["display.autoStackTicks"] = { special = "timerTicks" },
    ["display.iconMultiPositions"] = { gap = "the retired icon display mode", nv = true },
    ["display.displayType"] = { gap = "the retired icon display mode", nv = true },
    ["display.displayMode"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["display.iconPosition"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconBorderColor"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconCooldownDrawBling"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconCooldownDrawEdge"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconCooldownReverse"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconDesaturateOnCooldown"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconDesaturateWhenInactive"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconDurationColor"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconDurationFont"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconDurationFontSize"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconDurationOutline"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconDurationShadow"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackAnchor"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackColor"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackFont"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackFontSize"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackOutline"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackShadow"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackLevel"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackStrata"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackLocked"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconStackPosition"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiMode"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiDirection"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiSpacing"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiFreeMode"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiShowDurationOn"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiDurationAnchor"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiLockPositions"] = { gap = "the retired icon display mode", nv = true },
    ["display.iconMultiShowDesatBg"] = { gap = "the retired icon display mode", nv = true },
    ["behavior.hideWhenZeroStacks"] = { gap = "nothing in Arc UI reads it", nv = true },
    ["behavior.hideWhenEmpty"] = { gap = "nothing in Arc UI reads it", nv = true },
    events = { gap = "nothing in Arc UI reads it", nv = true },
}

-- v1's own bands on the time text (the bar's own are its thresholds)
for i = 2, 5 do
    for _, k in ipairs({ "Enabled", "Value", "Color" }) do
        IA.BAR_MAP["display.durationTextThreshold" .. i .. k] = { gap = "the time text takes the bar's threshold colours, not bands of its own" }
    end
end

-- The specials of the bar matrix as coverage targets (what MapBarLook does with them).
IA.BAR_SPECIALS = {
    orientation = "fill.orientation", tickMode = "ticks.tickMode", style = "resource.style = pips (secondary powers only: v1 forces a primary out of its point modes)",
    position = "the bar's pos", anchor = "anchor.* (a group by name, width matched)",
    thresholds = "thresholds.thresh2..4 + threshEnabled / Count / AsSeconds / Ref, behind durationColorCurveEnabled; bands in value order, the most urgent three of v1's four",
    hideWhen = "c.fadeWhen + c.fadeAlpha", specs = "c.specs", talents = "c.talents / talentsNot", identity = "the record itself",
    hideIcon = "the tracked Cooldown Manager icon stays out of the import in the bar's specs (IA.BarHides)",
    freeText = "text.stkAnchor / durAnchor / nameAnchor = CENTER + offsets from the bar (a free-dragged text, its drag point turned into its centre)",
    chargeText = "a cooldown bar's charge text (stk*) and a charge bar's timer text (dur*), which win over the generic text keys there",
    font = "text.font (the first text font the player changed from v1's default: stack, duration, name, recharge)",
    layers = "resource: powerthresholds.pth2..5 / pthEnabled / Count / Direction / Absolute from the colour-curve keys (colorCurve mode, or the old granular / threshold layers); aura stack: stackcolors.sc2..4 / scEnabled / Count (+ scPosition per stack); charge: segments.fullColor",
    fold = "resource.foldOn + foldColor (the second lap), fill.color (the first)",
    maxColor = "stackcolors.maxColor / powerthresholds.pthFullColor / segments.fullColor (by bar kind)",
    pipColors = "stackcolors.sc2..4 + scPosition (each pip its own colour; a secondary power in a point mode)",
    padding = "fill.fillInset (the largest side)", costTicks = "ticks.tickSpells + ticksShow",
    predict = "predict.predictEnabled (v1's Show prediction) + predictColor / predictAlpha",
    textThresh = "ptextcolors.ptx2..5 / ptxEnabled / Count / Direction / BaseColor (the texts' own bands)",
    recharge = "resource.rechargeColorEnabled / rechargeColor (runes, essence): v1's own colour or grey, off for Auto Charging",
    pipLayout = "fill.orientation of a point row (fragmentedLayoutDirection) + resource.rechargeDir (runes, essence)",
    rcText = "text.rcShow / rcSize / rcOffsetX / rcOffsetY / rcOutline / rcColor / rcDecimalsEnabled + rcDecimalThreshold (runes, essence; v1's older names by mode)",
    readyText = "text.readyShow / readyText / readyColor (a cooldown bar; v1's \"0 when ready\" takes the Ready text's place)",
    resFormat = "text.resFormat = pctnum (percent without its sign)",
    charged = "resource.chargedShow (always on, as in v1) + chargedColor (combo points)",
    textureColor = "fill.color white, fill.useGradient off, resource.usePowerColor off, no colour rule (Use Texture Colors)",
    gradient = "fill.gradientColor = the second colour at the intensity's opacity (0.5 when unset)",
    bgColor = "look.bgColor + look.bgAlpha (v1 keeps the opacity in the colour)",
    chargeSize = "size.height of a charge bar (its strip, slotHeight)",
    chargeBox = "a charge bar moved from v1's box onto its strip: pos, the box-anchored texts' offsets, icon.iconSpacing / iconOffsetX / iconOffsetY",
    chargeLook = "look.bgShow / bgColor / bgAlpha / bgTexture from a duration bar's own background or a charge bar's slots'",
    fullCharge = "segments.fullColorEnabled + fullColor (each available charge)",
    iconFree = "icon.iconSide (the side nearest a free-dragged icon) + iconOffsetX / iconOffsetY",
    usableText = "text.stkColor while v1's Color by usable state is on (its usable colour)",
    pipIcons = "resource.pipSpacing / pipWidth / pipHeight / pipShape (rune / essence icons in a row; a triangle as a diamond)",
    castLook = "a castbar's text style on the name and the time, the flat background (look.bgTexture Flat + bgColor / bgAlpha), frame.level, and no spark / icon / shield where v1 drew none",
    castHold = "cast.holdTime / holdIntColor / holdFailColor (the player's flash: one colour for both endings, its fade time; focus / target: the hold time)",
    castTicks = "ticks.* of a castbar (the channel profile's when it turns ticks on): mode, percent (5-50), custom list as percent, colour, thickness, height and its anchor, channels only",
    castProfiles = "v1's cast-type profiles folded: a per-type key from the Hardcast profile unless its category is shared; fill.castChannelOn / castChannelColor from the Channel profile",
    castColor = "fill.color = the class colour (a player bar), or white with no lock colour (Use Texture Colors)",
    castType = "a cast bar shows every cast (v1's cast-type filter is reported)",
    litColors = "the lit points' colour by how many are lit: a colour from 1 up as the bar's own (fill.color / pointColor), the rest powerthresholds above, absolute",
    timerMode = "rec.barMode: Timer runs a timer, Stack counts stacks, Toggle is a stack of one",
    timerRules = "driver.rules (Drivers\\AD_DriverCustom.lua): the trigger, death, retrigger, cancel, generators, spenders and the spells that hold spenders back; driver.duration / maxStacks / clearOnEnd / showWhile",
    skins = "v1's auto-switch skins: one bar per look a rule switches to (the skin over the bar), loading in the specs it shows in, with its rule's talents and without those of rules that win before it; the bar as saved loads in the rest",
    timerTicks = "a timer bar's ticks: one every interval seconds of its timer (ticks.tickMode custom, values in seconds; each second as all), or one per stack",
    timerName = "text.nameText", timerArt = "driver.spellID (the trigger or the first generator) and icon.iconOverride",
    castIcon = "icon.iconSide LEFT + iconSpacing 0 + iconOffsetX / iconOffsetY from a dragged icon's corner",
    looks = "rec.looks by power or spec (an Automatic bar's per-power profiles as their differences, or its per-power colours; a rune bar's own spec colours)",}

-- A cast bar record (v1's flat castbar table) -> the cast bar schema.
IA.CAST_MAP = {
    width = { "size", "width", "int" }, height = { "size", "height", "int" },
    opacity = { "size", "opacity", "num" }, barColor = { "fill", "color", "color" },
    texture = { "fill", "texture" },
    reverseFill = { gap = "Arc Auras' Reverse fill mirrors the bar; v1's swaps which casts fill and which drain" },
    showBackground = { "look", "bgShow", "bool" }, backgroundColor = { special = "castLook" },
    showBorder = { "look", "borderEnabled", "bool" }, borderColor = { "look", "borderColor", "color" },
    drawnBorderThickness = { "look", "borderThickness", "int" },
    showIcon = { "icon", "iconShow", "bool" }, iconSize = { "icon", "iconSize", "int" },
    showText = { "text", "nameShow", "bool" }, showSpellName = { "text", "nameShow", "bool" },
    showTimer = { "text", "durShow", "bool" }, font = { "text", "font", "font" },
    fontSize = { special = "castLook" }, textColor = { special = "castLook" }, textOutline = { special = "castLook" },
    barFrameStrata = { "frame", "strata" }, barFrameLevel = { special = "castLook" },
    barPosition = { special = "position" }, barAnchorPoint = { special = "position" },
    hideChannels = { "cast", "hideChannels", "bool" },
    hideCastBar = { "cast", "hideBlizzard", "bool" }, latencyEnabled = { "cast", "latencyOn", "bool" },
    latencyColor = { "cast", "latencyColor", "color" },
    interruptFeedbackEnabled = { "cast", "holdOn", "bool" },
    interruptColor = { special = "castHold" }, interruptFadeDuration = { special = "castHold" },
    holdEnabled = { "cast", "holdOn", "bool" }, holdDuration = { special = "castHold" },
    holdFailColor = { "cast", "holdFailColor", "color" }, holdInterruptedColor = { "cast", "holdIntColor", "color" },
    holdSuccessColor = { gap = "a finished cast never holds in Arc Auras" },
    uninterruptibleEnabled = { "fill", "castLockOn", "bool" },
    uninterruptibleColor = { "fill", "castLockColor", "color" },
    hideNotInterruptible = { "cast", "lockHide", "bool" },
    tickMarksEnabled = { special = "castTicks" }, tickPercent = { special = "castTicks" },
    tickCustom = { special = "castTicks" }, tickMarksColor = { special = "castTicks" },
    tickMarksThickness = { special = "castTicks" }, tickShowOn = { special = "castTicks" },
    tickMode = { special = "castTicks" }, tickMarksHeightFraction = { special = "castTicks" },
    tickHeightAnchor = { special = "castTicks" },
    tickThicknessAnchor = { gap = "a tick's thickness anchor is a resource bar's in Arc Auras" },
    profiles = { special = "castProfiles" }, autoShareCategories = { special = "castProfiles" },
    enabled = { special = "identity" }, castType = { special = "castType" },
    classColor = { special = "castColor" }, useTextureColor = { special = "castColor" },
    anchorToGroup = { special = "anchor" }, anchorGroupName = { special = "anchor" },
    anchorPoint = { special = "anchor" }, anchorOffsetX = { special = "anchor" },
    anchorOffsetY = { special = "anchor" }, matchGroupWidth = { special = "anchor" },
    matchWidthAdjust = { special = "anchor" }, anchorToFrame = { special = "anchor" },
    anchorFrameName = { special = "anchor" }, anchorRelativePoint = { special = "anchor" },
    iconMovable = { special = "castIcon" }, iconPosition = { special = "castIcon" },
    hideOutOfCombat = { special = "hideWhen" },
    barMovable = { special = "identity" },
    -- options Arc Auras does not offer yet
    matchSlotsOnly = { gap = "a matched width spans the group's frame, not only its slots (it comes in centred, as v1 drew it)" },
    empowerSegmentColorsEnabled = { gap = "Arc Auras does not draw empowered casts yet" },
    empowerSegmentColors = { gap = "Arc Auras does not draw empowered casts yet" },
    empowerStageDividers = { gap = "Arc Auras does not draw empowered casts yet" },
    empowerDividerPerColor = { gap = "Arc Auras does not draw empowered casts yet" },
    spellOverrides = { gap = "per-spell cast bar looks are not offered yet" },
    conditionalColorEnabled = { gap = "cast bar threshold colours are not offered yet" },
    conditionalColorAsSec = { gap = "cast bar threshold colours are not offered yet" },
    colorThresholds = { gap = "cast bar threshold colours are not offered yet" },
    presets = { special = "skins" },
    timerFormat = { gap = "the cast bar's time is the time left" },
    spellShortenEnabled = { gap = "spell names are never cut" },
    spellShortenLength = { gap = "spell names are never cut" },
    spellNameMaxWidth = { gap = "the spell name has no width of its own" },
    latencyManual = { gap = "the latency zone reads the world latency" },
    latencyManualMs = { gap = "the latency zone reads the world latency" },
    uninterruptibleBorderColor = { gap = "no border colour for casts that can't be interrupted" },
    showGlow = { gap = "a castbar's glows follow an aura or a spell, not the cast" },
    glowType = { gap = "a castbar's glows follow an aura or a spell, not the cast" },
    glowColor = { gap = "a castbar's glows follow an aura or a spell, not the cast" },
    glowWidth = { gap = "a castbar's glows follow an aura or a spell, not the cast" },
    glowLines = { gap = "a castbar's glows follow an aura or a spell, not the cast" },
    glowFrequency = { gap = "a castbar's glows follow an aura or a spell, not the cast" },
    importantGlowEnabled = { gap = "no glow on important casts yet" },
    importantGlowType = { gap = "no glow on important casts yet" },
    importantGlowColor = { gap = "no glow on important casts yet" },
    importantGlowLines = { gap = "no glow on important casts yet" },
    importantGlowFrequency = { gap = "no glow on important casts yet" },
    importantGlowThickness = { gap = "no glow on important casts yet" },
    hideNotImportant = { gap = "no important-casts-only switch yet" },
    showCasterName = { gap = "no caster name text yet" },
    casterNameColor = { gap = "no caster name text yet" },
    casterNameAnchor = { gap = "no caster name text yet" },
    casterNameOffsetX = { gap = "no caster name text yet" },
    casterNameOffsetY = { gap = "no caster name text yet" },
    showFocusTarget = { gap = "no caster's target text yet" },
    focusTargetColor = { gap = "no caster's target text yet" },
    focusTargetAnchor = { gap = "no caster's target text yet" },
    focusTargetOffsetX = { gap = "no caster's target text yet" },
    focusTargetOffsetY = { gap = "no caster's target text yet" },
    showTargetTarget = { gap = "no caster's target text yet" },
    targetTargetColor = { gap = "no caster's target text yet" },
    targetTargetAnchor = { gap = "no caster's target text yet" },
    targetTargetOffsetX = { gap = "no caster's target text yet" },
    targetTargetOffsetY = { gap = "no caster's target text yet" },
    showRaidMarker = { gap = "no raid marker on a castbar yet" },
    raidMarkerSize = { gap = "no raid marker on a castbar yet" },
    raidMarkerAnchor = { gap = "no raid marker on a castbar yet" },
    raidMarkerOffsetX = { gap = "no raid marker on a castbar yet" },
    raidMarkerOffsetY = { gap = "no raid marker on a castbar yet" },
    kickEnabled = { gap = "no interrupt-ready tint or tick yet" },
    kickNotReadyColor = { gap = "no interrupt-ready tint or tick yet" },
    kickTickColor = { gap = "no interrupt-ready tint or tick yet" },
    -- nothing v1 draws
    empowerMaxStages = { gap = "Arc UI's panel preview count; live casts use the real one", nv = true },
    raidMarkerDefault = { gap = "Arc UI's preview sample", nv = true },
    tickMarksDefaultCount = { gap = "not an Arc UI setting", nv = true },
}

-- The Reminder group's pulse and sound fields keep their v1 names.
IA.REMINDER_PULSE = { "iconEnabled", "cancelOnCast", "queueMode", "stackDirection", "stackSpacing",
    "replaceGuard", "queueMaxLen", "queueInterDelay", "pulseDuration", "size", "iconOpacity",
    "animStyle", "animFadeSmoothing", "animFlashSpeed", "animZoomStart", "animZoomPeak",
    "animZoomPopTime", "animZoomSettleTime" }
IA.REMINDER_AUDIO = { "soundEnabled", "soundChannel", "soundName", "cutoffPreviousSound",
    "cutoffFadeTime", "ttsVoiceOverride", "ttsRateOverride", "ttsRate" }

-- Coverage: how many records carried each v1 key, and where it went.
function IA.NewCoverage()
    return { mapped = {}, dropped = {}, ingame = {}, gaps = {}, groupGaps = {} }
end

-- A look Arc Auras cannot draw yet, counted for the report (the converter names it): an icon's,
-- or with fam "group" a group's.
function IA.Gap(cov, what, fam)
    local key = (fam == "group") and "groupGaps" or "gaps"
    cov[key] = cov[key] or {}
    cov[key][what] = (cov[key][what] or 0) + 1
end

local function Mapped(cov, path, target)
    local m = cov.mapped[path]
    if not m then m = { n = 0, to = target } cov.mapped[path] = m end
    m.n = m.n + 1
end

-- nv marks a key that changes nothing the player sees (a sound, a rule, a switch
-- Arc UI itself retired), so the report can count the visual gaps apart.
local function Dropped(cov, path, why, nv)
    local d = cov.dropped[path]
    if not d then d = { n = 0, why = why, visual = not nv } cov.dropped[path] = d end
    d.n = d.n + 1
end

local function Need(cov, what)
    cov.ingame[what] = (cov.ingame[what] or 0) + 1
end

-- true for a table that is a colour or a list (a leaf for coverage purposes)
local function IsLeafTable(v)
    if Color(v) then return true end
    return v[1] ~= nil
end

-- Walks a v1 settings table and files every present key as mapped or dropped
-- against a matrix; `route` picks a row's target for the record's kind. Coverage
-- keys carry the record type as "<tag>:<path>", so the report can split them.
function IA.Cover(cov, tbl, map, route, prefix, tag)
    for k, v in pairs(tbl) do
        local path = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
        local row = map[path]
        local key = (tag or "other") .. ":" .. path
        if row then
            local target, why, nv = route(row, path)
            if target then Mapped(cov, key, target) else Dropped(cov, key, why, row.nv or nv) end
        elseif type(v) == "table" and not IsLeafTable(v) then
            if next(v) == nil then
                Dropped(cov, key, "an empty table, nothing to carry", true)
            else
                IA.Cover(cov, v, map, route, path, tag)
            end
        else
            Dropped(cov, key, "no Arc Auras field for this v1 key")
        end
    end
end

-- Reads one matrix row's value off an effective table into o[section][field].
local function Put(o, sec, f, v)
    if v == nil then return end
    o[sec] = o[sec] or {}
    o[sec][f] = v
end
IA.Put = Put

function IA.MapRow(o, row, v, fam)
    if v == nil then return end
    local sec, f, conv = row[1], row[2], row[3]
    if fam == "au" and row.au then sec, f, conv = row.au[1], row.au[2], row.au[3] end
    if conv then
        local out = IA.CONV[conv](v)
        if out == nil then return end
        v = out
    elseif type(v) == "table" then
        return
    end
    Put(o, sec, f, v)
end

-- One v1 icon's effective settings -> Arc Auras overrides for `kind`. ctx: the icon's size
-- and the spec's switches (IA.MapCooldownIcon); cdm marks a Cooldown Manager icon.
function IA.MapIcon(eff, kind, ctx)
    ctx = ctx or {}
    if kind == "aura" then
        if ctx.cdm == false then return IA.MapArcAuraIcon(eff, ctx) end
        return IA.MapAuraIcon(eff, ctx)
    end
    if ctx.cdm == false then return IA.MapArcCooldownIcon(eff, kind, ctx) end
    return IA.MapCooldownIcon(eff, kind, ctx)
end

-- v1's talent conditions -> the who keys
function IA.Talents(c, list, mode)
    if type(list) ~= "table" or #list == 0 then return end
    for _, cond in ipairs(list) do
        local nodeID, required, entryID
        if type(cond) == "number" then
            nodeID, required = cond, true
        elseif type(cond) == "table" then
            nodeID, required, entryID = tonumber(cond.nodeID), cond.required ~= false, tonumber(cond.entryID)
        end
        if nodeID and nodeID > 0 then
            local key = required and "talents" or "talentsNot"
            c[key] = c[key] or {}
            c[key][nodeID] = true
            if entryID and entryID > 0 then
                c.talentEntry = c.talentEntry or {}
                c.talentEntry[nodeID] = entryID
            end
        end
    end
    if mode == "any" then c.talentMode = "any" end
end

-- v1's hide keys (a table, or the oldest strings) -> c.fadeWhen; v1's "hide only when all
-- hold" over two or more of them -> c.fadeWhenAll (Hide always hides whatever the logic)
function IA.HideWhen(c, vis, logic, alpha)
    local any = false
    if type(vis) == "table" then
        local n, always = 0, false
        for k, on in pairs(vis) do
            local key = IA.HIDE_WHEN[k]
            if on == true and key then
                c.fadeWhen = c.fadeWhen or {}
                if not c.fadeWhen[key] then n = n + 1 end
                c.fadeWhen[key] = true
                any = true
                if key == "always" then always = true end
            end
        end
        if logic == "all" and n > 1 and not always then c.fadeWhenAll = true end
    elseif type(vis) == "string" then
        local key = IA.LEGACY_VIS[vis]
        if key then
            c.fadeWhen = { [key] = true }
            any = true
        end
    end
    if any and tonumber(alpha) and tonumber(alpha) > 0 then c.fadeAlpha = tonumber(alpha) end
    return any
end

-- spec indexes v1 saved (showOnSpecs) -> spec ids; nil when every spec shows
function IA.Specs(list, classID, opts)
    if type(list) ~= "table" or #list == 0 then return nil end
    local set, n = {}, 0
    for _, idx in ipairs(list) do
        local id = IA.SpecID(classID, tonumber(idx), opts)
        if id then set[id] = true n = n + 1 end
    end
    return n > 0 and set or nil
end

function IA.SpecID(classID, idx, opts)
    if not (classID and idx) then return nil end
    if opts and opts.specID then
        local id, name = opts.specID(classID, idx)
        if type(id) == "number" and id > 0 then return id, name end
    end
    local ids = IA.SPEC_IDS[classID]
    return ids and ids[idx] or nil
end

function IA.ClassTag(classID, opts)
    if opts and opts.classTag then
        local tag = opts.classTag(classID)
        if type(tag) == "string" and tag ~= "" then return tag end
    end
    return IA.CLASS_TAGS[classID]
end

-- v1's group anchor -> a plan anchor (resolved to ids at Apply)
function IA.GroupAnchor(a, cov)
    if type(a) ~= "table" then return nil end
    if a.enabled ~= true or a.mode == nil or a.mode == "none" then return nil end
    local out = { src = a.sourcePoint or "TOP", dst = a.destPoint or "BOTTOM",
        x = tonumber(a.offsetX) or 0, y = tonumber(a.offsetY) or 0 }
    if a.mode == "toGroup" and type(a.targetGroup) == "string" and a.targetGroup ~= "" then
        out.kind, out.group = "group", a.targetGroup
    elseif a.mode == "toFrame" and type(a.targetFrame) == "string" and a.targetFrame ~= "" then
        out.kind, out.frame = "frame", a.targetFrame
    elseif a.mode == "toMouse" then
        out.kind = "mouse"
    else
        return nil
    end
    return out
end

-- v1's game frames anchored to a group -> pins (Core\AD_Pins.lua), its Safe and direct ones
-- alike: a pin places the frame by its screen spot, never by a link. v1 moves them only while
-- the group's anchoring is on.
IA.PINS_MAX = 4
IA.PIN_POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
function IA.GroupPins(a, cov)
    if type(a) ~= "table" or type(a.anchoredFrames) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(a.anchoredFrames) do
        if type(e) == "table" and type(e.frameName) == "string" and e.frameName ~= "" then
            if a.enabled ~= true then
                Dropped(cov, "group:anchor.anchoredFrames", "game frames on a group whose anchoring is off: Arc UI leaves them be", true)
            elseif #out >= IA.PINS_MAX then
                IA.Gap(cov, "a group moving more than four game frames (Arc Auras moves four)", "group")
            else
                out[#out + 1] = { frame = e.frameName,
                    src = IA.PIN_POINTS[e.sourcePoint] and e.sourcePoint or "BOTTOM",
                    dst = IA.PIN_POINTS[e.destPoint] and e.destPoint or "TOP",
                    x = tonumber(e.offsetX) or 0, y = tonumber(e.offsetY) or 0,
                    snap = (e.snapBack == true) or nil }
                Mapped(cov, "group:anchor.anchoredFrames", "pins")
            end
        end
    end
    return #out > 0 and out or nil
end

-- v1's Button Press Highlight (per character) -> Arc Auras' press highlight (Modules), as
-- settings: nil while v1 had it off, so a highlight set up in Arc Auras stays. v1's looks by
-- number: a colour fill, the quest border, the action bar's pushed, hover and flash frames;
-- its custom texture has no twin and becomes the fill. v1 tints the art only with its own
-- colour on, and untinted art draws at full opacity.
IA.PRESS_LOOKS = { [1] = "fill", [2] = "quest", [4] = "down", [5] = "hover", [6] = "flash" }
function IA.PressHighlight(b, cov)
    if type(b) ~= "table" or b.enabled ~= true then return nil end
    local look = IA.PRESS_LOOKS[tonumber(b.textureType) or 1]
    if not look then
        IA.Gap(cov, "a press highlight with a texture of its own (Arc Auras: a colour fill)")
        look = "fill"
    end
    local custom = b.useCustomColor == true and type(b.customColor) == "table"
    local c = custom and b.customColor or (type(b.color) == "table" and b.color or {})
    local d = custom and { 0.2, 0.6, 1, 0.5 } or { 0.95, 0.95, 0.32, 0.45 }
    local a = math.max(0.05, math.min(1, tonumber(c.a) or d[4]))
    local out = { pressHighlight = true, pressMode = (b.mode == "hold") and "hold" or nil,
        pressDuration = math.max(0.05, math.min(0.5, tonumber(b.flashDuration) or 0.1)), pressLook = (look ~= "fill") and look or nil,
        pressColor = { tonumber(c.r) or d[1], tonumber(c.g) or d[2], tonumber(c.b) or d[3] } }
    if look == "fill" then
        out.pressAlpha = a
    else
        out.pressTint = custom or nil
        out.pressAlpha = custom and a or 1
    end
    return out
end
-- every key it writes, a nil one too: the import resets what it leaves at the default
IA.PRESS_KEYS = { "pressHighlight", "pressMode", "pressDuration", "pressLook", "pressColor", "pressAlpha", "pressTint" }

-- v1's group hide keys -> Arc Auras fade conditions. Arc UI never reads three of the keys a
-- group can carry, and "in a group" there is a party or a raid.
IA.GROUP_HIDE = {}
for k, v in pairs(IA.HIDE_WHEN) do IA.GROUP_HIDE[k] = { v } end
IA.GROUP_HIDE.hideInGroup = { "party", "raid" }
IA.GROUP_HIDE.hideInBerserkerStance, IA.GROUP_HIDE.hideInNoShadowform, IA.GROUP_HIDE.hideOutOfCombat = nil, nil, nil
-- each hide key's opposite (shown while any of them holds), for v1's "hide only when all hold"
IA.GROUP_HIDE_NOT = { hideOOC = { "inCombat" }, hideInCombat = { "outOfCombat" }, hideDead = { "alive" },
    hideSolo = { "party", "raid" }, hideInGroup = { "solo" }, hideInRaid = { "solo", "party" },
    hideInInstance = { "openWorld" }, hideNoTarget = { "hasTarget" }, hideHasTarget = { "noTarget" },
    hideNotCasting = { "casting" }, hideCasting = { "notCasting" }, hideInShadowform = { "noShadowform" } }

-- A v1 group's visibility -> c.fadeWhen (any of them hides; "all" logic over several keys:
-- c.fadeWhenAll, or where a key is two of ours, c.showWhen while any opposite holds); the alpha
-- it hides to.
function IA.GroupVisibility(c, vis, logic, alpha, cov)
    local keys = {}
    if type(vis) == "table" then
        for _, k in ipairs(IA.SortedKeys(vis)) do
            if vis[k] == true and IA.GROUP_HIDE[k] then keys[#keys + 1] = k end
        end
    elseif type(vis) == "string" and IA.LEGACY_VIS[vis] then
        local key = IA.LEGACY_VIS[vis]
        c.fadeWhen = { [key] = true }
    end
    local all = logic == "all" and #keys > 1 and vis.hideAlways ~= true
    if all then
        local single = true
        for _, k in ipairs(keys) do
            if #IA.GROUP_HIDE[k] ~= 1 then single = false end
        end
        if single then
            c.fadeWhen, c.fadeWhenAll = {}, true
            for _, k in ipairs(keys) do c.fadeWhen[IA.GROUP_HIDE[k][1]] = true end
        else
            local show = {}
            for _, k in ipairs(keys) do
                if not IA.GROUP_HIDE_NOT[k] then show = nil break end
                for _, key in ipairs(IA.GROUP_HIDE_NOT[k]) do show[key] = true end
            end
            if show then
                c.showWhen = show
            else
                IA.Gap(cov, "a group hidden only while all its conditions hold", "group")
                all = false
            end
        end
    end
    if not all and #keys > 0 then
        c.fadeWhen = {}
        for _, k in ipairs(keys) do
            for _, key in ipairs(IA.GROUP_HIDE[k]) do c.fadeWhen[key] = true end
        end
    end
    if (c.fadeWhen or c.showWhen) and tonumber(alpha) and tonumber(alpha) > 0 then c.fadeAlpha = tonumber(alpha) end
    return c.fadeWhen ~= nil or c.showWhen ~= nil
end

-- The alignment v1 packs a group by (only a packed group reads it), written as Arc Auras reads it
-- for the same grid: one row centres or packs right, else left; one column centres or packs to the
-- bottom, else the top; a grid packs by its gravity, unset = top and an unknown value right.
function IA.V1Alignment(a, rows, cols)
    if rows <= 1 then
        if a == nil then return "center" end
        return (a == "center" or a == "right") and a or "left"
    elseif cols <= 1 then
        if a == nil then return "center" end
        return (a == "center" or a == "bottom") and a or "top"
    end
    if a == nil then return "top" end
    if a == "center" then return "center_h" end
    if a == "top" or a == "bottom" or a == "center_v" or a == "left" or a == "center_h" then return a end
    return "right"
end

-- A v1 group record -> a plan group (no icons yet). gl: the record as v1 reads it
-- (IA.NormalizeGroup: its flat fields, CreateGroup's defaults filled); raw: as saved, for coverage.
function IA.MapGroup(name, gl, cov, raw)
    local eff = gl
    local o, c = {}, {}
    for path, row in pairs(IA.GROUP_MAP) do
        if not row.gap and not row.special then IA.MapRow(o, row, Leaf(eff, path)) end
    end
    local kind = (eff.groupType == "aura") and "aura" or "cooldown"
    -- v1's container edge is two units wide
    if eff.showBorder == true then Put(o, "look", "borderSize", 2) end
    -- the inset from the frame's edge to the first icon: v1 draws six past what it stores
    local pad = math.floor((tonumber(eff.containerPadding) or -4) + 6 + 0.5)
    if pad < -6 or pad > 12 then IA.Gap(cov, "a group's container padding past Arc Auras' range", "group") end
    Put(o, "arrangement", "containerPadding", math.max(-6, math.min(12, pad)))
    -- v1 reads Spacing X and Y whenever they are set, whatever its switch says
    local sp, sx, sy = tonumber(eff.spacing) or 2, tonumber(eff.spacingX), tonumber(eff.spacingY)
    for _, v in ipairs({ sp, sx or sp, sy or sp }) do
        if v ~= math.floor(v) then IA.Gap(cov, "a group's half-unit spacing", "group") break end
    end
    Put(o, "arrangement", "separateSpacing", sx ~= nil or sy ~= nil)
    if sx or sy then
        Put(o, "arrangement", "spacingX", math.floor((sx or sp) + 0.5))
        Put(o, "arrangement", "spacingY", math.floor((sy or sp) + 0.5))
    end
    -- Dynamic Layout (v1's autoReflow) packs the icons with the panel closed, whatever else is on;
    -- Dynamic Cooldowns also drops an icon drawn at no opacity
    local packed = eff.autoReflow == true
    local rows, cols = math.max(1, math.floor((tonumber(eff.gridRows) or 1) + 0.5)), math.max(1, math.floor((tonumber(eff.gridCols) or 1) + 0.5))
    Put(o, "arrangement", "dynamicLayout", packed)
    if packed and kind == "cooldown" then
        Put(o, "arrangement", "dynamicCollapse", eff.dynamicCooldowns == true and "hidden" or "none")
    end
    Put(o, "arrangement", "alignment", IA.V1Alignment(eff.alignment, rows, cols))
    IA.GroupVisibility(c, eff.visibility, eff.visibilityLogic, eff.hiddenAlpha, cov)
    local pos = type(eff.position) == "table" and eff.position or {}
    local s36 = math.floor((tonumber(eff.iconSize) or 36) + 0.5) / 36
    local g = {
        name = name, kind = kind,
        pos = { x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0 },
        o = o, c = c, anchor = IA.GroupAnchor(eff.anchor, cov), pins = IA.GroupPins(eff.anchor, cov), icons = {},
        -- what IA.PlaceCells needs once the icons are known
        v1 = { rows = rows, cols = cols, packed = packed, growthH = eff.horizontalGrowth, growthV = eff.verticalGrowth,
            slotW = math.floor(math.floor((tonumber(eff.iconWidth) or 36) + 0.5) * s36 + 0.5),
            slotH = math.floor(math.floor((tonumber(eff.iconHeight) or 36) + 0.5) * s36 + 0.5),
            dynAuras = packed and eff.dynamicLayout == true,
            fcfs = packed and eff.dynamicOrderMode == "fcfs" and eff.dynamicCooldowns == true,
            spX = sx or sp, spY = sy or sp, align = IA.V1Alignment(eff.alignment, rows, cols),
            shrink = packed and eff.dynamicContainerSize == true },
    }
    IA.Cover(cov, raw or gl, IA.GROUP_MAP, function(row, path)
        if row.gap then return nil, row.gap, row.nv end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end, nil, "group")
    return g
end

-- v1's size for one icon: its group's slot (iconWidth / iconHeight times iconSize over 36,
-- each rounded as v1 rounds), or, with Use group scale off, its own width / height (else the
-- slot) times its scale; a free icon (its width or the free spot's size, else 36) times its scale.
function IA.V1IconSize(eff, g, place)
    local scale = tonumber(eff.scale) or 1
    if g then
        local s = math.floor((tonumber(g.iconSize) or 36) + 0.5) / 36
        local sw = math.floor(math.floor((tonumber(g.iconWidth) or 36) + 0.5) * s + 0.5)
        local sh = math.floor(math.floor((tonumber(g.iconHeight) or 36) + 0.5) * s + 0.5)
        if eff.useGroupScale == false then
            return (tonumber(eff.width) or sw) * scale, (tonumber(eff.height) or sh) * scale
        end
        return sw, sh
    end
    local base = place and tonumber(place.iconSize) or 36
    return (tonumber(eff.width) or base) * scale, (tonumber(eff.height) or base) * scale
end

-- A group's icons placed as v1 draws them, once every profile has fed the group. v1 never draws
-- a cell flipped (growth only picks where a new icon goes) while Arc Auras draws cells from the
-- growth edge, so a left- or up-growing group's cells are mirrored. A static grid grows to its
-- outermost saved cell; a packed one folds that icon into a free cell. What moves the group as a
-- whole lands in g.fix for IA.SettleGroups: an oversized icon on a static grid's edge carries a
-- 4-unit margin in v1 (m: left, right, top, bottom), and a packed row's half pixel (s).
function IA.PlaceCells(g, icons, cov, ppu)
    local v = g.v1
    if not v then return end
    local rows, cols = v.rows, v.cols
    local maxR, maxC = rows - 1, cols - 1
    for _, I in ipairs(icons) do
        local gp = I.gpos
        if gp and v.packed and (gp.row >= v.rows or gp.col >= v.cols) then
            I.gpos = nil
        elseif gp then
            if gp.row > maxR then maxR = gp.row end
            if gp.col > maxC then maxC = gp.col end
        end
    end
    if maxR + 1 > rows then rows = maxR + 1 Put(g.o, "arrangement", "rows", rows) end
    if maxC + 1 > cols then cols = maxC + 1 Put(g.o, "arrangement", "cols", cols) end
    -- v1 packs a one-row group into that one row however many icons show (a one-column
    -- group into its column), where Arc Auras wraps past its cells: the row takes them all
    if v.packed and rows == 1 and #icons > cols then
        cols = #icons Put(g.o, "arrangement", "cols", cols)
    elseif v.packed and cols == 1 and rows > 1 and #icons > rows then
        rows = #icons Put(g.o, "arrangement", "rows", rows)
    end
    local over = { 0, 0, 0, 0 }
    local own, auras = false, false
    for _, I in ipairs(icons) do
        local w, h = I.v1w or v.slotW, I.v1h or v.slotH
        if math.abs(w - v.slotW) > 0.01 or math.abs(h - v.slotH) > 0.01 then own = true end
        if I.cdm and I.kind == "aura" then auras = true end
        local gp = I.gpos
        if gp then
            local ox, oy = math.max(0, (w - v.slotW) / 2), math.max(0, (h - v.slotH) / 2)
            if gp.col == 0 then over[1] = math.max(over[1], ox) end
            if gp.col == cols - 1 then over[2] = math.max(over[2], ox) end
            if gp.row == 0 then over[3] = math.max(over[3], oy) end
            if gp.row == rows - 1 then over[4] = math.max(over[4], oy) end
        end
    end
    local fix = { m = { 0, 0, 0, 0 }, sx = 0, sy = 0, shrink = v.shrink }
    g.fix = fix
    if not v.packed then
        for i = 1, 4 do fix.m[i] = over[i] > 0 and 4 or 0 end
    end
    if v.packed and own then IA.Gap(cov, "a packed group with icons of their own size (Arc Auras packs by the slot)", "group") end
    if v.dynAuras and auras then IA.Gap(cov, "a gone aura's spot closing up (Arc UI's Dynamic Auras)", "group") end
    -- v1 packs a row right from an even pixel count of the grid and steps back over the block's
    -- own width rounded up to even (a column down the same way), while Arc Auras' whole-pixel frame
    -- leans left and up; the group moves by the difference for its icons all up (ppu: the client's
    -- physical pixels per unit). Only where the group's spot is a whole pixel: elsewhere the frame's
    -- lean follows the spot's fraction and both stay within a pixel.
    ppu = (tonumber(ppu) and ppu > 0) and ppu or 1
    local function Whole(x) return math.abs(x * ppu - math.floor(x * ppu + 0.5)) < 1e-6 end
    local spot = g.anchor and { x = g.anchor.x or 0, y = g.anchor.y or 0 } or g.pos
    -- (a pinned frame that shrinks to its icons carries them with it: nothing to move)
    if v.packed and not (g.anchor and v.shrink) and Whole(1) and Whole(spot.x) and Whole(spot.y) then
        local function P(x) return math.floor(x * ppu + 0.5) end
        local function Odd(n, slot, step) return n > 0 and (n * slot + (n - 1) * (step - slot)) % 2 == 1 and 1 or 0 end
        local sW, sH, stX, stY = P(v.slotW), P(v.slotH), P(v.slotW + v.spX), P(v.slotH + v.spY)
        if v.align == "right" and v.rows <= 1 then
            fix.sx = (Odd(v.cols, sW, stX) - Odd(math.min(#icons, v.cols), sW, stX)) / ppu
        elseif v.align == "right" and v.cols > 1 then
            fix.sx = Odd(v.cols, sW, stX) / ppu
        elseif v.align == "bottom" and v.rows > 1 and v.cols <= 1 then
            fix.sy = (Odd(math.min(#icons, v.rows), sH, stY) - Odd(v.rows, sH, stY)) / ppu
        end
    end
    if v.fcfs and ((rows == 1 and v.growthH == "LEFT") or (rows > 1 and cols == 1 and v.growthV == "UP")) then
        IA.Gap(cov, "a returning icon joining a row that grows left or up (Arc Auras puts it first)", "group")
    end
    for _, I in ipairs(icons) do
        local gp = I.gpos
        if gp then
            if v.growthH == "LEFT" then gp.col = cols - 1 - gp.col end
            if v.growthV == "UP" then gp.row = rows - 1 - gp.row end
        end
    end
end

-- a frame point's side: x -1 left / 1 right, y 1 top / -1 bottom
local function PointSide(pt)
    pt = type(pt) == "string" and pt or "CENTER"
    return (pt:find("LEFT") and -1) or (pt:find("RIGHT") and 1) or 0, (pt:find("TOP") and 1) or (pt:find("BOTTOM") and -1) or 0
end

-- The groups of one layout take their g.fix: a free group moves its spot, a pinned one its pin's
-- offset (the margin sits at the edge it pins by). Arc Auras' frame then has each edge off v1's by
-- the margin and the half pixel, so a group pinned to it takes the opposite on its own offset.
function IA.SettleGroups(groups)
    local byName = {}
    for _, g in ipairs(groups) do byName[g.name] = g end
    for _, g in ipairs(groups) do
        local fx = g.fix
        if fx then
            local m = fx.m
            local a = g.anchor
            if a then
                local sx, sy = PointSide(a.src)
                a.x = (a.x or 0) + (m[1] - m[2]) / 2 - sx * (m[1] + m[2]) / 2 + fx.sx
                a.y = (a.y or 0) - (m[3] - m[4]) / 2 - sy * (m[3] + m[4]) / 2 + fx.sy
            else
                g.pos.x = g.pos.x + (m[1] - m[2]) / 2 + fx.sx
                g.pos.y = g.pos.y - (m[3] - m[4]) / 2 + fx.sy
            end
            -- a frame that shrinks to its icons follows them onto v1's spots, edges and all
            local ex, ey = fx.shrink and 0 or fx.sx, fx.shrink and 0 or fx.sy
            g.edge = { l = m[1] + ex, r = -m[2] + ex, t = -m[3] + ey, b = m[4] + ey }
        end
    end
    for _, g in ipairs(groups) do
        local a = g.anchor
        local t = a and a.kind == "group" and byName[a.group]
        local e = t and t.edge
        if e then
            local dx, dy = PointSide(a.dst)
            a.x = a.x - ((dx < 0 and e.l) or (dx > 0 and e.r) or (e.l + e.r) / 2)
            a.y = a.y - ((dy > 0 and e.t) or (dy < 0 and e.b) or (e.t + e.b) / 2)
        end
        -- a game frame pinned to the group sits off the same edges
        local ge = g.edge
        for _, p in ipairs(ge and g.pins or {}) do
            local dx, dy = PointSide(p.dst)
            p.x = p.x - ((dx < 0 and ge.l) or (dx > 0 and ge.r) or (ge.l + ge.r) / 2)
            p.y = p.y - ((dy > 0 and ge.t) or (dy < 0 and ge.b) or (ge.t + ge.b) / 2)
        end
    end
end

IA.GROUP_SPECIALS = {
    padding = "arrangement.containerPadding (+6, v1's inset)", collapse = "arrangement.dynamicCollapse = hidden",
    reflow = "arrangement.dynamicLayout (v1's Dynamic Layout packs)", dynamicAuras = "noted (Arc Auras keeps an aura icon's spot)",
    spacing = "arrangement.separateSpacing + spacingX / spacingY", alignment = "arrangement.alignment (v1's for the grid's shape)",
    visibility = "c.fadeWhen / c.showWhen / c.fadeAlpha",
    anchor = "o.anchor (group / frame / mouse); anchoredFrames -> pins", position = "pos",
    kind = "groupKind", identity = "the record's identity, not a setting",
}

-- What a v1 key names: a Cooldown Manager cooldown id, an Arc Auras id, or junk.
function IA.KeyKind(key)
    if type(key) == "number" then return "cdm", key end
    if type(key) == "string" then
        if key:match("^%d+$") then return "cdm", tonumber(key) end
        if key:match("^arc_") then return "arc", key end
    end
    return nil
end

-- "arc_item_123#2" -> "item", 123, 2 (the copy number)
function IA.ParseArc(arcID)
    local kind, tail = arcID:match("^arc_(%a+)_(.+)$")
    if not kind then return nil end
    local id = tonumber(tail:match("^(%d+)"))
    local copy = tonumber(tail:match("#(%d+)$")) or tonumber(tail:match("_(%d+)$")) or 1
    return kind, id, copy
end

-- A Cooldown Manager cooldown id -> its Arc Auras kind and driver. Only the game
-- can answer (opts.cooldown); without it the icon is planned as unresolved.
function IA.ResolveCDM(cdID, iao, opts)
    local info = opts and opts.cooldown and opts.cooldown(cdID)
    if type(info) ~= "table" then return nil end
    local cat = tonumber(info.category)
    local sid = tonumber(info.spellID)
    if cat == 7 and tonumber(info.equipSlot) then
        local slot = tonumber(info.equipSlot)
        local res = { kind = "trinket", driver = { slotID = slot }, name = "Trinket " .. (slot == 14 and 2 or 1) }
        -- its on-use buff over it, as the Cooldown Manager shows it: the trinket worn in the
        -- slot names the buff (Drivers\AD_DriverCooldown.lua LearnTrinkets), the IDs read now start it
        local M = NS.CDMMirror
        res.hasAura = not M.HasFlag(info.flags, M.Flag("HideAura"))
        if res.hasAura and not iao then
            local ids = M.AuraIDs(info)
            res.driver.overlay = { on = true, worn = true, auraType = "buff", unit = "player",
                spellID = ids[1], spellIDs = (#ids > 1) and ids or nil }
        end
        return res
    end
    -- a bag item by its category (potions, healthstones) has no spell: the item icon that
    -- follows the category, as the Cooldown Manager import builds it (Core\AD_CDMMirror.lua)
    local scat = tonumber(info.spellCategoryID)
    if scat then
        if cat == 2 or cat == 3 or cat == 6 or cat == 8 then
            return nil, "a potion or healthstone buff (the Cooldown Manager learns its spell at a use)"
        end
        local M = NS.CDMMirror
        local iid = M.ITEM_FALLBACK[scat] or (opts.categoryItem and opts.categoryItem(scat)) or nil
        return { kind = "item", driver = { category = scat, itemID = iid }, name = M.ItemName(scat) }
    end
    -- the IDs the Cooldown Manager matches an aura by, its picture's first; an entry can rest
    -- on a spec's passive and show its aura through the tooltip override (Core\AD_CDMMirror.lua)
    local M = NS.CDMMirror
    local named = M.NameSpell(info) or sid
    -- the Cooldown Manager reads no flag for where an aura sits (selfAura says "you" on
    -- Flame Shock): it watches you and your target for the IDs. So: your buff, then your
    -- target's aura, its side by the spell the entry shows
    local function Lanes(d, ids)
        local harmful = opts.spellHarmful and opts.spellHarmful(ids[1]) == true
        d.spellID, d.spellIDs = ids[1], (#ids > 1) and ids or nil
        d.auraType, d.unit, d.unit2, d.caster = harmful and "debuff" or "buff", "player", "target", "mine"
        return d
    end
    if cat == 2 or cat == 3 or cat == 4 or cat == 6 or cat == 8 then
        if not sid or sid == 0 then return nil, "an aura icon with no spell id (an equipment buff)" end
        -- the Cooldown Manager shows an aura only while it lists it as learned (a talent
        -- taken): the icon keeps the entry and asks it (Store.CdmKnown). Its icon shows the
        -- entry's totem or guardian first, then the aura, as the Manager does (NS.CDMMirror
        -- PieceFor does the same for its icons)
        local d = Lanes({ cdmID = tonumber(cdID), onlyKnown = true, totem = true }, M.AuraIDs(info))
        return { kind = "aura", driver = d, name = (opts.spellName and opts.spellName(named)) or ("Aura " .. named) }
    end
    if not sid or sid == 0 then return nil, "a cooldown with no spell id" end
    -- the Cooldown Manager lists only spells you know: Only load once learned
    local d = { spellID = sid, onlyKnown = true }
    -- the Cooldown Manager's aura phase on a cooldown becomes the aura on this icon. It shows
    -- one on every entry not flagged HideAura; its hasAura hint is never read, and is off on
    -- entries that do show their buff
    local auraPhase = not M.HasFlag(info.flags, M.Flag("HideAura"))
    if auraPhase and not iao then
        d.overlay = Lanes({ on = true }, M.AuraIDs(info))
    end
    local res = { kind = "spell", driver = d, name = (opts.spellName and opts.spellName(named)) or ("Spell " .. named),
        hasAura = auraPhase }
    -- the tooltip override's picture over the spell's own, as the Cooldown Manager draws it
    local art = M.ArtSpell(info)
    if art and art ~= sid then res.art = art end -- raw-id: the same entry, not a match
    return res
end

-- An Arc Auras v1 id -> its kind, driver and name from the character's v1 store.
function IA.ResolveArc(arcID, arcDB, specKey, classID, cov, opts)
    local kind, id, copy = IA.ParseArc(arcID)
    if not kind then return nil, "an unreadable Arc Auras id" end
    -- v1's Arc Auras switched off hides every one of its icons
    if type(arcDB) == "table" and arcDB.enabled == false then return nil, "Arc UI's Arc Auras were switched off" end
    local c = {}
    local function Who(def)
        if type(def) ~= "table" then return end
        local specs = IA.Specs(def.showOnSpecs, classID, opts)
        if specs then c.specs = specs end
        IA.Talents(c, def.talentConditions, def.talentConditionMode)
    end
    if kind == "trinket" or kind == "item" then
        local def = arcDB and arcDB.trackedItems and arcDB.trackedItems[arcID]
        if type(def) ~= "table" then return nil, "no tracked item for this id" end
        if def.enabled == false then return nil, "the item icon was disabled in v1" end
        local o = {}
        if def.hideWhenUnequipped == true then Put(o, "outOfStock", "hideWhenMissing", true) end
        if kind == "trinket" then
            local slot = tonumber(def.slotID) or id
            -- an auto-tracked slot toggled off is never drawn (nil counts as on)
            local slots = arcDB.autoTrackSlots
            if def.isAutoTrackSlot == true and type(slots) == "table" and slots[slot] == false then
                return nil, "the trinket slot was switched off in v1"
            end
            if arcDB.onlyOnUseTrinkets == true then Put(o, "trinket", "onlyOnUse", true) end
            return { kind = "trinket", driver = { slotID = slot }, name = "Trinket " .. (slot == 14 and 2 or 1), o = o, c = c, def = def }
        end
        local itemID = tonumber(def.itemID) or id
        if not itemID then return nil, "an item icon with no item id" end
        -- v1 gates a bag item by its specs and talents (never a trinket slot)
        Who(def)
        return { kind = "item", driver = { itemID = itemID }, o = o, c = c, def = def,
            name = (opts.itemName and opts.itemName(itemID)) or ("Item " .. itemID) }
    elseif kind == "spell" then
        -- v1 draws an Arc icon from its list entry alone: a place left behind by a deleted one draws nothing
        local def = arcDB and arcDB.trackedSpells and arcDB.trackedSpells[arcID]
        if type(def) ~= "table" then return nil, "an Arc spell icon deleted in Arc UI" end
        local sid = tonumber(def.spellID) or id
        if not sid then return nil, "a spell icon with no spell id" end
        Who(def)
        -- v1 shows an Arc spell only once known (Force Show skips that) and can pin the base spell
        local d = { spellID = sid }
        if type(def) == "table" and def.ignoreSpellOverride == true then d.ignoreSpellOverride = true end
        if not (type(def) == "table" and def.forceShow == true) then d.onlyKnown = true end
        return { kind = "spell", driver = d, o = {}, c = c, def = def,
            name = (type(def) == "table" and def.name) or (opts.spellName and opts.spellName(sid)) or ("Spell " .. sid) }
    elseif kind == "aura" then
        local def = arcDB and arcDB.auraIcons and arcDB.auraIcons[arcID]
        if type(def) ~= "table" then return nil, "an Arc aura icon deleted in Arc UI" end
        local sid = tonumber(def.spellID) or id
        if not sid then return nil, "an aura icon with no spell id" end
        Who(def)
        -- v1's lanes (its old unitMode, or every unit on the helpful and / or harmful side): one
        -- lane is a unit, your buff then the target's aura is "you, then your target", any other
        -- set is several units in v1's order with the first lane's aura type
        local lanes = IA.V1AuraLanes and IA.V1AuraLanes(def) or { { unit = "player", harmful = false } }
        local d = { spellID = sid, unit = lanes[1].unit, auraType = lanes[1].harmful and "debuff" or "buff" }
        if #lanes == 2 and lanes[1].unit == "player" and not lanes[1].harmful and lanes[2].unit == "target" then
            d.unit2 = "target"
            d.auraType = lanes[2].harmful and "debuff" or "buff"
        elseif #lanes > 1 then
            local units, seen = {}, {}
            for _, l in ipairs(lanes) do
                if l.harmful == lanes[1].harmful then
                    if not seen[l.unit] then
                        seen[l.unit] = true
                        units[#units + 1] = l.unit
                    end
                else
                    Dropped(cov, "icon:auraIcons.lanes." .. l.unit .. (l.harmful and ".harmful" or ".helpful"),
                        "an aura icon watching buffs and debuffs at once (Arc Auras: the first lane's kind)")
                end
            end
            if #units > 1 then d.units = units end
        end
        if type(def) == "table" and def.ownOnly == true then d.caster = "mine" end
        if type(def) == "table" and type(def.spellIDs) == "table" then
            local list = { sid }
            for x, on in pairs(def.spellIDs) do
                if on and tonumber(x) and tonumber(x) ~= sid then list[#list + 1] = tonumber(x) end
            end
            if #list > 1 then table.sort(list, function(a, b) return a == sid or (b ~= sid and a < b) end) d.spellIDs = list end
        end
        return { kind = "aura", driver = d, o = {}, c = c, def = def,
            name = (type(def) == "table" and def.name) or (opts.spellName and opts.spellName(sid)) or ("Aura " .. sid) }
    elseif kind == "totem" then
        local slot = id
        if not slot or slot < 1 or slot > 4 then return nil, "a totem icon with no slot" end
        local ts = arcDB and arcDB.totemSlots and arcDB.totemSlots.bySpec and arcDB.totemSlots.bySpec[specKey]
        if type(ts) == "table" and (ts.enabled == false or (type(ts.perSlot) == "table" and ts.perSlot[slot] == false)) then
            return nil, "the totem slot was switched off in v1"
        end
        return { kind = "totem", driver = { slot = slot }, o = {}, c = c, name = "Totem slot " .. slot }
    elseif kind == "timer" then
        -- a custom timer: Arc Auras' Custom engine runs it as rules
        local def = arcDB and arcDB.customTimers and arcDB.customTimers[arcID]
        if type(def) ~= "table" then return nil, "no custom timer for this id" end
        local sid = tonumber(def.spellID)
        if not sid or sid <= 0 or (tonumber(def.duration) or 0) <= 0 then return nil, "a custom timer with no spell or length" end
        -- Force Show skips the timer's specs and talents
        if def.forceShow ~= true then Who(def) end
        local notes = {}
        local d = IA.MapArcTimerDriver(def, notes)
        for _, n in ipairs(notes) do IA.Gap(cov, n) end
        return { kind = "timer", driver = d, o = {}, c = c, def = def,
            name = def.name or (opts.spellName and opts.spellName(sid)) or ("Timer " .. sid) }
    end
    return nil, "an unknown Arc Auras id kind"
end

-- Spec key "class_3_spec_2" -> 3, 2
function IA.SpecKey(key)
    local c, s = tostring(key):match("^class_(%d+)_spec_(%d+)$")
    if not c then return nil end
    return tonumber(c), tonumber(s)
end

-- v1's character key "Name - Realm" -> the retail who key "Name-Realm"
function IA.CharKey(v1key)
    local name, realm = tostring(v1key):match("^(.-) %- (.+)$")
    if not name then return tostring(v1key), nil, nil end
    return name .. "-" .. realm, name, realm
end

-- A profile's place inside its character's layout, on one of its records' conditions:
-- its spec only, never for a spare one (an icon's own spec list keeps the specs both name).
-- The Cooldown Manager entries v1 kept hidden in one spec because a switched-on
-- aura bar of that spec tracks them with Hide buff icon: the bar's entry and
-- its alternates. v1 drew the bar there, never the icon. nil when none.
function IA.BarHides(charDB, classID, specID, opts)
    local bars = type(charDB) == "table" and type(charDB.bars) == "table" and charDB.bars or {}
    local out
    for _, i in ipairs(IA.OrderedKeys(bars)) do
        local cfg = IA.V1AceFirst(bars[i], i, "aura")
        local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
        local bh = type(cfg) == "table" and type(cfg.behavior) == "table" and cfg.behavior or nil
        if tr and bh and tr.enabled == true and bh.hideBuffIcon == true then
            local specs = IA.Specs(bh.showOnSpecs, classID, opts)
            if not specs or (specID and specs[specID]) then
                local function Add(id)
                    id = tonumber(id)
                    if id and id > 0 then
                        out = out or {}
                        out[math.floor(id)] = true
                    end
                end
                Add(tr.cooldownID)
                for _, alt in ipairs(type(tr.alternateCooldownIDs) == "table" and tr.alternateCooldownIDs or {}) do Add(alt) end
            end
        end
    end
    return out
end

function IA.GatePart(c, who)
    if who.never then c.loadNever = { always = true } end
    if not who.specs then return end
    if c.specs then
        local both = {}
        for id in pairs(c.specs) do if who.specs[id] then both[id] = true end end
        if next(both) == nil then
            c.specs = Copy(who.specs)
            c.loadNever = { always = true }
        else
            c.specs = both
        end
    else
        c.specs = Copy(who.specs)
    end
end

-- The specs whose profiles place each cooldown id in a group or free (a model character).
function IA.PlacedBySpec(C)
    local out = {}
    for _, S in ipairs(type(C) == "table" and C.specs or {}) do
        for _, P in ipairs(S.profiles or {}) do
            for skey in pairs(P.placements or {}) do
                out[skey] = out[skey] or {}
                out[skey][S.key] = true
            end
        end
    end
    return out
end

-- Whether a styled id no group of this profile holds is in this spec's Cooldown Manager.
-- The game answers for the character logged in; else an id that one other spec alone
-- places is that spec's, and its look here came over in a copied icon table. Two specs
-- placing it marks a class spell, which every spec's Manager lists.
function IA.UnplacedHere(ctx, skey, classID, specIndex, isMe)
    local id, opts = tonumber(skey), ctx.opts
    if isMe and id and classID and specIndex and opts.cdmInSpec then
        local here = opts.cdmInSpec(id, classID, specIndex)
        if here ~= nil then return here end
    end
    local by = ctx.placedIn and ctx.placedIn[tostring(skey)]
    if not by or by[ctx.specKey] then return true end
    local n = 0
    for _ in pairs(by) do n = n + 1 end
    return n ~= 1
end

-- Plans one profile of one spec (a model profile, IA.ReadV1): its groups, icons and free
-- icons, a part of its character's one layout (IA.Plan). The live profile loads in its spec;
-- every other one is kept dormant, as v1 never switches to it (its talent conditions are not
-- read). A profile on an account-wide group set (P.link) takes its own copy of the set's groups.
function IA.PlanProfile(ctx, P, S, plan)
    local cov, opts = ctx.cov, ctx.opts
    local profileName = P.name
    local pkey = ctx.charKey .. "|" .. ctx.specKey .. "|" .. tostring(profileName)
    local L = { groups = {}, icons = {}, profile = profileName, specName = ctx.specName, who = {},
        key = "layout:" .. pkey, freeUnit = "free:" .. pkey, charKey = ctx.charKey, specID = ctx.specID }
    local active = P.active == true
    if ctx.specID then L.who.specs = { [ctx.specID] = true } else Need(cov, "spec ids (GetSpecializationInfoForClassID)") end
    if not active then
        L.who.never = true
        L.dormant = true
    end
    if P.talentsIgnored then L.talentsIgnored = true end
    L.active = active
    L.linked = P.link
    local rawSet = P.link and ctx.db.global and ctx.db.global.groupLayouts and ctx.db.global.groupLayouts[P.link] or nil
    local byName, groupRec = {}, {}
    local rawProf = ctx.rawProfiles and ctx.rawProfiles[profileName]
    local rawOwn = type(rawProf) == "table" and (rawSet or rawProf.groupLayouts) or nil
    for _, gname in ipairs(IA.SortedKeys(P.groups)) do
        local g = IA.MapGroup(gname, P.groups[gname], cov, type(rawOwn) == "table" and rawOwn[gname] or nil)
        g.unit = "group:" .. pkey .. "|" .. gname
        IA.GatePart(g.c, L.who)
        byName[gname] = g
        L.groups[#L.groups + 1] = g
    end
    ctx.counts.groups = ctx.counts.groups + #L.groups
    for gname, gl in pairs(P.groups) do groupRec[gname] = gl end
    -- the icons: every placed id, its look from v1's own merge
    local settings = P.iconSettings
    local placed = {}
    -- the Cooldown Manager's own choice of what shows can be read for this character only
    local cdmClass, cdmSpec = IA.SpecKey(ctx.specKey)
    local isMe = ctx.charKey == IA.CurrentChar()
    local cdmHere = opts.cdmShown ~= nil and cdmClass ~= nil and isMe
    local function Icon(key, place)
        IA.Yield()
        local kk, id = IA.KeyKind(key)
        if not kk then Dropped(cov, "icon:placement.unreadable", "an icon placed under a key that names nothing", true) return end
        local skey = tostring(key)
        if placed[skey] then return end
        placed[skey] = true
        local res, why
        local raw = settings[skey]
        -- Ignore Aura Override, from the icon's own table or a global layer
        local eff0 = IA.V1Effective(ctx.C, P, skey, false)
        local iao = (type(eff0.auraActiveState) == "table" and eff0.auraActiveState.ignoreAuraOverride == true)
            or (type(eff0.cooldownSwipe) == "table" and eff0.cooldownSwipe.ignoreAuraOverride == true)
        if kk == "cdm" then
            res, why = IA.ResolveCDM(id, iao, opts)
            -- set to "not displayed" in the Cooldown Manager: v1 had no frame to show for
            -- it, whatever its group kept, so it stays out (the logged-in character only)
            if res and cdmHere and opts.cdmShown(id, cdmClass, cdmSpec) == false then
                Dropped(cov, "icon:dropped.cdm: not displayed in the Cooldown Manager",
                    "set to not displayed in your Cooldown Manager", true)
                ctx.counts.iconsDropped = ctx.counts.iconsDropped + 1
                ctx.counts.cdmHidden = (ctx.counts.cdmHidden or 0) + 1
                -- counted where it sat, for the picker's words
                local gp = place.type == "group" and place.target and byName[place.target]
                if gp then gp.cdmHidden = (gp.cdmHidden or 0) + 1 else L.cdmHidden = (L.cdmHidden or 0) + 1 end
                return
            end
            -- a bar of this spec tracked it with Hide buff icon: v1 drew the bar, not the icon
            if ctx.barHides and ctx.barHides[id] then
                Dropped(cov, "icon:dropped.cdm: hidden by a bar that tracks it",
                    "a bar that tracks it hid it in Arc UI (Hide buff icon)", true)
                ctx.counts.iconsDropped = ctx.counts.iconsDropped + 1
                ctx.counts.barHidden = (ctx.counts.barHidden or 0) + 1
                return
            end
            if not res and not why then
                -- no game: the viewer type saved with the placement still names the kind
                local vt = place.viewerType
                if vt == "aura" or vt == "cooldown" or vt == "utility" then
                    res = { kind = (vt == "aura") and "aura" or "spell", driver = { cooldownID = id }, name = "Cooldown " .. id, unresolved = true }
                else
                    res = { kind = "spell", driver = { cooldownID = id }, name = "Cooldown " .. id, unresolved = true, kindUnknown = true }
                end
                Need(cov, "cooldown ids (C_CooldownViewer.GetCooldownViewerCooldownInfo)")
            end
        else
            res, why = IA.ResolveArc(id, ctx.arcDB, ctx.specKey, ctx.classID, cov, opts)
        end
        if not res then
            Dropped(cov, "icon:dropped." .. (kk == "cdm" and "cdm" or (IA.ParseArc(id) or "arc")) .. ": " .. (why or "unresolved"), why or "unresolved", true)
            ctx.counts.iconsDropped = ctx.counts.iconsDropped + 1
            return
        end
        -- v1's family: a Cooldown Manager aura takes the aura layer, everything else the cooldown one
        local auraFamily = kk == "cdm" and res.kind == "aura"
        -- the cooldown family's look is eff0 already
        local eff = auraFamily and IA.V1Effective(ctx.C, P, skey, true) or eff0
        -- Arc UI's own icons: their painters' look (the Arc defaults and Arc-wide layer around it)
        if kk == "arc" and IA.V1ArcEffective then eff = IA.V1ArcEffective(ctx.C, eff) end
        local g = place.type == "group" and place.target and groupRec[place.target] or nil
        local W, H = IA.V1IconSize(eff, g, place)
        -- whether the cooldown has an aura phase: the game's answer, unknown offline
        local hasAura
        if not res.unresolved then hasAura = res.hasAura == true end
        local mctx = { cdm = (kk == "cdm"), W = W, H = H, keepCDMStyle = S.keepCDMStyle == true,
            nativeGlow = ctx.nativeGlow, keybinds = S.keybinds, hasAura = hasAura, iao = iao == true, notes = {},
            ach = ctx.ach,
            cdmHidesMissing = opts.cdmHidesMissing and opts.cdmHidesMissing() or nil, arcDef = res.def }
        if mctx.cdm and tonumber(eff.customIconID) and tonumber(eff.customIconID) > 0 then
            if opts.spellTexture then
                mctx.iconFrom = opts.spellTexture(tonumber(eff.customIconID)) and "spell" or "icon"
            else
                Need(cov, "custom icon ids (spell or file id)")
            end
        end
        local o = IA.MapIcon(eff, res.kind, mctx)
        for _, n in ipairs(mctx.notes) do IA.Gap(cov, n) end
        -- a Duration Override becomes what shows on the icon: its aura, totem or set duration
        if mctx.overlayAura and (res.kind == "spell" or res.kind == "item" or res.kind == "trinket")
            and type(res.driver) == "table" then
            res.driver.overlay = mctx.overlayAura
        end
        for sec, fields in pairs(res.o or {}) do for f, v in pairs(fields) do Put(o, sec, f, v) end end
        -- the Cooldown Manager's own picture when v1 set none of its own
        if res.art and eff.forceHideIcon ~= true and tonumber(eff.customIconID) == nil then
            Put(o, "appearance", "customIcon", res.art)
            Put(o, "appearance", "customIconFrom", "spell")
        end
        -- the converters' notes are the icon's losses; the offline dry run audits its keys
        if IA.KeyAudit then IA.KeyAudit(raw, res.kind, mctx, skey) end
        local I = { kind = res.kind, driver = res.driver, name = res.name, o = o, c = res.c or {},
            src = skey, unresolved = res.unresolved, kindUnknown = res.kindUnknown, cdm = kk == "cdm", v1w = W, v1h = H }
        if place.type == "group" and place.target and byName[place.target] then
            local row, col = tonumber(place.row), tonumber(place.col)
            if row and col and row >= 0 and col >= 0 then I.gpos = { row = math.floor(row), col = math.floor(col) } end
            I.sortIndex = tonumber(place.sortIndex) or ((row or 0) * 20 + (col or 0))
            local gp = byName[place.target]
            gp.icons[#gp.icons + 1] = I
            -- its own size instead of the group's slot
            if eff.useGroupScale == false then
                Put(I.o, "position", "useGroupScale", false)
                if tonumber(eff.width) then Put(I.o, "position", "iconWidth", math.floor(tonumber(eff.width) + 0.5)) end
                if tonumber(eff.height) then Put(I.o, "position", "iconHeight", math.floor(tonumber(eff.height) + 0.5)) end
                Put(I.o, "position", "iconScale", tonumber(eff.scale) or 1)
            end
        else
            I.pos = { x = tonumber(place.x) or 0, y = tonumber(place.y) or 0 }
            -- v1 sizes a free icon by its own width / height, else the free spot's size
            local size = tonumber(place.iconSize)
            local w = tonumber(eff.width) or size
            local h = tonumber(eff.height) or size
            if w and w > 0 then Put(I.o, "position", "iconWidth", math.floor(w + 0.5)) end
            if h and h > 0 then Put(I.o, "position", "iconHeight", math.floor(h + 0.5)) end
            Put(I.o, "position", "iconScale", tonumber(eff.scale) or 1)
            -- Stack Priority: its strata, and its level over the layout's (a child of UIParent, level 1,
            -- under the engine's two)
            local fp = type(eff.freePosition) == "table" and eff.freePosition or nil
            if fp then
                local okStrata = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
                if okStrata[fp.strata] then Put(I.o, "position", "strata", fp.strata)
                elseif fp.strata ~= nil then IA.Gap(cov, "a free icon's strata above Dialog") Put(I.o, "position", "strata", "DIALOG") end
                local lv = tonumber(fp.frameLevel)
                if lv then Put(I.o, "position", "frameLevel", math.max(0, math.min(50, math.floor(lv + 0.5) - 3))) end
            end
            -- a free icon sits in the character's layout itself: it carries its profile's place
            IA.GatePart(I.c, L.who)
            L.icons[#L.icons + 1] = I
        end
        ctx.counts.icons[res.kind] = (ctx.counts.icons[res.kind] or 0) + 1
        if kk == "cdm" then ctx.counts.cdmIcons = ctx.counts.cdmIcons + 1 else ctx.counts.arcIcons = ctx.counts.arcIcons + 1 end
    end
    -- grouped icons first, then the free ones
    local keys = IA.SortedKeys(P.placements)
    for _, k in ipairs(keys) do
        local pl = P.placements[k]
        if pl.pos.type == "group" then Icon(pl.key, pl.pos) end
    end
    for _, k in ipairs(keys) do
        local pl = P.placements[k]
        if pl.pos.type ~= "group" then Icon(pl.key, pl.pos) end
    end
    -- styled icons never placed anywhere (they sat in the Cooldown Manager's own viewer): the
    -- game's category names their default group, or they go free at the centre. Only the
    -- ones this spec's Manager lists: v1 showed a styled id only where the Manager drew it
    local unplaced = {}
    for skey, raw in pairs(settings) do
        if not placed[skey] and type(raw) == "table" and next(raw) ~= nil and IA.KeyKind(skey) == "cdm" then unplaced[#unplaced + 1] = skey end
    end
    table.sort(unplaced)
    for _, skey in ipairs(unplaced) do
        if not IA.UnplacedHere(ctx, skey, cdmClass, cdmSpec, isMe) then
            Dropped(cov, "icon:dropped.cdm: not in this spec's Cooldown Manager",
                "styled in this spec, but only another spec's Cooldown Manager lists it", true)
            ctx.counts.iconsDropped = ctx.counts.iconsDropped + 1
            ctx.counts.otherSpec = (ctx.counts.otherSpec or 0) + 1
        else
            ctx.counts.unplaced = ctx.counts.unplaced + 1
            local info = opts.cooldown and opts.cooldown(tonumber(skey))
            local cat = type(info) == "table" and tonumber(info.category)
            if cat then
                local home = (cat == 1) and "Utility" or ((cat == 0 or cat == 5 or cat == 7) and "Essential" or "Buffs")
                if byName[home] then Icon(skey, { type = "group", target = home }) else Icon(skey, { type = "free", x = 0, y = 0 }) end
            else
                Need(cov, "unplaced styled cooldowns (the game's category picks Buffs / Essential / Utility)")
            end
        end
    end
    for _, g in ipairs(L.groups) do
        table.sort(g.icons, function(a, b) return (a.sortIndex or 0) < (b.sortIndex or 0) end)
    end
    ctx.counts.freeIcons = ctx.counts.freeIcons + #L.icons
    return L
end

-- v1's global icon layers (the account profile the character used) -> Arc Auras
-- saved defaults per icon kind, so the copied icons stay sparse and new ones match.
function IA.PlanDefaults(ctx)
    local out = {}
    local base = IA.V1.DEFAULT_ICON_SETTINGS
    for _, kind in ipairs({ "spell", "item", "trinket", "totem" }) do
        out["icon:" .. kind] = IA.MapIcon(IA.V1Merge(base, ctx.globals.cooldown), kind,
            { cdm = true, H = 36, W = 36, nativeGlow = ctx.nativeGlow })
    end
    out["icon:aura"] = IA.MapIcon(IA.V1Merge(base, ctx.globals.aura), "aura",
        { cdm = true, H = 36, W = 36, nativeGlow = ctx.nativeGlow })
    return out
end

-- A v1 bar's shared display / behavior tables -> a plan bar's o, c, pos and anchor.
-- v1 strips every bar setting equal to its default at logout and fills them back only
-- for the character logging in (Utilities\ArcUI_DataRepair.lua FillDefaults): a missing
-- key takes its default, display and behavior key by key. The import fills a copy the
-- same way for every character, so a bar comes in as v1 drew it; the save is never written.
IA.V1_FILL_SECTIONS = { display = true, behavior = true }
local function V1Fill(saved, defaults, depth)
    if depth > 6 then return end
    for k, dv in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = Copy(dv)
        elseif type(dv) == "table" and type(saved[k]) == "table" and IA.V1_FILL_SECTIONS[k] then
            V1Fill(saved[k], dv, depth + 1)
        end
    end
end
-- A v1 drag position ({ point, relPoint, x, y } on the screen) as the dragged frame's
-- centre, in offsets from the screen's centre: the frame's own point sits at relPoint + (x, y).
-- w, h are the frame's size; sw, sh the screen's (UIParent's in game).
IA.POINT_SIDES = { CENTER = { 0, 0 }, TOP = { 0, 1 }, BOTTOM = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 },
    TOPLEFT = { -1, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { -1, -1 }, BOTTOMRIGHT = { 1, -1 } }
function IA.ScreenCenter(pos, w, h, sw, sh)
    if type(pos) ~= "table" then return nil end
    local x, y = tonumber(pos.x), tonumber(pos.y)
    if not (x and y) then return nil end
    local PS = IA.POINT_SIDES
    local pt = PS[pos.point] or PS.CENTER
    local rp = PS[pos.relPoint] or PS[pos.point] or PS.CENTER
    if not (sw and sh) then
        local U = rawget(_G, "UIParent")
        sw, sh = U and U.GetWidth and U:GetWidth() or 0, U and U.GetHeight and U:GetHeight() or 0
    end
    return rp[1] * sw / 2 + x - pt[1] * (w or 0) / 2, rp[2] * sh / 2 + y - pt[2] * (h or 0) / 2
end

-- v1 drew a charge bar as a box (frameWidth x frameHeight, saved by its centre) with the icon
-- inside it and the charge strip centred at slotOffset; the charge and timer texts anchor to
-- the box. Here the strip is the bar: it moves by that offset, each box-anchored text keeps
-- its point plus the gap between that point on the box and on the strip, and the icon's gap
-- and offsets are worked out so it lands where v1 drew it. Standing bars (v1 swaps every
-- axis) keep v1's own offsets.
function IA.ChargeBox(B, o, d)
    if type(d.barOrientation) == "string" and d.barOrientation:lower() == "vertical" then return end
    local FW, FH = tonumber(d.frameWidth) or 200, tonumber(d.frameHeight) or 38
    local W, H = tonumber(d.width) or 100, tonumber(d.slotHeight) or 14
    local sx, sy = tonumber(d.slotOffsetX) or 0, tonumber(d.slotOffsetY) or 0
    local function Round(v) return math.floor(v + 0.5) end
    B.pos = { x = Round((B.pos and B.pos.x or 0) + sx), y = Round((B.pos and B.pos.y or 0) + sy) }
    local PS = IA.POINT_SIDES
    local function Move(prefix)
        local t = o.text
        local an = t and t[prefix .. "Anchor"]
        local side = an and PS[an]
        if not side then return end
        local dx = side[1] * (FW - W) / 2 - sx
        local dy = side[2] * (FH - H) / 2 - sy
        t[prefix .. "OffsetX"] = math.max(-100, math.min(100, Round((t[prefix .. "OffsetX"] or 0) + dx)))
        t[prefix .. "OffsetY"] = math.max(-100, math.min(100, Round((t[prefix .. "OffsetY"] or 0) + dy)))
    end
    Move("stk")
    Move("dur")
    -- the icon: v1 set it in from the box's edge by the bar gap; Arc Auras sets it off the
    -- bar's side by the icon gap
    if o.icon and o.icon.iconShow ~= false and d.barIconShow ~= false then
        local S = tonumber(d.barIconSize) or 30
        local sp = tonumber(d.iconBarSpacing) or 0
        local ix, iy = tonumber(d.iconOffsetX) or 0, tonumber(d.iconOffsetY) or 0
        local side = (o.icon.iconSide == "RIGHT" or o.icon.iconSide == "TOP" or o.icon.iconSide == "BOTTOM") and o.icon.iconSide or "LEFT"
        local gap, ox, oy
        if side == "LEFT" then
            gap = (sx - W / 2) - (-FW / 2 + sp + ix + S)
            ox, oy = 0, iy - sy
        elseif side == "RIGHT" then
            gap = (FW / 2 - sp + ix - S) - (sx + W / 2)
            ox, oy = 0, iy - sy
        elseif side == "TOP" then
            gap = (FH / 2 - sp + iy - S) - (sy + H / 2)
            ox, oy = ix - sx, 0
        else
            gap = (sy - H / 2) - (-FH / 2 + sp + iy + S)
            ox, oy = ix - sx, 0
        end
        -- Arc Auras' gap runs -20 to 40; the rest moves the icon along that axis
        local g = math.max(-20, math.min(40, Round(gap)))
        local rest = Round(gap) - g
        if side == "LEFT" then ox = ox - rest elseif side == "RIGHT" then ox = ox + rest
        elseif side == "TOP" then oy = oy + rest else oy = oy - rest end
        Put(o, "icon", "iconSpacing", g)
        Put(o, "icon", "iconOffsetX", math.max(-100, math.min(100, Round(ox))))
        Put(o, "icon", "iconOffsetY", math.max(-100, math.min(100, Round(oy))))
    end
end

-- What a look holds: every field of o that differs from the bar's own (base).
local function LookDiff(o, base)
    local out
    for sec, fields in pairs(o) do
        if type(fields) == "table" then
            for k, v in pairs(fields) do
                local b = base[sec] and base[sec][k]
                local same = (type(v) == "table" and type(b) == "table" and #v == #b) or v == b
                if same and type(v) == "table" then
                    for i = 1, #v do if v[i] ~= b[i] then same = false break end end
                end
                if not same then
                    out = out or {}
                    out[sec] = out[sec] or {}
                    out[sec][k] = Copy(v)
                end
            end
        end
    end
    return out
end
IA.LookDiff = LookDiff

-- A resource bar's own looks (Core\AD_Looks.lua: rec.looks, by power or by spec, each only
-- what differs from the bar). An Automatic bar's per-power profiles: v1 keeps a whole look
-- per power (or per spec with its per-spec switch) and the saved display is the last one
-- shown, so each profile is mapped like the bar and kept as its differences. Runes: v1
-- colours them by spec (the game's three colours, which Arc Auras uses too) unless the
-- player set their own, or turned spec colours off for the bar colour.
IA.SNAP_TOP_KEY, IA.SNAP_TOP_LISTS = "_arcTopLevel", { "colorRanges", "abilityThresholds" }
IA.DK_SPEC_COLORS = { [250] = { 0.77, 0.12, 0.23, 1 }, [251] = { 0.2, 0.6, 1, 1 }, [252] = { 0, 0.8, 0.2, 1 } }
function IA.ResourceLooks(B, cfg, ctx)
    local tr = type(cfg.tracking) == "table" and cfg.tracking or {}
    local d = type(cfg.display) == "table" and cfg.display or {}
    local profiles = cfg.autoPowerProfiles
    if tr.resourceCategory == "autoPrimary" and type(profiles) == "table" then
        local bySpec = tr.usePerSpecProfiles == true
        local by = bySpec and "spec" or "power"
        local looks = { by = by, [by] = {} }
        for key, prof in pairs(profiles) do
            local ids = {}
            if bySpec then
                local idx = tonumber(tostring(key):match("^spec(%d+)$"))
                for id in pairs(idx and IA.Specs({ idx }, ctx.classID, ctx.opts) or {}) do ids[#ids + 1] = id end
            elseif type(key) == "number" then
                ids[1] = key
            end
            if #ids > 0 and type(prof) == "table" and type(prof.display) == "table" then
                local c2 = Copy(cfg)
                c2.autoPowerProfiles = nil
                c2.display = type(c2.display) == "table" and c2.display or {}
                for k, v in pairs(prof.display) do
                    if k ~= IA.SNAP_TOP_KEY then c2.display[k] = Copy(v) end
                end
                local top = prof.display[IA.SNAP_TOP_KEY]
                if type(top) == "table" then
                    for _, k in ipairs(IA.SNAP_TOP_LISTS) do if top[k] ~= nil then c2[k] = Copy(top[k]) end end
                end
                if prof.thresholds ~= nil then c2.thresholds = Copy(prof.thresholds) end
                local P = { barKind = "resource", o = {}, c = {}, driver = B.driver }
                IA.MapBarLook(P, IA.V1FillBar(c2, "resource"), IA.BAR_MAP, ctx)
                local diff = LookDiff(P.o, B.o)
                if diff then
                    for _, id in ipairs(ids) do looks[by][id] = Copy(diff) end
                end
            end
        end
        if next(looks[by]) then B.looks = looks end
        return
    end
    -- an Automatic bar's per-power colours without profiles: v1's panel sets and shows them
    -- but its bar never drew them, so the colour the player picked comes in per power
    if tr.resourceCategory == "autoPrimary" and type(d.autoPowerColors) == "table" then
        local looks = { by = "power", power = {} }
        for pt, col in pairs(d.autoPowerColors) do
            local cc = type(pt) == "number" and Color(col)
            if cc then looks.power[pt] = { fill = { color = cc }, resource = { usePowerColor = false } } end
        end
        if next(looks.power) then B.looks = looks end
        return
    end
    if tr.resourceCategory == "secondary" and tr.secondaryType == "runes" then
        local sc = d.fragmentedSpecColors
        if type(sc) == "table" and sc.enabled == true then
            local pips = B.o.resource and B.o.resource.style == "pips"
            local looks = { by = "spec", spec = {} }
            for id, def in pairs(IA.DK_SPEC_COLORS) do
                local col = Color(sc[id]) or def
                local o = { resource = { usePowerColor = false } }
                if pips then o.resource.pointColor = col else o.fill = { color = col } end
                looks.spec[id] = o
            end
            B.looks = looks
        elseif type(sc) == "table" then
            -- spec colours off: the bar colour
            Put(B.o, "resource", "usePowerColor", false)
        end
    end
end

-- AceDB's defaults (copyDefaults): every missing key takes its default, tables filled
-- key by key; on a copy, the save is never written.
local function V1FillDeep(saved, defaults, depth)
    for k, dv in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = Copy(dv)
        elseif type(dv) == "table" and type(saved[k]) == "table" and depth < 8 then
            V1FillDeep(saved[k], dv, depth + 1)
        end
    end
end
function IA.V1FillDeep(cfg, defaults)
    if type(cfg) ~= "table" or type(defaults) ~= "table" then return cfg end
    local out = Copy(cfg)
    V1FillDeep(out, defaults, 0)
    return out
end

-- v1's AceDB defaults name bars[1] and resourceBars[1] themselves, so those two
-- are saved stripped of every default value, down to a colour's channels (a
-- threshold layer saved as { enabled = true }), and AceDB fills them back whole
-- at load. Every other bar has only display and behavior filled (V1FillBar).
function IA.V1AceFirst(cfg, index, kind)
    if index ~= 1 or type(cfg) ~= "table" then return cfg end
    return IA.V1FillDeep(cfg, IA.V1BarDefaults(kind))
end

-- Two saved values the same (a colour key by key).
function IA.SameValue(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- A castbar as one cast type draws it: a key its cast-type categories keep per type comes
-- from that type's profile unless the category is shared (v1's panel starts on Hardcast,
-- so that is where its edits live).
function IA.CastFold(cfg, castType)
    local prof = type(cfg.profiles) == "table" and type(cfg.profiles[castType]) == "table" and cfg.profiles[castType] or nil
    if not prof then return cfg end
    local share = type(cfg.autoShareCategories) == "table" and cfg.autoShareCategories or {}
    local out = setmetatable({}, { __index = cfg })
    for k, v in pairs(prof) do
        local cat = (IA.V1.CASTBAR_CATEGORY or {})[k]
        if cat and not share[cat] then out[k] = v end
    end
    return out
end

-- v1 lines a bar up on a group by the left edges: TOP puts the bar's bottom-left on the
-- group's top-left, BOTTOM its top-left on the bottom-left, LEFT and RIGHT the facing
-- sides; "match slots only" centres a matched bar instead. A side anchor's match is the
-- group's height, which Arc Auras has no field for.
function IA.BarGroupAnchor(d)
    if not (d.anchorToGroup == true and type(d.anchorGroupName) == "string" and d.anchorGroupName ~= "") then return nil end
    local pt = d.anchorPoint or "BOTTOM"
    local match = d.matchGroupWidth == true
    local centred = match and d.matchSlotsOnly == true and d.matchIconEdges ~= true
    local src, dst
    if pt == "TOP" then
        src, dst = centred and "BOTTOM" or "BOTTOMLEFT", centred and "TOP" or "TOPLEFT"
    elseif pt == "LEFT" then
        src, dst, match = "RIGHT", "LEFT", false
    elseif pt == "RIGHT" then
        src, dst, match = "LEFT", "RIGHT", false
    else
        pt = "BOTTOM"
        src, dst = centred and "TOP" or "TOPLEFT", centred and "BOTTOM" or "BOTTOMLEFT"
    end
    return { kind = "group", group = d.anchorGroupName, src = src, dst = dst,
        x = tonumber(d.anchorOffsetX) or 0, y = tonumber(d.anchorOffsetY) or 0,
        match = match, adjust = tonumber(d.matchWidthAdjust) or 0 }
end

-- A castbar's look beyond its matrix rows: what Arc Auras' new-castbar template turns on
-- that v1 never drew, one text style for the name and the time, the flat background, the
-- hold, the ticks (the channel profile's when it turns them on), the channel colour, the
-- class or texture colours, a dragged icon.
function IA.CastLook(B, cfg, eff, unit, classID)
    local o = B.o
    local function Round(v) return math.floor(v + 0.5) end
    if unit == "player" then
        Put(o, "cast", "sparkOn", false)
        Put(o, "icon", "iconFollowBar", false)
    else
        Put(o, "icon", "iconShow", false)
        Put(o, "icon", "iconShield", false)
    end
    local size = tonumber(eff.fontSize)
    local tc = Color(eff.textColor)
    local ol = eff.textOutline ~= nil and IA.CONV.outline(eff.textOutline) or nil
    if size then Put(o, "text", "nameSize", Round(size)) Put(o, "text", "durSize", Round(size)) end
    if tc then Put(o, "text", "nameColor", tc) Put(o, "text", "durColor", tc) end
    if ol then Put(o, "text", "nameOutline", ol) Put(o, "text", "durOutline", ol) end
    Put(o, "text", "durAnchor", "RIGHT")
    Put(o, "text", "durOffsetX", -4)
    Put(o, "look", "bgTexture", "Flat")
    local bg = Color(eff.backgroundColor)
    if bg then
        Put(o, "look", "bgColor", { bg[1], bg[2], bg[3], 1 })
        Put(o, "look", "bgAlpha", bg[4] or 1)
    end
    local lvl = tonumber(cfg.barFrameLevel)
    if lvl then Put(o, "frame", "level", math.max(1, math.min(100, Round(lvl)))) end
    -- the hold: the player's flash keeps one colour for both endings and fades over its time
    if unit == "player" then
        if eff.interruptFeedbackEnabled == true then
            local ic = Color(eff.interruptColor)
            if ic then Put(o, "cast", "holdIntColor", ic) Put(o, "cast", "holdFailColor", ic) end
            local t = tonumber(eff.interruptFadeDuration)
            if t then Put(o, "cast", "holdTime", math.max(0.1, math.min(3, t))) end
        end
    else
        local t = tonumber(cfg.holdDuration)
        if t then Put(o, "cast", "holdTime", math.max(0.1, math.min(3, t))) end
    end
    -- ticks: the channel profile's own when it turns them on, else the folded ones
    local ch = IA.CastFold(cfg, "channel")
    local tk = (ch ~= cfg and ch.tickMarksEnabled == true) and ch or eff
    Put(o, "ticks", "ticksShow", tk.tickMarksEnabled == true)
    if tk.tickMarksEnabled == true then
        local custom = tk.tickMode == "custom"
        Put(o, "ticks", "tickMode", custom and "custom" or "percent")
        if custom then
            if type(tk.tickCustom) == "string" then Put(o, "ticks", "tickValues", tk.tickCustom) end
            Put(o, "ticks", "tickAsPercent", true)
        elseif tonumber(tk.tickPercent) then
            Put(o, "ticks", "tickPercent", math.max(5, math.min(50, Round(tonumber(tk.tickPercent)))))
        end
        if tk.tickShowOn == "channels" then Put(o, "ticks", "tickChannelOnly", true) end
        local tcol = Color(tk.tickMarksColor)
        if tcol then Put(o, "ticks", "tickColor", tcol) end
        if tonumber(tk.tickMarksThickness) then Put(o, "ticks", "tickThickness", Round(tonumber(tk.tickMarksThickness))) end
        local frac = tonumber(tk.tickMarksHeightFraction)
        if frac then Put(o, "ticks", "tickHeight", math.max(10, math.min(100, Round(frac * 100)))) end
        local ha = tk.tickHeightAnchor
        if ha then Put(o, "ticks", "tickHeightAnchor", (ha == "top" and "start") or (ha == "bottom" and "end") or "center") end
    end
    -- the channel colour: when colours are kept per cast type
    local share = type(cfg.autoShareCategories) == "table" and cfg.autoShareCategories or {}
    local chc = not share.colors and type(cfg.profiles) == "table" and type(cfg.profiles.channel) == "table"
        and Color(cfg.profiles.channel.barColor)
    if chc then
        Put(o, "fill", "castChannelOn", true)
        Put(o, "fill", "castChannelColor", chc)
    end
    -- a class colour: the player's bar only ever shows its own class
    if unit == "player" and eff.classColor == true then
        local CI = rawget(_G, "C_CreatureInfo")
        local info = CI and CI.GetClassInfo and classID and CI.GetClassInfo(classID)
        local rc = info and rawget(_G, "RAID_CLASS_COLORS") and RAID_CLASS_COLORS[info.classFile]
        if rc then
            local a = (Color(eff.barColor) or {})[4] or 1
            Put(o, "fill", "color", { rc.r, rc.g, rc.b, a })
        end
    end
    -- Use Texture Colors: a white fill (and channel colour), nothing tinting it
    if eff.useTextureColor == true then
        local a = (Color(eff.barColor) or {})[4] or 1
        Put(o, "fill", "color", { 1, 1, 1, a })
        if o.fill.castChannelOn then Put(o, "fill", "castChannelColor", { 1, 1, 1, a }) end
        Put(o, "fill", "castLockOn", false)
    end
    -- a dragged icon: v1 saved it from the bar's bottom-left corner
    if unit == "player" and cfg.iconMovable == true and type(cfg.iconPosition) == "table" then
        local S = tonumber(cfg.iconSize) or 20
        local H = tonumber(cfg.height) or 20
        local x, y = tonumber(cfg.iconPosition.x) or 0, tonumber(cfg.iconPosition.y) or 0
        Put(o, "icon", "iconSide", "LEFT")
        Put(o, "icon", "iconSpacing", 0)
        Put(o, "icon", "iconOffsetX", math.max(-100, math.min(100, Round(x + S))))
        Put(o, "icon", "iconOffsetY", math.max(-100, math.min(100, Round(y + S / 2 - H / 2))))
    end
end

-- v1's defaults for a bar of this kind ("aura" / "cdmbar" / "resource" / "cooldown"), as the
-- table its compaction compared against; nil for kinds it never compacted.
function IA.V1BarDefaults(kind)
    local V1 = IA.V1 or {}
    if kind == "aura" or kind == "cdmbar" then return V1.BAR_DEFAULTS end
    if kind == "resource" then return V1.RESOURCE_BAR_DEFAULTS end
    if kind == "cooldown" then return V1.CD_DISPLAY_DEFAULTS and { display = V1.CD_DISPLAY_DEFAULTS } end
    return nil
end
function IA.V1FillBar(cfg, kind)
    local defaults = IA.V1BarDefaults(kind)
    if type(cfg) ~= "table" or type(defaults) ~= "table" then return cfg end
    local out = Copy(cfg)
    V1Fill(out, defaults, 0)
    return out
end

function IA.MapBarLook(B, cfg, map, ctx)
    local cov = ctx.cov
    local o, c = B.o, B.c
    for path, row in pairs(map) do
        if not row.gap and not row.special then IA.MapRow(o, row, Leaf(cfg, path)) end
    end
    local d = type(cfg.display) == "table" and cfg.display or cfg
    local kind, isStack = B.barKind, B.barMode == "stack"
    if type(d.barOrientation) == "string" then Put(o, "fill", "orientation", (d.barOrientation:lower() == "vertical") and "VERTICAL" or "HORIZONTAL") end
    if d.tickMode == "all" or d.tickMode == "percent" or d.tickMode == "custom" then Put(o, "ticks", "tickMode", d.tickMode) end
    -- pips: v1 forces a primary power out of its point modes, so only a secondary gets them
    local secondary = type(cfg.tracking) == "table" and cfg.tracking.resourceCategory == "secondary"
    if secondary and (d.thresholdMode == "fragmented" or d.thresholdMode == "icons") then Put(o, "resource", "style", "pips") end
    -- folded in half: the first lap's colour is the fill's, the second its own
    if kind == "resource" and d.thresholdMode == "folded" then
        Put(o, "resource", "foldOn", true)
        local c1, c2 = Color(d.foldedColor1), Color(d.foldedColor2)
        if c1 then Put(o, "fill", "color", c1) end
        Put(o, "resource", "usePowerColor", false)
        if c2 then Put(o, "resource", "foldColor", c2) end
    end
    -- the colour v1 draws: the bar's own; with none, an Automatic bar its power's and a
    -- secondary its type's (the power colour), any other bar v1's light blue. Runes in
    -- their spec colours are looks (IA.ResourceLooks).
    if kind == "resource" then
        local tr = type(cfg.tracking) == "table" and cfg.tracking or {}
        local sc = d.fragmentedSpecColors
        local specRunes = tr.secondaryType == "runes" and (sc == nil or (type(sc) == "table" and sc.enabled))
        if not specRunes and d.thresholdMode ~= "folded" then
            if Color(d.barColor) then
                Put(o, "resource", "usePowerColor", false)
            elseif tr.resourceCategory ~= "autoPrimary" and tr.resourceCategory ~= "secondary" then
                Put(o, "resource", "usePowerColor", false)
                Put(o, "fill", "color", { 0.2, 0.8, 1, 1 })
            end
        end
    end
    local bx, by = IA.ScreenCenter(d.barPosition, tonumber(d.width) or 200, tonumber(d.height) or 20)
    B.pos = { x = bx or 0, y = by or 0 }
    B.anchor = IA.BarGroupAnchor(d)
    -- one font per bar: the first text font the player changed from v1's (stack, duration,
    -- name, recharge text), else the stack text's; with v1's defaults filled, a font left
    -- alone reads as its default
    local vd = IA.V1BarDefaults(kind)
    local dd = type(vd) == "table" and type(vd.display) == "table" and vd.display or {}
    local font
    for _, k in ipairs({ "font", "durationFont", "nameFont", "cdTextFont" }) do
        if d[k] ~= nil and d[k] ~= dd[k] then font = d[k] break end
    end
    font = font or d.font or d.durationFont or d.nameFont
    if font ~= nil then Put(o, "text", "font", IA.CONV.font(font)) end
    local function Round(v) return math.floor(tonumber(v) + 0.5) end
    -- a cooldown bar's charge text reads its own keys (v1's cooldown renderers never read
    -- the generic text anchor keys); elsewhere they stand in only when those are unset. A
    -- charge bar's recharge time is its timer text, and its strip is slotHeight thick.
    local cdBar = kind == "cooldown"
    if (cdBar or d.textAnchor == nil) and IA.CONV.barAnchor(d.chargeTextAnchor) then Put(o, "text", "stkAnchor", d.chargeTextAnchor) end
    if (cdBar or d.textAnchorOffsetX == nil) and tonumber(d.chargeTextOffsetX) then Put(o, "text", "stkOffsetX", Round(d.chargeTextOffsetX)) end
    if (cdBar or d.textAnchorOffsetY == nil) and tonumber(d.chargeTextOffsetY) then Put(o, "text", "stkOffsetY", Round(d.chargeTextOffsetY)) end
    if cdBar and isStack then
        if IA.CONV.barAnchor(d.timerTextAnchor) then Put(o, "text", "durAnchor", d.timerTextAnchor) end
        if tonumber(d.timerTextOffsetX) then Put(o, "text", "durOffsetX", Round(d.timerTextOffsetX)) end
        if tonumber(d.timerTextOffsetY) then Put(o, "text", "durOffsetY", Round(d.timerTextOffsetY)) end
        if (tonumber(d.slotHeight) or 0) >= 1 then Put(o, "size", "height", Round(d.slotHeight)) end
    end
    -- a free-dragged text: v1 saved a screen position (each renderer its own key); here it
    -- is offsets from the bar's centre
    local function FreeText(anchorKey, prefix, ...)
        if d[anchorKey] ~= "FREE" then return end
        Put(o, "text", prefix .. "Anchor", "CENTER")
        local p
        for i = 1, select("#", ...) do
            local v = d[select(i, ...)]
            if type(v) == "table" then p = v break end
        end
        local wide = tonumber(d[prefix == "name" and "nameTextFrameWidth" or prefix == "dur" and "durationTextFrameWidth"
            or "stackTextFrameWidth"]) or 60
        local x, y = IA.ScreenCenter(p, wide, 20)
        if x and y then
            Put(o, "text", prefix .. "OffsetX", Round(x - B.pos.x))
            Put(o, "text", prefix .. "OffsetY", Round(y - B.pos.y))
        end
    end
    FreeText("textAnchor", "stk", "textPosition")
    FreeText("durationAnchor", "dur", cdBar and "durationTextPosition" or "durationPosition")
    FreeText("nameAnchor", "name", cdBar and "nameTextPosition" or "namePosition")
    if cdBar and isStack then FreeText("timerTextAnchor", "dur", "timerTextPosition") end
    if cdBar and isStack then IA.ChargeBox(B, o, d) end
    -- a free-dragged side icon: the side its spot is nearest, the rest as offsets from where
    -- Arc Auras puts the icon on that side
    if d.barIconAnchor == "FREE" then
        local size = tonumber(d.barIconSize) or 24
        local ix, iy = IA.ScreenCenter(d.barIconPosition, size, size)
        if ix and iy then
            local w, h = tonumber(d.width) or 200, tonumber(d.height) or 20
            local gap = tonumber(d.iconBarSpacing) or 2
            local dx, dy = ix - B.pos.x, iy - B.pos.y
            local side, hx, hy
            if math.abs(dx) * h >= math.abs(dy) * w then
                side = (dx < 0) and "LEFT" or "RIGHT"
                hx, hy = ((dx < 0) and -1 or 1) * (w / 2 + gap + size / 2), 0
            else
                side = (dy < 0) and "BOTTOM" or "TOP"
                hx, hy = 0, ((dy < 0) and -1 or 1) * (h / 2 + gap + size / 2)
            end
            Put(o, "icon", "iconSide", side)
            Put(o, "icon", "iconOffsetX", math.max(-100, math.min(100, Round(dx - hx))))
            Put(o, "icon", "iconOffsetY", math.max(-100, math.min(100, Round(dy - hy))))
        end
    end
    -- a resource bar's main text is its resource text
    if kind == "resource" and o.text then
        for _, f in ipairs({ "Show", "Size", "Color", "Outline", "Shadow", "Anchor", "OffsetX", "OffsetY" }) do
            if o.text["stk" .. f] ~= nil then
                o.text["res" .. f] = o.text["stk" .. f]
                o.text["stk" .. f] = nil
            end
        end
    end
    -- the fill inset: the largest of v1's four sides
    local inset = 0
    for _, side in ipairs({ "L", "R", "T", "B" }) do inset = math.max(inset, tonumber(d["barPadding" .. side]) or 0) end
    if inset > 0 then Put(o, "fill", "fillInset", math.floor(inset + 0.5)) end
    -- duration colour bands: v1's colour curve, behind its master switch; bands 2 to 5 (a
    -- band never set takes v1's value and colour for that bar kind) in value order, the
    -- most urgent three in Arc Auras' three slots. A cooldown bar's seconds count against
    -- its real cooldown, as v1's panel promises (v1 divided by a typed 30 s); an aura
    -- bar's against v1's typed length, which Arc Auras needs for an aura too
    if d.durationColorCurveEnabled == true and (kind == "aura" or kind == "cooldown") then
        local V1 = IA.V1
        local DV = (kind == "aura") and V1.DURATION_THRESHOLD_DEFAULT_VALUES or V1.CD_THRESHOLD_DEFAULT_VALUES
        local DC = (kind == "aura") and V1.DURATION_THRESHOLD_DEFAULT_COLORS or V1.CD_THRESHOLD_DEFAULT_COLORS
        local bands = {}
        for i = 2, 5 do
            if d["durationThreshold" .. i .. "Enabled"] == true then
                local v = tonumber(d["durationThreshold" .. i .. "Value"]) or DV[i]
                if v then bands[#bands + 1] = { v = v, c = Color(d["durationThreshold" .. i .. "Color"]) or Color(DC[i]) } end
            end
        end
        table.sort(bands, function(a, b) return a.v < b.v end)
        if #bands > 0 then
            for n = 1, math.min(3, #bands) do
                Put(o, "thresholds", "thresh" .. (n + 1) .. "Value", bands[n].v)
                if bands[n].c then Put(o, "thresholds", "thresh" .. (n + 1) .. "Color", bands[n].c) end
            end
            Put(o, "thresholds", "threshEnabled", true)
            Put(o, "thresholds", "threshCount", math.min(3, #bands))
            Put(o, "thresholds", "threshAsSeconds", d.durationThresholdAsSeconds == true)
            if kind == "aura" then
                local ref = tonumber(d.durationThresholdMaxDuration) or 30
                if ref > 0 then Put(o, "thresholds", "threshRef", math.floor(ref + 0.5)) end
            end
        end
    end
    -- colour layers by value: v1's threshold layers, colour ranges and per-stack colours
    IA.MapLayers(o, cfg, d, kind, isStack)
    -- the full colour: by bar kind
    local maxc = d.enableMaxColor == true and Color(d.maxColor)
    if maxc then
        if kind == "resource" then
            Put(o, "powerthresholds", "pthFullEnabled", true) Put(o, "powerthresholds", "pthFullColor", maxc)
        elseif kind == "cooldown" then
            Put(o, "segments", "fullColorEnabled", true) Put(o, "segments", "fullColor", maxc)
        else
            Put(o, "stackcolors", "maxColorEnabled", true) Put(o, "stackcolors", "maxColor", maxc)
        end
    end
    -- cost ticks and the cast cost forecast: a v1 tick naming a spell follows
    -- its cost; one holding a typed number (the custom mode's list) is a
    -- custom tick in power units
    local ids, costs = {}, {}
    for _, t in pairs(type(cfg.abilityThresholds) == "table" and cfg.abilityThresholds or {}) do
        local on = not (type(t) == "table" and t.enabled == false)
        local sid = type(t) == "table" and tonumber(t.spellID) or tonumber(t)
        local cost = type(t) == "table" and tonumber(t.cost)
        if on and sid and sid > 0 then
            ids[#ids + 1] = sid
        elseif on and cost and cost > 0 then
            costs[#costs + 1] = cost
        end
    end
    if #ids > 0 then
        table.sort(ids)
        Put(o, "ticks", "tickSpells", table.concat(ids, ","))
        Put(o, "ticks", "ticksShow", true)
    end
    if kind == "resource" and #costs > 0 and d.tickMode == "custom" then
        table.sort(costs)
        for i, v in ipairs(costs) do costs[i] = (v == math.floor(v)) and tostring(math.floor(v)) or tostring(v) end
        Put(o, "ticks", "tickValues", table.concat(costs, ","))
        Put(o, "ticks", "tickAsPercent", false)
    end
    -- the cast forecast follows v1's Show prediction switch (its spell list is seeded on
    -- every soul shard bar, switched on or not)
    if kind == "resource" and d.showPrediction == true then
        Put(o, "predict", "predictEnabled", true)
        local pc = Color(d.predCostColor)
        if pc then
            Put(o, "predict", "predictColor", { pc[1], pc[2], pc[3], 1 })
            Put(o, "predict", "predictAlpha", math.max(0.1, math.min(1, pc[4] or 1)))
        end
    end
    -- the texts' own bands (v1's text colour thresholds, in percent)
    if kind == "resource" and d.textColorThresholdEnabled == true then
        local n = 0
        for i = 1, 4 do
            local key = "textColorThresholdT" .. i
            local v = tonumber(d[key .. "Value"])
            if d[key .. "Enabled"] == true and v then
                n = n + 1
                Put(o, "ptextcolors", "ptx" .. (n + 1) .. "Value", math.floor(v + 0.5))
                local col = Color(d[key .. "Color"])
                if col then Put(o, "ptextcolors", "ptx" .. (n + 1) .. "Color", col) end
            end
        end
        if n > 0 then
            Put(o, "ptextcolors", "ptxEnabled", true)
            Put(o, "ptextcolors", "ptxCount", n)
            Put(o, "ptextcolors", "ptxDirection", (d.textColorThresholdFill == true) and "above" or "below")
            local bc = Color(d.textColorThresholdBaseColor)
            if bc then Put(o, "ptextcolors", "ptxBaseColor", bc) end
        end
    end
    -- the background: v1 draws "Solid" (its default) flat; Arc Auras' empty is the fill texture
    if d.backgroundTexture == nil or d.backgroundTexture == "Solid" then Put(o, "look", "bgTexture", "Flat") end
    -- the background: v1 keeps its opacity in the colour, Arc Auras on its own row
    local bgc = Color(d.backgroundColor)
    if bgc then
        Put(o, "look", "bgColor", { bgc[1], bgc[2], bgc[3], 1 })
        Put(o, "look", "bgAlpha", bgc[4] or 1)
    end
    -- the gradient: v1 blends its end toward the second colour by the intensity (0.5 when
    -- unset); Arc Auras lays that colour over the fill at that opacity, the same end colour
    if d.useGradient == true then
        local sc = Color(d.gradientSecondColor) or { 0, 0, 0, 1 }
        local k = tonumber(d.gradientIntensity) or 0.5
        Put(o, "fill", "gradientColor", { sc[1], sc[2], sc[3], math.max(0, math.min(1, k)) })
    end
    if cdBar then
        -- a duration bar's own background, a charge bar's slots' (both win over the box's)
        local show, col, tex
        if isStack then show, col, tex = d.showSlotBackground, d.slotBackgroundColor, d.slotBackgroundTexture
        else show, col, tex = d.showBarBackground, d.barBackgroundColor, d.texture end
        if show ~= nil then Put(o, "look", "bgShow", show ~= false) end
        local c2 = Color(col)
        if c2 then
            Put(o, "look", "bgColor", { c2[1], c2[2], c2[3], 1 })
            Put(o, "look", "bgAlpha", c2[4] or 1)
        end
        if type(tex) == "string" and tex ~= "" then Put(o, "look", "bgTexture", (tex == "Solid") and "Flat" or tex) end
        -- each available charge in its own full colour
        if d.useDifferentFullColor == true then
            Put(o, "segments", "fullColorEnabled", true)
            local fc = Color(d.fullChargeColor)
            if fc then Put(o, "segments", "fullColor", fc) end
        end
        -- the Ready word, or v1's "0" in the time text's place (the "0" wins, as in v1)
        if d.showZeroWhenReady == true then
            Put(o, "text", "readyShow", true)
            Put(o, "text", "readyText", "0")
            local dc = Color(d.durationColor)
            if dc then Put(o, "text", "readyColor", dc) end
        else
            if d.showReadyText ~= nil then Put(o, "text", "readyShow", d.showReadyText == true) end
            if type(d.readyText) == "string" and d.readyText ~= "" then Put(o, "text", "readyText", d.readyText) end
            local rc = Color(d.readyColor)
            if rc then Put(o, "text", "readyColor", rc) end
        end
        -- while "Color by usable state" is on, its usable colour is the stack text's
        if d.textColorByState == true then
            local uc = Color(d.textUsableColor)
            if uc then Put(o, "text", "stkColor", uc) end
        end
    end
    if kind == "resource" then
        local pt = B.driver and tonumber(B.driver.powerType)
        local recharges = pt == 5 or pt == 19
        local pointMode = secondary and (d.thresholdMode == "fragmented" or d.thresholdMode == "icons")
        if recharges then
            -- the recharge countdown: v1's own keys, else the older names of its mode
            local icons = d.thresholdMode == "icons"
            local function Pick(own, frag, icon)
                if d[own] ~= nil then return d[own] end
                if icons then return d[icon] end
                return d[frag]
            end
            local show = Pick("cdTextShow", "fragmentedShowSegmentText", "iconsShowCooldownText")
            if show ~= nil then Put(o, "text", "rcShow", show == true) end
            local size = tonumber(Pick("cdTextSize", "fragmentedTextSize", "iconsCooldownTextSize"))
            if size then Put(o, "text", "rcSize", Round(size)) end
            local ox = tonumber(Pick("cdTextOffsetX", "fragmentedTextOffsetX", "iconsCDTextOffsetX"))
            local oy = tonumber(Pick("cdTextOffsetY", "fragmentedTextOffsetY", "iconsCDTextOffsetY"))
            if ox then Put(o, "text", "rcOffsetX", Round(ox)) end
            if oy then Put(o, "text", "rcOffsetY", Round(oy)) end
            if d.cdTextOutline ~= nil then Put(o, "text", "rcOutline", IA.CONV.outline(d.cdTextOutline)) end
            local tc = Color(d.cdTextColor)
            if tc then Put(o, "text", "rcColor", tc) end
            local prec = tonumber(d.cdTextDecimalPrecision)
            if prec then
                Put(o, "text", "rcDecimalsEnabled", prec > 0)
                if prec > 0 then Put(o, "text", "rcDecimalThreshold", 60) end
            end
            -- a recharging point: v1's own colour (its grey when unset), or "Auto Charging"
            -- (the ready colour dimmed: Arc Auras' own colour at half)
            if d.smartChargingColor == true then
                Put(o, "resource", "rechargeColorEnabled", false)
            else
                Put(o, "resource", "rechargeColorEnabled", true)
                Put(o, "resource", "rechargeColor", Color(d.fragmentedChargingColor) or { 0.4, 0.4, 0.4, 1 })
            end
        end
        if pointMode and d.thresholdMode == "fragmented" then
            -- v1 stands point rows up by their own switch, not the bar's orientation
            local standing = d.fragmentedLayoutDirection == "vertical"
            Put(o, "fill", "orientation", standing and "VERTICAL" or "HORIZONTAL")
            if recharges then
                local up = d.fragmentedFillOrientation == "vertical"
                Put(o, "resource", "rechargeDir", (up == standing) and "bar" or (up and "up" or "right"))
            end
        elseif pointMode then
            -- rune / essence icons in a row are pips; a triangle comes in as the nearest, a diamond
            if tonumber(d.iconsSpacing) then Put(o, "resource", "pipSpacing", Round(d.iconsSpacing)) end
            local sz = tonumber(d.iconsSize)
            if sz and sz >= 1 then
                Put(o, "resource", "pipWidth", Round(sz))
                Put(o, "resource", "pipHeight", Round(sz))
            end
            local sh = type(d.iconsShape) == "string" and d.iconsShape or "square"
            Put(o, "resource", "pipShape", (sh:find("^circle") and "circle") or (sh:find("^triangle") and "diamond") or "square")
        end
        -- percent text without its sign
        if d.textFormat == "percent" and d.textShowPercentSymbol == false then Put(o, "text", "resFormat", "pctnum") end
        -- v1 always shows Animacharged combo points (it has no off switch)
        if pt == 4 then
            Put(o, "resource", "chargedShow", true)
            local cc = Color(d.chargedComboColor)
            if cc then Put(o, "resource", "chargedColor", cc) end
        end
    end
    -- "Use Texture Colors": the fill stays white so a coloured texture shows as drawn, and no
    -- colour rule paints it
    if d.useTextureColor == true then
        Put(o, "fill", "color", { 1, 1, 1, 1 })
        Put(o, "fill", "useGradient", false)
        if kind == "resource" then Put(o, "resource", "usePowerColor", false) end
        o.thresholds, o.stackcolors, o.powerthresholds = nil, nil, nil
    end
    -- a row of points shows its own colour in the point colour (the fill is hidden there)
    if kind == "resource" and o.resource and o.resource.style == "pips" and o.resource.usePowerColor == false
        and o.fill and o.fill.color then
        Put(o, "resource", "pointColor", Copy(o.fill.color))
    end
    -- v1 keeps a bar's length in width and its thickness in height and draws a vertical
    -- bar turned (SetSize(height, width) in every bar kind); ours are the frame's own width
    -- and height, so a vertical bar comes in standing. Its icon side and gradient are on the
    -- screen in both. Point rows and charge boxes size their cells themselves.
    if type(d.barOrientation) == "string" and d.barOrientation:lower() == "vertical" then
        local cells = (kind == "resource" and o.resource and o.resource.style == "pips")
            or (kind == "cooldown" and isStack)
        local sz = o.size
        if not cells and sz and tonumber(sz.width) and tonumber(sz.height) then
            sz.width, sz.height = sz.height, sz.width
        end
    end
    local bh = type(cfg.behavior) == "table" and cfg.behavior or {}
    local vis = bh.hideWhen
    if bh.hideOutOfCombat == true then
        vis = type(vis) == "table" and Copy(vis) or {}
        vis.hideOOC = true
    end
    IA.HideWhen(c, vis, bh.hideLogic, bh.hideWhenAlpha)
    local specs = IA.Specs(bh.showOnSpecs, ctx.classID, ctx.opts)
    if specs then c.specs = specs end
    IA.Talents(c, bh.talentConditions, bh.talentMatchMode)
end

-- A resource bar's colour bands as v1 drew them: its colour-curve keys, else (a save
-- still in the old granular or threshold mode) the layers table v1 moves there at load.
-- A primary power's curve reads percent unless told otherwise and drains; a secondary
-- power's direct compare reads percent only past a max of 30 (none gets there) and fills.
function IA.ResourceBands(o, cfg, d, layers)
    local DV, DC = IA.V1.RESOURCE_THRESHOLD_DEFAULT_VALUES, IA.V1.RESOURCE_THRESHOLD_DEFAULT_COLORS
    local secondary = type(cfg.tracking) == "table" and cfg.tracking.resourceCategory == "secondary"
    -- only v1's colour-curve mode draws bands (its simple mode the base and max colours
    -- alone); the old granular and threshold modes become it at load
    local mode = d.thresholdMode
    local old = mode == "granular" or mode == "threshold"
    if not (mode == "colorCurve" or old) then return end
    local bands, pct = {}, nil
    if d.colorCurveEnabled == true then
        pct = d.colorCurveThresholdAsPercent
        for i = 2, 5 do
            if d["colorCurveThreshold" .. i .. "Enabled"] == true then
                bands[#bands + 1] = { v = tonumber(d["colorCurveThreshold" .. i .. "Value"]) or DV[i],
                    c = Color(d["colorCurveThreshold" .. i .. "Color"]) or Color(DC[i]) }
            end
        end
    elseif old then
        pct = d.thresholdAsPercent or false
        for i = 2, 5 do
            local t = layers[i]
            if type(t) == "table" and t.enabled == true then
                bands[#bands + 1] = { v = tonumber(t.minValue) or DV[i], c = Color(t.color) or Color(DC[i]) }
            end
        end
    end
    if #bands == 0 then return end
    local asPercent
    if secondary then asPercent = pct == true else asPercent = pct ~= false end
    local filling = d.colorCurveDirection == "fill" or d.colorCurveDirectionFilling == true
    if secondary and d.colorCurveDirection == nil and not d.colorCurveDirectionFilling then filling = true end
    for n = 1, math.min(4, #bands) do
        Put(o, "powerthresholds", "pth" .. (n + 1) .. "Value", math.floor(bands[n].v + 0.5))
        if bands[n].c then Put(o, "powerthresholds", "pth" .. (n + 1) .. "Color", bands[n].c) end
    end
    Put(o, "powerthresholds", "pthEnabled", true)
    Put(o, "powerthresholds", "pthCount", math.min(4, #bands))
    Put(o, "powerthresholds", "pthDirection", filling and "above" or "below")
    Put(o, "powerthresholds", "pthAbsolute", not asPercent)
end

-- v1's lit-count colours: every lit point in one colour by how many are lit (up to three
-- ranges, the last matching wins) as bands at or above each count where the colour changes;
-- a colour from 1 up is the bar's own. v1 skipped them while the count was secret, so they
-- never showed on a primary power in combat; bands do.
function IA.ActiveCountBands(o, cfg, d)
    if d.enableActiveCountColors ~= true or type(d.activeCountColors) ~= "table" then return end
    if o.powerthresholds and o.powerthresholds.pthEnabled then return end
    local tr = type(cfg.tracking) == "table" and cfg.tracking or {}
    local conds = {}
    for i = 1, 3 do
        local cd = d.activeCountColors[i]
        local col = type(cd) == "table" and (i == 1 or cd.enabled) and Color(cd.color)
        if col then conds[#conds + 1] = { from = tonumber(cd.from) or 1, to = tonumber(cd.to) or 99, c = col } end
    end
    if #conds == 0 then return end
    local function At(v)
        local c
        for _, cd in ipairs(conds) do if v >= cd.from and v <= cd.to then c = cd.c end end
        return c
    end
    local top = math.max(1, math.min(20, math.floor(tonumber(tr.maxValue) or tonumber(tr.maxStacks) or 10)))
    local bands, prev = {}, nil
    for v = 1, top do
        local c = At(v)
        if not IA.SameValue(c, prev) then bands[#bands + 1] = { v = v, c = c } end
        prev = c
    end
    -- (a row of points takes this as its point colour at the end of MapBarLook)
    if bands[1] and bands[1].v == 1 and bands[1].c then
        Put(o, "fill", "color", bands[1].c)
        Put(o, "resource", "usePowerColor", false)
        table.remove(bands, 1)
    end
    local base = o.resource and o.resource.usePowerColor == false and o.fill and o.fill.color
    local n = 0
    for _, b in ipairs(bands) do
        local c = b.c or base
        if not c or n >= 4 then break end
        n = n + 1
        Put(o, "powerthresholds", "pth" .. (n + 1) .. "Value", b.v)
        Put(o, "powerthresholds", "pth" .. (n + 1) .. "Color", c)
    end
    if n > 0 then
        Put(o, "powerthresholds", "pthEnabled", true)
        Put(o, "powerthresholds", "pthCount", n)
        Put(o, "powerthresholds", "pthDirection", "above")
        Put(o, "powerthresholds", "pthAbsolute", true)
    end
end

-- v1 coloured a bar by its value three ways: threshold layers ({ enabled, minValue,
-- maxValue, color }; layer 1 is the base), colour ranges ({ from, to, color }) and
-- per-stack colours ({ [n] = color }, segmented). A resource bar takes them as
-- power thresholds, a stack bar as stack colours, a charge bar as its full colour.
function IA.MapLayers(o, cfg, d, kind, isStack)
    local layers = type(cfg.thresholds) == "table" and cfg.thresholds or {}
    local perStack = type(cfg.stackColors) == "table" and cfg.stackColors or {}
    if kind == "resource" then
        -- layer 1 is only ever a copy of the bar colour: v1 draws the bar colour (or its
        -- fallback), never the layer
        IA.ResourceBands(o, cfg, d, layers)
        -- pips: each its own colour (a secondary power in a point mode)
        local pointMode = type(cfg.tracking) == "table" and cfg.tracking.resourceCategory == "secondary"
            and (d.thresholdMode == "fragmented" or d.thresholdMode == "icons")
        local pips = pointMode and type(d.fragmentedColors) == "table" and d.fragmentedColors or {}
        local m = 0
        for i = 2, 4 do
            local col = Color(pips[i])
            if col then
                m = m + 1
                Put(o, "stackcolors", "sc" .. i .. "Value", i)
                Put(o, "stackcolors", "sc" .. i .. "Color", col)
            end
        end
        if m > 0 then
            Put(o, "stackcolors", "scEnabled", true)
            Put(o, "stackcolors", "scCount", m)
            Put(o, "stackcolors", "scPosition", true)
            local first = Color(pips[1])
            if first and d.barColor == nil then
                Put(o, "fill", "color", first)
                Put(o, "resource", "usePowerColor", false)
            end
        end
        IA.ActiveCountBands(o, cfg, d)
        return
    end
    if kind == "cooldown" then
        -- charges: the layer that starts at the last charge is the full colour
        local maxc = tonumber(cfg.tracking and cfg.tracking.maxStacks)
        for i = 2, 4 do
            local t = layers[i]
            if type(t) == "table" and t.enabled == true and maxc and tonumber(t.minValue) == maxc and Color(t.color) then
                Put(o, "segments", "fullColorEnabled", true)
                Put(o, "segments", "fullColor", Color(t.color))
            end
        end
        return
    end
    if not isStack then return end
    -- A stack bar draws colour bands in one mode only (v1 Display ~2981 / 3122):
    -- segmented ("perStack") paints each stack's own colour (cfg.stackColors; its
    -- colour ranges only feed those through the options), granular ("Thresholds"
    -- ticked) the threshold layers, simple and folded neither. Ranges left from
    -- another mode never count.
    local n = 0
    local function Band(from, col)
        if n >= 3 or not (from and col) then return end
        n = n + 1
        Put(o, "stackcolors", "sc" .. (n + 1) .. "Value", math.floor(from + 0.5))
        Put(o, "stackcolors", "sc" .. (n + 1) .. "Color", col)
    end
    local mode = d.thresholdMode or "simple"
    local maxS = tonumber(cfg.tracking and cfg.tracking.maxStacks) or 10
    if mode == "perStack" then
        -- each stack its own colour (none = the bar colour): a band where it changes
        local first = Color(perStack[1])
        local base = Color(d.barColor) or first
        local prev = first or base
        for i = 2, math.min(maxS, 99) do
            local c = Color(perStack[i]) or base
            if c and not IA.SameValue(c, prev) then
                Band(i, c)
                prev = c
            end
        end
        if n > 0 then Put(o, "stackcolors", "scPosition", true) end
        if first and d.barColor == nil then Put(o, "fill", "color", first) end
    elseif mode == "granular" then
        -- v1's GetThresholdValue: an unset value is its layer's share of the max,
        -- "As %" a percent of it; the bands go up in order of where they start
        local SHARE = { 0.5, 0.8, 0.5, 0.7, 0.9 }
        local list = {}
        for i = 2, 6 do
            local t = layers[i]
            local col = type(t) == "table" and t.enabled == true and Color(t.color)
            if col then
                local v = tonumber(t.minValue) or math.floor(maxS * SHARE[i - 1])
                if d.thresholdAsPercent == true then v = math.floor(maxS * v / 100) end
                list[#list + 1] = { from = v, c = col, i = i }
            end
        end
        table.sort(list, function(a, b)
            if a.from ~= b.from then return a.from < b.from end
            return a.i < b.i
        end)
        for _, b in ipairs(list) do Band(b.from, b.c) end
        local first = type(layers[1]) == "table" and layers[1].enabled ~= false and Color(layers[1].color)
        if first and d.barColor == nil then Put(o, "fill", "color", first) end
    end
    if n > 0 then
        Put(o, "stackcolors", "scEnabled", true)
        Put(o, "stackcolors", "scCount", n)
    end
end

-- A table's keys, numbers first in order, then the rest by name: a stable order
-- for the lists v1 keeps by index or spell id.
function IA.OrderedKeys(t)
    local keys = {}
    for k in pairs(type(t) == "table" and t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local na, nb = type(a) == "number", type(b) == "number"
        if na ~= nb then return na end
        if na then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- The aura IDs a v1 bar's Cooldown Manager entries match (its entry, then its alternates),
-- the picture's first; nil without the game or without an entry on a spell.
function IA.CdmAuraIDs(opts, tr)
    if not (opts and opts.cooldown) then return nil end
    local list = {}
    if tonumber(tr.cooldownID) then list[1] = tonumber(tr.cooldownID) end
    for _, alt in ipairs(type(tr.alternateCooldownIDs) == "table" and tr.alternateCooldownIDs or {}) do
        if tonumber(alt) then list[#list + 1] = tonumber(alt) end
    end
    local ids, seen = {}, {}
    for _, cd in ipairs(list) do
        local info = cd > 0 and opts.cooldown(cd) or nil
        if type(info) == "table" and tonumber(info.spellID) and info.spellCategoryID == nil then
            for _, id in ipairs(NS.CDMMirror.AuraIDs(info)) do
                if not seen[id] then
                    seen[id] = true
                    ids[#ids + 1] = id
                end
            end
        end
    end
    return (#ids > 0) and ids or nil
end

-- A summon's spell as its Cooldown Manager entry shows it (the tooltip override
-- first: an entry may rest on a spec passive), the spell a totem bar follows.
function IA.SummonSpell(opts, cooldownID)
    local info = opts and opts.cooldown and cooldownID and opts.cooldown(cooldownID)
    local M = NS.CDMMirror
    if type(info) ~= "table" or info.spellCategoryID ~= nil or not (M and M.ArtSpell) then return nil end
    return M.ArtSpell(info)
end

-- The per-character bar stores -> plan bars (the character's bars layout; its cast bars,
-- one per character in v1, go to own, the character's layout). Each bar is its own pick,
-- keyed by where v1 keeps it so the key outlives a session; a bar of a kind the import
-- does not carry yet goes on L.later.
-- v1's timer bars (their own engine, Bars\ArcUI_CooldownBars.lua) -> Custom Bars (barKind
-- "timer", the rules of Drivers\AD_DriverCustom.lua): Timer mode runs the timer, Stack mode
-- counts stacks, Toggle mode is a stack of one its trigger turns on and off.
local TIMER_RULES = { special = "timerRules" }
IA.TIMER_MAP = {
    ["tracking.enabled"] = { special = "identity" }, ["tracking.timerID"] = { special = "identity" },
    ["tracking.barType"] = { special = "identity" }, ["tracking.preset"] = { gap = "a label v1 never applies", nv = true },
    ["tracking.barMode"] = { special = "timerMode" }, ["tracking.unlimitedDuration"] = { special = "timerMode" },
    ["tracking.barName"] = { special = "timerName" },
    ["tracking.iconTextureID"] = { special = "timerArt" }, ["tracking.iconOverride"] = { special = "timerArt" },
    ["tracking.triggerAuraID"] = { special = "timerArt" },
    ["tracking.triggerType"] = TIMER_RULES, ["tracking.triggerSpellID"] = TIMER_RULES,
    ["tracking.triggerCooldownID"] = TIMER_RULES, ["tracking.auraType"] = TIMER_RULES,
    ["tracking.customDuration"] = TIMER_RULES, ["tracking.resetOnRetrigger"] = TIMER_RULES,
    ["tracking.resetOnDeath"] = TIMER_RULES, ["tracking.cancelMethod"] = TIMER_RULES,
    ["tracking.cancelSpellID"] = TIMER_RULES, ["tracking.cancelCooldownID"] = TIMER_RULES,
    ["tracking.maxStacks"] = TIMER_RULES, ["tracking.stackDuration"] = TIMER_RULES,
    ["tracking.stackExpireByDuration"] = TIMER_RULES, ["tracking.stackResetOnDeath"] = TIMER_RULES,
    ["tracking.generators"] = TIMER_RULES, ["tracking.spenders"] = TIMER_RULES, ["tracking.suppressors"] = TIMER_RULES,
}
IA.V1_TIMER_EVENT = { spellcast = "cast", glowShow = "proc_on", glowHide = "proc_off" }

-- One v1 timer bar -> a plan Custom Bar, or nil and why (to finish "Arc UI's bar ...").
function IA.MapTimerBar(cfg, ctx)
    local cov = ctx.cov
    local tr = type(cfg.tracking) == "table" and cfg.tracking or {}
    local function Note(k, why) Dropped(cov, "timer:" .. k, why) end
    local function Id(v)
        v = tonumber(v)
        return (v and v > 0) and math.floor(v) or nil
    end
    local function Hears(r, ids)
        r.spellID = ids[1]
        if #ids > 1 then
            local l = {}
            for i, v in ipairs(ids) do l[i] = v end
            r.spellIDs = l
        end
        return r
    end
    local maxSecs = (NS.Schema and NS.Schema.CUSTOM_MAX_SECONDS) or 7200
    local maxIds = (NS.Schema and NS.Schema.CUSTOM_RULE_MAX_SPELLS) or 13
    local stack = tr.barMode == "stack"
    local toggle = not stack and tr.unlimitedDuration == true
    local d, rules = {}, {}
    local function Add(r)
        rules[#rules + 1] = r
        return #rules
    end
    local B = { barKind = "timer", barMode = (stack or toggle) and "stack" or "duration", o = {}, c = {}, driver = d }
    if not stack then
        local trig = tr.triggerType or "spellcast"
        local tsid = Id(tr.triggerSpellID)
        if trig == "spellcastSent" then return nil, "starts on a cast's press, which Custom Bars cannot hear yet." end
        if trig ~= "spellcast" then return nil, "starts on a Cooldown Manager aura, which Custom Bars cannot hear yet." end
        if not tsid then return nil, "never had a spell picked to start it." end
        d.spellID = tsid
        if toggle then
            local method = tr.cancelMethod or "sameSpell"
            local cid = Id(tr.cancelSpellID)
            if method == "auraLost" or method == "auraGained" then
                return nil, "turns off on a Cooldown Manager aura, which Custom Bars cannot hear yet."
            end
            d.maxStacks, d.showWhile = 1, "stacks"
            if tr.resetOnDeath ~= false then Add({ when = "cond_on", cond = "dead", act = "set" }) end
            local on = Add({ when = "cast", spellID = tsid, act = "set", n = 1, stacksMax = 0 })
            if method == "differentSpell" and cid then
                Add({ when = "cast", spellID = cid, act = "set", stacksMin = 1 })
            elseif method == "overlayHide" then
                Add({ when = "proc_off", spellID = cid or tsid, act = "set", stacksMin = 1 })
            else
                -- the same cast turns it off, never the cast that just turned it on
                Add({ when = "cast", spellID = tsid, act = "set", stacksMin = 1, withinRule = on, withinSecs = 0.1, withinNot = true })
            end
            Note("limit.toggle readout", "a toggle shows its stack, not v1's endless sign")
        else
            local dur = tonumber(tr.customDuration) or 10
            if dur > maxSecs then Note("tracking.customDuration", "a timer runs two hours at most") end
            d.duration = math.min(math.max(dur, 0.1), maxSecs)
            d.showWhile = "timer"
            if tr.resetOnDeath ~= false then Add({ when = "cond_on", cond = "dead", timer = "running", act = "reset" }) end
            Add({ when = "cast", spellID = tsid, act = "start", mode = (tr.resetOnRetrigger == false) and "idle" or nil })
            Note("limit.idle fill", "an idle timer bar shows empty; v1 drew it full")
        end
    else
        d.maxStacks = math.max(1, math.min(99, math.floor(tonumber(tr.maxStacks) or 4)))
        local expire = tr.stackExpireByDuration ~= false
        if expire then
            d.duration = math.min(math.max(tonumber(tr.stackDuration) or 20, 0.1), maxSecs)
            d.clearOnEnd = true
        end
        d.showWhile = "stacks"
        if tr.stackResetOnDeath ~= false then Add({ when = "cond_on", cond = "dead", act = "reset" }) end
        -- the casts that hold the spenders back: one rule that only marks the moment
        local supIds, supSecs, lens = {}, 0, {}
        for _, sp in ipairs(type(tr.suppressors) == "table" and tr.suppressors or {}) do
            if type(sp) == "table" then
                local sid, secs = Id(sp.spellID), tonumber(sp.duration) or 0
                if (sp.triggerType or "spellcast") ~= "spellcast" then
                    Note("suppressor." .. tostring(sp.triggerType), "a hold on spenders by a Cooldown Manager aura is not offered yet")
                elseif sid and secs > 0 and #supIds < maxIds then
                    supIds[#supIds + 1] = sid
                    supSecs = math.max(supSecs, secs)
                    lens[secs] = true
                end
            end
        end
        if next(lens) and next(lens, next(lens)) then
            Note("limit.suppressor lengths", "spenders wait the longest of v1's hold times")
        end
        local marker = (#supIds > 0) and Add(Hears({ when = "cast", act = "sound" }, supIds)) or nil
        -- generators, then spenders: a rule per event and amount, hearing its spells
        local function Rules(list, act, extra, what)
            local open, order = {}, {}
            for _, g in ipairs(type(list) == "table" and list or {}) do
                if type(g) == "table" then
                    local ev = IA.V1_TIMER_EVENT[g.triggerType or "spellcast"]
                    local sid = Id(g.spellID)
                    if not ev then
                        Note(what .. "." .. tostring(g.triggerType), (g.triggerType == "spellcastSent")
                            and "a cast's press is not a trigger yet" or "a Cooldown Manager aura is not a trigger yet")
                    elseif sid then
                        if g.requireHostileTarget == true then
                            Note("limit.hostile target", "a stack also counts without a living enemy target")
                        end
                        local n = math.max(1, math.min(999, math.floor(tonumber(g.stacks) or 1)))
                        local key = ev .. ":" .. n
                        local grp = open[key]
                        if not grp or #grp.ids >= maxIds then
                            grp = { ev = ev, n = n, ids = {} }
                            open[key] = grp
                            order[#order + 1] = grp
                        end
                        grp.ids[#grp.ids + 1] = sid
                        d.spellID = d.spellID or sid
                    end
                end
            end
            for _, grp in ipairs(order) do
                local r = Hears({ when = grp.ev, act = act, n = (grp.n > 1) and grp.n or nil }, grp.ids)
                for k, v in pairs(extra) do r[k] = v end
                Add(r)
            end
        end
        Rules(tr.generators, "add", { restartToo = expire or nil }, "generator")
        Rules(tr.spenders, "remove", marker and { withinRule = marker, withinSecs = supSecs, withinNot = true } or {}, "spender")
        if not d.spellID then return nil, "never had a spell picked to gain a stack." end
    end
    local maxRules = (NS.Schema and NS.Schema.CUSTOM_MAX_RULES) or 8
    if #rules > maxRules then
        Note("limit.rules", "a Custom Bar holds eight rules; the rest are left out")
        for i = #rules, maxRules + 1, -1 do rules[i] = nil end
    end
    d.rules = rules
    -- the look: v1 dresses a timer bar as its cooldown duration bar
    local full = IA.V1FillBar(cfg, "cooldown")
    local look = { barKind = "cooldown", barMode = "duration", o = B.o, c = B.c, driver = { spellID = d.spellID } }
    IA.MapBarLook(look, full, IA.BAR_MAP, ctx)
    B.pos, B.anchor = look.pos, look.anchor
    local o = B.o
    local disp = type(full.display) == "table" and full.display or {}
    local bh = type(full.behavior) == "table" and full.behavior or {}
    if bh.hideWhenInactive == false then d.showWhile = "always" end
    if type(tr.barName) == "string" and tr.barName ~= "" then Put(o, "text", "nameText", tr.barName) end
    -- the icon: v1's own pick, else the art it stored when no spell gives one
    local io = Id(tr.iconOverride)
    if io then Put(o, "icon", "iconOverride", io)
    elseif not d.spellID and Id(tr.iconTextureID) then Put(o, "icon", "iconOverride", Id(tr.iconTextureID)) end
    -- ticks: one every interval seconds of the timer (each second is "all"), or each stack
    if B.barMode == "duration" and disp.showTickMarks == true then
        local iv = tonumber(disp.tickMarkInterval) or 1
        Put(o, "ticks", "ticksShow", true)
        if iv <= 1 then
            Put(o, "ticks", "tickMode", "all")
        else
            local vals = {}
            local k = iv
            while k < d.duration and #vals < 29 do
                vals[#vals + 1] = tostring(k)
                k = k + iv
            end
            Put(o, "ticks", "tickMode", "custom")
            Put(o, "ticks", "tickValues", table.concat(vals, ","))
            Put(o, "ticks", "tickAsPercent", false)
        end
    elseif stack and disp.autoStackTicks == true then
        Put(o, "ticks", "ticksShow", true)
        Put(o, "ticks", "tickMode", "all")
    end
    -- a stack bar: v1 writes the count in the duration text's place and style
    if stack then
        local t = o.text or {}
        for _, k in ipairs({ "Size", "Color", "Anchor", "OffsetX", "OffsetY", "Outline" }) do
            if t["dur" .. k] ~= nil then Put(o, "text", "stk" .. k, t["dur" .. k]) end
        end
        Put(o, "text", "stkShow", disp.showDuration ~= false)
        Put(o, "text", "durShow", false)
        Put(o, "text", "stkHideAtZero", disp.showZeroWhenReady ~= true)
        if disp.showDuration ~= false then Note("limit.stack shows max", "the count shows without its cap") end
    end
    return B
end

-- v1's skins (global.skinLibrary): a saved look a bar wears. Wearing one copies its display
-- keys in the categories it was saved with (a bar's place only when a castbar skin carries it)
-- and its top-level colour and tick lists, as v1's Presets.ApplySkin does.
function IA.V1KeyCategory(key)
    local V1 = IA.V1
    if V1.KEY_TO_CATEGORY and V1.KEY_TO_CATEGORY[key] then return V1.KEY_TO_CATEGORY[key] end
    for _, e in ipairs(V1.KEY_CATEGORY_PREFIXES or {}) do
        if key:sub(1, #e.prefix) == e.prefix then return e.category end
    end
    return nil
end
function IA.V1TextSub(key)
    local sub = IA.V1.TEXT_SUBCATEGORY and IA.V1.TEXT_SUBCATEGORY[key]
    if sub then return sub end
    if key:sub(1, 13) == "durationColor" or key:sub(1, 12) == "durationText" then return "textDuration" end
    return "textStacks"
end
function IA.V1SkinGroup(t)
    if type(t) ~= "string" then return "unknown" end
    local base = t:match("^(cd_%a+)_%d+$") or t
    return (IA.V1.BAR_TYPE_GROUPS or {})[base] or base
end
-- v1 resets a display mode the bar's kind cannot draw after a skin lands
function IA.V1SanitizeMode(cfg, kindType)
    local d, tr = cfg.display, cfg.tracking
    if type(d) ~= "table" or type(tr) ~= "table" then return end
    local mode = d.thresholdMode or "simple"
    local resCat = tr.resourceCategory
    local tt = tr.trackType
    if tt == nil and kindType == "buff" then tt = "buff" end
    local reset = false
    if resCat then
        if resCat == "secondary" then return end
        reset = mode == "fragmented" or mode == "icons" or mode == "perStack"
    elseif tt == "buff" or tt == "debuff" or tt == "both" then
        reset = mode == "fragmented" or mode == "icons"
    else
        reset = mode ~= "simple" and mode ~= "colorCurve"
    end
    if reset then d.thresholdMode = "simple" end
    if resCat and resCat ~= "secondary" then
        for _, k in ipairs(IA.V1.STALE_FRAGMENTED_KEYS or {}) do d[k] = nil end
    end
end
function IA.V1ApplySkin(cfg, entry, kindType)
    local out = Copy(cfg)
    local skin = type(entry.data) == "table" and entry.data or {}
    local filter = type(entry.categories) == "table" and entry.categories or nil
    local flat = type(out.display) ~= "table"
    local target = flat and out or out.display
    local excluded = IA.V1.EXCLUDED_DISPLAY_KEYS or {}
    local data = type(skin.display) == "table" and skin.display or skin
    for k, v in pairs(data) do
        if type(k) == "string" and not excluded[k] and k:sub(1, 1) ~= "_" then
            local cat = IA.V1KeyCategory(k)
            local allowed
            if not filter or not cat then
                allowed = true
            elseif cat == "text" then
                allowed = filter[IA.V1TextSub(k)]
                if allowed == nil then allowed = filter.text end
            else
                allowed = filter[cat]
            end
            if allowed then target[k] = Copy(v) end
        end
    end
    if flat and data.barPosition ~= nil and filter and filter.position then target.barPosition = Copy(data.barPosition) end
    if not flat then
        if type(skin.topLevel) == "table" then
            for key, cat in pairs(IA.V1.TOP_LEVEL_KEY_CATEGORIES or {}) do
                if skin.topLevel[key] ~= nil and (not filter or filter[cat]) then out[key] = Copy(skin.topLevel[key]) end
            end
        end
        out.display.stackColors, out.stackColors = nil, nil
        IA.V1SanitizeMode(out, kindType)
    end
    return out
end

-- v1's auto-switch (cfg.presets.autoSwitch.rules): per spec, the first rule with talents that
-- are taken wins, else the first rule for the spec alone, else the bar keeps the look it has.
-- Returns each look the bar can wear in order, with the specs it shows in and the talent rules
-- that win before it there, and the specs the bar shows in at all; nil when no rule applies.
function IA.SkinLooks(cfg, kindType, ctx)
    local p = type(cfg.presets) == "table" and cfg.presets or {}
    local rules = type(p.autoSwitch) == "table" and type(p.autoSwitch.rules) == "table" and p.autoSwitch.rules or {}
    if #rules == 0 then return nil end
    local G = ctx.db and ctx.db.global or {}
    local lib = type(G.skinLibrary) == "table" and G.skinLibrary or {}
    local usable = {}
    for i, r in ipairs(rules) do
        local e = type(r) == "table" and r.skinName and lib[r.skinName]
        if type(e) == "table" and IA.V1SkinGroup(e.barType) == IA.V1SkinGroup(kindType) then
            usable[#usable + 1] = { i = i, r = r, e = e,
                talented = type(r.talentConditions) == "table" and #r.talentConditions > 0 }
        elseif type(r) == "table" then
            Dropped(ctx.cov, "bar:presets.autoSwitch.missing skin", "a rule's skin is not in Arc UI's library for this kind of bar", true)
        end
    end
    if #usable == 0 then return nil end
    local bh = type(cfg.behavior) == "table" and cfg.behavior or {}
    local allowed
    if type(bh.showOnSpecs) == "table" and #bh.showOnSpecs > 0 then
        allowed = {}
        for _, si in ipairs(bh.showOnSpecs) do allowed[tonumber(si) or 0] = true end
    end
    local specs = {}
    for si = 1, 4 do
        if IA.SpecID(ctx.classID, si, ctx.opts) and (not allowed or allowed[si]) then specs[#specs + 1] = si end
    end
    if #specs == 0 then return nil end
    local function SpecOK(r, si)
        if type(r.specIndices) ~= "table" or #r.specIndices == 0 then return true end
        for _, v in ipairs(r.specIndices) do if tonumber(v) == si then return true end end
        return false
    end
    local looks, order = {}, {}
    local function Add(key, u, winners, si)
        local look = looks[key]
        if not look then
            local nots = {}
            for k, w in ipairs(winners) do nots[k] = w end
            look = { key = key, u = u, specs = {}, nots = nots }
            looks[key] = look
            order[#order + 1] = look
        end
        look.specs[#look.specs + 1] = si
    end
    for _, si in ipairs(specs) do
        local winners, sig = {}, {}
        for _, u in ipairs(usable) do
            if u.talented and SpecOK(u.r, si) then
                Add("t" .. u.i .. ":" .. table.concat(sig, ","), u, winners, si)
                winners[#winners + 1] = u
                sig[#sig + 1] = u.i
            end
        end
        local fb
        for _, u in ipairs(usable) do
            if not u.talented and SpecOK(u.r, si) then fb = u break end
        end
        Add((fb and ("s:" .. fb.r.skinName) or "base") .. ":" .. table.concat(sig, ","), fb, winners, si)
    end
    -- the bar as saved, in every spec, with nothing ahead of it: no rule ever applies
    if #order == 1 and not order[1].u and #order[1].nots == 0 then return nil end
    return order, specs
end

-- One plan bar per look v1's rules switch it between; the first look keeps the bar's own unit.
-- Relook(cfg2, entry) maps a skinned config to a bar (its o and looks; a castbar's place too).
-- Load conditions come from the bar (a skin never carries them), narrowed per look.
function IA.SkinBars(L, B, cfg, kindType, ctx, Relook)
    local order, specs = IA.SkinLooks(cfg, kindType, ctx)
    if not order then return 0 end
    local at
    for k, x in ipairs(L.bars) do if x == B then at = k end end
    local baseO, baseLooks = Copy(B.o), B.looks and Copy(B.looks)
    local baseC, basePos, baseAnchor, baseName, baseUnit = Copy(B.c), Copy(B.pos), B.anchor and Copy(B.anchor), B.name, B.unit
    local extra = 0
    for n, look in ipairs(order) do
        local T = B
        if n > 1 then T = { barKind = B.barKind, barMode = B.barMode, driver = Copy(B.driver) } end
        T.pos, T.anchor = Copy(basePos), baseAnchor and Copy(baseAnchor)
        if look.u then
            local R = Relook(IA.V1ApplySkin(cfg, look.u.e, kindType), look.u.e)
            T.o, T.looks = R.o or {}, R.looks
            if R.pos then T.pos, T.anchor = R.pos, R.anchor end
            T.name = baseName .. " (" .. look.u.r.skinName .. ")"
        else
            T.o, T.looks = Copy(baseO), baseLooks and Copy(baseLooks)
            T.name = baseName
        end
        T.unit = (n == 1) and baseUnit or (baseUnit .. "|skin|" .. look.key)
        local c = Copy(baseC)
        T.c = c
        if #look.specs < #specs then c.specs = IA.Specs(look.specs, ctx.classID, ctx.opts) end
        local own = look.u and look.u.talented and look.u.r or nil
        if own then IA.Talents(c, own.talentConditions, own.talentMatchMode) end
        -- not while a rule that wins before it here has its one talent taken
        for _, w in ipairs(look.nots) do
            local conds = w.r.talentConditions
            if #conds == 1 and c.talentMode ~= "any" then
                local cond = conds[1]
                if type(cond) == "number" then
                    IA.Talents(c, { { nodeID = cond, required = false } })
                elseif type(cond) == "table" then
                    IA.Talents(c, { { nodeID = cond.nodeID, required = cond.required == false, entryID = cond.entryID } })
                end
            else
                Dropped(ctx.cov, "bar:presets.autoSwitch.overlap", "a look also shows while an earlier rule's talents are taken")
            end
        end
        if n > 1 then
            extra = extra + 1
            table.insert(L.bars, at + extra, T)
        end
    end
    return extra
end

function IA.PlanBars(ctx, charDB, L, own)
    local cov, counts = ctx.cov, ctx.counts
    own = own or L
    local route = function(row, path)
        if row.gap then return nil, row.gap end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end
    L.later = L.later or {}
    local unitBase = "bar:" .. tostring(ctx.charKey) .. "|"
    local function Later(name, kind, why) L.later[#L.later + 1] = { name = name, kind = kind, why = why } end
    -- aura bars
    local auras = type(charDB.bars) == "table" and charDB.bars or {}
    for _, i in ipairs(IA.OrderedKeys(auras)) do
        local cfg = IA.V1AceFirst(auras[i], i, "aura")
        local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
        if tr and tr.enabled == true then
            local tt, sid = tr.trackType, tonumber(tr.spellID)
            -- v1's data repair strips the default track type ("buff") from saved bars
            if tt == nil then tt = "buff" end
            -- the units v1 watched, in its order ("party" is party1 to party4)
            local units = {}
            if type(tr.auraUnits) == "table" then
                for _, u in ipairs(IA.AURA_UNITS) do
                    if tr.auraUnits[u] == true or (u == "party1" and tr.auraUnits.party == true) then units[#units + 1] = u end
                end
            end
            if #units > 1 then
                Dropped(cov, "bar:tracking.auraUnits.several", "an aura bar watches one unit: the first of v1's comes in")
            end
            if tt == "both" then
                -- v1 builds the debuff half only on a target or focus: without one, nothing is lost
                local hostile = false
                for _, u in ipairs(units) do if u == "target" or u == "focus" then hostile = true end end
                if hostile then
                    Dropped(cov, "bar:tracking.trackType.both", "a buff-and-debuff bar becomes a buff bar; add a debuff bar for the other side")
                end
                tt = "buff"
            end
            local name = (type(tr.buffName) == "string" and tr.buffName ~= "") and tr.buffName or ("Aura " .. tostring(sid))
            -- v1's CDM Timer Mirror: a duration bar fed by the Cooldown Manager's own bar
            local summon = tt == "totem" or tt == "ground" or tt == "pet"
            local mirror = (tr.cdmMirror == true and tr.useDurationBar == true) and tonumber(tr.cooldownID)
            -- a summon (totem, ground effect, pet): v1 read its slot off the entry and drew the
            -- slot's time, so it comes in as a totem bar on the spell the entry shows
            local entry = summon and tonumber(tr.cooldownID)
            if summon and tr.dynamicMaxDuration == false then
                Dropped(cov, "bar:tracking.maxDuration", "a totem bar fills over the totem's own length")
            end
            if entry and entry > 0 then
                local ids = IA.CdmAuraIDs(ctx.opts, tr)
                local spell = IA.SummonSpell(ctx.opts, entry) or ((sid and sid > 0) and sid or nil)
                local B = { barKind = "totembar", name = name, unit = unitBase .. "aura|" .. tostring(i),
                    driver = { spellID = spell, spellIDs = (ids and #ids > 1) and ids or nil, slot = (not spell) and 1 or nil },
                    o = {}, c = {} }
                IA.MapBarLook(B, IA.V1FillBar(cfg, "aura"), IA.BAR_MAP, ctx)
                IA.Cover(cov, cfg, IA.BAR_MAP, route, nil, "bar")
                L.bars[#L.bars + 1] = B
                counts.bars.totembar = (counts.bars.totembar or 0) + 1
                counts.bars.totembar = counts.bars.totembar + IA.SkinBars(L, B, cfg, "buff", ctx, function(c2)
                    local T = { barKind = B.barKind, driver = B.driver, o = {}, c = {} }
                    IA.MapBarLook(T, IA.V1FillBar(c2, "aura"), IA.BAR_MAP, ctx)
                    return T
                end)
            elseif mirror and mirror > 0 then
                local B = { barKind = "cdmbar", name = name, unit = unitBase .. "aura|" .. tostring(i),
                    driver = { cooldownID = math.floor(mirror), spellID = (sid and sid > 0) and sid or nil },
                    o = {}, c = {} }
                IA.MapBarLook(B, IA.V1FillBar(cfg, "aura"), IA.BAR_MAP, ctx)
                IA.Cover(cov, cfg, IA.BAR_MAP, route, nil, "bar")
                L.bars[#L.bars + 1] = B
                counts.bars.cdmbar = (counts.bars.cdmbar or 0) + 1
                counts.bars.cdmbar = counts.bars.cdmbar + IA.SkinBars(L, B, cfg, "buff", ctx, function(c2)
                    local T = { barKind = B.barKind, driver = B.driver, o = {}, c = {} }
                    IA.MapBarLook(T, IA.V1FillBar(c2, "aura"), IA.BAR_MAP, ctx)
                    return T
                end)
            elseif (tt == "buff" or tt == "debuff" or tt == "petbuff") and sid and sid > 0 then
                local B = { barKind = "aura", barMode = (tr.useDurationBar == true) and "duration" or "stack",
                    name = name, unit = unitBase .. "aura|" .. tostring(i),
                    driver = { spellID = sid, auraType = (tt == "debuff") and "debuff" or "buff",
                        unit = (tt == "debuff") and "target" or (tt == "petbuff") and "pet" or "player",
                        maxStacks = tonumber(tr.maxStacks) }, o = {}, c = {} }
                if tr.auraOwnOnly == true then B.driver.caster = "mine" end
                -- a bar on a Cooldown Manager entry followed the entry in v1: what the Manager
                -- matches, never the spell the entry rests on alone
                local ids = IA.CdmAuraIDs(ctx.opts, tr)
                if ids then
                    B.driver.spellID = ids[1]
                    B.driver.spellIDs = (#ids > 1) and ids or nil
                end
                if units[1] then B.driver.unit = units[1] end
                IA.MapBarLook(B, IA.V1FillBar(cfg, "aura"), IA.BAR_MAP, ctx)
                IA.Cover(cov, cfg, IA.BAR_MAP, route, nil, "bar")
                L.bars[#L.bars + 1] = B
                counts.bars.aura = (counts.bars.aura or 0) + 1
                counts.bars.aura = counts.bars.aura + IA.SkinBars(L, B, cfg, "buff", ctx, function(c2)
                    local T = { barKind = B.barKind, barMode = B.barMode, driver = B.driver, o = {}, c = {} }
                    IA.MapBarLook(T, IA.V1FillBar(c2, "aura"), IA.BAR_MAP, ctx)
                    return T
                end)
            elseif tt == "" or tt == "none" then
                -- v1's panel shows it as never set up (its code ran it as a buff on you)
                Dropped(cov, "bar:dropped.aura bar: no track type", "v1 never picked a type for it", true)
                counts.barsDropped = counts.barsDropped + 1
                Later(name, "aura", "Arc UI never had a type picked for this bar, so it tracked nothing.")
            elseif tt == "customAura" or tt == "customCooldown" or tt == "cooldownCharge" then
                -- old kinds nothing in v1 draws any more
                Dropped(cov, "bar:dropped.aura bar: track type " .. tt, "nothing in Arc UI draws this old kind", true)
                counts.barsDropped = counts.barsDropped + 1
            else
                local why = summon and "no Cooldown Manager entry to follow" or "only buff and debuff bars with a spell id are carried"
                Dropped(cov, "bar:dropped.aura bar: track type " .. tostring(tt), why)
                counts.barsDropped = counts.barsDropped + 1
                Later(name, "aura")
            end
        end
    end
    -- cooldown and charge bars
    local cds = type(charDB.cooldownBarConfigs) == "table" and charDB.cooldownBarConfigs or {}
    for _, sid in ipairs(IA.OrderedKeys(cds)) do
        local kinds = cds[sid]
        for _, barType in ipairs(IA.OrderedKeys(type(kinds) == "table" and kinds or {})) do
            local cfg = kinds[barType]
            local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
            local spellID = tonumber(sid) or (tr and tonumber(tr.spellID))
            if tr and tr.enabled ~= false and spellID then
                local base = tostring(barType):match("^(%a+)")
                if base == "cooldown" or base == "charge" then
                    local B = { barKind = "cooldown", barMode = (base == "charge") and "stack" or "duration",
                        name = (ctx.opts.spellName and ctx.opts.spellName(spellID)) or ("Spell " .. spellID),
                        unit = unitBase .. "cd|" .. tostring(sid) .. "|" .. tostring(barType),
                        driver = { spellID = spellID }, o = {}, c = {} }
                    IA.MapBarLook(B, IA.V1FillBar(cfg, "cooldown"), IA.BAR_MAP, ctx)
                    IA.Cover(cov, cfg, IA.BAR_MAP, route, nil, "bar")
                    L.bars[#L.bars + 1] = B
                    counts.bars[base] = (counts.bars[base] or 0) + 1
                    counts.bars[base] = counts.bars[base] + IA.SkinBars(L, B, cfg, "cd_" .. tostring(barType), ctx, function(c2)
                        local T = { barKind = B.barKind, barMode = B.barMode, driver = B.driver, o = {}, c = {} }
                        IA.MapBarLook(T, IA.V1FillBar(c2, "cooldown"), IA.BAR_MAP, ctx)
                        return T
                    end)
                else
                    Dropped(cov, "bar:dropped.cooldown bar type " .. tostring(barType), "only cooldown and charge bars are carried")
                    counts.barsDropped = counts.barsDropped + 1
                end
            end
        end
    end
    -- resource bars
    local res = type(charDB.resourceBars) == "table" and charDB.resourceBars or {}
    for _, i in ipairs(IA.OrderedKeys(res)) do
        local cfg = IA.V1AceFirst(res[i], i, "resource")
        local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
        if tr and tr.enabled == true then
            local power
            if tr.resourceCategory == "secondary" then
                power = IA.POWERS[tr.secondaryType]
                if not power then Dropped(cov, "bar:dropped.resource bar: " .. tostring(tr.secondaryType), "Arc Auras has no bar for this resource") end
            elseif tr.resourceCategory == "autoPrimary" then
                -- the options' POWER_AUTO: the bar follows the power in use
                power = -1
            else
                power = tonumber(tr.powerType)
            end
            if power then
                local B = { barKind = "resource", name = (type(tr.powerName) == "string" and tr.powerName ~= "") and tr.powerName
                    or IA.SECONDARY_NAMES[tr.secondaryType] or ("Power " .. power),
                    unit = unitBase .. "res|" .. tostring(i), driver = { powerType = power }, o = {}, c = {} }
                IA.MapBarLook(B, IA.V1FillBar(cfg, "resource"), IA.BAR_MAP, ctx)
                IA.ResourceLooks(B, cfg, ctx)
                IA.Cover(cov, cfg, IA.BAR_MAP, route, nil, "bar")
                -- v1 hid an Automatic bar on the powers it excluded: the
                -- "Using ..." condition rows fade it out instead
                if power == -1 and type(tr.autoPowerExclude) == "table" then
                    for pt, on in pairs(tr.autoPowerExclude) do
                        local key = on == true and IA.POWER_ROWS[tonumber(pt)]
                        if key then
                            B.c.fadeWhen = B.c.fadeWhen or {}
                            B.c.fadeWhen[key] = true
                        end
                    end
                end
                L.bars[#L.bars + 1] = B
                counts.bars.resource = (counts.bars.resource or 0) + 1
                counts.bars.resource = counts.bars.resource + IA.SkinBars(L, B, cfg, "resource", ctx, function(c2)
                    local T = { barKind = "resource", driver = B.driver, o = {}, c = {} }
                    IA.MapBarLook(T, IA.V1FillBar(c2, "resource"), IA.BAR_MAP, ctx)
                    IA.ResourceLooks(T, c2, ctx)
                    return T
                end)
            else
                counts.barsDropped = counts.barsDropped + 1
                Later((type(tr.powerName) == "string" and tr.powerName ~= "") and tr.powerName
                    or IA.SECONDARY_NAMES[tr.secondaryType] or tostring(tr.secondaryType), "resource")
            end
        end
    end
    -- timer bars: v1 draws the ones on its active list, in that order
    local configs = type(charDB.timerBarConfigs) == "table" and charDB.timerBarConfigs or {}
    local active = type(charDB.timerBars) == "table" and type(charDB.timerBars.activeTimers) == "table"
        and charDB.timerBars.activeTimers or {}
    local timerRoute = function(row)
        if row.gap then return nil, row.gap end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end
    for _, id in ipairs(active) do
        local cfg = configs[id]
        local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
        if tr and tr.enabled ~= false then
            local name = (type(tr.barName) == "string" and tr.barName ~= "") and tr.barName or "Timer bar"
            local B, why = IA.MapTimerBar(cfg, ctx)
            if B then
                B.name, B.unit = name, unitBase .. "timer|" .. tostring(id)
                IA.Cover(cov, tr, IA.TIMER_MAP, timerRoute, "tracking", "timer")
                IA.Cover(cov, { display = cfg.display, behavior = cfg.behavior }, IA.BAR_MAP, route, nil, "bar")
                L.bars[#L.bars + 1] = B
                counts.bars.timer = (counts.bars.timer or 0) + 1
                counts.bars.timer = counts.bars.timer + IA.SkinBars(L, B, cfg, "timer", ctx, function(c2)
                    return IA.MapTimerBar(c2, ctx) or { o = {} }
                end)
            else
                Dropped(cov, "bar:dropped.timer bar", why)
                counts.barsDropped = counts.barsDropped + 1
                Later(name, "timer", "Arc UI's bar " .. why)
            end
        end
    end
    -- cast bars: the player's instances, then the focus and target bars
    local castRoute = function(row, path)
        if row.gap then return nil, row.gap end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end
    local function BuildCast(raw, unit, name, key, defaults, posRaw)
        local cfg = IA.V1FillDeep(raw, defaults)
        if cfg.enabled ~= true then return nil end
        local B = { barKind = "cast", name = name, unit = unitBase .. "cast|" .. key, driver = { unit = unit }, o = {}, c = {} }
        local eff = IA.CastFold(cfg, "hardcast")
        for path, row in pairs(IA.CAST_MAP) do
            if not row.gap and not row.special then IA.MapRow(B.o, row, eff[path]) end
        end
        IA.CastLook(B, cfg, eff, unit, ctx.classID)
        -- what v1 drew differently for a channel (beyond its colour and ticks) or, on an
        -- Evoker, an empowered cast: those casts take the bar's hardcast look
        for _, ct in ipairs({ "channel", "empower" }) do
            local e2 = (ct == "channel" or ctx.classID == 13) and IA.CastFold(cfg, ct) or cfg
            if e2 ~= cfg then
                for k, cat in pairs(IA.V1.CASTBAR_CATEGORY or {}) do
                    local skip = ct == "channel" and (k == "barColor" or cat == "tickMarks")
                    if not skip and not IA.SameValue(e2[k], eff[k]) then
                        Dropped(cov, "cast:profiles." .. ct .. "." .. k, "a " .. ct .. " cast takes the bar's hardcast look")
                    end
                end
            end
        end
        -- the place: the character's own unless the shared bar shares it, through the
        -- point the drag saved
        local pc = posRaw and IA.V1FillDeep(posRaw, defaults) or cfg
        local pos = type(pc.barPosition) == "table" and pc.barPosition or {}
        local pt = pos.point or pc.barAnchorPoint or "CENTER"
        local cx, cy = IA.ScreenCenter({ point = pt, relPoint = pos.relPoint or pt, x = pos.x or 0, y = pos.y or 0 },
            tonumber(cfg.width) or 220, tonumber(cfg.height) or 20)
        B.pos = { x = math.floor((cx or 0) + 0.5), y = math.floor((cy or 0) + 0.5) }
        if cfg.hideOutOfCombat == true then B.c.fadeWhen = { outOfCombat = true } end
        B.anchor = IA.BarGroupAnchor(cfg)
        if not B.anchor and unit ~= "player" and cfg.anchorToFrame == true and type(cfg.anchorFrameName) == "string"
            and cfg.anchorFrameName ~= "" then
            B.anchor = { kind = "frame", frame = cfg.anchorFrameName, src = cfg.anchorPoint or "CENTER",
                dst = cfg.anchorRelativePoint or "CENTER", x = tonumber(cfg.anchorOffsetX) or 0, y = tonumber(cfg.anchorOffsetY) or 0 }
        end
        if cfg.castType and cfg.castType ~= "all" then Dropped(cov, "cast:castType." .. tostring(cfg.castType), "a cast bar shows every cast; the type filter is dropped", true) end
        return B
    end
    local function CastBar(raw, unit, name, key, defaults, posRaw)
        if type(raw) ~= "table" then return end
        local B = BuildCast(raw, unit, name, key, defaults, posRaw)
        if not B then return end
        IA.Cover(cov, raw, IA.CAST_MAP, castRoute, nil, "cast")
        own.bars[#own.bars + 1] = B
        counts.bars.cast = (counts.bars.cast or 0) + 1
        counts.bars.cast = counts.bars.cast + IA.SkinBars(own, B, raw, "castbar", ctx, function(c2, entry)
            local carries = type(entry.categories) == "table" and entry.categories.position == true
            local T = BuildCast(c2, unit, name, key, defaults, (not carries) and posRaw or nil) or { o = {} }
            if not carries then T.pos, T.anchor = nil, nil end
            return T
        end)
    end
    local cbs = charDB.castbars
    local G = ctx.db.global or {}
    local shared = G.castbarShared == true and type(G.castbars) == "table"
    if shared then cbs = G.castbars end
    -- Settings > Modules: the castbars' switch off draws none of the three
    local mods = type(G.moduleToggles) == "table" and G.moduleToggles or {}
    if mods.castbar == false then return end
    local V1 = IA.V1
    for _, i in ipairs(IA.OrderedKeys(type(cbs) == "table" and cbs or {})) do
        if type(i) == "number" then
            local own = shared and G.castbarShareLocation ~= true and type(charDB.castbars) == "table" and charDB.castbars[i] or nil
            CastBar(cbs[i], "player", "Cast bar " .. i, tostring(i), V1.CASTBAR_DEFAULTS, own)
        end
    end
    CastBar(charDB.focusCastbar, "focus", "Focus cast bar", "focus", V1.FOCUS_CASTBAR_DEFAULTS)
    CastBar(charDB.targetCastbar, "target", "Target cast bar", "target", V1.TARGET_CASTBAR_DEFAULTS)
end

-- v1's Aura Textures -> texture records (Bars\AD_TextureElement.lua): the picture, its look
-- while the aura is up and while it is missing, its drain, pulse and countdown.
local TEX_SRC = { special = "texAura" }
local TEX_PIC = { special = "texPicture" }
local TEX_LOOK = { special = "texLooks" }
local TEX_DRAIN = { special = "texDrain" }
local TEX_TEXT = { special = "texText" }
local TEX_NOINSET = { gap = "only part of the picture draining is not offered yet" }
local TEX_NOBANDS = { gap = "time text colours by seconds left are not offered on textures yet" }
IA.TEX_MAP = {
    ["tracking.enabled"] = { special = "identity" }, ["tracking.buffName"] = { special = "identity" },
    ["tracking.cooldownID"] = TEX_SRC, ["tracking.alternateCooldownIDs"] = TEX_SRC, ["tracking.spellID"] = TEX_SRC,
    ["tracking.trackedSpellID"] = TEX_SRC, ["tracking.customAura"] = TEX_SRC, ["tracking.trackType"] = TEX_SRC,
    ["tracking.iconTextureID"] = { gap = "Arc UI's textures never read it", nv = true },
    ["tracking.slotNumber"] = { gap = "Arc UI's textures never read it", nv = true },
    ["tracking.auraInstanceID"] = { gap = "Arc UI's textures never read it", nv = true },
    ["tracking.useBaseSpell"] = { gap = "Arc UI's textures never read it", nv = true },
    ["tracking.excludedCooldownIDs"] = { gap = "Arc UI's textures never read it", nv = true },
    ["tracking.source"] = { gap = "Arc UI's textures never read it", nv = true },
    ["behavior.showOnSpecs"] = { special = "specs" }, ["behavior.showOnSpec"] = { special = "specs" },
    ["behavior.talentConditions"] = { special = "talents" }, ["behavior.talentMatchMode"] = { special = "talents" },
    ["behavior.hideWhen"] = { special = "hideWhen" }, ["behavior.hideLogic"] = { special = "hideWhen" },
    ["behavior.hideWhenAlpha"] = { special = "hideWhen" },
    ["display.enabled"] = { gap = "Arc UI's textures never read it", nv = true },
    ["display.width"] = { "size", "width", "int" }, ["display.height"] = { "size", "height", "int" },
    ["display.position"] = { special = "position" },
    ["display.frameStrata"] = { special = "texFrame" }, ["display.frameLevel"] = { "frame", "level", "int" },
    ["display.movable"] = { gap = "Arc UI's editor state", nv = true },
    ["display.lockAspect"] = { gap = "Arc UI's editor state", nv = true },
    ["display.textureSource"] = TEX_PIC, ["display.textureID"] = TEX_PIC, ["display.customTexturePath"] = TEX_PIC,
    ["display.blendMode"] = { "texlook", "blend" },
    ["display.rotateEnabled"] = TEX_PIC, ["display.rotation"] = TEX_PIC,
    ["display.mirrorH"] = TEX_PIC, ["display.mirrorV"] = TEX_PIC,
    ["display.zoomEnabled"] = TEX_PIC, ["display.zoomPct"] = TEX_PIC,
    ["display.cropEnabled"] = TEX_PIC, ["display.cropL"] = TEX_PIC, ["display.cropR"] = TEX_PIC,
    ["display.cropT"] = TEX_PIC, ["display.cropB"] = TEX_PIC,
    ["display.activeColor"] = TEX_LOOK, ["display.activeAlpha"] = TEX_LOOK,
    ["display.activeDesaturate"] = TEX_LOOK, ["display.activeDesaturatePct"] = TEX_LOOK,
    ["display.showWhenInactive"] = TEX_LOOK, ["display.inactiveColor"] = TEX_LOOK, ["display.inactiveAlpha"] = TEX_LOOK,
    ["display.inactiveDesaturate"] = TEX_LOOK, ["display.inactiveDesaturatePct"] = TEX_LOOK,
    ["display.progressEnabled"] = TEX_DRAIN, ["display.progressDir"] = TEX_DRAIN, ["display.progressHideGhost"] = TEX_DRAIN,
    ["display.drainInsetL"] = TEX_NOINSET, ["display.drainInsetR"] = TEX_NOINSET,
    ["display.drainInsetT"] = TEX_NOINSET, ["display.drainInsetB"] = TEX_NOINSET,
    ["display.pulseEnabled"] = { special = "texPulse" }, ["display.pulseScale"] = { special = "texPulse" },
    ["display.pulseSpeed"] = { special = "texPulse" },
    ["display.fadeOutEnabled"] = { special = "texFade" }, ["display.fadeStartPct"] = { special = "texFade" },
    ["display.glowEnabled"] = { gap = "no Arc UI control and nothing reads it", nv = true },
    ["display.glowType"] = { gap = "no Arc UI control and nothing reads it", nv = true },
    ["display.showDuration"] = { "pictext", "ptTimeShow", "bool" },
    ["display.durationFont"] = { "pictext", "ptFont", "font" },
    ["display.durationFontSize"] = { "pictext", "ptTimeSize", "int" },
    ["display.durationColor"] = { "pictext", "ptTimeColor", "color" },
    ["display.durationOutline"] = { "pictext", "ptOutline", "outline" },
    ["display.durationShadow"] = { "pictext", "ptShadow", "bool" },
    ["display.durationDecimals"] = TEX_TEXT, ["display.durationAnchor"] = TEX_TEXT,
    ["display.durationAnchorOffsetX"] = TEX_TEXT, ["display.durationAnchorOffsetY"] = TEX_TEXT,
    ["display.durationTextStrata"] = { gap = "texts sit on the picture's own level", nv = true },
    ["display.durationTextLevel"] = { gap = "texts sit on the picture's own level", nv = true },
    ["display.durationTextColorEnabled"] = TEX_NOBANDS,
}
for i = 2, 5 do
    for _, k in ipairs({ "Enabled", "Value", "Color" }) do IA.TEX_MAP["display.durationTextThreshold" .. i .. k] = TEX_NOBANDS end
end
IA.TEX_SPECIALS = {
    identity = "the record itself", position = "the record's pos (v1's drag position as the picture's centre)",
    specs = "c.specs (showOnSpecs, else showOnSpec)", talents = "c.talents / talentsNot / talentMode", hideWhen = "c.fadeWhen + c.fadeAlpha",
    texAura = "driver: the Cooldown Manager entry's aura IDs, else trackedSpellID or spellID; buff on you, debuff on your target (yours), pet buff",
    texFrame = "frame.strata (FULLSCREEN and higher as DIALOG)",
    texPicture = "texlook.image (a file ID, atlas or cleaned path; none = the question mark), rotation, and in show mode flipH / flipV / zoom (2 x v1's per side) / crops; an atlas takes none of them",
    texLooks = "texlook.color (rgb + active alpha), desat (grey 50 % and up); while missing: bgShow + bgInactive, bgAlpha, bgTint / bgColor, bgDesat / bgDesatAmount",
    texDrain = "texlook.mode fill + fillMode drain + fillDir (v1's sweep as the fill's growth); the grey half-alpha copy behind as the dim copy",
    texPulse = "texlook.pulse + pulseSize ((scale - 1) x 100) + pulseTime (2 x v1's half cycle)",
    texFade = "texstate.timeOn + timePct + timeColor at half alpha (one step for v1's smooth fade)",
    texText = "pictext.ptTimeDecimals / ptTimeDecTo and ptTimeAnchor / ptTimeX / ptTimeY (v1's text box centre)",
}

-- The keys of a saved table that differ from v1's defaults (what the player changed).
function IA.V1Changed(saved, defaults)
    if type(saved) ~= "table" then return saved end
    local out = {}
    for k, v in pairs(saved) do
        local dv
        if type(defaults) == "table" then dv = defaults[k] end
        if type(v) == "table" and type(dv) == "table" and not IsLeafTable(v) then
            local sub = IA.V1Changed(v, dv)
            if next(sub) then out[k] = sub end
        elseif not IA.SameValue(v, dv) then
            out[k] = v
        end
    end
    return out
end

-- v1's countdown on a texture is a box (4 x its size wide, its size + 4 tall) with the text
-- in its middle, hung on the picture by v1's anchor. Arc Auras places the text's centre from
-- the picture's centre; past the offsets' reach, by the nearest edge (the text about an em).
IA.TEX_TIME_EDGE = { [-1] = { [-1] = "BOTTOMLEFT", [0] = "LEFT", [1] = "TOPLEFT" },
    [0] = { [-1] = "BOTTOM", [0] = "CENTER", [1] = "TOP" }, [1] = { [-1] = "BOTTOMRIGHT", [0] = "RIGHT", [1] = "TOPRIGHT" } }
function IA.TexTimeSpot(a, ox, oy, fw, fh, size)
    local W, H, pad = size * 4, size + 4, 5
    local hw, hh = fw / 2, fh / 2
    local S = {
        CENTER = { 0, 0 }, RIGHT = { hw - pad, 0 }, LEFT = { -hw + pad, 0 }, TOP = { 0, hh - pad }, BOTTOM = { 0, -hh + pad },
        TOPLEFT = { -hw + pad - W / 2, hh - pad + H / 2 }, TOPRIGHT = { hw - pad + W / 2, hh - pad + H / 2 },
        BOTTOMLEFT = { -hw + pad - W / 2, -hh + pad - H / 2 }, BOTTOMRIGHT = { hw - pad + W / 2, -hh + pad - H / 2 },
        OUTERRIGHT = { hw - 20 + W / 2, 0 }, OUTERLEFT = { -hw + 20 - W / 2, 0 },
        OUTERTOP = { 0, hh + H / 2 }, OUTERBOTTOM = { 0, -hh - H / 2 },
        OUTERTOPLEFT = { -hw - W / 2, hh + H / 2 }, OUTERTOPRIGHT = { hw + W / 2, hh + H / 2 },
        OUTERBOTTOMLEFT = { -hw - W / 2, -hh - H / 2 }, OUTERBOTTOMRIGHT = { hw + W / 2, -hh - H / 2 },
    }
    S.CENTERRIGHT, S.CENTERLEFT = S.RIGHT, S.LEFT
    S.OUTERCENTERRIGHT, S.OUTERCENTERLEFT = S.OUTERRIGHT, S.OUTERLEFT
    local spot = S[a] or S.CENTER
    local cx, cy = spot[1] + ox, spot[2] + oy
    local function Round(v) return math.floor(v + 0.5) end
    local function Clamp(v) return math.max(-100, math.min(100, Round(v))) end
    if math.abs(cx) <= 100 and math.abs(cy) <= 100 then return "CENTER", Round(cx), Round(cy) end
    local px = (cx > 100) and 1 or (cx < -100) and -1 or 0
    local py = (cy > 100) and 1 or (cy < -100) and -1 or 0
    return IA.TEX_TIME_EDGE[px][py], Clamp(cx - px * hw + px * 0.6 * size), Clamp(cy - py * hh + py * 0.5 * size)
end

-- v1's drain names where the emptying sweeps; Arc Auras' fill names where it grows.
IA.TEX_DRAIN_DIR = { TOP_TO_BOTTOM = "UP", BOTTOM_TO_TOP = "DOWN", RIGHT_TO_LEFT = "RIGHT", LEFT_TO_RIGHT = "LEFT" }

-- One v1 texture (its defaults filled) -> a plan texture record, or nil and why not.
function IA.MapTexture(t, ctx)
    local cov = ctx.cov
    local tr, d, bh = t.tracking or {}, t.display or {}, t.behavior or {}
    local tt = tr.trackType
    if tt == "pet" or tt == "totem" or tt == "ground" then
        return nil, "Arc Auras' textures do not follow a summon's time yet."
    end
    local B = { barKind = "texture", o = {}, c = {}, driver = { source = "aura" } }
    local o, dr = B.o, B.driver
    -- the aura: what the Cooldown Manager entry matches, else v1's own spell
    local ids = IA.CdmAuraIDs(ctx.opts, tr)
    local sid = tonumber(tr.trackedSpellID) or tonumber(tr.spellID)
    if ids then
        dr.spellID, dr.spellIDs = ids[1], (#ids > 1) and ids or nil
    elseif sid and sid > 0 then
        dr.spellID = math.floor(sid)
    else
        return nil, "Arc UI never had an aura picked for this texture."
    end
    if tt == "debuff" then
        dr.auraType, dr.unit, dr.caster = "debuff", "target", "mine"
    elseif tt == "petbuff" then
        dr.auraType, dr.unit = "buff", "pet"
    else
        dr.auraType, dr.unit = "buff", "player"
    end
    for path, row in pairs(IA.TEX_MAP) do
        if not row.gap and not row.special then IA.MapRow(o, row, Leaf(t, path)) end
    end
    local w, h = tonumber(d.width) or 64, tonumber(d.height) or 64
    local cx, cy = IA.ScreenCenter(d.position, w, h)
    B.pos = { x = math.floor((cx or 0) + 0.5), y = math.floor((cy or 0) + 0.5) }
    local st = d.frameStrata
    if st == "FULLSCREEN" or st == "FULLSCREEN_DIALOG" or st == "TOOLTIP" then st = "DIALOG" end
    if st == "BACKGROUND" or st == "LOW" or st == "MEDIUM" or st == "HIGH" or st == "DIALOG" then Put(o, "frame", "strata", st) end
    -- the picture: a file ID or an atlas as is, a typed path cleaned as v1 cleans it; none is
    -- v1's question mark: an empty picture here would be the spell's own icon
    local art, atlas
    if d.textureSource == "custom" then
        local path = type(d.customTexturePath) == "string" and d.customTexturePath:gsub("^%s+", ""):gsub("%s+$", "") or ""
        path = path:gsub("\\\\", "\\")
        art = (path ~= "") and path or nil
    else
        art = d.textureID
        atlas = type(art) == "string" and tonumber(art) == nil and art ~= ""
    end
    if art == nil or art == "" or art == 0 then art, atlas = 134400, false end
    Put(o, "texlook", "image", tostring(art))
    -- the looks while the aura is up
    local ac = Color(d.activeColor) or { 1, 1, 1, 1 }
    Put(o, "texlook", "color", { ac[1], ac[2], ac[3], tonumber(d.activeAlpha) or 1 })
    if d.activeDesaturate == true then
        local pct = tonumber(d.activeDesaturatePct) or 100
        Put(o, "texlook", "desat", pct >= 50)
        if pct < 100 then Dropped(cov, "tex:limit.grey amount", "a picture greys all the way or not at all") end
    end
    -- the drain: v1 drains a file picture, an atlas stays still
    local drain = d.progressEnabled == true and not atlas
    if drain then
        Put(o, "texlook", "mode", "fill")
        Put(o, "texlook", "fillMode", "drain")
        Put(o, "texlook", "fillBy", "time")
        Put(o, "texlook", "fillDir", IA.TEX_DRAIN_DIR[d.progressDir] or "UP")
        if d.rotateEnabled == true and (tonumber(d.rotation) or 0) ~= 0 then
            Dropped(cov, "tex:limit.drain on a turned picture", "a draining picture stays upright")
        end
        if d.progressHideGhost ~= true and d.showWhenInactive ~= true then
            Put(o, "texlook", "bgShow", true)
            Put(o, "texlook", "bgTint", true)
            Put(o, "texlook", "bgColor", { 0.5, 0.5, 0.5 })
            Put(o, "texlook", "bgAlpha", 0.5)
        end
    else
        if d.rotateEnabled == true and tonumber(d.rotation) then
            local r = tonumber(d.rotation) % 360
            if r > 180 then r = r - 360 end
            Put(o, "texlook", "rotation", math.floor(r + 0.5))
        end
        if not atlas then
            if d.mirrorH == true then Put(o, "texlook", "flipH", true) end
            if d.mirrorV == true then Put(o, "texlook", "flipV", true) end
            if d.zoomEnabled == true and tonumber(d.zoomPct) then
                Put(o, "texlook", "zoom", math.max(0, math.min(45, math.floor(2 * tonumber(d.zoomPct) + 0.5))))
                if 2 * tonumber(d.zoomPct) > 45 then Dropped(cov, "tex:limit.zoom", "Arc Auras zooms a picture up to 45 %") end
            end
            if d.cropEnabled == true then
                for _, k in ipairs({ "L", "R", "T", "B" }) do
                    local v = tonumber(d["crop" .. k])
                    if v and v > 0 then Put(o, "texlook", "crop" .. k, math.max(0, math.min(90, math.floor(v + 0.5)))) end
                end
            end
        end
    end
    -- while the aura is missing: the same picture in its own look; that copy also sits
    -- under the picture while the aura is up, seen only through a see-through picture
    if d.showWhenInactive == true then
        Put(o, "texlook", "bgShow", true)
        Put(o, "texlook", "bgInactive", true)
        Put(o, "texlook", "bgAlpha", tonumber(d.inactiveAlpha) or 0.5)
        local ic = Color(d.inactiveColor)
        if ic and not (ic[1] == 1 and ic[2] == 1 and ic[3] == 1) then
            Put(o, "texlook", "bgTint", true)
            Put(o, "texlook", "bgColor", { ic[1], ic[2], ic[3] })
        end
        if d.inactiveDesaturate == true then
            Put(o, "texlook", "bgDesat", true)
            Put(o, "texlook", "bgDesatAmount", math.max(5, math.min(100, math.floor((tonumber(d.inactiveDesaturatePct) or 100) + 0.5))))
        end
        Dropped(cov, "tex:limit.missing look under the picture", "the look while missing also sits under the picture while it shows")
    end
    -- the pulse: v1 scales the picture by its size over a half cycle each way
    if d.pulseEnabled == true then
        local scale = tonumber(d.pulseScale) or 1.15
        Put(o, "texlook", "pulse", true)
        Put(o, "texlook", "pulseSize", math.max(2, math.min(60, math.floor(math.abs(scale - 1) * 100 + 0.5))))
        Put(o, "texlook", "pulseTime", math.max(0.2, math.min(4, 2 * (tonumber(d.pulseSpeed) or 0.5))))
        if scale < 1 then Dropped(cov, "tex:limit.shrinking pulse", "a pulse grows the picture") end
    end
    -- the fade: one step at its start for v1's smooth fade (the time left is secret)
    if d.fadeOutEnabled == true then
        Put(o, "texstate", "timeOn", true)
        Put(o, "texstate", "timeUnit", "pct")
        Put(o, "texstate", "timePct", math.max(1, math.min(99, math.floor((tonumber(d.fadeStartPct) or 50) + 0.5))))
        Put(o, "texstate", "timeColor", { ac[1], ac[2], ac[3], (tonumber(d.activeAlpha) or 1) * 0.5 })
        Dropped(cov, "tex:limit.smooth fade", "a texture fades in one step, not smoothly")
    end
    -- the countdown
    if d.showDuration == true then
        local dec = tonumber(d.durationDecimals) or 0
        if dec > 0 then
            Put(o, "pictext", "ptTimeDecimals", true)
            Put(o, "pictext", "ptTimeDecTo", 60)
            if dec > 1 then Dropped(cov, "tex:limit.decimals", "the time shows tenths at most") end
        end
        local anchor, x, y = IA.TexTimeSpot(d.durationAnchor or "CENTER", tonumber(d.durationAnchorOffsetX) or 0,
            tonumber(d.durationAnchorOffsetY) or 0, w, h, tonumber(d.durationFontSize) or 18)
        Put(o, "pictext", "ptTimeAnchor", anchor)
        Put(o, "pictext", "ptTimeX", x)
        Put(o, "pictext", "ptTimeY", y)
    end
    -- when it loads
    local specList = bh.showOnSpecs
    if (type(specList) ~= "table" or next(specList) == nil) and (tonumber(bh.showOnSpec) or 0) > 0 then specList = { bh.showOnSpec } end
    local specs = IA.Specs(specList, ctx.classID, ctx.opts)
    if specs then B.c.specs = specs end
    IA.Talents(B.c, bh.talentConditions, bh.talentMatchMode)
    IA.HideWhen(B.c, bh.hideWhen, bh.hideLogic, bh.hideWhenAlpha)
    return B
end

-- v1's Aura Textures: each one set up (a slot with an aura) a texture record and a pick;
-- the panel's list also carries what it shows. Slot 1 gets back the defaults AceDB strips.
function IA.PlanTextures(ctx, charDB, L)
    local out = {}
    local cov, counts = ctx.cov, ctx.counts
    local list = type(charDB) == "table" and type(charDB.textures) == "table" and charDB.textures or {}
    local route = function(row)
        if row.gap then return nil, row.gap end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end
    local base = "bar:" .. tostring(ctx.charKey) .. "|tex|"
    for _, i in ipairs(IA.OrderedKeys(list)) do
        local raw = list[i]
        local t = type(raw) == "table" and IA.V1FillDeep(raw, IA.V1.TEXTURE_DEFAULTS) or nil
        local tr = t and type(t.tracking) == "table" and t.tracking or nil
        local aimed = tr and ((tonumber(tr.spellID) or 0) > 0 or (tonumber(tr.trackedSpellID) or 0) > 0
            or (tonumber(tr.cooldownID) or 0) > 0)
        if tr and tr.enabled == true and aimed then
            local d = type(t.display) == "table" and t.display or {}
            local bh = type(t.behavior) == "table" and t.behavior or {}
            local art = (d.textureSource == "custom") and d.customTexturePath or d.textureID
            if art == "" or art == 0 then art = nil end
            local row = { name = (type(tr.buffName) == "string" and tr.buffName ~= "") and tr.buffName or ("Texture " .. tostring(i)),
                debuff = tr.trackType == "debuff", w = tonumber(d.width) or 64, h = tonumber(d.height) or 64,
                art = art, atlas = type(art) == "string" and d.textureSource ~= "custom",
                specs = IA.Specs(bh.showOnSpecs, ctx.classID, ctx.opts) }
            local B, why = IA.MapTexture(t, ctx)
            if B then
                B.name, B.unit = row.name, base .. tostring(i)
                row.unit = B.unit
                L.bars[#L.bars + 1] = B
                counts.bars.texture = (counts.bars.texture or 0) + 1
            else
                row.why = why
                Dropped(cov, "tex:dropped.texture", why)
            end
            IA.Cover(cov, IA.V1Changed(raw, IA.V1.TEXTURE_DEFAULTS), IA.TEX_MAP, route, nil, "tex")
            out[#out + 1] = row
        end
    end
    return out
end

-- v1's Cooldown Reminder -> a plan Reminder group with its reminders.
function IA.PlanReminders(ctx, charDB, L)
    local cr = charDB.cooldownReminder
    if type(cr) ~= "table" or type(cr.whitelist) ~= "table" or next(cr.whitelist) == nil then return end
    local cov = ctx.cov
    local RG = { name = "Reminders", pos = { x = tonumber(cr.x) or 0, y = tonumber(cr.y) or 0 }, o = {}, c = {}, reminders = {} }
    for _, k in ipairs(IA.REMINDER_PULSE) do if cr[k] ~= nil then Put(RG.o, "pulse", k, cr[k]) end end
    for _, k in ipairs(IA.REMINDER_AUDIO) do if cr[k] ~= nil then Put(RG.o, "audio", k, cr[k]) end end
    if cr.enabled == false then RG.c.loadNever = { always = true } end
    local keys = {}
    for k, on in pairs(cr.whitelist) do if on then keys[#keys + 1] = tostring(k) end end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local kind, id = "spell", tonumber(key)
        local item = key:match("^i:(%d+)$")
        if item then kind, id = "item", tonumber(item) end
        if id and id > 0 then
            local trig = type(cr.spellTriggers) == "table" and cr.spellTriggers[key]
            local triggers = {}
            if type(trig) == "table" and #trig > 0 then
                for _, t in ipairs(trig) do if type(t) == "table" then triggers[#triggers + 1] = Copy(t) end end
            else
                local t = { type = "when_ready", seconds = 3 }
                local snd = type(cr.spellSounds) == "table" and cr.spellSounds[key]
                if type(snd) == "string" and snd ~= "" then t.sound = snd end
                local tts = type(cr.spellTTS) == "table" and cr.spellTTS[key]
                if type(tts) == "string" and tts ~= "" then t.tts = tts end
                if type(cr.spellSoundDisabled) == "table" and cr.spellSoundDisabled[key] then t.soundDisabled = true end
                if type(cr.spellIconDisabled) == "table" and cr.spellIconDisabled[key] then t.showIcon = false end
                triggers[1] = t
            end
            RG.reminders[#RG.reminders + 1] = { kind = kind, id = id, triggers = triggers, c = {},
                name = (kind == "item") and ((ctx.opts.itemName and ctx.opts.itemName(id)) or ("Item " .. id))
                    or ((ctx.opts.spellName and ctx.opts.spellName(id)) or ("Spell " .. id)) }
            ctx.counts.reminders = ctx.counts.reminders + 1
        end
    end
    if type(cr.spellLoadConditions) == "table" and next(cr.spellLoadConditions) then
        Dropped(cov, "other:cooldownReminder.spellLoadConditions", "per-reminder load conditions are not carried; set them on each reminder", true)
    end
    L.reminders[#L.reminders + 1] = RG
    ctx.counts.reminderGroups = ctx.counts.reminderGroups + 1
end

-- The plan: every character, spec and profile of a v1 saved-variables table, as
-- layouts plus the picker's tree of import units (a group, a profile's free icons,
-- a character's bars, its reminders, its global look). opts (all optional, the
-- game's readers in play): cooldown(id), specID(classID, idx), classTag(classID),
-- spellName(id), itemName(id), spellHarmful(id), spellTexture(id).
function IA.Plan(db, opts)
    opts = opts or {}
    local cov = IA.NewCoverage()
    local plan = { version = 3, layouts = {}, looks = {}, tree = {}, leaves = {}, unitLayout = {}, coverage = cov,
        counts = { chars = 0, specs = 0, profiles = 0, layouts = 0, groups = 0, freeIcons = 0,
            cdmIcons = 0, arcIcons = 0, icons = {}, iconsDropped = 0, unplaced = 0, bars = {},
            barsDropped = 0, reminders = 0, reminderGroups = 0, dormant = 0, talentLayouts = 0, units = 0 } }
    if type(db) ~= "table" or type(db.char) ~= "table" then return plan end
    local model = IA.ReadV1(db, opts)
    plan.model = model
    plan.notes = model.notes
    local nativeGlow = type(db.global) == "table" and db.global.nativeGlowColors == true
    -- layoutKey: the stamp's key of the layout the unit lands in (none for the look),
    -- so an Imported mark lasts only while that layout does
    local function Leaf(node, kind, unit, label, n, layoutKey, name)
        local leaf = { id = unit, unit = unit, kind = kind, label = label, n = n, layoutKey = layoutKey, name = name }
        node.children[#node.children + 1] = leaf
        plan.leaves[unit] = leaf
        if layoutKey then plan.unitLayout[unit] = layoutKey end
        plan.counts.units = plan.counts.units + 1
        return leaf
    end
    for _, C in ipairs(model.chars) do
        local v1key = C.v1key
        local charDB = db.char[v1key]
        do
            local charKey, charName = C.charKey, C.name
            local profName = C.globals.profile
            local ctx = { db = db, opts = opts, cov = cov, counts = plan.counts, charKey = charKey,
                charName = charName, globals = C.globals, arcDB = C.arc, C = C, nativeGlow = nativeGlow,
                ach = type(charDB) == "table" and type(charDB.achSettings) == "table" and charDB.achSettings or nil }
            local node = { id = "char:" .. charKey, kind = "char", label = tostring(v1key), charKey = charKey, children = {},
                name = charName, realm = tostring(v1key):match("^.- %- (.+)$") or "" }
            local cdm = charDB.cdmGroups
            local hadLayout = false
            -- the character's one layout: every profile's groups and free icons (each part loading
            -- in its own spec only, a spare one never), its bars and its Cooldown Reminder group
            local CL = { name = charName, key = "layout:" .. charKey, charKey = charKey, c = { chars = { [charKey] = true } },
                pos = { x = 0, y = 0 }, o = {}, parts = {}, bars = {}, reminders = {},
                unitReminders = "reminders:" .. charKey, later = {} }
            -- the character's icon tooltips off in v1: the layout's mouse tier (clicks keep Arc
            -- Auras' click-through, which never caught anything on these icons)
            if C.noTips then Put(CL.o, "mouse", "showTooltip", "off") end
            -- its other bars and textures: a layout of their own that every character of the
            -- class loads, each bar by its own specs and talents (the import's Only on adds
            -- the character); its cast bars stay in CL, one per character as in v1
            local BL = { name = charName .. " bars", key = "layout:bars:" .. charKey, charKey = charKey, forBars = true,
                c = {}, pos = { x = 0, y = 0 }, o = {}, parts = {}, bars = {}, reminders = {}, later = {} }
            ctx.placedIn = IA.PlacedBySpec(C)
            for _, S in ipairs(C.specs) do
                plan.counts.specs = plan.counts.specs + 1
                ctx.specKey, ctx.classID = S.key, S.classID
                ctx.classTag = IA.ClassTag(S.classID, opts)
                ctx.specID = S.specID
                ctx.specName = S.specName
                ctx.rawProfiles = S.raw
                ctx.barHides = IA.BarHides(charDB, S.classID, S.specID, opts)
                local specNode = { id = "spec:" .. charKey .. "|" .. S.key, kind = "spec", label = ctx.specName, children = {},
                    specID = S.specID, index = S.index }
                for _, P in ipairs(S.profiles) do
                    IA.Yield()
                    plan.counts.profiles = plan.counts.profiles + 1
                    local L = IA.PlanProfile(ctx, P, S, plan)
                    CL.parts[#CL.parts + 1] = L
                    if L.dormant then plan.counts.dormant = plan.counts.dormant + 1 end
                    if L.talentsIgnored then plan.counts.talentLayouts = plan.counts.talentLayouts + 1 end
                    hadLayout = true
                    local tag = L.active and "active" or (L.talentsIgnored and "talents" or "spare")
                    local pnode = { id = "profile:" .. L.key, kind = "profile", label = tostring(P.name) .. " (" .. tag .. ")", tag = tag, children = {},
                        name = tostring(P.name), layoutKey = CL.key, linked = L.linked }
                    for _, g in ipairs(L.groups) do
                        local lf = Leaf(pnode, "group", g.unit, Tr("%s: %d icons"):format(g.name, #g.icons), #g.icons, CL.key, g.name)
                        lf.cdmHidden = g.cdmHidden
                    end
                    if #L.icons > 0 then
                        local lf = Leaf(pnode, "free", L.freeUnit, Tr("Free icons: %d"):format(#L.icons), #L.icons, CL.key, "Free icons")
                        lf.cdmHidden = L.cdmHidden
                    end
                    if #pnode.children > 0 then specNode.children[#specNode.children + 1] = pnode end
                end
                if #specNode.children > 0 then node.children[#node.children + 1] = specNode end
            end
            -- several profiles' groups in one layout: each says whose it is
            local withGroups = 0
            for _, L in ipairs(CL.parts) do if #L.groups > 0 then withGroups = withGroups + 1 end end
            for _, L in ipairs(CL.parts) do
                for _, g in ipairs(L.groups) do
                    g.recName = g.name
                    if withGroups > 1 then
                        local whose = L.active and tostring(L.specName) or (tostring(L.specName) .. ", " .. tostring(L.profile))
                        g.recName = ("%s (%s)"):format(g.name, whose)
                    end
                end
            end
            local anyClass
            if type(cdm) == "table" and type(cdm.specData) == "table" then
                for sk in pairs(cdm.specData) do
                    local cid = IA.SpecKey(sk)
                    if cid then anyClass = anyClass or IA.ClassTag(cid, opts) ctx.classID = ctx.classID or cid end
                end
            end
            if anyClass then CL.c.classes = { [anyClass] = true } end
            node.classID = C.classID or ctx.classID
            node.classTag = node.classID and IA.ClassTag(node.classID, opts) or anyClass
            -- no class known: the class gate cannot hold them, the character does
            if node.classTag then BL.c.classes = { [node.classTag] = true } else BL.c.chars = { [charKey] = true } end
            node.barsLayout = BL
            IA.Yield()
            IA.PlanBars(ctx, charDB, BL, CL)
            IA.Yield()
            IA.PlanReminders(ctx, charDB, CL)
            -- what the panel lists without a pick yet: bars of a kind the import
            -- does not carry, and Arc UI's textures
            node.later = BL.later
            node.textures = IA.PlanTextures(ctx, charDB, BL)
            if #BL.bars > 0 or #CL.bars > 0 or #CL.reminders > 0 then
                hadLayout = true
                local snode = { id = "shared:" .. charKey, kind = "shared", label = "Bars and reminders", children = {} }
                -- a pick per bar: the player brings the ones they use
                for _, BX in ipairs({ BL, CL }) do
                    for _, B in ipairs(BX.bars) do
                        local lf = Leaf(snode, "bar", B.unit, B.name, 1, BX.key, B.name)
                        lf.bar = B
                    end
                end
                if #CL.reminders > 0 then
                    local nrem = 0
                    for _, RG in ipairs(CL.reminders) do nrem = nrem + #RG.reminders end
                    Leaf(snode, "reminders", CL.unitReminders, Tr("Cooldown Reminder: %d reminders"):format(nrem), nrem, CL.key, "Cooldown Reminder")
                end
                node.children[#node.children + 1] = snode
            end
            if #CL.parts > 0 or #CL.bars > 0 or #CL.reminders > 0 then
                plan.layouts[#plan.layouts + 1] = CL
                plan.counts.layouts = plan.counts.layouts + 1
            end
            if #BL.bars > 0 then
                plan.layouts[#plan.layouts + 1] = BL
                plan.counts.layouts = plan.counts.layouts + 1
            end
            -- the character's global look (its account profile's two layers) as saved defaults
            if hadLayout then
                local look = { unit = "look:" .. charKey, profile = profName, defaults = IA.PlanDefaults(ctx),
                    press = IA.PressHighlight(type(charDB) == "table" and charDB.bphSettings or nil, cov) }
                plan.looks[charKey] = look
                Leaf(node, "look", look.unit, Tr("Global look (Arc UI profile '%s')"):format(tostring(profName)), 1, nil, "Arc UI's icon look")
                -- the press highlight it had on is its own pick
                if look.press then
                    look.pressUnit = "press:" .. charKey
                    Leaf(node, "press", look.pressUnit, "Button Press Highlight", 1, nil, "Button Press Highlight")
                end
            end
            if hadLayout or #node.later > 0 or #node.textures > 0 then
                plan.counts.chars = plan.counts.chars + 1
                plan.tree[#plan.tree + 1] = node
            end
        end
    end
    -- each group's cells as v1 draws them, once its profile has fed it
    for _, CL in ipairs(plan.layouts) do
        for _, L in ipairs(CL.parts) do
            for _, g in ipairs(L.groups) do IA.PlaceCells(g, g.icons, cov, opts.ppu and opts.ppu()) end
            IA.SettleGroups(L.groups)
        end
    end
    return plan
end

-- Whether the importer can run here: retail, with v1's saved data loaded.
function IA.Available()
    if NS.IsForever ~= nil then return false end
    local db = rawget(_G, "ArcUIDB")
    return type(db) == "table" and type(db.char) == "table"
end

-- Whether v1's save holds anything the plan would offer: a profile under a spec,
-- a switched-on bar or cast bar, cooldown bars, or reminders. A quick look for the
-- login offer, no plan; a save with only other v1 modules' settings says no.
function IA.HasSetup(db)
    if type(db) ~= "table" or type(db.char) ~= "table" then return false end
    local function On(list, sub)
        for _, cfg in pairs(type(list) == "table" and list or {}) do
            local t = cfg
            if sub then t = type(cfg) == "table" and cfg[sub] or nil end
            if type(t) == "table" and t.enabled == true then return true end
        end
        return false
    end
    local g = type(db.global) == "table" and db.global or {}
    local sharedCast = g.castbarShared == true and On(g.castbars)
    for _, c in pairs(db.char) do
        if type(c) == "table" then
            local specs = type(c.cdmGroups) == "table" and c.cdmGroups.specData or nil
            for sk, sd in pairs(type(specs) == "table" and specs or {}) do
                if IA.SpecKey(sk) and type(sd) == "table" and type(sd.layoutProfiles) == "table" then
                    for _, p in pairs(sd.layoutProfiles) do if type(p) == "table" then return true end end
                end
            end
            if sharedCast or On(c.bars, "tracking") or On(c.resourceBars, "tracking") or On(c.castbars)
                or On({ c.focusCastbar, c.targetCastbar }) then return true end
            if type(c.cooldownBarConfigs) == "table" and next(c.cooldownBarConfigs) ~= nil then return true end
            local cr = c.cooldownReminder
            if type(cr) == "table" and type(cr.whitelist) == "table" and next(cr.whitelist) ~= nil then return true end
        end
    end
    return false
end

-- The stamp: what has been imported, by unit, plus the layout and group records the
-- importer made, so a later run adds the rest to them and never to a player's own.
function IA.Stamp(create)
    local db = rawget(_G, "ArcAurasDB")
    if type(db) ~= "table" then return nil end
    local s = db.importArcUIv1
    if type(s) ~= "table" or type(s.units) ~= "table" then
        if not create then return nil end
        s = { at = 0, units = {}, layouts = {}, groups = {}, recs = {} }
        db.importArcUIv1 = s
    end
    s.layouts = s.layouts or {}
    s.groups = s.groups or {}
    -- [unit] = the record ids that unit made (none for the look and the press highlight)
    s.recs = s.recs or {}
    return s
end

function IA.UnitDone(unit)
    local s = IA.Stamp()
    return s ~= nil and s.units[unit] == true
end

function IA.DoneCount()
    local s = IA.Stamp()
    local n = 0
    for _ in pairs(s and s.units or {}) do n = n + 1 end
    return n
end

-- Imported and still there: one of the records the unit made still exists, so
-- a deleted bar, group or layout reads as never imported and can be brought in
-- again. Every bar of a character shares one layout, so the layout alone can't
-- tell them apart. A unit with no records (the look, the press highlight)
-- counts once imported.
function IA.UnitLive(unit, plan)
    local s = IA.Stamp()
    if not (s and s.units[unit]) then return false end
    local Store = NS.Store
    local ids = s.recs[unit]
    if ids then
        for _, id in ipairs(ids) do
            if Store and Store.Get(id) then return true end
        end
        return false
    end
    -- a stamp from before the records were kept: its layout must live, and
    -- for a bar or group, one of that name must still be in it
    local key = plan and plan.unitLayout and plan.unitLayout[unit]
    if not key then return true end
    local id = s.layouts[key]
    local r = id and Store and Store.Get(id)
    if not (r and r.type == "layout") then return false end
    local leaf = plan.leaves and plan.leaves[unit]
    if not (leaf and leaf.name and (leaf.kind == "bar" or leaf.kind == "group")) then return true end
    local groups, _, bars = Store.ChildrenOf(r)
    for _, c in ipairs(leaf.kind == "bar" and bars or groups) do
        local n = tostring(c.name or "")
        if n == leaf.name or n:sub(1, #leaf.name + 1) == leaf.name .. " " then return true end
    end
    return false
end

-- How many of the plan's units are not in Arc Auras now.
function IA.Remaining(plan)
    if not (plan and plan.leaves) then return 0 end
    local n = 0
    for unit in pairs(plan.leaves) do if not IA.UnitLive(unit, plan) then n = n + 1 end end
    return n
end

function IA.Done(plan)
    if not (plan and plan.leaves) or next(plan.leaves) == nil then return false end
    return IA.Remaining(plan) == 0
end

-- "Name-Realm" of the character logged in.
function IA.CurrentChar()
    local un, rn = rawget(_G, "UnitName"), rawget(_G, "GetRealmName")
    local name = un and un("player")
    if type(name) ~= "string" or name == "" then return nil end
    local realm = rn and rn()
    return name .. "-" .. (type(realm) == "string" and realm or "")
end

-- This character's active profiles, bars, reminders and global look; nothing of the
-- other characters, nothing that is in Arc Auras now. The picker starts empty.
function IA.DefaultPicks(plan)
    local picks = {}
    local me = IA.CurrentChar()
    if not (plan and plan.tree and me) then return picks end
    local function Walk(node, on)
        if node.unit then
            if on and not IA.UnitLive(node.unit, plan) then picks[node.unit] = true end
            return
        end
        for _, ch in ipairs(node.children or {}) do
            local childOn = on
            if ch.kind == "profile" then childOn = on and ch.tag == "active" end
            Walk(ch, childOn)
        end
    end
    for _, node in ipairs(plan.tree) do Walk(node, node.charKey == me) end
    return picks
end

-- The game's readers, each guarded: a missing API leaves the plan unresolved.
function IA.GameOpts()
    local o = {}
    -- the client's physical pixels per UI unit, as Arc UI measured them
    o.ppu = function()
        local _, h = GetPhysicalScreenSize()
        local sc = UIParent and UIParent:GetScale()
        if type(h) ~= "number" or h <= 0 or type(sc) ~= "number" or sc <= 0 then return 1 end
        return (h / 768) * sc
    end
    local CV = rawget(_G, "C_CooldownViewer")
    if type(CV) == "table" and CV.GetCooldownViewerCooldownInfo then
        o.cooldown = function(id)
            if type(id) ~= "number" then return nil end
            return CV.GetCooldownViewerCooldownInfo(id)
        end
    end
    local MM = NS.CDMMirror
    if type(CV) == "table" and CV.GetCooldownViewerCooldownInfo and CV.GetLayoutData and MM then
        -- whether an entry shows in one spec's active Cooldown Manager layout, for the
        -- character logged in: its default category (hidden when flagged so), then the
        -- player's moves (Blizzard's merge, Core\AD_CDMMirror.lua). nil = can't tell.
        local saved
        local function Saved()
            if saved == nil then
                local raw = CV.GetLayoutData()
                if type(raw) ~= "string" or not MM.Plain(raw) then
                    saved = "unknown"
                elseif raw == "" then
                    saved = "none"
                else
                    saved = MM.Decode(raw) or "unknown"
                end
            end
            return saved
        end
        o.cdmShown = function(id, classID, specIndex)
            if type(id) ~= "number" or type(classID) ~= "number" or type(specIndex) ~= "number" then return nil end
            Saved()
            if saved == "unknown" then return nil end
            local info = MM.CopyInfo(CV.GetCooldownViewerCooldownInfo(id))
            if not (info and type(info.category) == "number") then return nil end
            local cat = info.category
            if MM.HasFlag(info.flags, MM.Flag("HideByDefault")) then cat = MM.HiddenOf(cat) end
            local lay = type(saved) == "table" and MM.ActiveLayout(saved, classID * 10 + specIndex) or nil
            local moves = type(lay) == "table" and lay[2]
            if type(moves) == "table" then
                for c, ids in pairs(moves) do
                    if type(ids) == "table" then
                        for i = 1, #ids do
                            if ids[i] == id then cat = tonumber(c) or cat end
                        end
                    end
                end
            end
            return cat ~= MM.HIDDEN_ACTIVE and cat ~= MM.HIDDEN_PASSIVE
        end
        -- whether an entry is in one spec's Cooldown Manager at all, for the character logged
        -- in: the spec in play by its category sets, another by its saved layout's order, which
        -- Blizzard writes with every entry of that spec. nil = can't tell.
        local inPlay
        o.cdmInSpec = function(id, classID, specIndex)
            if type(id) ~= "number" or type(classID) ~= "number" or type(specIndex) ~= "number" then return nil end
            local tag = classID * 10 + specIndex
            if tag == MM.Tag() then
                if inPlay == nil and CV.GetCooldownViewerCategorySet then
                    inPlay = {}
                    for _, name in ipairs(MM.CATS) do
                        local ids = CV.GetCooldownViewerCategorySet(MM.Cat(name), true)
                        if type(ids) ~= "table" or not MM.Plain(ids) then inPlay = false break end
                        for i = 1, #ids do
                            if MM.Plain(ids[i]) then inPlay[ids[i]] = true end
                        end
                    end
                end
                if type(inPlay) ~= "table" then return nil end
                return inPlay[id] == true
            end
            local lay = type(Saved()) == "table" and MM.ActiveLayout(saved, tag) or nil
            local order = type(lay) == "table" and lay[1]
            if type(order) ~= "table" or #order == 0 then return nil end
            for i = 1, #order do
                if order[i] == id then return true end
            end
            return false
        end
    end
    local SI = rawget(_G, "C_SpecializationInfo")
    local specInfo = (type(SI) == "table" and SI.GetSpecializationInfoForClassID) or rawget(_G, "GetSpecializationInfoForClassID")
    if specInfo then
        o.specID = function(classID, idx)
            local id, name = specInfo(classID, idx)
            return id, name
        end
    end
    local classInfo = rawget(_G, "GetClassInfo")
    if classInfo then
        o.classTag = function(classID)
            local _, tag = classInfo(classID)
            return tag
        end
    end
    local CS = rawget(_G, "C_Spell")
    if type(CS) == "table" then
        if CS.GetSpellName then o.spellName = function(id) return CS.GetSpellName(id) end end
        if CS.IsSpellHarmful then o.spellHarmful = function(id) return CS.IsSpellHarmful(id) end end
        if CS.GetSpellTexture then o.spellTexture = function(id) return CS.GetSpellTexture(id) end end
        -- the item that last started a potion's category cooldown, when the game says plainly
        if CS.GetLastCategoryCooldownSource then
            o.categoryItem = function(cat)
                local _, iid = CS.GetLastCategoryCooldownSource(cat)
                if type(iid) ~= "number" or (issecretvalue and issecretvalue(iid)) or iid <= 0 then return nil end
                return iid
            end
        end
    end
    local CI = rawget(_G, "C_Item")
    if type(CI) == "table" and CI.GetItemNameByID then o.itemName = function(id) return CI.GetItemNameByID(id) end end
    -- the Tracked Buffs viewer's Hide When Inactive (an Edit Mode setting, read only)
    local BV = rawget(_G, "BuffIconCooldownViewer")
    if type(BV) == "table" and BV.GetHideWhenInactive then
        o.cdmHidesMissing = function() return BV:GetHideWhenInactive() == true end
    end
    return o
end

-- The plan for this account's v1 data, with the game's readers.
function IA.Preview()
    if not IA.Available() then return nil end
    return IA.Plan(rawget(_G, "ArcUIDB"), IA.GameOpts())
end

-- Writes one plan override table onto a record through the Store, fields the
-- schema takes for that record only, so the record stays sparse and clean.
function IA.WriteO(rec, o)
    local Store, Schema = NS.Store, NS.Schema
    local fam = Schema[Store.FamilyOf(rec)]
    if not fam then return end
    for section, fields in pairs(o or {}) do
        local sec = fam[section]
        if sec and sec.fields then
            for f, v in pairs(fields) do
                local def = sec.fields[f]
                if def and Schema.Applies(def, sec, Store.KindOf(rec), rec.barMode) then
                    Store.SetOverride(rec, section, f, Copy(v))
                end
            end
        end
    end
end

-- A plan anchor onto a record: a group by name inside the layout (a bar in the
-- shared layout takes the character's group of that name, from the layout of one
-- of the bar's specs when it has any), a frame or the mouse.
function IA.WriteAnchor(rec, a, groupIds, isBar, charGroups)
    if not a then return end
    local o = { anchorEnabled = true, anchorSrcPoint = a.src, anchorDstPoint = a.dst,
        anchorOffsetX = a.x, anchorOffsetY = a.y }
    if a.kind == "group" then
        local id = groupIds[a.group]
        if not id and charGroups and charGroups[a.group] then
            local specs = rec.c and rec.c.specs
            for _, e in ipairs(charGroups[a.group]) do
                if not specs or not e.specs then id = id or e.id
                else
                    for s in pairs(specs) do if e.specs[s] then id = e.id break end end
                end
                if id and specs and e.specs then break end
            end
            id = id or charGroups[a.group][1].id
        end
        if not id then return false end
        o.anchorTargetKind, o.anchorTargetId = "group", id
        if isBar and a.match then
            o.anchorMatchWidth = true
            o.anchorMatchWidthAdjust = a.adjust or 0
        end
    elseif a.kind == "frame" then
        o.anchorTargetKind, o.anchorTargetFrame = "frame", a.frame
    elseif a.kind == "mouse" then
        o.anchorTargetKind = "mouse"
    else
        return false
    end
    IA.WriteO(rec, { anchor = o })
    return true
end

-- Applies the picked units of a plan (a set of leaf units; nil = everything not in
-- Arc Auras now): fresh records through the Store, the picked look as saved defaults,
-- every unit stamped. A layout made on an earlier run (the stamp's ids) takes new parts
-- of it; a part imported before whose layout still exists comes in again as a fresh
-- copy (the old one stays for the player to delete). A player's own records are never
-- touched. Refused in combat. how.charOnly[charKey]: that character's bars layout, when
-- this run makes it, loads on the character alone.
function IA.Apply(plan, picks, how)
    local Store = NS.Store
    if not (Store and plan and plan.layouts) then return nil, Tr("nothing to import") end
    local lock = rawget(_G, "InCombatLockdown")
    if lock and lock() then return nil, Tr("not in combat") end
    local db = rawget(_G, "ArcAurasDB")
    if type(db) ~= "table" then return nil, Tr("the store is not loaded") end
    local stamp = IA.Stamp(true)
    if picks == nil then
        picks = {}
        for unit in pairs(plan.leaves or {}) do if not IA.UnitLive(unit, plan) then picks[unit] = true end end
    end
    local leaves = plan.leaves or {}
    local function Picked(unit) return unit ~= nil and picks[unit] == true and leaves[unit] ~= nil end
    local any = false
    for unit in pairs(picks) do if Picked(unit) then any = true break end end
    if not any then return nil, Tr("nothing picked") end
    local res = { layouts = 0, groups = 0, icons = 0, bars = 0, reminders = 0, skipped = 0, anchorsDropped = 0, units = 0, firstLayoutId = nil }
    local Schema = NS.Schema
    local function Live(id, kind)
        local r = id and Store.Get(id)
        if r and r.type == kind then return r end
        return nil
    end
    -- the layouts this run makes again: one of their picked parts is in a live copy
    local again = {}
    for unit in pairs(picks) do
        local key = Picked(unit) and plan.unitLayout and plan.unitLayout[unit]
        if key and IA.UnitLive(unit, plan) and Live(stamp.layouts[key], "layout") then again[key] = true end
    end
    local function EnsureLayout(key, L)
        local lay = not again[key] and Live(stamp.layouts[key], "layout") or nil
        if not lay then
            if not again[key] and stamp.layouts[key] ~= nil then
                -- the layout an earlier run made is gone, and what it held with it:
                -- its units must not read as imported once this run makes it anew
                for u, k in pairs(plan.unitLayout or {}) do
                    if k == key then stamp.units[u], stamp.recs[u] = nil, nil end
                end
            end
            if again[key] then
                -- the old copy keeps its groups; this copy anchors to its own, and
                -- the rest of this run adds to it
                local prefix = key .. "|"
                for gk in pairs(stamp.groups) do
                    if gk:sub(1, #prefix) == prefix then stamp.groups[gk] = nil end
                end
                again[key] = nil
            end
            lay = Store.NewLayout(L.name)
            lay.pos = { x = 0, y = 0 }
            lay.c = Copy(L.c)
            if L.forBars and how and how.charOnly and how.charOnly[L.charKey] then lay.c.chars = { [L.charKey] = true } end
            IA.WriteO(lay, L.o)
            stamp.layouts[key] = lay.id
            res.layouts = res.layouts + 1
        end
        res.firstLayoutId = res.firstLayoutId or lay.id
        return lay
    end
    -- each group is one unit: a run makes it once (a part imported before comes in a fresh copy)
    local function MakeGroup(key, lay, G)
        local g = Store.NewGroup(lay.id, G.recName or G.name, G.kind)
        g.pos = { x = G.pos.x, y = G.pos.y }
        g.c = Copy(G.c)
        IA.WriteO(g, G.o)
        -- the game frames it moves (Core\AD_Pins.lua)
        if G.pins then g.pins = Copy(G.pins) end
        stamp.groups[key] = g.id
        res.groups = res.groups + 1
        return g
    end
    -- who: the icon's profile place, for one its group refuses (it goes free in the layout)
    local function AddIcon(I, lay, groupId, who)
        if I.unresolved or (I.kind == "spell" and not I.driver.spellID) then
            res.skipped = res.skipped + 1
            return
        end
        local rec = Store.NewIcon(I.kind, Copy(I.driver), groupId, lay.id, I.name)
        local loose = false
        if not rec and groupId then
            rec = Store.NewIcon(I.kind, Copy(I.driver), nil, lay.id, I.name)
            if rec then
                local g = Store.Get(groupId)
                rec.pos = { x = (g and g.pos.x) or 0, y = (g and g.pos.y) or 0 }
                loose = true
            end
        end
        if not rec then res.skipped = res.skipped + 1 return end
        rec.c = Copy(I.c or {})
        if loose then
            if who then IA.GatePart(rec.c, who) end
            groupId = nil
        end
        if groupId then
            rec.gpos = I.gpos and { row = I.gpos.row, col = I.gpos.col } or nil
        elseif I.pos then
            rec.pos = { x = I.pos.x, y = I.pos.y }
        end
        IA.WriteO(rec, I.o)
        res.icons = res.icons + 1
        return rec
    end
    -- ids: the records the unit made; none made (the look, icons the game could
    -- not name yet) leaves it to its layout
    local function Mark(unit, ids)
        stamp.units[unit] = true
        stamp.recs[unit] = (ids and #ids > 0) and ids or nil
        res.units = res.units + 1
    end
    -- the global look: one set of saved defaults (the last picked wins), fields the kind takes
    db.newDefaults = db.newDefaults or {}
    local lookKeys = {}
    for charKey in pairs(plan.looks or {}) do lookKeys[#lookKeys + 1] = charKey end
    table.sort(lookKeys)
    for _, charKey in ipairs(lookKeys) do
        local look = plan.looks[charKey]
        if Picked(look.unit) then
            for fk, secs in pairs(look.defaults or {}) do
                local kind = fk:match("^icon:(%a+)$")
                for section, fields in pairs(secs) do
                    local sec = Schema.icon[section]
                    if sec and sec.fields then
                        for f, v in pairs(fields) do
                            local def = sec.fields[f]
                            if def and Schema.Applies(def, sec, kind, nil) then
                                db.newDefaults[fk] = db.newDefaults[fk] or {}
                                db.newDefaults[fk][section] = db.newDefaults[fk][section] or {}
                                db.newDefaults[fk][section][f] = Copy(v)
                            end
                        end
                    end
                end
            end
            Mark(look.unit)
        end
        -- the press highlight it had on, its own pick (the last picked one wins, as the look)
        if look.press and Picked(look.pressUnit) then
            for _, k in ipairs(IA.PRESS_KEYS) do Store.SetSetting(k, Copy(look.press[k])) end
            Mark(look.pressUnit)
        end
    end
    -- each character's one layout: the picked profiles' groups and free icons
    local later = {}
    for _, CL in ipairs(plan.layouts) do
        for _, L in ipairs(CL.parts) do
            for _, G in ipairs(L.groups) do
                if Picked(G.unit) then
                    local lay = EnsureLayout(CL.key, CL)
                    local g = MakeGroup(L.key .. "|" .. G.name, lay, G)
                    for _, I in ipairs(G.icons) do AddIcon(I, lay, g.id, L.who) end
                    if G.anchor then later[#later + 1] = { rec = g, a = G.anchor, layoutKey = L.key } end
                    Mark(G.unit, { g.id })
                end
            end
            if #L.icons > 0 and Picked(L.freeUnit) then
                local lay = EnsureLayout(CL.key, CL)
                local ids = {}
                for _, I in ipairs(L.icons) do
                    local rec = AddIcon(I, lay, nil)
                    if rec then ids[#ids + 1] = rec.id end
                end
                Mark(L.freeUnit, ids)
            end
        end
    end
    -- group anchors, by name inside their profile (this run's groups and earlier runs')
    local function GroupIds(layoutKey)
        local ids = {}
        local prefix = layoutKey .. "|"
        for key, id in pairs(stamp.groups) do
            if key:sub(1, #prefix) == prefix and Live(id, "group") then ids[key:sub(#prefix + 1)] = id end
        end
        return ids
    end
    for _, e in ipairs(later) do
        if not IA.WriteAnchor(e.rec, e.a, GroupIds(e.layoutKey), false) then res.anchorsDropped = res.anchorsDropped + 1 end
    end
    -- then each character's bars (anchored to its live groups by name) and reminders
    for _, L in ipairs(plan.layouts) do
        local wantBars = false
        for _, B in ipairs(L.bars) do if Picked(B.unit) then wantBars = true break end end
        local wantRem = #L.reminders > 0 and Picked(L.unitReminders)
        if wantBars or wantRem then
            local lay = EnsureLayout(L.key, L)
            if wantBars then
                local charGroups = IA.CharGroups(plan, stamp, L.charKey)
                for _, B in ipairs(L.bars) do
                    if Picked(B.unit) then
                        local rec = Store.NewBar(lay.id, B.barKind, Copy(B.driver), B.name, B.barMode)
                        if rec then
                            rec.c = Copy(B.c or {})
                            rec.pos = { x = B.pos.x, y = B.pos.y }
                            IA.WriteO(rec, B.o)
                            if B.looks then rec.looks = Copy(B.looks) end
                            res.bars = res.bars + 1
                            if B.anchor and not IA.WriteAnchor(rec, B.anchor, {}, true, charGroups) then res.anchorsDropped = res.anchorsDropped + 1 end
                        end
                        Mark(B.unit, { rec and rec.id or nil })
                    end
                end
            end
            if wantRem then
                local ids = {}
                for _, RG in ipairs(L.reminders) do
                    local g = Store.NewGroup(lay.id, RG.name, "reminder")
                    ids[#ids + 1] = g.id
                    g.pos = { x = RG.pos.x, y = RG.pos.y }
                    g.c = Copy(RG.c)
                    IA.WriteO(g, RG.o)
                    res.groups = res.groups + 1
                    for _, R in ipairs(RG.reminders) do
                        local rec = Store.NewReminder(g.id, R.kind, R.id, R.name)
                        if rec then
                            rec.triggers = Copy(R.triggers)
                            rec.c = Copy(R.c or {})
                            res.reminders = res.reminders + 1
                        end
                    end
                end
                Mark(L.unitReminders, ids)
            end
        end
    end
    Store.Normalize()
    local clock = rawget(_G, "time")
    stamp.at = clock and clock() or 0
    db.migratedFrom = IA.STAMP
    Store.Dirty("tree")
    return res
end

-- A character's live groups by their Arc UI name (its active profiles' ones, each with
-- its spec), for its bars' anchors.
function IA.CharGroups(plan, stamp, charKey)
    local Store = NS.Store
    local out = {}
    local function Add(name, id, specs)
        local r = id and Store.Get(id)
        if not (r and r.type == "group") then return end
        out[name] = out[name] or {}
        table.insert(out[name], { id = id, specs = specs })
    end
    for _, CL in ipairs(plan.layouts) do
        if CL.charKey == charKey then
            for _, L in ipairs(CL.parts) do
                if L.active and not L.dormant then
                    for _, G in ipairs(L.groups) do Add(G.name, stamp.groups[L.key .. "|" .. G.name], L.who.specs) end
                end
            end
        end
    end
    return out
end
