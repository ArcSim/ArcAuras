-- Option schema: every setting is declared once, and the store resolver,
-- Normalize, the serializer and the options panel derive from it.
-- A value resolves from the record, its layout, newDefaults, dk[kind], then d.
-- Sections with push = true get Push to All and Save as Default.

local ADDON, NS = ...
local Schema = {}
NS.Schema = Schema

Schema.VERSION = 1

Schema.ICON_KINDS = { "spell", "item", "trinket", "timer", "totem", "aura", "ammo", "enchant" }
Schema.GROUP_KINDS = { "cooldown", "aura" }
-- Creatable bar kinds; cooldown and aura bars carry rec.barMode ("duration" or
-- "stack"). The create UI hides swing where C_SwingTimer is missing, but the
-- kind stays valid everywhere, so sync never rewrites a record. Legacy "timer"
-- and "stack" (power) bars stay legal but cannot be created.
Schema.BAR_KINDS = { "cooldown", "aura", "swing", "resource", "health", "cast", "enchant", "range" }
-- Units a castbar can follow (rec.driver.unit): the three that fire cast events
-- and a change event of their own.
Schema.CAST_UNITS = { "player", "target", "focus" }
-- Units a health bar can follow (rec.driver.unit). Validity is schema-level,
-- like the kinds: a synced record keeps its unit, and the Add window offers
-- only the units this client has. No target-of-target: compound units fire no
-- health events, so a bar for one would have to poll.
Schema.HEALTH_UNITS = { "player", "target", "focus", "pet",
    "party1", "party2", "party3", "party4" }
-- A range bar's own bands (rec.driver.bands): the distances a check may use,
-- each read plain in combat on hostile targets (Bars\AD_RangeBar.lua maps them to
-- an item or an interact index), and how many bands and checks a bar keeps.
Schema.RANGE_YARDS = { 5, 10, 20, 28, 35, 40 }
Schema.RANGE_MAX_BANDS = 8
Schema.RANGE_MAX_CHECKS = 4
-- A swing bar's ability colours (rec.driver.swingColors): how many rules a bar
-- keeps, and the colour a new rule starts with.
Schema.SWING_COLOR_MAX = 8
Schema.SWING_COLOR_DEFAULT = { 1, 0.55, 0.15, 1 }

-- enchant: a weapon enchant, timed on the swipe; its sounds say applied and
-- fell off (NS.DriverEnchant).
local CD  = { spell = true, item = true, trinket = true, timer = true, totem = true, enchant = true }
local USE = { spell = true, item = true, trinket = true, timer = true, enchant = true }
local SP  = { spell = true }
local AU  = { aura = true }
local AA  = { spell = true, aura = true }
-- Every kind but aura: holder-only options (keep bright) mean nothing on an
-- engine-drawn aura button.
local NA  = { spell = true, item = true, trinket = true, timer = true, totem = true, ammo = true,
    enchant = true }
-- Stack text: only kinds something writes a count for (spell charges, item and
-- ammo bag counts, aura applications, timer stacks, enchant charges). Trinkets
-- have none.
local STK = { spell = true, item = true, timer = true, aura = true, ammo = true, enchant = true }
-- "Minutes and seconds" cutoffs in seconds, for icons and bars alike.
local ABBREV_VALUES = { 0, 120, 300, 600, 3600 }
local ABBREV_LABELS = { [0] = "Off", [120] = "Under 2 minutes", [300] = "Under 5 minutes",
    [600] = "Under 10 minutes", [3600] = "Under 1 hour" }
-- How the GCD and the wand's lock draw on a spell icon. Neither ever counts as
-- a real cooldown, so these are looks only.
local GCD_LOOKS = { "hidden", "edge", "swipe", "both" }
local GCD_LOOK_LABELS = { hidden = "Hidden", edge = "Edge only", swipe = "Swipe", both = "Swipe and edge" }
local GCD_SWIPE_DRAWN = { swipe = true, both = true }
-- The classes that shoot a wand; the wand rows show only there.
local WAND_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true }

local GK_CD = { cooldown = true }
local GK_AU = { aura = true }

local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- What an icon override's number is. Spell, item and icon file IDs overlap, so
-- each `<x>Icon` has an `<x>IconFrom` beside it and nothing is guessed. Icon ID
-- is the default: the tooltip shows icon IDs, and any art has one.
local ICON_FROM = { "icon", "spell", "item" }
local ICON_FROM_LABELS = { icon = "Icon ID", spell = "Spell ID", item = "Item ID" }

-- Glow styles for all four glows (ready, proc, usable, aura active): procloop
-- is the proc glow without its opening burst, ants Blizzard's marching ants,
-- flash the Cooldown Manager's flash. Proc, proc loop and ants run at
-- Blizzard's fixed pace, so Speed shows only for GLOW_SPEED_STYLES.
local GLOW_STYLES = { "button", "pixel", "autocast", "proc", "procloop", "ants", "flash" }
local PROC_GLOW_STYLES = { "proc", "procloop", "button", "pixel", "autocast", "ants", "flash" }
-- The aura active glow never opens with a burst, so Proc already draws the loop
-- alone there and its twin would only repeat it.
local AURA_GLOW_STYLES = { "button", "pixel", "autocast", "proc", "ants", "flash" }
local GLOW_STYLE_LABELS = { button = "Button", pixel = "Pixel", autocast = "Autocast",
    proc = "Proc", procloop = "Proc loop (no burst)", ants = "Marching ants",
    flash = "Cooldown Manager flash" }
local GLOW_SPEED_STYLES = { button = true, pixel = true, autocast = true, flash = true }

Schema.icon = {
    appearance = { push = true, inherit = true, fields = {
        zoom  = { d = 0.08, t = "num", min = 0, max = 0.4, label = "Icon zoom" },
        aspectRatio = { d = 1, t = "num", min = 0.25, max = 2.5, label = "Aspect ratio" },
        alpha = { d = 1.0,  t = "num", min = 0.1, max = 1, label = "Base alpha" },
        -- Shrinks the art inside the frame; border and swipe insets follow it.
        padding = { d = 0, t = "int", min = 0, max = 20, label = "Icon padding" },
        -- dep: the options panel hides the row unless the named field resolves
        -- to the wanted value (default true). In a list every entry must pass;
        -- nonempty gates on a non-empty text.
        borderEnabled = { d = true, t = "bool", label = "Border" },
        borderColor = { d = { 0, 0, 0, 1 }, t = "color", label = "Border color", dep = { field = "borderEnabled" } },
        borderThickness = { d = 2, t = "int", min = 1, max = 20, label = "Border thickness", dep = { field = "borderEnabled" } },
        borderInset = { d = 0, t = "int", min = -20, max = 20, label = "Border offset", dep = { field = "borderEnabled" } },
        -- Aura icons: the engine colours the border through the button's own
        -- dispel-type textures. No Lua reads the type, so it works in combat.
        dispelBorder = { d = false, t = "bool", kinds = AU, label = "Border colour by dispel type",
            desc = "While the aura is up, its border takes the game's colour for its type: Magic, Curse, Disease or Poison. Auras without a type keep the border color." },
        shadowEnabled = { d = false, t = "bool", label = "Icon shadow",
            desc = "The Cooldown Manager's soft shadow frame around the icon art." },
        shadowSize = { d = 1, t = "num", min = 0.1, max = 3, step = 0.05, fmt = "%g",
            label = "Shadow size", dep = { field = "shadowEnabled" } },
        forceHideIcon = { inherit = false, d = false, t = "bool", label = "Hide icon art" },
        customIconFrom = { inherit = false, d = "icon", t = "enum", values = ICON_FROM, labels = ICON_FROM_LABELS,
            label = "Custom icon from" },
        customIcon = { inherit = false, d = 0, t = "id", label = "Custom icon ID" },
        -- Toggled spells (aspects, stances, ranked-realm auras): the icon
        -- copies the art of the action button holding the spell, such as the
        -- active swirl or Auto Shot's bow, so no list of toggles is needed. Off
        -- pins the spell's own art. On by default, unlike most options.
        activeArt = { inherit = false, d = true, t = "bool", kinds = SP, label = "Show active art while toggled on" },
        keepBright = { inherit = false, d = false, t = "bool", kinds = NA, label = "Keep bright" },
        keepBrightAllowDesat = { inherit = false, d = false, t = "bool", kinds = NA, label = "Keep bright: allow desaturation", dep = { field = "keepBright" } },
    } },
    -- A nudge and size that never change the icon's grid cell or drop math: the
    -- frame is offset around its slot center. Size 0 = auto (cell / 36).
    position = { push = true, fields = {
        offsetX = { d = 0, t = "int", min = -50, max = 50, label = "Offset X" },
        offsetY = { d = 0, t = "int", min = -50, max = 50, label = "Offset Y" },
        -- A group member follows its group's icon scale and size until Use
        -- group scale is off; then, and on free icons, these apply (0 = base
        -- size, times the scale). groupOnly: the switch shows only in a group;
        -- unlessFree: the rest always show on a free icon. Shown under
        -- Appearance > Size.
        useGroupScale = { d = true, t = "bool", groupOnly = true, label = "Use group scale" },
        iconScale = { d = 1, t = "num", min = 0.25, max = 4, label = "Icon scale",
            dep = { field = "useGroupScale", value = false, unlessFree = true } },
        iconWidth = { d = 0, t = "int", min = 0, max = 200, label = "Width (0 = auto)",
            dep = { field = "useGroupScale", value = false, unlessFree = true } },
        iconHeight = { d = 0, t = "int", min = 0, max = 200, label = "Height (0 = auto)",
            dep = { field = "useGroupScale", value = false, unlessFree = true } },
        strata = { d = "AUTO", t = "enum",
            values = { "AUTO", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
            label = "Frame strata" },
        frameLevel = { d = 0, t = "int", min = 0, max = 50, label = "Frame level bump" },
    } },
    states = { push = true, inherit = true, fields = {
        readyAlpha    = { d = 1.0,  t = "num", min = 0, max = 1, label = "Ready alpha" },
        -- Not on ammo icons: they never have a cooldown.
        cooldownAlpha = { d = 1.0,  t = "num", min = 0, max = 1, kinds = CD, label = "On cooldown alpha" },
        cooldownDesaturate = { d = true, t = "bool", kinds = CD, label = "Desaturate on cooldown" },
        -- On: duration, stack and label texts stay bright while the icon dims.
        -- Off: they follow the state alpha.
        preserveDurationText = { d = true, t = "bool", label = "Keep texts bright while dimmed" },
        procOverride = { d = false, t = "bool", kinds = SP, label = "Proc overrides dim" },
        -- With the ready alpha at 0, a reactive ability shows only while
        -- usable. Out of range counts as usable; the range tint marks it.
        usableOverride = { d = false, t = "bool", kinds = SP, label = "Usable overrides dim" },
        -- A recharging spell uses the cooldown alpha unless this waits for the
        -- last charge. Desaturation only ever happens at zero charges.
        waitForNoCharges = { d = false, t = "bool", kinds = SP, label = "Wait for no charges" },
        readyGlow = { d = false, t = "bool", kinds = CD, label = "Glow when ready" },
        readyGlowType = { d = "button", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = CD, label = "Glow style", dep = { field = "readyGlow" } },
        readyGlowColor = { d = { 0.95, 0.95, 0.32, 1 }, t = "color", kinds = CD, label = "Glow color", dep = { field = "readyGlow" } },
        readyGlowSpeed = { d = 0.25, t = "num", min = 0.05, max = 1, kinds = CD, label = "Glow speed",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", anyOf = GLOW_SPEED_STYLES } } },
        readyGlowLines = { d = 8, t = "int", min = 1, max = 16, kinds = CD, label = "Glow lines",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "pixel" } } },
        readyGlowThickness = { d = 2, t = "int", min = 1, max = 20, kinds = CD, label = "Glow thickness",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "pixel" } } },
        readyGlowLength = { d = 0, t = "int", min = 0, max = 40, kinds = CD, label = "Glow line length (0 = auto)",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "pixel" } } },
        readyGlowParticles = { d = 4, t = "int", min = 1, max = 16, kinds = CD, label = "Glow particles",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "autocast" } } },
        readyGlowIntensity = { d = 1, t = "num", min = 0.1, max = 1, kinds = CD, label = "Glow intensity",
            dep = { field = "readyGlow" } },
        readyGlowScale = { d = 1, t = "num", min = 0.5, max = 2, kinds = CD, label = "Glow size",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "autocast" } } },
        readyGlowXOffset = { d = 0, t = "int", min = -20, max = 20, kinds = CD, label = "Glow X offset",
            dep = { field = "readyGlow" } },
        readyGlowYOffset = { d = 0, t = "int", min = -20, max = 20, kinds = CD, label = "Glow Y offset",
            dep = { field = "readyGlow" } },
        -- Move shifts the glow without resizing it; the X/Y offsets above grow
        -- or shrink it.
        readyGlowMoveX = { d = 0, t = "int", min = -20, max = 20, kinds = CD, label = "Glow move X",
            dep = { field = "readyGlow" } },
        readyGlowMoveY = { d = 0, t = "int", min = -20, max = 20, kinds = CD, label = "Glow move Y",
            dep = { field = "readyGlow" } },
        readyGlowCombatOnly = { d = false, t = "bool", kinds = CD, label = "Glow only in combat",
            dep = { field = "readyGlow" } },
        readyGlowStrata = { d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = CD, label = "Glow strata",
            dep = { field = "readyGlow" } },
        readyGlowLevel = { d = 7, t = "int", min = 1, max = 30, kinds = CD, label = "Glow frame level",
            dep = { field = "readyGlow" } },
        readyTintEnabled = { d = false, t = "bool", kinds = CD, label = "Ready tint" },
        readyTintColor = { d = { 1, 1, 1, 1 }, t = "color", kinds = CD, label = "Ready tint color", dep = { field = "readyTintEnabled" } },
        cooldownTintEnabled = { d = false, t = "bool", kinds = CD, label = "Cooldown tint" },
        cooldownTintColor = { d = { 0.5, 0.5, 0.5, 1 }, t = "color", kinds = CD, label = "Cooldown tint color", dep = { field = "cooldownTintEnabled" } },
        -- On by default, mirroring Blizzard's own proc overlay.
        procGlow = { d = true, t = "bool", kinds = SP, label = "Proc glow" },
        procGlowType = { d = "proc", t = "enum", values = PROC_GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = SP, label = "Proc glow style", dep = { field = "procGlow" } },
        procGlowColor = { d = { 0.95, 0.95, 0.32, 1 }, t = "color", kinds = SP, label = "Proc glow color", dep = { field = "procGlow" } },
        procGlowSpeed = { d = 0.4, t = "num", min = 0.05, max = 1, kinds = SP, label = "Proc glow speed",
            dep = { { field = "procGlow" }, { field = "procGlowType", anyOf = GLOW_SPEED_STYLES } } },
        procGlowLines = { d = 10, t = "int", min = 1, max = 16, kinds = SP, label = "Proc glow lines",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "pixel" } } },
        procGlowThickness = { d = 2, t = "int", min = 1, max = 20, kinds = SP, label = "Proc glow thickness",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "pixel" } } },
        procGlowLength = { d = 0, t = "int", min = 0, max = 40, kinds = SP, label = "Proc glow line length (0 = auto)",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "pixel" } } },
        procGlowParticles = { d = 4, t = "int", min = 1, max = 16, kinds = SP, label = "Proc glow particles",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "autocast" } } },
        procGlowScale = { d = 1, t = "num", min = 0.5, max = 2, kinds = SP, label = "Proc glow size",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "autocast" } } },
        procGlowIntensity = { d = 1, t = "num", min = 0.1, max = 1, kinds = SP, label = "Proc glow intensity",
            dep = { field = "procGlow" } },
        procGlowXOffset = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow X offset",
            dep = { field = "procGlow" } },
        procGlowYOffset = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow Y offset",
            dep = { field = "procGlow" } },
        procGlowMoveX = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow move X",
            dep = { field = "procGlow" } },
        procGlowMoveY = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow move Y",
            dep = { field = "procGlow" } },
        procGlowStrata = { d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = SP, label = "Proc glow strata",
            dep = { field = "procGlow" } },
        procGlowLevel = { d = 7, t = "int", min = 1, max = 30, kinds = SP, label = "Proc glow frame level",
            dep = { field = "procGlow" } },
        -- On by default, like Blizzard's action buttons.
        usabilityTint = { d = true, t = "bool", kinds = SP, label = "Usability tints" },
        resourceTintColor = { d = { 0.35, 0.45, 1, 1 }, t = "color", kinds = SP, label = "No-resource tint", dep = { field = "usabilityTint" } },
        resourceDesaturate = { d = false, t = "bool", kinds = SP, label = "Desaturate on no resource", dep = { field = "usabilityTint" } },
        unusableTintColor = { d = { 0.45, 0.45, 0.45, 1 }, t = "color", kinds = SP, label = "Unusable tint", dep = { field = "usabilityTint" } },
        unusableDesaturate = { d = false, t = "bool", kinds = SP, label = "Desaturate while unusable", dep = { field = "usabilityTint" } },
        -- A reactive ability is ready nearly always but usable only briefly; at
        -- 0 it shows only while it can be pressed. Applies as the lower of this
        -- and the ready alpha; out of range never dims. The usability flags are
        -- plain on every client (no Secret annotation; action buttons test them
        -- in combat).
        unusableAlpha = { d = 1, t = "num", min = 0, max = 1, kinds = SP, label = "Unusable alpha" },
        resourceAlpha = { d = 1, t = "num", min = 0, max = 1, kinds = SP, label = "No-resource alpha" },
        -- Glows while the spell can be cast now: resources available and no
        -- real cooldown. The GCD does not count: the shadow is fed ignoreGCD.
        usableGlow = { d = false, t = "bool", kinds = SP, label = "Glow when usable" },
        usableGlowType = { d = "button", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = SP, label = "Usable glow style", dep = { field = "usableGlow" } },
        usableGlowColor = { d = { 0.48, 0.85, 0.56, 1 }, t = "color", kinds = SP, label = "Usable glow color", dep = { field = "usableGlow" } },
        usableGlowSpeed = { d = 0.25, t = "num", min = 0.05, max = 1, kinds = SP, label = "Usable glow speed",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", anyOf = GLOW_SPEED_STYLES } } },
        usableGlowLines = { d = 8, t = "int", min = 1, max = 16, kinds = SP, label = "Usable glow lines",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "pixel" } } },
        usableGlowThickness = { d = 2, t = "int", min = 1, max = 20, kinds = SP, label = "Usable glow thickness",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "pixel" } } },
        usableGlowLength = { d = 0, t = "int", min = 0, max = 40, kinds = SP, label = "Usable glow line length (0 = auto)",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "pixel" } } },
        usableGlowParticles = { d = 4, t = "int", min = 1, max = 16, kinds = SP, label = "Usable glow particles",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "autocast" } } },
        usableGlowScale = { d = 1, t = "num", min = 0.5, max = 2, kinds = SP, label = "Usable glow size",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "autocast" } } },
        usableGlowIntensity = { d = 1, t = "num", min = 0.1, max = 1, kinds = SP, label = "Usable glow intensity",
            dep = { field = "usableGlow" } },
        usableGlowXOffset = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow X offset",
            dep = { field = "usableGlow" } },
        usableGlowYOffset = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow Y offset",
            dep = { field = "usableGlow" } },
        usableGlowMoveX = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow move X",
            dep = { field = "usableGlow" } },
        usableGlowMoveY = { d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow move Y",
            dep = { field = "usableGlow" } },
        usableGlowCombatOnly = { d = false, t = "bool", kinds = SP, label = "Usable glow only in combat",
            dep = { field = "usableGlow" } },
        usableGlowStrata = { d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = SP, label = "Usable glow strata",
            dep = { field = "usableGlow" } },
        usableGlowLevel = { d = 7, t = "int", min = 1, max = 30, kinds = SP, label = "Usable glow frame level",
            dep = { field = "usableGlow" } },
        rangeTint = { d = false, t = "bool", kinds = SP, label = "Out-of-range tint" },
        rangeTintColor = { d = { 0.85, 0.2, 0.2, 1 }, t = "color", kinds = SP, label = "Out-of-range color", dep = { field = "rangeTint" } },
    } },
    -- Up to three custom texts per icon, each shown or hidden by state.
    label = { push = true, inherit = true, fields = {
        labelText = { inherit = false, d = "", t = "text", label = "Label text" },
        -- One font for all three labels.
        labelFont = { d = "", t = "text", font = true, label = "Label font",
            dep = { field = "labelText", nonempty = true } },
        labelSize = { d = 12, t = "int", min = 6, max = 32, label = "Label size", dep = { field = "labelText", nonempty = true } },
        labelColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Label color", dep = { field = "labelText", nonempty = true } },
        labelAnchor = { d = "CENTER", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Label anchor", dep = { field = "labelText", nonempty = true } },
        labelX = { d = 0, t = "int", min = -50, max = 50, label = "Label X", dep = { field = "labelText", nonempty = true } },
        labelY = { d = 0, t = "int", min = -50, max = 50, label = "Label Y", dep = { field = "labelText", nonempty = true } },
        labelShowReady = { inherit = false, d = true, t = "bool", kinds = NA, label = "Show label when ready", dep = { field = "labelText", nonempty = true } },
        labelShowCooldown = { inherit = false, d = true, t = "bool", kinds = NA, label = "Show label on cooldown", dep = { field = "labelText", nonempty = true } },
        -- Aura icons: drawn on the engine button, which the game shows exactly
        -- while the aura is up, so it holds in combat with no presence read.
        labelActiveOnly = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show label only while the aura is up", dep = { field = "labelText", nonempty = true } },
        labelText2 = { inherit = false, d = "", t = "text", label = "Label 2 text" },
        labelSize2 = { d = 12, t = "int", min = 6, max = 32, label = "Label 2 size", dep = { field = "labelText2", nonempty = true } },
        labelColor2 = { d = { 1, 1, 1, 1 }, t = "color", label = "Label 2 color", dep = { field = "labelText2", nonempty = true } },
        labelAnchor2 = { d = "TOP", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Label 2 anchor", dep = { field = "labelText2", nonempty = true } },
        labelX2 = { d = 0, t = "int", min = -50, max = 50, label = "Label 2 X", dep = { field = "labelText2", nonempty = true } },
        labelY2 = { d = 0, t = "int", min = -50, max = 50, label = "Label 2 Y", dep = { field = "labelText2", nonempty = true } },
        labelShowReady2 = { inherit = false, d = true, t = "bool", kinds = NA, label = "Show label 2 when ready", dep = { field = "labelText2", nonempty = true } },
        labelShowCooldown2 = { inherit = false, d = true, t = "bool", kinds = NA, label = "Show label 2 on cooldown", dep = { field = "labelText2", nonempty = true } },
        labelActiveOnly2 = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show label 2 only while the aura is up", dep = { field = "labelText2", nonempty = true } },
        labelText3 = { inherit = false, d = "", t = "text", label = "Label 3 text" },
        labelSize3 = { d = 12, t = "int", min = 6, max = 32, label = "Label 3 size", dep = { field = "labelText3", nonempty = true } },
        labelColor3 = { d = { 1, 1, 1, 1 }, t = "color", label = "Label 3 color", dep = { field = "labelText3", nonempty = true } },
        labelAnchor3 = { d = "BOTTOM", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Label 3 anchor", dep = { field = "labelText3", nonempty = true } },
        labelX3 = { d = 0, t = "int", min = -50, max = 50, label = "Label 3 X", dep = { field = "labelText3", nonempty = true } },
        labelY3 = { d = 0, t = "int", min = -50, max = 50, label = "Label 3 Y", dep = { field = "labelText3", nonempty = true } },
        labelShowReady3 = { inherit = false, d = true, t = "bool", kinds = NA, label = "Show label 3 when ready", dep = { field = "labelText3", nonempty = true } },
        labelShowCooldown3 = { inherit = false, d = true, t = "bool", kinds = NA, label = "Show label 3 on cooldown", dep = { field = "labelText3", nonempty = true } },
        labelActiveOnly3 = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show label 3 only while the aura is up", dep = { field = "labelText3", nonempty = true } },
    } },
    -- Transition sounds. A sound cannot be unplayed, so the driver fires only
    -- on verified transitions. Each trigger is a toggle plus a t = "sound"
    -- field: a name from NS.Sounds, or "" for none.
    alerts = { push = true, kinds = USE, fields = {
        soundChannel = { d = "Master", t = "enum", values = { "Master", "SFX", "Music", "Ambience", "Dialog" },
            labels = { Master = "Master (ignores the other sliders)", SFX = "Sound Effects", Music = "Music", Ambience = "Ambience", Dialog = "Dialog" },
            label = "Sound channel" },
        readySoundEnabled = { d = false, t = "bool", label = "Play a sound when ready" },
        readySound = { d = "", t = "sound", label = "Ready sound", dep = { field = "readySoundEnabled" } },
        -- From shadow edges, never secret numbers: cooldown start, recharge
        -- start, and a charge returning while the spell stays castable.
        cooldownSoundEnabled = { d = false, t = "bool", label = "Play a sound when the cooldown starts" },
        cooldownSound = { d = "", t = "sound", label = "Cooldown-start sound", dep = { field = "cooldownSoundEnabled" } },
        rechargeSoundEnabled = { d = false, t = "bool", kinds = SP, label = "Play a sound when recharging starts" },
        rechargeSound = { d = "", t = "sound", kinds = SP, label = "Recharge-start sound", dep = { field = "rechargeSoundEnabled" } },
        chargeGainedSoundEnabled = { d = false, t = "bool", kinds = SP, label = "Play a sound when a charge returns" },
        chargeGainedSound = { d = "", t = "sound", kinds = SP, label = "Charge-gained sound", dep = { field = "chargeGainedSoundEnabled" } },
    } },
    -- The key bound to the spell's action button, found by walking the bars.
    -- Factory.KeybindEnabled shows it when this switch or the group's is on.
    keybind = { push = true, inherit = true, kinds = { spell = true, timer = true }, fields = {
        keybindEnabled = { d = false, t = "bool", label = "Show keybind" },
        -- Ranked realms: the bar often holds another rank of the tracked spell,
        -- an unrelated ID with the same name, so bindings match by name too. On
        -- by default on Forever; retail has no ranks and hides the row.
        keybindByName = { d = NS.IsForever == true, t = "bool", foreverOnly = true,
            label = "Match by spell name (ranks)", dep = { field = "keybindEnabled" } },
        keybindSize = { d = 12, t = "int", min = 6, max = 32, label = "Keybind size", dep = { field = "keybindEnabled" } },
        keybindFont = { d = "", t = "text", font = true, label = "Keybind font", dep = { field = "keybindEnabled" } },
        keybindColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Keybind color", dep = { field = "keybindEnabled" } },
        keybindAnchor = { d = "TOPLEFT", t = "enum",
            values = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
            label = "Keybind anchor", dep = { field = "keybindEnabled" } },
        keybindX = { d = 2, t = "int", min = -50, max = 50, label = "Keybind X", dep = { field = "keybindEnabled" } },
        keybindY = { d = -2, t = "int", min = -50, max = 50, label = "Keybind Y", dep = { field = "keybindEnabled" } },
    } },
    -- Things that run out: an item's bag count, the quiver. Counts are compared
    -- only when plain; a secret count keeps the last known state.
    outOfStock = { push = true, inherit = true, kinds = { item = true, trinket = true, ammo = true }, fields = {
        outDesaturate = { d = true, t = "bool", kinds = { item = true, ammo = true }, label = "Desaturate when out of stock" },
        outAlphaEnabled = { d = false, t = "bool", kinds = { item = true, ammo = true }, label = "Out-of-stock alpha" },
        outAlpha = { d = 0.4, t = "num", min = 0, max = 1, kinds = { item = true, ammo = true }, label = "Out-of-stock alpha value", dep = { field = "outAlphaEnabled" } },
        -- Hide instead of dimming. An item is missing when its guarded bag
        -- count is empty, a trinket when nothing is equipped in its slot.
        hideWhenMissing = { d = false, t = "bool", label = "Hide when missing" },
    } },
    -- A trinket slot that shows only on-use trinkets: a passive one (no use
    -- spell) hides and gives up its cell in a dynamic group, as a missing one.
    trinket = { push = true, kinds = { trinket = true }, fields = {
        onlyOnUse = { d = false, t = "bool", label = "Only on-use trinkets (hide passive ones)" },
    } },
    -- A totem's pulse: a bar under the art that refills at every pulse,
    -- counted from when the totem went down (NS.DriverTotem).
    pulse = { push = true, inherit = true, kinds = { totem = true }, fields = {
        pulseShow = { d = false, t = "bool", label = "Show the pulse timer" },
        -- 0 takes the totem's own pulse, for the totems that pulse.
        pulseInterval = { d = 0, t = "num", min = 0, max = 10, step = 0.5, fmt = "%.1f",
            label = "Seconds between pulses (0 = the totem's own)", dep = { field = "pulseShow" } },
        pulseColor = { d = { 1, 0.82, 0.2, 1 }, t = "color", label = "Pulse bar color",
            dep = { field = "pulseShow" } },
        pulseHeight = { d = 3, t = "int", min = 2, max = 10, label = "Pulse bar height",
            dep = { field = "pulseShow" } },
    } },
    -- Mouse tiers: icon, group, layout, then the two addon settings. "inherit"
    -- defers to the tier above; "on" and "off" override it.
    mouse = { push = true, fields = {
        clickThrough = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Click-through" },
        showTooltip = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Show tooltip" },
    } },
    -- Anchoring (Core\AD_Anchor.lua), free icons only: a group member's cell
    -- places it. The target fields are hidden: the Anchor tab draws its own
    -- rows. Matching a target's width would stretch the icon, so those rows
    -- are hidden too.
    anchor = { fields = {
        anchorEnabled = { d = false, t = "bool", hidden = true, label = "Anchor this icon" },
        anchorTargetKind = { d = "group", t = "enum", values = { "group", "bar", "layout", "frame", "mouse" },
            hidden = true, label = "Anchor to", dep = { field = "anchorEnabled" } },
        anchorTargetId = { d = 0, t = "id", hidden = true, label = "Anchor target id" },
        anchorTargetFrame = { d = "", t = "text", hidden = true, label = "Anchor frame name" },
        anchorSrcPoint = { d = "TOP", t = "enum", values = POINTS,
            label = "My point", dep = { field = "anchorEnabled" } },
        -- The cursor is a point, so there is no target point to pick.
        anchorDstPoint = { d = "BOTTOM", t = "enum", values = POINTS,
            label = "Target point",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "mouse" } } },
        anchorOffsetX = { d = 0, t = "int", min = -400, max = 400,
            label = "Anchor offset X", dep = { field = "anchorEnabled" } },
        anchorOffsetY = { d = 0, t = "int", min = -400, max = 400,
            label = "Anchor offset Y", dep = { field = "anchorEnabled" } },
        anchorMatchWidth = { d = false, t = "bool", hidden = true, label = "Match target width" },
        anchorMatchWidthAdjust = { d = 0, t = "int", min = -200, max = 200, hidden = true,
            label = "Match width adjust" },
    } },
    swipe = { push = true, inherit = true, kinds = CD, fields = {
        showSwipe = { d = true,  t = "bool", label = "Cooldown swipe" },
        gcdSwipe = { d = "hidden", t = "enum", values = GCD_LOOKS, labels = GCD_LOOK_LABELS,
            kinds = { spell = true }, label = "GCD" },
        gcdSwipeColor = { d = { 0, 0, 0, 0.5 }, t = "color", kinds = { spell = true },
            label = "GCD swipe color", dep = { field = "gcdSwipe", anyOf = GCD_SWIPE_DRAWN } },
        wandSwipe = { d = "hidden", t = "enum", values = GCD_LOOKS, labels = GCD_LOOK_LABELS,
            kinds = { spell = true }, classOnly = WAND_CLASSES, label = "Wand GCD" },
        wandSwipeColor = { d = { 0, 0, 0, 0.5 }, t = "color", kinds = { spell = true },
            classOnly = WAND_CLASSES, label = "Wand swipe color",
            dep = { field = "wandSwipe", anyOf = GCD_SWIPE_DRAWN } },
        -- While a charge spell still has a charge (recharging), these two hold
        -- back the dark fill or the edge until every charge is spent.
        swipeWaitForNoCharges = { d = false, t = "bool", kinds = { spell = true }, label = "Swipe only when no charges", dep = { field = "showSwipe" } },
        showEdge  = { d = true,  t = "bool", label = "Swipe edge" },
        edgeWaitForNoCharges = { d = false, t = "bool", kinds = { spell = true }, label = "Edge only when no charges", dep = { field = "showEdge" } },
        showBling = { d = true,  t = "bool", label = "Finish flash" },
        reverse   = { d = false, t = "bool", label = "Reverse swipe", dep = { field = "showSwipe" } },
        swipeColor = { d = { 0, 0, 0, 0.8 }, t = "color", label = "Swipe color", dep = { field = "showSwipe" } },
        -- 1.8 matches the Cooldown Manager's edge. CooldownFrameTemplate's own
        -- 1.0 draws a stubby line that stops short of the icon corner.
        edgeScale = { d = 1.8, t = "num", min = 0.1, max = 3, label = "Edge scale", dep = { field = "showEdge" } },
        edgeColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Edge color", dep = { field = "showEdge" } },
        swipeInset = { d = 0, t = "int", min = -20, max = 40, label = "Swipe inset",
            dep = { { field = "showSwipe" }, { field = "separateInsets", value = false } } },
        separateInsets = { d = false, t = "bool", label = "Separate inset W/H", dep = { field = "showSwipe" } },
        swipeInsetX = { d = 0, t = "int", min = -20, max = 40, label = "Swipe inset W",
            dep = { { field = "showSwipe" }, { field = "separateInsets" } } },
        swipeInsetY = { d = 0, t = "int", min = -20, max = 40, label = "Swipe inset H",
            dep = { { field = "showSwipe" }, { field = "separateInsets" } } },
    } },
    auraMissing = { push = true, inherit = true, kinds = AU, fields = {
        showWhileMissing = { d = true, t = "bool", label = "Show while missing" },
        -- Art while missing: 0 falls back to Appearance's Custom icon, then the
        -- first tracked spell's art.
        missingIconFrom = { inherit = false, d = "icon", t = "enum", values = ICON_FROM, labels = ICON_FROM_LABELS,
            label = "Missing icon from", dep = { field = "showWhileMissing" } },
        missingIcon = { inherit = false, d = 0, t = "id", label = "Missing icon ID", dep = { field = "showWhileMissing" } },
        missingDesaturate = { d = true, t = "bool", label = "Desaturate while missing", dep = { field = "showWhileMissing" } },
        -- The default missing look is the desaturated art at full opacity.
        missingAlpha = { d = 1, t = "num", min = 0, max = 1, label = "Missing alpha", dep = { field = "showWhileMissing" } },
        -- The aura twin of states.preserveDurationText (aura icons have no
        -- States tab). On by default: the missing dim touches only the art.
        missingPreserveText = { d = true, t = "bool", label = "Keep texts bright while missing", dep = { field = "showWhileMissing" } },
    } },
    -- The look while the aura is up, drawn on the engine button the game shows
    -- exactly then, so it works in combat with no presence read. That button is
    -- locked in combat (and in instances): the glow is textures and engine
    -- animations, and a glow gate moves it onto a button of its own (DriverAura).
    -- A spell icon with "Aura on this icon" on draws this on its own button.
    auraActive = { push = true, inherit = true, kinds = AA, fields = {
        -- On a spell icon the button wears the spell's art by default, reading
        -- as one icon changing phase, as in the Cooldown Manager; Active icon
        -- below overrides both.
        overlayArt = { d = "spell", t = "enum", values = { "spell", "aura" }, kinds = SP,
            labels = { spell = "This spell's icon", aura = "The aura's icon" },
            label = "Icon while the aura is up" },
        -- Greys the cooldown under a spell icon's aura button for good. The
        -- button covers it while the aura is up, so it reads grey exactly while
        -- the aura is down. It wins over every other desaturation.
        overlayDesatInactive = { d = false, t = "bool", kinds = SP,
            label = "Desaturate while the aura is down" },
        -- 0 falls back to Appearance's Custom icon, then the aura's art. It is
        -- our texture on the engine button, so it holds in combat.
        activeIconFrom = { inherit = false, d = "icon", t = "enum", values = ICON_FROM, labels = ICON_FROM_LABELS,
            label = "Active icon from" },
        activeIcon = { inherit = false, d = 0, t = "id", label = "Active icon ID" },
        activeAlpha = { d = 1.0, t = "num", min = 0, max = 1, label = "Active alpha" },
        activeDesaturate = { d = false, t = "bool", label = "Desaturate while active" },
        activeTintEnabled = { d = false, t = "bool", label = "Active tint" },
        activeTintColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Active tint color", dep = { field = "activeTintEnabled" } },
        activeGlow = { d = false, t = "bool", label = "Glow while active" },
        -- The gates need the icon's own button (DriverAura.GlowLaneOK), never a
        -- Dynamic aura group's rows. The pick is one of the icon's spells, its
        -- ranks by name; 0 = any of them.
        activeGlowFor = { inherit = false, d = 0, t = "id", auraSpellPick = true,
            kinds = AU, label = "Glow for",
            showIf = function(rec)
                local DA = NS.DriverAura
                return DA ~= nil and DA.GlowLaneOK(rec) and #DA.GlowSpellGroups(rec.driver) > 1
            end,
            desc = "Any of the icon's spells, or only one of them (its ranks together). Works in combat.",
            dep = { field = "activeGlow" } },
        activeGlowCombatOnly = { d = false, t = "bool", kinds = AU,
            label = "Glow only in combat",
            showIf = function(rec)
                local DA = NS.DriverAura
                return DA ~= nil and DA.GlowLaneOK(rec)
            end,
            desc = "The glow waits for combat; out of combat the icon shows without it.",
            dep = { field = "activeGlow" } },
        -- Engine-driven, no reads: always while the aura is up, or under a
        -- time-left threshold, gated by a hidden duration bar the engine fills.
        -- Forever keeps no leftover time on a refresh, so the game opens no
        -- pandemic window: a saved "pandemic" draws the last 30%, and the list
        -- no longer offers it.
        activeGlowWhen = { d = "always", t = "enum", values = { "always", "pandemic", "time" },
            labels = { always = "The whole time", pandemic = "In the last 30%",
                time = "When little time is left" },
            valueIf = { pandemic = function() return false end },
            desc = "The whole time: while the aura is up. When little time is left: once the time left drops under the amount below. Both work in combat.",
            label = "Glow when", dep = { field = "activeGlow" } },
        -- Percent is exact for any aura; seconds need the aura's length typed
        -- in, as the engine's bar runs over a duration addons cannot read.
        activeGlowTimeUnit = { d = "pct", t = "enum", values = { "pct", "sec" },
            labels = { pct = "Percent of the aura", sec = "Seconds" },
            label = "Time left in", dep = { { field = "activeGlow" }, { field = "activeGlowWhen", value = "time" } } },
        activeGlowTimePct = { d = 30, t = "int", min = 1, max = 99, label = "Glow under this % left",
            dep = { { field = "activeGlow" }, { field = "activeGlowWhen", value = "time" },
                { field = "activeGlowTimeUnit", value = "pct" } } },
        activeGlowTimeSec = { d = 5, t = "num", min = 0.5, max = 120, step = 0.5, fmt = "%g",
            label = "Glow under this many seconds left",
            dep = { { field = "activeGlow" }, { field = "activeGlowWhen", value = "time" },
                { field = "activeGlowTimeUnit", value = "sec" } } },
        activeGlowAuraLength = { d = 0, t = "int", min = 0, max = 600, label = "The aura lasts (seconds)",
            desc = "The aura's full length. The game keeps the real length from addons, so a threshold in seconds needs it; percent does not. 0 = not set: the glow shows the whole time.",
            dep = { { field = "activeGlow" }, { field = "activeGlowWhen", value = "time" },
                { field = "activeGlowTimeUnit", value = "sec" } } },
        activeGlowType = { d = "button", t = "enum", values = AURA_GLOW_STYLES, labels = GLOW_STYLE_LABELS, label = "Active glow style", dep = { field = "activeGlow" } },
        activeGlowColor = { d = { 0.95, 0.95, 0.32, 1 }, t = "color", label = "Active glow color", dep = { field = "activeGlow" } },
        activeGlowSpeed = { d = 0.25, t = "num", min = 0.05, max = 1, label = "Active glow speed",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", anyOf = GLOW_SPEED_STYLES } } },
        activeGlowLines = { d = 8, t = "int", min = 1, max = 16, label = "Active glow lines",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "pixel" } } },
        activeGlowThickness = { d = 2, t = "int", min = 1, max = 20, label = "Active glow thickness",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "pixel" } } },
        -- On the live button this picks one of the dash texture's 8 bands.
        activeGlowLength = { d = 0, t = "int", min = 0, max = 40, label = "Active glow line length (0 = auto)",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "pixel" } } },
        activeGlowParticles = { d = 4, t = "int", min = 1, max = 16, label = "Active glow particles",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "autocast" } } },
        activeGlowIntensity = { d = 1, t = "num", min = 0.1, max = 1, label = "Active glow intensity",
            dep = { field = "activeGlow" } },
        activeGlowScale = { d = 1, t = "num", min = 0.5, max = 2, label = "Active glow size",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "autocast" } } },
        activeGlowXOffset = { d = 0, t = "int", min = -20, max = 20, label = "Active glow X offset",
            dep = { field = "activeGlow" } },
        activeGlowYOffset = { d = 0, t = "int", min = -20, max = 20, label = "Active glow Y offset",
            dep = { field = "activeGlow" } },
        activeGlowMoveX = { d = 0, t = "int", min = -20, max = 20, label = "Active glow move X",
            dep = { field = "activeGlow" } },
        activeGlowMoveY = { d = 0, t = "int", min = -20, max = 20, label = "Active glow move Y",
            dep = { field = "activeGlow" } },
        activeGlowStrata = { d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, label = "Active glow strata",
            dep = { field = "activeGlow" } },
        activeGlowLevel = { d = 7, t = "int", min = 1, max = 30, label = "Active glow frame level",
            dep = { field = "activeGlow" } },
    } },
    -- The engine button's swipe is our own Cooldown widget, so its look is
    -- plain writes; spell icons with the aura overlay use it too.
    auraSwipe = { push = true, inherit = true, kinds = AA, fields = {
        swipeShow = { d = true, t = "bool", label = "Aura swipe" },
        -- Colour and direction default per kind (two fields, one label): aura
        -- icons get the reversed dark swipe, a spell's aura phase the Cooldown
        -- Manager's unreversed gold (CooldownViewerConstants.ITEM_AURA_COLOR).
        swipeColor = { d = { 0, 0, 0, 0.8 }, t = "color", kinds = AU, label = "Aura swipe color", dep = { field = "swipeShow" } },
        overlaySwipeColor = { d = { 1, 0.95, 0.57, 0.7 }, t = "color", kinds = SP, label = "Aura swipe color",
            dep = { field = "swipeShow" } },
        swipeReverse = { d = true, t = "bool", kinds = AU, label = "Reverse aura swipe", dep = { field = "swipeShow" } },
        overlaySwipeReverse = { d = false, t = "bool", kinds = SP, label = "Reverse aura swipe",
            dep = { field = "swipeShow" } },
        swipeEdge = { d = false, t = "bool", label = "Aura swipe edge" },
        -- As on the cooldown swipe: 1.8 is the Cooldown Manager's edge length.
        edgeColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Aura edge color", dep = { field = "swipeEdge" } },
        edgeScale = { d = 1.8, t = "num", min = 0.1, max = 3, label = "Aura edge scale", dep = { field = "swipeEdge" } },
        swipeBling = { d = false, t = "bool", label = "Aura finish flash" },
    } },
    text = { push = true, inherit = true, fields = {
        durationText = { d = true, t = "bool", label = "Duration text" },
        -- "global" follows Settings > Timers.
        durationRounding = { d = "global", t = "enum", values = { "global", "up", "down" },
            labels = { global = "Same as Settings", up = "Round up", down = "Round down" },
            label = "Round timer numbers", dep = { field = "durationText" } },
        durationSize = { d = 14, t = "int", min = 6, max = 32, label = "Duration text size", dep = { field = "durationText" } },
        durationColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Duration text color", dep = { field = "durationText" } },
        -- A baked NumericRuleFormatter renders the countdown from the real
        -- remaining time, so it works on secret durations with no ticker. M:SS
        -- ("1:30") from 60 s up to this many seconds, "12 m" above; 0 = off.
        durationAbbrev = { d = 600, t = "enum", values = ABBREV_VALUES, labels = ABBREV_LABELS,
            label = "Minutes and seconds (1:30)", dep = { field = "durationText" } },
        durationShadow = { d = false, t = "bool", label = "Duration text shadow", dep = { field = "durationText" } },
        durationDecimals = { d = false, t = "bool", label = "Decimal seconds", dep = { field = "durationText" } },
        durationDecimalThreshold = { d = 10, t = "int", min = 2, max = 60, label = "Decimals under (seconds)",
            dep = { { field = "durationText" }, { field = "durationDecimals" } } },
        durationOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" },
            label = "Duration text outline", dep = { field = "durationText" } },
        durationFont = { d = "", t = "text", font = true, label = "Duration text font", dep = { field = "durationText" } },
        durationAnchor = { d = "CENTER", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Duration text anchor", dep = { field = "durationText" } },
        durationX = { d = 0, t = "int", min = -50, max = 50, label = "Duration text X", dep = { field = "durationText" } },
        durationY = { d = 0, t = "int", min = -50, max = 50, label = "Duration text Y", dep = { field = "durationText" } },
        -- Whether a charge is left comes from the shadow.
        hideDurWithCharges = { d = false, t = "bool", kinds = SP, label = "Hide duration while charges remain",
            dep = { field = "durationText" } },
        -- Bands bake into the countdown formatter as color escapes, so the
        -- engine colors the text from the real remaining time. A band colors
        -- values under its seconds (0 = off); above them, the plain color.
        durationColorBands = { d = false, t = "bool", label = "Color by remaining time",
            dep = { field = "durationText" } },
        durBand1Sec = { d = 5, t = "int", min = 0, max = 3600, label = "Band 1: under (seconds)",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        durBand1Color = { d = { 0.9, 0.15, 0.15, 1 }, t = "color", label = "Band 1 color",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        durBand2Sec = { d = 60, t = "int", min = 0, max = 3600, label = "Band 2: under (seconds)",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        durBand2Color = { d = { 0.95, 0.75, 0.2, 1 }, t = "color", label = "Band 2 color",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        durBand3Sec = { d = 0, t = "int", min = 0, max = 3600, label = "Band 3: under (seconds)",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        durBand3Color = { d = { 1, 1, 1, 1 }, t = "color", label = "Band 3 color",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        stackText = { d = true, t = "bool", kinds = STK, label = "Stack text" },
        stackSize = { d = 14, t = "int", min = 6, max = 32, kinds = STK, label = "Stack text size", dep = { field = "stackText" } },
        stackColor = { d = { 1, 1, 1, 1 }, t = "color", kinds = STK, label = "Stack text color", dep = { field = "stackText" } },
        stackOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = STK, label = "Stack text outline", dep = { field = "stackText" } },
        stackFont = { d = "", t = "text", font = true, kinds = STK, label = "Stack text font", dep = { field = "stackText" } },
        stackAnchor = { d = "BOTTOMRIGHT", t = "enum",
            values = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "TOP", "BOTTOM", "CENTER" },
            kinds = STK, label = "Stack text anchor", dep = { field = "stackText" } },
        stackX = { d = -2, t = "int", min = -50, max = 50, kinds = STK, label = "Stack text X", dep = { field = "stackText" } },
        stackY = { d = 2, t = "int", min = -50, max = 50, kinds = STK, label = "Stack text Y", dep = { field = "stackText" } },
        stackShadow = { d = false, t = "bool", kinds = STK, label = "Stack text shadow", dep = { field = "stackText" } },
        hideChargeAtZero = { d = false, t = "bool", kinds = SP, label = "Hide charge count at zero", dep = { field = "stackText" } },
        -- The engine prints an aura's count only above 1 unless it is handed a
        -- NumericRuleFormatter. The same formatter carries a color escape per
        -- breakpoint, so the count stays secret and the engine colors it.
        stackShowSingle = { d = false, t = "bool", kinds = AU, label = "Show count at 1 stack", dep = { field = "stackText" } },
        stackColorBands = { inherit = false, d = false, t = "bool", kinds = AU, label = "Color by stack count", dep = { field = "stackText" } },
        stkBand1Min = { inherit = false, d = 1, t = "int", min = 1, max = 50, kinds = AU, label = "Band 1: from (stacks)",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        stkBand1Color = { inherit = false, d = { 1, 1, 1, 1 }, t = "color", kinds = AU, label = "Band 1 color",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        stkBand2Min = { inherit = false, d = 3, t = "int", min = 1, max = 50, kinds = AU, label = "Band 2: from (stacks)",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        stkBand2Color = { inherit = false, d = { 0.48, 0.85, 0.56, 1 }, t = "color", kinds = AU, label = "Band 2 color",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        stkBand3Min = { inherit = false, d = 6, t = "int", min = 1, max = 50, kinds = AU, label = "Band 3: from (stacks)",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        stkBand3Color = { inherit = false, d = { 0.9, 0.15, 0.15, 1 }, t = "color", kinds = AU, label = "Band 3 color",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        -- The equipped ammo count on a spell icon, styled apart from the stack
        -- text: a charge spell can show both, hence the opposite corner. The
        -- count is plain in combat (no secrecy annotation; Blizzard's item
        -- buttons compare it).
        ammoText = { d = false, t = "bool", kinds = SP, label = "Ammo stack text" },
        ammoSize = { d = 14, t = "int", min = 6, max = 32, kinds = SP, label = "Ammo text size", dep = { field = "ammoText" } },
        ammoColor = { d = { 1, 1, 1, 1 }, t = "color", kinds = SP, label = "Ammo text color", dep = { field = "ammoText" } },
        ammoOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = SP, label = "Ammo text outline", dep = { field = "ammoText" } },
        ammoFont = { d = "", t = "text", font = true, kinds = SP, label = "Ammo text font", dep = { field = "ammoText" } },
        ammoAnchor = { d = "BOTTOMLEFT", t = "enum",
            values = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "TOP", "BOTTOM", "CENTER" },
            kinds = SP, label = "Ammo text anchor", dep = { field = "ammoText" } },
        ammoX = { d = 2, t = "int", min = -50, max = 50, kinds = SP, label = "Ammo text X", dep = { field = "ammoText" } },
        ammoY = { d = 2, t = "int", min = -50, max = 50, kinds = SP, label = "Ammo text Y", dep = { field = "ammoText" } },
        ammoShadow = { d = false, t = "bool", kinds = SP, label = "Ammo text shadow", dep = { field = "ammoText" } },
    } },
    -- Not schema sections: the driver (rec.driver, validated per kind by the
    -- driver module; retargeting re-keys it, never the record id) and
    -- conditions (rec.c, Core\AD_Conditions.lua). Neither is pushable.
}

-- Glows 2 to 4 on an aura icon: glow 1's fields again, numbered and per icon
-- (a layout's looks carry glow 1 only). Each rides its own glow lane
-- (DriverAura), so each needs the icon's own button.
Schema.AURA_GLOW_SLOTS = 4
Schema.AURA_GLOW_FIELDS = {
    "activeGlow", "activeGlowFor", "activeGlowCombatOnly",
    "activeGlowWhen", "activeGlowTimeUnit", "activeGlowTimePct",
    "activeGlowTimeSec", "activeGlowAuraLength",
    "activeGlowType", "activeGlowColor", "activeGlowSpeed",
    "activeGlowLines", "activeGlowThickness", "activeGlowLength", "activeGlowParticles",
    "activeGlowIntensity", "activeGlowScale",
    "activeGlowXOffset", "activeGlowYOffset", "activeGlowMoveX", "activeGlowMoveY",
    "activeGlowStrata", "activeGlowLevel",
}
do
    local fields = Schema.icon.auraActive.fields
    local isGlow = {}
    for _, name in ipairs(Schema.AURA_GLOW_FIELDS) do isGlow[name] = true end
    local function laneOK(rec)
        local DA = NS.DriverAura
        return DA ~= nil and DA.GlowLaneOK(rec)
    end
    local function copy(v)
        if type(v) ~= "table" then return v end
        local t = {}
        for k, x in pairs(v) do t[k] = copy(x) end
        return t
    end
    for k = 2, Schema.AURA_GLOW_SLOTS do
        local suf = tostring(k)
        -- a dep names this glow's own field
        local function own(d)
            local t = copy(d)
            if isGlow[t.field] then t.field = t.field .. suf end
            return t
        end
        for _, name in ipairs(Schema.AURA_GLOW_FIELDS) do
            local src = fields[name]
            local def = {}
            for key, v in pairs(src) do def[key] = v end
            def.d = copy(src.d)
            def.inherit = false
            def.kinds = AU
            local lbl = src.label or name
            local numbered = lbl:gsub("^Active glow", "Glow " .. suf, 1)
            if numbered == lbl then numbered = lbl:gsub("^Glow ", "Glow " .. suf .. " ", 1) end
            def.label = numbered
            if src.dep and src.dep.field then
                def.dep = own(src.dep)
            elseif src.dep then
                def.dep = {}
                for i, d in ipairs(src.dep) do def.dep[i] = own(d) end
            end
            def.showIf = src.showIf or laneOK
            fields[name .. suf] = def
        end
    end
end

Schema.iconGroup = {
    arrangement = { push = true, inherit = true, fields = {
        -- Rows is cooldown-only: the aura flow wraps by itself. Columns and the
        -- two growth fields drive the aura flow too.
        rows = { inherit = false, d = 1, t = "int", min = 1, max = 20, kinds = GK_CD, label = "Rows" },
        cols = { inherit = false, d = 6, t = "int", min = 1, max = 20, label = "Columns" },
        -- iconSize is a scale in 36ths (36 = 100%) over the base width/height.
        iconSize = { d = 36, t = "int", min = 16, max = 128, label = "Icon scale" },
        iconWidth = { d = 36, t = "int", min = 8, max = 128, label = "Icon width" },
        iconHeight = { d = 36, t = "int", min = 8, max = 128, label = "Icon height" },
        spacing = { d = 2, t = "int", min = -20, max = 50, label = "Spacing" },
        separateSpacing = { d = false, t = "bool", label = "Separate X/Y spacing" },
        spacingX = { d = 2, t = "int", min = -20, max = 50, label = "Spacing X" },
        spacingY = { d = 2, t = "int", min = -20, max = 50, label = "Spacing Y" },
        growthH = { d = "RIGHT", t = "enum", values = { "RIGHT", "LEFT" }, label = "Fill direction" },
        growthV = { d = "DOWN", t = "enum", values = { "DOWN", "UP" }, label = "Row growth" },
        lockGridSize = { inherit = false, d = false, t = "bool", kinds = GK_CD, label = "Lock grid size" },
        containerPadding = { d = 0, t = "int", min = -6, max = 12, label = "Container padding" },
        -- Panel closed, a dynamic group compacts; open, each icon returns to
        -- its cell for dragging (gpos is its identity). On an aura group it
        -- switches live view: on packs the engine rows with auras that are up,
        -- off keeps a static grid. The other dynamic fields are cooldown-only.
        dynamicLayout = { inherit = false, d = false, t = "bool", label = "Dynamic: compact icons" },
        -- Shape-aware: one row offers left/center/right, one column
        -- top/center/bottom, a grid six gravity modes. Remapped per shape at
        -- read time (LayoutEngine.EffectiveAlignment); hidden, since a bespoke
        -- dropdown draws it.
        alignment = { inherit = false, d = "center", t = "enum", hidden = true,
            values = { "left", "center", "right", "top", "bottom", "center_h", "center_v" },
            label = "Alignment" },
        -- Which icons give up their cells with the panel closed: ready ones (a
        -- totem shows only while down), ones on cooldown, or ones at state
        -- opacity 0. Aura icons stay: their presence cannot be read in combat.
        dynamicCollapse = { inherit = false, d = "none", t = "enum", kinds = GK_CD,
            values = { "none", "ready", "cooldown", "hidden" },
            labels = { none = "Never", ready = "They are ready",
                cooldown = "They are on cooldown", hidden = "Their opacity is 0" },
            label = "Icons drop out when", dep = { field = "dynamicLayout" } },
        dynamicOrder = { inherit = false, d = "priority", t = "enum", values = { "priority", "fcfs" }, kinds = GK_CD,
            labels = { priority = "Priority (cell order)", fcfs = "First come, first served" },
            label = "Icon order", dep = { { field = "dynamicLayout" },
                { field = "dynamicCollapse", notValue = "none" } } },
        dynamicShrink = { d = false, t = "bool", kinds = GK_CD,
            label = "Shrink container to content", dep = { field = "dynamicLayout" } },
        smoothMovement = { d = false, t = "bool", kinds = GK_CD,
            label = "Smooth movement", dep = { field = "dynamicLayout" } },
        -- Seconds. fmt keeps the generic slider from showing 0..1 as a percent.
        smoothDuration = { d = 0.18, t = "num", min = 0.05, max = 0.4, kinds = GK_CD,
            label = "Smooth duration (s)", fmt = "%.2f",
            dep = { { field = "dynamicLayout" }, { field = "smoothMovement" } } },
    } },
    look = { push = true, inherit = true, fields = {
        showBorder = { d = false, t = "bool", label = "Container border" },
        showBackground = { d = false, t = "bool", label = "Container background" },
        borderColor = { d = { 0.11, 0.16, 0.25, 1 }, t = "color", label = "Border color" },
        bgColor = { d = { 0, 0, 0, 0.6 }, t = "color", label = "Background color" },
    } },
    -- Keybind text on every member, ORed with each icon's own switch (styling
    -- stays on the icon). Cooldown groups only: auras have no binding.
    keybind = { push = true, inherit = true, kinds = GK_CD, fields = {
        showKeybinds = { d = false, t = "bool", label = "Show keybinds on all icons" },
    } },
    frame = { fields = {
        strata = { d = "MEDIUM", t = "enum",
            values = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }, label = "Frame strata" },
        level = { d = 1, t = "int", min = 1, max = 100, label = "Frame level" },
    } },
    -- Anchoring (Core\AD_Anchor.lua). Dragging an anchored group edits the
    -- offsets; pos is never written while anchored. The target fields are
    -- hidden: the Anchoring tab draws its own rows.
    anchor = { fields = {
        anchorEnabled = { d = false, t = "bool", hidden = true, label = "Anchor this group" },
        anchorTargetKind = { d = "group", t = "enum", values = { "group", "bar", "layout", "frame", "mouse" },
            hidden = true, label = "Anchor to", dep = { field = "anchorEnabled" } },
        anchorTargetId = { d = 0, t = "id", hidden = true, label = "Anchor target id" },
        anchorTargetFrame = { d = "", t = "text", hidden = true, label = "Anchor frame name" },
        anchorSrcPoint = { d = "TOP", t = "enum", values = POINTS,
            label = "My point", dep = { field = "anchorEnabled" } },
        -- The cursor is a point, so there is no target point to pick.
        anchorDstPoint = { d = "BOTTOM", t = "enum", values = POINTS,
            label = "Target point",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "mouse" } } },
        anchorOffsetX = { d = 0, t = "int", min = -400, max = 400,
            label = "Anchor offset X", dep = { field = "anchorEnabled" } },
        anchorOffsetY = { d = 0, t = "int", min = -400, max = 400,
            label = "Anchor offset Y", dep = { field = "anchorEnabled" } },
        anchorMatchWidth = { d = false, t = "bool", label = "Match target width",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "mouse" } } },
        anchorMatchWidthAdjust = { d = 0, t = "int", min = -200, max = 200,
            label = "Match width adjust",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "mouse" },
                { field = "anchorMatchWidth" } } },
    } },
    -- Mouse tier for the group's icons ("inherit": the layout, then Settings).
    mouse = { push = true, fields = {
        clickThrough = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Click-through" },
        showTooltip = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Show tooltips" },
    } },
}

-- Bars: layout children with a free position, never group members. A bar joins
-- a group by anchoring to it, so the group is an anchor field, not a parent.
-- This table is the only source of bar defaults.

local BK_CD   = { cooldown = true }
local BK_CDTM = { cooldown = true, timer = true }
-- Plus aura duration bars (the section's kindModes keeps aura stack bars out).
local BK_CDTMA = { cooldown = true, timer = true, aura = true }
-- Text runs go only to kinds something writes them for (checked against the
-- writers in Bars\AD_Bars.lua). Duration: cooldown (its Cooldown widget), aura
-- (engine SetDurationText), timer and swing (RunTimedFill). Stack: cooldown
-- (charges), aura (engine SetApplicationCount), stack (the power).
-- Enchant bars (Bars\AD_EnchantBar.lua) draw the countdown C-side like a
-- cooldown bar and write their charges as the stack text.
local BK_DUR  = { cooldown = true, aura = true, timer = true, swing = true, enchant = true }
-- Cast bars share the duration text's look (the castbar runtime writes the time
-- left with SetFormattedText; it is secret for a target in combat) but not the
-- rounding or the decimals threshold: both would compare that time.
local BK_CAST = { cast = true }
local BK_DURC = { cooldown = true, aura = true, timer = true, swing = true, cast = true, enchant = true }
local BK_RES  = { resource = true }
local BK_HP   = { health = true }
local BK_CST  = { cooldown = true, stack = true, aura = true, enchant = true }
-- Hide-at-zero needs our own writer to pass the count through the secret-safe
-- truncator; the engine writes an aura bar's stack text.
local BK_STKZ = { cooldown = true, stack = true }
local BK_TMSW = { timer = true, swing = true, aura = true, enchant = true }
-- Aura bars too: SetDurationBar takes direction and interpolation from the
-- caller, so fillMode and smoothing work on aura duration bars.
local BK_FILL = { cooldown = true, timer = true, swing = true, aura = true, enchant = true }
-- Smoothing also reaches resource and health bars (StatusBar:SetValue takes an
-- interpolation on 12.x). Timer and swing fills are per-frame GetTime math with
-- nothing to interpolate, so they are left out.
local BK_SMOOTH = { cooldown = true, aura = true, resource = true, health = true }
-- Every kind but range bars, whose plate is always full in its band's colour: no
-- fill colour, fill direction or tick marks there.
local BK_NOTRANGE = { cooldown = true, aura = true, timer = true, stack = true, swing = true,
    resource = true, health = true, cast = true, enchant = true }

local BAR_ANCHORS ={ "LEFT", "CENTER", "RIGHT", "TOPLEFT", "TOP", "TOPRIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
Schema.BAR_ANCHORS = BAR_ANCHORS
-- Bar text anchors: the frame points plus OUTER* positions outside the bar.
local TEXT_ANCHORS = { "LEFT", "CENTER", "RIGHT", "TOPLEFT", "TOP", "TOPRIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "OUTERTOP", "OUTERBOTTOM", "OUTERLEFT", "OUTERRIGHT",
    -- Outer corners: text off the top or bottom edge from the left or right
    -- end. The name defaults to OUTERTOPLEFT so it never meets the stack text.
    "OUTERTOPLEFT", "OUTERTOPRIGHT", "OUTERBOTTOMLEFT", "OUTERBOTTOMRIGHT" }
Schema.TEXT_ANCHORS = TEXT_ANCHORS
local TEXT_ANCHOR_LABELS = {
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
    BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
    OUTERTOP = "Above", OUTERBOTTOM = "Below",
    OUTERLEFT = "Left of the bar", OUTERRIGHT = "Right of the bar",
    OUTERTOPLEFT = "Above, left", OUTERTOPRIGHT = "Above, right",
    OUTERBOTTOMLEFT = "Below, left", OUTERBOTTOMRIGHT = "Below, right",
}
Schema.TEXT_ANCHOR_LABELS = TEXT_ANCHOR_LABELS

-- Live slider bounds: a field may carry minFn / maxFn (record -> number), which
-- the editor's number rows re-read on every sync. The stack threshold sliders
-- use this one to run up to the bar's own maximum.
Schema.MaxStacksFn = function(rec)
    local B = NS.Bars
    return (B and B.MaxStacksFor and B.MaxStacksFor(rec)) or 5
end

local READOUT_VALUES = { "value", "abbreviated", "valuemax", "percent", "none" }
local READOUT_LABELS = { value = "Value", abbreviated = "Short value (5.2k)", valuemax = "Value / max",
    percent = "Percent", none = "Nothing" }

Schema.bar = {
    size = { push = true, fields = {
        -- Both run to 600 because a standing bar is thin and tall.
        width   = { d = 193, t = "int", min = 4, max = 600, label = "Bar width" },
        height  = { d = 24, t = "int", min = 4, max = 600, label = "Bar height" },
        -- Multiplies width and height rather than calling SetScale.
        scale   = { d = 1, t = "num", min = 0.25, max = 4, label = "Bar scale" },
        opacity = { d = 1, t = "num", min = 0.1, max = 1, label = "Opacity" },
    } },
    fill = { push = true, inherit = true, fields = {
        -- Health bars. Health is secret on Forever: the gradient goes through
        -- UnitHealthPercent and a colour curve, class vs reaction through
        -- SetVertexColorFromBoolean (a creature has no class colour).
        colorMode = { inherit = false, d = "fill", t = "enum", values = { "fill", "class", "reaction", "gradient" },
            labels = { fill = "Fill color", class = "Class color (reaction for creatures)",
                reaction = "Reaction color", gradient = "Health gradient" },
            kinds = BK_HP, label = "Color by" },
        -- Only used while colorMode is "fill"; every other bar kind resolves
        -- colorMode to that default.
        color       = { inherit = false, d = { 0.247, 0.788, 0.949, 1 }, t = "color", label = "Fill color",
            kinds = BK_NOTRANGE, dep = { field = "colorMode", value = "fill" } },
        gradLowColor = { d = { 1, 0.15, 0.15, 1 }, t = "color", kinds = BK_HP, label = "Empty health color",
            dep = { field = "colorMode", value = "gradient" } },
        gradMidColor = { d = { 1, 0.82, 0.1, 1 }, t = "color", kinds = BK_HP, label = "Half health color",
            dep = { field = "colorMode", value = "gradient" } },
        gradHighColor = { d = { 0.2, 0.85, 0.3, 1 }, t = "color", kinds = BK_HP, label = "Full health color",
            dep = { field = "colorMode", value = "gradient" } },
        -- Cast bars: channels and uninterruptible casts can have their own
        -- colour; SetVertexColorFromBoolean applies it, since whether a cast
        -- can be interrupted is secret for a target or focus in combat.
        castChannelOn = { d = false, t = "bool", kinds = BK_CAST, label = "Own color for channels" },
        castChannelColor = { d = { 0.36, 0.85, 0.46, 1 }, t = "color", kinds = BK_CAST, label = "Channel color",
            dep = { field = "castChannelOn" } },
        castLockOn = { d = false, t = "bool", kinds = BK_CAST, label = "Own color when it can't be interrupted",
            desc = "Casts you cannot interrupt take this color. In combat the game hides whether a target's cast can be interrupted from addons, so this can only change how the bar looks." },
        castLockColor = { d = { 0.62, 0.64, 0.68, 1 }, t = "color", kinds = BK_CAST, label = "Can't be interrupted color",
            dep = { field = "castLockOn" } },
        -- Cooldown stack bars draw charge slots, never the fill, so they lack
        -- orientation and reverse; aura stack bars keep them. onSet runs after
        -- the editor writes: Horizontal lays a standing bar down.
        orientation = { inherit = false, d = "HORIZONTAL", t = "enum", values = { "HORIZONTAL", "VERTICAL" }, label = "Orientation",
            labels = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
            kindModes = { cooldown = { duration = true } },
            onSet = function(rec, v)
                if v ~= "VERTICAL" and NS.Store and NS.Store.SetBarStanding then
                    NS.Store.SetBarStanding(rec, false)
                end
            end },
        reverseFill = { d = false, t = "bool", label = "Reverse fill", kinds = BK_NOTRANGE,
            kindModes = { cooldown = { duration = true } } },
        -- Cooldowns drain toward ready; swing bars fill (dk: per-kind
        -- defaults). Duration mode only: a stack fill is a count, not a timer.
        fillMode    = { d = "drain", dk = { swing = "fill" }, t = "enum", values = { "drain", "fill" }, kinds = BK_FILL,
            modes = { duration = true }, label = "Fill mode" },
        -- On: the fill empties whenever nothing is running (a swing bar between
        -- swings, a cooldown bar while ready). Timer and aura bars empty on
        -- their own; stack bars show charges, so they are left out.
        idleEmpty   = { d = false, dk = { swing = true }, t = "bool", kinds = { cooldown = true, swing = true },
            kindModes = { cooldown = { duration = true } }, label = "Empty fill when idle" },
        -- Main-hand swing bars: the off-hand's swing as a second track on the
        -- same bar (Bars\AD_SwingOffhand.lua). Hidden: Tracking draws its switch.
        swingOffhand      = { d = false, t = "bool", inherit = false, hidden = true, kinds = { swing = true },
            label = "Show the off-hand on this bar" },
        swingOffhandStyle = { d = "thin", t = "enum", values = { "thin", "thick", "half", "mark" },
            labels = { thin = "Thin line", thick = "Thick line", half = "Half of the bar", mark = "Moving mark" },
            kinds = { swing = true }, dep = { field = "swingOffhand" }, label = "Off-hand style" },
        swingOffhandColor = { d = { 1, 0.75, 0.3, 1 }, t = "color", kinds = { swing = true },
            dep = { field = "swingOffhand" }, label = "Off-hand color" },
        -- A label riding the off-hand's moving edge while it swings, so the
        -- off-hand reads at a glance on a shared bar.
        swingOffhandLabel = { d = false, t = "bool", kinds = { swing = true },
            dep = { field = "swingOffhand" }, label = "Label on the off-hand's edge" },
        swingOffhandLabelText = { d = "OH", t = "text", kinds = { swing = true },
            dep = { { field = "swingOffhand" }, { field = "swingOffhandLabel" } }, label = "Off-hand label text" },
        -- On a standing bar, above is its left side and below its right.
        swingOffhandLabelPos = { d = "on", t = "enum", values = { "on", "above", "below" },
            labels = { on = "On the bar", above = "Above the bar", below = "Below the bar" },
            kinds = { swing = true }, dep = { { field = "swingOffhand" }, { field = "swingOffhandLabel" } },
            label = "Off-hand label position" },
        swingOffhandLabelSize = { d = 10, t = "int", min = 6, max = 24, kinds = { swing = true },
            dep = { { field = "swingOffhand" }, { field = "swingOffhandLabel" } }, label = "Off-hand label size" },
        swingOffhandLabelColor = { d = { 1, 1, 1, 1 }, t = "color", kinds = { swing = true },
            dep = { { field = "swingOffhand" }, { field = "swingOffhandLabel" } }, label = "Off-hand label color" },
        -- Swing bars: two halves that close in and meet as the swing lands, and
        -- ticks where a set time is left (Bars\AD_SwingClosing.lua). The
        -- off-hand track splits the fill its own way, so the two never show together.
        swingClosing = { d = false, t = "bool", kinds = { swing = true },
            dep = { field = "swingOffhand", value = false }, label = "Fill closes in from both ends" },
        swingTicks = { d = false, t = "bool", kinds = { swing = true }, label = "Tick before the swing lands" },
        swingTickTime = { d = 0.5, t = "num", min = 0.1, max = 1.5, step = 0.05, fmt = "%g",
            kinds = { swing = true }, dep = { field = "swingTicks" }, label = "Time before it lands (s)" },
        swingTickColor = { d = { 1, 1, 1, 0.9 }, t = "color", kinds = { swing = true },
            dep = { field = "swingTicks" }, label = "Tick color" },
        -- Up to three ticks: tick 1 is the pair above, so saved bars read the
        -- same; ticks 2 and 3 default to a GCD line and a seal-twist line.
        swingTickCount = { d = 1, t = "enum", values = { 1, 2, 3 }, labels = { "1 tick", "2 ticks", "3 ticks" },
            kinds = { swing = true }, dep = { field = "swingTicks" }, label = "Number of ticks" },
        swingTick2Time = { d = 1.5, t = "num", min = 0.1, max = 1.5, step = 0.05, fmt = "%g", kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 2 } },
            label = "Tick 2 time before it lands (s)" },
        swingTick2Color = { d = { 0.4, 1, 0.4, 0.9 }, t = "color", kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 2 } }, label = "Tick 2 color" },
        swingTick3Time = { d = 0.4, t = "num", min = 0.1, max = 1.5, step = 0.05, fmt = "%g", kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 3 } },
            label = "Tick 3 time before it lands (s)" },
        swingTick3Color = { d = { 1, 0.45, 0.9, 0.9 }, t = "color", kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 3 } }, label = "Tick 3 color" },
        -- Swing and timer bars: a bright line on the fill's moving edge while
        -- it runs (Bars\AD_BarSpark.lua), on each half with the closing fill.
        edgeSpark = { d = false, t = "bool", kinds = { swing = true, timer = true }, label = "Spark" },
        edgeSparkColor = { d = { 1, 1, 1, 0.9 }, t = "color", kinds = { swing = true, timer = true },
            dep = { field = "edgeSpark" }, label = "Spark color" },
        edgeSparkWidth = { d = 3, t = "int", min = 2, max = 16, kinds = { swing = true, timer = true },
            dep = { field = "edgeSpark" }, label = "Spark width" },
        -- Main-hand swing bars: each next-swing ability marked where it comes off
        -- cooldown (Bars\AD_SwingAbilities.lua). The spell IDs live on the driver
        -- (rec.driver.swingAbilIDs), so the editor draws that row itself.
        swingAbilities = { d = false, t = "bool", kinds = { swing = true }, label = "Show next-swing abilities" },
        swingAbilPlace = { d = "stay", t = "enum", values = { "stay", "jump", "follow" },
            labels = { stay = "Stays where it came back", jump = "Jumps to where the swing lands",
                follow = "Queued rides the swing" },
            kinds = { swing = true }, dep = { field = "swingAbilities" }, label = "Ready or queued marker" },
        -- The swing a queued marker rides; asked only with the off-hand track on.
        swingAbilFollow = { d = "mh", t = "enum", values = { "mh", "oh", "first" },
            labels = { mh = "Main hand", oh = "Off hand", first = "Whichever lands first" },
            kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilPlace", value = "follow" },
                { field = "swingOffhand" } },
            label = "Queued rides" },
        swingAbilAhead = { d = 4, t = "enum", values = { 1, 2, 3, 4, 5, 6 },
            labels = { "1 swing", "2 swings", "3 swings", "4 swings", "5 swings", "6 swings" },
            kinds = { swing = true }, dep = { field = "swingAbilities" }, label = "Swings to look ahead" },
        swingAbilIconSize = { d = 25, t = "int", min = 8, max = 48, kinds = { swing = true },
            dep = { field = "swingAbilities" }, label = "Ability icon size" },
        -- Stack bars use this for the slot recharge animation too.
        smoothing   = { d = true, t = "bool", kinds = BK_SMOOTH, label = "Smooth fill" },
        useGradient = { d = true, t = "bool", label = "Gradient fill" },
        -- VERTICAL fades toward the bottom, HORIZONTAL toward the far end.
        gradientDir = { d = "VERTICAL", t = "enum", values = { "VERTICAL", "HORIZONTAL" },
            label = "Gradient direction", dep = { field = "useGradient" } },
        gradientColor = { d = { 0, 0, 0, 0.45 }, t = "color", label = "Gradient end color",
            dep = { field = "useGradient" } },
        fillInset   = { d = 0, t = "int", min = 0, max = 12, label = "Fill padding" },
        -- A built-in key, or a LibSharedMedia key when an LSM addon is loaded
        -- (never bundled). Hidden: the bar editor draws its own dropdown.
        texture = { d = "", t = "text", hidden = true, media = "statusbar", label = "Bar texture" },
        rotateTexture = { d = false, t = "bool", label = "Rotate texture" },
    } },
    -- One section, two editor blocks: Background and Border.
    look = { push = true, inherit = true, fields = {
        bgShow          = { d = true, t = "bool", label = "Background" },
        -- "" = the fill's own texture, dimmed; else a built-in or
        -- LibSharedMedia texture. Hidden: the editor draws its own dropdown.
        bgTexture       = { d = "", t = "text", hidden = true, media = "statusbar", label = "Background texture" },
        -- Light, so the black ticks and dividers stay visible against it.
        bgColor         = { d = { 0.40, 0.42, 0.46, 0.90 }, t = "color", label = "Background color", dep = { field = "bgShow" } },
        -- The background's only opacity; the colour's alpha is ignored (the
        -- picker cannot show it). 0.9 keeps the look bars had when the colour
        -- above carried it.
        bgAlpha         = { d = 0.9, t = "num", min = 0, max = 1, label = "Background opacity", dep = { field = "bgShow" } },
        borderEnabled   = { d = true, t = "bool", label = "Border" },
        -- "" = flat pixel strips, else a Blizzard or LSM backdrop edge at the
        -- thickness. Hidden: the editor draws its own dropdown.
        borderStyle     = { d = "", t = "text", hidden = true, media = "border", label = "Border style" },
        -- Black, 5 px: bars read as solid objects rather than tinted panels.
        borderColor     = { d = { 0, 0, 0, 1 }, t = "color", label = "Border color", dep = { field = "borderEnabled" } },
        borderThickness = { d = 5, t = "int", min = 1, max = 20, label = "Border thickness", dep = { field = "borderEnabled" } },
        useClassColorBorder = { d = false, t = "bool", label = "Class color border", dep = { field = "borderEnabled" } },
    } },
    -- Charge slots on cooldown stack bars, dividers on legacy power-stack bars
    -- (no barMode, so the stack-mode gate passes them). Resource and aura stack
    -- bars use Ticks in "Every point" mode instead.
    segments = { push = true, inherit = true, kinds = { cooldown = true, stack = true }, modes = { stack = true }, fields = {
        segmentsShow = { inherit = false, d = true, t = "bool", label = "Segments" },
        -- 0 = from the driver (maxCharges or UnitPowerMax).
        segmentCount = { inherit = false, d = 0, t = "int", min = 0, max = 20, label = "Segment count (0 = auto)", dep = { field = "segmentsShow" } },
        -- Charge-slot bars use gaps, so only power-stack bars draw dividers.
        dividerColor = { d = { 0.039, 0.067, 0.125, 1 }, t = "color", kinds = { stack = true },
            label = "Divider color", dep = { field = "segmentsShow" } },
        -- Gap between segments, in pixel units.
        segmentSpacing = { d = 1, t = "int", min = 1, max = 10, label = "Segment spacing", dep = { field = "segmentsShow" } },
        -- Keyed off the ready state, which is not secret; never a count read.
        fullColorEnabled = { d = false, t = "bool", kinds = BK_CD, label = "Full charges color" },
        fullColor = { d = { 0.482, 0.847, 0.561, 1 }, t = "color", kinds = BK_CD, label = "Full charges color value", dep = { field = "fullColorEnabled" } },
        -- Recharge overlay tint; off uses the fill color.
        rechargeColorEnabled = { d = false, t = "bool", kinds = BK_CD, label = "Recharge color" },
        rechargeColor = { d = { 0.247, 0.788, 0.949, 0.55 }, t = "color", kinds = BK_CD, label = "Recharge color value", dep = { field = "rechargeColorEnabled" } },
    } },
    -- Resource bars (mana, rage, energy...), run by Bars\AD_Bars.lua. They have
    -- no barMode: neither a duration fill nor a stack.
    resource = { push = true, inherit = true, kinds = { resource = true }, fields = {
        usePowerColor = { d = true, t = "bool", label = "Use power color" },
        -- Pips: up to 20 cells, each a mini-bar in the bar's Background, Border
        -- and Fill texture. Each lights with no compares: its own StatusBar, range
        -- (i-0.5, i), is fed the possibly secret value and fills once the point is
        -- reached.
        style = { inherit = false, d = "bar", t = "enum", values = { "bar", "pips" }, label = "Style",
            labels = { bar = "Bar", pips = "Pips (one per point)" } },
        pipShape = { d = "square", t = "enum", values = { "square", "circle", "diamond" }, label = "Pip shape",
            dep = { field = "style", value = "pips" } },
        -- Each pip is pipWidth x pipHeight pixel units and the bar frame fits
        -- the row; Bar Size's scale and opacity still apply.
        pipWidth = { d = 28, t = "int", min = 4, max = 128, label = "Pip width",
            dep = { field = "style", value = "pips" } },
        pipHeight = { d = 28, t = "int", min = 4, max = 128, label = "Pip height",
            dep = { field = "style", value = "pips" } },
        -- Gap between cells, in pixel units; 0 = touching.
        pipSpacing = { d = 4, t = "int", min = 0, max = 20, label = "Pip spacing",
            dep = { field = "style", value = "pips" } },
        -- A lit point's colour when the power colour is off (the bar style uses
        -- fill.color). Stack Colors bands override it per position.
        pointColor = { d = { 0.247, 0.788, 0.949, 1 }, t = "color", label = "Point color",
            dep = { { field = "style", value = "pips" }, { field = "usePowerColor", value = false } } },
        -- The point colour showing faintly through an empty cell; 0, the
        -- default, leaves the Background colour reading as itself.
        pipEmptyTint = { d = 0, t = "num", min = 0, max = 1, label = "Empty pip tint",
            dep = { field = "style", value = "pips" } },
    } },
    -- Side icon. On a cast bar it shows the spell being cast.
    icon = { push = true, inherit = true, kinds = { cooldown = true, aura = true, cast = true, enchant = true }, fields = {
        iconShow = { d = false, t = "bool", label = "Icon" },
        -- Off: the icon keeps its own size; on: it follows the bar's thickness.
        iconFollowBar = { d = false, t = "bool", label = "Match the bar's size", dep = { field = "iconShow" } },
        iconSize = { d = 24, t = "int", min = 8, max = 128, label = "Icon size",
            dep = { { field = "iconShow" }, { field = "iconFollowBar", value = false } } },
        iconSide = { d = "LEFT", t = "enum", values = { "LEFT", "RIGHT", "TOP", "BOTTOM" }, label = "Icon side", dep = { field = "iconShow" } },
        iconSpacing = { d = 2, t = "int", min = -20, max = 40, label = "Icon spacing", dep = { field = "iconShow" } },
        iconOffsetX = { d = 0, t = "int", min = -100, max = 100, label = "Icon offset X", dep = { field = "iconShow" } },
        iconOffsetY = { d = 0, t = "int", min = -100, max = 100, label = "Icon offset Y", dep = { field = "iconShow" } },
        iconBorderEnabled = { d = true, t = "bool", label = "Icon border", dep = { field = "iconShow" } },
        iconBorderColor = { d = { 0, 0, 0, 1 }, t = "color", label = "Icon border color",
            dep = { { field = "iconShow" }, { field = "iconBorderEnabled" } } },
        iconBorderThickness = { d = 1, t = "int", min = 1, max = 10, label = "Icon border thickness",
            dep = { { field = "iconShow" }, { field = "iconBorderEnabled" } } },
        -- Not on cast bars: their icon is whatever is being cast.
        iconOverride = { inherit = false, d = 0, t = "id", kinds = { cooldown = true, aura = true },
            label = "Icon override (spell/texture ID)", dep = { field = "iconShow" } },
        -- Cast bars: a shield on the icon (or the bar's start without one) for
        -- casts that cannot be interrupted. The flag is secret for a target in
        -- combat, so it goes through SetAlphaFromBoolean.
        iconShield = { d = false, t = "bool", kinds = BK_CAST, label = "Shield on casts that can't be interrupted" },
        iconShieldSize = { d = 0, t = "int", min = 0, max = 96, kinds = BK_CAST,
            label = "Shield size (0 = automatic)", dep = { field = "iconShield" } },
    } },
    -- Each text is a flat-prefixed run (dur, stk, res, hp, name, ready) so the
    -- generic rows cluster them. Changing an anchor zeroes that text's offsets.
    text = { push = true, inherit = true, fields = {
        -- One font per bar: a built-in or LibSharedMedia font; "" = the game's
        -- default. Hidden: the bar editor draws its own dropdown.
        font = { d = "", t = "text", hidden = true, font = true, label = "Font" },
        durShow = { d = true, t = "bool", kinds = BK_DURC, label = "Duration text" },
        -- "global" follows Settings > Timers.
        durRounding = { d = "global", t = "enum", values = { "global", "up", "down" },
            labels = { global = "Same as Settings", up = "Round up", down = "Round down" },
            kinds = BK_DUR, label = "Round timer numbers", dep = { field = "durShow" } },
        durSize = { d = 12, t = "int", min = 6, max = 32, kinds = BK_DURC, label = "Duration text size" },
        durAnchor = { d = "RIGHT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, kinds = BK_DURC, label = "Duration anchor" },
        durOffsetX = { d = -3, t = "int", min = -100, max = 100, kinds = BK_DURC, label = "Duration offset X" },
        durOffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_DURC, label = "Duration offset Y" },
        durColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_DURC, label = "Duration color" },
        -- Decimals: cooldown bars render C-side from the real remaining time
        -- (the shared CooldownFormatter); timer and swing bars use plain math.
        durDecimalsEnabled = { d = false, t = "bool", kinds = BK_DURC, label = "Duration decimals",
            dep = { field = "durShow" } },
        durDecimalThreshold = { d = 10, t = "int", min = 2, max = 60, kinds = BK_DUR, label = "Decimals below (s)",
            dep = { { field = "durShow" }, { field = "durDecimalsEnabled" } } },
        -- The icons' durationAbbrev for bars: cooldown and aura bars through
        -- the shared formatter, timer and swing bars through FormatCountdown.
        durAbbrev = { d = 600, t = "enum", values = ABBREV_VALUES, labels = ABBREV_LABELS, kinds = BK_DUR,
            label = "Minutes and seconds (1:30)", dep = { field = "durShow" } },
        stkShow = { d = true, t = "bool", kinds = BK_CST, label = "Stack text" },
        stkSize = { d = 12, t = "int", min = 6, max = 32, kinds = BK_CST, label = "Stack text size" },
        stkAnchor = { d = "LEFT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, kinds = BK_CST, label = "Stack anchor" },
        stkOffsetX = { d = 3, t = "int", min = -100, max = 100, kinds = BK_CST, label = "Stack offset X" },
        stkOffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_CST, label = "Stack offset Y" },
        stkColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_CST, label = "Stack color" },
        stkHideAtZero = { d = true, t = "bool", kinds = BK_STKZ, label = "Stack hides at zero" },
        -- The "/max" suffix, built by the stack-mode slot pass. maxCharges is
        -- not secret; the count is never read.
        stkShowMax = { d = false, t = "bool", kinds = BK_CD, label = "Stack shows max",
            kindModes = { cooldown = { stack = true } } },
        -- Resource bars: the power value; resFormat picks what it shows.
        resShow = { d = true, t = "bool", kinds = BK_RES, label = "Resource text" },
        resSize = { d = 12, t = "int", min = 6, max = 32, kinds = BK_RES, label = "Resource text size" },
        resOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_RES, label = "Resource outline" },
        resColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_RES, label = "Resource color" },
        resAnchor = { d = "CENTER", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, kinds = BK_RES, label = "Resource anchor" },
        resOffsetX = { d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Resource offset X" },
        resOffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Resource offset Y" },
        -- What text 1 says. abbreviated takes secrets; percent runs a 0..100
        -- curve and a rule formatter; valuemax formats the value against the
        -- plain max. All of it works in combat.
        resFormat = { d = "value", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_RES, label = "Resource text shows", dep = { field = "resShow" } },
        -- Texts 2 and 3 have their own format, size, colour and place; outline
        -- and shadow come from text 1.
        resCount = { inherit = false, d = 1, t = "int", min = 1, max = 3, kinds = BK_RES, label = "Number of resource texts",
            dep = { field = "resShow" } },
        res2Format = { d = "percent", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_RES, label = "Text 2 shows", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_RES, label = "Text 2 size", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_RES, label = "Text 2 color", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2Anchor = { d = "RIGHT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_RES, label = "Text 2 anchor", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2OffsetX = { d = -3, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 2 offset X", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2OffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 2 offset Y", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res3Format = { d = "valuemax", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_RES, label = "Text 3 shows", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_RES, label = "Text 3 size", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_RES, label = "Text 3 color", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3Anchor = { d = "LEFT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_RES, label = "Text 3 anchor", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3OffsetX = { d = 3, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 3 offset X", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3OffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 3 offset Y", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        -- Health bars. Health is secret: only SetText, SetFormattedText and
        -- AbbreviateNumbers handle it, never Lua maths.
        hpShow = { d = true, t = "bool", kinds = BK_HP, label = "Health text" },
        hpFormat = { d = "value", t = "enum",
            values = { "value", "abbreviated", "valuemax", "percent", "none" },
            labels = { value = "Value", abbreviated = "Short value (5.2k)", valuemax = "Value / max",
                percent = "Percent", none = "Nothing" },
            kinds = BK_HP, label = "Health text shows", dep = { field = "hpShow" } },
        hpSize = { d = 12, t = "int", min = 6, max = 32, kinds = BK_HP, label = "Health text size" },
        hpOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_HP, label = "Health outline" },
        hpColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_HP, label = "Health text color" },
        hpAnchor = { d = "RIGHT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, kinds = BK_HP, label = "Health anchor" },
        hpOffsetX = { d = -3, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Health offset X" },
        hpOffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Health offset Y" },
        hpShadow = { d = false, t = "bool", kinds = BK_HP, label = "Health shadow" },
        -- Texts 2 and 3, as on resource bars.
        hpCount = { inherit = false, d = 1, t = "int", min = 1, max = 3, kinds = BK_HP, label = "Number of health texts",
            dep = { field = "hpShow" } },
        hp2Format = { d = "percent", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_HP, label = "Text 2 shows", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_HP, label = "Text 2 size", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_HP, label = "Text 2 color", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2Anchor = { d = "LEFT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_HP, label = "Text 2 anchor", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2OffsetX = { d = 3, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 2 offset X", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2OffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 2 offset Y", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp3Format = { d = "valuemax", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_HP, label = "Text 3 shows", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_HP, label = "Text 3 size", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", kinds = BK_HP, label = "Text 3 color", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3Anchor = { d = "CENTER", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_HP, label = "Text 3 anchor", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3OffsetX = { d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 3 offset X", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3OffsetY = { d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 3 offset Y", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        nameShow = { d = false, t = "bool", label = "Name text" },
        -- Health bars: the unit's live name (secret in instances; SetText takes
        -- it as is) or the bar's own name.
        nameSource = { inherit = false, d = "unit", t = "enum", values = { "unit", "bar" },
            labels = { unit = "The unit's name", bar = "This bar's name" },
            kinds = BK_HP, label = "Name text shows", dep = { field = "nameShow" } },
        -- Any text in place of the name, on every bar kind; empty = the default
        -- name. Per bar: the editor keeps it out of the Name block's copy and
        -- save list. hintFn fills the empty field; desc is the tooltip.
        nameText = { inherit = false, d = "", t = "text", label = "Custom name text", dep = { field = "nameShow" },
            desc = "Any text you like in place of the name. Leave it empty to show the default name.",
            hintFn = function(rec)
                if rec.barKind == "health" and ((NS.Store and NS.Store.Resolve(rec, "text", "nameSource")) or "unit") == "unit" then
                    return "the unit's name"
                end
                if rec.barKind == "cast" then return "the spell's name" end
                if rec.barKind == "range" then return "the band's name" end
                return rec.name or ""
            end },
        nameSize = { d = 11, t = "int", min = 6, max = 32, label = "Name text size" },
        -- Above the bar at its left end, so it never collides with the stack
        -- text on the bar's left edge.
        nameAnchor = { d = "OUTERTOPLEFT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, label = "Name anchor" },
        nameOffsetX = { d = 0, t = "int", min = -100, max = 100, label = "Name offset X" },
        nameOffsetY = { d = 1, t = "int", min = -100, max = 100, label = "Name offset Y" },
        nameColor = { d = { 0.7, 0.78, 0.88, 1 }, t = "color", label = "Name color" },
        readyShow = { d = false, t = "bool", kinds = BK_CD, label = "Ready text" },
        readyText = { inherit = false, d = "Ready", t = "text", kinds = BK_CD, label = "Ready text string", dep = { field = "readyShow" } },
        readyColor = { d = { 0.482, 0.847, 0.561, 1 }, t = "color", kinds = BK_CD, label = "Ready color", dep = { field = "readyShow" } },
        -- Per-text outlines; the ready text takes the duration text's styling.
        durOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_DURC, label = "Duration outline" },
        stkOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_CST, label = "Stack outline" },
        nameOutline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, label = "Name outline" },
        -- Per-text drop shadow (black, 1px down and right); ready follows dur.
        durShadow = { d = false, t = "bool", kinds = BK_DURC, label = "Duration shadow" },
        stkShadow = { d = false, t = "bool", kinds = BK_CST, label = "Stack shadow" },
        resShadow = { d = false, t = "bool", kinds = BK_RES, label = "Resource shadow" },
        nameShadow = { d = false, t = "bool", label = "Name shadow" },
    } },
    -- Cooldown bars evaluate durObj curves (useChargeDur fixed at setup); timer
    -- and swing bars compare plain seconds in the GetTime loop; aura duration
    -- bars get engine-driven colour layers, so their time never reaches Lua.
    thresholds = { push = true, kinds = { cooldown = true, timer = true, aura = true, swing = true },
        kindModes = { aura = { duration = true } }, fields = {
        threshEnabled = { d = false, t = "bool", label = "Threshold colors" },
        -- Bands in play (of three); the others hide and the runtime skips them.
        threshCount = { d = 2, t = "int", min = 1, max = 3, label = "Number of thresholds", dep = { field = "threshEnabled" } },
        threshAsSeconds = { d = true, t = "bool", label = "Thresholds in seconds", dep = { field = "threshEnabled" } },
        -- Seconds mode places its points as a fraction of the cooldown, so it
        -- needs the length: this field when set, else the client's
        -- base-cooldown API, else the last plain duration seen.
        threshCdSeconds = { d = 0, t = "int", min = 0, max = 3600, kinds = BK_CD, label = "Cooldown length (s, 0 = auto)",
            dep = { { field = "threshEnabled" } } },
        -- Aura bars only: the engine never gives an aura's full length, so
        -- seconds thresholds and the text bands convert against this. Percent
        -- thresholds need it only for the text.
        threshRef = { d = 30, t = "int", min = 1, max = 3600, kinds = { aura = true }, label = "Aura duration (s)", dep = { field = "threshEnabled" } },
        -- Tenths (step 0.1) for swing zones such as the last half second; swing
        -- bars default to 1 and 0.5 s.
        thresh2Value = { d = 10, dk = { swing = 1 }, t = "num", min = 0, max = 600, step = 0.1, fmt = "%g",
            label = "Threshold 2 value", dep = { field = "threshEnabled" } },
        thresh2Color = { d = { 0.95, 0.76, 0.31, 1 }, t = "color", label = "Threshold 2 color", dep = { field = "threshEnabled" } },
        thresh3Value = { d = 5, dk = { swing = 0.5 }, t = "num", min = 0, max = 600, step = 0.1, fmt = "%g",
            label = "Threshold 3 value",
            dep = { { field = "threshEnabled" }, { field = "threshCount", min = 2 } } },
        thresh3Color = { d = { 0.95, 0.40, 0.40, 1 }, t = "color", label = "Threshold 3 color",
            dep = { { field = "threshEnabled" }, { field = "threshCount", min = 2 } } },
        thresh4Value = { d = 0, t = "num", min = 0, max = 600, step = 0.1, fmt = "%g",
            label = "Threshold 4 value",
            dep = { { field = "threshEnabled" }, { field = "threshCount", min = 3 } } },
        thresh4Color = { d = { 1, 1, 1, 1 }, t = "color", label = "Threshold 4 color",
            dep = { { field = "threshEnabled" }, { field = "threshCount", min = 3 } } },
        -- The countdown text takes the same bands (C-side formatter on cooldown
        -- and aura bars, plain math on timer bars).
        threshText = { d = false, t = "bool", label = "Color duration text too", dep = { field = "threshEnabled" } },
    } },
    -- Swing bars: the fill wears an ability's colour while it is queued on the
    -- next swing, or from its cast until that swing lands, over the threshold
    -- and fill colours (Bars\AD_SwingColors.lua). The rules are the bar's own
    -- (rec.driver.swingColors), so the editor draws them; per bar, no push.
    abilcolors = { kinds = { swing = true }, fields = {
        abilColorsOn = { d = false, t = "bool", label = "Color the bar by ability" },
    } },
    -- Colour by stack count on aura stack bars, by position on pips resource
    -- bars (the editor shows it for pips only). A continuous bar flips the
    -- whole fill, a segmented one colours its cells, all as extra engine-driven
    -- fills shown by count, which is never read.
    stackcolors = { push = true, kinds = { aura = true, resource = true }, modes = { stack = true }, fields = {
        -- On: each cell keeps its band's colour by position. Off (default): the
        -- whole fill takes a band's colour once the count reaches it.
        scPosition = { d = false, t = "bool", kinds = { aura = true }, label = "Keep each stack's own color (segmented)" },
        scEnabled = { d = false, t = "bool", label = "Color by stack count" },
        -- Colour 1 is the fill colour; each extra colour takes over from a
        -- stack count, on a slider from 2 to the bar's maximum (maxFn).
        scCount = { d = 2, t = "int", min = 1, max = 3, label = "Extra colors (after the fill color)", dep = { field = "scEnabled" } },
        sc2Value = { d = 3, t = "int", min = 2, max = 99, maxFn = Schema.MaxStacksFn, label = "Color 2 from stack", dep = { field = "scEnabled" } },
        sc2Color = { d = { 1, 1, 0, 1 }, t = "color", label = "Color 2", dep = { field = "scEnabled" } },
        sc3Value = { d = 5, t = "int", min = 2, max = 99, maxFn = Schema.MaxStacksFn, label = "Color 3 from stack",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 2 } } },
        sc3Color = { d = { 1, 0.5, 0, 1 }, t = "color", label = "Color 3",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 2 } } },
        sc4Value = { d = 7, t = "int", min = 2, max = 99, maxFn = Schema.MaxStacksFn, label = "Color 4 from stack",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 3 } } },
        sc4Color = { d = { 0, 1, 0, 1 }, t = "color", label = "Color 4",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 3 } } },
        maxColorEnabled = { d = false, t = "bool", label = "Max stacks color" },
        maxColor = { d = { 0, 1, 0, 1 }, t = "color", label = "Max stacks color value", dep = { field = "maxColorEnabled" } },
    } },
    -- Primary resource bars: colour by power percent. UnitPowerPercent
    -- evaluates a colour curve client-side, so the possibly secret value never
    -- reaches Lua: one call per power event. "below" colours at or under the
    -- value (a mana warning), "above" at or over it.
    powerthresholds = { push = true, kinds = BK_RES, fields = {
        pthEnabled = { d = false, t = "bool", label = "Threshold colors" },
        -- Bands in play, one by default; the runtime reads only these.
        pthCount = { d = 1, t = "int", min = 1, max = 3, label = "Number of thresholds", dep = { field = "pthEnabled" } },
        -- Values in power units instead of percent (45 energy, 2000 mana): the
        -- plain cached max converts them, so the same percent curve serves both
        -- and the secret value never reaches Lua.
        pthAbsolute = { d = false, t = "bool", label = "Thresholds in power units", dep = { field = "pthEnabled" } },
        pthDirection = { d = "below", t = "enum", values = { "below", "above" }, label = "Color when power is", dep = { field = "pthEnabled" } },
        pth2Value = { d = 50, t = "int", min = 0, max = 20000, label = "Threshold 2 value", dep = { field = "pthEnabled" } },
        pth2Color = { d = { 1, 1, 0, 1 }, t = "color", label = "Threshold 2 color", dep = { field = "pthEnabled" } },
        pth3Value = { d = 25, t = "int", min = 0, max = 20000, label = "Threshold 3 value",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 2 } } },
        pth3Color = { d = { 1, 0.5, 0, 1 }, t = "color", label = "Threshold 3 color",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 2 } } },
        pth4Value = { d = 10, t = "int", min = 0, max = 20000, label = "Threshold 4 value",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 3 } } },
        pth4Color = { d = { 1, 0, 0, 1 }, t = "color", label = "Threshold 4 color",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 3 } } },
        pthFullEnabled = { d = false, t = "bool", label = "Full power color" },
        pthFullColor = { d = { 0, 1, 0, 1 }, t = "color", label = "Full power color value", dep = { field = "pthFullEnabled" } },
        pthText = { d = false, t = "bool", label = "Color the text too", dep = { field = "pthEnabled" } },
    } },
    -- Health bars: colour by health percent (execute range, low-health
    -- warning). UnitHealthPercent evaluates the colour curve C-side from the
    -- secret value: no compare, one call per health event.
    healththresholds = { push = true, kinds = BK_HP, fields = {
        hpthEnabled = { d = false, t = "bool", label = "Threshold colors" },
        hpthCount = { d = 1, t = "int", min = 1, max = 3, label = "Number of thresholds", dep = { field = "hpthEnabled" } },
        hpthDirection = { d = "below", t = "enum", values = { "below", "above" },
            labels = { below = "At or below the value", above = "At or above the value" },
            label = "Color when health is", dep = { field = "hpthEnabled" } },
        hpth2Value = { d = 35, t = "int", min = 1, max = 99, label = "First threshold (%)", dep = { field = "hpthEnabled" } },
        hpth2Color = { d = { 1, 0.55, 0.1, 1 }, t = "color", label = "First threshold color", dep = { field = "hpthEnabled" } },
        hpth3Value = { d = 20, t = "int", min = 1, max = 99, label = "Second threshold (%)",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 2 } } },
        hpth3Color = { d = { 1, 0.15, 0.15, 1 }, t = "color", label = "Second threshold color",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 2 } } },
        hpth4Value = { d = 10, t = "int", min = 1, max = 99, label = "Third threshold (%)",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 3 } } },
        hpth4Color = { d = { 0.65, 0, 0, 1 }, t = "color", label = "Third threshold color",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 3 } } },
        hpthText = { d = false, t = "bool", label = "Color the health text too", dep = { field = "hpthEnabled" } },
    } },
    -- Tick marks, laid out on size or setting changes, never per update. "all":
    -- one per unit while the bar's max is a small integer (stacks, small power
    -- maxes, seconds up to 60), else percent. "percent": every N%. "custom": a
    -- typed list in the bar's unit or in percent, plus cost ticks on resource
    -- bars. "pertick": one per tick, player castbars only. Cooldown stack bars
    -- have none: their slot gaps are the marks.
    ticks = { push = true, inherit = true, kinds = BK_NOTRANGE, kindModes = { cooldown = { duration = true } }, fields = {
        ticksShow = { inherit = false, d = false, t = "bool", label = "Tick marks" },
        tickMode = { inherit = false, d = "percent", t = "enum", values = { "all", "percent", "custom", "pertick" }, label = "Tick mode", dep = { field = "ticksShow" },
            labels = { all = "Every point", percent = "Every X percent", custom = "Custom values", pertick = "One per tick" },
            -- valueIf (record -> bool) hides a value from the editor's list. A target's or
            -- focus's channel is secret in combat, so only a player castbar can mark ticks.
            valueIf = { pertick = function(r) return r.barKind == "cast" and ((r.driver and r.driver.unit) or "player") == "player" end } },
        tickPercent = { inherit = false, d = 25, t = "int", min = 5, max = 50, label = "Tick every (%)",
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "percent" } } },
        tickValues = { inherit = false, d = "", t = "text", label = "Custom ticks (comma list)",
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "custom" } } },
        tickAsPercent = { inherit = false, d = false, t = "bool", label = "Custom ticks are percent",
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "custom" } } },
        tickScale = { inherit = false, d = 0, t = "int", min = 0, max = 3600, label = "Custom tick scale (0 = auto)",
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "custom" } } },
        tickSpells = { inherit = false, d = "", t = "text", kinds = BK_RES, label = "Cost ticks from spell IDs", dep = { field = "ticksShow" } },
        -- Cost-tick spells show their icon at the tick, optionally dimmed below
        -- the cost: a 1px detector StatusBar fed the possibly secret value
        -- pipes its texture width into SetAlpha, so nothing is compared.
        tickSpellIcons = { d = false, t = "bool", kinds = BK_RES, label = "Spell icons on cost ticks",
            dep = { { field = "ticksShow" }, { field = "tickSpells", nonempty = true } } },
        tickIconSize = { d = 0, t = "int", min = 0, max = 64, kinds = BK_RES, label = "Cost icon size (0 = bar height)",
            dep = { { field = "ticksShow" }, { field = "tickSpellIcons" } } },
        tickIconSide = { d = "TOP", t = "enum", values = { "TOP", "BOTTOM", "CENTER" }, kinds = BK_RES, label = "Cost icon side",
            dep = { { field = "ticksShow" }, { field = "tickSpellIcons" } } },
        tickIconDim = { d = false, t = "bool", kinds = BK_RES, label = "Dim icons you cannot afford",
            dep = { { field = "ticksShow" }, { field = "tickSpellIcons" } } },
        tickChannelOnly = { inherit = false, d = false, t = "bool", kinds = BK_CAST, label = "Tick marks on channels only",
            dep = { field = "ticksShow" } },
        tickColor = { d = { 0, 0, 0, 1 }, t = "color", label = "Tick color", dep = { field = "ticksShow" } },
        -- Min 2: a one-pixel mark at a fractional position (a dragged bar, a
        -- fractional UI scale) can rasterise to nothing.
        tickThickness = { d = 2, t = "int", min = 2, max = 10, label = "Tick thickness", dep = { field = "ticksShow" } },
        tickHeight = { d = 100, t = "int", min = 10, max = 100, label = "Tick height (%)", dep = { field = "ticksShow" } },
        tickHeightAnchor = { d = "center", t = "enum", values = { "center", "start", "end" }, label = "Tick height anchor", dep = { field = "ticksShow" } },
    } },
    -- Primary resource bars: the cost of the spell being cast, anchored to the
    -- fill's edge rather than computed from the secret value.
    predict = { push = true, inherit = true, kinds = BK_RES, fields = {
        predictEnabled = { d = false, t = "bool", label = "Show spell cost while casting" },
        predictColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Cost color", dep = { field = "predictEnabled" } },
        predictAlpha = { d = 0.5, t = "num", min = 0.1, max = 1, label = "Cost opacity", dep = { field = "predictEnabled" } },
    } },
    -- Health bars: heals, shields and heal absorbs at the health edge. Every
    -- amount is secret, so each overlay is a StatusBar with the health bar's
    -- range, anchored to the fill's edge and fed the amount; Lua never reads
    -- it. The colour picker has no alpha, so each overlay has its own opacity.
    healpred = { push = true, inherit = true, kinds = BK_HP, fields = {
        healShow = { d = false, t = "bool", label = "Incoming heals" },
        healMyColor = { d = { 0.35, 1, 0.55, 1 }, t = "color", label = "Your heals color", dep = { field = "healShow" } },
        healOtherColor = { d = { 0.1, 0.75, 0.4, 1 }, t = "color", label = "Other heals color", dep = { field = "healShow" } },
        healAlpha = { d = 0.6, t = "num", min = 0.1, max = 1, label = "Heals opacity", dep = { field = "healShow" } },
        absorbShow = { d = false, t = "bool", label = "Absorb shields" },
        -- stripes: Blizzard's shield art, tiled, never stretched. bar: the
        -- bar's own texture in the shield color.
        absorbStyle = { d = "stripes", t = "enum", values = { "stripes", "bar" },
            labels = { stripes = "Striped shield", bar = "Bar texture" }, label = "Shield look",
            dep = { field = "absorbShow" } },
        absorbColor = { d = { 0.8, 0.93, 1, 1 }, t = "color", label = "Shield color", dep = { field = "absorbShow" } },
        absorbAlpha = { d = 0.55, t = "num", min = 0.1, max = 1, label = "Shield opacity", dep = { field = "absorbShow" } },
        -- The calculator's clamped flag is secret: it goes straight into
        -- SetAlphaFromBoolean, never into an `if`.
        absorbOverflow = { d = false, t = "bool", label = "Glow when shields pass full health",
            dep = { field = "absorbShow" } },
        healAbsorbShow = { d = false, t = "bool", label = "Heal absorbs" },
        healAbsorbColor = { d = { 0.55, 0.05, 0.2, 1 }, t = "color", label = "Heal absorb color", dep = { field = "healAbsorbShow" } },
        healAbsorbAlpha = { d = 0.7, t = "num", min = 0.1, max = 1, label = "Heal absorb opacity", dep = { field = "healAbsorbShow" } },
    } },
    -- Cast bars (Bars\AD_Castbar.lua). Name, time, icon and colours live in the
    -- shared blocks. What a target's or focus's cast hides in combat (its time,
    -- whether it can be interrupted) reaches only secret-safe sinks.
    cast = { push = true, inherit = true, kinds = BK_CAST, fields = {
        sparkOn = { d = false, t = "bool", label = "Spark" },
        sparkColor = { d = { 1, 1, 1, 0.9 }, t = "color", label = "Spark color", dep = { field = "sparkOn" } },
        sparkWidth = { d = 3, t = "int", min = 1, max = 16, label = "Spark width", dep = { field = "sparkOn" } },
        holdOn = { d = false, t = "bool", label = "Hold interrupted and failed casts",
            desc = "An interrupted or failed cast stays up for a moment in its color, with the reason as its name. A finished cast always goes at once." },
        holdTime = { d = 0.6, t = "num", min = 0.1, max = 3, step = 0.1, fmt = "%g", label = "Hold for (s)",
            dep = { field = "holdOn" } },
        holdFailColor = { d = { 1, 0.55, 0.1, 1 }, t = "color", label = "Failed color", dep = { field = "holdOn" } },
        holdIntColor = { d = { 0.9, 0.2, 0.2, 1 }, t = "color", label = "Interrupted color", dep = { field = "holdOn" } },
        fadeOut = { d = 0, t = "num", min = 0, max = 2, step = 0.1, fmt = "%g", label = "Fade out (s)",
            desc = "How long the bar takes to fade away when a cast ends (after the hold, when that is on). 0 = it goes at once." },
        -- Which casts show
        hideChannels = { inherit = false, d = false, t = "bool", label = "Hide channels" },
        lockHide = { inherit = false, d = false, t = "bool", label = "Hide casts that can't be interrupted",
            desc = "In combat the game hides whether a target's cast can be interrupted from addons, so the bar still hides those casts but cannot do anything else about them (no sound, no alert)." },
        -- Your casts only: the editor offers these on a player castbar.
        latencyOn = { d = false, t = "bool", label = "Latency zone",
            desc = "The end of your cast that your connection's delay covers: start the next cast once the fill reaches it." },
        latencyColor = { d = { 1, 0.25, 0.2, 0.55 }, t = "color", label = "Latency color", dep = { field = "latencyOn" } },
        hideBlizzard = { inherit = false, d = false, t = "bool", label = "Hide Blizzard's castbar",
            desc = "Hides the game's own castbar under your character while this castbar is loaded. Turning it off brings the game's castbar back on your next cast." },
    } },
    -- Range bars (Bars\AD_RangeBar.lua): how the bands draw. The bands themselves
    -- (a preset's, or the bar's own list of text, colour, switch and checks) are
    -- the bar's own (rec.driver), edited on the Range tab.
    range = { push = true, kinds = { range = true }, fields = {
        style = { d = "plate", t = "enum", values = { "plate", "segmented" },
            labels = { plate = "Plate", segmented = "Segmented" }, label = "Style" },
        plateShow = { d = true, t = "bool", label = "Show plate", dep = { field = "style", value = "plate" } },
        textBandColor = { d = false, t = "bool", label = "Text in the band's color",
            dep = { field = "style", value = "plate" } },
        cellGap = { d = 2, t = "int", min = 0, max = 10, label = "Gap between cells",
            dep = { field = "style", value = "segmented" } },
        cellDim = { d = 0.25, t = "num", min = 0, max = 1, label = "Unlit cell opacity",
            dep = { field = "style", value = "segmented" } },
    } },
    -- Not pushable, like conditions. hiddenAlpha is the opacity for the state
    -- hides below; every kind it lists must honor it.
    behavior = { fields = {
        hideWhenReady = { d = false, t = "bool", kinds = BK_CD, label = "Hide when ready" },
        hideWhenFullCharges = { d = false, t = "bool", kinds = BK_CD, label = "Hide at full charges" },
        hideWhenInactive = { d = false, t = "bool", kinds = BK_TMSW, label = "Hide when inactive" },
        -- Swing bars: dim while the target is out of range of the bar's own
        -- spell, else its hand's usual one (Bars\AD_SwingRange.lua; the typed
        -- spell is rec.driver.rangeSpell).
        rangeDim = { d = false, t = "bool", kinds = { swing = true }, label = "Dim when out of range" },
        -- Only kinds with a state hide (ready, full charges, inactive); aura
        -- bars have none, as the engine hides the whole bar with the aura. On a
        -- cast bar, above 0 leaves the empty bar faintly visible between casts.
        hiddenAlpha = { d = 0, t = "num", min = 0, max = 1, kinds = { cooldown = true, timer = true, swing = true, cast = true, enchant = true }, label = "Hidden opacity" },
        -- Spell 61304 (the GCD), inverted readiness, exempt from the debounce.
        gcdMode = { d = false, t = "bool", kinds = BK_CD, label = "GCD tracker mode" },
    } },
    frame = { fields = {
        strata = { d = "MEDIUM", t = "enum",
            values = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }, label = "Frame strata" },
        level = { d = 10, t = "int", min = 1, max = 100, label = "Frame level" },
    } },
    -- Anchoring (Core\AD_Anchor.lua). These field names are shared by every
    -- anchorable family: don't rename them here or add a second set.
    anchor = { fields = {
        anchorEnabled = { d = false, t = "bool", hidden = true, label = "Anchor this bar" },
        -- "nameplate" is the current target's nameplate (bars only).
        anchorTargetKind = { d = "group", t = "enum", values = { "group", "bar", "layout", "frame", "nameplate", "mouse" },
            labels = { group = "Group", bar = "Bar", layout = "Layout", frame = "Named frame",
                nameplate = "Target's nameplate", mouse = "Mouse cursor" },
            hidden = true, label = "Anchor to", dep = { field = "anchorEnabled" } },
        anchorTargetId = { d = 0, t = "id", hidden = true, label = "Anchor target" },
        anchorTargetFrame = { d = "", t = "text", hidden = true, label = "Anchor frame name" },
        anchorSrcPoint = { d = "TOP", t = "enum", values = BAR_ANCHORS,
            label = "My point", dep = { field = "anchorEnabled" } },
        -- The cursor is a point, so there is no target point to pick.
        anchorDstPoint = { d = "BOTTOM", t = "enum", values = BAR_ANCHORS,
            label = "Target point",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "mouse" } } },
        anchorOffsetX = { d = 0, t = "int", min = -500, max = 500,
            label = "Anchor offset X", dep = { field = "anchorEnabled" } },
        anchorOffsetY = { d = -2, t = "int", min = -500, max = 500,
            label = "Anchor offset Y", dep = { field = "anchorEnabled" } },
        -- A standing bar matches the target's height, its long side. Not on a
        -- nameplate: its size can be secret, and a resize would lay the bar out
        -- on a rect it may not read.
        anchorMatchWidth = { d = false, t = "bool", label = "Match target width (height if standing)",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "nameplate" },
                { field = "anchorTargetKind", notValue = "mouse" } } },
        anchorMatchWidthAdjust = { d = 0, t = "int", min = -200, max = 200,
            label = "Match width adjust",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "nameplate" },
                { field = "anchorTargetKind", notValue = "mouse" }, { field = "anchorMatchWidth" } } },
        -- The short side, as width is the long one; same rules as above.
        anchorMatchHeight = { d = false, t = "bool", label = "Match target height (width if standing)",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "nameplate" },
                { field = "anchorTargetKind", notValue = "mouse" } } },
        anchorMatchHeightAdjust = { d = 0, t = "int", min = -200, max = 200,
            label = "Match height adjust",
            dep = { { field = "anchorEnabled" }, { field = "anchorTargetKind", notValue = "nameplate" },
                { field = "anchorTargetKind", notValue = "mouse" }, { field = "anchorMatchHeight" } } },
    } },
}

Schema.layout = {
    -- Conditions live on rec.c; pos and members are store-level identity. Mouse
    -- tier for the layout's icons ("inherit" defers to Settings).
    mouse = { fields = {
        clickThrough = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Click-through" },
        showTooltip = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Show tooltips" },
    } },
}

-- Iterates (section, key, def) over a family, sorted so the order is stable.
function Schema.Fields(family)
    local fam = Schema[family]
    local secs = {}
    for name in pairs(fam) do secs[#secs + 1] = name end
    table.sort(secs)
    local si, keys, ki, cur = 0, nil, 0, nil
    return function()
        while true do
            if cur and keys and ki < #keys then
                ki = ki + 1
                return cur, keys[ki], fam[cur].fields[keys[ki]]
            end
            si = si + 1
            cur = secs[si]
            if not cur then return nil end
            keys, ki = {}, 0
            for k in pairs(fam[cur].fields or {}) do keys[#keys + 1] = k end
            table.sort(keys)
        end
    end
end

-- Layout tier: may a field take its layout's value when the record has none? A
-- section opts in with inherit = true; a field's own inherit flag overrides its
-- section's either way. Store.Resolve asks this, and the layout editor lists
-- every field that answers true, so a new look joins by setting the flag.
function Schema.Inherits(def, sectionDef)
    if def == nil then return false end
    if def.inherit ~= nil then return def.inherit == true end
    return sectionDef ~= nil and sectionDef.inherit == true
end

function Schema.Applies(def, sectionDef, kind, mode)
    local k = (def and def.kinds) or (sectionDef and sectionDef.kinds)
    if k and not (kind ~= nil and k[kind] == true) then return false end
    local m = (def and def.modes) or (sectionDef and sectionDef.modes)
    if m and mode ~= nil and m[mode] ~= true then return false end
    -- A nil mode passes the modes gate (icons, groups, legacy bar kinds and
    -- PushToAll targets have none). kindModes limits one kind to some modes and
    -- leaves the others alone, e.g. aura thresholds in duration mode only.
    local km = (def and def.kindModes) or (sectionDef and sectionDef.kindModes)
    if km and kind ~= nil and mode ~= nil and km[kind] and km[kind][mode] ~= true then
        return false
    end
    return true
end
