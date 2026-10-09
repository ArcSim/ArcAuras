-- AD_ImportArcUI: reads an installed Arc UI v1 setup and copies it into Arc Auras records.
-- It owns the v1 field matrix, Plan (v1 data in, record plans out, no game reads) and
-- Apply (writes through the Store); the New Layout page's card calls both.
-- Retail only, and read-only on v1: the v1 saved data is never written, and a stamp on
-- the store keeps a second run from duplicating anything.
local ADDON, NS = ...

local IA = {}
NS.ImportArcUI = IA

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

-- The v1 icon defaults that shape a look. v1 strips defaults from its saved data, so a
-- per-icon table only says what differs from these plus the v1 global layer.
IA.V1_ICON_DEFAULTS = {
    scale = 1, aspectRatio = 1, zoom = 0.08, padding = 0, alpha = 1, keepBright = false,
    keepBrightAllowDesat = false, forceHideIcon = false, shadowSize = 1,
    cooldownStateVisuals = {
        readyState = { alpha = 1, glow = false, glowType = "button", glowIntensity = 1, glowScale = 1,
            glowSpeed = 0.25, glowLines = 8, glowThickness = 2, glowParticles = 4 },
        cooldownState = { alpha = 1, desaturate = false, noDesaturate = false, waitForNoCharges = false },
    },
    rangeIndicator = { enabled = true },
    spellUsability = { enabled = true },
    procGlow = { enabled = true, alpha = 1, scale = 1, glowType = "default", lines = 8, thickness = 2,
        particles = 4, speed = 0.25 },
    border = { enabled = false, color = { 1, 1, 1, 1 }, thickness = 2, inset = -3, useClassColor = false },
    cooldownSwipe = { showSwipe = true, noGCDSwipe = false, showEdge = true, showBling = true,
        reverse = false, reverseWhileAura = false, swipeInset = 0, separateInsets = false,
        swipeInsetX = 0, swipeInsetY = 0, swipeWaitForNoCharges = false, edgeWaitForNoCharges = false },
    auraActiveState = { ignoreAuraOverride = false, glow = false, glowType = "button", glowIntensity = 1,
        glowScale = 1, glowSpeed = 0.25, glowLines = 8, glowThickness = 2, glowParticles = 4,
        glowCombatOnly = false, desaturateWhenInactive = false },
    chargeText = { enabled = true, hideAtZero = false, showSingleStack = false, size = 16,
        color = { r = 1, g = 1, b = 1, a = 1 }, font = "Friz Quadrata TT", outline = "OUTLINE",
        shadow = false, anchor = "BOTTOMRIGHT", offsetX = -2, offsetY = 2 },
    cooldownText = { enabled = true, hideWhenHasCharges = false, size = 14,
        color = { r = 1, g = 1, b = 1, a = 1 }, font = "Friz Quadrata TT", outline = "OUTLINE",
        shadow = false, anchor = "CENTER", offsetX = 0, offsetY = 0, decimals = 0,
        decimalThreshold = 0, abbrevThreshold = 0, durationColor = false },
}

-- v1's group record defaults (MakeDefaultGroup); a stored record carries most of them.
IA.V1_GROUP_DEFAULTS = {
    gridRows = 2, gridCols = 4, iconSize = 36, iconWidth = 36, iconHeight = 36, spacing = 2,
    showBorder = false, showBackground = false, autoReflow = true, containerPadding = -4,
    lockGridSize = false, dynamicLayout = false, dynamicCooldowns = false, dynamicContainerSize = false,
    horizontalGrowth = "RIGHT", verticalGrowth = "DOWN",
}

-- v1 hide keys (groups' visibility tables, bars' hideWhen) -> Arc Auras fade conditions.
IA.HIDE_WHEN = {
    hideOOC = "outOfCombat", hideInCombat = "inCombat", hideMounted = "mounted",
    hideInVehicle = "vehicle", hideDead = "dead", hideResting = "resting", hideSolo = "solo",
    hideInGroup = "party", hideInRaid = "raid", hideInInstance = "instance",
    hideInEncounter = "encounter", hideInPetBattle = "petBattle", hidePvP = "pvp",
    hideDragonriding = "flying", hideNoTarget = "noTarget", hideHasTarget = "hasTarget",
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

IA.GLOW_TYPES = { default = "button", proc = "proc", pixel = "pixel", autocast = "autocast",
    button = "button", ants = "ants", ach_proc = "procloop", cdm_flash = "flash" }
IA.PROC_TYPES = { default = "proc", proc = "proc", pixel = "pixel", autocast = "autocast",
    button = "button", ants = "ants", ach_proc = "procloop", cdm_flash = "flash" }
IA.AURA_GLOW_TYPES = { default = "button", proc = "proc", pixel = "pixel", autocast = "autocast",
    button = "button", ants = "ants", ach_proc = "proc", cdm_flash = "flash" }
IA.ABBREV = { 0, 120, 300, 600, 3600 }
IA.TEXT_ANCHORS = { CENTER = true, TOP = true, BOTTOM = true, TOPLEFT = true, TOPRIGHT = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true }
IA.GLOW_STRATA = { LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
IA.AURA_UNITS = { "player", "target", "focus", "pet", "party1", "party2", "party3", "party4" }
-- v1 secondary resource names -> retail power ids Arc Auras draws
IA.POWERS = { comboPoints = 4, holyPower = 9, chi = 12, runes = 5, soulShards = 7, essence = 19,
    arcaneCharges = 16, stagger = 100 }
-- an Automatic bar's excluded powers -> the conditions' "Using ..." rows
IA.POWER_ROWS = { [0] = "powerMana", [1] = "powerRage", [3] = "powerEnergy", [8] = "powerAstral" }

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end
IA.Copy = Copy

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
    glow = function(v) return IA.GLOW_TYPES[v] or "button" end,
    auraglow = function(v) return IA.AURA_GLOW_TYPES[v] or "button" end,
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
    -- v1 hides the GCD swipe when on; off is the Cooldown Manager's full swipe and edge
    gcd = function(v) return v and "hidden" or "both" end,
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
    pad = function(v)
        v = tonumber(v) or 0
        if v < 0 then v = 0 elseif v > 20 then v = 20 end
        return v
    end,
    anchor7 = function(v)
        if IA.TEXT_ANCHORS[v] then return v end
        return nil, "anchor " .. tostring(v) .. " is not offered on icon texts"
    end,
    num = function(v) return tonumber(v) end,
    bool = function(v) return v == true end,
    int = function(v)
        v = tonumber(v)
        return v and math.floor(v + 0.5) or nil
    end,
}

-- The icon matrix: v1 setting path -> { section, field, conv, k, sp }. k = "cd" (spell,
-- item, trinket, totem) or "au" (aura); none = both. sp = spell icons only among the
-- cooldown kinds. A `gap` row is a known v1 setting Arc Auras has no field for.
IA.ICON_MAP = {
    scale = { "position", "iconScale", "num" },
    width = { "position", "iconWidth", "int" },
    height = { "position", "iconHeight", "int" },
    useGroupScale = { "position", "useGroupScale", "bool" },
    aspectRatio = { "appearance", "aspectRatio", "num" },
    zoom = { "appearance", "zoom", "num" },
    padding = { "appearance", "padding", "pad" },
    alpha = { "appearance", "alpha", "num" },
    keepBright = { "appearance", "keepBright", "bool", k = "cd", auspecial = "keepBrightAura" },
    keepBrightAllowDesat = { "appearance", "keepBrightAllowDesat", "bool", k = "cd" },
    forceHideIcon = { "appearance", "forceHideIcon", "bool" },
    shadowSize = { "appearance", "shadowSize", "num" },
    hideShadow = { special = "shadow" },
    customIconID = { special = "customIcon" },
    noPing = { gap = "the Cooldown Manager's ping has no Arc Auras twin", nv = true },
    ["debuffBorder.enabled"] = { "appearance", "dispelBorder", "bool", k = "au" },
    ["pandemicBorder.enabled"] = { gap = "Arc Auras draws no pandemic border; the aura glow's Glow when: time left is the nearest look" },
    ["position.mode"] = { special = "freepos" },
    ["position.freeX"] = { special = "freepos" },
    ["position.freeY"] = { special = "freepos" },
    -- ready state (cooldown kinds) / aura active (aura icons)
    ["cooldownStateVisuals.readyState.alpha"] = { "states", "readyAlpha", "num", k = "cd",
        au = { "auraActive", "activeAlpha", "num" } },
    ["cooldownStateVisuals.readyState.desaturate"] = { "states", "readyDesaturate", "bool",
        au = { "auraActive", "activeDesaturate", "bool" } },
    ["cooldownStateVisuals.readyState.noDesaturate"] = { gap = "no desaturate-while-ready look" },
    ["cooldownStateVisuals.readyState.preserveDurationText"] = { "states", "preserveDurationText", "bool", k = "cd",
        au = { "states", "preserveDurationText", "bool" } },
    ["cooldownStateVisuals.readyState.procOverride"] = { "states", "procOverride", "bool", k = "cd", sp = true },
    ["cooldownStateVisuals.readyState.tint"] = { "auraActive", "activeTintEnabled", "bool", k = "au",
        gapcd = "the ready tint is the usability normal colour on cooldown icons" },
    ["cooldownStateVisuals.readyState.tintColor"] = { "auraActive", "activeTintColor", "color", k = "au",
        gapcd = "the ready tint is the usability normal colour on cooldown icons" },
    ["cooldownStateVisuals.readyState.glow"] = { "states", "readyGlow", "bool", k = "cd",
        au = { "auraActive", "activeGlow", "bool" } },
    ["cooldownStateVisuals.readyState.glowType"] = { "states", "readyGlowType", "glow", k = "cd",
        au = { "auraActive", "activeGlowType", "auraglow" } },
    ["cooldownStateVisuals.readyState.glowColor"] = { "states", "readyGlowColor", "color", k = "cd",
        au = { "auraActive", "activeGlowColor", "color" } },
    ["cooldownStateVisuals.readyState.glowCombatOnly"] = { "states", "readyGlowCombatOnly", "bool", k = "cd",
        au = { "auraActive", "activeGlowCombatOnly", "bool" } },
    ["cooldownStateVisuals.readyState.glowIntensity"] = { "states", "readyGlowIntensity", "num", k = "cd",
        au = { "auraActive", "activeGlowIntensity", "num" } },
    ["cooldownStateVisuals.readyState.glowScale"] = { "states", "readyGlowScale", "num", k = "cd",
        au = { "auraActive", "activeGlowScale", "num" } },
    ["cooldownStateVisuals.readyState.glowSpeed"] = { "states", "readyGlowSpeed", "num", k = "cd",
        au = { "auraActive", "activeGlowSpeed", "num" } },
    ["cooldownStateVisuals.readyState.glowLines"] = { "states", "readyGlowLines", "int", k = "cd",
        au = { "auraActive", "activeGlowLines", "int" } },
    ["cooldownStateVisuals.readyState.glowThickness"] = { "states", "readyGlowThickness", "int", k = "cd",
        au = { "auraActive", "activeGlowThickness", "int" } },
    ["cooldownStateVisuals.readyState.glowLength"] = { "states", "readyGlowLength", "int", k = "cd",
        au = { "auraActive", "activeGlowLength", "int" } },
    ["cooldownStateVisuals.readyState.glowParticles"] = { "states", "readyGlowParticles", "int", k = "cd",
        au = { "auraActive", "activeGlowParticles", "int" } },
    ["cooldownStateVisuals.readyState.glowXOffset"] = { "states", "readyGlowXOffset", "int", k = "cd",
        au = { "auraActive", "activeGlowXOffset", "int" } },
    ["cooldownStateVisuals.readyState.glowYOffset"] = { "states", "readyGlowYOffset", "int", k = "cd",
        au = { "auraActive", "activeGlowYOffset", "int" } },
    ["cooldownStateVisuals.readyState.glowFrameStrata"] = { "states", "readyGlowStrata", "strata", k = "cd",
        au = { "auraActive", "activeGlowStrata", "strata" } },
    ["cooldownStateVisuals.readyState.glowFrameLevel"] = { "states", "readyGlowLevel", "int", k = "cd",
        au = { "auraActive", "activeGlowLevel", "int" } },
    ["cooldownStateVisuals.readyState.glowWhileChargesAvailable"] = { special = "glowCharges", k = "cd", sp = true },
    ["cooldownStateVisuals.readyState.glowAuraType"] = { gap = "the glow watches the icon's own aura; there is no aura to pick", nv = true },
    ["cooldownStateVisuals.readyState.glowThreshold"] = { special = "glowTime", sp = true },
    ["cooldownStateVisuals.readyState.glowThresholdSeconds"] = { special = "glowTime", sp = true },
    -- on cooldown (cooldown kinds) / aura missing (aura icons)
    ["cooldownStateVisuals.cooldownState.alpha"] = { "states", "cooldownAlpha", "num", k = "cd",
        au = { "auraMissing", "missingAlpha", "num" } },
    ["cooldownStateVisuals.cooldownState.desaturate"] = { special = "desat" },
    ["cooldownStateVisuals.cooldownState.noDesaturate"] = { special = "desat" },
    ["cooldownStateVisuals.cooldownState.preserveDurationText"] = { "states", "preserveDurationText", "bool", k = "cd",
        au = { "auraMissing", "missingPreserveText", "bool" } },
    ["cooldownStateVisuals.cooldownState.procOverride"] = { "states", "procOverride", "bool", k = "cd", sp = true },
    ["cooldownStateVisuals.cooldownState.waitForNoCharges"] = { "states", "waitForNoCharges", "bool", k = "cd", sp = true },
    ["cooldownStateVisuals.cooldownState.tint"] = { "states", "cooldownTintEnabled", "bool", k = "cd",
        gapau = "Arc Auras has no tint while an aura is missing" },
    ["cooldownStateVisuals.cooldownState.tintColor"] = { "states", "cooldownTintColor", "color", k = "cd",
        gapau = "Arc Auras has no tint while an aura is missing" },
    ["cooldownStateVisuals.cooldownState.dimWhenEmpty"] = { special = "dimEmpty", k = "cd" },
    ["cooldownStateVisuals.cooldownState.glow"] = { gap = "no glow while on cooldown or inactive" },
    ["cooldownStateVisuals.cooldownState.glowType"] = { gap = "no glow while on cooldown or inactive" },
    ["cooldownStateVisuals.cooldownState.glowColor"] = { gap = "no glow while on cooldown or inactive" },
    ["cooldownStateVisuals.cooldownState.glowCombatOnly"] = { gap = "no glow while on cooldown or inactive" },
    -- range, usability, proc glow: spell icons
    ["rangeIndicator.enabled"] = { "states", "rangeTint", "bool", k = "cd", sp = true },
    ["rangeIndicator.alpha"] = { "states", "rangeAlpha", "num", k = "cd", sp = true },
    ["rangeIndicator.desaturate"] = { "states", "rangeDesaturate", "bool", k = "cd", sp = true },
    ["spellUsability.enabled"] = { "states", "unusableTintEnabled", "bool", k = "cd", sp = true },
    ["spellUsability.procOverride"] = { "states", "procOverride", "bool", k = "cd", sp = true },
    ["spellUsability.useNormalColor"] = { "states", "readyTintEnabled", "bool", k = "cd" },
    ["spellUsability.normalColor"] = { "states", "readyTintColor", "color", k = "cd" },
    ["spellUsability.normalDesaturate"] = { special = "readyDesat", k = "cd" },
    ["spellUsability.useOnCooldownColor"] = { "states", "cooldownTintEnabled", "bool", k = "cd" },
    ["spellUsability.onCooldownColor"] = { "states", "cooldownTintColor", "color", k = "cd" },
    ["spellUsability.onCooldownDesaturate"] = { "states", "cooldownDesaturate", "bool", k = "cd" },
    ["spellUsability.notEnoughResourceAlpha"] = { "states", "resourceAlpha", "num", k = "cd", sp = true },
    ["spellUsability.notEnoughResourceColor"] = { "states", "resourceTintColor", "color", k = "cd", sp = true },
    ["spellUsability.notEnoughResourceDesaturate"] = { "states", "resourceDesaturate", "bool", k = "cd", sp = true },
    ["spellUsability.notUsableAlpha"] = { "states", "unusableAlpha", "num", k = "cd", sp = true },
    ["spellUsability.notUsableColor"] = { "states", "unusableTintColor", "color", k = "cd", sp = true },
    ["spellUsability.notUsableDesaturate"] = { "states", "unusableDesaturate", "bool", k = "cd", sp = true },
    ["spellUsability.usableGlow"] = { "states", "usableGlow", "bool", k = "cd", sp = true },
    ["spellUsability.usableGlowCombatOnly"] = { "states", "usableGlowCombatOnly", "bool", k = "cd", sp = true },
    ["spellUsability.usableGlowType"] = { "states", "usableGlowType", "glow", k = "cd", sp = true },
    ["spellUsability.usableGlowColor"] = { "states", "usableGlowColor", "color", k = "cd", sp = true },
    ["spellUsability.usableGlowScale"] = { "states", "usableGlowScale", "num", k = "cd", sp = true },
    ["spellUsability.usableGlowSpeed"] = { "states", "usableGlowSpeed", "num", k = "cd", sp = true },
    ["spellUsability.usableGlowLines"] = { "states", "usableGlowLines", "int", k = "cd", sp = true },
    ["spellUsability.usableGlowThickness"] = { "states", "usableGlowThickness", "int", k = "cd", sp = true },
    ["spellUsability.usableGlowParticles"] = { "states", "usableGlowParticles", "int", k = "cd", sp = true },
    ["spellUsability.usableGlowXOffset"] = { "states", "usableGlowXOffset", "int", k = "cd", sp = true },
    ["spellUsability.usableGlowYOffset"] = { "states", "usableGlowYOffset", "int", k = "cd", sp = true },
    ["spellUsability.usableGlowFrameStrata"] = { "states", "usableGlowStrata", "strata", k = "cd", sp = true },
    ["spellUsability.usableGlowFrameLevel"] = { "states", "usableGlowLevel", "int", k = "cd", sp = true },
    ["procGlow.enabled"] = { "states", "procGlow", "bool", k = "cd", sp = true, gapau = "auras never proc; the switch did nothing in Arc UI either", nvau = true },
    ["procGlow.glowType"] = { "states", "procGlowType", "proc", k = "cd", sp = true },
    ["procGlow.color"] = { "states", "procGlowColor", "color", k = "cd", sp = true },
    ["procGlow.alpha"] = { "states", "procGlowIntensity", "num", k = "cd", sp = true },
    ["procGlow.scale"] = { "states", "procGlowScale", "num", k = "cd", sp = true },
    ["procGlow.speed"] = { "states", "procGlowSpeed", "num", k = "cd", sp = true },
    ["procGlow.lines"] = { "states", "procGlowLines", "int", k = "cd", sp = true },
    ["procGlow.thickness"] = { "states", "procGlowThickness", "int", k = "cd", sp = true },
    ["procGlow.particles"] = { "states", "procGlowParticles", "int", k = "cd", sp = true },
    ["procGlow.xOffset"] = { "states", "procGlowXOffset", "int", k = "cd", sp = true },
    ["procGlow.yOffset"] = { "states", "procGlowYOffset", "int", k = "cd", sp = true },
    ["procGlow.strata"] = { "states", "procGlowStrata", "strata", k = "cd", sp = true },
    ["procGlow.frameLevel"] = { "states", "procGlowLevel", "int", k = "cd", sp = true },
    -- border
    ["border.enabled"] = { "appearance", "borderEnabled", "bool" },
    ["border.color"] = { "appearance", "borderColor", "color" },
    ["border.thickness"] = { "appearance", "borderThickness", "int" },
    ["border.inset"] = { "appearance", "borderInset", "int" },
    ["border.useClassColor"] = { gap = "no class-coloured icon border" },
    ["border.followDesaturation"] = { gap = "the border never desaturates with the art" },
    ["border.texture"] = { gap = "icon borders are flat strips" },
    -- swipe (cooldown kinds) / aura swipe (aura icons)
    ["cooldownSwipe.showSwipe"] = { "swipe", "showSwipe", "bool", k = "cd", au = { "auraSwipe", "swipeShow", "bool" } },
    ["cooldownSwipe.showEdge"] = { "swipe", "showEdge", "bool", k = "cd", au = { "auraSwipe", "swipeEdge", "bool" } },
    ["cooldownSwipe.showBling"] = { "swipe", "showBling", "bool", k = "cd", au = { "auraSwipe", "swipeBling", "bool" } },
    ["cooldownSwipe.reverse"] = { "swipe", "reverse", "bool", k = "cd", au = { "auraSwipe", "swipeReverse", "bool" } },
    ["cooldownSwipe.swipeColor"] = { "swipe", "swipeColor", "color", k = "cd", au = { "auraSwipe", "swipeColor", "color" } },
    ["cooldownSwipe.edgeColor"] = { "swipe", "edgeColor", "color", k = "cd", au = { "auraSwipe", "edgeColor", "color" } },
    ["cooldownSwipe.edgeScale"] = { "swipe", "edgeScale", "num", k = "cd", au = { "auraSwipe", "edgeScale", "num" } },
    ["cooldownSwipe.noGCDSwipe"] = { "swipe", "gcdSwipe", "gcd", k = "cd", sp = true, gapau = "auras carry no GCD", nvau = true },
    ["cooldownSwipe.swipeWaitForNoCharges"] = { "swipe", "swipeWaitForNoCharges", "bool", k = "cd", sp = true },
    ["cooldownSwipe.edgeWaitForNoCharges"] = { "swipe", "edgeWaitForNoCharges", "bool", k = "cd", sp = true },
    ["cooldownSwipe.hideTextWithSwipe"] = { gap = "the duration text never hides with the swipe" },
    ["cooldownSwipe.swipeInset"] = { "swipe", "swipeInset", "int", k = "cd", gapau = "the aura button's swipe has no inset" },
    ["cooldownSwipe.separateInsets"] = { "swipe", "separateInsets", "bool", k = "cd", gapau = "the aura button's swipe has no inset" },
    ["cooldownSwipe.swipeInsetX"] = { "swipe", "swipeInsetX", "int", k = "cd", gapau = "the aura button's swipe has no inset" },
    ["cooldownSwipe.swipeInsetY"] = { "swipe", "swipeInsetY", "int", k = "cd", gapau = "the aura button's swipe has no inset" },
    ["cooldownSwipe.auraSwipeColor"] = { "auraSwipe", "overlaySwipeColor", "color", k = "cd", sp = true },
    ["cooldownSwipe.reverseWhileAura"] = { "auraSwipe", "overlaySwipeReverse", "bool", k = "cd", sp = true },
    ["cooldownSwipe.ignoreAuraOverride"] = { special = "iao", k = "cd", sp = true },
    ["cooldownSwipe.ignoreHardICD"] = { "states", "ignoreHardICD", "bool", k = "cd", sp = true },
    -- the aura on a cooldown icon (cooldown kinds) / the glow-when-missing suite (aura icons)
    ["auraActiveState.ignoreAuraOverride"] = { special = "iao", k = "cd", sp = true },
    ["auraActiveState.glow"] = { "auraActive", "activeGlow", "bool", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowType"] = { "auraActive", "activeGlowType", "auraglow", k = "cd", sp = true, gapau = "Arc Auras has no glow while an aura is missing" },
    ["auraActiveState.glowColor"] = { "auraActive", "activeGlowColor", "color", k = "cd", sp = true, gapau = "Arc Auras has no glow while an aura is missing" },
    ["auraActiveState.glowIntensity"] = { "auraActive", "activeGlowIntensity", "num", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowScale"] = { "auraActive", "activeGlowScale", "num", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowSpeed"] = { "auraActive", "activeGlowSpeed", "num", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowLines"] = { "auraActive", "activeGlowLines", "int", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowThickness"] = { "auraActive", "activeGlowThickness", "int", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowLength"] = { "auraActive", "activeGlowLength", "int", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowParticles"] = { "auraActive", "activeGlowParticles", "int", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowXOffset"] = { "auraActive", "activeGlowXOffset", "int", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowYOffset"] = { "auraActive", "activeGlowYOffset", "int", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowFrameStrata"] = { "auraActive", "activeGlowStrata", "strata", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowFrameLevel"] = { "auraActive", "activeGlowLevel", "int", k = "cd", sp = true, gapau = "no glow while the aura is missing" },
    ["auraActiveState.glowCombatOnly"] = { gap = "the aura-on-a-spell glow has no combat-only switch, and Arc Auras has no glow while an aura is missing" },
    ["auraActiveState.glowWhenMissing"] = { gap = "Arc Auras has no glow while an aura is missing" },
    ["auraActiveState.glowFollowPandemic"] = { special = "pandemic", k = "cd", sp = true },
    ["auraActiveState.desaturateWhenInactive"] = { "auraActive", "overlayDesatInactive", "bool", k = "cd", sp = true },
    ["auraActiveState.activeAlphaEnabled"] = { gap = "a switch Arc UI itself no longer reads", nv = true },
    ["auraActiveState.activeAlpha"] = { "auraActive", "activeAlpha", "num", k = "cd", sp = true },
    -- out of stock (bag items)
    ["outOfStockState.desaturate"] = { "outOfStock", "outDesaturate", "bool", k = "cd" },
    ["outOfStockState.alphaEnabled"] = { "outOfStock", "outAlphaEnabled", "bool", k = "cd" },
    ["outOfStockState.alpha"] = { "outOfStock", "outAlpha", "num", k = "cd" },
    ["outOfStockState.tint"] = { gap = "no tint while out of stock" },
    ["outOfStockState.tintColor"] = { gap = "no tint while out of stock" },
    -- charge / stack text
    ["chargeText.enabled"] = { "text", "stackText", "bool" },
    ["chargeText.size"] = { "text", "stackSize", "int" },
    ["chargeText.color"] = { "text", "stackColor", "color" },
    ["chargeText.font"] = { "text", "stackFont", "font" },
    ["chargeText.outline"] = { "text", "stackOutline", "outline" },
    ["chargeText.shadow"] = { "text", "stackShadow", "bool" },
    ["chargeText.anchor"] = { "text", "stackAnchor", "anchor7" },
    ["chargeText.position"] = { special = "stackPos" },
    ["chargeText.offsetX"] = { "text", "stackX", "int" },
    ["chargeText.offsetY"] = { "text", "stackY", "int" },
    ["chargeText.hideAtZero"] = { "text", "hideChargeAtZero", "bool", k = "cd", sp = true },
    ["chargeText.showSingleStack"] = { "text", "stackShowSingle", "bool", k = "au", gapcd = "a single charge always shows on cooldown icons" },
    ["chargeText.autoHide"] = { gap = "the stack text hides at 0 and 1 by the engine's own rule" },
    ["chargeText.mode"] = { gap = "texts anchor to the icon; no free text placement" },
    ["chargeText.freeX"] = { gap = "texts anchor to the icon; no free text placement" },
    ["chargeText.freeY"] = { gap = "texts anchor to the icon; no free text placement" },
    ["chargeText.shadowOffsetX"] = { gap = "the text shadow has one fixed offset" },
    ["chargeText.shadowOffsetY"] = { gap = "the text shadow has one fixed offset" },
    ["chargeText.shadowColor"] = { gap = "the text shadow is black" },
    ["chargeText.thresholdColorEnabled"] = { special = "stackBands", k = "au", gapcd = "count colour bands are an aura icon's; charges cannot be compared" },
    ["chargeText.thresholdBands"] = { special = "stackBands", k = "au", gapcd = "count colour bands are an aura icon's; charges cannot be compared" },
    -- cooldown / duration text
    ["cooldownText.enabled"] = { "text", "durationText", "bool" },
    ["cooldownText.size"] = { "text", "durationSize", "int" },
    ["cooldownText.color"] = { "text", "durationColor", "color" },
    ["cooldownText.font"] = { "text", "durationFont", "font" },
    ["cooldownText.outline"] = { "text", "durationOutline", "outline" },
    ["cooldownText.shadow"] = { "text", "durationShadow", "bool" },
    ["cooldownText.anchor"] = { "text", "durationAnchor", "anchor7" },
    ["cooldownText.offsetX"] = { "text", "durationX", "int" },
    ["cooldownText.offsetY"] = { "text", "durationY", "int" },
    ["cooldownText.decimals"] = { "text", "durationDecimals", "dec" },
    ["cooldownText.decimalThreshold"] = { special = "decThreshold" },
    ["cooldownText.abbrevThreshold"] = { "text", "durationAbbrev", "abbrev" },
    ["cooldownText.hideWhenHasCharges"] = { "text", "hideDurWithCharges", "bool", k = "cd", sp = true },
    ["cooldownText.durationColor"] = { special = "durBands" },
    ["cooldownText.durationColorCustom"] = { special = "durBands" },
    ["cooldownText.durationColorPreset"] = { special = "durBands" },
    ["cooldownText.durationColorCustomDefault"] = { special = "durBands" },
    ["cooldownText.durationColorUsePercent"] = { gap = "duration colour bands are in seconds" },
    ["cooldownText.mode"] = { gap = "texts anchor to the icon; no free text placement" },
    ["cooldownText.freeX"] = { gap = "texts anchor to the icon; no free text placement" },
    ["cooldownText.freeY"] = { gap = "texts anchor to the icon; no free text placement" },
    ["cooldownText.position"] = { gap = "texts anchor to the icon; no free text placement" },
    ["cooldownText.shadowOffsetX"] = { gap = "the text shadow has one fixed offset" },
    ["cooldownText.shadowOffsetY"] = { gap = "the text shadow has one fixed offset" },
    ["cooldownText.shadowColor"] = { gap = "the text shadow is black" },
    ["cooldownText.mmss"] = { gap = "minutes and seconds follow the abbreviation threshold" },
    ["cooldownText.minCountdownDuration"] = { gap = "the countdown's minimum is fixed" },
    ["cooldownText.showBelowSeconds"] = { gap = "the countdown has no show-below threshold" },
    -- keybind
    ["keybindText.enabled"] = { "keybind", "keybindEnabled", "bool", k = "cd", sp = true },
    hideKeybind = { special = "hideKeybind", k = "cd", sp = true },
    ["keybindText.size"] = { "keybind", "keybindSize", "int", k = "cd", sp = true },
    ["keybindText.color"] = { "keybind", "keybindColor", "color", k = "cd", sp = true },
    ["keybindText.font"] = { "keybind", "keybindFont", "font", k = "cd", sp = true },
    ["keybindText.anchor"] = { "keybind", "keybindAnchor", nil, k = "cd", sp = true },
    ["keybindText.offsetX"] = { "keybind", "keybindX", "int", k = "cd", sp = true },
    ["keybindText.offsetY"] = { "keybind", "keybindY", "int", k = "cd", sp = true },
    ["keybindText.outline"] = { gap = "the keybind text has one outline" },
    -- sounds
    ["cooldownAlerts.channel"] = { "alerts", "soundChannel", nil, k = "cd" },
    ["cooldownAlerts.readySoundOn"] = { "alerts", "readySoundEnabled", "bool", k = "cd" },
    ["cooldownAlerts.readySound"] = { "alerts", "readySound", nil, k = "cd" },
    ["cooldownAlerts.cooldownSoundOn"] = { "alerts", "cooldownSoundEnabled", "bool", k = "cd" },
    ["cooldownAlerts.cooldownSound"] = { "alerts", "cooldownSound", nil, k = "cd" },
    ["cooldownAlerts.rechargingSoundOn"] = { "alerts", "rechargeSoundEnabled", "bool", k = "cd", sp = true },
    ["cooldownAlerts.rechargingSound"] = { "alerts", "rechargeSound", nil, k = "cd", sp = true },
    ["cooldownAlerts.chargeSoundOn"] = { "alerts", "chargeGainedSoundEnabled", "bool", k = "cd", sp = true },
    ["cooldownAlerts.chargeSound"] = { "alerts", "chargeGainedSound", nil, k = "cd", sp = true },
    ["cooldownAlerts.readyTTS"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    ["cooldownAlerts.readyTTSOn"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    ["cooldownAlerts.cooldownTTS"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    ["cooldownAlerts.cooldownTTSOn"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    ["cooldownAlerts.rechargingTTS"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    ["cooldownAlerts.rechargingTTSOn"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    ["cooldownAlerts.chargeTTS"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    ["cooldownAlerts.chargeTTSOn"] = { gap = "icons speak no text; the Reminder group does", nv = true },
    -- whole v1 sections with no twin
    alertEvents = { gap = "the Cooldown Manager alert events are v1's own; Arc Auras alerts are sounds on shadow edges", nv = true },
    condition = { gap = "the per-icon condition rule has no Arc Auras twin", nv = true },
    auraAlerts = { gap = "aura icons have no sound alerts in Arc Auras", nv = true },
    durationOverride = { special = "durationOverride", k = "cd", sp = true },
    customLabel = { special = "labels" },
}

-- Custom labels: v1 keys with their suffix, mapped per label 1 to 3.
IA.LABEL_MAP = {
    text = { "labelText" }, size = { "labelSize", "int" }, color = { "labelColor", "color" },
    anchor = { "labelAnchor", "anchor7" }, xOffset = { "labelX", "int" }, yOffset = { "labelY", "int" },
    showInReadyState = { "labelShowReady", "bool", k = "cd" },
    showInCooldownState = { "labelShowCooldown", "bool", k = "cd" },
}

-- v1 group record fields -> the iconGroup schema.
IA.GROUP_MAP = {
    gridRows = { "arrangement", "rows", "int" },
    gridCols = { "arrangement", "cols", "int" },
    iconSize = { "arrangement", "iconSize", "int" },
    iconWidth = { "arrangement", "iconWidth", "int" },
    iconHeight = { "arrangement", "iconHeight", "int" },
    spacing = { "arrangement", "spacing", "int" },
    spacingX = { "arrangement", "spacingX", "int" },
    spacingY = { "arrangement", "spacingY", "int" },
    separateSpacing = { "arrangement", "separateSpacing", "bool" },
    alignment = { "arrangement", "alignment" },
    horizontalGrowth = { "arrangement", "growthH" },
    verticalGrowth = { "arrangement", "growthV" },
    lockGridSize = { "arrangement", "lockGridSize", "bool" },
    containerPadding = { special = "padding" },
    dynamicLayout = { "arrangement", "dynamicLayout", "bool" },
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
    ["display.gradientSecondColor"] = { "fill", "gradientColor", "color" },
    ["display.rotateTexture"] = { "fill", "rotateTexture", "bool" },
    ["display.showBackground"] = { "look", "bgShow", "bool" },
    ["display.backgroundColor"] = { "look", "bgColor", "color" },
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
    ["display.iconSize"] = { gap = "the icon display mode is not carried; the bar is" },
    ["display.iconShowTexture"] = { gap = "the icon display mode is not carried; the bar is" },
    ["display.iconShowStacks"] = { gap = "the icon display mode is not carried; the bar is" },
    ["display.iconShowDuration"] = { gap = "the icon display mode is not carried; the bar is" },
    ["display.iconShowBorder"] = { gap = "the icon display mode is not carried; the bar is" },
    ["display.iconShowCooldownSwipe"] = { gap = "the icon display mode is not carried; the bar is" },
    ["display.iconZoom"] = { gap = "the icon display mode is not carried; the bar is" },
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
    ["behavior.hideBuffIcon"] = { gap = "no Cooldown Manager icon to hide", nv = true },
    ["behavior.hideBlizzardFrame"] = { gap = "the game's own resource frame stays; Arc Auras hides only the cast bar's", nv = true },
    ["behavior.forceShow"] = { gap = "a preview switch, not a setting", nv = true },
    ["tracking"] = { special = "identity" },
    thresholds = { special = "layers" },
    colorRanges = { special = "layers" },
    stackColors = { special = "layers" },
    abilityThresholds = { special = "costTicks" },
    presets = { gap = "the v1 skin library is not carried", nv = true },
    prediction = { special = "predict" },
    autoPowerProfiles = { gap = "auto-power profiles are not carried; the bar follows the power in use", nv = true },
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
    ["display.durationColorCurveEnabled"] = { special = "durCurve" },
    ["display.durationColorCurveMode"] = { special = "durCurve" },
    ["display.durationColorCurveThreshold"] = { special = "durCurve" },
    ["display.durationColorCurveLowColor"] = { special = "durCurve" },
    ["display.durationColorCurveHighColor"] = { special = "durCurve" },
    ["display.durationColorCurveMidColor"] = { gap = "the curve's middle colour: Arc Auras colours in steps, not a gradient" },
    ["display.colorCurveEnabled"] = { special = "layers" },
    ["display.colorCurveDirection"] = { special = "layers" },
    ["display.colorCurveDirectionFilling"] = { special = "layers" },
    ["display.colorCurveThreshold2Enabled"] = { special = "layers" },
    ["display.colorCurveThreshold2Value"] = { special = "layers" },
    ["display.colorCurveThresholdAsPercent"] = { special = "layers" },
    ["display.colorCurveMaxValue"] = { special = "layers" },
    ["display.enableMaxColor"] = { special = "maxColor" },
    ["display.maxColor"] = { special = "maxColor" },
    ["display.fragmentedSpacing"] = { "resource", "pipSpacing", "int" },
    ["display.fragmentedColors"] = { special = "pipColors" },
    ["display.fragmentedChargingColor"] = { gap = "pips have one empty tint in Arc Auras, not a recharging colour" },
    ["display.fragmentedLayoutDirection"] = { gap = "pips run along the bar" },
    ["display.fragmentedFillOrientation"] = { gap = "pips fill along the bar" },
    ["display.fragmentedShowSegmentText"] = { gap = "pips carry no text of their own" },
    ["display.fragmentedTextSize"] = { gap = "pips carry no text of their own" },
    ["display.segmentedSpacing"] = { "segments", "segmentSpacing", "int" },
    ["display.iconBarSpacing"] = { "icon", "iconSpacing", "int" },
    ["display.stackShowAtZero"] = { "text", "stkHideAtZero", "not" },
    ["display.showZeroWhenReady"] = { "text", "stkHideAtZero", "not" },
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
    ["display.frameWidth"] = { gap = "the charge bar's outer frame follows its width" },
    ["display.frameHeight"] = { gap = "the charge bar's outer frame follows its height" },
    ["display.durationThreshold5Enabled"] = { gap = "three duration thresholds at most in Arc Auras; the fourth is dropped" },
    ["display.durationThreshold5Value"] = { gap = "three duration thresholds at most in Arc Auras; the fourth is dropped" },
    ["display.durationThreshold5Color"] = { gap = "three duration thresholds at most in Arc Auras; the fourth is dropped" },
    ["display.dynamicTextOnSlot"] = { gap = "the charge text sits on the bar, not on the active segment" },
    ["display.slotHeight"] = { gap = "charge segments share the bar's height" },
    ["display.slotOffsetX"] = { gap = "charge segments sit on the bar" },
    ["display.showSlotBorder"] = { gap = "charge segments share the bar's border" },
    ["display.matchSlotsOnly"] = { gap = "a matched width spans the group's container" },
    ["display.matchIconEdges"] = { gap = "a matched width spans the group's container" },
    ["display.gradientIntensity"] = { gap = "the gradient runs to its end colour" },
    ["display.mirrorStaticTexture"] = { gap = "the bar texture is not mirrored" },
    ["display.nameTextStrata"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.stackTextStrata"] = { gap = "texts sit on the bar's own level", nv = true },
    ["display.tickTrackSegments"] = { gap = "ticks follow the tick mode" },
    ["display.tickThicknessAnchor"] = { "ticks", "tickThicknessAnchor" },
    ["display.fillTextureScale"] = { gap = "the fill texture is not scaled" },
    ["display.borderStyle"] = { gap = "one drawn border style" },
    ["display.durationShowWhenReady"] = { gap = "a duration bar hides its time when ready; Ready text is its own switch" },
    ["display.smartChargingColor"] = { gap = "a setting Arc UI itself retired", nv = true },
    ["display.activeCountColors"] = { gap = "a setting Arc UI itself retired", nv = true },
    ["display.enableActiveCountColors"] = { gap = "a setting Arc UI itself retired", nv = true },
    ["display.foldedColor1"] = { special = "fold" },
    ["display.foldedColor2"] = { special = "fold" },
    ["display.iconMultiPositions"] = { gap = "the multi-icon display mode is not carried; the bar is", nv = true },
    ["display.iconsPositions"] = { gap = "the icons display mode is not carried; the bar is", nv = true },
    ["display.iconsSpacing"] = { gap = "the icons display mode is not carried; the bar is" },
    ["display.iconsMode"] = { gap = "the icons display mode is not carried; the bar is" },
    ["display.iconsSize"] = { gap = "the icons display mode is not carried; the bar is" },
    ["display.iconsShape"] = { gap = "the icons display mode is not carried; the bar is" },
    ["display.iconsShowCooldownText"] = { gap = "the icons display mode is not carried; the bar is" },
    ["display.iconsCooldownTextSize"] = { gap = "the icons display mode is not carried; the bar is" },
    ["display.displayType"] = { gap = "the icon display mode is not carried; the bar is", nv = true },
    ["display.displayMode"] = { gap = "the single / multi display mode is the bar's", nv = true },
}

-- The specials of the bar matrix as coverage targets (what MapBarLook does with them).
IA.BAR_SPECIALS = {
    orientation = "fill.orientation", tickMode = "ticks.tickMode", style = "resource.style = pips",
    position = "the bar's pos", anchor = "anchor.* (a group by name, width matched)", thresholds = "thresholds.thresh2..4 + threshEnabled / Count / AsSeconds / Ref",
    hideWhen = "c.fadeWhen + c.fadeAlpha", specs = "c.specs", talents = "c.talents / talentsNot", identity = "the record itself",
    freeText = "text.stkAnchor / resAnchor / durAnchor = CENTER + offsets from the bar (a free-dragged text)",
    chargeText = "text.stkAnchor / stkOffsetX / stkOffsetY (when the text anchor keys are unset)",
    font = "text.font (the stack text's font, else the duration's, else the name's)",
    durCurve = "thresholds.thresh2 at the curve's threshold with its low colour; fill.color = the high colour",
    layers = "resource: powerthresholds.pth2..5 / pthEnabled / Count / Direction / Absolute; aura stack: stackcolors.sc2..4 / scEnabled / Count (+ scPosition per stack); charge: segments.fullColor",
    fold = "resource.foldOn + foldColor (the second lap), fill.color (the first)",
    maxColor = "stackcolors.maxColor / powerthresholds.pthFullColor / segments.fullColor (by bar kind)",
    pipColors = "stackcolors.sc2..4 + scPosition (each pip its own colour)",
    padding = "fill.fillInset (the largest side)", costTicks = "ticks.tickSpells + ticksShow", predict = "predict.predictEnabled",
    textThresh = "ptextcolors.ptx2..5 / ptxEnabled / Count / Direction / BaseColor (the texts' own bands)",
}

-- A cast bar record (v1's flat castbar table) -> the cast bar schema.
IA.CAST_MAP = {
    width = { "size", "width", "int" }, height = { "size", "height", "int" },
    opacity = { "size", "opacity", "num" }, barColor = { "fill", "color", "color" },
    texture = { "fill", "texture" }, reverseFill = { "fill", "reverseFill", "bool" },
    showBackground = { "look", "bgShow", "bool" }, backgroundColor = { "look", "bgColor", "color" },
    showBorder = { "look", "borderEnabled", "bool" }, borderColor = { "look", "borderColor", "color" },
    drawnBorderThickness = { "look", "borderThickness", "int" },
    showIcon = { "icon", "iconShow", "bool" }, iconSize = { "icon", "iconSize", "int" },
    showText = { "text", "nameShow", "bool" }, showSpellName = { "text", "nameShow", "bool" },
    showTimer = { "text", "durShow", "bool" }, font = { "text", "font", "font" },
    fontSize = { "text", "nameSize", "int" }, textColor = { "text", "nameColor", "color" },
    textOutline = { "text", "nameOutline", "outline" },
    barFrameStrata = { "frame", "strata" }, barFrameLevel = { "frame", "level", "int" },
    barPosition = { special = "position" }, hideChannels = { "cast", "hideChannels", "bool" },
    hideCastBar = { "cast", "hideBlizzard", "bool" }, latencyEnabled = { "cast", "latencyOn", "bool" },
    latencyColor = { "cast", "latencyColor", "color" },
    interruptFeedbackEnabled = { "cast", "holdOn", "bool" },
    interruptColor = { "cast", "holdIntColor", "color" },
    interruptFadeDuration = { "cast", "fadeOut", "num" },
    uninterruptibleEnabled = { "fill", "castLockOn", "bool" },
    uninterruptibleColor = { "fill", "castLockColor", "color" },
    hideNotInterruptible = { "cast", "lockHide", "bool" },
    tickMarksEnabled = { "ticks", "ticksShow", "bool" }, tickPercent = { "ticks", "tickPercent", "int" },
    tickCustom = { "ticks", "tickValues" }, tickMarksColor = { "ticks", "tickColor", "color" },
    tickMarksThickness = { "ticks", "tickThickness", "int" },
    tickShowOn = { special = "tickShowOn" }, tickMode = { special = "tickModeCast" },
    profiles = { special = "castProfiles" }, enabled = { special = "identity" },
    castType = { special = "castType" },
    anchorToGroup = { special = "anchor" }, anchorGroupName = { special = "anchor" },
    anchorPoint = { special = "anchor" }, anchorOffsetX = { special = "anchor" },
    anchorOffsetY = { special = "anchor" }, matchGroupWidth = { special = "anchor" },
    matchWidthAdjust = { special = "anchor" },
    empowerSegmentColorsEnabled = { gap = "empowered casts draw as plain casts" },
    empowerSegmentColors = { gap = "empowered casts draw as plain casts" },
    empowerStageDividers = { gap = "empowered casts draw as plain casts" },
    empowerDividerPerColor = { gap = "empowered casts draw as plain casts" },
    empowerMaxStages = { gap = "empowered casts draw as plain casts" },
    spellOverrides = { gap = "per-spell cast bar looks are not carried" },
    conditionalColorEnabled = { gap = "cast bar threshold colours are not carried" },
    conditionalColorAsSec = { gap = "cast bar threshold colours are not carried" },
    colorThresholds = { gap = "cast bar threshold colours are not carried" },
    autoShareCategories = { gap = "the v1 cast type profiles are folded into one look" },
    presets = { gap = "the v1 skin library is not carried" },
    timerFormat = { gap = "the cast bar's time is the remaining time" },
    spellShortenEnabled = { gap = "spell names are never shortened" },
    spellShortenLength = { gap = "spell names are never shortened" },
    iconMovable = { gap = "the cast bar's icon sits on its side" },
    iconPosition = { gap = "the cast bar's icon sits on its side" },
    latencyManual = { gap = "the latency zone reads the world latency" },
    latencyManualMs = { gap = "the latency zone reads the world latency" },
    barMovable = { special = "identity" }, barAnchorPoint = { special = "identity" },
    tickMarksDefaultCount = { gap = "tick counts come from the channel" },
    tickMarksHeightFraction = { gap = "cast ticks span the bar" },
    tickHeightAnchor = { gap = "cast ticks span the bar" },
    tickThicknessAnchor = { gap = "cast ticks span the bar" },
    uninterruptibleBorderColor = { gap = "no border colour for locked casts" },
    hideOutOfCombat = { special = "hideWhen" },
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
    return { mapped = {}, dropped = {}, ingame = {} }
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

-- The icon matrix's route: kind family "cd" or "au", and whether the icon is a spell.
function IA.IconRoute(kind)
    local fam = (kind == "aura") and "au" or "cd"
    local isSpell = kind == "spell"
    -- the third value marks a key that did nothing on this kind in v1 either (a
    -- cooldown setting saved on an aura icon), so it is no visual loss
    return function(row, path)
        if row.gap then return nil, row.gap end
        if fam == "au" then
            if row.au then return row.au[1] .. "." .. row.au[2] end
            if row.auspecial then return "(" .. row.auspecial .. ")" end
            if row.gapau then return nil, row.gapau, row.nvau end
            if row.k == "cd" then return nil, "a cooldown-icon setting; aura icons have no twin (it did nothing on them in Arc UI either)", true end
        else
            if row.gapcd then return nil, row.gapcd, row.nvcd end
            if row.k == "au" then return nil, "an aura-icon setting; cooldown icons have no twin (it did nothing on them in Arc UI either)", true end
            if row.sp and not isSpell then return nil, "spell icons only: items, trinkets and totems have no aura phase or charges" end
        end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
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

-- v1's colour bands for a duration text: the enabled ones by threshold, three at most.
local function DurationBands(o, list)
    local bands = {}
    for _, b in ipairs(list) do
        if type(b) == "table" and b.enabled ~= false and tonumber(b.threshold) and Color(b.color) then
            bands[#bands + 1] = { sec = tonumber(b.threshold), color = Color(b.color) }
        end
    end
    table.sort(bands, function(a, b) return a.sec < b.sec end)
    for i = 1, 3 do
        local b = bands[i]
        Put(o, "text", "durBand" .. i .. "Sec", b and math.floor(b.sec + 0.5) or 0)
        if b then Put(o, "text", "durBand" .. i .. "Color", b.color) end
    end
    -- the bands in play: one shows by default now
    if #bands > 0 then Put(o, "text", "durBandCount", math.min(3, #bands)) end
    return #bands
end

-- v1's stack count bands on aura icons: the enabled ones, three at most.
local function StackBands(o, list)
    local bands = {}
    for _, b in ipairs(list) do
        if type(b) == "table" and b.enabled ~= false and tonumber(b.threshold) and Color(b.color) then
            bands[#bands + 1] = { min = tonumber(b.threshold), color = Color(b.color) }
        end
    end
    table.sort(bands, function(a, b) return a.min < b.min end)
    for i = 1, 3 do
        local b = bands[i]
        if b then
            Put(o, "text", "stkBand" .. i .. "Min", math.max(1, math.floor(b.min + 0.5)))
            Put(o, "text", "stkBand" .. i .. "Color", b.color)
        end
    end
    if #bands > 0 then Put(o, "text", "stkBandCount", math.min(3, #bands)) end
    return #bands
end

-- The v1 icon's effective settings -> an Arc Auras override table for `kind`.
-- `flags` says what the record is: cdm (a Cooldown Manager icon) for the shadow rule.
function IA.MapIcon(eff, kind, flags)
    local o = {}
    local fam = (kind == "aura") and "au" or "cd"
    local isSpell = kind == "spell"
    for path, row in pairs(IA.ICON_MAP) do
        if not row.gap and not row.special then
            local skip = (fam == "au" and (row.gapau or row.k == "cd") and not row.au)
                or (fam == "cd" and (row.gapcd or row.k == "au" or (row.sp and not isSpell)))
            if fam == "au" and row.k == "au" then skip = false end
            if not skip then IA.MapRow(o, row, Leaf(eff, path), fam) end
        end
    end
    -- v1's one usability switch served both usability tints
    if o.states and o.states.unusableTintEnabled ~= nil then
        Put(o, "states", "resourceTintEnabled", o.states.unusableTintEnabled)
    end
    -- v1 greyed a ready icon from its ready state or its usability look:
    -- either one greys it
    local su = eff.spellUsability
    if fam == "cd" and type(su) == "table" and su.normalDesaturate == true then
        Put(o, "states", "readyDesaturate", true)
    end
    -- shadow: a Cooldown Manager icon wears the game's shadow unless v1 hid it
    if flags and flags.cdm then
        Put(o, "appearance", "shadowEnabled", eff.hideShadow ~= true)
    elseif eff.shadowSize ~= nil and eff.hideShadow ~= true then
        Put(o, "appearance", "shadowEnabled", true)
    end
    -- custom art: 0 is v1's transparent icon
    local cid = tonumber(eff.customIconID)
    if cid == 0 then
        Put(o, "appearance", "forceHideIcon", true)
    elseif cid and cid > 0 then
        Put(o, "appearance", "customIcon", cid)
        Put(o, "appearance", "customIconFrom", (flags and flags.iconFrom) or "icon")
    end
    -- the on-cooldown desaturation: v1 adds it or blocks the game's; auras read it as the missing look
    local cs = eff.cooldownStateVisuals and eff.cooldownStateVisuals.cooldownState
    if cs then
        if fam == "au" then
            if cs.desaturate ~= nil or cs.noDesaturate ~= nil then
                Put(o, "auraMissing", "missingDesaturate", cs.desaturate == true and cs.noDesaturate ~= true)
            end
        elseif cs.noDesaturate ~= nil or cs.desaturate ~= nil then
            Put(o, "states", "cooldownDesaturate", cs.noDesaturate ~= true)
        end
        if cs.dimWhenEmpty == true and (kind == "item" or kind == "trinket") then
            Put(o, "outOfStock", "outAlphaEnabled", true)
            Put(o, "outOfStock", "outAlpha", tonumber(cs.alpha) or 0.4)
        end
    end
    -- a free text place on the icon: v1's freeX / freeY become the icon's own offsets
    local pos = eff.position
    if type(pos) == "table" and pos.mode == "free" then
        Put(o, "position", "offsetX", tonumber(pos.freeX) or 0)
        Put(o, "position", "offsetY", tonumber(pos.freeY) or 0)
    end
    -- the stack text's anchor was saved under two names
    local ct = eff.chargeText
    if type(ct) == "table" then
        if ct.anchor == nil and IA.TEXT_ANCHORS[ct.position] then
            Put(o, "text", "stackAnchor", ct.position)
        end
        if fam == "au" and ct.thresholdColorEnabled == true and type(ct.thresholdBands) == "table" then
            if StackBands(o, ct.thresholdBands) > 0 then Put(o, "text", "stackColorBands", true) end
        end
    end
    local cd = eff.cooldownText
    if type(cd) == "table" then
        if cd.durationColor == true and (cd.durationColorPreset == nil or cd.durationColorPreset == "custom")
            and type(cd.durationColorCustom) == "table" then
            if DurationBands(o, cd.durationColorCustom) > 0 then
                Put(o, "text", "durationColorBands", true)
                -- v1's colour above the top band is the plain text colour here
                local top = Color(cd.durationColorCustomDefault)
                if top then Put(o, "text", "durationColor", top) end
            end
        end
        local dt = tonumber(cd.decimalThreshold)
        if dt and dt > 0 then Put(o, "text", "durationDecimalThreshold", math.max(2, math.min(60, math.floor(dt + 0.5)))) end
    end
    if isSpell and eff.hideKeybind == true then Put(o, "keybind", "keybindEnabled", false) end
    -- an aura icon's Keep Bright kept the missing look bright: no desaturation while missing
    if fam == "au" and eff.keepBright == true then Put(o, "auraMissing", "missingDesaturate", false) end
    -- the active glow's timing: v1's threshold (a fraction of the aura, or seconds) is
    -- Glow when: time left; the ready glow while charges remain is Wait for no charges
    local rs = eff.cooldownStateVisuals and eff.cooldownStateVisuals.readyState
    if type(rs) == "table" and (fam == "au" or isSpell) then
        local sec, pct = tonumber(rs.glowThresholdSeconds), tonumber(rs.glowThreshold)
        if sec and sec > 0 then
            Put(o, "auraActive", "activeGlowWhen", "time")
            Put(o, "auraActive", "activeGlowTimeUnit", "sec")
            Put(o, "auraActive", "activeGlowTimeSec", sec)
        elseif pct and pct > 0 and pct < 1 then
            Put(o, "auraActive", "activeGlowWhen", "time")
            Put(o, "auraActive", "activeGlowTimeUnit", "pct")
            Put(o, "auraActive", "activeGlowTimePct", math.floor(pct * 100 + 0.5))
        end
        if isSpell and rs.glowWhileChargesAvailable == true then Put(o, "states", "waitForNoCharges", true) end
    end
    -- v1's "glow follows the pandemic window" is the last 30 percent here
    local aa = eff.auraActiveState
    if isSpell and type(aa) == "table" and aa.glowFollowPandemic == true then
        Put(o, "auraActive", "activeGlowWhen", "time")
        Put(o, "auraActive", "activeGlowTimeUnit", "pct")
        Put(o, "auraActive", "activeGlowTimePct", 30)
    end
    -- custom labels: three suites; an aura label's state pair becomes "only while up / missing"
    local cl = eff.customLabel
    if type(cl) == "table" then
        for i = 1, 3 do
            local suf = (i == 1) and "" or tostring(i)
            for v1key, row in pairs(IA.LABEL_MAP) do
                local v = cl[v1key .. suf]
                if v ~= nil and not (row.k == "cd" and fam == "au") then
                    local out = v
                    if row[2] then out = IA.CONV[row[2]](v) end
                    if out ~= nil then Put(o, "label", row[1] .. suf, out) end
                end
            end
            if fam == "au" then
                local up, down = cl["showWhenActive" .. suf], cl["showWhenInactive" .. suf]
                if up == true and down == false then Put(o, "label", "labelActiveOnly" .. suf, true) end
                if down == true and up == false then Put(o, "label", "labelMissingOnly" .. suf, true) end
            end
        end
        if cl.font ~= nil then Put(o, "label", "labelFont", IA.CONV.font(cl.font)) end
    end
    -- v1 clamps that differ from the schema's: the ranges are the schema's job at Apply
    return o
end

-- The specials of the icon matrix as coverage targets (what MapIcon does with them).
IA.ICON_SPECIALS = {
    shadow = "appearance.shadowEnabled", customIcon = "appearance.customIcon (+customIconFrom)",
    freepos = "position.offsetX / offsetY (free mode only)", desat = "states.cooldownDesaturate / auraMissing.missingDesaturate",
    dimEmpty = "outOfStock.outAlphaEnabled + outAlpha", iao = "the aura overlay stays off",
    pandemic = "auraActive.activeGlowWhen = time, 30 percent", stackPos = "text.stackAnchor",
    stackBands = "text.stackColorBands + stkBand1..3 (aura icons)", decThreshold = "text.durationDecimalThreshold",
    durBands = "text.durationColorBands + durBand1..3 (custom preset only)", hideKeybind = "keybind.keybindEnabled = false",
    durationOverride = "driver.overlay (enabled + an aura spell id); the manual and totem modes are dropped",
    labels = "label.labelText / Size / Color / Anchor / X / Y / ShowReady / ShowCooldown / ActiveOnly / MissingOnly 1..3 + labelFont",
    glowTime = "auraActive.activeGlowWhen = time + activeGlowTimeUnit / TimePct / TimeSec",
    glowCharges = "states.waitForNoCharges = true, folded at the end into Recharging's own look and glow (Store.KeepRechargeLook)",
    keepBrightAura = "auraMissing.missingDesaturate = false",
    readyDesat = "states.readyDesaturate = true (on with the ready state's own grey out)",
}

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

-- v1's hide keys (a table, or the oldest strings) -> c.fadeWhen
function IA.HideWhen(c, vis, logic, alpha)
    local any = false
    if type(vis) == "table" then
        for k, on in pairs(vis) do
            local key = IA.HIDE_WHEN[k]
            if on == true and key then
                c.fadeWhen = c.fadeWhen or {}
                c.fadeWhen[key] = true
                any = true
            end
        end
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
    if type(a.anchoredFrames) == "table" and #a.anchoredFrames > 0 then
        Dropped(cov, "group:anchor.anchoredFrames", "other addons' frames anchored to a group have no Arc Auras twin", true)
    end
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

-- A v1 group record -> a plan group (no icons yet).
function IA.MapGroup(name, gl, cov)
    local eff = IA.Merge(IA.V1_GROUP_DEFAULTS, gl)
    local o, c = {}, {}
    for path, row in pairs(IA.GROUP_MAP) do
        if not row.gap and not row.special then IA.MapRow(o, row, Leaf(eff, path)) end
    end
    -- v1 stores its padding four under what it shows
    Put(o, "arrangement", "containerPadding", math.max(-6, math.min(12, (tonumber(eff.containerPadding) or -4) + 4)))
    -- the dynamic family only ran while auto reflow was on
    if eff.autoReflow == false then
        o.arrangement.dynamicLayout = nil
    elseif eff.dynamicCooldowns == true then
        Put(o, "arrangement", "dynamicCollapse", "ready")
    end
    IA.HideWhen(c, eff.visibility, eff.visibilityLogic, eff.hiddenAlpha)
    local pos = type(eff.position) == "table" and eff.position or {}
    local g = {
        name = name, kind = (eff.groupType == "aura") and "aura" or "cooldown",
        pos = { x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0 },
        o = o, c = c, anchor = IA.GroupAnchor(eff.anchor, cov), icons = {},
    }
    IA.Cover(cov, gl, IA.GROUP_MAP, function(row, path)
        if row.gap then return nil, row.gap end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end, nil, "group")
    return g
end

IA.GROUP_SPECIALS = {
    padding = "arrangement.containerPadding (+4)", collapse = "arrangement.dynamicCollapse = ready",
    reflow = "gates the dynamic family, as in v1", visibility = "c.fadeWhen / c.fadeAlpha (all-match reads as any)",
    anchor = "o.anchor (group / frame / mouse); anchoredFrames dropped", position = "pos",
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
        return { kind = "trinket", driver = { slotID = tonumber(info.equipSlot) }, name = "Trinket " .. (tonumber(info.equipSlot) == 14 and 2 or 1) }
    end
    if cat == 2 or cat == 3 or cat == 4 or cat == 6 or cat == 8 then
        if not sid or sid == 0 then return nil, "an aura icon with no spell id (an equipment buff)" end
        local self = info.selfAura ~= false
        local d = { spellID = sid, auraType = self and "buff" or "debuff", unit = self and "player" or "target", caster = "mine" }
        local linked = type(info.linkedSpellIDs) == "table" and info.linkedSpellIDs or nil
        if linked and #linked > 0 then
            d.spellIDs = { sid }
            for _, x in ipairs(linked) do if tonumber(x) and x ~= sid then d.spellIDs[#d.spellIDs + 1] = tonumber(x) end end
            if #d.spellIDs == 1 then d.spellIDs = nil end
        end
        return { kind = "aura", driver = d, name = (opts.spellName and opts.spellName(sid)) or ("Aura " .. sid) }
    end
    if not sid or sid == 0 then return nil, "a cooldown with no spell id" end
    local d = { spellID = sid }
    -- the Cooldown Manager's aura phase on a cooldown becomes the aura on this icon
    if info.hasAura == true and not iao then
        local harmful = opts.spellHarmful and opts.spellHarmful(sid) == true
        d.overlay = { on = true, spellID = sid, auraType = harmful and "debuff" or "buff",
            unit = harmful and "target" or "player", caster = "mine" }
    end
    return { kind = "spell", driver = d, name = (opts.spellName and opts.spellName(sid)) or ("Spell " .. sid) }
end

-- An Arc Auras v1 id -> its kind, driver and name from the character's v1 store.
function IA.ResolveArc(arcID, arcDB, specKey, classID, cov, opts)
    local kind, id, copy = IA.ParseArc(arcID)
    if not kind then return nil, "an unreadable Arc Auras id" end
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
            if arcDB.onlyOnUseTrinkets == true then Put(o, "trinket", "onlyOnUse", true) end
            return { kind = "trinket", driver = { slotID = slot }, name = "Trinket " .. (slot == 14 and 2 or 1), o = o, c = c }
        end
        local itemID = tonumber(def.itemID) or id
        if not itemID then return nil, "an item icon with no item id" end
        return { kind = "item", driver = { itemID = itemID }, o = o, c = c,
            name = (opts.itemName and opts.itemName(itemID)) or ("Item " .. itemID) }
    elseif kind == "spell" then
        local def = arcDB and arcDB.trackedSpells and arcDB.trackedSpells[arcID]
        local sid = (type(def) == "table" and tonumber(def.spellID)) or id
        if not sid then return nil, "a spell icon with no spell id" end
        Who(def)
        return { kind = "spell", driver = { spellID = sid }, o = {}, c = c,
            name = (type(def) == "table" and def.name) or (opts.spellName and opts.spellName(sid)) or ("Spell " .. sid) }
    elseif kind == "aura" then
        local def = arcDB and arcDB.auraIcons and arcDB.auraIcons[arcID]
        local sid = (type(def) == "table" and tonumber(def.spellID)) or id
        if not sid then return nil, "an aura icon with no spell id" end
        Who(def)
        local d = { spellID = sid, auraType = (type(def) == "table" and def.auraType == "debuff") and "debuff" or "buff" }
        local units = type(def) == "table" and def.units
        d.unit = (d.auraType == "debuff") and "target" or "player"
        if type(units) == "table" then
            local first
            for _, u in ipairs(IA.AURA_UNITS) do
                if units[u] == true then
                    if not first then first = u
                    else Dropped(cov, "icon:auraIcons.units." .. u, "an aura icon tracks one unit; the first stays") end
                end
            end
            if first then d.unit = first end
        end
        if type(def) == "table" and def.ownOnly == true then d.caster = "mine" end
        if type(def) == "table" and type(def.spellIDs) == "table" then
            local list = { sid }
            for x, on in pairs(def.spellIDs) do
                if on and tonumber(x) and tonumber(x) ~= sid then list[#list + 1] = tonumber(x) end
            end
            if #list > 1 then table.sort(list, function(a, b) return a == sid or (b ~= sid and a < b) end) d.spellIDs = list end
        end
        return { kind = "aura", driver = d, o = {}, c = c,
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
        return nil, "custom timers: Arc Auras has no timer engine yet"
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

-- Plans one profile of one spec: a layout with its groups, icons and free icons.
function IA.PlanProfile(ctx, profileName, profile, specData, plan)
    local cov, opts = ctx.cov, ctx.opts
    local pkey = ctx.charKey .. "|" .. ctx.specKey .. "|" .. tostring(profileName)
    local L = { name = ctx.charName .. " " .. ctx.specName, c = {}, pos = { x = 0, y = 0 }, o = {},
        groups = {}, icons = {}, bars = {}, reminders = {}, profile = profileName,
        key = "layout:" .. pkey, freeUnit = "free:" .. pkey, charKey = ctx.charKey, specID = ctx.specID }
    local active = (specData.activeProfile or "Default") == profileName
    if not active then L.name = L.name .. " (" .. tostring(profileName) .. ")" end
    L.c.chars = { [ctx.charKey] = true }
    if ctx.classTag then L.c.classes = { [ctx.classTag] = true } end
    if ctx.specID then L.c.specs = { [ctx.specID] = true } else Need(cov, "spec ids (GetSpecializationInfoForClassID)") end
    local conditioned = type(profile.talentConditions) == "table" and #profile.talentConditions > 0
    if conditioned then
        IA.Talents(L.c, profile.talentConditions, profile.matchMode)
    elseif not active then
        -- a spare profile: kept, but it never draws until the player switches it on
        L.c.loadNever = { always = true }
        L.dormant = true
    end
    L.active, L.conditioned = active, conditioned
    -- the groups: the profile's own, or the account-wide set it links to
    local groups = profile.groupLayouts
    local linkName = (type(profile.groupLayoutName) == "string" and profile.groupLayoutName ~= "") and profile.groupLayoutName or nil
    if linkName then
        local shared = ctx.db.global and ctx.db.global.groupLayouts and ctx.db.global.groupLayouts[linkName]
        if type(shared) == "table" then
            groups = shared
        else
            Dropped(cov, "group:profile.groupLayoutName", "the linked account-wide group set is missing", true)
            linkName = nil
        end
    end
    -- an active, unconditioned profile on an account-wide set feeds the one layout
    -- that set becomes (its icons kept apart, gated to this character and spec); a
    -- spare or talent profile on one keeps its own copy, dormant or gated as usual
    local G
    if linkName and active and not conditioned then
        G = plan.globals[linkName]
        if not G then
            G = { kind = "global", key = "glayout:" .. linkName, name = linkName, c = { chars = {}, classes = {}, specs = {} },
                pos = { x = 0, y = 0 }, o = {}, groups = {}, icons = {}, bars = {}, reminders = {}, contributions = {} }
            for gname, gl in pairs(groups) do
                if type(gl) == "table" and type(gname) == "string" then G.groups[#G.groups + 1] = IA.MapGroup(gname, gl, cov) end
            end
            table.sort(G.groups, function(a, b) return a.name < b.name end)
            plan.globals[linkName] = G
            plan.globalList[#plan.globalList + 1] = G
            ctx.counts.groups = ctx.counts.groups + #G.groups
            ctx.counts.globalLayouts = ctx.counts.globalLayouts + 1
        end
        L.linked = linkName
    end
    local byName = {}
    if G then
        local contrib = { charKey = ctx.charKey, classTag = ctx.classTag, specID = ctx.specID, specKey = ctx.specKey,
            profile = profileName, groups = {} }
        for _, g in ipairs(G.groups) do
            local part = { name = g.name, icons = {}, unit = "ggroup:" .. pkey .. "|" .. g.name }
            byName[g.name] = part
            contrib.groups[#contrib.groups + 1] = part
        end
        G.contributions[#G.contributions + 1] = contrib
        G.c.chars[ctx.charKey] = true
        if ctx.classTag then G.c.classes[ctx.classTag] = true end
        if ctx.specID then G.c.specs[ctx.specID] = true end
        L.contribution = contrib
    else
        for gname, gl in pairs(type(groups) == "table" and groups or {}) do
            if type(gl) == "table" and type(gname) == "string" then
                local g = IA.MapGroup(gname, gl, cov)
                g.unit = "group:" .. pkey .. "|" .. gname
                byName[gname] = g
                L.groups[#L.groups + 1] = g
            end
        end
        table.sort(L.groups, function(a, b) return a.name < b.name end)
        ctx.counts.groups = ctx.counts.groups + #L.groups
    end
    -- the icons: every placed id, its look from the profile's per-icon settings
    local settings = type(profile.iconSettings) == "table" and profile.iconSettings or {}
    local placed = {}
    local function Icon(key, place)
        local kk, id = IA.KeyKind(key)
        if not kk then Dropped(cov, "icon:placement.unreadable", "an icon placed under a key that names nothing", true) return end
        local skey = tostring(key)
        if placed[skey] then return end
        placed[skey] = true
        local res, why
        local raw = settings[skey]
        local iao = type(raw) == "table" and ((raw.auraActiveState and raw.auraActiveState.ignoreAuraOverride == true)
            or (raw.cooldownSwipe and raw.cooldownSwipe.ignoreAuraOverride == true))
        if kk == "cdm" then
            res, why = IA.ResolveCDM(id, iao, opts)
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
        local family = (res.kind == "aura") and "aura" or "cooldown"
        local eff = IA.Merge(IA.V1_ICON_DEFAULTS, ctx.globals[family], raw)
        local flags = { cdm = (kk == "cdm") }
        if flags.cdm and eff.customIconID and tonumber(eff.customIconID) and tonumber(eff.customIconID) > 0 then
            if opts.spellTexture then
                flags.iconFrom = opts.spellTexture(tonumber(eff.customIconID)) and "spell" or "icon"
            else
                Need(cov, "custom icon ids (spell or file id)")
            end
        end
        local o = IA.MapIcon(eff, res.kind, flags)
        for sec, fields in pairs(res.o or {}) do for f, v in pairs(fields) do Put(o, sec, f, v) end end
        if type(raw) == "table" then IA.Cover(cov, raw, IA.ICON_MAP, IA.IconRoute(res.kind), nil, "icon") end
        local I = { kind = res.kind, driver = res.driver, name = res.name, o = o, c = res.c or {},
            src = skey, unresolved = res.unresolved, kindUnknown = res.kindUnknown }
        if place.type == "group" and place.target and byName[place.target] then
            local row, col = tonumber(place.row), tonumber(place.col)
            if row and col and row >= 0 and col >= 0 then I.gpos = { row = math.floor(row), col = math.floor(col) } end
            I.sortIndex = tonumber(place.sortIndex) or ((row or 0) * 20 + (col or 0))
            local g = byName[place.target]
            g.icons[#g.icons + 1] = I
            -- inside a shared layout an icon is this character's and spec's alone
            if G then
                I.c.chars = { [ctx.charKey] = true }
                if not I.c.specs and ctx.specID then I.c.specs = { [ctx.specID] = true } end
            end
        else
            I.pos = { x = tonumber(place.x) or 0, y = tonumber(place.y) or 0 }
            local size = tonumber(place.iconSize)
            if size and size > 0 then
                Put(I.o, "position", "iconWidth", math.floor(size + 0.5))
                Put(I.o, "position", "iconHeight", math.floor(size + 0.5))
            end
            L.icons[#L.icons + 1] = I
        end
        ctx.counts.icons[res.kind] = (ctx.counts.icons[res.kind] or 0) + 1
        if kk == "cdm" then ctx.counts.cdmIcons = ctx.counts.cdmIcons + 1 else ctx.counts.arcIcons = ctx.counts.arcIcons + 1 end
    end
    -- grouped first: a group placement outranks a stale free entry
    local sp = type(profile.savedPositions) == "table" and profile.savedPositions or {}
    local keys = {}
    for k in pairs(sp) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local p = sp[k]
        if type(p) == "table" and p.type == "group" then Icon(k, p) end
    end
    local fi = type(profile.freeIcons) == "table" and profile.freeIcons or {}
    keys = {}
    for k in pairs(fi) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local p = fi[k]
        if type(p) == "table" then Icon(k, { type = "free", x = p.x, y = p.y, iconSize = p.iconSize, viewerType = (sp[k] and sp[k].viewerType) or nil }) end
    end
    for _, k in ipairs((function() local t = {} for kk in pairs(sp) do t[#t + 1] = kk end table.sort(t, function(a, b) return tostring(a) < tostring(b) end) return t end)()) do
        local p = sp[k]
        if type(p) == "table" and p.type ~= "group" and not placed[tostring(k)] and p.x ~= nil then Icon(k, p) end
    end
    -- styled icons never placed anywhere (they sat in the Cooldown Manager's own
    -- viewer): the game's category names their default group, or they go free at
    -- the centre when the profile has no group of that name
    local unplaced = {}
    for skey, raw in pairs(settings) do
        if not placed[skey] and type(raw) == "table" and next(raw) ~= nil and IA.KeyKind(skey) == "cdm" then unplaced[#unplaced + 1] = skey end
    end
    table.sort(unplaced)
    for _, skey in ipairs(unplaced) do
        ctx.counts.unplaced = ctx.counts.unplaced + 1
        local info = opts.cooldown and opts.cooldown(tonumber(skey))
        local cat = type(info) == "table" and tonumber(info.category)
        if cat then
            local home = (cat == 1) and "Utility" or ((cat == 0 or cat == 5 or cat == 7) and "Essential" or "Buffs")
            if byName[home] then Icon(skey, { type = "group", target = home }) else Icon(skey, { type = "free", x = 0, y = 0 }) end
        else
            Need(cov, "unplaced styled cooldowns (the game's category picks Buffs / Essential / Utility)")
            IA.Cover(cov, settings[skey], IA.ICON_MAP, IA.IconRoute("spell"), nil, "icon")
        end
    end
    for _, g in ipairs(L.groups) do
        table.sort(g.icons, function(a, b) return (a.sortIndex or 0) < (b.sortIndex or 0) end)
    end
    if L.contribution then
        for _, g in ipairs(L.contribution.groups) do
            table.sort(g.icons, function(a, b) return (a.sortIndex or 0) < (b.sortIndex or 0) end)
        end
    end
    ctx.counts.freeIcons = ctx.counts.freeIcons + #L.icons
    return L
end

-- The base layout stays out while a talent layout's required nodes are taken, as
-- v1's talent profiles took over from the active one.
function IA.ExcludeSiblings(layouts)
    for _, base in ipairs(layouts) do
        if base.active and not base.conditioned then
            for _, other in ipairs(layouts) do
                if other ~= base and other.conditioned and other.c.talents then
                    for nodeID in pairs(other.c.talents) do
                        base.c.talentsNot = base.c.talentsNot or {}
                        base.c.talentsNot[nodeID] = true
                        -- the node's option and class / spec tags go with it
                        for _, k in ipairs({ "talentEntry", "talentClass", "talentSpec" }) do
                            local v = other.c[k] and other.c[k][nodeID]
                            if v then
                                base.c[k] = base.c[k] or {}
                                base.c[k][nodeID] = v
                            end
                        end
                    end
                end
            end
        end
    end
end

-- v1's global icon layers (the account profile the character used) -> Arc Auras
-- saved defaults per icon kind, so the copied icons stay sparse and new ones match.
-- cover files the layers' keys once per account profile.
function IA.PlanDefaults(ctx, cover)
    local cov = ctx.cov
    local out = {}
    for _, kind in ipairs({ "spell", "item", "trinket", "totem" }) do
        out["icon:" .. kind] = IA.MapIcon(IA.Merge(IA.V1_ICON_DEFAULTS, ctx.globals.cooldown), kind, { cdm = true })
    end
    out["icon:aura"] = IA.MapIcon(IA.Merge(IA.V1_ICON_DEFAULTS, ctx.globals.aura), "aura", { cdm = true })
    if cover then
        if type(ctx.globals.cooldown) == "table" then IA.Cover(cov, ctx.globals.cooldown, IA.ICON_MAP, IA.IconRoute("spell"), nil, "global.cooldown") end
        if type(ctx.globals.aura) == "table" then IA.Cover(cov, ctx.globals.aura, IA.ICON_MAP, IA.IconRoute("aura"), nil, "global.aura") end
    end
    return out
end

-- A v1 bar's shared display / behavior tables -> a plan bar's o, c, pos and anchor.
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
    if d.thresholdMode == "fragmented" or d.thresholdMode == "icons" then Put(o, "resource", "style", "pips") end
    -- folded in half: the first lap's colour is the fill's, the second its own
    if kind == "resource" and d.thresholdMode == "folded" then
        Put(o, "resource", "foldOn", true)
        local c1, c2 = Color(d.foldedColor1), Color(d.foldedColor2)
        if c1 then Put(o, "fill", "color", c1) end
        if c2 then Put(o, "resource", "foldColor", c2) end
    end
    local pos = type(d.barPosition) == "table" and d.barPosition or {}
    B.pos = { x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0 }
    if d.anchorToGroup == true and type(d.anchorGroupName) == "string" and d.anchorGroupName ~= "" then
        local pt = d.anchorPoint or "BOTTOM"
        local src = (pt == "TOP") and "BOTTOM" or (pt == "BOTTOM") and "TOP" or (pt == "LEFT") and "RIGHT" or (pt == "RIGHT") and "LEFT" or "TOP"
        B.anchor = { kind = "group", group = d.anchorGroupName, src = src, dst = pt,
            x = tonumber(d.anchorOffsetX) or 0, y = tonumber(d.anchorOffsetY) or 0,
            match = d.matchGroupWidth == true, adjust = tonumber(d.matchWidthAdjust) or 0 }
    end
    -- one font per bar: the stack text's, else the duration's, else the name's
    if d.font == nil then
        local f = d.durationFont or d.nameFont
        if f ~= nil then Put(o, "text", "font", IA.CONV.font(f)) end
    end
    -- the charge text's own keys stand in when the text anchor keys are unset
    if d.textAnchor == nil and IA.CONV.barAnchor(d.chargeTextAnchor) then Put(o, "text", "stkAnchor", d.chargeTextAnchor) end
    if d.textAnchorOffsetX == nil and tonumber(d.chargeTextOffsetX) then Put(o, "text", "stkOffsetX", math.floor(tonumber(d.chargeTextOffsetX) + 0.5)) end
    if d.textAnchorOffsetY == nil and tonumber(d.chargeTextOffsetY) then Put(o, "text", "stkOffsetY", math.floor(tonumber(d.chargeTextOffsetY) + 0.5)) end
    -- a free-dragged text: v1 saved a screen position; here it is offsets from the bar's centre
    local function FreeText(anchorKey, posKey, prefix)
        if d[anchorKey] ~= "FREE" then return end
        Put(o, "text", prefix .. "Anchor", "CENTER")
        local p = d[posKey]
        local x, y = type(p) == "table" and tonumber(p.x), type(p) == "table" and tonumber(p.y)
        if x and y then
            Put(o, "text", prefix .. "OffsetX", math.floor(x - B.pos.x + 0.5))
            Put(o, "text", prefix .. "OffsetY", math.floor(y - B.pos.y + 0.5))
        end
    end
    FreeText("textAnchor", "textPosition", "stk")
    FreeText("durationAnchor", "durationPosition", "dur")
    FreeText("nameAnchor", "textPosition", "name")
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
    -- duration thresholds: v1's bands 2 to 4, in seconds or percent
    local n = 0
    for i = 2, 4 do
        if d["durationThreshold" .. i .. "Enabled"] == true and tonumber(d["durationThreshold" .. i .. "Value"]) then
            n = n + 1
            Put(o, "thresholds", "thresh" .. i .. "Value", tonumber(d["durationThreshold" .. i .. "Value"]))
            local col = Color(d["durationThreshold" .. i .. "Color"])
            if col then Put(o, "thresholds", "thresh" .. i .. "Color", col) end
        end
    end
    if n > 0 then
        Put(o, "thresholds", "threshEnabled", true)
        Put(o, "thresholds", "threshCount", math.min(3, n))
        Put(o, "thresholds", "threshAsSeconds", d.durationThresholdAsSeconds == true)
        local ref = tonumber(d.durationThresholdMaxDuration)
        if ref and ref > 0 then
            Put(o, "thresholds", "threshRef", math.floor(ref + 0.5))
            Put(o, "thresholds", "threshCdSeconds", math.floor(ref + 0.5))
        end
    elseif d.durationColorCurveEnabled == true and (kind == "aura" or kind == "cooldown") then
        -- the older colour curve: one step at its threshold, the high colour as the fill
        local thr = tonumber(d.durationColorCurveThreshold) or 0.3
        Put(o, "thresholds", "threshEnabled", true)
        Put(o, "thresholds", "threshCount", 1)
        Put(o, "thresholds", "threshAsSeconds", false)
        Put(o, "thresholds", "thresh2Value", math.floor(thr * 100 + 0.5))
        local low, high = Color(d.durationColorCurveLowColor), Color(d.durationColorCurveHighColor)
        if low then Put(o, "thresholds", "thresh2Color", low) end
        if high then Put(o, "fill", "color", high) end
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
    local pr = type(cfg.prediction) == "table" and cfg.prediction.spells
    if type(pr) == "table" then
        for _, s in pairs(pr) do
            if type(s) == "table" and s.enabled ~= false then Put(o, "predict", "predictEnabled", true) break end
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

-- v1 coloured a bar by its value three ways: threshold layers ({ enabled, minValue,
-- maxValue, color }; layer 1 is the base), colour ranges ({ from, to, color }) and
-- per-stack colours ({ [n] = color }, segmented). A resource bar takes them as
-- power thresholds, a stack bar as stack colours, a charge bar as its full colour.
function IA.MapLayers(o, cfg, d, kind, isStack)
    local layers = type(cfg.thresholds) == "table" and cfg.thresholds or {}
    local ranges = type(cfg.colorRanges) == "table" and cfg.colorRanges or {}
    local perStack = type(cfg.stackColors) == "table" and cfg.stackColors or {}
    if kind == "resource" then
        local n = 0
        local unitsMax = tonumber(cfg.tracking and cfg.tracking.maxValue) or tonumber(layers[1] and layers[1].maxValue) or 100
        local base = type(layers[1]) == "table" and layers[1].enabled ~= false and Color(layers[1].color)
        if base and d.barColor == nil then Put(o, "fill", "color", base) end
        for i = 2, 5 do
            local t = layers[i]
            if type(t) == "table" and t.enabled == true and tonumber(t.minValue) then
                n = n + 1
                Put(o, "powerthresholds", "pth" .. (n + 1) .. "Value", math.floor(tonumber(t.minValue) + 0.5))
                local col = Color(t.color)
                if col then Put(o, "powerthresholds", "pth" .. (n + 1) .. "Color", col) end
            end
        end
        if n > 0 then
            Put(o, "powerthresholds", "pthEnabled", true)
            Put(o, "powerthresholds", "pthCount", math.min(4, n))
            Put(o, "powerthresholds", "pthDirection", "above")
            Put(o, "powerthresholds", "pthAbsolute", unitsMax ~= 100)
        end
        -- pips: each its own colour
        local pips = type(d.fragmentedColors) == "table" and d.fragmentedColors or {}
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
            if first and d.barColor == nil then Put(o, "fill", "color", first) end
        end
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
    -- a stack bar: per-stack colours first, then colour ranges, then the layers
    local n = 0
    local function Band(from, col)
        if n >= 3 or not (from and col) then return end
        n = n + 1
        Put(o, "stackcolors", "sc" .. (n + 1) .. "Value", math.floor(from + 0.5))
        Put(o, "stackcolors", "sc" .. (n + 1) .. "Color", col)
    end
    local anyStack = false
    for k in pairs(perStack) do if tonumber(k) then anyStack = true break end end
    if anyStack then
        for i = 2, 4 do Band(i, Color(perStack[i])) end
        if n > 0 then Put(o, "stackcolors", "scPosition", true) end
        local first = Color(perStack[1])
        if first and d.barColor == nil then Put(o, "fill", "color", first) end
    else
        local anyRange = false
        for i = 2, 4 do if type(ranges[i]) == "table" and ranges[i].enabled == true then anyRange = true end end
        if anyRange then
            for i = 2, 4 do
                local r = ranges[i]
                if type(r) == "table" and r.enabled == true then Band(tonumber(r.from), Color(r.color)) end
            end
            local first = type(ranges[1]) == "table" and Color(ranges[1].color)
            if first and d.barColor == nil then Put(o, "fill", "color", first) end
        else
            for i = 2, 4 do
                local t = layers[i]
                if type(t) == "table" and t.enabled == true then Band(tonumber(t.minValue), Color(t.color)) end
            end
            local first = type(layers[1]) == "table" and layers[1].enabled ~= false and Color(layers[1].color)
            if first and d.barColor == nil then Put(o, "fill", "color", first) end
        end
    end
    if n > 0 then
        Put(o, "stackcolors", "scEnabled", true)
        Put(o, "stackcolors", "scCount", n)
    end
end

-- The per-character bar stores -> plan bars (a character's shared layout).
function IA.PlanBars(ctx, charDB, L)
    local cov, counts = ctx.cov, ctx.counts
    local route = function(row, path)
        if row.gap then return nil, row.gap end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end
    -- aura bars
    for i, cfg in pairs(type(charDB.bars) == "table" and charDB.bars or {}) do
        local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
        if tr and tr.enabled == true then
            local tt, sid = tr.trackType, tonumber(tr.spellID)
            -- v1's data repair strips the default track type ("buff") from saved bars
            if tt == nil then tt = "buff" end
            if tt == "both" then
                Dropped(cov, "bar:tracking.trackType.both", "a buff-and-debuff bar becomes a buff bar on you; add a debuff bar for the other side")
                tt = "buff"
            end
            if (tt == "buff" or tt == "debuff" or tt == "petbuff") and sid and sid > 0 then
                local B = { barKind = "aura", barMode = (tr.useDurationBar == true) and "duration" or "stack",
                    name = (type(tr.buffName) == "string" and tr.buffName ~= "") and tr.buffName or ("Aura " .. sid),
                    driver = { spellID = sid, auraType = (tt == "debuff") and "debuff" or "buff",
                        unit = (tt == "debuff") and "target" or (tt == "petbuff") and "pet" or "player",
                        maxStacks = tonumber(tr.maxStacks) }, o = {}, c = {} }
                if tr.auraOwnOnly == true then B.driver.caster = "mine" end
                if type(tr.auraUnits) == "table" then
                    for _, u in ipairs(IA.AURA_UNITS) do
                        if tr.auraUnits[u] == true then B.driver.unit = u break end
                    end
                end
                IA.MapBarLook(B, cfg, IA.BAR_MAP, ctx)
                IA.Cover(cov, cfg, IA.BAR_MAP, route, nil, "bar")
                L.bars[#L.bars + 1] = B
                counts.bars.aura = (counts.bars.aura or 0) + 1
            else
                Dropped(cov, "bar:dropped.aura bar: track type " .. tostring(tt), "only buff and debuff bars with a spell id are carried")
                counts.barsDropped = counts.barsDropped + 1
            end
        end
    end
    -- cooldown and charge bars
    for sid, kinds in pairs(type(charDB.cooldownBarConfigs) == "table" and charDB.cooldownBarConfigs or {}) do
        for barType, cfg in pairs(type(kinds) == "table" and kinds or {}) do
            local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
            local spellID = tonumber(sid) or (tr and tonumber(tr.spellID))
            if tr and tr.enabled ~= false and spellID then
                local base = tostring(barType):match("^(%a+)")
                if base == "cooldown" or base == "charge" then
                    local B = { barKind = "cooldown", barMode = (base == "charge") and "stack" or "duration",
                        name = (ctx.opts.spellName and ctx.opts.spellName(spellID)) or ("Spell " .. spellID),
                        driver = { spellID = spellID }, o = {}, c = {} }
                    IA.MapBarLook(B, cfg, IA.BAR_MAP, ctx)
                    IA.Cover(cov, cfg, IA.BAR_MAP, route, nil, "bar")
                    L.bars[#L.bars + 1] = B
                    counts.bars[base] = (counts.bars[base] or 0) + 1
                else
                    Dropped(cov, "bar:dropped.cooldown bar type " .. tostring(barType), "only cooldown and charge bars are carried")
                    counts.barsDropped = counts.barsDropped + 1
                end
            end
        end
    end
    -- resource bars
    for i, cfg in pairs(type(charDB.resourceBars) == "table" and charDB.resourceBars or {}) do
        local tr = type(cfg) == "table" and type(cfg.tracking) == "table" and cfg.tracking or nil
        if tr and tr.enabled == true then
            local power
            if tr.resourceCategory == "secondary" then
                power = IA.POWERS[tr.secondaryType]
                if not power then Dropped(cov, "bar:dropped.resource bar: " .. tostring(tr.secondaryType), "this resource is an aura stack bar in Arc Auras, not a power") end
            elseif tr.resourceCategory == "autoPrimary" then
                -- the options' POWER_AUTO: the bar follows the power in use
                power = -1
            else
                power = tonumber(tr.powerType)
            end
            if power then
                local B = { barKind = "resource", name = (type(tr.powerName) == "string" and tr.powerName ~= "") and tr.powerName or ("Power " .. power),
                    driver = { powerType = power }, o = {}, c = {} }
                IA.MapBarLook(B, cfg, IA.BAR_MAP, ctx)
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
            else
                counts.barsDropped = counts.barsDropped + 1
            end
        end
    end
    -- timer bars
    for _, cfg in pairs(type(charDB.timerBarConfigs) == "table" and charDB.timerBarConfigs or {}) do
        if type(cfg) == "table" then
            Dropped(cov, "bar:dropped.timer bar", "custom timer bars: Arc Auras has no timer engine yet")
            counts.barsDropped = counts.barsDropped + 1
        end
    end
    -- cast bars: the player's instances, then the focus and target bars
    local castRoute = function(row, path)
        if row.gap then return nil, row.gap end
        if row.special then return "(" .. row.special .. ")" end
        return row[1] .. "." .. row[2]
    end
    local function CastBar(cfg, unit, name)
        if type(cfg) ~= "table" or cfg.enabled ~= true then return end
        local B = { barKind = "cast", name = name, driver = { unit = unit }, o = {}, c = {} }
        for path, row in pairs(IA.CAST_MAP) do
            if not row.gap and not row.special then IA.MapRow(B.o, row, cfg[path]) end
        end
        local pos = type(cfg.barPosition) == "table" and cfg.barPosition or {}
        B.pos = { x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0 }
        if cfg.tickMarksEnabled == true then
            Put(B.o, "ticks", "tickMode", (cfg.tickMode == "custom") and "custom" or "percent")
            if cfg.tickShowOn == "channels" then Put(B.o, "ticks", "tickChannelOnly", true) end
        end
        local ch = type(cfg.profiles) == "table" and type(cfg.profiles.channel) == "table" and Color(cfg.profiles.channel.barColor)
        if ch then
            Put(B.o, "fill", "castChannelOn", true)
            Put(B.o, "fill", "castChannelColor", ch)
        end
        if cfg.hideOutOfCombat == true then B.c.fadeWhen = { outOfCombat = true } end
        if cfg.anchorToGroup == true and type(cfg.anchorGroupName) == "string" and cfg.anchorGroupName ~= "" then
            local pt = cfg.anchorPoint or "BOTTOM"
            B.anchor = { kind = "group", group = cfg.anchorGroupName, src = (pt == "TOP") and "BOTTOM" or "TOP", dst = pt,
                x = tonumber(cfg.anchorOffsetX) or 0, y = tonumber(cfg.anchorOffsetY) or 0,
                match = cfg.matchGroupWidth == true, adjust = tonumber(cfg.matchWidthAdjust) or 0 }
        end
        if cfg.castType and cfg.castType ~= "all" then Dropped(cov, "cast:castType." .. tostring(cfg.castType), "a cast bar shows every cast; the type filter is dropped", true) end
        IA.Cover(cov, cfg, IA.CAST_MAP, castRoute, nil, "cast")
        L.bars[#L.bars + 1] = B
        counts.bars.cast = (counts.bars.cast or 0) + 1
    end
    local cbs = charDB.castbars
    if ctx.db.global and ctx.db.global.castbarShared == true and type(ctx.db.global.castbars) == "table" then cbs = ctx.db.global.castbars end
    for i, cfg in pairs(type(cbs) == "table" and cbs or {}) do
        if type(i) == "number" then CastBar(cfg, "player", "Cast bar " .. i) end
    end
    CastBar(charDB.focusCastbar, "focus", "Focus cast bar")
    CastBar(charDB.targetCastbar, "target", "Target cast bar")
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
    local plan = { version = 2, layouts = {}, globals = {}, globalList = {}, looks = {}, tree = {}, leaves = {}, coverage = cov,
        counts = { chars = 0, specs = 0, profiles = 0, layouts = 0, globalLayouts = 0, groups = 0, freeIcons = 0,
            cdmIcons = 0, arcIcons = 0, icons = {}, iconsDropped = 0, unplaced = 0, bars = {},
            barsDropped = 0, reminders = 0, reminderGroups = 0, dormant = 0, talentLayouts = 0, units = 0 } }
    if type(db) ~= "table" or type(db.char) ~= "table" then return plan end
    local chars = {}
    for k in pairs(db.char) do chars[#chars + 1] = k end
    table.sort(chars, function(a, b) return tostring(a) < tostring(b) end)
    local coveredProfiles = {}
    local function Leaf(node, kind, unit, label, n)
        local leaf = { id = unit, unit = unit, kind = kind, label = label, n = n }
        node.children[#node.children + 1] = leaf
        plan.leaves[unit] = leaf
        plan.counts.units = plan.counts.units + 1
        return leaf
    end
    for _, v1key in ipairs(chars) do
        local charDB = db.char[v1key]
        if type(charDB) == "table" then
            local charKey, charName = IA.CharKey(v1key)
            local profName = (type(db.profileKeys) == "table" and db.profileKeys[v1key]) or "Default"
            local prof = type(db.profiles) == "table" and db.profiles[profName] or nil
            local ce = type(prof) == "table" and prof.cdmEnhance or nil
            local globals = { cooldown = (type(ce) == "table" and ce.globalCooldownSettings) or {},
                aura = (type(ce) == "table" and ce.globalAuraSettings) or {} }
            local ctx = { db = db, opts = opts, cov = cov, counts = plan.counts, charKey = charKey,
                charName = charName or tostring(v1key), globals = globals, arcDB = charDB.arcAuras }
            local node = { id = "char:" .. charKey, kind = "char", label = tostring(v1key), charKey = charKey, children = {} }
            local cdm = charDB.cdmGroups
            local hadLayout = false
            if type(cdm) == "table" and type(cdm.specData) == "table" then
                local specKeys = {}
                for sk in pairs(cdm.specData) do specKeys[#specKeys + 1] = sk end
                table.sort(specKeys, function(a, b) return tostring(a) < tostring(b) end)
                for _, sk in ipairs(specKeys) do
                    local specData = cdm.specData[sk]
                    local classID, idx = IA.SpecKey(sk)
                    if classID and type(specData) == "table" and type(specData.layoutProfiles) == "table" then
                        plan.counts.specs = plan.counts.specs + 1
                        ctx.specKey, ctx.classID = sk, classID
                        ctx.classTag = IA.ClassTag(classID, opts)
                        local specID, specName = IA.SpecID(classID, idx, opts)
                        ctx.specID = specID
                        ctx.specName = specName or ("Spec " .. tostring(idx))
                        local specNode = { id = "spec:" .. charKey .. "|" .. sk, kind = "spec", label = ctx.specName, children = {} }
                        local made = {}
                        local pnames = {}
                        for pn in pairs(specData.layoutProfiles) do pnames[#pnames + 1] = pn end
                        table.sort(pnames, function(a, b) return tostring(a) < tostring(b) end)
                        for _, pn in ipairs(pnames) do
                            local profile = specData.layoutProfiles[pn]
                            if type(profile) == "table" then
                                plan.counts.profiles = plan.counts.profiles + 1
                                local L = IA.PlanProfile(ctx, pn, profile, specData, plan)
                                made[#made + 1] = L
                                local tag = L.conditioned and "talents" or (L.active and "active" or "spare")
                                local pnode = { id = "profile:" .. L.key, kind = "profile", label = tostring(pn) .. " (" .. tag .. ")", tag = tag, children = {} }
                                if L.contribution then
                                    for _, part in ipairs(L.contribution.groups) do
                                        Leaf(pnode, "group", part.unit, ("%s (account-wide layout '%s'): %d icons"):format(part.name, L.linked, #part.icons), #part.icons)
                                    end
                                else
                                    for _, g in ipairs(L.groups) do
                                        Leaf(pnode, "group", g.unit, ("%s: %d icons"):format(g.name, #g.icons), #g.icons)
                                    end
                                end
                                if #L.icons > 0 then Leaf(pnode, "free", L.freeUnit, ("Free icons: %d"):format(#L.icons), #L.icons) end
                                if #pnode.children > 0 then specNode.children[#specNode.children + 1] = pnode end
                            end
                        end
                        IA.ExcludeSiblings(made)
                        for _, L in ipairs(made) do
                            plan.layouts[#plan.layouts + 1] = L
                            plan.counts.layouts = plan.counts.layouts + 1
                            if L.dormant then plan.counts.dormant = plan.counts.dormant + 1 end
                            if L.conditioned then plan.counts.talentLayouts = plan.counts.talentLayouts + 1 end
                            hadLayout = true
                        end
                        if #specNode.children > 0 then node.children[#node.children + 1] = specNode end
                    end
                end
            end
            -- the character's bars and reminders share one layout (v1 kept them per character)
            local S = { name = ctx.charName .. " shared", c = { chars = { [charKey] = true } }, pos = { x = 0, y = 0 }, o = {},
                groups = {}, icons = {}, bars = {}, reminders = {}, shared = true, key = "layout:" .. charKey .. "|shared",
                unitBars = "bars:" .. charKey, unitReminders = "reminders:" .. charKey, charKey = charKey }
            local anyClass
            if type(cdm) == "table" and type(cdm.specData) == "table" then
                for sk in pairs(cdm.specData) do
                    local cid = IA.SpecKey(sk)
                    if cid then anyClass = anyClass or IA.ClassTag(cid, opts) ctx.classID = ctx.classID or cid end
                end
            end
            if anyClass then S.c.classes = { [anyClass] = true } end
            IA.PlanBars(ctx, charDB, S)
            IA.PlanReminders(ctx, charDB, S)
            if #S.bars > 0 or #S.reminders > 0 then
                plan.layouts[#plan.layouts + 1] = S
                plan.counts.layouts = plan.counts.layouts + 1
                hadLayout = true
                local snode = { id = "shared:" .. charKey, kind = "shared", label = "Bars and reminders", children = {} }
                if #S.bars > 0 then Leaf(snode, "bars", S.unitBars, ("Bars: %d"):format(#S.bars), #S.bars) end
                if #S.reminders > 0 then
                    local nrem = 0
                    for _, RG in ipairs(S.reminders) do nrem = nrem + #RG.reminders end
                    Leaf(snode, "reminders", S.unitReminders, ("Cooldown Reminder: %d reminders"):format(nrem), nrem)
                end
                node.children[#node.children + 1] = snode
            end
            -- the character's global look (its account profile's two layers) as saved defaults
            if hadLayout then
                local look = { unit = "look:" .. charKey, profile = profName, defaults = IA.PlanDefaults(ctx, not coveredProfiles[profName]) }
                coveredProfiles[profName] = true
                plan.looks[charKey] = look
                Leaf(node, "look", look.unit, ("Global look (Arc UI profile '%s')"):format(tostring(profName)), 1)
                plan.counts.chars = plan.counts.chars + 1
                plan.tree[#plan.tree + 1] = node
            end
        end
    end
    plan.counts.layouts = plan.counts.layouts + #plan.globalList
    return plan
end

-- Whether the importer can run here: retail, with v1's saved data loaded.
function IA.Available()
    if NS.IsForever ~= nil then return false end
    local db = rawget(_G, "ArcUIDB")
    return type(db) == "table" and type(db.char) == "table"
end

-- The stamp: what has been imported, by unit, plus the layout and group records the
-- importer made, so a later run adds the rest to them and never to a player's own.
function IA.Stamp(create)
    local db = rawget(_G, "ArcAurasDB")
    if type(db) ~= "table" then return nil end
    local s = db.importArcUIv1
    if type(s) ~= "table" or type(s.units) ~= "table" then
        if not create then return nil end
        s = { at = 0, units = {}, layouts = {}, groups = {} }
        db.importArcUIv1 = s
    end
    s.layouts = s.layouts or {}
    s.groups = s.groups or {}
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

-- How many of the plan's units are still to import.
function IA.Remaining(plan)
    if not (plan and plan.leaves) then return 0 end
    local n = 0
    for unit in pairs(plan.leaves) do if not IA.UnitDone(unit) then n = n + 1 end end
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

-- The picker's first state: this character's active profiles, bars, reminders and
-- global look; nothing of the other characters, nothing already imported.
function IA.DefaultPicks(plan)
    local picks = {}
    local me = IA.CurrentChar()
    if not (plan and plan.tree and me) then return picks end
    local function Walk(node, on)
        if node.unit then
            if on and not IA.UnitDone(node.unit) then picks[node.unit] = true end
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
    local CV = rawget(_G, "C_CooldownViewer")
    if type(CV) == "table" and CV.GetCooldownViewerCooldownInfo then
        o.cooldown = function(id)
            if type(id) ~= "number" then return nil end
            return CV.GetCooldownViewerCooldownInfo(id)
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
    end
    local CI = rawget(_G, "C_Item")
    if type(CI) == "table" and CI.GetItemNameByID then o.itemName = function(id) return CI.GetItemNameByID(id) end end
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

-- Applies the picked units of a plan (a set of leaf units; nil = everything not yet
-- done): fresh records through the Store, the picked global look as saved defaults,
-- every unit stamped. A layout or group the importer made on an earlier run (the
-- stamp's ids) takes the rest of its content; a player's own records are never
-- touched. Refused in combat.
function IA.Apply(plan, picks)
    local Store = NS.Store
    if not (Store and plan and plan.layouts) then return nil, "nothing to import" end
    local lock = rawget(_G, "InCombatLockdown")
    if lock and lock() then return nil, "not in combat" end
    local db = rawget(_G, "ArcAurasDB")
    if type(db) ~= "table" then return nil, "the store is not loaded" end
    local stamp = IA.Stamp(true)
    if picks == nil then
        picks = {}
        for unit in pairs(plan.leaves or {}) do if not stamp.units[unit] then picks[unit] = true end end
    end
    local function Picked(unit) return unit ~= nil and picks[unit] == true and not stamp.units[unit] end
    local any = false
    for unit in pairs(picks) do if Picked(unit) then any = true break end end
    if not any then return nil, "nothing picked" end
    local res = { layouts = 0, groups = 0, icons = 0, bars = 0, reminders = 0, skipped = 0, anchorsDropped = 0, units = 0, firstLayoutId = nil }
    local Schema = NS.Schema
    local function Live(id, kind)
        local r = id and Store.Get(id)
        if r and r.type == kind then return r end
        return nil
    end
    local function EnsureLayout(key, L)
        local lay = Live(stamp.layouts[key], "layout")
        if not lay then
            lay = Store.NewLayout(L.name)
            lay.pos = { x = 0, y = 0 }
            lay.c = Copy(L.c)
            stamp.layouts[key] = lay.id
            res.layouts = res.layouts + 1
        end
        res.firstLayoutId = res.firstLayoutId or lay.id
        return lay
    end
    local function EnsureGroup(key, lay, G)
        local g = Live(stamp.groups[key], "group")
        if g then return g, false end
        g = Store.NewGroup(lay.id, G.name, G.kind)
        g.pos = { x = G.pos.x, y = G.pos.y }
        g.c = Copy(G.c)
        IA.WriteO(g, G.o)
        stamp.groups[key] = g.id
        res.groups = res.groups + 1
        return g, true
    end
    local function AddIcon(I, lay, groupId)
        if I.unresolved or (I.kind == "spell" and not I.driver.spellID) then
            res.skipped = res.skipped + 1
            return
        end
        local rec = Store.NewIcon(I.kind, Copy(I.driver), groupId, lay.id, I.name)
        if not rec and groupId then
            rec = Store.NewIcon(I.kind, Copy(I.driver), nil, lay.id, I.name)
            if rec then
                local g = Store.Get(groupId)
                rec.pos = { x = (g and g.pos.x) or 0, y = (g and g.pos.y) or 0 }
            end
        end
        if not rec then res.skipped = res.skipped + 1 return end
        rec.c = Copy(I.c or {})
        if groupId then
            rec.gpos = I.gpos and { row = I.gpos.row, col = I.gpos.col } or nil
        elseif I.pos then
            rec.pos = { x = I.pos.x, y = I.pos.y }
        end
        IA.WriteO(rec, I.o)
        res.icons = res.icons + 1
    end
    local function Mark(unit)
        stamp.units[unit] = true
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
    end
    -- the per-spec layouts: picked groups and free icons
    local later = {}
    for _, L in ipairs(plan.layouts) do
        if not L.shared then
            local wantGroups = {}
            for _, G in ipairs(L.groups) do if Picked(G.unit) then wantGroups[#wantGroups + 1] = G end end
            local wantFree = #L.icons > 0 and Picked(L.freeUnit)
            if #wantGroups > 0 or wantFree then
                local lay = EnsureLayout(L.key, L)
                for _, G in ipairs(wantGroups) do
                    local g, fresh = EnsureGroup(L.key .. "|" .. G.name, lay, G)
                    for _, I in ipairs(G.icons) do AddIcon(I, lay, g.id) end
                    if fresh and G.anchor then later[#later + 1] = { rec = g, a = G.anchor, layoutKey = L.key } end
                    Mark(G.unit)
                end
                if wantFree then
                    for _, I in ipairs(L.icons) do AddIcon(I, lay, nil) end
                    Mark(L.freeUnit)
                end
            end
        end
    end
    -- the account-wide layouts: each once; every picked profile adds its icons to the
    -- shared groups and its character, class and spec to the layout's who
    for _, G in ipairs(plan.globalList or {}) do
        local lay
        for _, contrib in ipairs(G.contributions) do
            for _, part in ipairs(contrib.groups) do
                if Picked(part.unit) then
                    if not lay then lay = EnsureLayout(G.key, { name = G.name, c = { chars = {}, classes = {}, specs = {} } }) end
                    lay.c = lay.c or {}
                    lay.c.chars = lay.c.chars or {}
                    lay.c.chars[contrib.charKey] = true
                    if contrib.classTag then
                        lay.c.classes = lay.c.classes or {}
                        lay.c.classes[contrib.classTag] = true
                    end
                    if contrib.specID then
                        lay.c.specs = lay.c.specs or {}
                        lay.c.specs[contrib.specID] = true
                    end
                    local gdef
                    for _, gg in ipairs(G.groups) do if gg.name == part.name then gdef = gg end end
                    local g, fresh = EnsureGroup(G.key .. "|" .. part.name, lay, gdef)
                    for _, I in ipairs(part.icons) do AddIcon(I, lay, g.id) end
                    if fresh and gdef.anchor then later[#later + 1] = { rec = g, a = gdef.anchor, layoutKey = G.key } end
                    Mark(part.unit)
                end
            end
        end
    end
    -- group anchors, by name inside their layout (this run's groups and earlier runs')
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
    -- the shared layouts: bars (anchored to the character's live groups by name) and reminders
    for _, L in ipairs(plan.layouts) do
        if L.shared then
            local wantBars = #L.bars > 0 and Picked(L.unitBars)
            local wantRem = #L.reminders > 0 and Picked(L.unitReminders)
            if wantBars or wantRem then
                local lay = EnsureLayout(L.key, L)
                if wantBars then
                    local charGroups = IA.CharGroups(plan, stamp, L.charKey)
                    for _, B in ipairs(L.bars) do
                        local rec = Store.NewBar(lay.id, B.barKind, Copy(B.driver), B.name, B.barMode)
                        if rec then
                            rec.c = Copy(B.c or {})
                            rec.pos = { x = B.pos.x, y = B.pos.y }
                            IA.WriteO(rec, B.o)
                            res.bars = res.bars + 1
                            if B.anchor and not IA.WriteAnchor(rec, B.anchor, {}, true, charGroups) then res.anchorsDropped = res.anchorsDropped + 1 end
                        end
                    end
                    Mark(L.unitBars)
                end
                if wantRem then
                    for _, RG in ipairs(L.reminders) do
                        local g = Store.NewGroup(lay.id, RG.name, "reminder")
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
                    Mark(L.unitReminders)
                end
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

-- A character's groups by name across its live layouts (its active per-spec ones
-- and the account-wide ones it feeds), for its bars' anchors.
function IA.CharGroups(plan, stamp, charKey)
    local Store = NS.Store
    local out = {}
    local function Add(name, id, specs)
        local r = id and Store.Get(id)
        if not (r and r.type == "group") then return end
        out[name] = out[name] or {}
        table.insert(out[name], { id = id, specs = specs })
    end
    for _, L in ipairs(plan.layouts) do
        if not L.shared and L.charKey == charKey and L.active and not L.conditioned and not L.dormant then
            for _, G in ipairs(L.groups) do Add(G.name, stamp.groups[L.key .. "|" .. G.name], L.c.specs) end
        end
    end
    for _, G in ipairs(plan.globalList or {}) do
        local specs
        for _, contrib in ipairs(G.contributions) do
            if contrib.charKey == charKey and contrib.specID then
                specs = specs or {}
                specs[contrib.specID] = true
            end
        end
        if specs then
            for _, gg in ipairs(G.groups) do Add(gg.name, stamp.groups[G.key .. "|" .. gg.name], specs) end
        end
    end
    return out
end
